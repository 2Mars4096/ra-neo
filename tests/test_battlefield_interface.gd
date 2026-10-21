extends SceneTree
# Real scene layout and selection actions, fog-safe enemy information, objective
# semantics, and a read-only field guide advanced by ordinary simulation orders.
const Sim=preload("res://scripts/simulation.gd")
const Interface=preload("res://scripts/battlefield_interface.gd")
var failures:=0
var checks:=0
var battle
var hud
var sim

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func _init()->void:
	Sim.scenario_selection=6
	call_deferred("run")

func redraw()->void:
	hud.battlefield_ui.update(hud)
	hud.queue_redraw()
	await process_frame
	await process_frame

func hit(id:String)->Dictionary:
	for item in hud.hits:
		if item.id==id:return item
	return {}

func snapshot()->String:
	return var_to_str([sim.credits,sim.units.map(func(u):return [u.id,u.pos,u.hp,u.orders,u.command_group])])

func layout(label:String)->void:
	for dimensions in [Vector2i(1120,720),Vector2i(1280,720),Vector2i(1440,900),Vector2i(1920,1080)]:
		root.size=dimensions
		hud.size=Vector2(dimensions)
		await redraw()
		var hits:Array=hud.hits
		for i in hits.size():
			check(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(hits[i].rect),"%s %s fits %s" % [label,hits[i].id,dimensions])
			for j in range(i+1,hits.size()):check(not hits[i].rect.intersects(hits[j].rect),"%s %s/%s separate at %s" % [label,hits[i].id,hits[j].id,dimensions])
		check(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(hud.minimap),"minimap fits %s" % dimensions)

func run()->void:
	# Standalone HUDs are also used by map/minimap fixtures. Optional interface
	# hooks must decline actions and events until a live controller is bound.
	var detached=load("res://scripts/hud.gd").new()
	check(not detached.handle_action("minimap",Vector2.ZERO),"unbound HUD leaves core actions to the controller")
	check(not detached.handle_action("alert:focus",Vector2.ZERO),"unbound HUD declines interface actions")
	detached.observe_event({"type":"warning","text":"Incoming mortar fire","notice":"alert","pos":Vector2(350,600)})
	check(detached.battlefield_ui.last_alert.is_empty(),"unbound HUD ignores located events without inventing alert state")
	detached.free()
	root.size=Vector2i(1440,900)
	battle=load("res://scenes/main.tscn").instantiate()
	root.add_child(battle)
	current_scene=battle
	battle.set_process(false)
	battle.set_physics_process(false)
	hud=battle.hud
	sim=battle.sim
	await process_frame
	await process_frame
	check(sim.scenario.id=="black_sea_harbor","current Harbor fixture")
	await layout("briefing")
	check(not hit("tutorial:start").is_empty() and not hit("begin").is_empty(),"guided and free deployment are both available")
	battle.show_help=false
	battle.paused=true
	var ids:Array=battle.all_sections()
	battle.selected=ids.duplicate()
	await redraw()
	var ui=hud.battlefield_ui
	check(ui.roster_ids==ids,"group gets a roster")
	var before:=snapshot()
	var chosen:int=ids[0]
	check(hud.handle_action("roster:select:%d" % chosen,Vector2.ZERO),"roster handles select action")
	await redraw()
	check(battle.selected==[chosen],"click isolates the requested section")
	check(ui.roster_ids==ids and not hit("roster:all").is_empty(),"group remains available after isolating")
	hud.handle_action("roster:focus:%d" % chosen,Vector2.ZERO)
	check(Vector2(battle.camera_focus.x,battle.camera_focus.z).distance_to(battle.display_anchor(sim.get_unit(chosen)))<1.0,"focus locates the section")
	hud.handle_action("roster:all",Vector2.ZERO)
	check(battle.selected==ids,"back to group restores surviving selection")
	check(snapshot()==before,"roster actions never move, heal, spend or issue orders")
	hud.handle_action("roster:select:999999",Vector2.ZERO)
	check(battle.selected==ids,"stale roster id is harmless")
	await layout("group")
	hud.handle_action("tutorial:start",Vector2.ZERO)
	check(ui.tutorial_active,"field guide is opt-in")
	await layout("guided group")
	hud.handle_action("tutorial:hide",Vector2.ZERO)
	check(not ui.tutorial_active,"guide is dismissible")
	# Status priorities and ownership are read from authoritative values.
	var rifle:Dictionary=sim.living(0).filter(func(u):return u.kind=="rifle")[0]
	var status:Dictionary=rifle.duplicate(true)
	status.suppression=0.8
	check(Interface.critical_state(sim,status)=="PINNED","suppression is actionable in group view")
	status.suppression=0.0;status["mobility_kill"]=true
	check(Interface.critical_state(sim,status)=="IMMOBILISED","immobility outranks routine state")
	var ammo:Dictionary=sim.living(0).filter(func(u):return u.kind=="atgm")[0].duplicate(true)
	ammo["missiles"]=0
	check(Interface.critical_state(sim,ammo)=="RESUPPLY","empty AT team needs resupply")
	ammo.missiles=2
	check(Interface.critical_state(sim,ammo)=="AT 2/3","remaining missile count is shown")
	check(Interface.structure_color(hud,{"team":0},false)==hud.TEAL,"friendly work uses friendly colour")
	check(Interface.structure_color(hud,{"team":1},false)==hud.RED,"enemy work uses enemy colour")
	check(Interface.tactical_icons(220) and not Interface.tactical_icons(72),"role markers appear at wide zoom")
	# Hover always revalidates fog, even if the pointer/cache has not changed.
	root.size=Vector2i(1440,900);hud.size=Vector2(1440,900)
	battle.selected=[]
	var enemy:Dictionary=sim.living(1).filter(func(u):return u.kind=="tank")[0]
	ui.focus(battle,enemy.pos)
	await redraw()
	battle.pointer=battle.screen_pos(enemy.pos,battle.altitude(enemy)+0.8)
	enemy.visible=true
	ui.hover_checked=-10000
	check(ui.enemy_under_pointer(hud).get("id",-1)==enemy.id,"visible enemy has hover information")
	enemy.visible=false
	check(ui.enemy_under_pointer(hud).is_empty(),"loss of sight immediately hides cached enemy information")
	var lines:Array=ui.mission_lines(sim)
	check(lines[0].contains("90s") and lines[1].begins_with("Optional:"),"mission states hold duration and optional logistics")
	var old_hold:float=sim.score_hold
	sim.score_hold=12.0
	check(ui.mission_lines(sim)[0].contains("78s remaining"),"hold displays actual remaining time")
	sim.score_hold=old_hold
	# Alert locations must be explicitly supplied or verified friendly losses.
	ui.last_alert={}
	hud.observe_event({"type":"warning","text":"Unknown enemy origin","notice":"alert"})
	check(ui.last_alert.is_empty(),"an unlocated warning cannot reveal enemy coordinates")
	hud.observe_event({"type":"vehicle_damage","unit":enemy.id,"kind":"tank","team":1,"effect":"mobility","pos":enemy.pos,"visible":false})
	check(ui.last_alert.is_empty(),"unseen enemy damage cannot become an alert locator")
	var point:=Vector2(350,600)
	hud.observe_event({"type":"warning","text":"Incoming mortar fire","notice":"alert","pos":point})
	check(ui.last_alert.get("pos",Vector2.ZERO)==point,"declared incoming strike point is locatable")
	hud.handle_action("alert:focus",Vector2.ZERO)
	check(Vector2(battle.camera_focus.x,battle.camera_focus.z).distance_to(point)<0.1,"alert button focuses its declared location")
	await tutorial_commands()
	print("BATTLEFIELD INTERFACE: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)

func tutorial_commands()->void:
	var ui=hud.battlefield_ui
	ui.start_tutorial(battle)
	battle.selected=[]
	var before:=snapshot()
	for i in 20:ui.update_tutorial(battle)
	check(ui.tutorial_step==0 and snapshot()==before,"elapsed UI updates never award or manufacture progress")
	var drone:Dictionary=sim.living(0).filter(func(u):return u.kind=="drone")[0]
	battle.selected=[drone.id]
	ui.update_tutorial(battle)
	check(ui.tutorial_step==1,"selecting a real scout advances selection lesson")
	check(sim.issue([drone.id],drone.pos+Vector2(35,-35),"move")>0,"ordinary scout command accepted")
	for i in 240:
		sim.tick(1.0/30.0)
		ui.update_tutorial(battle)
		if ui.tutorial_step>=2:break
	check(ui.tutorial_step==2 and drone.pos.distance_to(ui.scout_origin)>=8.0,"scout must actually travel and reveal terrain")
	var rifle:Dictionary=sim.living(0).filter(func(u):return u.kind=="rifle")[0]
	var tank:Dictionary=sim.living(0).filter(func(u):return u.kind=="tank")[0]
	battle.selected=[rifle.id,tank.id]
	ui.update_tutorial(battle)
	check(ui.tutorial_step==2,"mixed selection alone does not complete attack lesson")
	var target:Vector2=rifle.pos+Vector2(8,-8)
	check(sim.issue(battle.selected,target,"attack_move")>0,"ordinary combined-arms attack-move accepted")
	ui.update_tutorial(battle)
	check(ui.tutorial_step==3,"accepted mixed attack-move completes command lesson")
	hud.handle_action("tutorial:hide",Vector2.ZERO)
	hud.handle_action("tutorial:start",Vector2.ZERO)
	check(ui.tutorial_active and ui.tutorial_step==3,"hiding and resuming preserves real opening progress")
	for i in 10:ui.update_tutorial(battle)
	check(ui.tutorial_step==3,"guide cannot award a sector that is not captured")
	check(not sim.objectives.any(func(obj):return obj.owner==0),"mission remains uncaptured in this opening fixture")
	ui.tutorial_active=false
