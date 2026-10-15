class_name AssetsCity
extends RefCounted

# Original low-poly Black Sea street furniture. Local +Z/+X details remain
# readable from the battle camera. Registry footprints are gameplay contracts;
# tree crowns, lamp arms and crane boom are explicitly visual overhangs.
const K=preload("res://scripts/parcel_kit.gd")
const Rural=preload("res://scripts/assets_rural.gd")
const LEAF=Color("536747")
const BLUE=Color("557472")
const RED=Color("865447")
static func specs()->Array:
	return JSON.parse_string(FileAccess.get_file_as_string("res://resources/assets_city.json"))

static func build(art,parent:Node3D,kind:String,variant:String)->Node3D:
	var spec:Dictionary={}
	for item in specs():
		if item.kind==kind and item.variant==variant:spec=item;break
	if spec.is_empty():return null
	var p:=Node3D.new();p.name=kind+"_"+variant;parent.add_child(p)
	match kind:
		"tree":_tree(art,p,variant)
		"lamp","trolley_pole":_pole(art,p,kind)
		"kiosk":_kiosk(art,p,variant)
		"monument":_monument(art,p,variant)
		"fountain":
			c(art,p,0,0.2,0,3,0.4,K.STONE)
			c(art,p,0,0.42,0,2.7,0.06,BLUE)
			c(art,p,0,0.85,0,0.28,0.9,K.TRIM)
			c(art,p,0,1.4,0,1.1,0.3,K.STONE,0.8)
		"wall","fence":_boundary(art,p,kind,variant)
		"playground":_playground(art,p)
		"laundry_line":
			for x in [-2.9,2.9]:
				b(art,p,x,1,0,0.12,2,0.12,BLUE)
				b(art,p,x,1.92,0,0.1,0.1,0.38,BLUE)
			for z in [-0.15,0.15]:
				t(art,p,Vector3(-2.9,1.9,z),Vector3(2.9,1.9,z),0.012,K.IRON)
			for i in 5:b(art,p,-1.9+i*0.85,1.4,0.15,0.64,0.95,0.025,K.TRIM if i%2==0 else BLUE)
		"heat_pipe":
			for x in [-5,0,5]:b(art,p,x,0.36,0,0.35,0.72,1.15,K.CONCRETE)
			for z in [-0.31,0.31]:
				t(art,p,Vector3(-6,0.98,z),Vector3(6,0.98,z),0.25,K.RENDER)
				for x in range(-5,6):t(art,p,Vector3(x-0.025,0.98,z),Vector3(x+0.025,0.98,z),0.27,K.IRON)
		"parking":
			for x in [-5.9,-3,0,3,5.9]:b(art,p,x,0.012,0,0.09,0.02,4.95,K.TRIM)
			b(art,p,0,0.012,2.44,12,0.02,0.09,K.TRIM)
		"car","van":_car(art,p,variant)
		"dumpster":
			for x in [-1.65,0,1.65]:
				b(art,p,x,0.65,0,1.4,1.1,1.4,BLUE)
				b(art,p,x,1.23,0,1.48,0.12,1.5,K.IRON)
				for z in [-0.55,0.55]:b(art,p,x,0.12,z,1.1,0.24,0.12,K.DARK)
		"portal_crane":_crane(art,p)
		"rail_siding":
			for x in range(-11,12,1):b(art,p,x,0.08,0,0.28,0.16,2.8,K.TIMBER)
			for z in [-0.76,0.76]:b(art,p,0,0.23,z,24,0.14,0.1,K.IRON)
		"freight_wagon":_wagon(art,p)
		"tank":
			c(art,p,0,4,0,5.8,8,K.RENDER)
			c(art,p,0,8.35,0,5.8,0.7,K.TRIM,0.8)
			for y in [0.15,2.7,5.3,7.8]:c(art,p,0,y,0,5.88,0.08,K.SHEET)
			_ladder(art,p,Vector3(0,0,5.9),8.6,0.7)
		"container":
			for y in [1.3,3.9]:
				b(art,p,0,y,0,6,2.55,2.44,BLUE if y<2 else RED)
				for x in range(-28,29,4):b(art,p,x/10.0,y,1.235,0.08,2.35,0.03,K.SHEET)
				for z in [-0.58,0.58]:b(art,p,2.99,y,z,0.02,2.3,1.12,K.RENDER)
		"pergola":
			for x in [-2.8,2.8]:
				for z in [-1.8,1.8]:
					b(art,p,x,1.08,z,0.16,2.16,0.16,K.TIMBER)
					t(art,p,Vector3(x+0.1,0,z),Vector3(x,2.22,z),0.045,K.TIMBER)
			for z in [-1.8,1.8]:b(art,p,0,2.12,z,5.9,0.18,0.16,K.TIMBER)
			for x in [-2.8,-2.1,-1.4,-0.7,0,0.7,1.4,2.1,2.8]:
				b(art,p,x,2.22,0,0.09,0.12,3.9,K.TIMBER)
			# A connected shallow leaf mat rests directly on the rafters.
			_vine_band(art,p,5.8,3.8,2.22,2.34,16,5)
			for i in 96:
				var x:float=-2.6+(i%12)*0.47+0.07*sin(float(i*7))
				var z:float=-1.55+floori(i/12.0)*0.44+0.06*cos(float(i*5))
				_leaf_patch(art,p,Vector3(x,2.375,z),Vector3(0.32,0,0),Vector3(0,0,0.28),i)
			for x in [-2.3,-0.8,0.8,2.3]:
				t(art,p,Vector3(x,2.22,1.7),Vector3(x+0.1,2.02,1.75),0.025,K.TIMBER)
				c(art,p,x+0.1,1.98,1.75,0.075,0.18,Color("54475b"),0.025)
		"greenhouse":_greenhouse(art,p)
		"shed":
			b(art,p,0,1.1,0,2.8,2.2,2.8,K.TIMBER)
			var roof=b(art,p,0,2.37,0,3,0.12,2.9,K.SHEET);roof.rotation.x=0.10
			b(art,p,0.2,0.95,1.41,0.9,1.9,0.04,K.DARK)
			for x in [-1.2,-0.9,-0.6,-0.3,0,0.3,0.6,0.9,1.2]:b(art,p,x,1.1,1.43,0.035,2.1,0.025,K.STONE)
		"vineyard":
			for i in 11:
				var x:float=-9.8+i*1.96
				b(art,p,x,0.8,0,0.11,1.6,0.11,K.CONCRETE)
			for y in [0.62,1.15]:t(art,p,Vector3(-9.8,y,0.365),Vector3(9.8,y,0.365),0.016,K.IRON)
			for i in 20:
				var x:float=-9.5+i
				t(art,p,Vector3(x,0,0),Vector3(x+0.1,0.65,0),0.045,K.TIMBER)
			# Contiguous ~1.2m leafy wall, not isolated miniature tree crowns.
			_vine_band(art,p,19.5,0.7,0.29,1.48,40,2)
			for i in 64:
				var x:float=-9.4+i*0.3
				_leaf_patch(art,p,Vector3(x,0.85+0.22*sin(float(i*5)),0.365),Vector3(0.32,0,0),Vector3(0,-0.4,0),i)
				_leaf_patch(art,p,Vector3(x,1.515,0),Vector3(0.3,0,0),Vector3(0,0,0.31),i+7)
		"water_tower":
			c(art,p,0,0.15,0,1.8,0.3,K.CONCRETE)
			c(art,p,0,4.2,0,0.75,8.1,RED)
			c(art,p,0,8.1,0,0.75,1.2,RED,1.85)
			c(art,p,0,10,0,1.85,2.6,RED)
			c(art,p,0,11.55,0,1.9,0.5,K.SHEET,0.1)
			_ladder(art,p,Vector3(0,0,0.9),11.2,0.5)
		"haystack":
			c(art,p,0,1,0,1.45,2,K.OCHRE,1.15)
			c(art,p,0,2.2,0,1.15,0.6,K.OCHRE,0.15)
			for x in [-0.8,0,0.8]:b(art,p,x,0.85,1.05,0.03,1.5,0.03,K.TIMBER)
		"bench":
			for x in [-0.75,0.75]:b(art,p,x,0.24,0,0.1,0.48,0.6,K.IRON)
			for z in [-0.2,0,0.2]:b(art,p,0,0.49,z,2,0.09,0.15,K.TIMBER)
			for y in [0.68,0.85]:b(art,p,0,y,0.29,2,0.1,0.1,K.TIMBER)
		"flowerbed":
			c(art,p,0,0.07,0,2.5,0.14,K.STONE)
			c(art,p,0,0.15,0,2.3,0.04,K.TIMBER)
			for i in 24:
				var a:float=i*2.4;var r:float=0.4+float(i%4)*0.5
				c(art,p,cos(a)*r,0.23,sin(a)*r,0.2,0.14,RED if i%2==0 else K.OCHRE)
	art.bake_model(p)
	var f:Array=spec.footprint
	p.set_meta("local_footprint",Rect2(f[0],f[1],f[2],f[3]))
	p.set_meta("height",spec.height);p.set_meta("grants_cover",false)
	p.set_meta("placement_policy","library_only")
	return p

# Shared section boundaries form one continuous foliage band. Subtle scallops
# and restrained green variation read as leaves without expensive alpha cards.
static func _vine_band(a,p,w:float,d:float,low:float,high:float,steps:int,seed_value:int)->void:
	var rings:Array=[]
	for i in steps+1:
		var x:float=-w/2+w*i/steps
		var wave:float=sin(float(i*7+seed_value))
		var half_depth:float=d*0.5*(0.94+0.05*wave)
		var top:float=high+minf(0.025,(high-low)*0.04)*wave
		var bottom:float=low+minf(0.04,(high-low)*0.05)*wave
		rings.append([Vector3(x,bottom,-half_depth*0.9),Vector3(x,bottom,half_depth*0.9),Vector3(x,top-0.04,half_depth),Vector3(x,top,half_depth*0.7),Vector3(x,top,-half_depth*0.7),Vector3(x,top-0.04,-half_depth)])
	for i in steps:
		a.models.shell(p,[rings[i],rings[i+1]],LEAF.lightened(0.07))

# Small faceted leaf groups break up the continuous mat without pod silhouettes.
static func _leaf_patch(a,p,center:Vector3,u:Vector3,v:Vector3,seed_value:int)->void:
	var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var normal:Vector3=v.cross(u).normalized()
	for i in 6:
		var angle:float=TAU*i/6+seed_value*0.7
		var next:float=angle+TAU/6
		var r:float=0.8+0.18*sin(float(seed_value+i*3))
		surface.add_vertex(center+normal*0.012)
		surface.add_vertex(center+(u*cos(next)+v*sin(next))*r)
		surface.add_vertex(center+(u*cos(angle)+v*sin(angle))*r)
	surface.generate_normals()
	var mesh:=MeshInstance3D.new();mesh.mesh=surface.commit()
	mesh.material_override=a.material(Color("718650").darkened(0.12+0.13*sin(float(seed_value*5))))
	p.add_child(mesh)

static func b(a,p,x:float,y:float,z:float,w:float,h:float,d:float,col:Color)->MeshInstance3D:
	return a.box(p,Vector3(x,y,z),Vector3(w,h,d),col)
static func c(a,p,x:float,y:float,z:float,r:float,h:float,col:Color,top:float=-1)->MeshInstance3D:
	return a.cylinder(p,Vector3(x,y,z),r,h,col,top)
static func t(a,p,from:Vector3,to:Vector3,r:float,col:Color)->void:
	a.models.tube(p,from,to,r,col)
static func _ladder(a,p,pos:Vector3,h:float,w:float)->void:
	for x in [-w/2,w/2]:b(a,p,pos.x+x,pos.y+h/2,pos.z,0.06,h,0.06,K.IRON)
	for i in int(h/0.4):b(a,p,pos.x,pos.y+0.2+i*0.4,pos.z,w,0.05,0.06,K.IRON)

# Clustered crown: a core plus jittered sub-lobes over an ellipsoid, sunlit greens
# on top and shaded greens below, so the silhouette breaks up into leaf masses
# instead of reading as one faceted blob. ~10 lobes x ~36 triangles.
const CANOPY:=[Color("44593a"),Color("4f6a3c"),Color("5d7843"),Color("6c874c")]
static func _fine_crown(a,p,center:Vector3,size:Vector3,seed_value:int,columnar:bool=false)->void:
	var spots:Array=[[Vector3.ZERO,0.62,1]]
	if columnar:
		for i in 6:
			var y:=(float(i)/5.0-0.5)*0.78
			var taper:=1.0-absf(y)*0.9
			spots.append([Vector3(sin(float(seed_value+i*5))*0.16*taper,y,cos(float(seed_value+i*3))*0.16*taper),0.42*taper+0.12,clampi(2+int(y*4),0,3)])
	else:
		for i in 7:
			var angle:=TAU*i/7.0+float(seed_value)*0.9
			var lift:=-0.12+0.22*float((i+seed_value)%3)/2.0
			spots.append([Vector3(cos(angle)*0.34,lift,sin(angle)*0.34),0.44+0.06*sin(float(i*5+seed_value)),2 if lift>0.0 else 1])
		for i in 2:
			var angle:=float(seed_value)+i*PI
			spots.append([Vector3(cos(angle)*0.14,0.3,sin(angle)*0.14),0.42,3])
		spots.append([Vector3(0,-0.28,0),0.5,0])
	for spot in spots:
		var offset:Vector3=spot[0]
		_lobe(a,p,center+Vector3(offset.x*size.x,offset.y*size.y,offset.z*size.z),size*float(spot[1]),seed_value*7+spots.find(spot),CANOPY[int(spot[2])])

static func _lobe(a,p,center:Vector3,size:Vector3,seed_value:int,color:Color)->void:
	var rings:Array=[]
	var widths:=[0.28,0.92,1.0,0.66,0.12]
	var heights:=[-0.5,-0.22,0.05,0.32,0.5]
	for layer in widths.size():
		var ring:Array[Vector3]=[]
		for i in 7:
			var angle:=TAU*i/7.0+float(seed_value)*0.37
			var irregular:=0.8+0.2*sin(float(i*7+seed_value*3+layer))
			ring.append(Vector3(cos(angle)*size.x*0.5*float(widths[layer])*irregular,float(heights[layer])*size.y,sin(angle)*size.z*0.5*float(widths[layer])*irregular))
		rings.append(ring)
	var node:MeshInstance3D=a.models.shell(p,rings,color)
	node.position=center

static func _tree(a,p,v:String)->void:
	var tall:bool=v in ["cypress","poplar"]
	var h:float={"plane_street":9.0,"acacia":7.0,"cypress":9.0,"poplar":14.0,"crimean_pine":10.0}[v]
	var bark:Color=K.TRIM if v=="plane_street" else K.TIMBER
	c(a,p,0,h*0.3,0,0.29,h*0.6,bark,0.13)
	if v=="plane_street":
		for i in 12:
			var angle:float=i*2.4
			b(a,p,cos(angle)*0.22,0.5+i*0.34,sin(angle)*0.22,0.12,0.35,0.12,K.RENDER if i%2==0 else K.OCHRE)
	if tall:
		_fine_crown(a,p,Vector3(0,h*0.57,0),Vector3(1.9 if v=="poplar" else 1.25,h*0.86*0.74,1.7 if v=="poplar" else 1.25),4,true)
	elif v=="crimean_pine":
		# Mature Crimean pine: exposed crooked limbs and broad flattened needle pads.
		for i in 6:
			var angle:float=i*TAU/6
			var top:=Vector3(cos(angle)*1.9,6.6+float(i%3)*0.7,sin(angle)*1.9)
			t(a,p,Vector3(0,4.0,0),top,0.16,bark)
			_fine_crown(a,p,top,Vector3(3.1,1.4,2.7),i*2)
		_fine_crown(a,p,Vector3(0,9,0),Vector3(3.9,2,3.2),4)
	elif v=="acacia":
		# Airier, spreading black-locust crown with smaller offset leaf clusters.
		for i in 7:
			var angle:float=i*TAU/7
			var top:=Vector3(cos(angle)*1.8,4.5+float(i%3)*0.6,sin(angle)*1.8)
			t(a,p,Vector3(0,2.2,0),top,0.09,bark)
			_fine_crown(a,p,top,Vector3(2.0,1.65,1.9),i*2+1)
		_fine_crown(a,p,Vector3(0,6.1,0),Vector3(2.1,1.8,2.1),3)
	else:
		for i in 5:
			var angle:float=i*TAU/5
			var top:=Vector3(cos(angle)*1.75,h*0.68+float(i%2)*0.5,sin(angle)*1.75)
			t(a,p,Vector3(0,h*0.35,0),top,0.12,bark)
			_fine_crown(a,p,top,Vector3(3.4,h*0.30,3.2),i+2)
		_fine_crown(a,p,Vector3(0,h*0.84,0),Vector3(3.1,h*0.32,3),5)

static func _pole(a,p,kind:String)->void:
	var lamp:bool=kind=="lamp"
	c(a,p,0,0.35,0,0.24 if lamp else 0.2,0.7,K.CONCRETE)
	c(a,p,0,2.6 if lamp else 4,0,0.09,4.7 if lamp else 8,K.IRON,0.05)
	if lamp:
		for side in [-1,1]:
			t(a,p,Vector3(0,4.35,0),Vector3(side*1.1,4.8,0),0.05,K.IRON)
			b(a,p,side*1.1,4.85,0,0.6,0.16,0.3,K.TRIM)
	else:
		for y in [6.7,7.2]:
			b(a,p,0,y,0,0.45,0.08,0.15,K.IRON)
			c(a,p,0.17,y+0.12,0,0.07,0.2,K.TRIM)

static func _kiosk(a,p,v:String)->void:
	var stall:bool=v=="market_stall"
	b(a,p,0,0.5,0,2.8,1,1.8,BLUE)
	if not stall:
		b(a,p,0,1.65,0,2.78,1.3,1.78,K.GLASS)
		for x in [-1.35,-0.45,0.45,1.35]:b(a,p,x,1.65,0.91,0.06,1.3,0.06,K.TRIM)
		for i in 6:
			b(a,p,-1.1+i*0.43,1.4,0.92,0.32,0.48,0.025,K.TRIM)
			b(a,p,-1.1+i*0.43,1.5,0.94,0.24,0.04,0.01,K.DARK)
	else:
		for x in [-1.3,1.3]:
			for z in [-1,1]:b(a,p,x,1.7,z,0.08,1.5,0.08,K.IRON)
		for x in [-0.9,0,0.9]:b(a,p,x,1.08,0.3,0.75,0.18,1.1,K.OCHRE)
	b(a,p,0,2.4,0,3,0.2,2.4 if stall else 2,BLUE)
	b(a,p,0,2.22,0.94,2.8,0.22,0.08,K.TRIM)

const GRANITE:=Color("8e8b81")
const GRANITE_DARK:=Color("67655d")
const BRONZE:=Color("4a5a4b")
const BRONZE_DARK:=Color("37443a")
const BRONZE_LIGHT:=Color("6f7f69")

# Memorial on a moulded granite pedestal. Statue: a bronze figure in a greatcoat
# with one arm raised, facing +Z (the camera side) on a 3x3 footprint. Column:
# a tall Doric column on the same pedestal, crowned by a small bronze figure.
static func _monument(a,p,v:String)->void:
	var col:bool=v=="column"
	var s:=1.3 if col else 1.0 # Column pedestal is wider (4x4 footprint).
	# Stepped base, socle, dado with corner pilasters, cornice and cap.
	b(a,p,0,0.11,0,3.0*s,0.22,3.0*s,GRANITE_DARK)
	b(a,p,0,0.32,0,2.62*s,0.2,2.62*s,GRANITE)
	b(a,p,0,0.56,0,2.08*s,0.28,2.08*s,GRANITE_DARK)
	b(a,p,0,0.74,0,1.86*s,0.08,1.86*s,GRANITE)
	b(a,p,0,1.5,0,1.6*s,1.44,1.6*s,GRANITE)
	for x in [-1,1]:
		for z in [-1,1]:b(a,p,x*0.76*s,1.5,z*0.76*s,0.16,1.44,0.16,GRANITE.lightened(0.06))
	b(a,p,0,2.26,0,1.8*s,0.1,1.8*s,GRANITE.lightened(0.05))
	b(a,p,0,2.36,0,1.92*s,0.1,1.92*s,GRANITE)
	b(a,p,0,2.48,0,1.64*s,0.14,1.64*s,GRANITE_DARK)
	# Bronze plaque with raised inscription lines and a laurel wreath below.
	b(a,p,0,1.62,0.81*s,0.86,0.56,0.04,BRONZE_DARK)
	for i in 3:b(a,p,0,1.78-i*0.13,0.83*s,0.62-i*0.12,0.035,0.02,BRONZE_LIGHT)
	for i in 9:
		var angle:=PI*0.15+i*PI*0.7/8.0
		a.models.ellipsoid(p,Vector3(cos(angle)*0.28,1.12-sin(angle)*0.1+0.1,0.83*s),Vector3(0.11,0.07,0.05),BRONZE)
	# Flowers laid on the lower step.
	for i in 4:a.models.ellipsoid(p,Vector3(-0.45+i*0.3,0.47,1.14*s),Vector3(0.16,0.09,0.12),[Color("8e3b36"),Color("d8d2bf"),Color("8e3b36"),Color("c99b3d")][i])
	if col:_column_top(a,p)
	else:
		_figure(a,p,2.55,1.0)
		# Square memorials stand well above street lamps: scale the whole statue 1.5x
		# (registry footprint 4.6 x 4.6, height 7).
		for child in p.get_children():
			if child is Node3D:child.position*=1.5;child.scale*=1.5

# Standing bronze figure: stride, flared greatcoat, shoulders, capped head,
# right arm raised forward. Base y and scale let the column reuse it.
static func _figure(a,p,y:float,k:float)->void:
	b(a,p,0,y+0.05*k,0.05*k,0.86*k,0.1*k,0.7*k,BRONZE_DARK)
	for side in [-1,1]:
		var stride:=0.1*k if side>0 else -0.06*k
		a.models.tube(p,Vector3(side*0.12*k,y+0.1*k,stride),Vector3(side*0.1*k,y+0.85*k,0),0.1*k,BRONZE,0.085*k)
		b(a,p,side*0.12*k,y+0.15*k,stride+0.06*k,0.15*k,0.1*k,0.3*k,BRONZE_DARK)
	# Greatcoat flares from the waist to below the knee.
	a.models.tube(p,Vector3(0,y+0.42*k,0),Vector3(0,y+1.42*k,0),0.36*k,BRONZE,0.21*k)
	a.models.tube(p,Vector3(0,y+0.95*k,0),Vector3(0,y+1.5*k,0),0.24*k,BRONZE,0.25*k)
	b(a,p,0,y+1.0*k,0.2*k,0.46*k,0.06*k,0.12*k,BRONZE_DARK)
	a.models.ellipsoid(p,Vector3(0,y+1.52*k,0),Vector3(0.66*k,0.22*k,0.36*k),BRONZE)
	a.models.tube(p,Vector3(0,y+1.55*k,0),Vector3(0,y+1.68*k,0.02*k),0.075*k,BRONZE)
	a.models.ellipsoid(p,Vector3(0,y+1.8*k,0.03*k),Vector3(0.23*k,0.29*k,0.26*k),BRONZE_LIGHT)
	c(a,p,0,y+1.95*k,0.02*k,0.15*k,0.06*k,BRONZE_DARK)
	b(a,p,0,y+1.93*k,0.15*k,0.2*k,0.025*k,0.1*k,BRONZE_DARK)
	# Right arm raised and pointing forward; left arm down, hand on sword hilt.
	var shoulder_r:=Vector3(0.3*k,y+1.5*k,0)
	var elbow_r:=Vector3(0.43*k,y+1.72*k,0.24*k)
	var hand_r:=Vector3(0.5*k,y+2.0*k,0.52*k)
	a.models.tube(p,shoulder_r,elbow_r,0.075*k,BRONZE)
	a.models.tube(p,elbow_r,hand_r,0.062*k,BRONZE)
	a.models.ellipsoid(p,hand_r,Vector3(0.1*k,0.1*k,0.13*k),BRONZE_LIGHT)
	var shoulder_l:=Vector3(-0.3*k,y+1.5*k,0)
	var elbow_l:=Vector3(-0.36*k,y+1.17*k,0.05*k)
	var hand_l:=Vector3(-0.3*k,y+0.9*k,0.14*k)
	a.models.tube(p,shoulder_l,elbow_l,0.075*k,BRONZE)
	a.models.tube(p,elbow_l,hand_l,0.062*k,BRONZE)
	a.models.tube(p,hand_l+Vector3(0,0.08*k,0),hand_l+Vector3(0.05*k,-0.62*k,0.08*k),0.025*k,BRONZE_DARK)

# Doric column with entasis, capital and abacus, crowned by a smaller figure.
static func _column_top(a,p)->void:
	c(a,p,0,2.7,0,0.62,0.26,GRANITE_DARK)
	c(a,p,0,2.9,0,0.55,0.16,GRANITE,0.52)
	c(a,p,0,6.35,0,0.5,6.8,GRANITE.lightened(0.04),0.41)
	for i in 12:
		var angle:=i*TAU/12.0
		a.models.tube(p,Vector3(cos(angle)*0.49,3.0,sin(angle)*0.49),Vector3(cos(angle)*0.4,9.7,sin(angle)*0.4),0.035,GRANITE.darkened(0.08))
	c(a,p,0,9.85,0,0.42,0.18,GRANITE,0.58)
	b(a,p,0,10.06,0,1.2,0.24,1.2,GRANITE.lightened(0.05))
	_figure(a,p,10.18,0.85)

static func _boundary(a,p,kind:String,v:String)->void:
	if kind=="wall":
		if v=="stone_gate":
			for x in [-1.35,1.35]:b(a,p,x,1.2,0,0.5,2.4,0.6,K.STONE)
			b(a,p,0,1,0,2.2,2,0.12,BLUE)
			for x in [-0.95,-0.65,-0.35,0.35,0.65,0.95]:b(a,p,x,1,0.09,0.04,1.85,0.04,K.IRON)
		else:
			for row in 4:
				for i in 8:b(a,p,-2.62+i*0.75,0.2+row*0.38,0,0.73,0.36,0.54,K.STONE.lightened(0.03*((i+row)%3)))
			b(a,p,0,1.67,0,6,0.22,0.6,K.TERRACOTTA)
	else:
		var h:float=2.5 if v=="concrete_panel" else (1.1 if v=="picket" else 2.0)
		for x in [-2.9,0,2.9]:b(a,p,x,h/2,0,0.12,h,0.15,K.CONCRETE)
		if v=="concrete_panel":
			for x in [-1.45,1.45]:
				b(a,p,x,1.2,0,2.75,2.3,0.2,K.CONCRETE)
				for y in [0.5,1.1,1.7,2.2]:b(a,p,x,y,0.12,2.6,0.07,0.04,K.STONE)
		elif v=="picket":
			for i in 23:b(a,p,-2.8+i*0.25,0.55,0,0.13,1.1,0.08,K.TRIM)
			for y in [0.3,0.8]:b(a,p,0,y,0,6,0.07,0.14,K.TIMBER)
		else:
			for y in [0.15,1.9]:b(a,p,0,y,0,5.8,0.04,0.04,K.IRON)
			# Open diamond mesh, clipped to each narrow panel.
			for i in 28:
				var x:float=-2.8+i*0.2
				t(a,p,Vector3(x,0.2,0),Vector3(minf(x+0.8,2.9),1.85,0),0.012,K.SHEET)
				t(a,p,Vector3(x,1.85,0),Vector3(minf(x+0.8,2.9),0.2,0),0.012,K.SHEET)

static func _playground(a,p)->void:
	for x in [-2.7,0.7]:
		for z in [-1.2,1.2]:t(a,p,Vector3(x,0,z),Vector3(x,2.4,0),0.07,RED)
	t(a,p,Vector3(-2.8,2.4,0),Vector3(0.8,2.4,0),0.09,BLUE)
	for x in [-1.9,-0.2]:
		for side in [-0.3,0.3]:t(a,p,Vector3(x+side,2.35,0),Vector3(x+side,0.6,0.15),0.018,K.IRON)
		b(a,p,x,0.58,0.15,0.8,0.08,0.4,K.TIMBER)
	_ladder(a,p,Vector3(2.3,0,-1),2.3,0.8)
	for x in [1.9,2.7]:t(a,p,Vector3(x,2.3,-1),Vector3(x,0.15,2.5),0.05,RED)
	var slide=b(a,p,2.3,1.2,0.75,0.8,0.08,4.05,K.SHEET);slide.rotation.x=0.55

static func _car(a,p,v:String)->void:
	var van:bool=v=="minibus";var hatch:bool=v=="hatchback"
	var w:float=1.9 if van else (1.6 if hatch else 1.7)
	var d:float=4.6 if van else (3.4 if hatch else 3.8)
	var paint:Color=K.OCHRE if van else (BLUE if hatch else K.TRIM)
	b(a,p,0,0.63,0,w,0.65,d,paint)
	b(a,p,0,1.45 if van else 1.1,0.1,w*0.87,1.2 if van else 0.55,d*(0.81 if van else (0.65 if hatch else 0.51)),K.GLASS)
	b(a,p,0,2.05 if van else 1.38,0.1,w*0.9,0.07,d*(0.83 if van else (0.67 if hatch else 0.53)),paint)
	for x in [-w*0.44,w*0.44]:
		for z in [-d*0.32,d*0.32]:
			t(a,p,Vector3(x-0.08,0.3,z),Vector3(x+0.08,0.3,z),0.3,K.DARK)
		for z in [-d*0.23,0,d*0.25]:b(a,p,x,1.45 if van else 1.1,z,0.06,1.1 if van else 0.5,0.07,paint)
	for z in [-d/2,d/2]:
		b(a,p,0,0.45,z,w,0.1,0.08,K.SHEET)
		for x in [-w*0.32,w*0.32]:b(a,p,x,0.76,z,0.3,0.16,0.04,K.TRIM if z<0 else RED)

static func _crane(a,p)->void:
	for x in [-3,3]:
		b(a,p,x,0.15,0,0.18,0.3,7,K.IRON)
		for z in [-2.7,2.7]:
			b(a,p,x,0.55,z,0.65,0.8,1.3,K.SHEET)
			t(a,p,Vector3(x,0.9,z),Vector3(x*0.55,7,z*0.55),0.25,BLUE)
		b(a,p,x*0.55,6.9,0,0.45,0.5,3.5,BLUE)
	b(a,p,0,7.3,0,4.4,0.7,4.3,BLUE)
	c(a,p,0,8,0,1.5,0.7,K.IRON)
	b(a,p,0,9,0,2.7,1.5,3.5,BLUE)
	b(a,p,1.15,9.5,1.5,1.3,1.7,1.6,K.GLASS)
	b(a,p,1.15,10.4,1.5,1.4,0.12,1.7,BLUE)
	# Latticed luffing boom: visual overhang beyond rail-leg collision.
	var start:=Vector3(0,9,0);var end:=Vector3(0,21,10)
	for side in [-0.45,0.45]:t(a,p,start+Vector3(side,0,0),end+Vector3(side,0,0),0.10,BLUE)
	t(a,p,start+Vector3(0,0.7,0),end+Vector3(0,0.7,0),0.09,BLUE)
	for i in 8:
		var u:float=i/8.0;var next:float=(i+1)/8.0
		t(a,p,start.lerp(end,u)+Vector3(-0.45,0,0),start.lerp(end,next)+Vector3(0.45,0,0),0.045,K.TRIM)
		t(a,p,start.lerp(end,u)+Vector3(0.45,0,0),start.lerp(end,next)+Vector3(-0.45,0,0),0.045,BLUE)
		for side in [-0.45,0.45]:t(a,p,start.lerp(end,u)+Vector3(side,0,0),start.lerp(end,next)+Vector3(0,0.7,0),0.045,BLUE)
	t(a,p,Vector3(0,9,-2.5),Vector3(0,16,0),0.12,BLUE)
	t(a,p,Vector3(0,16,0),end,0.025,K.IRON)
	t(a,p,end,Vector3(0,5,10),0.025,K.IRON)
	b(a,p,0,5,10,0.3,0.5,0.3,K.IRON)

static func _wagon(a,p)->void:
	b(a,p,0,2.3,0,13.5,3,2.8,RED)
	b(a,p,0,3.87,0,13.7,0.2,2.95,K.SHEET)
	for x in [-5,5]:
		for z in [-1.1,1.1]:t(a,p,Vector3(x-0.35,0.45,z),Vector3(x+0.35,0.45,z),0.4,K.IRON)
	for z in [-1.42,1.42]:
		b(a,p,0,2.2,z,3,2.7,0.06,K.TIMBER)
		for x in [-6,-4,-2,2,4,6]:b(a,p,x,2.3,z,0.1,2.9,0.1,K.SHEET)
		b(a,p,0,0.9,z,13.5,0.12,0.12,K.IRON)

static func _greenhouse(a,p)->void:
	var rings:Array=[]
	for z in [-3.9,3.9]:
		var ring:Array[Vector3]=[]
		for i in 9:
			var angle:float=PI*i/8
			ring.append(Vector3(cos(angle)*1.9,sin(angle)*2.3,z))
		rings.append(ring)
	a.models.shell(p,rings,Color("9da99a"))
	for z in [-3.9,-2.6,-1.3,0,1.3,2.6,3.9]:
		for i in 8:
			var u:float=PI*i/8;var v:float=PI*(i+1)/8
			t(a,p,Vector3(cos(u)*1.92,sin(u)*2.32,z),Vector3(cos(v)*1.92,sin(v)*2.32,z),0.025,K.TRIM)
	b(a,p,0,0.85,3.93,0.8,1.7,0.025,K.SHEET)
	b(a,p,0,1,3.95,0.65,1.3,0.025,Color("9da99a"))
