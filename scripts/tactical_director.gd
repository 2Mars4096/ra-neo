class_name TacticalDirector
extends RefCounted

const ARRIVED_SHORT:=1.0  # an arrival farther than this from the maneuver spot stopped short

static func cancel(u:Dictionary) -> void:
	u.maneuver={}
	u.reason="Following orders"
	u.commit_until=0.0
	u.next_decision=0.0
	u.hold_command=false
	u.maneuver_review=0.0
	u["pressure_pending"]=false
	u["pressure_review"]=0.0
	u.erase("pressure_route_after")
	u.erase("pressure_retry_facts")
	u.erase("pressure_reservations")

static func plan(sim,u:Dictionary,pos:Vector2,phase:String,reason:String,duration:float=6.0, route_hint:Array=[]) -> bool:
	if phase=="SUPPORT" and sim.time<u.get("support_after",0.0):return false
	var d:Dictionary=sim.definitions[u.kind]
	if not sim.terrain.traversable(pos,d.domain,d.radius):return false
	for other in sim.units:
		if other.id==u.id or not sim.alive(other) or other.team!=u.team:continue
		if not other.maneuver.is_empty() and pos.distance_to(other.maneuver.pos)<float(d.radius)+float(sim.definitions[other.kind].radius)+0.4:return false
	# Over the tick's route budget the maneuver is not taken now; the next
	# decision (<1 s) reconsiders it.
	if route_hint.is_empty() and not sim.take_route_budget(u.pos,pos,true,int(u.id),"maneuver:"+phase):
		u.next_decision=sim.time
		u.maneuver_review=sim.time
		if phase=="WITHDRAW":u["pressure_review"]=sim.time
		return false
	var t0:int=Time.get_ticks_usec() if sim.profiling else 0
	var route:Array=route_hint if not route_hint.is_empty() else sim.terrain.path(u.pos,pos,d.domain,d.radius,[],sim.terrain.mobility_profile(u.kind))
	if sim.profiling:sim._lap("director_path",t0)
	if route.is_empty():return false
	var previous:Dictionary=sim.actions.active(u,"movement")
	if not previous.is_empty():sim.actions.cancel(u,previous,sim.time,"maneuver_replaced")
	var deadline:float=sim.time+duration+(37.0 if phase=="WITHDRAW" else 12.0)
	var action:Dictionary=sim.actions.begin(u,phase.to_lower(),sim.time,{"channel":"movement","claims":["unit:%d:movement"%u.id],"target":{"pos":pos},"deadline":deadline,"reason":phase.to_lower()})
	if action.is_empty():
		if not u.maneuver.is_empty() and u.maneuver.get("phase","")!="PRESSURE_WAIT":resume(sim,u,"Decision pending · resuming objective")
		return false
	sim.actions.transition(u,action,"executing",sim.time,phase.to_lower())
	u.maneuver={"pos":pos,"mode":"retreat" if phase=="WITHDRAW" else "maneuver","phase":phase,"arrived":u.pos.distance_to(pos)<0.15,"progress_pos":u.pos,"progress_at":sim.time,"deadline":sim.time+duration+(37.0 if phase=="WITHDRAW" else 12.0)}
	u.maneuver["action_id"]=action.id
	u.path=[] if u.maneuver.arrived else route
	if phase=="SUPPORT":u.support_after=sim.time+20.0
	u.commit_until=sim.time+duration
	u.reason=reason
	u.next_decision=sim.time+duration
	sim.events.append({"type":"decision","unit":u.id,"phase":phase,"reason":reason,"pos":pos})
	return true

static func resume(sim,u:Dictionary,reason:String="Regrouping toward objective") -> void:
	var action:Dictionary=sim.actions.active(u,"movement")
	if not action.is_empty():
		if "blocked" in reason or "timed out" in reason or "Support lost" in reason:sim.actions.fail(u,action,sim.time,"blocked",1.0)
		else:sim.actions.complete(u,action,sim.time,"completed")
	u.maneuver={}
	u.reason=reason
	u.next_decision=sim.time+5.0
	u.commit_until=sim.time+5.0
	if not u.orders.is_empty():
		if not sim.take_route_budget(u.pos,u.orders[0].pos,false,int(u.id),"resume"):
			sim.defer_route(u,"direct")
			return
		var d:Dictionary=sim.definitions[u.kind]
		var t0:int=Time.get_ticks_usec() if sim.profiling else 0
		u.path=sim.terrain.path(u.pos,u.orders[0].pos,d.domain,d.radius,[],sim.terrain.mobility_profile(u.kind))
		if sim.profiling:sim._lap("director_path",t0)

static func critical_pressure(u:Dictionary)->bool:
	var threshold:=0.35 if not u.get("members",[]).is_empty() else 0.33
	return float(u.get("suppression",0.0))>0.82 or float(u.hp)<=float(u.get("assigned_hp",u.max_hp))*threshold

# Emergency assessment precedes a contact hold. A viable local survival action
# can continue; a rally route is useful only if it does not close on a known
# threat along the way. Direct move, retreat and hard Hold remain authoritative.
static func pressure_response(sim,u:Dictionary)->bool:
	# A response handles an episode of pressure, not the permanent fact that
	# dead squadmates cannot heal. Seeing the same contact again is no new hit.
	if u.has("pressure_resolved") and _new_pressure(u,u.pressure_resolved):
		u.erase("pressure_resolved")
		u.erase("pressure_route_after")
		u.erase("pressure_retry_facts")
	if u.has("pressure_retry_facts") and _new_pressure(u,u.pressure_retry_facts):
		u.erase("pressure_route_after")
		u.erase("pressure_retry_facts")
	# Evaluate the purpose of an active withdrawal even after suppression has
	# fallen below the entry threshold. Its original commitment still applies.
	if u.maneuver.get("phase","")=="WITHDRAW":return _disengaged(sim,u)
	if not critical_pressure(u):
		_clear_pressure_wait(sim,u)
		if u.reason=="Hold position · under pressure":u.reason="Holding position"
		return false
	var intent:Dictionary=u.intent if u.orders.is_empty() else u.orders[0]
	if intent.get("mode","") in ["move","retreat"]:
		_clear_pressure_wait(sim,u)
		return false
	if sim.time<float(u.get("pressure_review",0.0)):return u.get("pressure_pending",false)
	u["pressure_review"]=sim.time+0.3
	u["pressure_pending"]=false
	var threats:=_pressure_contacts(sim,u)
	if threats.is_empty():
		_clear_pressure_wait(sim,u)
		if u.reason=="Hold position · under pressure":u.reason="Holding position"
		return false
	if u.hold_command:
		u.reason="Hold position · under pressure"
		if sim.time>=float(u.get("hold_pressure_notice",0.0)):
			u["hold_pressure_notice"]=sim.time+10.0
			sim.actions.invalidate(u,sim.time,"hold_under_pressure")
			if u.team==0:sim.events.append({"type":"warning","text":"HOLD POSITION • Section under pressure","notice":"low"})
		return true
	if u.has("pressure_resolved"):
		_clear_pressure_wait(sim,u)
		return false
	# Losing most of a section is not a reason to abandon its last medic or
	# an already useful shelter. These are existing, physically validated local
	# choices, not a second cover search outside the work budget.
	if _pressure_local_response(sim,u,threats):
		_release_pressure_search(sim,u)
		return false
	if sim.time<float(u.get("pressure_route_after",0.0)):return false
	u["pressure_pending"]=true
	# Emergency acknowledgement is cheap and immediate. An exhausted planner
	# must never leave a stale flank advancing for another review interval.
	if u.maneuver.get("phase","")!="PRESSURE_WAIT":
		var previous:Dictionary=sim.actions.active(u,"movement")
		if not previous.is_empty():sim.actions.cancel(u,previous,sim.time,"urgent_withdrawal")
		u.maneuver={"phase":"PRESSURE_WAIT","mode":"maneuver","pos":u.pos,"arrived":true,"deadline":INF}
		u.path=[]
		u.reason="Under pressure · planning withdrawal"
		u.erase("pressure_reservations")
	if not sim.terrain.planning.request("formation",int(u.id),"withdrawal",2):
		u["pressure_review"]=sim.time
		return true
	var reservations:Array[Dictionary]=[]
	for other in sim.units:
		if other.id!=u.id and sim.alive(other) and other.team==u.team:
			reservations.append({"pos":other.maneuver.get("pos",other.pos),"radius":sim.definitions[other.kind].radius,"layer":sim.collision_layer(other)})
	# A moving friendly anywhere on the map must not restart the formation
	# cursor every tick. Snapshot claims for this search and validate the chosen
	# position against live claims before committing the route.
	if not u.has("pressure_reservations"):u["pressure_reservations"]=reservations.duplicate(true)
	var held:Array[Dictionary]=[]
	var placement:Dictionary=sim.formation_plan(sim.rally_point(u),u,u.pressure_reservations,{},held,"withdrawal")
	if not placement.done:
		u["pressure_review"]=sim.time
		return true
	var destination:Vector2=placement.pos
	if destination.x<0 or not sim.slot_clear(destination,sim.collision_layer(u),sim.crowd_radius(u.kind),reservations):
		_release_pressure_search(sim,u)
		u["pressure_route_after"]=sim.time+2.0
		u["pressure_retry_facts"]=_pressure_facts(u)
		u.reason="No safe withdrawal · holding for cover"
		return false
	if not sim.take_route_budget(u.pos,destination,true,int(u.id),"maneuver:WITHDRAW"):
		u["pressure_review"]=sim.time
		return true
	var d:Dictionary=sim.definitions[u.kind]
	var route:Array=sim.terrain.path(u.pos,destination,d.domain,d.radius,[],sim.terrain.mobility_profile(u.kind))
	if route.is_empty() or not _pressure_route_safe(u.pos,route,threats):
		# The candidate failed; no withdrawal action has begun or completed.
		# Stay physically halted while the normal, bounded cover/contact drill
		# finds local protection. Retry the rally later, rather than every tick.
		_release_pressure_search(sim,u)
		u["pressure_route_after"]=sim.time+2.0
		u["pressure_retry_facts"]=_pressure_facts(u)
		u.reason="No safe withdrawal · holding for cover"
		return false
	if plan(sim,u,destination,"WITHDRAW","Withdrawing under pressure",10,route):
		_release_pressure_search(sim,u)
		if u.orders.is_empty() and not intent.is_empty():u.orders.append(intent.duplicate())
		for action in sim.actions.actions.values().duplicate():
			if action.unit==u.id and action.channel!="movement":sim.actions.cancel(u,action,sim.time,"urgent_withdrawal")
	return true

static func _pressure_facts(u:Dictionary)->Dictionary:
	var able:=0
	for member in u.get("members",[]):
		if member.hp>0:able+=1
	return {"hp":float(u.hp),"able":able,"last_hit":float(u.last_hit),
		"fired_on":float(u.get("fired_on",-100.0)),"suppression":float(u.suppression)}

static func _new_pressure(u:Dictionary,previous:Dictionary)->bool:
	var current:=_pressure_facts(u)
	return current.hp<float(previous.hp)-0.001 or current.able<int(previous.able) \
		or current.last_hit>float(previous.last_hit) or current.fired_on>float(previous.fired_on) \
		or (current.suppression>0.82 and float(previous.suppression)<=0.82)

static func _pressure_quiet(sim,u:Dictionary)->bool:
	return sim.time-maxf(float(u.last_hit),float(u.get("fired_on",-100.0)))>=CONSOLIDATE_QUIET and float(u.suppression)<=0.2

static func _disengaged(sim,u:Dictionary)->bool:
	if u.maneuver.get("arrived",false) or sim.time<u.commit_until or not _pressure_quiet(sim,u):return false
	if sim.time<float(u.get("pressure_review",0.0)):return false
	u["pressure_review"]=sim.time+0.3
	if not _pressure_contacts(sim,u).is_empty():return false
	u["pressure_resolved"]=_pressure_facts(u)
	var action:Dictionary=sim.actions.active(u,"movement")
	if not action.is_empty():sim.actions.cancel(u,action,sim.time,"disengaged")
	u.path=[]
	resume(sim,u,"Disengaged · resuming objective")
	# A resumed accepted order gets this update; another autonomy choice must
	# not replace it again in the same pass through the director.
	return true

static func _pressure_contacts(sim,u:Dictionary)->Array:
	var threats:Array=[]
	for other in (sim.range_candidates(u.pos,25.0) if sim.ticking else sim.units):
		if other.team==u.team or not sim.alive(other) or not sim.contact_known(u,other) or not sim.effective_unit(other,u.kind):continue
		# Position is read only after the current-contact gate. Copy it so this
		# assessment never follows a hidden actor through a retained reference.
		var observed:Vector2=other.pos
		if u.pos.distance_to(observed)<25.0:threats.append({"id":other.id,"kind":other.kind,"pos":observed})
	return threats

static func _pressure_route_safe(origin:Vector2,route:Array,threats:Array)->bool:
	for threat in threats:
		var nearest:float=origin.distance_to(threat.pos)-2.0
		var previous:Vector2=origin
		for point in route:
			# Checking just waypoints misses a straight route through an enemy
			# whose far endpoint happens to be farther away than the origin.
			if Geometry2D.get_closest_point_to_segment(threat.pos,previous,point).distance_to(threat.pos)<nearest:return false
			previous=point
	return true

static func _pressure_local_response(sim,u:Dictionary,threats:Array)->bool:
	if u.members.is_empty():return false
	var phase:String=u.maneuver.get("phase","")
	if phase=="BOUND" and not u.maneuver.get("arrived",false) and not u.path.is_empty():
		return _pressure_route_safe(u.pos,u.path,threats)
	if phase not in ["","SUPPORT","CONSOLIDATE","BOUND","PRESSURE_WAIT"]:return false
	var medic:bool=u.members.any(func(member):return member.hp>0)
	for member in u.members:
		var point:Vector2=Vector2.INF
		var casualty_care:=false
		if member.hp>0 and member.get("cover_phase","") in ["SEEKING","SETTLING","SHELTERED"]:
			if float(member.get("cover_blocked",0.0))>2.0:continue
			if member.cover_phase!="SHELTERED" and sim.time>float(member.get("cover_deadline",0.0)):continue
			point=member.cover_goal
		elif medic and member.get("wound","")==sim.Infantry.SEVERE and not member.get("stable",false):
			point=member.get("drag_to",member.pos)
			if point.distance_to(member.pos)>sim.Infantry.DRAG_REACH:continue
			if not sim.terrain.segment_clear(member.pos,point,"land",0.42):continue
			casualty_care=true
		if point==Vector2.INF or point.distance_to(u.pos)>sim.Infantry.Cover.LEASH:continue
		if not sim.terrain.cover(point) or not sim.terrain.traversable(point,"land",0.8):continue
		# Buddy aid already accepts this physical shelter. A casualty need not
		# be able to return fire from it, as a new firing position would require.
		if casualty_care:return true
		var weapon:String=sim.Infantry.Cover.member_weapon(u,member)
		if sim.Infantry.Cover.rate(sim,point,threats[0],threats,weapon).ok:return true
	return false

static func _release_pressure_search(sim,u:Dictionary) -> void:
	u["pressure_pending"]=false
	u.erase("pressure_reservations")
	u.get("tactical_navigation",{}).erase("withdrawal")
	sim.terrain.planning.cancel_request("formation",int(u.id),"withdrawal")
	sim.terrain.planning.cancel_request("routes",int(u.id),"maneuver:WITHDRAW")

static func _clear_pressure_wait(sim,u:Dictionary) -> void:
	_release_pressure_search(sim,u)
	u.erase("pressure_route_after")
	u.erase("pressure_retry_facts")
	if u.maneuver.get("phase","")=="PRESSURE_WAIT":resume(sim,u,"Pressure eased · resuming objective")

static func update(sim) -> void:
	if not sim.scenario.get("autonomy",false):return
	for u in sim.units:
		if u.has("wreck_recovery"):continue
		if not sim.alive(u) or sim.definitions[u.kind].get("structure",false) or u.has("building_id") or u.kind=="harvester" or sim.definitions[u.kind].domain!="land":continue
		# A section whose survivors are all down cannot move: nothing to direct.
		if u.get("combat_ineffective",false):continue
		if not u.orders.is_empty() and u.orders[0].has("slot"):continue
		if pressure_response(sim,u):continue
		if u.hold_command:continue
		if not u.members.is_empty() and contact_drill(sim,u):continue
		var intent:Dictionary=u.intent if u.orders.is_empty() else u.orders[0]
		var withdrawing:bool=u.maneuver.get("phase","")=="WITHDRAW"
		# An idle section can withdraw without a parent order. Its arrival,
		# stall and deadline still belong to the active maneuver lifecycle.
		if not withdrawing and u.orders.is_empty() and (intent.is_empty() or intent.mode in ["move","retreat"] or u.maneuver.get("phase","")=="ENGAGE"):
			engage_idle(sim,u)
			continue
		if not withdrawing and (intent.is_empty() or intent.mode in ["move","retreat"]):continue
		# Active maneuvers still reassess observed danger/support at a bounded cadence.
		if u.maneuver.is_empty() and sim.time<u.next_decision:continue
		if not u.maneuver.is_empty() and sim.time<u.get("maneuver_review",0.0):continue
		var priority:=2 if int(u.get("tactical_wake_tick",-1))==sim.action_tick else 0
		if not sim.terrain.planning.request("decisions",int(u.id),"director",priority):continue
		u.maneuver_review=sim.time+0.8
		u.next_decision=sim.time+0.8+float(u.id%4)*0.1
		var contacts:Array=[]
		var allies:Array=[]
		for other in sim.units:
			if other.id==u.id or not sim.alive(other):continue
			var distance:float=u.pos.distance_to(other.pos)
			if other.team!=u.team and distance<25 and sim.contact_known(u,other):contacts.append(other)
			elif other.team==u.team and other.command_group==u.command_group and sim.definitions[other.kind].domain=="land" and (not sim.comms_blocked(u) or distance<14):allies.append(other)
		if not u.maneuver.is_empty():
			var phase:String=u.maneuver.phase
			# Held by contact_drill; only a withdrawal (above) overrides it here.
			if phase in HOLDS:continue
			var lost_support:=false
			if phase=="FLANK" and not u.maneuver.get("support_ids",[]).is_empty():
				lost_support=true
				for ally in allies:
					if ally.id not in u.maneuver.support_ids or u.pos.distance_to(ally.pos)>24:continue
					for threat in contacts:
						if sim.can_fire(ally,threat):lost_support=false
			if u.pos.distance_to(u.maneuver.get("progress_pos",u.pos))>0.5:
				u.maneuver.progress_pos=u.pos;u.maneuver.progress_at=sim.time
			var stalled:bool=not u.maneuver.arrived and sim.time-u.maneuver.get("progress_at",sim.time)>4.0
			# A crowded arrival (Simulation.crowded_arrival) halts a hull short of a
			# spot a friend holds: it never got there. A withdrawal near the rally
			# point has arrived; any other maneuver is blocked, not complete.
			if u.maneuver.arrived and phase!="WITHDRAW" and u.pos.distance_to(u.maneuver.pos)>ARRIVED_SHORT:stalled=true
			if sim.time>u.maneuver.deadline:
				resume(sim,u,"Maneuver timed out · resuming objective")
			elif lost_support:
				resume(sim,u,"Support lost · resuming objective")
			elif stalled:
				resume(sim,u,"Maneuver blocked · resuming objective")
			elif u.maneuver.arrived and sim.time>=u.commit_until:
				if phase=="WITHDRAW" and u.hp<sim.Infantry.capacity(u)*0.55 and sim.time<u.maneuver.deadline-2:continue
				if phase=="WITHDRAW" and _pressure_quiet(sim,u) and _pressure_contacts(sim,u).is_empty():u["pressure_resolved"]=_pressure_facts(u)
				resume(sim,u,"Maneuver complete · resuming objective")
			continue
		if contacts.is_empty():
			# A completed autonomous advance may occupy the only corridor exit.
			# Move its anchor to a nearby clear slot once, retaining the objective.
			if u.orders.is_empty() and intent.mode in ["attack_move","attack"] and sim.time>=u.get("yield_after",0.0):
				for ally in allies:
					if ally.blocked_time<2.0 or ally.orders.is_empty() or u.pos.distance_to(ally.pos)>12:continue
					var away:Vector2=(u.pos-ally.pos).normalized()
					var yielded:=false
					for angle in [0.0,0.8,-0.8,1.6,-1.6]:
						var slot:Vector2=u.pos+away.rotated(angle)*7.0
						if slot.distance_to(intent.pos)>8 or not sim.location_clear(slot,u.kind):continue
						if plan(sim,u,slot,"CLEARWAY","Clearing the objective approach",3):
							u.yield_after=sim.time+20.0;yielded=true;break
					if yielded:break
				if not u.maneuver.is_empty():continue
			if u.pos.distance_to(intent.pos)<8:continue
			# A bounded wait for lagging partners; it cannot indefinitely block progress.
			for ally in allies:
				if sim.time<u.commit_until or ally.orders.is_empty() or ally.hold_command:continue
				if u.pos.distance_to(ally.pos)>18 and u.pos.distance_to(intent.pos)+10<ally.pos.distance_to(intent.pos):
					if plan(sim,u,u.pos,"SUPPORT","Waiting briefly for support",3):break
			continue
		var partner_moving:=false
		var support_ids:Array=[]
		for ally in allies:
			if u.pos.distance_to(ally.pos)>24:continue
			if not ally.maneuver.is_empty() and ally.maneuver.phase=="FLANK":partner_moving=true
			for threat in contacts:
				if sim.can_fire(ally,threat) and ally.id not in support_ids:support_ids.append(ally.id)
		if partner_moving and u.target>=0:
			plan(sim,u,u.pos,"SUPPORT","Covering a repositioning partner",4)
			continue
		if u.kind in ["atgm","aa"] and u.target>=0:continue
		# A flank is useful only when a partner can support it or the route is blocked.
		if not u.orders.is_empty() and u.pos.distance_to(intent.pos)>8 and not partner_moving and (not support_ids.is_empty() or u.blocked_time>1.5):
			var choice:=flank_choice(sim,u,intent.pos,contacts)
			if not choice.is_empty() and plan(sim,u,choice.pos,"FLANK","Repositioning around obstruction" if support_ids.is_empty() else "Flanking with supporting fire",6,choice.path):
				u.maneuver["support_ids"]=support_ids

# Section reaction to contact (infantry). Casualties under fire stop an
# attack-move: the section consolidates on cover where it stands (the anchor
# holds, Cover stays active) until the fire dies down. A section with no cover
# in reach that stays under fire bounds to the nearest real cover within
# BOUND_REACH; prone and firing remains the first response. Explicit move,
# retreat, assault (attack) and hold orders are obeyed as given.
const HOLDS:=["CONSOLIDATE","BOUND","PRESSURE_WAIT"]
const CONSOLIDATE_QUIET:=6.0  # seconds without incoming fire before resuming
const CONSOLIDATE_HOLD:=18.0  # commit; the maneuver deadline adds 12 s
const BOUND_AFTER:=7.0        # sustained incoming fire before a bound
const BOUND_REACH:=20.0
const BOUND_HOLD:=6.0
static func contact_drill(sim,u:Dictionary) -> bool:
	if sim.time<float(u.get("contact_review",0.0)):return u.maneuver.get("phase","") in HOLDS
	u["contact_review"]=sim.time+0.25+float(u.id%4)*0.02
	var able:=0
	for m in u.members:
		if m.hp>0:able+=1
	if able<int(u.get("able_seen",able)):u["casualty_at"]=sim.time
	u["able_seen"]=able
	var fired:bool=sim.Infantry.in_contact(u,sim.time)
	if not fired:u.erase("fire_since")
	elif not u.has("fire_since"):u["fire_since"]=sim.time
	var phase:String=u.maneuver.get("phase","")
	if phase=="WITHDRAW":return false
	if able==0:
		# Nobody left on their feet to hold cover: the hold ends.
		if phase in HOLDS:
			if u.orders.is_empty():u.maneuver={}
			else:resume(sim,u,"Section down · resuming objective")
		return false
	if phase in HOLDS:
		var quiet:bool=sim.time-float(u.get("fired_on",-100.0))>=CONSOLIDATE_QUIET and u.suppression<=0.2
		if sim.time>float(u.maneuver.deadline) or (u.maneuver.arrived and quiet and sim.time-float(u.get("hold_since",0.0))>=2.0):
			if u.orders.is_empty():u.maneuver={};u.reason="Contact over · holding"
			else:resume(sim,u,"Contact over · resuming objective")
			return true
		# A weakened section under threat may still withdraw (update's rule).
		if phase!="PRESSURE_WAIT":return not critical_pressure(u)
	# A section standing where the player moved it (an explicit move, even one
	# completed) keeps that position; only attack-move pauses.
	var mode:String=u.orders[0].mode if not u.orders.is_empty() else str(u.intent.get("mode",""))
	if mode in ["move","retreat","attack"]:return false
	if u.orders.is_empty():mode=""
	if phase in ["","FLANK","CLEARWAY","SUPPORT"] and mode=="attack_move" and fired and sim.time-float(u.get("casualty_at",-100.0))<3.0 and float(u.get("consolidated_at",-100.0))<float(u.casualty_at):
		if plan(sim,u,u.pos,"CONSOLIDATE","Contact · casualties · consolidating on cover",CONSOLIDATE_HOLD):
			u["consolidated_at"]=sim.time
			u["hold_since"]=sim.time
			return true
	if phase in ["","SUPPORT","ENGAGE","PRESSURE_WAIT"] and fired and sim.time-float(u.fire_since)>=BOUND_AFTER and sim.time>=float(u.get("bound_check",0.0)) and caught_open(sim,u):
		if not sim.terrain.planning.request("decisions",int(u.id),"bound",1):
			u["contact_review"]=sim.time
			return false
		u["bound_check"]=sim.time+2.0
		var cover:=bound_destination(sim,u)
		if not cover.is_empty() and plan(sim,u,cover.pos,"BOUND","No cover here · bounding to cover",BOUND_HOLD,cover.path):
			if u.orders.is_empty():u["post"]=cover.pos;u["post_group"]=u.command_group
			u["hold_since"]=sim.time
			return true
	return false

# Cover found no shelter inside the leash for any living soldier (each is
# EXPOSED, or overwatching just after), and the section is not regrouping.
static func caught_open(sim,u:Dictionary) -> bool:
	if u.get("regroup_active",false):return false
	for m in u.members:
		if m.hp>0 and (m.get("in_trench",false) or not sim.Infantry.caught_open(m,sim.time)):return false
	return true

# Nearest real cover beyond the leash (rated against the observed threats like
# a soldier's shelter) and not toward the main threat; the anchor stops a few
# metres short so the soldiers take the cover from there.
static func bound_destination(sim,u:Dictionary) -> Dictionary:
	# One finite bundle: seven rings, at most three routes each (21 total).
	# Admitting individual candidates and restarting on denial would never
	# reach a valid ninth candidate behind eight unreachable ones.
	if not sim.take_route_budget(u.pos,u.pos+Vector2.RIGHT*BOUND_REACH,true,int(u.id),"bound"):
		u["bound_check"]=sim.time
		u["contact_review"]=sim.time
		return {}
	var threats:Array=[]
	var threat:Dictionary={}
	for other in (sim.range_candidates(u.pos,25) if sim.ticking else sim.units):
		if not sim.alive(other) or other.team==u.team or not sim.contact_known(u,other) or not sim.effective_unit(other,u.kind):continue
		if u.pos.distance_to(other.pos)>=25:continue
		threats.append(other)
		if threat.is_empty() or u.pos.distance_to(other.pos)<u.pos.distance_to(threat.pos):threat=other
	var d:Dictionary=sim.definitions[u.kind]
	var weapon:="rifle"
	for member in u.members:
		if sim.Infantry.Cover.member_weapon(u,member)=="atgm":weapon="atgm";break
	for ring in [10.5,12.0,13.5,15.0,16.5,18.0,BOUND_REACH]:
		var found:Array=[]
		for i in 24:
			var point:Vector2=u.pos+Vector2.from_angle(i*TAU/24)*ring
			if not sim.terrain.cover(point) or not sim.terrain.traversable(point,"land",0.8):continue
			if not threat.is_empty() and point.distance_to(threat.pos)<u.pos.distance_to(threat.pos)-2.0:continue
			if not threat.is_empty() and not sim.Infantry.Cover.rate(sim,point,threat,threats,weapon).ok:continue
			var anchor:Vector2=point+(u.pos-point).normalized()*2.5
			if not sim.terrain.traversable(anchor,d.domain,d.radius):continue
			found.append(anchor)
		found.sort_custom(func(a,b):return u.pos.distance_squared_to(a)<u.pos.distance_squared_to(b))
		for anchor in found.slice(0,3):
			var route:Array=sim.terrain.path(u.pos,anchor,d.domain,d.radius,[],sim.terrain.mobility_profile(u.kind))
			if route.is_empty() or sim.Infantry.Cover.route_length(u.pos,route)>BOUND_REACH*1.4:continue
			# The rush must not close on the main threat on its way.
			if not threat.is_empty() and route.any(func(point):return point.distance_to(threat.pos)<u.pos.distance_to(threat.pos)-2.0):continue
			return {"pos":anchor,"path":route}
	return {}

# Idle units (no orders, not holding) that see an enemy they can hurt but cannot
# reach close to firing range, leashed to where they were left. Units manning
# works, garrisons (hold) and busy engineers stay put.
const ENGAGE_LEASH:=14.0
# A sheltered section that just lost its target holds and observes this long
# (re-acquire, wait for spotting) before walking out toward another contact.
const ENGAGE_HOLD:=4.0
static func engage_idle(sim,u:Dictionary)->void:
	if u.target>=0:u["engaged_at"]=sim.time
	if u.maneuver.get("phase","")=="ENGAGE":
		if u.maneuver.arrived or sim.time>float(u.maneuver.deadline) or u.target>=0:
			u.maneuver={};u.reason="Engaging"
		return
	if not u.maneuver.is_empty() or u.target>=0 or sim.time<float(u.get("engage_check",0.0)):return
	if not sim.terrain.planning.request("decisions",int(u.id),"engage"):return
	u["engage_check"]=sim.time+0.7+float(u.id%5)*0.06
	if u.get("post_group",-1)!=u.command_group or not u.has("post"):
		u["post"]=u.pos;u["post_group"]=u.command_group
	if u.has("clearing_id") or sim.Garrison.transit(u)!="":return
	if u.members.any(func(m):return m.hp>0 and (m.get("occupying",false) or m.get("in_trench",false))):return
	if u.kind=="engineer" and sim.units.any(func(s):return s.get("queued_for",-1)==u.id and float(s.get("build_left",0.0))>0):return
	var d:Dictionary=sim.definitions[u.kind]
	var sight:float=float(d.sight)+4.0
	var enemy:Dictionary={};var best:=INF
	# Weapon-range candidate lists are too short here: scan everything (throttled).
	for other in sim.units:
		if not sim.alive(other) or other.team==u.team or sim.passive_work(other) or sim.definitions[other.kind].get("strike",false) or not sim.effective_unit(u,other.kind):continue
		var dist:float=u.pos.distance_to(other.pos)
		if dist<sight and dist<best and sim.contact_known(u,other):best=dist;enemy=other
	if enemy.is_empty():return
	var weapon:String=sim.attack_weapon(u,enemy.kind)
	var reach:float=float(sim.definitions[weapon].range)
	if best<=reach*0.95 and sim.terrain.line_clear(u.pos,enemy.pos):return
	# Soldiers settling into shelters that will see the enemy fire from cover,
	# a pinned section, and one that just lost its target stay behind their
	# shelters rather than walking out.
	for m in u.members:
		if m.hp<=0 or m.get("cover_phase","") not in ["SEEKING","SETTLING","SHELTERED"]:continue
		if u.suppression>0.65 and m.cover_phase=="SHELTERED":return
		if m.cover_phase!="SEEKING" and sim.time-float(u.get("engaged_at",-100.0))<ENGAGE_HOLD:return
		if m.cover_goal.distance_to(enemy.pos)<=reach and sim.terrain.line_clear(m.cover_goal,enemy.pos):return
	var desired:Vector2=enemy.pos+(u.pos-enemy.pos).normalized()*reach*0.8
	var post:Vector2=u.post
	if desired.distance_to(post)>ENGAGE_LEASH:desired=post+(desired-post).limit_length(ENGAGE_LEASH)
	if desired.distance_to(u.pos)<1.5:return
	plan(sim,u,desired,"ENGAGE","Closing to engage spotted enemy",4.0)

static func flank_choice(sim,u:Dictionary,goal:Vector2,contacts:Array) -> Dictionary:
	var d:Dictionary=sim.definitions[u.kind]
	var forward:Vector2=(goal-u.pos).normalized()
	# Both sides belong to one bounded comparison (at most two route calls).
	# A one-slot allowance still evaluates the second side after the first
	# proves blocked, retaining the original candidate order and best score.
	if not sim.take_route_budget(u.pos,u.pos+forward*7.0+forward.orthogonal()*8.0,true,int(u.id),"flank"):
		u.next_decision=sim.time
		return {}
	var avoid:Array=[]
	# Friendly positions are known. Enemy avoidance/scoring uses observed contacts only.
	for other in sim.units:
		if other.id==u.id or not sim.alive(other) or sim.definitions[other.kind].domain!="land":continue
		if other.team!=u.team and other not in contacts:continue
		if u.pos.distance_to(other.pos)>30:continue
		avoid.append({"pos":other.pos,"radius":float(d.radius)+float(sim.definitions[other.kind].radius)+0.1})
		for member in other.members:
			if member.hp>0:avoid.append({"pos":member.pos,"radius":float(d.radius)+float(member.get("body_radius",0.8))+0.1})
	var best:Dictionary={}
	var best_score:=INF
	for side in [1.0,-1.0]:
		var destination:Vector2=u.pos+forward*7.0+forward.orthogonal()*side*8.0
		if destination.distance_to(goal)>u.pos.distance_to(goal)+3:continue
		if not sim.terrain.traversable(destination,d.domain,d.radius):continue
		if avoid.any(func(body):return destination.distance_to(body.pos)<body.radius):continue
		var t0:int=Time.get_ticks_usec() if sim.profiling else 0
		var route:Array=sim.terrain.path(u.pos,destination,d.domain,d.radius,avoid,sim.terrain.mobility_profile(u.kind))
		if sim.profiling:sim._lap("director_path",t0)
		if route.is_empty():continue
		var length:=0.0
		var previous:Vector2=u.pos
		for point in route:length+=previous.distance_to(point);previous=point
		if length>28.0:continue
		var score:float=length+destination.distance_to(goal)*0.5
		for threat in contacts:
			if sim.effective_unit(threat,u.kind) and sim.terrain.line_clear(threat.pos,destination):score+=4.0
		if score<best_score:best={"pos":destination,"path":route};best_score=score
	return best
