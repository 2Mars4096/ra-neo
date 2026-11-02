extends SceneTree

# Lifecycle boundaries cross the work executor, real infantry movement, and
# accepted/provisional player orders. These checks do not advance build timers
# by hand or replace the actor-clearance executor.
const Sim=preload("res://scripts/simulation.gd")
const Positions=preload("res://scripts/field_positions.gd")
const Terrain=preload("res://scripts/terrain.gd")
const DT:=1.0/30.0
var checks:=0
var failures:=0

func _init()->void:call_deferred("run")

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func fixture(large:bool=false):
	var sim=Sim.new(false,5)
	sim.terrain=Terrain.new(0,{"id":"position_lifecycle","size":[256,192] if large else [96,72],
		"shore_x":250 if large else 90,"port":false,"mode":"field_ops","style":"showcase",
		"blocks":[],"woods":[],"rubble":[0,0,0,0],"mud":[0,0,0,0],"objectives":[],"roads":{}})
	sim.terrain.roadside_blocks.clear();sim.terrain.prop_blocks.clear();sim.terrain.trees.clear()
	sim.terrain.rebuild_static_index()
	sim.scenario=sim.scenario.duplicate(true);sim.scenario.autonomy=true;sim.scenario.jam_radius=0.0
	sim.objectives.clear();sim.field_ops.income_rate=0.0;sim.field_ops.started=false
	sim.field_ops.enemy_clock=10000.0;sim.enemy_clock=10000.0;sim.tactical_clock=10000.0
	sim.credits=1000.0
	sim.spawn("rifle",0,Vector2(24,36))
	sim.rebuild_spatial();sim.rebuild_actor_spatial();sim.update_visibility()
	return sim

func advance(sim,seconds:float)->void:
	for i in ceili(seconds/DT):sim.tick(DT)

func start(sim)->Dictionary:
	var unit:Dictionary=sim.units[0]
	check(sim.issue_dig([unit.id],unit.pos)==1,"lifecycle fixture accepts a real dig order")
	var site:Dictionary=sim.get_unit(int(unit.get("building_id",-1)))
	if site.is_empty():return {}
	advance(sim,2.0)
	check(float(site.position_progress)>0.0,"lifecycle fixture reaches physical work before interruption")
	return site

func claims_released(sim,unit:Dictionary,site:Dictionary,member:Dictionary)->bool:
	return not sim.actions.claims.has("actor:%d:%s"%[unit.id,member.member_id]) \
		and not sim.actions.claims.has("position:%d:work"%site.id) \
		and sim.actions.active(unit,"member:%s:task"%member.member_id).is_empty()

func hull_yield_preempts_work()->void:
	var sim=fixture()
	var unit:Dictionary=sim.units[0]
	var site:=start(sim)
	if site.is_empty():return
	var job:Dictionary=Positions.jobs(sim)[unit.id]
	var worker:Dictionary=sim.Infantry.member_by_id(unit,str(job.member))
	var before:Vector2=worker.pos
	var destination:Vector2=before+Vector2(0,-2.5)
	check(sim.Infantry.actor_clear(unit,worker,destination,sim),"hull-yield fixture supplies a physically clear escape")
	var progress:float=site.position_progress
	var funds:float=sim.credits
	worker["hull_yield"]={"spot":destination,"until":sim.time+2.5}
	sim.tick(DT)
	check(site.build_paused and is_equal_approx(site.position_progress,progress),"forced hull avoidance pauses work before another increment")
	check(not sim.Infantry.task_busy(worker) and claims_released(sim,unit,site,worker),"hull avoidance releases both actor and work claims")
	check(worker.pos.distance_to(before)>0.01 and worker.pos.distance_to(destination)<before.distance_to(destination),"ordinary infantry movement actually yields after work releases the soldier")
	advance(sim,0.5)
	check(is_equal_approx(site.position_progress,progress),"work cannot resume while the soldier still owes hull avoidance")
	check(Positions.jobs(sim).has(unit.id) and site.engineer_id==unit.id and sim.credits==funds,"yielding preserves assignment, paid materials and progress")
	advance(sim,5.0)
	check(site.position_progress>progress and Positions.jobs(sim).has(unit.id),"expired hull avoidance permits physical return and continued work")

func replacement_clears_stale_recovery()->void:
	var sim=fixture()
	var unit:Dictionary=sim.units[0]
	var old_anchor:Vector2=unit.pos
	# Recovery is an independent physical executor, not an ordinary queued move.
	# A stale record can survive a completed escape until the next tick.
	var recovery:={"pos":unit.pos+Vector2(5,0),"blocks":[],"retry_at":sim.time+0.5}
	unit[sim.SectionRecovery.KEY]=recovery.duplicate(true)
	unit["engage_shift"]=unit.pos+Vector2(4,0)
	unit["shift_until"]=sim.time+5.0
	var version:int=unit.order_version
	check(sim.issue_dig([unit.id],Vector2.INF)==0,"invalid work rejects before replacing independent recovery")
	check(unit.get(sim.SectionRecovery.KEY,{})==recovery and unit.has("engage_shift") and unit.order_version==version,"rejected work preserves recovery, spacing and accepted authority")
	check(sim.issue_dig([unit.id],unit.pos)==1,"valid work supersedes the obsolete recovery assignment")
	check(not unit.has(sim.SectionRecovery.KEY) and not unit.has("engage_shift"),"accepted work clears obsolete recovery and engage-spacing state")
	advance(sim,0.5)
	check(unit.pos.distance_to(old_anchor)<0.001,"accepted local work cannot continue the old recovery movement")
	check(Positions.jobs(sim).has(unit.id) and unit.assignment.mode=="dig","local work retains its accepted assignment after normal ticks")

func new_wreck_recovery_pauses_work()->void:
	var sim=fixture()
	var unit:Dictionary=sim.units[0]
	var site:=start(sim)
	if site.is_empty():return
	var job:Dictionary=Positions.jobs(sim)[unit.id]
	var worker:Dictionary=sim.Infantry.member_by_id(unit,str(job.member))
	var anchor:Vector2=unit.pos
	var old_body:Vector2=worker.pos
	var progress:float=site.position_progress
	var funds:float=sim.credits
	var hull:Dictionary=sim.spawn("tank",1,Vector2(70,55))
	hull.pos=anchor+Vector2(0,4);hull.facing=Vector2.UP
	sim.VehicleDamage.ensure_state(sim,hull)
	hull.hp-=sim.VehicleDamage._finish(sim,hull,hull.hp+1.0)
	sim.FieldOps.sync_obstacles(sim)
	check(hull.get("wrecked",false) and hull.hp<=0.0,"forced-recovery fixture creates a real tank wreck")
	check(not sim.terrain.traversable(anchor,"land",float(sim.definitions[unit.kind].radius)) and sim.SectionRecovery.bodies_clear(sim,unit),"wreck overlaps only the conservative section envelope, leaving actual bodies clear")
	check(unit.has(sim.SectionRecovery.KEY),"geometry publication starts actual section recovery during work")
	sim.tick(DT)
	check(site.build_paused and site.position_progress==progress and not sim.Infantry.task_busy(worker),"new physical recovery pauses progress and releases the worker before moving")
	check(claims_released(sim,unit,site,worker),"new physical recovery releases actor and work claims")
	check(unit.pos.distance_to(anchor)>0.01 and worker.pos.distance_to(old_body)>0.01,"real recovery and infantry executors can move both anchor and released worker")
	check(sim.SectionRecovery.bodies_clear(sim,unit) and Positions.jobs(sim).has(unit.id) and sim.credits==funds,"recovery keeps body clearance and retains resumable paid work")
	advance(sim,5.0)
	check(not unit.has(sim.SectionRecovery.KEY) and sim.terrain.traversable(unit.pos,"land",float(sim.definitions[unit.kind].radius)),"ordinary recovery physically clears the wreck envelope")
	check(site.position_progress>progress and Positions.jobs(sim).has(unit.id),"remaining local work resumes after actual recovery completes")

func replacement_during_real_recovery()->void:
	var sim=fixture()
	var unit:Dictionary=sim.units[0]
	var site:=start(sim)
	if site.is_empty():return
	var anchor:Vector2=unit.pos
	var earned:float=site.position_progress
	var hull:Dictionary=sim.spawn("tank",1,Vector2(70,55))
	hull.pos=anchor+Vector2(0,4);hull.facing=Vector2.UP
	sim.VehicleDamage.ensure_state(sim,hull)
	hull.hp-=sim.VehicleDamage._finish(sim,hull,hull.hp+1.0)
	sim.FieldOps.sync_obstacles(sim)
	check(unit.has(sim.SectionRecovery.KEY) and sim.SectionRecovery.bodies_clear(sim,unit),"replacement fixture has real unfinished physical recovery with clear bodies")
	check(sim.issue_dig([unit.id],anchor+Vector2(7.5,0))==1,"new local work is accepted while a real wreck still presses the section")
	var replacement:Dictionary=sim.get_unit(int(unit.get("building_id",-1)))
	if replacement.is_empty():return
	check(replacement.id!=site.id and site.build_paused and site.position_progress==earned,"new work releases the old site without losing its earned progress")
	check(unit.has(sim.SectionRecovery.KEY),"accepted work recomputes still-needed physical recovery rather than deleting it")
	sim.tick(DT)
	check(unit.pos.distance_to(anchor)>0.01 and replacement.build_paused,"the new work waits while actual wreck recovery moves its section")
	advance(sim,5.0)
	check(sim.terrain.traversable(unit.pos,"land",float(sim.definitions[unit.kind].radius)) and not unit.has(sim.SectionRecovery.KEY),"work replacement cannot strand the anchor inside a wreck envelope")
	check(replacement.position_progress>0.0 and Positions.jobs(sim).has(unit.id),"the newly accepted site receives work after physical recovery")

func displaced_goal_releases_work()->void:
	var sim=fixture()
	var unit:Dictionary=sim.units[0]
	var site:=start(sim)
	if site.is_empty():return
	var job:Dictionary=Positions.jobs(sim)[unit.id]
	var worker:Dictionary=sim.Infantry.member_by_id(unit,str(job.member))
	var body:Vector2=worker.pos
	var progress:float=site.position_progress
	var hp:float=site.hp
	# Stage the boundary state produced by an external physical relocation.
	# The retained work executor may release it, but cannot teleport the worker
	# or continue crediting work outside the section's local authority.
	unit.pos=job.goal+Vector2(sim.Infantry.Cover.LEASH+1.0,0)
	sim.rebuild_spatial();sim.rebuild_actor_spatial()
	Positions.tick(sim,DT)
	check(not Positions.jobs(sim).has(unit.id) and not unit.has("building_id"),"displacement beyond the local work leash cancels stale job authority")
	check(claims_released(sim,unit,site,worker) and not sim.Infantry.task_busy(worker),"out-of-leash cancellation frees actor, site and task channel")
	check(site.position_progress==progress and site.hp==hp and site.build_paused and site.engineer_id==-1,"out-of-leash cancellation preserves site progress and integrity")
	check(worker.pos==body,"work cancellation never teleports the displaced soldier")

func deadline_releases_claims()->void:
	var sim=fixture()
	var unit:Dictionary=sim.units[0]
	var site:=start(sim)
	if site.is_empty():return
	var job:Dictionary=Positions.jobs(sim)[unit.id]
	var worker:Dictionary=sim.Infantry.member_by_id(unit,str(job.member))
	var progress:float=site.position_progress
	var hp:float=site.hp
	var funds:float=sim.credits
	sim.time=float(job.deadline)
	sim.tick(DT)
	check(Positions.jobs(sim).is_empty() and not unit.has("building_id"),"absolute work deadline removes its job and builder attachment")
	check(claims_released(sim,unit,site,worker) and not sim.Infantry.task_busy(worker),"deadline releases actor, site and task channel ownership")
	check(site.build_paused and site.engineer_id==-1 and site.position_progress==progress and site.hp==hp,"deadline preserves earned work and integrity without finishing itself")
	check(sim.credits==funds and sim.FieldOps.resume(sim,site.id,unit.id),"timed-out free work remains explicitly resumable without payment")
	advance(sim,0.5)
	check(site.position_progress>progress,"explicit resumption after deadline performs additional physical work")

func job_limit_preserves_orders()->void:
	var sim=fixture(true)
	var unit:Dictionary=sim.units[0]
	check(sim.issue_dig([unit.id],unit.pos)==1,"capacity fixture starts its first real job")
	var site:Dictionary=sim.get_unit(int(unit.get("building_id",-1)))
	if site.is_empty():return
	var created:=1
	for i in Positions.MAX_JOBS-1:
		var point:=Vector2(52+24*(i%8),16+20*(i/8))
		var peer:Dictionary=sim.spawn("rifle",0,point)
		if not peer.is_empty() and sim.issue_dig([peer.id],peer.pos)==1:created+=1
	check(created==Positions.MAX_JOBS and Positions.jobs(sim).size()==Positions.MAX_JOBS,"capacity fixture fills the declared limit through actual dig commands")
	var candidate:Dictionary=sim.spawn("rifle",0,Vector2(24,80))
	check(not candidate.is_empty(),"capacity fixture can place one further infantry section")
	if candidate.is_empty():return
	var assignment:Dictionary=candidate.assignment.duplicate(true)
	var funds:float=sim.credits
	var count:int=sim.units.size()
	check(sim.issue_dig([candidate.id],candidate.pos)==0,"a new job beyond the cap is rejected")
	check(candidate.assignment==assignment and sim.credits==funds and sim.units.size()==count,"job-cap rejection changes no accepted order, supply or site count")
	var first_job:Dictionary=Positions.jobs(sim)[unit.id].duplicate(true)
	check(sim.issue_dig([unit.id],site.pos)==1 and Positions.jobs(sim)[unit.id]==first_job,"a duplicate current command remains idempotent at capacity")
	sim.stop([unit.id])
	check(Positions.jobs(sim).size()==Positions.MAX_JOBS-1,"cancelling one worker releases one capacity slot")
	check(sim.issue_dig([candidate.id],candidate.pos)==1 and Positions.jobs(sim).size()==Positions.MAX_JOBS,"a released job slot becomes usable without growing the cap")

func site_limit_preserves_orders()->void:
	var sim=fixture(true)
	var unit:Dictionary=sim.units[0]
	check(sim.issue_dig([unit.id],unit.pos)==1,"site-cap fixture creates a resumable local site")
	var first:Dictionary=sim.get_unit(int(unit.get("building_id",-1)))
	if first.is_empty():return
	sim.stop([unit.id])
	# Settled sites are ordinary world records. Seed completed remote defenses
	# to isolate the site cap from the independent 64-concurrent-job limit.
	var seeded:=1
	var expendable:Dictionary={}
	for i in Positions.MAX_SITES-1:
		var point:=Vector2(52+16*(i%12),12+20*(i/12))
		var site:Dictionary=sim.spawn(Positions.KIND,0,point)
		if site.is_empty():continue
		site.merge({"field_position":true,"position_stage":1,"position_progress":Positions.DIG_SECONDS,
			"position_total":Positions.DIG_SECONDS,"position_job":"dig","paid_cost":0.0,
			"build_left":0.0,"build_paused":false,"engineer_id":-1,"rotated":false},true)
		seeded+=1;expendable=site
	check(seeded==Positions.MAX_SITES,"site-cap fixture contains the declared number of live positions")
	var assignment:Dictionary=unit.assignment.duplicate(true)
	var funds:float=sim.credits
	var count:int=sim.units.size()
	var new_point:Vector2=unit.pos+Vector2(0,6)
	check(sim.issue_dig([unit.id],new_point)==0,"a new site beyond the live-site cap is rejected")
	check(unit.assignment==assignment and sim.credits==funds and sim.units.size()==count,"site-cap rejection preserves authority, supply and world records")
	check(sim.FieldOps.resume(sim,first.id,unit.id),"an existing unfinished position remains resumable at the site cap")
	sim.stop([unit.id])
	expendable.hp=0.0
	check(sim.issue_dig([unit.id],new_point)==1,"destroyed positions release their slot for one replacement site")
	check(sim.units.filter(func(item):return sim.alive(item) and item.get("field_position",false)).size()==Positions.MAX_SITES,"replacement never exceeds the live-site cap")

func provisional_and_queued_orders(queued:bool)->void:
	var sim=fixture()
	var unit:Dictionary=sim.units[0]
	var site:=start(sim)
	if site.is_empty():return
	var job:Dictionary=Positions.jobs(sim)[unit.id]
	var worker:Dictionary=sim.Infantry.member_by_id(unit,str(job.member))
	var assignment:Dictionary=unit.assignment.duplicate(true)
	var earned:float=site.position_progress
	sim.click_slots=0
	check(sim.issue([unit.id],Vector2(98,66),"move",queued)==1 and unit.orders[0].has("slot"),"invalid replacement remains provisional while placement is pending")
	sim.resolve_slots()
	check(unit.assignment==assignment and Positions.jobs(sim).has(unit.id) and unit.orders.is_empty(),"rejected provisional order preserves the accepted work assignment")
	advance(sim,0.5)
	check(site.position_progress>earned,"work continues after rejected provisional placement")
	var destination:=Vector2(24,52)
	check(sim.issue([unit.id],destination,"move",queued)==1 and unit.orders[0].has("slot"),"valid replacement also waits for actual placement acceptance")
	sim.resolve_slots()
	var stopped:float=site.position_progress
	sim.tick(DT)
	check(unit.assignment.mode=="move" and not Positions.jobs(sim).has(unit.id),"accepted movement ends the superseded work job before movement proceeds")
	check(claims_released(sim,unit,site,worker) and site.build_paused and site.position_progress==stopped,"movement replacement releases work claims and preserves progress")
	for tick in 600:
		sim.tick(DT)
		if unit.orders.is_empty():break
	check(unit.pos.distance_to(destination)<=1.0 and unit.orders.is_empty(),"replacement completes through ordinary movement without stale work ownership")

func run()->void:
	hull_yield_preempts_work()
	replacement_clears_stale_recovery()
	new_wreck_recovery_pauses_work()
	replacement_during_real_recovery()
	displaced_goal_releases_work()
	deadline_releases_claims()
	job_limit_preserves_orders()
	site_limit_preserves_orders()
	provisional_and_queued_orders(false)
	provisional_and_queued_orders(true)
	print("FIELD POSITION LIFECYCLE: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
