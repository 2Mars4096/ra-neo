extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Ops=preload("res://scripts/field_ops.gd")
class CountTerrain extends BattleTerrain:
	var grid_misses:=0
	func nav_grid(domain:String,radius:float,profile:String="default")->AStarGrid2D:
		var key:="%s:%.2f:%s" % [domain,radius,profile if domain=="land" else "default"]
		if not navigation.has(key):grid_misses+=1
		return super.nav_grid(domain,radius,profile)
func stats(values:Array)->Dictionary:
	var sorted:=values.duplicate();sorted.sort()
	var total:=0.0
	for value in values:total+=value
	return {"samples":values.size(),"total_ms":total,"mean_ms":total/values.size(),"p95_ms":sorted[mini(sorted.size()-1,int(sorted.size()*0.95))],"max_ms":sorted.back()}
func warm(t)->void:
	for profile in ["infantry","tracked","wheeled"]:
		for radius in [0.8,2.65]:t.nav_grid("land",radius,profile)
func _init()->void:
	if DisplayServer.get_name()!="headless":quit(2);return
	var terrain=CountTerrain.new(5)
	warm(terrain)
	var first:Array=[];var remainder:Array=[];var weights:Array=[];var routes:Array=[]
	for wet in [0.26,0.51,0.76,1.0,0.0,0.26,0.51,0.76]:
		terrain.wetness=wet
		var start:=Time.get_ticks_usec()
		terrain.nav_grid("land",2.65,"infantry")
		first.append((Time.get_ticks_usec()-start)/1000.0)
		start=Time.get_ticks_usec();warm(terrain)
		remainder.append((Time.get_ticks_usec()-start)/1000.0)
		for key in terrain.navigation:
			var grid:AStarGrid2D=terrain.navigation[key]
			for x in terrain.nav_size.x:
				for y in terrain.nav_size.y:weights.append(grid.get_point_weight_scale(Vector2i(x,y)))
		for profile in ["infantry","tracked","wheeled"]:
			routes.append(terrain.path(Vector2(14,97),Vector2(40,80),"land",2.65,[],profile))
	var sim=Sim.new(false,5)
	sim.terrain=CountTerrain.new(5)
	sim.spawn("engineer",0,Vector2(14,97));sim.update_visibility()
	sim.terrain.nav_grid("land",sim.definitions.engineer.radius,"infantry")
	var initial_misses:int=sim.terrain.grid_misses
	var costs:Array=[];var accepted:=0
	var before:=var_to_str([sim.units,sim.credits,sim.terrain.dynamic_blocks]).sha256_text()
	for kind in Ops.KINDS:
		for i in 6:
			var start:=Time.get_ticks_usec()
			var plan:Dictionary=Ops.proposal(sim,kind,Vector2(25,96.0+i*0.1),sim.units[0].id)
			costs.append((Time.get_ticks_usec()-start)/1000.0)
			if plan.reason=="":accepted+=1
	var report:={"engine":Engine.get_version_info().string,"weather_first_query":stats(first),"weather_remaining_queries":stats(remainder),"weather_weights_sha256":var_to_str(weights).sha256_text(),"weather_routes_sha256":var_to_str(routes).sha256_text(),"weather_nonempty_routes":routes.filter(func(r):return not r.is_empty()).size(),"weather_grid_creations":terrain.grid_misses,"placement":stats(costs),"placement_accepted":accepted,"placement_grid_creations":sim.terrain.grid_misses-initial_misses,"placement_state_unchanged":before==var_to_str([sim.units,sim.credits,sim.terrain.dynamic_blocks]).sha256_text()}
	var path:="res://artifacts/performance-repair-cost.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):path=arg.trim_prefix("--output=")
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(report,"  "))
	print("PERFORMANCE REPAIR COST: ",JSON.stringify(report))
	quit()
