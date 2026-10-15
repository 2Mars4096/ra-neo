extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)
func _init()->void:
	var sim=Sim.new(false,0)
	for weapon in sim.definitions:
		for target in sim.definitions:
			check(sim.effectiveness[weapon].has(target) and float(sim.effectiveness[weapon][target])>=0,"defined pairing "+weapon+"/"+target)
	var rifle=sim.spawn("rifle",0,Vector2(14,50))
	var tank=sim.spawn("tank",1,Vector2(14,40))
	sim.update_visibility()
	check(not sim.can_fire(rifle,tank),"rifles reject tank hull")
	check(sim.issue([rifle.id],tank.pos,"attack",false,tank.id)==0,"ineffective explicit attack rejected")
	for i in 200:sim.resolve_shot(rifle,tank,0.25)
	check(tank.hp==tank.max_hp,"sustained rifle fire cannot chip tank")
	check(not sim.effective_weapon("rifle","aa") and not sim.effective_weapon("rifle","boat"),"light armor and ship hull immune to rifle HP damage")
	var drone=sim.spawn("drone",1,Vector2(14,42))
	check(sim.damage_amount(rifle,drone)*0.25>=drone.max_hp,"one successful rifle hit disables small UAV")
	var aa=sim.spawn("aa",0,Vector2(19,50))
	check(sim.hit_chance(aa,drone)>sim.hit_chance(rifle,drone)*3,"AA tracks small UAV better")
	var stationary:float=sim.hit_chance(rifle,drone)
	drone.state="MOVING"
	check(sim.hit_chance(rifle,drone)<stationary,"moving UAV harder to hit")
	var hits:=0
	for i in 1000:
		drone.hp=drone.max_hp
		if sim.resolve_shot(rifle,drone,0.25):
			hits+=1
			check(drone.hp<=0,"successful rifle hit kills UAV")
		else:check(drone.hp==drone.max_hp,"miss causes zero HP loss")
	check(hits>20 and hits<200,"seeded low probability hits occur without every shot hitting")
	var ew=Sim.new(false,2)
	var squad=ew.spawn("rifle",0,Vector2(46,41))
	check(ew.issue([squad.id],ew.objectives[0].pos,"attack_move")==1,"orders issued outside interference")
	squad.pos=Vector2(46,26)
	for member in squad.members:member.pos=squad.pos+member.offset
	var old:Vector2=squad.orders[0].pos
	check(ew.comms_blocked(squad),"hostile exchange interrupts radio")
	check(ew.issue([squad.id],Vector2(15,60))==0 and squad.orders[0].pos==old,"lost commands do not overwrite last order")
	check(ew.stop([squad.id])==0 and not squad.orders.is_empty(),"remote stop also respects link loss")
	var enemy=ew.spawn("rifle",1,Vector2(46,19))
	enemy.seen_by[0]=false
	check(ew.can_fire(squad,enemy),"disconnected soldiers retain local defense")
	ew.update_visibility()
	check(not enemy.seen_by[0],"disconnected sensor does not upload contacts")
	ew.objectives[0].owner=0
	check(not ew.comms_blocked(squad) and ew.stop([squad.id])==1,"capture disables jammer and restores commands")
	print("COMBAT TESTS: ",checks," checks, ",failures," failures; UAV hits ",hits,"/1000")
	quit(0 if failures==0 else 1)
