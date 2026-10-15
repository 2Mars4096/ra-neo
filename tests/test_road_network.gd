extends SceneTree
var failures:Array=[]
var checks:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message)
func _init()->void:
	for scenario in [3,4]:
		var terrain=load("res://scripts/terrain.gd").new(scenario)
		var roads=terrain.roads
		var visited:Dictionary={roads.nodes.keys()[0]:true}
		for sweep in roads.nodes.size():
			for edge in roads.segments:
				if visited.has(edge.from):visited[edge.to]=true
				if visited.has(edge.to):visited[edge.from]=true
		check(visited.size()==roads.nodes.size(),"Disconnected graph %s"%scenario)
		for edge in roads.segments:
			var direction:Vector2=(edge.b-edge.a).normalized()
			var normal:=Vector2(-direction.y,direction.x)
			var steps:=ceili(edge.a.distance_to(edge.b)/0.5)
			for i in steps+1:
				var center:Vector2=edge.a.lerp(edge.b,float(i)/steps)
				check(terrain.on_road(center),"Surface/render mismatch")
				for offset in [-0.5,0.0,0.5]:
					var p:Vector2=center+normal*edge.width*offset
					check(not terrain.is_water(p) and not terrain.blocked(p),"Road intersects solid/water %s %s %s"%[scenario,edge.purpose,p])
					for tree in terrain.trees:check(p.distance_to(tree)>0.45,"Road intersects tree %s %s"%[scenario,p])
	var weather_terrain=load("res://scripts/terrain.gd").new(3)
	var dry_grid=weather_terrain.nav_grid("land",0.4)
	var cell:=Vector2i(10,31)
	var dry_cost:float=dry_grid.get_point_weight_scale(cell)
	weather_terrain.wetness=1.0
	var wet_grid=weather_terrain.nav_grid("land",0.4)
	check(dry_grid==wet_grid,"Weather rebuilt static navigation geometry")
	check(wet_grid.get_point_weight_scale(cell)>dry_cost,"Weather failed to update travel weights")
	print("ROAD NETWORK: ",checks," checks, ",failures.size()," failures")
	for f in failures:print(f)
	quit(0 if failures.is_empty() else 1)
