class_name SupportRequests
extends RefCounted

# M1 dispatches an explicitly delegated, existing infantry reserve. A request
# owns one provider lease; movement is a child of that provider's assignment.
const Infantry=preload("res://scripts/infantry.gd")
const Director=preload("res://scripts/tactical_director.gd")
const TERMINAL:=["completed","cancelled","unavailable","expired"]
const MAX_REQUESTS:=32
const MAX_RESERVES:=64
const MATCH_CANDIDATES:=12
const REQUEST_SECONDS:=8.0
const LEASE_SECONDS:=25.0
const RETURN_SECONDS:=20.0
const SERVICE_SECONDS:=4.0
const LOCAL_COMMS:=14.0
const RESERVE_REACH:=36.0
const SUPPORT_REACH:=12.0
const RETRY_SECONDS:=4.0
const HISTORY_SECONDS:=15.0
const REVIEW_SECONDS:=0.25

static func setup(sim)->void:
	sim.support_requests={"next_id":1,"requests":{},"reserves":{},"retry_after":{}}

static func _state(sim)->Dictionary:
	if sim.support_requests.is_empty():setup(sim)
	return sim.support_requests

static func owns_maneuver(u:Dictionary)->bool:
	return not u.get("support_task",{}).is_empty()

static func set_reserve(sim,ids:Array,enabled:bool)->int:
	if sim.result!="":return 0
	var state:=_state(sim)
	var count:=0
	for id in ids:
		var u:Dictionary=sim.get_unit(int(id))
		if not _infantry(sim,u) or sim.comms_blocked(u):continue
		if enabled and not state.reserves.has(u.id) and state.reserves.size()>=MAX_RESERVES:continue
		u["reserve_enabled"]=enabled
		if enabled:state.reserves[u.id]=true
		else:
			state.reserves.erase(u.id)
			var task:Dictionary=u.get("support_task",{})
			var request:Dictionary=state.requests.get(task.get("request",-1),{})
			if not request.is_empty() and request.phase not in TERMINAL:
				_start_return(sim,request,"cancelled","Reserve assignment ended")
		count+=1
		if not owns_maneuver(u):u["backup_status"]="Reserve ready" if enabled else "Reserve disabled"
	if count>0:sim.order_feedback="RESERVE • %d section%s %s"%[count,"" if count==1 else "s","available" if enabled else "released"]
	else:sim.order_feedback="RESERVE • Select a connected infantry section"
	return count

static func request_backup(sim,ids:Array)->int:
	if sim.result!="":return 0
	var state:=_state(sim)
	var count:=0
	for id in ids:
		var sender:Dictionary=sim.get_unit(int(id))
		if not _infantry(sim,sender) or sender.get("combat_ineffective",false):continue
		# A direct request must be communicated. Accepted leases have their own
		# local fallback and survive a later loss of the command link.
		if sim.comms_blocked(sender):
			sender["backup_status"]="Backup unavailable · radio lost"
			continue
		var current:=request_for(sim,sender)
		if not current.is_empty() and current.phase not in TERMINAL:
			count+=1
			continue
		if sim.time<float(state.retry_after.get(sender.id,-INF)):
			sender["backup_status"]="Backup unavailable · retry shortly"
			continue
		_trim(sim)
		if state.requests.size()>=MAX_REQUESTS:
			sender["backup_status"]="Backup unavailable · request limit"
			continue
		var observation:=_observation(sim,sender)
		var request:Dictionary={"id":int(state.next_id),"generation":1,"sender":int(sender.id),
			"sender_version":int(sender.order_version),"sender_assignment":int(sender.assignment.get("id",0)),
			"team":int(sender.team),"origin":sender.pos,"observation":observation,
			"created":sim.time,"expires":sim.time+REQUEST_SECONDS,"phase":"requested",
			"provider":-1,"review_at":sim.time,"service_time":0.0,"reason":"Requesting nearby backup"}
		state.next_id+=1
		state.requests[request.id]=request
		sender["backup_request"]=request.id
		sender["backup_status"]=request.reason
		count+=1
		_notice(sim,sender,"BACKUP • Requested")
	if count>0:sim.order_feedback="BACKUP • %d request%s"%[count,"" if count==1 else "s"]
	else:sim.order_feedback="BACKUP • No connected section ready to request help"
	return count

static func request_for(sim,u:Dictionary)->Dictionary:
	return _state(sim).requests.get(int(u.get("backup_request",-1)),{})

# Called only after a replacement order is accepted, never for a provisional
# destination. Tick's version checks provide the same guarantee to other APIs.
static func cancel_for_unit(sim,u:Dictionary,reason:String="order_replaced")->void:
	var state:=_state(sim)
	u["reserve_enabled"]=false
	state.reserves.erase(u.id)
	for request in state.requests.values():
		if request.phase in TERMINAL:continue
		if int(request.provider)==int(u.id):
			_finish(sim,request,"cancelled",reason,false)
		elif int(request.sender)==int(u.id):
			_end_request(sim,request,"cancelled","Request replaced")

static func tick(sim,dt:float)->void:
	if dt<=0.0 or not is_finite(dt):return
	var state:=_state(sim)
	var ids:Array=state.requests.keys()
	ids.sort()
	for id in ids:
		var request:Dictionary=state.requests[id]
		if request.phase in TERMINAL:continue
		_tick_request(sim,request,dt)
	_trim(sim)

static func _tick_request(sim,request:Dictionary,dt:float)->void:
	var sender:Dictionary=sim.get_unit(request.sender)
	if not _sender_current(sim,sender,request):
		_end_request(sim,request,"cancelled","Request replaced" if sim.alive(sender) else "Requesting section lost")
		if request.phase in TERMINAL:return
	if request.provider<0:
		if sim.time>=float(request.expires):
			_finish(sim,request,"expired","Backup request expired")
		elif sim.time>=float(request.review_at):
			request.review_at=sim.time+REVIEW_SECONDS
			_match(sim,request,sender)
		return
	var provider:Dictionary=sim.get_unit(request.provider)
	if not _provider_current(sim,provider,request):
		_finish(sim,request,"cancelled","Responder lost or retasked",false)
		return
	var connected:=_connected(sim,sender,provider)
	# An unacknowledged cancellation retains the exclusive claim until the
	# provider can hear it or the already accepted lease expires.
	if request.get("cancel_pending",false) and (connected or sim.time>=float(request.lease_until)):
		_start_return(sim,request,str(request.get("outcome","cancelled")),str(request.reason))
	if request.phase=="awaiting_ack":
		if connected or sim.time>=float(request.lease_until):
			_finish(sim,request,str(request.get("outcome","completed")),str(request.reason))
		return
	if request.phase in ["return_pending","returning"]:
		_tick_return(sim,request,provider,connected)
		return
	if sim.time>=float(request.lease_until):
		_start_return(sim,request,"expired","Backup lease expired")
		return
	if provider.suppression>0.82 or provider.hp<Infantry.assigned_capacity(provider)*0.35:
		_start_return(sim,request,"unavailable","Responder under pressure")
		return
	if request.phase=="accepted":
		if sim.time>=float(request.review_at):
			request.review_at=sim.time+REVIEW_SECONDS
			_plan_support(sim,request,provider)
		return
	if not provider.maneuver.is_empty() and not _our_maneuver(provider,request):
		_finish(sim,request,"cancelled","Responder maneuver changed",false)
		return
	if request.phase=="en_route":
		var gap:float=provider.pos.distance_to(request.position)
		var useful_short_stop:=false
		# The ordinary infantry executor can stop short while individual bodies
		# take firing positions. Accept a nearby physical position only if it
		# already delivers the requested lane/readiness; a wall still fails.
		if gap<=2.0 and sim.time>=float(request.review_at) and sim.terrain.planning.request("decisions",int(provider.id),"backup_arrival",1):
			request.review_at=sim.time+REVIEW_SECONDS
			useful_short_stop=useful(sim,provider,request)
		if gap<=1.0 or useful_short_stop:
			provider.path=[]
			request["actual_position"]=provider.pos
			provider.maneuver.pos=provider.pos
			provider.maneuver.arrived=true
			request.phase="delivering"
			request.review_at=sim.time
			request.last_review=sim.time
			_status(sim,request,"Checking supporting position")
		elif _stalled(sim,request,provider):
			_start_return(sim,request,"unavailable","Backup route blocked")
		return
	if request.phase=="delivering" and sim.time>=float(request.review_at):
		if not sim.terrain.planning.request("decisions",int(provider.id),"backup_useful",1):return
		var elapsed:float=minf(0.5,maxf(0.0,sim.time-float(request.last_review)))
		request.last_review=sim.time
		request.review_at=sim.time+REVIEW_SECONDS
		if useful(sim,provider,request):
			request.service_time+=elapsed
			_status(sim,request,"Backup covering")
			if request.service_time>=SERVICE_SECONDS:
				_start_return(sim,request,"completed","Backup delivered · returning")
		else:
			request.service_time=0.0
			_status(sim,request,"Backup waiting for a useful line")

static func _match(sim,request:Dictionary,sender:Dictionary)->void:
	if sender.is_empty() or not sim.terrain.planning.request("decisions",int(sender.id),"backup_match",1):return
	var state:=_state(sim)
	var candidates:Array[Dictionary]=[]
	for id in state.reserves.keys():
		var u:Dictionary=sim.get_unit(int(id))
		if not _eligible(sim,u,sender,request):continue
		candidates.append(u)
	candidates.sort_custom(func(a,b):
		var da:float=a.pos.distance_squared_to(request.origin)
		var db:float=b.pos.distance_squared_to(request.origin)
		return da<db if not is_equal_approx(da,db) else int(a.id)<int(b.id))
	for provider in candidates.slice(0,MATCH_CANDIDATES):
		var action:Dictionary=sim.actions.begin(provider,"nearby_backup",sim.time,{"channel":"support",
			"claims":["backup:request:%d"%request.id,"backup:provider:%d"%provider.id],
			"target":{"request":request.id,"generation":request.generation,"pos":request.origin},
			"deadline":sim.time+LEASE_SECONDS+RETURN_SECONDS+2.0,"reason":"backup_accepted"})
		if action.is_empty():continue
		sim.actions.transition(provider,action,"preparing",sim.time,"backup_accepted")
		request.provider=provider.id
		request.provider_version=int(provider.order_version)
		request.provider_assignment=int(provider.assignment.get("id",0))
		request.action=action.id
		request.lease_until=sim.time+LEASE_SECONDS
		request.saved={"pos":provider.pos,"hold_command":provider.hold_command}
		request.phase="accepted"
		request.review_at=sim.time
		request.progress_pos=provider.pos
		request.progress_at=sim.time
		provider["support_task"]={"request":request.id,"generation":request.generation,
			"version":request.provider_version,"assignment":request.provider_assignment}
		provider.hold_command=false
		_status(sim,request,"Backup accepted · section %d"%provider.id)
		_notice(sim,sender,"BACKUP • Section %d responding"%provider.id)
		return
	_finish(sim,request,"unavailable","No available nearby reserve")

static func _plan_support(sim,request:Dictionary,provider:Dictionary)->void:
	if not sim.terrain.planning.request("decisions",int(provider.id),"backup_position",1):return
	var points:=_positions(request)
	var cursor:int=int(request.get("candidate",0))
	if cursor>=points.size():
		_start_return(sim,request,"unavailable","No useful supporting position")
		return
	var point:Vector2=points[cursor]
	var d:Dictionary=sim.definitions[provider.kind]
	if not sim.terrain.traversable(point,"land",float(d.radius)) or not _space(sim,provider,point) or not _point_useful(sim,provider,request,point):
		request.candidate=cursor+1
		return
	if not sim.take_route_budget(provider.pos,point,false,int(provider.id),"backup_route"):
		request.review_at=sim.time
		return
	var route:Array=sim.terrain.path(provider.pos,point,"land",float(d.radius),[],sim.terrain.mobility_profile(provider.kind))
	if route.is_empty():
		request.candidate=cursor+1
		return
	if not Director.plan(sim,provider,point,"BACKUP","Moving to support",LEASE_SECONDS,route):
		request.candidate=cursor+1
		return
	provider.maneuver["support_request"]=request.id
	request.position=point
	request.phase="en_route"
	request.progress_pos=provider.pos
	request.progress_at=sim.time
	var action:Dictionary=sim.actions.actions.get(request.action,{})
	sim.actions.transition(provider,action,"executing",sim.time,"backup_en_route")
	_status(sim,request,"Backup en route")

static func useful(sim,provider:Dictionary,request:Dictionary)->bool:
	if not _infantry(sim,provider) or provider.get("fire_policy","free")=="hold":return false
	if provider.pos.distance_to(request.origin)>SUPPORT_REACH:return false
	var fact:Dictionary=request.observation
	if fact.get("source","")=="sensor" and sim.time-float(fact.observed_at)>30.0:return false
	for member in provider.members:
		var weapon:=_support_weapon(sim,provider,member,fact)
		if not Infantry.ready_to_cover(provider,member,sim.time,weapon):continue
		if not str(fact.kind).is_empty() and not sim.effective_weapon(weapon,str(fact.kind)):continue
		if _lane(sim,member.pos,fact.pos,float(sim.definitions[weapon].range)):
			return true
	return false

static func _point_useful(sim,provider:Dictionary,request:Dictionary,point:Vector2)->bool:
	var fact:Dictionary=request.observation
	for member in provider.members:
		var weapon:=_support_weapon(sim,provider,member,fact)
		if not Infantry.ready_to_cover(provider,member,sim.time,weapon):continue
		if not str(fact.kind).is_empty() and not sim.effective_weapon(weapon,str(fact.kind)):continue
		if _lane(sim,point,fact.pos,float(sim.definitions[weapon].range)):return true
	return false

# The ordinary executor uses a rifle against exposed infantry, even when its
# operator carries a loaded launcher. A copied contact supplies no reliable
# current garrison state; conservatively require rifle coverage for personnel
# and unspecified frontage instead of borrowing the launcher's range or stock.
# Do not inspect the live target here: it may have moved since the observation.
static func _support_weapon(sim,provider:Dictionary,member:Dictionary,fact:Dictionary)->String:
	var weapon:String=sim.section_weapon(provider,member)
	var kind:String=str(fact.get("kind",""))
	if weapon=="atgm" and (kind.is_empty() or kind in ["rifle","atgm","engineer"]):return "rifle"
	return weapon

static func _lane(sim,from:Vector2,to:Vector2,reach:float)->bool:
	var a:=Vector3(from.x,sim.terrain.height_at(from)+1.6,from.y)
	var b:=Vector3(to.x,sim.terrain.height_at(to)+1.6,to.y)
	return a.distance_to(b)<=reach and sim.optical_ray_clear(a,b)

static func _positions(request:Dictionary)->Array[Vector2]:
	var origin:Vector2=request.origin
	var forward:Vector2=(request.observation.pos-origin).normalized()
	if forward.length_squared()<0.01:forward=Vector2.UP
	var side:=forward.orthogonal()
	return [origin+side*6.0,origin-side*6.0,origin+forward*5.0+side*5.5,
		origin+forward*5.0-side*5.5,origin-forward*6.0,origin+forward*8.0]

static func _start_return(sim,request:Dictionary,outcome:String,reason:String)->void:
	if request.phase in TERMINAL or request.phase in ["return_pending","returning","awaiting_ack"]:return
	request.erase("cancel_pending")
	request.outcome=outcome
	request.reason=reason
	var provider:Dictionary=sim.get_unit(request.provider)
	if request.provider<0 or not _provider_current(sim,provider,request):
		_finish(sim,request,outcome,reason,false)
		return
	_clear_motion(sim,provider,request)
	request.phase="return_pending"
	request.return_deadline=sim.time+RETURN_SECONDS
	request.review_at=sim.time
	request.progress_pos=provider.pos
	request.progress_at=sim.time
	var action:Dictionary=sim.actions.actions.get(request.action,{})
	if action.get("phase","")=="preparing":sim.actions.transition(provider,action,"executing",sim.time,"backup_returning")
	sim.actions.transition(provider,action,"recovering",sim.time,"backup_returning")
	_status(sim,request,reason)

static func _tick_return(sim,request:Dictionary,provider:Dictionary,connected:bool)->void:
	var home:Vector2=request.saved.pos
	if provider.pos.distance_to(home)<=1.0:
		_clear_motion(sim,provider,request)
		provider.hold_command=bool(request.saved.hold_command)
		if connected or sim.time>=float(request.lease_until):
			_finish(sim,request,str(request.outcome),str(request.reason))
		else:
			request.phase="awaiting_ack"
			_status(sim,request,"Backup returned · awaiting radio")
		return
	if sim.time>=float(request.return_deadline):
		_finish(sim,request,"unavailable","Return route unavailable")
		return
	if request.phase=="returning":
		if _stalled(sim,request,provider):_finish(sim,request,"unavailable","Return route blocked")
		return
	if sim.time<float(request.review_at):return
	request.review_at=sim.time+REVIEW_SECONDS
	if not sim.take_route_budget(provider.pos,home,false,int(provider.id),"backup_return"):
		request.review_at=sim.time
		return
	var d:Dictionary=sim.definitions[provider.kind]
	var route:Array=sim.terrain.path(provider.pos,home,"land",float(d.radius),[],sim.terrain.mobility_profile(provider.kind))
	if route.is_empty():
		_finish(sim,request,"unavailable","Return route unavailable")
		return
	if Director.plan(sim,provider,home,"BACKUP_RETURN","Returning to reserve",RETURN_SECONDS,route):
		provider.maneuver["support_request"]=request.id
		request.phase="returning"
		request.progress_pos=provider.pos
		request.progress_at=sim.time
	else:_finish(sim,request,"unavailable","Return position occupied")

static func _end_request(sim,request:Dictionary,outcome:String,reason:String)->void:
	if request.phase in TERMINAL or request.phase in ["return_pending","returning","awaiting_ack"]:return
	var provider:Dictionary=sim.get_unit(request.provider)
	var sender:Dictionary=sim.get_unit(request.sender)
	if request.provider>=0 and _provider_current(sim,provider,request) and not _connected(sim,sender,provider) and sim.time<float(request.lease_until):
		request["cancel_pending"]=true
		request.outcome=outcome
		_status(sim,request,"Cancellation awaiting radio")
		return
	_start_return(sim,request,outcome,reason)

static func _finish(sim,request:Dictionary,outcome:String,reason:String,restore:bool=true)->void:
	if request.phase in TERMINAL:return
	var provider:Dictionary=sim.get_unit(request.provider)
	if not provider.is_empty():
		if _same_provider_assignment(provider,request):
			_clear_motion(sim,provider,request)
			if restore and sim.alive(provider):provider.hold_command=bool(request.get("saved",{}).get("hold_command",false))
			provider.reason="Reserve ready" if provider.get("reserve_enabled",false) else reason
			provider.next_decision=sim.time+1.0
		var action:Dictionary=sim.actions.actions.get(request.get("action",-1),{})
		if not action.is_empty():
			if outcome=="completed":sim.actions.complete(provider,action,sim.time,"backup_delivered")
			else:sim.actions.cancel(provider,action,sim.time,"backup_"+outcome)
		if provider.get("support_task",{}).get("request",-1)==request.id:provider.erase("support_task")
		provider["backup_status"]="Reserve ready" if provider.get("reserve_enabled",false) else reason
		if outcome!="completed":provider["reserve_available_after"]=sim.time+RETRY_SECONDS
	request.phase=outcome
	request.finished=sim.time
	request.reason=reason
	var sender:Dictionary=sim.get_unit(request.sender)
	if not sender.is_empty() and sender.get("backup_request",-1)==request.id:
		sender["backup_status"]=reason
	_state(sim).retry_after[request.sender]=sim.time+RETRY_SECONDS
	_notice(sim,sender,"BACKUP • "+reason)

static func _clear_motion(sim,provider:Dictionary,request:Dictionary)->void:
	if not _our_maneuver(provider,request):return
	var action:Dictionary=sim.actions.active(provider,"movement")
	if not action.is_empty():sim.actions.cancel(provider,action,sim.time,"backup_stage_finished")
	provider.maneuver={}
	provider.path=[]
	provider.speed_now=0.0
	provider.commit_until=0.0

static func _our_maneuver(provider:Dictionary,request:Dictionary)->bool:
	return provider.get("maneuver",{}).get("support_request",-1)==request.id

static func _stalled(sim,request:Dictionary,provider:Dictionary)->bool:
	if provider.pos.distance_to(request.progress_pos)>0.4:
		request.progress_pos=provider.pos
		request.progress_at=sim.time
	return sim.time-float(request.progress_at)>5.0

static func _sender_current(sim,sender:Dictionary,request:Dictionary)->bool:
	return sim.alive(sender) and int(sender.team)==int(request.team) and not sender.get("combat_ineffective",false) and int(sender.order_version)==int(request.sender_version) and int(sender.assignment.get("id",0))==int(request.sender_assignment)

static func _provider_current(sim,provider:Dictionary,request:Dictionary)->bool:
	if not sim.alive(provider) or int(provider.team)!=int(request.team) or provider.get("combat_ineffective",false) or not _same_provider_assignment(provider,request):return false
	var action:Dictionary=sim.actions.active(provider,"support")
	return action.get("id",-1)==request.get("action",-2) and sim.actions.valid(provider,action,sim.time)

static func _same_provider_assignment(provider:Dictionary,request:Dictionary)->bool:
	return not provider.is_empty() and int(provider.get("order_version",-1))==int(request.get("provider_version",-2)) and int(provider.get("assignment",{}).get("id",0))==int(request.get("provider_assignment",-1)) and provider.get("support_task",{}).get("request",-1)==request.id

static func _infantry(sim,u:Dictionary)->bool:
	return sim.alive(u) and not u.get("members",[]).is_empty() and sim.definitions[u.kind].domain=="land"

static func _eligible(sim,u:Dictionary,sender:Dictionary,request:Dictionary)->bool:
	if not _infantry(sim,u) or u.team!=sender.team or u.id==sender.id or not u.get("reserve_enabled",false):return false
	if u.get("combat_ineffective",false) or u.get("fire_policy","free")=="hold" or owns_maneuver(u):return false
	if not u.orders.is_empty() or not u.maneuver.is_empty() or not u.path.is_empty() or u.target>=0:return false
	if u.has("building_id") or u.has("clearing_id") or u.has("garrison_target") or u.has("wreck_recovery") or u.has("build_task"):return false
	if int(u.get("garrison",-1))>=0 or str(u.get("garrison_transit","")).length()>0:return false
	if sim.time<float(u.get("reserve_available_after",-INF)):return false
	if u.members.any(func(member):return int(member.get("task_action",-1))>0):return false
	if u.get("suppression",0.0)>0.65 or sim.time-float(u.get("last_hit",-100.0))<2.0:return false
	if u.pos.distance_to(request.origin)>RESERVE_REACH or not _connected(sim,sender,u):return false
	if not sim.actions.active(u,"unit").is_empty() or not sim.actions.active(u,"support").is_empty():return false
	var fact:Dictionary=request.observation
	for member in u.members:
		var weapon:=_support_weapon(sim,u,member,fact)
		if not Infantry.ready_to_cover(u,member,sim.time,weapon):continue
		if str(fact.kind).is_empty() or sim.effective_weapon(weapon,str(fact.kind)):return true
	return false

static func _connected(sim,a:Dictionary,b:Dictionary)->bool:
	if a.is_empty() or b.is_empty():return false
	return a.pos.distance_to(b.pos)<=LOCAL_COMMS or (not sim.comms_blocked(a) and not sim.comms_blocked(b))

static func _space(sim,provider:Dictionary,point:Vector2)->bool:
	for other in sim.units:
		if other.id==provider.id or other.team!=provider.team or not sim.alive(other):continue
		if sim.definitions[other.kind].domain!="land":continue
		var occupied:Vector2=other.maneuver.get("pos",other.pos)
		if occupied.distance_to(point)<float(sim.definitions[provider.kind].radius)+float(sim.definitions[other.kind].radius)+0.4:return false
	return true

static func _observation(sim,sender:Dictionary)->Dictionary:
	var contacts:Array=sim.context.local_snapshot(sender.id,sim.time,sender.team) if sim.comms_blocked(sender) else sim.context.team_snapshot(sender.team,sim.time)
	var best:Dictionary={}
	for fact in contacts:
		if not sim.definitions.has(str(fact.kind)) or sim.definitions[str(fact.kind)].domain!="land":continue
		if float(fact.age)>6.0 or sender.pos.distance_to(fact.pos)>28.0:continue
		if best.is_empty() or sender.pos.distance_squared_to(fact.pos)<sender.pos.distance_squared_to(best.pos):best=fact
	if not best.is_empty():return best.duplicate(true)
	return {"id":-1,"kind":"","pos":sender.pos+sender.facing.normalized()*8.0,"observed_at":sim.time,"source":"requested_frontage","confidence":1.0}

static func _status(sim,request:Dictionary,text:String)->void:
	request.reason=text
	var sender:Dictionary=sim.get_unit(request.sender)
	var provider:Dictionary=sim.get_unit(request.provider)
	if not sender.is_empty() and sender.get("backup_request",-1)==request.id:sender["backup_status"]=text
	if not provider.is_empty():provider["backup_status"]=text;provider.reason=text

static func _notice(sim,u:Dictionary,text:String)->void:
	if not u.is_empty() and u.team==0:sim.events.append({"type":"warning","text":text,"notice":"low"})

static func _trim(sim)->void:
	var state:=_state(sim)
	for id in state.requests.keys():
		var request:Dictionary=state.requests[id]
		if request.phase in TERMINAL and sim.time-float(request.finished)>HISTORY_SECONDS:state.requests.erase(id)
	for id in state.retry_after.keys():
		if sim.time>=float(state.retry_after[id]):state.retry_after.erase(id)
	for id in state.reserves.keys():
		var unit:Dictionary=sim.get_unit(int(id))
		if not sim.alive(unit) or not unit.get("reserve_enabled",false):state.reserves.erase(id)
