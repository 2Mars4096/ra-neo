extends Control
# A native, keyboard-focusable modal above the custom-drawn battlefield HUD.
# battle.gd owns pause/restore and all side effects; this view only emits actions.
signal changed(key:String,value:Variant)
signal closed
signal restart_confirmed
signal defaults_requested
signal report_requested

const INK:=Color("191d1b")
const PANEL:=Color("242923")
const LINE:=Color("647253")
const TEXT:=Color("e7e6d7")
var mode:=""
var panel:PanelContainer
var body:VBoxContainer
var fields:Dictionary={}
var status:Label
var syncing:=false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	var shade:=ColorRect.new()
	shade.color=Color(0.02,0.03,0.025,0.82)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var center:=CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(center)
	panel=PanelContainer.new()
	panel.custom_minimum_size=Vector2(540,0)
	var style:=StyleBoxFlat.new()
	style.bg_color=PANEL
	style.border_color=LINE
	style.set_border_width_all(2)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel",style)
	center.add_child(panel)
	body=VBoxContainer.new()
	body.add_theme_constant_override("separation",12)
	panel.add_child(body)
	add_theme_color_override("font_color",TEXT)
	add_theme_font_size_override("font_size",17)
	hide()

func clear_body() -> void:
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	fields.clear()

func label(text:String,size_px:int=17) -> Label:
	var result:=Label.new()
	result.text=text
	result.add_theme_font_size_override("font_size",size_px)
	result.add_theme_color_override("font_color",TEXT)
	body.add_child(result)
	return result

func action_button(text:String,callback:Callable,parent:Node=null) -> Button:
	if parent==null:parent=body
	var button:=Button.new()
	button.text=text
	button.custom_minimum_size=Vector2(0,38)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func checkbox(key:String,text:String,values:Dictionary) -> void:
	var box:=CheckButton.new()
	box.text=text
	box.button_pressed=bool(values[key])
	box.toggled.connect(func(value:bool):
		if not syncing:changed.emit(key,value))
	body.add_child(box)
	fields[key]=box

func slider(key:String,text:String,values:Dictionary,low:float,high:float,step:float) -> void:
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",14)
	body.add_child(row)
	var name_label:=Label.new()
	name_label.text=text
	name_label.custom_minimum_size.x=170
	row.add_child(name_label)
	var control:=HSlider.new()
	control.min_value=low;control.max_value=high;control.step=step
	control.value=float(values[key])
	control.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	control.custom_minimum_size=Vector2(200,30)
	row.add_child(control)
	var value_label:=Label.new()
	value_label.custom_minimum_size.x=55
	row.add_child(value_label)
	var format_value:=func(value:float):value_label.text="%d%%" % roundi(value*100)
	format_value.call(control.value)
	control.value_changed.connect(func(value:float):
		format_value.call(value)
		if not syncing:changed.emit(key,value))
	fields[key]=control

func show_settings(values:Dictionary) -> void:
	clear_body()
	mode="settings"
	label("SETTINGS",25)
	label("The battle is paused while this menu is open.",14)
	slider("master_volume","Master volume",values,0,1,0.05)
	checkbox("muted","Mute audio (M)",values)
	checkbox("fullscreen","Fullscreen (F11)",values)
	slider("ui_scale","Interface scale",values,0.8,1.5,0.1)
	checkbox("edge_scroll","Pan at all four screen edges",values)
	slider("camera_speed","Camera pan speed",values,0.5,2.0,0.1)
	slider("zoom_speed","Wheel / pinch speed",values,0.5,2.0,0.1)
	checkbox("invert_zoom","Reverse zoom direction",values)
	slider("camera_shake","Camera shake",values,0,1,0.1)
	status=label("Scale is limited to fit the window. Preferences save locally.",13)
	status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	action_button("Copy bug report",func():report_requested.emit())
	var buttons:=HBoxContainer.new()
	buttons.add_theme_constant_override("separation",12)
	body.add_child(buttons)
	action_button("Restore defaults",func():defaults_requested.emit(),buttons)
	var done:=action_button("Done  ·  Esc",func():closed.emit(),buttons)
	done.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	show()
	done.grab_focus()

func sync_values(values:Dictionary) -> void:
	syncing=true
	for key in fields:
		if fields[key] is Range:fields[key].value=float(values[key])
		else:fields[key].button_pressed=bool(values[key])
	syncing=false

func show_restart(scenario_name:String) -> void:
	clear_body()
	mode="restart"
	label("RESTART THIS BATTLE?",25)
	label("Your current progress will be lost.\nStart %s again from deployment." % scenario_name,17)
	var buttons:=HBoxContainer.new()
	buttons.add_theme_constant_override("separation",12)
	body.add_child(buttons)
	var cancel:=action_button("Keep playing  ·  Esc",func():closed.emit(),buttons)
	cancel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	action_button("Restart battle",func():restart_confirmed.emit(),buttons)
	show()
	# Enter initially activates the safe choice; Tab selects Restart explicitly.
	cancel.grab_focus()

func dismiss() -> void:
	hide()
	mode=""
