extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Art=preload("res://scripts/visuals.gd")
const Motion=preload("res://scripts/unit_animation.gd")
var failures:=0
var low:=INF
var radius:=0.0
func check(ok:bool,label:String)->void:
	if not ok:failures+=1;printerr("FAIL: ",label)
func bounds(node:Node3D,xf:Transform3D)->void:
	if node is MeshInstance3D:
		for surface in node.mesh.get_surface_count():
			for v in node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var p:Vector3=xf*v
				low=minf(low,p.y)
				radius=maxf(radius,Vector2(p.x,p.z).length())
	for child in node.get_children():
		if child is Node3D:bounds(child,xf*child.transform)
func _init()->void:call_deferred("run")
func run()->void:
	var sim=Sim.new(false,3)
	var squad=sim.spawn("rifle",0,Vector2(12,48))
	var foe=sim.spawn("rifle",1,Vector2(12,40))
	sim.update_visibility()
	var m:Dictionary=squad.members[0]
	m.travel=0.02
	sim.infantry_combat(squad,0.1)
	check(m.last_shot<0 and m.state=="SETTLING","moving soldier cannot fire a settled shot")
	m.travel=0
	sim.infantry_combat(squad,0.1)
	check(m.posture=="CROUCHED" and m.last_shot<0,"crouch and settle precede fire")
	# Isolate one pinned actor to leave room for an extended prone silhouette.
	for peer in squad.members:
		if peer.index>0:peer.hp=0
	m.suppression=0.75
	sim.time=1
	sim.infantry_combat(squad,0.1)
	check(m.posture=="PRONE" and m.last_shot<0,"pinned isolated soldier drops prone and pauses firing")
	var art=Art.new()
	var stage:=Node3D.new();root.add_child(stage)
	var unit=art.make_unit(stage,squad)
	var model=unit.get_node("Model")
	for frame in 30:
		Motion.pose(model,squad,sim,1.0/30)
		var soldier=model.get_node("Soldier0")
		bounds(soldier,Transform3D.IDENTITY)
	check(low>=-0.04,"posture transition stays above ground")
	check(radius<=1.15,"prone geometry fits reserved footprint")
	m.suppression=0
	m.posture="CROUCHED";m.posture_until=0;m.aim=0;m.cooldown=0;m.travel=0
	for frame in 30:
		sim.time+=0.1
		sim.infantry_combat(squad,0.1)
	check(m.last_shot>1,"settled soldier eventually fires")
	for frame in 40:Motion.pose(model,squad,sim,1.0/30)
	for side in [-1,1]:
		var leg:Node3D=model.get_node("Soldier0/LegL" if side<0 else "Soldier0/LegR")
		var foot_transform:Transform3D=leg.transform*leg.get_node("Knee").transform*leg.get_node("Knee/Foot").transform
		check(foot_transform.origin.x*side>0,"settled feet remain on their own sides")
	stage.free()
	print("STANCE TESTS: ",failures," failures; low=",low," radius=",radius)
	quit(0 if failures==0 else 1)
