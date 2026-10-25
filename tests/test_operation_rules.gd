extends SceneTree
# Controlled mission states test the decisions introduced by regional rules;
# they are not a claim of full AI or human balance acceptance.
const Sim=preload("res://scripts/simulation.gd")
const Catalog=preload("res://scripts/scenario_catalog.gd")
const FieldOps=preload("res://scripts/field_ops.gd")
const Rules=preload("res://scripts/operation_rules.gd")
var checks:=0
var failures:=0

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func mission(id:String):
	var index:=Catalog.index_for_id(id)
	check(index>=0,"operation exists: "+id)
	return Sim.new(false,index)

func secure(sim,index:int)->void:
	sim.objectives[index].owner=0
	sim.objectives[index].progress=sim.capture_time
	sim.objectives[index]["enemy_present"]=false

func rail_logistics()->void:
	var sim=mission("bayhead_rail_valley")
	check(Rules.income_bonus(sim)==0.0,"uncaptured rail facilities produce no supply")
	check(Rules.forward_point(sim)==Vector2(-1,-1),"uncaptured yard cannot insert troops")
	secure(sim,0)
	check(Rules.income_bonus(sim)==2.0,"station has its own supply value")
	secure(sim,1)
	check(Rules.income_bonus(sim)==6.0,"station and yard effects add once")
	var funds:float=sim.credits
	FieldOps.tick(sim,2.0)
	check(is_equal_approx(sim.credits-funds,24.0),"base and captured supply are integrated once per second")
	check(Rules.forward_point(sim)==Vector2(275,206),"captured yard opens authored reinforcement access")
	check(FieldOps.deploy(sim,"rifle"),"connected captured yard accepts a real reinforcement")
	check(sim.field_ops.last_entry_forward,"yard reinforcement reports forward entry")
	check(sim.units.back().pos.distance_to(Vector2(275,206))<12.1,"reinforcement stays near the legal yard entry")
	sim.objectives[1].enemy_present=true
	check(Rules.income_bonus(sim)==2.0,"contesting yard immediately stops its supply")
	check(Rules.forward_point(sim)==Vector2(-1,-1),"contesting yard closes reinforcement access")
	sim.objectives[1].enemy_present=false
	sim.objectives[1].owner=1
	check(Rules.income_bonus(sim)==2.0,"lost yard cannot retain its captured benefit")
	secure(sim,1)
	# A malformed/disconnected runtime entry is still unable to bypass the
	# physical route check. The checked-in blueprint rejects such geometry.
	sim.scenario.operation.facilities[1].forward_position=[228,40]
	check(FieldOps.deploy(sim,"tank"),"blocked forward entry safely falls back to the original insertion")
	check(not sim.field_ops.last_entry_forward,"blocked yard does not pretend to be a forward insertion")
	check(sim.units.back().pos.distance_to(sim.field_ops.insertion)<12.1,"fallback tank arrives at its legal original insertion")

func route_denial()->void:
	var sim=mission("bayhead_rail_valley")
	sim.spawn("rifle",0,sim.field_ops.insertion)
	sim.field_ops.started=true
	secure(sim,2)
	sim.counterattack_at=sim.time
	FieldOps.tick(sim,0.0)
	check(not FieldOps.enemy_logistics_alive(sim),"junction control cuts authored enemy dispatch route")
	check(not sim.counterattack_sent and sim.counterattack_ids.is_empty(),"cut route prevents an unsent reserve")
	sim.objectives[2].owner=1
	sim.objectives[2].progress=0.0
	FieldOps.tick(sim,0.0)
	check(FieldOps.enemy_logistics_alive(sim),"losing the junction restores dispatch access")
	check(sim.counterattack_sent and sim.counterattack_ids.size()==3,"restored route dispatches one authored reserve")
	var ids:Array=sim.counterattack_ids.duplicate()
	secure(sim,2)
	FieldOps.tick(sim,0.0)
	check(sim.counterattack_ids==ids,"cutting a route does not erase already dispatched forces")
	check(ids.all(func(id):return sim.alive(sim.get_unit(id))),"dispatched reserve remains physically alive")
	var pass_sim=mission("limestone_pass")
	check(Rules.reserve_delay(pass_sim)==24.0,"pass response has authored timing")
	pass_sim.field_ops.reserve_delay_bonus=45.0
	check(Rules.reserve_delay(pass_sim)==69.0,"regional route disruption adds to actual reserve delay")
	secure(pass_sim,1)
	check(Rules.enemy_routes_open(pass_sim),"crossroads alone does not close both pass access points")
	secure(pass_sim,2)
	check(not Rules.enemy_routes_open(pass_sim),"crossroads and upper hamlet close pass access")
	pass_sim.objectives[2].enemy_present=true
	check(Rules.enemy_routes_open(pass_sim),"contested pass access cannot claim route denial")
	check(FieldOps.site_ground_clear(pass_sim,"observation_post",Vector2(244,116),false),"flat lookout plateau supports engineer observation works")
	check(not FieldOps.site_ground_clear(pass_sim,"observation_post",Vector2(246,134),false),"steep ramp cannot support a floating rigid field work")

func coastal_control()->void:
	var sim=mission("south_inlet")
	for index in sim.objectives.size():secure(sim,index)
	sim.counterattack_sent=true;sim.counterattack_at=0.0;sim.time=21.0
	sim.score_hold=float(sim.scenario.hold)
	sim.update_objectives(0.0)
	check(not Rules.hold_ready(sim) and sim.result=="" and sim.score_hold==0.0,"shore capture alone cannot win or start the inlet hold")
	check(Rules.income_bonus(sim)==0.0,"coastal supply waits for both land and sea control")
	var boat:Dictionary=sim.spawn("boat",0,Vector2(285,160))
	check(not boat.is_empty() and boat.pos.distance_to(Vector2(285,160))<18.0,"real ship fits inside naval control zone")
	check(Rules.hold_ready(sim) and Rules.income_bonus(sim)==4.0,"ship and shore control open coastal logistics and final hold")
	boat.suppression=0.8
	check(not Rules.hold_ready(sim),"suppressed ship cannot establish naval control")
	boat.suppression=0.0
	boat.orders=[{"mode":"retreat"}]
	check(not Rules.hold_ready(sim),"withdrawing ship cannot retain naval control")
	boat.orders=[]
	var enemy:Dictionary=sim.spawn("boat",1,Vector2(273,160))
	check(not enemy.is_empty() and enemy.pos.distance_to(Vector2(285,160))<=18.0,"enemy naval contest has a legal physical body")
	enemy.seen_by[0]=false
	check(not Rules.hold_ready(sim) and Rules.income_bonus(sim)==0.0,"contested sea lane closes the operation and resupply")
	check(Rules.status(sim)=="Sea lane unsecured","status does not disclose an unseen contesting ship")
	enemy.hp=0.0
	sim.objectives[0].owner=1;sim.objectives[0].progress=0.0
	check(not Rules.hold_ready(sim),"ship alone cannot substitute for shore prerequisites")
	secure(sim,0)
	sim.score_hold=float(sim.scenario.hold)-0.5
	sim.update_objectives(0.25)
	check(sim.result=="","land and naval control still need the complete hold duration")
	sim.update_objectives(0.25)
	check(sim.result=="VICTORY","joint shore and naval control can finish the operation")
	check(FieldOps.reserve_target(sim,"sea")==Vector2(285,160),"naval reserve attacks the sea lane, not a land point")

func legacy_unchanged()->void:
	var sim=mission("black_sea_harbor")
	check(Rules.config(sim).is_empty(),"legacy harbor does not opt into new scenario rules")
	check(Rules.income_bonus(sim)==0.0 and Rules.hold_ready(sim),"legacy economy and hold requirements stay intact")
	check(Rules.forward_point(sim)==Vector2(-1,-1) and Rules.reserve_delay(sim)==12.0,"legacy reinforcement entry and reserve timing stay intact")
	check(Rules.status(sim)=="" and Rules.brief(sim.scenario)=="","legacy UI receives no empty rule labels")

func _init()->void:
	call_deferred("run")

func run()->void:
	rail_logistics()
	route_denial()
	coastal_control()
	legacy_unchanged()
	print("OPERATION RULES: %d checks, %d failures"%[checks,failures])
	quit(1 if failures>0 else 0)
