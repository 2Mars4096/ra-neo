extends SceneTree
# Separate assaults keep retreat, re-crewing and defender/garrison exclusions
# when a later scheduled wave launches before the earlier one is resolved.
const Sim=preload("res://scripts/simulation.gd")
const FieldOps=preload("res://scripts/field_ops.gd")
const VehicleDamage=preload("res://scripts/vehicle_damage.gd")
const DT:=1.0/30.0
var checks:=0
var failures:=0

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func _init()->void:call_deferred("run")

func launch(near_objective:bool=false)->Object:
	var sim=Sim.new(false,6)
	if near_objective:sim.field_ops.enemy_insertion=sim.objectives[0].pos
	FieldOps.spawn_prepared_works(sim,[{"kind":"command_post","position":sim.field_ops.enemy_insertion+Vector2(30,30)}],1)
	sim.spawn("rifle",0,sim.field_ops.insertion)
	sim.field_ops.started=true
	sim.time=float(sim.scenario.enemy_waves.first)+0.1
	FieldOps.enemy_offensive(sim)
	return sim

func next_wave(sim)->void:
	sim.time=float(sim.field_ops.waves.next)+0.1
	FieldOps.enemy_offensive(sim)

func weaken(sim,formation:Dictionary,except:int=-1)->void:
	for id in formation.active:
		var unit:Dictionary=sim.get_unit(id)
		if id!=except and sim.alive(unit):unit.hp=unit.max_hp*0.05

func independent_retreat()->void:
	var sim=launch()
	var state:Dictionary=sim.field_ops.waves
	var first:Dictionary=state.latest
	var first_ids:Array=first.active.duplicate()
	var first_strength:float=first.strength
	var first_target:Vector2=first.target
	next_wave(sim)
	var second:Dictionary=state.latest
	var second_ids:Array=second.active.duplicate()
	check(state.formations.size()==2 and first_ids.all(func(id):return sim.alive(sim.get_unit(id))),"both overlapping waves remain managed and alive")
	check(first.active==first_ids and first.strength==first_strength and first.target==first_target,"new wave preserves the older wave's membership, strength and objective")
	check(first_ids.all(func(id):return id in FieldOps.active_wave_ids(state)) and second_ids.all(func(id):return id in FieldOps.active_wave_ids(state)),"all-wave membership includes both assaults")
	check(first_ids.all(func(id):return not id in second_ids),"wave memberships are disjoint")
	weaken(sim,first)
	FieldOps.enemy_offensive(sim)
	check(first.active.is_empty() and state.formations.size()==1,"only the damaged older wave is removed from active assaults")
	check(first_ids.all(func(id):var u:Dictionary=sim.get_unit(id);return not u.orders.is_empty() and u.orders[0].mode=="retreat"),"every surviving older attacker receives retreat")
	check(second.active==second_ids and second_ids.all(func(id):var u:Dictionary=sim.get_unit(id);return not u.orders.is_empty() and u.orders[0].mode!="retreat"),"the intact newer wave continues attacking")
	check(state.active==second_ids and state.strength==second.strength,"latest-wave diagnostic fields still describe the current assault")
	var warnings:int=sim.events.filter(func(e):return e.type=="warning" and "assault broken" in str(e.text)).size()
	FieldOps.enemy_offensive(sim)
	check(sim.events.filter(func(e):return e.type=="warning" and "assault broken" in str(e.text)).size()==warnings,"a resolved wave does not warn or retreat repeatedly")
	weaken(sim,second)
	FieldOps.enemy_offensive(sim)
	check(state.formations.is_empty() and state.active.is_empty(),"each wave resolves independently, including the latest")

func older_wave_exclusions()->void:
	var sim=launch(true)
	var state:Dictionary=sim.field_ops.waves
	var first_ids:Array=state.active.duplicate()
	next_wave(sim)
	var section:Dictionary=first_ids.map(func(id):return sim.get_unit(id)).filter(func(u):return u.kind=="rifle")[0]
	# Isolate membership: an older wave section has no orders and an observed
	# intruder nearby. It must not be reassigned as a local static defender.
	section.orders=[];section.path=[]
	var intruder:Dictionary=sim.spawn("rifle",0,section.pos+Vector2(14,0))
	sim.spawn("drone",1,intruder.pos+Vector2(0,3))
	sim.update_visibility()
	check(intruder.seen_by[1],"real reconnaissance sees the local intruder")
	state.local_next=0.0
	FieldOps.local_counterattacks(sim,state)
	check(section.orders.is_empty() and not section.has("post"),"older active wave members do not become local defenders")
	# This fixture launched beside an objective, so the sections are physically
	# close enough to enter its buildings if wave membership fails to exclude them.
	for id in first_ids:
		var unit:Dictionary=sim.get_unit(id)
		unit.home=sim.objectives[0].pos
		unit.orders=[];unit.path=[];unit.maneuver={}
	sim.field_ops.garrison_next=0.0
	FieldOps.enemy_garrisons(sim)
	check(first_ids.all(func(id):var u:Dictionary=sim.get_unit(id);return not u.get("garrison_role",false) and not u.has("garrison_target")),"older active waves stay excluded from garrison roles")
	# Positive control: releasing this same formation from offensive duties must
	# make its nearby idle infantry eligible through the ordinary garrison logic.
	state.formations.remove_at(0)
	sim.field_ops.garrison_next=0.0
	FieldOps.enemy_garrisons(sim)
	check(first_ids.any(func(id):return sim.get_unit(id).get("garrison_role",false)),"the same sections can garrison once released from their active wave")

func overlapping_recrew()->void:
	var sim=launch()
	var state:Dictionary=sim.field_ops.waves
	var first:Dictionary=state.latest
	var sections:Array=first.active.map(func(id):return sim.get_unit(id)).filter(func(u):return u.kind in VehicleDamage.RECREW_KINDS)
	for section in sections:section.orders=[];section.path=[]
	var hull:Dictionary=sim.spawn("tank",1,sections[0].pos+Vector2(6,0))
	VehicleDamage.ensure_state(sim,hull)
	hull.crew=0;hull.abandoned=true;hull["abandoned_hp"]=hull.max_hp
	hull.hp-=VehicleDamage._finish(sim,hull,hull.hp+1.0)
	VehicleDamage.enemy_recrew(sim)
	FieldOps.enemy_offensive(sim) # Remember the older wave's pending boarders.
	check(not first.recrew.is_empty(),"an older wave has a pending real re-crew job")
	var strength:float=first.strength
	next_wave(sim)
	var second:Dictionary=state.latest
	var second_strength:float=second.strength
	check(not first.recrew.is_empty(),"launching the next wave preserves the older boarding job")
	for i in 30*30:
		sim.tick(DT)
		if hull.has("recrewed_as") or sim.result!="":break
	var fresh:Dictionary=sim.get_unit(int(hull.get("recrewed_as",-1)))
	check(not fresh.is_empty() and sim.alive(fresh) and fresh.team==1,"the older wave completes re-crewing through ordinary simulation ticks")
	if fresh.is_empty():return
	check(fresh.id in first.active and not fresh.id in second.active,"the new hull belongs only to its boarding section's older wave")
	check(is_equal_approx(first.strength,strength+float(fresh.hp)) and second.strength==second_strength,"re-crewed integrity updates only the older formation's strength")
	check(not fresh.orders.is_empty() and fresh.orders[-1].mode=="attack_move" and fresh.orders[-1].pos.distance_to(first.target)<8.0,"the re-crewed hull retains its own formation's objective")
	check(first.recrew.is_empty(),"completed boarding leaves no stale job")
	weaken(sim,first,fresh.id)
	FieldOps.enemy_offensive(sim)
	check(not first.active.is_empty(),"the older formation still accounts for its healthy re-crewed hull")
	fresh.hp=fresh.max_hp*0.05
	FieldOps.enemy_offensive(sim)
	check(first.active.is_empty() and not fresh.orders.is_empty() and fresh.orders[0].mode=="retreat","a re-crewed hull withdraws with its older formation when it breaks")
	check(not second.active.is_empty() and second.strength==second_strength,"the newer wave remains independent of that retreat")

func run()->void:
	independent_retreat()
	older_wave_exclusions()
	overlapping_recrew()
	print("WAVE OVERLAP: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
