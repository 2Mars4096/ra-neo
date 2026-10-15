extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const FieldOps=preload("res://scripts/field_ops.gd")
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)
func fixture():
	var sim=Sim.new(false,5)
	sim.spawn("engineer",0,Vector2(14,97))
	sim.update_visibility()
	return sim
func site(sim,kind:String)->Vector2:
	for y in range(85,102,2):
		for x in range(7,30,2):
			var pos:=Vector2(x,y)
			if FieldOps.can_build(sim,kind,pos,sim.units[0].id):return pos
	return Vector2(-1,-1)
func _init()->void:
	var sim=fixture()
	check(sim.classic.is_empty() and not sim.field_ops.is_empty(),"independent mode")
	check(sim.credits==900,"starting supply")
	check(sim.units[0].members.size()==3,"three engineers")
	check(sim.objectives[0].pos==Vector2(56,54) and sim.objectives[1].pos==Vector2(108,78),"objective locations")
	for weapon in sim.definitions:
		for target in sim.definitions:check(sim.effectiveness[weapon].has(target),"complete combat matrix")
	FieldOps.tick(sim,2.5)
	check(sim.credits==905,"exact offmap income")
	check(sim.recruit("engineer") and sim.credits==785,"paid offmap purchase")
	var waiting:float=sim.credits
	check(sim.recruit("tank") and FieldOps.queued(sim,"tank")==1 and is_equal_approx(sim.credits,waiting-sim.definitions.tank.cost),"purchase during cooldown queues and pays")
	check(sim.recruit("rifle") and FieldOps.queue(sim)==["tank","rifle"],"mixed purchases queue in click order")
	check(FieldOps.cancel_queued(sim,"rifle") and is_equal_approx(sim.credits,waiting-sim.definitions.tank.cost),"cancel refunds the queued unit")
	check(not FieldOps.cancel_queued(sim,"rifle"),"cancel with nothing queued is refused")
	var tanks:int=sim.living(0).filter(func(u):return u.kind=="tank").size()
	for i in 120:sim.tick(1.0/30)
	check(FieldOps.queue(sim).is_empty() and sim.living(0).filter(func(u):return u.kind=="tank").size()==tanks+1,"queued tank deploys after the interval")
	check(not sim.recruit("aid_post"),"structures require engineer construction")
	var p:=site(sim,"tactical_cover")
	check(p.x>=0,"valid site exists")
	var funds:float=sim.credits
	check(FieldOps.build(sim,"tactical_cover",p,sim.units[0].id),"valid building")
	var building:Dictionary=sim.units.back()
	check(sim.credits==funds-60 and building.build_left==8,"atomic cost and timer")
	check(not sim.terrain.traversable(p,"land",0.8),"unfinished footprint reserved")
	check(not Sim.Infantry.actor_clear(sim.units[0],sim.units[0].members[0],p,sim),"soldier cannot enter construction footprint")
	check(not sim.movement_clear(sim.units[0],p,sim.units),"section cannot cross construction footprint")
	check(not sim.can_fire(building,sim.units[0]) and sim.issue([building.id],Vector2(20,97))==0,"structure stationary and unarmed")
	var paid:float=sim.credits
	check(not FieldOps.build(sim,"aid_post",p,sim.units[0].id) and sim.credits==paid,"overlap rejection atomic")
	for i in 600:sim.tick(1.0/30)
	check(building.build_left==0,"routed engineer completes construction")
	check(sim.terrain.field_cover.size()==1,"completed cover active")
	check(not FieldOps.cancel(sim,building.id),"cannot refund completed structure")
	building.hp=0
	FieldOps.tick(sim,0)
	check(sim.terrain.dynamic_blocks.is_empty() and sim.terrain.field_cover.is_empty(),"destruction releases geometry and cover")
	for kind in FieldOps.KINDS:
		var work=fixture()
		var position:=site(work,kind)
		check(position.x>=0 and FieldOps.build(work,kind,position,work.units[0].id),"build "+kind)
		if position.x<0:continue
		var structure:Dictionary=work.units.back()
		var builder:Dictionary=work.units[0]
		var left:float=structure.build_left
		FieldOps.tick(work,1)
		check(structure.build_left==left,"no remote progress "+kind)
		work.stop([builder.id])
		check(structure.build_paused,"Stop pauses construction")
		var before:float=work.credits
		check(FieldOps.cancel(work,structure.id),"cancel "+kind)
		check(is_equal_approx(work.credits,before+work.definitions[kind].cost),"unused full refund")
		check(not FieldOps.cancel(work,structure.id),"no double refund")
	var dead=fixture()
	check(FieldOps.build(dead,"observation_post",site(dead,"observation_post"),dead.units[0].id),"builder death fixture")
	var dead_site:Dictionary=dead.units.back()
	dead.units[0].hp=0
	FieldOps.tick(dead,100)
	check(dead_site.build_left==10,"dead builder cannot complete")
	var blocked=fixture()
	var legal:=site(blocked,"tactical_cover")
	var before:float=blocked.credits
	blocked.terrain.blocks.append(Rect2(legal-Vector2(3,3),Vector2(6,6)))
	check(not FieldOps.build(blocked,"tactical_cover",legal,blocked.units[0].id) and blocked.credits==before,"terrain rejection atomic")
	check(not FieldOps.can_build(blocked,"tactical_cover",Vector2(114,12),blocked.units[0].id),"cannot construct in unseen enemy area")
	var health=fixture()
	var medic:Dictionary=health.spawn("aid_post",0,Vector2(22,97))
	var engineers:Dictionary=health.units[0]
	engineers.members[0].hp=0;engineers.members[1].hp=10
	Sim.Infantry.publish(engineers)
	var damaged:float=engineers.hp
	health.time=10
	FieldOps.tick(health,1)
	check(engineers.hp>damaged and engineers.members[0].hp==0,"aid heals living engineers without resurrection")
	engineers.suppression=0.9;damaged=engineers.hp
	FieldOps.tick(health,1)
	check(engineers.hp==damaged,"suppression prevents aid")
	var repair:Dictionary=health.spawn("repair_point",0,Vector2(32,97))
	var tank:Dictionary=health.spawn("tank",0,Vector2(39,97))
	tank.hp=100
	FieldOps.tick(health,1)
	check(tank.hp==106,"repair heals vehicle")
	check(medic.hp==medic.max_hp and repair.hp==repair.max_hp,"support buildings remain intact")
	var mission=Sim.new(true,5)
	check(mission.living(1).size()==9 and mission.living(0).size()==5,"initial combined forces")
	check(mission.units.all(func(u):return u.kind not in ["hq","factory","refinery","harvester","power"]),"no classic economy actors")
	mission.objectives[0].owner=0
	FieldOps.tick(mission,0.1)
	mission.time=mission.counterattack_at+0.1
	FieldOps.tick(mission,0.1)
	check(mission.counterattack_sent and mission.counterattack_ids.size()==3,"mixed reserve response")
	for id in mission.counterattack_ids:
		check(mission.get_unit(id).orders.size()==1 and mission.get_unit(id).orders[0].pos.distance_to(mission.objectives[0].pos)<15,"reserve targets objective")
	for enemy in mission.living(1):enemy.hp=0
	for obj in mission.objectives:
		obj.owner=0;obj.progress=mission.capture_time
	mission.time+=21
	mission.update_objectives(61)
	check(mission.result=="VICTORY","objective hold mission ends")
	var loss=Sim.new(true,5)
	for unit in loss.living(0):unit.hp=0
	FieldOps.tick(loss,0.1)
	check(loss.result=="DEFEAT","force loss ends mission")
	print("FIELD OPS TESTS: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
