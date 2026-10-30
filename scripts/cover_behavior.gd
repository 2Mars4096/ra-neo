class_name CoverBehavior
extends RefCounted

# Fictional game distances/timings, not real-world movement doctrine.
const LEASH:=10.0
# Contact drill: on first incoming fire the section drops and returns fire for
# this long before the first soldier rushes for shelter.
const DRILL:=0.8
# Slots rated for line of fire (the costly part of a search), and enough valid
# ones to stop early. Cheap filters order the nearest candidates first.
const RATED:=24
const RATED_VALID:=8
# A soldier gets up to run for shelter: routes are planned for the standing
# body. The prone footprint (1.15 m) closed gaps a runner fits through, so a
# soldier who had gone flat in the open found no route to reachable cover.
const STRIDE:=0.8
# Stand just outside the physical wall, using the movement check's clearance.
const FACE_GAP:=STRIDE+preload("res://scripts/terrain.gd").OBSTACLE_MARGIN+0.03
# Leave room for two standing bodies (1.55 minimum), including when a new
# occupant must settle between squadmates who already reached their slots.
const WORK_SPACING:=1.65
# A halted friendly section's formation (offsets ~1 u, prone 1.5 u, plus a body).
const FOOTPRINT:=2.0

# Maneuvers that leave the soldiers free to take cover: covering a partner,
# consolidating after casualties, and a cover bound once it has arrived.
static func holds_cover(maneuver:Dictionary) -> bool:
	var phase:String=maneuver.get("phase","")
	return phase in ["SUPPORT","CONSOLIDATE","PRESSURE_WAIT"] or (phase=="BOUND" and maneuver.get("arrived",false))

static func clear(member:Dictionary) -> void:
	member["occupying"]=false
	member.cover_goal=Vector2.ZERO
	member["cover_path"]=[]
	member["cover_phase"]=""
	member["cover_blocked"]=0.0
	member["cover_screened"]=false
	member.cover_until=0.0
	member["cover_deadline"]=0.0
	member.erase("cover_from")

# Shelter points that pass the terrain tests, by anchor position. Every soldier
# of a section rates the same points and terrain cannot change during one
# update(), so the scan is shared by the section only while update() runs.
static var _shelters:Dictionary={}
static var _sharing:=false

static func update(u:Dictionary,sim) -> void:
	if u.members.is_empty() or not sim.scenario.get("autonomy",false):return
	var t0:int=Time.get_ticks_usec() if sim.profiling else 0
	_sharing=true
	_update(u,sim)
	_sharing=false
	_shelters.clear()
	if sim.profiling:sim._lap("cover_update",t0)

static func _update(u:Dictionary,sim) -> void:
	var constrained:bool=u.has("building_id") or u.hold_command or u.get("regroup_active",false) or sim.time<u.get("cover_resume_after",0.0) or (not u.orders.is_empty() and u.orders[0].mode in ["move","retreat"]) or (not u.maneuver.is_empty() and not holds_cover(u.maneuver))
	# First incoming fire after a quiet spell: drop and return fire before
	# anyone rushes (DRILL). Fire taken while under orders is not a fresh contact.
	var fired:float=float(u.get("fired_on",-100.0))
	if fired>float(u.get("drill_seen",-100.0)):
		if fired-float(u.get("drill_seen",-100.0))>8.0 and not constrained:u["drill_until"]=sim.time+DRILL
		u["drill_seen"]=fired
	if constrained:
		for member in u.members:
			clear(member)
			_cancel_search(u,member,sim)
		u["crossfire"]=false
		return
	_revalidate_shelters(u,sim)
	var threats:Array=[]
	var threat:Dictionary={}
	var weight:=0.0
	var neighbors:Array=sim.range_candidates(u.pos,25) if sim.ticking else sim.units
	for other in neighbors:
		if not sim.alive(other) or other.team==u.team or not sim.contact_known(u,other) or not sim.effective_unit(other,u.kind):continue
		if sim.can_fire(u,other) and not in_weapon_range(other,u,sim):continue
		var gap:float=u.pos.distance_squared_to(other.pos)
		if gap<625:
			threats.append(other)
			# The main threat is the strongest per distance, not merely the nearest.
			var w:float=power(other)/maxf(4.0,sqrt(gap))
			if w>weight:threat=other;weight=w
	if threats.size()>1:
		threats.sort_custom(func(a,b):return power(a)/maxf(4.0,u.pos.distance_to(a.pos))>power(b)/maxf(4.0,u.pos.distance_to(b.pos)))
		threats=threats.slice(0,3)
	u["crossfire"]=crossfire(u,threats)
	var alert:bool=not threat.is_empty() or u.suppression>0.2
	if not alert:
		# A section halted beside its own works occupies them (no enemy needed).
		# Engineers with a site to build stay on the job instead of manning works.
		# Occupied shelters stay put while their geometry remains valid. Combat
		# shelters without current contact expire before the next halt search.
		for member in u.members:
			if member.get("occupying",false):continue
			if sim.time>=maxf(member.cover_until,member.get("cover_deadline",0.0)):clear(member)
		var building:bool=u.has("building_id") or u.has("clearing_id") or (u.kind=="engineer" and sim.units.any(func(s):return s.get("queued_for",-1)==u.id and float(s.get("build_left",0.0))>0))
		# A bleeding squadmate comes first: stay beside the casualty for buddy aid instead of
		# walking off to man works (aid would only call the soldier back).
		var bleeding:bool=u.members.any(func(m):return m.get("wound","")=="SEVERE" and not m.get("stable",false))
		if u.orders.is_empty() and not building and not bleeding:occupy_works(u,sim,threat)
		else:
			for member in u.members:_cancel_search(u,member,sim)
		return
	var moving:=0
	for member in u.members:
		if member.hp>0 and member.get("cover_phase","")=="SEEKING":moving+=1
	# Keep at least half the living section available while others move. Rounding
	# up sent two of three rifles away at once; dead records must not add slots.
	var living:int=u.members.filter(func(m):return m.hp>0).size()
	var limit:int=maxi(1,floori(living/2.0))
	var bearing:Vector2=(threat.pos-u.pos).normalized() if not threat.is_empty() else Vector2.ZERO
	# Anchors of other friendly sections halted to fight: a soldier trailing
	# through one does not stop there to watch or hide, but carries on to its
	# own section's formation.
	var footprints:=PackedVector2Array()
	for other in neighbors:
		if other.team==u.team and other.id!=u.id and not other.members.is_empty() and other.pos.distance_squared_to(u.pos)<(LEASH+FOOTPRINT)*(LEASH+FOOTPRINT) and sim.fight_halted(other):footprints.append(other.pos)
	for member in u.members:
		if member.hp<=0:
			_cancel_search(u,member,sim)
			continue
		var phase:String=member.get("cover_phase","")
		# Inside one, or still to pass through one on the way to its own slot.
		var intruding:=false
		var slot:Vector2=u.pos+member.offset
		for at in footprints:
			if member.pos.distance_squared_to(at)<FOOTPRINT*FOOTPRINT:intruding=true;break
			if member.pos.distance_squared_to(slot)>4.0 and Geometry2D.get_closest_point_to_segment(at,member.pos,slot).distance_squared_to(at)<FOOTPRINT*FOOTPRINT:intruding=true;break
		if intruding and phase in ["OVERWATCH","EXPOSED"]:member.cover_phase="";phase=""
		if phase in ["SEEKING","SETTLING","SHELTERED"]:
			var weapon:String=member_weapon(u,member)
			# A wall shelter seen by a threat it cannot answer from there is lost;
			# one it can shoot back at is now a fire-from-cover position.
			var exposed:bool=member.get("cover_screened",false) and threats.any(func(contact):return sees(sim,contact,member.cover_goal) and not answers(sim,weapon,member.cover_goal,contact))
			# A shelter taken before this bearing was known (only suppressed, or
			# halted facing a guess; field works carry no bearing) is checked
			# against the new main threat: a wall face it sees but cannot be
			# answered from is abandoned; screened or firing shelters are kept.
			var stale:bool=not exposed and bearing!=Vector2.ZERO and member.has("cover_from") and (member.cover_from==Vector2.ZERO or member.cover_from.dot(bearing)<0.7)
			if stale:
				member.cover_from=bearing
				exposed=not soft_cover(sim,member.cover_goal) and sees(sim,threat,member.cover_goal) and not answers(sim,weapon,member.cover_goal,threat)
			# Shot at with no shot back (the enemy moved or took cover) and not
			# pinned: every couple of seconds look for a firing slot a short rush
			# away; a long run in the open is worse than holding the shelter.
			elif not exposed and phase=="SHELTERED" and member.has("cover_from") and member.target<0 and sim.time>=member.cover_until and moving<limit and sim.time>=u.get("drill_until",0.0) and sim.time-float(u.get("fired_on",-100.0))<2.0 and maxf(u.suppression,member.suppression)<=0.65:
				var result:=find_slot(u,member,sim,threat,threats)
				if result.get("pending",false):continue
				member.cover_until=sim.time+2.0+member.index*0.15
				if result.get("fire",false) and route_length(member.pos,result.path)<=6.0:
					clear(member)
					assign(u,member,sim,result,bearing)
					member.cover_until=sim.time+2.0+member.index*0.15
					moving+=1
					continue
			if exposed:
				clear(member);member.cover_until=sim.time+(0.0 if stale and exposed else 1.0)
			else:
				_cancel_search(u,member,sim)
				continue
		if intruding or sim.time<member.cover_until:
			_cancel_search(u,member,sim)
			continue
		# Contact drill, then bounding: one soldier rushes while the rest fire.
		if moving>=limit or sim.time<u.get("drill_until",0.0):
			_cancel_search(u,member,sim)
			member.cover_phase="OVERWATCH"
			continue
		var result:=find_slot(u,member,sim,threat,threats)
		if result.get("pending",false):continue
		member.cover_until=sim.time+2.0+member.index*0.15
		if result.is_empty():member.cover_phase="EXPOSED";continue
		assign(u,member,sim,result,bearing)
		moving+=1

# Apply the same validity and approach limits to quiet occupation and combat
# shelter. Previously the idle branch skipped occupants forever, even after
# their trench disappeared or a route had been blocked for half a minute.
static func _revalidate_shelters(u:Dictionary,sim) -> void:
	for member in u.members:
		if member.hp<=0:continue
		var phase:String=member.get("cover_phase","")
		if phase not in ["SEEKING","SETTLING","SHELTERED"]:continue
		var unavailable:bool=not sim.terrain.cover(member.cover_goal) or not sim.terrain.traversable(member.cover_goal,"land",STRIDE)
		var stranded:bool=phase=="SHELTERED" and not sim.terrain.cover(member.pos)
		var failed:bool=member.get("cover_blocked",0.0)>2.0 or (phase!="SHELTERED" and sim.time>member.get("cover_deadline",0.0))
		if not unavailable and not stranded and not failed and member.cover_goal.distance_to(u.pos)<=LEASH:continue
		var occupied:bool=member.get("occupying",false)
		clear(member)
		# Back off a failed approach, but let destroyed shelter be replaced at
		# once. Other soldiers can retain their still-valid positions.
		member.cover_until=sim.time+(1.0 if failed else 0.0)
		if occupied:u["occupy_check"]=minf(float(u.get("occupy_check",sim.time)),member.cover_until)

static func assign(u:Dictionary,member:Dictionary,sim,result:Dictionary,bearing:Vector2) -> void:
	member.cover_goal=result.pos
	member["cover_screened"]=result.screened
	member["cover_from"]=bearing
	member.cover_path=result.path
	member.cover_phase="SEEKING"
	member.cover_blocked=0.0
	member["cover_deadline"]=sim.time+12.0
	sim.events.append({"type":"decision","unit":u.id,"phase":"COVER","reason":"Soldier moving to shelter","pos":result.pos})

static func route_length(from:Vector2,route:Array) -> float:
	var length:=0.0
	for point in route:length+=from.distance_to(point);from=point
	return length

# Both combat shelter and idle work occupation use the same local route
# contract. Every waypoint must fit inside the soldier's movement leash.
static func _shelter_route(u:Dictionary,member:Dictionary,sim,goal:Vector2) -> Array:
	if goal.distance_to(u.pos)>LEASH:return []
	var route:Array
	if _squadmate_blocks(u,member,[goal]) and sim.terrain.segment_clear(member.pos,goal,"land",STRIDE):
		route=_detour(u,member,sim,goal)
	else:
		route=sim.terrain.path(member.pos,goal,"land",STRIDE,[],"infantry")
		if not route.is_empty() and _squadmate_blocks(u,member,route):route=_detour(u,member,sim,goal)
	if route.is_empty() or route.any(func(point):return point.distance_to(u.pos)>LEASH) or route_length(member.pos,route)>18.0:return []
	return route

static func find_slot(u:Dictionary,member:Dictionary,sim,threat:Dictionary,threats:Array=[]) -> Dictionary:
	if not _search_admitted(u,member,sim,1 if threat.has("id") else 0):return {"pending":true}
	var t0:int=Time.get_ticks_usec() if sim.profiling else 0
	var slot:=_find_slot(u,member,sim,threat,threats)
	if sim.profiling:sim._lap("cover_find_slot",t0)
	return slot

# A complete search rates <=24 slots and tries <=6 routes. Reserve a bounded
# bundle before evaluating any candidates; existing shelter and retry times
# survive denial. Deferred owners retry on the next simulation tick.
static func _search_admitted(u:Dictionary,member:Dictionary,sim,priority:int=0) -> bool:
	if sim.terrain.planning.request("cover",int(u.id),"member:%d"%member.index,priority):return true
	u["cover_next"]=sim.time
	return false

static func _cancel_search(u:Dictionary,member:Dictionary,sim) -> void:
	sim.terrain.planning.cancel_request("cover",int(u.id),"member:%d"%member.index)

static func _find_slot(u:Dictionary,member:Dictionary,sim,threat:Dictionary,threats:Array=[]) -> Dictionary:
	if threats.is_empty() and not threat.is_empty():threats=[threat]
	var occupants:Array=sim.range_candidates(u.pos,LEASH*2+4) if sim.ticking else sim.units
	var shelters:Array
	if _sharing and _shelters.has(u.pos):shelters=_shelters[u.pos]
	else:
		shelters=_shelter_points(u,sim)
		if _sharing:_shelters[u.pos]=shelters
	return _pick_slot(u,member,sim,threat,threats,occupants,shelters)

# Candidate points within the leash that offer cover and room for a soldier.
static func _shelter_points(u:Dictionary,sim) -> Array:
	var lap:int=Time.get_ticks_usec() if sim.profiling else 0
	var points:Array[Vector2]=[]
	var protected:=PackedByteArray()
	for ring in [1.2,2.4,3.6,5.5,7.5,9.0]:
		for index in 16:
			points.append(u.pos+Vector2.from_angle(index*TAU/16)*ring)
			protected.append(0)
	# Sample the actual thin wall bands; coarse circular rings miss them. Yard
	# walls, cars and kiosks (hard cover props) screen as well as buildings.
	var wall_groups:Array=[sim.terrain._static_candidates("building",u.pos,LEASH),sim.terrain.dynamic_blocks]
	for source in wall_groups.size():
		# These samples are 1.05 units outside a cover wall: strictly inside
		# its 1.4-unit cover band. The source proves cover, but never clearance
		# from a neighboring wall. Field-mode dynamic blocks need the full
		# cover query because not every dynamic blocker supplies cover.
		var known_cover:int=1 if sim.terrain.style=="showcase" and (source==0 or not sim.terrain.field_mode) else 0
		for wall in wall_groups[source]:
			if not wall.grow(LEASH).has_point(u.pos):continue
			for x in range(ceili(wall.position.x),floori(wall.end.x)+1,1 if wall.size.x<8 else 2):
				points.append(Vector2(x,wall.position.y-1.05));points.append(Vector2(x,wall.end.y+1.05))
				protected.append(known_cover);protected.append(known_cover)
			for y in range(ceili(wall.position.y),floori(wall.end.y)+1,2):
				points.append(Vector2(wall.position.x-1.05,y));points.append(Vector2(wall.end.x+1.05,y))
				protected.append(known_cover);protected.append(known_cover)
	# Trench and hedgehog interiors are protective positions in their own right.
	for zone in sim.terrain.field_zones:
		if not ("infantry" in zone.cover) or not zone.rect.grow(LEASH).has_point(u.pos):continue
		var long_x:bool=zone.rect.size.x>=zone.rect.size.y
		var length:float=zone.rect.size.x if long_x else zone.rect.size.y
		for i in int(length/1.3):
			var t:=(i+0.5)*1.3
			points.append(zone.rect.position+(Vector2(t,zone.rect.size.y/2) if long_x else Vector2(zone.rect.size.x/2,t)))
			protected.append(1) # Interior of a zone explicitly granting infantry cover.
	if sim.profiling:lap=sim._lap("cover_points_generate",lap)
	var shelters:Array=[]
	for i in points.size():
		var point:Vector2=points[i]
		if point.distance_to(u.pos)>LEASH:continue
		if protected[i]==0 and not sim.terrain.cover(point):continue
		if not sim.terrain.traversable(point,"land",0.8):continue
		shelters.append(point)
	if sim.profiling:sim._lap("cover_points_filter",lap)
	return shelters

static func _pick_slot(u:Dictionary,member:Dictionary,sim,threat:Dictionary,threats:Array,occupants:Array,shelters:Array) -> Dictionary:
	var lap:int=Time.get_ticks_usec() if sim.profiling else 0
	var candidates:Array=[]
	# Occupied spots (bodies and friendly cover goals) do not depend on the
	# point: gathered once instead of per candidate point.
	var taken:=PackedVector2Array()
	var clearances:=PackedFloat64Array()
	for other in occupants:
		if not sim.alive(other) or sim.definitions[other.kind].domain!="land":continue
		# Exact structure rectangles are already in the terrain query. Their
		# enclosing actor radii would reserve the very faces being sampled.
		if other.get("structure",false):continue
		if other.team!=u.team and not sim.contact_known(u,other):continue
		if other.members.is_empty():
			taken.append(other.pos);clearances.append(float(sim.definitions[other.kind].radius)+0.85)
		# Another friendly section halted to fight: its formation footprint
		# stays its own, so the two do not mingle into one target.
		elif other.team==u.team and other.id!=u.id and sim.fight_halted(other):
			taken.append(other.pos);clearances.append(FOOTPRINT)
		for peer in other.members:
			if peer.hp<=0 or (u.id==other.id and member.index==peer.index):continue
			taken.append(peer.pos);clearances.append(1.65)
			if other.team==u.team and peer.cover_goal!=Vector2.ZERO:taken.append(peer.cover_goal);clearances.append(1.65)
	var nearby:Array=[]
	for point in shelters:
		var reserved:=false
		for i in taken.size():
			if point.distance_to(taken[i])<clearances[i]:reserved=true;break
		if reserved:continue
		var score:float=member.pos.distance_to(point)
		if not threat.is_empty() and point.distance_to(threat.pos)<member.pos.distance_to(threat.pos)-2:score+=4.0
		nearby.append({"pos":point,"score":score})
	nearby.sort_custom(func(a,b):return a.score<b.score)
	if sim.profiling:lap=sim._lap("cover_reservations",lap)
	# Line-of-fire rating (the costly part) for the nearest candidates only.
	# Pinned soldiers want a screen; otherwise a slot with a shot at a known
	# enemy (fire from cover) beats one that only hides.
	var weapon:String=member_weapon(u,member)
	var pinned:bool=maxf(u.suppression,member.suppression)>0.65
	for entry in nearby.slice(0,RATED):
		var rating:=rate(sim,entry.pos,threat,threats,weapon)
		if not rating.ok:continue
		var score:float=entry.score+2.5*rating.flank
		if rating.screened and not threat.is_empty():score-=3.0
		if rating.fire:score-=1.0 if pinned else 4.0
		candidates.append({"pos":entry.pos,"score":score,"screened":rating.screened and not threat.is_empty() and not rating.soft,"fire":rating.fire})
		if candidates.size()>=RATED_VALID:break
	candidates.sort_custom(func(a,b):return a.score<b.score)
	if sim.profiling:lap=sim._lap("cover_ratings",lap)
	for candidate in candidates.slice(0,6):
		var route:=_shelter_route(u,member,sim,candidate.pos)
		if not route.is_empty():
			if sim.profiling:sim._lap("cover_routes",lap)
			return {"pos":candidate.pos,"path":route,"screened":candidate.screened,"fire":candidate.fire}
	if sim.profiling:sim._lap("cover_routes",lap)
	return {}

# How a slot stands against the observed threats: screened from the main one,
# a shot at a known enemy (fire from cover), and how many others see it.
# Vegetation/rubble/trenches protect from any side. A wall slot must screen
# the main threat, or be its corner (a side-step from screened) with a shot at
# it, and must not lie open to a threat it cannot answer.
static func rate(sim,point:Vector2,threat:Dictionary,threats:Array,weapon:String) -> Dictionary:
	var soft:=soft_cover(sim,point)
	var screened:=true
	var fire:=false
	var main_fire:=false
	var flank:=0
	for contact in ([threat] if threats.is_empty() and not threat.is_empty() else threats):
		if not sees(sim,contact,point):continue
		var answer:=answers(sim,weapon,point,contact)
		fire=fire or answer
		if is_same(contact,threat):
			screened=false;main_fire=answer
		else:
			# Open to a threat it cannot answer: never behind a wall, and only
			# reluctantly in vegetation/rubble.
			flank+=1 if answer else 2
			if not soft and not answer:return {"ok":false}
	if not soft and not screened and not (main_fire and corner(sim,point,threat)):return {"ok":false}
	return {"ok":true,"screened":screened,"fire":fire,"flank":flank,"soft":soft}

# A side-step (and half a step back) from the slot is out of the threat's sight:
# the soldier fires around the end of the wall rather than from its open face.
static func corner(sim,point:Vector2,threat:Dictionary) -> bool:
	var away:Vector2=(point-threat.pos).normalized()
	for side in [1.0,-1.0]:
		var duck:Vector2=point+away.orthogonal()*side*1.3+away*0.6
		if sim.terrain.traversable(duck,"land",0.6) and not sim.terrain.line_clear(threat.pos,duck):return true
	return false

# Whether a threat can shoot at `point`: line of fire within its weapon reach
# (synthetic threats reach everywhere).
static func sees(sim,contact:Dictionary,point:Vector2) -> bool:
	if contact.has("kind"):
		var weapon:String=contact.kind if contact.get("members",[]).is_empty() else ("atgm" if contact.kind=="atgm" else "rifle")
		var reach:float=float(sim.definitions[weapon].get("range",0.0))
		if point.distance_squared_to(contact.pos)>reach*reach:return false
	return sim.terrain.line_clear(contact.pos,point)

# Whether a soldier at `point` can hit this contact (synthetic threats cannot be answered).
static func answers(sim,weapon:String,point:Vector2,contact:Dictionary) -> bool:
	if not contact.has("kind") or not sim.effective_weapon(weapon,contact.kind):return false
	var reach:float=float(sim.definitions[weapon].range)
	return point.distance_squared_to(contact.pos)<=reach*reach

static func member_weapon(u:Dictionary,member:Dictionary) -> String:
	if u.kind!="atgm" or float(member.get("hp",0.0))<=0 or int(u.get("missiles",1))<=0:return "rifle"
	# Explicit empty equipment means the specialist capability has been lost.
	# Array position is only a migration fallback for old fieldless fixtures.
	if not u.has("equipment"):return "atgm" if member.index==0 else "rifle"
	var launcher:Dictionary=u.equipment.get("launcher",{})
	var holder:String=launcher.get("holder","")
	return "atgm" if not holder.is_empty() and holder==str(member.get("member_id","")) else "rifle"

# Threat weight: a vehicle or emplacement outweighs a single rifle.
static func power(other:Dictionary) -> float:
	if other.get("members",[]).is_empty():return 3.0
	var living:=0
	for member in other.members:
		if member.hp>0:living+=1
	return float(living)

# Known threats from two clearly different bearings.
static func crossfire(u:Dictionary,threats:Array) -> bool:
	for i in threats.size():
		for j in range(i+1,threats.size()):
			if (threats[i].pos-u.pos).normalized().dot((threats[j].pos-u.pos).normalized())<0.3:return true
	return false

# Squadmates holding still (overwatch, sheltered) never yield, and a soldier may
# not close within a shoulder's width of one, so a route brushing past one
# stalls the seeker until it gives up. Moving squadmates are not obstacles.
static func _squadmate_blocks(u:Dictionary,member:Dictionary,route:Array) -> bool:
	return not _blocker(u,member,route).is_empty()

static func _blocker(u:Dictionary,member:Dictionary,route:Array) -> Dictionary:
	var radius:=STRIDE
	for peer in u.members:
		if peer.hp<=0 or peer.index==member.index or peer.get("cover_phase","")=="SEEKING":continue
		var clearance:float=minf(radius+float(peer.get("body_radius",0.8))-0.05,member.pos.distance_to(peer.pos)-0.05)
		var previous:Vector2=member.pos
		for point in route:
			if Geometry2D.get_closest_point_to_segment(peer.pos,previous,point).distance_to(peer.pos)<clearance:return peer
			previous=point
	return {}

# A squadmate holding the first slot along a wall would otherwise lock the rest
# of the wall face: pass them a body's width to the side, or round them (out,
# along, back in) when the slot hugs the same wall. Straight legs only, no extra
# planning. Empty when no side is clear.
static func _detour(u:Dictionary,member:Dictionary,sim,goal:Vector2) -> Array:
	var peer:=_blocker(u,member,[goal])
	if peer.is_empty():return []
	var gap:float=STRIDE+float(peer.get("body_radius",0.8))+0.4
	var along:Vector2=(goal-member.pos).normalized()
	var best:Array=[]
	var shortest:=INF
	for side in [along.orthogonal()*gap,-along.orthogonal()*gap]:
		for route in [[peer.pos+side,goal],[peer.pos+side-along*gap,peer.pos+side+along*gap,goal]]:
			var length:=route_length(member.pos,route)
			if length>=shortest or route.any(func(point):return point.distance_to(u.pos)>LEASH):continue
			var from:Vector2=member.pos
			var clear:=true
			for point in route:
				if not sim.terrain.segment_clear(from,point,"land",STRIDE):clear=false;break
				from=point
			if clear and not _squadmate_blocks(u,member,route):best=route;shortest=length
	return best

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
		# Centre the run with at least half a unit at either end. Dividing the
		# whole length into 1.3-unit cells produced 1.4-spaced trench goals: a
		# middle soldier could never fit between two stationary occupants.
		var count:=maxi(1,floori((length-1.0)/WORK_SPACING)+1)
		for i in count:
			var t:=(length-(count-1)*WORK_SPACING)/2+i*WORK_SPACING
			var along:=rect.position+(Vector2(t,0) if long_x else Vector2(0,t))
			var middle:=along+across*(rect.size.y/2 if long_x else rect.size.x/2)
			var slot:Vector2=middle if site.kind=="fighting_trench" else middle+across*side*((rect.size.y if long_x else rect.size.x)/2+FACE_GAP)
			if slot.distance_to(u.pos)<=LEASH:slots.append(slot)
	return slots

# Sections do not all settle in at the same instant: the first search waits a
# per-section reaction (id slots one tick apart), which also spreads the
# costly searches of a freshly deployed force over the first ticks.
const REACT_SLOTS:=20
const REACT_STEP:=1.0/30.0

static func occupy_works(u:Dictionary,sim,threat:Dictionary) -> bool:
	if not u.has("occupy_check"):
		u["occupy_check"]=sim.time+REACT_STEP*float(u.id%REACT_SLOTS)
		# Look again at that moment rather than at the next 0.3 s threat scan.
		if u.occupy_check>sim.time:u["cover_next"]=minf(float(u.get("cover_next",0.0)),u.occupy_check)
	if sim.time<u.get("occupy_check",0.0):return u.members.any(func(m):return m.get("occupying",false))
	# The rest of a halt cut short by the per-tick search budget (same bearing).
	var resume:Variant=u.get("halt_resume",null)
	u.erase("halt_resume")
	if resume!=null and sim.time-float(resume[0])<=1.0:
		u["occupy_check"]=float(resume[2])
		return halt_in_cover(u,sim,resume[1],int(resume[3])) or u.members.any(func(m):return m.hp>0 and m.get("occupying",false))
	# Searching is costly: a failed search backs off ~10 s (staggered per unit) so
	# idle defenders across the map do not re-run it every few ticks.
	u["occupy_check"]=sim.time+9.0+float(u.id%7)*0.4
	var enemy_side:Vector2=sim.field_ops.get("enemy_insertion",u.pos+Vector2(0,-1)) if u.team==0 else sim.field_ops.get("insertion",u.pos+Vector2(0,1))
	var aim:Vector2=threat.pos if not threat.is_empty() else enemy_side
	var threat_dir:Vector2=(aim-u.pos).normalized()
	var slots:=work_slots(u,sim,threat_dir)
	if slots.is_empty():return halt_in_cover(u,sim,threat_dir) or u.members.any(func(m):return m.hp>0 and m.get("occupying",false))
	var taken:Array=[]
	# Keep valid occupants and reserve their goals while an uncovered member
	# tries again. Neighbouring sections and generic shelters reserve space too.
	var occupants:Array=sim.range_candidates(u.pos,LEASH*2+4) if sim.ticking else sim.units
	for other in occupants:
		if not sim.alive(other) or other.team!=u.team:continue
		for member in other.members:
			if member.hp>0 and member.get("cover_phase","") in ["SEEKING","SETTLING","SHELTERED"]:taken.append(member.cover_goal)
	var assigned:=false
	for member in u.members:
		if member.hp<=0 or member.get("cover_phase","") in ["SEEKING","SETTLING","SHELTERED"] or sim.time<member.cover_until:continue
		var best:=Vector2(-1,-1);var distance:=INF
		for slot in slots:
			# End slots on adjoining works can be closer than WORK_SPACING even
			# though each work's own slots fit. Reserve distance, not just identity;
			# the tiny tolerance absorbs coordinate rounding on this large map.
			if taken.any(func(goal):return slot.distance_to(goal)<WORK_SPACING-0.001) or not sim.terrain.traversable(slot,"land",STRIDE):continue
			if slot.distance_squared_to(member.pos)<distance:distance=slot.distance_squared_to(member.pos);best=slot
		if best.x<0:continue
		if not _search_admitted(u,member,sim):
			u["occupy_check"]=sim.time
			return u.members.any(func(m):return m.hp>0 and m.get("occupying",false))
		var route:=_shelter_route(u,member,sim,best)
		if route.is_empty():continue
		taken.append(best)
		assigned=true
		member.cover_goal=best;member.cover_path=route;member.cover_phase="SEEKING";member.cover_blocked=0.0
		member["cover_screened"]=false;member["occupying"]=true;member["hold_facing"]=threat_dir
		member.cover_until=sim.time+12.0;member["cover_deadline"]=sim.time+12.0
	if assigned:sim.events.append({"type":"decision","unit":u.id,"phase":"COVER","reason":"Section manning field works","pos":u.pos})
	if not assigned:halt_in_cover(u,sim,threat_dir)
	return u.members.any(func(m):return m.hp>0 and m.get("occupying",false))

# No field works nearby: each soldier takes the nearest real cover within a few
# metres (building corner, yard wall, car, rubble) that screens the enemy side,
# using a far synthetic threat along the expected direction of contact.
static func halt_in_cover(u:Dictionary,sim,threat_dir:Vector2,first:int=0) -> bool:
	var phantom:={"pos":u.pos+threat_dir*35.0,"members":[]}
	var any:=false
	for i in range(first,u.members.size()):
		var member:Dictionary=u.members[i]
		if member.hp<=0 or member.get("cover_phase","") in ["SEEKING","SETTLING","SHELTERED"] or sim.time<member.cover_until:continue
		var result:=find_slot(u,member,sim,phantom,[phantom])
		if result.get("pending",false):
			# Deferral is not a failed search and never starts the long no-cover
			# backoff; resume this exact member on the next authoritative tick.
			u["halt_resume"]=[sim.time,threat_dir,u.occupy_check,i]
			u["occupy_check"]=sim.time
			break
		if result.is_empty() or result.pos.distance_to(member.pos)>8.0:continue
		member.cover_goal=result.pos;member.cover_path=result.path;member.cover_phase="SEEKING";member.cover_blocked=0.0
		member["cover_screened"]=false;member["occupying"]=true;member["hold_facing"]=threat_dir
		member.cover_until=sim.time+12.0;member["cover_deadline"]=sim.time+12.0
		member["cover_from"]=Vector2.ZERO
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
		var weapon:String=threat.kind if threat.members.is_empty() else member_weapon(threat,source)
		if not sim.effective_weapon(weapon,u.kind):continue
		var definition:Dictionary=sim.definitions[weapon]
		var height:float=float(definition.altitude)-float(sim.definitions[u.kind].altitude)
		# Per soldier, matching can_fire's soldier-to-soldier range (no centre-point flicker).
		for body in ([u] if u.members.is_empty() else u.members):
			if body.hp>0 and source.pos.distance_squared_to(body.pos)+height*height<=float(definition.range)*float(definition.range):return true
	return false
