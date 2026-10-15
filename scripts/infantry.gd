class_name InfantryActors
extends RefCounted
const Cover=preload("res://scripts/cover_behavior.gd")

static func formation_offset(index:int,count:int)->Vector2:
	if count==3:
		return [Vector2(0,-0.98),Vector2(-0.85,0.49),Vector2(0.85,0.49)][index]
	return Vector2((index%2)*1.7-0.85,(index/2)*1.7-0.85)

static func create(u:Dictionary,d:Dictionary) -> void:
	u["members"]=[]
	if u.kind not in ["rifle","atgm","engineer"]:return
	for i in int(d.members):
		var offset:=formation_offset(i,int(d.members))
		u.members.append({"index":i,"offset":offset,"pos":u.pos+offset,"hp":float(d.hp)/int(d.members),"max_hp":float(d.hp)/int(d.members),"cooldown":i*0.19,"target":-1,"aim":0.0,"suppression":0.0,"last_hit":-100.0,"last_shot":-100.0,"facing":u.facing,"state":"HOLDING","travel":0.0,"phase":i*1.7,"cover_goal":Vector2.ZERO,"cover_until":0.0,"rounds":6 if not (u.kind=="atgm" and i==0) else 1,"reload_until":0.0,"speed":0.0,"posture":"STANDING","body_radius":0.8,"posture_until":0.0})
	u["member_hp_snapshot"]=u.hp

static func reconcile(u:Dictionary) -> void:
	if u.members.is_empty():return
	# External setup/tests and legacy squad recovery remain compatible. Combat
	# updates members directly and immediately publishes the new aggregate.
	if not is_equal_approx(u.hp,float(u.member_hp_snapshot)):
		var total:=0.0
		for member in u.members:total+=member.hp
		if total>0:
			for member in u.members:member.hp=minf(member.max_hp,member.hp*u.hp/total)
	publish(u)

static func publish(u:Dictionary) -> void:
	u.hp=0.0
	for member in u.members:u.hp+=member.hp
	u.member_hp_snapshot=u.hp

static func move(u:Dictionary,sim,dt:float) -> void:
	if not u.members.is_empty() and sim.scenario.get("autonomy",false):update_regroup(u,sim)
	# The threat scan (line-of-fire checks against every nearby enemy) runs ~3x a
	# second per section, staggered by id, instead of every 30 Hz tick. A new
	# order still clears stale cover immediately.
	var ordered:bool=u.get("cover_command",-1)!=u.command_group
	if ordered or sim.time>=u.get("cover_next",0.0):
		u["cover_command"]=u.command_group
		u["cover_next"]=sim.time+0.3+float(u.id%5)*0.02
		Cover.update(u,sim)
	for member in u.members:
		if member.hp<=0:continue
		member.cooldown-=dt
		member.suppression=maxf(0,member.suppression-dt*0.12)
		var offset:Vector2=member.offset
		var desired:Vector2=u.pos+offset
		if sim.scenario.get("autonomy",false):
			var phase:String=member.get("cover_phase","")
			if u.hold_command:desired=member.pos
			elif u.get("regroup_active",false):desired=regroup_destination(u,member,sim,desired)
			elif phase=="OVERWATCH":desired=member.pos
			elif phase in ["SEEKING","SETTLING","SHELTERED"]:
				while not member.cover_path.is_empty() and member.pos.distance_to(member.cover_path[0])<0.15:member.cover_path.pop_front()
				desired=member.cover_goal if member.cover_path.is_empty() else member.cover_path[0]
			elif member.pos.distance_to(desired)>0.3:
				desired=regroup_destination(u,member,sim,desired)
		var old:Vector2=member.pos
		var speed:float=float(sim.definitions[u.kind].speed)*(1.04+member.index*0.035)*sim.terrain.ground_speed(old,"infantry")
		if member.suppression>0.6:speed*=0.75
		if member.get("cover_phase","")=="SEEKING":speed*=1.2
		if not u.orders.is_empty() and u.orders[0].mode=="retreat":speed*=1.2
		if sim.scenario.get("autonomy",false):
			speed=minf(speed,sqrt(2.0*12.0*old.distance_to(desired)))
			member.speed=move_toward(member.speed,speed,dt*14.0)
			speed=member.speed
		if sim.scenario.get("autonomy",false) and member.posture=="PRONE":
			# Recover from the ground before moving; preserve the larger footprint.
			if desired.distance_to(old)>0.2:
				member.posture="RISING"
				member.posture_until=sim.time+0.45
			else:speed=0.0
		if member.get("posture","")=="RISING" and sim.time<member.posture_until:speed=0.0
		var next:Vector2=old.move_toward(desired,speed*dt)
		# Anticipatory avoidance: sidestep soldiers/vehicles a few metres ahead and
		# ease off when someone is right in front, instead of shoving through.
		if sim.scenario.get("autonomy",false) and speed>0.0 and old.distance_to(desired)>0.3:
			var heading:Vector2=(desired-old).normalized()
			var steer:Vector3=avoidance(u,member,old,heading,sim,old.distance_to(desired))
			if steer.z>0.0:
				var adjusted:Vector2=(heading+Vector2(steer.x,steer.y)).normalized()
				if adjusted.dot(heading)>0.2:
					speed*=1.0-0.45*steer.z
					next=old+adjusted*minf(speed*dt,old.distance_to(desired))
		# A stationary actor has no proposed displacement to validate.
		if speed>0.0 and desired!=old:
			var clear:bool=sim.terrain.segment_clear(old,next,"land",0.42)
			for other in u.members:
				# Squadmates keep a shoulder's width but may always step apart.
				if other.index!=member.index and other.hp>0 and next.distance_to(other.pos)<1.3 and next.distance_to(other.pos)<old.distance_to(other.pos):clear=false
			if sim.scenario.get("autonomy",false):clear=clear and actor_clear(u,member,next,sim)
			if clear:member.pos=next
			elif sim.scenario.get("autonomy",false):
				# Individual local steering; retain the chosen cover slot.
				for angle in [0.65,-0.65,1.2,-1.2]:
					var step:Vector2=old+(desired-old).normalized().rotated(angle)*minf(speed*dt,old.distance_to(desired))
					if actor_clear(u,member,step,sim):member.pos=step;break
		sim.relocate_actor(u,member,old)
		member.travel=old.distance_to(member.pos)
		member["regroup_blocked"]=member.get("regroup_blocked",0.0)+dt if member.travel<0.001 and old.distance_to(desired)>0.3 else 0.0
		if member.get("cover_phase","")=="SEEKING":
			member.cover_blocked=member.get("cover_blocked",0.0)+dt if member.travel<0.001 else 0.0
			if member.pos.distance_to(member.cover_goal)<0.2:
				member.cover_phase="SETTLING"
				member["cover_settle_until"]=sim.time+0.45
				member.cover_until=sim.time+4.0
		if member.get("cover_phase","")=="SETTLING" and sim.time>=member.cover_settle_until:
			member.cover_phase="SHELTERED"
			member.cover_deadline=sim.time+8.0
		member.phase+=member.travel*(6.5 if sim.scenario.get("autonomy",false) else 3.0)
		if member.travel>0.001:
			member.facing=(member.pos-old).normalized()
			member.state="MARCHING"
		else:member.state="HOLDING"
		# Preserve the squad's conservative navigation envelope. The leader
		# waits for stragglers instead of dragging soldiers through obstacles.

# Return paths are local, footprint-checked, throttled and tied to the current
# command. A squad pauses before the leash goes taut so actors can round walls.
static func update_regroup(u:Dictionary,sim) -> void:
	var command:int=u.command_group
	if u.get("regroup_command",-1)!=command or u.hold_command:
		u["regroup_command"]=command
		u["regroup_active"]=false
		for member in u.members:
			member["regroup_path"]=[]
			member["regroup_after"]=0.0
	if u.hold_command:return
	if u.pos.distance_to(u.get("regroup_progress_pos",u.pos))>1.0 or not u.has("regroup_progress_at"):
		u["regroup_progress_pos"]=u.pos
		u["regroup_progress_at"]=sim.time
	var stalled_cover:bool=Cover.seeking(u) and sim.time-u.regroup_progress_at>8.0
	var spread:=0.0
	for member in u.members:
		if member.hp>0:spread=maxf(spread,member.pos.distance_to(u.pos))
	if u.get("regroup_active",false):
		if spread<2.8:
			u.regroup_active=false
			u["regroup_count"]=u.get("regroup_count",0)+1
			u["cover_resume_after"]=sim.time+6.0
			u.regroup_progress_at=sim.time
			u.reason="Section reunited · resuming orders"
		# Seeking already pauses the anchor. Let valid shelter trips finish; only
		# recover them when progress times out, rather than at the return threshold.
	elif (not u.orders.is_empty() or not u.maneuver.is_empty()) and ((spread>7.5 and not Cover.seeking(u)) or (stalled_cover and spread>2.8)):
		u["regroup_active"]=true
		u.reason="Regrouping separated soldiers"
		for member in u.members:
			Cover.clear(member)
			member["regroup_path"]=[]
			member["regroup_after"]=0.0

static func regroup_destination(u:Dictionary,member:Dictionary,sim,goal:Vector2) -> Vector2:
	var route:Array=member.get("regroup_path",[])
	if goal.distance_to(member.get("regroup_goal",goal))>1.0:
		route=[];member["regroup_after"]=0.0
	while not route.is_empty() and member.pos.distance_to(route[0])<0.15:route.pop_front()
	var radius:float=member.get("body_radius",0.8)
	var obstructed:bool=not sim.terrain.segment_clear(member.pos,goal,"land",radius)
	if (obstructed or member.get("regroup_blocked",0.0)>0.5) and sim.time>=member.get("regroup_after",0.0):
		member["regroup_after"]=sim.time+1.0
		member["regroup_goal"]=goal
		var avoid:Array=[]
		for entry in sim.actor_candidates(member.pos,goal,Cover.LEASH):
			var other:Dictionary=entry.unit;var peer:Dictionary=entry.actor
			if not sim.alive(other) or peer.hp<=0 or (other.id==u.id and not other.members.is_empty() and peer.index==member.index):continue
			var clearance:float=radius+(float(sim.definitions[other.kind].radius) if other.members.is_empty() else float(peer.get("body_radius",0.8)))-0.04
			# Match actor_clear: soldiers of other sections squeeze past shoulder to shoulder.
			if not other.members.is_empty() and other.id!=u.id:clearance*=0.7
			avoid.append({"pos":peer.pos,"radius":clearance})
		var candidate:Array=sim.terrain.path(member.pos,goal,"land",radius,avoid,"infantry")
		if candidate.is_empty():
			# Tight formations can have a clear exact slot but an occupied nearest
			# grid centre. Approach through a nearby clear centre, checking the
			# final edge as well; never remove peers from avoidance to make it fit.
			var approaches:Array=[]
			var cell:Vector2=goal.floor()+Vector2(0.5,0.5)
			for x in range(-2,3):
				for y in range(-2,3):
					var point:Vector2=cell+Vector2(x,y)
					if point.distance_to(u.pos)>Cover.LEASH or point.distance_to(goal)>3.0:continue
					if not sim.terrain.segment_clear(point,goal,"land",radius) or not sim.terrain.avoids_bodies(point,goal,avoid):continue
					approaches.append({"pos":point,"cost":member.pos.distance_to(point)+point.distance_to(goal)})
			approaches.sort_custom(func(a,b):return a.cost<b.cost)
			for approach in approaches.slice(0,8):
				candidate=sim.terrain.path(member.pos,approach.pos,"land",radius,avoid,"infantry")
				if not candidate.is_empty():
					candidate.append(goal)
					break
		var length:=0.0
		var previous:Vector2=member.pos
		var bounded:=not candidate.is_empty()
		for point in candidate:
			if point.distance_to(u.pos)>Cover.LEASH:bounded=false
			length+=previous.distance_to(point);previous=point
		if bounded and length<=28.0:route=candidate
	member["regroup_path"]=route
	return goal if route.is_empty() else route[0]

static func hit(u:Dictionary,amount:float,source:Vector2,now:float) -> void:
	reconcile(u)
	if u.members.is_empty():
		u.hp-=amount
		return
	var chosen:Dictionary={}
	var nearest:=INF
	for member in u.members:
		if member.hp<=0:continue
		var distance:float=source.distance_squared_to(member.pos)
		if distance<nearest:chosen=member;nearest=distance
	if chosen.is_empty():return
	chosen.hp=maxf(0,chosen.hp-amount)
	chosen.last_hit=now
	chosen.suppression=minf(1,chosen.suppression+0.35)
	chosen.state="DOWN" if chosen.hp<=0 else "BRACING"
	publish(u)

# High explosive (shells, rockets, missiles, autocannon): the soldier nearest
# the shooter takes the full hit and others within the blast radius take
# fragment damage, so HE fire breaks up a section instead of chipping one man.
static func blast(u:Dictionary,amount:float,source:Vector2,now:float,radius:float=3.2) -> void:
	reconcile(u)
	if u.members.is_empty():
		u.hp-=amount
		return
	var primary:Dictionary={}
	var nearest:=INF
	for member in u.members:
		if member.hp<=0:continue
		var d:float=source.distance_squared_to(member.pos)
		if d<nearest:primary=member;nearest=d
	if primary.is_empty():return
	for member in u.members:
		if member.hp<=0:continue
		var gap:float=member.pos.distance_to(primary.pos)
		if member!=primary and gap>radius:continue
		var share:float=1.0 if member==primary else 0.6*(1.0-0.5*gap/radius)
		member.hp=maxf(0,member.hp-amount*share)
		member.last_hit=now
		member.suppression=minf(1,member.suppression+0.45)
		member.state="DOWN" if member.hp<=0 else "BRACING"
	publish(u)

static func capacity(u:Dictionary) -> float:
	if u.members.is_empty():return u.max_hp
	var total:=0.0
	for member in u.members:
		if member.hp>0:total+=member.max_hp
	return total

static func recover(u:Dictionary,amount:float) -> float:
	var restored:=0.0
	for member in u.members:
		if member.hp<=0:continue
		var heal:=minf(amount-restored,member.max_hp-member.hp)
		member.hp+=heal
		restored+=heal
		if restored>=amount:break
	publish(u)
	return restored

static func actor_clear(u:Dictionary,member:Dictionary,to:Vector2,sim) -> bool:
	if not sim.terrain.segment_clear(member.pos,to,"land",member.get("body_radius",0.8)):return false
	if to.distance_to(u.pos)>Cover.LEASH:return false
	var body_radius:float=member.get("body_radius",0.8)
	var min_x:=minf(member.pos.x,to.x)
	var max_x:=maxf(member.pos.x,to.x)
	var min_y:=minf(member.pos.y,to.y)
	var max_y:=maxf(member.pos.y,to.y)
	for entry in sim.actor_candidates(member.pos,to,body_radius):
		var other:Dictionary=entry.unit
		var peer:Dictionary=entry.actor
		if not sim.alive(other) or peer.hp<=0:continue
		# Retain the original squad broad-phase contract exactly.
		if other.pos.x<min_x-12.5 or other.pos.x>max_x+12.5 or other.pos.y<min_y-12.5 or other.pos.y>max_y+12.5:continue
		if other.members.is_empty():
			# Stepping away from a vehicle is always allowed (no mutual lock).
			if to.distance_squared_to(other.pos)>=member.pos.distance_squared_to(other.pos):continue
			if segment_distance(member.pos,to,other.pos)<float(sim.definitions[other.kind].radius)+body_radius:return false
		else:
			if other.id==u.id and peer.index==member.index:continue
			# Soldiers of another section may squeeze past (shoulder to shoulder).
			var clearance:=body_radius+float(peer.get("body_radius",0.8))-0.05
			if other.id!=u.id:clearance*=0.7
			if peer.pos.x<min_x-clearance or peer.pos.x>max_x+clearance or peer.pos.y<min_y-clearance or peer.pos.y>max_y+clearance:continue
			# Never block a step that opens distance: interleaved soldiers can always
			# separate instead of locking each other in place.
			var before:float=member.pos.distance_to(peer.pos)
			var after:float=to.distance_to(peer.pos)
			if after>=before:continue
			# Jammed against another section: brush past it as a last resort, but
			# shoulders never pass through each other.
			if other.id!=u.id and member.get("regroup_blocked",0.0)>0.8 and to.distance_to(peer.pos)>=0.65:continue
			if segment_distance(member.pos,to,peer.pos)<clearance:return false
	return true

# Lateral steering for one soldier. Looks AVOID_AHEAD metres down its heading
# for bodies of other sections (and vehicles) inside a comfortable passing
# lane; returns (steer.x, steer.y, urgency 0..1). Everyone passes on their own
# right when a body is dead ahead, so two oncoming soldiers sidestep apart
# instead of mirroring each other.
const AVOID_AHEAD:=3.5
static func avoidance(u:Dictionary,member:Dictionary,from:Vector2,heading:Vector2,sim,remaining:float=AVOID_AHEAD) -> Vector3:
	var right:=Vector2(-heading.y,heading.x)
	var body:float=member.get("body_radius",0.8)
	var push:=Vector2.ZERO
	var urgency:=0.0
	for entry in sim.actor_candidates(from,from+heading*AVOID_AHEAD,body+0.5):
		var other:Dictionary=entry.unit
		var peer:Dictionary=entry.actor
		if other.id==u.id or not sim.alive(other) or peer.hp<=0:continue
		var relative:Vector2=peer.pos-from
		var ahead:float=relative.dot(heading)
		# Bodies beyond our own slot are not in the way (arrival crowds).
		if ahead<-0.2 or ahead>minf(AVOID_AHEAD,remaining+body):continue
		var lane:float=body+(float(sim.definitions[other.kind].radius)+0.6 if other.members.is_empty() else float(peer.get("body_radius",0.8))+0.35)
		var lateral:float=relative.dot(right)
		if absf(lateral)>=lane:continue
		# Someone walking the same way at a similar pace is not an obstacle.
		var peer_motion:Vector2=peer.get("facing",Vector2.ZERO)*(1.0 if peer.get("travel",0.0)>0.001 else 0.0)
		if peer_motion.dot(heading)>0.7 and ahead>body*2.0:continue
		var side:float=-signf(lateral) if absf(lateral)>0.12 else 1.0
		var weight:float=(1.0-maxf(ahead,0.0)/AVOID_AHEAD)*(1.0-absf(lateral)/lane)
		push+=right*side*weight*1.6
		urgency=maxf(urgency,weight)
	return Vector3(push.x,push.y,urgency)

static func choose_cover(u:Dictionary,member:Dictionary,sim) -> Vector2:
	var best:Vector2=Vector2.ZERO
	var score:float=INF
	for ring in [1.2,2.4,3.6]:
		for index in 12:
			var candidate:Vector2=u.pos+Vector2.from_angle(index*TAU/12)*ring
			if not sim.terrain.cover(candidate) or not actor_clear(u,member,candidate,sim):continue
			var reserved:=false
			for peer in u.members:
				if peer.index!=member.index and peer.hp>0 and peer.cover_goal!=Vector2.ZERO and candidate.distance_to(peer.cover_goal)<1.6:reserved=true
			if reserved:continue
			var cost:float=member.pos.distance_squared_to(candidate)
			if cost<score:score=cost;best=candidate
	return best

static func segment_distance(a:Vector2,b:Vector2,point:Vector2) -> float:
	var delta:=b-a
	return (a+delta*clampf((point-a).dot(delta)/maxf(0.00001,delta.length_squared()),0,1)).distance_to(point)

static func prone_clear(u:Dictionary,member:Dictionary,sim) -> bool:
	if not sim.terrain.traversable(member.pos,"land",1.15):return false
	for other in sim.units:
		if not sim.alive(other) or sim.definitions[other.kind].domain!="land":continue
		if other.members.is_empty():
			if member.pos.distance_to(other.pos)<1.15+float(sim.definitions[other.kind].radius):return false
		else:
			for peer in other.members:
				if peer.hp>0 and not (other.id==u.id and peer.index==member.index) and member.pos.distance_to(peer.pos)<1.15+float(peer.get("body_radius",0.8)):return false
	return true
