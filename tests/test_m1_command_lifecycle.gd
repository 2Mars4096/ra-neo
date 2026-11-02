extends SceneTree

# Real Battle input dispatch against deterministic clear-soil simulation state.
# The authored Harbor command/layout fixture remains test_m1_commands.gd.
const Sim=preload("res://scripts/simulation.gd")
const Terrain=preload("res://scripts/terrain.gd")
var battle
var checks:=0
var failures:=0

func _init()->void:
	Sim.scenario_selection=Sim.Scenarios.index_for_id("black_sea_harbor")
	call_deferred("run")

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func key(code:Key)->void:
	var event:=InputEventKey.new()
	event.keycode=code;event.pressed=true
	battle._input(event)

func click(point:Vector2,button:int=MOUSE_BUTTON_LEFT,pressed:bool=true)->void:
	var event:=InputEventMouseButton.new()
	event.position=point;event.button_index=button;event.pressed=pressed
	battle._input(event)

func refresh()->void:
	battle.hud.battlefield_ui.update(battle.hud)
	battle.hud.queue_redraw()
	await process_frame;await process_frame

func preview_at(point:Vector2)->Dictionary:
	var event:=InputEventMouseMotion.new()
	event.position=battle.screen_pos(point)
	battle._input(event)
	await refresh()
	return battle.hud.tactical_ui.preview_data

func fixture()->Dictionary:
	# Reuse the small field-ops ruleset before installing the deterministic
	# terrain, avoiding six redundant full Harbor terrain constructions.
	var sim=Sim.new(false,5)
	sim.scenario.id="black_sea_harbor"
	sim.terrain=Terrain.new(0,{"id":"command_lifecycle_fixture","size":[96,72],"shore_x":90,"port":false,
		"mode":"field_ops","style":"showcase","blocks":[],"woods":[],"rubble":[0,0,0,0],
		"mud":[0,0,0,0],"objectives":[],"roads":{}})
	sim.terrain.roadside_blocks.clear();sim.terrain.prop_blocks.clear();sim.terrain.trees.clear()
	sim.terrain.rebuild_static_index()
	sim.scenario.autonomy=true;sim.scenario.jam_radius=0.0
	sim.objectives.clear();sim.field_ops.income_rate=0.0;sim.field_ops.started=false
	sim.field_ops.enemy_clock=1000.0;sim.enemy_clock=1000.0;sim.credits=1000.0
	sim.field_ops.insertion=Vector2(12,50)
	var infantry:Dictionary=sim.spawn("rifle",0,Vector2(28,36))
	var engineer:Dictionary=sim.spawn("engineer",0,Vector2(36,32))
	var reserve:Dictionary=sim.spawn("rifle",0,Vector2(18,36))
	sim.rebuild_spatial();sim.rebuild_actor_spatial();sim.update_visibility()
	battle.sim=sim;battle.selected=[infantry.id];battle.set_targeting("")
	battle.show_help=false;battle.paused=true;battle.pointer=Vector2(-100,-100)
	battle.camera_focus=Vector3(28,0,36);battle.camera_size=36;battle.camera_zoom_target=36;battle.update_camera()
	battle.hud.battlefield_ui.roster_ids.clear();battle.hud.battlefield_ui.tutorial_active=false
	return {"sim":sim,"infantry":infantry,"engineer":engineer,"reserve":reserve}

func advance(sim,seconds:float)->void:
	for i in ceili(seconds*30.0):sim.tick(1.0/30.0)

func usable_screen(point:Vector2,label:String)->Vector2:
	var screen:Vector2=battle.screen_pos(point)
	check(battle.hud.battlefield_rect().has_point(screen) and battle.hud.action_at(screen)=="",label+" is an unobstructed battlefield click")
	return screen

func unavailable_hotkeys()->void:
	var f:=fixture()
	await refresh()
	key(KEY_U)
	check(battle.tactical_mode.is_empty(),"rifle-only U cannot arm an unsupported engineer upgrade")
	battle.cancel_targeting(false)
	for member in f.infantry.members:member.throwables.frag=0
	key(KEY_G)
	check(battle.tactical_mode.is_empty(),"zero-stock G agrees with the unavailable frag button")
	battle.cancel_targeting(false)
	var field_state:Dictionary=f.sim.field_ops
	f.sim.field_ops={}
	key(KEY_D)
	check(battle.tactical_mode.is_empty(),"D cannot arm field work in a non-field mode")
	battle.cancel_targeting(false);f.sim.field_ops=field_state
	var tank:Dictionary=f.sim.spawn("tank",0,Vector2(50,44))
	battle.selected=[tank.id]
	for code in [KEY_G,KEY_V,KEY_D,KEY_U,KEY_B,KEY_H]:key(code)
	check(battle.tactical_mode.is_empty() and f.sim.throwables.preparations.is_empty() and f.sim.SupportRequests.request_for(f.sim,tank).is_empty(),"vehicle-only selection cannot execute infantry controls")
	battle.selected=[];key(KEY_G);key(KEY_D)
	check(battle.tactical_mode.is_empty(),"empty selection cannot enter a tactical gesture")

func radio_delegation()->void:
	var f:=fixture()
	var sim=f.sim
	var u:Dictionary=f.infantry
	var peer:Dictionary=f.engineer
	sim.objectives.append({"name":"Jammer","pos":u.pos,"owner":1,"progress":0.0})
	sim.scenario.jam_radius=0.5
	await refresh()
	check(sim.comms_blocked(u) and not sim.comms_blocked(peer),"policy fixture isolates one disconnected section")
	for action in ["reserve","auto_frag"]:
		battle.selected=[u.id]
		battle.ui_action("tactical:"+action,Vector2.ZERO)
		var notice:String=battle.notices.cursor_text.to_lower()
		check(not u.get("reserve_enabled",false) if action=="reserve" else u.throw_policy=="manual",action+" does not change a disconnected section")
		check(notice.contains("radio") or notice.contains("disconnect") or notice.contains("connected"),action+" rejection explains the lost communication")
		battle.selected=[u.id,peer.id]
		battle.ui_action("tactical:"+action,Vector2.ZERO)
		notice=battle.notices.cursor_text.to_lower()
		check(peer.get("reserve_enabled",false) and not u.get("reserve_enabled",false) if action=="reserve" else peer.throw_policy=="defensive" and u.throw_policy=="manual",action+" applies only to the connected member of a mixed selection")
		check((notice.contains("1 / 2") or notice.contains("1/2") or notice.contains("1 of 2")) and (notice.contains("radio") or notice.contains("disconnect")),action+" partial acknowledgement identifies the accepted fraction and radio loss")
		battle.ui_action("tactical:"+action,Vector2.ZERO)
		check(not peer.get("reserve_enabled",false) and not u.get("reserve_enabled",false) if action=="reserve" else peer.throw_policy=="manual" and u.throw_policy=="manual",action+" can toggle the connected section off while its disconnected peer remains unchanged")
	battle.selected=[u.id,peer.id]
	key(KEY_H)
	check(peer.fire_policy=="hold" and u.fire_policy=="free","mixed H puts only the connected section on Hold fire")
	key(KEY_H)
	check(peer.fire_policy=="free" and u.fire_policy=="free","repeated H releases the connected section even when its disconnected peer never received Hold fire")

func digging_and_upgrade()->void:
	var f:=fixture()
	var sim=f.sim
	var u:Dictionary=f.infantry
	var engineer:Dictionary=f.engineer
	await refresh()
	var point:=Vector2(31,38)
	var screen:=usable_screen(point,"local dig site")
	check(sim.FieldPositions.dig_reason(sim,[u.id],point).is_empty(),"clear-soil fixture admits a real worker route")
	var initial:Dictionary=u.assignment.duplicate(true)
	var funds:float=sim.credits
	var count:int=sim.units.size()
	key(KEY_D);click(screen,MOUSE_BUTTON_RIGHT)
	check(battle.tactical_mode.is_empty() and u.assignment==initial and sim.units.size()==count and sim.credits==funds,"right-click cancels pending digging without creating work or replacing the assignment")
	key(KEY_D);click(screen)
	var site:Dictionary=sim.get_unit(int(u.get("building_id",-1)))
	check(not site.is_empty() and site.get("field_position",false),"D and a world click start the real field-position executor")
	if site.is_empty():return
	check(battle.tactical_mode.is_empty() and not battle.dragging and sim.credits==funds and int(site.position_stage)==0,"accepted dig exits targeting, creates an unfinished survey and spends no supply")
	advance(sim,2.0)
	var version:int=u.order_version
	var job:Dictionary=sim.FieldPositions.jobs(sim)[u.id].duplicate(true)
	var progress:float=site.position_progress
	key(KEY_D)
	var snapped:Dictionary=await preview_at(site.pos+Vector2(1,0))
	var snapped_rect:Rect2=snapped.get("rect",Rect2())
	check(snapped.get("ok",false) and snapped_rect.get_center().is_equal_approx(site.pos),"dig preview near existing work shows the executor's snapped site footprint")
	key(KEY_D);click(screen)
	check(u.order_version==version and sim.FieldPositions.jobs(sim)[u.id]==job and sim.units.size()==count+1,"repeated D at the same current site preserves its worker and assignment")
	key(KEY_D)
	var rejected:=usable_screen(Vector2(28,22),"distant rejected dig site")
	click(rejected)
	check(battle.tactical_mode=="dig" and not battle.dragging,"rejected dig remains a targeting gesture rather than a selection drag")
	check(u.order_version==version and sim.FieldPositions.jobs(sim)[u.id]==job and site.position_progress==progress and sim.credits==funds,"rejected distant digging preserves current work, progress and supply")
	check(not battle.notices.cursor_text.is_empty(),"rejected dig gives an actionable reason")
	key(KEY_ESCAPE)
	check(sim.FieldPositions.jobs(sim).has(u.id) and site.position_progress==progress,"Escape cancels only the uncommitted gesture and retains accepted digging")
	for i in 900:
		sim.tick(1.0/30.0)
		if int(site.position_stage)==1:break
	check(int(site.position_stage)==1 and float(site.build_left)<=0,"input-created position completes through physical work")
	if int(site.position_stage)!=1:return
	battle.selected=[engineer.id]
	await refresh()
	var engineer_before:Dictionary=engineer.assignment.duplicate(true)
	sim.credits=0.0
	key(KEY_U);click(screen)
	check(not site.get("upgrade_paid",false) and sim.credits==0 and engineer.assignment==engineer_before and not sim.FieldPositions.jobs(sim).has(engineer.id),"unaffordable U-click leaves the hasty position and engineer orders unchanged")
	check(battle.notices.cursor_text.to_lower().contains("supply"),"unaffordable upgrade explains the missing supply")
	sim.credits=funds
	key(KEY_U);click(screen)
	var cost:float=sim.definitions.fighting_trench.cost
	check(site.get("upgrade_paid",false) and sim.credits==funds-cost and sim.FieldPositions.jobs(sim).has(engineer.id),"U-click starts the engineer upgrade and spends its real price exactly once")
	if not site.get("upgrade_paid",false):return
	version=engineer.order_version
	job=sim.FieldPositions.jobs(sim)[engineer.id].duplicate(true)
	key(KEY_U);click(screen)
	check(sim.credits==funds-cost and engineer.order_version==version and sim.FieldPositions.jobs(sim)[engineer.id]==job,"repeated U-click preserves the current worker without charging again")
	advance(sim,2.0)
	progress=site.position_progress
	engineer.suppression=0.9
	sim.FieldPositions.tick(sim,1.0/30.0)
	var status:String=battle.hud.engineer_status(sim,engineer).to_lower()
	check(sim.FieldPositions.jobs(sim).has(engineer.id) and site.build_paused and (status.contains("paused") or status.contains("cover")) and not status.begins_with("ready"),"paused engineer feedback retains the live work assignment instead of advertising availability")
	engineer.suppression=0.0
	key(KEY_S)
	check(not sim.FieldPositions.jobs(sim).has(engineer.id) and site.build_paused and site.position_progress==progress and int(site.position_stage)==1,"S stops accepted reinforcement while retaining hasty protection and earned progress")
	check(site.upgrade_paid and sim.credits==funds-cost,"stopping the upgrade retains paid materials without a refund")
	sim.objectives.append({"name":"Jammer","pos":engineer.pos,"owner":1,"progress":0.0})
	sim.scenario.jam_radius=0.5
	battle.selected=[site.id]
	await refresh()
	var resume_buttons:Array=battle.hud.hits.filter(func(hit):return hit.id=="resume_build")
	check(resume_buttons.size()==1 and not resume_buttons[0].enabled and not battle.hud.resume_reason(sim,site).is_empty(),"Resume stays unavailable when the living last engineer has lost radio contact")
	if not resume_buttons.is_empty():click(resume_buttons[0].rect.get_center())
	check(site.build_paused and not sim.FieldPositions.jobs(sim).has(engineer.id) and sim.credits==funds-cost,"disabled Resume cannot reactivate work or charge disconnected engineers")
	sim.objectives.clear();sim.scenario.jam_radius=0.0
	battle.selected=[engineer.id]
	await refresh()
	key(KEY_U)
	var resumed:Dictionary=await preview_at(site.pos)
	check(resumed.get("ok",false) and float(resumed.get("cost",-1.0))==0.0,"paid interrupted upgrade previews no additional supply charge")
	key(KEY_U);click(screen)
	check(sim.credits==funds-cost and sim.FieldPositions.jobs(sim).has(engineer.id),"U-click resumes an interrupted paid upgrade without another purchase")
	for i in 600:
		sim.tick(1.0/30.0)
		if int(site.position_stage)==2:break
	check(int(site.position_stage)==2 and site.max_hp==320.0,"input-resumed engineer physically completes reinforcement")

func payload_replacement_and_overlays()->void:
	var f:=fixture()
	var sim=f.sim
	var u:Dictionary=f.infantry
	await refresh()
	var point:Vector2=u.pos+Vector2(0,-12)
	var screen:=usable_screen(point,"smoke target")
	check(sim.Throwables.preview(sim,u,"smoke",point).ok,"smoke fixture starts with a legal trajectory")
	var stock:int=sim.Throwables.total(u,"smoke")
	var assignment:Dictionary=u.assignment.duplicate(true)
	var frag_stock:int=sim.Throwables.total(u,"frag")
	var unsafe:=usable_screen(f.engineer.pos,"friendly-risk frag target")
	key(KEY_G);click(unsafe)
	check(battle.tactical_mode=="frag" and sim.throwables.preparations.is_empty() and u.assignment==assignment and sim.Throwables.total(u,"frag")==frag_stock,"unsafe frag click retains the gesture without spending stock or replacing orders")
	key(KEY_V)
	click(battle.hud.minimap.get_center())
	check(sim.throwables.preparations.is_empty() and u.assignment==assignment,"left-click minimap navigates without committing the pending smoke throw")
	# Restore camera after the deliberately separate minimap navigation.
	battle.camera_focus=Vector3(28,0,36);battle.update_camera()
	battle.hud.battlefield_ui.tutorial_active=true
	await refresh()
	var guide:Rect2=battle.hud.battlefield_ui.tutorial_rect(battle.hud)
	click(guide.position+Vector2(15,15))
	check(sim.throwables.preparations.is_empty() and u.assignment==assignment,"opaque Field Guide consumes clicks without throwing through it")
	key(KEY_F10);key(KEY_V);click(screen)
	check(battle.menu_open() and battle.tactical_mode.is_empty() and sim.throwables.preparations.is_empty(),"settings cancels pending targeting and blocks tactical key/click input")
	key(KEY_ESCAPE)
	key(KEY_V);click(screen)
	check(sim.throwables.preparations.size()==1,"world input starts one smoke preparation after closing settings")
	key(KEY_R)
	for i in 10:
		sim.tick(1.0/30.0)
		if sim.throwables.preparations.is_empty():break
	check(sim.throwables.preparations.is_empty() and sim.Throwables.total(u,"smoke")==stock,"accepted Retreat cancels unreleased smoke without spending stock")
	f=fixture();sim=f.sim;u=f.infantry
	await refresh()
	point=u.pos+Vector2(0,-12);screen=usable_screen(point,"move-replaced smoke target")
	stock=sim.Throwables.total(u,"smoke")
	key(KEY_V);click(screen)
	click(usable_screen(u.pos+Vector2(0,6),"replacement Move target"),MOUSE_BUTTON_RIGHT)
	for i in 10:
		sim.tick(1.0/30.0)
		if sim.throwables.preparations.is_empty():break
	check(sim.throwables.preparations.is_empty() and sim.Throwables.total(u,"smoke")==stock,"accepted world Move cancels unreleased smoke without spending stock")
	# Reset for an actual release; the earlier retreat owns its normal route.
	f=fixture();sim=f.sim;u=f.infantry
	await refresh()
	point=u.pos+Vector2(0,-12);screen=usable_screen(point,"released smoke target")
	stock=sim.Throwables.total(u,"smoke")
	key(KEY_V);click(screen)
	for i in 70:
		sim.tick(1.0/30.0)
		if not sim.throwables.projectiles.is_empty():break
	check(sim.throwables.projectiles.size()==1 and sim.Throwables.total(u,"smoke")==stock-1,"real preparation releases one charged smoke projectile")
	if sim.throwables.projectiles.is_empty():return
	var projectile_id:int=sim.throwables.projectiles[0].id
	key(KEY_S)
	check(sim.throwables.projectiles.size()==1 and int(sim.throwables.projectiles[0].id)==projectile_id and sim.Throwables.total(u,"smoke")==stock-1,"S cannot erase or refund an already released projectile")
	advance(sim,2.0)
	check(sim.throwables.smoke.size()==1 and sim.throwables.projectiles.is_empty(),"released payload completes its smoke effect after replacement input")

func run()->void:
	root.size=Vector2i(1280,800)
	battle=load("res://scenes/main.tscn").instantiate()
	battle.settings_path="user://m1-command-lifecycle-settings.cfg"
	root.add_child(battle);current_scene=battle
	battle.set_process(false);battle.set_physics_process(false)
	battle.close_region();battle.show_help=false;battle.paused=true
	await unavailable_hotkeys()
	await radio_delegation()
	await digging_and_upgrade()
	await payload_replacement_and_overlays()
	print("M1 COMMAND LIFECYCLE: %d checks, %d failures"%[checks,failures])
	battle.queue_free();await process_frame;await process_frame
	quit(1 if failures else 0)
