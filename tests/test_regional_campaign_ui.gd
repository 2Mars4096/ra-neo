extends SceneTree
# Actual modal signals, scene reloads and save files; deliberately controlled
# battle outcomes keep this a lifecycle test rather than a balance playthrough.
const Campaign=preload("res://scripts/regional_campaign.gd")
const Scenarios=preload("res://scripts/scenario_catalog.gd")
const Sim=preload("res://scripts/simulation.gd")
var checks:=0
var failures:=0
var save_path:=""
var original_enabled:=false
var original_path:=""
var original_loaded:=false
var original_selection:=-1

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func frames()->void:
	await process_frame
	await process_frame

func freeze_scene():
	await frames()
	var battle=current_scene
	if battle!=null:
		battle.set_process(false)
		battle.set_physics_process(false)
	return battle

func unit_of(sim,kind:String)->Dictionary:
	for unit in sim.living(0):
		if unit.kind==kind:return unit
	return {}

func cleanup_save()->void:
	for suffix in ["",".bak",".tmp"]:
		var path:String=ProjectSettings.globalize_path(save_path+suffix)
		if FileAccess.file_exists(path):DirAccess.remove_absolute(path)

func _init()->void:
	original_enabled=Campaign.enabled
	original_path=Campaign.storage_path
	original_loaded=Campaign.session_loaded
	original_selection=Sim.scenario_selection
	save_path="user://test_regional_campaign_ui_%s.json"%OS.get_process_id()
	Campaign.enabled=true
	Campaign.storage_path=save_path
	Campaign.session_loaded=true
	Sim.scenario_selection=Scenarios.index_for_id("bayhead_rail_valley")
	cleanup_save()
	call_deferred("run")

func run()->void:
	root.size=Vector2i(1440,900)
	var battle=load("res://scenes/main.tscn").instantiate()
	root.add_child(battle);current_scene=battle
	battle.set_process(false);battle.set_physics_process(false)
	await frames()
	check(battle.campaign.active and battle.campaign_path==save_path,"real scene opts into the isolated campaign")
	check(battle.show_help and battle.paused and not battle.campaign.begun,"fresh operation opens at a deployment briefing")
	check(not FileAccess.file_exists(save_path),"viewing a new briefing does not create a deployment save")
	check(" ".join(battle.hud.brief_lines).ends_with("Hold all sectors for 75 seconds."),"wrapped rail briefing retains its final mission instruction")
	var initial_count:int=battle.sim.living(0).size()
	battle.ui_action("begin",Vector2.ZERO)
	battle._physics_process(1.0/30.0)
	check(not battle.show_help and not battle.paused and battle.campaign.begun,"Deploy and the first actual tick begin the campaign")
	check(FileAccess.file_exists(save_path) and battle.campaign.data.retry.roster.size()==initial_count,"deployment writes the real initial-force checkpoint")
	var rifle:Dictionary=unit_of(battle.sim,"rifle")
	var tank:Dictionary=unit_of(battle.sim,"tank")
	var helo:Dictionary=unit_of(battle.sim,"helo")
	check(not rifle.is_empty() and not tank.is_empty() and not helo.is_empty(),"authored force supports casualty and vehicle test fixtures")
	rifle.members[0].hp=0.0;rifle.members[0].wound="KIA"
	battle.sim.Infantry.publish(rifle)
	var rifle_hp:float=rifle.hp
	tank.hp=float(tank.max_hp)*0.6
	var tank_hp:float=tank.hp
	helo.hp=0.0
	var surviving_count:int=battle.sim.living(0).size()
	battle.sim.credits=777.5
	battle.sim.field_ops["queue"]=["rifle"]
	battle.sim.recruit_clock=100.0
	var withdrawal_supply:float=777.5+float(battle.sim.definitions.rifle.cost)
	var old_id:int=battle.get_instance_id()
	var sim_id:int=battle.sim.get_instance_id()
	var old_save:String=FileAccess.get_file_as_string(save_path)
	battle.ui_action("region",Vector2.ZERO)
	check(battle.region_open() and battle.paused and root.disable_3d,"Region pauses play and hides the covered 3D battlefield")
	check(battle.sim.get_instance_id()==sim_id and not battle.campaign.finished,"browsing keeps the live battle and expedition")
	check(FileAccess.get_file_as_string(save_path)==old_save,"browsing alone does not record a withdrawal")
	check(battle.regional_map.campaign_summary.text.contains("deployed") and battle.regional_map.campaign_summary.text.contains("777"),"atlas summarizes the current force and unspent supply")
	battle.close_region()
	check(not battle.paused and not root.disable_3d,"returning restores the live battle pause/render state")
	battle.open_region()
	battle.regional_map.select_battlefield("limestone_pass")
	battle.regional_map.launch.pressed.emit()
	check(battle.regional_map.confirming and battle.get_instance_id()==old_id,"first switch click requests withdrawal confirmation")
	check(battle.regional_map.status.text.contains("Survivors") and not battle.campaign.finished,"confirmation explains the saved force without committing it")
	battle.regional_map.launch.pressed.emit()
	battle=await freeze_scene()
	check(battle!=null and battle.get_instance_id()!=old_id,"confirmed withdrawal reloads the selected battlefield")
	if battle==null:
		finish();return
	check(battle.sim.scenario.id=="limestone_pass" and battle.show_help and battle.paused,"selected pass opens at its own deployment briefing")
	check(battle.campaign.data.history.bayhead_rail_valley=="WITHDRAWN","scene transition persists the withdrawal result")
	var roster:Array=battle.campaign.snapshot(battle.sim)
	check(roster.size()==surviving_count and roster.size()==initial_count-1,"transition carries survivors without adding a free starter army")
	check(roster.any(func(record):return record.kind=="rifle" and is_equal_approx(float(record.hp),rifle_hp)),"withdrawn infantry keeps its casualty-adjusted health")
	check(roster.any(func(record):return record.kind=="tank" and is_equal_approx(float(record.hp),tank_hp)),"withdrawn armor keeps its damage")
	check(is_equal_approx(battle.sim.credits,withdrawal_supply),"new battle receives unspent supply plus one queue refund")
	check(battle.sim.field_ops.get("queue",[]).is_empty(),"old tactical purchase queue cannot deploy again after its refund")
	check(not root.disable_3d and not battle.region_open(),"scene transition restores normal 3D rendering")
	battle.ui_action("begin",Vector2.ZERO)
	battle._physics_process(1.0/30.0)
	battle.sim.result="VICTORY"
	battle._physics_process(0.0)
	check(battle.campaign.finished and battle.campaign.secured("limestone_pass"),"finished tactical result is saved by the real controller")
	check(battle.campaign_message.contains("saved"),"results expose successful campaign persistence")
	# Simulate quitting and launching a new session from the normal default.
	# This exercises _ready's persisted last-battlefield resolution, rather than
	# relying on the previous scene's static selected index.
	var resume_count:int=battle.campaign.data.roster.size()
	var resume_supply:float=battle.campaign.data.supply
	battle.queue_free()
	await frames()
	Sim.scenario_selection=Sim.default_selection()
	Campaign.session_loaded=false
	battle=load("res://scenes/main.tscn").instantiate()
	root.add_child(battle);current_scene=battle
	battle.set_process(false);battle.set_physics_process(false)
	await frames()
	check(Campaign.session_loaded and battle.sim.scenario.id=="limestone_pass","new session resumes the last saved battlefield instead of default Harbor")
	check(Sim.scenario_selection==Scenarios.index_for_id("limestone_pass") and battle.sim.terrain.scenario_id==Sim.scenario_selection,"resumed scenario selection and loaded terrain agree")
	check(battle.campaign.snapshot(battle.sim).size()==resume_count,"startup restores the saved expedition without a second starter army")
	check(is_equal_approx(battle.sim.credits,resume_supply),"startup restores saved supply without another refund")
	check(battle.campaign.secured("limestone_pass") and battle.sim.field_ops.reserve_delay_bonus==45.0,"startup restores ownership and its actual strategic consequence")
	check(battle.show_help and battle.paused and battle.sim.time==0.0 and not battle.campaign.begun,"resumed operation waits at a fresh deployment briefing")
	battle.open_region()
	check(battle.regional_map.region_buttons.limestone_pass.text.begins_with("✓"),"secured battlefield is visibly marked on the atlas")
	battle.regional_map.select_battlefield("windbreak_fields")
	battle.regional_map.launch.pressed.emit()
	battle=await freeze_scene()
	check(battle!=null and battle.sim.scenario.id=="windbreak_fields","completed battle can open the new agricultural operation")
	if battle==null:
		finish();return
	check(battle.sim.field_ops.reserve_delay_bonus==45.0,"saved pass control changes the next operation's reserve timing")
	battle.ui_action("begin",Vector2.ZERO)
	battle._physics_process(1.0/30.0)
	var checkpoint:Dictionary=battle.campaign.data.retry.duplicate(true)
	for unit in battle.sim.units:
		if unit.team==0:unit.hp=0.0
	battle.sim.result="DEFEAT"
	battle._physics_process(0.0)
	check(battle.campaign.finished and battle.campaign.data.history.windbreak_fields=="DEFEAT","defeat is durably recorded")
	old_id=battle.get_instance_id()
	battle.ui_action("restart",Vector2.ZERO)
	battle=await freeze_scene()
	check(battle!=null and battle.get_instance_id()!=old_id,"retry after defeat reloads the actual scene")
	if battle==null:
		finish();return
	check(battle.sim.scenario.id=="windbreak_fields" and battle.sim.time==0.0,"retry stays on the defeated operation")
	check(battle.campaign.snapshot(battle.sim).size()==checkpoint.roster.size(),"retry restores the previous expedition instead of a free default army")
	check(is_equal_approx(battle.sim.credits,float(checkpoint.supply)),"retry restores the deployment budget")
	check(battle.campaign.secured("limestone_pass"),"retry preserves previously secured regional progress")
	battle.open_region()
	old_save=FileAccess.get_file_as_string(save_path)
	battle.regional_map.request_reset()
	check(battle.regional_map.confirming and battle.regional_map.resetting,"new campaign asks for confirmation inside the atlas")
	battle.regional_map.cancel_switch.pressed.emit()
	check(not battle.regional_map.confirming and not battle.regional_map.resetting,"cancel retains the current campaign")
	check(FileAccess.get_file_as_string(save_path)==old_save and battle.campaign.secured("limestone_pass"),"cancelled reset does not modify saved progress")
	battle.regional_map.request_reset()
	battle.regional_map.launch.pressed.emit()
	battle=await freeze_scene()
	check(battle!=null and battle.show_help and battle.paused,"confirmed new campaign opens a clean briefing")
	if battle!=null:
		check(not battle.campaign.data.started and battle.campaign.data.secured.is_empty(),"confirmed reset clears saved operations and the expedition")
		check(battle.sim.living(0).size()==battle.sim.scenario.player_force.size(),"only a new campaign restores the authored initial force")
		check(battle.sim.credits==float(battle.sim.scenario.field_supply),"new campaign restores the selected operation's starting budget")
		battle.queue_free()
	await frames()
	finish()

func finish()->void:
	cleanup_save()
	Campaign.enabled=original_enabled
	Campaign.storage_path=original_path
	Campaign.session_loaded=original_loaded
	Sim.scenario_selection=original_selection
	print("REGIONAL CAMPAIGN UI: %d checks, %d failures"%[checks,failures])
	quit(1 if failures>0 else 0)
