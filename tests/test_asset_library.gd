extends SceneTree
const Library=preload("res://scripts/asset_library.gd")
const Art=preload("res://scripts/visuals.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok and label not in failures:failures.append(label);printerr("FAIL: ",label)
func _init()->void:call_deferred("run")
func meshes(node:Node)->Array:
	var result:Array=[]
	if node is MeshInstance3D:result.append(node)
	for child in node.get_children():result.append_array(meshes(child))
	return result
# Collision remains the small ground footprint. Permit only specifically
# authored elevated visual overhangs, never arbitrary footprint growth.
static func visual_bounds(spec:Dictionary,height:float=INF)->Rect2:
	var f:Array=spec.footprint
	var bounds:=Rect2(f[0],f[1],f[2],f[3])
	if spec.get("builder","")=="res://scripts/assets_city.gd":
		if spec.kind=="tree" and height>1.0:bounds=bounds.grow(3.1)
		elif spec.id=="lamp.boulevard_double" and height>4.2:bounds=bounds.grow(1.15)
		elif spec.id=="portal_crane.rail" and height>=4.7:bounds=bounds.expand(Vector2(0,10.2))
	return bounds

func run()->void:
	var specs:=Library.entries()
	var expected:Dictionary={};var expected_categories:Dictionary={}
	for bundle in Library.BUNDLES:
		var source:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/assets_"+bundle+".json"))
		for item in source:
			expected[item.kind+"."+item.variant]=true;expected_categories[item.category]=true
	for item in preload("res://scripts/assets_existing.gd").specs()+preload("res://scripts/city_buildings.gd").specs():
		expected[item.kind+"."+item.variant]=true;expected_categories[item.category]=true
	var variants=preload("res://scripts/environment_variants.gd")
	for kind in ["pipe_rack","sandbags","quay_fender"]:
		for variant in variants.VARIANTS[kind]:expected[kind+"."+variant]=true
	for category in ["industry","field_defences","waterfront"]:expected_categories[category]=true
	check(specs.size()==expected.size(),"all manifest and adapter models registered")
	check(specs.size()==100+38+preload("res://scripts/city_buildings.gd").DESIGNS.size(),"100 original, 38 city decor, all city building families")
	for id in expected:check(not Library.find(id).is_empty(),"registered manifest id "+id)
	var ids:Dictionary={};var categories:Dictionary={};var totals:Dictionary={}
	var stage:=Node3D.new();root.add_child(stage);var art=Art.new()
	for spec in specs:
		check(not ids.has(spec.id),"unique id "+spec.id);ids[spec.id]=true
		categories[spec.category]=true
		check(spec.footprint.size()==4 and spec.footprint[2]>0 and spec.footprint[3]>0,"valid bounds "+spec.id)
		check((spec.height>0 or (spec.height==0 and spec.collision=="flat")) and spec.collision in ["solid","flat","overhead"],"valid geometry contract "+spec.id)
		check(not spec.placement.is_empty(),"placement context "+spec.id)
		var model:=Library.build(art,stage,spec.id)
		check(model!=null,"build "+spec.id)
		if model==null:continue
		check(not model.get_meta("gameplay_collision_installed",true),"library does not silently install physics "+spec.id)
		var nodes:=meshes(model);check(not nodes.is_empty(),"visible geometry "+spec.id)
		var f:Array=spec.footprint
		if spec.builder=="res://scripts/assets_city.gd":
			check(model.get_meta("local_footprint")==Rect2(f[0],f[1],f[2],f[3]),"visual overhang never changes collision "+spec.id)
		var measured:=Library.render_bounds(model)
		if measured.end.y>float(spec.height)+0.05:print("HEIGHT CONTRACT: ",spec.id," declared=",spec.height," measured=",measured.end.y)
		var vertices:=0
		for mesh in nodes:
			for surface in mesh.mesh.get_surface_count():
				for vertex in mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
					var local:Vector3=model.global_transform.affine_inverse()*mesh.global_transform*vertex
					check(visual_bounds(spec,local.y).grow(0.04).has_point(Vector2(local.x,local.z)),"bounded render footprint "+spec.id)
					check(local.y>=-0.04 and local.y<=float(spec.height)+0.05,"vertical bounds "+spec.id)
					vertices+=1
		totals[spec.id]=vertices
		model.free()
	check(categories.size()==expected_categories.size(),"all declared categories represented")
	for category in expected_categories:check(categories.has(category),"registered category "+category)
	check(Library.build(art,stage,"missing.id")==null,"invalid ID rejected")
	var id:String=specs[0].id if not specs.is_empty() else "missing.id"
	check(not Library.placement_issues(id,Vector2(-100,-100),0,Rect2(0,0,50,50),[],"land").is_empty(),"out-of-map placement rejected")
	check(not Library.placement_issues(id,Vector2(10,10),0,Rect2(0,0,50,50),[Rect2(0,0,20,20)],"land").is_empty(),"occupied corridor rejected")
	stage.free()
	FileAccess.open("res://artifacts/asset-library-checks.json",FileAccess.WRITE).store_string(JSON.stringify({"entries":specs.size(),"categories":categories.keys(),"checks":checks,"failures":failures,"vertices":totals},"  "))
	print("ASSET LIBRARY: ",checks," checks, ",failures.size()," failures; ",specs.size()," models")
	quit(0 if failures.is_empty() else 1)
