extends RefCounted

# One continuous, deterministic local encounter on the authored Harbor map.
# Only the initial forces and strategic clocks are controlled. Orders, actor
# movement, fire, releases, service, work and payment use the normal executors.
const Sim=preload("res://scripts/simulation.gd")
const DT:=1.0/30.0
const SITE:=Vector2(230,660)
const SMOKE_POINT:=Vector2(234,665)
var sim
var units:Dictionary={}
var site:Dictionary={}
var request:Dictionary={}
var phase:="setup"
var phase_started:=0.0
var errors:Array[String]=[]
var metrics:Dictionary={}
var initial_stock:Dictionary={}
var initial_supply:=0.0
var reserve_home:=Vector2.ZERO
var reserve_assignment:Dictionary={}
var initial_geometry:Dictionary={}
var paused_progress:=0.0
var upgrade_progress:=0.0
var _automatic_enabled:=false

func setup(existing_sim=null)->bool:
	# Match Battle's populated initialization, including monotonic actor IDs and
	# ID-staggered decision schedules, before selecting the local test forces.
	sim=existing_sim if existing_sim!=null else Sim.new(true,Sim.Scenarios.index_for_id("black_sea_harbor"))
	if str(sim.scenario.get("id",""))!="black_sea_harbor":
		_error("The integrated fixture requires the actual Harbor scenario")
		return false
	# Native review supplies Battle's untouched Harbor world. Retain its terrain,
	# renderer-facing IDs and authored geometry when replacing scenario forces.
	for old in sim.units:sim.actions.cancel_unit(old,sim.time,"fixture_setup")
	sim.units.clear();sim.units_by_id.clear()
	sim.FieldOps.sync_obstacles(sim)
	sim.scenario=sim.scenario.duplicate(true)
	sim.scenario.jam_radius=0.0
	sim.field_ops.income_rate=0.0;sim.field_ops.started=false
	sim.field_ops.enemy_clock=10000.0;sim.enemy_clock=10000.0;sim.tactical_clock=10000.0
	sim.credits=1000.0
	sim.combat_rng.seed=47291
	initial_geometry={"blocks":sim.terrain.blocks.size(),"props":sim.terrain.prop_blocks.size(),"trees":sim.terrain.trees.size(),"size":sim.terrain.world_size}
	units={"defender":sim.spawn("rifle",0,SITE),"engineer":sim.spawn("engineer",0,SITE+Vector2(-6,0)),
		"reserve":sim.spawn("rifle",0,SITE+Vector2(-16,-6)),"enemy":sim.spawn("rifle",1,SITE+Vector2(0,10))}
	for name in units:
		if units[name].is_empty():_error("Could not seed Harbor "+name)
	if not errors.is_empty():return false
	var ids:Array=[]
	for u in units.values():ids.append(u.id)
	sim.stop(ids)
	sim.set_fire_policy([units.engineer.id,units.reserve.id,units.enemy.id],"hold")
	sim.rebuild_spatial();sim.rebuild_actor_spatial();sim.update_visibility()
	initial_supply=sim.credits
	reserve_home=units.reserve.pos
	reserve_assignment=units.reserve.assignment.duplicate(true)
	for u in units.values():
		for member in u.members:initial_stock[_member_key(u,member)]=member.throwables.duplicate(true)
	metrics={"opening_shots":0,"covering_shots":0,"enemy_shots":0,"reserve_shots":0,"combined_roles":false,
		"worker_moved":false,"frag_releases":0,"smoke_releases":0,"frag_bursts":0,"smoke_deployed":0,
		"reserve_moved":false,"reserve_delivered":false,"max_service":0.0,"claim_samples":0,"claim_errors":[],
		"released_members":{},"commands":{},"same_site":true,"smoke_cancel_unspent":false,"smoke_released_after_replacement":false}
	phase_started=sim.time
	return true

func start_defense()->bool:
	phase="defense";phase_started=sim.time
	metrics.commands.dig=sim.issue_dig([units.defender.id],SITE)
	for candidate in sim.units:
		if candidate.get("field_position",false):site=candidate;break
	sim.set_fire_policy([units.reserve.id],"free")
	metrics.commands.reserve=sim.set_reserve([units.reserve.id],true)
	metrics.commands.backup=sim.request_backup([units.engineer.id])
	request=sim.SupportRequests.request_for(sim,units.engineer)
	return int(metrics.commands.dig)==1 and int(metrics.commands.reserve)==1 and int(metrics.commands.backup)==1 and not site.is_empty()

# Call once the automatic frag is a world projectile. This accepted replacement
# releases the digger, and a cancelled smoke preparation proves no early debit.
func begin_smoke()->bool:
	phase="smoke";phase_started=sim.time
	paused_progress=float(site.get("position_progress",0.0))
	sim.stop([units.defender.id])
	sim.Throwables.set_policy(sim,[units.defender.id],"manual")
	# The requesting engineer also protects the arriving reserve once the
	# opening frag is released and the opposing section returns fire.
	sim.set_fire_policy([units.enemy.id,units.engineer.id],"free")
	var before:=stock(units.defender,"smoke")
	metrics.commands.cancelled_smoke=sim.issue_throw([units.defender.id],"smoke",SMOKE_POINT)
	sim.stop([units.defender.id])
	metrics.smoke_cancel_unspent=stock(units.defender,"smoke")==before
	metrics.commands.smoke=sim.issue_throw([units.defender.id],"smoke",SMOKE_POINT)
	return int(metrics.commands.cancelled_smoke)==1 and int(metrics.commands.smoke)==1

# A second replacement after release cannot recall either released payload.
func resume_work()->bool:
	phase="work";phase_started=sim.time
	metrics.commands.resume=sim.issue_dig([units.defender.id],SITE)
	metrics.same_site=int(units.defender.get("building_id",-1))==int(site.id)
	metrics.smoke_released_after_replacement=sim.throwables.projectiles.any(func(p):return p.payload=="smoke") or not sim.throwables.smoke.is_empty()
	return int(metrics.commands.resume)==1

func begin_upgrade()->bool:
	phase="upgrade";phase_started=sim.time
	metrics.commands.upgrade=sim.upgrade_position([units.engineer.id],site.id)
	metrics.commands.duplicate_upgrade=sim.upgrade_position([units.engineer.id],site.id)
	return int(metrics.commands.upgrade)==1 and int(metrics.commands.duplicate_upgrade)==1

func interrupt_upgrade()->bool:
	upgrade_progress=float(site.position_progress)
	sim.stop([units.engineer.id])
	return site.build_paused and not sim.FieldPositions.jobs(sim).has(units.engineer.id)

func resume_upgrade()->bool:
	metrics.commands.resume_upgrade=sim.upgrade_position([units.engineer.id],site.id)
	return int(metrics.commands.resume_upgrade)==1

func tick()->void:
	var covering:Array=[]
	var worker_before:Dictionary={}
	for member in units.defender.members:
		if not str(member.get("cover_for","")).is_empty():covering.append({"id":member.member_id,"pos":member.pos})
		if member.get("task_kind","")=="dig":worker_before={"id":member.member_id,"pos":member.pos}
	sim.events.clear()
	sim.tick(DT)
	if not worker_before.is_empty():
		var worker:Dictionary=sim.Infantry.member_by_id(units.defender,worker_before.id)
		metrics.worker_moved=bool(metrics.worker_moved) or worker.pos.distance_to(worker_before.pos)>0.001
	var workers:=0;var throwers:=0;var partners:=0
	for member in units.defender.members:
		if member.get("task_kind","")=="dig":workers+=1
		if member.get("task_kind","")=="throw":throwers+=1
		if not str(member.get("cover_for","")).is_empty():partners+=1
	metrics.combined_roles=bool(metrics.combined_roles) or (workers==1 and throwers==1 and partners==1)
	for event in sim.events:
		match str(event.get("type","")):
			"shot":
				var origin:Vector2=event.get("from",Vector2.INF)
				if units.defender.members.any(func(m):return m.pos.distance_to(origin)<0.01):metrics.opening_shots+=1
				if covering.any(func(m):return m.pos.distance_to(origin)<0.01) and workers==1 and throwers==1:metrics.covering_shots+=1
				if units.enemy.members.any(func(m):return m.pos.distance_to(origin)<0.01):metrics.enemy_shots+=1
				if units.reserve.members.any(func(m):return m.pos.distance_to(origin)<0.01):metrics.reserve_shots+=1
			"throw_release":
				var payload:String=event.payload
				metrics[payload+"_releases"]+=1
				var key:="%d:%s:%s"%[int(event.unit),str(event.member),payload]
				metrics.released_members[key]=int(metrics.released_members.get(key,0))+1
			"grenade_burst":metrics.frag_bursts+=1
			"smoke_deployed":metrics.smoke_deployed+=1
	# Waiting for the first real rifle shot lets the covering soldier acquire a
	# target before he is relied on by the 1.1 second automatic preparation.
	if phase=="defense" and not _automatic_enabled and int(metrics.opening_shots)>0:
		metrics.commands.defensive=sim.Throwables.set_policy(sim,[units.defender.id],"defensive")
		_automatic_enabled=true
	metrics.reserve_moved=bool(metrics.reserve_moved) or units.reserve.pos.distance_to(reserve_home)>3.0
	if not request.is_empty():
		metrics.reserve_delivered=bool(metrics.reserve_delivered) or request.phase=="delivering"
		metrics.max_service=maxf(float(metrics.max_service),float(request.service_time))
	_observe_claims()
	if not site.is_empty() and int(site.position_stage)==2:phase="complete"

func _observe_claims()->void:
	metrics.claim_samples+=1
	var seen:Dictionary={}
	for action in sim.actions.actions.values():
		for claim in action.claims:
			if seen.has(claim) or int(sim.actions.claims.get(claim,-1))!=int(action.id):_claim_error("Duplicate or unowned claim "+str(claim))
			seen[claim]=true
	for claim in sim.actions.claims:
		if not seen.has(claim):_claim_error("Orphan claim "+str(claim))
	for u in units.values():
		for member in u.members:
			var task:int=int(member.get("task_action",0))
			if task<=0:continue
			var claim:="actor:%d:%s"%[int(u.id),str(member.member_id)]
			if int(sim.actions.claims.get(claim,-1))!=task:_claim_error("Task without its exclusive actor "+claim)
			if not str(member.get("cover_for","")).is_empty():_claim_error("Task actor also covers another soldier "+claim)

func _claim_error(message:String)->void:
	if message not in metrics.claim_errors:metrics.claim_errors.append(message)

func _error(message:String)->void:
	errors.append(message)

func stock(u:Dictionary,payload:String)->int:
	var count:=0
	for member in u.members:count+=int(member.get("throwables",{}).get(payload,0))
	return count

func _member_key(u:Dictionary,member:Dictionary)->String:
	return "%d:%s"%[int(u.id),str(member.member_id)]

func stock_balances()->bool:
	for u in units.values():
		for member in u.members:
			var key:=_member_key(u,member)
			for payload in ["frag","smoke"]:
				var released:int=int(metrics.released_members.get(key+":"+payload,0))
				if int(member.get("throwables",{}).get(payload,0))!=int(initial_stock[key][payload])-released:return false
	return true
