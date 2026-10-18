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
# Returning harvesters each drive to their own dock spot round it, never one
# another harvester stands on or is headed for, and wait there for their turn;
# with every dock spot taken they queue at a staging spot on STAGE_RINGS, and
# idle harvesters park off the dock the same way.
const DOCK_REACH:=8.0
# Any unloading time delays the economy: 0.5 s per load halved scripted
# classic wins over 28 seeds (credits for the opening Javelin teams came late).
const UNLOAD_TIME:=0.0
const STAGE_RINGS:=[12.5,15.5] # clear of a hull stopped at the edge of reach
const STAGE_ROUTES:=2 # path queries per body set when planning a staging spot
const HAUL_GAP:=4.3 # between harvester stops and destinations: two hulls and a margin

static func harvest(sim,u:Dictionary,dt:float) -> void:
	if not u.has("cargo"):u["cargo"]=0.0;u["haul"]="COLLECT"
	# Its own trip (a player's order stands), even once a friend making way has rerouted it.
	var own:bool=not u.orders.is_empty() and u.command_group==int(u.get("haul_command",-1))
	var refineries:=structures(sim,u.team,"refinery")
	if refineries.is_empty():
		u.reason="Waiting for refinery"
		if own and u.blocked_time>4.0:sim.stop([u.id])
		return
	var refinery:Dictionary=refineries[0]
	for r in refineries:
		if r.id==u.get("dock_refinery",-1):refinery=r;break
		if u.pos.distance_to(r.pos)<u.pos.distance_to(refinery.pos):refinery=r
	if u.haul=="RETURN":
		# It unloads on its dock spot (or where it stopped, was held up or was
		# ordered to), not wherever it crosses into reach.
		var docked:bool=not own or u.get("dock_unload",false) or u.blocked_time>1.0 or u.pos.distance_to(u.haul_destination)<1.5
		if u.pos.distance_to(refinery.pos)<DOCK_REACH and docked:
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
		if (u.orders.is_empty() and sim.time>=float(u.get("haul_retry_at",0.0))) or (u.blocked_time>4.0 and sim.time>=float(u.get("haul_repath_at",0.0)) and own):
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
			u.reason="Resource deposits exhausted" if sim.classic.fields.all(func(f):return f.remaining<=0) else "No reachable deposit"
			# Idle: off the dock and clear of other harvesters.
			if own and u.blocked_time>4.0:sim.stop([u.id])
			if u.orders.is_empty() and sim.time>=float(u.get("haul_retry_at",0.0)):
				u["haul_retry_at"]=sim.time+1.0
				if u.pos.distance_to(refinery.pos)<DOCK_REACH+float(sim.definitions[u.kind].radius) or claimed(u.pos,haul_claims(sim,u)):stage(sim,u,refinery)
		return
	# Passing over the centre it collects there, unless another harvester stands
	# or is headed within a hull of it.
	if (u.pos.distance_to(field.pos)<4 and (u.orders.is_empty() or not claimed(u.pos,haul_claims(sim,u)))) or (u.pos.distance_to(u.get("ore_cell",Vector2.INF))<ORE_SCOOP and field.pos.distance_to(u.ore_cell)<ORE_RINGS[-1][0]+0.5):
		sim.stop([u.id])
		var amount:float=minf(18*dt,minf(120-u.cargo,field.remaining))
		u.cargo+=amount;field.remaining-=amount
		u.reason="Harvesting: %d / 120" % u.cargo
		if u.cargo>=119.9 or field.remaining<=0:u.haul="RETURN"
	elif (u.orders.is_empty() and sim.time>=float(u.get("haul_retry_at",0.0))) or (u.blocked_time>4.0 and sim.time>=float(u.get("haul_repath_at",0.0)) and own):
		var excluded:Vector2=u.get("haul_destination",Vector2.INF) if own else Vector2.INF
		u["haul_repath_at"]=sim.time+5.0
		clear_deposit(sim,u,field)
		var approach:=ore_route(sim,u,field,excluded)
		# Units that can move (idle crowds, the blockers just asked to make
		# way) are not walls: plan round fixed obstacles only and let local
		# movement and the blocked re-plan handle them.
		if approach.is_empty():approach=ore_route(sim,u,field,excluded,true)
		if not approach.is_empty() and sim.issue([u.id],approach.pos)>0:
			u.path=approach.path;u["haul_destination"]=approach.pos;u["haul_command"]=u.command_group;u["ore_cell"]=approach.pos
		else:
			# Walled off by wrecks or immobilised hulls: try another deposit.
			if not u.has("ore_skip"):u["ore_skip"]={}
			u.ore_skip[sim.classic.fields.find(field)]=sim.time+ORE_SKIP
			u["haul_retry_at"]=sim.time+1.0;u.reason="Deposit blocked · rerouting"

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

# Where other friendly harvesters are stopped or headed (a moving hull is
# planned round as a body, not claimed where it passes).
static func haul_claims(sim,u:Dictionary)->Array:
	var claims:Array=[]
	for other in sim.units:
		if other.id==u.id or other.kind!="harvester" or other.team!=u.team or not sim.alive(other):continue
		claims.append(other.pos if other.orders.is_empty() else Vector2(other.orders.back().pos))
	return claims

static func claimed(point:Vector2,claims:Array)->bool:
	for claim in claims:
		if point.distance_squared_to(claim)<HAUL_GAP*HAUL_GAP:return true
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

# Ore deposits. The marker ring is 3.3 m across the ore; a harvester collects
# from stand points on and round it (its scoop reaches the edge from 5.5 m),
# so a hull or wreck on the centre does not close the whole deposit.
const ORE_RINGS:=[[0.0,1],[2.0,6],[3.8,12],[5.5,16]]
const ORE_FOOTPRINT:=3.3
const ORE_SCOOP:=1.5 # collects within this of its chosen stand point
const ORE_ROUTES:=2 # path queries per stand-point ring when planning a trip
const ORE_SKIP:=30.0 # seconds before an unreachable deposit is retried

# Nearest deposit with ore that has not recently proved unreachable.
static func ore_field(sim,u:Dictionary)->Dictionary:
	var skip:Dictionary=u.get("ore_skip",{})
	var field:Dictionary={}
	for i in sim.classic.fields.size():
		var f:Dictionary=sim.classic.fields[i]
		if f.remaining<=0 or sim.time<float(skip.get(i,-1.0)):continue
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
			if claimed(point,claims) or not sim.terrain.traversable(point,"land",radius):continue
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
