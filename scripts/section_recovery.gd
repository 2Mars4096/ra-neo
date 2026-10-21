extends RefCounted
# A new wreck can overlap an abstract section envelope while every soldier is
# still physically clear. Only that starting overlap may be left: static walls,
# other dynamic blocks, the actual wreck body and all soldier movement keep
# their normal collision checks. No position is assigned during route preview.
const KEY:="wreck_recovery"
const BODY:=0.8
const REACH:=8.0

static func eligible(sim,u:Dictionary,release_hold:bool=false)->bool:
	return sim.alive(u) and sim.scenario.get("autonomy",false) and not u.members.is_empty() and sim.definitions[u.kind].domain=="land" and not u.get("combat_ineffective",false) and (release_hold or not u.hold_command) and not sim.Garrison.inside(u) and sim.Garrison.transit(u)=="" and not u.has("garrison_target")

static func bodies_clear(sim,u:Dictionary)->bool:
	for member in u.members:
		if member.hp>0 and not sim.terrain.traversable(member.pos,"land",float(member.get("body_radius",BODY))):return false
	return true

static func pressed(sim,u:Dictionary)->Array:
	var result:Array=[]
	var radius:float=sim.definitions[u.kind].radius
	for wreck in sim.VehicleDamage.wrecks(sim):
		if not wreck.has("nav_rect"):continue
		var rect:Rect2=wreck.nav_rect
		if sim.terrain.dynamic_blocks.has(rect) and sim.terrain.circle_rect(u.pos,radius+sim.terrain.OBSTACLE_MARGIN,rect):result.append(rect)
	return result

# For a convex rectangle, a nonnegative dot with its outward normal means the
# entire straight step opens (or keeps) the starting gap, never crosses it.
static func opens_gap(from:Vector2,to:Vector2,blocks:Array)->bool:
	for rect in blocks:
		var outward:Vector2=from-from.clamp(rect.position,rect.end)
		if outward.length_squared()<0.000001 or (to-from).dot(outward)<-0.000001:return false
	return true

static func step_clear(sim,u:Dictionary,to:Vector2,blocks:Array)->bool:
	if not opens_gap(u.pos,to,blocks) or not bodies_clear(sim,u):return false
	var radius:float=sim.definitions[u.kind].radius
	if not sim.terrain.traversable(u.pos,"land",radius,blocks) or not sim.terrain.traversable(u.pos,"land",BODY):return false
	# The section anchor never crosses the physical wreck; only its conservative
	# envelope is waived for rectangles it already overlapped at recovery start.
	if not sim.terrain.segment_clear(u.pos,to,"land",BODY):return false
	# Direct commands run between ticks; their spatial buckets may describe the
	# previous tick. Only this rare bounded preview needs the full unit list.
	return sim.movement_clear(u,to,sim.movement_neighbors(u) if sim.ticking else sim.units,blocks)

static func plan(sim,u:Dictionary,release_hold:bool=false)->Dictionary:
	if not sim.has_meta(sim.VehicleDamage.WRECKS):return {}
	if not eligible(sim,u,release_hold):return {}
	var radius:float=sim.definitions[u.kind].radius
	if sim.terrain.traversable(u.pos,"land",radius):return {}
	var blocks:=pressed(sim,u)
	if blocks.is_empty() or not bodies_clear(sim,u) or not sim.terrain.traversable(u.pos,"land",BODY):return {}
	# A wall, tree, shoreline or unrelated structure is never waived.
	if not sim.terrain.traversable(u.pos,"land",radius,blocks):return {}
	var away:=Vector2.ZERO
	for rect in blocks:away+=(u.pos-u.pos.clamp(rect.position,rect.end)).normalized()
	var angle:=away.angle()
	for ring in range(1,int(REACH*2)+1):
		for index in 32:
			var spot:Vector2=u.pos+Vector2.from_angle(angle+index*TAU/32.0)*float(ring)*0.5
			if not sim.terrain.traversable(spot,"land",radius):continue
			if step_clear(sim,u,spot,blocks):return {"pos":spot,"blocks":blocks}
	return {}

static func begin(sim,u:Dictionary,recovery:Dictionary)->void:
	u[KEY]=recovery.duplicate()
	u[KEY]["retry_at"]=sim.time+0.5
	# A SUPPORT/ENGAGE hold is no longer a valid position, but the player's
	# orders, queued commands, intent and command group remain authoritative.
	u.maneuver={}
	u.erase("engage_shift")
	u.path.clear()
	u.erase("route_pending")
	u.reason="Wreck appeared · clearing formation space"

static func refresh(sim)->void:
	if sim.VehicleDamage.wrecks(sim).is_empty():return
	for u in sim.units:
		var recovery:=plan(sim,u)
		if not recovery.is_empty():begin(sim,u,recovery)

# Called independently of the tactical moving/holding choice. Otherwise the
# arrived SUPPORT maneuver that exposed this bug would never start its exit.
static func step(sim,u:Dictionary,dt:float)->bool:
	if not u.has(KEY):return false
	if not eligible(sim,u):u.erase(KEY);return false
	var recovery:Dictionary=u[KEY]
	var goal:Vector2=recovery.pos
	var speed:float=float(sim.definitions[u.kind].speed)*sim.terrain.ground_speed(u.pos,"infantry")
	if u.suppression>0.6:speed*=0.6
	if sim.Infantry.carrying(u):speed*=sim.Infantry.CARRY_SCALE
	var next:Vector2=u.pos.move_toward(goal,speed*dt)
	if not step_clear(sim,u,next,recovery.blocks):
		# Geometry or traffic can invalidate the cached exit after the anchor has
		# already cleared the old wreck. Resume planning from its actual position
		# instead of remaining in recovery while no starting overlap exists.
		if sim.terrain.traversable(u.pos,"land",float(sim.definitions[u.kind].radius)):
			u.erase(KEY)
			sim.start_next_order(u)
			return true
		if sim.time>=float(recovery.retry_at):
			recovery.retry_at=sim.time+0.5
			var replacement:=plan(sim,u)
			if not replacement.is_empty():begin(sim,u,replacement)
		u.speed_now=0.0
		u.state="YIELDING"
		return true
	var previous:Vector2=u.pos
	var old_bucket:Vector3i=sim.bucket(u)
	u.pos=next
	u.speed_now=previous.distance_to(next)/maxf(dt,0.00001)
	if next!=previous:u.facing=(next-previous).normalized()
	u.blocked_time=0.0
	u.state="REPOSITIONING"
	var new_bucket:Vector3i=sim.bucket(u)
	if new_bucket!=old_bucket:
		if sim.spatial.has(old_bucket):sim.spatial[old_bucket].erase(u)
		if not sim.spatial.has(new_bucket):sim.spatial[new_bucket]=[]
		sim.spatial[new_bucket].append(u)
	if next.distance_to(goal)<0.001:
		u.erase(KEY)
		u.reason="Clear of wreck · resuming orders"
		sim.start_next_order(u)
	return true
