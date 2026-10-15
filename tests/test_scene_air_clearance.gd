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
			evidence.append({"scenario":scenario,"kind":kind,"scenery_top":scenery.y,"altitude":definitions[kind].altitude,"clearance":clearance})
			checks+=1
			if clearance<0.15:
				failures+=1;printerr("FAIL: scenario ",scenario," ",kind," air/scenery clearance=",clearance," top=",scenery.y)
			unit.free()
		world.free()
	var report:=FileAccess.open("res://artifacts/scene-air-clearance.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"geometry":evidence},"  "))
	print("SCENE AIR CLEARANCE: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
