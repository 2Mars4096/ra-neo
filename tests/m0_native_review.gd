extends SceneTree
# Actual engine-rendered readiness/command review. Ammunition is staged; the
# reload, interruption and completion use the existing authoritative executors.
# Requires a graphics display. This is not a timing or human gameplay test.
const Sim=preload("res://scripts/simulation.gd")
var battle
var failures:=0
var captures:Array=[]
var output_dir:="res://docs/images"

func _init()->void:
	if DisplayServer.get_name()=="headless":
		printerr("M0 NATIVE REVIEW requires a graphics display")
		quit(1);return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):output_dir=argument.trim_prefix("--output=")
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))!=OK:
		printerr("M0 NATIVE REVIEW could not create output folder")
		quit(1);return
	call_deferred("run")

func check(ok:bool,message:String)->void:
	if ok:return
	failures+=1;printerr("FAIL: ",message)

func capture(name:String,unit:Dictionary)->void:
	for i in 10:battle.sync_units(0.1)
	battle.hud.queue_redraw()
	for i in 4:await process_frame
	await RenderingServer.frame_post_draw
	var path:=output_dir.path_join("m0-"+name+".png")
	var error:=root.get_texture().get_image().save_png(path)
	check(error==OK,"capture "+name)
	captures.append({"name":name,"path":path,"state":str(unit.members[0].state),"rounds":unit.members[0].rounds,"strength":battle.sim.Infantry.strength(unit,battle.sim.time),"action_events":battle.sim.actions.event_log.duplicate(true)})
	print("M0 CAPTURE ",path," (",error,")")

func run()->void:
	root.size=Vector2i(1280,720)
	Sim.scenario_selection=Sim.Scenarios.index_for_id("black_sea_harbor")
	battle=load("res://scenes/main.tscn").instantiate()
	battle.settings_path="user://m0-native-review-settings.cfg"
	root.add_child(battle);current_scene=battle
	battle.set_process(false);battle.set_physics_process(false)
	battle.effects.muted=true
	battle.close_region();battle.ui_action("begin",Vector2.ZERO)
	battle.show_help=false;battle.paused=false
	var sim=battle.sim
	var unit:Dictionary=sim.living(0).filter(func(u):return u.kind=="rifle")[0]
	battle.selected=[unit.id]
	battle.camera_focus=Vector3(unit.pos.x,0,unit.pos.y)
	battle.camera_size=32.0;battle.camera_zoom_target=32.0;battle.update_camera()
	var label:=Label.new()
	label.text="M0 READINESS REVIEW · STAGED AMMUNITION"
	var backdrop:=ColorRect.new()
	backdrop.color=Color(0.05,0.07,0.06,0.92)
	backdrop.position=Vector2(12,636);backdrop.size=Vector2(366,27)
	battle.hud.add_child(backdrop)
	label.position=Vector2(20,642)
	label.add_theme_font_size_override("font_size",12)
	label.add_theme_color_override("font_color",Color("e9d7ad"))
	battle.hud.add_child(label)
	var member:Dictionary=unit.members[0]
	member.rounds=0;member.magazines.rifle=0
	sim.time=4.0
	sim.infantry_combat(unit,1.0/30.0,[]);sim.sync_action_state(unit)
	check(member.state=="RELOADING" and member.reload_until>sim.time,"quiet empty soldier begins reload")
	check(sim.Infantry.strength(unit,sim.time).ready_members==unit.members.size()-1,"partners remain ready")
	await capture("readiness",unit)
	var destination:Vector2=unit.pos+Vector2(0,-5)
	var accepted:int=sim.issue([unit.id],destination,"move")
	check(accepted==1,"replacement move accepted")
	check(float(member.reload_until)==0.0 and int(member.rounds)==0,"move interrupts preparation without granting rounds")
	sim.sync_action_state(unit)
	for i in 12:sim.tick(1.0/30.0)
	check(float(member.reload_until)==0.0 and member.state!="RELOADING","moving soldier visibly leaves the reload state")
	await capture("reload-interrupted",unit)
	sim.stop([unit.id])
	for actor in unit.members:actor.travel=0.0
	sim.infantry_combat(unit,1.0/30.0,[]);sim.sync_action_state(unit)
	sim.time=float(member.reload_until)+0.01
	sim.infantry_combat(unit,1.0/30.0,[]);sim.sync_action_state(unit)
	check(int(member.rounds)==sim.Infantry.RIFLE_MAGAZINE and float(member.reload_until)==0.0,"quiet preparation completes")
	await capture("ready",unit)
	var report:=FileAccess.open(output_dir.path_join("m0-native-review.json"),FileAccess.WRITE)
	check(report!=null,"metadata file opens")
	if report!=null:report.store_string(JSON.stringify({"engine":Engine.get_version_info().string,"adapter":RenderingServer.get_video_adapter_name(),"render_pixels":str(root.get_texture().get_size()),"captures":captures,"failures":failures,"note":"Native staged readiness review; ordinary fog retained. No performance or human playtesting claim."},"  "))
	print("M0 NATIVE REVIEW: ",captures.size()," captures, ",failures," failures")
	battle.queue_free();await process_frame;await process_frame
	quit(1 if failures else 0)
