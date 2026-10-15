extends RefCounted

const PRODUCER={"rifle":"barracks","atgm":"barracks","tank":"factory","aa":"factory","drone":"factory","harvester":"hq"}
const BUILDINGS=["power","refinery","barracks","factory"]

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

static func harvest(sim,u:Dictionary,dt:float) -> void:
	if not u.has("cargo"):u["cargo"]=0.0;u["haul"]="COLLECT"
	var refineries:=structures(sim,u.team,"refinery")
	if refineries.is_empty():u.reason="Waiting for refinery";return
	var refinery:Dictionary=refineries[0]
	for r in refineries:
		if u.pos.distance_to(r.pos)<u.pos.distance_to(refinery.pos):refinery=r
	if u.haul=="RETURN":
		if u.pos.distance_to(refinery.pos)<8:
			spend(sim,u.team,-float(u.cargo));u.cargo=0.0;u.haul="COLLECT";sim.stop([u.id])
		elif u.orders.is_empty() or (u.blocked_time>4.0 and sim.time>=float(u.get("haul_repath_at",0.0)) and u.orders[0].pos==u.get("haul_destination",Vector2.INF)):
			var excluded:Vector2=u.get("haul_destination",Vector2.INF) if not u.orders.is_empty() else Vector2.INF
			var dock:=delivery_route(sim,u,refinery,excluded)
			u["haul_repath_at"]=sim.time+5.0
			if not dock.is_empty() and sim.issue([u.id],dock.pos)>0:
				u.path=dock.path;u["haul_destination"]=dock.pos
		u.reason="Returning cargo: %d" % u.cargo
		return
	var field:Dictionary={}
	for f in sim.classic.fields:
		if f.remaining>0 and (field.is_empty() or u.pos.distance_to(f.pos)<u.pos.distance_to(field.pos)):field=f
	if field.is_empty():
		if u.cargo>0:u.haul="RETURN"
		else:u.reason="Resource deposits exhausted"
		return
	if u.pos.distance_to(field.pos)<4:
		sim.stop([u.id])
		var amount:float=minf(18*dt,minf(120-u.cargo,field.remaining))
		u.cargo+=amount;field.remaining-=amount
		u.reason="Harvesting: %d / 120" % u.cargo
		if u.cargo>=119.9 or field.remaining<=0:u.haul="RETURN"
	elif u.orders.is_empty() or (u.blocked_time>4.0 and sim.time>=float(u.get("haul_repath_at",0.0)) and u.orders[0].pos==u.get("haul_destination",Vector2.INF)):
		var excluded:Vector2=u.get("haul_destination",Vector2.INF) if not u.orders.is_empty() else Vector2.INF
		var approach:=delivery_route(sim,u,field,excluded,3.0)
		u["haul_repath_at"]=sim.time+5.0
		if not approach.is_empty() and sim.issue([u.id],approach.pos)>0:
			u.path=approach.path;u["haul_destination"]=approach.pos

# Choose a reachable unloading side rather than the first terrain-legal side.
# This runs only when the economy needs a new trip; existing orders stay intact.
static func delivery_route(sim,u:Dictionary,refinery:Dictionary,excluded:Vector2=Vector2.INF,approach_radius:float=7.0) -> Dictionary:
	var radius:float=sim.definitions[u.kind].radius
	var avoid:Array=[]
	for other in sim.units:
		if other.id==u.id or not sim.alive(other) or sim.definitions[other.kind].domain!="land":continue
		if other.team!=u.team and not sim.contact_known(u,other):continue
		avoid.append({"pos":other.pos,"radius":radius+float(sim.definitions[other.kind].radius)+0.08})
		for member in other.members:
			if member.hp>0:avoid.append({"pos":member.pos,"radius":radius+float(member.get("body_radius",0.8))+0.02})
	var best:Dictionary={}
	var best_length:=INF
	for i in 8:
		var point:Vector2=refinery.pos+Vector2.from_angle(i*TAU/8)*approach_radius
		if excluded.is_finite() and point.distance_to(excluded)<1.0:continue
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
