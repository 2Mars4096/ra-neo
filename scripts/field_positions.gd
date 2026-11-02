class_name FieldPositions
extends RefCounted

# A local prepared-position abstraction: no terrain excavation, new currency,
# or replenished equipment. Infantry pay with one soldier's work and lost fire.
# An engineer may reinforce the same site for the existing trench price.
const JOBS:="field_position_jobs"
const KIND:="fighting_trench"
const DIG_SECONDS:=18.0
const HASTY_HP:=120.0
const LOCAL_REACH:=8.0
const MAX_JOBS:=64
const MAX_SITES:=96
const WORK_SUPPRESSION:=0.5

static func setup(sim)->void:
	if not sim.has_meta(JOBS):sim.set_meta(JOBS,{})

static func jobs(sim)->Dictionary:
	setup(sim)
	return sim.get_meta(JOBS)

static func _error(sim,message:String)->int:
	sim.order_feedback=message
	if not sim.field_ops.is_empty():sim.field_ops.last_build_error=message
	return 0

static func _eligible(sim,u:Dictionary,upgrade:bool=false)->bool:
	return sim.alive(u) and not u.get("combat_ineffective",false) and u.kind in (["engineer"] if upgrade else ["rifle","atgm","engineer"]) and not sim.comms_blocked(u) and not sim.Garrison.inside(u) and sim.Garrison.transit(u)==""

static func _member_available(member:Dictionary)->bool:
	return float(member.get("hp",0.0))>0 and member.get("wound","") not in ["SEVERE","KIA","CREW"] and int(member.get("aiding",-1))<0 and int(member.get("task_action",0))<=0

# Public terrain stays authoritative; an aiming preview must not discover an
# unseen enemy work through its published dynamic collision rectangle.
static func _unseen_work_blocks(sim,observer:Dictionary)->Array:
	var blocks:Array=[]
	if observer.is_empty():return blocks
	for other in sim.units:
		if not sim.alive(other) or not other.get("structure",false) or other.team==observer.team:continue
		if not sim.definitions[other.kind].get("solid",true) or sim.contact_known(observer,other):continue
		blocks.append(sim.FieldOps.footprint(sim,other.kind,other.pos,other.get("rotated",false)))
	return blocks

static func _ground_reason(sim,point:Vector2,existing:int=-1,observer:Dictionary={})->String:
	if not point.is_finite():return "Choose open soil nearby"
	var rect:Rect2=sim.FieldOps.footprint(sim,KIND,point)
	var ignored_blocks:=_unseen_work_blocks(sim,observer)
	var low:=INF
	var high:=-INF
	# Sample the entire narrow site, including its edges. Roads are real authored
	# ground, so this cannot put a free fighting position across a street.
	for x in 11:
		for y in 5:
			var sample:Vector2=rect.position+rect.size*Vector2(float(x)/10.0,float(y)/4.0)
			if not sim.terrain.inside(sample) or sim.terrain.is_water(sample) or sim.terrain.blocked(sample):return "Choose clear soil"
			if sim.terrain.on_road(sample):return "Cannot dig on a road"
			var height:float=sim.terrain.height_at(sample)
			low=minf(low,height);high=maxf(high,height)
	if high-low>0.5:return "Ground is too steep"
	for blocker in sim.terrain._static_candidates("solid",point,rect.size.length()*0.5):
		if blocker.intersects(rect):return "Choose clear soil"
	for other in sim.units:
		if not sim.alive(other) or not other.get("structure",false) or other.id==existing:continue
		if not observer.is_empty() and other.team!=observer.team and not sim.contact_known(observer,other):continue
		if sim.FieldOps.footprint(sim,other.kind,other.pos,other.get("rotated",false)).intersects(rect):return "Another work occupies this site"
	# Coastline slivers and low obstacles between sample points still obstruct.
	for i in 19:
		var x:float=lerpf(rect.position.x,rect.end.x,float(i)/18.0)
		if not sim.terrain.segment_clear(Vector2(x,rect.position.y),Vector2(x,rect.end.y),"land",0.15,ignored_blocks):return "Choose clear soil"
	return ""

static func _worker_plan(sim,u:Dictionary,point:Vector2,known_only:bool=false)->Dictionary:
	if u.pos.distance_to(point)>LOCAL_REACH:return {}
	var rect:Rect2=sim.FieldOps.footprint(sim,KIND,point).grow(-0.84)
	var ignored_blocks:=_unseen_work_blocks(sim,u) if known_only else []
	var best:Dictionary={}
	var score:=INF
	for member in u.members:
		if not _member_available(member):continue
		var candidates:Array[Vector2]=[Vector2(clampf(member.pos.x,rect.position.x,rect.end.x),clampf(member.pos.y,rect.position.y,rect.end.y))]
		for offset in [-2.4,0.0,2.4]:candidates.append(point+Vector2(float(offset),0))
		# An occupied position can be improved from its lip without displacing
		# its defenders or making two actors share a trench slot.
		for side in [-1.0,1.0]:
			for offset in [-2.4,0.0,2.4]:candidates.append(point+Vector2(float(offset),float(side)*2.0))
		for goal in candidates:
			if goal.distance_to(u.pos)>sim.Infantry.Cover.LEASH or not sim.terrain.traversable(goal,"land",0.8,ignored_blocks):continue
			if not sim.Infantry.actor_clear(u,member,goal,sim,known_only,ignored_blocks):continue
			var distance:float=member.pos.distance_squared_to(goal)
			if distance<score:
				score=distance
				best={"member":str(member.member_id),"goal":goal}
	return best

static func _near_site(sim,point:Vector2,team:int)->Dictionary:
	for site in sim.units:
		if sim.alive(site) and site.team==team and site.get("field_position",false) and int(site.position_stage)==0 and site.pos.distance_to(point)<2.0:return site
	return {}

static func _site_busy(sim,site:Dictionary,worker:int)->bool:
	if site.has("cleared_by"):return true
	var owner:int=int(site.get("engineer_id",-1))
	return owner>=0 and owner!=worker and jobs(sim).has(owner) and sim.alive(sim.get_unit(owner))

# Repeating a still-current command acknowledges its existing worker. Choosing
# a second member while the first owns the task can route through that first
# actor, then strand the replacement after cancellation releases him to regroup.
static func _keeps_work(sim,u:Dictionary,site:Dictionary)->bool:
	var job:Dictionary=jobs(sim).get(int(u.id),{})
	if job.is_empty() or int(job.site)!=int(site.get("id",-1)) or int(u.get("building_id",-1))!=int(job.site):return false
	if int(site.get("engineer_id",-1))!=int(u.id) or int(job.version)!=int(u.order_version) or int(job.assignment)!=int(u.assignment.id):return false
	var member:Dictionary=sim.Infantry.member_by_id(u,str(job.member))
	if member.is_empty() or float(member.hp)<=0 or member.get("wound","") in ["SEVERE","KIA","CREW"]:return false
	return job.action.is_empty() or sim.actions.valid(u,job.action,sim.time)

static func dig_reason(sim,ids:Array,point:Vector2,known_only:bool=true)->String:
	if sim.field_ops.is_empty() or sim.result!="":return "Field work unavailable"
	if not point.is_finite():return "Choose open soil nearby"
	var message:="Select nearby infantry"
	for id in ids:
		var u:Dictionary=sim.get_unit(int(id))
		if not _eligible(sim,u):continue
		var existing:Dictionary=_near_site(sim,point,int(u.team))
		if _site_busy(sim,existing,u.id):message="Position already has a worker";continue
		if _keeps_work(sim,u,existing):return ""
		var reason:=_ground_reason(sim,existing.get("pos",point),int(existing.get("id",-1)),u if known_only else {})
		if reason!="":message=reason;continue
		if u.pos.distance_to(point)>LOCAL_REACH:message="Move infantry closer to the site";continue
		if _worker_plan(sim,u,existing.get("pos",point),known_only).is_empty():message="No free soldier with a clear work route";continue
		return ""
	return message

static func preview(sim,u:Dictionary,point:Vector2)->Dictionary:
	var ids:Array=[] if u.is_empty() else [int(u.id)]
	var reason:=dig_reason(sim,ids,point)
	var site:Dictionary={} if u.is_empty() else _near_site(sim,point,int(u.team))
	var location:Vector2=site.get("pos",point)
	return {"ok":reason=="","reason":reason,"site_id":int(site.get("id",-1)),
		"rect":Rect2(location-Vector2(3.5,1.0),Vector2(7.0,2.0)),
		"seconds":float(site.get("build_left",DIG_SECONDS)),"cost":0.0}

static func issue_dig(sim,ids:Array,point:Vector2)->int:
	var reason:=dig_reason(sim,ids,point,false)
	if reason!="":return _error(sim,reason)
	for id in ids:
		var u:Dictionary=sim.get_unit(int(id))
		if not _eligible(sim,u):continue
		var site:Dictionary=_near_site(sim,point,int(u.team))
		if _site_busy(sim,site,u.id):continue
		if _keeps_work(sim,u,site):
			sim.order_feedback="Preparing position"
			return 1
		if jobs(sim).size()>=MAX_JOBS and not jobs(sim).has(int(u.id)):return _error(sim,"Too many active work sites")
		var location:Vector2=site.get("pos",point)
		if _ground_reason(sim,location,int(site.get("id",-1)))!="":continue
		var plan:=_worker_plan(sim,u,location)
		if plan.is_empty():continue
		if site.is_empty():
			var count:int=sim.units.filter(func(item):return sim.alive(item) and item.get("field_position",false)).size()
			if count>=MAX_SITES:return _error(sim,"Prepared-position limit reached")
			# Non-solid zones may be prepared under their own infantry. Spawn's
			# mobile-body spacing is irrelevant to this already validated zone.
			site=sim.spawn(KIND,int(u.team),location)
			if site.is_empty():return _error(sim,"Site unavailable")
			site.pos=location;site.home=location
			site.merge({"field_position":true,"position_stage":0,"position_progress":0.0,
				"position_total":DIG_SECONDS,"position_job":"dig","paid_cost":0.0,"build_left":DIG_SECONDS,
				"build_paused":true,"engineer_id":-1,"rotated":false,"max_hp":HASTY_HP,"hp":HASTY_HP*0.2},true)
		_assign(sim,u,site,plan)
		sim.FieldOps.sync_obstacles(sim)
		sim.order_feedback="Preparing position"
		return 1
	return _error(sim,"No free soldier with a clear work route")

static func upgrade_reason(sim,ids:Array,site_id:int,known_only:bool=true)->String:
	var site:Dictionary=sim.get_unit(site_id)
	if sim.field_ops.is_empty() or sim.result!="" or not sim.alive(site) or not site.get("field_position",false) or int(site.position_stage)!=1:return "Select a hasty position"
	var message:="Select a nearby engineer"
	for id in ids:
		var u:Dictionary=sim.get_unit(int(id))
		if not _eligible(sim,u,true) or u.team!=site.team:continue
		if _site_busy(sim,site,u.id):message="Position already has a worker";continue
		if _keeps_work(sim,u,site):return ""
		if u.pos.distance_to(site.pos)>LOCAL_REACH:message="Move engineers closer to the position";continue
		if _worker_plan(sim,u,site.pos,known_only).is_empty():message="No free engineer with a clear work route";continue
		if not site.get("upgrade_paid",false):
			var funds:float=sim.credits if u.team==0 else float(sim.field_ops.get("enemy_engineer_supply",0.0))
			if funds<float(sim.definitions[KIND].cost):message="Insufficient supply";continue
		return ""
	return message

static func upgrade_preview(sim,u:Dictionary,site_id:int)->Dictionary:
	var ids:Array=[] if u.is_empty() else [int(u.id)]
	var reason:=upgrade_reason(sim,ids,site_id)
	var site:Dictionary=sim.get_unit(site_id)
	var location:Vector2=site.get("pos",Vector2.ZERO)
	var definition:Dictionary=sim.definitions.get(KIND,{})
	return {"ok":reason=="","reason":reason,"site_id":site_id,
		"rect":Rect2(location-Vector2(3.5,1.0),Vector2(7.0,2.0)),
		"seconds":float(site.get("build_left",0.0)) if site.get("upgrade_paid",false) else float(definition.get("build_seconds",10.0)),
		"cost":0.0 if site.get("upgrade_paid",false) else float(definition.get("cost",50.0))}

# Cheap UI availability query; actual local swept access is validated at commit.
static func available_worker(sim,site_id:int)->int:
	var site:Dictionary=sim.get_unit(site_id)
	if not sim.alive(site) or not site.get("field_position",false) or float(site.get("build_left",0.0))<=0:return -1
	var best:=-1
	var distance:=INF
	for u in sim.units:
		if u.team!=site.team or not _eligible(sim,u,int(site.position_stage)==1) or _site_busy(sim,site,int(u.id)):continue
		var gap:float=u.pos.distance_to(site.pos)
		if gap>LOCAL_REACH or not u.members.any(func(member):return _member_available(member)):continue
		if gap<distance:distance=gap;best=int(u.id)
	return best

static func issue_upgrade(sim,ids:Array,site_id:int)->int:
	var reason:=upgrade_reason(sim,ids,site_id,false)
	if reason!="":return _error(sim,reason)
	var site:Dictionary=sim.get_unit(site_id)
	for id in ids:
		var u:Dictionary=sim.get_unit(int(id))
		if not _eligible(sim,u,true) or u.team!=site.team or _site_busy(sim,site,u.id):continue
		if _keeps_work(sim,u,site):
			sim.order_feedback="Reinforcing position"
			return 1
		if jobs(sim).size()>=MAX_JOBS and not jobs(sim).has(int(u.id)):return _error(sim,"Too many active work sites")
		var plan:=_worker_plan(sim,u,site.pos)
		if plan.is_empty():continue
		if not site.get("upgrade_paid",false):
			var cost:float=float(sim.definitions[KIND].cost)
			var funds:float=sim.credits if u.team==0 else float(sim.field_ops.get("enemy_engineer_supply",0.0))
			if funds<cost:continue
			if u.team==0:sim.credits-=cost
			else:sim.field_ops["enemy_engineer_supply"]=funds-cost
			site.merge({"upgrade_paid":true,"paid_cost":cost,"position_job":"upgrade","position_total":float(sim.definitions[KIND].build_seconds),"position_progress":0.0,"build_left":float(sim.definitions[KIND].build_seconds)},true)
		_assign(sim,u,site,plan)
		sim.FieldOps.sync_obstacles(sim)
		sim.order_feedback="Reinforcing position"
		return 1
	return _error(sim,"No free engineer with a clear work route")

static func _assign(sim,u:Dictionary,site:Dictionary,plan:Dictionary)->void:
	var was_recovering:bool=u.has(sim.SectionRecovery.KEY)
	# A committed local work order replaces any delegated reserve/service.
	# Do this only after placement, capability and payment preflight succeeds;
	# rejected work must keep the current assignment and its support lease.
	sim.SupportRequests.cancel_for_unit(sim,u)
	sim.FieldOps.pause_builder(sim,int(u.id))
	sim.Director.cancel(u)
	sim.cancel_preparation(u)
	sim.terrain.planning.cancel_owner(int(u.id))
	var kind:String=site.position_job
	var order:Dictionary={"mode":kind,"pos":site.pos,"target":site.id}
	sim.actions.accept_order(u,order,sim.time,"player" if u.team==0 else "ai")
	u.orders.clear();u.path.clear();u.intent=order.duplicate()
	u.erase("provisional_before");u.erase("route_pending")
	# Accepted local work supersedes earlier anchor moves. Fresh physical
	# recovery can still pause the actor below without losing the paid site.
	u.erase("engage_shift");u.erase(sim.SectionRecovery.KEY)
	u["building_id"]=site.id
	u.hold_command=false
	# Replace the obsolete recovery goal, not a still-required physical escape.
	# Replanning is needed only when the previous assignment was recovering.
	if was_recovering:
		var recovery:Dictionary=sim.SectionRecovery.plan(sim,u)
		if not recovery.is_empty():sim.SectionRecovery.begin(sim,u,recovery)
	site.engineer_id=u.id;site["last_engineer_id"]=u.id
	site.work_point=plan.goal;site.build_paused=false
	var job:Dictionary={"unit":u.id,"site":site.id,"member":plan.member,"goal":plan.goal,
		"version":u.order_version,"assignment":u.assignment.id,"kind":kind,"action":{},"resume_at":sim.time,"deadline":sim.time+120.0,"blocked":0.0}
	jobs(sim)[int(u.id)]=job
	_start_actor(sim,u,site,job)
	sim.field_ops.last_build_error=""

static func _start_actor(sim,u:Dictionary,site:Dictionary,job:Dictionary)->bool:
	var member:Dictionary=sim.Infantry.member_by_id(u,job.member)
	if not _member_available(member):return false
	var identity:String=str(member.member_id)
	var action:Dictionary=sim.actions.begin(u,job.kind,sim.time,{"channel":"member:%s:task"%identity,
		"claims":["actor:%d:%s"%[u.id,identity],"position:%d:work"%site.id],
		"target":{"site":site.id,"member":identity,"pos":job.goal},"deadline":job.deadline,"reason":"preparing_position"})
	if action.is_empty():return false
	sim.actions.transition(u,action,"preparing",sim.time,"preparing_position")
	job.action=action
	member["task_action"]=action.id;member["task_kind"]=job.kind
	sim.Infantry.cancel_readiness(member);sim.Infantry.Cover.clear(member)
	member.target=-1;member.aim=0.0
	return true

static func _release_actor(sim,u:Dictionary,job:Dictionary,reason:String,complete:bool=false)->void:
	var action:Dictionary=job.get("action",{})
	if not action.is_empty():
		if complete:sim.actions.complete(u,action,sim.time,reason)
		else:sim.actions.cancel(u,action,sim.time,reason)
	var member:Dictionary=sim.Infantry.member_by_id(u,str(job.member))
	if not member.is_empty() and int(member.get("task_action",0))==int(action.get("id",-1)):
		member.erase("task_action");member.erase("task_kind")
		member.travel=0.0;member.speed=0.0
		if member.hp>0:member.state="HOLDING"
	job.action={}

static func cancel_worker(sim,u:Dictionary,reason:String="order_replaced")->void:
	if u.is_empty() or not jobs(sim).has(int(u.id)):return
	var job:Dictionary=jobs(sim)[int(u.id)]
	_release_actor(sim,u,job,reason)
	var site:Dictionary=sim.get_unit(int(job.site))
	if not site.is_empty() and int(site.get("engineer_id",-1))==int(u.id):
		site.engineer_id=-1;site.build_paused=true
		site.state="WORK PAUSED" if sim.alive(site) else site.state
	if int(u.get("building_id",-1))==int(job.site):u.erase("building_id")
	jobs(sim).erase(int(u.id))

static func _safe(sim,u:Dictionary,member:Dictionary)->bool:
	# The shared task lock must not prevent a soldier from yielding to a hull
	# or following a section displaced by new wreck geometry.
	if sim.time<float(member.get("hull_yield",{}).get("until",-INF)) or u.has(sim.SectionRecovery.KEY):return false
	if maxf(float(u.suppression),float(member.get("suppression",0.0)))>WORK_SUPPRESSION or sim.time-float(u.last_hit)<1.5:return false
	var threat:Dictionary=sim.get_unit(int(u.get("target",-1)))
	if not sim.alive(threat) or not sim.contact_known(u,threat):return true
	# Work under contact needs an actually ready, permitted weapon and a lane.
	for peer in u.members:
		if peer.member_id==member.member_id:continue
		if sim.Coordination.can_cover(u,peer,sim,threat):return true
	return false

static func tick(sim,dt:float)->void:
	if sim.result!="" or sim.field_ops.is_empty() or dt<=0:return
	for unit_id in jobs(sim).keys():
		var job:Dictionary=jobs(sim)[unit_id]
		var u:Dictionary=sim.get_unit(int(unit_id))
		var site:Dictionary=sim.get_unit(int(job.site))
		if not sim.alive(u) or not sim.alive(site) or u.get("combat_ineffective",false) or int(u.get("order_version",-1))!=int(job.version) or int(u.get("assignment",{}).get("id",-1))!=int(job.assignment) or int(u.get("building_id",-1))!=int(job.site) or sim.time>=float(job.deadline):
			cancel_worker(sim,u,"work_interrupted")
			continue
		var member:Dictionary=sim.Infantry.member_by_id(u,job.member)
		if member.is_empty() or member.hp<=0 or member.get("wound","") in ["SEVERE","KIA","CREW"]:
			cancel_worker(sim,u,"member_lost")
			continue
		if u.pos.distance_to(job.goal)>sim.Infantry.Cover.LEASH:
			cancel_worker(sim,u,"work_out_of_reach")
			continue
		if not _safe(sim,u,member) or int(member.get("aiding",-1))>=0:
			_release_actor(sim,u,job,"work_unsafe")
			job.resume_at=sim.time+0.4
			site.build_paused=true;site.state="WAITING FOR COVER"
			u.reason="Work paused"
			continue
		if sim.time<float(job.resume_at):continue
		if job.action.is_empty():
			if not _start_actor(sim,u,site,job):continue
		elif not sim.actions.valid(u,job.action,sim.time):
			cancel_worker(sim,u,"work_interrupted")
			continue
		member.travel=0.0;member.speed=0.0
		site.build_paused=false
		if member.pos.distance_to(job.goal)>0.12:
			var speed:float=float(sim.definitions[u.kind].speed)*0.7*sim.terrain.ground_speed(member.pos,"infantry")
			if member.get("wound","")=="LIGHT":speed*=sim.Infantry.LIGHT_SPEED
			var next:Vector2=member.pos.move_toward(job.goal,speed*dt)
			if sim.Infantry.actor_clear(u,member,next,sim):
				var old:Vector2=member.pos
				member.travel=member.pos.distance_to(next);member.speed=member.travel/dt
				member.facing=(next-member.pos).normalized();member.pos=next
				sim.relocate_actor(u,member,old)
				job.blocked=0.0
			else:job.blocked+=dt
			member.state="MOVING TO POSITION";member.posture="STANDING"
			site.state="WAITING FOR WORKER"
			if float(job.blocked)>2.0:cancel_worker(sim,u,"work_route_blocked")
			continue
		if job.action.phase!="executing":sim.actions.transition(u,job.action,"executing",sim.time,"digging" if job.kind=="dig" else "reinforcing")
		var used:float=minf(dt,float(site.build_left))
		site.build_left=maxf(0.0,float(site.build_left)-used)
		site.position_progress=float(site.position_total)-float(site.build_left)
		var capacity:float=HASTY_HP*0.8 if job.kind=="dig" else float(sim.definitions[KIND].hp)-HASTY_HP
		var earned:float=capacity*used/float(site.position_total)
		if job.kind=="upgrade":site.max_hp=minf(float(sim.definitions[KIND].hp),float(site.max_hp)+earned)
		site.hp=minf(float(site.max_hp),float(site.hp)+earned)
		member.state="DIGGING" if job.kind=="dig" else "REINFORCING"
		member.posture="CROUCHED"
		u.state=member.state;u.reason="Preparing position" if job.kind=="dig" else "Reinforcing position"
		site.state=member.state
		if float(site.build_left)<=0:
			site.position_stage=1 if job.kind=="dig" else 2
			site.state="HASTY POSITION" if job.kind=="dig" else "REINFORCED POSITION"
			site.build_paused=false;site.engineer_id=-1
			_release_actor(sim,u,job,"position_ready",true)
			if int(u.get("building_id",-1))==int(site.id):u.erase("building_id")
			jobs(sim).erase(unit_id)
			u.reason="Position prepared" if job.kind=="dig" else "Position reinforced"
			sim.FieldOps.sync_obstacles(sim)
			if u.team==0:sim.events.append({"type":"warning","text":"Position prepared" if job.kind=="dig" else "Position reinforced","notice":"low"})

# Existing site's Resume button can hand an unfinished job to a compatible
# nearby section. It never replenishes time-only work or charges twice.
static func resume(sim,site_id:int,worker_id:int=-1)->bool:
	var site:Dictionary=sim.get_unit(site_id)
	if not sim.alive(site) or not site.get("field_position",false):return false
	var ids:Array=[worker_id] if worker_id>=0 else []
	if worker_id<0:
		for u in sim.units:
			if u.team==site.team and _eligible(sim,u,int(site.position_stage)==1):ids.append(u.id)
	return (issue_dig(sim,ids,site.pos) if int(site.position_stage)==0 else issue_upgrade(sim,ids,site_id))>0
