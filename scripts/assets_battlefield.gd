class_name AssetsBattlefield
extends RefCounted

# Original library geometry only. Collision tags describe placement envelopes,
# not physics, navigation or cover. All models use a local flat y=0 datum.
const METADATA = "res://resources/assets_battlefield.json"
# Neutral colors only: art.models.* fields are reassigned per team by unit builds.
const P = preload("res://scripts/environment_palette.gd")
const CONCRETE = Color("858a80")
const EARTH = Color("75644c")
const SPOIL = Color("857659")
const ASH = Color("3a403d")
const CHAR = Color("42453f")
const SOOT = Color("4c4b42")
const SINGE = Color("5f5948")
const BURNT = Color("4f4b45")
const RUST = Color("6b4a36")
# Streak burns spread from an impact origin and drag toward +Z.
const STREAK_ORIGIN = Vector3(0,0,-1.0)
const BAYS = 5

static func specs()->Array:
	var data = JSON.parse_string(FileAccess.get_file_as_string(METADATA))
	return data if data is Array else []

static func build(art,parent:Node3D,kind:String,variant:String)->Node3D:
	var spec:Dictionary={}
	for entry in specs():
		if entry.kind==kind and entry.variant==variant:spec=entry;break
	if spec.is_empty():return null
	var p:=Node3D.new()
	p.name=kind+"_"+variant
	parent.add_child(p)
	match kind:
		"concrete_barrier":_barrier(art,p,variant=="linked_blocks")
		"filled_wire_basket":_basket(art,p,variant=="stepped")
		"checkpoint_gate":_gate(art,p,variant=="swing")
		"supply_tent":_tent(art,p,variant=="lean_to")
		"antenna":_antenna(art,p,variant=="panel_mast")
		"camouflage_net":_net(art,p,variant=="high_ridge")
		"scorch_mark":_scorch(art,p,variant=="streak")
		"wreck":_wreck(art,p,variant=="tracked_hulk")
		"crater":_crater(art,p,variant=="elongated")
	if kind in ["scorch_mark","crater"]:
		# Uncoated earth/char must not inherit the painted-metal atlas stripes.
		for child in p.get_children():
			if child is MeshInstance3D and child.material_override is ShaderMaterial:
				var paint:Color=child.material_override.get_shader_parameter("paint")
				child.material_override=art.models.mat(paint,0.7)
	art.bake_model(p)
	if kind in ["scorch_mark","crater"]:
		for child in p.get_children():
			if child is GeometryInstance3D:child.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var f:Array=spec.footprint
	p.set_meta("local_footprint",Rect2(f[0],f[1],f[2],f[3]))
	p.set_meta("height",spec.height)
	p.set_meta("grants_cover",false)
	p.set_meta("placement_policy","library_only")
	return p

# Finish is passed explicitly: models.mat() otherwise infers it by comparing with
# its team-mutable fields, which would make cached paint depend on build order.
static func _mat(art,color:Color)->Material:
	var finish:float=0.9 if color==P.GLASS else (0.6 if color==P.RUBBER else (0.3 if color==P.STEEL else (0.12 if color==P.CANVAS else 0.0)))
	return art.models.mat(color,finish) if finish>0.0 else art.models.mat(color)

static func _box(art,p:Node3D,pos:Vector3,size:Vector3,color:Color)->void:
	var node:MeshInstance3D=art.models.box(p,pos,size,color)
	node.material_override=_mat(art,color)

static func _tube(art,p:Node3D,a:Vector3,b:Vector3,r:float,color:Color,top:float=-1.0)->void:
	var node:MeshInstance3D=art.models.tube(p,a,b,r,color,top)
	node.material_override=_mat(art,color)

static func _shell(art,p:Node3D,rings:Array,color:Color)->void:
	var node:MeshInstance3D=art.models.shell(p,rings,color)
	node.material_override=_mat(art,color)

# Explicit two-sided panels permit cloth, torn sheet and ground edges to be
# viewed from either side without allocating new materials or textures.
static func _panel(art,p:Node3D,points:Array,color:Color)->void:
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1,points.size()-1):
		var a:Vector3=points[0];var b:Vector3=points[i];var c:Vector3=points[i+1]
		var normal:Vector3=(c-a).cross(b-a).normalized()
		st.set_normal(normal)
		for v in [a,b,c]:st.add_vertex(v)
		st.set_normal(-normal)
		for v in [a,c,b]:st.add_vertex(v)
	var node:=MeshInstance3D.new();node.mesh=st.commit()
	node.material_override=_mat(art,color);p.add_child(node)

static func _beam(art,p:Node3D,a:Vector3,b:Vector3,r:float=0.04)->void:
	_tube(art,p,a,b,r,P.STEEL)

static func _foot(art,p:Node3D,x:float,z:float,height:float)->void:
	art.box(p,Vector3(x,0.06,z),Vector3(0.32,0.12,0.32),CONCRETE)
	_beam(art,p,Vector3(x,0.12,z),Vector3(x,height,z),0.045)

static func _barrier(art,p:Node3D,linked:bool)->void:
	if linked:
		for side in [-1,1]:
			_box(art,p,Vector3(side*0.81,0.48,side*0.08),Vector3(1.42,0.96,0.85),CONCRETE)
			for z in [-0.29,0.29]:
				_beam(art,p,Vector3(side*0.1,0.52,z),Vector3(-side*0.13,0.70,z),0.035)
	else:
		_shell(art,p,[art.models.octagon(1.5,0.44,0.44,0,0.08),art.models.octagon(1.5,0.44,0.44,0.20,0.08),art.models.octagon(1.46,0.17,0.17,0.72,0.04),art.models.octagon(1.46,0.14,0.14,1.10,0.04)],CONCRETE)
		for x in [-0.96,0.96]:
			art.box(p,Vector3(x,0.88,-0.157),Vector3(0.025,0.30,0.012),ASH)
			art.box(p,Vector3(x,0.08,-0.445),Vector3(0.30,0.12,0.015),ASH)

static func _basket(art,p:Node3D,stepped:bool)->void:
	if stepped:
		_cage(art,p,-0.77,1.4,1.52)
		_cage(art,p,0.77,1.4,0.94)
	else:_cage(art,p,0,1.96,1.04)

static func _cage(art,p:Node3D,x:float,width:float,height:float)->void:
	_box(art,p,Vector3(x,height/2,0),Vector3(width,height,1.10),P.CANVAS)
	# Fill mounds sit on the liner; the cage reaches above them.
	for i in 5:
		_box(art,p,Vector3(x-width*0.36+i*width*0.18,height+0.025,0.05*sin(i*2.0)),Vector3(width*0.22,0.05,0.87),EARTH)
	for y in [0.035,height*0.25,height*0.5,height*0.75,height+0.065]:
		for z in [-0.565,0.565]:_beam(art,p,Vector3(x-width/2,y,z),Vector3(x+width/2,y,z),0.012)
		for side in [-1,1]:_beam(art,p,Vector3(x+side*width/2,y,-0.565),Vector3(x+side*width/2,y,0.565),0.012)
	for i in 9:
		var xx:float=x-width/2+width*i/8.0
		for z in [-0.565,0.565]:_beam(art,p,Vector3(xx,0.02,z),Vector3(xx,height+0.065,z),0.012)
		_beam(art,p,Vector3(xx,height+0.065,-0.565),Vector3(xx,height+0.065,0.565),0.012)
	for z in [-0.28,0,0.28]:
		for side in [-1,1]:_beam(art,p,Vector3(x+side*width/2,0.02,z),Vector3(x+side*width/2,height+0.065,z),0.012)

static func _gate(art,p:Node3D,swing:bool)->void:
	for x in [-2.25,2.25]:
		_box(art,p,Vector3(x,0.16,0),Vector3(0.60,0.32,1.0),CONCRETE)
		_box(art,p,Vector3(x,0.86,0),Vector3(0.20,1.36,0.24),P.STEEL)
	if swing:
		for side in [-1,1]:
			var a:float=side*0.06;var b:float=side*2.14
			for y in [0.45,1.7]:_beam(art,p,Vector3(a,y,0),Vector3(b,y,0),0.045)
			_beam(art,p,Vector3(a,0.45,0),Vector3(b,1.7,0),0.04)
			for i in 7:
				var x:float=lerpf(a,b,i/6.0)
				_beam(art,p,Vector3(x,0.45,0),Vector3(x,1.7,0),0.023)
	else:
		art.box(p,Vector3(-0.12,1.12,0),Vector3(4.65,0.18,0.18),P.SAFETY_WHITE)
		# Muted red sleeves wrap the bar, so the boom reads from either approach.
		for i in 9:art.box(p,Vector3(-2.15+i*0.49,1.12,0),Vector3(0.19,0.196,0.196),P.SAFETY_RED)
		_box(art,p,Vector3(-2.2,0.97,0.22),Vector3(0.5,0.55,0.42),P.OLIVE)

static func _roof_y(x:float,lean:bool)->float:
	# Lean-to: one plane falling from the tall -X posts to the low +X eave.
	return 2.5-(x+2.0)*0.15 if lean else 2.72-absf(x)*0.41

static func _tent(art,p:Node3D,lean:bool)->void:
	for x in [-2.0,2.0]:
		for z in [-2.4,2.4]:_foot(art,p,x,z,_roof_y(x,lean))
	var zs:Array=[]
	for i in BAYS+1:zs.append(-2.4+i*0.96)
	for z in zs:
		if lean:_beam(art,p,Vector3(-2,_roof_y(-2,true),z),Vector3(2,_roof_y(2,true),z),0.028)
		else:
			for side in [-1,1]:_beam(art,p,Vector3(side*2,_roof_y(2,false),z),Vector3(0,_roof_y(0,false),z),0.028)
	# Cloth is a shared-vertex grid: rafters, ridge and eaves stay taut, and only
	# each bay's centre sags, so neighbouring bays meet without open seams.
	var slopes:Array=[[-2.12,0.0,2.12]] if lean else [[0.0,-1.06,-2.12],[0.0,1.06,2.12]]
	var sag:float=0.08 if lean else 0.10
	for bay in BAYS:
		var bay_z:Array=[zs[bay],(zs[bay]+zs[bay+1])/2.0,zs[bay+1]]
		for stations in slopes:
			var grid:Array=[]
			for i in 3:
				var row:Array=[]
				for j in 3:
					var x:float=stations[i]
					row.append(Vector3(x,_roof_y(x,lean)-(sag if i==1 and j==1 else 0.0),bay_z[j]))
				grid.append(row)
			for i in 2:
				for j in 2:_panel(art,p,[grid[i][j],grid[i+1][j],grid[i+1][j+1],grid[i][j+1]],P.CANVAS)
			if not lean:
				var edge:float=stations[2]
				var foot:float=signf(edge)*2.04
				_panel(art,p,[grid[2][0],Vector3(foot,0.06,bay_z[0]),Vector3(foot,0.06,bay_z[2]),grid[2][2]],P.CANVAS)
	# Back wall follows the roof line; the ridge tent's front split curtains leave an entrance.
	if lean:
		_panel(art,p,[Vector3(-2,0.03,2.4),Vector3(2,0.03,2.4),Vector3(2,_roof_y(2,true),2.4),Vector3(-2,_roof_y(-2,true),2.4)],P.CANVAS)
		for x in [-1.35,-0.55]:_box(art,p,Vector3(x,0.33,1.85),Vector3(0.7,0.66,0.8),EARTH)
	else:
		_panel(art,p,[Vector3(-2,0.03,2.4),Vector3(2,0.03,2.4),Vector3(2,1.9,2.4),Vector3(0,2.72,2.4),Vector3(-2,1.9,2.4)],P.CANVAS)
		for side in [-1,1]:
			_panel(art,p,[Vector3(side*2,0.04,-2.4),Vector3(side*0.66,0.04,-2.3),Vector3(side*0.24,2.3,-2.38),Vector3(0,2.72,-2.4),Vector3(side*2,1.9,-2.4)],P.CANVAS)
	for x in [-2.0,2.0]:
		for z in [-2.4,2.4]:
			var stake:=Vector3(x*1.3,0.04,z*1.17)
			art.box(p,Vector3(stake.x,0.06,stake.z),Vector3(0.08,0.12,0.08),P.STEEL)
			_beam(art,p,stake,Vector3(x,1.85,z),0.012)

static func _antenna(art,p:Node3D,panel:bool)->void:
	var height:float=3.35 if panel else 4.05
	art.box(p,Vector3(0,0.09,0),Vector3(0.4,0.18,0.4),CONCRETE)
	_tube(art,p,Vector3(0,0.18,0),Vector3(0,height,0),0.08,P.STEEL,0.025)
	for i in 3:
		var a:float=TAU*i/3
		var foot:=Vector3(cos(a)*1.02,0.08,sin(a)*1.02)
		art.box(p,Vector3(foot.x,0.04,foot.z),Vector3(0.22,0.08,0.22),CONCRETE)
		_beam(art,p,foot,Vector3(0,1.85,0),0.035)
	if panel:
		for side in [-1,1]:
			_beam(art,p,Vector3(0,2.65,0),Vector3(side*0.40,2.65,0),0.04)
			_box(art,p,Vector3(side*0.43,2.77,0),Vector3(0.28,0.92,0.15),P.MARKING)
		_box(art,p,Vector3(0.23,0.43,0),Vector3(0.32,0.5,0.35),P.OLIVE)
	else:
		for y in [3.05,3.48,3.8]:_beam(art,p,Vector3(-0.50,y,0),Vector3(0.50,y,0),0.022)

static func _net_y(x:float,z:float,ridge:bool)->float:
	return (2.85-absf(x)*0.36 if ridge else 2.18)-0.24*(1.0-pow(x/2.0,2))*(1.0-pow(z/1.7,2))

static func _net(art,p:Node3D,ridge:bool)->void:
	for x in ([-2.0,0.0,2.0] if ridge else [-2.0,2.0]):
		for z in [-1.7,1.7]:_foot(art,p,x,z,_net_y(x,z,ridge))
	# Open crossing ribbons: actual holes, no alpha textures or unsupported sheet.
	for i in 11:
		var x:float=-2+i*0.4
		for j in 10:
			var z:float=-1.7+j*0.34
			_panel(art,p,[Vector3(x-0.07,_net_y(x,z,ridge),z),Vector3(x+0.07,_net_y(x,z,ridge),z),Vector3(x+0.07,_net_y(x,z+0.34,ridge),z+0.34),Vector3(x-0.07,_net_y(x,z+0.34,ridge),z+0.34)],P.OLIVE)
	for j in 11:
		var z:float=-1.7+j*0.34
		for i in 10:
			var x:float=-2+i*0.4
			_panel(art,p,[Vector3(x,_net_y(x,z,ridge)+0.007,z-0.06),Vector3(x+0.4,_net_y(x+0.4,z,ridge)+0.007,z-0.06),Vector3(x+0.4,_net_y(x+0.4,z,ridge)+0.007,z+0.06),Vector3(x,_net_y(x,z,ridge)+0.007,z+0.06)],P.CANVAS)
	for x in [-2.0,2.0]:
		for z in [-1.7,1.7]:
			var stake:=Vector3(x*1.28,0.04,z*1.28)
			art.box(p,Vector3(stake.x,0.06,stake.z),Vector3(0.08,0.12,0.08),P.STEEL)
			_beam(art,p,stake,Vector3(x,_net_y(x,z,ridge),z),0.013)

# Sum of low harmonics (2, 3, 5 lobes): organic outlines without the per-vertex
# alternation that made earlier rings read as stars or cogs. Range about ±0.19.
static func _irregular(angle:float,phase:float)->float:
	return 0.09*sin(2.0*angle+0.7+phase)+0.06*sin(3.0*angle+2.1+phase*1.7)+0.04*sin(5.0*angle+4.0+phase*0.6)

static func _scorch(art,p:Node3D,streak:bool)->void:
	var origin:=STREAK_ORIGIN if streak else Vector3.ZERO
	# Teardrop: the +Z half of the blob is pulled along a slightly skewed drag
	# direction, so the tail narrows toward its tip instead of fanning out.
	var drag:=Vector3(sin(0.12),0,cos(0.12))
	# Opaque value steps grade from charred core to singed edge; no alpha or textures.
	var bands:Array=[[0.42,0.20,ASH],[0.66,0.45,CHAR],[0.86,0.72,SOOT],[1.0,1.0,SINGE]]
	var rings:Array=[]
	for band in bands:
		var ring:Array=[]
		for i in 24:
			var a:float=TAU*i/24
			var r:float=(0.85 if streak else 1.45)*band[0]*(1.0+_irregular(a,1.3 if streak else 0.0))
			var point:=origin+Vector3(cos(a)*r,0.008,sin(a)*r)
			if streak:point+=drag*2.0*band[1]*pow(maxf(0.0,sin(a)),4)
			ring.append(point)
		rings.append(ring)
	var centre:=origin+Vector3(0,0.008,0)
	for i in 24:
		var j:=(i+1)%24
		_panel(art,p,[centre,rings[0][i],rings[0][j]],ASH)
		for b in range(1,rings.size()):
			_panel(art,p,[rings[b-1][i],rings[b][i],rings[b][j],rings[b-1][j]],bands[b][2])
	# Thin core is grounded; the raised 8 mm stain avoids ground z-fighting.
	art.box(p,origin+Vector3(0,0.004,0),Vector3(0.2,0.008,0.2),ASH)

static func _wreck(art,p:Node3D,tracked:bool)->void:
	var half:float=1.17 if tracked else 0.83
	# Burnt-out hulk: heat-greyed shell, rusted running gear, tyres burnt away and
	# only a scrap of factory paint surviving. Not a live unit model.
	_box(art,p,Vector3(0,0.37,0.15),Vector3(half*2,0.40,3.45),BURNT)
	for x in [-half,half]:
		var out:float=signf(x)*0.012
		if tracked:
			_box(art,p,Vector3(x,0.10,0),Vector3(0.36,0.20,3.7),RUST)
			for i in 6:_tube(art,p,Vector3(x-0.16,0.34,-1.4+i*0.54),Vector3(x+0.16,0.34,-1.4+i*0.54),0.27,RUST)
			for i in 10:art.box(p,Vector3(x,0.035,-1.65+i*0.35),Vector3(0.43,0.07,0.13),P.STEEL)
		else:
			for z in [-1.15,1.22]:
				# Bare rims settle onto the datum once the tyres have burnt.
				_tube(art,p,Vector3(x-0.10,0.27,z),Vector3(x+0.10,0.27,z),0.27,RUST)
				_tube(art,p,Vector3(x-0.13,0.27,z),Vector3(x+0.13,0.27,z),0.09,P.STEEL)
		# Torn side skin: low front, high surviving rear edge, with a paint scrap.
		_panel(art,p,[Vector3(x,0.48,-1.65),Vector3(x,0.78,-0.9),Vector3(x,0.62,-0.3),Vector3(x,1.05,1.65),Vector3(x,0.48,1.78)],RUST)
		_panel(art,p,[Vector3(x+out,0.55,0.4),Vector3(x+out,0.75,0.6),Vector3(x+out,0.92,1.4),Vector3(x+out,0.6,1.5)],P.OLIVE)
	if not tracked:
		for x in [-0.73,0.73]:
			_beam(art,p,Vector3(x,0.54,-0.90),Vector3(x,1.63,-0.64),0.055)
			_beam(art,p,Vector3(x,1.63,-0.64),Vector3(x,1.48,0.48),0.055)
			_beam(art,p,Vector3(x,1.48,0.48),Vector3(x,0.54,0.65),0.055)
		_beam(art,p,Vector3(-0.73,1.63,-0.64),Vector3(0.73,1.63,-0.64),0.055)
		_panel(art,p,[Vector3(-0.73,1.63,-0.64),Vector3(0.73,1.63,-0.64),Vector3(0.56,1.56,-0.15),Vector3(-0.73,1.52,0.1)],ASH)
	else:
		for x in [-0.62,0.62]:_box(art,p,Vector3(x,0.67,0.45),Vector3(0.30,0.20,1.6),P.STEEL)
		_panel(art,p,[Vector3(-0.8,0.60,-1.6),Vector3(0.8,0.60,-1.6),Vector3(0.55,1.10,-0.7),Vector3(-0.5,0.83,-0.55)],RUST)
	# Detached pieces remain on the datum and inside the declared footprint: a bare
	# rim and a buckled plate folded against the rear, not a flat paper triangle.
	_tube(art,p,Vector3(0.85,0,-2.04),Vector3(0.85,0.20,-2.04),0.28,RUST)
	_panel(art,p,[Vector3(-0.9,0.015,2.42),Vector3(0.1,0.015,2.48),Vector3(0.15,0.12,2.22),Vector3(-0.85,0.14,2.18)],RUST)
	_panel(art,p,[Vector3(-0.85,0.14,2.18),Vector3(0.15,0.12,2.22),Vector3(0.2,0.46,1.93),Vector3(-0.75,0.50,1.92)],BURNT)

static func _crater(art,p:Node3D,long_form:bool)->void:
	var outer:Array=[];var apron:Array=[];var lip:Array=[];var inner:Array=[]
	var phase:float=2.4 if long_form else 0.0
	for i in 24:
		var a:float=TAU*i/24
		var r:float=0.87*(1.0+0.65*_irregular(a,phase))
		var v:=Vector3(cos(a)*(1.4 if long_form else 1.86),0,sin(a)*(2.44 if long_form else 1.86))*r
		# Lip height also varies at low frequency, so the rim reads as thrown spoil.
		var rise:float=(0.19 if long_form else 0.14)+0.05*sin(2.0*a+1.3+phase)+0.025*sin(3.0*a+0.4)
		outer.append(v)
		apron.append(Vector3(v.x*0.86,rise*0.45,v.z*0.86))
		lip.append(Vector3(v.x*0.73,rise,v.z*0.73))
		inner.append(Vector3(v.x*0.48,0.012,v.z*0.48))
	for i in 24:
		var j:int=(i+1)%24
		# Lighter spoil apron grades the outer edge into the surrounding ground.
		_panel(art,p,[outer[i],outer[j],apron[j],apron[i]],SPOIL)
		_panel(art,p,[apron[i],apron[j],lip[j],lip[i]],EARTH)
		_panel(art,p,[lip[i],lip[j],inner[j],inner[i]],CONCRETE if i in [2,3,11,17] else EARTH)
		_panel(art,p,[Vector3(0,0.012,0),inner[i],inner[j]],ASH)
