extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Director=preload("res://scripts/tactical_director.gd")
const Actors=preload("res://scripts/infantry.gd")
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)
func _init()->void:
	var sim=Sim.new(false,3)
	var tank=sim.spawn("tank",0,Vector2(14,56))
	check(sim.issue([tank.id],Vector2(14,43),"attack_move")==1,"showcase accepts objective")
	var goal:Vector2=tank.orders[0].pos
	check(Director.plan(sim,tank,Vector2(19,53),"FLANK","test flank",4),"reachable flank committed")
	check(tank.orders[0].pos==goal,"maneuver preserves original intent")
	check(sim.issue([tank.id],Vector2(12,60))==1 and tank.maneuver.is_empty(),"new received command replaces maneuver")
	sim.stop([tank.id])
	Director.update(sim)
	check(tank.hold_command and tank.maneuver.is_empty(),"hold forbids autonomous departure")
	sim.issue([tank.id],Vector2(14,43))
	sim.tick(0.1)
	check(tank.speed_now>0 and tank.speed_now<sim.definitions.tank.speed,"vehicle accelerates rather than instantly reaching speed")
	var pressure=Sim.new(false,3)
	var unit=pressure.spawn("tank",0,Vector2(14,50))
	pressure.spawn("tank",1,Vector2(14,40))
	pressure.issue([unit.id],Vector2(14,30),"attack_move")
	unit.hp=unit.max_hp*0.2
	pressure.update_visibility()
	Director.update(pressure)
	check(unit.maneuver.get("phase","")=="WITHDRAW","observed danger triggers autonomous withdrawal")
	check(unit.orders[0].pos==Vector2(14,30),"withdrawal retains objective")
	pressure.time=unit.maneuver.deadline+1
	Director.update(pressure)
	check(unit.maneuver.is_empty(),"deadline prevents endless tactical wait")
	var cover=Sim.new(false,3)
	var squad=cover.spawn("rifle",0,Vector2(65,43))
	squad.suppression=0.5
	Actors.move(squad,cover,0.1)
	var reservations:=0
	for member in squad.members:
		if member.cover_goal!=Vector2.ZERO:reservations+=1
		for peer in squad.members:
			if peer.index>member.index and peer.cover_goal!=Vector2.ZERO and member.cover_goal!=Vector2.ZERO:
				check(peer.cover_goal.distance_to(member.cover_goal)>=1.6,"cover slots are independently reserved")
	check(reservations>0,"soldiers select actual cover positions")
	# Electronic disruption also blocks replacement of an autonomous maneuver.
	pressure.scenario=pressure.scenario.duplicate(true)
	pressure.scenario.jam_radius=100.0
	var before:Array=unit.orders.duplicate(true)
	check(pressure.issue([unit.id],Vector2(18,60))==0 and unit.orders==before,"jammed commands do not replace intent")
	pressure.objectives[0].owner=0
	check(pressure.issue([unit.id],Vector2(18,60))==1,"fresh command works after radio recovery")
	var mission=Sim.new(false,3)
	mission.objectives[0].owner=0
	mission.showcase_mission()
	check(mission.counterattack_at==12 and not mission.counterattack_sent,"capture schedules a warned counterattack")
	mission.time=12
	mission.showcase_mission()
	check(mission.counterattack_sent and mission.counterattack_ids.size()==3,"counterattack has a mixed force")
	mission.showcase_mission()
	check(mission.counterattack_ids.size()==3,"counterattack triggers once")
	print("SHOWCASE TESTS: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
