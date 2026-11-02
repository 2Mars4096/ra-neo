extends SceneTree

# Native rendering of section 2's API-level mechanics. Contextual input remains
# section 5; these calls use the same preparation, flight and effect executors.
const Sim=preload("res://scripts/simulation.gd")
const Campaign=preload("res://scripts/regional_campaign.gd")
const DT:=1.0/30.0
const SOURCES:=["scripts/simulation.gd","scripts/throwables.gd","scripts/infantry_coordination.gd",
	"scripts/tactical_effects.gd","scripts/battle.gd","scripts/unit_animation.gd","tests/m1_section2_native_review.gd"]
var battle
var failures:=0
var captures:Array=[]
var output_dir:="res://artifacts/m1-section2-native"

func _init()->void:
	if DisplayServer.get_name()=="headless":
		printerr("M1 SECTION 2 NATIVE requires a graphics display");quit(1);return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):output_dir=argument.trim_prefix("--output=")
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))!=OK:
		printerr("M1 SECTION 2 NATIVE cannot create output folder");quit(1);return
	call_deferred("run")

func check(ok:bool,label:String)->void:
	if not ok:failures+=1;printerr("FAIL: ",label)

func step()->void:
	battle.sim.tick(DT)
	battle.consume_events()
	battle.effects._process(DT)
	battle.notices.advance(DT)

func capture(name:String,unit:Dictionary)->void:
	battle.sim.update_visibility()
	for frame in 8:
		battle.sync_units(0.1)
		battle.tactical_effects.sync(battle.sim)
	if battle.refresh_fog_pixels():battle.fog_texture.update(battle.fog_image)
	battle.hud.queue_redraw()
	for frame in 5:await process_frame
	await RenderingServer.frame_post_draw
	var path:=output_dir.path_join(name+".png")
	var error:=root.get_texture().get_image().save_png(path)
	check(error==OK,"capture "+name)
	captures.append({"name":name,"path":path,"time":battle.sim.time,"frag":battle.sim.Throwables.total(unit,"frag"),
		"smoke":battle.sim.Throwables.total(unit,"smoke"),"preparations":battle.sim.throwables.preparations.size(),
		"projectiles":battle.sim.throwables.projectiles.size(),"clouds":battle.sim.throwables.smoke.size(),
		"visible_projectiles":battle.tactical_effects.grenades.multimesh.visible_instance_count,
		"visible_puffs":battle.tactical_effects.clouds.multimesh.visible_instance_count})
	print("M1 SECTION 2 CAPTURE ",path)

func run()->void:
	root.size=Vector2i(1280,720)
	Campaign.enabled=false
	Sim.scenario_selection=Sim.Scenarios.index_for_id("black_sea_harbor")
	battle=load("res://scenes/main.tscn").instantiate()
	battle.settings_path="user://m1-section2-native-settings.cfg"
	root.add_child(battle);current_scene=battle
	battle.set_process(false);battle.set_physics_process(false)
	battle.effects.muted=true
	battle.close_region();battle.ui_action("begin",Vector2.ZERO)
	battle.show_help=false;battle.paused=false;battle.pointer=Vector2(-1,-1)
	var sim=battle.sim
	var unit:Dictionary=sim.living(0).filter(func(u):return u.kind=="rifle")[0]
	sim.stop([unit.id])
	for actor in unit.members:actor.travel=0.0
	var point:=Vector2.INF
	for index in 16:
		var candidate:Vector2=unit.pos+Vector2.from_angle(-PI/2+index*TAU/16)*12.0
		if sim.Throwables.preview(sim,unit,"frag",candidate).ok and sim.Throwables.preview(sim,unit,"smoke",candidate).ok:
			point=candidate;break
	check(point.is_finite(),"native scene has a reachable safe payload destination")
	if not point.is_finite():quit(1);return
	battle.selected=[unit.id]
	var focus:Vector2=unit.pos.lerp(point,0.5)
	battle.camera_focus=Vector3(focus.x,sim.terrain.height_at(focus),focus.y)
	battle.camera_size=31.0;battle.camera_zoom_target=31.0;battle.update_camera()
	var initial_frag:int=sim.Throwables.total(unit,"frag")
	var initial_smoke:int=sim.Throwables.total(unit,"smoke")
	check(sim.issue_throw([unit.id],"frag",point)==1,"fragmentation preparation accepted")
	for tick in 9:step()
	check(unit.members.any(func(member):return member.get("task_kind","")=="throw"),"preparing actor has visible throw state")
	await capture("01-preparation",unit)
	for tick in 60:
		step()
		if not sim.throwables.projectiles.is_empty():break
	for tick in 10:step()
	check(sim.throwables.projectiles.size()==1 and sim.Throwables.total(unit,"frag")==initial_frag-1,"one released projectile spends one frag")
	await capture("02-flight",unit)
	check(battle.tactical_effects.grenades.multimesh.visible_instance_count==1,"released payload has a rendered instance")
	for tick in 90:
		step()
		if sim.throwables.projectiles.is_empty():break
	check(sim.issue_throw([unit.id],"smoke",point)==1,"smoke preparation accepted")
	for tick in 120:
		step()
		if not sim.throwables.smoke.is_empty():break
	check(sim.throwables.smoke.size()==1 and sim.Throwables.total(unit,"smoke")==initial_smoke-1,"one smoke charge creates an authoritative cloud")
	await capture("03-smoke",unit)
	check(battle.tactical_effects.clouds.multimesh.visible_instance_count==battle.tactical_effects.PUFFS,"cloud renders through the bounded presentation pool")
	check(not sim.smoke_clear(unit.pos,point),"rendered cloud blocks the ground optical ray")
	var hashes:Dictionary={}
	for path in SOURCES:hashes[path]=FileAccess.get_sha256("res://"+path)
	var report:=FileAccess.open(output_dir.path_join("review.json"),FileAccess.WRITE)
	check(report!=null,"native metadata opens")
	if report!=null:report.store_string(JSON.stringify({"engine":Engine.get_version_info().string,"adapter":RenderingServer.get_video_adapter_name(),
		"render_pixels":str(root.get_texture().get_size()),"source_sha256":hashes,"captures":captures,"failures":failures,
		"note":"Staged API-level section 2 mechanics in the actual Harbor scene with ordinary fog. Campaign persistence disabled. No contextual input, performance or human-playtest claim."},"  "))
	print("M1 SECTION 2 NATIVE: ",captures.size()," captures, ",failures," failures")
	battle.queue_free();await process_frame;await process_frame
	quit(1 if failures else 0)
