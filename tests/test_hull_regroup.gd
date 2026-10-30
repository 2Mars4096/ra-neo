extends SceneTree
# A friendly tank parked on a soldier's formation slot must not stop that
# soldier's regroup: he takes a clear spot beside the hull and walks round it,
# and the section reunites within the regroup bound (test_regroup_recovery).
const Sim=preload("res://scripts/simulation.gd")
const Actors=preload("res://scripts/infantry.gd")
const REGROUP_BOUND:=12.0
const ANCHOR:=Vector2(10,38)
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		if failures<=12:printerr("FAIL: ",label)

func _init()->void:
	# Held hull (cannot be asked to move) and an idle parked hull.
	for held in [true,false]:run_case(held)
	run_reunion_slot()
	run_occupied_slot()
	print("HULL REGROUP: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)

func run_case(held:bool)->void:
	var label:="held" if held else "parked"
	var sim=Sim.new(false,3)
	var u=sim.spawn("rifle",0,ANCHOR)
	var actor:Dictionary=u.members[0]
	var slot:Vector2=u.pos+actor.offset
	# The reproduced mission geometry: hull centre 1.76 u from the slot.
	# Placed after spawning: spawn_position would nudge it off the section.
	var tank=sim.spawn("tank",0,ANCHOR+Vector2(0,-12))
	tank.pos=slot+Vector2(0,-1.76)
	if held:sim.stop([tank.id])
	var hull:float=float(sim.definitions[tank.kind].radius)
	var reach:float=hull+actor.body_radius
	actor.pos=tank.pos+Vector2(0,-5.0)
	check(slot.distance_to(tank.pos)<reach,"slot lies inside the hull margin: "+label)
	check(sim.terrain.traversable(actor.pos,"land",0.8) and sim.terrain.traversable(tank.pos,"land",hull),"fixture starts on clear ground: "+label)
	check(actor.pos.distance_to(u.pos)>7.5 and actor.pos.distance_to(u.pos)<Actors.Cover.LEASH,"straggler is separated inside the leash: "+label)
	check(Actors.segment_distance(actor.pos,slot,tank.pos)<reach,"hull blocks the straight return: "+label)
	check(sim.issue([u.id],ANCHOR+Vector2(0,8),"attack_move")==1,"order accepted: "+label)
	var tank_start:Vector2=tank.pos
	var started:=-1.0
	var ended:=-1.0
	var reunion_gap:=INF
	for frame in 600:
		var old:Vector2=actor.pos
		sim.tick(1.0/30.0);sim.events.clear()
		check(actor.pos.distance_to(old)<0.3,"straggler moves continuously: "+label)
		check(sim.terrain.segment_clear(old,actor.pos,"land",actor.body_radius),"straggler keeps terrain clearance: "+label)
		check(actor.pos.distance_to(tank.pos)>=reach-0.051,"straggler never enters the hull: "+label)
		for peer in u.members:
			if peer.index!=actor.index:check(actor.pos.distance_to(peer.pos)>=0.6,"soldiers keep separation: "+label)
		var active:bool=u.get("regroup_active",false)
		if active and started<0:started=sim.time
		if started>=0 and not active and ended<0:
			ended=sim.time
			reunion_gap=u.members.reduce(func(g,m):return maxf(g,m.pos.distance_to(u.pos)) if m.hp>0 else g,0.0)
			break
	if held:check(tank.pos.distance_to(tank_start)<0.01,"held hull stays put (soldier walks round it)")
	check(started>=0 and started<0.5,"regroup starts at once: "+label)
	check(ended>=0 and ended-started<=REGROUP_BOUND,"regroup past the parked hull is bounded: "+label)
	check(reunion_gap<2.8,"section together when the regroup ends: "+label)
	check(u.get("regroup_count",0)>=1,"regroup completed: "+label)
	print("HULL CASE ",label," regroup ",snappedf(started,0.01)," -> ",snappedf(ended,0.01)," gap=",snappedf(reunion_gap,0.01)," tank moved=",snappedf(tank.pos.distance_to(tank_start),0.01))

# Reproduced village corner: the first terrain-clear point around the tank
# lies beyond reunion distance; a later point on that same ring is usable.
# A cached slot from before regroup must be reconsidered by the same rule.
func run_reunion_slot()->void:
	var sim=Sim.new(false,3)
	var u:Dictionary=sim.spawn("rifle",0,Vector2(35,18))
	u.pos=Vector2(39.83962,15.36709)
	var actor:Dictionary=u.members[0]
	actor.pos=Vector2(41.7261,16.85319)
	u.members[1].hp=0
	u.members[2].pos=Vector2(35.97403,17.46456)
	var tank:Dictionary=sim.spawn("tank",0,Vector2(10,35))
	tank.pos=Vector2(39.59725,14.39142)
	sim.rebuild_spatial()
	var goal:Vector2=u.pos+actor.offset
	actor.regroup_blocked=0.6
	var outside:Vector2=Actors.clear_of_hulls(u,actor,sim,goal)
	check(outside.distance_to(u.pos)>2.8,"fixture's ordinary hull slot is outside reunion radius")
	check(actor.has("hull_slot"),"fixture retains the previous hull slot")
	u.regroup_active=true
	var inside:Vector2=Actors.clear_of_hulls(u,actor,sim,goal)
	check(inside.distance_to(u.pos)<2.8,"active regroup replaces an outlying cached hull slot")
	check(inside.distance_to(tank.pos)>=float(sim.definitions[tank.kind].radius)+actor.body_radius,"regroup slot retains physical hull clearance")
	check(sim.terrain.traversable(inside,"land",actor.body_radius) and Actors.return_slot_free(u,actor,inside),"regroup slot remains clear of terrain and teammates")
	check(not sim.terrain.path(actor.pos,inside,"land",actor.body_radius).is_empty(),"regroup slot has a physical route from the soldier")
	check(Actors.clear_of_hulls(u,actor,sim,goal)==inside,"valid regroup hull slot remains stable")

func run_occupied_slot()->void:
	var sim=Sim.new(false,3)
	var u:Dictionary=sim.spawn("rifle",0,Vector2(35,18))
	u.pos=Vector2(39.83962,15.36709)
	var medic:Dictionary=u.members[0]
	var casualty:Dictionary=u.members[1]
	var actor:Dictionary=u.members[2]
	medic.pos=Vector2(41.08576,15.7496)
	casualty.pos=Vector2(39.91472,15.90617)
	casualty.hp=0.0
	casualty.wound=Actors.SEVERE
	casualty.bleed_at=INF
	casualty.medic=medic.index
	medic.aiding=casualty.index
	actor.pos=Vector2(31.43554,15.94582)
	Actors.publish(u)
	sim.rebuild_spatial()
	check(not Actors.return_slot_free(u,actor,u.pos+actor.offset),"medic occupies the straggler's ordinary return slot")
	check(sim.issue([u.id],Vector2(39,22),"attack_move")==1,"occupied-slot fixture receives a single order")
	var group:int=u.command_group
	var intent:Dictionary=u.intent.duplicate(true)
	var started:=-1.0
	var ended:=-1.0
	for frame in int(REGROUP_BOUND*30.0):
		var old:Vector2=actor.pos
		sim.tick(1.0/30.0);sim.events.clear()
		check(actor.pos.distance_to(old)<0.3,"occupied-slot return moves continuously")
		check(sim.terrain.segment_clear(old,actor.pos,"land",actor.body_radius),"occupied-slot return keeps swept terrain clearance")
		check(actor.pos.distance_to(medic.pos)>=1.54,"occupied-slot return never enters the medic's body")
		if u.get("regroup_active",false) and started<0:started=sim.time
		if started>=0 and not u.get("regroup_active",false):ended=sim.time;break
	check(started>=0 and ended>=0 and ended-started<=REGROUP_BOUND,"occupied-slot regroup completes within the unchanged reunion bound")
	check(ended>=0 and casualty.aid<Actors.AID_SECONDS,"straggler rejoins before the medic vacates the occupied slot")
	check(u.members.all(func(m):return m.hp<=0 or m.pos.distance_to(u.pos)<2.8),"occupied-slot regroup ends with every live member within2.8")
	check(u.command_group==group and u.intent==intent,"alternate regroup slot preserves the original objective")
