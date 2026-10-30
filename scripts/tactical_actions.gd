class_name TacticalActions
extends RefCounted

# The action contract owns assignments, reservations, and bounded traces.
# Existing executors own inventory and world effects; cancellation cannot refund them.
const TERMINAL:=["completed","failed","cancelled"]
const NEXT:={"reserved":["preparing","executing"],"preparing":["executing"],"executing":["recovering"],"recovering":[]}
const MAX_ACTIONS:=4096
const MAX_UNIT_CHANNELS:=32
const MAX_CLAIMS:=16
const MAX_EVENTS:=128
const MAX_BACKOFF:=256
const OBSERVATION_LEASE:=2.0
const DEFAULT_WORK:={"decisions":32,"line_checks":256,"route_searches":1,"cover_queries":32}

var actions:Dictionary={}
var claims:Dictionary={}
var owners:Dictionary={}
var retry_after:Dictionary={}
var event_log:Array[Dictionary]=[]
var next_action:=1
var next_event:=1
var tick_id:=-1
var work_limits:Dictionary=DEFAULT_WORK.duplicate()
var work_used:Dictionary={}

static func ensure_unit(u:Dictionary)->void:
	if not u.has("order_version"):u.order_version=0
	if not u.has("assignment_serial"):u.assignment_serial=0
	if not u.has("assignment"):u.assignment={}
	if not u.has("fire_policy"):u.fire_policy="free"
	if not u.has("action_revision"):u.action_revision=0
	if not u.has("action_reason"):u.action_reason="ready"

func accept_order(u:Dictionary,order:Dictionary,now:float,issuer:String="player")->int:
	ensure_unit(u)
	cancel_unit(u,now,"order_replaced")
	u.order_version+=1
	activate_order(u,order,now,issuer)
	return u.order_version

func activate_order(u:Dictionary,order:Dictionary,now:float,issuer:String="player")->void:
	ensure_unit(u)
	cancel_unit(u,now,"assignment_changed")
	var prefix:="%d:"%u.id
	for key in retry_after.keys():
		if str(key).begins_with(prefix):retry_after.erase(key)
	u.assignment_serial+=1
	u.assignment={"id":u.assignment_serial,"version":u.order_version,
		"mode":str(order.get("mode","hold")),"target":int(order.get("target",-1)),
		"pos":order.get("pos",u.get("pos",Vector2.ZERO)),"issuer":issuer,
		"permission_used":false,"permission_revoked":bool(order.get("permission_revoked",false))}
	invalidate(u,now,"order_accepted")

func active(u:Dictionary,channel:String="unit")->Dictionary:
	var channels:Dictionary=owners.get(int(u.id),{})
	return actions.get(channels.get(channel,-1),{})

func begin(u:Dictionary,kind:String,now:float,options:Dictionary={})->Dictionary:
	ensure_unit(u)
	if not is_finite(now):return {}
	expire(u,now)
	var channel:String=options.get("channel","unit")
	var requested:Array=options.get("claims",[])
	if kind.is_empty() or channel.is_empty() or requested.size()>MAX_CLAIMS:
		_block(u,now,"invalid_action");return {}
	if not _available(u) or not options.get("available",true):
		_block(u,now,"unavailable");return {}
	if now<float(retry_after.get(_retry_key(u,kind,channel),-INF)):
		_block(u,now,"backoff");return {}
	var channels:Dictionary=owners.get(int(u.id),{})
	if channels.has(channel):
		_block(u,now,"channel_busy");return {}
	if channels.size()>=MAX_UNIT_CHANNELS or actions.size()>=MAX_ACTIONS:
		_block(u,now,"action_limit");return {}
	var deadline:float=options.get("deadline",now+30.0)
	if deadline<=now or not is_finite(deadline):
		_block(u,now,"invalid_deadline");return {}
	var unique:Array[String]=[]
	for key in requested:
		if not key is String or key.is_empty() or claims.has(key):
			_block(u,now,"claim_busy");return {}
		if key not in unique:unique.append(key)
	var action:Dictionary={"id":next_action,"unit":int(u.id),"version":int(u.order_version),
		"assignment":int(u.assignment.get("id",0)),"channel":channel,"kind":kind,
		"phase":"reserved","target":options.get("target",{}).duplicate(true),
		"claims":unique,"committed":[],"started":now,"deadline":deadline,
		"reason":str(options.get("reason","reserved"))}
	next_action+=1
	actions[action.id]=action
	channels[channel]=action.id
	owners[int(u.id)]=channels
	for key in unique:claims[key]=action.id
	_note(u,action,now,action.reason)
	return action

func valid(u:Dictionary,action:Dictionary,now:float)->bool:
	if not _owned(u,action):return false
	return is_finite(now) and _available(u) and int(action.version)==int(u.get("order_version",0)) \
		and int(action.assignment)==int(u.get("assignment",{}).get("id",0)) and now<float(action.deadline)

func transition(u:Dictionary,action:Dictionary,phase:String,now:float,reason:String="")->bool:
	if not is_finite(now) or not _owned(u,action):return false
	if not valid(u,action,now):
		_cancel_invalid(u,action,now);return false
	if phase=="failed":return fail(u,action,now,reason if not reason.is_empty() else phase)
	# A reservation or preparation is not delivered work. An executor must enter
	# execution before it can report completion; cancellation/failure remain legal.
	if phase=="completed" and action.phase not in ["executing","recovering"]:return false
	if phase in TERMINAL:return _finish(u,action,phase,now,reason if not reason.is_empty() else phase)
	if phase==action.phase:return true
	if phase not in NEXT.get(action.phase,[]):return false
	action.phase=phase
	action.reason=reason if not reason.is_empty() else phase
	_note(u,action,now,action.reason)
	return true

func commit(u:Dictionary,action:Dictionary,key:String,now:float)->bool:
	if not is_finite(now):return false
	if not valid(u,action,now):
		if _owned(u,action):_cancel_invalid(u,action,now)
		return false
	if action.phase!="executing" or claims.get(key,-1)!=action.id or key in action.committed:return false
	action.committed.append(key)
	_note(u,action,now,"committed")
	return true

func complete(u:Dictionary,action:Dictionary,now:float,reason:String="completed")->bool:
	return transition(u,action,"completed",now,reason)

func cancel(u:Dictionary,action:Dictionary,now:float,reason:String="cancelled")->bool:
	if not is_finite(now) or not _owned(u,action):return false
	return _finish(u,action,"cancelled",now,reason)

func fail(u:Dictionary,action:Dictionary,now:float,reason:String="blocked",retry_delay:float=1.0)->bool:
	if not is_finite(now) or not _owned(u,action):return false
	if not _available(u):return cancel(u,action,now,"owner_lost")
	if action.version!=u.get("order_version",0) or action.assignment!=u.get("assignment",{}).get("id",0):
		return cancel(u,action,now,"stale_order")
	var key:=_retry_key(u,action.kind,action.channel)
	if not retry_after.has(key) and retry_after.size()>=MAX_BACKOFF:retry_after.erase(retry_after.keys()[0])
	retry_after[key]=now+clampf(retry_delay if is_finite(retry_delay) else 1.0,0.25,5.0)
	return _finish(u,action,"failed",now,reason)

func cancel_unit(u:Dictionary,now:float,reason:String="cancelled")->void:
	var channels:Dictionary=owners.get(int(u.id),{})
	for id in channels.values().duplicate():
		if actions.has(id):cancel(u,actions[id],now,reason)

func expire(u:Dictionary,now:float)->void:
	if not is_finite(now):return
	var channels:Dictionary=owners.get(int(u.id),{})
	for id in channels.values().duplicate():
		if actions.has(id) and not valid(u,actions[id],now):_cancel_invalid(u,actions[id],now)

# Leases observe real legacy executor state, without spending resources twice.
func observe_existing(u:Dictionary,channel:String,kind:String,now:float,target:Dictionary={},reason:String="",phase:String="executing")->Dictionary:
	if not is_finite(now) or phase not in ["reserved","preparing","executing","recovering"]:return {}
	var current:Dictionary=active(u,channel)
	if not current.is_empty() and not valid(u,current,now):
		_cancel_invalid(u,current,now);current={}
	if not current.is_empty() and (current.kind!=kind or current.target!=target):
		cancel(u,current,now,"executor_changed");current={}
	if current.is_empty():
		current=begin(u,kind,now,{"channel":channel,"target":target,"deadline":now+OBSERVATION_LEASE,"reason":reason if not reason.is_empty() else kind})
	if current.is_empty():return {}
	current.deadline=now+OBSERVATION_LEASE
	if phase=="recovering" and current.phase in ["reserved","preparing"]:transition(u,current,"executing",now,reason)
	if phase!=current.phase:transition(u,current,phase,now,reason)
	return current

func invalidate(u:Dictionary,now:float,reason:String)->void:
	_note(u,{},now,reason)

func begin_tick(tick:int,limits:Dictionary={})->bool:
	if tick<=tick_id:return false
	tick_id=tick
	if not limits.is_empty():
		work_limits={}
		for key in limits:work_limits[str(key)]=maxi(0,int(limits[key]))
	work_used.clear()
	return true

func take_work(category:String,amount:int=1)->bool:
	if tick_id<0 or amount<=0 or not work_limits.has(category):return false
	var used:int=work_used.get(category,0)
	if amount>int(work_limits[category])-used:return false
	work_used[category]=used+amount
	return true

static func engagement_allowed(u:Dictionary,target_id:int=-1,action_kind:String="attack",target_point:Vector2=Vector2.INF)->bool:
	if u.get("fire_policy","free")!="hold":return true
	var assignment:Dictionary=u.get("assignment",{})
	if assignment.get("version",-1)!=u.get("order_version",0):return false
	if assignment.get("permission_revoked",false):return false
	if assignment.get("mode","")!=action_kind:return false
	if action_kind in ["attack","bombard"]:
		return target_id>=0 and target_id==int(assignment.get("target",-1))
	if action_kind=="throw" and not assignment.get("permission_used",false):
		if int(assignment.get("target",-1))>=0:return target_id==int(assignment.target)
		return target_point!=Vector2.INF and target_point==assignment.get("pos",Vector2.INF)
	return false

static func consume_permission(u:Dictionary,action_kind:String="throw")->bool:
	var assignment:Dictionary=u.get("assignment",{})
	if action_kind!="throw" or assignment.get("mode","")!=action_kind:return false
	if assignment.get("version",-1)!=u.get("order_version",0) or assignment.get("permission_used",false) or assignment.get("permission_revoked",false):return false
	assignment.permission_used=true
	return true

static func revoke_permission(u:Dictionary)->void:
	var assignment:Dictionary=u.get("assignment",{})
	if not assignment.is_empty():assignment.permission_revoked=true

static func reason_text(code:String)->String:
	return {"ready":"Ready","reserved":"Preparing","preparing":"Preparing",
		"reloading":"Reloading","aiming":"Aiming","covering":"Using cover",
		"executing":"Acting","recovering":"Recovering","completed":"Complete",
		"order_accepted":"Following orders","order_replaced":"Order replaced",
		"assignment_changed":"Next assignment","executor_changed":"Action changed",
		"cancelled":"Cancelled","blocked":"Blocked","failed":"Unable to act",
		"deadline":"Action timed out","owner_lost":"Unit unavailable",
		"stale_order":"Order replaced","claim_busy":"Waiting for a free role",
		"channel_busy":"Already occupied","backoff":"Reconsidering shortly",
		"unavailable":"Capability unavailable","hold_fire":"Holding fire",
		"work_budget":"Decision pending","committed":"Action released"}.get(code,code.replace("_"," ").capitalize())

func _owned(u:Dictionary,action:Dictionary)->bool:
	return not action.is_empty() and actions.has(action.get("id",-1)) and int(action.get("unit",-1))==int(u.id) and is_same(actions[action.id],action)

func _retry_key(u:Dictionary,kind:String,channel:String)->String:
	return "%d:%s:%s"%[u.id,channel,kind]

static func _available(u:Dictionary)->bool:
	return float(u.get("hp",1.0))>0.0 and not u.get("combat_ineffective",false)

func _cancel_invalid(u:Dictionary,action:Dictionary,now:float)->void:
	var reason:="deadline"
	if not _available(u):reason="owner_lost"
	elif action.version!=u.get("order_version",0) or action.assignment!=u.get("assignment",{}).get("id",0):reason="stale_order"
	if reason=="deadline":fail(u,action,now,reason)
	else:cancel(u,action,now,reason)

func _finish(u:Dictionary,action:Dictionary,phase:String,now:float,reason:String)->bool:
	action.phase=phase
	action.reason=reason
	action.finished=now
	for key in action.claims:
		if claims.get(key,-1)==action.id:claims.erase(key)
	var channels:Dictionary=owners.get(int(u.id),{})
	if channels.get(action.channel,-1)==action.id:channels.erase(action.channel)
	if channels.is_empty():owners.erase(int(u.id))
	actions.erase(action.id)
	u.last_action={"id":action.id,"kind":action.kind,"phase":phase,"reason":reason,"finished":now}
	_note(u,action,now,reason)
	return true

func _block(u:Dictionary,now:float,reason:String)->void:
	if u.get("action_reason","")!=reason:_note(u,{},now,reason)

func _note(u:Dictionary,action:Dictionary,now:float,reason:String)->void:
	ensure_unit(u)
	u.action_revision+=1
	u.action_reason=reason
	event_log.append({"id":next_event,"tick":tick_id,"time":now,"unit":int(u.id),
		"team":int(u.get("team",-1)),"version":int(u.order_version),
		"action":int(action.get("id",0)),"kind":str(action.get("kind","")),
		"phase":str(action.get("phase","")),"reason":reason,"revision":int(u.action_revision)})
	next_event+=1
	if event_log.size()>MAX_EVENTS:event_log.pop_front()
