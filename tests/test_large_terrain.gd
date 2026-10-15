extends SceneTree
const Terrain=preload("res://scripts/terrain.gd")
const Roads=preload("res://scripts/road_network.gd")
var checks:=0
var failures:=0
var metrics:Dictionary={}
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)
func config()->Dictionary:
	var data:Dictionary={"size":[1024,768],"nav_cell_size":4,"fog_cell_size":8,"mode":"field_ops","style":"showcase","port":false,"shore_x":1024,"blocks":[],"woods":[[800,430,30,35]],"objectives":[],"rubble":[0,0,0,0],"mud":[650,240,100,100],"water_polygons":[[[0,0],[160,0],[160,768],[0,768]],[[120,200],[420,200],[420,360],[120,360]],[[120,430],[370,430],[370,600],[120,600]]],"prop_blocks":[[500,300,5,8]],"water_blocks":[[50,100,10,10]],"static_cover":[[500,330,10,10]],"map_props":[{"kind":"flat_marking","pos":[520,300]}]}
	for i in 128:data.blocks.append([600+(i%16)*21+(i%3),30+(i/16)*22+(i%5),8+(i%3),9])
	return data
func route_safe(t,start:Vector2,route:Array,domain:String,radius:float,label:String)->void:
	check(not route.is_empty(),label+" exists")
	for point in route:
		check(t.segment_clear(start,point,domain,radius),label+" continuous segment clearance")
		for i in 30:check(t.traversable(start.lerp(point,float(i)/29),domain,radius),label+" footprint")
		start=point
func grid_hash(grid:AStarGrid2D)->String:
	var values:Array=[]
	for x in grid.region.size.x:
		for y in grid.region.size.y:values.append([grid.is_point_solid(Vector2i(x,y)),grid.get_point_weight_scale(Vector2i(x,y))])
	return var_to_str(values).sha256_text()
func _init()->void:
	if DisplayServer.get_name()!="headless":quit(2);return
	var scenario_hash_before:=FileAccess.get_sha256("res://resources/scenarios.json")
	var legacy=Terrain.new(0)
	check(legacy.nav_cell_size==1 and legacy.fog_cell_size==2,"legacy cell defaults")
	check(legacy.center(Vector2i(2,3))==Vector2(5,7) and legacy.cell(Vector2(5,7))==Vector2i(2,3),"legacy fog mapping")
	check(legacy.is_water(Vector2(83,20)) and not legacy.is_water(Vector2(81,20)),"legacy vertical shore")
	check(not legacy.traversable(Vector2(83,20),"sea",3.3),"legacy boat coastline footprint")
	var start_time:=Time.get_ticks_usec()
	var t=Terrain.new(6,config())
	metrics.setup_ms=(Time.get_ticks_usec()-start_time)/1000.0
	check(t.nav_size==Vector2i(256,192) and t.fog_grid_size==Vector2i(128,96),"large map bounded grids")
	check(t.nav_center(Vector2i(2,3))==Vector2(10,14) and t.nav_cell(Vector2(10,14))==Vector2i(2,3),"coarse nav mapping")
	check(t.center(Vector2i(2,3))==Vector2(20,28) and t.cell(Vector2(20,28))==Vector2i(2,3),"coarse fog mapping")
	check(t.water_mask.get_format()==Image.FORMAT_R8 and t.water_mask_data.size()==1024*768,"shared mask dimensions and format")
	check(t.is_water(Vector2(300,250)) and not t.is_water(Vector2(300,400)),"bay and headland classification")
	check(t.traversable(Vector2(150,280),"sea",3.3),"overlapping water polygons have no internal seam")
	check(not t.traversable(Vector2(418,280),"sea",3.3),"boat footprint cannot touch land")
	check(not t.traversable(Vector2(422,280),"land",3.3),"land footprint cannot touch bay")
	check(not t.traversable(Vector2(55,105),"sea",1),"explicit water solid")
	check(not t.traversable(Vector2(502,304),"land",1),"explicit prop solid")
	check(t.traversable(Vector2(520,300),"land",1),"flat map prop does not implicitly block")
	check(t.cover(Vector2(505,335)),"explicit static cover")
	# Fast mask vs exact union, including tiny offsets around every coast.
	var rng:=RandomNumberGenerator.new();rng.seed=78531
	for i in 1500:
		var p:=Vector2(rng.randf_range(0,1023.99),rng.randf_range(0,767.99))
		check(t.is_water(p)==t._water_exact(p),"mask exact-union equivalence")
	for x in [119.999,120.0,159.999,160.0,160.001,369.999,370.001,419.999,420.001]:
		for y in [199.999,200.0,200.001,359.999,360.001,429.999,430.001,599.999,600.001]:
			var p:=Vector2(x,y)
			check(t.is_water(p)==t._water_exact(p),"boundary exact-union equivalence")
	# Index/reference equality uses identical static arrays and all query domains.
	for i in 600:
		var p:=Vector2(rng.randf_range(0,1024),rng.randf_range(0,768));var radius:=rng.randf_range(0.3,5.0)
		t.use_static_index=true
		var indexed:Array=[t.blocked(p),t.cover(p),t.traversable(p,"land",radius),t.traversable(p,"sea",radius)]
		t.use_static_index=false
		check(indexed==[t.blocked(p),t.cover(p),t.traversable(p,"land",radius),t.traversable(p,"sea",radius)],"static spatial equivalence")
	for tree in t.trees:
		for distance in [0.2,1.1,2.4]:
			var point:Vector2=tree+Vector2(distance,0)
			t.use_static_index=true;var indexed:bool=t.traversable(point,"land",0.8)
			t.use_static_index=false;check(indexed==t.traversable(point,"land",0.8),"indexed tree clearance boundary")
	var query_points:Array[Vector2]=[]
	for i in 2500:query_points.append(Vector2(rng.randf_range(590,1000),rng.randf_range(20,510)))
	var totals:Array=[]
	for indexed in [true,false]:
		t.use_static_index=indexed
		var began:=Time.get_ticks_usec();var total:=0
		for point in query_points:
			if t.traversable(point,"land",2.65):total+=1
			if t.cover(point):total+=1
		totals.append(total)
		metrics["indexed_queries_ms" if indexed else "exhaustive_queries_ms"]=(Time.get_ticks_usec()-began)/1000.0
	check(totals[0]==totals[1],"CPU comparison query outputs equal")
	t.use_static_index=true
	t.blocks[0]=Rect2(530,360,8,8);t.rebuild_static_index()
	check(t.blocked(Vector2(534,364)),"same-length layout edits rebuilt explicitly")
	t.blocks.append(Rect2(540,360,8,8))
	check(t.blocked(Vector2(544,364)),"length-changing layout edit auto-detected")
	var roads=Roads.new()
	for i in 130:roads.segments.append({"a":Vector2(i*7,20+i%5),"b":Vector2(i*7+40,70+i%9),"width":3+i%7})
	for i in 700:
		var p:=Vector2(rng.randf_range(-10,1000),rng.randf_range(0,100))
		roads.use_spatial_index=true;var indexed:bool=roads.contains(p)
		roads.use_spatial_index=false;check(indexed==roads.contains(p),"road spatial equivalence")
	roads.segments[0].a=Vector2(500,500);roads.segments[0].b=Vector2(550,500);roads.rebuild_index();roads.use_spatial_index=true
	check(roads.contains(Vector2(525,500)),"road same-length edit rebuild")
	start_time=Time.get_ticks_usec()
	var grid:AStarGrid2D=t.nav_grid("land",1.2,"infantry")
	metrics.first_grid_ms=(Time.get_ticks_usec()-start_time)/1000.0
	check(grid.cell_size==Vector2(4,4) and grid.offset==Vector2(2,2),"AStar world scale")
	var baseline:=grid_hash(grid)
	var avoidance:Array=[{"pos":Vector2(480,680),"radius":8.0}]
	var route:Array=t.path(Vector2(450,680),Vector2(520,680),"land",1.2,avoidance,"infantry")
	route_safe(t,Vector2(450,680),route,"land",1.2,"coarse temporary-avoid route")
	var previous:=Vector2(450,680)
	for point in route:check(t.avoids_bodies(previous,point,avoidance),"temporary avoid survives smoothing");previous=point
	check(grid_hash(grid)==baseline,"temporary exclusions fully restored")
	var rect:=Rect2(475,674,10,12)
	check(t.update_field_geometry([rect],[]),"coarse dirty update reports occlusion")
	check(grid==t.nav_grid("land",1.2,"infantry"),"coarse dirty update preserves grid")
	var oracle=Terrain.new(6,config());oracle.blocks=t.blocks.duplicate();oracle.rebuild_static_index();oracle.dynamic_blocks.append(rect)
	check(grid_hash(grid)==grid_hash(oracle.nav_grid("land",1.2,"infantry")),"coarse dirty grid equals fresh oracle")
	t.update_field_geometry([],[])
	check(grid_hash(grid)==baseline,"coarse removal restores grid")
	var soil:float=t.ground_speed(Vector2(505,680),"infantry")
	t.update_field_geometry([],[Rect2(502,677,2,2)])
	check(t.ground_speed(Vector2(505,680),"infantry")==soil,"field cover never changes soil cost")
	start_time=Time.get_ticks_usec()
	route_safe(t,Vector2(300,280),t.path(Vector2(300,280),Vector2(300,520),"sea",3.3),"sea",3.3,"boat rounds headland")
	route_safe(t,Vector2(350,180),t.path(Vector2(350,180),Vector2(350,385),"land",1.2,[],"infantry"),"land",1.2,"land rounds bay")
	metrics.coastal_paths_ms=(Time.get_ticks_usec()-start_time)/1000.0
	check(not t.segment_clear(Vector2(300,280),Vector2(300,520),"sea",3.3),"boat cannot cut headland")
	check(not t.segment_clear(Vector2(350,180),Vector2(350,385),"land",1.2),"land cannot cut bay")
	t.wetness=0.76;oracle.wetness=0.76;oracle.dynamic_blocks.clear();oracle.navigation.clear();oracle.navigation_weights.clear()
	check(grid_hash(t.nav_grid("land",1.2,"infantry"))==grid_hash(oracle.nav_grid("land",1.2,"infantry")),"coarse weather weights equal fresh oracle")
	var scenarios:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	metrics.authored_map_present=false
	if scenarios.size()>6 and scenarios[6].get("id","")=="black_sea_harbor":
		start_time=Time.get_ticks_usec();var authored=Terrain.new(6)
		metrics.authored_setup_ms=(Time.get_ticks_usec()-start_time)/1000.0;metrics.authored_map_present=true
		check(authored.world_size==Vector2(1024,768) and authored.nav_size==Vector2i(256,192),"authored map dimensions")
		check(not authored.water_polygons.is_empty() and authored.field_mode,"authored map polygon water and field mode")
		check(authored.blocks.size()>=120,"authored map dense layout supplied")
		var definition:Dictionary=scenarios[6]
		var insertion:=Vector2(definition.field_insertion[0],definition.field_insertion[1])
		var sea_insertion:=Vector2(definition.field_sea_insertion[0],definition.field_sea_insertion[1])
		check(authored.traversable(insertion,"land",2.65),"authored land insertion clearance")
		check(authored.traversable(sea_insertion,"sea",3.3),"authored sea insertion clearance")
		for point in definition.objectives:
			var goal:=Vector2(point[0],point[1])+Vector2(0,8)
			var destination:Vector2=authored.reachable_destination(insertion,goal,"land",2.65,"infantry")
			check(destination.x>=0,"authored objective approach exists")
			if destination.x>=0:route_safe(authored,insertion,authored.path(insertion,destination,"land",2.65,[],"infantry"),"land",2.65,"authored objective route")
		route_safe(authored,sea_insertion,authored.path(sea_insertion,Vector2(650,250),"sea",3.3),"sea",3.3,"authored sea bay route")
		for i in 500:
			var point:=Vector2(rng.randf_range(0,1023.99),rng.randf_range(0,767.99))
			check(authored.is_water(point)==authored._water_exact(point),"authored irregular polygon mask equivalence")

	metrics.checks=checks;metrics.failures=failures
	metrics.source_sha256={"terrain":FileAccess.get_sha256("res://scripts/terrain.gd"),"roads":FileAccess.get_sha256("res://scripts/road_network.gd"),"scenario":FileAccess.get_sha256("res://resources/scenarios.json")}
	metrics.scenario_unchanged_during_run=scenario_hash_before==metrics.source_sha256.scenario
	var evidence:=FileAccess.open("res://artifacts/large-terrain-proof.json",FileAccess.WRITE)
	if evidence!=null:evidence.store_string(JSON.stringify(metrics,"  "))
	print("LARGE TERRAIN: ",checks," checks, ",failures," failures; ",JSON.stringify(metrics))
	quit(1 if failures else 0)
