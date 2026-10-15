extends SceneTree
# Counter-drone combat on the harbor map: attack orders on UAVs, the AA/rifle/
# coax hierarchy, slant-range reach against altitude, and FPV strike swarms.
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

const BASE:=Vector2(300,640)

# Seconds until the drone dies under an explicit attack order (-1 = survived).
func duel(kind:String,limit:float=40.0)->Dictionary:
	var sim=Sim.new(false,harbor_index())
	var u:Dictionary=sim.spawn(kind,0,BASE)
	var drone:Dictionary=sim.spawn("drone",1,BASE+Vector2(12,0))
	sim.update_visibility()
	var accepted:int=sim.issue([u.id],drone.pos,"attack",false,drone.id)
	var killed:=-1.0
	for i in int(limit*30):
		sim.tick(1.0/30)
		if drone.hp<=0:killed=sim.time;break
	return {"accepted":accepted,"killed":killed,"feedback":sim.order_feedback}

# Launch a swarm at a cluster of player units; returns damage taken and drone fate.
func swarm_run(with_aa:int,count:int)->Dictionary:
	var sim=Sim.new(false,harbor_index())
	var victims:Array=[]
	for offset in [Vector2(0,0),Vector2(8,2),Vector2(-6,6),Vector2(4,10)]:
		var kind:String="tank" if victims.size()==1 else "rifle"
		var unit:Dictionary=sim.spawn(kind,0,BASE+offset)
		if not unit.is_empty():victims.append(unit)
	for i in with_aa:sim.spawn("aa",0,BASE+Vector2(-10+20*i,-8))
	sim.update_visibility()
	var before:=0.0
	for v in victims:before+=v.hp
	var events_before:int=sim.events.size()
	var ids:Array=FieldOps.launch_swarm(sim,BASE+Vector2(2,4),count)
	var warned:=false
	for i in range(events_before,sim.events.size()):
		if sim.events[i].type=="warning" and "FPV" in str(sim.events[i].text):warned=true
	var drones:Array=ids.map(func(id):return sim.get_unit(id))
	var dove:=false
	var max_alt:=0.0
	var start_distance:float=drones[0].pos.distance_to(BASE) if not drones.is_empty() else 0.0
	sim.events.clear()
	var elapsed:=0.0
	for i in 40*30:
		sim.tick(1.0/30)
		for d in drones:
			if sim.alive(d):
				if d.state=="DIVING":dove=true
				max_alt=maxf(max_alt,float(d.altitude))
		if drones.all(func(d):return not sim.alive(d)):elapsed=sim.time;break
	var after:=0.0
	for v in victims:after+=maxf(0,v.hp)
	var blasts:=0
	var shot_down:=0
	for e in sim.events:
		if e.type=="destroyed" and e.kind=="fpv_drone":blasts+=1
	for d in drones:
		if d.get("last_hit",-100.0)>0:shot_down+=1
	return {"launched":ids.size(),"warned":warned,"damage":before-after,"all_gone":drones.all(func(d):return not sim.alive(d)),"elapsed":elapsed,"blasts":blasts,"shot_down":shot_down,"dove":dove,"max_alt":max_alt,"start_distance":start_distance,"kills":sim.kills}

func _init()->void:
	var sim=Sim.new(false,harbor_index())
	# Believable counter-UAV table: AA strong, rifles and MGs light, coax weak, Javelin none.
	var e:Dictionary=sim.effectiveness
	check(float(e.aa.drone)>=1.5 and float(e.aa.fpv_drone)>=1.5,"AA is the strong counter to drones")
	check(float(e.rifle.drone)>0 and float(e.rifle.fpv_drone)>0,"rifles can engage drones")
	check(float(e.tank.drone)>0 and float(e.tank.drone)<0.3,"tank coax engages drones weakly")
	check(float(e.atgm.drone)==0 and float(e.atgm.fpv_drone)==0,"Javelin missile cannot engage drones")
	check(float(e.bunker.fpv_drone)>0,"MG bunker can engage strike drones")
	check(sim.definitions.fpv_drone.domain=="air" and sim.definitions.fpv_drone.get("strike",false),"FPV strike drone defined as air munition")

	# Slant range: a scout at its harbor flight band is reachable by rifles only nearly overhead.
	var drone:Dictionary=sim.spawn("drone",1,BASE+Vector2(0,-40))
	var alt:float=sim.unit_altitude(drone)
	check(alt>=10.0,"harbor scout flies above rooflines (%.1f)" % alt)
	check(sim.weapon_reaches("rifle",drone.pos+Vector2(5,0),drone),"rifle reaches drone nearly overhead")
	check(not sim.weapon_reaches("rifle",drone.pos+Vector2(10,0),drone),"rifle cannot reach drone at 10 m ground distance")
	check(sim.weapon_reaches("aa",drone.pos+Vector2(18,0),drone),"AA reaches drone at 18 m")
	check(sim.weapon_reaches("tank",drone.pos+Vector2(9,0),drone) and not sim.weapon_reaches("tank",drone.pos+Vector2(14,0),drone),"tank coax has elevation-limited reach")
	check(not sim.weapon_reaches("atgm",drone.pos+Vector2(3,0),drone),"Javelin never reaches a drone")
	drone.altitude=2.0
	check(sim.weapon_reaches("rifle",drone.pos+Vector2(12,0),drone),"per-unit altitude: low drone reachable at 12 m")
	drone.erase("altitude")

	# Attack orders on an enemy drone: accepted by valid units, refused with feedback otherwise.
	var times:Dictionary={}
	for kind in ["rifle","aa","tank","atgm"]:
		var result:=duel(kind)
		times[kind]=result.killed
		check(result.accepted==1,"%s accepts an attack order on a drone" % kind)
	check(times.aa>0 and times.aa<4.0,"AA downs a drone quickly (%.1f s)" % times.aa)
	check(times.rifle>0 and times.rifle<30.0,"rifles down a drone eventually (%.1f s)" % times.rifle)
	check(times.rifle>times.aa,"AA beats rifles against drones")
	var scout:=duel("drone",1.0)
	check(scout.accepted==0 and "ineffective" in str(scout.feedback),"unarmed scout refused with 'Weapon ineffective' feedback")
	print("COUNTER DRONE duel seconds: ",times)

	# Automatic targeting: AA prefers the aircraft over a nearer infantry section.
	var auto=Sim.new(false,harbor_index())
	var aa:Dictionary=auto.spawn("aa",0,BASE)
	var infantry:Dictionary=auto.spawn("rifle",1,BASE+Vector2(0,-12))
	var uav:Dictionary=auto.spawn("drone",1,BASE+Vector2(10,-8))
	auto.update_visibility()
	for i in 6:auto.tick(1.0/30)
	check(aa.target==uav.id,"AA auto-targets the drone over nearer infantry (target %d, drone %d, rifles %d)" % [aa.target,uav.id,infantry.id])
	# A tank's coax ignores a hovering scout unless ordered, but defends against an FPV.
	var tank:Dictionary=auto.spawn("tank",0,BASE+Vector2(40,0))
	var hover:Dictionary=auto.spawn("drone",1,tank.pos+Vector2(6,0))
	auto.update_visibility()
	check(auto.can_fire(tank,hover) and not auto.auto_target_ok(tank,hover),"tank coax does not auto-lock onto a scout drone")
	var inbound:Dictionary=auto.spawn("fpv_drone",1,tank.pos+Vector2(0,30))
	check(auto.auto_target_ok(tank,inbound),"tank coax auto-engages an inbound strike drone")
	inbound.hp=0;hover.hp=0
	# Riflemen auto-engage a low inbound strike drone in preference to ground targets.
	var squad:Dictionary=auto.spawn("rifle",0,BASE+Vector2(-30,30))
	var fpv:Dictionary=auto.spawn("fpv_drone",1,squad.pos+Vector2(9,0))
	var ground:Dictionary=auto.spawn("rifle",1,squad.pos+Vector2(-7,0))
	fpv.strike_target=squad.id
	fpv.altitude=2.0;fpv.fuse=1000.0
	auto.update_visibility()
	auto.infantry_combat(squad,1.0/30)
	check(squad.members.any(func(m):return m.target==fpv.id),"riflemen engage an inbound FPV before ground targets (ground %d)" % ground.id)

	# FPV swarm: launches with a warning, homes, dives, blasts and self-destructs.
	var bare:=swarm_run(0,6)
	print("COUNTER DRONE swarm without AA: ",bare)
	check(bare.launched==6,"swarm of 6 launched")
	check(bare.warned,"swarm launch warns the player")
	check(bare.start_distance>40.0,"swarm launches from standoff range (%.0f m)" % bare.start_distance)
	check(bare.dove,"strike drones dive on the target")
	check(bare.all_gone,"every strike drone is expended")
	check(bare.blasts>=6,"each drone ends in a destroyed event (%d)" % bare.blasts)
	check(bare.damage>100.0,"unopposed swarm inflicts heavy damage (%.0f)" % bare.damage)
	var defended:=swarm_run(2,6)
	print("COUNTER DRONE swarm with 2 AA: ",defended)
	check(defended.all_gone,"defended swarm expended")
	check(defended.kills>=2,"AA shoots down strike drones (%d)" % defended.kills)
	check(defended.damage<bare.damage*0.8,"AA reduces swarm damage (%.0f vs %.0f)" % [defended.damage,bare.damage])

	# Field ops schedules swarms with later waves and between waves.
	var war=Sim.new(true,harbor_index())
	var plan:Dictionary=war.scenario.enemy_waves
	war.time=float(plan.first)+0.1
	FieldOps.enemy_offensive(war)
	check(war.units.filter(func(u):return u.kind=="fpv_drone").is_empty(),"first wave carries no swarm")
	check(war.field_ops.waves.has("swarm_next"),"swarm strikes scheduled after the first wave")
	for u in war.units:
		if u.team==0 and not u.get("structure",false):u.seen_by[1]=true
	war.time=float(war.field_ops.waves.swarm_next)+0.1
	FieldOps.enemy_offensive(war)
	var swarm:int=war.units.filter(func(u):return u.kind=="fpv_drone" and war.alive(u)).size()
	check(swarm>=4 and swarm<=8,"mid-wave strike launches a 4-8 drone swarm on a seen cluster (%d)" % swarm)
	war.time=float(war.field_ops.waves.next)+0.1
	FieldOps.enemy_offensive(war)
	var total:int=war.units.filter(func(u):return u.kind=="fpv_drone" and war.alive(u)).size()
	check(total>swarm and total<=FieldOps.SWARM_LIVE_LIMIT,"second wave adds its own swarm within the live cap (%d)" % total)
	print("COUNTER DRONE: ",checks," checks, ",failures," failures")
	quit(1 if failures>0 else 0)
