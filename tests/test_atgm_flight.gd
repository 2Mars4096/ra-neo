extends SceneTree
# Javelin flight (fire-and-forget) and missile load: lock-on before launch needs line of sight;
# real time of flight compressed with the game time scale; after launch the
# gunner is free and the missile's seeker follows the target (a moving tank is
# still hit; the gunner killed, suppressed, moving or blinded changes nothing);
# a target destroyed in flight leaves the missile to strike its last position;
# a missile that strikes nothing bursts where it lands; top attack; and the
# presentation (effects missile, audio impact) arriving with the sim impact.
const Sim=preload("res://scripts/simulation.gd")
const Effects=preload("res://scripts/effects.gd")
const AudioFX=preload("res://scripts/audio_fx.gd")
const VehicleDamage=preload("res://scripts/vehicle_damage.gd")
const HUD=preload("res://scripts/hud.gd")
const DT:=1.0/30
const BASE:=Vector2(30,62)
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func _init()->void:
	flight_checks()
	lock_checks()
	free_gunner_checks()
	moving_checks()
	destroyed_checks()
	miss_checks()
	presentation_checks()
	audio_checks()
	load_checks()
	resupply_checks()
	ai_resupply_checks()
	infantry_target_checks()
	print("ATGM FLIGHT: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)

# One Javelin team `distance` m west of a passive tank on the open coast map
# (legacy preset, as test_vehicle_damage kill_times).
func setup(distance:float,seed:int=1)->Dictionary:
	var sim=Sim.new(false,0)
	sim.combat_rng.seed=seed
	var tank:Dictionary=sim.spawn("tank",1,BASE+Vector2(distance,0))
	var team:Dictionary=sim.spawn("atgm",0,BASE)
	tank.facing=Vector2.LEFT
	sim.update_visibility()
	return {"sim":sim,"tank":tank,"team":team}

func step(sim,tank:Dictionary,log:Array)->void:
	tank.cooldown=1000.0
	sim.tactical_clock=1000.0
	sim.tick(DT)
	for event in sim.events:
		if event.type in ["shot","missile_impact","world_blast"]:
			var entry:Dictionary=event.duplicate()
			entry["at"]=sim.time
			log.append(entry)
	sim.events.clear()

# Ticks until the first missile is in the air; returns its launch event.
func launch(world:Dictionary,log:Array,seconds:float=20.0)->Dictionary:
	for i in int(seconds*30):
		step(world.sim,world.tank,log)
		if not world.sim.missiles.is_empty():break
	return first(log,"shot")

func first(log:Array,type:String)->Dictionary:
	for event in log:
		if event.type==type and (type!="shot" or event.kind=="atgm"):return event
	return {}

func run_until(world:Dictionary,log:Array,type:String,seconds:float,each:Callable=Callable())->Dictionary:
	for i in int(seconds*30):
		if each.is_valid():each.call()
		step(world.sim,world.tank,log)
		var found:=first(log,type)
		if not found.is_empty():return found
	return {}

func flight_checks()->void:
	var atgm:Dictionary=setup(16.0).sim.definitions.atgm
	# FM 3-21.71 App. F: 1,000 m 4.6 s, 2,000 m 14.5 s; 20 u = 2,000 m; x0.35.
	check(absf(Sim.missile_flight(atgm,10.0)-4.6*0.35)<0.01,"1,000 m (10 u) flies 4.6 s x 0.35")
	check(absf(Sim.missile_flight(atgm,20.0)-14.5*0.35)<0.01,"2,000 m (20 u) flies 14.5 s x 0.35")
	for distance in [8.0,16.0]:
		var world:=setup(distance)
		var log:Array=[]
		var shot:=launch(world,log)
		check(not shot.is_empty() and shot.get("guided",false),"a guided launch event at %d m" % distance)
		if shot.is_empty():continue
		var range_u:float=(shot.from as Vector2).distance_to(shot.to)
		var expected:float=Sim.missile_flight(atgm,range_u)
		check(absf(float(shot.flight)-expected)<0.001,"launch event carries the flight time")
		var hp:float=world.tank.hp
		var seen:={"early":false}
		var impact:=run_until(world,log,"missile_impact",expected+1.0,func():if world.tank.hp<hp:seen.early=true)
		check(not impact.is_empty(),"the missile arrives (%d m)" % distance)
		if impact.is_empty():continue
		var flown:float=float(impact.at)-float(shot.at)
		print("FLIGHT %.1f u: launch %.2f s, impact %.2f s, flight %.2f s (expected %.2f), attack %s, hit %s" % [range_u,shot.at,impact.at,flown,expected,shot.get("attack",""),impact.hit])
		check(absf(flown-expected)<=DT+0.001,"impact at launch + time of flight (%.2f vs %.2f s)" % [flown,expected])
		check(not seen.early,"no damage before the missile arrives")
		check(shot.get("attack","")=="top","%d m is beyond the top-attack minimum: top attack" % distance)
	# Top-attack minimum range: 150 m = 1.5 u; direct attack inside it.
	var world:=setup(16.0)
	check(VehicleDamage.top_attack(world.sim,atgm,world.tank,1.6) and not VehicleDamage.top_attack(world.sim,atgm,world.tank,1.4),"top attack from 1.5 u (150 m); direct attack inside")

# Lock-on before launch: no launch while the sight line is blocked; once it
# clears, the lock takes the preparation time before the missile leaves.
func lock_checks()->void:
	var world:=setup(16.0)
	var block:=Rect2(BASE+Vector2(7,-4),Vector2(2,8))
	world.sim.terrain.dynamic_blocks.append(block)
	var log:Array=[]
	for i in 30*4:step(world.sim,world.tank,log)
	check(first(log,"shot").is_empty(),"no lock and no launch without line of sight")
	world.sim.terrain.dynamic_blocks.erase(block)
	var cleared:float=world.sim.time
	var shot:=launch(world,log,6.0)
	var lock:float=float(shot.get("at",INF))-cleared
	print("LOCK sight cleared at %.2f s, launch %.2f s later" % [cleared,lock])
	check(not shot.is_empty(),"launch once the sight line clears")
	check(lock>=0.75-0.001 and lock<2.0,"lock-on takes ~0.75 s (2.1 s real) before launch (%.2f s)" % lock)

# Fire-and-forget: whatever happens to the gunner after launch, the seeker
# still flies the missile into the tank, and the gunner is free to act.
func free_gunner_checks()->void:
	for case in ["killed","suppressed","sight","moved"]:
		var hits:=0
		var trials:=4
		var free:=0
		for trial in trials:
			var world:=setup(16.0,20+trial)
			var log:Array=[]
			var shot:=launch(world,log)
			if shot.is_empty():continue
			var gunner:Dictionary=world.team.members[0]
			for i in int(float(shot.flight)*15):step(world.sim,world.tank,log)
			match case:
				"killed":
					gunner.hp=0.0;gunner.wound="KIA";gunner.state="KIA"
				"sight":
					var mid:Vector2=(shot.from as Vector2).lerp(shot.to,0.5)
					world.sim.terrain.dynamic_blocks.append(Rect2(mid-Vector2(1,3),Vector2(2,6)))
				"moved":world.sim.issue([world.team.id],BASE+Vector2(-12,6),"move")
			var hp:float=world.tank.hp
			var start:Vector2=gunner.pos
			var impact:=run_until(world,log,"missile_impact",float(shot.flight)+1.0,func():if case=="suppressed":world.team.suppression=1.0)
			if impact.get("hit",false) and world.tank.hp<hp:hits+=1
			if case=="moved" and gunner.pos.distance_to(start)>1.5:free+=1
			if case=="sight":world.sim.terrain.dynamic_blocks.pop_back()
		print("FIRE-AND-FORGET gunner %s mid-flight: %d/%d hits" % [case,hits,trials])
		check(hits>=trials-1,"gunner %s after launch: the seeker still hits (%d/%d)" % [case,hits,trials])
		if case=="moved":check(free==trials,"the gunner moves off while the missile flies (%d/%d)" % [free,trials])

# The seeker follows a tank driving across the line of fire.
func moving_checks()->void:
	var hits:=0
	var on_target:=0
	var trials:=6
	var moved_total:=0.0
	for trial in trials:
		var world:=setup(16.0,40+trial)
		var log:Array=[]
		var shot:=launch(world,log)
		if shot.is_empty():continue
		world.sim.issue([world.tank.id],world.tank.pos+Vector2(0,-40),"move")
		var start:Vector2=world.tank.pos
		var impact:=run_until(world,log,"missile_impact",float(shot.flight)+1.0)
		if impact.is_empty():continue
		moved_total+=start.distance_to(world.tank.pos)
		if impact.hit:hits+=1
		if (impact.pos as Vector2).distance_to(world.tank.pos)<=4.6:on_target+=1
	print("MOVING tank 16 m crossing: mean %.1f m driven in flight, %d/%d hits, %d/%d impacts at the tank" % [moved_total/trials,hits,trials,on_target,trials])
	check(moved_total/trials>4.0,"the tank moves well clear of its launch-time position")
	check(on_target==trials,"the seeker follows the moving tank")
	check(hits>=trials-1,"a locked seeker hits a moving tank (%d/%d)" % [hits,trials])

# Target destroyed in flight: the missile strikes the old spot and bursts,
# wounding soldiers standing there.
func destroyed_checks()->void:
	var world:=setup(16.0,3)
	var foot:Dictionary=world.sim.spawn("rifle",1,BASE+Vector2(16,8))
	var log:Array=[]
	var shot:=launch(world,log)
	if shot.is_empty():check(false,"launch for destroyed target");return
	step(world.sim,world.tank,log)
	var spot:Vector2=world.tank.pos
	world.tank.hp=0.0
	# Soldiers gathered on the spot the missile is heading for.
	for k in foot.members.size():foot.members[k].pos=spot+Vector2(0.6*k,0.4)
	foot.pos=spot
	var before:=0.0
	for m in foot.members:before+=float(m.hp)
	var impact:=run_until(world,log,"missile_impact",float(shot.flight)+1.0)
	var blast:=first(log,"world_blast")
	var after:=0.0
	var hurt:=0
	for m in foot.members:
		after+=float(m.hp)
		if m.wound!="HEALTHY" or float(m.suppression)>0.5:hurt+=1
	print("DESTROYED in flight: impact %.1f m from the old spot, lost %s, blast %s, soldiers hp %.0f -> %.0f, %d/%d struck" % [(impact.get("pos",Vector2.INF) as Vector2).distance_to(spot),impact.get("lost","-"),blast.get("kind","-"),before,after,hurt,foot.members.size()])
	check(impact.get("lost","")=="destroyed","the seeker loses a destroyed target")
	check((impact.pos as Vector2).distance_to(spot)<0.01,"the missile comes down on the target's last position")
	check(blast.get("kind","")=="missile" and (blast.pos as Vector2).distance_to(spot)<0.01,"the warhead bursts where it lands")
	check(hurt==foot.members.size() and after<before,"soldiers at the impact point are caught in the burst")

# A missile that misses (seeker_hit forced to 0) bursts where it lands.
func miss_checks()->void:
	var world:=setup(16.0,5)
	world.sim.definitions.atgm.seeker_hit=0.0
	var log:Array=[]
	var shot:=launch(world,log)
	if shot.is_empty():check(false,"launch for miss");return
	var hp:float=world.tank.hp
	var impact:=run_until(world,log,"missile_impact",float(shot.flight)+1.0)
	var blast:=first(log,"world_blast")
	var off:float=(impact.get("pos",Vector2.INF) as Vector2).distance_to(world.tank.pos)
	print("MISS: impact %.1f m from the tank, blast %s at the impact point, tank hp %.0f -> %.0f" % [off,blast.get("kind","-"),hp,world.tank.hp])
	check(not impact.get("hit",true) and off>=2.4 and off<=4.6,"a miss lands 2.5-4.5 m off")
	check(blast.get("kind","")=="missile" and (blast.pos as Vector2).distance_to(impact.pos)<0.01,"the missed warhead bursts where it lands")

# The effects missile binds to the sim missile and arrives with the impact.
func presentation_checks()->void:
	for case in ["moving","destroyed"]:
		var world:=setup(16.0,11)
		var effects=Effects.new()
		root.add_child(effects)
		effects.watch(world.sim)
		var log:Array=[]
		var shot:=launch(world,log)
		if shot.is_empty():check(false,"launch for presentation");effects.free();continue
		var a:=Vector3(shot.from.x,float(shot.from_y),shot.from.y)
		var b:=Vector3(shot.to.x,float(shot.to_y),shot.to.y)
		var travel:float=effects.fire("atgm",a,b,true,false,"tank")
		check(effects.projectiles.size()==1 and effects.projectiles[0].has("track"),"%s: the visual missile follows the sim missile" % case)
		check(absf(travel-float(shot.flight))<0.001,"%s: visual travel time is the sim time of flight" % case)
		if case=="moving":world.sim.issue([world.tank.id],world.tank.pos+Vector2(0,-40),"move")
		var missile:Dictionary=effects.projectiles[0]
		var arrived:=-1.0
		var impact:Dictionary={}
		for i in int((float(shot.flight)+2.0)*30):
			if case=="destroyed" and world.sim.time>float(shot.at)+1.0 and world.tank.hp>0:world.tank.hp=0.0
			step(world.sim,world.tank,log)
			effects._process(DT)
			if impact.is_empty():impact=first(log,"missile_impact")
			if arrived<0.0 and effects.projectiles.is_empty():arrived=world.sim.time
			if arrived>=0.0 and not impact.is_empty():break
		check(not impact.is_empty() and arrived>=0.0,"%s: sim impact and visual arrival both happen" % case)
		if impact.is_empty() or arrived<0.0:effects.free();continue
		var arrival:Vector3=missile.b
		var gap:float=arrived-float(impact.at)
		var off:float=Vector2(arrival.x,arrival.z).distance_to(impact.pos)
		print("PRESENTATION %s: sim impact %.2f s, visual arrival %.2f s (%+.3f), arrival %.2f m from the sim impact point, hit %s, surface %s" % [case,impact.at,arrived,gap,off,impact.hit,missile.surface])
		check(gap>=-0.001 and gap<=2.0*DT+0.001,"%s: the visual missile arrives with the sim impact" % case)
		check(off<0.05,"%s: the visual missile lands where the sim missile did" % case)
		check(missile.surface==("armor" if impact.hit else "ground"),"%s: the visual impact matches the sim outcome (%s)" % [case,missile.surface])
		if case=="moving":check(Vector2(arrival.x,arrival.z).distance_to(shot.to)>3.0,"moving: the visual missile tracked the tank off its launch-time position")
		effects.free()

# Guided launch: launch sound only; the impact sound comes with missile_impact;
# the missile's burst (world_blast "missile") is not voiced twice.
func audio_checks()->void:
	var audio=AudioFX.new()
	root.add_child(audio)
	var focus:=Vector3(300,0,640)
	audio.frame(1.0/60,focus,Basis(),72.0)
	var centre:=Vector2(focus.x,focus.z)
	var played:int=audio.stats().counters.played
	audio.event({"type":"shot","from":centre,"to":centre+Vector2(16,0),"kind":"atgm","target_kind":"tank","hit":true,"from_y":0.95,"to_y":0.8,"visible":true,"flight":3.7,"guided":true})
	check(audio.stats().counters.played==played+1 and audio.stats().pending==0,"guided launch: launch sound, no early impact")
	played=audio.stats().counters.played
	audio.event({"type":"missile_impact","pos":centre+Vector2(16,0),"y":0.8,"hit":true,"target_kind":"tank","lost":"","visible":true})
	check(audio.stats().counters.played>=played+2,"missile impact on armour: metal and boom")
	played=audio.stats().counters.played
	audio.event({"type":"world_blast","kind":"missile","pos":centre+Vector2(18,0),"radius":2.5,"visible":true})
	check(audio.stats().counters.played==played and audio.stats().pending==0,"the missile burst is voiced once, by missile_impact")
	audio.free()

# A team carries three missiles (CLU + one round on the gunner, two on the
# ammunition bearer); when they are spent the gunner fights with his rifle.
func load_checks()->void:
	var world:=setup(16.0,9)
	var sim=world.sim
	check(sim.missiles_left(world.team)==3 and int(sim.definitions.atgm.missiles)==3,"a Javelin team carries three missiles")
	check(Array(HUD.damage_tags(sim,world.team))==["MISSILES 3/3"],"HUD reads MISSILES 3/3: %s" % [HUD.damage_tags(sim,world.team)])
	var log:Array=[]
	var warned:=false
	for i in 30*40:
		world.tank.hp=world.tank.max_hp
		world.tank.cooldown=1000.0
		sim.tactical_clock=1000.0
		sim.tick(DT)
		for event in sim.events:
			if event.type=="shot" and event.kind=="atgm":log.append(event)
			if event.type=="warning" and str(event.text).contains("out of missiles"):warned=true
		sim.events.clear()
	print("LOAD launches in 40 s: %d, missiles left %d" % [log.size(),sim.missiles_left(world.team)])
	check(log.size()==3 and sim.missiles_left(world.team)==0,"three launches and no more (%d)" % log.size())
	check(warned,"the player is told the team is out of missiles")
	check(sim.section_weapon(world.team,world.team.members[0])=="rifle","the empty gunner fights with his rifle")
	check(Array(HUD.damage_tags(sim,world.team))==["NO MISSILES · RESUPPLY"],"HUD reads NO MISSILES: %s" % [HUD.damage_tags(sim,world.team)])

# Rounds are drawn one per resupply_real s (game-scaled) beside a supply
# source, not away from it and not under fire.
func resupply_checks()->void:
	var world:=setup(16.0,9)
	var sim=world.sim
	var team:Dictionary=world.team
	team.missiles=0
	var per:float=float(sim.definitions.atgm.resupply_real)*Sim.GAME_TIME_SCALE
	for i in 30*int(per+2):step(sim,world.tank,[])
	check(sim.missiles_left(team)==0,"no resupply away from a supply source")
	var source:Dictionary=sim.supply_source(team)
	var spot:Vector2=source.pos
	world.tank.pos=spot+Vector2(60,0)
	place(team,spot)
	team.last_hit=sim.time
	for i in 30*2:step(sim,world.tank,[])
	team.last_hit=sim.time
	for i in 30*int(per):
		step(sim,world.tank,[])
		team.last_hit=sim.time
	check(sim.missiles_left(team)==0,"no resupply under fire")
	var started:float=sim.time
	var full:=-1.0
	for i in 30*int(4*per):
		step(sim,world.tank,[])
		if full<0.0 and sim.missiles_left(team)==3:full=sim.time-started
	print("RESUPPLY 3 rounds in %.1f s (%.1f s each = %.0f s real)" % [full,per,float(sim.definitions.atgm.resupply_real)])
	check(full>=3*per-RESUPPLY_SLACK-0.5 and full<=3*per+RESUPPLY_SLACK+3.0,"three rounds take ~3 x %.1f s beside the supply source (%.1f s)" % [per,full])

const RESUPPLY_SLACK:=0.5

func place(team:Dictionary,at:Vector2)->void:
	team.pos=at
	team.orders.clear()
	team.path.clear()
	for k in team.members.size():team.members[k].pos=at+Vector2(0.8*k,0.3)

# The enemy AI walks an empty team back for rounds and returns it to its order.
func ai_resupply_checks()->void:
	var sim=Sim.new(false,0)
	# A distant player unit keeps the mission running (no side wiped out).
	sim.spawn("rifle",0,Vector2(8,10))
	var team:Dictionary=sim.spawn("atgm",1,BASE+Vector2(10,0))
	var mark:=BASE+Vector2(-14,-10)
	sim.issue([team.id],mark,"attack_move")
	team.missiles=0
	var source:Dictionary=sim.supply_source(team)
	var reached:=false
	var refilled:=-1.0
	for i in 30*90:
		sim.tactical_clock=1000.0
		sim.tick(DT)
		sim.events.clear()
		if team.pos.distance_to(source.pos)<=float(source.reach):reached=true
		if refilled<0.0 and sim.missiles_left(team)==3:refilled=sim.time
		if refilled>0.0 and sim.time>refilled+1.0:break
	var resumed:bool=not team.orders.is_empty() and Vector2(team.orders[-1].pos).distance_to(mark)<1.0
	print("AI RESUPPLY reached source %s, full at %.1f s, resumed %s" % [reached,refilled,resumed])
	check(reached,"an empty enemy team walks back to its supply source")
	check(refilled>0.0,"it draws three rounds there")
	check(resumed,"then returns to its last order")

# Missiles are kept for vehicles, works and troops in buildings: against a
# section in the open the gunner uses his rifle.
func infantry_target_checks()->void:
	var sim=Sim.new(false,0)
	var team:Dictionary=sim.spawn("atgm",0,BASE)
	var foot:Dictionary=sim.spawn("rifle",1,BASE+Vector2(10,0))
	sim.update_visibility()
	var missiles:=0
	var rifle:=0
	for i in 30*15:
		sim.tactical_clock=1000.0
		sim.tick(DT)
		for event in sim.events:
			if event.type=="shot" and event.kind=="atgm":missiles+=1
			if event.type=="shot" and event.kind=="rifle" and (event.from as Vector2).distance_to(team.members[0].pos)<0.5:rifle+=1
		sim.events.clear()
		for m in foot.members:m.hp=m.max_hp
	print("INFANTRY in the open: %d missiles, %d gunner rifle shots" % [missiles,rifle])
	check(missiles==0,"no missile at a section in the open")
	check(rifle>0,"the gunner fires his rifle at it")
