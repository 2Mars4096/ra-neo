extends SceneTree
const Art=preload("res://scripts/visuals.gd")
const Terrain=preload("res://scripts/terrain.gd")
const Detail=preload("res://scripts/environment_detail.gd")
const Props=preload("res://scripts/harbor_props.gd")
const Library=preload("res://scripts/asset_library.gd")
const Kit=preload("res://scripts/parcel_kit.gd")
class MissingMask:
	extends RefCounted
	var world_size:=Vector2(16,8)
	var water_mask:Image
	func is_water(p:Vector2)->bool:return p.x<4

var checks:=0
var failures:Array[String]=[]
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok and not failures.has(message):failures.append(message);printerr("FAIL: ",message)
func triangles(node:Node)->int:
	var total:=0
	var mesh:Mesh=node.mesh if node is MeshInstance3D else (node.multimesh.mesh if node is MultiMeshInstance3D else null)
	if mesh!=null:
		for surface in mesh.get_surface_count():
			var a:Array=mesh.surface_get_arrays(surface)
			var count:int=(a[Mesh.ARRAY_INDEX].size() if a[Mesh.ARRAY_INDEX]!=null and not a[Mesh.ARRAY_INDEX].is_empty() else a[Mesh.ARRAY_VERTEX].size())/3
			total+=count*(node.multimesh.instance_count if node is MultiMeshInstance3D else 1)
	for child in node.get_children():total+=triangles(child)
	return total
func inspect(node:Node3D,bounds:Rect2,xf:Transform3D)->void:
	check(not node is CollisionObject3D and not node is CollisionShape3D and not node is Light3D,"render adds no private physics or lights")
	if node is MeshInstance3D:
		for surface in node.mesh.get_surface_count():
			for v in node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var p:Vector3=xf*v
				check(bounds.grow(0.003).has_point(Vector2(p.x,p.z)),"all transformed vertices within compiled AABB: "+str(node.get_parent().name))
	for child in node.get_children():
		if child is Node3D:inspect(child,bounds,xf*child.transform)
func colors(node:Node)->Array:
	var result:Array=[]
	var mesh:Mesh=node.mesh if node is MeshInstance3D else (node.multimesh.mesh if node is MultiMeshInstance3D else null)
	if mesh!=null:
		for surface in mesh.get_surface_count():result.append(mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR])
	for child in node.get_children():result.append_array(colors(child))
	return result
func inspect_props(group:Node3D)->void:
	var placements:Array=group.get_meta("placements")
	var by_id:Dictionary={}
	for entry in placements:
		check(entry.compiled_bounds.grow(0.001).encloses(entry.registry_bounds) and entry.compiled_bounds.size.distance_to(entry.registry_bounds.size)<0.002,"same registry bounds as terrain compiler")
		check(not entry.gameplay_collision_installed,"no private prop physics")
		check(entry.transform.is_equal_approx(Transform3D(Basis(Vector3.UP,entry.yaw),Vector3(entry.pos.x,entry.elevation,entry.pos.y))),"retained placement rotation and elevation")
		if not by_id.has(entry.asset_id):by_id[entry.asset_id]=[]
		by_id[entry.asset_id].append(entry)
	var represented:Dictionary={}
	for batch in group.get_children():
		check(batch is MultiMeshInstance3D,"only instanced render nodes")
		if not batch is MultiMeshInstance3D:continue
		var id:String=batch.get_meta("asset_id");represented[id]=true
		check(by_id.has(id),"batch maps to placements")
		check(batch.multimesh.instance_count==by_id[id].size(),"all placements included per template surface")
		check(not batch.get_meta("gameplay_collision_installed"),"batch adds no physics")
		var spec:=Library.find(id)
		# Headless dummy renderer does not retain GPU instance transforms. Inspect
		# the exact template mesh against each retained CPU placement transform.
		for entry in by_id[id]:
			for surface in batch.multimesh.mesh.get_surface_count():
				for vertex in batch.multimesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
					var local:Vector3=batch.get_meta("template_transform")*vertex
					var allowed:Rect2=preload("res://tests/test_asset_library.gd").visual_bounds(spec,local.y)
					check(allowed.grow(0.04).has_point(Vector2(local.x,local.z)),"template bounded "+id)
					var world:Vector3=entry.transform*local
					var expanded:=Rect2()
					for corner in [allowed.position,Vector2(allowed.end.x,allowed.position.y),allowed.end,Vector2(allowed.position.x,allowed.end.y)]:
						var point:Vector3=entry.transform*Vector3(corner.x,0,corner.y)
						if corner==allowed.position:expanded=Rect2(Vector2(point.x,point.z),Vector2.ZERO)
						else:expanded=expanded.expand(Vector2(point.x,point.z))
					check(expanded.grow(0.04).has_point(Vector2(world.x,world.z)),"placed render bounds "+id)
	check(represented.size()==by_id.size(),"every placement id rendered")

func rotated_bounds(size:Vector2,center:Vector2,degrees:float)->Rect2:
	var r:=Rect2(center,Vector2.ZERO)
	for x in [-0.5,0.5]:
		for y in [-0.5,0.5]:r=r.expand(center+(Vector2(x,y)*size).rotated(-deg_to_rad(degrees)))
	return r
func fixture()->Dictionary:
	return {"id":"harbor_visual_fixture","size":[1024,768],"nav_cell_size":4,"fog_cell_size":8,"mode":"field_ops","style":"showcase","port":false,"shore_x":1024,
		"water_polygons":[[[0,0],[230,0],[280,250],[220,480],[300,768],[0,768]],[[200,270],[650,300],[710,360],[570,410],[200,420]]],
		"blocks":[],"architecture":[],"woods":[[760,80,24,24]],"rubble":[0,0,0,0],"mud":[0,0,0,0],"objectives":[[770,540],[820,240]],
		"roads":{"nodes":{"a":[730,100],"b":[730,650]},"edges":[["a","b",12,"urban street"]]},
		"districts":[{"name":"Dense centre","type":"urban","bounds":[760,200,160,180]},{"name":"Cargo","type":"industry","bounds":[760,400,160,100]},{"name":"Orchards","type":"rural","bounds":[400,500,240,200]},{"name":"Arrival","type":"staging","bounds":[800,550,120,100]}],
		"map_props":[{"asset_id":"quay_bay.existing","position":[700,200],"rotation_degrees":37},{"asset_id":"quay_bay.existing","position":[700,230],"rotation_degrees":-17},{"asset_id":"pickup.single_cab","position":[840,250],"rotation_degrees":27},{"asset_id":"lifebuoy.post","position":[690,260],"rotation_degrees":11}]}
func _init()->void:call_deferred("run")
func run()->void:
	var stage:=Node3D.new();root.add_child(stage)
	var art=Art.new()
	var fallback:Image=art.harbor_water_image(MissingMask.new(),{"nav_cell_size":4})
	check(fallback.get_size()==Vector2i(4,2),"guard fallback bounded at navigation resolution")
	check(fallback.get_pixel(0,0).r==1 and fallback.get_pixel(1,0).r==0,"guard fallback samples terrain classifier")
	var config:=fixture()
	var terrain=Terrain.new(6,config)
	var mask:Image=art.harbor_water_image(terrain,config)
	check(mask==terrain.water_mask,"uses terrain-owned image directly")
	for y in range(0,768,7):
		for x in range(0,1024,7):
			var p:=Vector2(x+0.5,y+0.5)
			var on_edge:=false
			for polygon in terrain.water_polygons:
				for i in polygon.size():
					if Geometry2D.get_closest_point_to_segment(p,polygon[i],polygon[(i+1)%polygon.size()]).distance_to(p)<0.001:on_edge=true
			check(on_edge or (mask.get_pixel(x,y).r>0.5)==terrain.is_water(p),"mask centers match navigation water away from exact polygon edge")
	for p in [Vector2(10,300),Vector2(620,330)]:check(terrain.is_water(p),"open west sea and deep bay")
	check(not terrain.is_water(Vector2(650,500)),"headland remains land")
	check(Detail.land_use_at(terrain,config,Vector2(840,280)).r>0.7,"typed urban district")
	check(Detail.land_use_at(terrain,config,Vector2(840,280)).b==0,"no farmland in urban core")
	check(Detail.land_use_at(terrain,config,Vector2(840,450)).g>0.8,"typed industrial district")
	check(Detail.land_use_at(terrain,config,Vector2(520,600)).b>0.9,"authored rural district")
	check(Detail.land_use_at(terrain,config,Vector2(850,600)).r>0.4,"typed staging district")
	check(Detail.land_use_at(terrain,config,Vector2(730,300))==Color(0,0,0,1),"roads excluded from semantic ground")
	art.make_harbor_surfaces(stage,terrain,config)
	check(triangles(stage)==4,"full 1024x768 land/water requires four triangles")
	var land:MeshInstance3D=stage.get_node("HarborLand")
	var water:MeshInstance3D=stage.get_node("HarborWater")
	check(land.mesh.size==Vector2(1024,768) and water.mesh.size==Vector2(1024,768),"planes span the whole map")
	check(land.material_override.get_shader_parameter("water_mask")==water.material_override.get_shader_parameter("water_mask"),"land/water share one nearest-filter mask")
	check(art.ground_material.get_shader_parameter("land_use_mask").get_size()==Vector2(256,192),"semantic texture bounded at 4m")
	var geometry:=0
	for design in Kit.INTACT+Kit.RUINS:
		for angle in [-31.0,0.0,23.0,90.0]:
			var size:=Vector2(10,8) if design=="warehouse" else Vector2(8,8)
			var bounds:=rotated_bounds(size,Vector2(500,500),angle)
			var spec:Dictionary={"design":design,"facing":"north","source_size":[size.x,size.y],"rotation_degrees":angle}
			var building:Node3D=art.make_authored_building(stage,bounds,3,spec)
			inspect(building,bounds,building.transform)
			check(building.get_child_count()<=6,"rotated prefab remains batched")
			check(building.position==Vector3(500,0,500),"prefab root at compiled AABB center")
			var raw:=Node3D.new()
			if design in Kit.RUINS:preload("res://scripts/ruined_building.gd").build(art,raw,Rect2(-size/2,size),3,spec)
			else:preload("res://scripts/architectural_block.gd").build(art,raw,Rect2(-size/2,size),3,spec)
			check(triangles(raw)==triangles(building),"batching preserves prefab triangles")
			geometry+=triangles(building)
			raw.free();building.free()
	var props:Node3D=Props.build(art,stage,config)
	check(props.get_meta("placements").size()==4,"all authored registry placements retained")
	check(Props.build(art,stage,config)==props,"prop integration idempotent")
	inspect_props(props)
	var quay_batches:=0
	for batch in props.get_children():
		if batch.get_meta("asset_id")=="quay_bay.existing":
			quay_batches+=1
			check(batch.multimesh.instance_count==2,"repeated quays share one mesh per surface")
	check(quay_batches>0,"quay template surfaces present")
	var neutral:=colors(props)
	props.free()
	var enemy:=Node3D.new();art.models.build(enemy,"tank",1);enemy.free()
	props=Props.build(art,stage,config)
	check(colors(props)==neutral,"harbor registry palette independent of last faction")
	props.free();land.free();water.free()
	art.make_harbor_world(stage,terrain,config)
	check(stage.has_node("HarborGroundDetail") and stage.has_node("HarborProps"),"actual harbor world integrates detail/registry")
	check(triangles(stage)<20000,"fixture road/surface geometry bounded")
	print("HARBOR FIXTURE: ",triangles(stage)," static triangles; rotated prefab checks: ",geometry," triangles")
	stage.free()
	# If the map owner has delivered scenario6, exercise its actual authored geometry.
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	if configs.size()>6:
		var actual=Terrain.new(6)
		var world:=Node3D.new();root.add_child(world);art.make_world(world,actual)
		var buildings:Node3D=world.get_node("HarborBuildings")
		var entries:Array=buildings.get_meta("placements")
		check(entries.size()==configs[6].architecture.size(),"all independent architecture entries batched")
		var source_triangles:=0
		for entry in entries:
			var parcel:Node3D=art.make_authored_building(world,entry.compiled_bounds,entry.architecture_index,entry.spec)
			var bounds:Rect2=entry.compiled_bounds
			if entry.spec.has("collision"):
				bounds=rotated_bounds(Vector2(entry.spec.source_size[0],entry.spec.source_size[1]),Vector2(entry.spec.position[0],entry.spec.position[1]),float(entry.spec.get("rotation_degrees",0)))
			inspect(parcel,bounds,parcel.transform)
			check(triangles(parcel)>0,"every authored parcel has geometry")
			source_triangles+=triangles(parcel)
			parcel.free()
		check(triangles(buildings)==source_triangles,"chunk merging preserves all building triangles")
		var map_props:Node3D=world.get_node("HarborProps")
		inspect_props(map_props)
		print("HARBOR AUTHORED: ",entries.size()," buildings, ",map_props.get_meta("placements").size()," props in ",map_props.get_child_count()," batches, ",triangles(world)," static triangles")
		world.free()
	else:print("HARBOR AUTHORED: pending scenario6 data; synthetic full-size fixture verified")
	print("HARBOR VISUALS: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
