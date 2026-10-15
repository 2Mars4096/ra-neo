class_name AssetsRural
extends RefCounted

# Original static library assets; metres, Y up, vehicles face -Z. No placement effects.
const Palette = preload("res://scripts/environment_palette.gd")
const DATA = "res://resources/assets_rural.json"
const WOOD = Color("75644c")
const LEAF = Color("555a40")
const LEAF_LIGHT = Color("76785a")
const SOIL = Color("5e5944")
const DAMP_BED = Color("393a2e")
const CONCRETE = Color("aaa792")
const CONCRETE_JOINT = Color("686958")

static func specs()->Array:
	var data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	return data if data is Array else []

static func build(art,parent:Node3D,kind:String,variant:String)->Node3D:
	var spec:Dictionary = {}
	for entry in specs():
		if entry.kind == kind and entry.variant == variant:
			spec = entry
			break
	if spec.is_empty():return null
	var model := Node3D.new()
	model.name = kind + "_" + variant
	parent.add_child(model)
	match kind:
		"orchard":_orchard(art,model,variant == "trained_row")
		"hedgerow":_hedge(art,model,variant == "laid_bank")
		"irrigation_ditch":_ditch(art,model,variant == "lined_sluice")
		"tractor":_tractor(art,model,variant == "cab_utility")
		"farm_trailer":_trailer(art,model,variant == "grain_tipper")
		"grass_patch":_grass(art,model,variant == "dry_tussocks")
		"reed_bed":_reeds(art,model,variant == "cattails")
		"broken_tree":_broken(art,model,variant == "fallen_bough")
	art.bake_model(model)
	var f:Array = spec.footprint
	model.set_meta("local_footprint",Rect2(f[0],f[1],f[2],f[3]))
	model.set_meta("height",spec.height)
	model.set_meta("grants_cover",false)
	model.set_meta("placement_policy","library_only")
	return model

static func _beam(art,p:Node3D,a:Vector3,b:Vector3,r:float,color:Color,tip:float=-1.0)->void:
	var node:MeshInstance3D = art.models.tube(p,a,b,r,color,tip)
	# UnitModels infers canvas finish from its mutable faction color; pin it locally.
	if color == Palette.CANVAS:node.material_override = art.models.mat(color,0.12)

static func _crown(art,p:Node3D,center:Vector3,size:Vector3,seed_value:int)->void:
	# Closed asymmetric lobes, not spherical tree heads or transparent foliage cards.
	var rings:Array = []
	for layer in 4:
		var ring:Array[Vector3] = []
		var widths:Array = [0.30,1.0,0.82,0.16]
		for i in 8:
			var angle:float = TAU*i/8.0
			var irregular:float = 0.86 + 0.14*sin(float(i*7+seed_value))
			ring.append(Vector3(cos(angle)*size.x*0.5*float(widths[layer])*irregular,
				(float(layer)/3.0-0.5)*size.y,
				sin(angle)*size.z*0.5*float(widths[layer])*irregular))
		rings.append(ring)
	var node:MeshInstance3D = art.models.shell(p,rings,LEAF if seed_value%2 == 0 else LEAF_LIGHT)
	node.position = center

static func _orchard(art,p:Node3D,trained:bool)->void:
	for x in [-2.2,0.0,2.2]:
		var base := Vector3(x,0,0)
		_beam(art,p,base,base+Vector3(0,1.65,0),0.13,WOOD,0.07)
		for side in [-1.0,1.0]:
			var tip := base+Vector3(side*0.57,1.9,0.12*side)
			_beam(art,p,base+Vector3(0,0.85,0),tip,0.075,WOOD,0.025)
			_crown(art,p,tip+Vector3(0,0.16,0),Vector3(0.98,0.9,0.7 if trained else 1.2),int(x*10+side))
		if not trained:
			for z in [-0.53,0.53]:
				_beam(art,p,base+Vector3(0,1.1,0),base+Vector3(0,1.8,z),0.055,WOOD,0.02)
				_crown(art,p,base+Vector3(0,1.9,z),Vector3(1.0,0.8,0.95),int(z*10))
		else:
			art.box(p,base+Vector3(0.25,0.92,0.18),Vector3(0.07,1.84,0.07),WOOD)
	if trained:
		for y in [0.8,1.5]:_beam(art,p,Vector3(-3.15,y,0.18),Vector3(3.15,y,0.18),0.018,Palette.STEEL)
		for x in [-3.15,3.15]:art.box(p,Vector3(x,0.9,0.18),Vector3(0.12,1.8,0.12),WOOD)

static func _hedge(art,p:Node3D,laid:bool)->void:
	if laid:art.box(p,Vector3(0,0.12,0),Vector3(4.6,0.24,1.1),SOIL)
	for i in 7:
		var x:float = -1.95+i*0.65
		var bottom:float = 0.24 if laid else 0.0
		art.box(p,Vector3(x,bottom+0.04,0),Vector3(0.12,0.08,0.12),WOOD)
		_beam(art,p,Vector3(x,bottom+0.04,0),Vector3(x+0.18,0.85,0),0.065,WOOD,0.025)
		_crown(art,p,Vector3(x,0.88 if laid else 0.75,0),Vector3(0.98,0.86 if laid else 1.12,0.9),i)
		if laid:_beam(art,p,Vector3(x,0.32,-0.25),Vector3(x+0.52,0.69,-0.25),0.04,WOOD,0.02)
	if laid:
		for x in [-2.0,-0.65,0.65,2.0]:art.box(p,Vector3(x,0.68,-0.45),Vector3(0.07,1.36,0.07),WOOD)

static func _bank(art,p:Node3D,x0:float,x1:float,z:float,color:Color)->MeshInstance3D:
	# Closed earth/lining section: broad toe, narrow crest, sloped inner/outer faces.
	var half_length:float = (x1-x0)*0.5
	var node:MeshInstance3D = art.models.shell(p,[
		[Vector3(-half_length,0,-0.38),Vector3(half_length,0,-0.38),Vector3(half_length,0,0.38),Vector3(-half_length,0,0.38)],
		[Vector3(-half_length,0.36,-0.10),Vector3(half_length,0.36,-0.10),Vector3(half_length,0.36,0.10),Vector3(-half_length,0.36,0.10)]
	],color)
	node.position = Vector3((x0+x1)*0.5,0,z)
	return node

static func _ditch(art,p:Node3D,lined:bool)->void:
	# Bounded flat-datum assembly above y=0; no terrain excavation or water surface.
	var bed:MeshInstance3D = art.box(p,Vector3(0,0.025,0),Vector3(4.8,0.05,1.25),CONCRETE if lined else DAMP_BED)
	bed.name = "ChannelBed"
	for z in [-0.61,0.61]:
		if lined:
			# Separate concrete pours with full-section dark mortar joints, not steel walls.
			var start:float = -2.4
			for joint in [-1.6,0.0,1.6]:
				_bank(art,p,start,joint-0.025,z,CONCRETE)
				_bank(art,p,joint-0.025,joint+0.025,z,CONCRETE_JOINT)
				start = joint+0.025
			_bank(art,p,start,2.4,z,CONCRETE)
		else:
			var bank:MeshInstance3D = _bank(art,p,-2.4,2.4,z,SOIL)
			bank.name = "EarthBankNorth" if z<0 else "EarthBankSouth"
			for x in [-1.8,-0.6,0.6,1.8]:
				for j in 3:_blade(art,p,Vector3(x+0.035*j,0.36,z),0.12+0.015*j,float(j)*TAU/3.0,false)
	if lined:
		for x in [-1.6,0,1.6]:art.box(p,Vector3(x,0.052,0),Vector3(0.05,0.004,0.50),CONCRETE_JOINT)
		for z in [-0.67,0.67]:art.box(p,Vector3(1.5,0.57,z),Vector3(0.12,1.14,0.12),Palette.STEEL)
		art.box(p,Vector3(1.5,1.07,0),Vector3(0.16,0.14,1.46),Palette.STEEL)
		art.box(p,Vector3(1.5,0.46,0),Vector3(0.08,0.78,1.18),Palette.OLIVE)
		_beam(art,p,Vector3(1.5,0.78,0),Vector3(1.5,1.28,0),0.027,Palette.STEEL)
		art.box(p,Vector3(1.5,1.28,0),Vector3(0.4,0.05,0.05),WOOD)

static func _wheel(art,p:Node3D,x:float,z:float,r:float,width:float)->void:
	_beam(art,p,Vector3(x-width/2,r,z),Vector3(x+width/2,r,z),r,Palette.RUBBER)
	var outer:float = x+signf(x)*(width/2+0.008)
	_beam(art,p,Vector3(outer-signf(x)*0.025,r,z),Vector3(outer,r,z),r*0.48,Palette.STEEL)
	# Broad agricultural tread blocks, bounded by the declared footprint.
	for i in 10:
		var angle:float = TAU*i/10.0
		var block:MeshInstance3D = art.box(p,Vector3(x,r+cos(angle)*(r-0.025),z+sin(angle)*(r-0.025)),Vector3(width+0.025,0.05,0.15),Palette.RUBBER)
		block.rotation.x = angle

static func _tractor(art,p:Node3D,cab:bool)->void:
	for x in [-0.78,0.78]:_wheel(art,p,x,0.68,0.69,0.38)
	for x in [-0.64,0.64]:_wheel(art,p,x,-1.04,0.43,0.25)
	art.box(p,Vector3(0,0.66,-0.12),Vector3(0.9,0.26,2.55),Palette.STEEL)
	for z in [-1.04,0.68]:
		var axle_y:float = 0.43 if z<0 else 0.69
		_beam(art,p,Vector3(-0.78,axle_y,z),Vector3(0.78,axle_y,z),0.09,Palette.STEEL)
	art.box(p,Vector3(0,0.54,-1.04),Vector3(0.28,0.23,0.23),Palette.STEEL)
	art.models.box(p,Vector3(0,1.13,-0.68),Vector3(0.85,0.68,1.44),Palette.OLIVE)
	art.box(p,Vector3(0,1.12,-1.415),Vector3(0.70,0.44,0.03),Palette.RUBBER)
	for x in [-0.24,-0.12,0.0,0.12,0.24]:art.box(p,Vector3(x,1.12,-1.44),Vector3(0.025,0.4,0.035),Palette.STEEL)
	_beam(art,p,Vector3(0.30,1.42,-0.6),Vector3(0.30,2.02,-0.6),0.047,Palette.STEEL)
	art.box(p,Vector3(0,0.99,0.50),Vector3(0.92,0.12,1.0),Palette.STEEL)
	art.box(p,Vector3(0,1.23,0.68),Vector3(0.42,0.33,0.4),Palette.RUBBER)
	art.box(p,Vector3(0,1.51,0.85),Vector3(0.43,0.36,0.09),Palette.RUBBER)
	_beam(art,p,Vector3(0,1.0,0.16),Vector3(0,1.55,0.02),0.04,Palette.STEEL)
	art.box(p,Vector3(0,1.55,0.02),Vector3(0.32,0.04,0.16),Palette.RUBBER)
	for x in [-0.70,0.70]:
		art.box(p,Vector3(x,1.43,0.66),Vector3(0.40,0.08,1.13),Palette.OLIVE)
		art.box(p,Vector3(x*0.72,1.14,0.66),Vector3(0.06,0.58,1.02),Palette.OLIVE)
		art.box(p,Vector3(x,0.56,0.02),Vector3(0.33,0.10,0.4),Palette.STEEL)
	if cab:
		for x in [-0.49,0.49]:
			for z in [-0.03,1.1]:art.box(p,Vector3(x,1.65,z),Vector3(0.07,1.3,0.07),Palette.STEEL)
		art.box(p,Vector3(0,1.93,-0.03),Vector3(0.91,0.6,0.035),Palette.GLASS)
		art.box(p,Vector3(0,1.93,1.1),Vector3(0.91,0.6,0.035),Palette.GLASS)
		for x in [-0.49,0.49]:art.box(p,Vector3(x,1.93,0.54),Vector3(0.025,0.6,1.04),Palette.GLASS)
		art.box(p,Vector3(0,2.33,0.54),Vector3(1.16,0.12,1.43),Palette.OLIVE)
	else:
		for x in [-0.43,0.43]:art.box(p,Vector3(x,1.69,1.0),Vector3(0.08,1.42,0.08),Palette.STEEL)
		art.box(p,Vector3(0,2.36,1.0),Vector3(0.94,0.08,0.08),Palette.STEEL)
	art.box(p,Vector3(0,0.53,1.39),Vector3(0.22,0.1,0.4),Palette.STEEL)

static func _trailer(art,p:Node3D,tipper:bool)->void:
	for z in ([0.15,1.13] if tipper else [0.65]):
		for x in [-0.95,0.95]:_wheel(art,p,x,z,0.48,0.28)
		_beam(art,p,Vector3(-0.95,0.48,z),Vector3(0.95,0.48,z),0.09,Palette.STEEL)
		for x in [-0.58,0.58]:art.box(p,Vector3(x,0.58,z),Vector3(0.16,0.16,0.58),Palette.STEEL)
	for x in [-0.58,0.58]:art.box(p,Vector3(x,0.69,0),Vector3(0.12,0.2,3.32),Palette.STEEL)
	art.box(p,Vector3(0,0.88,0),Vector3(1.85,0.18,3.4),WOOD)
	for x in [-0.68,0.68]:_beam(art,p,Vector3(x,0.63,-1.45),Vector3(0,0.53,-2.6),0.07,Palette.STEEL)
	art.box(p,Vector3(0,0.26,-2.14),Vector3(0.08,0.52,0.08),Palette.STEEL)
	art.box(p,Vector3(0,0.035,-2.14),Vector3(0.32,0.07,0.30),Palette.STEEL)
	if tipper:
		for x in [-0.90,0.90]:
			art.box(p,Vector3(x,1.43,0),Vector3(0.09,1.0,3.4),Palette.OLIVE)
			for z in [-1.55,-0.5,0.5,1.55]:art.box(p,Vector3(x*1.07,1.43,z),Vector3(0.07,1.05,0.08),Palette.STEEL)
		for z in [-1.66,1.66]:art.box(p,Vector3(0,1.43,z),Vector3(1.8,1.0,0.08),Palette.OLIVE)
		_beam(art,p,Vector3(0,0.42,-0.9),Vector3(0,0.78,-0.3),0.08,Palette.STEEL)
	else:
		for z in [-1.58,1.58]:
			for x in [-0.85,0.85]:art.box(p,Vector3(x,1.27,z),Vector3(0.08,0.7,0.08),WOOD)
			for y in [1.12,1.48]:art.box(p,Vector3(0,y,z),Vector3(1.8,0.13,0.07),WOOD)
		for z in [-1.2,-0.6,0,0.6,1.2]:art.box(p,Vector3(0,0.9775,z),Vector3(1.73,0.015,0.025),SOIL)

static func _blade(art,p:Node3D,base:Vector3,height:float,yaw:float,dry:bool)->void:
	# Bent closed tapered stalks; opaque, deterministic and rooted at the datum.
	_beam(art,p,base,base+Vector3(0,0.025,0),0.028,LEAF_LIGHT if dry else LEAF)
	base.y += 0.025
	var drift := Vector3(cos(yaw),0,sin(yaw))*height*0.23
	_beam(art,p,base,base+Vector3(0,height*0.62,0)+drift*0.35,0.028,LEAF_LIGHT if dry else LEAF,0.018)
	_beam(art,p,base+Vector3(0,height*0.62,0)+drift*0.35,base+Vector3(0,height,0)+drift,0.018,LEAF_LIGHT if dry else LEAF,0.0)

static func _grass(art,p:Node3D,dry:bool)->void:
	for i in (9 if dry else 15):
		var center := Vector3(float(i%5)*0.49-0.98,0,float(i/5)*0.55-0.55)
		for j in 5:
			var angle:float = TAU*j/5.0+i*0.71
			_blade(art,p,center+Vector3(cos(angle)*0.08,0,sin(angle)*0.08),0.47+0.11*sin(float(i+j)) if dry else 0.24+0.06*sin(float(i+j)),angle,dry)

static func _reeds(art,p:Node3D,cattails:bool)->void:
	for i in 18:
		var base := Vector3(float(i%6)*0.36-0.9,0,float(i/6)*0.36-0.36)
		var height:float = 1.05+0.29*sin(float(i*3))
		_beam(art,p,base,base+Vector3(0,height,0),0.018,LEAF_LIGHT)
		for side in [-1.0,1.0]:
			_blade(art,p,base,0.63+float(i%3)*0.10,side*1.2+i,false)
		if cattails:_beam(art,p,base+Vector3(0,height-0.13,0),base+Vector3(0,height+0.13,0),0.047,WOOD)
		else:
			for j in 3:_beam(art,p,base+Vector3(0,height-0.15,0),base+Vector3(0.12*cos(float(j)*TAU/3),height+0.04,0.12*sin(float(j)*TAU/3)),0.025,Palette.CANVAS,0.005)

static func _broken(art,p:Node3D,fallen:bool)->void:
	# Exposed heartwood, rooted buttress and tapered snapped ends.
	_beam(art,p,Vector3.ZERO,Vector3(0,0.64 if fallen else 1.8,0),0.31,WOOD,0.20)
	for i in 5:
		var angle:float = TAU*i/5
		_beam(art,p,Vector3(0,0.25,0),Vector3(cos(angle)*0.63,0.06,sin(angle)*0.63),0.13,WOOD,0.06)
	if fallen:
		_beam(art,p,Vector3(-1.45,0.24,0.66),Vector3(1.50,0.24,0.35),0.24,WOOD,0.12)
		_beam(art,p,Vector3(0.4,0.24,0.46),Vector3(1.10,0.74,0.95),0.105,WOOD,0.025)
		_beam(art,p,Vector3(-0.9,0.24,0.60),Vector3(-0.4,0.65,1.02),0.095,WOOD,0.015)
		_beam(art,p,Vector3(-1.46,0.24,0.66),Vector3(-1.47,0.24,0.66),0.17,Palette.CANVAS)
	else:
		for x in [-0.13,0.10]:_beam(art,p,Vector3(x,1.68,0),Vector3(x,2.12 if x<0 else 1.98,0.04),0.065,Palette.CANVAS,0.0)
		_beam(art,p,Vector3(0,1.14,0),Vector3(0.90,1.78,0.28),0.14,WOOD,0.025)
		_beam(art,p,Vector3(0,0.85,0),Vector3(-0.74,1.27,-0.30),0.13,WOOD,0.035)
