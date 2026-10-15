extends SceneTree

const Library = preload("res://scripts/assets_rural.gd")
const Visuals = preload("res://scripts/visuals.gd")
const EXPECTED = ["orchard","hedgerow","irrigation_ditch","tractor","farm_trailer","grass_patch","reed_bed","broken_tree"]
const EPS = 0.001

class RawArt extends "res://scripts/visuals.gd":
	func bake_model(_model:Node3D)->void:pass

var checks := 0
var failures:Array[String] = []

func _init()->void:call_deferred("run")

func check(ok:bool,label:String)->void:
	checks += 1
	if not ok and not failures.has(label):
		failures.append(label)
		printerr("FAIL: ",label)

func vertices(node:Node3D,pose:Transform3D=Transform3D.IDENTITY)->PackedVector3Array:
	var result := PackedVector3Array()
	var local:Transform3D = pose*node.transform
	if node is MeshInstance3D:
		for surface in node.mesh.get_surface_count():
			for v in node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:result.append(local*v)
	for child in node.get_children():
		check(child is Node3D and not child is CollisionObject3D and not child is CollisionShape3D and not child is Light3D,"visual nodes only")
		if child is Node3D:result.append_array(vertices(child,local))
	return result

func triangles(node:Node3D)->int:
	var result:int = 0
	if node is MeshInstance3D:
		for surface in node.mesh.get_surface_count():
			var arrays:Array = node.mesh.surface_get_arrays(surface)
			# Unindexed ArrayMesh surfaces expose a null index slot, not an empty array.
			var indices = arrays[Mesh.ARRAY_INDEX]
			var count:int = arrays[Mesh.ARRAY_VERTEX].size()
			if indices is PackedInt32Array and not indices.is_empty():count = indices.size()
			check(count%3==0,"triangle surface has complete triples")
			result += int(count/3)
	for child in node.get_children():
		if child is Node3D:result += triangles(child)
	return result

func verify_bounds(points:PackedVector3Array,spec:Dictionary,label:String)->void:
	var f:Array = spec.footprint
	var volume := AABB(Vector3(f[0],0,f[1]),Vector3(f[2],spec.height,f[3]))
	var minimum_y:float = INF
	check(not points.is_empty(),label+" nonempty")
	for v in points:
		check(v.is_finite(),label+" finite vertex")
		check(volume.grow(EPS).has_point(v),label+" full local XYZ bounds")
		minimum_y = minf(minimum_y,v.y)
	check(absf(minimum_y)<EPS,label+" grounded datum")
	# Check every actual vertex at cardinal and oblique yaw, including translated parents.
	for yaw in [0.0,PI/2,PI,3*PI/2,0.37,-0.83]:
		var pose := Transform3D(Basis(Vector3.UP,yaw),Vector3(19,2.3,-11))
		var rotated:AABB = pose*volume
		for v in points:
			check(rotated.grow(EPS).has_point(pose*v),label+" rotated full XYZ bounds")
			check(volume.grow(EPS).has_point(pose.affine_inverse()*(pose*v)),label+" oriented footprint")

func raw_color(mesh:MeshInstance3D)->Color:
	var material:Material = mesh.material_override
	return material.albedo_color if material is StandardMaterial3D else material.get_shader_parameter("paint")

func verify_ditch(raw:Node3D,lined:bool)->void:
	var bed:MeshInstance3D = raw.get_node("ChannelBed")
	var bed_color:Color = raw_color(bed)
	if not lined:
		for label in ["EarthBankNorth","EarthBankSouth"]:
			var bank:MeshInstance3D = raw.get_node(label)
			var base_min:float = INF
			var base_max:float = -INF
			var top_min:float = INF
			var top_max:float = -INF
			for v in bank.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				if is_zero_approx(v.y):
					base_min = minf(base_min,v.z)
					base_max = maxf(base_max,v.z)
				else:
					top_min = minf(top_min,v.z)
					top_max = maxf(top_max,v.z)
			check(base_max-top_max>0.2 and top_min-base_min>0.2,"earth bank slopes on both faces "+label)
			check(top_max-top_min>0.15,"earth bank has distinct flat crest "+label)
			check(raw_color(bank).get_luminance()-bed_color.get_luminance()>0.10,"damp bed darker than earth crest "+label)
	else:
		check(bed_color.get_luminance()>0.55,"light concrete bed")
		var lining_count:int = 0
		var bank_joints:int = 0
		var bed_joints:int = 0
		for child in raw.get_children():
			if not child is MeshInstance3D or child==bed:continue
			var color:Color = raw_color(child)
			var bounds:AABB = child.mesh.get_aabb()
			if color.get_luminance()>0.55 and bounds.size.y>0.3:lining_count += 1
			if color==Library.CONCRETE_JOINT:
				if bounds.size.y>0.3:bank_joints += 1
				elif child.position.y>0.05:bed_joints += 1
		check(lining_count==8,"eight light concrete bank pours")
		check(bank_joints==6 and bed_joints==3,"visible joints cross both banks and bed")

func verify_neutral_palette(stage:Node3D,metadata:Array,baseline:Dictionary)->void:
	# Cold material caches and warm caches in both team build orders.
	for order in [[1,0,1],[0,1,0]]:
		var art = Visuals.new()
		for team in order:
			var unit := Node3D.new()
			stage.add_child(unit)
			art.models.build(unit,"tank",team)
			unit.free()
			check(art.models.olive!=Library.Palette.OLIVE,"fixture mutates faction palette")
			for spec in metadata:
				var key:String = spec.kind+"/"+spec.variant
				var model:Node3D = Library.build(art,stage,spec.kind,spec.variant)
				var colors:PackedColorArray = model.get_child(0).mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
				check(colors==baseline[key],"neutral vertex color and finish after team "+str(team)+" "+key)
				model.free()

func run()->void:
	var art = Visuals.new()
	var raw_art = RawArt.new()
	var stage := Node3D.new()
	root.add_child(stage)
	var metadata:Array = Library.specs()
	check(metadata.size()==16,"sixteen metadata rows")
	var seen:Dictionary = {}
	var signatures:Dictionary = {}
	var baseline:Dictionary = {}
	for spec in metadata:
		for key in ["kind","variant","category","label","footprint","height","placement","collision","cover","description"]:
			check(spec.has(key),"metadata field "+key)
		var key:String = spec.kind+"/"+spec.variant
		check(not seen.has(key),"unique "+key)
		seen[key] = true
		check(spec.kind in EXPECTED,"known kind "+key)
		check(spec.category in ["rural","vegetation"],"category "+key)
		check(spec.collision in ["solid","flat","overhead"] and spec.cover==false,"descriptive classification only "+key)
		check(spec.placement is Array and not spec.placement.is_empty(),"placement tags "+key)
		check(spec.footprint.size()==4 and spec.footprint[2]>0 and spec.footprint[3]>0 and spec.height>0,"positive bounds "+key)
		var model:Node3D = Library.build(art,stage,spec.kind,spec.variant)
		var raw:Node3D = Library.build(raw_art,stage,spec.kind,spec.variant)
		check(model!=null and raw!=null,"valid build "+key)
		if model==null or raw==null:continue
		check(model.transform==Transform3D.IDENTITY,"local origin "+key)
		check(model.get_meta("grants_cover")==false and model.get_meta("placement_policy")=="library_only","no gameplay claims "+key)
		check(model.get_child_count()==1 and model.get_child(0) is MeshInstance3D,"single rigid batch "+key)
		var mesh:MeshInstance3D = model.get_child(0)
		check(mesh.material_override==art.merged_paint,"shared merged material "+key)
		check(mesh.mesh.get_surface_count()==1,"single batch surface "+key)
		var points:PackedVector3Array = vertices(model)
		verify_bounds(points,spec,key+" baked")
		verify_bounds(vertices(raw),spec,key+" raw")
		if spec.kind=="irrigation_ditch":verify_ditch(raw,spec.variant=="lined_sluice")
		check(triangles(model)==triangles(raw),"batch preserves all triangles "+key)
		check(points.size()<30000,"bounded vertex budget "+key)
		if not signatures.has(spec.kind):signatures[spec.kind] = []
		signatures[spec.kind].append(hash(points))
		var material_count:int = art.materials.size()+art.models.palette.size()
		var repeat:Node3D = Library.build(art,stage,spec.kind,spec.variant)
		check(material_count==art.materials.size()+art.models.palette.size(),"cached palette reused "+key)
		check(repeat.get_child(0).material_override==mesh.material_override,"batch material identity reused "+key)
		check(vertices(repeat)==points,"deterministic repeated geometry "+key)
		var arrays:Array = mesh.mesh.surface_get_arrays(0)
		var colors:PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		baseline[key] = colors
		check(colors.size()==points.size(),"baked vertex paint present "+key)
		art.bake_model(model)
		check(vertices(model)==points,"second bake preserves vertices "+key)
		check(model.get_child(0).mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]==colors,"second bake preserves paint "+key)
		repeat.free()
		raw.free()
		model.free()
	verify_neutral_palette(stage,metadata,baseline)
	for kind in EXPECTED:
		check(signatures.has(kind) and signatures[kind].size()==2,"two variants "+kind)
		if signatures.has(kind) and signatures[kind].size()==2:
			check(signatures[kind][0]!=signatures[kind][1],"distinct geometry "+kind)
	check(Library.build(art,stage,"missing","missing")==null,"invalid kind rejected")
	for kind in EXPECTED:check(Library.build(art,stage,kind,"missing")==null,"invalid variant rejected "+kind)
	check(stage.get_child_count()==0,"invalid input leaves no nodes")
	stage.free()
	print("ASSETS RURAL: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
