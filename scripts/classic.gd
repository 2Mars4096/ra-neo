extends RefCounted

const PRODUCER={"rifle":"barracks","atgm":"barracks","tank":"factory","aa":"factory","drone":"factory","harvester":"hq"}
const BUILDINGS=["power","refinery","barracks","factory"]
const VehicleDamage=preload("res://scripts/vehicle_damage.gd")

static func setup(sim) -> void:
	var extra:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/classic_units.json"))
	sim.definitions.merge(extra)
	for weapon in sim.definitions:
		if not sim.effectiveness.has(weapon):sim.effectiveness[weapon]={}
		for target in sim.definitions:
			if extra.has(weapon):sim.effectiveness[weapon][target]=0.0
			elif extra.has(target):sim.effectiveness[weapon][target]=(0.4 if weapon=="rifle" else 1.0) if target=="harvester" else (0.0 if weapon in ["rifle","drone"] else 0.8)
	sim.classic={"enemy_credits":900.0,"ai_clock":1.0,"attack_clock":55.0,"fields":[{"pos":Vector2(24,38),"remaining":6000.0},{"pos":Vector2(60,33),"remaining":6000.0}],"started":false}
	if sim.scenario.has("resource_fields"):
		sim.classic.fields=[]
		for field in sim.scenario.resource_fields:
			sim.classic.fields.append({"pos":Vector2(field[0],field[1]),"remaining":float(field[2])})
	sim.credits=900

static func populate(sim) -> void:
	for team in 2:
		var home:=Vector2(10,sim.terrain.world_size.y-11) if team==0 else Vector2(sim.terrain.shore_x-14,9)
		var hq=sim.spawn("hq",team,home)
		hq["build_left"]=0.0;hq["queue"]=[];hq["rally"]=home+Vector2(0,-8 if team==0 else 8)
		for kind in ["rifle","rifle","harvester"]:sim.spawn(kind,team,home+Vector2(8,-4 if team==0 else 4))
	sim.classic.started=true
	sync_obstacles(sim)

static func wallet(sim,team:int) -> float:
	return sim.credits if team==0 else sim.classic.enemy_credits

static func spend(sim,team:int,amount:float) -> void:
	if team==0:sim.credits-=amount
	else:sim.classic.enemy_credits-=amount

static func structures(sim,team:int,kind:String="",ready:bool=true) -> Array:
	return sim.living(team).filter(func(u):return sim.definitions[u.kind].get("structure",false) and (kind=="" or u.kind==kind) and (not ready or u.get("build_left",0.0)<=0))

static func power(sim,team:int) -> Vector2:
	var capacity:=0.0
	var demand:=0.0
	for u in structures(sim,team):
		var value:float=sim.definitions[u.kind].get("power",0)
		if u.kind=="hq":capacity+=12
		elif value<0:capacity-=value
		else:demand+=value
	return Vector2(capacity,demand)

static func can_build(sim,kind:String,team:int,pos:Vector2) -> bool:
	if not kind in BUILDINGS or structures(sim,team,"hq").is_empty() or wallet(sim,team)<sim.definitions[kind].cost:return false
	for u in structures(sim,team,"",false):
		if u.get("build_left",0.0)>0:return false
	for field in sim.classic.fields:
		if pos.distance_to(field.pos)<7.5:return false
	var nearby:=false
	for u in structures(sim,team):
		if u.pos.distance_to(pos)<23:nearby=true
	if not nearby or not sim.terrain.traversable(pos,"land",3.5):return false
	for u in sim.units:
		if not sim.alive(u) or sim.definitions[u.kind].domain!="land":continue
		if u.pos.distance_to(pos)<3.8+float(sim.definitions[u.kind].radius):return false
		for member in u.members:
			if member.hp>0 and member.pos.distance_to(pos)<3.8+float(member.get("body_radius",0.8)):return false
	return true

static func build(sim,kind:String,team:int,pos:Vector2) -> bool:
	if sim.result!="" or not can_build(sim,kind,team,pos):return false
	var u=sim.spawn(kind,team,pos)
	if u.is_empty():return false
	spend(sim,team,sim.definitions[kind].cost)
	u["build_left"]=float(sim.definitions[kind].build_seconds)
	u["queue"]=[];u["rally"]=pos+Vector2(0,-7 if team==0 else 7)
	u.hp=u.max_hp*0.2
	u.state="BUILDING"
	sync_obstacles(sim)
	return true

static func producer(sim,kind:String,team:int) -> Dictionary:
	if not PRODUCER.has(kind):return {}
	var best:Dictionary={}
	for u in structures(sim,team,PRODUCER[kind]):
		if best.is_empty() or u.get("queue",[]).size()<best.get("queue",[]).size():best=u
	return best

static func production_reason(sim,kind:String,team:int=0)->String:
	if sim.result!="":return "Match ended"
	if not PRODUCER.has(kind):return "Air/naval production unavailable"
	var facility:=producer(sim,kind,team)
	if facility.is_empty():return "Requires "+str(PRODUCER[kind])
	if facility.get("queue",[]).size()>=5:return "All "+str(PRODUCER[kind])+" queues full (5/5)"
	if wallet(sim,team)<sim.definitions[kind].cost:return "Insufficient supply"
	return ""

static func committed_count(sim,kind:String,team:int) -> int:
	var count:int=sim.living(team).filter(func(u):return u.kind==kind).size()
	for facility in structures(sim,team):
		for item in facility.get("queue",[]):
			if item.kind==kind:count+=1
	return count

static func enqueue(sim,kind:String,team:int=0) -> bool:
	if sim.result!="" or not PRODUCER.has(kind) or wallet(sim,team)<sim.definitions[kind].cost:return false
	var facility:=producer(sim,kind,team)
	if facility.is_empty() or facility.get("queue",[]).size()>=5:return false
	if not facility.has("queue"):facility.queue=[]
	var duration:=8.0 if kind in ["rifle","drone","harvester"] else 14.0
	facility.queue.append({"kind":kind,"left":duration,"duration":duration,"cost":sim.definitions[kind].cost})
	spend(sim,team,sim.definitions[kind].cost)
	return true

static func cancel(sim,facility:Dictionary) -> bool:
	if facility.get("queue",[]).is_empty():return false
	var item:Dictionary=facility.queue.pop_back()
	spend(sim,facility.team,-float(item.cost))
	return true

# Refinery dock. A refinery unloads one harvester at a time (UNLOAD_TIME for a
# full load, credited when done) and is free again the moment it is empty.
# Returning harvesters each head for their own dock spot round it, never one
# another harvester stands on or is headed for (re-planning should one stop
# there), unload on reaching DOCK_REACH and wait there for their turn; with
# every dock spot taken they queue at a staging spot on STAGE_RINGS, and idle
# harvesters park off the dock the same way.
const DOCK_REACH:=8.0
# Any unloading time delays the economy: 0.5 s per load halved scripted
# classic wins over 28 seeds (credits for the opening Javelin teams came late).
const UNLOAD_TIME:=0.0
const STAGE_RINGS:=[12.5,15.5] # clear of a hull stopped at the edge of reach
const STAGE_ROUTES:=2 # path queries per body set when planning a staging spot
const HAUL_HULLS:=3.8 # from a stopped harvester: two hulls
const HAUL_GAP:=4.3 # from where one is headed: two hulls and some slack (it may stop short)

static func harvest(sim,u:Dictionary,dt:float) -> void:
	if not u.has("cargo"):u["cargo"]=0.0;u["haul"]="COLLECT"
	# Its own trip (a player's order stands), even once a friend making way has rerouted it.
	var own:bool=not u.orders.is_empty() and u.command_group==int(u.get("haul_command",-1))
	# A harvester stopped on its destination since it set off: pick another.
	var taken:bool=own and not u.get("dock_wait",false) and spot_taken(sim,u,u.haul_destination)
	var refineries:=structures(sim,u.team,"refinery")
	if refineries.is_empty():
		u.reason="Waiting for refinery"
		if own and u.blocked_time>4.0:sim.stop([u.id])
		return
	var refinery:Dictionary=refineries[0]
	for r in refineries:
		if r.id==u.get("dock_refinery",-1):refinery=r;break
		if u.pos.distance_to(r.pos)<u.pos.distance_to(refinery.pos):refinery=r
	# Hit on the way or at work: the side marks the spot and the harvester
	# gives up a trip or deposit it no longer judges safe (loaded, it heads home).
	if float(u.last_hit)>float(u.get("hit_logged",-100.0)):
		u["hit_logged"]=u.last_hit
		if not defended(sim,u.team,u.pos):mark_danger(sim,u.team,u.pos,HIT_RADIUS,HIT_MEMORY)
		if u.haul=="COLLECT" and (own or u.orders.is_empty()) and not defended(sim,u.team,u.pos):
			sim.stop([u.id])
			if u.cargo>0:u.haul="RETURN"
			else:u["retreat_until"]=sim.time+HIT_MEMORY
			u["haul_retry_at"]=sim.time
	if u.haul=="COLLECT" and sim.time<float(u.get("retreat_until",-1.0)):
		# Hit with nothing aboard: back to a safe spot by the refinery for now.
		u.reason="Under fire · pulling back"
		if u.orders.is_empty() and sim.time>=float(u.get("haul_retry_at",0.0)):
			u["haul_retry_at"]=sim.time+1.0
			if not safe(sim,u.team,u.pos,true) or not defended(sim,u.team,u.pos) or u.pos.distance_to(refinery.pos)>STAGE_RINGS[-1]+4.0 or u.pos.distance_to(refinery.pos)<DOCK_REACH+float(sim.definitions[u.kind].radius):stage(sim,u,refinery)
		return
	if u.haul=="COLLECT" and sim.time>=float(u.get("safety_at",0.0)):
		u["safety_at"]=sim.time+1.0
		var working:bool=u.orders.is_empty() and u.reason.begins_with("Harvesting")
		if (own and not u.get("dock_wait",false) and not safe(sim,u.team,u.haul_destination)) or (working and not safe(sim,u.team,u.pos)):
			sim.stop([u.id])
			if u.cargo>0:u.haul="RETURN"
			u["haul_retry_at"]=sim.time
			u.reason="Deposit under threat · pulling back"
			return
	if u.haul=="RETURN":
		if u.pos.distance_to(refinery.pos)<DOCK_REACH:
			var holder:=dock_holder(sim,refinery)
			if holder.is_empty():
				sim.stop([u.id])
				refinery["dock_id"]=u.id;u["dock_refinery"]=refinery.id;u["dock_unload"]=true;u["unload_left"]=UNLOAD_TIME*float(u.cargo)/120.0;holder=u
			elif holder.id!=u.id:
				if not u.orders.is_empty():sim.stop([u.id])
				u.reason="Queued to unload: %d" % u.cargo
				return
			u.unload_left-=dt
			u.reason="Unloading: %d" % u.cargo
			if u.unload_left<=0.0:
				spend(sim,u.team,-float(u.cargo));u.cargo=0.0;u.haul="COLLECT";u.dock_unload=false
				refinery.dock_id=-1;u.erase("dock_refinery")
			return
		var staged:bool=u.get("dock_wait",false)
		if taken or (u.orders.is_empty() and sim.time>=float(u.get("haul_retry_at",0.0))) or (u.blocked_time>4.0 and sim.time>=float(u.get("haul_repath_at",0.0)) and own):
			var excluded:Vector2=u.get("haul_destination",Vector2.INF) if own and not staged else Vector2.INF
			var dock:=delivery_route(sim,u,refinery,excluded)
			if dock.is_empty():dock=delivery_route(sim,u,refinery,excluded,7.0,true)
			u["haul_repath_at"]=sim.time+5.0
			if not dock.is_empty() and sim.issue([u.id],dock.pos)>0:
				u.path=dock.path;u["haul_destination"]=dock.pos;u["haul_command"]=u.command_group;u["dock_wait"]=false;staged=false
			else:
				u["haul_retry_at"]=sim.time+1.0
				# Every dock spot taken: queue off the dock (where it waits already, or a staging spot).
				if not (staged and u.orders.is_empty()):staged=stage(sim,u,refinery,u.haul_destination if own and staged else Vector2.INF)
		u.reason=("Queued to unload: %d" if staged else "Returning cargo: %d") % u.cargo
		return
	var field:=ore_field(sim,u)
	if field.is_empty():
		if u.cargo>0:u.haul="RETURN"
		else:
			var threatened:bool=deposits_threatened(sim,u)
			u.reason="Deposits under threat · waiting" if threatened else "Resource deposits exhausted" if sim.classic.fields.all(func(f):return f.remaining<=0) else "No reachable deposit"
			# Idle: off the dock, clear of other harvesters and, while it
			# waits out a threat, somewhere safe near its refinery.
			if own and u.blocked_time>4.0:sim.stop([u.id])
			if u.orders.is_empty() and sim.time>=float(u.get("haul_retry_at",0.0)):
				u["haul_retry_at"]=sim.time+1.0
				var exposed:bool=threatened and (not safe(sim,u.team,u.pos,true) or u.pos.distance_to(refinery.pos)>STAGE_RINGS[-1]+4.0)
				if exposed or u.pos.distance_to(refinery.pos)<DOCK_REACH+float(sim.definitions[u.kind].radius) or claimed(u.pos,haul_claims(sim,u)):stage(sim,u,refinery)
		return
	# Passing over the centre it collects there, unless another harvester stands
	# or is headed within a hull of it.
	if (u.pos.distance_to(field.pos)<4 and (u.orders.is_empty() or not claimed(u.pos,haul_claims(sim,u)))) or (u.pos.distance_to(u.get("ore_cell",Vector2.INF))<ORE_SCOOP and field.pos.distance_to(u.ore_cell)<ORE_RINGS[-1][0]+0.5):
		sim.stop([u.id])
		var amount:float=minf(18*dt,minf(120-u.cargo,field.remaining))
		u.cargo+=amount;field.remaining-=amount
		u.reason="Harvesting: %d / 120" % u.cargo
		if u.cargo>=119.9 or field.remaining<=0:u.haul="RETURN"
	elif taken or (u.orders.is_empty() and sim.time>=float(u.get("haul_retry_at",0.0))) or (u.blocked_time>4.0 and sim.time>=float(u.get("haul_repath_at",0.0)) and own):
		var excluded:Vector2=u.get("haul_destination",Vector2.INF) if own else Vector2.INF
		u["haul_repath_at"]=sim.time+5.0
		clear_deposit(sim,u,field)
		u["ore_busy"]=false;u["ore_unsafe"]=false
		var approach:=ore_route(sim,u,field,excluded)
		# Units that can move (idle crowds, the blockers just asked to make
		# way) are not walls: plan round fixed obstacles only and let local
		# movement and the blocked re-plan handle them.
		if approach.is_empty():approach=ore_route(sim,u,field,excluded,true)
		if not approach.is_empty() and sim.issue([u.id],approach.pos)>0:
			u.path=approach.path;u["haul_destination"]=approach.pos;u["haul_command"]=u.command_group;u["ore_cell"]=approach.pos
		else:
			# Walled off by wrecks or immobilised hulls: try another deposit
			# (soon again where friends merely hold the open stand points).
			if not u.has("ore_skip"):u["ore_skip"]={}
			var busy:bool=u.ore_busy and not u.ore_unsafe
			u.ore_skip[sim.classic.fields.find(field)]=sim.time+(ORE_BUSY if busy else ORE_SKIP)
			u["haul_retry_at"]=sim.time+1.0;u.reason="Deposit busy · waiting" if busy else "Deposit under threat · rerouting" if u.ore_unsafe else "Deposit blocked · rerouting"

# The harvester unloading at the refinery, or {} when its dock is free.
static func dock_holder(sim,refinery:Dictionary)->Dictionary:
	var holder:Dictionary=sim.get_unit(int(refinery.get("dock_id",-1)))
	if not sim.alive(holder) or holder.get("haul","")!="RETURN" or not holder.get("dock_unload",false) or int(holder.get("dock_refinery",-1))!=refinery.id:return {}
	return holder

# Sends the harvester to a staging spot off the dock; false when none is free.
static func stage(sim,u:Dictionary,refinery:Dictionary,excluded:Vector2=Vector2.INF)->bool:
	u["haul_repath_at"]=sim.time+5.0
	var spot:=stage_route(sim,u,refinery,excluded)
	if spot.is_empty() or sim.issue([u.id],spot.pos)==0:
		u["haul_retry_at"]=sim.time+1.0
		return false
	u.path=spot.path;u["haul_destination"]=spot.pos;u["haul_command"]=u.command_group;u["dock_wait"]=true
	return true

# Where other friendly harvesters are stopped or headed, as (x, y, keep-off
# radius); a moving hull is planned round as a body, not claimed where it passes.
static func haul_claims(sim,u:Dictionary)->Array:
	var claims:Array=[]
	for other in sim.units:
		if other.id==u.id or other.kind!="harvester" or other.team!=u.team or not sim.alive(other):continue
		if other.orders.is_empty():claims.append(Vector3(other.pos.x,other.pos.y,HAUL_HULLS))
		else:
			var to:Vector2=other.orders.back().pos
			claims.append(Vector3(to.x,to.y,HAUL_GAP))
	return claims

# Another friendly harvester is stopped within a hull's reach of `point`.
static func spot_taken(sim,u:Dictionary,point:Vector2)->bool:
	for other in sim.units:
		if other.kind=="harvester" and other.id!=u.id and other.team==u.team and other.orders.is_empty() and sim.alive(other) and point.distance_squared_to(other.pos)<HAUL_HULLS*HAUL_HULLS:return true
	return false

static func claimed(point:Vector2,claims:Array)->bool:
	for claim in claims:
		if point.distance_squared_to(Vector2(claim.x,claim.y))<claim.z*claim.z:return true
	return false

# Nearest reachable staging spot round the refinery: off every dock, off the
# ore, clear of bodies and of other harvesters' stops and destinations.
static func stage_route(sim,u:Dictionary,refinery:Dictionary,excluded:Vector2=Vector2.INF)->Dictionary:
	var radius:float=sim.definitions[u.kind].radius
	var avoid:=haul_bodies(sim,u)
	var claims:=haul_claims(sim,u)
	var docks:Array=structures(sim,u.team,"refinery")
	var cells:Array=[]
	for ring in STAGE_RINGS:
		for i in 16:
			var point:Vector2=refinery.pos+Vector2.from_angle(i*TAU/16)*ring
			if excluded.is_finite() and point.distance_to(excluded)<1.0:continue
			if claimed(point,claims) or not sim.terrain.traversable(point,"land",radius):continue
			if docks.any(func(r):return point.distance_to(r.pos)<DOCK_REACH+radius):continue
			if sim.classic.fields.any(func(f):return f.remaining>0 and point.distance_to(f.pos)<ORE_RINGS[-1][0]+radius):continue
			if not safe(sim,u.team,point,true):continue
			var clear:=true
			for body in avoid:
				if point.distance_squared_to(body.pos)<(body.radius+0.5)*(body.radius+0.5):clear=false;break
			if clear:cells.append(point)
	cells.sort_custom(func(a,b):return a.distance_squared_to(u.pos)<b.distance_squared_to(u.pos))
	for bodies in [avoid,haul_bodies(sim,u,true)]:
		for point in cells.slice(0,STAGE_ROUTES):
			var route:Array=sim.terrain.path(u.pos,point,"land",radius,bodies,"wheeled")
			if not route.is_empty() and route.back().distance_to(point)<=1.0:return {"pos":point,"path":route}
	return {}

# Threat-aware harvesting. Each side keeps what it actually knows (no
# omniscience): enemy combat units it has seen, at their last seen spot until
# one of its units looks there again and finds it empty (or THREAT_MEMORY s
# pass, or the unit is destroyed); the enemy structures it has seen (starting
# HQs are disclosed); and where its own harvesters were hit or lost. A spot is
# unsafe within a known threat's weapon range plus THREAT_MARGIN, near a recent
# hit or loss, or in enemy territory: within TERRITORY of a known enemy
# structure, REFINERY_ZONE of a refinery (the deposit it serves). Harvesters
# never pick or keep an unsafe deposit, ore spot or route; one hit beyond its
# defended ground aborts the trip and returns; with no safe deposit they wait
# off the dock near their refinery. On defended ground (DEFENDED of their own
# structures) they work on as before: closing the home deposit to every raid
# starved the economy (29 seeds: 2 wins). A permanent map-half rule did too
# once the home deposit ran out (8 games stalled unresolved, both sides broke).
const INTEL_PERIOD:=1.0
const THREAT_MEMORY:=90.0
const THREAT_MARGIN:=3.0
const HIT_RADIUS:=12.0
const HIT_MEMORY:=20.0
const LOSS_RADIUS:=15.0
const LOSS_MEMORY:=60.0
const TERRITORY:=14.0
const REFINERY_ZONE:=20.0
const DEFENDED:=18.0

static func intel(sim,team:int)->Dictionary:
	if not sim.classic.has("intel"):
		sim.classic["intel"]=[]
		for t in 2:sim.classic.intel.append({"threats":{},"structures":{},"marks":[],"open_fields":[],"lost":{},"own":[]})
	return sim.classic.intel[team]

static func mark_danger(sim,team:int,pos:Vector2,radius:float,memory:float)->void:
	intel(sim,team).marks.append({"pos":pos,"radius":radius,"until":sim.time+memory})

# Once per INTEL_PERIOD: what `team` sees now, its harvester losses, expiries,
# and which deposits still have a safe stand point.
static func update_intel(sim,team:int)->void:
	var known:=intel(sim,team)
	known.own=[]
	var eyes:Array=[] # (x, y, sight squared) of the side's units
	for other in sim.units:
		if other.team==team and sim.alive(other):
			var sight:float=float(sim.definitions[other.kind].get("sight",0))
			if sight>0:eyes.append(Vector3(other.pos.x,other.pos.y,sight*sight))
			if sim.definitions[other.kind].get("structure",false):known.own.append(other.pos)
	for other in sim.units:
		if other.kind=="harvester" and other.team==team and not sim.alive(other) and not known.lost.has(other.id):
			known.lost[other.id]=true
			if not defended(sim,team,other.pos):mark_danger(sim,team,other.pos,LOSS_RADIUS,LOSS_MEMORY)
		if other.team==team or not sim.alive(other):continue
		var d:Dictionary=sim.definitions[other.kind]
		if d.get("structure",false):
			if other.seen_by[team] or other.kind=="hq":known.structures[other.id]=Vector3(other.pos.x,other.pos.y,REFINERY_ZONE if other.kind=="refinery" else TERRITORY)
		elif other.seen_by[team] and float(d.get("damage",0))>0 and float(d.get("range",0))>0 and sim.effective_unit(other,"harvester"):
			known.threats[other.id]={"pos":other.pos,"time":sim.time,"range":float(d.range)}
	for id in known.threats.keys():
		var threat:Dictionary=known.threats[id]
		if sim.time-float(threat.time)>THREAT_MEMORY or not sim.alive(sim.get_unit(id)):known.threats.erase(id)
		elif threat.time<sim.time and eyes.any(func(e):return Vector2(e.x,e.y).distance_squared_to(threat.pos)<e.z):known.threats.erase(id)
	for id in known.structures.keys():
		if not sim.alive(sim.get_unit(id)):known.structures.erase(id)
	known.marks=known.marks.filter(func(m):return sim.time<float(m.until))
	known.open_fields=[]
	for f in sim.classic.fields:
		var open:=false
		if f.remaining>0:
			for ring in [ORE_RINGS[0],ORE_RINGS[-1]]:
				for i in ring[1]:
					if safe(sim,team,f.pos+Vector2.from_angle(i*TAU/ring[1])*ring[0]):open=true;break
				if open:break
		known.open_fields.append(open)

# Within DEFENDED of its own structures a side holds the ground: harvesters
# work on through sightings, hits and losses there (its forces answer them);
# the caution above applies beyond it.
static func defended(sim,team:int,point:Vector2)->bool:
	for at in intel(sim,team).own:
		if point.distance_squared_to(at)<DEFENDED*DEFENDED:return true
	return false

# `strict` (where to wait) counts known threats on defended ground too.
static func safe(sim,team:int,point:Vector2,strict:bool=false)->bool:
	if not point.is_finite():return true
	var known:=intel(sim,team)
	for at in known.structures.values():
		if point.distance_squared_to(Vector2(at.x,at.y))<at.z*at.z:return false
	if (known.threats.is_empty() and known.marks.is_empty()) or (not strict and defended(sim,team,point)):return true
	for threat in known.threats.values():
		var reach:float=float(threat.range)+THREAT_MARGIN
		if point.distance_squared_to(threat.pos)<reach*reach:return false
	for m in known.marks:
		if point.distance_squared_to(m.pos)<float(m.radius)*float(m.radius):return false
	return true

# A route keeps out of every known threat's weapon range, enemy territory and
# other hit or loss spots (the one it is leaving does not hold it in).
static func route_safe(sim,team:int,from:Vector2,route:Array)->bool:
	var known:=intel(sim,team)
	var a:=from
	for b in route:
		if defended(sim,team,b):
			a=b
			continue
		for m in known.marks:
			if from.distance_to(m.pos)>=float(m.radius) and Geometry2D.get_closest_point_to_segment(m.pos,a,b).distance_to(m.pos)<float(m.radius):return false
		for threat in known.threats.values():
			if Geometry2D.get_closest_point_to_segment(threat.pos,a,b).distance_to(threat.pos)<float(threat.range):return false
		for at in known.structures.values():
			var centre:=Vector2(at.x,at.y)
			if Geometry2D.get_closest_point_to_segment(centre,a,b).distance_to(centre)<at.z:return false
		a=b
	return true

# Ore left only where its side judges it unsafe.
static func deposits_threatened(sim,u:Dictionary)->bool:
	var open:Array=intel(sim,u.team).open_fields
	for i in sim.classic.fields.size():
		if sim.classic.fields[i].remaining>0 and i<open.size() and not open[i]:return true
	return false

# Ore deposits. The marker ring is 3.3 m across the ore; a harvester collects
# from stand points on and round it (its scoop reaches the edge from 5.5 m),
# so a hull or wreck on the centre does not close the whole deposit.
const ORE_RINGS:=[[0.0,1],[2.0,6],[3.8,12],[5.5,16]]
const ORE_FOOTPRINT:=3.3
const ORE_SCOOP:=1.5 # collects within this of its chosen stand point
const ORE_ROUTES:=2 # path queries per stand-point ring when planning a trip
const ORE_SKIP:=30.0 # seconds before an unreachable deposit is retried
const ORE_BUSY:=5.0 # ... and one with every open stand point taken by friends

# Nearest deposit with ore that has not recently proved unreachable and that
# its side judges safe (some stand point clear of known threats).
static func ore_field(sim,u:Dictionary)->Dictionary:
	var skip:Dictionary=u.get("ore_skip",{})
	var field:Dictionary={}
	var open:Array=intel(sim,u.team).open_fields
	for i in sim.classic.fields.size():
		var f:Dictionary=sim.classic.fields[i]
		if f.remaining<=0 or sim.time<float(skip.get(i,-1.0)) or (i<open.size() and not open[i]):continue
		if field.is_empty() or u.pos.distance_to(f.pos)<u.pos.distance_to(field.pos):field=f
	return field

# Bodies a harvester plans round: known land units (immobilised hulls among
# them) and vehicle wrecks; `fixed` keeps only what cannot move off.
static func haul_bodies(sim,u:Dictionary,fixed:bool=false)->Array:
	var radius:float=sim.definitions[u.kind].radius
	var avoid:Array=[]
	for other in sim.units:
		if other.id==u.id or not sim.alive(other) or sim.definitions[other.kind].domain!="land":continue
		if other.team!=u.team and not sim.contact_known(u,other):continue
		if fixed and float(sim.definitions[other.kind].speed)>0 and not other.get("mobility_kill",false) and not other.get("abandoned",false):continue
		avoid.append({"pos":other.pos,"radius":radius+float(sim.definitions[other.kind].radius)+0.08})
		for member in other.members:
			if member.hp>0:avoid.append({"pos":member.pos,"radius":radius+float(member.get("body_radius",0.8))+0.02})
	for wreck in VehicleDamage.wrecks(sim):
		avoid.append({"pos":wreck.pos,"radius":radius+float(wreck.radius)+0.1})
	# A body already touching the harvester shrinks to its gap, so a route
	# can still lead away from it.
	for body in avoid:body.radius=minf(body.radius,u.pos.distance_to(body.pos)-0.05)
	return avoid

# Route to the innermost clear, reachable stand point of the deposit (outer
# rings only when the ore nearer the centre is blocked). Per ring only the
# ORE_ROUTES clear points nearest the harvester are path-checked, so an open
# deposit costs one query and a closed one at most seven (per body set).
static func ore_route(sim,u:Dictionary,field:Dictionary,excluded:Vector2=Vector2.INF,fixed:bool=false)->Dictionary:
	var radius:float=sim.definitions[u.kind].radius
	var avoid:=haul_bodies(sim,u,fixed)
	var claims:=haul_claims(sim,u)
	for ring in ORE_RINGS:
		var cells:Array=[]
		for i in ring[1]:
			var point:Vector2=field.pos+Vector2.from_angle(i*TAU/ring[1])*ring[0]
			if excluded.is_finite() and point.distance_to(excluded)<1.0:continue
			if not sim.terrain.traversable(point,"land",radius) or not safe(sim,u.team,point):continue
			if claimed(point,claims):u["ore_busy"]=true;continue
			# Half a nav cell of slack: a point grazing a body has no grid route.
			var clear:=true
			for body in avoid:
				if point.distance_squared_to(body.pos)<(body.radius+0.5)*(body.radius+0.5):clear=false;break
			if clear:cells.append(point)
		cells.sort_custom(func(a,b):return a.distance_squared_to(u.pos)<b.distance_squared_to(u.pos))
		var best:Dictionary={}
		var best_length:=INF
		for point in cells.slice(0,ORE_ROUTES):
			var route:Array=sim.terrain.path(u.pos,point,"land",radius,avoid,"wheeled")
			if route.is_empty() or route.back().distance_to(point)>1.0:continue
			if not route_safe(sim,u.team,u.pos,route):u["ore_unsafe"]=true;continue
			var length:=0.0
			var previous:Vector2=u.pos
			for waypoint in route:length+=previous.distance_to(waypoint);previous=waypoint
			if length<best_length:best_length=length;best={"pos":point,"path":route}
		if not best.is_empty():return best
	return {}

# Idle friendly units parked on the deposit pull off it (immobilised, held and
# garrisoned ones cannot). Returns how many were asked.
static func clear_deposit(sim,u:Dictionary,field:Dictionary)->int:
	var asked:=0
	for other in sim.living(u.team):
		var d:Dictionary=sim.definitions[other.kind]
		if other.id==u.id or other.kind=="harvester" or d.domain!="land" or d.get("structure",false) or float(d.speed)<=0:continue
		if not other.orders.is_empty() or not other.maneuver.is_empty() or other.hold_command or other.has("building_id") or other.get("mobility_kill",false):continue
		if sim.time<float(other.get("ore_yield_until",-1.0)):continue
		var on_ore:bool=other.pos.distance_to(field.pos)<ORE_FOOTPRINT+float(d.radius)
		if not other.members.is_empty():
			on_ore=false
			for member in other.members:
				if member.hp>0 and member.pos.distance_to(field.pos)<ORE_FOOTPRINT+float(member.get("body_radius",0.8)):on_ore=true
		if not on_ore:continue
		var away:Vector2=other.pos-field.pos
		if away.length()<0.5:away=field.pos-u.pos
		var reach:float=ORE_RINGS[-1][0]+float(sim.definitions[u.kind].radius)+float(d.radius)+0.5
		for k in 8:
			var spot:Vector2=field.pos+away.normalized().rotated(((k+1)>>1)*(1 if k%2==0 else -1)*TAU/8)*reach
			if not sim.location_clear(spot,other.kind,other.id) or sim.issue([other.id],spot)==0:continue
			other["ore_yield_until"]=sim.time+20.0
			other.reason="Making way for harvester"
			asked+=1
			break
	return asked

# Choose a reachable unloading side rather than the first terrain-legal side.
# This runs only when the economy needs a new trip; existing orders stay intact.
static func delivery_route(sim,u:Dictionary,refinery:Dictionary,excluded:Vector2=Vector2.INF,approach_radius:float=7.0,fixed:bool=false) -> Dictionary:
	var radius:float=sim.definitions[u.kind].radius
	var avoid:=haul_bodies(sim,u,fixed)
	var claims:=haul_claims(sim,u)
	var best:Dictionary={}
	var best_length:=INF
	for i in 8:
		var point:Vector2=refinery.pos+Vector2.from_angle(i*TAU/8)*approach_radius
		if excluded.is_finite() and point.distance_to(excluded)<1.0:continue
		# Never onto a harvester or where one is headed, even planning round fixed bodies only.
		if claimed(point,claims):continue
		if not sim.terrain.traversable(point,"land",radius) or not sim.terrain.avoids_bodies(point,point,avoid):continue
		var route:Array=sim.terrain.path(u.pos,point,"land",radius,avoid,"wheeled")
		if route.is_empty():continue
		var length:=0.0
		var previous:Vector2=u.pos
		for waypoint in route:length+=previous.distance_to(waypoint);previous=waypoint
		if length<best_length:best_length=length;best={"pos":point,"path":route}
	return best

static func production_exit(sim,facility:Dictionary,kind:String) -> Vector2:
	for i in 24:
		var point:Vector2=facility.pos+Vector2.from_angle((-PI/2 if facility.team==0 else PI/2)+i*TAU/24)*7.0
		if not sim.location_clear(point,kind):continue
		var free:=true
		if sim.definitions[kind].domain=="land":
			for other in sim.units:
				if not sim.alive(other):continue
				for member in other.members:
					if member.hp>0 and point.distance_to(member.pos)<float(sim.definitions[kind].radius)+float(member.get("body_radius",0.8))+0.12:free=false
		if free:return point
	return Vector2(-1,-1)

static func tick(sim,dt:float) -> void:
	sync_obstacles(sim)
	sim.classic["intel_clock"]=float(sim.classic.get("intel_clock",0.0))-dt
	if sim.classic.intel_clock<=0:
		sim.classic.intel_clock=INTEL_PERIOD
		for team in 2:update_intel(sim,team)
	for team in 2:
		var electricity:=power(sim,team)
		for u in structures(sim,team,"",false):
			if u.get("build_left",0.0)>0:
				u.build_left=maxf(0,u.build_left-dt)
				u.hp=minf(u.max_hp,u.hp+u.max_hp*0.8*dt/float(sim.definitions[u.kind].build_seconds))
				u.reason="Construction %.0fs" % u.build_left
				continue
			u.reason="Operational" if electricity.x>=electricity.y else "Low power: production slowed"
			if u.get("queue",[]).is_empty():continue
			var item:Dictionary=u.queue[0]
			item.left=maxf(0,item.left-dt*(1.0 if electricity.x>=electricity.y else 0.35))
			if item.left<=0:
				var exit_point:=production_exit(sim,u,item.kind)
				if exit_point.x<0:
					u.reason="Production ready · exit blocked"
					continue
				var unit=sim.spawn(item.kind,team,exit_point)
				if not unit.is_empty():
					u.queue.pop_front()
					if item.kind!="harvester":sim.issue([unit.id],u.rally,"attack_move")
		for u in sim.living(team):
			if u.kind=="harvester":harvest(sim,u,dt)
	if sim.classic.started:
		if structures(sim,0,"",false).is_empty():sim.result="DEFEAT"
		elif structures(sim,1,"",false).is_empty():sim.result="VICTORY"
	sim.classic.ai_clock-=dt
	if sim.classic.ai_clock<=0:
		sim.classic.ai_clock=4.0
		for kind in ["refinery","power","barracks","factory"]:
			if structures(sim,1,kind,false).is_empty():
				var site:=find_site(sim,kind,1)
				if site.x>=0:build(sim,kind,1,site)
				break
		if committed_count(sim,"harvester",1)==0:enqueue(sim,"harvester",1)
		if not structures(sim,1,"factory").is_empty():enqueue(sim,"tank" if int(sim.time/4)%3==0 else "atgm",1)
	sim.classic.attack_clock-=dt
	if sim.classic.attack_clock<=0:
		sim.classic.attack_clock=40.0
		var force:Array=sim.living(1).filter(func(u):return not sim.definitions[u.kind].get("structure",false) and u.kind!="harvester").map(func(u):return u.id)
		# Starting base locations are disclosed in this skirmish; live enemy positions are not.
		for id in force:
			var unit:Dictionary=sim.get_unit(id)
			var targets:Array=structures(sim,0,"",false).filter(func(target):return sim.contact_known(unit,target) and sim.effective_unit(unit,target.kind))
			if not targets.is_empty():sim.issue([id],targets[0].pos,"attack",false,targets[0].id)
			else:
				var approach:=known_base_approach(sim,unit,0)
				if approach.x>=0:sim.issue([id],approach,"attack_move")

# Starting HQ locations are disclosed map setup, not live hidden contacts.
# Reach a clear observation approach rather than stopping outside rifle sight.
static func known_base_approach(sim,u:Dictionary,target_team:int) -> Vector2:
	var home:=Vector2(10,sim.terrain.world_size.y-11) if target_team==0 else Vector2(sim.terrain.shore_x-14,9)
	var d:Dictionary=sim.definitions[u.kind]
	var radius:float=d.radius
	var distance:float=minf(10.0,float(d.sight)*0.65)
	var best:=Vector2(-1,-1)
	var best_length:=INF
	for i in 16:
		var point:Vector2=home+Vector2.from_angle(i*TAU/16)*distance
		if not sim.terrain.traversable(point,d.domain,radius) or not sim.terrain.line_clear(point,home):continue
		var route:Array=sim.terrain.path(u.pos,point,d.domain,radius,[],sim.terrain.mobility_profile(u.kind))
		if route.is_empty():continue
		var length:=0.0
		var previous:Vector2=u.pos
		for waypoint in route:length+=previous.distance_to(waypoint);previous=waypoint
		if length<best_length:best_length=length;best=point
	return best

static func sync_obstacles(sim) -> void:
	var all:Array=structures(sim,0,"",false)+structures(sim,1,"",false)
	var key:String=str(all.map(func(u):return u.id))
	if key==sim.classic.get("obstacle_key",""):return
	sim.classic.obstacle_key=key
	sim.terrain.dynamic_blocks.clear()
	for u in all:sim.terrain.dynamic_blocks.append(Rect2(u.pos-Vector2(2.4,2.25),Vector2(4.8,4.5)))
	sim.terrain.navigation.clear()
	sim.visibility_cache.clear()

static func find_site(sim,kind:String,team:int) -> Vector2:
	var home:=Vector2(10,sim.terrain.world_size.y-11) if team==0 else Vector2(sim.terrain.shore_x-14,9)
	var best:=Vector2(-1,-1)
	var distance:=INF
	for x in range(6,mini(ceili(sim.terrain.shore_x)-5,ceili(sim.terrain.world_size.x)-5),10):
		for y in range(6,ceili(sim.terrain.world_size.y)-5,10):
			var point:=Vector2(x,y)
			var score:float=point.distance_squared_to(home)
			if kind=="refinery":
				var field_distance:=INF
				for field in sim.classic.fields:
					if field.remaining>0:field_distance=minf(field_distance,point.distance_squared_to(field.pos))
				score=field_distance+score*0.2
			if score<distance and can_build(sim,kind,team,point):
				best=point;distance=score
	return best
