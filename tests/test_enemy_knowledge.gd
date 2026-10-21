extends SceneTree
# Fog-honest strategic planning and FPV locks on the real Harbor terrain.
# Visibility comes from real observers and update_visibility, not forced flags.
const Sim=preload("res://scripts/simulation.gd")
const FieldOps=preload("res://scripts/field_ops.gd")
const StructureDamage=preload("res://scripts/structure_damage.gd")
const BASE:=Vector2(300,640)
const DT:=1.0/30.0
var checks:=0
var failures:=0

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func _init()->void:call_deferred("run")

func site(sim,kind:String,pos:Vector2)->Dictionary:
	var before:int=sim.units.size()
	FieldOps.spawn_prepared_works(sim,[{"kind":kind,"position":pos}],0)
	check(sim.units.size()==before+1,"prepared player site spawned: "+kind)
	return sim.units.back()

func site_memory()->void:
	var sim=Sim.new(false,6)
	check(sim.credits==3200.0 and sim.field_ops.income_rate==6.0,"testing economy is unchanged")
	var known:=site(sim,"forward_supply_point",BASE)
	var hidden:=site(sim,"forward_supply_point",Vector2(280,720))
	sim.update_visibility()
	check(not known.seen_by[1] and not hidden.seen_by[1],"both forward sites start unseen")
	check(FieldOps.wave_target(sim)==sim.field_ops.insertion,"unseen forward sites do not redirect the public landing-zone attack")
	var scout:Dictionary=sim.spawn("drone",1,known.pos+Vector2(0,4))
	sim.update_visibility()
	check(known.seen_by[1] and not hidden.seen_by[1],"real reconnaissance sees only the first site")
	check(FieldOps.wave_target(sim)==known.pos,"the observed site takes priority over the newer hidden site")
	var remembered:Vector2=known.pos
	var observed_at:float=sim.time
	scout.hp=0.0
	sim.update_visibility()
	check(not known.seen_by[1],"destroying the only scout removes live knowledge")
	known.hp=0.0 # Demolition in fog must not notify the opposing planner.
	sim.update_visibility()
	check(FieldOps.wave_target(sim)==remembered,"a remembered site keeps its last observed position after unseen destruction")
	sim.time=observed_at+FieldOps.SITE_MEMORY_SECONDS
	check(FieldOps.wave_target(sim)==remembered,"site memory lasts through its exact time boundary")
	sim.time+=0.01
	check(FieldOps.wave_target(sim)==sim.field_ops.insertion,"stale memory expires without inspecting hidden live structures")
	sim.spawn("drone",1,hidden.pos+Vector2(0,4))
	sim.update_visibility()
	check(hidden.seen_by[1] and FieldOps.wave_target(sim)==hidden.pos,"new reconnaissance can discover the relocated forward site")
	# Refresh is tied to an actual visibility sample, not wave_target calls.
	sim.time+=FieldOps.SITE_MEMORY_SECONDS-1.0
	sim.update_visibility()
	sim.time+=2.0
	check(FieldOps.wave_target(sim)==hidden.pos,"continued observation refreshes the contact lifetime")

func observed_completion()->void:
	var sim=Sim.new(false,6)
	var forward:=site(sim,"forward_supply_point",BASE)
	forward.build_left=10.0
	var other:=site(sim,"aid_post",BASE+Vector2(14,0))
	var scout:Dictionary=sim.spawn("drone",1,BASE+Vector2(7,0))
	sim.update_visibility()
	check(forward.seen_by[1] and other.seen_by[1],"observer sees both construction sites")
	var centroid:Vector2=(forward.pos+other.pos)/2.0
	check(FieldOps.wave_target(sim)==centroid,"an unfinished forward site is remembered without completed-base priority")
	scout.hp=0.0
	sim.update_visibility()
	forward.build_left=0.0
	check(FieldOps.wave_target(sim)==centroid,"hidden completion does not update remembered priority")
	sim.spawn("drone",1,BASE+Vector2(7,0))
	sim.update_visibility()
	check(FieldOps.wave_target(sim)==forward.pos,"a new sighting observes completion and enables forward-base priority")

func observed_demolition()->void:
	for seen in [true,false]:
		var sim=Sim.new(false,6)
		var forward:=site(sim,"forward_supply_point",BASE)
		var scout:Dictionary=sim.spawn("drone",1,BASE+Vector2(0,4))
		sim.update_visibility()
		check(forward.seen_by[1] and FieldOps.wave_target(sim)==forward.pos,"reconnaissance records the site before its destruction")
		if not seen:
			scout.hp=0.0
			sim.update_visibility()
		StructureDamage.explosion(sim,forward.pos,8.0,10000.0,0.0)
		check(not sim.alive(forward),"ordinary blast damage destroys the remembered site")
		sim.update_visibility()
		if seen:
			check(FieldOps.wave_target(sim)==sim.field_ops.insertion and sim.field_ops.enemy_sites.is_empty(),"an observed destroyed site is forgotten on the next visibility sample")
		else:
			check(FieldOps.wave_target(sim)==forward.pos,"destruction under fog preserves the remembered site")
			sim.spawn("drone",1,BASE+Vector2(0,4))
			sim.update_visibility()
			check(FieldOps.wave_target(sim)==sim.field_ops.insertion and sim.field_ops.enemy_sites.is_empty(),"reconnaissance of the empty remembered position clears stale knowledge")

func swarm_acquisition(team:int)->void:
	var sim=Sim.new(false,6)
	var known:Dictionary=sim.spawn("rifle",1-team,BASE)
	var hidden:Dictionary=sim.spawn("tank",1-team,BASE+Vector2(-20,0))
	sim.update_visibility()
	check(FieldOps.launch_swarm(sim,BASE,4,team).is_empty(),"team %d cannot launch at an entirely unseen cluster" % team)
	var scout:Dictionary=sim.spawn("drone",team,BASE+Vector2(18,0))
	sim.update_visibility()
	check(known.seen_by[team] and not hidden.seen_by[team],"team %d sees one victim but not its neighboring tank" % team)
	check(hidden.pos.distance_to(BASE)<FieldOps.SWARM_TARGET_RADIUS,"hidden neighbor lies inside the strike area")
	var ids:Array=FieldOps.launch_swarm(sim,BASE,4,team)
	check(ids.size()==4,"team %d can launch on an observed target" % team)
	check(ids.all(func(id):return sim.get_unit(id).strike_target==known.id),"team %d assigns no drone to the unseen higher-priority vehicle" % team)
	if team==1:
		check(sim.events.any(func(e):return e.type=="warning" and "FPV SWARM INBOUND" in str(e.text) and e.get("pos",Vector2.INF)==BASE),"enemy strike alert locates the threatened player area")
	# Losing the observer after a valid launch must not cancel acquired guidance.
	scout.hp=0.0
	sim.update_visibility()
	check(not known.seen_by[team],"team %d loses team vision while its FPVs are still at standoff" % team)
	for id in ids:
		var drone:Dictionary=sim.get_unit(id)
		var before:Vector2=drone.pos
		sim.fpv_strike(drone,sim.definitions.fpv_drone,DT)
		check(sim.alive(drone) and drone.strike_target==known.id and drone.pos!=before,"team %d retains already acquired flight guidance" % team)

func replacement_lock(team:int)->void:
	var sim=Sim.new(false,6)
	var old:Dictionary=sim.spawn("rifle",1-team,BASE+Vector2(0,30))
	var replacement:Dictionary=sim.spawn("tank",1-team,BASE+Vector2(25,0))
	var drone:Dictionary=sim.spawn("fpv_drone",team,BASE)
	drone.strike_target=old.id
	old.hp=0.0
	sim.update_visibility()
	check(not replacement.seen_by[team] and drone.pos.distance_to(replacement.pos)<40.0,"replacement is within retarget range but beyond the drone's own sight")
	check(sim.fpv_retarget(drone).is_empty(),"team %d cannot replace a dead lock with an unseen unit" % team)
	var hp:float=replacement.hp
	sim.fpv_strike(drone,sim.definitions.fpv_drone,DT)
	check(not sim.alive(drone) and drone.strike_target==-1 and replacement.hp==hp,"team %d expires an orphan FPV instead of homing onto a hidden neighbor" % team)
	var fresh:Dictionary=sim.spawn("fpv_drone",team,BASE)
	fresh.strike_target=old.id
	sim.spawn("drone",team,replacement.pos+Vector2(0,3))
	sim.update_visibility()
	check(replacement.seen_by[team],"a real spotter reveals the replacement")
	sim.fpv_strike(fresh,sim.definitions.fpv_drone,DT)
	check(sim.alive(fresh) and fresh.strike_target==replacement.id,"team %d can acquire a newly observed replacement" % team)

func run()->void:
	site_memory()
	observed_completion()
	observed_demolition()
	for team in [0,1]:
		swarm_acquisition(team)
		replacement_lock(team)
	print("ENEMY KNOWLEDGE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
