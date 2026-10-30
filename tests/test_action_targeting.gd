extends SceneTree

const Sim=preload("res://scripts/simulation.gd")
const DT:=1.0/30.0
var checks:=0
var failures:=0

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func field():
	var sim=Sim.new(false,0)
	sim.scenario=sim.scenario.duplicate(true)
	sim.scenario.jam_radius=0
	return sim

func air_priority()->void:
	var sim=field()
	var aa:Dictionary=sim.spawn("aa",0,Vector2(12,50))
	var ground:Dictionary=sim.spawn("rifle",1,Vector2(12,40))
	sim.update_visibility()
	aa.target=ground.id
	check(sim.select_combat_target(aa).id==ground.id,"AA keeps a useful ground engagement")
	var drone:Dictionary=sim.spawn("fpv_drone",1,Vector2(14,36))
	check(not sim.contact_known(aa,drone),"new drone is not known before a visibility sample")
	check(sim.select_combat_target(aa).id==ground.id,"hidden urgent threat cannot preempt a valid target")
	sim.update_visibility()
	check(sim.contact_known(aa,drone),"real observation reveals incoming drone")
	aa.aim_target=ground.id;aa.aim_time=2.0;aa.cooldown=100.0
	sim.tick(DT)
	check(aa.target==drone.id,"AA switches to newly observed drone in one tick")
	check(aa.aim_time<=DT+0.00001,"urgent switch still pays weapon acquisition time")
	check(int(aa.get("tactical_wake_tick",-1))>=0,"observation records a tactical wake")
	# A target of the same ordinary class becoming closer is not an emergency.
	drone.hp=0.0
	var other:Dictionary=sim.spawn("rifle",1,Vector2(20,44))
	sim.update_visibility();aa.target=ground.id
	check(sim.select_combat_target(aa).id==ground.id,"nearer ground target does not discard an existing engagement")
	ground.hp=0.0
	check(sim.select_combat_target(aa).id==other.id,"lost target releases the commitment")

func explicit_first()->void:
	var sim=field()
	sim.terrain.style="showcase"
	sim.terrain.dynamic_blocks.append(Rect2(8,35,8,6))
	var squad:Dictionary=sim.spawn("rifle",0,Vector2(12,30))
	var member:Dictionary=squad.members[0]
	member.pos=Vector2(12,30)
	var candidates:Array=[]
	for index in 4:
		var hidden:Dictionary=sim.spawn("rifle",1,Vector2(22+index*5,45))
		for body in hidden.members:body.pos=Vector2(12,43)
		candidates.append(hidden)
	var desired:Dictionary=sim.spawn("rifle",1,Vector2(23,37))
	for body in desired.members:body.pos=Vector2(22,36)
	candidates.append(desired)
	squad.orders=[{"mode":"attack","target":desired.id,"pos":desired.pos}]
	sim.actions.accept_order(squad,squad.orders[0],sim.time)
	sim.soldier_checks=0
	var selected:Dictionary=sim.select_infantry_target(squad,member,"rifle",candidates,1.0)
	check(not selected.is_empty() and selected.target.id==desired.id,"late explicit target is evaluated before blocked incidental sections")
	check(sim.soldier_checks<=Sim.SHOOTER_CHECKS,"explicit targeting preserves individual line-check cap")
	# The same physical target remains the target even when another member is closer.
	member.target=desired.id;member.aim_member=desired.members[1].index
	desired.members[0].pos=Vector2(20,34)
	desired.members[1].pos=Vector2(23,36)
	selected=sim.select_infantry_target(squad,member,"rifle",candidates,1.0)
	check(selected.get("victim",{}).get("index",-1)==desired.members[1].index,"retained soldier body does not flicker to a slightly nearer body")
	desired.members[1].hp=0.0
	selected=sim.select_infantry_target(squad,member,"rifle",candidates,1.0)
	check(selected.get("victim",{}).get("index",-1)!=desired.members[1].index,"dead body releases individual aim tracking")

func hold_fire()->void:
	var sim=field()
	var aa:Dictionary=sim.spawn("aa",0,Vector2(12,50))
	var ground:Dictionary=sim.spawn("rifle",1,Vector2(12,40))
	var drone:Dictionary=sim.spawn("fpv_drone",1,Vector2(15,35))
	sim.update_visibility()
	check(sim.set_fire_policy([aa.id],"hold")==1,"hold-fire policy accepted")
	check(sim.select_combat_target(aa).is_empty(),"urgent aircraft does not override Hold fire")
	check(sim.issue([aa.id],ground.pos,"attack",false,ground.id)==1,"explicit attack is accepted under Hold fire")
	check(sim.select_combat_target(aa).get("id",-1)==ground.id,"explicit target has scoped firing permission")
	check(not sim.engagement_allowed(aa,drone.id),"scoped order does not permit an unrelated urgent target")
	sim.stop([aa.id])
	check(sim.select_combat_target(aa).is_empty(),"Stop ends explicit firing scope and restores Hold fire")
	sim.set_fire_policy([aa.id],"free")
	check(not sim.select_combat_target(aa).is_empty(),"free-fire policy restores legal automatic selection")

func run()->void:
	air_priority();explicit_first();hold_fire()
	print("ACTION TARGETING: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func _init()->void:call_deferred("run")
