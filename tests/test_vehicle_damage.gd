extends SceneTree
# Vehicle component damage: penetration by weapon x hull face x range, the
# component outcome mix, immobilised/disarmed/abandoned behaviour, persistent
# wrecks that block vehicles, and a measured ATGM-vs-tank kill time.
const Sim=preload("res://scripts/simulation.gd")
const FieldOps=preload("res://scripts/field_ops.gd")
const VehicleDamage=preload("res://scripts/vehicle_damage.gd")
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
const FACES:=["front","side","rear"]
const ARC:={"front":Vector2.LEFT,"side":Vector2.UP,"rear":Vector2.RIGHT}

# Penetration chance with the shooter `distance` m east of a target whose hull
# faces `face` relative to it (front: facing the shooter).
func chance(sim,weapon:String,target_kind:String,face:String,distance:float)->float:
	var target:={"kind":target_kind,"pos":Vector2(100,100),"facing":-ARC[face]}
	var shooter:={"kind":weapon,"pos":Vector2(100+distance,100)}
	return VehicleDamage.penetration_chance(sim,shooter,target)

func _init()->void:
	var sim=Sim.new(false,harbor_index())
	# --- 1. Penetration table -------------------------------------------------
	var table:Dictionary={}
	print("PENETRATION (close 5 m / long 90% range)")
	for weapon in ["rifle","bunker","aa","boat","tank","at_gun","atgm","helo"]:
		for target in ["tank","aa","boat","helo"]:
			var row:="  %-7s -> %-5s" % [weapon,target]
			for face in FACES:
				var reach:float=sim.weapon_range(weapon,sim.definitions[target])
				var near:=chance(sim,weapon,target,face,5.0)
				var far:=chance(sim,weapon,target,face,reach*0.9)
				table["%s/%s/%s" % [weapon,target,face]]=near
				row+="  %s %.2f/%.2f" % [face,near,far]
			print(row)
	check(table["atgm/tank/side"]>=0.99 and table["atgm/tank/rear"]>=0.99,"Javelin reliably penetrates tank side and rear")
	# Frontal arcs are not uniform: the glacis/turret face stops tank AP and
	# mostly stops a Javelin, the mantlet and lower plate (a quarter of the
	# frontal hits) do not.
	check(table["atgm/tank/front"]>0.3 and table["atgm/tank/front"]<0.65,"Javelin penetrates tank front about half the time (weak zones)")
	check(table["tank/tank/side"]>=0.99 and table["tank/tank/rear"]>=0.99 and table["tank/tank/front"]<0.35,"tank AP: flank reliable, frontal duel hard")
	# Top attack lands on the roof whatever the facing.
	for face in FACES:
		var top:={"kind":"atgm","pos":Vector2(116,100),"attack":"top"}
		var hull:={"kind":"tank","pos":Vector2(100,100),"facing":-ARC[face]}
		check(VehicleDamage.penetration_chance(sim,top,hull)>=0.99,"Javelin top attack penetrates the tank roof (%s arc)" % face)
		check(VehicleDamage.roll_location(sim,top,hull,RandomNumberGenerator.new()).zone.zone in ["turret_roof","engine_deck"],"top attack strikes a roof zone (%s arc)" % face)
	var roof:Array=VehicleDamage.zones(sim,"tank")[VehicleDamage.ROOF]
	for zone in roof:check(float(zone.mm)<=70.0 and float(zone.mm)<sim.definitions.tank.armor_mm[1],"tank %s (%d mm) is thinner than the hull side" % [zone.zone,zone.mm])
	check(VehicleDamage.top_attack(sim,sim.definitions.atgm,{"kind":"tank","members":[]},16.0) and not VehicleDamage.top_attack(sim,sim.definitions.atgm,{"kind":"tank","members":[]},1.0),"top attack beyond 150 m (1.5 u), direct attack inside it")
	check(not VehicleDamage.top_attack(sim,sim.definitions.atgm,{"kind":"helo","members":[]},16.0),"no top attack against aircraft")
	var duel_front:=chance(sim,"tank","tank","front",19.0)
	check(duel_front<table["tank/tank/front"],"tank AP penetration falls with range")
	check(duel_front>0.15,"tank AP still finds frontal weak zones at duel range (%.2f)" % duel_front)
	check(table["at_gun/tank/side"]>=0.99 and table["at_gun/tank/front"]<0.3,"AT gun kills from the flank; frontally only through weak zones")
	check(table["aa/aa/side"]>=0.99 and table["aa/tank/side"]==0.0 and table["aa/tank/rear"]==0.0,"autocannon defeats light armour only")
	for target in ["tank","aa","boat"]:
		for face in FACES:check(table["rifle/%s/%s" % [target,face]]==0.0 and table["bunker/%s/%s" % [target,face]]==0.0,"small arms never penetrate %s %s" % [target,face])
	check(table["aa/helo/side"]>=0.99,"autocannon tears through a gunship")
	check(chance(sim,"rifle","helo","side",0.0)>0.0 and chance(sim,"rifle","helo","side",0.0)<1.0,"rifles sometimes penetrate a gunship overhead")
	# Expected integrity loss keeps the rear weaker than the front.
	var shooter:Dictionary=sim.spawn("tank",0,BASE)
	var target:Dictionary=sim.spawn("tank",1,BASE+Vector2(12,0))
	target.facing=Vector2.LEFT
	var front:float=sim.damage_amount(shooter,target)
	target.facing=Vector2.RIGHT
	var rear:float=sim.damage_amount(shooter,target)
	check(rear>front*3.0,"rear hits cost far more integrity than frontal ones (%.1f vs %.1f)" % [rear,front])

	# --- 2. Component outcomes --------------------------------------------------
	var tally:Dictionary={}
	var trials:=4000
	target.facing=Vector2.UP
	for i in trials:
		reset(target)
		sim.events.clear()
		VehicleDamage.strike(sim,shooter,target,sim.damage_amount(shooter,target))
		var effect:="penetration"
		for event in sim.events:
			if event.type=="vehicle_damage" and event.effect not in ["destroyed","wreck"]:effect=event.effect
		tally[effect]=tally.get(effect,0)+1
	sim.remove_meta(VehicleDamage.WRECKS)
	print("OUTCOMES tank AP vs tank side (n=%d): %s" % [trials,str(tally)])
	var weights:Dictionary=sim.definitions.tank.damage_effects
	for effect in weights:
		var share:float=float(tally.get(effect,0))/trials
		check(absf(share-float(weights[effect]))<0.03,"%s share %.3f near authored %.2f" % [effect,share,weights[effect]])
	check(not tally.has("ricochet"),"flank AP never ricochets")
	tally.clear()
	target.facing=Vector2.RIGHT
	var shooter_front:={"kind":"atgm","pos":target.pos+Vector2(12,0),"team":0}
	for i in trials:
		reset(target)
		sim.events.clear()
		VehicleDamage.strike(sim,shooter_front,target,sim.damage_amount(shooter_front,target))
		var effect:="penetration"
		for event in sim.events:
			if event.type=="vehicle_damage" and event.effect not in ["destroyed","wreck"]:effect=event.effect if event.penetrated else "nonpen_"+event.effect
		tally[effect]=tally.get(effect,0)+1
	print("OUTCOMES Javelin vs tank front (n=%d): %s" % [trials,str(tally)])
	var nonpens:=0
	for key in tally:
		if str(key).begins_with("nonpen_"):nonpens+=int(tally[key])
	var ricochet:float=float(nonpens)/trials
	check(absf(ricochet-(1.0-table["atgm/tank/front"]))<0.03,"frontal Javelin non-penetration share %.2f matches table" % ricochet)
	var track:float=float(tally.get("nonpen_mobility",0))/maxf(1,nonpens)
	check(track>0.015 and track<0.09,"a few non-penetrating hits break a track (%.3f)" % track)
	var shock:float=float(tally.get("nonpen_shock",0))/maxf(1,nonpens)
	check(shock>0.15 and shock<0.35,"heavy non-penetrating hits shake the crew (%.3f)" % shock)
	if sim.has_meta(VehicleDamage.WRECKS):sim.remove_meta(VehicleDamage.WRECKS)

	# --- 3. Immobilised tank holds position but fires --------------------------------
	var s2=Sim.new(false,harbor_index())
	var tank:Dictionary=s2.spawn("tank",0,BASE)
	var foe:Dictionary=s2.spawn("rifle",1,BASE+Vector2(0,-14))
	VehicleDamage.ensure_state(s2,tank)
	tank.mobility_kill=true
	s2.update_visibility()
	var start:Vector2=tank.pos
	s2.issue([tank.id],BASE+Vector2(40,0),"move")
	var shots:=0
	for i in 150:
		s2.tick(1.0/30)
		for event in s2.events:
			if event.type=="shot" and event.from==tank.pos and event.kind=="tank":shots+=1
		s2.events.clear()
	check(tank.pos.distance_to(start)<0.01,"immobilised tank does not move (%.3f m)" % tank.pos.distance_to(start))
	check(tank.orders.is_empty(),"immobilised tank drops its move order")
	check(shots>0,"immobilised tank keeps firing (%d shots)" % shots)

	# --- 4. Disarmed tank cannot fire ----------------------------------------------
	var s3=Sim.new(false,harbor_index())
	var gunless:Dictionary=s3.spawn("tank",0,BASE)
	var foe3:Dictionary=s3.spawn("rifle",1,BASE+Vector2(0,-14))
	s3.update_visibility()
	check(s3.can_fire(gunless,foe3),"intact tank can engage")
	VehicleDamage.ensure_state(s3,gunless)
	gunless.firepower_kill=true
	check(not s3.can_fire(gunless,foe3),"main gun disabled: cannot fire")
	shots=0
	var hp3:float=foe3.hp
	for i in 150:
		s3.tick(1.0/30)
		for event in s3.events:
			if event.type=="shot" and event.kind=="tank":shots+=1
		s3.events.clear()
	check(shots==0 and foe3.hp==hp3,"disarmed tank never shoots (%d shots)" % shots)
	start=gunless.pos
	s3.issue([gunless.id],BASE+Vector2(-20,0),"move")
	for i in 90:s3.tick(1.0/30)
	check(gunless.pos.distance_to(start)>2.0,"disarmed tank can still drive")

	# --- 5. Crew casualties: slower, then bail out -----------------------------------
	var s4=Sim.new(false,harbor_index())
	var gunner:Dictionary=s4.spawn("tank",1,BASE+Vector2(14,0))
	var crew_tank:Dictionary=s4.spawn("tank",0,BASE)
	crew_tank.facing=Vector2.UP
	VehicleDamage.ensure_state(s4,crew_tank)
	var casualties:=0
	var kinds:Dictionary={}
	var bailed_warning:=false
	for i in 400:
		# Keep rolling until the crew outcome decides it: other results are undone.
		crew_tank.hp=crew_tank.max_hp
		crew_tank.firepower_kill=false
		crew_tank.mobility_kill=false
		VehicleDamage.wrecks(s4).clear()
		s4.events.clear()
		var crew_before:int=crew_tank.crew
		VehicleDamage.strike(s4,gunner,crew_tank,s4.damage_amount(gunner,crew_tank))
		if crew_tank.crew<crew_before:casualties+=1
		if crew_tank.abandoned:break
	for event in s4.events:
		if event.type=="warning" and "bailed out" in str(event.text):bailed_warning=true
		if event.type=="vehicle_damage":
			kinds[event.effect]=true
			check(event.unit==crew_tank.id and event.has("pos"),"vehicle_damage event names unit and position")
	check(casualties==2,"two crew casualties (%d)" % casualties)
	check(crew_tank.abandoned and crew_tank.crew==0 and crew_tank.hp<=0.0,"second crew casualty bails the crew out")
	check(VehicleDamage.wrecks(s4).size()==1 and VehicleDamage.wrecks(s4)[0].abandoned,"abandoned tank leaves a wreck")
	check(bailed_warning,"player warned when a crew bails out")
	check(kinds.has("abandoned") and kinds.has("wreck"),"abandonment emits vehicle_damage events")
	# Injured crew reloads more slowly (once per shot) and re-acquires slowly.
	var s6=Sim.new(false,harbor_index())
	var hurt:Dictionary=s6.spawn("tank",0,BASE)
	var mark:Dictionary=s6.spawn("rifle",1,BASE+Vector2(0,-14))
	s6.update_visibility()
	var cycle_intact:=reload_cycle(s6,hurt)
	VehicleDamage.ensure_state(s6,hurt)
	hurt.crew=1
	var cycle_hurt:=reload_cycle(s6,hurt)
	print("RELOAD CYCLE intact %.2fs, one crew down %.2fs" % [cycle_intact,cycle_hurt])
	check(cycle_hurt>cycle_intact*1.4,"crew casualty slows the firing cycle")

	# --- 6. Wrecks persist and block vehicles ------------------------------------------
	var s7=Sim.new(false,harbor_index())
	var victim:Dictionary=s7.spawn("tank",1,BASE)
	var killer:Dictionary=s7.spawn("tank",0,BASE+Vector2(-14,0))
	victim.facing=Vector2.UP
	s7.update_visibility()
	for i in 60:
		if not s7.alive(victim):break
		s7.resolve_shot(killer,victim,1.0)
	check(not s7.alive(victim),"flank fire destroys the tank")
	check(VehicleDamage.wrecks(s7).size()==1,"destroyed tank becomes a wreck")
	var wreck:Dictionary=VehicleDamage.wrecks(s7)[0]
	killer.hp=0.0
	var mover:Dictionary=s7.spawn("tank",0,BASE+Vector2(-16,0))
	var probe_from:Vector2=wreck.pos+Vector2(-6.0,0)
	mover.pos=probe_from
	check(not s7.movement_clear(mover,probe_from+Vector2(1.5,0),[]),"wreck blocks a vehicle driving into it")
	check(s7.movement_clear(mover,probe_from+Vector2(-0.5,0),[]),"vehicle may always back away from a wreck")
	mover.pos=BASE+Vector2(-16,0)
	s7.issue([mover.id],BASE+Vector2(18,0),"move")
	var closest:=INF
	for i in 30*30:
		s7.tick(1.0/30)
		closest=minf(closest,mover.pos.distance_to(wreck.pos))
		if mover.orders.is_empty():break
	print("WRECK pass: closest approach %.2f (limit %.2f), arrived %s at %.1fs, mover at %s" % [closest,float(wreck.radius)*2,str(mover.orders.is_empty()),s7.time,str(mover.pos)])
	check(closest>=float(wreck.radius)*2.0-0.05,"vehicle never drives through the wreck")
	check(mover.pos.distance_to(BASE+Vector2(18,0))<4.0,"vehicle finds a way round the wreck")
	check(VehicleDamage.wrecks(s7).size()==1 and VehicleDamage.wrecks(s7)[0].pos==wreck.pos,"wreck persists for the battle")
	check(VehicleDamage.wreck_cover(s7,wreck.pos+Vector2(-4,0),wreck.pos+Vector2(20,0)),"wreck gives hard cover against fire from beyond it")
	check(not VehicleDamage.wreck_cover(s7,wreck.pos+Vector2(-4,0),wreck.pos+Vector2(-20,0)),"no cover from the open side")

	# --- 7. Gunship damage ------------------------------------------------------------
	var s8=Sim.new(false,harbor_index())
	var helo:Dictionary=s8.spawn("helo",0,BASE)
	VehicleDamage.ensure_state(s8,helo)
	s8.issue([helo.id],BASE+Vector2(60,0),"move")
	start=helo.pos
	for i in 30:s8.tick(1.0/30)
	var intact_flight:float=helo.pos.distance_to(start)
	helo.mobility_kill=true
	start=helo.pos
	for i in 30:s8.tick(1.0/30)
	var damaged_flight:float=helo.pos.distance_to(start)
	print("GUNSHIP 1 s flight intact %.2f m, damaged %.2f m" % [intact_flight,damaged_flight])
	check(damaged_flight<intact_flight*0.75 and damaged_flight>0.5,"damaged gunship flies slower")

	# --- 8. Two Javelin teams vs a tank: flank vs front --------------------------------
	# Top attack (16 m is beyond the top-attack minimum) strikes the roof from
	# any side; in direct-attack mode the frontal arc still holds.
	var flank:=kill_times(true)
	var frontal:=kill_times(false)
	print("ATGM x2 vs TANK top attack flank: mean %.1fs %s | front: mean %.1fs %s" % [mean(flank),str(flank),mean(frontal),str(frontal)])
	check(not flank.has(-1.0) and not frontal.has(-1.0),"two Javelin teams always kill the tank within 120 s")
	check(mean(frontal)<mean(flank)*1.25,"top attack: frontal kills about as fast as flank kills")
	var direct_flank:=kill_times(true,true)
	var direct_front:=kill_times(false,true)
	print("ATGM x2 vs TANK direct attack flank: mean %.1fs %s | front: mean %.1fs %s" % [mean(direct_flank),str(direct_flank),mean(direct_front),str(direct_front)])
	check(not direct_flank.has(-1.0),"direct attack kills the tank from the flank within 120 s")
	check(mean(direct_front)>mean(direct_flank)*1.8,"direct attack: flank kills markedly faster than frontal fire")
	# --- 9. Hit location: angled hulls, grazing hits, non-penetrating effects ----------
	var s9=Sim.new(false,harbor_index())
	var square:=yawed_chance(s9,"tank",0.0,19.0)
	var angled:=yawed_chance(s9,"tank",20.0,19.0)
	var grazing:=yawed_chance(s9,"tank",5.0,19.0)
	print("TANK AP vs TANK at 19 m: square-on %.2f, yawed 5 deg %.2f, yawed 20 deg %.2f" % [square,grazing,angled])
	check(angled>square+0.05,"a hull yawed 20 degrees exposes its side to frontal fire")
	check(grazing<=square+0.001,"grazing hits on the side glance off")
	var layer:Dictionary=s9.spawn("tank",0,BASE)
	var plated:Dictionary=s9.spawn("tank",1,BASE+Vector2(19,0))
	plated.facing=Vector2.LEFT
	var effects:Dictionary={}
	var sighted:=false
	for i in 3000:
		reset(plated)
		s9.events.clear()
		VehicleDamage.strike(s9,layer,plated,s9.damage_amount(layer,plated))
		for event in s9.events:
			if event.type=="vehicle_damage" and not event.penetrated:effects[event.effect]=effects.get(event.effect,0)+1
		if plated.get("optics_kill",false) and not sighted:
			sighted=true
			check(is_equal_approx(float(plated.accuracy),VehicleDamage.OPTICS_ACCURACY),"smashed sights cut the layer's accuracy")
			var before:float=s9.hit_chance(layer,plated)
			layer["accuracy"]=plated.accuracy
			check(s9.hit_chance(layer,plated)<before*0.7,"a tank on its auxiliary sight hits less often")
			layer.erase("accuracy")
			VehicleDamage.ensure_state(s9,plated)
			VehicleDamage.field_repair(s9,plated,VehicleDamage.REPAIR_SECONDS.optics+0.1)
			check(not plated.has("optics_kill") and not plated.has("accuracy"),"field repair replaces the sights")
	print("NON-PENETRATING tank AP vs tank front at 19 m (n=3000): %s" % str(effects))
	check(sighted,"frontal hits sometimes smash the sights")
	for effect in ["shock","optics","firepower","mobility"]:check(effects.get(effect,0)>0,"non-penetrating hits cause %s" % effect)
	if s9.has_meta(VehicleDamage.WRECKS):s9.remove_meta(VehicleDamage.WRECKS)

	# --- 10. Tank duel: square-on at 18 m, both firing ---------------------------------
	var duels:=duel_times()
	print("TANK DUEL square-on 18 m: mean %.1fs %s" % [mean(duels),str(duels)])
	check(not duels.has(-1.0),"a frontal tank duel is decided within 90 s")
	print("VEHICLE DAMAGE: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)

func reset(u:Dictionary)->void:
	for key in ["crew","crew_full","mobility_kill","firepower_kill","optics_kill","accuracy","abandoned","buttoned_until","reload_mark","aim_mark"]:u.erase(key)
	u.hp=u.max_hp
	u.cooldown=0.0

# Seconds between the first two shots at a stationary infantry target.
func reload_cycle(sim,tank:Dictionary)->float:
	var fired:Array=[]
	tank.cooldown=0.0
	for i in 30*20:
		sim.tick(1.0/30)
		for event in sim.events:
			if event.type=="shot" and event.kind=="tank":fired.append(sim.time)
		sim.events.clear()
		for unit in sim.units:
			if unit.team==1:unit.hp=unit.max_hp;sim.Infantry.reconcile(unit);for m in unit.members:m.hp=m.max_hp
		if fired.size()>=3:break
	return fired[2]-fired[1] if fired.size()>=3 else 0.0

func mean(values:Array)->float:
	var total:=0.0
	for v in values:total+=v
	return total/maxf(1,values.size())

# Two Javelin teams 16 m from a passive tank on the open coast map (legacy
# preset: no autonomous cover-seeking, so the measurement is the damage model
# plus the real fire cadence and missile flight; `direct` forces direct attack).
# Seconds to kill; -1 = survived 120 s.
func kill_times(flank:bool,direct:bool=false)->Array:
	var times:Array=[]
	for trial in 8:
		var sim=Sim.new(false,0)
		if direct:sim.definitions.atgm.top_attack_min_m=1.0e9
		sim.combat_rng.seed=1000+trial
		var rng:=RandomNumberGenerator.new()
		rng.seed=500+trial
		sim.set_meta("vehicle_damage_rng",rng)
		var base:=Vector2(30,62)
		var tank:Dictionary=sim.spawn("tank",1,base)
		sim.spawn("atgm",0,base+Vector2(-16,-3))
		sim.spawn("atgm",0,base+Vector2(-16,4))
		tank.facing=Vector2.UP if flank else Vector2.LEFT
		sim.update_visibility()
		var killed:=-1.0
		for i in 120*30:
			tank.cooldown=1000.0
			sim.tactical_clock=1000.0
			sim.tick(1.0/30)
			if not sim.alive(tank):killed=sim.time;break
		times.append(snappedf(killed,0.1))
	return times

# Penetration chance of `weapon` at `distance` m against a tank whose hull is
# yawed `yaw` degrees off the line of fire (0 = square-on).
func yawed_chance(sim,weapon:String,yaw:float,distance:float)->float:
	var target:={"kind":"tank","pos":Vector2(100,100),"facing":Vector2.RIGHT.rotated(deg_to_rad(yaw))}
	var shooter:={"kind":weapon,"pos":Vector2(100+distance,100)}
	return VehicleDamage.penetration_chance(sim,shooter,target)

# Two stationary tanks 18 m apart, hulls square-on, both firing (legacy coast
# preset, as kill_times). Seconds to the first loss; -1 = none within 90 s.
func duel_times()->Array:
	var times:Array=[]
	for trial in 6:
		var sim=Sim.new(false,0)
		sim.combat_rng.seed=3000+trial
		var rng:=RandomNumberGenerator.new()
		rng.seed=900+trial
		sim.set_meta("vehicle_damage_rng",rng)
		var base:=Vector2(22,62)
		var a:Dictionary=sim.spawn("tank",0,base)
		var b:Dictionary=sim.spawn("tank",1,base+Vector2(18,0))
		a.facing=Vector2.RIGHT
		b.facing=Vector2.LEFT
		sim.update_visibility()
		var decided:=-1.0
		for i in 90*30:
			sim.tactical_clock=1000.0
			sim.tick(1.0/30)
			if not sim.alive(a) or not sim.alive(b):decided=sim.time;break
		times.append(snappedf(decided,0.1))
	return times
