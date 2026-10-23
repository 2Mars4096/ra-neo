extends Control
# Geographical operation selection. Terrain and combat stay in the selected
# battlefield; this view never creates a second simulation or changes its rules.
signal closed
signal battlefield_requested(scenario_index:int)

const Catalog := preload("res://scripts/region_catalog.gd")
const INK := Color("131c1d")
const PANEL := Color("202b29")
const LINE := Color("4c6158")
const TEXT := Color("e6e8d9")
const MUTED := Color("a5b8a9")
const ACCENT := Color("dac18a")
var region:Dictionary={}
var selected_id:=""
var active_id:=""
var live_battle:=false
var confirming:=false
var canvas:MapCanvas
var title:Label
var details_title:Label
var terrain_label:Label
var summary:Label
var features:Label
var status:Label
var attribution:Label
var launch:Button
var cancel_switch:Button
var region_buttons:Dictionary={}

class MapCanvas extends Control:
	const LAND := Color("4b5b48")
	const WATER := Color("1d3940")
	const GRID := Color(0.75,0.81,0.72,0.075)
	var controller:Control
	var zoom:=1.0
	var pan:=Vector2.ZERO
	var dragging:=false
	var drag_origin:=Vector2.ZERO
	var last_pointer:=Vector2.ZERO
	var moved:=false
	var hover_id:=""
	var map_font:=SystemFont.new()

	func _ready() -> void:
		mouse_filter=Control.MOUSE_FILTER_STOP
		clip_contents=true
		focus_mode=Control.FOCUS_ALL
		mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
		map_font.font_names=PackedStringArray(["Avenir Next","Helvetica Neue","Arial"])
		resized.connect(func():clamp_pan();queue_redraw())
		mouse_exited.connect(func():hover_id="";queue_redraw())

	func extent() -> Vector2:
		var dimensions:Array=controller.region.get("size",[1200,840])
		return Vector2(maxf(1,float(dimensions[0])),maxf(1,float(dimensions[1])))

	func scale_factor() -> float:
		var area:=extent()
		return maxf(0.01,minf((size.x-48)/area.x,(size.y-48)/area.y))*zoom

	func origin() -> Vector2:
		return (size-extent()*scale_factor())*0.5+pan

	func world_to_screen(point:Vector2) -> Vector2:
		return origin()+point*scale_factor()

	func screen_to_world(point:Vector2) -> Vector2:
		return (point-origin())/scale_factor()

	func reset_view() -> void:
		zoom=1.0;pan=Vector2.ZERO
		queue_redraw()

	func clamp_pan() -> void:
		var overflow:Vector2=(extent()*scale_factor()-size)*0.5
		pan.x=clampf(pan.x,-maxf(0,overflow.x+48),maxf(0,overflow.x+48))
		pan.y=clampf(pan.y,-maxf(0,overflow.y+48),maxf(0,overflow.y+48))

	func zoom_at(factor:float,at:Vector2) -> void:
		var before:=screen_to_world(at)
		zoom=clampf(zoom*factor,1.0,4.0)
		pan+=at-world_to_screen(before)
		clamp_pan()
		queue_redraw()

	func polygon(points:Array) -> PackedVector2Array:
		var result:=PackedVector2Array()
		for point in points:
			if point is Array and point.size()>=2:result.append(world_to_screen(Vector2(point[0],point[1])))
		return result

	func path_points(item) -> Array:
		return item.get("points",[]) if item is Dictionary else item

	func draw_routes(key:String,color:Color,width:float,dashed:bool=false) -> void:
		for route in controller.region.get(key,[]):
			var points:=polygon(path_points(route))
			if points.size()<2:continue
			if dashed:
				for i in points.size()-1:draw_dashed_line(points[i],points[i+1],color,width,5,true)
			else:draw_polyline(points,color,width,true)
			if key=="railways":
				for i in points.size()-1:
					var segment:Vector2=points[i+1]-points[i]
					var length:=segment.length()
					var normal:=segment.normalized().orthogonal()*3
					for offset in range(5,int(length),9):
						var centre:Vector2=points[i]+segment*(float(offset)/maxf(length,1))
						draw_line(centre-normal,centre+normal,color,1,true)

	func hit_at(at:Vector2) -> String:
		var best:=""
		var distance:=INF
		for item in controller.region.get("battlefields",[]):
			var bounds:Rect2=Catalog.bounds(item)
			var centre:=world_to_screen(bounds.get_center())
			var screen_bounds:=Rect2(world_to_screen(bounds.position),bounds.size*scale_factor())
			var candidate:=at.distance_to(centre)
			if (screen_bounds.has_point(at) or candidate<20) and candidate<distance:
				distance=candidate;best=str(item.id)
		return best

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO,size),WATER.darkened(0.23))
		var map_bounds:=Rect2(origin(),extent()*scale_factor())
		draw_rect(map_bounds,LAND)
		for area in controller.region.get("woods",[]):
			var points:Array=area.get("points",[]) if area is Dictionary else area
			var outline:=polygon(points)
			if outline.size()>2:draw_colored_polygon(outline,Color("354d3e"))
		for ridge in controller.region.get("ridges",[]):
			var outline:=polygon(path_points(ridge))
			if outline.size()>1:
				draw_polyline(outline,Color("7a7d62"),maxf(9,16*zoom),true)
				draw_polyline(outline,Color("96977b"),maxf(2,3*zoom),true)
		for water in controller.region.get("water_polygons",[]):
			var points:Array=water.get("points",[]) if water is Dictionary else water
			var outline:=polygon(points)
			if outline.size()>2:
				draw_colored_polygon(outline,WATER)
				var closed_outline:=outline.duplicate();closed_outline.append(outline[0])
				draw_polyline(closed_outline,Color("738d7d"),1.2,true)
		for x in range(0,int(extent().x)+1,100):draw_line(world_to_screen(Vector2(x,0)),world_to_screen(Vector2(x,extent().y)),GRID,1)
		for y in range(0,int(extent().y)+1,100):draw_line(world_to_screen(Vector2(0,y)),world_to_screen(Vector2(extent().x,y)),GRID,1)
		draw_routes("roads",Color("c2b18a"),2.5)
		draw_routes("railways",Color("e0ddd0"),1.5)
		draw_routes("ferries",Color("78a7ae"),1.3,true)
		var settlement_labels:Array[Rect2]=[]
		for settlement in controller.region.get("settlements",[]):
			var at:Vector2=world_to_screen(Catalog.point(settlement.get("at",[0,0])))
			var name:=str(settlement.get("name",""))
			draw_circle(at,3,Color("d5d5bc"))
			draw_string(map_font,at+Vector2(7,-7),name,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("d5ddcd"))
			settlement_labels.append(Rect2(at+Vector2(7,-20),Vector2(map_font.get_string_size(name,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x,16)))
		var number:=0
		for item in controller.region.get("battlefields",[]):
			number+=1
			var bounds:Rect2=Catalog.bounds(item)
			var r:=Rect2(world_to_screen(bounds.position),bounds.size*scale_factor())
			var chosen:bool=str(item.id)==controller.selected_id
			var hovered:bool=str(item.id)==hover_id
			var color:Color=ACCENT if chosen else (TEXT if hovered else Color("a4c1ad"))
			draw_rect(r,Color(color,0.16 if chosen else 0.06))
			draw_rect(r,color,false,2 if chosen else 1)
			var centre:=r.get_center()
			draw_circle(centre,15,INK)
			draw_arc(centre,15,0,TAU,32,color,2,true)
			draw_string(map_font,centre+Vector2(-8,5),"%02d" % number,HORIZONTAL_ALIGNMENT_LEFT,-1,13,color)
			if chosen:
				var label:=str(item.get("name",item.id))
				var width:=map_font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x+16
				var label_at:=Vector2(clampf(r.position.x,8,maxf(8,size.x-width-8)),clampf(r.end.y+7,8,size.y-32))
				var tag:=Rect2(label_at,Vector2(width,25))
				if settlement_labels.any(func(rect):return rect.grow(4).intersects(tag)):
					label_at.y=clampf(r.position.y-32,8,size.y-32)
				draw_rect(Rect2(label_at,Vector2(width,25)),INK)
				draw_string(map_font,label_at+Vector2(8,17),label,HORIZONTAL_ALIGNMENT_LEFT,-1,13,ACCENT)
		draw_rect(Rect2(Vector2.ZERO,size),LINE,false,1)
		# North is always up; unlike the battle camera this atlas never rotates.
		draw_string(map_font,Vector2(size.x-31,27),"N",HORIZONTAL_ALIGNMENT_LEFT,-1,13,TEXT)
		draw_line(Vector2(size.x-27,36),Vector2(size.x-27,61),TEXT,1.5)
		draw_line(Vector2(size.x-27,36),Vector2(size.x-32,44),TEXT,1.5)
		draw_line(Vector2(size.x-27,36),Vector2(size.x-22,44),TEXT,1.5)

	func _gui_input(event:InputEvent) -> void:
		if event is InputEventMouseButton:
			if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
				zoom_at(1.2 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.0/1.2,event.position)
				accept_event()
			elif event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_MIDDLE]:
				if event.pressed:
					dragging=true;drag_origin=event.position;last_pointer=event.position;moved=false
					grab_focus()
				elif dragging:
					dragging=false
					if not moved and event.button_index==MOUSE_BUTTON_LEFT:
						var hit:=hit_at(event.position)
						if hit!="":controller.select_battlefield(hit)
				accept_event()
		elif event is InputEventMouseMotion:
			if dragging:
				if event.position.distance_to(drag_origin)>4:moved=true
				if moved:
					pan+=event.position-last_pointer;clamp_pan();queue_redraw()
				last_pointer=event.position
			else:
				var next:=hit_at(event.position)
				if next!=hover_id:hover_id=next;queue_redraw()
			accept_event()
		elif event is InputEventMagnifyGesture:
			zoom_at(event.factor,event.position);accept_event()
		elif event is InputEventKey and event.pressed:
			if event.keycode==KEY_HOME:reset_view();accept_event()
			elif event.keycode in [KEY_PLUS,KEY_EQUAL,KEY_KP_ADD]:zoom_at(1.2,size*0.5);accept_event()
			elif event.keycode in [KEY_MINUS,KEY_KP_SUBTRACT]:zoom_at(1.0/1.2,size*0.5);accept_event()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	var background:=ColorRect.new()
	background.color=INK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(background)
	add_theme_color_override("font_color",TEXT)
	add_theme_font_size_override("font_size",15)
	var margin:=MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,20)
	add_child(margin)
	var layout:=VBoxContainer.new()
	layout.add_theme_constant_override("separation",12)
	margin.add_child(layout)
	var header:=HBoxContainer.new()
	header.add_theme_constant_override("separation",16)
	layout.add_child(header)
	var heading:=VBoxContainer.new()
	heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	make_label(heading,"FOR EVERY DAWN  /  REGIONAL MAP",12,ACCENT)
	title=make_label(heading,"BLACK SEA COAST",27,TEXT)
	var close:=make_button("Back to battlefield  ·  Esc",func():closed.emit())
	close.custom_minimum_size=Vector2(230,42)
	close.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	header.add_child(close)
	var body:=HBoxContainer.new()
	body.size_flags_vertical=Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",20)
	layout.add_child(body)
	var left:=VBoxContainer.new()
	left.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation",9)
	body.add_child(left)
	canvas=MapCanvas.new()
	canvas.controller=self
	canvas.custom_minimum_size=Vector2(400,300)
	canvas.size_flags_vertical=Control.SIZE_EXPAND_FILL
	left.add_child(canvas)
	var controls:=HBoxContainer.new()
	controls.add_theme_constant_override("separation",8)
	left.add_child(controls)
	controls.add_child(make_button("−",func():canvas.zoom_at(1.0/1.2,canvas.size*0.5)))
	controls.add_child(make_button("+",func():canvas.zoom_at(1.2,canvas.size*0.5)))
	controls.add_child(make_button("Fit region",func():canvas.reset_view()))
	var help:=make_label(controls,"Wheel / pinch to zoom · Drag to pan · Click a battlefield",12,MUTED)
	help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	help.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var legend:=make_label(left,"━━ Road      ╫ Railway      - - Ferry      ▰ Woodland      ∿ Ridge",12,MUTED)
	legend.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var sidebar:=VBoxContainer.new()
	sidebar.custom_minimum_size=Vector2(310,0)
	sidebar.add_theme_constant_override("separation",9)
	body.add_child(sidebar)
	var scroll:=ScrollContainer.new()
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	sidebar.add_child(scroll)
	var right:=VBoxContainer.new()
	right.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation",9)
	scroll.add_child(right)
	make_label(right,"BATTLEFIELDS",12,ACCENT)
	var locations:=VBoxContainer.new()
	locations.name="Locations"
	locations.add_theme_constant_override("separation",6)
	right.add_child(locations)
	var separator:=HSeparator.new()
	separator.add_theme_constant_override("separation",14)
	right.add_child(separator)
	terrain_label=make_label(right,"",12,ACCENT)
	details_title=make_label(right,"",23,TEXT)
	details_title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	summary=make_label(right,"",15,TEXT)
	summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	features=make_label(right,"",13,MUTED)
	features.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	# The briefing can scroll in a short window; the operation action and its
	# progress-loss confirmation remain visible below it.
	status=make_label(sidebar,"",13,ACCENT)
	status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	launch=make_button("Open briefing",request_battlefield)
	launch.custom_minimum_size.y=45
	sidebar.add_child(launch)
	cancel_switch=make_button("Keep current battle",cancel_confirmation)
	sidebar.add_child(cancel_switch)
	cancel_switch.hide()
	attribution=make_label(layout,"",11,MUTED)
	attribution.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	hide()

func make_label(parent:Node,value:String,size_px:int,color:Color) -> Label:
	var label:=Label.new()
	label.text=value
	label.add_theme_font_size_override("font_size",size_px)
	label.add_theme_color_override("font_color",color)
	parent.add_child(label)
	return label

func make_button(value:String,callback:Callable) -> Button:
	var button:=Button.new()
	button.text=value
	button.custom_minimum_size=Vector2(36,34)
	button.add_theme_color_override("font_color",TEXT)
	button.add_theme_color_override("font_hover_color",TEXT)
	button.add_theme_color_override("font_pressed_color",ACCENT)
	button.add_theme_font_size_override("font_size",14)
	for state in ["normal","hover","pressed","focus"]:
		var style:=StyleBoxFlat.new()
		style.bg_color=PANEL.lightened(0.12) if state=="hover" else PANEL
		style.border_color=ACCENT if state in ["focus","pressed"] else LINE
		style.set_border_width_all(2 if state=="focus" else 1)
		style.content_margin_left=10;style.content_margin_right=10
		style.content_margin_top=5;style.content_margin_bottom=5
		button.add_theme_stylebox_override(state,style)
	button.pressed.connect(callback)
	return button

func show_region(scenario_id:String,in_progress:bool=false) -> void:
	region=Catalog.data()
	active_id=Catalog.for_scenario(region,scenario_id)
	live_battle=in_progress
	confirming=false
	title.text=str(region.get("name","REGIONAL MAP")).to_upper()
	attribution.text=str(region.get("attribution","Fictional region inspired by real coastal geography. Battlefield distances are compressed for play."))
	var locations:VBoxContainer=find_child("Locations",true,false)
	for child in locations.get_children():
		locations.remove_child(child);child.queue_free()
	region_buttons.clear()
	var index:=0
	for item in region.get("battlefields",[]):
		index+=1
		var id:=str(item.id)
		var button:=make_button("%02d  %s" % [index,str(item.get("name",id))],func():select_battlefield(id))
		button.alignment=HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode=true
		button.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		button.tooltip_text=str(item.get("summary",""))
		locations.add_child(button)
		region_buttons[id]=button
	var fallback:=str(region.battlefields[0].id) if not region.get("battlefields",[]).is_empty() else ""
	select_battlefield(active_id if active_id!="" else fallback)
	canvas.reset_view()
	show()
	if region_buttons.has(selected_id):region_buttons[selected_id].grab_focus()

func select_battlefield(id:String) -> void:
	var item:=Catalog.battlefield(region,id)
	selected_id=id
	confirming=false
	cancel_switch.hide()
	details_title.text=str(item.get("name","No battlefield selected"))
	terrain_label.text=str(item.get("terrain","Regional operation")).to_upper()
	summary.text=str(item.get("summary",region.get("description","")))
	var lines:=PackedStringArray()
	for feature in item.get("features",[]):lines.append("• "+str(feature))
	features.text="\n".join(lines)
	for key in region_buttons:region_buttons[key].set_pressed_no_signal(key==id)
	launch.disabled=Catalog.scenario_index(region,id)<0
	launch.text="Back to current battlefield" if id==active_id else "Open battlefield briefing  →"
	status.text="CURRENT BATTLEFIELD" if id==active_id else "A fresh operation starts at its deployment briefing."
	if launch.disabled:status.text="This battlefield is currently unavailable."
	canvas.queue_redraw()

func cancel_confirmation() -> void:
	select_battlefield(selected_id)
	launch.grab_focus()

func request_battlefield() -> void:
	var index:=Catalog.scenario_index(region,selected_id)
	if index<0:return
	if selected_id==active_id:
		closed.emit()
		return
	if live_battle and not confirming:
		confirming=true
		status.text="Switch battlefield? Your current battle progress will be lost."
		launch.text="Leave battle and open briefing"
		cancel_switch.show()
		cancel_switch.grab_focus()
		return
	battlefield_requested.emit(index)

func dismiss() -> void:
	canvas.dragging=false
	hide()
	confirming=false
