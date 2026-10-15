extends SceneTree
# Hidden states made visible: garrison ENTERING / GARRISONED / EXITING and
# BOMBARDING reach UnitAnimation.state (the selected-unit status), vehicle
# component damage yields compact HUD tags (never infantry wounds), and ordering
# an immobilised vehicle to move gives a toast while the rest of the selection moves.
const Sim=preload("res://scripts/simulation.gd")
const Garrison=preload("res://scripts/garrison.gd")
const StructureDamage=preload("res://scripts/structure_damage.gd")
const VehicleDamage=preload("res://scripts/vehicle_damage.gd")
const Motion=preload("res://scripts/unit_animation.gd")
const HUD=preload("res://scripts/hud.gd")
const DT:=1.0/30.0
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func harbor_index()->int:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		if configs[i].id=="black_sea_harbor":return i
	return -1

func _init()->void:
	garrison_states()
	damage_tags()
	Sim.scenario_selection=harbor_index()
	call_deferred("battle_checks")

# A building with a reachable doorway and a rifle section beside it.
func fixture(sim)->Array:
	for b in Garrison.index(sim).buildings:
		var door:=Garrison.entry_point(sim,b.id,b.bounds.get_center()+Vector2(0,30))
		if door.x<0:continue
		var start:=door+Vector2(0,6)
		if not sim.terrain.traversable(start,"land",2.65):continue
		var squad:Dictionary=sim.spawn("rifle",0,start)
		if not squad.is_empty() and squad.pos.distance_to(start)<1.0:return [b,squad]
		if not squad.is_empty():squad.hp=0
	return []

func garrison_states()->void:
	var sim=Sim.new(false,harbor_index())
	var found:=fixture(sim)
	check(not found.is_empty(),"fixture building with a doorway")
	if found.is_empty():return
	var building:Dictionary=found[0]
	var squad:Dictionary=found[1]
	check(Garrison.order(sim,[squad.id],building.id)==1,"garrison order accepted")
	var seen:={}
	for i in 600:
		sim.tick(DT)
		seen[Motion.state(squad,sim)]=true
		if Garrison.inside(squad):break
	check(seen.has("ENTERING"),"walking through the door reads ENTERING: %s" % [seen.keys()])
	check(Motion.state(squad,sim)=="GARRISONED","inside reads GARRISONED (was %s)" % Motion.state(squad,sim))
	# Firing from the windows keeps the building state on the panel.
	squad.last_shot=sim.time
	squad.cooldown=1.0
	check(Motion.state(squad,sim)=="GARRISONED","firing from windows still reads GARRISONED")
	squad.suppression=0.9
	check(Motion.state(squad,sim)=="PINNED","a pinned garrison reads PINNED")
	squad.suppression=0.0
	var away:Vector2=(squad.pos-building.bounds.get_center()).normalized()
	sim.issue([squad.id],squad.pos+away*8.0,"move")
	seen.clear()
	for i in 90:
		sim.tick(DT)
		seen[Motion.state(squad,sim)]=true
		if Garrison.transit(squad)=="" and not Garrison.inside(squad):break
	check(seen.has("EXITING"),"leaving reads EXITING: %s" % [seen.keys()])
	# A tank given a fire mission on the building reads BOMBARDING once in place.
	var aim:Vector2=building.bounds.get_center()
	var tank:Dictionary=sim.spawn("tank",0,aim+(squad.pos-aim).normalized()*(building.bounds.size.length()*0.5+12.0))
	var shelling:int=StructureDamage.bombard(sim,[tank.id],building.id)
	check(shelling==1,"tank accepts the fire mission")
	var bombarding:=false
	for i in 900:
		sim.tick(DT)
		if Motion.state(tank,sim)=="BOMBARDING":bombarding=true;break
	check(bombarding,"tank shelling the building reads BOMBARDING (orders %d, bombard %s)" % [tank.orders.size(),tank.has("bombard")])
	tank.erase("bombard")
	check(Motion.state(tank,sim)!="BOMBARDING","no BOMBARDING after the mission ends")
	print("GARRISON STATES ok, tank shelled in %.1fs" % sim.time)

func damage_tags()->void:
	var sim=Sim.new(false,harbor_index())
	var base:=Vector2(300,640)
	var tank:Dictionary=sim.spawn("tank",0,base)
	check(HUD.damage_tags(sim,tank).is_empty(),"undamaged tank has no tags")
	VehicleDamage.ensure_state(sim,tank)
	check(HUD.damage_tags(sim,tank).is_empty(),"hit-but-intact tank has no tags")
	tank.mobility_kill=true
	tank.firepower_kill=true
	tank.crew=1
	var tags:=HUD.damage_tags(sim,tank)
	check(Array(tags)==["IMMOBILISED","GUN OUT","CREW 1/%d" % int(tank.crew_full)],"tank tags: %s" % [tags])
	var helo:Dictionary=sim.spawn("helo",0,base+Vector2(20,0))
	VehicleDamage.ensure_state(sim,helo)
	helo.mobility_kill=true
	check(Array(HUD.damage_tags(sim,helo))==["DAMAGED"],"damaged gunship reads DAMAGED: %s" % [HUD.damage_tags(sim,helo)])
	var boat:Dictionary={"kind":"boat","crew":4,"crew_full":4,"mobility_kill":false,"firepower_kill":false,"abandoned":false,"fire_until":sim.time+5.0,"flood_rate":0.03,"flood":0.1}
	check(Array(HUD.damage_tags(sim,boat))==["ON FIRE","FLOODING"],"corvette tags: %s" % [HUD.damage_tags(sim,boat)])
	boat.fire_until=sim.time-1.0
	boat.flood_rate=0.0
	check(HUD.damage_tags(sim,boat).is_empty(),"fire out and pumps winning clear the tags")
	boat.abandoned=true
	check(Array(HUD.damage_tags(sim,boat))==["ABANDONED"],"abandoned tag")
	# Wounded soldiers are never labelled.
	var section:Dictionary=sim.spawn("rifle",0,base+Vector2(0,20))
	section.members[0].wound="SEVERE"
	section.hp*=0.5
	check(HUD.damage_tags(sim,section).is_empty(),"no wounded/casualty tag for infantry")

func battle_checks()->void:
	root.size=Vector2i(1440,900)
	var battle=load("res://scenes/main.tscn").instantiate()
	root.add_child(battle)
	current_scene=battle
	battle.show_help=false
	battle.paused=true
	await process_frame
	await process_frame
	var sim=battle.sim
	var section:Dictionary=sim.get_unit(1)
	check(section.kind=="rifle" or not section.members.is_empty(),"unit 1 is an infantry section (%s)" % section.kind)
	var tank:Dictionary=sim.spawn("tank",0,section.pos+Vector2(8,0))
	VehicleDamage.ensure_state(sim,tank)
	tank.mobility_kill=true
	battle.sync_units(0.016)
	battle.selected=[tank.id]
	battle.give_order(battle.screen_pos(section.pos+Vector2(0,12)),false,false)
	check(battle.toast=="Tank immobilised · cannot move","immobilised toast: %s" % battle.toast)
	check(tank.orders.is_empty(),"immobilised tank gets no move order")
	battle.selected=[tank.id,section.id]
	battle.give_order(battle.screen_pos(section.pos+Vector2(0,12)),false,false)
	check(str(battle.toast).begins_with("Tank immobilised · cannot move") and str(battle.toast).contains("1 / 2 moving"),"mixed selection toast: %s" % battle.toast)
	check(not section.orders.is_empty() and tank.orders.is_empty(),"the rest of the selection moves")
	tank.mobility_kill=false
	battle.selected=[tank.id]
	battle.give_order(battle.screen_pos(section.pos+Vector2(0,14)),false,false)
	check(not tank.orders.is_empty() and not str(battle.toast).contains("immobilised"),"a mobile tank moves normally: %s" % battle.toast)
	# Draw passes with a damaged selected tank, a damaged enemy and an abandoned
	# hull complete (each layer reaches its final buttons).
	tank.orders.clear();tank.path.clear()
	tank.mobility_kill=true
	tank.crew=1
	var enemy:Dictionary=sim.spawn("tank",1,section.pos+Vector2(-8,4))
	VehicleDamage.ensure_state(sim,enemy)
	enemy.firepower_kill=true
	var hull:Dictionary=sim.spawn("tank",0,section.pos+Vector2(0,-10))
	VehicleDamage.ensure_state(sim,hull)
	hull.crew=0;hull.abandoned=true;hull["abandoned_hp"]=200.0
	hull.hp-=VehicleDamage._finish(sim,hull,hull.hp+1.0)
	check(VehicleDamage.recrewable(sim,hull),"abandoned hull fixture")
	sim.update_visibility()
	battle.sync_units(0.016)
	battle.hud.layer_hits=[[],[],[]]
	battle.hud.queue_redraw()
	await process_frame
	await process_frame
	var world_ids:Array=battle.hud.layer_hits[0].map(func(h):return h.id)
	var sidebar_ids:Array=battle.hud.layer_hits[1].map(func(h):return h.id)
	check("pause" in world_ids,"world layer drew through unit and hull tags: %s" % [world_ids])
	check("attack" in sidebar_ids,"sidebar drew the damaged unit panel: %s" % [sidebar_ids])
	check(Array(HUD.damage_tags(sim,tank))==["IMMOBILISED","CREW 1/%d" % int(tank.crew_full)],"selected tank panel tags")
	print("HUD STATES: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
