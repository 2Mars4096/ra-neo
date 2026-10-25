extends SceneTree
const Terrain=preload("res://scripts/terrain.gd")
class CountTerrain extends BattleTerrain:
	var traversable_calls:=0
	func traversable(p:Vector2,domain:String,radius:float=-1,pressed_wrecks:Array=[],profile:String="")->bool:
		traversable_calls+=1
		return super.traversable(p,domain,radius,pressed_wrecks,profile)
var specs:Array=[["land",0.8,"infantry"],["land",2.654,"infantry"],["land",2.65,"tracked"],["land",1.23456,"wheeled"],["sea",3.3,"default"],["air",1.55,"default"]]
var failures:=0
var checks:=0
var proof:Array=[]
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",message)
func fixture():
	var t=CountTerrain.new(5)
	# Explicit independent obstacles overlap the editable field region.
	t.blocks.append(Rect2(22,92,2,2))
	t.roadside_blocks.append(Rect2(31,90,2,2))
	t.trees.append(Vector2(30,96))
	t.wetness=0.51
	return t
func warm(t)->Array:
	var grids:Array=[]
	for spec in specs:grids.append(t.nav_grid(spec[0],spec[1],spec[2]))
	return grids
func compare(a,b,label:String)->void:
	for i in specs.size():
		var spec:Array=specs[i]
		var left:AStarGrid2D=a.nav_grid(spec[0],spec[1],spec[2])
		var right:AStarGrid2D=b.nav_grid(spec[0],spec[1],spec[2])
		var equal_solids:=true;var equal_weights:=true
		for x in a.nav_size.x:
			for y in a.nav_size.y:
				var id:=Vector2i(x,y)
				if left.is_point_solid(id)!=right.is_point_solid(id):equal_solids=false
				if left.get_point_weight_scale(id)!=right.get_point_weight_scale(id):equal_weights=false
		check(equal_solids,label+" full-grid solids "+str(spec))
		check(equal_weights,label+" full-grid weights "+str(spec))
		if spec[0]!="land":continue
		var start:=Vector2(14,a.world_size.y-11);var goal:=Vector2(40,a.world_size.y-11)
		check(a.path(start,goal,"land",spec[1],[],spec[2])==b.path(start,goal,"land",spec[1],[],spec[2]),label+" weighted route "+str(spec))
func _init()->void:
	if DisplayServer.get_name()!="headless":quit(2);return
	var cached=fixture()
	var identities:=warm(cached)
	var a:=Rect2(25.123,90.2,5.6,6)
	var b:=Rect2(28.4,92.5,2.8,2)
	var edge:=Rect2(-1,105,5.6,6)
	var stages:Array=[
		["add",[a],[],true],
		["complete",[a],[a],false],
		["overlap_add",[a,b],[a],true],
		["overlap_complete",[a,b],[a,b],false],
		["reorder_duplicate",[b,a,a],[b,a,a],false],
		["overlap_remove",[b],[b],true],
		["cover_remove",[b],[],false],
		["map_edge",[b,edge],[],true],
		["remove_all",[],[],true],
		["unchanged",[],[],false]]
	for stage in stages:
		var label:String=stage[0]
		cached.traversable_calls=0
		var start:=Time.get_ticks_usec()
		var occlusion:bool=cached.update_field_geometry(stage[1],stage[2])
		var update_ms:float=(Time.get_ticks_usec()-start)/1000.0
		var local_calls:int=cached.traversable_calls
		check(occlusion==stage[3],label+" occlusion result")
		if not stage[3]:check(local_calls==0,label+" performs zero solid traversal work")
		else:check(local_calls<cached.nav_size.x*cached.nav_size.y,label+" bounds local solid recomputation")
		start=Time.get_ticks_usec();warm(cached)
		var weights_ms:float=(Time.get_ticks_usec()-start)/1000.0
		for i in specs.size():check(identities[i]==warm(cached)[i],label+" retains land/sea/air grid identity")
		var oracle=fixture()
		for rect in stage[1]:oracle.dynamic_blocks.append(rect)
		for rect in stage[2]:oracle.field_cover.append(rect)
		oracle.traversable_calls=0
		start=Time.get_ticks_usec();warm(oracle)
		var rebuild_ms:float=(Time.get_ticks_usec()-start)/1000.0
		proof.append({"operation":label,"update_ms":update_ms,"lazy_weight_requests_ms":weights_ms,"fresh_build_ms":rebuild_ms,"local_solid_checks":local_calls,"fresh_solid_checks":oracle.traversable_calls})
		compare(cached,oracle,label)
	# Defensive copies: caller mutation cannot silently change installed geometry.
	var caller:Array=[a];cached.update_field_geometry(caller,caller);caller.clear()
	check(cached.dynamic_blocks==[a] and cached.field_cover==[a],"input arrays copied")
	warm(cached)
	# Completion during a new weather band invalidates all costs coherently,
	# even when the next access is sea and land requests are delayed.
	cached.wetness=0.76
	check(not cached.update_field_geometry([a],[]),"cover change with weather transition is not occlusion")
	cached.nav_grid("sea",3.3)
	cached.wetness=0.83
	var oracle=fixture();oracle.wetness=0.76;oracle.dynamic_blocks.append(a);warm(oracle);oracle.wetness=0.83
	compare(cached,oracle,"deferred cover/weather")
	check(cached.wetness==0.83,"cost generation restores live wetness")
	cached.update_field_geometry([],[])
	check(cached.navigation.size()==specs.size(),"no cache entries leaked")
	# Other showcase maps derive cover from dynamic rectangles as well.
	var other=Terrain.new(3);other.wetness=0.5;warm(other)
	var legacy_rect:=Rect2(25,40,5.6,6)
	other.update_field_geometry([legacy_rect],[])
	var other_oracle=Terrain.new(3);other_oracle.wetness=0.5;other_oracle.dynamic_blocks.append(legacy_rect)
	compare(other,other_oracle,"legacy automatic cover")
	var precise=Terrain.new(5)
	precise.blocks.clear();precise.roadside_blocks.clear();precise.trees.clear();precise.poles.clear();precise.port=false
	var precise_grid:=precise.nav_grid("land",1.23456,"wheeled")
	check(not precise_grid.is_point_solid(Vector2i(58,86)),"precision fixture initially open")
	precise.update_field_geometry([Rect2(60.002,85,3,3)],[])
	check(precise_grid.is_point_solid(Vector2i(58,86)),"update uses actual 1.23456 radius, not rounded key 1.23")
	check(precise_grid.get_meta("navigation_radius")==1.23456,"grid retains exact construction radius")
	precise.update_field_geometry([],[])
	check(not precise_grid.is_point_solid(Vector2i(58,86)),"exact-radius boundary cell restored after removal")
	var evidence:=FileAccess.open("res://artifacts/field-geometry-proof.json",FileAccess.WRITE)
	if evidence!=null:evidence.store_string(JSON.stringify({"engine":Engine.get_version_info().string,"checks":checks,"failures":failures,"operations":proof},"  "))
	print("FIELD GEOMETRY: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
