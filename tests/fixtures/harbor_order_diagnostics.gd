extends RefCounted
# Read-only rejection evidence. Detailed route queries run after a diagnostic
# trace has stopped, because even pure navigation queries populate caches.

static func plain(value:Variant)->Variant:
	if value is float and not is_finite(value):return str(value)
	if value is Vector2 or value is Vector2i:return [plain(value.x),plain(value.y)]
	if value is Rect2:return {"position":plain(value.position),"size":plain(value.size)}
	if value is Dictionary:
		var result:Dictionary={}
		for key in value:result[str(key)]=plain(value[key])
		return result
	if value is Array or value is PackedVector2Array:
		var result:Array=[]
		for item in value:result.append(plain(item))
		return result
	return value

static func capture(sim,ids:Array,goal:Vector2,mode:String,accepted:int)->Dictionary:
	var rejected:Array=[]
	var units:Array=[]
	for id in ids:
		var unit:Dictionary=sim.get_unit(int(id))
		if int(unit.get("command_group",-1))!=sim.command_serial:rejected.append(id)
		units.append(plain(unit))
	return {"seconds":sim.time,"ids":ids.duplicate(),"goal":plain(goal),"mode":mode,
		"accepted":accepted,"rejected_ids":rejected,"command_serial":sim.command_serial,
		"feedback":sim.order_feedback,"adjusted":sim.order_adjusted,"resolving":sim.order_resolving,
		"route_budget_after_command":sim.route_budget,"units":units}

static func anchor(sim,id:int)->Dictionary:
	var unit:Dictionary=sim.get_unit(id)
	if not sim.alive(unit):return {}
	return {"seconds":sim.time,"unit":plain(unit),"clear":sim.terrain.traversable(unit.pos,
		sim.definitions[unit.kind].domain,float(sim.definitions[unit.kind].radius))}

static func navigation(sim,evidence:Dictionary)->Array:
	var output:Array=[]
	var goal:=Vector2(evidence.goal[0],evidence.goal[1])
	var ids:Array=evidence.ids
	var spacing:Dictionary={}
	for id in ids:
		var unit:Dictionary=sim.get_unit(int(id))
		var definition:Dictionary=sim.definitions[unit.kind]
		spacing[definition.domain]=maxf(spacing.get(definition.domain,0.0),sim.crowd_radius(unit.kind)*2.0+0.7)
	var indices:Dictionary={}
	var slots:Array[Dictionary]=[]
	for id in ids:
		var unit:Dictionary=sim.get_unit(int(id))
		var definition:Dictionary=sim.definitions[unit.kind]
		var domain:String=definition.domain
		var radius:float=definition.radius
		var index:int=indices.get(domain,0)
		indices[domain]=index+1
		if not evidence.rejected_ids.has(id):
			if not unit.orders.is_empty():slots.append({"pos":unit.orders[0].pos,"radius":sim.crowd_radius(unit.kind),"layer":sim.collision_layer(unit)})
			continue
		var target:=goal
		if ids.size()>1:target+=Vector2((index%3-1)*spacing[domain],(index/3)*spacing[domain])
		if not sim.terrain.traversable(target,domain,radius):target=goal
		var held:Array[Dictionary]=sim.held_spots(unit,goal,ids)
		var profile:String=sim.terrain.mobility_profile(unit.kind)
		var previous_probe:bool=sim.terrain.path_probe
		sim.terrain.path_probe=false
		var chosen:Vector2=sim.formation_slot(target,unit,slots,{},held)
		var route:Array=sim.order_route(unit,chosen,ids) if chosen.x>=0 else []
		sim.terrain.path_probe=true
		var probe_chosen:Vector2=sim.formation_slot(target,unit,slots,{},held)
		sim.terrain.path_probe=previous_probe
		var members:Array=[]
		for member in unit.members:
			members.append({"index":member.index,"hp":member.hp,"wound":member.get("wound",""),
				"pos":plain(member.pos),"body_clear":sim.terrain.traversable(member.pos,"land",float(member.get("body_radius",0.8)))})
		var static_blocks:Array=[]
		for rect in sim.terrain._static_candidates("solid",unit.pos,16.0):
			static_blocks.append({"rect":plain(rect),"anchor_gap":unit.pos.distance_to(unit.pos.clamp(rect.position,rect.end)),
				"overlaps_envelope":sim.terrain.circle_rect(unit.pos,radius+sim.terrain.OBSTACLE_MARGIN,rect)})
		var dynamic_blocks:Array=[]
		for rect in sim.terrain.dynamic_blocks:
			if rect.grow(16.0).has_point(unit.pos):dynamic_blocks.append(plain(rect))
		var poles:Array=[]
		for point in sim.terrain.poles:
			if point.distance_to(unit.pos)<16.0:poles.append(plain(point))
		var trees:Array=[]
		for point in sim.terrain._static_candidates("tree",unit.pos,16.0):trees.append(plain(point))
		var grid=sim.terrain._nav_grid(domain,radius,profile,false)
		var grid_start:Vector2i=sim.terrain.nearest_cell(unit.pos,grid,domain,radius)
		var grid_goal:Vector2i=sim.terrain.nearest_cell(goal,grid,domain,radius)
		var connected:=false
		if grid_start.x>=0 and grid_goal.x>=0:connected=not grid.get_id_path(grid_start,grid_goal).is_empty()
		var nearby:Array=[]
		for other in sim.units:
			if other.id!=id and other.pos.distance_to(unit.pos)<24.0:
				nearby.append({"id":other.id,"kind":other.kind,"team":other.team,"hp":other.hp,
					"pos":plain(other.pos),"radius":sim.definitions[other.kind].radius,
					"orders":plain(other.orders),"members":plain(other.members)})
		output.append({"id":id,"kind":unit.kind,"hp":unit.hp,"pos":plain(unit.pos),"radius":radius,
			"anchor_clear":sim.terrain.traversable(unit.pos,domain,radius),
			"anchor_body_clear":sim.terrain.traversable(unit.pos,domain,0.8),
			"anchor_is_water":sim.terrain.is_water(unit.pos),"anchor_inside_solid":sim.terrain.blocked(unit.pos),
			"comms_blocked":sim.comms_blocked(unit),"combat_ineffective":unit.get("combat_ineffective",false),
			"members":members,"initial_formation_target":plain(target),"formation_slot":plain(chosen),
			"formation_slot_probe":plain(probe_chosen),"order_route":plain(route),
			"direct_goal_route":plain(sim.terrain.path(unit.pos,goal,domain,radius,[],profile)),
			"nearest_grid_start":plain(grid_start),"nearest_grid_goal":plain(grid_goal),"grid_connected":connected,
			"held_spots":plain(held),"previous_group_slots":plain(slots),
			"static_blocks":static_blocks,"dynamic_blocks":dynamic_blocks,"nearby_poles":poles,
			"nearby_trees":trees,"nearby_units":nearby})
	return output
