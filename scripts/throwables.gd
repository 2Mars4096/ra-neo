class_name InfantryThrowables
extends RefCounted

# Fictional balance values. Preparation belongs to a member/action; a released
# object belongs to the world and is never refunded or cancelled by an order.
const PAYLOADS:={
	"frag":{"prepare":1.1,"range":18.0,"radius":4.0,"fuse":0.35,"arc":2.8},
	"smoke":{"prepare":0.9,"range":18.0,"radius":4.5,"fuse":0.15,"arc":2.8,"height":4.0,"lifetime":18.0},
}
const MAX_PROJECTILES:=64
const MAX_SMOKE:=32
const MAX_PREPARATIONS:=64
const PROJECTILE_RADIUS:=0.08
const MAX_FLIGHT_STEP:=1.0/60.0
const PREVIEW_STEPS:=48
const ALLY_MARGIN:=0.65
const AUTO_REVIEW_SECONDS:=1.2
const AUTO_RELEASE_GAP:=6.0
const AUTO_CHECKS_PER_TICK:=2
const AUTO_CONTACTS:=4
const AUTO_MEMBERS:=8
const AUTO_LINE_BUDGET:=48
const GarrisonSystem=preload("res://scripts/garrison.gd")
const City=preload("res://scripts/city_buildings.gd")

static func setup(sim)->void:
	if not sim.throwables.is_empty():return
	sim.throwables={"projectiles":[],"smoke":[],"preparations":[],"next_id":1,"revision":0,"geometry_version":-1,"tops":{},"defenders":[],"auto_cursor":0}

# Explicit emptiness and casualties survive migration. Initial inventory is
# per person, so another section/member cannot recreate a fallen actor's kit.
static func ensure_unit(u:Dictionary)->void:
	if not u.has("throw_policy"):u["throw_policy"]="manual"
	for member in u.get("members",[]):
		if not member.has("throwables"):
			member["throwables"]={"frag":1,"smoke":1} if float(member.get("hp",0.0))>0 and member.get("wound","") not in ["SEVERE","KIA","CREW"] else {"frag":0,"smoke":0}

static func total(u:Dictionary,payload:String)->int:
	var count:=0
	for member in u.get("members",[]):
		if float(member.get("hp",0.0))>0 and member.get("wound","") not in ["SEVERE","KIA","CREW"]:
			count+=maxi(0,int(member.get("throwables",{}).get(payload,0)))
	return count

# Delegation enables only a bounded defensive frag decision. It grants no
# movement, purchase or automatic smoke use. Manual remains the default.
static func set_policy(sim,ids:Array,policy:String)->int:
	setup(sim)
	if sim.result!="" or policy not in ["manual","defensive"]:return 0
	var accepted:=0
	var handled:Dictionary={}
	for identity in ids:
		var id:=int(identity)
		if handled.has(id):continue
		handled[id]=true
		var u:Dictionary=sim.get_unit(id)
		if not sim.alive(u) or u.get("members",[]).is_empty() or sim.comms_blocked(u):continue
		u.throw_policy=policy
		u["throw_next_review"]=sim.time+0.2+float(id%5)*0.1
		if policy=="defensive":
			if id not in sim.throwables.defenders:sim.throwables.defenders.append(id)
		else:
			sim.throwables.defenders.erase(id)
			for job in sim.throwables.preparations.duplicate():
				if int(job.unit)==id and job.get("automatic",false):
					sim.actions.cancel(u,job.action,sim.time,"throw_policy_changed")
					_finish_preparation(sim,job,sim.Infantry.member_by_id(u,str(job.member)))
		accepted+=1
	return accepted

static func busy(sim,u:Dictionary,member:Dictionary)->bool:
	if member.get("task_kind","")!="throw":return false
	var action:Dictionary=sim.actions.active(u,_channel(member))
	return not action.is_empty() and int(action.id)==int(member.get("task_action",-1)) and sim.actions.valid(u,action,sim.time)

static func _channel(member:Dictionary)->String:
	return "member:%s:task"%str(member.member_id)

static func _actor_claim(u:Dictionary,member:Dictionary)->String:
	return "actor:%d:%s"%[int(u.id),str(member.member_id)]

static func _capable(u:Dictionary,member:Dictionary)->bool:
	return float(member.get("hp",0.0))>0 and member.get("wound","") not in ["SEVERE","KIA","CREW"] and int(member.get("aiding",-1))<0 and float(member.get("reload_until",0.0))<=0.0 and maxf(float(member.get("suppression",0.0)),float(u.get("suppression",0.0)))<0.8

static func _origin(sim,member:Dictionary)->Vector3:
	var point:Vector2=member.pos
	return Vector3(point.x,sim.terrain.height_at(point)+1.25,point.y)

static func _duration(source:Vector3,target:Vector3)->float:
	return clampf(Vector2(source.x,source.z).distance_to(Vector2(target.x,target.z))/12.0,0.45,1.5)

static func trajectory(source:Vector3,target:Vector3,fraction:float,arc:float)->Vector3:
	var t:=clampf(fraction,0.0,1.0)
	return source.lerp(target,t)+Vector3.UP*(4.0*arc*t*(1.0-t))

# Preview uses world geometry and known bodies only. Hidden enemies may stop a
# released grenade physically, but they cannot be disclosed by the aiming UI.
static func preview(sim,u:Dictionary,payload:String,point:Vector2)->Dictionary:
	setup(sim)
	var answer:={"ok":false,"reason":"No eligible section","payload":payload,"point":point,"landing":Vector3.ZERO,"arc":[],"collision":false,"radius":0.0,"prepare":0.0,"member":{}}
	if not is_finite(float(sim.time)):answer.reason="Simulation time unavailable";return answer
	if not PAYLOADS.has(payload):answer.reason="Unknown payload";return answer
	var spec:Dictionary=PAYLOADS[payload]
	answer.radius=float(spec.radius);answer.prepare=float(spec.prepare)
	if not sim.alive(u) or u.get("combat_ineffective",false) or u.get("members",[]).is_empty():return answer
	if not point.is_finite() or not sim.terrain.inside(point):answer.reason="Outside battlefield";return answer
	if sim.terrain.is_water(point):answer.reason="Choose a position on land";return answer
	if sim.comms_blocked(u):answer.reason="Radio link lost";return answer
	if GarrisonSystem.inside(u) or GarrisonSystem.transit(u)!="":answer.reason="Throw from outside the building";return answer
	if sim.actions.actions.size()>=sim.actions.MAX_ACTIONS:answer.reason="Action capacity occupied";return answer
	if sim.throwables.projectiles.size()+sim.throwables.preparations.size()>=MAX_PROJECTILES or sim.throwables.preparations.size()>=MAX_PREPARATIONS:answer.reason="Throw capacity occupied";return answer
	if payload=="smoke" and sim.throwables.smoke.size()+_pending_smoke(sim)>=MAX_SMOKE:answer.reason="Smoke capacity occupied";return answer
	ensure_unit(u)
	var candidates:Array=[]
	var stocked:=false
	var in_range:=false
	for member in u.members:
		if int(member.get("throwables",{}).get(payload,0))<=0:continue
		stocked=true
		var distance:float=member.pos.distance_to(point)
		if distance>float(spec.range) or distance<1.0:continue
		in_range=true
		if not _capable(u,member) or int(member.get("task_action",0))>0 or not str(member.get("cover_for","")).is_empty() or not sim.actions.active(u,_channel(member)).is_empty():continue
		if sim.actions.claims.has(_actor_claim(u,member)) or sim.actions.claims.has(_item_claim(u,member,payload)):continue
		if float(member.get("travel",0.0))>0.03 or member.get("cover_phase","") in ["SEEKING","SETTLING"]:continue
		candidates.append(member)
	if candidates.is_empty():
		answer.reason="No %s grenades left"%payload if not stocked else ("Out of throwing range" if not in_range else "No member ready to throw")
		return answer
	candidates.sort_custom(func(a,b):
		var da:float=a.pos.distance_squared_to(point);var db:float=b.pos.distance_squared_to(point)
		return int(a.index)<int(b.index) if da==db else da<db)
	var rejected:Dictionary={}
	# Local body positions differ at a corner: an obstructed nearest member
	# must not prevent a ready teammate with a clear arc from taking the throw.
	# The section's finite member list bounds this nearest-first shortlist.
	for chosen in candidates:
		var candidate:Dictionary=answer.duplicate()
		var source:=_origin(sim,chosen)
		var target:=Vector3(point.x,sim.terrain.height_at(point)+PROJECTILE_RADIUS+0.01,point.y)
		var flight:=_preview_flight(sim,source,target,float(spec.arc),int(u.id),str(chosen.member_id),int(u.team))
		candidate.merge(flight,true)
		candidate.member=chosen
		candidate["source"]=source;candidate["target"]=target
		candidate["duration"]=_duration(source,target)
		# A blocked arc remains visible, but an explicit order must not knowingly
		# throw into the wall at the thrower's feet instead of at the indicated point.
		if not _useful_landing(candidate,point,float(spec.radius)):
			candidate.reason="Throw trajectory blocked"
		elif payload=="frag" and _friendly_risk(sim,int(u.team),candidate.landing,float(spec.radius)):
			candidate.reason="Friendlies near the blast area"
		else:
			candidate.ok=true;candidate.reason="Ready to throw"
			return candidate
		if rejected.is_empty():rejected=candidate
	return rejected

static func preview_selection(sim,ids:Array,payload:String,point:Vector2)->Dictionary:
	var plan:=preview(sim,{},payload,point)
	var handled:Dictionary={}
	for identity in ids:
		if handled.has(int(identity)):continue
		handled[int(identity)]=true
		var u:Dictionary=sim.get_unit(int(identity))
		plan=preview(sim,u,payload,point)
		plan["unit"]=int(identity)
		if plan.ok:return plan
	return plan

# One targeted gesture requests one payload. Selection order is shared with
# the preview; other sections keep their orders, roles and finite equipment.
static func issue_throw(sim,ids:Array,payload:String,point:Vector2)->int:
	setup(sim)
	if sim.result!="":return 0
	var plan:=preview_selection(sim,ids,payload,point)
	if not plan.ok:sim.order_feedback=plan.reason;return 0
	if not _start_preparation(sim,sim.get_unit(int(plan.unit)),plan,true):return 0
	sim.order_feedback="Preparing %s"%("fragmentation grenade" if payload=="frag" else "smoke")
	return 1

static func _item_claim(u:Dictionary,member:Dictionary,payload:String)->String:
	return "throwable:%d:%s:%s"%[int(u.id),str(member.member_id),payload]

static func _start_preparation(sim,u:Dictionary,plan:Dictionary,replace_order:bool,coverer:Dictionary={},threat_id:int=-1)->bool:
	var member:Dictionary=plan.member
	var payload:String=plan.payload
	var point:Vector2=plan.point
	var item_claim:=_item_claim(u,member,payload)
	var claims:Array=[_actor_claim(u,member),item_claim]
	# The support role can be handed to another capable partner without moving
	# an actor claim owned by the action. Coordination owns its actual member.
	if not coverer.is_empty():claims.append("throw_cover:%d"%int(u.id))
	# All begin() admission constraints are checked before replacing an explicit
	# order. No executor runs between this preflight and the atomic reservation.
	if sim.actions.actions.size()>=sim.actions.MAX_ACTIONS or not sim.actions.active(u,_channel(member)).is_empty():return false
	for key in claims:
		if sim.actions.claims.has(key):return false
	if not replace_order:
		if sim.actions.owners.get(int(u.id),{}).size()>=sim.actions.MAX_UNIT_CHANNELS:return false
		var retry:="%d:throw:%s"%[int(u.id),_channel(member)]
		if sim.time<float(sim.actions.retry_after.get(retry,-INF)):return false
	if replace_order:
		# The explicit throw replaces the relevant command and holds afterward.
		sim.command_serial+=1
		sim.record_order(u,"throw",point,-1,false)
		u.orders.clear();u.path.clear();u.hold_command=true;u.speed_now=0.0
	var action:Dictionary=sim.actions.begin(u,"throw",sim.time,{"channel":_channel(member),"claims":claims,"deadline":sim.time+5.0,"target":{"point":point,"payload":payload,"member":str(member.member_id),"automatic":not replace_order},"reason":"preparing_throw"})
	if action.is_empty():return false
	sim.actions.transition(u,action,"preparing",sim.time,"preparing_throw")
	member["task_action"]=int(action.id);member["task_kind"]="throw"
	member["throw_until"]=sim.time+float(PAYLOADS[payload].prepare)
	member.aim=0.0;member.target=-1;member.state="THROWING";member.travel=0.0
	member.facing=(point-member.pos).normalized()
	u.state="THROWING";u.reason="Preparing %s grenade"%payload
	var job:={"unit":int(u.id),"member":str(member.member_id),"payload":payload,"point":point,"origin":member.pos,"left":float(PAYLOADS[payload].prepare),"action":action,"item_claim":item_claim,"automatic":not replace_order,"threat":threat_id,"coverer":str(coverer.get("member_id",""))}
	if not coverer.is_empty():
		member["covered_by"]=str(coverer.member_id);member["support_threat"]=threat_id
		coverer["cover_for"]=str(member.member_id);coverer["coord_reason"]="covering_teammate"
	sim.throwables.preparations.append(job)
	return true

static func _automatic(sim)->void:
	var defenders:Array=sim.throwables.defenders
	if defenders.is_empty():return
	var checked:=0
	for attempt in mini(8,defenders.size()):
		if defenders.is_empty():break
		sim.throwables.auto_cursor=int(sim.throwables.auto_cursor)%defenders.size()
		var id:int=defenders[int(sim.throwables.auto_cursor)]
		sim.throwables.auto_cursor=(int(sim.throwables.auto_cursor)+1)%defenders.size()
		var u:Dictionary=sim.get_unit(id)
		if not sim.alive(u) or u.get("throw_policy","manual")!="defensive":defenders.erase(id);continue
		if sim.time<float(u.get("throw_next_review",0.0)):continue
		if not sim.actions.take_work("decisions"):break
		u["throw_next_review"]=sim.time+AUTO_REVIEW_SECONDS
		checked+=1
		if _automatic_allowed(sim,u) and sim.actions.take_work("line_checks",AUTO_LINE_BUDGET):_consider_frag(sim,u)
		if checked>=AUTO_CHECKS_PER_TICK:break

static func _automatic_allowed(sim,u:Dictionary)->bool:
	if u.get("fire_policy","free")!="free" or sim.comms_blocked(u) or u.get("combat_ineffective",false):return false
	if not u.orders.is_empty() or not u.path.is_empty() or not u.maneuver.is_empty():return false
	if GarrisonSystem.inside(u) or GarrisonSystem.transit(u)!="" or u.get("recovering",false):return false
	if float(u.get("suppression",0.0))>=0.6 or sim.time-float(u.get("last_throw_at",-INF))<AUTO_RELEASE_GAP:return false
	return total(u,"frag")>0 and not sim.throwables.preparations.any(func(job):return int(job.unit)==int(u.id))

static func _known_targets(sim,u:Dictionary)->Array:
	var candidates:Array=[]
	for fact in sim.context.team_snapshot(int(u.team),sim.time):
		if float(fact.age)>0.4 or u.pos.distance_to(fact.pos)>float(PAYLOADS.frag.range)+2.5:continue
		var target:Dictionary=sim.get_unit(int(fact.id))
		if not sim.alive(target) or target.team==u.team or target.members.is_empty() or not sim.contact_known(u,target):continue
		candidates.append(target)
	candidates.sort_custom(func(a,b):return u.pos.distance_squared_to(a.pos)<u.pos.distance_squared_to(b.pos))
	return candidates.slice(0,AUTO_CONTACTS)

static func _known_members(sim,u:Dictionary,targets:Array)->Array:
	var result:Array=[]
	var source:=Vector3(u.pos.x,sim.terrain.height_at(u.pos)+1.6,u.pos.y)
	for target in targets:
		for member in target.members:
			if float(member.hp)<=0.0:continue
			var endpoint:=Vector3(member.pos.x,sim.terrain.height_at(member.pos)+1.6,member.pos.y)
			if source.distance_to(endpoint)>float(sim.definitions[u.kind].sight)*float(sim.weather.sight_scale):continue
			if sim.optical_ray_clear(source,endpoint):result.append({"unit":target,"member":member})
			if result.size()>=AUTO_MEMBERS:return result
	return result

static func _useful_count(sim,origin:Vector3,radius:float,members:Array)->int:
	var count:=0
	for entry in members:
		var member:Dictionary=entry.member
		var endpoint:=Vector3(member.pos.x,sim.terrain.height_at(member.pos)+0.9,member.pos.y)
		if endpoint.distance_to(origin)<=radius*0.85 and _exposure(sim,entry.unit,member,origin)>0.0:count+=1
	return count

static func _consider_frag(sim,u:Dictionary)->void:
	var targets:=_known_targets(sim,u)
	var members:=_known_members(sim,u,targets)
	if members.size()<2:return
	for threat in targets.slice(0,2):
		var plan:=preview(sim,u,"frag",threat.pos)
		if not plan.ok or _useful_count(sim,plan.landing,float(PAYLOADS.frag.radius),members)<2:continue
		for peer in u.members:
			if peer.member_id==plan.member.member_id or not str(peer.get("cover_for","")).is_empty():continue
			if not sim.Coordination.can_cover(u,peer,sim,threat):continue
			if _start_preparation(sim,u,plan,false,peer,int(threat.id)):return

static func _pending_smoke(sim)->int:
	var count:=0
	for collection in [sim.throwables.preparations,sim.throwables.projectiles]:
		for item in collection:
			if item.payload=="smoke":count+=1
	return count

static func tick(sim,dt:float)->void:
	setup(sim)
	if not is_finite(dt) or dt<=0.0:return
	# Capture existing objects first: objects released at this tick start at the
	# hand and must not gain a free dt of flight on their release frame.
	var existing:Array=sim.throwables.projectiles.duplicate()
	_automatic(sim)
	for job in sim.throwables.preparations.duplicate():_prepare(sim,job,dt)
	for projectile in existing:_flight(sim,projectile,dt)
	var changed:=false
	for cloud in sim.throwables.smoke.duplicate():
		if sim.time>=float(cloud.expires):sim.throwables.smoke.erase(cloud);changed=true
	if changed:_smoke_changed(sim)

static func _prepare(sim,job:Dictionary,dt:float)->void:
	var u:Dictionary=sim.get_unit(int(job.unit))
	var member:Dictionary=sim.Infantry.member_by_id(u,str(job.member)) if not u.is_empty() else {}
	var action:Dictionary=job.action
	if u.is_empty() or not sim.actions.valid(u,action,sim.time):
		if not u.is_empty():sim.actions.cancel(u,action,sim.time,"throw_interrupted")
		_finish_preparation(sim,job,member);return
	if member.is_empty() or int(member.get("task_action",-1))!=int(action.id) or member.get("task_kind","")!="throw" or not _capable(u,member) or member.pos.distance_to(job.origin)>0.65 or GarrisonSystem.inside(u) or GarrisonSystem.transit(u)!="":
		sim.actions.fail(u,action,sim.time,"thrower_unavailable")
		_finish_preparation(sim,job,member);return
	if not sim.Actions.engagement_allowed(u,-1,"throw",job.point):
		sim.actions.cancel(u,action,sim.time,"hold_fire")
		_finish_preparation(sim,job,member);return
	if job.get("automatic",false):
		var threat:Dictionary=sim.get_unit(int(job.threat))
		var partner:Dictionary=sim.Infantry.member_by_id(u,str(member.get("covered_by","")))
		if u.get("throw_policy","manual")!="defensive" or u.get("fire_policy","free")!="free" or not u.orders.is_empty() or not u.path.is_empty() or not u.maneuver.is_empty() or partner.is_empty() or str(partner.get("cover_for",""))!=str(job.member) or not sim.alive(threat) or not sim.Infantry.ready_to_cover(u,partner,sim.time,sim.Coordination.covering_weapon(u,partner,sim,threat)):
			sim.actions.cancel(u,action,sim.time,"cover_unavailable")
			_finish_preparation(sim,job,member);return
		job.coverer=str(partner.member_id)
	member.state="THROWING";member.aim=0.0;member.target=-1;member.travel=0.0
	job.left=maxf(0.0,float(job.left)-dt)
	if float(job.left)>0.00001:return
	if job.get("automatic",false):
		# Defer the final physical review when its shared query budget is busy;
		# preparation never skips the review or releases on an unverified lane.
		if not sim.actions.take_work("line_checks",AUTO_LINE_BUDGET):return
		var partner:Dictionary=sim.Infantry.member_by_id(u,str(job.coverer))
		if not sim.Coordination.can_cover(u,partner,sim,sim.get_unit(int(job.threat))):
			sim.actions.cancel(u,action,sim.time,"cover_unavailable")
			_finish_preparation(sim,job,member);return
	var spec:Dictionary=PAYLOADS[job.payload]
	var source:=_origin(sim,member)
	var point:Vector2=job.point
	var target:=Vector3(point.x,sim.terrain.height_at(point)+PROJECTILE_RADIUS+0.01,point.y)
	var flight:=_preview_flight(sim,source,target,float(spec.arc),int(u.id),str(member.member_id),int(u.team))
	if Vector2(source.x,source.z).distance_to(point)>float(spec.range) or not _useful_landing(flight,point,float(spec.radius)):
		sim.actions.fail(u,action,sim.time,"throw_blocked")
		_finish_preparation(sim,job,member);return
	if job.payload=="frag" and _friendly_risk(sim,int(u.team),flight.landing,float(spec.radius)):
		sim.actions.fail(u,action,sim.time,"friendlies_near_throw")
		_finish_preparation(sim,job,member);return
	if job.get("automatic",false) and _useful_count(sim,flight.landing,float(spec.radius),_known_members(sim,u,_known_targets(sim,u)))<2:
		sim.actions.cancel(u,action,sim.time,"throw_opportunity_lost")
		_finish_preparation(sim,job,member);return
	if int(member.get("throwables",{}).get(job.payload,0))<=0 or sim.throwables.projectiles.size()>=MAX_PROJECTILES:
		sim.actions.fail(u,action,sim.time,"no_throwable")
		_finish_preparation(sim,job,member);return
	if not sim.actions.transition(u,action,"executing",sim.time,"throw_released") or not sim.actions.commit(u,action,str(job.item_claim),sim.time):
		_finish_preparation(sim,job,member);return
	member.throwables[job.payload]=int(member.throwables[job.payload])-1
	u["last_throw_at"]=sim.time
	# One scoped explicit release, even under Hold fire. It grants no ordinary
	# rifle shot and cannot be reused by a second automatic action.
	if u.get("assignment",{}).get("mode","")=="throw":sim.Actions.consume_permission(u)
	var duration:=_duration(source,target)
	var id:int=sim.throwables.next_id
	sim.throwables.next_id+=1
	var projectile:={"id":id,"payload":str(job.payload),"unit":int(u.id),"member":str(member.member_id),"team":int(u.team),"source":source,"target":target,"pos":source,"arc":float(spec.arc),"duration":duration,"elapsed":0.0,"landed":false,"released":sim.time,"fuse":duration+float(spec.fuse),"visible":bool(u.get("visible",false))}
	sim.throwables.projectiles.append(projectile)
	sim.events.append({"type":"throw_release","unit":u.id,"member":str(member.member_id),"payload":str(job.payload),"pos":member.pos,"from":Vector2(source.x,source.z),"to":point,"from_y":source.y,"to_y":target.y,"flight":duration,"visible":projectile.visible})
	sim.actions.complete(u,action,sim.time,"throw_released")
	u.reason="%s released"%("Grenade" if job.payload=="frag" else "Smoke")
	_finish_preparation(sim,job,member)

static func _finish_preparation(sim,job:Dictionary,member:Dictionary)->void:
	# An accepted replacement can already have assigned this soldier a new
	# covered bound before the cancelled preparation is drained next tick.
	# Only the job still owning the actor may release its cooperation roles.
	var owns_actor:bool=not member.is_empty() and int(member.get("task_action",-1))==int(job.action.id)
	if owns_actor:
		member.erase("task_action");member.erase("task_kind");member.erase("throw_until")
		if member.get("state","")=="THROWING":member.state="HOLDING"
	if owns_actor and job.get("automatic",false):
		var u:Dictionary=sim.get_unit(int(job.unit))
		for peer in u.get("members",[]):
			if str(peer.get("cover_for",""))==str(job.member):
				peer.erase("cover_for");peer.erase("coord_reason")
				var support:Dictionary=sim.actions.active(u,"member:%s:support"%peer.member_id)
				if not support.is_empty() and str(support.target.get("member",""))==str(job.member):sim.actions.complete(u,support,sim.time,"support_released")
		if not member.is_empty():member.erase("covered_by");member.erase("support_threat")
	sim.throwables.preparations.erase(job)

static func _flight(sim,projectile:Dictionary,dt:float)->void:
	var end:=minf(float(projectile.elapsed)+dt,float(projectile.fuse))
	while float(projectile.elapsed)<end-0.000001:
		var next:=minf(end,float(projectile.elapsed)+MAX_FLIGHT_STEP)
		if not bool(projectile.landed):
			var desired:=trajectory(projectile.source,projectile.target,next/float(projectile.duration),float(projectile.arc))
			var sweep:=_sweep(sim,projectile.pos,desired,int(projectile.unit),str(projectile.member))
			if bool(sweep.hit):
				projectile.pos=sweep.pos;projectile.landed=true
				projectile["collision"]=str(sweep.kind)
			else:
				projectile.pos=desired
				if next>=float(projectile.duration):projectile.landed=true
		projectile.elapsed=next
	if float(projectile.elapsed)>=float(projectile.fuse)-0.000001:
		_activate(sim,projectile)
		sim.throwables.projectiles.erase(projectile)

static func _activate(sim,projectile:Dictionary)->void:
	var point:Vector3=projectile.pos
	var flat:=Vector2(point.x,point.z)
	var spec:Dictionary=PAYLOADS[projectile.payload]
	# Water extinguishes the M1 ground payloads; throws at water are refused,
	# but a physical collision/changed terrain still follows this world rule.
	if sim.terrain.is_water(flat):return
	if projectile.payload=="smoke":
		if sim.throwables.smoke.size()>=MAX_SMOKE:return
		var visible:bool=bool(projectile.visible) or sim.visible_cells.has(sim.terrain.cell(flat))
		sim.throwables.smoke.append({"id":int(projectile.id),"pos":Vector3(flat.x,sim.terrain.height_at(flat),flat.y),"radius":float(spec.radius),"height":float(spec.height),"born":sim.time,"expires":sim.time+float(spec.lifetime),"team":int(projectile.team),"visible":visible})
		_smoke_changed(sim)
		sim.events.append({"type":"smoke_deployed","pos":flat,"radius":float(spec.radius),"visible":visible,"unit":int(projectile.unit)})
	else:
		_blast(sim,point,float(spec.radius))
		sim.events.append({"type":"world_blast","kind":"grenade","pos":flat,"height":point.y,"radius":float(spec.radius),"visible":bool(projectile.visible) or sim.visible_cells.has(sim.terrain.cell(flat))})
		sim.events.append({"type":"grenade_burst","pos":flat,"height":point.y,"unit":int(projectile.unit),"payload":"frag"})

static func _smoke_changed(sim)->void:
	sim.throwables.revision+=1
	sim.visibility_cache.clear()
	sim.sensor_clock=0.0

# Opaque finite cylinders are owner-independent. Elevated lines can clear the
# cloud; ordinary optical acquisition and tracking cannot see through it.
# Already released fire-and-forget missiles retain their existing seeker rules.
static func blocks_sight(sim,a:Vector3,b:Vector3)->bool:
	if sim.throwables.is_empty():return false
	if not a.is_finite() or not b.is_finite():return true
	for cloud in sim.throwables.smoke:
		if sim.time>=float(cloud.expires):continue
		var center:Vector3=cloud.pos
		var low:=0.0;var high:=1.0
		var dy:=b.y-a.y
		if absf(dy)<0.000001:
			if a.y<center.y or a.y>center.y+float(cloud.height):continue
		else:
			var ta:=(center.y-a.y)/dy;var tb:=(center.y+float(cloud.height)-a.y)/dy
			low=maxf(low,minf(ta,tb));high=minf(high,maxf(ta,tb))
		if low>high:continue
		var offset:=Vector2(a.x-center.x,a.z-center.z)
		var direction:=Vector2(b.x-a.x,b.z-a.z)
		var aa:=direction.length_squared()
		var cc:=offset.length_squared()-pow(float(cloud.radius),2)
		if aa<0.000001:
			if cc<=0.0:return true
			continue
		var bb:=2.0*offset.dot(direction)
		var discriminant:=bb*bb-4.0*aa*cc
		if discriminant<0.0:continue
		var root:=sqrt(discriminant)
		low=maxf(low,(-bb-root)/(2.0*aa));high=minf(high,(-bb+root)/(2.0*aa))
		if low<=high:return true
	return false

static func _preview_flight(sim,source:Vector3,target:Vector3,arc:float,unit_id:int,member_id:String,team:int)->Dictionary:
	var points:Array[Vector3]=[source]
	var previous:=source
	var collided:=false
	var collision_kind:=""
	for i in range(1,PREVIEW_STEPS+1):
		var next:=trajectory(source,target,float(i)/PREVIEW_STEPS,arc)
		var sweep:=_sweep(sim,previous,next,unit_id,member_id,team)
		if sweep.hit:
			points.append(sweep.pos);previous=sweep.pos;collided=true;collision_kind=str(sweep.kind);break
		points.append(next);previous=next
	return {"arc":points,"landing":previous,"collision":collided,"collision_kind":collision_kind}

static func _useful_landing(flight:Dictionary,point:Vector2,radius:float)->bool:
	var distance:float=Vector2(flight.landing.x,flight.landing.z).distance_to(point)
	# Contact with a known body in the target area is a usable impact. Walls
	# farther from the indicated point remain a refused trajectory.
	return distance<=1.0 or (flight.get("collision_kind","")=="body" and distance<=radius*0.75)

static func _friendly_risk(sim,team:int,origin:Vector3,radius:float)->bool:
	var flat:=Vector2(origin.x,origin.z)
	for entry in sim.actor_candidates(flat,flat,radius+ALLY_MARGIN):
		var u:Dictionary=entry.unit;var member:Dictionary=entry.actor
		if int(u.team)!=team or not sim.alive(u):continue
		var body:float=float(member.get("body_radius",sim.definitions[u.kind].get("radius",0.8)))
		if flat.distance_to(member.pos)<=radius+ALLY_MARGIN+body:return true
	return false

static func _geometry_tops(sim)->Dictionary:
	var state:Dictionary=sim.throwables
	if int(state.geometry_version)==int(sim.terrain.geometry_version):return state.tops
	var tops:Dictionary={}
	for rect in sim.terrain.blocks:
		tops[rect]=sim.terrain.height_at(rect.get_center())+(0.6 if sim.terrain.low_obstacle_blocks.has(rect) else 5.5)
	for rect in sim.terrain.prop_blocks+sim.terrain.roadside_blocks:
		tops[rect]=sim.terrain.height_at(rect.get_center())+2.6
	for building in GarrisonSystem.index(sim).buildings:
		if int(building.state)>=GarrisonSystem.COLLAPSED:continue
		var spec:Dictionary=building.get("spec",{})
		var height:float=City.height_cap(str(building.design),int(building.floors)) if City.handles(str(building.design)) else float(building.height)
		for rect in building.rects:
			tops[rect]=sim.terrain.height_at(rect.get_center())+height
	state.geometry_version=sim.terrain.geometry_version;state.tops=tops
	return tops

# Exact segment/prism clipping catches thin walls between sample positions.
# Ground uses bounded subsegments of the analytic arc, with a conservative skin.
static func _sweep(sim,a:Vector3,b:Vector3,owner:int=-1,owner_member:String="",preview_team:int=-1,bodies:bool=true)->Dictionary:
	var flat_a:=Vector2(a.x,a.z);var flat_b:=Vector2(b.x,b.z)
	var center:Vector2=(flat_a+flat_b)*0.5
	var reach:=flat_a.distance_to(flat_b)*0.5+PROJECTILE_RADIUS
	var best:=INF
	var kind:=""
	var tops:=_geometry_tops(sim)
	for rect in sim.terrain._static_candidates("solid",center,reach):
		var top:float=float(tops.get(rect,sim.terrain.height_at(rect.get_center())+5.5))
		var fraction:=_prism_fraction(a,b,rect.grow(PROJECTILE_RADIUS),-1000.0,top+PROJECTILE_RADIUS)
		if fraction<best:best=fraction;kind="wall"
	for rect in sim.terrain.dynamic_blocks:
		if not rect.grow(reach+PROJECTILE_RADIUS).has_point(center):continue
		var fraction:=_prism_fraction(a,b,rect.grow(PROJECTILE_RADIUS),-1000.0,sim.terrain.height_at(rect.get_center())+1.6)
		if fraction<best:best=fraction;kind="field_work"
	var steps:=maxi(1,ceili(a.distance_to(b)/0.2))
	for i in range(1,steps+1):
		var fraction:=float(i)/steps
		if fraction>=best:break
		var at:=a.lerp(b,fraction)
		if at.y<=sim.terrain.height_at(Vector2(at.x,at.z))+PROJECTILE_RADIUS:
			best=fraction;kind="ground";break
	if bodies:
		for entry in sim.actor_candidates(flat_a,flat_b,PROJECTILE_RADIUS):
			var u:Dictionary=entry.unit;var actor:Dictionary=entry.actor
			if int(u.id)==owner and str(actor.get("member_id",""))==owner_member:continue
			if not sim.alive(u) or not sim.definitions[u.kind].get("solid",true) or GarrisonSystem.member_indoors(u,actor):continue
			if preview_team>=0 and int(u.team)!=preview_team and not bool(u.get("seen_by",[false,false])[preview_team]):continue
			var ground:float=sim.terrain.height_at(actor.pos)
			var is_member:bool=not u.members.is_empty()
			var radius:float=float(actor.get("body_radius",0.8)) if is_member else float(sim.definitions[u.kind].radius)
			var height:float=(0.5 if actor.get("posture","")=="PRONE" else 1.5) if is_member else (1.6 if u.get("structure",false) else 2.4)
			var rect:=Rect2(actor.pos-Vector2.ONE*radius,Vector2.ONE*radius*2.0)
			var fraction:=_prism_fraction(a,b,rect.grow(PROJECTILE_RADIUS),ground,ground+height)
			if fraction<best:best=fraction;kind="body"
	return {"hit":is_finite(best),"pos":a.lerp(b,maxf(0.0,best-0.001)) if is_finite(best) else b,"kind":kind}

static func _prism_fraction(a:Vector3,b:Vector3,rect:Rect2,bottom:float,top:float)->float:
	var low:=Vector3(rect.position.x,bottom,rect.position.y)
	var high:=Vector3(rect.end.x,top,rect.end.y)
	var delta:=b-a
	var enter:=0.0;var leave:=1.0
	for axis in 3:
		if absf(delta[axis])<0.000001:
			if a[axis]<low[axis] or a[axis]>high[axis]:return INF
		else:
			var first:float=(low[axis]-a[axis])/delta[axis]
			var last:float=(high[axis]-a[axis])/delta[axis]
			enter=maxf(enter,minf(first,last));leave=minf(leave,maxf(first,last))
			if enter>leave:return INF
	return enter if leave>=0.0 and enter<=1.0 else INF

static func _exposure(sim,u:Dictionary,member:Dictionary,origin:Vector3)->float:
	var flat:Vector2=member.pos
	var indoors:=GarrisonSystem.member_indoors(u,member)
	var endpoint:=Vector3(flat.x,sim.terrain.height_at(flat)+(2.2 if indoors else (0.35 if member.get("posture","")=="PRONE" else 0.9)),flat.y)
	var ray:=_sweep(sim,origin+Vector3.UP*0.04,endpoint,-1,"",-1,false)
	if ray.hit:return 0.0
	var shelter:=GarrisonSystem.DAMAGE_SCALE if indoors else (0.5 if member.get("in_trench",false) or sim.terrain.cover(flat) else 1.0)
	return shelter

static func _blast(sim,origin:Vector3,radius:float)->void:
	var flat:=Vector2(origin.x,origin.z)
	var candidates:Array=sim.actor_candidates(flat,flat,radius)
	candidates.sort_custom(func(a,b):return int(a.unit.id)<int(b.unit.id) or (int(a.unit.id)==int(b.unit.id) and int(a.actor.get("index",-1))<int(b.actor.get("index",-1))))
	var hit_units:Dictionary={}
	for entry in candidates:
		var u:Dictionary=entry.unit;var member:Dictionary=entry.actor
		if not sim.alive(u) or float(member.get("hp",0.0))<=0:continue
		var d:Dictionary=sim.definitions[u.kind]
		if d.domain!="land" or float(d.get("armor",0.0))>0.0 or d.get("small_arms_proof",false):continue
		var at:=Vector3(member.pos.x,sim.terrain.height_at(member.pos)+(2.2 if GarrisonSystem.member_indoors(u,member) else 0.9),member.pos.y)
		var distance:=origin.distance_to(at)
		if distance>radius:continue
		var exposure:=_exposure(sim,u,member,origin)
		if exposure<=0.0:continue
		var falloff:=clampf(1.0-distance/radius,0.0,1.0)
		var pin:=(0.2+0.45*falloff)*exposure
		member.suppression=minf(1.0,float(member.get("suppression",0.0))+pin)
		member.last_hit=sim.time
		if u.members.is_empty():u.hp=maxf(0.0,float(u.hp)-18.0*(0.2+0.8*falloff)*exposure)
		elif sim.combat_rng.randf()<(0.35+0.65*falloff)*exposure:
			sim.Infantry.wound(u,member,sim.Infantry.roll("FRAGMENT",(0.45+0.75*falloff)*exposure,sim.combat_rng),sim.time,sim.combat_rng)
		hit_units[int(u.id)]=u
	for u in hit_units.values():
		u.last_hit=sim.time;u.suppression=minf(1.0,float(u.suppression)+0.25)
		if not u.members.is_empty():sim.Infantry.publish(u)
		sim.wake_tactical(u,"grenade_burst")
		if u.hp<=0 and not u.get("lost_counted",false):
			u["lost_counted"]=true
			sim.events.append({"type":"destroyed","kind":u.kind,"pos":u.pos,"visible":u.visible})
			if int(u.team)==1:sim.kills+=1
			else:sim.losses+=1
