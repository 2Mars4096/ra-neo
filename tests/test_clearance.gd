extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Visuals=preload("res://scripts/visuals.gd")
var failures:Array[String]=[]
var checks:=0
var minimum_margin:=INF

func check(value:bool,message:String) -> void:
	checks+=1
	if not value and not failures.has(message):
		failures.append(message)
		printerr("FAIL: ",message)

func _init() -> void:
	call_deferred("run")

func assert_clear(sim) -> void:
	for u in sim.units:
		if not sim.alive(u): continue
		var d:Dictionary=sim.definitions[u.kind]
		check(sim.terrain.traversable(u.pos,d.domain,float(d.radius)),"static clearance "+str(u.id))
		for other in sim.units:
			if not sim.alive(other) or other.id<=u.id or sim.collision_layer(u)!=sim.collision_layer(other): continue
			# A section whose survivors are all down is no body: its men lie where
			# they fell and others step past (Simulation.collision_layer). A live
			# section can cross that spot and go down on it in turn.
			if sim.collision_layer(u)=="downed": continue
			var margin:float=u.pos.distance_to(other.pos)-float(d.radius)-float(sim.definitions[other.kind].radius)
			minimum_margin=minf(minimum_margin,margin)
			check(margin>=-0.001,"model overlap %d/%d" % [u.id,other.id])

func mesh_bounds(node:Node3D,transform:Transform3D=Transform3D.IDENTITY) -> Vector2:
	var bound:=Vector2.ZERO
	for child in node.get_children():
		if not child is Node3D or child.name=="Selection": continue
		var local:Transform3D=transform*child.transform
		if child is MeshInstance3D:
			for surface in child.mesh.get_surface_count():
				var arrays:Array=child.mesh.surface_get_arrays(surface)
				for vertex in arrays[Mesh.ARRAY_VERTEX]:
					var p:Vector3=local*vertex
					bound.x=maxf(bound.x,Vector2(p.x,p.z).length())
					bound.y=maxf(bound.y,p.y)
		var nested:=mesh_bounds(child,local)
		bound.x=maxf(bound.x,nested.x)
		bound.y=maxf(bound.y,nested.y)
	return bound

func triangle_count(node:Node) -> int:
	var count:=0
	if node is MeshInstance3D:
		for surface in node.mesh.get_surface_count():
			var arrays:Array=node.mesh.surface_get_arrays(surface)
			var indices=arrays[Mesh.ARRAY_INDEX]
			count+=(indices.size() if indices!=null and indices.size()>0 else arrays[Mesh.ARRAY_VERTEX].size())/3
	for child in node.get_children():count+=triangle_count(child)
	return count

func run() -> void:
	var sim=Sim.new(true,0)
	var art=Visuals.new()
	var stage:=Node3D.new()
	root.add_child(stage)
	for kind in sim.definitions:
		var original:=Node3D.new()
		art.models.build(original,kind,0)
		var original_triangles:=triangle_count(original)
		art.bake_model(original)
		check(triangle_count(original)==original_triangles,"batching preserves all authored triangles: "+kind)
		original.free()
		var model=art.make_unit(stage,{"kind":kind,"team":0})
		var bounds:=mesh_bounds(model.get_node("Model"))
		check(bounds.x<=float(sim.definitions[kind].radius),"visual footprint fits collision radius: "+kind)
		if sim.definitions[kind].domain=="air":
			check(float(sim.definitions[kind].altitude)-0.8>5.4,"legacy minimum flight band; full scene tested separately: "+kind)
		if sim.definitions[kind].domain=="land":
			check(bounds.y<4.0,"aircraft altitude clears land model: "+kind)
		model.queue_free()
	assert_clear(sim)
	# Dense deployment must find distinct safe spawn positions.
	for i in 12:
		sim.spawn("tank" if i%3==0 else "rifle",0,Vector2(14,56))
	assert_clear(sim)
	var land:Array=sim.living(0).filter(func(u): return sim.definitions[u.kind].domain=="land").map(func(u): return u.id)
	sim.issue(land,Vector2(46,22),"attack_move")
	for i in 600:
		if i==250: sim.issue(land,Vector2(70,44),"attack_move")
		if i==450: sim.issue(land,Vector2(18,42),"move")
		sim.tick(0.1)
		sim.events.clear()
		assert_clear(sim)
	# A ship must route around pier geometry and remain within water clearance.
	var naval=Sim.new(false,0)
	var ship=naval.spawn("boat",0,Vector2(91,61))
	check(naval.issue([ship.id],Vector2(92,27))==1,"naval passage order accepted")
	for i in 250:
		naval.tick(0.1)
		naval.events.clear()
		assert_clear(naval)
	check(ship.pos.distance_to(Vector2(92,27))<0.2,"ship clears both piers and reaches destination")
	var report={"checks":checks,"failures":failures,"minimum_separation_margin":minimum_margin,"scenario":"Dense deployment, ridge traversal, forest lanes, mixed-group redirection, combat, naval passage, and mesh-vertex footprint validation"}
	FileAccess.open("res://artifacts/clearance.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("CLEARANCE TESTS: ",checks," checks, ",failures.size()," failures; minimum margin=",minimum_margin)
	quit(0 if failures.is_empty() else 1)
