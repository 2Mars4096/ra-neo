extends SceneTree
const Library=preload("res://scripts/assets_waterfront.gd")
const Visuals=preload("res://scripts/visuals.gd")
const EXPECTED={
	"pipe_stack":["paired_large","pyramid"],"gantry":["fixed","travelling"],
	"tyre_fender":["single","double"],"railings":["straight","corner"],
	"access_ladder":["wall","guarded"],"mooring_rope":["coil","bollard"],
	"small_boat":["rowing","outboard"],"barge":["flat_deck","cargo_hold"],
	"lifebuoy":["post","cabinet"],
}
var checks:=0
var failures:Array[String]=[]
func _init()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok and not failures.has(label):
		failures.append(label)
		printerr("FAIL: ",label)

func vertices(node:Node3D,pose:Transform3D=Transform3D.IDENTITY)->PackedVector3Array:
	var result:=PackedVector3Array()
	var next:Transform3D=pose*node.transform
	check(not node is CollisionObject3D and not node is Light3D,"no physics bodies or lights")
	if node is MeshInstance3D:
		for surface in node.mesh.get_surface_count():
			var arrays:Array=node.mesh.surface_get_arrays(surface)
			for v in arrays[Mesh.ARRAY_VERTEX]:result.append(next*v)
	for child in node.get_children():
		if child is Node3D:result.append_array(vertices(child,next))
	return result

func first_hit(mesh:Mesh,from:Vector3,to:Vector3)->float:
	var result:=INF
	for surface in mesh.get_surface_count():
		var arrays:Array=mesh.surface_get_arrays(surface)
		var points:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		# Unindexed ArrayMesh surfaces expose a null slot, not an empty packed array.
		var indices:=PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX]!=null:indices=arrays[Mesh.ARRAY_INDEX]
		var count:int=indices.size() if not indices.is_empty() else points.size()
		for i in range(0,count,3):
			var a:Vector3=points[indices[i] if not indices.is_empty() else i]
			var b:Vector3=points[indices[i+1] if not indices.is_empty() else i+1]
			var c:Vector3=points[indices[i+2] if not indices.is_empty() else i+2]
			var hit=Geometry3D.segment_intersects_triangle(from,to,a,b,c)
			if hit!=null:result=minf(result,from.distance_to(hit))
	return result

func raw_model(art,spec:Dictionary)->Node3D:
	var node:=Node3D.new()
	match spec.kind:
		"pipe_stack":Library._pipes(art,node,spec.variant=="pyramid")
		"gantry":Library._gantry(art,node,spec.variant=="travelling")
		"tyre_fender":Library._fender(art,node,spec.variant=="double")
		"railings":Library._railings(art,node,spec.variant=="corner")
		"access_ladder":Library._ladder(art,node,spec.variant=="guarded")
		"mooring_rope":Library._rope(art,node,spec.variant=="bollard")
		"small_boat":Library._boat(art,node,spec.variant=="outboard")
		"barge":Library._barge(art,node,spec.variant=="cargo_hold")
		"lifebuoy":Library._lifebuoy(art,node,spec.variant=="cabinet")
	return node

func bounds_check(points:PackedVector3Array,spec:Dictionary,label:String)->void:
	var f:Array=spec.footprint
	var bounds:=AABB(Vector3(f[0],0,f[1]),Vector3(f[2],spec.height,f[3]))
	var minimum_y:=INF
	for v in points:
		check(v.is_finite(),label+" finite vertices")
		check(bounds.grow(0.001).has_point(v),label+" complete xyz bounds")
		minimum_y=minf(minimum_y,v.y)
	check(absf(minimum_y)<0.001,label+" bottom datum zero")
	# All points, all axes, quarter turns and oblique rotations after translation.
	for yaw in [0.0,PI/2,PI,3*PI/2,0.37,-0.81]:
		var pose:=Transform3D(Basis(Vector3.UP,yaw),Vector3(17,2,-23))
		var transformed:AABB=pose*bounds
		for v in points:check(transformed.grow(0.001).has_point(pose*v),label+" rotated xyz bounds")

func run()->void:
	# Both topology paths must detect real hits as well as misses; a broken ray
	# helper must not silently make the hollow-part checks pass.
	var fixture:=SurfaceTool.new()
	fixture.begin(Mesh.PRIMITIVE_TRIANGLES)
	for point in [Vector3(-1,-1,0),Vector3(0,1,0),Vector3(1,-1,0)]:fixture.add_vertex(point)
	var unindexed:ArrayMesh=fixture.commit()
	check(unindexed.surface_get_arrays(0)[Mesh.ARRAY_INDEX]==null,"fixture exercises null index slot")
	check(is_equal_approx(first_hit(unindexed,Vector3(0,0,1),Vector3(0,0,-1)),1.0),"unindexed ray detects triangle")
	check(is_inf(first_hit(unindexed,Vector3(2,0,1),Vector3(2,0,-1))),"unindexed ray misses triangle")
	fixture.index()
	var indexed:ArrayMesh=fixture.commit()
	check(indexed.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size()==3,"fixture exercises indexed topology")
	check(is_equal_approx(first_hit(indexed,Vector3(0,0,1),Vector3(0,0,-1)),1.0),"indexed ray detects triangle")
	check(is_inf(first_hit(indexed,Vector3(2,0,1),Vector3(2,0,-1))),"indexed ray misses triangle")
	var art=Visuals.new()
	var stage:=Node3D.new();root.add_child(stage)
	var catalog:Array=Library.specs()
	check(catalog.size()==18,"18 metadata entries")
	var seen:Dictionary={}
	var signatures:Dictionary={}
	for spec in catalog:
		var key:String=spec.kind+"/"+spec.variant
		check(not seen.has(key),"unique "+key);seen[key]=true
		check(EXPECTED.has(spec.kind) and spec.variant in EXPECTED[spec.kind],"expected pair "+key)
		check(spec.category in ["industry","waterfront"],key+" category")
		check(spec.footprint.size()==4 and spec.footprint[2]>0 and spec.footprint[3]>0 and spec.height>0,key+" dimensions")
		check(spec.cover==false and spec.collision in ["solid","flat","overhead"],key+" metadata classification")
		check(spec.label is String and not spec.label.is_empty() and spec.description is String and not spec.description.is_empty(),key+" labelled description")
		check(spec.placement is Array and not spec.placement.is_empty(),key+" placement")
		for placement in spec.placement:check(placement is String,key+" placement strings")
		if spec.kind in ["small_boat","barge"]:check("immersion" in spec.description and "datum y=0" in spec.description,key+" immersion documented")
		var model:Node3D=Library.build(art,stage,spec.kind,spec.variant)
		check(model!=null,key+" builds")
		if model==null:continue
		check(model.transform==Transform3D.IDENTITY,key+" local origin")
		check(model.get_meta("grants_cover")==false and model.get_meta("placement_policy")=="library_only",key+" library only")
		check(model.get_child_count()==1 and model.get_child(0) is MeshInstance3D,key+" one static batch")
		var points:PackedVector3Array=vertices(model)
		check(points.size()>0 and points.size()<30000,key+" geometry budget")
		bounds_check(points,spec,key+" baked")
		signatures[key]=hash(points)
		for child in model.get_children():
			if child is MeshInstance3D:
				check(child.material_override==art.merged_paint,key+" shared batch material")
				check(child.mesh.get_surface_count()==1,key+" one surface")
		var raw:Node3D=raw_model(art,spec)
		var raw_points:PackedVector3Array=vertices(raw)
		bounds_check(raw_points,spec,key+" raw")
		# Every raw coordinate must survive topology normalization / batching.
		var baked_coordinates:Dictionary={}
		for point in points:baked_coordinates[point.snapped(Vector3.ONE*0.0001)]=true
		for point in raw_points:check(baked_coordinates.has(point.snapped(Vector3.ONE*0.0001)),key+" bake preserves coordinates")
		var ring_count:=0
		for child in raw.get_children():
			if child is MeshInstance3D and child.mesh is TorusMesh:
				ring_count+=1
				check(is_inf(first_hit(child.mesh,Vector3(0,-2,0),Vector3(0,2,0))),key+" torus has open centre")
		if spec.kind in ["tyre_fender","lifebuoy","mooring_rope"]:check(ring_count>0,key+" actual rings")
		if spec.kind=="pipe_stack":
			for child in raw.get_children():
				if child is MeshInstance3D and child.mesh is ArrayMesh:
					var center:Vector3=child.mesh.get_aabb().get_center()
					check(is_inf(first_hit(child.mesh,center-Vector3(3,0,0),center+Vector3(3,0,0))),key+" pipe bore open end to end")
		if spec.kind=="small_boat" or (spec.kind=="barge" and spec.variant=="cargo_hold"):
			# Centre ray avoids seats/ribs and must reach the inner floor rather than a cap.
			var distance:=INF
			for child in raw.get_children():
				if child is MeshInstance3D:
					var inverse:Transform3D=child.transform.affine_inverse()
					distance=minf(distance,first_hit(child.mesh,inverse*Vector3(0,3,-0.35),inverse*Vector3(0,-1,-0.35)))
			check(absf(distance-2.86)<0.005,key+" open hull reaches floor")
		var material_count:int=art.materials.size()+art.models.palette.size()
		var repeat:Node3D=Library.build(art,stage,spec.kind,spec.variant)
		check(art.materials.size()+art.models.palette.size()==material_count,key+" material cache reuse")
		check(hash(vertices(repeat))==signatures[key],key+" deterministic repeat")
		art.bake_model(model)
		check(hash(vertices(model))==signatures[key],key+" repeat batching preserves geometry")
		repeat.free();raw.free();model.free()
	for kind in EXPECTED:
		for variant in EXPECTED[kind]:check(seen.has(kind+"/"+variant),"complete "+kind+"/"+variant)
		check(signatures.get(kind+"/"+EXPECTED[kind][0])!=signatures.get(kind+"/"+EXPECTED[kind][1]),kind+" variant geometry differs")
		check(Library.build(art,stage,kind,"missing")==null,kind+" invalid variant")
	check(Library.build(art,stage,"missing","missing")==null,"invalid kind")
	check(stage.get_child_count()==0,"invalid builds create no nodes")
	stage.free()
	print("WATERFRONT ASSETS: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
