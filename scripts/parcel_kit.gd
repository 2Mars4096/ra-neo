extends RefCounted

# Shared construction kit for authored parcel buildings.
# Geometry is authored in a street-facing local frame: x runs along the frontage,
# z runs into the parcel and the street face is at -z. finish() rotates the
# pieces into the world parcel and flattens them so bake_model() batches them.
# Every solid must stay inside [-w/2,w/2] x [-d/2,d/2]; tests verify this.

# Rect position -> [design, street side]. Facing comes from the scenario road
# graph (verified by hand against resources/scenarios.json); unknown parcels
# fall back to an index-based design that still faces north.
const DESIGNS:={
	# CANAL WATCH
	"24,29":["cafe","north"],"24,17":["terrace","south"],"15,14":["villa","south"],
	"46,31":["chapel","west"],"57,55":["warehouse","north"],
	"43,14":["shelled_house","west"],"61,27":["gutted_shed","south"],"62,15":["roofless_barn","east"],
	# FRONTIER SKIRMISH
	"34,24":["flat_block","east"],"51,18":["farmstead","west"],"44,47":["corner_collapse","west"],
}
const INTACT:=["cafe","terrace","villa","chapel","warehouse","flat_block","farmstead"]
const RUINS:=["shelled_house","gutted_shed","roofless_barn","corner_collapse"]

# Restrained shared palette; few distinct architecture materials keep batches low.
const OCHRE:=Color("a08a62")
const CREAM:=Color("a39a80")
const RENDER:=Color("8a8a7e")
const BRICK:=Color("6e4b3b")
const STONE:=Color("968c74")
const CONCRETE:=Color("85847a")
const TERRACOTTA:=Color("7d5640")
const SLATE:=Color("4e585b")
const SHEET:=Color("5d6461")
const GLASS:=Color("26363a")
const DARK:=Color("1f2522")
const TIMBER:=Color("5f523d")
const IRON:=Color("33392f")
const TRIM:=Color("b0a68f")

static func design(r:Rect2,index:int,ruin:bool,specification:Dictionary={})->Array:
	if not specification.is_empty():return [specification.design,specification.facing]
	var key:="%d,%d"%[int(r.position.x),int(r.position.y)]
	if DESIGNS.has(key):return DESIGNS[key]
	var pool:Array=RUINS if ruin else INTACT
	return [pool[index%pool.size()],"north"]

var art
var parent:Node3D
var pivot:Node3D
var w:float
var d:float
var rng:=RandomNumberGenerator.new()

func _init(art_ref,parent_node:Node3D,r:Rect2,facing:String,seed_value:int)->void:
	art=art_ref;parent=parent_node
	rng.seed=seed_value
	var angle:float={"north":0.0,"south":PI,"west":PI/2,"east":-PI/2}[facing]
	var across:bool=facing in ["west","east"]
	w=r.size.y if across else r.size.x
	d=r.size.x if across else r.size.y
	pivot=Node3D.new()
	pivot.transform=Transform3D(Basis(Vector3.UP,angle),Vector3(r.get_center().x,0,r.get_center().y))
	parent.add_child(pivot)

# Reparent all pieces into the building root with composed transforms.
func finish()->void:
	for piece in pivot.get_children():
		var t:Transform3D=pivot.transform*piece.transform
		pivot.remove_child(piece);parent.add_child(piece);piece.transform=t
	pivot.free()

# --- Primitive pieces -------------------------------------------------------

func paint(color:Color)->Material:
	return art.material(color)

func wallmat(color:Color)->Material:
	return art.architecture_material(color,0)

func roofmat(color:Color)->Material:
	return art.architecture_material(color,1)

func metalmat(color:Color)->Material:
	return art.architecture_material(color,2)

# Axis-aligned block from extents; material defaults to batched vertex paint.
func blk(x0:float,x1:float,y0:float,y1:float,z0:float,z1:float,color:Color,material:Material=null)->MeshInstance3D:
	var node:MeshInstance3D=art.box(pivot,Vector3((x0+x1)/2,(y0+y1)/2,(z0+z1)/2),Vector3(absf(x1-x0),absf(y1-y0),absf(z1-z0)),color)
	if material!=null:node.material_override=material
	return node

func tube(a:Vector3,b:Vector3,radius:float,color:Color,material:Material=null)->MeshInstance3D:
	var node:MeshInstance3D=art.models.tube(pivot,a,b,radius,color)
	node.material_override=material if material!=null else paint(color)
	return node

# Thin disc: a short cylinder whose axis follows the given normal.
func disc(center:Vector3,normal:Vector3,radius:float,color:Color)->MeshInstance3D:
	return tube(center,center+normal*0.05,radius,color)

func plant(p:Vector3,size:float,seed_value:int,color:Color=Color("4c5737"))->void:
	var leaf:=MeshInstance3D.new()
	leaf.mesh=preload("res://scripts/foliage_mesh.gd").cluster(seed_value,true)
	leaf.position=p;leaf.scale=Vector3.ONE*size*2.0
	leaf.material_override=art.models.mat(color)
	pivot.add_child(leaf)

# Tall narrow cypress / poplar built from stacked opaque leaf clusters.
func cypress(x:float,z:float,height:float,seed_value:int)->void:
	tube(Vector3(x,0.0,z),Vector3(x,0.6,z),0.07,Color("4a4030"))
	var steps:=int(height/0.55)
	for i in steps:
		var t:=float(i)/maxf(1.0,steps-1)
		var radius:=0.24*(1.0-t*0.7)+0.06
		var leaf:=MeshInstance3D.new()
		leaf.mesh=preload("res://scripts/foliage_mesh.gd").cluster(seed_value+i,true)
		leaf.position=Vector3(x,0.7+i*0.55,z)
		leaf.scale=Vector3(radius*3.4,1.0,radius*3.4)
		leaf.material_override=art.models.mat(Color("34432f"))
		pivot.add_child(leaf)

# Convex solid from planar faces. Normals point away from the solid centroid.
func solid(faces:Array,material:Material)->MeshInstance3D:
	var center:=Vector3.ZERO
	var count:=0
	for face in faces:
		for p in face:
			center+=p
			count+=1
	center/=count
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in faces:
		var mid:=Vector3.ZERO
		for p in face:mid+=p
		mid/=face.size()
		var n:Vector3=(face[1]-face[0]).cross(face[2]-face[0])
		if n.length_squared()<1e-10 and face.size()>3:n=(face[2]-face[0]).cross(face[3]-face[0])
		n=n.normalized()
		var flip:=n.dot(mid-center)<0
		if flip:n=-n
		for i in range(1,face.size()-1):
			var a:Vector3=face[0]
			var b:Vector3=face[i]
			var c:Vector3=face[i+1]
			if flip:
				var swap:=b
				b=c
				c=swap
			st.set_normal(n)
			# Godot front faces are clockwise.
			for v in [a,c,b]:st.add_vertex(v)
	var node:=MeshInstance3D.new()
	node.mesh=st.commit()
	node.material_override=material
	pivot.add_child(node)
	return node

# Prism from a convex (z,y) profile extruded between x0 and x1.
func prism_x(profile:Array,x0:float,x1:float,material:Material)->MeshInstance3D:
	var a:=[];var b:=[]
	for q in profile:a.append(Vector3(x0,q.y,q.x));b.append(Vector3(x1,q.y,q.x))
	return _prism(a,b,material)

# Prism from a convex (x,y) profile extruded between z0 and z1.
func prism_z(profile:Array,z0:float,z1:float,material:Material)->MeshInstance3D:
	var a:=[];var b:=[]
	for q in profile:a.append(Vector3(q.x,q.y,z0));b.append(Vector3(q.x,q.y,z1))
	return _prism(a,b,material)

func _prism(a:Array,b:Array,material:Material)->MeshInstance3D:
	var faces:=[a,b]
	for i in a.size():
		var j:=(i+1)%a.size()
		faces.append([a[i],a[j],b[j],b[i]])
	return solid(faces,material)

# Roof plane: four top corners, extruded straight down by thickness.
func slab(top:Array,thickness:float,material:Material)->MeshInstance3D:
	var bottom:=[]
	for p in top:bottom.append(p-Vector3(0,thickness,0))
	return _prism(top,bottom,material)

# --- Building masses ----------------------------------------------------------

# Wall mass with gable ends built into the masonry. Ridge along "x" (eaves to
# the street) or "z" (gable end to the street).
func gabled_mass(x0:float,x1:float,z0:float,z1:float,h:float,rise:float,axis:String,material:Material)->void:
	if axis=="x":
		var zc:=(z0+z1)/2
		prism_x([Vector2(z0,0),Vector2(z1,0),Vector2(z1,h),Vector2(zc,h+rise),Vector2(z0,h)],x0,x1,material)
	else:
		var xc:=(x0+x1)/2
		prism_z([Vector2(x0,0),Vector2(x1,0),Vector2(x1,h),Vector2(xc,h+rise),Vector2(x0,h)],z0,z1,material)

func gable_roof(x0:float,x1:float,z0:float,z1:float,h:float,rise:float,axis:String,overhang:float,material:Material,ridge_color:Color=Color.TRANSPARENT)->void:
	var t:=0.14
	if axis=="x":
		var zc:=(z0+z1)/2;var drop:=rise/((z1-z0)/2)*overhang
		for side in [[z0-overhang,zc],[z1+overhang,zc]]:
			slab([Vector3(x0-overhang,h-drop+t,side[0]),Vector3(x1+overhang,h-drop+t,side[0]),Vector3(x1+overhang,h+rise+t,side[1]),Vector3(x0-overhang,h+rise+t,side[1])],t,material)
		if ridge_color.a>0:tube(Vector3(x0-overhang,h+rise+t,zc),Vector3(x1+overhang,h+rise+t,zc),0.07,ridge_color,material)
	else:
		var xc:=(x0+x1)/2;var drop:=rise/((x1-x0)/2)*overhang
		for side in [[x0-overhang,xc],[x1+overhang,xc]]:
			slab([Vector3(side[0],h-drop+t,z0-overhang),Vector3(side[0],h-drop+t,z1+overhang),Vector3(side[1],h+rise+t,z1+overhang),Vector3(side[1],h+rise+t,z0-overhang)],t,material)
		if ridge_color.a>0:tube(Vector3(xc,h+rise+t,z0-overhang),Vector3(xc,h+rise+t,z1+overhang),0.07,ridge_color,material)

# Hipped roof as one closed solid; inset=0 on a square plan gives a pyramid.
func hip_roof(x0:float,x1:float,z0:float,z1:float,h:float,rise:float,overhang:float,material:Material,ridge_along_x:bool=true)->void:
	var a:=Vector3(x0-overhang,h-0.05,z0-overhang);var b:=Vector3(x1+overhang,h-0.05,z0-overhang)
	var c:=Vector3(x1+overhang,h-0.05,z1+overhang);var e:=Vector3(x0-overhang,h-0.05,z1+overhang)
	var xc:=(x0+x1)/2;var zc:=(z0+z1)/2
	var half:float=maxf(0.0,((x1-x0)-(z1-z0))/2) if ridge_along_x else maxf(0.0,((z1-z0)-(x1-x0))/2)
	if half<0.02:
		var top:=Vector3(xc,h+rise,zc)
		solid([[a,b,c,e],[a,b,top],[b,c,top],[c,e,top],[e,a,top]],material)
	elif ridge_along_x:
		var r1:=Vector3(xc-half,h+rise,zc);var r2:=Vector3(xc+half,h+rise,zc)
		solid([[a,b,c,e],[a,b,r2,r1],[c,e,r1,r2],[e,a,r1],[b,c,r2]],material)
	else:
		var r1:=Vector3(xc,h+rise,zc-half);var r2:=Vector3(xc,h+rise,zc+half)
		solid([[a,b,c,e],[b,c,r2,r1],[e,a,r1,r2],[a,b,r1],[c,e,r2]],material)

# Single-pitch roof falling from the high z edge to the low z edge.
func lean_roof(x0:float,x1:float,z_high:float,z_low:float,y_high:float,y_low:float,material:Material)->void:
	slab([Vector3(x0,y_high+0.1,z_high),Vector3(x1,y_high+0.1,z_high),Vector3(x1,y_low+0.1,z_low),Vector3(x0,y_low+0.1,z_low)],0.1,material)

# Flat roof with parapet, coping and a darker membrane.
func parapet_roof(x0:float,x1:float,z0:float,z1:float,h:float,color:Color)->void:
	blk(x0+0.12,x1-0.12,h,h+0.04,z0+0.12,z1-0.12,Color("3f403b"))
	for e in [[x0,x1,z0,z0+0.14],[x0,x1,z1-0.14,z1],[x0,x0+0.14,z0,z1],[x1-0.14,x1,z0,z1]]:
		blk(e[0],e[1],h,h+0.42,e[2],e[3],color)
		blk(e[0]-0.03,e[1]+0.03,h+0.42,h+0.5,e[2]-0.03,e[3]+0.03,TRIM)

func chimney(x:float,z:float,base:float,top:float,color:Color,pots:int=2)->void:
	blk(x-0.28,x+0.28,base,top,z-0.24,z+0.24,color)
	blk(x-0.33,x+0.33,top,top+0.1,z-0.29,z+0.29,Color("5b554a"))
	for i in pots:
		var px:=x-0.12*(pots-1)+i*0.24
		tube(Vector3(px,top+0.1,z),Vector3(px,top+0.36,z),0.065,Color("8a5a40"))

# --- Facade pieces --------------------------------------------------------------

# Box aligned to a facade. n is an axis normal; u runs along the facade.
func fbox(p:Vector3,n:Vector3,u:float,v:float,depth:float,color:Color,material:Material=null)->MeshInstance3D:
	var size:=Vector3(u,v,depth) if absf(n.z)>0.5 else Vector3(depth,v,u)
	var node:MeshInstance3D=art.box(pivot,p+n*depth/2,size,color)
	if material!=null:node.material_override=material
	return node

# Windows with distinct conditions: shutter, plain, boarded, broken, shop and blind.
func window(p:Vector3,n:Vector3,ww:float,wh:float,style:String,shutter:Color=Color("59624f"))->void:
	var along:=Vector3(-n.z,0,n.x)
	fbox(p,n,ww+0.16,wh+0.16,0.03,TRIM)
	match style:
		"boarded":
			fbox(p,n,ww,wh,0.04,DARK)
			for i in 3:
				var plank:=fbox(p+Vector3(0,(i-1)*wh*0.3,0),n,ww+0.1,0.16,0.07,Color("75684e"))
				plank.rotate(n.abs(),(i-1)*0.12)
		"broken":
			fbox(p,n,ww,wh,0.035,DARK)
			fbox(p+along*ww*0.22+Vector3(0,wh*0.2,0),n,ww*0.35,wh*0.35,0.05,GLASS)
		"blind":
			fbox(p,n,ww,wh,0.04,Color("6f6a5a"))
			for i in 4:fbox(p+Vector3(0,-wh/2+(i+0.5)*wh/4,0),n,ww,0.03,0.06,Color("8c8572"))
		_:
			fbox(p,n,ww,wh,0.035,GLASS)
			fbox(p,n,0.045,wh,0.06,Color("8f8a77"))
			fbox(p+Vector3(0,wh*0.12,0),n,ww,0.04,0.06,Color("8f8a77"))
	fbox(p-Vector3(0,wh/2+0.06,0),n,ww+0.26,0.08,0.10,Color("bdb39b"))
	if style=="shutter":
		for edge in [-1.0,1.0]:
			fbox(p+along*edge*(ww/2+0.16),n,0.26,wh,0.05,shutter)
			for slat in 4:fbox(p+along*edge*(ww/2+0.16)+Vector3(0,-wh*0.36+slat*wh*0.24,0),n,0.22,0.03,0.07,shutter.lightened(0.12))

func door(p:Vector3,n:Vector3,dw:float,dh:float,color:Color,step:bool=true)->void:
	fbox(p+Vector3(0,dh/2,0),n,dw+0.18,dh+0.12,0.03,TRIM)
	fbox(p+Vector3(0,dh/2,0),n,dw,dh,0.05,color)
	if step:fbox(p+Vector3(0,0.06,0),n,dw+0.35,0.12,0.30,Color("8d8674"))

# Low masonry boundary with pier caps; gaps are purely visual (parcel stays blocked).
func yard_wall(a:Vector2,b:Vector2,h:float,color:Color,gap:float=-1.0,gap_width:float=1.2)->void:
	var length:=a.distance_to(b)
	var dir:=(b-a)/length
	var segments:=[]
	if gap<0:segments.append([0.0,length])
	else:
		segments.append([0.0,gap-gap_width/2]);segments.append([gap+gap_width/2,length])
	for s in segments:
		if s[1]-s[0]<0.05:continue
		var p0:Vector2=a+dir*float(s[0])
		var p1:Vector2=a+dir*float(s[1])
		var t:=0.18
		blk(minf(p0.x,p1.x)-(t/2 if absf(dir.y)>0.5 else 0.0),maxf(p0.x,p1.x)+(t/2 if absf(dir.y)>0.5 else 0.0),0,h,minf(p0.y,p1.y)-(t/2 if absf(dir.x)>0.5 else 0.0),maxf(p0.y,p1.y)+(t/2 if absf(dir.x)>0.5 else 0.0),color)
		for e in [p0,p1]:blk(e.x-0.15,e.x+0.15,0,h+0.18,e.y-0.15,e.y+0.15,color.darkened(0.08))
	if gap>=0:
		var g:=a+dir*gap
		for i in 6:
			var q:=g+dir*(-gap_width/2+0.12+i*(gap_width-0.24)/5)
			tube(Vector3(q.x,0.05,q.y),Vector3(q.x,h*0.92,q.y),0.022,IRON)
		var g0:=g-dir*(gap_width/2-0.1);var g1:=g+dir*(gap_width/2-0.1)
		for y in [0.25,h*0.85]:tube(Vector3(g0.x,y,g0.y),Vector3(g1.x,y,g1.y),0.025,IRON)

func rubble(x0:float,x1:float,z0:float,z1:float,count:int,_top:float,colors:Array)->void:
	for i in count:
		var s:=Vector3(rng.randf_range(0.14,0.55),rng.randf_range(0.10,0.34),rng.randf_range(0.14,0.45))
		var reach:=maxf(s.x,s.z)*0.75
		var pos:=Vector3(rng.randf_range(x0+reach,x1-reach),0,rng.randf_range(z0+reach,z1-reach))
		pos.y=0.0
		var piece:=blk(pos.x-s.x/2,pos.x+s.x/2,pos.y-s.y/2,pos.y+s.y/2,pos.z-s.z/2,pos.z+s.z/2,colors[i%colors.size()])
		piece.rotation=Vector3(rng.randf_range(-0.35,0.35),rng.randf_range(0,TAU),rng.randf_range(-0.35,0.35))
		var bottom:=INF
		for corner in 8:bottom=minf(bottom,(piece.transform*piece.mesh.get_aabb().get_endpoint(corner)).y)
		piece.position.y-=bottom # Loose debris rests on ground; larger piles use authored structural pieces.

func crate(x:float,z:float,size:float,y:float=0.0,color:Color=Color("7a6748"))->void:
	blk(x-size/2,x+size/2,y,y+size*0.85,z-size/2,z+size/2,color)
	blk(x-size/2-0.01,x+size/2+0.01,y+size*0.38,y+size*0.46,z-size/2-0.01,z+size/2+0.01,color.darkened(0.2))
