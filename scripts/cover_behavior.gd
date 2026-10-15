class_name CoverBehavior
extends RefCounted

# Fictional game distances/timings, not real-world movement doctrine.
const LEASH:=10.0

static func clear(member:Dictionary) -> void:
	member["occupying"]=false
	member.cover_goal=Vector2.ZERO
	member["cover_path"]=[]
	member["cover_phase"]=""
	member["cover_blocked"]=0.0
	member["cover_screened"]=false

static func update(u:Dictionary,sim) -> void:
	if u.members.is_empty() or not sim.scenario.get("autonomy",false):return
	var constrained:bool=u.has("building_id") or u.hold_command or u.get("regroup_active",false) or sim.time<u.get("cover_resume_after",0.0) or (not u.orders.is_empty() and u.orders[0].mode in ["move","retreat"]) or (not u.maneuver.is_empty() and u.maneuver.get("phase","")!="SUPPORT")
	if constrained:
		for member in u.members:clear(member)
		return
	var threats:Array=[]
	var threat:Dictionary={}
	var distance:=INF
	var neighbors:Array=sim.range_candidates(u.pos,25) if sim.ticking else sim.units
	for other in neighbors:
		if not sim.alive(other) or other.team==u.team or not sim.contact_known(u,other) or not sim.effective_unit(other,u.kind):continue
		if sim.can_fire(u,other) and not in_weapon_range(other,u,sim):continue
		var gap:float=u.pos.distance_squared_to(other.pos)
		if gap<625:
			threats.append(other)
			if gap<distance:threat=other;distance=gap
	var alert:bool=not threat.is_empty() or u.suppression>0.2
	if not alert:
		# A section halted beside its own works occupies them (no enemy needed).
		# Engineers with a site to build stay on the job instead of manning works.
		var building:bool=u.has("building_id") or (u.kind=="engineer" and sim.units.any(func(s):return s.get("queued_for",-1)==u.id and float(s.get("build_left",0.0))>0))
		if u.orders.is_empty() and not building and occupy_works(u,sim,threat):return
		for member in u.members:
			if member.get("occupying",false):continue
			if sim.time>=maxf(member.cover_until,member.get("cover_deadline",0.0)):clear(member)
		return
	var moving:=0
	for member in u.members:
		if member.hp>0 and member.get("cover_phase","")=="SEEKING":moving+=1
	# Keep at least half the living section available while others move. Rounding
	# up sent two of three rifles away at once; dead records must not add slots.
	var living:int=u.members.filter(func(m):return m.hp>0).size()
	var limit:int=maxi(1,floori(living/2.0))
	for member in u.members:
		if member.hp<=0:continue
		var phase:String=member.get("cover_phase","")
		if phase in ["SEEKING","SETTLING","SHELTERED"]:
			var exposed:bool=member.get("cover_screened",false) and threats.any(func(contact):return sim.terrain.line_clear(contact.pos,member.cover_goal))
			if exposed or member.cover_goal.distance_to(u.pos)>LEASH or member.get("cover_blocked",0.0)>2.0 or (phase!="SHELTERED" and sim.time>member.get("cover_deadline",0.0)):
				clear(member);member.cover_until=sim.time+1.0
			else:continue
		if sim.time<member.cover_until:continue
		if moving>=limit:
			member.cover_phase="OVERWATCH"
			continue
		var result:=find_slot(u,member,sim,threat,threats)
		member.cover_until=sim.time+2.0+member.index*0.15
		if result.is_empty():member.cover_phase="EXPOSED";continue
		member.cover_goal=result.pos
		member["cover_screened"]=not threat.is_empty() and not soft_cover(sim,result.pos) and not sim.terrain.line_clear(threat.pos,result.pos)
		member.cover_path=result.path
		member.cover_phase="SEEKING"
		member.cover_blocked=0.0
		member["cover_deadline"]=sim.time+12.0
		moving+=1
		sim.events.append({"type":"decision","unit":u.id,"phase":"COVER","reason":"Soldier moving to shelter","pos":result.pos})

static func find_slot(u:Dictionary,member:Dictionary,sim,threat:Dictionary,threats:Array=[]) -> Dictionary:
	if threats.is_empty() and not threat.is_empty():threats=[threat]
	var candidates:Array=[]
	var occupants:Array=sim.range_candidates(u.pos,LEASH*2+4) if sim.ticking else sim.units
	var points:Array[Vector2]=[]
	for ring in [1.2,2.4,3.6,5.5,7.5,9.0]:
		for index in 16:points.append(u.pos+Vector2.from_angle(index*TAU/16)*ring)
	# Sample the actual thin wall bands; coarse circular rings miss them.
	for wall in sim.terrain.blocks+sim.terrain.dynamic_blocks:
		if not wall.grow(LEASH).has_point(u.pos):continue
		for x in range(ceili(wall.position.x),floori(wall.end.x)+1,1 if wall.size.x<8 else 2):
			points.append(Vector2(x,wall.position.y-1.05));points.append(Vector2(x,wall.end.y+1.05))
		for y in range(ceili(wall.position.y),floori(wall.end.y)+1,2):
			points.append(Vector2(wall.position.x-1.05,y));points.append(Vector2(wall.end.x+1.05,y))
	# Trench and hedgehog interiors are protective positions in their own right.
	for zone in sim.terrain.field_zones:
		if not ("infantry" in zone.cover) or not zone.rect.grow(LEASH).has_point(u.pos):continue
		var long_x:bool=zone.rect.size.x>=zone.rect.size.y
		var length:float=zone.rect.size.x if long_x else zone.rect.size.y
		for i in int(length/1.3):
			var t:=(i+0.5)*1.3
			points.append(zone.rect.position+(Vector2(t,zone.rect.size.y/2) if long_x else Vector2(zone.rect.size.x/2,t)))
	for point in points:
		if point.distance_to(u.pos)>LEASH:continue
		if not sim.terrain.cover(point) or not sim.terrain.traversable(point,"land",0.8):continue
		# Vegetation/rubble offer abstract partial protection. A wall slot must
		# actually screen the observed threat rather than reward its exposed face.
		var soft:bool=soft_cover(sim,point)
		if not soft and threats.any(func(contact):return sim.terrain.line_clear(contact.pos,point)):continue
		var reserved:=false
		for other in occupants:
			if not sim.alive(other) or sim.definitions[other.kind].domain!="land":continue
			if other.team!=u.team and not sim.contact_known(u,other):continue
			if other.members.is_empty():
				if point.distance_to(other.pos)<float(sim.definitions[other.kind].radius)+0.85:reserved=true
			for peer in other.members:
				if peer.hp<=0 or (u.id==other.id and member.index==peer.index):continue
				if point.distance_to(peer.pos)<1.65 or (other.team==u.team and peer.cover_goal!=Vector2.ZERO and point.distance_to(peer.cover_goal)<1.65):reserved=true
		if reserved:continue
		var score:float=member.pos.distance_to(point)
		if not threat.is_empty():
			if not sim.terrain.line_clear(threat.pos,point):score-=3.0
			if point.distance_to(threat.pos)<member.pos.distance_to(threat.pos)-2:score+=4.0
		candidates.append({"pos":point,"score":score})
	candidates.sort_custom(func(a,b):return a.score<b.score)
	for candidate in candidates.slice(0,6):
		var route:Array=sim.terrain.path(member.pos,candidate.pos,"land",float(member.get("body_radius",0.8)),[],"infantry")
		if route.is_empty():continue
		var bounded:=true
		var length:=0.0
		var previous:Vector2=member.pos
		for point in route:
			if point.distance_to(u.pos)>LEASH:bounded=false
			length+=previous.distance_to(point);previous=point
		if bounded and length<=18:return {"pos":candidate.pos,"path":route}
	return {}

# Slots along nearby own sandbag lines (friendly side, away from the threat)
# and inside own trenches, one per soldier, nearest first.
static func work_slots(u:Dictionary,sim,threat_dir:Vector2) -> Array:
	var slots:Array=[]
	for site in sim.units:
		if not sim.alive(site) or site.team!=u.team or site.get("build_left",0.0)>0:continue
		if site.kind not in ["tactical_cover","fighting_trench"]:continue
		var rect:Rect2=sim.FieldOps.footprint(sim,site.kind,site.pos,site.get("rotated",false))
		if rect.get_center().distance_to(u.pos)>LEASH+4.0:continue
		var long_x:bool=rect.size.x>=rect.size.y
		var length:float=rect.size.x if long_x else rect.size.y
		var across:=Vector2(0,1) if long_x else Vector2(1,0)
		var side:float=-signf(threat_dir.dot(across)) if absf(threat_dir.dot(across))>0.05 else 1.0
		for i in maxi(1,int(length/1.3)):
			var t:=(i+0.5)*length/maxi(1,int(length/1.3))
			var along:=rect.position+(Vector2(t,0) if long_x else Vector2(0,t))
			var middle:=along+across*(rect.size.y/2 if long_x else rect.size.x/2)
			if site.kind=="fighting_trench":slots.append(middle)
			# Shoulder against the friendly face of the wall (body radius + a hand).
			else:slots.append(middle+across*side*((rect.size.y if long_x else rect.size.x)/2+0.85))
	return slots

static func occupy_works(u:Dictionary,sim,threat:Dictionary) -> bool:
	if sim.time<u.get("occupy_check",0.0):return u.members.any(func(m):return m.get("occupying",false))
	# Searching is costly: a failed search backs off ~10 s (staggered per unit) so
	# idle defenders across the map do not re-run it every few ticks.
	u["occupy_check"]=sim.time+9.0+float(u.id%7)*0.4
	if u.members.any(func(m):return m.hp>0 and m.get("occupying",false)):return true
	var enemy_side:Vector2=sim.field_ops.get("enemy_insertion",u.pos+Vector2(0,-1)) if u.team==0 else sim.field_ops.get("insertion",u.pos+Vector2(0,1))
	var aim:Vector2=threat.pos if not threat.is_empty() else enemy_side
	var threat_dir:Vector2=(aim-u.pos).normalized()
	var slots:=work_slots(u,sim,threat_dir)
	if slots.is_empty():return halt_in_cover(u,sim,threat_dir)
	var taken:Array=[]
	for member in u.members:
		if member.hp<=0:continue
		var best:=Vector2(-1,-1);var distance:=INF
		for slot in slots:
			if slot in taken or not sim.terrain.traversable(slot,"land",0.8):continue
			if slot.distance_squared_to(member.pos)<distance:distance=slot.distance_squared_to(member.pos);best=slot
		if best.x<0:continue
		var route:Array=sim.terrain.path(member.pos,best,"land",float(member.get("body_radius",0.8)),[],"infantry")
		if route.is_empty():continue
		taken.append(best)
		member.cover_goal=best;member.cover_path=route;member.cover_phase="SEEKING";member.cover_blocked=0.0
		member["cover_screened"]=false;member["occupying"]=true;member["hold_facing"]=threat_dir
		member.cover_until=sim.time+100000.0;member["cover_deadline"]=sim.time+100000.0
	if taken.is_empty():return halt_in_cover(u,sim,threat_dir)
	sim.events.append({"type":"decision","unit":u.id,"phase":"COVER","reason":"Section manning field works","pos":u.pos})
	return true

# No field works nearby: each soldier takes the nearest real cover within a few
# metres (building corner, yard wall, car, rubble) that screens the enemy side,
# using a far synthetic threat along the expected direction of contact.
static func halt_in_cover(u:Dictionary,sim,threat_dir:Vector2) -> bool:
	var phantom:={"pos":u.pos+threat_dir*35.0,"members":[]}
	var any:=false
	for member in u.members:
		if member.hp<=0 or member.get("occupying",false):continue
		var result:=find_slot(u,member,sim,phantom,[phantom])
		if result.is_empty() or result.pos.distance_to(member.pos)>8.0:continue
		member.cover_goal=result.pos;member.cover_path=result.path;member.cover_phase="SEEKING";member.cover_blocked=0.0
		member["cover_screened"]=false;member["occupying"]=true;member["hold_facing"]=threat_dir
		member.cover_until=sim.time+100000.0;member["cover_deadline"]=sim.time+100000.0
		any=true
	if any:sim.events.append({"type":"decision","unit":u.id,"phase":"COVER","reason":"Section taking cover at halt","pos":u.pos})
	return any

static func seeking(u:Dictionary) -> bool:
	return u.members.any(func(m):return m.hp>0 and m.get("cover_phase","") in ["SEEKING","SETTLING"])

static func soft_cover(sim,point:Vector2) -> bool:
	if sim.terrain.rubble.has_point(point):return true
	if sim.terrain.zone_cover(point):return true
	for patch in sim.terrain.woods:
		if patch.has_point(point):return true
	return false

static func in_weapon_range(threat:Dictionary,u:Dictionary,sim) -> bool:
	# A section already able to fire outside an observed enemy's weapon range
	# need not abandon that firing position. Keep screened positions valid: range alone,
	# not line of fire through the shelter, determines this threat envelope.
	for source in ([threat] if threat.members.is_empty() else threat.members):
		if source.hp<=0:continue
		var weapon:String=threat.kind if threat.members.is_empty() else ("atgm" if threat.kind=="atgm" and source.index==0 else "rifle")
		if not sim.effective_weapon(weapon,u.kind):continue
		var definition:Dictionary=sim.definitions[weapon]
		var height:float=float(definition.altitude)-float(sim.definitions[u.kind].altitude)
		if source.pos.distance_squared_to(u.pos)+height*height<=float(definition.range)*float(definition.range):return true
	return false
