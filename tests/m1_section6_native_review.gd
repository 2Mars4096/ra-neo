extends SceneTree

# Render the shared, continuous Harbor integration encounter. Initial forces
# are controlled by its fixture; all subsequent work and world effects come
# from the ordinary simulation commands. This is not a human balance playtest.
const Sim=preload("res://scripts/simulation.gd")
const Campaign=preload("res://scripts/regional_campaign.gd")
const Fixture=preload("res://tests/m1_defense_fixture.gd")
const DT:=1.0/30.0
var battle
var fixture
var failures:=0
var checks:=0
var captures:Array=[]
var source_start:Dictionary={}
var sight_from:=Vector3.ZERO
var sight_to:=Vector3.ZERO
var output_dir:="res://artifacts/m1-section6-native"

func _init()->void:
	if DisplayServer.get_name()=="headless":
		printerr("M1 SECTION 6 NATIVE requires a graphics display");quit(1);return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):output_dir=argument.trim_prefix("--output=")
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))!=OK:
		printerr("M1 SECTION 6 NATIVE cannot create output folder");quit(1);return
	source_start=source_hashes()
	call_deferred("run")

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func _source_files(path:String,files:Array[String])->void:
	for name in DirAccess.get_files_at(path):
		if name.get_extension() in ["gd","tscn","json","png","gdshader"]:files.append(path.path_join(name))
	for name in DirAccess.get_directories_at(path):_source_files(path.path_join(name),files)

func source_hashes()->Dictionary:
	var files:Array[String]=["res://project.godot","res://tests/m1_defense_fixture.gd","res://tests/m1_section6_native_review.gd"]
	for path in ["scripts","resources","scenes","assets"]:_source_files("res://"+path,files)
	files.sort()
	var hashes:Dictionary={}
	for path in files:hashes[path.trim_prefix("res://")]=FileAccess.get_sha256(path)
	return hashes

func step()->void:
	fixture.tick()
	# Observe authoritative events in the fixture before Battle consumes them.
	# Cosmetic effects use the same simulated elapsed time between captures.
	battle.consume_events();battle.effects._process(DT);battle.notices.advance(DT)

func advance_until(condition:Callable,max_ticks:int,label:String)->bool:
	for tick in max_ticks:
		if condition.call():check(true,label);return true
		step()
	var reached:bool=condition.call()
	check(reached,label)
	return reached

func select(names:Array)->void:
	battle.selected=[]
	for name in names:battle.selected.append(fixture.units[name].id)

func point(at:Vector2)->void:
	var event:=InputEventMouseMotion.new()
	event.position=at;battle._input(event)

func refresh()->void:
	battle.hud.battlefield_ui.update(battle.hud)
	battle.sim.update_visibility()
	battle.weather_fx.sync(battle.sim.weather,battle.sim.time)
	for frame in 5:
		battle.sync_units(0.1);battle.tactical_effects.sync(battle.sim)
	if battle.refresh_fog_pixels():battle.fog_texture.update(battle.fog_image)
	battle.hud.queue_redraw()
	for frame in 4:await process_frame
	await RenderingServer.frame_post_draw

func member_state(member:Dictionary)->Dictionary:
	var state:Dictionary={}
	for name in ["member_id","state","pos","hp","wound","task_kind","task_action","cover_for","cover_phase","throwables"]:
		state[name]=member.get(name,null)
	return state.duplicate(true)

func unit_state(unit:Dictionary)->Dictionary:
	var members:Array=[]
	for member in unit.members:members.append(member_state(member))
	return {"id":unit.id,"kind":unit.kind,"pos":unit.pos,"hp":unit.hp,"visible":unit.visible,
		"status":battle.TacticalInterface.status(battle.sim,unit),"reason":unit.reason,"members":members,
		"frag":battle.sim.Throwables.total(unit,"frag"),"smoke":battle.sim.Throwables.total(unit,"smoke"),
		"support_task":unit.get("support_task",{}).duplicate(true)}

func button_label(id:String)->String:
	var units:Array=battle.TacticalInterface.sections(battle)
	var kind:=id.trim_prefix("tactical:")
	if kind in ["frag","smoke"]:
		var stock:=0
		for unit in units:stock+=battle.sim.Throwables.total(unit,kind)
		return ("G FRAG %d" if kind=="frag" else "V SMOKE %d")%stock
	if kind=="fire":
		var connected:Array=battle.TacticalInterface.policy_sections(battle.sim,units)
		return "H FIRE FREE" if connected.all(func(unit):return unit.fire_policy=="hold") else "H HOLD FIRE"
	return {"dig":"D DIG","upgrade":"U UPGRADE","backup":"B BACKUP","reserve":"RESERVE","auto_frag":"AUTO FRAG"}.get(kind,"")

func capture(name:String)->void:
	point(Vector2(30,100));await refresh()
	var hud=battle.hud
	var geometry:Array=[]
	var roster:Rect2=hud.battlefield_ui.roster_rect(hud)
	for button in hud.hits.filter(func(hit):return str(hit.id).begins_with("tactical:")):
		var label:=button_label(button.id)
		var label_width:float=hud.bold.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x
		check(Rect2(Vector2.ZERO,hud.size).encloses(button.rect),"command stays in viewport: "+name+" "+button.id)
		check(label_width+16<=button.rect.size.x,"command label fits: "+name+" "+button.id)
		if hud.battlefield_ui.roster_ids.size()>1:check(not button.rect.intersects(roster),"command clears roster: "+name+" "+button.id)
		geometry.append({"id":button.id,"rect":str(button.rect),"label":label,"label_width":label_width})
	var path:=output_dir.path_join(name+".jpg")
	check(root.get_texture().get_image().save_jpg(path,0.9)==OK,"capture "+name)
	var units:Dictionary={}
	for role in fixture.units:units[role]=unit_state(fixture.units[role])
	var site:Dictionary={}
	for field in ["id","kind","pos","position_stage","position_progress","position_total","build_left","build_paused","paid_cost","engineer_id"]:
		site[field]=fixture.site.get(field,null)
	var selected:Array=[]
	for id in battle.selected:selected.append(id)
	captures.append({"name":name,"path":path,"window_pixels":str(root.size),"render_pixels":str(root.get_texture().get_size()),
		"hud_points":str(hud.size),"requested_ui_scale":battle.settings.values.ui_scale,"simulation_seconds":battle.sim.time,
		"phase":fixture.phase,"units":units,"selected":selected,"site":site,"request":fixture.request.duplicate(true),
		"metrics":fixture.metrics.duplicate(true),"actor_claims":battle.sim.actions.claims.duplicate(true),
		"preparations":battle.sim.throwables.preparations.size(),"projectiles":battle.sim.throwables.projectiles.size(),
		"smoke":battle.sim.throwables.smoke.size(),"visible_smoke_puffs":battle.tactical_effects.clouds.multimesh.visible_instance_count,
		"frontage_clear_forward":battle.sim.optical_ray_clear(sight_from,sight_to),"frontage_clear_reverse":battle.sim.optical_ray_clear(sight_to,sight_from),
		"credits":battle.sim.credits,"buttons":geometry})
	print("M1 SECTION 6 CAPTURE ",path)

func run()->void:
	root.size=Vector2i(1280,800)
	Campaign.enabled=false
	Sim.scenario_selection=Sim.Scenarios.index_for_id("black_sea_harbor")
	battle=load("res://scenes/main.tscn").instantiate()
	battle.settings_path="user://m1-section6-native-settings.cfg"
	root.add_child(battle);current_scene=battle
	battle.set_process(false);battle.set_physics_process(false)
	battle.effects.muted=true;battle.effects.set_process(false)
	battle.close_region();battle.ui_action("begin",Vector2.ZERO)
	battle.show_help=false;battle.paused=true
	battle.hud.battlefield_ui.tutorial_active=false
	fixture=Fixture.new()
	check(fixture.setup(battle.sim),"shared fixture preserves actual Harbor terrain")
	if not fixture.errors.is_empty():await finish();return
	sight_from=Vector3(Fixture.SITE.x,1.6,Fixture.SITE.y)
	sight_to=Vector3(fixture.units.enemy.pos.x,1.6,fixture.units.enemy.pos.y)
	check(battle.sim.optical_ray_clear(sight_from,sight_to),"the later smoke frontage begins optically clear")
	# Removed scenario combatants must not remain as visible orphan models.
	for id in battle.nodes:
		if not battle.sim.units_by_id.has(id):battle.nodes[id].queue_free()
	battle.nodes.clear();battle.render_history.clear()
	battle.camera_focus=Vector3(Fixture.SITE.x-3,battle.sim.terrain.height_at(Fixture.SITE),Fixture.SITE.y+2)
	battle.camera_size=34;battle.camera_zoom_target=34;battle.update_camera()
	select(["defender","engineer","reserve"])
	await capture("01-harbor-defense-ready")
	check(fixture.start_defense(),"ordinary commands start digging and dispatch a delegated reserve")
	if not advance_until(func():return fixture.metrics.combined_roles,240,"one section concurrently digs, covers and prepares its delegated frag"):
		await finish();return
	select(["defender"])
	await capture("02-cover-throw-and-dig")
	if not advance_until(func():return int(fixture.metrics.frag_releases)==1,120,"automatic frag physically releases once"):
		await finish();return
	check(fixture.begin_smoke(),"replacement starts real smoke after a cancelled preparation")
	check(fixture.metrics.smoke_cancel_unspent,"cancelled smoke preparation preserves inventory")
	await capture("03-released-frag-smoke-preparation")
	if not advance_until(func():return int(fixture.metrics.smoke_releases)==1,180,"explicit smoke physically releases once"):
		await finish();return
	check(fixture.resume_work(),"accepted replacement resumes the same unfinished site")
	check(fixture.metrics.smoke_released_after_replacement,"accepted work preserves the already released smoke")
	if not advance_until(func():return not battle.sim.throwables.smoke.is_empty(),180,"physical smoke lands and creates its optical volume"):
		await finish();return
	select(["defender","reserve"])
	await capture("04-smoke-and-resumed-work")
	check(int(fixture.metrics.frag_bursts)==1,"released frag detonates after its owning order was replaced")
	check(battle.tactical_effects.clouds.multimesh.visible_instance_count>0,"authoritative smoke has visible native puffs")
	check(not battle.sim.optical_ray_clear(sight_from,sight_to) and not battle.sim.optical_ray_clear(sight_to,sight_from),"visible smoke blocks the original optical frontage in both directions")
	if not advance_until(func():return int(fixture.site.position_stage)==1 and fixture.request.phase in battle.sim.SupportRequests.TERMINAL,1500,"digging completes and the reserve finishes its service lifecycle"):
		await finish();return
	check(fixture.request.phase=="completed","reserve delivers sustained useful support and returns successfully")
	select(["defender","engineer"])
	await capture("05-hasty-position-backup-returned")
	var supply:float=battle.sim.credits
	check(fixture.begin_upgrade(),"engineer accepts one idempotent reinforcement job")
	check(is_equal_approx(supply-battle.sim.credits,float(battle.sim.definitions.fighting_trench.cost)),"duplicate reinforcement request charges once")
	if not advance_until(func():return float(fixture.site.position_progress)>=2.0,300,"engineer physically reaches and reinforces the site"):
		await finish();return
	select(["engineer"])
	battle.settings.values.ui_scale=1.5;battle.update_interface_scale();battle.update_camera()
	await capture("06-reinforcing-largest-ui")
	check(fixture.interrupt_upgrade(),"Hold releases the engineer claim and pauses paid work")
	var progress:float=fixture.site.position_progress
	for tick in 18:step()
	check(is_equal_approx(progress,float(fixture.site.position_progress)),"interrupted work does not advance without a worker")
	await capture("07-paid-work-paused")
	check(fixture.resume_upgrade(),"ordinary reinforcement command resumes paid progress")
	check(is_equal_approx(supply-battle.sim.credits,float(battle.sim.definitions.fighting_trench.cost)),"paid resume does not charge supply again")
	if not advance_until(func():return int(fixture.site.position_stage)==2,900,"resumed physical work completes the reinforced position"):
		await finish();return
	select(["defender","engineer","reserve"])
	await capture("08-reinforced-defense-complete")
	check(fixture.metrics.covering_shots>0,"covering soldier fired during concurrent dig and throw tasks")
	check(fixture.metrics.reserve_moved and fixture.metrics.reserve_delivered and float(fixture.metrics.max_service)>=4.0,"reserve physically moved and supplied the complete useful service")
	check(fixture.metrics.same_site and fixture.stock_balances(),"same site and every member inventory balance survive the encounter")
	check(fixture.metrics.claim_errors.is_empty(),"all observed actor and resource claims remain exclusive")
	check(battle.sim.FieldPositions.jobs(battle.sim).is_empty(),"completed work leaves no outstanding job")
	check(battle.sim.throwables.smoke.is_empty() and battle.sim.optical_ray_clear(sight_from,sight_to),"finite smoke expires and restores the original optical frontage")
	await finish()

func finish()->void:
	var end_hashes:=source_hashes()
	check(source_start==end_hashes,"render and simulation sources remain unchanged during this native process")
	var report:=FileAccess.open(output_dir.path_join("review.json"),FileAccess.WRITE)
	check(report!=null,"native metadata opens")
	if report!=null:
		report.store_string(JSON.stringify({"engine":Engine.get_version_info().string,"adapter":RenderingServer.get_video_adapter_name(),
			"checks":checks,"failures":failures,"source_sha256":end_hashes,"process_start_source_sha256":source_start,"captures":captures,
			"metrics":fixture.metrics if fixture!=null else {},"fixture_errors":fixture.errors if fixture!=null else [],
			"note":"One continuous deterministic encounter on actual Harbor terrain, using the shared defense fixture and ordinary commands. Campaign disabled for native review; actual scene/disk inventory lifecycle is checked separately. Screenshots remain local. No supported-hardware performance or human balance claim."},"  "))
	print("M1 SECTION 6 NATIVE: %d captures, %d checks, %d failures"%[captures.size(),checks,failures])
	if is_instance_valid(battle):battle.queue_free()
	await process_frame;await process_frame
	quit(1 if failures else 0)
