extends SceneTree
# Enemy wave strength bookkeeping: a vehicle re-crewed (or captured) by a wave
# section joins that wave, adds its integrity to the wave's strength (the
# boarders leave the section's hp), keeps the wave from being judged broken
# while it holds, takes up the attack if it has no orders, and withdraws with
# the wave. Sections outside the wave do not add to it, and FPV swarm drones
# are never wave members.
const Sim=preload("res://scripts/simulation.gd")
const FieldOps=preload("res://scripts/field_ops.gd")
const VehicleDamage=preload("res://scripts/vehicle_damage.gd")
const DT:=1.0/30.0
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
	recrew_joins_wave()
	idle_boarder_gets_wave_orders()
	outsider_does_not_join()
	swarms_excluded()
	print("WAVE STRENGTH: ",checks," checks, ",failures," failures")
	quit(1 if failures>0 else 0)

# A lean harbor sim with enemy logistics alive and the first wave launched.
func launch(index:int=0)->Object:
	var sim=Sim.new(false,harbor_index())
	FieldOps.spawn_prepared_works(sim,[{"kind":"command_post","position":[sim.field_ops.enemy_insertion.x+30,sim.field_ops.enemy_insertion.y+30]}],1)
	sim.field_ops.started=true
	# A player squad far back at the landing zone keeps the battle running.
	sim.spawn("rifle",0,sim.field_ops.insertion)
	sim.time=float(sim.scenario.enemy_waves.first)+0.1
	if index>0:
		sim.field_ops["waves"]={"next":sim.time,"index":index,"active":[],"strength":0.0}
	FieldOps.enemy_offensive(sim)
	return sim

func wave_hp(sim)->float:
	var hp:=0.0
	for id in sim.field_ops.waves.active:
		if sim.alive(sim.get_unit(id)):hp+=float(sim.get_unit(id).hp)
	return hp

# An enemy hull whose crew bailed out beside pos (hp 0, abandoned wreck).
func make_abandoned(sim,team:int,pos:Vector2,integrity:float)->Dictionary:
	var hull:Dictionary=sim.spawn("tank",team,pos)
	hull.facing=Vector2.UP
	VehicleDamage.ensure_state(sim,hull)
	hull.crew=0
	hull.abandoned=true
	hull["abandoned_hp"]=minf(integrity,hull.max_hp)
	hull.hp-=VehicleDamage._finish(sim,hull,hull.hp+1.0)
	return hull

func wave_sections(sim)->Array:
	return sim.field_ops.waves.active.map(func(id):return sim.get_unit(id)).filter(func(u):return u.kind in VehicleDamage.RECREW_KINDS)

func run_until(sim,seconds:float,done:Callable)->void:
	for i in int(seconds/DT):
		sim.tick(DT)
		if done.call() or sim.result!="":break
	check(sim.result=="","battle still running (%s)" % sim.result)

func boarding_event(sim,hull:Dictionary)->Dictionary:
	for e in sim.events:
		if e.type=="vehicle_damage" and e.effect in ["recrewed","captured"] and int(e.get("from",-1))==hull.id:return e
	return {}

# --- 1. A wave section re-crews a hull: the vehicle joins, strength follows -------
func recrew_joins_wave()->void:
	var sim=launch()
	var state:Dictionary=sim.field_ops.waves
	var sections:=wave_sections(sim)
	check(not sections.is_empty(),"wave has infantry sections")
	if sections.is_empty():return
	var hull:=make_abandoned(sim,1,sections[0].pos+Vector2(6,0),9999.0)
	var hp_before:={}
	for s in sections:hp_before[s.id]=float(s.hp)
	var strength_before:float=state.strength
	run_until(sim,30.0,func():return hull.has("recrewed_as"))
	var fresh:Dictionary=sim.get_unit(int(hull.get("recrewed_as",-1)))
	check(not fresh.is_empty() and sim.alive(fresh) and fresh.team==1,"a wave section re-crews the hull")
	if fresh.is_empty():return
	var event:=boarding_event(sim,hull)
	var section:Dictionary=sim.get_unit(int(event.get("section",-1)))
	check(not section.is_empty() and section.id in state.active,"the boarding section is a wave member")
	check(fresh.id in state.active,"re-crewed vehicle joins the wave (%d members)" % state.active.size())
	check(state.active.count(fresh.id)==1,"vehicle listed once")
	check(is_equal_approx(state.strength,strength_before+float(fresh.hp)),"wave strength grows by the vehicle's integrity (%.0f -> %.0f, vehicle %.0f)" % [strength_before,state.strength,fresh.hp])
	if not section.is_empty():
		check(float(section.hp)<float(hp_before.get(section.id,0.0)),"boarding section's reduced size counts (%.0f -> %.0f hp)" % [hp_before.get(section.id,0.0),section.hp])
	check(not fresh.orders.is_empty() and fresh.orders[-1].mode=="attack_move" and fresh.orders[-1].pos.distance_to(state.target)<8.0,"re-crewed vehicle carries the wave's attack")
	check(state.get("recrew",{}).is_empty(),"no stale re-crew bookkeeping")
	print("RECREW JOINS strength %.0f -> %.0f, live hp %.0f, members %d" % [strength_before,state.strength,wave_hp(sim),state.active.size()])

	# Originals mauled below 30% of the launch strength: the vehicle holds the wave.
	for id in state.active:
		var u:Dictionary=sim.get_unit(id)
		if id!=fresh.id and sim.alive(u):u.hp=u.max_hp*0.05
	var originals:float=wave_hp(sim)-float(fresh.hp)
	check(originals<strength_before*0.3,"setup: originals alone would read broken (%.0f < %.0f)" % [originals,strength_before*0.3])
	check(wave_hp(sim)>=state.strength*0.3,"setup: with the vehicle the wave holds (%.0f >= %.0f)" % [wave_hp(sim),state.strength*0.3])
	FieldOps.enemy_offensive(sim)
	check(fresh.id in state.active and state.active.size()>1,"wave not judged broken while the re-crewed vehicle fights")
	check(fresh.orders.is_empty() or fresh.orders[0].mode!="retreat","vehicle not withdrawn early")
	# Vehicle knocked about too: the wave breaks and the vehicle falls back with it.
	fresh.hp=fresh.max_hp*0.05
	FieldOps.enemy_offensive(sim)
	check(state.active.is_empty(),"wave breaks once the vehicle is also mauled")
	check(not fresh.orders.is_empty() and fresh.orders[0].mode=="retreat","re-crewed vehicle withdraws with the wave")

# --- 2. A boarder with no orders: the vehicle takes up the wave's attack -----------
func idle_boarder_gets_wave_orders()->void:
	var sim=launch()
	var state:Dictionary=sim.field_ops.waves
	var sections:=wave_sections(sim)
	if sections.is_empty():check(false,"wave has infantry sections");return
	for s in sections:s.orders=[]
	var hull:=make_abandoned(sim,1,sections[0].pos+Vector2(6,0),400.0)
	run_until(sim,30.0,func():return hull.has("recrewed_as"))
	var fresh:Dictionary=sim.get_unit(int(hull.get("recrewed_as",-1)))
	check(not fresh.is_empty() and fresh.team==1,"idle wave section re-crews the hull")
	if fresh.is_empty():return
	check(fresh.id in state.active,"vehicle joins the wave")
	check(not fresh.orders.is_empty() and fresh.orders[-1].mode=="attack_move" and fresh.orders[-1].pos.distance_to(state.target)<8.0,"vehicle given the wave's attack order")

# --- 3. A section outside the wave re-crews: the wave does not grow ---------------
func outsider_does_not_join()->void:
	var sim=launch()
	var state:Dictionary=sim.field_ops.waves
	var spot:Vector2=sim.field_ops.enemy_insertion+Vector2(-70,60)
	var guard:Dictionary=sim.spawn("rifle",1,spot)
	check(not guard.is_empty() and not guard.id in state.active,"defender section outside the wave")
	if guard.is_empty():return
	var hull:=make_abandoned(sim,1,guard.pos+Vector2(6,0),400.0)
	var strength:float=state.strength
	var members:int=state.active.size()
	run_until(sim,30.0,func():return hull.has("recrewed_as"))
	var fresh:Dictionary=sim.get_unit(int(hull.get("recrewed_as",-1)))
	var event:=boarding_event(sim,hull)
	check(not fresh.is_empty() and int(event.get("section",-1))==guard.id,"the defender re-crews the hull")
	check(not fresh.is_empty() and not fresh.id in state.active and state.active.size()==members and is_equal_approx(state.strength,strength),"wave membership and strength unchanged")

# --- 4. FPV swarm drones are never wave members -----------------------------------
func swarms_excluded()->void:
	var sim=Sim.new(false,harbor_index())
	FieldOps.spawn_prepared_works(sim,[{"kind":"command_post","position":[sim.field_ops.enemy_insertion.x+30,sim.field_ops.enemy_insertion.y+30]}],1)
	sim.field_ops.started=true
	sim.time=float(sim.scenario.enemy_waves.first)+0.1
	# A player squad at the wave target gives the swarm something to dive on.
	var target:=FieldOps.wave_target(sim)
	var victim:Dictionary=sim.spawn("rifle",0,target)
	check(not victim.is_empty(),"swarm victim fixture")
	sim.spawn("drone",1,target+Vector2(0,4))
	sim.update_visibility()
	check(victim.seen_by[1],"a scout observes the wave's swarm victim")
	sim.field_ops["waves"]={"next":sim.time,"index":2,"active":[],"strength":0.0,"swarm_next":sim.time+1000.0}
	FieldOps.enemy_offensive(sim)
	var state:Dictionary=sim.field_ops.waves
	var swarm:Array=sim.units.filter(func(u):return sim.alive(u) and u.team==1 and u.kind=="fpv_drone")
	check(state.index==3 and not state.active.is_empty(),"third wave launched")
	check(not swarm.is_empty(),"an FPV swarm launched with the wave (%d drones)" % swarm.size())
	check(swarm.all(func(u):return not u.id in state.active),"swarm drones are not wave members")
	check(state.active.all(func(id):return sim.get_unit(id).kind!="fpv_drone"),"wave holds no strike drones")
	check(is_equal_approx(state.strength,wave_hp(sim)),"wave strength counts members only (%.0f)" % state.strength)
	# A between-waves strike adds no members either.
	var members:int=state.active.size()
	state.swarm_next=sim.time
	FieldOps.swarm_strikes(sim,state,sim.scenario.enemy_waves)
	check(state.active.size()==members,"between-wave swarm adds no wave members")
