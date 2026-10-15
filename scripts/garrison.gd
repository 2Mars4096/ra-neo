class_name Garrison
extends RefCounted

# Infantry garrisons of compiled city buildings (scenario.architecture with
# collision ranges). A section walks to the nearest doorway, enters and is
# seated at window positions just outside the walls on every face, so its own
# fire and the enemy's fire use ordinary line-of-fire checks. Inside, damage
# and suppression are reduced and sight is raised. Any new order exits.
const DAMAGE_SCALE:=0.35
const SUPPRESSION_SCALE:=0.3
const SIGHT_BONUS:=6.0
const RANGE_SCALE:=1.4  # upper-floor firing positions out-range the street
const ENTER_DISTANCE:=4.5

static func index(sim)->Dictionary:
	if sim.has_meta("garrison_index"):return sim.get_meta("garrison_index")
	var result:={"buildings":[],"owner":{}}
	var blocks:Array=sim.scenario.get("blocks",[])
	for spec in sim.scenario.get("architecture",[]):
		if str(spec.get("design",""))=="rock" or not spec.has("collision"):continue
		var first:int=int(spec.collision[0]);var count:int=int(spec.collision[1])
		var rects:Array[Rect2]=[]
		var bounds:=Rect2()
		for k in range(first,mini(first+count,blocks.size())):
			var r:Array=blocks[k]
			var rect:=Rect2(float(r[0]),float(r[1]),float(r[2]),float(r[3]))
			rects.append(rect)
			bounds=rect if bounds.size==Vector2.ZERO else bounds.merge(rect)
		if rects.is_empty():continue
		var area:=float(spec.source_size[0])*float(spec.source_size[1]) if spec.has("source_size") else bounds.get_area()
		var building:={"id":result.buildings.size(),"design":str(spec.design),"rects":rects,"bounds":bounds,"capacity":clampi(int(area/70.0),2,8),"height":float(spec.get("floors",2))*3.2+1.5,
			"floors":int(spec.get("floors",2)),"area":area,"blocks":range(first,mini(first+count,blocks.size())),"spec":spec,"damage":0.0,"state":0}
		for k in range(first,first+count):result.owner[k]=building.id
		result.buildings.append(building)
	sim.set_meta("garrison_index",result)
	return result

# Collapsed buildings (structure_damage.gd) are rubble: nothing to enter.
const COLLAPSED:=3
static func building_at(sim,p:Vector2)->int:
	var data:=index(sim)
	for building in data.buildings:
		if int(building.state)>=COLLAPSED or not building.bounds.grow(0.5).has_point(p):continue
		for rect in building.rects:
			if rect.grow(0.5).has_point(p):return building.id
	return -1

static func occupants(sim,building_id:int,team:int)->Array:
	return sim.units.filter(func(u):return sim.alive(u) and u.team==team and u.get("garrison",-1)==building_id)

# Nearest open doorway on the building's outline, reachable by a soldier.
static func entry_point(sim,building_id:int,from:Vector2,radius:float=2.65)->Vector2:
	var building:Dictionary=index(sim).buildings[building_id]
	var best:=Vector2(-1,-1);var distance:=INF
	# The doorway must hold the whole section footprint so orders can leave from it.
	var outline:Rect2=building.bounds.grow(radius+0.4)
	var steps:=maxi(8,int((outline.size.x+outline.size.y)*2.0/1.5))
	for i in steps:
		var t:=float(i)/steps
		var p:=perimeter_point(outline,t)
		if not sim.terrain.traversable(p,"land",radius) or sim.terrain.is_water(p):continue
		if p.distance_squared_to(from)<distance:distance=p.distance_squared_to(from);best=p
	return best

static func perimeter_point(r:Rect2,t:float)->Vector2:
	var perimeter:=2.0*(r.size.x+r.size.y)
	var d:=fposmod(t,1.0)*perimeter
	if d<r.size.x:return r.position+Vector2(d,0)
	d-=r.size.x
	if d<r.size.y:return Vector2(r.end.x,r.position.y+d)
	d-=r.size.y
	if d<r.size.x:return Vector2(r.end.x-d,r.end.y)
	d-=r.size.x
	return Vector2(r.position.x,r.end.y-d)

static func can_garrison(sim,u:Dictionary)->bool:
	return sim.alive(u) and not u.members.is_empty() and sim.definitions[u.kind].domain=="land"

# Player/AI order: returns how many sections were sent.
static func order(sim,ids:Array,building_id:int)->int:
	if building_id<0:return 0
	var sent:=0
	var building:Dictionary=index(sim).buildings[building_id]
	if int(building.state)>=COLLAPSED:return 0
	for id in ids:
		var u:Dictionary=sim.get_unit(id)
		if not can_garrison(sim,u):continue
		if occupants(sim,building_id,u.team).size()+sent>=int(building.capacity):break
		var door:=entry_point(sim,building_id,u.pos,float(sim.definitions[u.kind].radius))
		if door.x<0:continue
		leave(sim,u)
		if sim.issue([u.id],door,"move")<=0:continue
		u["garrison_target"]=building_id
		u["garrison_door"]=door
		sent+=1
	return sent

# Entry and exit are walked: soldiers queue at the doorway and pass through the
# wall one by one (hidden once through); leaving reverses it. While in transit
# the section's own movement and cover logic pause.
const DOOR_SPEED:=3.0
const QUEUE_SPACING:=1.1

static func transit(u:Dictionary)->String:
	return str(u.get("garrison_transit",""))

# Point on the building wall facing the doorway.
static func wall_point(sim,building_id:int,door:Vector2)->Vector2:
	var b:Rect2=index(sim).buildings[building_id].bounds
	return Vector2(clampf(door.x,b.position.x,b.end.x),clampf(door.y,b.position.y,b.end.y))

static func begin_entry(sim,u:Dictionary,building_id:int)->void:
	var door:Vector2=u.get("garrison_door",u.pos)
	u["garrison_transit"]="IN"
	u["garrison_wall"]=wall_point(sim,building_id,door)
	u.orders=[];u.path=[];u.intent={}
	u.hold_command=true
	u.state="ENTERING"
	var living:Array=u.members.filter(func(m):return m.hp>0)
	living.sort_custom(func(a,b):return a.pos.distance_squared_to(door)<b.pos.distance_squared_to(door))
	for rank in living.size():
		var m:Dictionary=living[rank]
		sim.Infantry.Cover.clear(m)
		m["transit_rank"]=rank
		m["at_door"]=false
		m["indoors"]=false

# Scripted walk for one soldier (bypasses section steering; short and local).
static func walk(sim,u:Dictionary,m:Dictionary,goal:Vector2,dt:float)->void:
	var old:Vector2=m.pos
	m.pos=old.move_toward(goal,DOOR_SPEED*dt)
	m.travel=old.distance_to(m.pos)
	if m.travel>0.001:
		m.facing=(m.pos-old).normalized()
		m.state="MARCHING"
		m.phase+=m.travel*6.5
	else:m.state="HOLDING"
	m.posture="STANDING"
	sim.relocate_actor(u,m,old)

static func step_transit(sim,u:Dictionary,dt:float)->void:
	var door:Vector2=u.get("garrison_door",u.pos)
	var wall:Vector2=u.get("garrison_wall",door)
	var outward:Vector2=(door-wall).normalized() if door.distance_to(wall)>0.01 else Vector2.RIGHT
	var living:Array=u.members.filter(func(m):return m.hp>0)
	if transit(u)=="IN":
		var through:=living.filter(func(m):return m.get("at_door",false)).size()
		var done:=true
		for m in living:
			if m.get("indoors",false):continue
			done=false
			var queue:int=int(m.get("transit_rank",0))-through
			if m.get("at_door",false) or queue<=0:
				# My turn: doorway, then through the wall.
				if not m.get("at_door",false):
					walk(sim,u,m,door,dt)
					if m.pos.distance_to(door)<0.3:m.at_door=true
				else:
					walk(sim,u,m,wall,dt)
					if m.pos.distance_to(wall)<0.25:m.indoors=true
			else:walk(sim,u,m,door+outward*QUEUE_SPACING*queue,dt)
		if done:
			u.erase("garrison_transit")
			enter(sim,u,int(u.garrison_target))
	elif transit(u)=="OUT":
		# One soldier at a time steps out through the wall to the doorway.
		var walking:Array=living.filter(func(m):return not m.get("indoors",false) and not m.get("at_door",false))
		var waiting:Array=living.filter(func(m):return m.get("indoors",false))
		if walking.is_empty() and not waiting.is_empty():
			waiting.sort_custom(func(a,b):return int(a.get("transit_rank",0))<int(b.get("transit_rank",0)))
			waiting[0].indoors=false
			waiting[0].pos=wall
			walking.append(waiting[0])
		for m in walking:
			# Step clear of the doorway to the soldier's formation spot.
			var spot:Vector2=door+m.offset
			walk(sim,u,m,spot,dt)
			if m.pos.distance_to(spot)<0.3:m.at_door=true
		if walking.is_empty() and waiting.is_empty():
			u.erase("garrison_transit")
			u.hold_command=false
			u.state="READY"
			for m in living:m.erase("at_door")

static func enter(sim,u:Dictionary,building_id:int)->void:
	var building:Dictionary=index(sim).buildings[building_id]
	u["garrison"]=building_id
	u.erase("garrison_target")
	u.orders=[];u.path=[];u.intent={}
	u.hold_command=true
	u.state="GARRISONED"
	for m in u.members:sim.Infantry.Cover.clear(m)
	# Window posts on every face, just outside the walls, spread around the outline.
	# Window posts clear of the wall so shots along a face are not self-blocked;
	# each extra section takes posts offset around the outline.
	var outline:Rect2=building.bounds.grow(0.7)
	var living:Array=u.members.filter(func(m):return m.hp>0)
	var slot:int=occupants(sim,building_id,u.team).filter(func(o):return o.id!=u.id).size()
	for i in living.size():
		var m:Dictionary=living[i]
		m.pos=perimeter_point(outline,(i+0.5)/living.size()+0.08+slot*0.137)
		# Inside, nobody is walking: clear motion so combat can aim and fire.
		m.travel=0.0;m.speed=0.0;m.state="HOLDING"
		m["cover_phase"]="";m.cover_goal=Vector2.ZERO
		m.posture="CROUCHED"
		m["indoors"]=true
	u.pos=u.get("garrison_door",u.pos)
	sim.events.append({"type":"decision","unit":u.id,"phase":"GARRISON","reason":"Section entered a building","pos":building.bounds.get_center()})

static func leave(sim,u:Dictionary)->void:
	if u.get("garrison",-1)<0:return
	var building:int=int(u.garrison)
	u["garrison"]=-1
	var door:Vector2=u.get("garrison_door",u.pos)
	u["garrison_wall"]=wall_point(sim,building,door)
	u["garrison_transit"]="OUT"
	u.hold_command=true
	u.state="EXITING"
	var rank:=0
	for m in u.members:
		if m.hp<=0:continue
		m["indoors"]=true
		m["at_door"]=false
		m["transit_rank"]=rank
		m.pos=u.garrison_wall
		rank+=1
	u.pos=door

# Per tick: sections reaching their doorway enter; garrisoned sections given a
# new order leave. Sections redirected elsewhere drop their garrison intent.
static func tick(sim,dt:float=1.0/30.0)->void:
	for u in sim.units:
		if not sim.alive(u) or u.members.is_empty():continue
		if transit(u)=="IN" and not u.orders.is_empty():
			# Re-ordered mid-entry: whoever got in files back out.
			u.erase("garrison_target")
			u["garrison_transit"]="OUT"
			var rank:=0
			for m in u.members:
				if m.hp>0 and m.get("indoors",false):m.transit_rank=rank;rank+=1
				else:m["at_door"]=true
		if transit(u)!="":
			step_transit(sim,u,dt)
			continue
		if u.get("garrison",-1)>=0:
			if not u.orders.is_empty():leave(sim,u)
			elif sim.time>=float(u.get("window_check",0.0)):
				u["window_check"]=sim.time+1.0+float(u.id%5)*0.1
				man_windows(sim,u)
			continue
		if not u.has("garrison_target"):continue
		var door:Vector2=u.get("garrison_door",u.pos)
		if u.orders.is_empty() or u.orders[0].pos.distance_to(door)>3.0:
			if u.pos.distance_to(door)<=ENTER_DISTANCE:begin_entry(sim,u,u.garrison_target)
			else:u.erase("garrison_target")
		elif u.pos.distance_to(door)<=ENTER_DISTANCE:
			begin_entry(sim,u,u.garrison_target)

# Defenders move room to room to the windows facing the nearest spotted enemy.
static func man_windows(sim,u:Dictionary)->void:
	var building:Dictionary=index(sim).buildings[int(u.garrison)]
	var center:Vector2=building.bounds.get_center()
	var reach:float=maxf(building.bounds.size.x,building.bounds.size.y)*0.5+30.0
	var threat:Dictionary={}
	var best:=INF
	for other in sim.units:
		if not sim.alive(other) or other.team==u.team or sim.definitions[other.kind].get("structure",false):continue
		var d:float=other.pos.distance_to(center)
		if d<reach and d<best and sim.contact_known(u,other):best=d;threat=other
	if threat.is_empty() or u.get("window_threat",-1)==threat.id and threat.pos.distance_to(u.get("window_threat_pos",Vector2.ZERO))<4.0:return
	u["window_threat"]=threat.id
	u["window_threat_pos"]=threat.pos
	var outline:Rect2=building.bounds.grow(0.7)
	var posts:Array=[]
	var steps:=maxi(8,int((outline.size.x+outline.size.y)*2.0/1.6))
	for i in steps:posts.append(perimeter_point(outline,float(i)/steps))
	# Keep clear of windows other sections already hold.
	var held:Array=[]
	for other in occupants(sim,int(u.garrison),u.team):
		if other.id==u.id:continue
		for m in other.members:if m.hp>0:held.append(m.pos)
	posts=posts.filter(func(p):return held.all(func(h):return p.distance_to(h)>1.4))
	posts.sort_custom(func(a,b):return a.distance_squared_to(threat.pos)<b.distance_squared_to(threat.pos))
	var k:=0
	for m in u.members:
		if m.hp<=0 or k>=posts.size():continue
		var old:Vector2=m.pos
		m.pos=posts[k];k+=1
		m.travel=0.0
		m.facing=(threat.pos-m.pos).normalized()
		sim.relocate_actor(u,m,old)

# The building is gone (collapse): survivors are thrown clear where they stand,
# with no doorway walk, and drop any pending entry.
static func evict(sim,u:Dictionary)->void:
	u["garrison"]=-1
	for key in ["garrison_transit","garrison_target","garrison_wall","window_threat","window_threat_pos"]:u.erase(key)
	u.hold_command=false
	u.orders=[];u.path=[];u.intent={}
	u.state="READY"
	var centre:=Vector2.ZERO;var count:=0
	for m in u.members:
		for key in ["indoors","at_door","transit_rank"]:m.erase(key)
		if m.hp>0:centre+=m.pos;count+=1
	if count>0:u.pos=centre/count

static func inside(u:Dictionary)->bool:
	return u.get("garrison",-1)>=0
