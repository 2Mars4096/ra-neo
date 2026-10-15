extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Art=preload("res://scripts/visuals.gd")
const Motion=preload("res://scripts/unit_animation.gd")
var checks:=0
var failures:Array[String]=[]
func check(value:bool,message:String) -> void:
	checks+=1
	if not value and not failures.has(message):
		failures.append(message)
		printerr("FAIL: ",message)
func bounds(node:Node3D,xf:Transform3D) -> Vector3:
	var result:=Vector3(0,INF,-INF)
	if node is MeshInstance3D:
		for surface in node.mesh.get_surface_count():
			for vertex in node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var p:Vector3=xf*vertex
				result.x=maxf(result.x,Vector2(p.x,p.z).length())
				result.y=minf(result.y,p.y)
				result.z=maxf(result.z,p.y)
	for child in node.get_children():
		if child is Node3D:
			var b:=bounds(child,xf*child.transform)
			result=Vector3(maxf(result.x,b.x),minf(result.y,b.y),maxf(result.z,b.z))
	return result
func _init() -> void:call_deferred("run")
func run() -> void:
	var sim=Sim.new(false,0)
	var art=Art.new()
	var stage:=Node3D.new()
	root.add_child(stage)
	for kind in sim.definitions:
		var u=sim.spawn(kind,0,Vector2(90,60) if kind=="boat" else Vector2(15,60))
		var enemy=sim.spawn("drone",1,Vector2(40,20))
		enemy.seen_by[0]=true
		u.target=enemy.id
		var visual=art.make_unit(stage,u)
		var model:Node3D=visual.get_node("Model")
		for frame in 36:
			sim.time=frame*0.13
			u.pos+=Vector2(0.1,0)
			u.suppression=1.0 if frame>18 else 0.0
			u.last_shot=sim.time if frame%8==0 else u.last_shot
			u.last_hit=sim.time if frame%9==0 else u.last_hit
			enemy.pos=u.pos+Vector2.from_angle(frame*TAU/36)*10
			preload("res://scripts/infantry.gd").move(u,sim,0.13)
			for member in u.members:
				member.target=enemy.id
				member.last_hit=u.last_hit
				member.last_shot=u.last_shot-member.index*0.07
			Motion.pose(model,u,sim,0.13)
			var b:=bounds(model,model.transform)
			check(b.x<=float(sim.definitions[kind].radius)+0.001,"animated envelope: "+kind)
			if sim.definitions[kind].domain=="air":check(b.y+float(sim.definitions[kind].altitude)>5.4,"air animation clears props: "+kind)
			else:check(b.y>=-0.04,"animation stays above ground: "+kind)
		visual.free()
		u.hp=0;enemy.hp=0
	var engagement=Sim.new(false,0)
	var tank=engagement.spawn("tank",0,Vector2(10,50))
	var target=engagement.spawn("tank",1,Vector2(10,40))
	engagement.tick(0.1)
	check(target.hp==target.max_hp and tank.state=="AIMING","new target requires visible preparation")
	for i in 8:engagement.tick(0.1)
	check(target.hp<target.max_hp,"prepared weapon fires")
	check(engagement.terrain.ground_speed(Vector2(50,60))<engagement.terrain.ground_speed(Vector2(15,60)),"mud slows ground travel")
	check(engagement.terrain.cover(Vector2(15,30)),"ruins provide cover")
	print("ANIMATION TESTS: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
