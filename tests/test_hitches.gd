extends SceneTree
# Simulation hitch fixes: weather re-weighting spread over ticks, exact cheaper
# path helpers, resumable route jobs and the per-tick route budget/queue.
const Terrain=preload("res://scripts/terrain.gd")
const Sim=preload("res://scripts/simulation.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)
func harbor_index()->int:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		if configs[i].id=="black_sea_harbor":return i
	return -1
func grid_state(grid:AStarGrid2D)->String:
	var cells:Array=[]
	for x in grid.region.size.x:
		for y in grid.region.size.y:cells.append([grid.is_point_solid(Vector2i(x,y)),grid.get_point_weight_scale(Vector2i(x,y))])
	return var_to_str(cells).sha256_text()
# The pre-optimisation nearest_cell: every candidate tested in scan order.
func reference_nearest(t,p:Vector2,base:Vector2i,grid:AStarGrid2D,radius:float,avoid:Array)->Vector2i:
	var best:=Vector2i(-1,-1)
	var distance:=INF
	var anchors:Dictionary=grid.get_meta("anchors",{})
	for x in range(base.x-3,base.x+4):
		for y in range(base.y-3,base.y+4):
			var id:=Vector2i(x,y)
			if not grid.is_in_boundsv(id) or grid.is_point_solid(id):continue
			var center:Vector2=t._anchor(anchors,id)
			var dist:=p.distance_squared_to(center)
			if dist<distance and t.segment_clear(p,center,"land",radius) and t.avoids_bodies(p,center,avoid):
				distance=dist;best=id
	return best

func _init()->void:
	weights()
	paths()
	routes()
	print("HITCHES: ",checks," checks, ",failures," failures")
	quit(1 if failures>0 else 0)

func weights()->void:
	var t=Terrain.new(5)
	t.update_field_zones([{"rect":Rect2(10,90,7,2),"speed":{"infantry":0.15,"tracked":0.6},"cover":["infantry"]}])
	for wet in [0.0,0.3,0.55,0.8,1.0]:
		t.wetness=wet
		t._sync_weight_band("land")
		for profile in ["infantry","tracked","wheeled","default"]:
			var layer:PackedFloat32Array=t._navigation_weight_layer(profile)
			var exact:=true
			for x in t.nav_size.x:
				for y in t.nav_size.y:
					var point:Vector2=t.nav_center(Vector2i(x,y))
					if not is_equal_approx(layer[x*t.nav_size.y+y],1.0/t.ground_speed(point,profile)):exact=false
			check(exact,"cached surface layer equals 1/ground_speed everywhere: %s wet %.2f" % [profile,wet])
	# Incremental refresh (simulation hook) reaches exactly the eager weights.
	var lazy=Terrain.new(5)
	var eager=Terrain.new(5)
	var keys:=[[1.2,"infantry"],[2.0,"tracked"],[1.6,"wheeled"]]
	for terrain in [lazy,eager]:
		for key in keys:terrain.nav_grid("land",key[0],key[1])
	var first:AStarGrid2D=lazy.nav_grid("land",1.2,"infantry")
	var second:AStarGrid2D=lazy.nav_grid("land",2.0,"tracked")
	var untouched:=grid_state(second)
	lazy.wetness=0.6;eager.wetness=0.6
	var rows:int=lazy.nav_size.y
	lazy.advance_navigation_weights(rows*3)
	check(first.get_meta("weight_column",0)==3 and first.get_meta("weight_epoch")!=lazy.navigation_weight_epoch,"one tick refreshes only its cell budget (3 columns)")
	check(grid_state(second)==untouched,"later grids wait for their turn")
	var sample:=Vector2i(lazy.nav_size.x-2,5)
	var partial:=first.get_point_weight_scale(sample)
	var grid:AStarGrid2D=lazy.nav_grid("land",1.2,"infantry")
	check(grid==first and grid.get_point_weight_scale(sample)!=partial and is_equal_approx(grid.get_point_weight_scale(sample),1.0/lazy.ground_speed(lazy.nav_center(sample),"infantry")),"nav_grid() completes a partially refreshed grid before returning it")
	var ticks:=0
	while ticks<200 and lazy.navigation.keys().any(func(k):return lazy.navigation[k].get_meta("weight_epoch")!=lazy.navigation_weight_epoch):
		lazy.advance_navigation_weights(rows*3);ticks+=1
	check(ticks<200,"incremental refresh converges")
	for key in keys:
		var cached:AStarGrid2D=lazy.navigation["land:%.2f:%s" % key]
		check(grid_state(cached)==grid_state(eager.nav_grid("land",key[0],key[1])),"incremental refresh equals eager weights/solids: %s" % [key])
	# A path mid-refresh (simulation mode) still returns a valid route.
	lazy.wetness=0.95
	lazy.advance_navigation_weights(rows)
	var route:Array=lazy.path(Vector2(14,97),Vector2(40,80),"land",1.2,[],"infantry")
	var previous:=Vector2(14,97)
	var valid:=not route.is_empty()
	for point in route:
		valid=valid and lazy.segment_clear(previous,point,"land",1.2);previous=point
	check(valid,"route planned on a grid mid-refresh clears geometry")
	# Soil/cover edits invalidate the cached surface classes.
	var soil=Terrain.new(5)
	var probe:=Vector2(30.5,30.5)
	soil.nav_grid("land",1.2,"tracked")
	soil.woods.append(Rect2(28,28,6,6))
	soil.rebuild_static_index()
	var rebuilt:AStarGrid2D=soil.nav_grid("land",1.2,"tracked")
	check(is_equal_approx(rebuilt.get_point_weight_scale(soil.nav_cell(probe)),1.0/soil.ground_speed(soil.nav_center(soil.nav_cell(probe)),"tracked")),"static index rebuild refreshes cached soil classes")

func paths()->void:
	var sim=Sim.new(false,harbor_index())
	var t=sim.terrain
	var rng:=RandomNumberGenerator.new();rng.seed=7
	var infantry:AStarGrid2D=t.nav_grid("land",2.65,"infantry")
	var tracked:AStarGrid2D=t.nav_grid("land",2.45,"tracked")
	var same:=true
	var avoid:Array=[{"pos":Vector2(300,640),"radius":1.6},{"pos":Vector2(307,647),"radius":1.6},{"pos":Vector2(307,633),"radius":1.6},{"pos":Vector2(296,666),"radius":3.2}]
	for i in 300:
		var p:=Vector2(rng.randf_range(20,1000),rng.randf_range(20,740))
		var grid:AStarGrid2D=infantry if i%2==0 else tracked
		var radius:=2.65 if i%2==0 else 2.45
		t.crush_pass=i%2==1
		if t.nearest_cell(p,grid,"land",radius)!=reference_nearest(t,p,t.nav_cell(p),grid,radius,[]):same=false
		var q:=Vector2(rng.randf_range(290,340),rng.randf_range(630,650))
		if t._nearest_open(q,t.nav_cell(q),grid,grid.get_meta("anchors",{}),"land",radius,avoid)!=reference_nearest(t,q,t.nav_cell(q),grid,radius,avoid):same=false
		t.crush_pass=false
	check(same,"distance-ordered nearest cell equals exhaustive scan (300 points, with and without bodies)")
	var cases:=[[Vector2(942.5,124.33),Vector2(274.4,680),2.65,"infantry",[]],[Vector2(937.5,115.67),Vector2(285.6,680),2.45,"tracked",[]],[Vector2(945,120),Vector2(584.59,509.38),2.65,"infantry",[]],[Vector2(285,640),Vector2(318,640),2.65,"infantry",avoid],[Vector2(285,655),Vector2(318,652),2.45,"tracked",avoid]]
	for c in cases:
		var full:Array=t.path(c[0],c[1],"land",c[2],c[4],c[3])
		check(not full.is_empty(),"fixture route exists: %s" % [c])
		for work in [1,7,40]:
			var job:Dictionary=t.path_job(c[0],c[1],"land",c[2],c[4],c[3])
			var steps:=0
			while not t.path_job_step(job,work) and steps<10000:steps+=1
			check(job.result==full,"route job sliced by %d checks equals path(): %s %s" % [work,c[3],c[0]])
		check(t.reachable(c[0],c[1],"land",c[2],c[3]),"reachable() agrees with a found route")
	check(t.is_water(Vector2(640,220)) and not t.reachable(Vector2(300,640),Vector2(640,220),"land",2.65,"infantry"),"reachable() rejects water")
	# Batch connectivity links answer exactly like single searches.
	var expected:Array=[]
	var starts:Array=[]
	for i in 10:starts.append(Vector2(260+i*6,600+(i%3)*8))
	var goal:=Vector2(942.5,124.33)
	starts.append(Vector2(640,220)) # water: never reachable
	for s in starts:expected.append(t.reachable(s,goal,"land",2.65,"infantry"))
	t.begin_path_memo()
	var batched:Array=[]
	for s in starts:batched.append(t.reachable(s,goal,"land",2.65,"infantry"))
	var memo:Array=t.path(starts[0],goal,"land",2.65,[],"infantry")
	check(t.path(starts[0],goal,"land",2.65,[],"infantry")==memo,"batch memo returns the same route")
	t.end_path_memo()
	check(batched==expected and expected.count(true)>=5 and not expected.back(),"batched reachability equals per-query searches %s %s" % [expected,batched])
	check(memo==t.path(starts[0],goal,"land",2.65,[],"infantry"),"memoised route equals a fresh plan")

func order_group(sim)->Array:
	var group:Array=[]
	for i in 12:group.append(sim.spawn("rifle",0,Vector2(250+(i%4)*7,600+(i/4)*7)).id)
	for i in 4:group.append(sim.spawn("tank",0,Vector2(250+i*9,630)).id)
	return group

func routes()->void:
	var runs:Array=[]
	for run in 2:
		var sim=Sim.new(false,harbor_index())
		for kind in ["rifle","tank"]:
			var definition:Dictionary=sim.definitions[kind]
			sim.terrain.nav_grid(definition.domain,float(definition.radius),sim.terrain.mobility_profile(kind))
		var group:Array=order_group(sim)
		var started:=Time.get_ticks_usec()
		var accepted:int=sim.issue(group,Vector2(860,200),"move")
		var issue_ms:=(Time.get_ticks_usec()-started)/1000.0
		check(accepted==group.size(),"cross-map group order accepts every unit")
		var queued:int=sim.route_queue.size()
		check(queued>0,"over-budget routes queue instead of planning in the command")
		check(group.all(func(id):var u=sim.get_unit(id);return not u.orders.is_empty() and (not u.path.is_empty() or sim.route_waiting(u))),"queued units hold their order while waiting")
		var routed_at:=-1
		var worst:=0.0
		var budget_low:=INF
		for i in 150:
			started=Time.get_ticks_usec()
			sim.tick(1.0/30)
			worst=maxf(worst,(Time.get_ticks_usec()-started)/1000.0)
			budget_low=minf(budget_low,sim.route_budget)
			if routed_at<0 and sim.route_queue.is_empty():routed_at=i+1
		check(routed_at>0 and routed_at<=60,"queue drains within two seconds (%d ticks)" % routed_at)
		# Queue work is capped per tick: one route's search and a string-pull step past the cap at most.
		check(budget_low>=Sim.ROUTE_BUDGET-float(Sim.ROUTE_QUEUE_WORK+2*Sim.ROUTE_SEARCH_WORK+17)/Sim.ROUTE_WORK_PER_UNIT-0.01,"queued planning stays within its per-tick work cap")
		var progressed:=group.filter(func(id):var u=sim.get_unit(id);return u.pos.distance_to(u.home)>8.0 and not u.orders.is_empty() and not u.path.is_empty()).size()
		check(progressed==group.size(),"every queued unit departs on its planned route (%d/%d)" % [progressed,group.size()])
		print("HITCH group order: issue=%.1fms queued=%d drained_after=%d ticks worst_tick=%.1fms" % [issue_ms,queued,routed_at,worst])
		check(issue_ms<250.0,"16-unit cross-map command stays far below the old ~900 ms stall")
		runs.append(var_to_str(group.map(func(id):var u=sim.get_unit(id);return [u.pos,u.path,u.orders])))
	check(runs[0]==runs[1],"budgeted planning is deterministic across identical runs")
