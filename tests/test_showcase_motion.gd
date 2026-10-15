extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Art=preload("res://scripts/visuals.gd")
const Motion=preload("res://scripts/unit_animation.gd")
var failures:=0
var checks:=0
var min_height:=INF
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok and failures<8:printerr("FAIL: ",label)
	if not ok:failures+=1
func lowest(node:Node3D,xf:Transform3D)->float:
	var value:=INF
	if node is MeshInstance3D:
		for surface in node.mesh.get_surface_count():
			for vertex in node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:value=minf(value,(xf*vertex).y)
	for child in node.get_children():
		if child is Node3D:value=minf(value,lowest(child,xf*child.transform))
	return value
func _init()->void:call_deferred("run")
func run()->void:
	var sim=Sim.new(false,3)
	var squad=sim.spawn("rifle",0,Vector2(14,54))
	var tank=sim.spawn("tank",0,Vector2(20,55))
	var art=Art.new()
	var stage:=Node3D.new()
	root.add_child(stage)
	var visual=art.make_unit(stage,squad)
	var model=visual.get_node("Model")
	sim.issue([squad.id,tank.id],Vector2(18,41),"move")
	for frame in 300:
		sim.tick(1.0/30.0)
		visual.position=Vector3(squad.pos.x,0,squad.pos.y)
		model.rotation.y=atan2(-squad.facing.x,-squad.facing.y)
		Motion.pose(model,squad,sim,1.0/30.0)
		if frame%3==0:
			var low:=lowest(model,Transform3D.IDENTITY)
			min_height=minf(min_height,low)
			check(low>=-0.04,"feet remain above ground during stride and settling")
		for member in squad.members:
			check(sim.terrain.traversable(member.pos,"land",0.8),"individual footprint clears terrain")
			check(member.pos.distance_to(tank.pos)>=float(sim.definitions.tank.radius)+0.79,"vehicle never penetrates individual soldier")
			for peer in squad.members:
				if member.index<peer.index:check(member.pos.distance_to(peer.pos)>=1.54,"individuals remain separated")
	check(squad.orders.is_empty() and tank.orders.is_empty(),"mixed movement arrives without congestion deadlock")
	stage.free()
	print("SHOWCASE MOTION: ",checks," checks, ",failures," failures; minimum height ",min_height)
	quit(0 if failures==0 else 1)
