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

static func plan(sim,u:Dictionary,pos:Vector2,phase:String,reason:String,duration:float=6.0, route_hint:Array=[]) -> bool:
	if phase=="SUPPORT" and sim.time<u.get("support_after",0.0):return false
	var d:Dictionary=sim.definitions[u.kind]
	if not sim.terrain.traversable(pos,d.domain,d.radius):return false
	for other in sim.units:
		if other.id==u.id or not sim.alive(other) or other.team!=u.team:continue
		if not other.maneuver.is_empty() and pos.distance_to(other.maneuver.pos)<float(d.radius)+float(sim.definitions[other.kind].radius)+0.4:return false
	# Over the tick's route budget the maneuver is not taken now; the next
	# decision (<1 s) reconsiders it.
	if route_hint.is_empty() and not sim.take_route_budget(u.pos,pos,true):return false
	var t0:int=Time.get_ticks_usec() if sim.profiling else 0
	var route:Array=route_hint if not route_hint.is_empty() else sim.terrain.path(u.pos,pos,d.domain,d.radius,[],sim.terrain.mobility_profile(u.kind))
	if sim.profiling:sim._lap("director_path",t0)
	if route.is_empty():return false
	u.maneuver={"pos":pos,"mode":"retreat" if phase=="WITHDRAW" else "maneuver","phase":phase,"arrived":u.pos.distance_to(pos)<0.15,"progress_pos":u.pos,"progress_at":sim.time,"deadline":sim.time+duration+(37.0 if phase=="WITHDRAW" else 12.0)}
	u.path=[] if u.maneuver.arrived else route
	if phase=="SUPPORT":u.support_after=sim.time+20.0
	u.commit_until=sim.time+duration
	u.reason=reason
	u.next_decision=sim.time+duration
	sim.events.append({"type":"decision","unit":u.id,"phase":phase,"reason":reason,"pos":pos})
	return true

static func resume(sim,u:Dictionary,reason:String="Regrouping toward objective") -> void:
	u.maneuver={}
	u.reason=reason
	u.next_decision=sim.time+5.0
	u.commit_until=sim.time+5.0
	if not u.orders.is_empty():
		if not sim.take_route_budget(u.pos,u.orders[0].pos):
			sim.defer_route(u,"direct")
			return
		var d:Dictionary=sim.definitions[u.kind]
		var t0:int=Time.get_ticks_usec() if sim.profiling else 0
		u.path=sim.terrain.path(u.pos,u.orders[0].pos,d.domain,d.radius,[],sim.terrain.mobility_profile(u.kind))
		if sim.profiling:sim._lap("director_path",t0)

static func update(sim) -> void:
	if not sim.scenario.get("autonomy",false):return
	for u in sim.units:
		if not sim.alive(u) or sim.definitions[u.kind].get("structure",false) or u.has("building_id") or u.kind=="harvester" or sim.definitions[u.kind].domain!="land" or u.hold_command:continue
		# A section whose survivors are all down cannot move: nothing to direct.
		if u.get("combat_ineffective",false):continue
		if not u.members.is_empty() and contact_drill(sim,u):continue
		var intent:Dictionary=u.intent if u.orders.is_empty() else u.orders[0]
		if u.orders.is_empty() and (intent.is_empty() or intent.mode in ["move","retreat"] or u.maneuver.get("phase","")=="ENGAGE"):
			engage_idle(sim,u)
			continue
		if intent.is_empty() or intent.mode in ["move","retreat"]:continue
		# Active maneuvers still reassess observed danger/support at a bounded cadence.
		if u.maneuver.is_empty() and sim.time<u.next_decision:continue
		if not u.maneuver.is_empty() and sim.time<u.get("maneuver_review",0.0):continue
		u.maneuver_review=sim.time+0.8
		u.next_decision=sim.time+0.8+float(u.id%4)*0.1
		var contacts:Array=[]
		var allies:Array=[]
		for other in sim.units:
			if other.id==u.id or not sim.alive(other):continue
			var distance:float=u.pos.distance_to(other.pos)
			if other.team!=u.team and distance<25 and sim.contact_known(u,other):contacts.append(other)
			elif other.team==u.team and other.command_group==u.command_group and sim.definitions[other.kind].domain=="land" and (not sim.comms_blocked(u) or distance<14):allies.append(other)
		var danger:=false
		for threat in contacts:
			if sim.effective_unit(threat,u.kind):danger=true
		if u.maneuver.get("phase","")!="WITHDRAW" and danger and (u.hp<sim.Infantry.capacity(u)*0.33 or u.suppression>0.82):
			var reservations:Array[Dictionary]=[]
			for other in sim.units:
				if other.id==u.id or not sim.alive(other) or other.team!=u.team:continue
				reservations.append({"pos":other.maneuver.get("pos",other.pos),"radius":sim.definitions[other.kind].radius,"layer":sim.collision_layer(other)})
			var destination:Vector2=sim.formation_slot(sim.rally_point(u),u,reservations)
			if plan(sim,u,destination,"WITHDRAW","Withdrawing under pressure",10):
				if u.orders.is_empty():u.orders.append(intent.duplicate())
				continue
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
const HOLDS:=["CONSOLIDATE","BOUND"]
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
		return u.hp>=sim.Infantry.capacity(u)*0.33
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
	if phase in ["","SUPPORT","ENGAGE"] and fired and sim.time-float(u.fire_since)>=BOUND_AFTER and sim.time>=float(u.get("bound_check",0.0)) and caught_open(sim,u):
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
	var threats:Array=[]
	var threat:Dictionary={}
	for other in (sim.range_candidates(u.pos,25) if sim.ticking else sim.units):
		if not sim.alive(other) or other.team==u.team or not sim.contact_known(u,other) or not sim.effective_unit(other,u.kind):continue
		if u.pos.distance_to(other.pos)>=25:continue
		threats.append(other)
		if threat.is_empty() or u.pos.distance_to(other.pos)<u.pos.distance_to(threat.pos):threat=other
	var d:Dictionary=sim.definitions[u.kind]
	var weapon:String="atgm" if u.kind=="atgm" else "rifle"
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
	var weapon:String=u.kind if u.members.is_empty() else ("atgm" if u.kind=="atgm" and sim.effective_weapon("atgm",enemy.kind) else "rifle")
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
