class_name AssetsWaterfront
extends RefCounted
const Palette=preload("res://scripts/environment_palette.gd")

# Original library geometry only. Metadata collision is a placement classification,
# never a physics body, navigation blocker, or cover grant.
const DATA_PATH = "res://resources/assets_waterfront.json"
const STOCK = preload("res://scripts/environment_variants.gd")
const WOOD = Color("75644c")
const METAL = Color("596460")

static func specs()->Array:
	var data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	return data if data is Array else []

static func build(art,parent:Node3D,kind:String,variant:String)->Node3D:
	var spec:Dictionary = {}
	for entry in specs():
		if entry.kind == kind and entry.variant == variant:
			spec = entry
			break
	if spec.is_empty():return null
	var model:=Node3D.new()
	model.name=kind+"_"+variant
	parent.add_child(model)
	match kind:
		"pipe_stack":_pipes(art,model,variant=="pyramid")
		"gantry":_gantry(art,model,variant=="travelling")
		"tyre_fender":_fender(art,model,variant=="double")
		"railings":_railings(art,model,variant=="corner")
		"access_ladder":_ladder(art,model,variant=="guarded")
		"mooring_rope":_rope(art,model,variant=="bollard")
		"small_boat":_boat(art,model,variant=="outboard")
		"barge":_barge(art,model,variant=="cargo_hold")
		"lifebuoy":_lifebuoy(art,model,variant=="cabinet")
	art.bake_model(model)
	var f:Array=spec.footprint
	model.set_meta("local_footprint",Rect2(f[0],f[1],f[2],f[3]))
	model.set_meta("grants_cover",false)
	model.set_meta("placement_policy","library_only")
	return model

static func _pipes(art,p:Node3D,pyramid:bool)->void:
	for x in [-1.15,1.15]:
		art.box(p,Vector3(x,0.10,0),Vector3(0.28,0.20,1.70),WOOD)
		for z in [-0.78,0.78]:
			art.box(p,Vector3(x,0.28,z),Vector3(0.28,0.24,0.12),WOOD)
	if pyramid:
		for z in [-0.50,0.0,0.50]:STOCK._pipe(art,p,Vector3(0,0.45,z),1.65,0.25)
		for z in [-0.25,0.25]:STOCK._pipe(art,p,Vector3(0,0.8830127,z),1.65,0.25)
		STOCK._pipe(art,p,Vector3(0,1.3160254,0),1.65,0.25)
	else:
		for z in [-0.39,0.39]:STOCK._pipe(art,p,Vector3(0,0.59,z),1.85,0.39)

static func _beam(art,p:Node3D,a:Vector3,b:Vector3,width:float,color:Color)->void:
	var part:MeshInstance3D=art.box(p,(a+b)/2,Vector3(width,a.distance_to(b),width),color)
	var direction:Vector3=(b-a).normalized()
	part.quaternion=Quaternion(Vector3.UP,direction)

static func _gantry(art,p:Node3D,travelling:bool)->void:
	for x in [-2.3,2.3]:
		if travelling:
			for z in [-0.70,0.70]:
				var wheel:MeshInstance3D=art.models.tube(p,Vector3(x-0.14,0.20,z),Vector3(x+0.14,0.20,z),0.20,Palette.RUBBER)
				wheel.mesh.radial_segments=12
			art.box(p,Vector3(x,0.42,0),Vector3(0.48,0.20,1.9),METAL)
		else:
			art.box(p,Vector3(x,0.10,0),Vector3(0.72,0.20,1.8),METAL)
		art.box(p,Vector3(x,1.9,0),Vector3(0.22,3.4,0.26),METAL)
		for z in [-0.75,0.75]:_beam(art,p,Vector3(x,0.46 if travelling else 0.20,z),Vector3(x,2.2,0),0.10,METAL)
		_beam(art,p,Vector3(x,2.7,0),Vector3(x-signf(x)*0.8,3.5,0),0.10,METAL)
	# Recognisable I section, supported by both columns.
	for y in [3.52,3.86]:art.box(p,Vector3(0,y,0),Vector3(5.1,0.10,0.40),METAL)
	art.box(p,Vector3(0,3.69,0),Vector3(5.1,0.24,0.10),METAL)
	var hx:float=0.85 if travelling else -0.55
	art.box(p,Vector3(hx,3.39,0),Vector3(0.48,0.22,0.46),Palette.OLIVE)
	for x in [-0.10,0.10]:art.models.tube(p,Vector3(hx+x,3.28,0),Vector3(hx+x,2.25,0),0.018,Palette.STEEL)
	art.box(p,Vector3(hx,2.22,0),Vector3(0.30,0.18,0.22),METAL)
	_arc(art,p,Vector3(hx,2.00,0),0.15,0.026,0,PI*1.65,Palette.STEEL)

static func _torus(art,p:Node3D,center:Vector3,outer:float,inner:float,vertical:bool,color:Color)->void:
	var mesh:=TorusMesh.new()
	mesh.inner_radius=inner
	mesh.outer_radius=outer
	mesh.rings=24
	mesh.ring_segments=8
	var part:MeshInstance3D=art.models.mesh_node(p,mesh,center,color)
	if vertical:part.rotation.x=PI/2

static func _arc(art,p:Node3D,center:Vector3,radius:float,thickness:float,start:float,stop:float,color:Color)->void:
	for i in 16:
		var a:float=lerpf(start,stop,i/16.0)
		var b:float=lerpf(start,stop,(i+1)/16.0)
		art.models.tube(p,center+Vector3(cos(a),sin(a),0)*radius,center+Vector3(cos(b),sin(b),0)*radius,thickness,color)

static func _fender(art,p:Node3D,double:bool)->void:
	var positions:Array=[-0.56,0.56] if double else [0.0]
	for x in positions:
		art.box(p,Vector3(x,0.08,0.30),Vector3(0.38,0.16,0.46),METAL)
		art.box(p,Vector3(x,0.74,0.40),Vector3(0.13,1.32,0.13),METAL)
		_torus(art,p,Vector3(x,0.60,0),0.52,0.28,true,Palette.RUBBER)
		for dx in [-0.20,0.20]:
			art.models.tube(p,Vector3(x+dx,0.96,0),Vector3(x+dx,1.34,0.4),0.022,Palette.STEEL)
		art.box(p,Vector3(x,1.34,0.38),Vector3(0.55,0.10,0.16),METAL)

static func _rail_run(art,p:Node3D,a:Vector3,b:Vector3,skip_first:bool=false)->void:
	for fraction in [0.0,0.5,1.0]:
		if skip_first and fraction==0.0:continue
		var point:Vector3=a.lerp(b,fraction)
		art.box(p,point+Vector3(0,0.04,0),Vector3(0.22,0.08,0.22),METAL)
		art.models.tube(p,point+Vector3(0,0.08,0),point+Vector3(0,1.10,0),0.042,METAL)
	for y in [0.52,1.10]:art.models.tube(p,a+Vector3(0,y,0),b+Vector3(0,y,0),0.032,METAL)
	var toe:MeshInstance3D=art.box(p,(a+b)/2+Vector3(0,0.15,0),Vector3(a.distance_to(b),0.16,0.04),METAL)
	toe.rotation.y=-atan2(b.z-a.z,b.x-a.x)

static func _railings(art,p:Node3D,corner:bool)->void:
	_rail_run(art,p,Vector3(-1.4,0,0),Vector3(1.4,0,0))
	if corner:_rail_run(art,p,Vector3(1.4,0,0),Vector3(1.4,0,1.8),true)

static func _ladder(art,p:Node3D,guarded:bool)->void:
	for x in [-0.33,0.33]:
		art.box(p,Vector3(x,0.04,0),Vector3(0.16,0.08,0.22),METAL)
		art.models.tube(p,Vector3(x,0.08,0),Vector3(x,3.1,0),0.042,METAL)
		for y in [0.30,1.50,2.70]:art.models.tube(p,Vector3(x,y,0),Vector3(x,y,0.30),0.035,METAL)
	for i in 10:art.models.tube(p,Vector3(-0.33,0.20+i*0.28,0),Vector3(0.33,0.20+i*0.28,0),0.032,METAL)
	if guarded:
		# Cage is open toward its wall (+Z); hoop ends attach to rails.
		for y in [1.55,2.25,2.95]:
			for i in 16:
				var a:float=PI*i/16.0
				var b:float=PI*(i+1)/16.0
				art.models.tube(p,Vector3(cos(a)*0.33,y,-sin(a)*0.65),Vector3(cos(b)*0.33,y,-sin(b)*0.65),0.025,METAL)
		for a in [PI/4,PI/2,3*PI/4]:
			art.models.tube(p,Vector3(cos(a)*0.33,1.55,-sin(a)*0.65),Vector3(cos(a)*0.33,2.95,-sin(a)*0.65),0.018,METAL)

static func _rope(art,p:Node3D,bollard:bool)->void:
	if bollard:
		art.box(p,Vector3(0,0.06,0),Vector3(1.15,0.12,0.66),METAL)
		for x in [-0.32,0.32]:
			art.models.tube(p,Vector3(x,0.12,0),Vector3(x,0.75,0),0.12,Palette.STEEL)
			art.models.tube(p,Vector3(x-0.20,0.68,0),Vector3(x+0.20,0.68,0),0.07,METAL)
		for y in [0.24,0.31,0.38]:
			for x in [-0.32,0.32]:_torus(art,p,Vector3(x,y,0),0.18,0.12,false,Palette.CANVAS)
			for z in [-0.15,0.15]:art.models.tube(p,Vector3(-0.32,y,z),Vector3(0.32,y,z),0.03,Palette.CANVAS)
	else:
		for radius in [0.16,0.24,0.32,0.40,0.48]:_torus(art,p,Vector3(0,0.04,0),radius+0.04,radius-0.04,false,Palette.CANVAS)
		for radius in [0.24,0.32,0.40]:_torus(art,p,Vector3(0,0.12,0),radius+0.04,radius-0.04,false,Palette.CANVAS)
		art.models.tube(p,Vector3(0.40,0.04,0.30),Vector3(0.77,0.04,0.30),0.035,Palette.CANVAS)

static func _quad(st:SurfaceTool,a:Vector3,b:Vector3,c:Vector3,d:Vector3)->void:
	# Outward mathematical normal, reversed winding for Godot clockwise faces.
	_triangle(st,a,b,c)
	_triangle(st,a,c,d)

static func _triangle(st:SurfaceTool,a:Vector3,b:Vector3,c:Vector3)->void:
	st.set_normal((b-a).cross(c-a).normalized())
	for v in [a,c,b]:st.add_vertex(v)

static func _hull(art,p:Node3D,width:float,length:float,height:float,pointed:bool)->void:
	# Bow -Z. Open top; outer chine, inner wall, rim and raised floor are real geometry.
	var outline:Array=[Vector2(-width*0.5,length*0.5),Vector2(width*0.5,length*0.5),Vector2(width*0.5,-length*0.30),Vector2(width*0.20,-length*0.5),Vector2(-width*0.20,-length*0.5),Vector2(-width*0.5,-length*0.30)]
	if not pointed:outline=[Vector2(-width/2,length/2),Vector2(width/2,length/2),Vector2(width/2,-length/2),Vector2(-width/2,-length/2)]
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in outline.size():
		var a:Vector2=outline[i];var b:Vector2=outline[(i+1)%outline.size()]
		var ba:=Vector3(a.x*0.76,0,a.y*0.88);var bb:=Vector3(b.x*0.76,0,b.y*0.88)
		var ta:=Vector3(a.x,height,a.y);var tb:=Vector3(b.x,height,b.y)
		var ia:=Vector3(a.x*0.90,height,a.y*0.96);var ib:=Vector3(b.x*0.90,height,b.y*0.96)
		var fa:=Vector3(a.x*0.70,0.14,a.y*0.84);var fb:=Vector3(b.x*0.70,0.14,b.y*0.84)
		_quad(st,ba,bb,tb,ta)
		_quad(st,ta,tb,ib,ia)
		_quad(st,ia,ib,fb,fa)
		_triangle(st,Vector3(0,0.14,0),fa,fb)
		_triangle(st,Vector3.ZERO,bb,ba)
		art.models.tube(p,ta,tb,0.045,WOOD)
	art.models.mesh_node(p,st.commit(),Vector3.ZERO,Palette.OLIVE)

static func _boat(art,p:Node3D,outboard:bool)->void:
	_hull(art,p,1.65,4.0,0.72,true)
	for z in ([-0.80,0.50] if outboard else [-0.85,0.20,1.15]):
		for x in [-0.47,0.47]:art.box(p,Vector3(x,0.30,z),Vector3(0.08,0.32,0.22),WOOD)
		art.box(p,Vector3(0,0.49,z),Vector3(1.24,0.10,0.28),WOOD)
	if outboard:
		art.box(p,Vector3(0,0.77,2.05),Vector3(0.35,0.16,0.32),METAL)
		art.models.box(p,Vector3(0,0.93,2.23),Vector3(0.40,0.44,0.44),Palette.STEEL)
		art.box(p,Vector3(0,0.42,2.28),Vector3(0.12,0.70,0.13),METAL)
		art.models.tube(p,Vector3(0,0.15,2.27),Vector3(0,0.15,2.50),0.06,METAL)
		art.box(p,Vector3(0,0.15,2.50),Vector3(0.32,0.07,0.04),METAL)
		art.models.tube(p,Vector3(0,0.84,2.15),Vector3(-0.35,0.84,1.65),0.025,Palette.RUBBER)
	else:
		for x in [-0.50,0.50]:
			art.models.tube(p,Vector3(x,0.59,-1.20),Vector3(x,0.59,1.10),0.025,WOOD)
			art.box(p,Vector3(x,0.59,1.25),Vector3(0.15,0.045,0.50),WOOD)
		for x in [-0.78,0.78]:_torus(art,p,Vector3(x,0.79,0.20),0.08,0.045,true,METAL)

static func _barge(art,p:Node3D,cargo:bool)->void:
	_hull(art,p,3.6,7.0,0.90,false)
	if cargo:
		# Open hold with raised hatch coaming and cross ribs; no cargo hides the interior.
		for x in [-1.40,1.40]:art.box(p,Vector3(x,0.66,0),Vector3(0.14,1.04,5.6),METAL)
		for z in [-2.73,2.73]:art.box(p,Vector3(0,0.66,z),Vector3(2.8,1.04,0.14),METAL)
		for z in [-2.0,-1.0,0.0,1.0,2.0]:art.box(p,Vector3(0,0.19,z),Vector3(2.52,0.08,0.09),METAL)
	else:
		art.box(p,Vector3(0,0.84,0),Vector3(3.40,0.12,6.8),WOOD)
		for z in [-2.7,-1.8,-0.9,0,0.9,1.8,2.7]:art.box(p,Vector3(0,0.905,z),Vector3(3.36,0.01,0.02),METAL)
	for x in [-1.45,1.45]:
		for z in [-3.12,3.12]:
			art.box(p,Vector3(x,0.81,z),Vector3(0.34,0.18,0.34),METAL)
			art.models.tube(p,Vector3(x,0.90,z),Vector3(x,1.20,z),0.065,METAL)
			art.models.tube(p,Vector3(x-0.15,1.15,z),Vector3(x+0.15,1.15,z),0.04,METAL)

static func _lifebuoy(art,p:Node3D,cabinet:bool)->void:
	art.box(p,Vector3(0,0.06,0.12),Vector3(0.60,0.12,0.52),METAL)
	art.box(p,Vector3(0,0.76,0.20),Vector3(0.10,1.4,0.10),METAL)
	if cabinet:
		art.box(p,Vector3(0,1.30,0.22),Vector3(1.0,1.12,0.08),Palette.OLIVE)
		for x in [-0.48,0.48]:art.box(p,Vector3(x,1.30,0.06),Vector3(0.06,1.12,0.32),METAL)
		for y in [0.77,1.83]:art.box(p,Vector3(0,y,0.06),Vector3(0.96,0.06,0.32),METAL)
	else:art.box(p,Vector3(0,1.60,0.09),Vector3(0.16,0.08,0.30),METAL)
	_torus(art,p,Vector3(0,1.30,-0.04),0.43,0.27,true,Palette.SAFETY_ORANGE)
	for angle in [0.0,PI/2,PI,3*PI/2]:
		var center:=Vector3(cos(angle)*0.35,1.30+sin(angle)*0.35,-0.12)
		var band:MeshInstance3D=art.box(p,center,Vector3(0.15,0.07,0.025),Palette.SAFETY_WHITE)
		band.rotation.z=angle
		art.models.tube(p,Vector3(cos(angle)*0.40,1.30+sin(angle)*0.40,-0.04),Vector3(cos(angle)*0.455,1.30+sin(angle)*0.455,-0.04),0.012,Palette.CANVAS)
	_torus(art,p,Vector3(0,1.30,-0.04),0.465,0.445,true,Palette.CANVAS)
