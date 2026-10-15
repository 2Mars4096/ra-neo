extends SceneTree
const Library=preload("res://scripts/environment_variants.gd")
const Visuals=preload("res://scripts/visuals.gd")
var checks:=0
var failures:Array[String]=[]
func _init()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok and not failures.has(label):failures.append(label);printerr("FAIL: ",label)
func run()->void:
	var art=Visuals.new()
	var stage:=Node3D.new();root.add_child(stage)
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/environment_catalog.json"))
	for kind in Library.VARIANTS:
		var signatures:Array[int]=[]
		for variant in Library.VARIANTS[kind]:
			var bounds:Rect2=Library.local_footprint(kind,variant)
			var model:Node3D=Library.build(art,stage,kind,variant)
			check(model!=null,"valid build")
			check(model.get_child_count()==1 and model.get_child(0) is MeshInstance3D,"one static batch")
			check(model.get_meta("grants_cover")==false,"no implicit cover")
			var mesh:MeshInstance3D=model.get_child(0)
			check(mesh.material_override==art.merged_paint,"shared cached batch material")
			var minimum_y:=INF
			var vertices:PackedVector3Array=mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			signatures.append(hash(vertices))
			check(vertices.size()<12000,"bounded geometry budget")
			for v in vertices:
				check(bounds.grow(0.001).has_point(Vector2(v.x,v.z)),"local footprint "+kind+"/"+variant)
				check(v.y>=-0.001 and v.y<2.0,"above datum and below two units")
				minimum_y=minf(minimum_y,v.y)
			check(absf(minimum_y)<0.001,"assembly contacts ground")
			# World rotation containment, including oblique placement inside a manager parcel.
			for yaw in [0.0,PI/2,0.37]:
				var transform:=Transform3D(Basis(Vector3.UP,yaw),Vector3(20,0,30))
				var world:=Rect2(Vector2(20,30),Vector2.ZERO)
				for corner in [bounds.position,Vector2(bounds.end.x,bounds.position.y),bounds.end,Vector2(bounds.position.x,bounds.end.y)]:
					world=world.expand(Vector2(20,30)+corner.rotated(-yaw))
				for v in vertices:
					var p:Vector3=transform*v
					check(world.grow(0.001).has_point(Vector2(p.x,p.z)),"rotated footprint")
			var category:String="industry" if kind=="pipe_rack" else ("field_defences" if kind=="sandbags" else "waterfront")
			check(catalog[category].library_ready.has(kind+"/"+variant),"catalogue library parity")
			var material_count:int=art.materials.size()+art.models.palette.size()
			var repeat:Node3D=Library.build(art,stage,kind,variant)
			check(art.materials.size()+art.models.palette.size()==material_count,"repeat uses cached palette")
			repeat.free();model.free()
		check(signatures[0]!=signatures[1],"variant geometry differs")
	check(Library.build(art,stage,"missing","missing")==null,"unknown kind rejected")
	check(Library.build(art,stage,"pipe_rack","missing")==null,"unknown variant rejected")
	check(stage.get_child_count()==0,"invalid input creates no nodes")
	# Every loose first-course bag contacts the datum; subsequent courses touch the prior one.
	var raw:=Node3D.new();stage.add_child(raw)
	Library._sandbags(art,raw,true)
	var bags:=0
	for part in raw.get_children():
		if part.material_override is StandardMaterial3D:continue # attached seam
		bags+=1
		var bottom:float=part.position.y+part.mesh.get_aabb().position.y
		check(absf(bottom/0.24-roundf(bottom/0.24))<0.001,"bag course support height")
	check(bags==19,"all corner bags checked")
	stage.free()
	print("ENVIRONMENT VARIANTS: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
