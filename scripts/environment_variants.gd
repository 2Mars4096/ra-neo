class_name EnvironmentVariants
extends RefCounted
const Palette=preload("res://scripts/environment_palette.gd")

# Original static assemblies. No placement, collision, cover or simulation side effects.
const VARIANTS = {
	"pipe_rack": ["low_cradle", "tiered"],
	"sandbags": ["straight", "corner"],
	"quay_fender": ["timber_piles", "rubber_panel"],
}
const STEEL = Color("596460")
const WOOD = Color("75644c")

static func local_footprint(kind:String, variant:String)->Rect2:
	if not VARIANTS.has(kind) or not variant in VARIANTS[kind]:return Rect2()
	match kind:
		"pipe_rack":return Rect2(-1.6,-0.7,3.2,1.4)
		"sandbags":return Rect2(-1.3,-0.4,2.6,0.8) if variant=="straight" else Rect2(-1.3,-0.4,2.6,1.9)
		"quay_fender":return Rect2(-1.3,-0.4,2.6,0.8)
	return Rect2()

static func build(art,parent:Node3D,kind:String,variant:String)->Node3D:
	# Unknown pairs fail without creating nodes. Parent must supply a flat local y=0.
	if local_footprint(kind,variant).size==Vector2.ZERO:return null
	var model:=Node3D.new()
	model.name=kind+"_"+variant
	parent.add_child(model)
	match kind:
		"pipe_rack":_pipes(art,model,variant=="tiered")
		"sandbags":_sandbags(art,model,variant=="corner")
		"quay_fender":_fender(art,model,variant=="rubber_panel")
	art.bake_model(model)
	model.set_meta("local_footprint",local_footprint(kind,variant))
	model.set_meta("placement_policy","inside_existing_blocked_parcel")
	model.set_meta("grants_cover",false)
	return model

static func _pipes(art,p:Node3D,tiered:bool)->void:
	# Pipes run along X; steel crossbars support each pipe at its bottom tangent.
	for x in [-1.05,1.05]:
		art.box(p,Vector3(x,0.06,0),Vector3(0.34,0.12,1.2),STEEL)
		for z in [-0.51,0.51]:
			art.box(p,Vector3(x,0.69 if tiered else 0.26,z),Vector3(0.10,1.26 if tiered else 0.40,0.10),STEEL)
		for y in ([0.30,1.02] if tiered else [0.16]):
			art.box(p,Vector3(x,y,0),Vector3(0.16,0.12,1.12),STEEL)
	for y in ([0.56,1.28] if tiered else [0.42]):
		for z in [-0.25,0.25]:
			_pipe(art,p,Vector3(0,y,z),1.5,0.20)

static func _pipe(art,p:Node3D,center:Vector3,half_length:float,radius:float)->void:
	# Hollow annular ends and a dark inner wall distinguish stock pipe from drums/reels.
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 12:
		var a:=TAU*i/12.0;var b:=TAU*(i+1)/12.0
		var oa:=Vector3(0,cos(a)*radius,sin(a)*radius)
		var ob:=Vector3(0,cos(b)*radius,sin(b)*radius)
		var ia:=oa*0.73;var ib:=ob*0.73
		var left:=center+Vector3(-half_length,0,0);var right:=center+Vector3(half_length,0,0)
		_quad(st,left+oa,right+oa,right+ob,left+ob)
		_quad(st,left+ib,right+ib,right+ia,left+ia)
		_quad(st,left+ia,left+oa,left+ob,left+ib)
		_quad(st,right+ib,right+ob,right+oa,right+ia)
	var mesh:=MeshInstance3D.new();mesh.mesh=st.commit()
	mesh.material_override=art.material(Color("858a80"));p.add_child(mesh)

static func _quad(st:SurfaceTool,a:Vector3,b:Vector3,c:Vector3,d:Vector3)->void:
	st.set_normal((c-a).cross(b-a).normalized())
	for v in [a,b,c,a,c,d]:st.add_vertex(v)

static func _sandbags(art,p:Node3D,corner:bool)->void:
	# Three compressed courses, alternating long/short end bags avoid floating offsets.
	for level in 3:
		var y:=0.12+level*0.24
		if level%2==0:
			for x in [-0.9,-0.3,0.3,0.9]:_bag(art,p,Vector3(x,y,0),Vector3(0.60,0.24,0.48))
		else:
			for x in [-0.6,0.0,0.6]:_bag(art,p,Vector3(x,y,0),Vector3(0.60,0.24,0.48))
			for x in [-1.05,1.05]:_bag(art,p,Vector3(x,y,0),Vector3(0.30,0.24,0.48))
		if corner:
			for z in [0.54,1.14]:_bag(art,p,Vector3(-0.96,y,z),Vector3(0.48,0.24,0.60))

static func _bag(art,p:Node3D,pos:Vector3,size:Vector3)->void:
	art.models.box(p,pos,size,Palette.CANVAS)
	# A restrained seam on the exposed face; no random scatter or floating tied ends.
	art.box(p,pos+Vector3(0,0,-size.z/2),Vector3(size.x*0.72,0.018,0.012),Color("5e5944"))

static func _fender(art,p:Node3D,panel:bool)->void:
	# Ground datum is the quay toe; mount +Z against the wall, working face points -Z.
	if panel:
		for x in [-0.85,0.85]:
			art.box(p,Vector3(x,0.08,0.12),Vector3(0.34,0.16,0.50),STEEL)
			art.box(p,Vector3(x,0.72,0.19),Vector3(0.16,1.28,0.16),STEEL)
		art.models.box(p,Vector3(0,0.74,-0.03),Vector3(2.35,1.20,0.34),Palette.RUBBER)
		for x in [-0.85,0,0.85]:
			art.box(p,Vector3(x,0.74,-0.22),Vector3(0.12,1.02,0.06),Color("3a403d"))
	else:
		for x in [-0.95,0,0.95]:
			art.models.box(p,Vector3(x,0.86,0),Vector3(0.24,1.72,0.30),WOOD)
		for y in [0.40,1.18]:
			art.box(p,Vector3(0,y,-0.20),Vector3(2.35,0.22,0.16),WOOD)
			for x in [-0.95,0,0.95]:
				art.models.tube(p,Vector3(x,y,-0.28),Vector3(x,y,-0.30),0.035,STEEL)

# A bounded integration option for the authored warehouse loading platform.
# Call BEFORE architecture batching, while individual mesh bounds are available.
static func try_warehouse_rack(art,building:Node3D,parcel:Rect2,spec:Dictionary)->Node3D:
	if spec.get("design","")!="warehouse":return null
	var facing:String=spec.get("facing","north")
	var across:bool=facing in ["west","east"]
	var depth:float=parcel.size.x if across else parcel.size.y
	if depth<10.0:return null # Smaller loading platforms cannot fit without blocking doors.
	var yaw:float={"north":0.0,"south":PI,"west":PI/2,"east":-PI/2}.get(facing,0.0)
	var rotation:=Basis(Vector3.UP,yaw)
	var origin:=Vector3(parcel.get_center().x,0,parcel.get_center().y)
	# Left end of dock, away from central arched door/office stair; rest on its 0.92 top.
	var local:=Vector3(-1.7,0.92,-depth/2+1.0)
	var pose:=Transform3D(rotation,origin+rotation*local)
	var footprint:=local_footprint("pipe_rack","low_cradle")
	var volume:=AABB(Vector3(footprint.position.x,0.012,footprint.position.y),Vector3(footprint.size.x,0.64,footprint.size.y))
	var world:AABB=pose*volume
	for corner in [footprint.position,Vector2(footprint.end.x,footprint.position.y),footprint.end,Vector2(footprint.position.x,footprint.end.y)]:
		var point:Vector3=pose*Vector3(corner.x,0,corner.y)
		if not parcel.grow(-0.12).has_point(Vector2(point.x,point.z)):return null
	# Conservative whole-part bounds reject walls, crates, rails and all door trim.
	# The platform lies below the raised check volume; a 0.08 horizontal gap is required.
	for part in building.get_children():
		if not part is MeshInstance3D:return null # Unknown hierarchy: fail closed.
		var occupied:AABB=part.transform*part.mesh.get_aabb()
		occupied.position.x-=0.08;occupied.position.z-=0.08
		occupied.size.x+=0.16;occupied.size.z+=0.16
		if world.intersects(occupied):return null
	var model:Node3D=build(art,building,"pipe_rack","low_cradle")
	model.transform=pose
	model.set_meta("support_height",0.92)
	return model
