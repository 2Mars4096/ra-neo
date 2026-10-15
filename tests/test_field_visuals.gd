extends SceneTree
const Art=preload("res://scripts/visuals.gd")
const Fields=preload("res://scripts/field_models.gd")
const Motion=preload("res://scripts/unit_animation.gd")
var checks:=0
var failures:Array[String]=[]
class Clock:
	extends RefCounted
	var time:=1.0
	var scenario:Dictionary={"autonomy":true}
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok and not failures.has(message):failures.append(message);printerr("FAIL: ",message)
func vertices(node:Node3D,xf:Transform3D=Transform3D.IDENTITY)->Array[Vector3]:
	var result:Array[Vector3]=[]
	if node is MeshInstance3D:
		for surface in node.mesh.get_surface_count():
			for vertex in node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:result.append(xf*vertex)
	for child in node.get_children():
		check(not child is CollisionObject3D and not child is CollisionShape3D,"art creates no physics")
		if child is Node3D:result.append_array(vertices(child,xf*child.transform))
	return result
func colors(node:Node3D)->Array:
	var result:Array=[]
	if node is MeshInstance3D:
		for surface in node.mesh.get_surface_count():result.append(node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR])
	for child in node.get_children():
		if child is Node3D:result.append_array(colors(child))
	return result
func _init()->void:call_deferred("run")
func run()->void:
	var art=Art.new()
	var stage:=Node3D.new();root.add_child(stage)
	for kind in Fields.FOOTPRINTS:
		var size:Vector2=Fields.FOOTPRINTS[kind]
		var reference:Array=[]
		for team in [0,1,0]:
			# Exercise the shared mutable palette in the opposite faction first.
			var other:=Node3D.new();art.models.build(other,"rifle",1-team);other.free()
			var model:=Node3D.new();stage.add_child(model)
			art.models.build(model,kind,team)
			check(model.get_meta("local_footprint")==Rect2(-size/2,size),kind+" reservation metadata")
			for baked in [false,true]:
				if baked:art.bake_model(model)
				var points:=vertices(model)
				check(not points.is_empty(),kind+" has geometry")
				var bottom:=INF
				for v in points:
					check(absf(v.x)<=size.x/2+0.001 and absf(v.z)<=size.y/2+0.001,kind+" all vertices including ropes within footprint")
					check(v.y>=-0.001,kind+" no subterranean vertices")
					bottom=minf(bottom,v.y)
				check(absf(bottom)<0.001,kind+" grounded")
			var paint:=colors(model)
			if reference.is_empty():reference=paint
			else:check(reference==paint,kind+" neutral colors stable across team build order")
			check(model.find_children("Soldier*","Node3D",true,false).is_empty(),kind+" no cosmetic extra soldiers")
			var u:Dictionary={"kind":kind,"build_left":Fields.BUILD_SECONDS[kind]}
			Fields.sync_construction(model,u)
			check(model.get_node("ConstructionProgress").visible,kind+" initial progress visible")
			u.build_left=Fields.BUILD_SECONDS[kind]*0.5;Fields.sync_construction(model,u)
			check(is_equal_approx(model.get_node("ConstructionProgress").scale.x,0.5),kind+" progress updates")
			for mesh in model.get_meta("field_meshes"):check(mesh.material_override==model.get_meta("construction_material"),kind+" construction ghost")
			u.build_left=0;Fields.sync_construction(model,u)
			check(not model.get_node("ConstructionProgress").visible,kind+" completed progress hidden")
			for mesh in model.get_meta("field_meshes"):check(mesh.material_override==mesh.get_meta("completed_material"),kind+" completed material restored")
			model.free()
		var visual:Node3D=art.make_unit(stage,{"kind":kind,"team":0,"structure":true,"build_left":4.0})
		check(visual.get_node("Model").get_meta("field_kind")==kind,kind+" flagged unit dispatch")
		visual.free()
	var engineer:=Node3D.new();stage.add_child(engineer);art.models.build(engineer,"engineer",0);art.bake_model(engineer)
	check(engineer.get_child_count()==3,"engineer exactly three articulated soldiers")
	var members:Array=[]
	for i in 3:
		check(engineer.has_node("Soldier%d/Upper/EngineerKit"%i),"engineer tools attached to upper articulation")
		members.append({"pos":Vector2(i*0.6,0),"hp":30.0,"travel":0.1,"facing":Vector2(0,-1),"last_shot":-100.0,"last_hit":-100.0,"target":-1,"suppression":0.0,"phase":0.0})
	var u:Dictionary={"id":1,"kind":"engineer","hp":90.0,"pos":Vector2.ZERO,"members":members,"orders":[],"recovering":false,"suppression":0.0,"state":"IDLE","target":-1,"cooldown":0.0,"blocked_time":0.0}
	var clock:=Clock.new()
	var initial:Transform3D=engineer.get_node("Soldier0/LegL").transform
	for frame in 20:
		clock.time+=0.1
		for member in members:member.phase+=0.5;member.pos.y-=0.03
		Motion.pose(engineer,u,clock,0.1)
		for v in vertices(engineer):check(v.y>=-0.04,"active engineer grounded")
	check(engineer.get_node("Soldier0/LegL").transform!=initial,"engineer walking animation active")
	var weapon:Node3D=engineer.get_node("Soldier0/Upper/Weapon")
	members[0].last_shot=clock.time;members[0].target=7
	Motion.pose(engineer,u,clock,0.1)
	check(weapon.position.z>0,"engineer rifle recoil active")
	u.suppression=1.0;Motion.pose(engineer,u,clock,0.1)
	check(engineer.get_node("Soldier0/Upper").position.y<0,"engineer suppression pose active")
	members[1].hp=0;Motion.pose(engineer,u,clock,0.1)
	check(not engineer.get_node("Soldier1").visible,"dead engineer hidden without extra actor")
	members.pop_back();Motion.pose(engineer,u,clock,0.1)
	check(not engineer.get_node("Soldier2").visible,"missing member safely hidden")
	engineer.free()
	var legacy:Node3D=art.make_unit(stage,{"kind":"hq","team":0,"structure":true})
	check(not vertices(legacy.get_node("Model")).is_empty(),"legacy classic structure remains available")
	legacy.free();stage.free()
	print("FIELD VISUALS: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
