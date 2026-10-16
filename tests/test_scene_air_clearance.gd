extends SceneTree
const Visuals=preload("res://scripts/visuals.gd")
const Sim=preload("res://scripts/simulation.gd")
var checks:=0
var failures:=0
var evidence:Array=[]
func _init()->void:call_deferred("run")
func bounds_y(box:AABB,transform:Transform3D)->Vector2:
	var low:=INF;var high:=-INF
	for i in 8:
		var point:Vector3=transform*box.get_endpoint(i)
		low=minf(low,point.y);high=maxf(high,point.y)
	return Vector2(low,high)
func height_range(node:Node)->Vector2:
	var result:=Vector2(INF,-INF)
	if node is MeshInstance3D:
		result=bounds_y(node.mesh.get_aabb(),node.global_transform)
	elif node is MultiMeshInstance3D:
		var batch:MultiMesh=node.multimesh
		for i in batch.instance_count:
			var current:=bounds_y(batch.mesh.get_aabb(),node.global_transform*batch.get_instance_transform(i))
			result.x=minf(result.x,current.x);result.y=maxf(result.y,current.y)
	for child in node.get_children():
		var current:=height_range(child)
		result.x=minf(result.x,current.x);result.y=maxf(result.y,current.y)
	return result
# World AABB of every rendered structure. Harbor buildings are merged into
# spatial tiles, so they are rebuilt one by one from the tile placements.
var structure_cache:Dictionary={}
func structures(art,world:Node3D)->Array:
	if structure_cache.has(world):return structure_cache[world]
	var result:Array=[]
	collect(world,result)
	var group:=world.find_child("HarborBuildings",true,false)
	if group!=null:
		var staging:=Node3D.new();root.add_child(staging)
		for placement in group.get_meta("placements",[]):
			var building:Node3D=art.make_authored_building(staging,placement.compiled_bounds,placement.architecture_index,placement.spec)
			collect(building,result)
			building.free()
		staging.free()
	structure_cache[world]=result
	return result
func collect(node:Node,result:Array)->void:
	if node.name=="HarborBuildings":return
	if node is MeshInstance3D and node.mesh!=null:result.append(node.global_transform*node.mesh.get_aabb())
	elif node is MultiMeshInstance3D:
		# Headless (dummy renderer) multimeshes read back identity transforms;
		# harbor prop batches rebuild theirs from the placement metadata.
		var placed:Array=node.get_parent().get_meta("placements",[]).filter(func(e):return e.get("asset_id","")==node.get_meta("asset_id","")) if node.has_meta("template_transform") else []
		for i in node.multimesh.instance_count:
			var instance:Transform3D=placed[i].transform*node.get_meta("template_transform") if i<placed.size() else node.multimesh.get_instance_transform(i)
			result.append(node.global_transform*instance*node.multimesh.mesh.get_aabb())
	for child in node.get_children():collect(child,result)
# Lowest body clearance over every structure the cruise altitude does not clear,
# sampled across its whole plan at the simulation's flight altitude.
func local_clearance(sim,definition:Dictionary,low:float,boxes:Array)->float:
	var worst:=INF
	for box in boxes:
		if float(definition.altitude)+low-box.end.y>=0.15:continue
		var nx:=ceili(box.size.x);var nz:=ceili(box.size.z)
		for ix in nx+1:
			for iz in nz+1:
				var p:=Vector2(box.position.x+box.size.x*ix/nx,box.position.z+box.size.z*iz/nz)
				worst=minf(worst,sim.flight_altitude(definition,p)+low-box.end.y)
	return worst
# Live flight across the tallest structure: the ticking simulation must apply
# the same climb (unit_altitude), not only the static query.
func fly_over(sim,kind:String,low:float,boxes:Array)->void:
	var tallest:AABB=boxes[0]
	for box in boxes:if box.end.y>tallest.end.y:tallest=box
	var center:=Vector2(tallest.get_center().x,tallest.get_center().z)
	var start:=center+Vector2(-60,0)
	var unit=sim.spawn(kind,0,start)
	sim.issue([unit.id],center+Vector2(60,0))
	var worst:=INF;var climbed:=0.0
	for frame in 600:
		sim.tick(1.0/30.0)
		if not sim.alive(unit):break
		climbed=maxf(climbed,sim.unit_altitude(unit))
		var p:Vector2=unit.pos
		if p.x>=tallest.position.x and p.x<=tallest.end.x and p.y>=tallest.position.z and p.y<=tallest.end.z:
			worst=minf(worst,sim.unit_altitude(unit)+low-tallest.end.y)
		if p.distance_to(center+Vector2(60,0))<1.0:break
	checks+=1
	if worst==INF or worst<0.15:
		failures+=1;printerr("FAIL: ",kind," live flight over ",tallest," clearance=",worst)
	evidence.append({"kind":kind,"live_overflight_top":tallest.end.y,"live_clearance":worst,"peak_altitude":climbed})
	unit.hp=0.0

func run()->void:
	for scenario in JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json")).size():
		var sim=Sim.new(false,scenario)
		var definitions:Dictionary=sim.definitions
		var art=Visuals.new()
		var world:=Node3D.new();root.add_child(world)
		art.make_world(world,sim.terrain)
		var scenery:=height_range(world)
		for kind in ["drone","helo"]:
			var unit=art.make_unit(world,{"kind":kind,"team":0})
			var model:Node3D=unit.get_node("Model")
			# Runtime flight pitches down by 0.07 radians and bobs +/-0.08.
			var body:=height_range(model)
			model.rotation.x=-0.07;model.position.y=-0.08
			var moving_body:=height_range(model)
			body.x=minf(body.x-0.08,moving_body.x)
			var clearance:float=float(definitions[kind].altitude)+body.x-scenery.y
			# An authored skyline (harbor towers, cranes, poplars) taller than any
			# usable cruise altitude: aircraft climb over each structure instead.
			if clearance<0.15:clearance=local_clearance(sim,definitions[kind],body.x,structures(art,world))
			evidence.append({"scenario":scenario,"kind":kind,"scenery_top":scenery.y,"altitude":definitions[kind].altitude,"clearance":clearance})
			checks+=1
			if clearance<0.15:
				failures+=1;printerr("FAIL: scenario ",scenario," ",kind," air/scenery clearance=",clearance," top=",scenery.y)
			if scenery.y>float(definitions[kind].altitude):fly_over(sim,kind,body.x,structures(art,world))
			unit.free()
		world.free()
	var report:=FileAccess.open("res://artifacts/scene-air-clearance.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"geometry":evidence},"  "))
	print("SCENE AIR CLEARANCE: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
