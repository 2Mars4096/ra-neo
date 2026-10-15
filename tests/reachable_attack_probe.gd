extends "res://scripts/simulation.gd"
# Diagnostic only: prove the attack-position failure without editing the
# integration owner's simulation.gd or altering the mission policy/assertion.
func attack_position(u:Dictionary,enemy:Dictionary)->Vector2:
	var d:Dictionary=definitions[u.kind]
	var candidates:Array=[]
	for x in terrain.fog_grid_size.x:
		for y in terrain.fog_grid_size.y:
			var p:Vector2=terrain.center(Vector2i(x,y))
			if not terrain.traversable(p,d.domain,float(d.radius)) or p.distance_to(enemy.pos)>float(d.range)*0.9:continue
			if definitions[enemy.kind].domain!="air" and not terrain.line_clear(p,enemy.pos):continue
			candidates.append({"pos":p,"distance":p.distance_squared_to(u.pos)})
	candidates.sort_custom(func(a,b):return a.distance<b.distance)
	for candidate in candidates:
		if not terrain.path(u.pos,candidate.pos,d.domain,float(d.radius),[],terrain.mobility_profile(u.kind)).is_empty():return candidate.pos
	return Vector2(-1,-1)
