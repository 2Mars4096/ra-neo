extends SceneTree
# Enemy prepared positions on the harbor map and armed emplacements.
const Sim=preload("res://scripts/simulation.gd")
const FieldOps=preload("res://scripts/field_ops.gd")
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func harbor_index()->int:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		if configs[i].id=="black_sea_harbor":return i
	return -1

func _init()->void:
	var sim=Sim.new(true,harbor_index())
	var authored:Array=sim.scenario.get("enemy_works",[])
	check(authored.size()>=15,"harbor authors a prepared defence (%d works)" % authored.size())
	var works:Array=sim.units.filter(func(u):return sim.alive(u) and u.team==1 and u.get("prepared",false))
	check(works.size()==authored.size(),"every prepared work spawned (%d/%d)" % [works.size(),authored.size()])
	check(works.all(func(u):return u.build_left<=0 and is_equal_approx(u.hp,u.max_hp)),"prepared works start complete and intact")
	for kind in ["bunker","at_gun","fighting_trench","concertina_wire","command_post","ammo_depot"]:
		check(works.any(func(u):return u.kind==kind),"defence includes "+kind)
	check(sim.units.filter(func(u):return u.team==1 and not u.get("structure",false)).size()>=20,"defenders garrison every objective")
	check(sim.scenario.get("reserve_force",[]).size()>=6,"armoured reserve staged")
	check(not sim.terrain.field_zones.is_empty(),"enemy wire and trenches install terrain zones")

	# A bunker engages infantry in range and never fires before completion.
	var bunker:Dictionary=works.filter(func(u):return u.kind=="bunker")[0]
	var rifle:Dictionary=sim.spawn("rifle",0,bunker.pos+Vector2(0,-12))
	if rifle.is_empty():rifle=sim.spawn("rifle",0,bunker.pos+Vector2(12,0))
	check(not rifle.is_empty(),"rifle fixture near bunker")
	if not rifle.is_empty():
		rifle.seen_by=[true,true];rifle.visible=true
		sim.update_visibility()
		var before:float=rifle.hp
		for i in 240:sim.tick(1.0/30)
		check(rifle.hp<before or rifle.suppression>0.3,"bunker MG damages or pins infantry (hp %s->%s, supp %.2f)" % [before,rifle.hp,rifle.suppression])
	var site:Dictionary=sim.spawn("bunker",1,bunker.pos+Vector2(30,30))
	if not site.is_empty():
		site.merge({"structure":true,"build_left":10.0,"engineer_id":-1,"build_paused":true},true)
		check(not sim.can_fire(site,rifle),"unfinished bunker cannot fire")
		site.hp=0

	# Gun pit hurts armour; rifles cannot scratch a bunker.
	check(float(sim.effectiveness["at_gun"]["tank"])>1.0,"AT gun effective against tanks")
	check(float(sim.effectiveness["bunker"]["tank"])==0.0,"bunker MG cannot hurt tanks")
	check(float(sim.effectiveness["rifle"]["bunker"])<0.3,"rifles barely damage bunkers")
	check(float(sim.effectiveness["tank"]["bunker"])>=0.8,"tank guns reduce bunkers")

	# Escalating two-pronged assault waves toward the player's base.
	var war=Sim.new(true,harbor_index())
	check(war.credits>=1500 and float(war.field_ops.income_rate)>=3.0,"player starts with build-up supply")
	check(not war.scenario.get("enemy_waves",{}).is_empty(),"harbor schedules enemy waves")
	var before:int=war.units.filter(func(u):return u.team==1 and not u.get("structure",false)).size()
	war.time=float(war.scenario.enemy_waves.first)+0.1
	FieldOps.enemy_offensive(war)
	var state:Dictionary=war.field_ops.waves
	check(state.index==1 and state.active.size()>=6,"first wave spawned (%d units)" % state.active.size())
	check(war.units.filter(func(u):return u.team==1 and not u.get("structure",false)).size()>=before+6,"wave adds attackers")
	var attackers:Array=state.active.map(func(id):return war.get_unit(id))
	check(attackers.all(func(u):return not u.orders.is_empty()),"every wave unit has orders")
	var target:=FieldOps.wave_target(war)
	check(attackers.any(func(u):return u.orders.size()>=2),"flank group detours before attacking")
	check(attackers.all(func(u):return u.orders.back().pos.distance_to(target)<30),"wave converges on the player's base")
	check(FieldOps.wave_composition(4).size()>FieldOps.wave_composition(0).size(),"waves escalate")
	for u in attackers:u.hp=u.max_hp*0.1
	FieldOps.enemy_offensive(war)
	check(state.active.is_empty() and attackers.any(func(u):return not u.orders.is_empty() and u.orders[0].mode=="retreat"),"broken wave withdraws")

	# Aggressive defence: an idle defender strikes a seen intruder near its post.
	var guard=Sim.new(true,harbor_index())
	var defender:Dictionary=guard.units.filter(func(u):return u.team==1 and u.kind=="rifle")[0]
	defender.orders=[]
	var intruder:Dictionary=guard.spawn("rifle",0,defender.pos+Vector2(18,0))
	if intruder.is_empty():intruder=guard.spawn("rifle",0,defender.pos+Vector2(-18,0))
	check(not intruder.is_empty(),"intruder fixture")
	if not intruder.is_empty():
		intruder.seen_by=[true,true]
		FieldOps.local_counterattacks(guard,{"active":[]})
		check(not defender.orders.is_empty() and defender.orders[0].mode=="attack_move","idle defender counter-attacks a nearby intruder")

	# Passive works draw no automatic fire; an explicit attack order engages them.
	var quiet=Sim.new(false,harbor_index())
	FieldOps.spawn_prepared_works(quiet,[{"kind":"concertina_wire","position":[300,700]}],1)
	var wire:Dictionary=quiet.units.back()
	var squad:Dictionary=quiet.spawn("rifle",0,Vector2(300,709))
	wire.seen_by=[true,true];wire.visible=true
	check(quiet.passive_work(wire) and not quiet.passive_work(squad),"wire is a passive work")
	for i in 120:quiet.tick(1.0/30)
	check(is_equal_approx(wire.hp,wire.max_hp) and squad.target!=wire.id,"squad ignores passive wire by default")
	quiet.issue([squad.id],wire.pos,"attack",false,wire.id)
	for i in 300:quiet.tick(1.0/30)
	check(wire.hp<wire.max_hp,"explicit attack order engages the wire")
	check(not quiet.passive_work({"kind":"bunker"}),"armed bunkers remain automatic targets")

	# Counterattack is staged from command posts and depots.
	check(FieldOps.enemy_logistics_alive(sim),"enemy logistics alive at start")
	for u in sim.units:
		if u.team==1 and u.kind in ["command_post","ammo_depot"]:u.hp=0
	check(not FieldOps.enemy_logistics_alive(sim),"destroying command posts and depots stops the reserve")
	print("ENEMY DEFENCES: ",checks," checks, ",failures," failures")
	quit(1 if failures>0 else 0)
