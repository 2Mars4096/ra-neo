extends SceneTree
const Terrain=preload("res://scripts/terrain.gd")
const Props=preload("res://scripts/roadside_props.gd")
const Visuals=preload("res://scripts/visuals.gd")
var checks:=0
var failures:Array[String]=[]
func _init()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok and not failures.has(label):failures.append(label);printerr("FAIL: ",label)
func route_safe(terrain,origin:Vector2,route:Array,radius:float)->bool:
	for point in route:
		var count:=maxi(1,ceili(origin.distance_to(point)/0.05))
		for step in range(count+1):
			if not terrain.traversable(origin.lerp(point,float(step)/count),"land",radius):return false
		origin=point
	return not route.is_empty()
func run()->void:
	if "--haul-probe" in OS.get_cmdline_user_args():
		haul_probe();return
	var art=Visuals.new()
	for scenario in [0,1,2]:check(Props.layout(scenario).is_empty(),"legacy map has no extra props")
	for scenario in [3,4]:
		var terrain=Terrain.new(scenario)
		var baseline=Terrain.new(scenario);baseline.roadside_blocks.clear()
		check(terrain.roadside_props.size()==5,"bounded five-prop layout")
		var stage:=Node3D.new();root.add_child(stage)
		var models:Node3D=Props.build(art,stage,terrain)
		check(Props.build(art,stage,terrain)==models and stage.get_child_count()==1,"integration is idempotent")
		for i in terrain.roadside_props.size():
			var prop:Dictionary=terrain.roadside_props[i]
			var bounds:Rect2=terrain.roadside_blocks[i]
			var model:Node3D=models.get_child(i)
			check(model.get_child_count()==1 and model.get_child(0) is MeshInstance3D,"one baked mesh per prop")
			var minimum_y:=INF
			for mesh in model.get_children():
				check(not mesh is Light3D,"no live prop lights")
				for surface in mesh.mesh.get_surface_count():
					var arrays:Array=mesh.mesh.surface_get_arrays(surface)
					for vertex in arrays[Mesh.ARRAY_VERTEX]:
						var p:Vector3=model.transform*mesh.transform*vertex
						minimum_y=minf(minimum_y,p.y)
						check(bounds.grow(0.001).has_point(Vector2(p.x,p.z)),"all rendered vertices inside shared footprint %s/%s"%[scenario,i])
						check(p.y>=-0.001 and p.y<4.0,"geometry above ground and below aircraft")
			check(minimum_y<0.03,"lamp base / car tires grounded")
			check(not terrain.traversable(prop.pos,"land",0.8),"prop has land collision")
			check(terrain.traversable(prop.pos,"air",1.55),"low prop preserves air access")
			check(not terrain.line_clear(bounds.get_center()-Vector2(3,0),bounds.get_center()+Vector2(3,0)),"static prop participates in ground sight blockers")
			for building in terrain.blocks:check(not building.grow(0.3).intersects(bounds),"prop clears building and yard walls")
			for tree in terrain.trees:check(not terrain.circle_rect(tree,1.2,bounds),"prop clears authored trees")
			for pole in terrain.poles:check(not terrain.circle_rect(pole,2.8,bounds),"capture pole approach clear")
			for node in terrain.roads.nodes.values():check(not terrain.circle_rect(node,3.5,bounds),"junction approach clear")
			for j in range(i):check(not bounds.intersects(terrain.roadside_blocks[j]),"props do not overlap")
		# Every formerly clear road center/edge stays clear for its tested footprint.
		for edge in terrain.roads.segments:
			var normal:=Vector2(-(edge.b-edge.a).y,(edge.b-edge.a).x).normalized()
			var count:=ceili(edge.a.distance_to(edge.b)/0.25)
			for step in range(count+1):
				var center:Vector2=edge.a.lerp(edge.b,float(step)/count)
				for radius in [0.8,2.45,2.65]:
					if baseline.traversable(center,"land",radius):check(terrain.traversable(center,"land",radius),"road center clearance retained %s/%s"%[scenario,edge.purpose])
				for sign in [-1.0,1.0]:
					var edge_point:Vector2=center+normal*edge.width*0.5*sign
					if baseline.traversable(edge_point,"land",0.8):check(terrain.traversable(edge_point,"land",0.8),"road edge access retained %s/%s/%s"%[scenario,edge.purpose,edge_point])
			for radius in [0.8,2.45,2.65]:
				if not baseline.path(edge.a,edge.b,"land",radius).is_empty():
					check(route_safe(terrain,edge.a,terrain.path(edge.a,edge.b,"land",radius),radius),"road graph route remains safely reachable")
		# Sample original front/rear approach space; the yard itself stays solid.
		for building in terrain.blocks:
			for side in [-1.0,1.0]:
				var approach:Vector2=building.get_center()+Vector2(0,side*(building.size.y/2+3.5))
				for radius in [0.8,2.65]:
					var origin:=Vector2(40,26.5) if scenario==3 else Vector2(40,60)
					if not baseline.path(origin,approach,"land",radius).is_empty():
						check(route_safe(terrain,origin,terrain.path(origin,approach,"land",radius),radius),"building approach remains reachable")
		stage.free()
	run_quay(art)
	if "--render" in OS.get_cmdline_user_args():await render_review()
	print("ROADSIDE PROPS: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)

func render_review()->void:
	root.size=Vector2i(1440,900)
	for scenario in [3,4]:
		var terrain=Terrain.new(scenario)
		var art=Visuals.new()
		var stage:=Node3D.new();root.add_child(stage)
		art.make_world(stage,terrain)
		Props.build(art,stage,terrain)
		var env:=WorldEnvironment.new();env.environment=Environment.new()
		env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("4e595b")
		env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color=Color("d4deea");env.environment.ambient_light_energy=0.7
		stage.add_child(env)
		var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-55,-35,0);sun.light_energy=1.5;sun.shadow_enabled=true;stage.add_child(sun)
		var camera:=Camera3D.new();stage.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.current=true
		for shot in ["sedan","service","overview"]:
			var focus:=Vector3(36,0,14) if scenario==3 else Vector3(26,0,57)
			if shot=="service":focus=Vector3(51,0,54) if scenario==3 else Vector3(56,0,63)
			if shot=="overview":focus=Vector3(42,0,36)
			camera.size=60 if shot=="overview" else 16
			camera.position=focus+Vector3(15,22,19);camera.look_at(focus)
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var path:="/private/tmp/ra-roadside-%s-%s.png"%[scenario,shot]
			check(root.get_texture().get_image().save_png(path)==OK,"render capture saved")
			print("ROADSIDE CAPTURE ",path)
		stage.free()
		await process_frame

func run_quay(art)->void:
	var terrain=Terrain.new(5)
	var baseline=Terrain.new(5)
	baseline.roadside_blocks.clear()
	for prop in baseline.roadside_props:
		if prop.kind!="quay_bay":baseline.roadside_blocks.append(Props.footprint(prop))
	var previous:Array=[
		["sedan",31,49,90],["service",104,79,0],["sedan",86,59.5,90],["service",104,33,0],
		["lamp",44,49,0],["lamp",68,59,0],["lamp",104,59,0],["lamp",76,34,0],["lamp",44,80,0],
		["pallets",102,87,0],["drums",102,82,0],["reel",103,94,0],["cabinet",119,75,0],
		["bench",86,50,90],["bin",84,50,0],["bollard",127.2,72,0],["bollard",127.2,80,0],
		["bollard",127.2,94,0],["pallets",116,44,90],["drums",119,45,0],["reel",115,75,90]]
	for i in previous.size():
		var row:Array=previous[i];var prop:Dictionary=terrain.roadside_props[i]
		check(prop.kind==row[0] and prop.pos.is_equal_approx(Vector2(row[1],row[2])) and is_equal_approx(prop.yaw,deg_to_rad(row[3])),"preserve existing Riverside prop %s"%i)
	var bays:Array=terrain.roadside_props.filter(func(p):return p.kind=="quay_bay")
	check(bays.size()==8 and terrain.roadside_props.size()==29,"eight bays added to all twenty-one existing props")
	var stage:=Node3D.new();root.add_child(stage)
	var models:Node3D=Props.build(art,stage,terrain)
	check(Props.build(art,stage,terrain)==models and models.get_child_count()==29,"Riverside prop build is idempotent")
	var evidence:Array=[]
	var previous_end:=16.0
	var triangles:=0
	for i in terrain.roadside_props.size():
		var prop:Dictionary=terrain.roadside_props[i]
		var footprint:Rect2=terrain.roadside_blocks[i]
		var model:Node3D=models.get_child(i)
		check(model.scale==Vector3.ONE,"no generic scaling of waterfront or existing props")
		check(model.get_child_count()==1 and model.get_child(0) is MeshInstance3D,"one baked mesh per Riverside prop")
		var low:=Vector3(INF,INF,INF);var high:=Vector3(-INF,-INF,-INF)
		for mesh in model.get_children():
			for surface in mesh.mesh.get_surface_count():
				var arrays:Array=mesh.mesh.surface_get_arrays(surface)
				if prop.kind=="quay_bay":triangles+=arrays[Mesh.ARRAY_INDEX].size()/3
				for vertex in arrays[Mesh.ARRAY_VERTEX]:
					var world:Vector3=model.transform*mesh.transform*vertex
					low=low.min(world);high=high.max(world)
					check(footprint.grow(0.0001).has_point(Vector2(world.x,world.z)),"all Riverside vertices inside shared collision footprints")
		if prop.kind=="quay_bay":
			check(is_equal_approx(footprint.position.x,126.9) and is_equal_approx(footprint.end.x,128.0),"exact land-side quay footprint x126.9..128")
			check(low.is_equal_approx(Vector3(126.9,0,footprint.position.y)) and high.is_equal_approx(Vector3(128,0.56,footprint.end.y)),"exact quay mesh bounds match footprint and low height")
			check(high.x<=terrain.shore_x+0.00001,"no visible quay geometry enters navigable sea")
			check(footprint.position.y>=16 and footprint.end.y<=102.0001,"quay ends within authored y16..102")
			var expected_gap:=0.0 if evidence.is_empty() else (5.0 if evidence.size()==2 else 0.12)
			check(is_equal_approx(footprint.position.y-previous_end,expected_gap),"exact expansion joints and northern loading opening")
			previous_end=footprint.end.y
			check(not terrain.traversable(prop.pos,"land",0.2),"quay bay blocks land movement")
			for other in terrain.roadside_props:
				if other==prop or other.kind=="bollard":continue
				check(not footprint.intersects(Props.footprint(other)),"quay does not overlap other substantial props")
			evidence.append({"bounds":[low.x,low.y,low.z,high.x,high.y,high.z]})
		elif prop.kind=="bollard":
			check(is_equal_approx(low.y,0.56),"bollard base sits exactly on coping top")
			var supported:=false
			for bay in bays:
				var support:Rect2=Props.footprint(bay)
				if support.grow(0.0001).encloses(footprint):supported=true
			check(supported,"entire bollard plan footprint supported by its quay bay")
	check(is_equal_approx(previous_end,102.0),"quay reaches exact southern endpoint")
	check(baseline.traversable(Vector2(126.2,21),"land",0.8) and not terrain.traversable(Vector2(126.2,21),"land",0.8),"shared quay footprint adds real land clearance exclusion")
	var definitions:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/units.json"))
	var tank_radius:float=definitions.tank.radius
	var boat_radius:float=definitions.boat.radius
	check(terrain.segment_clear(Vector2(123,16),Vector2(123,102),"land",tank_radius),"full quayside tank center route stays clear")
	check(terrain.traversable(Vector2(125.5,32.06218),"land",tank_radius),"northern loading opening preserves tank deployment sweep")
	check(126.9-(123+tank_radius)>1.0,"quay retains over one unit beyond actual tank envelope")
	for step in 345:
		var y:=16.0+step*0.25
		check(terrain.traversable(Vector2(123,y),"land",tank_radius),"sampled road tank envelope clear")
		check(terrain.traversable(Vector2(terrain.shore_x+boat_radius+0.001,y),"sea",boat_radius),"shore-tangent vessel envelope remains clear of land-side masonry")
		check(not terrain.traversable(Vector2(127.5,y),"sea",0.2),"sea units cannot cross shoreline into quay")
	for edge in terrain.roads.segments:
		var count:=maxi(1,ceili(edge.a.distance_to(edge.b)/0.25))
		var normal:Vector2=(edge.b-edge.a).normalized().orthogonal()
		for step in count+1:
			var center:Vector2=edge.a.lerp(edge.b,float(step)/count)
			if baseline.traversable(center,"land",tank_radius):check(terrain.traversable(center,"land",tank_radius),"all previously clear Riverside road tank centers retained")
			for sign in [-1.0,1.0]:
				var shoulder:Vector2=center+normal*edge.width*0.5*sign
				if baseline.traversable(shoulder,"land",0.8):check(terrain.traversable(shoulder,"land",0.8),"Riverside road shoulder infantry clearance retained")
	FileAccess.open("res://artifacts/waterfront-bounds.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"bays":evidence,"new_quay_triangles":triangles,"new_quay_meshes":8,"tank_radius":tank_radius,"boat_radius":boat_radius,"native_review":false},"  "))
	stage.free()

func haul_probe()->void:
	var Sim=load("res://scripts/simulation.gd")
	var Classic=load("res://scripts/classic.gd")
	var sims:Array=[]
	for remove_quay in [false,true]:
		var sim=Sim.new(false,5)
		if remove_quay:
			sim.terrain.roadside_props=sim.terrain.roadside_props.filter(func(p):return p.kind!="quay_bay")
			sim.terrain.roadside_blocks.clear()
			for prop in sim.terrain.roadside_props:sim.terrain.roadside_blocks.append(Props.footprint(prop))
			for x in sim.terrain.fog_grid_size.x:
				for y in sim.terrain.fog_grid_size.y:
					var point:Vector2=sim.terrain.center(Vector2i(x,y))
					sim.terrain.land.set_point_solid(Vector2i(x,y),sim.terrain.is_water(point) or sim.terrain.blocked(point))
		Classic.populate(sim);sim.update_visibility()
		for team in 2:Classic.build(sim,"refinery",team,Vector2(6,86) if team==0 else Vector2(116,26))
		sim.classic.ai_clock=100000;sim.classic.attack_clock=100000
		sims.append(sim)
	var different:=false
	for frame in 1800:
		for sim in sims:
			sim.tick(0.1);sim.events.clear()
			if frame==150:
				for team in 2:Classic.build(sim,"barracks",team,Classic.find_site(sim,"barracks",team))
			if frame==250:Classic.enqueue(sim,"harvester",0)
			if frame==400:
				for team in 2:Classic.enqueue(sim,"rifle",team)
		var state:Array=[]
		for sim in sims:state.append(sim.living(0).map(func(u):return {"id":u.id,"kind":u.kind,"pos":u.pos,"orders":u.orders,"cargo":u.get("cargo",0)}))
		if not different and state[0]!=state[1]:
			different=true
			print("FIRST HAUL DIFFERENCE frame=",frame," time=",sims[0].time," new=",state[0]," old=",state[1])
			for sim in sims:
				for u in sim.living(0):print(" DETAIL ",u.id," kind=",u.kind," pos=",u.pos," path=",u.path," members=",u.members)
		if frame in [499,899,1799]:
			for i in sims.size():
				for u in sims[i].living(0):print("PROBE ",i," t=",sims[i].time," id=",u.id," kind=",u.kind," pos=",u.pos," cargo=",u.get("cargo",0)," path=",u.path," orders=",u.orders," phase=",u.maneuver)
	quit()
