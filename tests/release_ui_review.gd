extends SceneTree
# Actual native-render review of the integrated Harbor player interface.
# Run with a graphics display, not --headless. Captures are staged UI states;
# the scout contact is earned through ordinary issue/tick simulation.
const ReleaseInfo=preload("res://scripts/release_info.gd")
var battle
var captures:Array=[]
var failures:=0
var output_dir:="res://artifacts"

func _init()->void:
	if DisplayServer.get_name()=="headless":
		printerr("RELEASE UI REVIEW requires a graphics display")
		quit(1);return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):output_dir=argument.trim_prefix("--output=")
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))!=OK:
		printerr("RELEASE UI REVIEW could not create output folder")
		quit(1);return
	call_deferred("run")

func shoot(name:String)->void:
	battle.hud.queue_redraw()
	for i in 3:await process_frame
	await RenderingServer.frame_post_draw
	var path:=output_dir.path_join("release-ui-"+name+".png")
	var error:=root.get_texture().get_image().save_png(path)
	if error!=OK:failures+=1
	captures.append({"name":name,"path":path,"window_pixels":str(root.size),"logical_viewport":str(root.get_visible_rect().size),"render_pixels":str(root.get_texture().get_size()),"save_error":error})
	print("CAPTURE ",name," ",root.size," logical=",root.get_visible_rect().size," status=",error)

func press(code:Key)->void:
	var event:=InputEventKey.new()
	event.keycode=code;event.pressed=true
	battle._input(event)

func run()->void:
	root.size=Vector2i(1440,900)
	battle=load("res://scenes/main.tscn").instantiate()
	battle.settings_path="user://release-ui-review-settings.cfg"
	root.add_child(battle);current_scene=battle
	battle.set_physics_process(false)
	battle.effects.muted=true
	battle.settings.reset();battle.apply_settings()
	await shoot("01-briefing-1440")
	battle.ui_action("begin",Vector2.ZERO)
	battle.paused=true
	battle.selected=battle.all_sections()
	await shoot("02-roster-1440")
	battle.ui_action("tutorial:start",Vector2.ZERO)
	await shoot("03-guide-1440")
	root.size=Vector2i(1280,720)
	await shoot("04-roster-guide-1280")
	var engineer:Dictionary=battle.sim.living(0).filter(func(u):return u.kind=="engineer")[0]
	battle.ui_action("roster:focus:%d" % engineer.id,Vector2.ZERO)
	battle.ui_action("tutorial:hide",Vector2.ZERO)
	await shoot("05-engineers-1280")
	press(KEY_F10)
	await shoot("06-settings-1280")
	# Exercise the actual focused Control and its signal wiring. Clear any old
	# report first so a stale X11 clipboard cannot make a disconnected button pass.
	DisplayServer.clipboard_set("For Every Dawn clipboard probe")
	var report_buttons:Array=battle.menu.find_children("*","Button",true,false).filter(func(button):return button.text=="Copy bug report")
	if report_buttons.size()!=1:
		failures+=1
		printerr("FAIL: Settings must expose one Copy bug report button")
	else:
		report_buttons[0].grab_focus()
		for pressed in [true,false]:
			var event:=InputEventKey.new()
			event.keycode=KEY_ENTER;event.pressed=pressed
			root.push_input(event,true)
			await process_frame
	var copied=JSON.parse_string(DisplayServer.clipboard_get())
	if not copied is Dictionary or copied.get("mission",{}).get("id","")!="black_sea_harbor" or copied.get("build",{}).get("commit","")!=ReleaseInfo.build_info().get("commit",""):
		failures+=1
		printerr("FAIL: Settings did not copy a current Harbor diagnostic report")
	await shoot("07-report-1280")
	press(KEY_ESCAPE)
	# Visible enemy information is captured only after a live scout reveals it.
	var sim=battle.sim
	var scout:Dictionary=sim.living(0).filter(func(u):return u.kind=="drone")[0]
	var goal:Vector2=sim.objectives[1].pos
	sim.issue([scout.id],goal,"move")
	var enemy:Dictionary={}
	for i in 30*45:
		sim.tick(1.0/30.0)
		var spotted:Array=sim.units.filter(func(u):return sim.alive(u) and u.team==1 and u.visible)
		if not spotted.is_empty():enemy=spotted[0];break
	battle.sync_units(0.0)
	battle.selected=[]
	if enemy.is_empty():
		failures+=1
		printerr("FAIL: ordinary UAV scouting did not reveal a contact")
	else:
		battle.camera_focus=Vector3(enemy.pos.x,0,enemy.pos.y)
		battle.camera_size=72.0;battle.camera_zoom_target=72.0;battle.update_camera()
		battle.pointer=battle.click_points(enemy)[0]
		battle.hud.battlefield_ui.hover_checked=-10000
		await shoot("08-observed-enemy-1280")
		battle.camera_size=150.0;battle.camera_zoom_target=150.0;battle.update_camera()
		battle.pointer=Vector2(-1,-1)
		await shoot("09-role-tags-1280")
	battle.request_restart()
	await shoot("10-restart-1280")
	battle.close_menu()
	root.size=Vector2i(1120,720)
	battle.selected=battle.all_sections()
	await shoot("11-compact-1120")
	var file:=FileAccess.open(output_dir.path_join("release-ui.json"),FileAccess.WRITE)
	if file==null:
		failures+=1
		printerr("FAIL: could not save UI review metadata")
	else:
		file.store_string(JSON.stringify({"build":ReleaseInfo.build_info(),"engine":Engine.get_version_info().string,"adapter":RenderingServer.get_video_adapter_name(),"captures":captures,"failures":failures,"note":"Native rendered appearance checks; software rendering is not target-hardware performance certification."},"  "))
	print("RELEASE UI REVIEW: ",captures.size()," captures, ",failures," failures")
	quit(1 if failures else 0)
