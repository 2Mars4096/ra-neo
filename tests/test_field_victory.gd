extends SceneTree
# Controlled mission states exercise victory rules without a full combat playthrough.
const Sim=preload("res://scripts/simulation.gd")
const FieldOps=preload("res://scripts/field_ops.gd")
var failures:=0
var checks:=0

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func mission(id:String):
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	var index:int=configs.find_custom(func(config):return config.id==id)
	check(index>=0,"scenario fixture exists: "+id)
	var sim=Sim.new(false,index)
	if not sim.field_ops.is_empty():
		check(not sim.spawn("rifle",0,sim.field_ops.insertion).is_empty(),"living player fixture: "+id)
		var logistics:Array=sim.scenario.get("enemy_works",[]).filter(func(work):return work.kind in ["command_post","ammo_depot"])
		FieldOps.spawn_prepared_works(sim,logistics,1)
		sim.field_ops.started=true
	for objective in sim.objectives:
		objective.owner=0
		objective.progress=sim.capture_time
	sim.time=400.0
	sim.counterattack_at=sim.time
	return sim

func destroy_logistics(sim,keep_id:int=-1)->void:
	for unit in sim.units:
		if unit.team==1 and unit.kind in ["command_post","ammo_depot"] and unit.id!=keep_id:
			unit.hp=0

func neutralized_before_reserve()->void:
	var sim=mission("black_sea_harbor")
	check(FieldOps.enemy_logistics_alive(sim),"Harbor starts with real enemy logistics")
	destroy_logistics(sim)
	FieldOps.tick(sim,0.0)
	check(not sim.counterattack_sent and sim.counterattack_ids.is_empty(),"destroyed logistics prevent the reserve")
	sim.score_hold=float(sim.scenario.hold)-1.0
	sim.update_objectives(0.5)
	check(sim.result=="","neutralized logistics still require the full hold")
	sim.update_objectives(0.5)
	check(sim.result=="VICTORY","full hold wins when logistics were destroyed before the reserve")
	check(not sim.counterattack_sent and sim.counterattack_ids.is_empty(),"victory does not invent a dispatched reserve")

	# Destruction alone cannot substitute for ownership or an uncontested hold.
	sim.result=""
	sim.objectives[0].owner=1
	sim.objectives[0].progress=0.0
	sim.update_objectives(0.5)
	check(sim.result=="" and sim.score_hold==0.0,"one uncaptured objective blocks victory and resets the hold")
	sim.objectives[0].owner=0
	sim.objectives[0].progress=sim.capture_time
	var enemy:Dictionary=sim.spawn("rifle",1,sim.objectives[0].pos+Vector2(4,0))
	check(not enemy.is_empty(),"enemy objective-contest fixture spawns")
	sim.score_hold=float(sim.scenario.hold)
	sim.update_objectives(0.5)
	check(sim.objectives[0].enemy_present,"enemy fixture is inside the capture radius")
	check(sim.result=="" and sim.score_hold==0.0,"enemy presence blocks victory and resets the hold")

func surviving_logistics_and_dispatched_reserve()->void:
	for kind in ["command_post","ammo_depot"]:
		var sim=mission("black_sea_harbor")
		var survivors:Array=sim.units.filter(func(unit):return unit.team==1 and unit.kind==kind)
		check(not survivors.is_empty(),"authored surviving "+kind)
		if survivors.is_empty():continue
		destroy_logistics(sim,int(survivors[0].id))
		sim.score_hold=float(sim.scenario.hold)
		sim.update_objectives(0.0)
		check(sim.result=="","one surviving "+kind+" keeps the reserve requirement")
		FieldOps.tick(sim,0.0)
		check(sim.counterattack_sent and not sim.counterattack_ids.is_empty(),"one surviving "+kind+" can dispatch the reserve")
		destroy_logistics(sim)
		for elapsed in [19.9,20.0]:
			sim.time=sim.counterattack_at+elapsed
			sim.update_objectives(0.0)
			check(sim.result=="","destroying logistics after dispatch preserves grace at %.1f s (%s)" % [elapsed,kind])
		sim.time=sim.counterattack_at+20.1
		sim.update_objectives(0.0)
		check(sim.result=="VICTORY","normal victory after dispatched-reserve grace ("+kind+")")

func defeat_is_final()->void:
	var sim=mission("black_sea_harbor")
	destroy_logistics(sim)
	for unit in sim.units:
		if unit.team==0:unit.hp=0
	FieldOps.spawn_prepared_works(sim,[{"kind":"aid_post","position":sim.field_ops.insertion}],0)
	check(sim.living(0).any(func(unit):return unit.get("structure",false)),"a friendly support structure survives the mobile force")
	sim.score_hold=float(sim.scenario.hold)
	FieldOps.tick(sim,0.0)
	check(sim.result=="DEFEAT","losing every player mobile unit records defeat")
	# Exercise the complete tick: the surviving structure keeps living(0) nonempty.
	sim.result=""
	sim.tick(1.0/30)
	check(sim.result=="DEFEAT","completed objectives cannot overwrite defeat in the same tick")

func legacy_missions()->void:
	for id in ["riverside_town","showcase"]:
		var sim=mission(id)
		sim.score_hold=float(sim.scenario.hold)
		sim.update_objectives(0.0)
		check(sim.result=="",id+" still requires its reserve without authored logistics")
		if not sim.field_ops.is_empty():
			FieldOps.tick(sim,0.0)
		else:
			sim.showcase_mission()
		check(sim.counterattack_sent and not sim.counterattack_ids.is_empty(),id+" still dispatches its normal reserve")
		sim.time=sim.counterattack_at+20.1
		sim.update_objectives(0.0)
		check(sim.result=="VICTORY",id+" still wins after its reserve grace")
	var ordinary=mission("coast")
	ordinary.score_hold=float(ordinary.scenario.hold)
	ordinary.update_objectives(0.0)
	check(ordinary.result=="VICTORY" and not ordinary.counterattack_sent,"nonautonomous mission does not require a reserve")

func _init()->void:
	neutralized_before_reserve()
	surviving_logistics_and_dispatched_reserve()
	defeat_is_final()
	legacy_missions()
	print("FIELD VICTORY: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)
