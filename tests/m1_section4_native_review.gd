extends SceneTree

# Same physical site, progressed through the real work executor in Harbor.
# Contextual commands remain section 5; this fixture calls the simulation API.
const Sim=preload("res://scripts/simulation.gd")
const Campaign=preload("res://scripts/regional_campaign.gd")
const Positions=preload("res://scripts/field_positions.gd")
const DT:=1.0/30.0
const SOURCES:=["scripts/simulation.gd","scripts/field_positions.gd","scripts/field_ops.gd",
	"scripts/field_models.gd","scripts/infantry.gd","scripts/battle.gd","tests/m1_section4_native_review.gd"]
var battle
var failures:=0
var captures:Array=[]
var output_dir:="res://artifacts/m1-section4-native"

func _init()->void:
	if DisplayServer.get_name()=="headless":
		printerr("M1 SECTION 4 NATIVE requires a graphics display");quit(1);return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):output_dir=argument.trim_prefix("--output=")
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))!=OK:
		printerr("M1 SECTION 4 NATIVE cannot create output folder");quit(1);return
	call_deferred("run")

func check(ok:bool,label:String)->void:
	if not ok:failures+=1;printerr("FAIL: ",label)

func step()->void:
	battle.sim.tick(DT)
	battle.consume_events()
	battle.effects._process(DT)
	battle.notices.advance(DT)

func capture(name:String,site:Dictionary)->void:
	battle.sim.update_visibility()
	for frame in 8:
		battle.sync_units(0.1)
		battle.tactical_effects.sync(battle.sim)
	if battle.refresh_fog_pixels():battle.fog_texture.update(battle.fog_image)
	battle.hud.queue_redraw()
	for frame in 5:await process_frame
	await RenderingServer.frame_post_draw
	var model:Node3D=battle.nodes[site.id].get_meta("model")
	var stage:int=site.position_stage
	var survey:bool=model.get_node("PositionSurvey").visible
	var earth:bool=model.get_node("HastyEarth").visible
	var original:Array=model.get_meta("position_original_meshes",[])
	check(survey==(stage==0),"survey marker visibility matches authoritative stage")
	check(earth==(stage==1),"shallow earth visibility matches authoritative stage")
	check(not original.is_empty() and original.all(func(mesh):return mesh.visible==(stage>=2)),"reinforced assembly visibility matches authoritative stage")
	var path:=output_dir.path_join(name+".jpg")
	check(root.get_texture().get_image().save_jpg(path,0.9)==OK,"capture "+name)
	captures.append({"name":name,"path":path,"time":battle.sim.time,"site_id":site.id,
		"position_stage":stage,"work_left":site.build_left,"hp":site.hp,"max_hp":site.max_hp,
		"ordinary_cover":battle.sim.terrain.cover(site.pos),"dug_in":battle.sim.terrain.dug_in(site.pos),
		"survey_visible":survey,"hasty_earth_visible":earth,"reinforced_mesh_count":original.size() if stage>=2 else 0})
	print("M1 SECTION 4 CAPTURE ",path)

func find_site(sim,engineer:Dictionary)->Dictionary:
	# Prefer a rifle section sharing a nearby site with the existing engineer.
	# The engineer itself is also an eligible ordinary digger if its frontage is
	# the only clear soil. No actors or works are teleported into a valid state.
	var candidates:Array=sim.living(0).filter(func(u):return u.kind=="rifle")
	candidates.append(engineer)
	for unit in candidates:
		for radius in [0.0,3.0,5.0,7.0]:
			for index in (1 if radius==0.0 else 24):
				var point:Vector2=unit.pos+Vector2.from_angle(index*TAU/24)*float(radius)
				if point.distance_to(engineer.pos)>Positions.LOCAL_REACH:continue
				if Positions.dig_reason(sim,[unit.id],point,false)!="":continue
				if Positions._worker_plan(sim,engineer,point).is_empty():continue
				return {"unit":unit,"point":point}
	return {}

func prepare_frontage(sim,engineer:Dictionary)->bool:
	# Harbor's insertion is paved. Reach nearby soil through the existing move
	# command before preparing a position, preserving real geometry and actors.
	var origin:Vector2=engineer.pos
	for radius in [16.0,24.0,32.0]:
		for index in 24:
			var point:Vector2=origin+Vector2.from_angle(index*TAU/24)*float(radius)
			if Positions._ground_reason(sim,point)!="":continue
			if not sim.terrain.traversable(point,"land",float(sim.definitions.engineer.radius),[],"infantry"):continue
			if sim.issue([engineer.id],point)==0:continue
			for tick in 900:
				step()
				if engineer.orders.is_empty():break
			sim.stop([engineer.id])
			for tick in 15:step()
			print("M1 SECTION 4 FRONTAGE ",engineer.pos," after move to ",point)
			return not find_site(sim,engineer).is_empty()
	return false

func run()->void:
	root.size=Vector2i(1280,720)
	Campaign.enabled=false
	Sim.scenario_selection=Sim.Scenarios.index_for_id("black_sea_harbor")
	battle=load("res://scenes/main.tscn").instantiate()
	battle.settings_path="user://m1-section4-native-settings.cfg"
	root.add_child(battle);current_scene=battle
	battle.set_process(false);battle.set_physics_process(false)
	battle.effects.muted=true
	battle.close_region();battle.ui_action("begin",Vector2.ZERO)
	battle.show_help=false;battle.paused=false;battle.pointer=Vector2(-1,-1)
	var sim=battle.sim
	var engineer:Dictionary=sim.living(0).filter(func(u):return u.kind=="engineer")[0]
	var infantry:Array=sim.living(0).filter(func(u):return u.kind in ["rifle","engineer"])
	sim.stop(infantry.map(func(u):return u.id))
	var plan:Dictionary=find_site(sim,engineer)
	if plan.is_empty() and prepare_frontage(sim,engineer):plan=find_site(sim,engineer)
	check(not plan.is_empty(),"native Harbor frontage contains reachable level soil")
	if plan.is_empty():quit(1);return
	var unit:Dictionary=plan.unit
	var point:Vector2=plan.point
	var funds:float=sim.credits
	check(sim.issue_dig([unit.id],point)==1,"native infantry dig order accepted")
	check(sim.credits==funds,"digging has no supply charge")
	var sites:Array=sim.units.filter(func(u):return u.get("field_position",false))
	if sites.size()!=1:check(false,"one authoritative site exists");quit(1);return
	var site:Dictionary=sites[0]
	battle.selected=[unit.id]
	battle.camera_focus=Vector3(point.x,sim.terrain.height_at(point),point.y)
	battle.camera_size=23.0;battle.camera_zoom_target=23.0;battle.update_camera()
	for tick in 180:
		step()
		if float(site.position_progress)>=1.0:break
	check(site.position_stage==0 and site.build_left>0 and site.position_progress>0,"survey capture follows real approach and unfinished work")
	check(not sim.terrain.cover(site.pos) and not sim.terrain.dug_in(site.pos),"unfinished site grants no protection")
	await capture("01-survey",site)
	for tick in 1000:
		step()
		if site.position_stage==1:break
	check(site.position_stage==1 and is_equal_approx(site.max_hp,Positions.HASTY_HP),"real dig work completes at hasty durability")
	check(sim.terrain.cover(site.pos) and not sim.terrain.dug_in(site.pos),"completed hasty site publishes only ordinary cover")
	await capture("02-hasty",site)
	var before_upgrade:float=sim.credits
	check(sim.upgrade_position([engineer.id],site.id)==1,"existing nearby engineer accepts reinforcement")
	check(is_equal_approx(before_upgrade-sim.credits,float(sim.definitions.fighting_trench.cost)),"engineer upgrade charges the existing trench cost once")
	battle.selected=[engineer.id]
	for tick in 800:
		step()
		if site.position_stage==2:break
	check(site.position_stage==2 and is_equal_approx(site.max_hp,float(sim.definitions.fighting_trench.hp)),"same site completes reinforced durability")
	check(sim.terrain.dug_in(site.pos),"completed reinforced site publishes dug-in protection")
	await capture("03-reinforced",site)
	check(captures.size()==3 and captures.all(func(item):return item.site_id==site.id),"all captures follow the same authoritative site")
	var hashes:Dictionary={}
	for path in SOURCES:hashes[path]=FileAccess.get_sha256("res://"+path)
	var report:=FileAccess.open(output_dir.path_join("review.json"),FileAccess.WRITE)
	check(report!=null,"native metadata opens")
	if report!=null:report.store_string(JSON.stringify({"engine":Engine.get_version_info().string,"adapter":RenderingServer.get_video_adapter_name(),
		"render_pixels":str(root.get_texture().get_size()),"source_sha256":hashes,"captures":captures,"failures":failures,
		"digger_kind":unit.kind,"initial_supply":funds,"note":"Same site progresses through real API work in the native Harbor scene with ordinary fog and existing infantry. Campaign persistence disabled. No contextual input, performance or human-playtest claim."},"  "))
	print("M1 SECTION 4 NATIVE: ",captures.size()," captures, ",failures," failures")
	battle.queue_free();await process_frame;await process_frame
	quit(1 if failures else 0)
