class_name ArchitecturalBlock
extends RefCounted

# Original authored parcel buildings. Each visible parcel has its own function,
# mass, roof form and yard arrangement; the street face follows the road graph.
# Every solid vertex stays within the existing map blocker (see ParcelKit).
const Kit=preload("res://scripts/parcel_kit.gd")
const F:=Vector3(0,0,-1)
const B:=Vector3(0,0,1)
const L:=Vector3(-1,0,0)
const R:=Vector3(1,0,0)

static func build(art,parent:Node3D,r:Rect2,index:int,specification:Dictionary={})->void:
	var plan:Array=Kit.design(r,index,false,specification)
	if not (plan[0] in Kit.INTACT):plan=[Kit.INTACT[index%Kit.INTACT.size()],plan[1]]
	var k=Kit.new(art,parent,r,plan[1],4099+index*37)
	k.blk(-k.w/2,k.w/2,0,0.05,-k.d/2,k.d/2,Color("626153"))
	match plan[0]:
		"cafe":_cafe(k)
		"terrace":_terrace(k)
		"villa":_villa(k)
		"chapel":_chapel(k)
		"warehouse":_warehouse(k)
		"flat_block":_flat_block(k)
		"farmstead":_farmstead(k)
	k.finish()

# Two-storey corner cafe: the street door faces the high street, while the
# terrace, the town's only striped awning and an iron balcony wrap the east
# corner that the game camera actually sees. Rear pergola courtyard.
static func _cafe(k)->void:
	var wall:Material=k.wallmat(Kit.OCHRE)
	var green:=Color("2f4a3c")
	var x0:=-3.1;var x1:=1.5;var z0:=-1.9;var z1:=1.3;var h:=5.4
	k.blk(x0,x1,0,h,z0,z1,Kit.OCHRE,wall)
	k.blk(x0-0.05,x1+0.05,0,0.4,z0-0.05,z1+0.05,Color("7b745f"))
	k.blk(x0-0.05,x1+0.05,2.95,3.1,z0-0.05,z1+0.05,Kit.TRIM)
	k.blk(x0-0.08,x1+0.08,h-0.15,h,z0-0.08,z1+0.08,Kit.TRIM)
	k.hip_roof(x0,x1,z0,z1,h,1.5,0.3,k.roofmat(Kit.TERRACOTTA))
	k.chimney(-2.1,0.5,5.6,7.2,Color("8f7a5c"),3)
	k.chimney(0.6,-0.6,5.9,7.0,Color("8f7a5c"),1)
	# Solar panel on the rear (south) slope, which faces the sun and the camera.
	var slope:=1.55/1.9
	var panel:=[]
	for q in [Vector2(-1.5,1.05),Vector2(-0.2,1.05),Vector2(-0.2,0.3),Vector2(-1.5,0.3)]:
		panel.append(Vector3(q.x,h+0.04+(z1+0.3-q.y)*slope,q.y))
	k.slab(panel,0.05,k.paint(Color("27313b")))
	# Shopfront wraps the corner: fascia, glazing, stall riser and abstract lettering.
	k.fbox(Vector3(-0.8,2.65,z0),F,4.7,0.5,0.08,green)
	k.fbox(Vector3(x1,2.65,-0.3),R,3.3,0.5,0.08,green)
	for i in 7:k.fbox(Vector3(x1+0.08,2.65,-1.55+i*0.42),R,0.24,0.16,0.03,Color("c9bf9f"))
	var panes:=[[F,Vector3(-2.2,0,z0),1.4],[F,Vector3(0.6,0,z0),1.2],[R,Vector3(x1,0,-1.05),1.3],[R,Vector3(x1,0,0.65),1.0]]
	for p in panes:
		var n:Vector3=p[0];var base:Vector3=p[1];var width:float=p[2]
		var along:=Vector3(-n.z,0,n.x)
		k.fbox(base+Vector3(0,0.45,0),n,width,0.5,0.06,green)
		k.fbox(base+Vector3(0,1.45,0),n,width,1.5,0.04,Kit.GLASS)
		k.fbox(base+Vector3(0,2.15,0),n,width,0.06,0.07,green)
		for e in [-0.5,0.0,0.5]:k.fbox(base+along*e*width+Vector3(0,1.45,0),n,0.06,1.5,0.07,green)
	k.door(Vector3(-0.85,0.05,z0),F,0.9,2.2,green,false)
	k.door(Vector3(x1,0.05,-0.2),R,0.85,2.2,green,false)
	# Projecting striped awning on iron arms over the east terrace.
	var stripes:=10
	for s in stripes:
		var a:=-1.85+s*3.0/stripes;var b:=a+3.0/stripes
		var col:=Color("355543") if s%2==0 else Color("c3b894")
		k.slab([Vector3(x1+0.02,2.55,a),Vector3(x1+0.02,2.55,b),Vector3(3.05,2.05,b),Vector3(3.05,2.05,a)],0.03,k.paint(col))
		k.blk(3.04,3.08,1.82,2.05,a,b,col)
	for z in [-1.8,-0.35,1.1]:k.tube(Vector3(x1+0.02,1.75,z),Vector3(3.0,2.03,z),0.02,Kit.IRON)
	# Terrace paving, bistro tables, chairs, planters and an A-board.
	k.blk(x1,3.35,0.05,0.09,-3.4,z1,Color("8a8470"))
	k.blk(-3.35,x1,0.05,0.09,-3.4,z0,Color("8a8470"))
	for tz in [-1.25,0.45]:
		var tx:=2.45
		k.tube(Vector3(tx,0.09,tz),Vector3(tx,0.72,tz),0.03,Kit.IRON)
		k.tube(Vector3(tx,0.72,tz),Vector3(tx,0.76,tz),0.30,Color("b9b19a"))
		for side in [-1.0,1.0]:
			var cz:float=tz+side*0.48
			k.blk(tx-0.17,tx+0.17,0.42,0.47,cz-0.17,cz+0.17,Color("4c5640"))
			k.blk(tx-0.17,tx+0.17,0.47,0.85,cz+side*0.15-0.02,cz+side*0.15+0.02,Color("4c5640"))
	for pz in [-2.9,1.0]:
		k.blk(2.9,3.3,0.09,0.5,pz-0.3,pz+0.3,Color("6d5b45"))
		k.plant(Vector3(3.1,0.68,pz),0.2,61+int(pz))
	k.blk(2.0,2.2,0.09,0.75,-2.85,-2.55,Color("3a4a3d")).rotation.x=0.18
	for x in [-2.6,-1.6]:k.plant(Vector3(x,0.35,-2.9),0.22,67+int(x))
	# Upper floor: shuttered windows; continuous wrought-iron balcony on the corner.
	for x in [-2.3,-0.85,0.6]:k.window(Vector3(x,4.15,z0),F,0.62,1.2,"shutter",Color("4f6a52"))
	for z in [-1.2,0.0,0.85]:k.window(Vector3(x1,4.15,z),R,0.55,1.2,"shutter",Color("4f6a52"))
	k.blk(x1,2.05,3.12,3.24,-1.75,1.15,Color("8e8673"))
	k.tube(Vector3(2.02,4.12,-1.72),Vector3(2.02,4.12,1.12),0.025,Kit.IRON)
	for i in 17:
		var z:=-1.72+i*2.84/16
		k.tube(Vector3(2.02,3.24,z),Vector3(2.02,4.12,z),0.012,Kit.IRON)
	for z in [-0.6,0.5]:k.plant(Vector3(1.8,3.5,z),0.18,73+int(z*3))
	# West end and rear walls are inhabited, not blank.
	for z in [-0.9,0.5]:k.window(Vector3(x0,4.15,z),L,0.6,1.1,"shutter",Color("4f6a52"))
	k.door(Vector3(x0,0.05,0.3),L,0.85,2.1,Color("54473a"))
	for x in [-2.3,-0.8]:k.window(Vector3(x,4.1,z1),B,0.6,1.1,"plain")
	k.window(Vector3(0.7,4.1,z1),B,0.6,1.1,"blind")
	k.door(Vector3(0.6,0.05,z1),B,0.8,2.0,Color("3e5044"))
	k.fbox(Vector3(-1.6,3.55,z1),B,0.8,0.5,0.35,Color("8e9089"))
	k.disc(Vector3(x0-0.05,4.9,-1.3),Vector3(-0.7,0.4,0).normalized(),0.3,Color("b6b4aa"))
	for i in 9:k.plant(Vector3(x0-0.04,0.6+i*0.42,0.9-fmod(i*0.61,1.4)),0.2,90+i,Color("465a34"))
	# Rear pergola courtyard with umbrella table and bins.
	k.blk(-3.3,3.3,0.05,0.08,z1,3.3,Color("817b67"))
	k.yard_wall(Vector2(-3.3,z1),Vector2(-3.3,3.3),1.3,Color("8b836d"))
	k.yard_wall(Vector2(3.3,z1),Vector2(3.3,3.3),1.3,Color("8b836d"))
	k.yard_wall(Vector2(-3.3,3.3),Vector2(3.3,3.3),1.3,Color("8b836d"),1.2,1.1)
	for p in [Vector2(-0.3,1.65),Vector2(2.7,1.65),Vector2(-0.3,2.95),Vector2(2.7,2.95)]:
		k.blk(p.x-0.05,p.x+0.05,0.05,2.1,p.y-0.05,p.y+0.05,Color("6a5f48"))
	for z in [1.65,2.95]:k.blk(-0.4,2.8,2.1,2.18,z-0.05,z+0.05,Color("6a5f48"))
	for i in 7:k.blk(-0.3+i*0.5-0.03,-0.3+i*0.5+0.03,2.18,2.24,1.55,3.05,Color("7b7153"))
	for i in 4:k.plant(Vector3(0.1+i*0.75,2.35,2.3+0.25*(i%2)),0.28,101+i,Color("4f5f37"))
	k.blk(0.7,1.8,0.7,0.75,2.0,2.6,Color("70664f"))
	k.blk(1.2,1.3,0.08,0.7,2.25,2.35,Color("4d4b39"))
	k.tube(Vector3(-1.9,0.08,2.3),Vector3(-1.9,2.2,2.3),0.025,Color("cfc8b2"))
	k.hip_roof(-2.75,-1.05,1.45,3.15,2.0,0.42,0.0,k.paint(Color("c9c0a0")))
	k.tube(Vector3(-1.9,0.7,2.3),Vector3(-1.9,0.74,2.3),0.34,Color("b9b19a"))
	for z in [1.55,1.95]:k.blk(-3.05,-2.65,0.08,0.95,z-0.18,z+0.18,Color("3d4b3c"))

# Stepped terrace of three narrow houses: brick three-storey with bay window,
# rendered house with a carriage arch and patched roof, flat-roofed corner shop.
static func _terrace(k)->void:
	var z0:=-2.4;var z1:=0.9
	var brick:Material=k.wallmat(Kit.BRICK)
	var render:Material=k.wallmat(Kit.RENDER)
	var cream:Material=k.wallmat(Kit.CREAM)
	var tile:Material=k.roofmat(Kit.TERRACOTTA)
	var slate:Material=k.roofmat(Kit.SLATE)
	# House one.
	k.gabled_mass(-3.2,-1.0,z0,z1,6.6,1.3,"x",brick)
	k.gable_roof(-3.2,-1.0,z0,z1,6.6,1.3,"x",0.2,tile,Color("8a6048"))
	for y in [2.4,4.5]:k.blk(-3.22,-1.0,y,y+0.1,z0-0.03,z1+0.03,Color("9b8e78"))
	k.blk(-2.25,-1.2,0.3,2.15,-2.78,z0,Kit.BRICK,brick)
	k.blk(-2.3,-1.15,2.15,2.27,-2.83,z0,Kit.TRIM)
	k.fbox(Vector3(-1.72,1.25,-2.78),F,0.8,1.2,0.04,Kit.GLASS)
	k.door(Vector3(-2.75,0.05,z0),F,0.7,2.0,Color("5c2f2a"))
	for x in [-2.55,-1.65]:
		k.window(Vector3(x,3.45,z0),F,0.55,1.15,"plain")
		k.window(Vector3(x,5.55,z0),F,0.55,1.05,"boarded" if x<-2.0 else "plain")
		k.window(Vector3(x,3.45,z1),B,0.55,1.1,"plain")
	k.window(Vector3(-3.2,5.4,0.3),L,0.5,0.9,"plain")
	# Faded painted advert on the exposed brick end wall.
	k.fbox(Vector3(-3.2,4.9,-1.3),L,1.5,1.1,0.02,Color("a49a7c"))
	k.fbox(Vector3(-3.2,5.15,-1.3),L,1.2,0.25,0.03,Color("6e3b30"))
	for i in 5:k.fbox(Vector3(-3.2,4.65,-1.8+i*0.25),L,0.16,0.18,0.03,Color("3b3a33"))
	# House two.
	k.gabled_mass(-1.0,1.4,z0,z1,5.2,1.6,"x",render)
	k.gable_roof(-1.0,1.4,z0,z1,5.2,1.6,"x",0.2,slate,Color("3f4749"))
	k.blk(-1.0,1.4,0,0.35,z0-0.04,z1,Color("6e6c62"))
	k.fbox(Vector3(0.6,1.25,z0),F,1.2,2.5,0.05,Kit.DARK)
	# Clearly closed carriage gate: the parcel is solid, not a traversable archway.
	for bar in 8:k.fbox(Vector3(0.08+bar*0.15,1.2,z0-0.07),F,0.035,2.30,0.035,Color("707367"))
	for y in [0.42,1.85]:k.fbox(Vector3(0.6,y,z0-0.085),F,1.15,0.055,0.035,Color("707367"))
	for i in 7:
		var t:=PI*float(i)/6.0
		k.fbox(Vector3(0.6+cos(t)*0.68,2.5+sin(t)*0.4,z0),F,0.22,0.16,0.08,Kit.TRIM)
	k.door(Vector3(-0.5,0.05,z0),F,0.75,2.05,Color("2f4642"))
	for x in [-0.5,0.6]:
		k.window(Vector3(x,3.5,z0),F,0.6,1.15,"shutter",Color("6a5a44"))
		k.window(Vector3(x,3.4,z1),B,0.55,1.05,"broken" if x>0 else "plain")
	# Shell-damaged slate patch: torn hole, bare rafters and a weighted tarp.
	var s2:=1.6/1.65
	var hole:=[]
	for q in [Vector2(-0.6,-1.95),Vector2(0.35,-1.95),Vector2(0.35,-1.2),Vector2(-0.6,-1.2)]:
		hole.append(Vector3(q.x,5.2+0.16+(q.y-z0)*s2,q.y))
	k.slab(hole,0.03,k.paint(Kit.DARK))
	for x in [-0.45,-0.15,0.15]:k.tube(Vector3(x,5.2+0.2+0.5*s2,-1.9),Vector3(x,5.2+0.2+1.2*s2,-1.2),0.035,Color("6b5a43"))
	var tarp:=[]
	for q in [Vector2(0.4,-2.1),Vector2(1.35,-2.1),Vector2(1.35,-1.05),Vector2(0.4,-1.05)]:
		tarp.append(Vector3(q.x,5.2+0.19+(q.y-z0)*s2,q.y))
	k.slab(tarp,0.03,k.paint(Color("56646a")))
	# House three: corner shop with half-raised roller shutter, parapet roof terrace.
	k.blk(1.4,3.2,0,4.6,z0,z1,Kit.CREAM,cream)
	k.parapet_roof(1.4,3.2,z0,z1,4.6,Color("9a917a"))
	k.fbox(Vector3(2.3,1.55,z0),F,1.4,1.1,0.04,Kit.DARK)
	k.fbox(Vector3(2.3,2.5,z0),F,1.6,0.35,0.07,Color("6d3b2e"))
	for i in 6:k.fbox(Vector3(2.3,1.55+i*0.1,z0-0.01),F,1.4,0.05,0.06,Color("8b8d84"))
	k.window(Vector3(2.3,3.5,z0),F,0.6,1.1,"shutter",Color("4e5f6a"))
	k.window(Vector3(3.2,3.5,-0.75),R,0.55,1.05,"shutter",Color("4e5f6a"))
	k.window(Vector3(3.2,1.4,0.0),R,0.55,1.0,"boarded")
	k.tube(Vector3(2.9,4.64,0.4),Vector3(2.9,5.4,0.4),0.33,Color("8a8e8c"))
	for i in 3:k.plant(Vector3(1.8+i*0.4,4.85,-2.0),0.2,121+i)
	k.chimney(-1.0,-0.75,5.4,8.3,Kit.BRICK,3)
	k.chimney(1.4,-0.5,4.6,7.0,Color("7c7366"),2)
	# Rear yards: one plot each, divided by party walls with separate gates.
	k.blk(-3.3,3.3,0.05,0.08,z1,3.3,Color("736f5d"))
	for x in [-1.0,1.4]:k.yard_wall(Vector2(x,z1+0.1),Vector2(x,3.3),1.1,Color("7d7563"))
	k.yard_wall(Vector2(-3.3,z1),Vector2(-3.3,3.3),1.2,Color("7d7563"))
	k.yard_wall(Vector2(3.3,z1),Vector2(3.3,3.3),1.2,Color("7d7563"))
	k.yard_wall(Vector2(-3.3,3.3),Vector2(-1.0,3.3),1.2,Color("7d7563"),1.15,0.9)
	k.yard_wall(Vector2(-1.0,3.3),Vector2(1.4,3.3),1.2,Color("7d7563"),1.2,0.9)
	k.yard_wall(Vector2(1.4,3.3),Vector2(3.3,3.3),1.2,Color("7d7563"),0.95,0.9)
	for x in [-2.9,-1.4]:k.tube(Vector3(x,0.08,2.1),Vector3(x,1.8,2.1),0.03,Color("5e5a4b"))
	k.tube(Vector3(-2.9,1.75,2.1),Vector3(-1.4,1.75,2.1),0.008,Color("d0cbb8"))
	for i in 4:k.blk(-2.75+i*0.35,-2.55+i*0.35,1.25,1.73,2.08,2.12,[Color("b8b2a0"),Color("7b8a90"),Color("a07060"),Color("c8c1a8")][i])
	k.blk(-0.85,0.25,0.05,1.8,2.2,3.1,Kit.TIMBER)
	k.slab([Vector3(-0.95,2.0,2.1),Vector3(0.35,2.0,2.1),Vector3(0.35,1.7,3.15),Vector3(-0.95,1.7,3.15)],0.05,k.paint(Color("5a5f58")))
	k.fbox(Vector3(-0.3,0.9,2.2),F,0.6,1.6,0.03,Color("4a3f2f"))
	for i in 3:k.plant(Vector3(1.8+i*0.5,0.35,2.6),0.25,131+i)
	for x in [2.9]:k.blk(x-0.22,x+0.22,0.05,1.0,1.1,1.5,Color("34463b"))

# Detached hipped villa set back behind a walled front garden with cypresses,
# portico entrance, single-storey kitchen wing and vine pergola terrace.
static func _villa(k)->void:
	var color:=Color("b09864")
	var wall:Material=k.wallmat(color)
	var tile:Material=k.roofmat(Kit.TERRACOTTA)
	var hd:float=k.d/2
	var x0:=-2.1;var x1:=2.1;var z0:=-0.4;var z1:=hd-0.6;var h:=5.0
	k.blk(x0,x1,0,h,z0,z1,color,wall)
	k.blk(x0-0.06,x1+0.06,0,0.45,z0-0.06,z1+0.06,Color("80786a"))
	k.blk(x0-0.06,x1+0.06,2.5,2.62,z0-0.06,z1+0.06,Kit.TRIM)
	k.hip_roof(x0,x1,z0,z1,h,1.25,0.42,tile)
	k.chimney(0.9,1.2,5.6,6.9,color,2)
	# Portico: columns, pediment and recessed door.
	for x in [-0.6,0.6]:
		k.tube(Vector3(x,0.45,-1.05),Vector3(x,2.6,-1.05),0.09,Color("c4baa0"))
		k.blk(x-0.14,x+0.14,0.05,0.45,-1.19,-0.91,Color("a59b85"))
	k.blk(-0.85,0.85,2.6,2.72,-1.3,z0,Kit.TRIM)
	k.prism_z([Vector2(-0.85,2.72),Vector2(0.85,2.72),Vector2(0.0,3.15)],-1.3,-1.18,k.paint(Kit.TRIM))
	k.gable_roof(-0.85,0.85,-1.3,z0,2.72,0.43,"z",0.06,tile)
	k.door(Vector3(0,0.45,z0),F,0.9,2.0,Color("4a3b2c"),false)
	k.blk(-0.9,0.9,0.05,0.45,-1.4,z0,Color("a59b85"))
	for x in [-1.45,1.45]:k.window(Vector3(x,1.6,z0),F,0.7,1.45,"shutter",Color("4d6a66"))
	for x in [-1.45,0.0,1.45]:k.window(Vector3(x,3.8,z0),F,0.62,1.2,"shutter",Color("4d6a66"))
	# One shutter hangs loose from its top hinge.
	k.fbox(Vector3(-0.05,3.75,z0-0.3),F,0.26,1.15,0.05,Color("4d6a66")).rotation=Vector3(0.0,0.35,0.22)
	for z in [0.5,1.6]:
		k.window(Vector3(x0,3.8,z),L,0.6,1.1,"shutter",Color("4d6a66"))
		k.window(Vector3(x1,3.8,z),R,0.6,1.1,"plain")
	for x in [-1.0,1.0]:k.window(Vector3(x,3.8,z1),B,0.6,1.1,"plain")
	# Kitchen wing with a single pitch roof falling away from the house.
	k.blk(x1,3.15,0,2.8,0.3,2.1,color,wall)
	k.slab([Vector3(2.05,3.22,0.12),Vector3(3.32,2.78,0.12),Vector3(3.32,2.78,2.28),Vector3(2.05,3.22,2.28)],0.1,tile)
	k.door(Vector3(3.15,0.05,1.2),R,0.75,1.9,Color("54473a"))
	k.window(Vector3(2.62,1.6,0.3),F,0.5,0.7,"plain")
	k.tube(Vector3(2.75,2.95,1.6),Vector3(2.75,3.55,1.6),0.08,Color("6b6152"))
	# Vine pergola terrace on the west.
	for p in [Vector2(-3.15,-0.2),Vector2(-3.15,1.0),Vector2(-3.15,2.2)]:
		k.tube(Vector3(p.x,0.05,p.y),Vector3(p.x,2.45,p.y),0.05,Color("6a5f48"))
	k.blk(-3.25,-3.05,2.45,2.53,-0.3,2.3,Color("6a5f48"))
	for i in 6:k.blk(-3.25,x0,2.53,2.6,-0.15+i*0.45-0.03,-0.15+i*0.45+0.03,Color("7b7153"))
	for i in 5:k.plant(Vector3(-2.65,2.72,-0.1+i*0.55),0.27,141+i,Color("51613a"))
	k.blk(-2.95,-2.25,0.7,0.75,0.6,1.3,Color("8a7e62"))
	k.blk(-2.65,-2.55,0.05,0.7,0.9,1.0,Color("4d4b39"))
	# Walled front garden: gate piers, gravel path, beds and cypress pair.
	var front:float=-hd+0.2
	k.blk(-3.3,3.3,0.05,0.07,front,z0,Color("5d6447"))
	k.blk(-0.5,0.5,0.05,0.09,front,-1.4,Color("a59d86"))
	k.yard_wall(Vector2(-3.3,front),Vector2(3.3,front),0.9,Color("a29880"),3.3,1.2)
	k.yard_wall(Vector2(-3.3,front),Vector2(-3.3,hd-0.2),1.1,Color("a29880"))
	k.yard_wall(Vector2(3.3,front),Vector2(3.3,hd-0.2),1.1,Color("a29880"))
	k.yard_wall(Vector2(-3.3,hd-0.2),Vector2(3.3,hd-0.2),1.1,Color("a29880"))
	k.cypress(-1.55,front+0.8,4.4,151)
	k.cypress(1.6,front+0.8,3.9,161)
	for i in 4:k.plant(Vector3(-2.8+i*0.32,0.25,-1.2),0.18,171+i,Color("5f6b3e"))
	for i in 4:k.plant(Vector3(2.0+i*0.32,0.25,-1.2),0.18,181+i,Color("6b6a3c"))
	for x in [-0.75,0.75]:
		k.blk(x-0.16,x+0.16,0.05,0.42,-1.58,-1.26,Color("8a5a40"))
		k.plant(Vector3(x,0.62,-1.42),0.2,191+int(x*4))

# Stone chapel with a corner bell tower, rose window and walled churchyard.
static func _chapel(k)->void:
	var stone:Material=k.wallmat(Kit.STONE)
	var tile:Material=k.roofmat(Kit.TERRACOTTA)
	var x0:=-1.3;var x1:=1.9;var z0:=-1.8;var z1:=3.1;var h:=4.0
	var xc:=(x0+x1)/2
	k.gabled_mass(x0,x1,z0,z1,h,1.7,"z",stone)
	k.gable_roof(x0,x1,z0,z1,h,1.7,"z",0.2,tile,Color("8a6048"))
	k.blk(x0-0.06,x1+0.06,0,0.5,z0-0.06,z1+0.06,Color("7a7262"))
	# West front: arched door, rose window, coping on the gable.
	k.disc(Vector3(xc,2.05,z0-0.04),F,0.64,Kit.TRIM)
	k.disc(Vector3(xc,2.05,z0-0.06),F,0.52,Color("4a3a2a"))
	k.door(Vector3(xc,0.05,z0),F,1.04,2.05,Color("4a3a2a"))
	k.disc(Vector3(xc,4.05,z0-0.04),F,0.55,Kit.TRIM)
	k.disc(Vector3(xc,4.05,z0-0.06),F,0.45,Kit.GLASS)
	for i in 4:
		var bar:MeshInstance3D=k.fbox(Vector3(xc,4.05,z0-0.1),F,0.86,0.05,0.04,Kit.TRIM)
		bar.rotation.z=i*PI/4
	# Buttresses and lancet windows along the nave.
	for z in [-0.55,0.95,2.45]:
		for side in [[x0,-1.0],[x1,1.0]]:
			var bx:float=side[0]+side[1]*0.22
			if side[1]<0 and z<0:continue
			k.blk(bx-0.22,bx+0.22,0,2.6,z-0.2,z+0.2,Kit.STONE,stone)
			k.slab([Vector3(bx-0.24,2.6,z-0.22),Vector3(bx-0.24,2.6,z+0.22),Vector3(bx+0.24,2.6-side[1]*0.35,z+0.22),Vector3(bx+0.24,2.6-side[1]*0.35,z-0.22)],0.06,k.paint(Color("7a7262")))
	for z in [0.2,1.7]:
		for side in [[x0,L],[x1,R]]:
			k.fbox(Vector3(side[0],2.1,z),side[1],0.4,1.5,0.04,Kit.GLASS)
			k.disc(Vector3(side[0],2.85,z)+side[1]*0.02,side[1],0.2,Kit.GLASS)
	# Bell tower: belfry openings, clock and pyramid cap.
	var t0:=-3.2;var t1:=-1.5;var u0:=-2.6;var u1:=-0.9;var th:=7.0
	k.blk(t0,t1,0,th,u0,u1,Kit.STONE,stone)
	for y in [5.1,th-0.12]:k.blk(t0-0.06,t1+0.06,y,y+0.14,u0-0.06,u1+0.06,Kit.TRIM)
	k.hip_roof(t0,t1,u0,u1,th,1.6,0.12,tile)
	k.tube(Vector3((t0+t1)/2,th+1.6,(u0+u1)/2),Vector3((t0+t1)/2,th+2.1,(u0+u1)/2),0.03,Kit.IRON)
	var mid:=Vector3((t0+t1)/2,0,(u0+u1)/2)
	for face in [[F,Vector3(mid.x,0,u0)],[B,Vector3(mid.x,0,u1)],[L,Vector3(t0,0,mid.z)],[R,Vector3(t1,0,mid.z)]]:
		k.fbox(face[1]+Vector3(0,5.95,0),face[0],0.62,1.0,0.03,Kit.DARK)
		k.disc(face[1]+Vector3(0,6.45,0)+face[0]*0.01,face[0],0.31,Kit.DARK)
		k.fbox(face[1]+Vector3(0,2.2,0),face[0],0.16,0.7,0.03,Kit.DARK)
	k.disc(Vector3(mid.x,4.45,u0-0.03),F,0.42,Color("d2c9ad"))
	for a in [0.3,1.9]:
		var hand:MeshInstance3D=k.fbox(Vector3(mid.x,4.45,u0-0.09),F,0.04,0.34,0.03,Kit.DARK)
		hand.rotation.z=a
	# Churchyard: graves, cypresses, bench, perimeter wall with gate on the door axis.
	var hw:float=k.w/2-0.2;var hd:float=k.d/2-0.2
	k.blk(-hw,hw,0.05,0.07,-hd,hd,Color("5a6243"))
	k.blk(xc-0.55,xc+0.55,0.05,0.09,-hd,z0,Color("a39b85"))
	k.yard_wall(Vector2(-1.2,-hd),Vector2(hw,-hd),0.95,Color("8b836d"),xc+1.2,1.1)
	k.yard_wall(Vector2(hw,-hd),Vector2(hw,hd),0.95,Color("8b836d"))
	k.yard_wall(Vector2(-hw,hd),Vector2(hw,hd),0.95,Color("8b836d"))
	k.yard_wall(Vector2(-hw,-0.7),Vector2(-hw,hd),0.95,Color("8b836d"))
	# Graves sit on the south side, facing the camera; cypresses screen the north.
	for i in 10:
		var gx:float=-2.95+0.75*float(i%2)
		var gz:float=-0.35+float(i/2)*0.72
		var grave:MeshInstance3D=k.blk(gx-0.2,gx+0.2,0.05,0.6+0.1*float(i%3),gz-0.05,gz+0.05,Color("a7a08c"))
		grave.rotation.z=float(i%3-1)*0.07
		k.blk(gx-0.18,gx+0.18,0.05,0.12,gz+0.08,gz+0.5,Color("6e6a58"))
	k.tube(Vector3(-2.2,0.05,2.95),Vector3(-2.2,1.25,2.95),0.05,Color("8a8270"))
	k.blk(-2.45,-1.95,0.85,0.95,2.9,3.0,Color("8a8270"))
	k.cypress(2.8,-2.55,4.6,201)
	k.cypress(2.75,-0.2,5.2,211)
	k.cypress(2.75,1.9,4.2,221)
	k.blk(2.55,3.0,0.38,0.44,0.6,1.2,Color("77694d"))
	# East end: triple lancet and oculus above the altar.
	for x in [xc-0.55,xc,xc+0.55]:
		k.fbox(Vector3(x,2.2,z1),B,0.32,1.4 if x==xc else 1.1,0.04,Kit.GLASS)
		k.disc(Vector3(x,2.9 if x==xc else 2.75,z1+0.02),B,0.16,Kit.GLASS)
	k.disc(Vector3(xc,4.5,z1+0.02),B,0.3,Kit.GLASS)

# Twin-gabled brick warehouse with arched doors, skylights, a loading dock,
# rendered two-storey office annex and an external steel stair.
static func _warehouse(k)->void:
	var brick:Material=k.wallmat(Kit.BRICK)
	var sheet:Material=k.metalmat(Kit.SHEET)
	var render:Material=k.wallmat(Kit.RENDER)
	var z0:=-2.2;var z1:=1.6;var h:=4.6;var rise:=1.3
	var bays:=[[-4.2,-0.9],[-0.9,2.4]]
	for bay in bays:
		var xc:float=(bay[0]+bay[1])/2
		k.gabled_mass(bay[0],bay[1],z0,z1,h,rise,"z",brick)
		k.gable_roof(bay[0],bay[1],z0,z1,h,rise,"z",0.1,sheet)
		# Arched cart door with brick voussoirs and a round gable vent.
		k.disc(Vector3(xc,2.8,z0-0.03),F,1.12,Color("5a3c30"))
		k.disc(Vector3(xc,2.8,z0-0.05),F,0.98,Kit.DARK)
		k.fbox(Vector3(xc,1.45,z0-0.05),F,1.96,2.8,0.05,Color("41504a"))
		for i in 6:k.fbox(Vector3(xc-0.82+i*0.33,1.45,z0-0.1),F,0.04,2.7,0.03,Color("2f3a35"))
		k.disc(Vector3(xc,h+0.55,z0-0.03),F,0.3,Kit.DARK)
		# Skylight strips; one roof bay lost sheets to shellfire.
		var slope:float=rise/((bay[1]-bay[0])/2)
		for i in 3:
			var q0:float=z0+0.4+i*1.2
			var lx0:float=bay[0]+0.45;var lx1:float=bay[0]+1.2
			var pane:=[]
			for q in [Vector2(lx0,q0),Vector2(lx1,q0),Vector2(lx1,q0+0.9),Vector2(lx0,q0+0.9)]:
				pane.append(Vector3(q.x,h+0.17+(q.x-bay[0]-0.1+0.1)*slope,q.y))
			k.slab(pane,0.03,k.paint(Kit.DARK if (i+int(xc))%3==0 else Color("53656b")))
	var hole:=[]
	var s1:float=rise/1.65
	for q in [Vector2(1.0,-0.4),Vector2(2.0,-0.4),Vector2(2.0,1.0),Vector2(1.0,1.0)]:
		hole.append(Vector3(q.x,h+0.17+(2.4-q.x)*s1,q.y))
	k.slab(hole,0.03,k.paint(Kit.DARK))
	for x in [1.25,1.5,1.75]:k.tube(Vector3(x,h+0.2+(2.4-x)*s1,-0.45),Vector3(x,h+0.2+(2.4-x)*s1,1.05),0.03,Color("6c4b36"))
	k.blk(-0.97,-0.83,h-0.05,h+0.1,z0-0.1,z1+0.1,Color("3b3f3c"))
	k.tube(Vector3(0.75,h+rise+0.1,1.4),Vector3(0.75,h+rise+0.7,1.4),0.16,Color("6d736e"))
	k.blk(-3.15,-1.95,3.75,4.15,z0-0.08,z0-0.03,Color("b8ad8f"))
	for i in 6:k.blk(-3.05+i*0.19,-2.93+i*0.19,3.85,4.05,z0-0.1,z0-0.07,Kit.DARK)
	for z in [-1.1,0.4]:k.window(Vector3(-4.2,2.6,z),L,0.75,1.0,"broken" if z>0 else "plain")
	for x in [-3.4,-1.7,0.0,1.6]:k.window(Vector3(x,2.6,z1),B,0.75,1.0,"plain" if x<0 else "broken")
	# Office annex.
	var a0:=2.4;var a1:=4.3;var a2:=-1.6
	k.blk(a0,a1,0,5.6,a2,z1,Kit.RENDER,render)
	k.parapet_roof(a0,a1,a2,z1,5.6,Color("8e8f86"))
	for y in [1.4,3.9]:
		k.window(Vector3(3.35,y,a2),F,0.9,1.0,"plain")
		for z in [-0.8,0.8]:k.window(Vector3(a1,y,z),R,0.55,0.95,"blind" if y<2 and z>1 else "plain")
	k.door(Vector3(2.85,0.05,a2),F,0.7,2.0,Color("40504c"),false)
	k.door(Vector3(3.95,2.95,a2),F,0.6,1.9,Color("40504c"),false)
	k.blk(3.4,4.3,2.85,2.95,-2.4,a2,Color("596059"))
	for i in 9:
		var t:=float(i)/9.0
		k.blk(2.6+t*0.8-0.12,2.6+t*0.8+0.12,0.25+t*2.6,0.31+t*2.6,-2.35,-1.9,Color("596059"))
	for side in [-2.38,-1.88]:
		k.tube(Vector3(2.45,0.1,side),Vector3(3.45,3.0,side),0.025,Color("596059"))
		k.tube(Vector3(4.25,2.95,side),Vector3(4.25,3.9,side),0.02,Color("596059"))
	k.tube(Vector3(3.45,3.9,-2.38),Vector3(4.25,3.9,-2.38),0.02,Color("596059"))
	# Loading dock with buffers, steps, crates, pallets and drums.
	var hd:float=k.d/2-0.2
	k.blk(-4.25,2.4,0,0.9,-hd,z0,Kit.CONCRETE)
	k.blk(-4.25,2.4,0.85,0.92,-hd-0.03,z0,Color("9a9888"))
	for x in [-3.6,-1.2,1.0]:k.blk(x-0.15,x+0.15,0.3,0.7,-hd-0.05,-hd+0.08,Color("2b2b28"))
	k.crate(-2.9,-2.85,0.6,0.92)
	k.crate(-2.25,-2.75,0.55,0.92,Color("6e5e42"))
	k.crate(-2.6,-2.8,0.45,1.43)
	k.blk(-0.2,0.9,0.92,1.02,-3.1,-2.4,Color("8a7a5b"))
	k.blk(-0.2,0.9,1.02,1.62,-3.05,-2.45,Color("5e6a5d"))
	for x in [3.3,3.85]:k.tube(Vector3(x,0.05,-2.9),Vector3(x,0.95,-2.9),0.26,Color("4f5d52") if x<3.5 else Color("7a3f2c"))
	k.blk(-4.3,4.3,0.05,0.08,z1,hd,Color("5f5e55"))
	k.yard_wall(Vector2(-4.3,hd),Vector2(4.3,hd),1.4,Color("7e7465"),6.2,1.4)
	# Rear service yard, seen from the game camera: short container, pallets,
	# forklift and gas bottles.
	k.blk(-4.1,-1.7,0.05,1.3,2.0,3.05,Color("7a3f2c"))
	for i in 12:k.fbox(Vector3(-3.95+i*0.2,0.68,3.05),B,0.06,1.15,0.03,Color("8c4c35"))
	for y in [0.1,1.25]:k.blk(-4.12,-1.68,y-0.05,y+0.05,1.98,3.07,Color("5b2f22"))
	for z in [2.25,2.8]:k.fbox(Vector3(-1.7,0.68,z),R,0.04,1.1,0.05,Color("5b2f22"))
	for p in [Vector2(-1.0,2.6),Vector2(-0.1,2.6),Vector2(-0.55,2.9)]:
		for j in 3:k.blk(p.x-0.38,p.x+0.38,0.05+j*0.16,0.15+j*0.16,p.y-0.3,p.y+0.3,Color("8a7a5b"))
	k.crate(-0.55,2.6,0.55,0.53,Color("6e5e42"))
	k.blk(0.9,1.6,0.25,1.15,2.1,2.75,Color("b89a3a"))
	k.blk(0.95,1.55,1.15,1.95,2.15,2.7,Color("33392f"))
	for z in [2.15,2.7]:k.tube(Vector3(0.82,0.1,z),Vector3(0.82,2.2,z),0.03,Kit.IRON)
	for z in [2.25,2.6]:k.blk(0.25,0.82,0.08,0.13,z-0.05,z+0.05,Kit.IRON)
	for x in [1.05,1.45]:k.tube(Vector3(x,0.2,2.05),Vector3(x,0.2,2.8),0.2,Color("262826"))
	for i in 4:k.tube(Vector3(2.9+i*0.35,0.08,2.9),Vector3(2.9+i*0.35,1.15,2.9),0.13,Color("707f6e"))

# Three-storey flat-roofed apartment block over shops, with balconies,
# rooftop services and a single-storey tyre workshop wing.
static func _flat_block(k)->void:
	var concrete:Material=k.wallmat(Kit.CONCRETE)
	var sheet:Material=k.metalmat(Kit.SHEET)
	var x0:=-3.2;var x1:=1.2;var z0:=-2.1;var z1:=2.8;var h:=7.4
	k.blk(x0,x1,0,h,z0,z1,Kit.CONCRETE,concrete)
	for y in [2.45,4.85]:k.blk(x0-0.05,x1+0.05,y,y+0.14,z0-0.05,z1+0.05,Color("9c9a8e"))
	k.parapet_roof(x0,x1,z0,z1,h,Color("8f8d82"))
	# Ground floor shops: one shutter closed, one half raised.
	for p in [[-2.2,false],[-0.35,true]]:
		var x:float=p[0]
		k.fbox(Vector3(x,1.15,z0),F,1.5,2.1,0.03,Kit.DARK)
		var bottom:=1.25 if p[1] else 0.1
		for i in int((2.2-bottom)/0.12):k.fbox(Vector3(x,bottom+i*0.12,z0-0.01),F,1.5,0.07,0.06,Color("8b8d84"))
		k.fbox(Vector3(x,2.3,z0),F,1.6,0.25,0.07,Color("5d3a2e") if p[1] else Color("37505a"))
	k.door(Vector3(0.75,0.05,z0),F,0.7,2.05,Color("3f4744"),false)
	k.blk(0.35,1.15,2.3,2.38,-2.55,z0,Color("8f8d82"))
	# Upper floors: windows, AC units, balconies with one bent railing.
	for y in [3.65,6.05]:
		for x in [-2.4,-1.0,0.4]:
			var style:="boarded" if (y>5 and x>0) else "plain"
			k.window(Vector3(x,y,z0),F,0.8,1.15,style)
		k.blk(-3.0,-0.3,y-1.15,y-1.05,-2.65,z0,Color("9c9a8e"))
		k.blk(-3.0,-0.3,y-1.05,y-0.6,-2.66,-2.6,Color("8f8d82"))
		for x in [-3.0,-0.3]:k.blk(x-0.03,x+0.03,y-1.05,y-0.15,-2.65,z0,Color("8f8d82"))
		k.tube(Vector3(-3.0,y-0.18,-2.63),Vector3(-0.3,y-0.18+(0.12 if y>5 else 0.0),-2.63-(0.12 if y>5 else 0.0)),0.02,Kit.IRON)
		k.fbox(Vector3(0.4,y-0.95,z0),F,0.6,0.4,0.25,Color("a3a59d"))
		k.disc(Vector3(0.4,y-0.95,z0-0.26),F,0.14,Color("4b4e4a"))
	k.plant(Vector3(-2.6,4.05,-2.38),0.2,231)
	k.blk(-1.8,-1.2,2.75,3.4,-2.6,-2.55,Color("b7a37e"))
	# Shell scars and a chipped corner on the street face.
	for p in [Vector3(-1.7,5.4,0.3),Vector3(0.9,3.0,-0.4),Vector3(-2.9,6.6,0.6)]:
		var scar:MeshInstance3D=k.fbox(Vector3(p.x,p.y,z0),F,0.45,0.32,0.025,Color("4d4a42"))
		scar.rotation.z=p.z
	k.fbox(Vector3(x1-0.32,h-0.45,z0),F,0.6,0.9,0.03,Color("4d4a42"))
	k.rubble(0.5,1.15,-2.95,-2.25,6,0.25,[Color("85847a"),Color("5a574e")])
	for z in [-0.8,0.6,2.0]:
		for y in [3.65,6.05]:k.window(Vector3(x0,y,z),L,0.7,1.0,"plain" if z<1.5 else "broken")
	for x in [-2.4,-1.0,0.4]:k.window(Vector3(x,4.85,z1),B,0.7,1.0,"plain")
	# South flank above the workshop roof: stair-light strip and flat windows.
	for y in [3.65,6.05]:
		for z in [-1.1,1.9]:k.window(Vector3(x1,y,z),R,0.7,1.0,"plain" if y<5 or z<0 else "broken")
		k.fbox(Vector3(x1,y,0.4),R,0.35,1.5,0.04,Kit.GLASS)
	k.fbox(Vector3(x1,5.0,-1.9),R,0.12,2.4,0.3,Color("6d3b2e"))
	for i in 4:k.fbox(Vector3(x1+0.15,4.25+i*0.5,-1.96),F,0.2,0.32,0.03,Color("d0c49c"))
	# Roof: stair house, water tank on legs, HVAC units, dish and antenna.
	k.blk(-2.9,-1.7,h,h+2.2,1.4,2.5,Kit.CONCRETE,concrete)
	k.blk(-2.95,-1.65,h+2.2,h+2.3,1.35,2.55,Color("6a6a62"))
	k.door(Vector3(-2.3,h,1.4),F,0.6,1.8,Color("40504c"),false)
	for p in [Vector2(0.0,1.3),Vector2(0.7,1.3),Vector2(0.0,2.0),Vector2(0.7,2.0)]:
		k.tube(Vector3(p.x,h,p.y),Vector3(p.x,h+0.8,p.y),0.03,Kit.IRON)
	k.tube(Vector3(0.35,h+0.8,1.65),Vector3(0.35,h+1.9,1.65),0.48,Color("8c8f8b"))
	for p in [Vector2(-2.5,-1.0),Vector2(-1.3,-1.0)]:
		k.blk(p.x-0.4,p.x+0.4,h+0.04,h+0.75,p.y-0.35,p.y+0.35,Color("a2a49c"))
		k.disc(Vector3(p.x,h+0.78,p.y),Vector3.UP,0.25,Color("4b4e4a"))
	k.tube(Vector3(0.6,h+0.5,-1.6),Vector3(0.6,h+1.0,-1.6),0.03,Kit.IRON)
	k.disc(Vector3(0.6,h+1.15,-1.6),Vector3(0.5,0.6,-0.6).normalized(),0.42,Color("c2c1b8"))
	k.tube(Vector3(-0.6,h,0.4),Vector3(-0.6,h+2.6,0.4),0.025,Kit.IRON)
	for i in 3:k.tube(Vector3(-0.95,h+1.8+i*0.25,0.4),Vector3(-0.25,h+1.8+i*0.25,0.4),0.015,Kit.IRON)
	# Tyre workshop wing with a sheet roof and forecourt clutter.
	var a0:=-1.4
	k.blk(x1,3.2,0,3.0,a0,z1,Kit.CONCRETE,concrete)
	k.lean_roof(x1-0.05,3.3,a0-0.15,z1+0.1,3.25,2.75,sheet)
	k.fbox(Vector3(2.2,1.2,a0),F,1.6,2.3,0.04,Color("3d4a4c"))
	for i in 9:k.fbox(Vector3(2.2,0.15+i*0.25,a0-0.02),F,1.6,0.04,0.05,Color("6b7472"))
	k.fbox(Vector3(2.2,2.65,a0),F,1.9,0.3,0.06,Color("b8a24f"))
	k.window(Vector3(3.2,1.7,0.8),R,0.8,0.7,"plain")
	var hd:float=k.d/2-0.2
	k.blk(-3.3,3.3,0.05,0.08,-hd,z0,Color("6d6c64"))
	for stack in [Vector2(2.95,-2.0),Vector2(2.95,-2.75)]:
		for i in 4:k.tube(Vector3(stack.x,0.08+i*0.24,stack.y),Vector3(stack.x,0.3+i*0.24,stack.y),0.3,Color("262826"))
	k.blk(1.5,2.4,0.05,0.85,-2.9,-2.5,Color("6b5a43"))
	k.tube(Vector3(1.75,0.85,-2.7),Vector3(1.75,1.05,-2.7),0.08,Color("a0352a"))
	k.blk(-3.3,3.3,0.05,0.08,z1,hd,Color("5f5e55"))
	k.yard_wall(Vector2(-3.3,hd),Vector2(3.3,hd),1.6,Color("6f6d63"))
	for i in 3:k.blk(-2.8+i*0.6,-2.35+i*0.6,0.05,1.05,2.95,3.25,[Color("355c46"),Color("2f3f52"),Color("6a6a40")][i])

# L-plan farmstead: ochre farmhouse with exterior stair, stone barn with
# sheet roof and plank doors, polytunnel greenhouse and raised beds.
static func _farmstead(k)->void:
	var color:=Color("a8925f")
	var wall:Material=k.wallmat(color)
	var stone:Material=k.wallmat(Kit.STONE)
	var tile:Material=k.roofmat(Kit.TERRACOTTA)
	var sheet:Material=k.metalmat(Kit.SHEET)
	var hw:float=k.w/2;var hd:float=k.d/2
	var x0:=-hw+0.2;var x1:=0.6;var z0:=-2.4;var z1:=0.6;var h:=5.0
	k.gabled_mass(x0,x1,z0,z1,h,1.4,"x",wall)
	k.gable_roof(x0,x1,z0,z1,h,1.4,"x",0.18,tile,Color("8a6048"))
	k.blk(x0-0.04,x1,0,0.4,z0-0.04,z1+0.04,Color("7d7563"))
	k.chimney(x0+0.6,-0.9,5.6,7.0,color,1)
	# Exterior stone stair from the courtyard to the upper living floor.
	for i in 8:
		var t:=float(i)/8.0
		k.blk(-2.4+t*1.4,-2.4+t*1.4+0.22,0,0.3+t*2.3,z1,z1+0.5,Color("8b836d"))
	k.blk(-1.0,-0.2,0,2.65,z1,z1+0.5,Color("8b836d"))
	k.tube(Vector3(-2.4,1.1,z1+0.48),Vector3(-1.0,3.4,z1+0.48),0.02,Kit.IRON)
	k.tube(Vector3(-1.0,3.4,z1+0.48),Vector3(-0.2,3.4,z1+0.48),0.02,Kit.IRON)
	k.door(Vector3(-0.6,2.65,z1),B,0.75,1.9,Color("5b4632"),false)
	k.window(Vector3(-0.6,3.6,z0),F,0.55,0.95,"shutter",Color("6b5338"))
	k.door(Vector3(0.05,0.05,z0),F,0.8,2.0,Color("5b4632"))
	k.window(Vector3(-2.3,1.5,z0),F,0.55,0.9,"shutter",Color("6b5338"))
	k.window(Vector3(-1.9,3.6,z0),F,0.55,0.95,"shutter",Color("6b5338"))
	k.window(Vector3(x0,3.6,-0.9),L,0.55,0.95,"shutter",Color("6b5338"))
	k.window(Vector3(-2.0,3.6,z1),B,0.55,0.95,"plain")
	for i in 8:k.plant(Vector3(x0+0.02,0.5+i*0.45,-2.0+fmod(i*0.53,1.0)),0.15,241+i,Color("4b5d34"))
	# Stone barn, gable end to the lane.
	var b0:=x1;var b1:=hw-0.2;var c0:=-2.6;var c1:=hd-0.6
	var bc:=(b0+b1)/2
	k.gabled_mass(b0,b1,c0,c1,3.8,1.3,"z",stone)
	k.gable_roof(b0,b1,c0,c1,3.8,1.3,"z",0.12,sheet)
	k.fbox(Vector3(bc,1.35,c0),F,1.5,2.6,0.05,Kit.TIMBER)
	for i in 5:k.fbox(Vector3(bc-0.6+i*0.3,1.35,c0-0.05),F,0.03,2.5,0.02,Color("4a3f2f"))
	var brace:MeshInstance3D=k.fbox(Vector3(bc,1.35,c0-0.08),F,0.1,2.8,0.03,Color("4a3f2f"))
	brace.rotation.z=0.52
	k.fbox(Vector3(bc,4.25,c0),F,0.6,0.55,0.04,Kit.DARK)
	k.window(Vector3(b1,2.2,0.5),R,0.4,0.5,"broken")
	# Hay bales and a ladder against the barn.
	for x in [1.0,2.4]:k.tube(Vector3(x,0.05,-3.05),Vector3(x,0.8,-3.05),0.37,Color("b49a5c"))
	k.tube(Vector3(2.4,0.8,-3.05),Vector3(2.4,1.5,-3.05),0.34,Color("a68e55"))
	# Kitchen-garden courtyard: polytunnel, raised beds, water butt, fence.
	k.blk(x0,x1,0.05,0.07,z1,hd-0.2,Color("5b5233"))
	var g0:=x0+0.15;var g1:=-0.75;var gz0:=z1+0.75;var gz1:=hd-0.45
	var gc:=(g0+g1)/2;var gr:=(g1-g0)/2
	for i in 5:
		var z:=gz0+i*(gz1-gz0)/4
		var prev:=Vector3(g0,0.05,z)
		for s in range(1,7):
			var a:=PI-PI*float(s)/6.0
			var next:=Vector3(gc+cos(a)*gr,0.05+sin(a)*gr*1.05,z)
			k.tube(prev,next,0.02,Color("8f948c"))
			prev=next
	for s in 6:
		var a0:=PI-PI*float(s)/6.0;var a1:=PI-PI*float(s+1)/6.0
		var p0:=Vector2(gc+cos(a0)*(gr-0.03),0.05+sin(a0)*(gr-0.03)*1.05)
		var p1:=Vector2(gc+cos(a1)*(gr-0.03),0.05+sin(a1)*(gr-0.03)*1.05)
		if s==2:continue
		k.slab([Vector3(p0.x,p0.y,gz0),Vector3(p1.x,p1.y,gz0),Vector3(p1.x,p1.y,gz1),Vector3(p0.x,p0.y,gz1)],0.02,k.paint(Color("b9c2b8")))
	for i in 3:
		var bz:=z1+0.75+i*0.75
		k.blk(-0.55,0.4,0.05,0.3,bz-0.25,bz+0.25,Kit.TIMBER)
		for j in 3:k.plant(Vector3(-0.35+j*0.3,0.42,bz),0.14,251+i*3+j,Color("5b7a3a"))
	k.tube(Vector3(0.45,0.05,z1+0.3),Vector3(0.45,0.85,z1+0.3),0.22,Color("3f5a4a"))
	k.yard_wall(Vector2(x0,z1),Vector2(x0,hd-0.2),1.0,Color("8b836d"))
	for i in 9:
		var fx:float=x0+i*(b1-x0)/8.0
		k.blk(fx-0.05,fx+0.05,0.05,1.2,hd-0.27,hd-0.17,Kit.TIMBER)
	for y in [0.45,0.95]:k.blk(x0,b1,y,y+0.08,hd-0.25,hd-0.19,Color("6c5d43"))
	# Lane frontage: woodpile and a low wall.
	for i in 3:k.tube(Vector3(-2.7,0.12+i*0.16,-3.15),Vector3(-1.4,0.12+i*0.16,-3.15),0.08,Color("6e5a3e"))
