extends SceneTree

const Terrain=preload("res://scripts/terrain.gd")
const Elevation=preload("res://scripts/elevation.gd")
const Art=preload("res://scripts/visuals.gd")
const Sim=preload("res://scripts/simulation.gd")
const Effects=preload("res://scripts/effects.gd")
var checks:=0
var failures:Array[String]=[]

func _init() -> void:call_deferred("run")
func check(value:bool,message:String) -> void:
	checks+=1
	if not value:failures.append(message);printerr("FAIL: ",message)

func config(patches:Array=[]) -> Dictionary:
	return {"id":"elevation_fixture","size":[96,72],"shore_x":96,"port":false,
		"blocks":[],"woods":[],"objectives":[],"rubble":[0,0,0,0],"mud":[0,0,0,0],
		"roads":{},"elevation":patches}

func run() -> void:
	var flat:=Terrain.new(0,config())
	check(not flat.has_elevation() and flat.height_at(Vector2(48,36))==0.0,"omitted relief keeps a flat map")
	check(flat.slope_at(Vector2(48,36))==0.0,"flat slope is zero")
	check(flat.elevation_clear(Vector2(8,36),Vector2(88,36)),"flat relief adds no sight restriction")
	check(is_equal_approx(flat.ground_speed(Vector2(48,36),"tracked"),0.88),"flat mobility values unchanged")
	var relief:=Elevation.new([{"rect":[34,0,16,72],"height":6,"ramp":12}])
	check(is_equal_approx(relief.height_at(Vector2(40,30)),6.0),"plateau keeps authored elevation")
	check(is_equal_approx(relief.height_at(Vector2(28,30)),3.0),"mid-ramp height is smooth and deterministic")
	check(is_equal_approx(relief.height_at(Vector2(20,30)),0.0),"height returns to zero outside ramp")
	check(is_equal_approx(relief.slope_at(Vector2(28,30)),0.75),"grade derives from physical height change")
	check(relief.slope_at(Vector2(34,30))==0.0 and relief.slope_at(Vector2(22,30))==0.0,"ramp meets plateau and base smoothly")
	check(relief.traversable(Vector2(28,30),0.8,"infantry"),"infantry can climb the steep approach")
	check(not relief.traversable(Vector2(28,30),2.45,"tracked"),"armor cannot climb an infantry-only slope")
	check(not relief.traversable(Vector2(28,30),1.4,"wheeled"),"wheels obey their own slope limit")
	check(relief.speed_at(Vector2(28,30),"infantry")<1.0,"climbing slows infantry")
	var ridge:=Terrain.new(0,config([{"rect":[34,0,16,72],"height":6,"ramp":12}]))
	var a:=Vector2(10,36);var b:=Vector2(82,36)
	check(not ridge.path(a,b,"land",0.8,[],"infantry").is_empty(),"infantry path crosses a traversable ridge")
	check(ridge.path(a,b,"land",2.45,[],"tracked").is_empty(),"armor cannot smooth a path through a steep full-width ridge")
	check(not ridge.reachable(a,b,"land",2.45,"tracked"),"reachability agrees with actual armor path")
	check(ridge.reachable(a,b,"land",0.8,"infantry"),"infantry reachability remains independent of prior armor query")
	check(not ridge.segment_clear(a,b,"land",2.45,[],"tracked"),"live swept movement rejects the same slope as routing")
	check(ridge.segment_clear(a,b,"land",0.8,[],"infantry"),"live infantry sweep accepts their own climb")
	check(not ridge.line_clear(a,b) and not ridge.line_clear(b,a),"ridge physically blocks ground sight in both directions")
	check(not ridge.elevation_clear(a,b,3.0,1.6,true),"low aircraft cannot see through a ridge")
	check(ridge.elevation_clear(a,b,12.0,12.0,true),"high observation clears the ridge")
	check(ridge.height_at(Vector2(42,36))<=ridge.air_ceiling(Vector2(42,36)),"aircraft clearance includes terrain height")
	var forest_config:=config([{"rect":[34,0,16,72],"height":6,"ramp":12}])
	forest_config.woods=[[36,30,10,12]]
	var forest:=Terrain.new(0,forest_config)
	check(forest.air_ceiling(Vector2(37,31))>=9.99,"elevated tree crowns enter the aircraft skyline at map load")
	var gentle:=Terrain.new(0,config([{"rect":[34,0,16,72],"height":6,"ramp":32}]))
	check(not gentle.path(Vector2(5,36),Vector2(88,36),"land",2.45,[],"tracked").is_empty(),"gentle incline supports armor")
	check(gentle.ground_speed(Vector2(18,36),"tracked")<flat.ground_speed(Vector2(18,36),"tracked"),"vehicle travel-time cost includes grade")
	var hill:=Terrain.new(0,config([{"rect":[34,28,20,16],"height":6,"ramp":12}]))
	var detour:=hill.path(a,b,"land",2.45,[],"tracked")
	check(not detour.is_empty(),"armor can use a real route around the hill")
	var previous:=a
	var clear:=true
	var distance:=0.0
	for point in detour:
		clear=clear and hill.segment_clear(previous,point,"land",2.45,[],"tracked")
		distance+=previous.distance_to(point);previous=point
	check(clear and distance>a.distance_to(b)*1.1,"every detour edge clears the slope; route is meaningfully different")
	var overlapped:=Elevation.new([{"rect":[20,20,20,20],"height":6,"ramp":12},{"rect":[24,24,12,12],"height":8,"ramp":12}])
	check(overlapped.height_at(Vector2(30,30))==8.0,"overlapping patches take max instead of stacking spikes")
	var top:=Vector3(42,50,36)
	var hit:=ridge.ground_intersection(top,Vector3.DOWN)
	check(hit.distance_to(Vector3(42,6,36))<0.001,"mouse ray hits visible plateau instead of buried zero plane")
	var oblique:=Vector3(0.2,-1,0.1).normalized()
	var hit2:=ridge.ground_intersection(top,oblique)
	check(absf(hit2.y-ridge.height_at(Vector2(hit2.x,hit2.z)))<0.001,"oblique ground pick agrees with terrain")
	var from_below:=flat.ground_intersection(Vector3(48,-5,36),Vector3.DOWN)
	check(from_below.y==0.0,"wide orthographic corners keep signed plane intersection")
	var art:=Art.new()
	var mesh:=art.heightfield_mesh(hill)
	var exact:=true
	for vertex in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		var p:=Vector2(vertex.x,vertex.z)+hill.world_size*0.5
		if absf(vertex.y-hill.height_at(p))>0.0001:exact=false;break
	check(exact,"rendered vertices use the authoritative elevation")
	check(mesh.get_aabb().size.y>=5.99,"relief is real geometry with raised bounds")
	var array:Array=mesh.surface_get_arrays(0)
	var vertices:PackedVector3Array=array[Mesh.ARRAY_VERTEX]
	var indices:PackedInt32Array=array[Mesh.ARRAY_INDEX]
	var winding:Vector3=(vertices[indices[1]]-vertices[indices[0]]).cross(vertices[indices[2]]-vertices[indices[0]])
	check(winding.y<0.0,"heightfield front faces use Godot clockwise winding")
	var stage:=Node3D.new();root.add_child(stage)
	var marking:=art.box(stage,Vector3(42,0.02,36),Vector3(2,0.01,2),Color.WHITE)
	art.drape_ground_detail(marking,ridge)
	var on_surface:=true
	for vertex in marking.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		var world:Vector3=marking.transform*vertex
		if absf(world.y-ridge.height_at(Vector2(world.x,world.z))-0.02)>0.0051:on_surface=false
	check(on_surface,"road paint drapes onto the visible relief")
	var junction=art.cylinder(stage,Vector3(28,0.016,36),5.0,0.012,Color.WHITE)
	art.drape_ground_detail(junction,ridge)
	var junction_arrays:Array=junction.mesh.surface_get_arrays(0)
	var junction_vertices:PackedVector3Array=junction_arrays[Mesh.ARRAY_VERTEX]
	var junction_normals:PackedVector3Array=junction_arrays[Mesh.ARRAY_NORMAL]
	var junction_indices:PackedInt32Array=junction_arrays[Mesh.ARRAY_INDEX]
	var conforms:=true
	var cells_checked:=0
	for i in range(0,junction_indices.size(),3):
		var ids:=Vector3i(junction_indices[i],junction_indices[i+1],junction_indices[i+2])
		if junction_normals[ids.x].y<0.7 or junction_normals[ids.y].y<0.7 or junction_normals[ids.z].y<0.7:continue
		var center:Vector3=junction.transform*((junction_vertices[ids.x]+junction_vertices[ids.y]+junction_vertices[ids.z])/3.0)
		var floor_height:=ridge.elevation.mesh_height_at(Vector2(center.x,center.z),Vector2.ONE*2.0)
		if absf(center.y-floor_height-0.022)>0.0001:conforms=false
		cells_checked+=1
	check(conforms and cells_checked>40,"junction interiors conform to land triangles without clipping or hovering on curved ramps")
	stage.free()
	check_simulation(ridge)
	check_effect_grounding(ridge)
	print("ELEVATION: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)

func check_simulation(ridge:BattleTerrain) -> void:
	var sim=Sim.new(false,0)
	sim.terrain=ridge
	sim.definitions.tank.range=100.0;sim.definitions.tank.sight=100.0
	var tank:Dictionary=sim.spawn("tank",0,Vector2(10,36))
	var enemy:Dictionary=sim.spawn("tank",1,Vector2(82,36))
	sim.update_visibility()
	check(not enemy.seen_by[0],"actual ground observers cannot reveal a unit beyond the ridge")
	enemy.seen_by[0]=true
	check(not sim.can_fire(tank,enemy),"team contact does not let a tank shoot through terrain")
	check(not sim.movement_clear(tank,Vector2(28,36),[]),"actual tank motion rejects infantry-only slope")
	check(not sim.location_clear(Vector2(28,20),"tank"),"vehicle spawn validation obeys slope profile")
	check(sim.location_clear(Vector2(28,20),"rifle"),"infantry spawn validation allows its traversable slope")
	tank.pos=Vector2(42,36)
	check(is_equal_approx(sim.unit_altitude(tank),6.0),"simulation land height equals plateau height")
	check(sim.shot_distance(tank,enemy)>tank.pos.distance_to(enemy.pos),"actual shot distance includes elevation difference")
	sim.update_visibility()
	check(enemy.seen_by[0] and sim.can_fire(tank,enemy),"crest observation opens a physical clear firing line")
	var air=Sim.new(false,0);air.terrain=ridge
	air.definitions.helo.sight=100.0;air.definitions.helo.range=100.0
	var helo:Dictionary=air.spawn("helo",0,Vector2(10,36))
	var target:Dictionary=air.spawn("tank",1,Vector2(82,36))
	helo.altitude=2.0
	air.update_visibility()
	check(not target.seen_by[0],"actual low aircraft sight is occluded by relief")
	target.seen_by[0]=true
	check(not air.can_fire(helo,target),"actual low aircraft cannot fire through a ridge")
	var tile:=ridge.cell(target.pos)
	check(not air.visible_cells.has(tile),"airborne fog field respects low-flight terrain shadow")
	helo.altitude=18.0
	air.update_visibility()
	check(target.seen_by[0] and air.can_fire(helo,target),"actual raised aircraft sees and fires above relief")
	check(air.visible_cells.has(tile),"changing actual air height refreshes cached fog")
	var infantry=Sim.new(false,0);infantry.terrain=ridge
	infantry.definitions.rifle.range=100.0;infantry.definitions.rifle.sight=100.0
	var section:Dictionary=infantry.spawn("rifle",0,Vector2(10,36))
	var foe:Dictionary=infantry.spawn("rifle",1,Vector2(82,36))
	foe.seen_by[0]=true
	check(not infantry.can_fire(section,foe),"individual soldier targeting cannot bypass ridge occlusion")
	check(infantry.aim_soldier(section.members[0].pos,foe,10000.0,true).is_empty(),"individual aim points obey the terrain ray")
	var steep:=Vector2(28,36)
	section.pos=Vector2(27.8,36)
	for member in section.members:member.pos=section.pos+Vector2.from_angle(float(member.index)*TAU/section.members.size())*0.7
	check(infantry.movement_clear(section,steep,[]),"infantry motion accepts its own slope profile")
	var plateau_air:Dictionary=air.spawn("drone",0,Vector2(42,10))
	check(air.unit_altitude(plateau_air)>=ridge.height_at(plateau_air.pos)+air.AIR_GAP,"new aircraft starts above raised ground before the first tick")

func check_effect_grounding(terrain:BattleTerrain) -> void:
	var effects:=Effects.new();root.add_child(effects);effects.muted=true
	effects.set_ground_terrain(terrain);effects.set_world_bounds(terrain.world_size,terrain.shore_x)
	var pos:=Vector3(42,6,36)
	var decal:int=effects.decal(pos,Effects.SCORCH,1,1,2,Color.BLACK)
	check(decal>=0 and effects.ground.pos[decal].y>6.0,"temporary impact decal sits above raised ground")
	effects.mark(pos,1.5,effects.Remains.CRATER)
	var tile:Dictionary=effects.remains.tiles[Vector2i.ZERO]
	var visible_relief:=false
	for vertex in tile.node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		if vertex.y>5.9:visible_relief=true;break
	check(visible_relief,"persistent crater tile follows heightfield instead of being buried")
	var fragment:int=effects.debris(pos+Vector3.UP*0.1,Vector3.DOWN*4,0.2,1,Color.GRAY,true)
	effects._process(0.05);effects._process(0.05)
	check(fragment>=0 and effects.volume.pos[fragment].y>=6.0,"falling debris collides with raised terrain")
	check(effects.remains.relief_tiles.size()==4,"relief crater meshes prebuilt at setup for bounded map tiles")
	effects.clear();effects.free()
