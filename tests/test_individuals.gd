extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Actors=preload("res://scripts/infantry.gd")
var failures:Array[String]=[]
var checks:=0
func check(value:bool,label:String) -> void:
	checks+=1
	if not value and not failures.has(label):failures.append(label);printerr("FAIL: ",label)
func _init() -> void:
	var sim=Sim.new(false,0)
	var squad=sim.spawn("rifle",0,Vector2(14,50))
	var enemy=sim.spawn("rifle",1,Vector2(14,40))
	check(squad.members.size()==3,"three independent soldier records")
	sim.tick(0.1)
	check(squad.members[0].aim>0,"individual target acquisition")
	for i in 7:sim.tick(0.1)
	var times:Array=[]
	for member in squad.members:times.append(member.last_shot)
	check(times[0]!=times.back(),"soldiers do not fire in lockstep")
	var before:float=squad.hp
	Actors.hit(squad,80,squad.members[0].pos,sim.time)
	check(squad.members[0].hp==0 and squad.hp<before,"localized hit removes one soldier")
	var capacity:float=Actors.capacity(squad)
	Actors.recover(squad,1000)
	check(squad.members[0].hp==0 and squad.hp==capacity,"repair does not resurrect casualties")
	enemy.hp=0
	sim.stop([squad.id])
	check(sim.issue([squad.id],Vector2(16,61))==1,"depleted group still accepts movement")
	for i in 200:
		sim.tick(0.1)
		for member in squad.members:
			if member.hp<=0:continue
			check(member.pos.distance_to(squad.pos)<=1.76,"soldier remains inside group clearance envelope")
			check(sim.terrain.traversable(member.pos,"land",0.42),"individual avoids solid terrain")
			for other in squad.members:
				if other.hp>0 and other.index>member.index:check(member.pos.distance_to(other.pos)>=1.54,"individual separation")
	check(squad.orders.is_empty(),"individual members arrive with their group")
	print("INDIVIDUAL TESTS: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
