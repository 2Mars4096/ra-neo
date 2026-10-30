class_name TacticalNavigation
extends RefCounted

# Resumable command-position searches. Geometry and candidate ordering match
# Simulation's synchronous helpers; callers retain state while done is false.
# Limits bound admission of path queries, not the CPU time of one Godot A*.

static func _claims(slots:Array)->Array:
	var result:Array=[]
	for slot in slots:result.append([slot.pos,float(slot.radius),str(slot.layer)])
	return result

static func _wrecks(sim)->Array:
	var result:Array=[]
	for wreck in sim.VehicleDamage.wrecks(sim):result.append([wreck.pos,float(wreck.radius)])
	return result

static func _restart(state:Dictionary,signature:Array)->void:
	state.clear()
	state.merge({"signature":signature.duplicate(true),"done":false,"pos":Vector2(-1,-1),"queries":0,"points":0,"last_queries":0,"last_points":0})

static func _finish(state:Dictionary,pos:Vector2)->Dictionary:
	state.done=true
	state.pos=pos
	return state

static func _point(state:Dictionary)->void:
	state.points+=1
	state.last_points+=1

static func _query(state:Dictionary)->void:
	state.queries+=1
	state.last_queries+=1

static func _memo(open:Dictionary,terrain_token:Array,taken_key:String,claims:Array)->void:
	if open.get("_tactical_terrain",[])!=terrain_token:
		for key in open.keys():
			if str(key).begins_with("terrain:"):open.erase(key)
		open["_tactical_terrain"]=terrain_token.duplicate(true)
	var claim_key:="_tactical_"+taken_key
	var previous:Array=open.get(claim_key,[])
	# Ordinary command slots only grow, so existing taken entries stay valid.
	# A removed or moved claim must release its old cached exclusion.
	if previous.any(func(claim):return not claims.has(claim)):open.erase(taken_key)
	open[claim_key]=claims.duplicate(true)

static func formation(sim,origin:Vector2,u:Dictionary,slots:Array[Dictionary],open:Dictionary,held:Array[Dictionary],state:Dictionary,checks:int=4,points:int=64)->Dictionary:
	var d:Dictionary=sim.definitions[u.kind]
	var domain:String=d.domain
	var radius:=float(d.radius)
	var layer:String=sim.collision_layer(u)
	var crowd:float=sim.crowd_radius(u.kind)
	var profile:String=sim.terrain.mobility_profile(u.kind)
	var wreck_signature:=_wrecks(sim) if sim.VehicleDamage.wreck_bound(sim,u) else []
	var all_slots:Array[Dictionary]=slots+held
	var claims:=_claims(all_slots)
	var signature:Array=[u.id,u.pos,origin,u.kind,domain,radius,layer,crowd,profile,sim.terrain.path_probe,sim.terrain.geometry_version,_claims(slots),_claims(held),wreck_signature]
	if state.get("signature",[])!=signature:
		_restart(state,signature)
		state.merge({"origin":origin,"phase":"adjust","adjust_index":0,"ring":0,"angle":0,"stay":INF,"ring_entered":-1})
	state.last_queries=0;state.last_points=0
	if state.done:return state
	if checks<=0 or points<=0:return state
	# clear_goal's near-side wreck displacement has at most 64 geometric
	# candidates. Count them in the same point budget as formation rings.
	if state.phase=="adjust":
		var wreck:Dictionary=sim.VehicleDamage.wreck_at(sim,origin,radius) if not wreck_signature.is_empty() else {}
		if wreck.is_empty():state.phase="rings"
		else:
			var clearance:float=radius+float(wreck.radius)
			var away:Vector2=(origin-wreck.pos)/clearance+(u.pos-wreck.pos).normalized()*0.5
			if away.length_squared()<0.0001:away=(u.pos-wreck.pos).normalized() if u.pos!=wreck.pos else Vector2.RIGHT
			while int(state.adjust_index)<64 and int(state.last_points)<points:
				var at:=int(state.adjust_index)
				var ring:int=at/16
				var k:=at%16
				var turn:int=(k+1)/2*(1 if k%2==1 else -1)
				var reach:float=clearance+sim.VehicleDamage.WRECK_STOP_SLACK+ring*1.5
				var candidate:Vector2=wreck.pos+Vector2.from_angle(away.angle()+turn*TAU/16.0)*reach
				state.adjust_index=at+1;_point(state)
				if sim.VehicleDamage.wreck_at(sim,candidate,radius).is_empty() and sim.terrain.traversable(candidate,"land",radius):
					state.origin=candidate;state.phase="rings";break
			if int(state.adjust_index)>=64:state.phase="rings"
			if state.phase=="adjust":return state
	origin=state.origin
	var nearby:Array=sim.VehicleDamage.wrecks_near(sim,origin,radius,18.0) if not wreck_signature.is_empty() else []
	var wrecked:=not nearby.is_empty()
	var known_key:="terrain:%s:%s:%s:%s"%[domain,radius,wrecked,profile]
	var taken_key:="slots:%s:%s"%[layer,crowd]
	_memo(open,[sim.terrain.geometry_version,wreck_signature],taken_key,claims)
	var known:Dictionary=open.get_or_add(known_key,{})
	var taken:Dictionary=open.get_or_add(taken_key,{})
	var probe:bool=sim.terrain.path_probe and sim.terrain.traversable(u.pos,domain,radius,[],profile)
	var section:bool=not held.is_empty() and not u.members.is_empty() and not sim.slot_clear(origin,layer,crowd,held)
	var ahead:float=(origin-u.pos).angle() if section and u.pos.distance_squared_to(origin)>0.0001 else 0.0
	while int(state.ring)<18 and int(state.last_queries)<checks and int(state.last_points)<points:
		var ring:=int(state.ring)
		if int(state.ring_entered)!=ring:
			state.ring_entered=ring
			if ring==1 and section and sim.slot_clear(u.pos,layer,crowd,all_slots) and sim.terrain.traversable(u.pos,domain,radius,[],profile):state.stay=u.pos.distance_to(origin)-sim.SECTION_STAY
			if float(state.stay)<=ring:return _finish(state,u.pos)
		var at:=int(state.angle)
		var p:Vector2=origin+Vector2.from_angle(ahead+int(sim.SECTION_RING[at])*TAU/16.0 if section else at*TAU/16.0)*ring
		state.angle=at+1
		if int(state.angle)>=(1 if ring==0 else 16):state.ring=ring+1;state.angle=0
		_point(state)
		if taken.has(p):continue
		if not sim.slot_clear(p,layer,crowd,all_slots):taken[p]=true;continue
		var free:Variant=known.get(p)
		if free==null:
			free=sim.terrain.traversable(p,domain,radius,[],profile) and not (wrecked and not sim.VehicleDamage.wreck_at(sim,p,radius,nearby).is_empty())
			known[p]=free
		if not free:continue
		if probe:
			_query(state)
			if sim.terrain.reachable(u.pos,p,domain,radius,profile):return _finish(state,p)
		elif sim.terrain.segment_clear(u.pos,p,domain,radius,[],profile):return _finish(state,p)
		else:
			_query(state)
			if not sim.terrain.path(u.pos,p,domain,radius,[],profile).is_empty():return _finish(state,p)
	if int(state.ring)>=18:return _finish(state,Vector2(-1,-1))
	return state

const ATTACK_REFRESHES:=2

static func _attack_hulks(sim,u:Dictionary,target:Vector2,reach:float)->Array:
	var d:Dictionary=sim.definitions[u.kind]
	var hulks:Array=[]
	if sim.has_meta(sim.VehicleDamage.WRECKS) and sim.VehicleDamage.wreck_bound(sim,u):
		var span:float=u.pos.distance_to(target)+reach+20.0
		var slack:float=0.4 if u.kind in ["tank","aa","boat"] else 0.0
		var can_push:bool=sim.VehicleDamage.pusher(sim,u)
		for wreck in sim.VehicleDamage.wrecks(sim):
			if can_push and not sim.VehicleDamage.solid_wreck(sim,wreck,true):continue
			var gap:float=wreck.pos.distance_to(u.pos)
			if gap<span:hulks.append({"pos":wreck.pos,"radius":minf(float(d.radius)+float(wreck.radius)+slack,gap-0.05)})
	return hulks

static func _attack_token(u:Dictionary,enemy:Dictionary,reach:float,taken:Array,hulks:Array)->Array:
	return [u.pos,enemy.pos,reach,_claims(taken),hulks]

static func _capture_attack(sim,u:Dictionary,enemy:Dictionary,reach:float,taken:Array,hulks:Array,state:Dictionary)->void:
	var low:Vector2i=sim.terrain.cell(enemy.pos-Vector2.ONE*reach)
	var high:Vector2i=sim.terrain.cell(enemy.pos+Vector2.ONE*reach)
	state.merge({"snapshot":_attack_token(u,enemy,reach,taken,hulks).duplicate(true),"source":u.pos,"target":enemy.pos,"reach":reach,"taken":taken.duplicate(true),"hulks":hulks.duplicate(true),"phase":"gather","low":low,"high":high,"cell":low,"candidates":[],"candidate":0,"pass":0,"misses":0},true)

static func _exhaust_attack(sim,u:Dictionary,enemy:Dictionary,reach:float,taken:Array,hulks:Array,state:Dictionary)->Dictionary:
	var stale:bool=state.snapshot!=_attack_token(u,enemy,reach,taken,hulks)
	if stale and int(state.refreshes)<ATTACK_REFRESHES:
		state.refreshes+=1
		_capture_attack(sim,u,enemy,reach,taken,hulks,state)
		state.reason="refreshing"
		return state
	state.reason="stale_search" if stale else "unreachable"
	return _finish(state,Vector2(-1,-1))

static func attack(sim,u:Dictionary,enemy:Dictionary,taken:Array,state:Dictionary,checks:int=4,points:int=64)->Dictionary:
	# Do not consult a hidden contact's current position, even for invalidation.
	# The stored target snapshot was acquired while this knowledge check passed.
	if not sim.alive(u) or not sim.alive(enemy) or not sim.contact_known(u,enemy):
		_restart(state,[])
		state.reason="contact_lost" if sim.alive(u) and sim.alive(enemy) else "unavailable"
		return _finish(state,Vector2(-1,-1))
	var d:Dictionary=sim.definitions[u.kind]
	var profile:String=sim.terrain.mobility_profile(u.kind)
	var weapon:String=sim.attack_weapon(u,enemy.kind)
	var reach:float=sim.horizontal_reach(weapon,enemy,sim.unit_altitude(u))*0.9
	var hulks:=_attack_hulks(sim,u,enemy.pos,reach)
	var ground:bool=sim.definitions[enemy.kind].domain!="air"
	# Motion and moving friendly claims change continuously. Retain one coherent
	# observed snapshot while scanning; hard authority/geometry changes restart.
	var signature:Array=[u.id,enemy.id,u.get("order_version",0),u.get("assignment",{}).get("id",0),u.kind,enemy.kind,d.domain,float(d.radius),profile,weapon,sim.weapon_range(weapon,sim.definitions[enemy.kind]),ground,sim.terrain.geometry_version]
	var token:=_attack_token(u,enemy,reach,taken,hulks)
	if state.get("signature",[])!=signature or (state.get("done",false) and state.get("snapshot",[])!=token):
		_restart(state,signature)
		state.refreshes=0
		state.reason="planning"
		_capture_attack(sim,u,enemy,reach,taken,hulks,state)
	state.last_queries=0;state.last_points=0
	if state.done or checks<=0 or points<=0:return state
	while state.phase=="gather" and int(state.last_points)<points:
		var cell:Vector2i=state.cell
		if cell.x>state.high.x:
			state.candidates.sort_custom(func(a,b):return a.distance<b.distance)
			state.phase="select"
			break
		var p:Vector2=sim.terrain.center(cell)
		state.cell=Vector2i(cell.x+1,state.low.y) if cell.y>=state.high.y else Vector2i(cell.x,cell.y+1)
		_point(state)
		if not sim.terrain.traversable(p,d.domain,float(d.radius),[],profile) or p.distance_to(state.target)>float(state.reach):continue
		if ground and not sim.terrain.line_clear(p,state.target):continue
		if not state.hulks.is_empty() and not sim.terrain.avoids_bodies(p,p,state.hulks):continue
		state.candidates.append({"pos":p,"distance":p.distance_squared_to(state.source)})
	if state.phase!="select":return state
	var layer:String=sim.collision_layer(u)
	var crowd:float=sim.crowd_radius(u.kind)
	var passes:=1 if state.taken.is_empty() else 2
	var changed_claims:bool=_claims(taken)!=_claims(state.taken)
	while int(state.pass)<passes and int(state.last_queries)<checks and int(state.last_points)<points:
		if int(state.candidate)>=state.candidates.size():
			state.pass+=1;state.candidate=0
			continue
		var candidate:Dictionary=state.candidates[int(state.candidate)]
		state.candidate+=1;_point(state)
		var spread:bool=not state.taken.is_empty() and int(state.pass)==0
		# Preserve the existing occupied-position fallback for an unchanged
		# request. Newly moved/added claims never acquire that exception.
		if (spread or changed_claims) and taken.any(func(slot):return slot.layer==layer and candidate.pos.distance_to(slot.pos)<crowd+float(slot.radius)+0.7):continue
		# Revalidate against the current observation and physical origin before
		# publishing. A stale snapshot cannot grant range, sight or a clear route.
		if candidate.pos.distance_to(enemy.pos)>reach or not sim.terrain.traversable(candidate.pos,d.domain,float(d.radius),[],profile):continue
		if ground and not sim.terrain.line_clear(candidate.pos,enemy.pos):continue
		if not hulks.is_empty() and not sim.terrain.avoids_bodies(candidate.pos,candidate.pos,hulks):continue
		if ground:
			var side:Vector2=(enemy.pos-candidate.pos).normalized().orthogonal()*0.75
			if not sim.terrain.line_clear(candidate.pos+side,enemy.pos) or not sim.terrain.line_clear(candidate.pos-side,enemy.pos):continue
		_query(state)
		if not sim.terrain.path(u.pos,candidate.pos,d.domain,float(d.radius),hulks,profile).is_empty():
			state.snapshot=token.duplicate(true)
			state.reason="ready"
			return _finish(state,candidate.pos)
		if not hulks.is_empty():
			state.misses+=1
			if int(state.misses)>=sim.WRECK_SPOT_MISSES:return _exhaust_attack(sim,u,enemy,reach,taken,hulks,state)
	if int(state.pass)>=passes:return _exhaust_attack(sim,u,enemy,reach,taken,hulks,state)
	return state
