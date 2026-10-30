class_name TacticalWorkBudget
extends RefCounted

# Admission counts bounded search bundles, never physical feasibility. A denial
# means "pending", not "unreachable". Each caller keeps its last safe action and
# retries with the same owner/part; it must not consume a failure backoff.
# A cover bundle tests <=6 routes; regroup <=9; bound <=21; flank <=2.
# Other route bundles retain their documented caller limits. Terrain counts actual A* starts,
# because a synchronous grid search is not bounded in elapsed CPU time.
const DEFAULT_LIMITS:={"routes":8,"cover":2,"regroup":1,"decisions":32,"formation":8}
const PRIORITY_TICKS:=4
const MAX_PRIORITY:=2
const MAX_PENDING:=2048
const EXPIRE_TICKS:=60

var active:=false
var tick_id:=-1
var limits:Dictionary=DEFAULT_LIMITS.duplicate()
var used:Dictionary={}
var pending:Dictionary={}
var admitted:=0
var deferred:=0
var expired:=0
var cancelled:=0
var rejected:=0
var max_wait_ticks:=0

func begin_tick(tick:int,overrides:Dictionary={}) -> void:
	if tick!=tick_id:
		used.clear()
		tick_id=tick
	limits=DEFAULT_LIMITS.duplicate()
	for kind in overrides:
		if limits.has(kind):limits[kind]=maxi(0,int(overrides[kind]))
	active=true
	for key in pending.keys():
		if tick_id-int(pending[key].seen)>EXPIRE_TICKS:
			pending.erase(key)
			expired+=1

func end_tick() -> void:
	active=false

func request(kind:String,owner:int,part:String,priority:int=0) -> bool:
	# Load-time geometry checks and direct test/tool calls are synchronous. The
	# simulation explicitly enables admission only during authoritative ticks.
	if not active:return true
	if not limits.has(kind) or part.is_empty():
		rejected+=1
		return false
	var key:="%s:%d:%s"%[kind,owner,part]
	var entry:Dictionary=pending.get(key,{})
	if entry.is_empty():
		if pending.size()>=MAX_PENDING:
			rejected+=1
			return false
		entry={"kind":kind,"owner":owner,"part":part,"first":tick_id,"seen":tick_id,"priority":clampi(priority,0,MAX_PRIORITY)}
		pending[key]=entry
	else:
		entry.seen=tick_id
		entry.priority=maxi(int(entry.priority),clampi(priority,0,MAX_PRIORITY))
	var left:=int(limits[kind])-int(used.get(kind,0))
	if left<=0:
		deferred+=1
		return false
	# Reserve remaining capacity for earlier/higher-priority requests even when
	# units are visited in a fixed order. A fresh urgent request advances by at
	# most eight ticks, so an ordinary queued owner cannot starve under a flood.
	var ahead:=0
	for other in pending.values():
		# A requester can become safe/blocked/dead before its next visit. Keep
		# its age for a later retry, but never let an unvisited job reserve scarce
		# capacity for the whole expiry lease. Active deferred callers retry next
		# tick; one missed visit is enough to release their unused capacity.
		if other.kind==kind and int(other.seen)>=tick_id-1 and _before(other,entry):ahead+=1
	if ahead>=left:
		deferred+=1
		return false
	pending.erase(key)
	used[kind]=int(used.get(kind,0))+1
	admitted+=1
	max_wait_ticks=maxi(max_wait_ticks,tick_id-int(entry.first))
	return true

static func _before(a:Dictionary,b:Dictionary) -> bool:
	var rank_a:=int(a.first)-int(a.priority)*PRIORITY_TICKS
	var rank_b:=int(b.first)-int(b.priority)*PRIORITY_TICKS
	if rank_a!=rank_b:return rank_a<rank_b
	if a.owner!=b.owner:return int(a.owner)<int(b.owner)
	return str(a.part)<str(b.part)

func cancel_owner(owner:int) -> void:
	for key in pending.keys():
		if int(pending[key].owner)==owner:
			pending.erase(key)
			cancelled+=1

func cancel_request(kind:String,owner:int,part:String) -> void:
	var key:="%s:%d:%s"%[kind,owner,part]
	if pending.erase(key):cancelled+=1

func snapshot() -> Dictionary:
	var oldest:=0
	var waiting:Dictionary={}
	for entry in pending.values():
		oldest=maxi(oldest,tick_id-int(entry.first))
		waiting[entry.kind]=int(waiting.get(entry.kind,0))+1
	return {"tick":tick_id,"limits":limits.duplicate(),"used":used.duplicate(),"pending":pending.size(),"waiting":waiting,
		"oldest_ticks":oldest,"max_wait_ticks":max_wait_ticks,"admitted":admitted,"deferred":deferred,
		"expired":expired,"cancelled":cancelled,"rejected":rejected}
