extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Classic=preload("res://scripts/classic.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)
func _init()->void:
	var sim=Sim.new(false,4)
	sim.classic.ai_clock=100000;sim.classic.attack_clock=100000
	var hq=sim.spawn("hq",0,Vector2(10,sim.terrain.world_size.y-11))
	Classic.sync_obstacles(sim)
	var rifle=sim.spawn("rifle",1,Vector2(62,9))
	var hidden=sim.spawn("tank",0,Vector2(18,60))
	sim.update_visibility()
	check(not sim.contact_known(rifle,hq) and not sim.contact_known(rifle,hidden),"attacker starts without hidden live contacts")
	var approach:Vector2=Classic.known_base_approach(sim,rifle,0)
	check(approach.x>=0 and approach.distance_to(hq.pos)<=float(sim.definitions.rifle.sight)*0.8,"disclosed base approach is within adverse-weather rifle sight")
	var original:Vector2=hidden.pos
	hidden.pos=Vector2(70,60)
	check(Classic.known_base_approach(sim,rifle,0)==approach,"hidden mobile contact cannot change disclosed-base approach")
	hidden.pos=original
	sim.classic.attack_clock=0.0
	Classic.tick(sim,0.1)
	check(not rifle.orders.is_empty() and rifle.orders[0].mode=="attack_move" and rifle.orders[0].pos==approach,"AI fallback issues the disclosed-base approach")
	var acquired:=false
	for frame in 1400:
		sim.tick(0.1);sim.events.clear()
		acquired=acquired or sim.contact_known(rifle,hq)
		if acquired:break
	check(acquired,"one attack-move actually observes the starting HQ")
	print("KNOWN BASE APPROACH: ",approach," acquired=",acquired," seconds=",sim.time)
	# Reproduce the classic HQ firing-position pocket. Candidate selection must
	# test connectivity, not only footprint clearance and geometric proximity.
	var pocket=Sim.new(false,4)
	var target=pocket.spawn("hq",1,Vector2(62,9))
	pocket.spawn("power",1,Vector2(46,6))
	pocket.spawn("barracks",1,Vector2(46,16))
	Classic.sync_obstacles(pocket)
	var tank=pocket.spawn("tank",0,Vector2(21.05103,30.94121))
	target.seen_by[0]=true
	var chosen:Vector2=pocket.attack_position(tank,target)
	check(chosen.x>=0 and not pocket.terrain.path(tank.pos,chosen,"land",pocket.definitions.tank.radius,[],"tracked").is_empty(),"explicit attack chooses a reachable firing position")
	check(pocket.issue([tank.id],target.pos,"attack",false,target.id)==1,"reachable visible HQ attack accepted")
	if not tank.orders.is_empty():check(tank.orders[0].target==target.id and tank.orders[0].mode=="attack","direct attack retains exact target identity")
	print("HQ APPROACH: ",chosen)
	print("CLASSIC NAVIGATION: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
