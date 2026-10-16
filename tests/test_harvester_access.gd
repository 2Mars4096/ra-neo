extends SceneTree
# Harvester ore access (classic skirmish). Found in long classic games: a
# friendly tank immobilised ~2 m from the ore field centre plus wrecks kept the
# harvester off the remaining ore and the economy died. The harvester must
#  1. work ore it can actually reach round an immobilised tank and wrecks;
#  2. keep delivering when they close the deposit (the reported layout), and
#     fall back to another deposit when a field is walled off by wrecks;
#  3. ask an idle friendly vehicle parked on the deposit to make way.
const Sim=preload("res://scripts/simulation.gd")
const C=preload("res://scripts/classic.gd")
const VehicleDamage=preload("res://scripts/vehicle_damage.gd")
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
	blocked_centre()
	closed_centre()
	walled_field()
	parked_on_field()
	print("HARVESTER ACCESS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)

# Quiet economy: enemy AI idle, enemy units gone, a ready refinery near the ore.
func economy()->Object:
	var sim=Sim.new(true,scenario_index("classic"))
	sim.classic.ai_clock=1e9
	sim.classic.attack_clock=1e9
	for u in sim.living(1):
		if not sim.definitions[u.kind].get("structure",false):u.hp=0.0
	var site:Vector2=C.find_site(sim,"refinery",0)
	check(site.x>=0,"refinery site found")
	sim.spawn("refinery",0,site)
	C.sync_obstacles(sim)
	return sim

func harvester(sim)->Dictionary:
	return sim.living(0).filter(func(u):return u.kind=="harvester")[0]

func wreck(sim,pos:Vector2,radius:float=2.45)->void:
	if not sim.has_meta(VehicleDamage.WRECKS):sim.set_meta(VehicleDamage.WRECKS,[])
	sim.get_meta(VehicleDamage.WRECKS).append({"id":-1,"kind":"tank","team":0,"pos":pos,"facing":Vector2.RIGHT,"radius":radius,"abandoned":false})

func immobilised_tank(sim,pos:Vector2)->Dictionary:
	var tank:Dictionary=sim.spawn("tank",0,pos)
	VehicleDamage.ensure_state(sim,tank)
	tank.mobility_kill=true
	return tank

# Runs the economy; returns loads delivered (cargo >100 dropping to 0).
func run(sim,seconds:float,watch:Array=[])->int:
	var truck:=harvester(sim)
	var loads:=0
	var previous:=0.0
	var started:=Time.get_ticks_usec()
	for frame in int(seconds/0.1):
		for tank in watch:tank.mobility_kill=true
		sim.tick(0.1)
		var cargo:float=truck.get("cargo",0.0)
		if previous>100 and cargo==0:loads+=1
		previous=cargo
	print("  %.0f s: %d loads, harvester at %s cargo %d reason '%s' (%.0f ms, %d path queries)" % [seconds,loads,truck.pos,truck.get("cargo",0.0),truck.reason,(Time.get_ticks_usec()-started)/1000.0,sim.terrain.path_calls])
	return loads

# 1. Immobilised tank ~2 m from the centre, wrecks on and beside the centre.
func blocked_centre()->void:
	var sim=economy()
	var field:Dictionary=sim.classic.fields[0]
	var centre:Vector2=field.pos
	var tank:=immobilised_tank(sim,centre+Vector2(2.0,-0.2))
	wreck(sim,centre+Vector2(0.7,1.7))
	wreck(sim,centre+Vector2(-3.7,-5.2))
	var loads:=run(sim,240.0,[tank])
	var mined:float=6000.0-field.remaining
	print("BLOCKED CENTRE: loads=",loads," west mined=",mined," east mined=",6000.0-sim.classic.fields[1].remaining)
	# Pure collection is ~36 loads in 240 s here; before the fix it managed 17
	# (stand points it could not reach, wrecks missing from its plan).
	check(loads>=24,"harvester keeps delivering past an immobilised tank and wrecks (%d loads)"%loads)
	check(mined>=loads*120-1,"ore worked from the blocked deposit's open side")
	check(tank.pos.distance_to(centre+Vector2(2.0,-0.2))<0.1,"immobilised tank stayed put")

# 2a. The reported layout: tank ~2 m from the centre and wrecks on both other
# sides close the deposit (open ground beyond is terrain-blocked). Before the
# fix the harvester delivered nothing; now it works the other deposit.
func closed_centre()->void:
	var sim=economy()
	var centre:Vector2=sim.classic.fields[0].pos
	var tank:=immobilised_tank(sim,centre+Vector2(2.0,0.3))
	wreck(sim,centre+Vector2(-1.8,1.6))
	wreck(sim,centre+Vector2(-1.2,-2.4))
	var loads:=run(sim,240.0,[tank])
	print("CLOSED CENTRE: loads=",loads," west mined=",6000.0-sim.classic.fields[0].remaining," east mined=",6000.0-sim.classic.fields[1].remaining)
	check(loads>=3,"harvester keeps delivering when the deposit is closed (%d loads)"%loads)

# 2b. The west deposit is ringed by wrecks: fall back to the east deposit.
func walled_field()->void:
	var sim=economy()
	var west:Dictionary=sim.classic.fields[0]
	for i in 12:wreck(sim,west.pos+Vector2.from_angle(i*TAU/12)*6.0)
	for i in 4:wreck(sim,west.pos+Vector2.from_angle(i*TAU/4+0.4)*2.0)
	var loads:=run(sim,300.0)
	var east_mined:float=6000.0-sim.classic.fields[1].remaining
	print("WALLED FIELD: loads=",loads," west mined=",6000.0-west.remaining," east mined=",east_mined)
	check(is_equal_approx(west.remaining,6000.0),"walled-off deposit is not mined through wrecks")
	check(loads>=1 and east_mined>=120,"harvester falls back to the other deposit (%d loads)"%loads)

# 3. An idle friendly tank parked on the deposit centre is asked to make way.
func parked_on_field()->void:
	var sim=economy()
	var field:Dictionary=sim.classic.fields[0]
	var parked:Dictionary=sim.spawn("tank",0,field.pos+Vector2(0.4,0.2))
	var loads:=run(sim,150.0)
	print("PARKED TANK: loads=",loads," tank at ",parked.pos," gap ",parked.pos.distance_to(field.pos))
	check(parked.pos.distance_to(field.pos)>4.5,"idle tank on the deposit made way")
	check(loads>=2,"harvester delivers from the cleared deposit (%d loads)"%loads)
