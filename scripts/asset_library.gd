class_name EnvironmentAssetLibrary
extends RefCounted

const BUNDLES=["street","rural","waterfront","battlefield","city"]
static var cached:Array=[]

static func entries()->Array:
	if not cached.is_empty():return cached.duplicate(true)
	for bundle in BUNDLES:
		var path:String="res://resources/assets_"+bundle+".json"
		if not FileAccess.file_exists(path):continue
		var data=JSON.parse_string(FileAccess.get_file_as_string(path))
		if not data is Array:continue
		for source in data:
			var spec:Dictionary=source.duplicate(true)
			spec["id"]=str(spec.kind)+"."+str(spec.variant)
			spec["builder"]="res://scripts/assets_"+bundle+".gd"
			spec["status"]="library_ready"
			spec["gameplay_integrated"]=false
			cached.append(spec)
	for spec in preload("res://scripts/assets_existing.gd").specs():
		spec["id"]=str(spec.kind)+"."+str(spec.variant)
		spec["builder"]="res://scripts/assets_existing.gd"
		spec["status"]="implemented"
		spec["gameplay_integrated"]=true
		cached.append(spec)
	for spec in preload("res://scripts/city_buildings.gd").specs():
		spec["id"]=str(spec.kind)+"."+str(spec.variant)
		spec["builder"]="res://scripts/city_buildings.gd"
		spec["status"]="library_ready"
		spec["gameplay_integrated"]=false
		cached.append(spec)
	for kind in ["pipe_rack","sandbags","quay_fender"]:
		var library=preload("res://scripts/environment_variants.gd")
		for variant in library.VARIANTS[kind]:
			var r:Rect2=library.local_footprint(kind,variant)
			cached.append({"id":kind+"."+variant,"kind":kind,"variant":variant,"category":{"pipe_rack":"industry","sandbags":"field_defences","quay_fender":"waterfront"}[kind],"label":(kind+" / "+variant).replace("_"," "),"footprint":[r.position.x,r.position.y,r.size.x,r.size.y],"height":1.8,"placement":["inside_existing_blocked_parcel"],"collision":"solid","cover":false,"builder":"res://scripts/environment_variants.gd","status":"library_ready","gameplay_integrated":kind=="pipe_rack"})
	for spec in cached:
		spec["placement_contract"]={"allowed_contexts":spec.placement,"collision_policy":"whole_footprint_non_traversable_pending_part_integration" if spec.collision=="overhead" else spec.collision,"requires_external_support":spec.kind=="access_ladder","access_zone_required":spec.has("entrance"),"discharge_zone_required":spec.kind=="drain_outfall"}
	return cached.duplicate(true)

static func find(id:String)->Dictionary:
	for spec in entries():
		if spec.id==id:return spec
	return {}

static func build(art,parent:Node3D,id:String)->Node3D:
	var spec:=find(id)
	if spec.is_empty():return null
	var builder=load(spec.builder)
	if builder==null:return null
	var model:Node3D=builder.build(art,parent,spec.kind,spec.variant)
	if model!=null:
		model.set_meta("asset_id",id)
		model.set_meta("asset_spec",spec)
		model.set_meta("gameplay_collision_installed",false)
	return model

static func footprint(id:String,position:Vector2,yaw:float=0.0)->Rect2:
	var spec:=find(id)
	if spec.is_empty():return Rect2()
	var f:Array=spec.footprint
	var local:=Rect2(float(f[0]),float(f[1]),float(f[2]),float(f[3]))
	var corners:=[local.position,Vector2(local.end.x,local.position.y),local.end,Vector2(local.position.x,local.end.y)]
	var bounds:=Rect2(position+corners[0].rotated(-yaw),Vector2.ZERO)
	for corner in corners:bounds=bounds.expand(position+corner.rotated(-yaw))
	return bounds

# Geometry authoring check only. Terrain, sight and tactical cover must still be
# installed in the authoritative map model before a placed asset affects play.
static func placement_issues(id:String,position:Vector2,yaw:float,world:Rect2,reserved:Array,surface:String,supported:bool=true,context:Dictionary={})->Array[String]:
	var issues:Array[String]=[]
	var spec:=find(id)
	if spec.is_empty():return ["Unknown asset"]
	if not position.is_finite() or not is_finite(yaw):return ["Non-finite placement"]
	var bounds:=footprint(id,position,yaw)
	if not world.encloses(bounds):issues.append("Outside map bounds")
	if spec.kind in ["small_boat","barge"]:
		if surface!="water":issues.append("Requires water placement and hull immersion")
	elif surface=="water":issues.append("Requires supported land or waterfront structure")
	if spec.placement_contract.requires_external_support and not supported:
		issues.append("Requires an authored support or anchor")
	var tags:Array=context.get("tags",[])
	if not spec.placement.any(func(tag):return tag in tags):issues.append("Missing compatible placement context")
	if spec.has("entrance"):
		var e:Array=spec.entrance
		var entry:=Vector2(float(e[0]),float(e[1]))
		var normal:=entry.normalized() if entry.length()>0.01 else Vector2.DOWN
		for distance in [0.3,0.8,1.3]:
			var point:Vector2=position+(entry+normal*distance).rotated(-yaw)
			if not context.get("access_zones",[]).any(func(zone):return zone.has_point(point)):
				issues.append("Entrance lacks a connected access zone");break
			if reserved.any(func(zone):return zone.grow(0.3).has_point(point)):
				issues.append("Entrance access is obstructed");break
	if spec.kind=="drain_outfall":
		var f:Array=spec.footprint
		var discharge:=position+Vector2(0,float(f[1])+float(f[3])+0.5).rotated(-yaw)
		if not context.get("drainage_zones",[]).any(func(zone):return zone.has_point(discharge)):
			issues.append("Outlet does not face a receiving drainage zone")
	for exclusion in reserved:
		if bounds.intersects(exclusion):issues.append("Overlaps reserved corridor or occupied footprint");break
	return issues

static func render_bounds(model:Node3D)->AABB:
	var result:=AABB();var found:=false
	var nodes:Array=[model]
	while not nodes.is_empty():
		var node:Node=nodes.pop_back()
		nodes.append_array(node.get_children())
		if node is MeshInstance3D and node.mesh!=null:
			var box:AABB=model.global_transform.affine_inverse()*node.global_transform*node.mesh.get_aabb()
			result=result.merge(box) if found else box;found=true
	return result
