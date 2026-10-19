extends SceneTree
# Threat-aware harvesting (classic skirmish). Harvesters lost money and lives
# driving to deposits beside enemy forces or into the enemy base (classic seed
# sweeps: replacement harvesters dying at the enemy-side deposit). A side's
# harvesters now judge deposits by what that side knows:
#  1. a deposit with a known enemy tank beside it is skipped; the harvester
#     waits somewhere safe by its refinery and never comes within the tank's
#     reach; once the tank is destroyed it goes back to work;
#  2. fog: an enemy tank nobody has seen does not stop it setting off, and on
#     sighting the tank it turns back;
#  3. a harvester hit on its way to the ore aborts and returns (empty: to a
#     safe spot by the refinery; loaded: to unload);
#  4. with only the deposit by the enemy's (known) refinery left it waits at home.
const Sim=preload("res://scripts/simulation.gd")
const C=preload("res://scripts/classic.gd")
const TANK_AT:=Vector2(24,27) # 11 m north of the west deposit, 19 m from the refinery
const UNSEEN_AT:=Vector2(18,30) # out of the refinery's sight, in a harvester's at the ore
const ENEMY_WORKS:=Vector2(66,26) # where the AI builds its refinery
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func scenario_index(id:String)->int:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		if configs[i].id==id:return i
	return -1

func _init()->void:
	known_tank()
	unseen_tank()
	attacked_en_route()
	enemy_base()
	print("HARVESTER THREAT: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)

# Quiet economy: enemy AI idle, units gone (structures stay: the enemy HQ marks
# its base), the starting harvester and a refinery set back from the west
# deposit (beyond defended ground: by its base a side's harvesters work on).
# The enemy has its refinery by the east deposit, as the AI builds it, and a
# friendly drone has seen it.
func economy()->Object:
	var sim=Sim.new(true,scenario_index("classic"))
	sim.classic.ai_clock=1e9
	sim.classic.attack_clock=1e9
	for u in sim.units:
		if not sim.definitions[u.kind].get("structure",false) and (u.team==1 or u.kind!="harvester"):u.hp=0.0
	sim.spawn("refinery",0,Vector2(6,56))
	var works:Dictionary=sim.spawn("refinery",1,ENEMY_WORKS)
	C.sync_obstacles(sim)
	var scout:Dictionary=sim.spawn("drone",0,ENEMY_WORKS)
	for frame in 15:sim.tick(0.1)
	scout.hp=0.0
	check(C.intel(sim,0).structures.has(works.id),"the side knows the enemy refinery its drone saw")
	return sim

func harvester(sim)->Dictionary:
	return sim.living(0).filter(func(u):return u.kind=="harvester")[0]

func refinery(sim)->Dictionary:
	return C.structures(sim,0,"refinery")[0]

# An enemy tank held in place with its gun silent (the test is about choices).
func hold(tank:Dictionary)->void:
	tank.pos=tank.get("hold_at",TANK_AT);tank.orders.clear();tank.path.clear();tank.cooldown=1e9

# Runs while holding the tanks; returns the harvester's closest approach to `to`.
func run(sim,seconds:float,tanks:Array=[],to:Vector2=TANK_AT)->float:
	var truck:=harvester(sim)
	var closest:=INF
	for frame in int(seconds/0.1):
		for tank in tanks:
			if sim.alive(tank):hold(tank)
		sim.tick(0.1)
		closest=minf(closest,truck.pos.distance_to(to))
	return closest

# 1. Known tank beside the deposit (a friendly drone overhead sees it).
func known_tank()->void:
	var sim=economy()
	var west:Dictionary=sim.classic.fields[0]
	var tank:Dictionary=sim.spawn("tank",1,TANK_AT)
	var drone:Dictionary=sim.spawn("drone",0,west.pos)
	var closest:=run(sim,40.0,[tank])
	var truck:=harvester(sim)
	var reach:float=float(sim.definitions.tank.range)
	print("KNOWN TANK: closest %.1f m (reach %.0f), west mined %.0f, harvester at %s '%s', %.1f m from the refinery, hp %.0f" % [closest,reach,6000.0-west.remaining,truck.pos.snapped(Vector2(0.1,0.1)),truck.reason,truck.pos.distance_to(refinery(sim).pos),truck.hp])
	check(C.intel(sim,0).threats.has(tank.id),"the side knows the tank its drone sees")
	check(is_equal_approx(west.remaining,6000.0),"the threatened deposit is not worked")
	check(closest>reach,"the harvester never comes within the tank's reach (%.1f m)" % closest)
	check(truck.reason.begins_with("Deposits under threat"),"it reports waiting out the threat ('%s')" % truck.reason)
	check(truck.orders.is_empty() and truck.pos.distance_to(refinery(sim).pos)<C.STAGE_RINGS[-1]+4.0 and C.safe(sim,0,truck.pos,true),"it waits at a safe spot by its refinery")
	check(is_equal_approx(sim.classic.fields[1].remaining,6000.0),"nor does it drive to the deposit by the enemy base")
	# The tank is destroyed: the deposit is safe again and work resumes.
	tank.hp=0.0
	drone.hp=0.0
	run(sim,40.0)
	print("CLEARED: west mined %.0f, harvester '%s'" % [6000.0-west.remaining,truck.reason])
	check(west.remaining<6000.0,"work resumes once the threat is gone")

# 2. Fog: the tank is out of every friendly unit's sight at first.
func unseen_tank()->void:
	var sim=economy()
	var west:Dictionary=sim.classic.fields[0]
	var tank:Dictionary=sim.spawn("tank",1,UNSEEN_AT)
	tank["hold_at"]=UNSEEN_AT
	var truck:=harvester(sim)
	var set_off:=false
	var turned:=false
	var start_gap:float=truck.pos.distance_to(west.pos)
	var nearest:=INF
	for frame in 400:
		hold(tank)
		sim.tick(0.1)
		if frame==20:
			check(not C.intel(sim,0).threats.has(tank.id),"an unseen tank is not known")
			set_off=not truck.orders.is_empty() and Vector2(truck.orders.back().pos).distance_to(west.pos)<C.ORE_RINGS[-1][0]+0.5
		nearest=minf(nearest,truck.pos.distance_to(west.pos))
		if C.intel(sim,0).threats.has(tank.id) and truck.reason in ["Deposit under threat · pulling back","Deposits under threat · waiting"]:turned=true
	print("UNSEEN TANK: set off %s, nearest to deposit %.1f m (from %.1f), turned back %s, west mined %.0f, harvester '%s' hp %.0f" % [set_off,nearest,start_gap,turned,6000.0-west.remaining,truck.reason,truck.hp])
	check(set_off,"with the tank unseen the harvester sets off for the deposit")
	check(turned,"on sighting the tank it gives up the deposit")
	print("  ends at %s, %.1f m from the tank, safe %s" % [truck.pos.snapped(Vector2(0.1,0.1)),truck.pos.distance_to(UNSEEN_AT),C.safe(sim,0,truck.pos)])
	check(truck.pos.distance_to(UNSEEN_AT)>float(sim.definitions.tank.range) and C.safe(sim,0,truck.pos,true),"it ends out of the tank's reach, somewhere safe")

# 3. A harvester hit on its way to the ore aborts and returns.
func attacked_en_route()->void:
	var sim=economy()
	var west:Dictionary=sim.classic.fields[0]
	var truck:=harvester(sim)
	for frame in 300:
		sim.tick(0.1)
		if not truck.orders.is_empty() and not C.defended(sim,0,truck.pos):break
	check(not truck.orders.is_empty() and not C.defended(sim,0,truck.pos),"on its way to the deposit, out past the base")
	var hit_at:Vector2=truck.pos
	var before:float=truck.pos.distance_to(west.pos)
	truck.last_hit=sim.time
	truck.hp-=10.0
	run(sim,15.0)
	print("ATTACKED: hit %.1f m from the deposit, now %.1f m (%.1f m from the refinery, %.1f from the hit, defended %s), '%s', west mined %.0f" % [before,truck.pos.distance_to(west.pos),truck.pos.distance_to(refinery(sim).pos),truck.pos.distance_to(hit_at),C.defended(sim,0,truck.pos),truck.reason,6000.0-west.remaining])
	check(is_equal_approx(west.remaining,6000.0),"it does not carry on to the ore")
	check(truck.reason=="Under fire · pulling back","it pulls back ('%s')" % truck.reason)
	check(truck.pos.distance_to(refinery(sim).pos)<C.STAGE_RINGS[-1]+4.0 and C.defended(sim,0,truck.pos) and truck.pos.distance_to(hit_at)>4.0,"back to defended ground by its refinery")
	run(sim,30.0)
	check(west.remaining<6000.0,"after the alarm it goes back to work")
	# Loaded and hit at the ore: it heads home to unload.
	var funds:float=sim.credits
	truck.cargo=60.0;truck.haul="COLLECT";truck.last_hit=sim.time
	run(sim,0.3)
	check(truck.haul=="RETURN" or sim.credits>=funds+60.0,"a loaded harvester under fire heads home to unload")

# 4. Only the deposit by the enemy refinery (where the AI builds it, seen by a
# passing friendly drone) has ore: the harvester stays home.
func enemy_base()->void:
	var sim=economy()
	sim.classic.fields[0].remaining=0.0
	var east:Dictionary=sim.classic.fields[1]
	var closest:=run(sim,60.0,[],ENEMY_WORKS)
	var truck:=harvester(sim)
	print("ENEMY BASE: closest to the enemy refinery %.1f m, east mined %.0f, harvester '%s'" % [closest,6000.0-east.remaining,truck.reason])
	check(is_equal_approx(east.remaining,6000.0),"the deposit by the enemy refinery is not worked")
	check(closest>C.REFINERY_ZONE,"it never enters the enemy base (%.1f m from the refinery)" % closest)
	check(truck.orders.is_empty() and truck.pos.distance_to(refinery(sim).pos)<C.STAGE_RINGS[-1]+4.0,"it waits by its refinery")
