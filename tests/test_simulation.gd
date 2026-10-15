extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
var failures: Array[String]=[]
var checks:=0

func check(value: bool, message: String) -> void:
	checks+=1
	if not value:
		failures.append(message)
		printerr("FAIL: ",message)

func advance(sim, seconds: float) -> void:
	for i in ceili(seconds*10):
		sim.tick(0.1)
		sim.events.clear()

func _init() -> void:
	var sim=Sim.new(false,0)
	check(sim.terrain.path(Vector2(20,34),Vector2(48,34),"land").size()>0,"land can route around ridge")
	var route=sim.terrain.path(Vector2(20,34),Vector2(48,34),"land")
	var prev:=Vector2(20,34)
	for p in route:
		check(not sim.terrain.blocked(p),"path node stays outside obstacles")
		check(sim.terrain.line_clear(prev,p),"path segment does not cut ridge")
		prev=p
	check(sim.terrain.path(Vector2(12,50),Vector2(89,50),"land").is_empty(),"land rejects sea destination")
	check(sim.terrain.path(Vector2(89,50),Vector2(12,50),"sea").is_empty(),"sea rejects land destination")
	check(not sim.terrain.path(Vector2(12,50),Vector2(89,50),"air").is_empty(),"air crosses coastline")
	check(not sim.terrain.line_clear(Vector2(30,34),Vector2(42,34)),"ridge blocks sight")
	var rifle=sim.spawn("rifle",0,Vector2(12,50))
	check(sim.issue([rifle.id],Vector2(20,50))==1,"move order accepted")
	check(sim.issue([rifle.id],Vector2(24,50),"move",true)==1,"queued order accepted")
	advance(sim,6)
	check(rifle.pos.distance_to(Vector2(24,50))<0.1,"queued destinations complete")
	check(rifle.orders.is_empty(),"completed queue drains")
	sim.issue([rifle.id],Vector2(40,50))
	sim.stop([rifle.id])
	var held: Vector2=rifle.pos
	advance(sim,1)
	check(rifle.pos==held,"stop cancels movement")
	check(sim.issue([rifle.id],Vector2(35,35))==0,"unreachable order rejected")
	var funds: float=sim.credits
	check(sim.recruit("drone"),"funded reinforcement succeeds")
	check(sim.credits==funds-80,"reinforcement spends exact cost")
	check(not sim.recruit("tank"),"deployment cooldown enforced")
	sim=Sim.new(false,0)
	var friend=sim.spawn("tank",0,Vector2(30,35))
	var enemy=sim.spawn("tank",1,Vector2(42,35))
	sim.update_visibility()
	check(not enemy.seen_by[0],"enemy hidden behind ridge")
	check(not sim.can_fire(friend,enemy),"cannot shoot hidden enemy")
	check(sim.issue([friend.id],enemy.pos,"attack",false,enemy.id)==0,"hidden explicit attack rejected")
	var scout=sim.spawn("drone",0,Vector2(35,35))
	sim.update_visibility()
	check(enemy.seen_by[0],"drone shares elevated reconnaissance")
	check(not sim.can_fire(friend,enemy),"shared vision does not shoot through ridge")
	scout.hp=0
	sim.update_visibility()
	check(not enemy.seen_by[0],"lost scout removes current vision")
	friend.pos=Vector2(44,35)
	sim.update_visibility()
	check(sim.can_fire(friend,enemy),"visible unobstructed target can be attacked")
	var victim=sim.spawn("rifle",1,Vector2(25,18))
	var attacker=sim.spawn("rifle",0,Vector2(15,18))
	var protected_damage:float=sim.damage_amount(attacker,victim)
	victim.pos=Vector2(15,40)
	for member in victim.members:member.pos=victim.pos+member.offset
	check(sim.damage_amount(attacker,victim)>protected_damage,"woods reduce incoming infantry damage")
	enemy.facing=Vector2.RIGHT
	friend.pos=enemy.pos+Vector2(5,0)
	var front:float=sim.damage_amount(friend,enemy)
	friend.pos=enemy.pos-Vector2(5,0)
	check(sim.damage_amount(friend,enemy)>front,"rear armor is weaker")
	var air=sim.spawn("helo",1,friend.pos+Vector2(3,0))
	sim.update_visibility()
	check(not sim.can_fire(friend,air),"tank cannot attack aircraft")
	var aa=sim.spawn("aa",0,friend.pos)
	sim.update_visibility()
	check(sim.can_fire(aa,air),"AA can attack detected aircraft")
	sim=Sim.new(false,0)
	var drone=sim.spawn("drone",0,sim.objectives[0].pos)
	advance(sim,13)
	check(sim.objectives[0].owner==1,"air cannot capture")
	var ground=sim.spawn("rifle",0,sim.objectives[0].pos)
	advance(sim,13)
	check(sim.objectives[0].owner==0,"ground captures relay")
	sim.spawn("rifle",0,sim.objectives[1].pos)
	advance(sim,29)
	check(sim.result=="VICTORY","both sectors held produce victory")
	var ended:float=sim.time
	sim.tick(1)
	check(sim.time==ended,"terminal state freezes simulation")
	sim=Sim.new(false,0)
	var sole=sim.spawn("rifle",0,Vector2(10,10))
	sole.hp=0
	sim.tick(0.1)
	check(sim.result=="DEFEAT","loss of entire force produces defeat")
	var reset=Sim.new(true,0)
	check(reset.result=="" and reset.time==0 and reset.living(0).size()==6,"new scenario resets state")
	print("SIMULATION TESTS: ",checks," checks, ",failures.size()," failures")
	quit(1 if not failures.is_empty() else 0)
