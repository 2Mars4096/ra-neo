extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Cover=preload("res://scripts/cover_behavior.gd")
var failures:=0
func check(ok:bool,label:String)->void:
	if not ok:failures+=1;printerr("FAIL: ",label)
func _init()->void:
	var sim=Sim.new(false,3)
	var squad=sim.spawn("rifle",0,Vector2(17,33))
	var enemy=sim.spawn("rifle",1,Vector2(17,21))
	for actor in enemy.members:actor.cooldown=1000
	sim.update_visibility()
	var initial:Array=squad.members.map(func(m):return m.pos)
	var maximum_travel:=0.0
	var arrived:=false
	var running:=false
	for frame in 120:
		sim.tick(0.1)
		var seeking:=0
		for actor in squad.members:
			if actor.get("cover_phase","")=="SEEKING":
				seeking+=1;running=true
				check(actor.last_shot<sim.time-0.09,"moving soldier does not fire")
			if actor.get("cover_phase","")=="SHELTERED":arrived=true
			maximum_travel=maxf(maximum_travel,actor.pos.distance_to(initial[actor.index]))
			check(sim.terrain.traversable(actor.pos,"land",actor.body_radius),"actor stays outside scenery")
			for peer in squad.members:
				if peer.index>actor.index:check(actor.pos.distance_to(peer.pos)>=1.54,"independent actors remain separated")
		check(seeking<=2,"only part of section moves while partners hold")
		sim.events.clear()
	check(running and maximum_travel>3.6,"visible run to shelter beyond old search radius")
	check(arrived,"soldier reaches shelter and settles")
	sim.stop([squad.id]);sim.tick(0.1)
	check(not Cover.seeking(squad),"explicit hold cancels cover movement")
	check(sim.issue([squad.id],Vector2(12,41),"move")==1,"new move accepted")
	check(squad.members.all(func(m):return m.cover_goal==Vector2.ZERO),"new order clears stale cover goals")
	var unobserved=Sim.new(false,3)
	var scout=unobserved.spawn("rifle",0,Vector2(17,33))
	unobserved.spawn("rifle",1,Vector2(69,8))
	unobserved.tick(0.1)
	# Halted sections may take local cover on their own; an unseen enemy must not
	# trigger threat-driven shelter (only the halt-in-cover kind is allowed).
	check(scout.members.all(func(m):return m.get("cover_phase","") not in ["SEEKING","SETTLING"] or m.get("occupying",false)),"unseen distant enemy does not trigger shelter")
	# Holding a valid shelter must not periodically trigger another run.
	var stable=Sim.new(false,3)
	var section=stable.spawn("rifle",0,Vector2(17,33))
	var contact=stable.spawn("rifle",1,Vector2(17,21))
	for actor in contact.members:actor.cooldown=1000
	for frame in 120:stable.tick(0.1);stable.events.clear()
	var shelters:Array=section.members.filter(func(m):return m.hp>0 and m.get("cover_phase","")=="SHELTERED")
	check(not shelters.is_empty(),"retention fixture reaches a real shelter")
	if not shelters.is_empty():
		var settled:Dictionary=shelters[0]
		check(stable.terrain.cover(settled.pos),"retention fixture is physically in cover")
		var goal:Vector2=settled.cover_goal
		settled.cover_deadline=-1.0
		Cover.update(section,stable)
		check(settled.cover_phase=="SHELTERED" and settled.cover_goal==goal,"valid shelter does not expire into repeated running")
	print("COVER BEHAVIOR: ",failures," failures; maximum individual movement=",maximum_travel," settled=",arrived)
	quit(0 if failures==0 else 1)
