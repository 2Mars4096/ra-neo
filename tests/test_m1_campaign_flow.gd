extends SceneTree

# Actual Battle inputs, atlas signals, scene reloads and isolated campaign files.
# Terminal results are controlled fixtures; this does not claim mission balance.
const Campaign=preload("res://scripts/regional_campaign.gd")
const Sim=preload("res://scripts/simulation.gd")
const DT:=1.0/30.0
var battle
var checks:=0
var failures:=0
var save_path:=""
var previous_enabled:=false
var previous_path:=""
var previous_loaded:=false
var previous_selection:=-1

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func frames()->void:
	await process_frame;await process_frame

func freeze_scene()->void:
	await frames()
	battle=current_scene
	if battle!=null:
		battle.set_process(false);battle.set_physics_process(false)

func key(code:Key)->void:
	var event:=InputEventKey.new()
	event.keycode=code;event.pressed=true;battle._input(event)
	event.pressed=false;battle._input(event)

func click(at:Vector2)->void:
	var event:=InputEventMouseButton.new()
	event.position=at;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true;battle._input(event)
	event.pressed=false;battle._input(event)

func inventory(unit:Dictionary)->Array:
	var result:Array=[]
	for member in unit.get("members",[]):
		# JSON reads integral stock as floats; compare its values and key set.
		var stock:Dictionary={}
		for payload in member.get("throwables",{}):stock[payload]=int(member.throwables[payload])
		result.append({"id":str(member.member_id),"wound":str(member.wound),"throwables":stock})
	return result

func find_veteran(expected:Array)->Dictionary:
	for unit in battle.sim.living(0):
		if unit.kind=="rifle" and inventory(unit)==expected:return unit
	return {}

func transient_world_empty()->bool:
	var sim=battle.sim
	return sim.throwables.preparations.is_empty() and sim.throwables.projectiles.is_empty() and sim.throwables.smoke.is_empty() and sim.support_requests.requests.is_empty() and sim.FieldPositions.jobs(sim).is_empty()

func focus(unit:Dictionary)->void:
	battle.selected=[unit.id]
	battle.camera_focus=Vector3(unit.pos.x,battle.sim.terrain.height_at(unit.pos),unit.pos.y)
	battle.camera_size=42;battle.camera_zoom_target=42;battle.update_camera()
	battle.hud.battlefield_ui.tutorial_active=false
	battle.hud.queue_redraw();await frames()

func aim_point(unit:Dictionary,payload:String)->Vector2:
	for distance in [12.0,15.0,17.0,10.0]:
		for direction in 36:
			var world:Vector2=unit.pos+Vector2.from_angle(direction*TAU/36)*float(distance)
			var screen:Vector2=battle.screen_pos(world)
			if not battle.hud.battlefield_rect().has_point(screen) or battle.hud.action_at(screen)!="":continue
			if battle.sim.Throwables.preview(battle.sim,unit,payload,battle.world_pos(screen)).ok:return screen
	return Vector2.INF

func advance_to_release(unit:Dictionary,payload:String,before:int)->bool:
	for tick in 180:
		battle._physics_process(DT)
		if battle.sim.Throwables.total(unit,payload)==before-1:return true
	return false

func create_scene()->void:
	battle=load("res://scenes/main.tscn").instantiate()
	battle.settings_path="user://m1-campaign-flow-settings.cfg"
	root.add_child(battle);current_scene=battle
	battle.set_process(false);battle.set_physics_process(false);battle.effects.muted=true
	await frames()

func cleanup()->void:
	for suffix in ["",".bak",".tmp"]:
		var path:=ProjectSettings.globalize_path(save_path+suffix)
		if FileAccess.file_exists(path):DirAccess.remove_absolute(path)

func _init()->void:
	previous_enabled=Campaign.enabled;previous_path=Campaign.storage_path;previous_loaded=Campaign.session_loaded;previous_selection=Sim.scenario_selection
	save_path="user://test_m1_campaign_flow_%s.json"%OS.get_process_id()
	Campaign.enabled=true;Campaign.storage_path=save_path;Campaign.session_loaded=true
	Sim.scenario_selection=Sim.Scenarios.index_for_id("bayhead_rail_valley")
	cleanup();call_deferred("run")

func run()->void:
	root.size=Vector2i(1440,900)
	await create_scene()
	check(battle.campaign.active and battle.campaign_path==save_path,"Battle uses the isolated operational campaign")
	battle.ui_action("begin",Vector2.ZERO);battle._physics_process(DT)
	check(battle.campaign.begun and FileAccess.file_exists(save_path),"actual deployment creates its retry checkpoint")
	var rifle:Dictionary=battle.sim.living(0).filter(func(unit):return unit.kind=="rifle")[0]
	await focus(rifle);key(KEY_S)
	var stock:int=battle.sim.Throwables.total(rifle,"smoke")
	var point:Vector2=aim_point(rifle,"smoke")
	check(point.is_finite(),"real regional insertion has an eligible UI smoke target")
	if not point.is_finite():await finish();return
	key(KEY_V);click(point)
	check(battle.sim.throwables.preparations.size()==1 and battle.sim.Throwables.total(rifle,"smoke")==stock,"UI preparation reserves one smoke without spending")
	key(KEY_S);battle._physics_process(DT)
	check(battle.sim.throwables.preparations.is_empty() and battle.sim.Throwables.total(rifle,"smoke")==stock,"pre-release Hold preserves campaign equipment")
	key(KEY_V);click(point)
	if battle.sim.throwables.preparations.is_empty():check(false,"second smoke command starts preparation");await finish();return
	var thrower:String=battle.sim.throwables.preparations[0].member
	check(advance_to_release(rifle,"smoke",stock),"actual UI-requested smoke release spends exactly one carried charge")
	key(KEY_S)
	for tick in 180:
		battle._physics_process(DT)
		if not battle.sim.throwables.smoke.is_empty():break
	check(not battle.sim.throwables.smoke.is_empty(),"released smoke survives Hold and becomes a real optical volume")
	# Explicit empty equipment and casualty slots are supported campaign states.
	var others:Array=rifle.members.filter(func(member):return member.member_id!=thrower)
	others[0].throwables={}
	others[1].hp=0.0;others[1].wound="KIA"
	battle.sim.Infantry.publish(rifle)
	var expected:Array=inventory(rifle)
	check(battle.sim.Throwables.total(rifle,"smoke")==0,"empty inventory and a casualty cannot donate replacement smoke")
	key(KEY_B)
	check(not battle.sim.SupportRequests.request_for(battle.sim,rifle).is_empty(),"backup request exists in the world before withdrawal")
	var old_id:int=battle.get_instance_id()
	var old_save:String=FileAccess.get_file_as_string(save_path)
	battle.open_region()
	check(FileAccess.get_file_as_string(save_path)==old_save,"browsing the atlas does not prematurely replace the deployment checkpoint")
	battle.regional_map.select_battlefield("limestone_pass")
	battle.regional_map.launch.pressed.emit()
	check(battle.regional_map.confirming,"switching a live operation asks for its existing withdrawal confirmation")
	battle.regional_map.launch.pressed.emit();await freeze_scene()
	check(battle!=null and battle.get_instance_id()!=old_id,"confirmed withdrawal loads a new actual Battle scene")
	if battle==null:await finish();return
	check(battle.sim.scenario.id=="limestone_pass" and battle.campaign.data.history.bayhead_rail_valley=="WITHDRAWN","scene transition records withdrawal and opens the selected operation")
	rifle=find_veteran(expected)
	check(not rifle.is_empty(),"new operation preserves exact per-member stock, explicit emptiness and casualty identity")
	check(transient_world_empty(),"new operation starts without old preparations, projectiles, smoke, backup or work jobs")
	check(int(battle.campaign.data.version)==3,"actual campaign transition writes the version-three schema")
	if rifle.is_empty():await finish();return
	check(battle.sim.Throwables.total(rifle,"smoke")==0,"new deployment cannot refill exhausted usable smoke")
	battle.ui_action("begin",Vector2.ZERO);battle._physics_process(DT)
	battle.sim.result="VICTORY";battle._physics_process(0.0)
	check(battle.campaign.finished and battle.campaign.secured("limestone_pass"),"actual result handler persists the controlled victory")
	# A new application session resolves its saved last operation in Battle._ready.
	battle.queue_free();await frames();Campaign.session_loaded=false;Sim.scenario_selection=Sim.default_selection()
	await create_scene()
	check(battle.sim.scenario.id=="limestone_pass" and Campaign.session_loaded,"new session resolves the saved last battlefield")
	rifle=find_veteran(expected)
	check(not rifle.is_empty() and transient_world_empty(),"disk reload preserves stock and casualty slots without restoring tactical effects")
	if rifle.is_empty():await finish();return
	battle.ui_action("begin",Vector2.ZERO);battle._physics_process(DT)
	var checkpoint:Array=inventory(rifle)
	await focus(rifle);key(KEY_S)
	var frag:int=battle.sim.Throwables.total(rifle,"frag")
	point=aim_point(rifle,"frag")
	check(frag==1 and point.is_finite(),"carried surviving member has one real frag available in the next operation")
	if point.is_finite():
		key(KEY_G);click(point)
		check(advance_to_release(rifle,"frag",frag),"second-operation release spends the carried frag rather than fresh stock")
		check(battle.sim.Throwables.total(rifle,"frag")==0,"carried usable frag inventory is now empty")
	battle.sim.result="DEFEAT";battle._physics_process(0.0)
	check(battle.campaign.finished and battle.campaign.data.history.limestone_pass=="DEFEAT","real result handler writes depleted equipment at defeat")
	old_id=battle.get_instance_id();battle.ui_action("restart",Vector2.ZERO);await freeze_scene()
	check(battle!=null and battle.get_instance_id()!=old_id,"defeat retry reloads the real scene")
	if battle!=null:
		rifle=find_veteran(checkpoint)
		check(not rifle.is_empty(),"explicit retry restores the exact prior deployment equipment instead of a default kit")
		check(transient_world_empty() and battle.sim.time==0.0,"retry restores a deployment checkpoint with a fresh tactical world")
		if not rifle.is_empty():check(battle.sim.Throwables.total(rifle,"frag")==1 and battle.sim.Throwables.total(rifle,"smoke")==0,"retry restores only its one checkpoint frag while exhausted smoke remains exhausted")
		var saved:Variant=JSON.parse_string(FileAccess.get_file_as_string(save_path))
		check(Campaign.valid(saved) and int(saved.version)==3,"post-retry disk state remains a valid current-schema campaign")
	await finish()

func finish()->void:
	if is_instance_valid(battle):battle.queue_free()
	await frames();cleanup()
	Campaign.enabled=previous_enabled;Campaign.storage_path=previous_path;Campaign.session_loaded=previous_loaded;Sim.scenario_selection=previous_selection
	print("M1 CAMPAIGN FLOW: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
