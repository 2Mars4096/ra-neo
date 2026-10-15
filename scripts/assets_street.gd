class_name AssetsStreet
extends RefCounted

# Original street, town-life and utility assemblies for the asset library.
# Library-only: no placement, collision bodies, cover, lights or new textures.
# Local origin is the ground datum (y=0). Vehicles face -Z like RoadsideProps;
# every other model presents its working face toward +Z.
const SPEC_PATH:="res://resources/assets_street.json"
const CONCRETE:=Color("9c9a8e")
const CONCRETE_DARK:=Color("85847a")
const STONE:=Color("8b836d")
const STONE_DARK:=Color("7d7563")
const IRON:=Color("393c36")
const VOID:=Color("262826")
const STEEL:=Color("596460")
const DARK_STEEL:=Color("4b4e4a")
const GALV:=Color("8d9795")
const TIMBER:=Color("6e675a")
const WOOD:=Color("75644c")
const PALE:=Color("d7d5b7")
const MARK:=Color("bdc8b6")
const SIGN_GREEN:=Color("355c46")
const POLE_GREEN:=Color("4c5640")
const CABINET_GREEN:=Color("4f6a52")
const WARN:=Color("a38548")
const SIGNAL_RED:=Color("8e4235")
const PORCELAIN:=Color("b9b19a")
const CABLE:=Color("33392f")
const SHEET:=Color("8a8470")

static var _cache:Array=[]
static var _shelter_glass_material:StandardMaterial3D

static func specs()->Array:
	if _cache.is_empty():
		var parsed=JSON.parse_string(FileAccess.get_file_as_string(SPEC_PATH))
		if parsed is Array:_cache=parsed
	return _cache.duplicate(true)

static func spec(kind:String,variant:String)->Dictionary:
	for entry in specs():
		if entry.kind==kind and entry.variant==variant:return entry
	return {}

static func local_footprint(kind:String,variant:String)->Rect2:
	var entry:=spec(kind,variant)
	if entry.is_empty():return Rect2()
	return Rect2(entry.footprint[0],entry.footprint[1],entry.footprint[2],entry.footprint[3])

static func build(art,parent:Node3D,kind:String,variant:String)->Node3D:
	# Unknown pairs fail without creating nodes. Parent must supply a flat local y=0.
	var entry:=spec(kind,variant)
	if entry.is_empty():return null
	var model:=Node3D.new()
	model.name=kind+"_"+variant
	parent.add_child(model)
	_assemble(art,model,kind,variant)
	art.bake_model(model)
	# Keep architectural transparency out of the opaque vertex-paint merger.
	if kind=="bus_stop" and variant=="glazed_shelter":_shelter_glass(model)
	model.set_meta("local_footprint",local_footprint(kind,variant))
	model.set_meta("height",float(entry.height))
	model.set_meta("category",entry.category)
	model.set_meta("collision_hint",entry.collision)
	model.set_meta("placement_policy","library_only")
	model.set_meta("grants_cover",false)
	return model

static func _assemble(art,p:Node3D,kind:String,variant:String)->void:
	match kind:
		"manhole":_manhole(art,p,variant=="open_works")
		"direction_sign":
			if variant=="fingerpost":_fingerpost(art,p)
			else:_roadside_panel(art,p)
		"guardrail":
			if variant=="w_beam":_w_beam(art,p)
			else:_wire_rope(art,p)
		"bicycle_rack":
			if variant=="sheffield_stands":_sheffield(art,p)
			else:_wheel_slots(art,p)
		"pickup":_pickup(art,p,variant=="crew_cab_canopy")
		"bus_stop":
			if variant=="glazed_shelter":_glazed_shelter(art,p)
			else:_timber_shelter(art,p)
		"transformer":
			if variant=="pad_mounted":_pad_transformer(art,p)
			else:_fenced_transformer(art,p)
		"utility_pole":
			if variant=="timber_crossarm":_timber_pole(art,p)
			else:_concrete_pole(art,p)
		"overhead_cable":
			if variant=="three_phase_span":_three_phase_span(art,p)
			else:_service_drop(art,p)
		"drain_outfall":
			if variant=="pipe_headwall":_pipe_headwall(art,p)
			else:_box_culvert(art,p)

# --- geometry helpers -------------------------------------------------------

static func _quad(st:SurfaceTool,a:Vector3,b:Vector3,c:Vector3,d:Vector3,outward:Vector3)->void:
	var n:=(c-a).cross(b-a)
	if n.dot(outward)<0.0:
		var t:=b;b=d;d=t
		n=-n
	st.set_normal(n.normalized())
	for v in [a,b,c,a,c,d]:st.add_vertex(v)

static func _tri(st:SurfaceTool,a:Vector3,b:Vector3,c:Vector3,outward:Vector3)->void:
	var n:=(c-a).cross(b-a)
	if n.dot(outward)<0.0:
		var t:=b;b=c;c=t
		n=-n
	st.set_normal(n.normalized())
	for v in [a,b,c]:st.add_vertex(v)

static func _commit(art,p:Node3D,st:SurfaceTool,color:Color)->MeshInstance3D:
	var node:=MeshInstance3D.new()
	node.mesh=st.commit()
	node.material_override=art.material(color)
	p.add_child(node)
	return node

static func _box(art,p:Node3D,center:Vector3,x_axis:Vector3,z_axis:Vector3,size:Vector3,color:Color)->MeshInstance3D:
	# Oriented box: size.x along x_axis, size.z along z_axis.
	var x:=x_axis.normalized()
	var z:=(z_axis-x*z_axis.dot(x)).normalized()
	var node:MeshInstance3D=art.box(p,center,size,color)
	node.transform=Transform3D(Basis(x,z.cross(x),z),center)
	return node

static func _beam(art,p:Node3D,a:Vector3,b:Vector3,thick:float,width:float,color:Color,up:=Vector3.UP)->MeshInstance3D:
	# Bar from a to b; thick is measured toward up, width across it.
	var x:=(b-a).normalized()
	var y:=up-x*up.dot(x)
	if y.length()<0.001:y=Vector3.BACK-x*Vector3.BACK.dot(x)
	return _box(art,p,(a+b)/2.0,x,x.cross(y.normalized()),Vector3(a.distance_to(b),thick,width),color)

static func _sweep(art,p:Node3D,points:Array,radius:float,color:Color,sides:=6,caps:=true)->MeshInstance3D:
	# Continuous tube through points with a parallel-transported frame (no seams at bends).
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings:=[]
	var u:=Vector3.ZERO
	for i in points.size():
		var dir:Vector3
		if i==0:dir=points[1]-points[0]
		elif i==points.size()-1:dir=points[i]-points[i-1]
		else:dir=(points[i+1]-points[i]).normalized()+(points[i]-points[i-1]).normalized()
		dir=dir.normalized()
		if i==0:u=dir.cross(Vector3.UP if absf(dir.y)<0.9 else Vector3.RIGHT).normalized()
		else:u=(u-dir*u.dot(dir)).normalized()
		var v:=dir.cross(u)
		var ring:=[]
		for s in sides:
			var a:=TAU*s/sides
			ring.append(points[i]+(u*cos(a)+v*sin(a))*radius)
		rings.append(ring)
	for i in points.size()-1:
		var mid:Vector3=(points[i]+points[i+1])/2.0
		for s in sides:
			var a:Vector3=rings[i][s];var b:Vector3=rings[i][(s+1)%sides]
			var c:Vector3=rings[i+1][(s+1)%sides];var d:Vector3=rings[i+1][s]
			_quad(st,a,b,c,d,(a+b+c+d)/4.0-mid)
	if caps:
		for end in [0,points.size()-1]:
			var outward:Vector3=(points[0]-points[1]) if end==0 else (points[end]-points[end-1])
			for s in sides:_tri(st,points[end],rings[end][s],rings[end][(s+1)%sides],outward)
	return _commit(art,p,st,color)

static func _disc(art,p:Node3D,center:Vector3,radius:float,height:float,color:Color,sides:=16)->MeshInstance3D:
	return _sweep(art,p,[center,center+Vector3(0,height,0)],radius,color,sides)

static func _torus(art,p:Node3D,center:Vector3,axis:Vector3,radius:float,thick:float,color:Color,segments:=16,sides:=5)->MeshInstance3D:
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	axis=axis.normalized()
	var u:=axis.cross(Vector3.UP if absf(axis.y)<0.9 else Vector3.RIGHT).normalized()
	var v:=axis.cross(u)
	for i in segments:
		var a0:=TAU*i/segments;var a1:=TAU*(i+1)/segments
		var r0:=u*cos(a0)+v*sin(a0);var r1:=u*cos(a1)+v*sin(a1)
		for j in sides:
			var b0:=TAU*j/sides;var b1:=TAU*(j+1)/sides
			var q:=[center+r0*(radius+thick*cos(b0))+axis*thick*sin(b0),center+r1*(radius+thick*cos(b0))+axis*thick*sin(b0),
				center+r1*(radius+thick*cos(b1))+axis*thick*sin(b1),center+r0*(radius+thick*cos(b1))+axis*thick*sin(b1)]
			var mid:Vector3=center+(r0+r1).normalized()*radius
			_quad(st,q[0],q[1],q[2],q[3],(q[0]+q[1]+q[2]+q[3])/4.0-mid)
	return _commit(art,p,st,color)

static func _slab(art,p:Node3D,poly:Array,thick:float,xf:Transform3D,color:Color)->MeshInstance3D:
	# Convex outline in local XY, extruded thick along local Z, then placed by xf.
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center:=Vector2.ZERO
	for q in poly:center+=q
	center/=poly.size()
	var h:=thick/2.0
	for i in poly.size():
		var a:Vector2=poly[i];var b:Vector2=poly[(i+1)%poly.size()]
		var out2:=((a+b)/2.0-center)
		_quad(st,xf*Vector3(a.x,a.y,-h),xf*Vector3(b.x,b.y,-h),xf*Vector3(b.x,b.y,h),xf*Vector3(a.x,a.y,h),xf.basis*Vector3(out2.x,out2.y,0))
		for side in [-1.0,1.0]:
			_tri(st,xf*Vector3(center.x,center.y,side*h),xf*Vector3(a.x,a.y,side*h),xf*Vector3(b.x,b.y,side*h),xf.basis*Vector3(0,0,side))
	return _commit(art,p,st,color)

static func _circle(radius:float,count:int,offset:=Vector2.ZERO)->Array:
	var result:=[]
	for i in count:result.append(offset+Vector2(cos(TAU*i/count),sin(TAU*i/count))*radius)
	return result

static func _span(a:Vector3,b:Vector3,sag:float,segments:int)->Array:
	# Parabolic catenary approximation; sag measured below the chord at mid-span.
	var result:=[]
	for i in segments+1:
		var t:=float(i)/segments
		result.append(a.lerp(b,t)+Vector3(0,-4.0*sag*t*(1.0-t),0))
	return result

static func _arc(center:Vector3,u:Vector3,v:Vector3,radius:float,from:float,to:float,steps:int)->Array:
	var result:=[]
	for i in steps+1:
		var a:=lerpf(from,to,float(i)/steps)
		result.append(center+(u*cos(a)+v*sin(a))*radius)
	return result

static func _rock(art,p:Node3D,pos:Vector3,size:Vector3,rng:RandomNumberGenerator,color:Color)->void:
	# Flat-bedded irregular stone: footprint ring on the datum, shoulder, smaller crown.
	var base:=[]
	for i in 7:
		var a:=TAU*i/7.0+rng.randf_range(-0.2,0.2)
		base.append(Vector2(cos(a)*size.x,sin(a)*size.z)*0.5*rng.randf_range(0.8,1.0))
	var rings:=[]
	for level in [[0.0,1.0],[0.55,1.0],[1.0,0.55]]:
		var ring:=[]
		for q in base:ring.append(Vector3(q.x*level[1],size.y*level[0],q.y*level[1]))
		rings.append(ring)
	var node:MeshInstance3D=art.models.shell(p,rings,color)
	node.position=pos

static func _bicycle(art,p:Node3D,xf:Transform3D,frame:Color)->void:
	# Upright diamond-frame bicycle in its own YZ plane, front wheel toward local -Z.
	var rubber:Color=art.models.rubber
	var axle:=xf.basis*Vector3.RIGHT
	for z in [-0.52,0.52]:
		var hub:=Vector3(0,0.36,z)
		_torus(art,p,xf*hub,axle,0.33,0.03,rubber,18,5)
		_torus(art,p,xf*hub,axle,0.295,0.011,GALV,18,4)
		_sweep(art,p,[xf*(hub+Vector3(-0.05,0,0)),xf*(hub+Vector3(0.05,0,0))],0.025,GALV,6)
		for k in 6:
			var a:=TAU*k/6.0
			_beam(art,p,xf*hub,xf*(hub+Vector3(0,cos(a),sin(a))*0.29),0.006,0.006,GALV,axle)
	var rear:=Vector3(0,0.36,0.52);var front:=Vector3(0,0.36,-0.52)
	var bb:=Vector3(0,0.30,0.06);var seat:=Vector3(0,0.80,0.17)
	var head_top:=Vector3(0,0.84,-0.36);var head_low:=Vector3(0,0.70,-0.40)
	for pair in [[seat,bb],[bb,head_low],[seat,head_top],[head_low,head_top]]:
		art.models.tube(p,xf*pair[0],xf*pair[1],0.02,frame)
	for side in [-0.045,0.045]:
		var o:=Vector3(side,0,0)
		art.models.tube(p,xf*(bb+o*0.5),xf*(rear+o),0.012,frame)
		art.models.tube(p,xf*(seat+o*0.4),xf*(rear+o),0.011,frame)
		art.models.tube(p,xf*(head_low+o*0.3),xf*(front+o),0.014,frame)
	var stem:=Vector3(0,0.98,-0.34)
	art.models.tube(p,xf*head_top,xf*stem,0.016,DARK_STEEL)
	art.models.tube(p,xf*(stem+Vector3(-0.26,0,0.03)),xf*(stem+Vector3(0.26,0,0.03)),0.014,DARK_STEEL)
	for side in [-1.0,1.0]:
		art.models.tube(p,xf*(stem+Vector3(side*0.27,0,0.03)),xf*(stem+Vector3(side*0.27,0,0.13)),0.018,rubber)
	art.models.tube(p,xf*seat,xf*(seat+Vector3(0,0.09,0.03)),0.012,GALV)
	_box(art,p,xf*(seat+Vector3(0,0.115,0.04)),axle,xf.basis*Vector3.BACK,Vector3(0.12,0.045,0.25),rubber)
	_torus(art,p,xf*(bb+Vector3(0.05,0,0)),axle,0.09,0.012,DARK_STEEL,12,4)
	for side in [-1.0,1.0]:
		var crank:=bb+Vector3(side*0.07,side*-0.14,side*0.04)
		_beam(art,p,xf*(bb+Vector3(side*0.07,0,0)),xf*crank,0.02,0.02,DARK_STEEL,axle)
		var pedal:MeshInstance3D=art.box(p,xf*(crank+Vector3(side*0.05,0,0)),Vector3(0.09,0.02,0.07),rubber)
		pedal.basis=xf.basis

# --- circulation --------------------------------------------------------------

static func _manhole(art,p:Node3D,open:bool)->void:
	if not open:
		# Cast cover seated in an iron frame and a round concrete collar, flush to grade.
		_disc(art,p,Vector3.ZERO,0.56,0.035,CONCRETE_DARK,16)
		_disc(art,p,Vector3(0,0.035,0),0.42,0.015,IRON,20)
		_disc(art,p,Vector3(0,0.05,0),0.36,0.008,DARK_STEEL,20)
		_torus(art,p,Vector3(0,0.06,0),Vector3.UP,0.33,0.01,IRON,24,4)
		for i in range(-4,5):
			for j in range(-4,5):
				var q:=Vector2(i,j)*0.068
				if q.length()>0.27 or (absi(i)<=1 and j==0):continue
				art.box(p,Vector3(q.x,0.064,q.y),Vector3(0.044,0.012,0.044),IRON)
		art.box(p,Vector3(0,0.061,0),Vector3(0.2,0.006,0.06),DARK_STEEL)
		for x in [-0.055,0.055]:art.box(p,Vector3(x,0.063,0),Vector3(0.05,0.004,0.022),VOID)
		return
	# Street works: open square chamber, lid laid aside, ladder extension and guard barrier.
	var cx:=-0.3
	art.models.box(p,Vector3(cx,0.03,-0.475),Vector3(1.2,0.06,0.25),CONCRETE)
	art.models.box(p,Vector3(cx,0.03,0.475),Vector3(1.2,0.06,0.25),CONCRETE)
	art.models.box(p,Vector3(cx-0.475,0.03,0),Vector3(0.25,0.06,0.7),CONCRETE)
	art.models.box(p,Vector3(cx+0.475,0.03,0),Vector3(0.25,0.06,0.7),CONCRETE)
	art.box(p,Vector3(cx,0.004,0),Vector3(0.7,0.008,0.7),VOID)
	for z in [-0.34,0.34]:art.box(p,Vector3(cx,0.064,z),Vector3(0.72,0.008,0.03),IRON)
	for x in [cx-0.34,cx+0.34]:art.box(p,Vector3(x,0.064,0),Vector3(0.03,0.008,0.72),IRON)
	for x in [cx-0.18,cx+0.18]:_sweep(art,p,[Vector3(x,0,-0.3),Vector3(x,0.62,-0.3),Vector3(x,0.7,-0.24),Vector3(x,0.66,-0.18)],0.022,GALV,6)
	for y in [0.18,0.42]:art.box(p,Vector3(cx,y,-0.3),Vector3(0.36,0.028,0.028),GALV)
	art.models.box(p,Vector3(0.66,0.02,0),Vector3(0.66,0.04,0.66),DARK_STEEL)
	for k in 5:
		var o:=-0.2+k*0.1
		_beam(art,p,Vector3(0.66+o-0.08,0.043,-0.12),Vector3(0.66+o+0.08,0.043,0.12),0.006,0.02,IRON)
	for z in [-0.18,0.18]:art.box(p,Vector3(0.66,0.041,z),Vector3(0.07,0.004,0.025),VOID)
	for leg in [Vector2(-1.1,-0.8),Vector2(0,-0.8),Vector2(1.1,-0.8),Vector2(-1.1,0.8),Vector2(0,0.8),Vector2(1.1,0.8)]:
		art.box(p,Vector3(leg.x,0.02,leg.y),Vector3(0.18,0.04,0.22),art.models.rubber)
		art.models.tube(p,Vector3(leg.x,0.04,leg.y),Vector3(leg.x,1.0,leg.y),0.022,GALV)
	for side in [[Vector2(-1.1,-0.8),Vector2(1.1,-0.8)],[Vector2(-1.1,0.8),Vector2(1.1,0.8)],[Vector2(-1.1,-0.8),Vector2(-1.1,0.8)],[Vector2(1.1,-0.8),Vector2(1.1,0.8)]]:
		var a:Vector2=side[0];var b:Vector2=side[1]
		var count:=int(round(a.distance_to(b)/0.32))
		for k in count:
			var s:=a.lerp(b,float(k)/count);var e:=a.lerp(b,float(k+1)/count)
			_beam(art,p,Vector3(s.x,0.94,s.y),Vector3(e.x,0.94,e.y),0.12,0.025,SIGNAL_RED if k%2==0 else PALE)
		art.models.tube(p,Vector3(a.x,0.55,a.y),Vector3(b.x,0.55,b.y),0.016,GALV)

static func _fingerpost(art,p:Node3D)->void:
	art.models.box(p,Vector3(0,0.05,0),Vector3(0.42,0.1,0.42),CONCRETE)
	art.models.tube(p,Vector3(0,0.1,0),Vector3(0,0.45,0),0.095,POLE_GREEN,0.068)
	art.models.tube(p,Vector3(0,0.45,0),Vector3(0,2.78,0),0.065,POLE_GREEN,0.055)
	art.models.tube(p,Vector3(0,2.78,0),Vector3(0,2.84,0),0.078,IRON)
	art.models.ellipsoid(p,Vector3(0,2.9,0),Vector3(0.12,0.13,0.12),POLE_GREEN)
	# Three pointed blades at different heights; lettering is abstract raised bars.
	for blade in [[2.48,0.0,0.8],[2.18,PI,0.62],[1.88,-PI/3.0,0.7]]:
		var reach:float=blade[2]+0.1
		var arrow:=[Vector2(0.07,-0.11),Vector2(reach,-0.11),Vector2(reach+0.12,0),Vector2(reach,0.11),Vector2(0.07,0.11)]
		var xf:=Transform3D(Basis(Vector3.UP,blade[1]),Vector3(0,blade[0],0))
		_slab(art,p,arrow,0.035,xf,PALE)
		for face in [-1.0,1.0]:
			for row in [0.035,-0.035]:
				_beam(art,p,xf*Vector3(0.16,row,face*0.021),xf*Vector3(0.16+float(blade[2])*(0.9 if row>0 else 0.7),row,face*0.021),0.026,0.006,IRON)
		_disc(art,p,Vector3(0,blade[0]-0.13,0),0.074,0.26,IRON,10)

static func _roadside_panel(art,p:Node3D)->void:
	for x in [-0.95,0.95]:
		art.models.box(p,Vector3(x,0.075,-0.11),Vector3(0.36,0.15,0.36),CONCRETE)
		art.box(p,Vector3(x,0.16,-0.11),Vector3(0.2,0.02,0.2),IRON)
		art.box(p,Vector3(x,1.575,-0.11),Vector3(0.1,2.85,0.1),STEEL)
	for y in [1.85,2.65]:art.box(p,Vector3(0,y,-0.03),Vector3(2.4,0.08,0.06),DARK_STEEL)
	art.models.box(p,Vector3(0,2.25,0.03),Vector3(2.5,1.3,0.06),SIGN_GREEN)
	for y in [1.625,2.875]:art.box(p,Vector3(0,y,0.064),Vector3(2.4,0.025,0.008),MARK)
	for x in [-1.225,1.225]:art.box(p,Vector3(x,2.25,0.064),Vector3(0.025,1.25,0.008),MARK)
	# Ahead/left arrow and stacked destination bars on the +Z face.
	art.box(p,Vector3(-0.8,2.12,0.064),Vector3(0.1,0.7,0.008),MARK)
	for side in [-1.0,1.0]:_beam(art,p,Vector3(-0.8,2.58,0.064),Vector3(-0.8+side*0.17,2.41,0.064),0.08,0.008,MARK,Vector3.BACK.cross(Vector3(side*0.17,-0.17,0)).normalized())
	for row in [[2.62,1.3],[2.36,0.9],[2.1,1.15],[1.84,0.7]]:
		art.box(p,Vector3(-0.45+row[1]/2.0,row[0],0.064),Vector3(row[1],0.07,0.008),MARK)
	art.box(p,Vector3(0.95,2.65,0.066),Vector3(0.3,0.16,0.012),WARN)

static func _w_beam(art,p:Node3D)->void:
	# Profile (z offset toward traffic, y) of a W-section rail swept along a flared plan path.
	var profile:=[Vector2(0.04,0.79),Vector2(0.12,0.725),Vector2(0.07,0.635),Vector2(0.12,0.545),Vector2(0.04,0.48)]
	var path:=[Vector2(-3.0,-0.38),Vector2(-2.3,0.0),Vector2(2.3,0.0),Vector2(3.0,-0.38)]
	for i in path.size()-1:
		var a:Vector2=path[i];var b:Vector2=path[i+1]
		var d:=(b-a).normalized();var n:=Vector2(-d.y,d.x)
		var d3:=Vector3(d.x,0,d.y);var n3:=Vector3(n.x,0,n.y)
		var extend:=0.0 if i==1 else 0.02
		for k in profile.size()-1:
			var p0:Vector2=profile[k];var p1:Vector2=profile[k+1]
			var w:Vector3=n3*(p1.x-p0.x)+Vector3.UP*(p1.y-p0.y)
			var mid:=(a+b)/2.0+n*((p0.x+p1.x)/2.0)
			_box(art,p,Vector3(mid.x,(p0.y+p1.y)/2.0,mid.y),d3,w,Vector3(a.distance_to(b)+extend,0.012,w.length()+0.004),GALV)
	for end in [-1.0,1.0]:
		_disc(art,p,Vector3(end*3.0-end*0.02,0.48,-0.42),0.12,0.31,GALV,10)
		_post(art,p,Vector2(end*2.66,-0.37))
	for x in [-1.9,-0.0,1.9]:
		_post(art,p,Vector2(x,-0.17))
		art.models.box(p,Vector3(x,0.635,-0.03),Vector3(0.15,0.33,0.13),WOOD)
		for y in [0.6,0.67]:art.box(p,Vector3(x,y,0.083),Vector3(0.03,0.03,0.02),DARK_STEEL)
	for x in [-0.95,0.95]:
		for y in [0.6,0.67]:
			for dx in [-0.06,0.06]:art.box(p,Vector3(x+dx,y,0.083),Vector3(0.025,0.025,0.02),DARK_STEEL)

static func _post(art,p:Node3D,at:Vector2)->void:
	# Galvanised I-section post: web across the rail line plus two flanges.
	art.box(p,Vector3(at.x,0.36,at.y),Vector3(0.012,0.72,0.15),STEEL)
	for side in [-0.075,0.075]:art.box(p,Vector3(at.x,0.36,at.y+side),Vector3(0.1,0.72,0.012),STEEL)

static func _wire_rope(art,p:Node3D)->void:
	var posts:=[-3.2,-1.6,0.0,1.6,3.2]
	for i in posts.size():
		var x:float=posts[i]
		_disc(art,p,Vector3(x,0,0),0.09,0.08,CONCRETE,8)
		art.box(p,Vector3(x,0.4,0),Vector3(0.09,0.72,0.06),STEEL)
		art.box(p,Vector3(x,0.775,0),Vector3(0.1,0.03,0.08),PALE)
		art.box(p,Vector3(x,0.69,0.036),Vector3(0.06,0.08,0.012),WARN)
	for end in [-1.0,1.0]:
		art.models.box(p,Vector3(end*4.45,0.125,0),Vector3(0.6,0.25,0.5),CONCRETE_DARK)
		art.box(p,Vector3(end*4.28,0.27,0),Vector3(0.14,0.04,0.2),IRON)
	# Four tensioned ropes: outer pair runs on the traffic face, middle pair weaves.
	for r in 4:
		var h:=0.48+r*0.08
		var points:=[Vector3(-4.28,0.29,-0.06+r*0.04)]
		for i in posts.size():
			var z:=0.045
			if r in [1,2]:z=0.045 if (i+r)%2==0 else -0.045
			points.append(Vector3(posts[i],h,z))
		points.append(Vector3(4.28,0.29,-0.06+r*0.04))
		_sweep(art,p,points,0.012,GALV,5,false)
		for end in [-1.0,1.0]:
			var a:Vector3=points[0] if end<0 else points[points.size()-1]
			var b:Vector3=points[1] if end<0 else points[points.size()-2]
			var dir:=(b-a).normalized()
			_sweep(art,p,[a+dir*0.38,a+dir*0.54],0.024,DARK_STEEL,6)

# --- town life ----------------------------------------------------------------

static func _sheffield(art,p:Node3D)->void:
	for sx in [-1.0,0.0,1.0]:
		var pts:=[Vector3(sx,0,-0.35)]
		pts.append_array(_arc(Vector3(sx,0.62,-0.18),Vector3.BACK,Vector3.UP,0.17,PI,PI/2.0,4))
		pts.append_array(_arc(Vector3(sx,0.62,0.18),Vector3.BACK,Vector3.UP,0.17,PI/2.0,0.0,4))
		pts.append(Vector3(sx,0,0.35))
		_sweep(art,p,pts,0.026,GALV,8,false)
		for z in [-0.35,0.35]:art.box(p,Vector3(sx,0.005,z),Vector3(0.13,0.01,0.13),IRON)
	_bicycle(art,p,Transform3D(Basis.IDENTITY,Vector3(0.09,0,0)),Color("4d6a66"))
	_bicycle(art,p,Transform3D(Basis(Vector3.UP,PI),Vector3(-1.09,0,0.05)),Color("8a5a40"))

static func _wheel_slots(art,p:Node3D)->void:
	for z in [-0.3,0.3]:art.box(p,Vector3(0,0.03,z),Vector3(2.9,0.06,0.07),STEEL)
	for x in [-1.42,1.42]:art.box(p,Vector3(x,0.015,0),Vector3(0.12,0.03,0.78),IRON)
	for i in 7:
		var x:=-1.26+i*0.42
		var leg:=0.42 if i%2==0 else 0.16
		var pts:=[Vector3(x,0.06,-0.3),Vector3(x,leg,-0.3)]
		pts.append_array(_arc(Vector3(x,leg,0),Vector3.BACK,Vector3.UP,0.3,PI,0.0,8).slice(1,8))
		pts.append_array([Vector3(x,leg,0.3),Vector3(x,0.06,0.3)])
		_sweep(art,p,pts,0.024,GALV,8,false)
	_bicycle(art,p,Transform3D(Basis.IDENTITY,Vector3(-1.05,0,0.47)),Color("4d6a66"))
	_bicycle(art,p,Transform3D(Basis.IDENTITY,Vector3(0.63,0,0.47)),Color("59624f"))

static func _pickup(art,p:Node3D,crew:bool)->void:
	var paint:=Color("8b8d84") if crew else Color("707f6e")
	var rubber:Color=art.models.rubber
	var glass:Color=art.models.glass
	var front:=-2.6
	var cab_front:=-1.35
	var cab_back:=0.95 if crew else 0.15
	var bed_front:=cab_back+0.06
	var rear:=2.75 if crew else 2.6
	var wheels:=[-1.55,1.85 if crew else 1.55]
	# Ten-sided tyre rests on a flat, so lower the hub to put that flat on the datum.
	var hub:=0.38*cos(PI/10.0)
	for z in wheels:
		for side in [-1.0,1.0]:
			art.models.tube(p,Vector3(side*0.68,hub,z),Vector3(side*0.94,hub,z),0.38,rubber)
			art.models.tube(p,Vector3(side*0.94,hub,z),Vector3(side*0.955,hub,z),0.2,GALV)
			art.box(p,Vector3(side*0.93,0.8,z),Vector3(0.1,0.07,0.98),rubber)
	art.box(p,Vector3(0,0.45,(front+rear)/2.0),Vector3(0.9,0.14,rear-front-0.5),DARK_STEEL)
	# Axles carry the ladder frame; mounts carry the body.
	for z in wheels:
		art.models.tube(p,Vector3(-0.7,hub,z),Vector3(0.7,hub,z),0.05,DARK_STEEL)
		for side in [-1.0,1.0]:art.box(p,Vector3(side*0.4,0.565,z+0.5),Vector3(0.08,0.09,0.1),IRON)
	# Bonnet, grille, lamps and bumper.
	art.models.box(p,Vector3(0,0.86,(front+cab_front)/2.0),Vector3(1.84,0.5,cab_front-front),paint)
	art.box(p,Vector3(0,0.55,front-0.03),Vector3(1.9,0.2,0.14),DARK_STEEL)
	art.box(p,Vector3(0,0.88,front-0.01),Vector3(1.1,0.28,0.03),IRON)
	for y in [0.8,0.88,0.96]:art.box(p,Vector3(0,y,front-0.03),Vector3(1.0,0.025,0.02),GALV)
	for side in [-1.0,1.0]:art.box(p,Vector3(side*0.72,0.93,front-0.015),Vector3(0.28,0.13,0.03),PALE)
	# Cab: painted lower body, glazed glasshouse, roof and pillars.
	art.models.box(p,Vector3(0,0.86,(cab_front+cab_back)/2.0),Vector3(1.84,0.5,cab_back-cab_front),paint)
	var lo_f:=cab_front+0.05;var lo_b:=cab_back-0.02;var hi_f:=cab_front+0.48;var hi_b:=cab_back-0.1
	art.models.shell(p,[[Vector3(-0.88,1.11,lo_f),Vector3(0.88,1.11,lo_f),Vector3(0.88,1.11,lo_b),Vector3(-0.88,1.11,lo_b)],
		[Vector3(-0.76,1.8,hi_f),Vector3(0.76,1.8,hi_f),Vector3(0.76,1.8,hi_b),Vector3(-0.76,1.8,hi_b)]],glass)
	art.models.box(p,Vector3(0,1.84,(hi_f+hi_b)/2.0),Vector3(1.6,0.08,hi_b-hi_f+0.06),paint)
	for side in [-1.0,1.0]:
		art.models.tube(p,Vector3(side*0.88,1.11,lo_f),Vector3(side*0.76,1.8,hi_f),0.04,paint)
		art.box(p,Vector3(side*0.83,1.45,lo_b-0.05),Vector3(0.1,0.7,0.1),paint)
		art.box(p,Vector3(side*1.0,1.2,cab_front+0.2),Vector3(0.12,0.16,0.05),DARK_STEEL)
		art.box(p,Vector3(side*0.94,1.16,cab_front+0.2),Vector3(0.08,0.03,0.03),DARK_STEEL)
		var doors:=[cab_front+0.05,cab_front+1.12,cab_back-0.04] if crew else [cab_front+0.05,cab_back-0.04]
		for z in doors:art.box(p,Vector3(side*0.925,0.86,z),Vector3(0.01,0.48,0.012),IRON)
		for k in doors.size()-1:art.box(p,Vector3(side*0.93,0.98,doors[k+1]-0.22),Vector3(0.012,0.03,0.12),IRON)
		if crew:art.box(p,Vector3(side*0.82,1.45,cab_front+1.1),Vector3(0.1,0.7,0.08),paint)
	# Load bed with wheel tubs, ribbed floor, tailgate and lamps.
	var bed_mid:=(bed_front+rear)/2.0;var bed_len:=rear-bed_front
	art.box(p,Vector3(0,0.88,bed_mid),Vector3(1.7,0.06,bed_len),DARK_STEEL)
	for x in [-0.6,-0.3,0.0,0.3,0.6]:art.box(p,Vector3(x,0.915,bed_mid),Vector3(0.05,0.012,bed_len-0.1),GALV)
	for side in [-1.0,1.0]:
		art.models.box(p,Vector3(side*0.87,1.13,bed_mid),Vector3(0.1,0.34,bed_len),paint)
		var arch:float=wheels[1]
		art.models.box(p,Vector3(side*0.87,0.78,(bed_front+arch-0.5)/2.0),Vector3(0.1,0.34,arch-0.5-bed_front),paint)
		art.models.box(p,Vector3(side*0.87,0.78,(arch+0.5+rear)/2.0),Vector3(0.1,0.34,rear-arch-0.5),paint)
		art.box(p,Vector3(side*0.66,1.0,arch),Vector3(0.32,0.2,0.9),DARK_STEEL)
		art.box(p,Vector3(side*0.86,1.0,rear+0.01),Vector3(0.1,0.3,0.03),SIGNAL_RED)
	art.models.box(p,Vector3(0,0.98,rear-0.05),Vector3(1.64,0.62,0.1),paint)
	art.box(p,Vector3(0,1.18,rear+0.005),Vector3(0.26,0.06,0.02),IRON)
	art.box(p,Vector3(0,0.56,rear+0.03),Vector3(1.86,0.16,0.14),DARK_STEEL)
	art.models.box(p,Vector3(0,1.08,bed_front),Vector3(1.84,0.44,0.1),paint)
	if crew:
		# Glazed canopy over the bed and roof bars over the cab.
		var cf:=bed_front+0.05;var cr:=rear-0.02
		art.models.shell(p,[[Vector3(-0.92,1.3,cf),Vector3(0.92,1.3,cf),Vector3(0.92,1.3,cr),Vector3(-0.92,1.3,cr)],
			[Vector3(-0.84,1.9,cf+0.08),Vector3(0.84,1.9,cf+0.08),Vector3(0.84,1.9,cr-0.12),Vector3(-0.84,1.9,cr-0.12)]],paint)
		for side in [-1.0,1.0]:
			_box(art,p,Vector3(side*0.885,1.6,(cf+cr)/2.0),Vector3.BACK,Vector3(-side*0.08,0.6,0),Vector3(bed_len-0.6,0.012,0.3),glass)
		_box(art,p,Vector3(0,1.6,cr-0.055),Vector3.RIGHT,Vector3(0,0.12,0.6),Vector3(1.5,0.3,0.012),glass)
		for z in [hi_f+0.25,hi_b-0.2]:
			art.box(p,Vector3(0,1.93,z),Vector3(1.5,0.04,0.06),GALV)
			for side in [-1.0,1.0]:art.box(p,Vector3(side*0.7,1.895,z),Vector3(0.06,0.04,0.08),DARK_STEEL)
	else:
		# Headache rack guarding the rear window.
		var z:=bed_front+0.12
		for side in [-1.0,1.0]:art.models.tube(p,Vector3(side*0.78,1.3,z),Vector3(side*0.78,1.94,z),0.035,DARK_STEEL)
		art.models.tube(p,Vector3(-0.8,1.94,z),Vector3(0.8,1.94,z),0.035,DARK_STEEL)
		for x in [-0.4,0.0,0.4]:art.box(p,Vector3(x,1.62,z),Vector3(0.025,0.64,0.025),DARK_STEEL)

static func _shelter_glass(p:Node3D)->void:
	# Two thin panes, one surface/material, no duplicate back faces or shadow pass.
	# Vehicle glazing continues to use the existing opaque miniature material.
	if _shelter_glass_material==null:
		_shelter_glass_material=StandardMaterial3D.new()
		_shelter_glass_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		_shelter_glass_material.albedo_color=Color(0.68,0.82,0.80,0.18)
		_shelter_glass_material.roughness=0.18
		_shelter_glass_material.metallic_specular=0.65
		_shelter_glass_material.cull_mode=BaseMaterial3D.CULL_DISABLED
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(st,Vector3(-1.56,0.3,-0.66),Vector3(1.56,0.3,-0.66),Vector3(1.56,2.1,-0.66),Vector3(-1.56,2.1,-0.66),Vector3.BACK)
	_quad(st,Vector3(-1.6,0.3,-0.61),Vector3(-1.6,0.3,0.45),Vector3(-1.6,2.1,0.45),Vector3(-1.6,2.1,-0.61),Vector3.RIGHT)
	var pane:=MeshInstance3D.new();pane.name="ShelterGlass"
	pane.mesh=st.commit();pane.material_override=_shelter_glass_material
	pane.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(pane)

static func _glazed_shelter(art,p:Node3D)->void:
	art.box(p,Vector3(0,0.015,0),Vector3(3.5,0.03,1.8),CONCRETE)
	for x in [-1.6,0.0,1.6]:art.box(p,Vector3(x,1.18,-0.66),Vector3(0.08,2.3,0.08),STEEL)
	for x in [-1.6,1.6]:art.box(p,Vector3(x,1.23,0.62),Vector3(0.08,2.4,0.08),STEEL)
	for y in [0.27,2.13]:art.box(p,Vector3(0,y,-0.66),Vector3(3.2,0.06,0.06),STEEL)
	for y in [0.27,2.13]:art.box(p,Vector3(-1.6,y,-0.08),Vector3(0.06,0.06,1.12),STEEL)
	# Advertising case closes the downstream end; pale faces, no emissive light.
	art.models.box(p,Vector3(1.6,1.2,-0.05),Vector3(0.16,1.86,1.1),STEEL)
	for side in [-1.0,1.0]:art.box(p,Vector3(1.6+side*0.083,1.2,-0.05),Vector3(0.008,1.62,0.94),Color("d6d2b1"))
	_box(art,p,Vector3(0,2.42,0),Vector3.RIGHT,Vector3(0,0.08,1.56),Vector3(3.5,0.07,1.62),STEEL)
	art.box(p,Vector3(0,2.44,0.8),Vector3(3.5,0.14,0.04),DARK_STEEL)
	art.box(p,Vector3(-0.6,2.44,0.825),Vector3(1.2,0.07,0.01),PALE)
	_sweep(art,p,[Vector3(-1.75,2.34,-0.8),Vector3(1.75,2.34,-0.8)],0.04,GALV,6)
	for z in [-0.56,-0.47,-0.38]:art.box(p,Vector3(0,0.5,z),Vector3(2.9,0.04,0.07),WOOD)
	for x in [-1.2,0.0,1.2]:art.box(p,Vector3(x,0.255,-0.47),Vector3(0.05,0.45,0.24),DARK_STEEL)
	art.box(p,Vector3(1.38,1.45,0.69),Vector3(0.5,0.66,0.05),STEEL)
	art.box(p,Vector3(1.38,1.45,0.717),Vector3(0.42,0.56,0.006),PALE)
	_stop_flag(art,p,Vector3(2.2,0,0.72),true)

static func _stop_flag(art,p:Node3D,at:Vector3,disc:bool)->void:
	art.models.box(p,at+Vector3(0,0.04,0),Vector3(0.24,0.08,0.24),CONCRETE)
	art.models.tube(p,at+Vector3(0,0.08,0),at+Vector3(0,2.62,0),0.04,STEEL)
	art.models.tube(p,at+Vector3(0,2.62,0),at+Vector3(0,2.66,0),0.05,DARK_STEEL)
	if disc:
		_slab(art,p,_circle(0.24,14),0.02,Transform3D(Basis.IDENTITY,at+Vector3(0,2.42,0.05)),WARN)
		_slab(art,p,_circle(0.2,14),0.024,Transform3D(Basis.IDENTITY,at+Vector3(0,2.42,0.052)),PALE)
		# Original pictogram: coach body, windows and wheels.
		art.box(p,at+Vector3(0,2.44,0.067),Vector3(0.22,0.1,0.008),IRON)
		art.box(p,at+Vector3(0,2.46,0.071),Vector3(0.18,0.03,0.006),PALE)
		for x in [-0.06,0.06]:_slab(art,p,_circle(0.022,8),0.01,Transform3D(Basis.IDENTITY,at+Vector3(x,2.385,0.067)),IRON)
		art.box(p,at+Vector3(0,2.0,0.05),Vector3(0.42,0.24,0.02),SIGN_GREEN)
		art.box(p,at+Vector3(0,2.0,0.062),Vector3(0.3,0.05,0.006),PALE)
	else:
		art.box(p,at+Vector3(0,2.38,0.05),Vector3(0.4,0.3,0.02),PALE)
		for y in [2.27,2.49]:art.box(p,at+Vector3(0,y,0.062),Vector3(0.36,0.025,0.006),SIGN_GREEN)
		art.box(p,at+Vector3(0,2.38,0.062),Vector3(0.18,0.07,0.006),IRON)
		art.box(p,at+Vector3(0,1.55,0.06),Vector3(0.28,0.4,0.04),STEEL)
		art.box(p,at+Vector3(0,1.55,0.082),Vector3(0.22,0.32,0.006),PALE)
		_disc(art,p,at+Vector3(0,0.35,-0.22),0.18,0.5,CABINET_GREEN,10)
		_disc(art,p,at+Vector3(0,0.85,-0.22),0.19,0.03,DARK_STEEL,10)
		art.box(p,at+Vector3(0,0.75,-0.05),Vector3(0.1,0.06,0.06),DARK_STEEL)

static func _timber_shelter(art,p:Node3D)->void:
	# Rural lean-to: boarded back and cheeks on pad stones, corrugated sheet roof.
	var posts:=[Vector3(-1.35,0,-0.7),Vector3(1.35,0,-0.7),Vector3(-1.35,0,0.6),Vector3(1.35,0,0.6)]
	for q in posts:
		var top:=2.05 if q.z<0 else 2.35
		art.models.box(p,q+Vector3(0,0.06,0),Vector3(0.26,0.12,0.26),STONE)
		art.box(p,q+Vector3(0,(0.12+top)/2.0,0),Vector3(0.12,top-0.12,0.12),WOOD)
	art.box(p,Vector3(0,0.17,-0.7),Vector3(2.82,0.1,0.12),WOOD)
	for i in 9:
		art.box(p,Vector3(0,0.3+i*0.19,-0.775+(i%2)*0.008),Vector3(2.82,0.2,0.025),WOOD.darkened(0.08*(i%3)))
	for side in [-1.0,1.0]:
		art.box(p,Vector3(side*1.35,1.62,-0.05),Vector3(0.1,0.08,1.3),WOOD)
		for i in 7:
			art.box(p,Vector3(side*1.425,0.3+i*0.19,-0.255),Vector3(0.025,0.2,0.9),WOOD.darkened(0.08*((i+1)%3)))
	for z in [-0.7,0.6]:art.box(p,Vector3(0,(2.07 if z<0 else 2.37),z),Vector3(2.84,0.1,0.14),WOOD)
	var low:=Vector3(0,2.15,-0.92);var high:=Vector3(0,2.47,0.84)
	var slope:=(high-low).normalized()
	for x in [-1.35,0.0,1.35]:_beam(art,p,low+Vector3(x,-0.04,0),high+Vector3(x,-0.04,0),0.12,0.08,WOOD)
	var normal:=slope.cross(Vector3.RIGHT)
	var sheet_mid:=(low+high)/2.0+normal*0.03
	_box(art,p,sheet_mid,Vector3.RIGHT,slope,Vector3(3.06,0.02,low.distance_to(high)+0.06),SHEET)
	for i in 16:
		var x:=-1.5+i*0.2
		_sweep(art,p,[low+Vector3(x,0,0)+normal*0.05-slope*0.03,high+Vector3(x,0,0)+normal*0.05+slope*0.03],0.022,SHEET,5,true)
	art.box(p,Vector3(0,0.45,-0.55),Vector3(2.4,0.05,0.3),WOOD)
	for x in [-0.9,0.9]:art.models.box(p,Vector3(x,0.21,-0.55),Vector3(0.25,0.42,0.28),STONE_DARK)
	_stop_flag(art,p,Vector3(-1.95,0,0.78),false)

# --- utilities ----------------------------------------------------------------

static func _louvre(art,p:Node3D,center:Vector3,across:Vector3,outward:Vector3,width:float,height:float)->void:
	# Recessed dark frame with pitched rain-shedding slats.
	var face_x:=across.normalized();var face_n:=outward.normalized()
	_box(art,p,center,face_x,face_n,Vector3(width,height,0.012),IRON)
	var slats:=int(height/0.06)
	for k in slats:
		var y:=-height/2.0+(k+0.5)*height/slats
		var tilt:=(face_n*0.6+Vector3.DOWN*0.8).normalized()
		_box(art,p,center+Vector3(0,y,0)+face_n*0.022,face_x,tilt,Vector3(width-0.03,0.01,0.065),CABINET_GREEN.darkened(0.15))

static func _pad_transformer(art,p:Node3D)->void:
	art.models.box(p,Vector3(0,0.075,0),Vector3(1.9,0.15,1.5),CONCRETE)
	art.models.box(p,Vector3(0,0.78,0),Vector3(1.5,1.26,1.1),CABINET_GREEN)
	art.box(p,Vector3(0,1.45,0),Vector3(1.62,0.08,1.22),CABINET_GREEN.darkened(0.12))
	art.box(p,Vector3(0,1.5,0),Vector3(1.4,0.03,0.5),CABINET_GREEN.darkened(0.12))
	art.box(p,Vector3(0,0.78,0.556),Vector3(0.012,1.12,0.012),IRON)
	for x in [-0.37,0.37]:
		for y in [0.45,1.08]:_louvre(art,p,Vector3(x,y,0.556),Vector3.RIGHT,Vector3.BACK,0.5,0.3)
	_louvre(art,p,Vector3(0.756,0.85,0),Vector3.FORWARD,Vector3.RIGHT,0.6,0.42)
	for side in [-1.0,1.0]:
		for y in [0.4,0.8,1.2]:art.models.tube(p,Vector3(side*0.73,y-0.05,0.565),Vector3(side*0.73,y+0.05,0.565),0.018,IRON)
	art.box(p,Vector3(0.08,0.78,0.565),Vector3(0.04,0.16,0.02),DARK_STEEL)
	art.box(p,Vector3(0.08,0.78,0.578),Vector3(0.05,0.05,0.012),WARN)
	_slab(art,p,[Vector2(-0.1,-0.08),Vector2(0.1,-0.08),Vector2(0,0.09)],0.008,Transform3D(Basis.IDENTITY,Vector3(-0.37,0.77,0.56)),WARN)
	for x in [-0.65,0.65]:
		for z in [-0.45,0.45]:_torus(art,p,Vector3(x,1.53,z),Vector3.RIGHT,0.035,0.01,DARK_STEEL,10,4)
	for x in [-0.4,0.4]:
		_sweep(art,p,[Vector3(x,0,-0.98),Vector3(x,0.07,-0.98),Vector3(x,0.12,-0.92),Vector3(x,0.12,-0.75)],0.05,Color("4d4535"),8)

static func _fenced_transformer(art,p:Node3D)->void:
	var tank:=Color("707367")
	art.models.box(p,Vector3(0,0.1,-0.05),Vector3(2.6,0.2,2.0),CONCRETE)
	art.models.box(p,Vector3(0,0.85,-0.1),Vector3(1.2,1.3,0.8),tank)
	art.box(p,Vector3(0,1.52,-0.1),Vector3(1.26,0.04,0.86),tank.darkened(0.15))
	for side in [-1.0,1.0]:
		for k in 7:art.box(p,Vector3(side*0.8,0.85,-0.4+k*0.1),Vector3(0.36,1.0,0.025),tank)
		for y in [0.38,1.32]:art.models.tube(p,Vector3(side*0.6,y,-0.1),Vector3(side*0.98,y,-0.1),0.05,tank.darkened(0.1))
		for y in [0.38,1.32]:art.models.tube(p,Vector3(side*0.8,y,-0.43),Vector3(side*0.8,y,0.23),0.035,tank.darkened(0.1))
	for x in [-0.35,0.35]:art.box(p,Vector3(x,1.59,-0.35),Vector3(0.08,0.1,0.2),DARK_STEEL)
	art.models.tube(p,Vector3(-0.5,1.78,-0.35),Vector3(0.5,1.78,-0.35),0.16,tank)
	art.models.tube(p,Vector3(0.2,1.54,-0.25),Vector3(0.2,1.66,-0.3),0.025,DARK_STEEL)
	for x in [-0.35,0.0,0.35]:
		_disc(art,p,Vector3(x,1.54,0.08),0.07,0.05,DARK_STEEL,8)
		art.models.tube(p,Vector3(x,1.59,0.08),Vector3(x,2.0,0.08),0.035,PORCELAIN)
		for k in 4:_disc(art,p,Vector3(x,1.64+k*0.09,0.08),0.075,0.025,PORCELAIN,10)
		_disc(art,p,Vector3(x,2.0,0.08),0.03,0.06,GALV,6)
	for x in [-0.3,-0.1,0.1,0.3]:
		art.models.tube(p,Vector3(x,1.22,0.3),Vector3(x,1.22,0.44),0.03,PORCELAIN)
	art.box(p,Vector3(0,0.62,0.4),Vector3(0.8,0.4,0.2),tank.darkened(0.08))
	art.models.tube(p,Vector3(0,0.2,0.42),Vector3(0,0.42,0.42),0.06,Color("4d4535"))
	art.box(p,Vector3(0.42,1.05,0.305),Vector3(0.18,0.12,0.012),PALE)
	# Galvanised palisade: posts, two rails and pointed pales, double gate on +Z.
	var x0:=-1.75;var x1:=1.75;var z0:=-1.45;var z1:=1.45
	var corners:=[Vector2(x0,z0),Vector2(x1,z0),Vector2(x1,z1),Vector2(x0,z1)]
	var pale:=[Vector2(-0.032,0.03),Vector2(0.032,0.03),Vector2(0.032,1.75),Vector2(0,1.86),Vector2(-0.032,1.75)]
	for i in 4:
		var a:Vector2=corners[i];var b:Vector2=corners[(i+1)%4]
		var d:=(b-a).normalized();var inward:=Vector2(-d.y,d.x)
		var yaw:=-atan2(d.y,d.x)
		var length:=a.distance_to(b)
		art.box(p,Vector3(a.x,1.0,a.y),Vector3(0.08,2.0,0.08),GALV)
		if i!=2:
			var mid:=a.lerp(b,0.5)
			art.box(p,Vector3(mid.x,1.0,mid.y),Vector3(0.08,2.0,0.08),GALV)
		# Rails stop at the gate posts on the +Z side.
		var runs:=[[a,b]] if i!=2 else [[a,Vector2(0.66,z1)],[Vector2(-0.66,z1),b]]
		for run in runs:
			var s:Vector2=run[0]+inward*0.03;var e:Vector2=run[1]+inward*0.03
			for y in [0.35,1.55]:_beam(art,p,Vector3(s.x,y,s.y),Vector3(e.x,y,e.y),0.05,0.04,GALV)
		var count:=int(length/0.16)
		for k in range(1,count):
			var q:=a.lerp(b,float(k)/count)
			if i==2 and absf(q.x)<0.66:continue
			_slab(art,p,pale,0.018,Transform3D(Basis(Vector3.UP,yaw),Vector3(q.x,0,q.y)),GALV)
	for side in [-1.0,1.0]:
		art.box(p,Vector3(side*0.66,1.0,z1),Vector3(0.12,2.0,0.12),STEEL)
		var cx:float=side*0.33
		for y in [0.12,0.35,1.55]:art.box(p,Vector3(cx,y,z1-0.03),Vector3(0.58,0.05,0.04),GALV)
		for edge in [-1.0,1.0]:art.box(p,Vector3(cx+edge*0.27,0.95,z1-0.03),Vector3(0.04,1.7,0.04),GALV)
		for k in 4:
			_slab(art,p,pale,0.018,Transform3D(Basis.IDENTITY,Vector3(cx-0.225+k*0.15,0.08,z1)),GALV)
	art.box(p,Vector3(0.33,1.1,z1+0.02),Vector3(0.3,0.22,0.01),PALE)
	_slab(art,p,[Vector2(-0.07,-0.06),Vector2(0.07,-0.06),Vector2(0,0.06)],0.006,Transform3D(Basis.IDENTITY,Vector3(0.33,1.1,z1+0.028)),WARN)
	art.box(p,Vector3(0,0.95,z1-0.03),Vector3(0.1,0.08,0.06),DARK_STEEL)

static func _pin_insulator(art,p:Node3D,base:Vector3)->void:
	art.models.tube(p,base,base+Vector3(0,0.08,0),0.012,GALV)
	art.models.tube(p,base+Vector3(0,0.06,0),base+Vector3(0,0.26,0),0.03,PORCELAIN)
	for k in 3:_disc(art,p,base+Vector3(0,0.08+k*0.06,0),0.068-k*0.01,0.022,PORCELAIN,10)

static func _strain_string(art,p:Node3D,a:Vector3,b:Vector3)->void:
	var dir:=(b-a).normalized()
	_sweep(art,p,[a,b],0.012,GALV,5)
	for k in 3:
		var c:=a.lerp(b,0.25+k*0.25)
		_sweep(art,p,[c-dir*0.012,c+dir*0.012],0.07,PORCELAIN,10)

static func _guy(art,p:Node3D,top:Vector3,ground:Vector3)->void:
	var dir:=(ground-top).normalized()
	var rod_top:=ground-dir*0.35
	_sweep(art,p,[top,rod_top],0.01,IRON,5,false)
	_sweep(art,p,[rod_top,ground+Vector3(0,0.1,0)],0.018,GALV,6)
	_sweep(art,p,[rod_top-dir*1.6,rod_top-dir*0.05],0.034,WARN,6)
	_sweep(art,p,[top.lerp(rod_top,0.35)-dir*0.07,top.lerp(rod_top,0.35)+dir*0.07],0.04,PORCELAIN,6)
	art.models.box(p,Vector3(ground.x,0.05,ground.z),Vector3(0.28,0.1,0.28),CONCRETE)

static func _timber_pole(art,p:Node3D)->void:
	art.models.tube(p,Vector3.ZERO,Vector3(0,7.2,0),0.15,TIMBER,0.11)
	art.models.tube(p,Vector3(0,7.2,0),Vector3(0,7.25,0),0.12,IRON,0.08)
	art.box(p,Vector3(0,6.75,0.175),Vector3(2.1,0.1,0.1),WOOD)
	for side in [-1.0,1.0]:
		_beam(art,p,Vector3(side*0.66,6.7,0.16),Vector3(0,6.15,0.14),0.04,0.05,STEEL)
		_pin_insulator(art,p,Vector3(side*0.9,6.8,0.175))
	_pin_insulator(art,p,Vector3(0,7.25,0))
	art.box(p,Vector3(0,6.75,0.115),Vector3(0.1,0.16,0.02),GALV)
	for k in 8:
		var side:=1.0 if k%2==0 else -1.0
		art.models.tube(p,Vector3(side*0.1,2.4+k*0.45,0),Vector3(side*0.28,2.4+k*0.45,0),0.012,GALV)
	art.box(p,Vector3(0,2.0,0.142),Vector3(0.12,0.18,0.012),PALE)
	for y in [1.96,2.04]:art.box(p,Vector3(0,y,0.15),Vector3(0.08,0.02,0.006),IRON)
	_guy(art,p,Vector3(0,6.05,-0.12),Vector3(0,0,-2.6))

static func _concrete_pole(art,p:Node3D)->void:
	var models=art.models
	models.shell(p,[models.octagon(0.17,0.17,0.17,0.0,0.05),models.octagon(0.1,0.1,0.1,6.6,0.03)],CONCRETE)
	_disc(art,p,Vector3.ZERO,0.24,0.25,CONCRETE_DARK,8)
	_disc(art,p,Vector3(0,6.6,0),0.115,0.05,IRON,8)
	# Secondary spool rack on the +Z face feeding a service cable with a drip loop.
	art.box(p,Vector3(0,5.85,0.12),Vector3(0.05,0.8,0.02),GALV)
	for k in 4:
		var y:=5.55+k*0.2
		for dy in [-0.055,0.055]:art.box(p,Vector3(0,y+dy,0.175),Vector3(0.06,0.01,0.11),GALV)
		_disc(art,p,Vector3(0,y-0.045,0.2),0.045,0.09,PORCELAIN,10)
	art.models.tube(p,Vector3(0.17,1.6,0),Vector3(0.17,5.2,0),0.035,GALV)
	_sweep(art,p,[Vector3(0.17,5.2,0),Vector3(0.17,5.32,0),Vector3(0.17,5.38,0.05),Vector3(0.17,5.36,0.11)],0.04,GALV,8)
	_sweep(art,p,[Vector3(0,5.55,0.235),Vector3(0.08,5.42,0.3),Vector3(0.15,5.25,0.28),Vector3(0.17,5.29,0.17),Vector3(0.17,5.34,0.12)],0.016,CABLE,5)
	art.models.box(p,Vector3(0.24,1.4,0),Vector3(0.16,0.4,0.28),DARK_STEEL)
	art.models.tube(p,Vector3(0.24,0.0,0),Vector3(0.24,1.2,0),0.035,GALV)
	# Outreach street-light arm (no light source) to +X.
	_sweep(art,p,[Vector3(0.08,5.4,0),Vector3(0.4,5.62,0),Vector3(0.8,5.76,0),Vector3(1.2,5.82,0)],0.035,STEEL,8)
	_beam(art,p,Vector3(0.1,5.05,0),Vector3(0.6,5.68,0),0.03,0.03,STEEL)
	art.box(p,Vector3(1.33,5.8,0),Vector3(0.5,0.13,0.26),STEEL)
	art.box(p,Vector3(1.35,5.725,0),Vector3(0.4,0.02,0.2),Color("d6d2b1"))
	art.box(p,Vector3(0,2.6,0.155),Vector3(0.16,0.14,0.012),WARN)
	art.box(p,Vector3(0,2.2,0.16),Vector3(0.12,0.18,0.012),PALE)

static func _three_phase_span(art,p:Node3D)->void:
	var phases:=[-0.75,0.0,0.75]
	for end in [-1.0,1.0]:
		var x:float=end*7.0
		art.models.tube(p,Vector3(x,0,0),Vector3(x,6.6,0),0.14,TIMBER,0.1)
		art.models.tube(p,Vector3(x,6.6,0),Vector3(x,6.64,0),0.11,IRON,0.08)
		var arm_x:float=x-end*0.16
		art.box(p,Vector3(arm_x,6.25,0),Vector3(0.1,0.1,1.8),WOOD)
		for side in [-1.0,1.0]:_beam(art,p,Vector3(arm_x,6.2,side*0.6),Vector3(x-end*0.12,5.7,0),0.04,0.05,STEEL)
		for z in phases:_strain_string(art,p,Vector3(arm_x-end*0.05,6.25,z),Vector3(arm_x-end*0.5,6.25,z))
		_guy(art,p,Vector3(x+end*0.12,5.9,0),Vector3(x+end*1.9,0,0))
	for z in phases:
		var points:=_span(Vector3(-6.34,6.25,z),Vector3(6.34,6.25,z),0.55,20)
		_sweep(art,p,points,0.02,CABLE,5,false)
		if z==0.0:
			for t in [0.33,0.66]:
				var q:Vector3=points[int(t*20)]
				_sweep(art,p,[q-Vector3(0.09,0,0),q+Vector3(0.09,0,0)],0.045,WARN,6)

static func _service_drop(art,p:Node3D)->void:
	var pole:=Vector3(-3.8,0,0)
	art.models.tube(p,pole,pole+Vector3(0,6.0,0),0.14,TIMBER,0.1)
	art.models.tube(p,pole+Vector3(0,6.0,0),pole+Vector3(0,6.04,0),0.11,IRON,0.08)
	art.box(p,pole+Vector3(0.115,5.6,0),Vector3(0.02,0.5,0.05),GALV)
	for y in [5.48,5.72]:
		for dy in [-0.055,0.055]:art.box(p,pole+Vector3(0.17,y+dy,0),Vector3(0.11,0.01,0.06),GALV)
		_disc(art,p,pole+Vector3(0.2,y-0.045,0),0.045,0.09,PORCELAIN,10)
	for k in 6:art.models.tube(p,pole+Vector3(0,2.4+k*0.5,(1 if k%2==0 else -1)*0.09),pole+Vector3(0,2.4+k*0.5,(1 if k%2==0 else -1)*0.25),0.012,GALV)
	# Meter pillar and service mast with weatherhead.
	var mast:=Vector3(3.9,0,-0.05)
	art.models.box(p,Vector3(3.9,0.04,0),Vector3(0.72,0.08,0.46),CONCRETE)
	art.models.box(p,Vector3(3.9,0.66,0),Vector3(0.6,1.16,0.35),Color("8f8a77"))
	art.box(p,Vector3(3.9,1.26,0),Vector3(0.66,0.05,0.41),Color("8f8a77").darkened(0.15))
	art.box(p,Vector3(3.9,0.66,0.177),Vector3(0.008,1.0,0.008),IRON)
	art.box(p,Vector3(3.76,0.86,0.18),Vector3(0.16,0.12,0.008),art.models.glass)
	art.box(p,Vector3(4.02,0.72,0.18),Vector3(0.04,0.08,0.01),IRON)
	_louvre(art,p,Vector3(4.205,0.4,0),Vector3.FORWARD,Vector3.RIGHT,0.22,0.18)
	art.models.tube(p,mast+Vector3(0,1.28,0),mast+Vector3(0,3.3,0),0.04,GALV)
	_sweep(art,p,[mast+Vector3(0,3.3,0),mast+Vector3(0,3.42,0),mast+Vector3(-0.05,3.48,0),mast+Vector3(-0.11,3.45,0)],0.045,GALV,8)
	art.box(p,mast+Vector3(-0.07,3.15,0),Vector3(0.1,0.04,0.04),GALV)
	_disc(art,p,mast+Vector3(-0.12,3.08,0),0.04,0.08,PORCELAIN,10)
	# Twisted duplex drop: two conductors wound around a sagging centre line, drip loop at mast.
	var path:=_span(pole+Vector3(0.245,5.68,0),mast+Vector3(-0.16,3.12,0),0.45,40)
	path.append_array([mast+Vector3(-0.2,3.0,0),mast+Vector3(-0.19,3.1,0),mast+Vector3(-0.15,3.3,0),mast+Vector3(-0.12,3.4,0)])
	for strand in 2:
		var pts:=[]
		for i in path.size():
			var a:=TAU*(i*0.35+strand*0.5)
			var o:=Vector3(0,cos(a),sin(a))*0.018 if i<41 else Vector3(0,0,(strand-0.5)*0.03)
			pts.append(path[i]+o)
		_sweep(art,p,pts,0.012,CABLE,4,false)

static func _pipe_headwall(art,p:Node3D)->void:
	# Outfall discharges toward +Z; datum is the apron/bed level.
	art.models.box(p,Vector3(0,0.7,-0.25),Vector3(2.6,1.4,0.36),CONCRETE)
	art.models.box(p,Vector3(0,1.45,-0.25),Vector3(2.75,0.1,0.46),CONCRETE_DARK)
	for side in [-1.0,1.0]:
		var dir:=Vector3(side*0.574,0,0.819)
		var yaw:=atan2(-dir.z,dir.x)
		_slab(art,p,[Vector2(0,0),Vector2(1.1,0),Vector2(1.1,0.45),Vector2(0,1.4)],0.28,Transform3D(Basis(Vector3.UP,yaw),Vector3(side*1.15,0,-0.2)),CONCRETE)
		art.box(p,Vector3(side*0.85,0.95,-0.065),Vector3(0.08,0.08,0.01),VOID)
	art.box(p,Vector3(0,0.06,0.53),Vector3(2.3,0.12,1.2),CONCRETE_DARK)
	art.models.box(p,Vector3(0,0.18,1.06),Vector3(2.3,0.12,0.12),CONCRETE)
	art.models.box(p,Vector3(0,0.15,0.06),Vector3(0.9,0.1,0.3),CONCRETE)
	# Annular pipe mouth, dark bore and a hinged flap valve hanging slightly open.
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c:=Vector3(0,0.62,0)
	for i in 16:
		var a0:=Vector3(cos(TAU*i/16.0),sin(TAU*i/16.0),0);var a1:=Vector3(cos(TAU*(i+1)/16.0),sin(TAU*(i+1)/16.0),0)
		var back:=c+Vector3(0,0,-0.1);var face:=c+Vector3(0,0,0.22)
		_quad(st,back+a0*0.42,face+a0*0.42,face+a1*0.42,back+a1*0.42,a0+a1)
		_quad(st,back+a0*0.34,face+a0*0.34,face+a1*0.34,back+a1*0.34,-(a0+a1))
		_quad(st,face+a0*0.34,face+a0*0.42,face+a1*0.42,face+a1*0.34,Vector3.BACK)
	_commit(art,p,st,CONCRETE_DARK)
	_slab(art,p,_circle(0.34,16),0.02,Transform3D(Basis.IDENTITY,c+Vector3(0,0,-0.08)),VOID)
	art.box(p,Vector3(0,1.08,0.2),Vector3(0.3,0.08,0.1),IRON)
	_slab(art,p,_circle(0.43,16,Vector2(0,-0.44)),0.04,Transform3D(Basis(Vector3.RIGHT,-0.22),Vector3(0,1.05,0.26)),IRON)
	art.box(p,Vector3(0,1.05,0.255),Vector3(0.36,0.05,0.05),DARK_STEEL)
	# Authored scour-protection pockets, not a perimeter necklace. Positions,
	# dimensions and bearings are fixed; the central discharge and soil gaps stay open.
	var stones:=[
		[Vector3(-1.70,0,0.48),Vector3(0.46,0.26,0.38),-0.20],
		[Vector3(-1.48,0,0.76),Vector3(0.48,0.32,0.43),0.32],
		[Vector3(-1.75,0,0.94),Vector3(0.36,0.20,0.34),-0.48],
		[Vector3(-1.43,0,1.13),Vector3(0.42,0.25,0.48),0.17],
		[Vector3(-1.20,0,1.41),Vector3(0.53,0.29,0.44),-0.10],
		[Vector3(-0.85,0,1.35),Vector3(0.29,0.18,0.30),0.61],
		[Vector3(1.73,0,0.67),Vector3(0.42,0.30,0.46),0.12],
		[Vector3(1.45,0,0.91),Vector3(0.48,0.23,0.35),-0.34],
		[Vector3(1.68,0,1.13),Vector3(0.36,0.19,0.35),0.27],
		[Vector3(1.39,0,1.40),Vector3(0.49,0.33,0.46),-0.16],
		[Vector3(0.93,0,1.43),Vector3(0.38,0.22,0.42),0.41],
	]
	var rng:=RandomNumberGenerator.new();rng.seed=4137 # shape only; never placement
	for i in stones.size():
		var stone:Array=stones[i]
		_rock(art,p,stone[0],stone[1],rng,STONE if i%3 else STONE_DARK)
		p.get_child(p.get_child_count()-1).rotation.y=stone[2]
	for x in [-1.2,0.0,1.2]:art.models.tube(p,Vector3(x,1.5,-0.25),Vector3(x,2.42,-0.25),0.03,GALV)
	for y in [1.98,2.4]:art.models.tube(p,Vector3(-1.25,y,-0.25),Vector3(1.25,y,-0.25),0.025,GALV)

static func _box_culvert(art,p:Node3D)->void:
	# Twin-cell box culvert, baffle apron and an inclined bar screen leaning on the parapet.
	art.models.box(p,Vector3(0,0.1,-0.5),Vector3(3.0,0.2,1.4),CONCRETE)
	for x in [-1.35,1.35]:art.models.box(p,Vector3(x,0.8,-0.5),Vector3(0.3,1.2,1.4),CONCRETE)
	art.models.box(p,Vector3(0,0.8,-0.5),Vector3(0.25,1.2,1.4),CONCRETE)
	art.models.box(p,Vector3(0,1.5,-0.5),Vector3(3.0,0.2,1.4),CONCRETE)
	art.models.box(p,Vector3(0,1.75,-0.05),Vector3(3.2,0.3,0.3),CONCRETE_DARK)
	for x in [-0.6375,0.6375]:
		art.box(p,Vector3(x,0.8,-1.15),Vector3(1.05,1.18,0.02),VOID)
		art.box(p,Vector3(x,0.205,-0.5),Vector3(1.05,0.01,1.3),Color("4d4a42"))
	for side in [-1.0,1.0]:
		_slab(art,p,[Vector2(0,0),Vector2(1.05,0),Vector2(1.05,0.5),Vector2(0,1.9)],0.3,Transform3D(Basis(Vector3.UP,-PI/2.0),Vector3(side*1.65,0,-0.2)),CONCRETE)
	art.models.box(p,Vector3(0,0.1,0.5),Vector3(3.0,0.2,1.0),CONCRETE_DARK)
	for x in [-0.9,-0.3,0.3,0.9]:art.models.box(p,Vector3(x,0.32,0.82),Vector3(0.28,0.24,0.28),CONCRETE)
	var foot:=0.62;var lean_top:=Vector3(0,1.86,0.13);var lean_bottom:=Vector3(0,0.2,foot)
	for x in [-1.2,1.2]:_beam(art,p,lean_bottom+Vector3(x,0,0),lean_top+Vector3(x,0,0),0.08,0.06,STEEL,Vector3.BACK)
	for y in [0.0,1.0]:
		var q:=lean_bottom.lerp(lean_top,y)
		_beam(art,p,q+Vector3(-1.24,0,0),q+Vector3(1.24,0,0),0.06,0.08,STEEL)
	for k in 23:
		var x:=-1.1+k*0.1
		_beam(art,p,lean_bottom+Vector3(x,0,0),lean_top+Vector3(x,0,0),0.015,0.06,DARK_STEEL,Vector3.BACK)
	for x in [-1.2,1.2]:art.box(p,Vector3(x,0.215,foot),Vector3(0.16,0.03,0.16),IRON)
	for x in [-0.8,0.8]:_torus(art,p,lean_top+Vector3(x,0.07,0.0),Vector3.RIGHT,0.045,0.012,DARK_STEEL,10,4)
	for x in [-1.4,0.0,1.4]:art.models.tube(p,Vector3(x,1.9,-0.1),Vector3(x,2.8,-0.1),0.03,GALV)
	for y in [2.36,2.78]:art.models.tube(p,Vector3(-1.45,y,-0.1),Vector3(1.45,y,-0.1),0.025,GALV)
