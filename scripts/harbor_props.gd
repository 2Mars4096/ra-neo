class_name HarborProps
extends RefCounted

const Library=preload("res://scripts/asset_library.gd")
const Palette=preload("res://scripts/environment_palette.gd")

# Input contract: asset_id (or id), position:[x,z], rotation_degrees; compiled
# entries may supply pos:Vector2, yaw:radians and bounds:Rect2 instead. The same
# registry footprint is used by the terrain compiler. No physics/cover here.
static func layout(config:Dictionary)->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	for source in config.get("map_props",[]):
		var id:String=source.get("asset_id",source.get("id",""))
		var point=source.get("pos",source.get("position",[0,0]))
		var pos:Vector2=point if point is Vector2 else Vector2(point[0],point[1])
		var yaw:float=float(source.get("yaw",deg_to_rad(float(source.get("rotation_degrees",0)))))
		var bounds:Rect2=Library.footprint(id,pos,yaw)
		var compiled=source.get("bounds",bounds)
		if compiled is Array:compiled=Rect2(compiled[0],compiled[1],compiled[2],compiled[3])
		result.append({"asset_id":id,"pos":pos,"yaw":yaw,"bounds":compiled,"registry_bounds":bounds,"elevation":float(source.get("elevation",0.0))})
	return result

# Metadata is a placement array on the root, not a node per placement. Each
# batch records its asset id and surface transform; entries retain collision
# bounds and instance transforms for inspection without duplicating geometry.
static func build(art,parent:Node3D,config:Dictionary)->Node3D:
	if parent.has_node("HarborProps"):return parent.get_node("HarborProps")
	var group:=Node3D.new();group.name="HarborProps";parent.add_child(group)
	var entries:=layout(config)
	var by_id:Dictionary={}
	for entry in entries:
		entry["compiled_bounds"]=entry.bounds
		entry["gameplay_collision_installed"]=false
		entry["transform"]=Transform3D(Basis(Vector3.UP,entry.yaw),Vector3(entry.pos.x,entry.elevation,entry.pos.y))
		if not by_id.has(entry.asset_id):by_id[entry.asset_id]=[]
		by_id[entry.asset_id].append(entry)
	group.set_meta("placements",entries)
	var staging:=Node3D.new()
	var saved:Array=[art.models.olive,art.models.edge,art.models.canvas,art.models.marking]
	art.models.olive=Palette.OLIVE;art.models.edge=Palette.EDGE
	art.models.canvas=Palette.CANVAS;art.models.marking=Palette.MARKING
	for id in by_id:
		var template:Node3D=Library.build(art,staging,id)
		if template==null:
			push_error("Unknown harbor map asset: "+id)
			continue
		_instance_surfaces(group,template,Transform3D.IDENTITY,by_id[id],id)
	staging.free()
	art.models.olive=saved[0];art.models.edge=saved[1]
	art.models.canvas=saved[2];art.models.marking=saved[3]
	return group

static func _instance_surfaces(group:Node3D,node:Node3D,ancestor:Transform3D,entries:Array,id:String)->void:
	var transform:Transform3D=ancestor*node.transform
	if node is MeshInstance3D and node.mesh!=null:
		for surface in node.mesh.get_surface_count():
			var mesh:=ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,node.mesh.surface_get_arrays(surface))
			var material:Material=node.get_active_material(surface)
			mesh.surface_set_material(0,material)
			var multi:=MultiMesh.new()
			multi.transform_format=MultiMesh.TRANSFORM_3D
			multi.mesh=mesh;multi.instance_count=entries.size()
			for i in entries.size():multi.set_instance_transform(i,entries[i].transform*transform)
			var instance:=MultiMeshInstance3D.new()
			instance.name=id.replace(".","_")+"_surface";instance.multimesh=multi
			instance.set_meta("asset_id",id)
			instance.set_meta("template_transform",transform)
			instance.set_meta("gameplay_collision_installed",false)
			group.add_child(instance)
	for child in node.get_children():
		if child is Node3D:_instance_surfaces(group,child,transform,entries,id)
