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
