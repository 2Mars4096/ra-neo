class_name RuinedBuilding
extends RefCounted

# Collapsed, impassable buildings authored inside the existing blocker.
# Four damage stories, each with a different former function and failure:
# a shelled townhouse, a burnt-out industrial shed, a roofless stone barn and
# a corner shop whose street corner fell into the parcel.
const Kit=preload("res://scripts/parcel_kit.gd")
const F:=Vector3(0,0,-1)
const B:=Vector3(0,0,1)
const L:=Vector3(-1,0,0)
const R:=Vector3(1,0,0)
const DEBRIS:=[Color("675344"),Color("797769"),Color("514d43"),Color("8b8070")]

static func build(art,parent:Node3D,r:Rect2,index:int,specification:Dictionary={})->void:
	var plan:Array=Kit.design(r,index,true,specification)
	if not (plan[0] in Kit.RUINS):plan=[Kit.RUINS[index%Kit.RUINS.size()],plan[1]]
	var k=Kit.new(art,parent,r,plan[1],1307+index)
	k.blk(-k.w/2,k.w/2,0,0.05,-k.d/2,k.d/2,Color("55524a"))
	match plan[0]:
		"shelled_house":_shelled_house(k)
		"gutted_shed":_gutted_shed(k)
		"roofless_barn":_roofless_barn(k)
		"corner_collapse":_corner_collapse(k)
	k.finish()

# Ragged wall run: piers of uneven height between window openings.
static func _ragged(k,a:float,b:float,fixed:float,along_x:bool,top:float,variance:float,material:Material,color:Color,thick:float=0.32)->void:
	var bays:=maxi(2,int(absf(b-a)/1.1))
	var step:float=(b-a)/bays
	for i in bays:
		var u0:float=a+i*step;var u1:float=u0+step
		var tall:float=top-variance*float((i*7+3)%4)/3.0
		var sill:=0.95
		var pier:float=u0+step*0.35
		if along_x:
			k.blk(u0,pier,0,tall,fixed-thick/2,fixed+thick/2,color,material)
			k.blk(pier,u1,0,sill,fixed-thick/2,fixed+thick/2,color,material)
			if tall>2.6:k.blk(pier,u1,2.25,minf(tall,2.6+0.4*float(i%2)),fixed-thick/2,fixed+thick/2,color,material)
		else:
			k.blk(fixed-thick/2,fixed+thick/2,0,tall,u0,pier,color,material)
			k.blk(fixed-thick/2,fixed+thick/2,0,sill,pier,u1,color,material)
			if tall>2.6:k.blk(fixed-thick/2,fixed+thick/2,2.25,minf(tall,2.6+0.4*float(i%2)),pier,u1,color,material)

# Three-storey townhouse: the north half stands with its roof, the south half
# (towards the camera) has lost its outer walls and floors, which slide into a
# rubble mound filling that part of the parcel.
static func _shelled_house(k)->void:
	var plaster:=Color("8b8070")
	var wall:Material=k.wallmat(plaster)
	var tile:Material=k.roofmat(Kit.TERRACOTTA)
	var hw:float=k.w/2-0.25;var hd:float=k.d/2-0.25
	var z0:=-1.6;var z1:=2.0;var split:=-0.2;var h:=7.0
	k.gabled_mass(split,hw-0.15,z0,z1,h,1.3,"x",wall)
	k.gable_roof(split+0.4,hw-0.15,z0,z1,h,1.3,"x",0.18,tile)
	for y in [2.35,4.65]:k.blk(split,hw-0.1,y,y+0.13,z0-0.05,z1+0.05,Color("9b8e78"))
	# Broken roof edge: snapped rafters and battens reaching over the void.
	for i in 5:
		var z:float=z0+0.25+i*0.75
		var y:float=h+0.15+1.3*(1.0-absf(z-0.2)/1.8)
		k.tube(Vector3(split+0.45,y,z),Vector3(split-0.55-0.2*(i%3),y-0.5-0.25*(i%2),z+0.1),0.05,Color("4d4535"))
	k.tube(Vector3(split+0.45,h+1.45,0.2),Vector3(split-0.9,h+1.0,0.2),0.07,Color("4d4535"))
	# Exposed rooms on the fractured face: wallpaper, sagging slabs, a bathtub.
	for p in [[1.2,Color("7f6f5c")],[3.55,Color("6b7a6e")],[5.85,Color("8a7a66")]]:
		k.fbox(Vector3(split,p[0],0.2),L,3.2,1.9,0.03,p[1])
	for y in [2.4,4.7]:
		var sag:MeshInstance3D=k.blk(split-1.3,split+0.1,y-0.08,y+0.08,z0+0.2,z1-0.2,Color("6e675a"))
		sag.rotation.z=0.22 if y<3 else 0.4
	k.blk(split-1.0,split-0.25,4.85,5.2,0.9,1.6,Color("c4c0b2")).rotation.z=0.35
	# Remaining shell of the lost half: rear wall and end wall with jagged tops.
	_ragged(k,-hw,split,z1-0.16,true,4.6,1.6,wall,plaster)
	_ragged(k,z0+0.4,z1,-hw+0.16,false,2.9,1.2,wall,plaster)
	k.blk(-hw,-hw+0.6,0,1.6,z0,z0+0.4,plaster,wall)
	var fall:MeshInstance3D=k.blk(-hw+0.5,split-0.2,0.9,1.06,z0+0.6,z1-0.4,Color("6e675a"))
	fall.rotation.z=0.42
	k.rubble(-hw,split+0.1,z0-0.6,hd,85,1.25,DEBRIS)
	k.rubble(-hw,hw,-hd,z0,30,0.35,DEBRIS)
	for i in 4:
		var x:float=split-0.4-i*0.6
		k.tube(Vector3(x,0.2,z1+0.8-i*0.3),Vector3(x-0.5,1.6-i*0.2,z1-1.0),0.06,Color("4d4535"))
	# Surviving facades: shattered shopfront and bare awning frame to the street,
	# damaged sash windows to the rear yard.
	k.fbox(Vector3(1.6,1.25,z0),F,2.6,1.9,0.04,Kit.DARK)
	for x in [0.3,1.6,2.9]:k.fbox(Vector3(x,1.25,z0),F,0.08,1.9,0.07,Color("3a3f39"))
	k.fbox(Vector3(1.2,1.0,z0-0.04),F,0.5,0.45,0.02,Kit.GLASS)
	for x in [0.3,2.9]:k.tube(Vector3(x,2.3,z0),Vector3(x,1.95,z0-0.85),0.02,Kit.IRON)
	k.tube(Vector3(0.3,1.95,z0-0.85),Vector3(2.9,2.05,z0-0.8),0.02,Kit.IRON)
	var styles:=["broken","shutter","boarded","broken"]
	for i in 2:
		for floor_i in 2:
			var x:float=0.8+i*1.6
			k.window(Vector3(x,3.5+floor_i*2.3,z0),F,0.6,1.15,styles[(i+floor_i*2)%4],Color("59624f"))
			k.window(Vector3(x,3.5+floor_i*2.3,z1),B,0.6,1.1,styles[(i+floor_i+1)%4])
	k.door(Vector3(1.6,0.05,z1),B,0.8,2.0,Color("3e3a30"))
	k.window(Vector3(hw-0.15,3.5,0.2),R,0.55,1.0,"boarded")
	k.chimney(2.2,0.9,7.4,8.6,Color("6f5b48"),2)
	for p in [Vector3(2.0,5.2,0.4),Vector3(0.6,2.9,-0.3)]:
		var scar:MeshInstance3D=k.fbox(Vector3(p.x,p.y,z1),B,0.55,0.4,0.025,Color("4a463e"))
		scar.rotation.z=p.z
	k.yard_wall(Vector2(split+0.3,hd-0.1),Vector2(hw,hd-0.1),1.2,Color("7d7563"),1.6,1.0)

# Burnt-out brick shed: steel trusses standing over an empty floor, a broken
# gable towards the camera, a few
# remaining sheets, one collapsed truss and scorched brickwork.
static func _gutted_shed(k)->void:
	var brick:Material=k.wallmat(Kit.BRICK)
	var sheet:Material=k.metalmat(Kit.SHEET)
	var hw:float=k.w/2-0.25;var hd:float=k.d/2-0.25
	var x0:float=-hw;var x1:float=hw;var z0:=-2.7;var z1:float=hd;var h:=4.0;var rise:=1.5
	var zc:=(z0+z1)/2
	# Left gable intact; right gable broken below its apex.
	k.prism_x([Vector2(z0,0),Vector2(z1,0),Vector2(z1,h),Vector2(zc,h+rise),Vector2(z0,h)],x1-0.32,x1,brick)
	k.prism_x([Vector2(z0,0),Vector2(z1,0),Vector2(z1,h-0.6),Vector2(zc+0.6,h+0.3),Vector2(z0+0.8,h)],x0,x0+0.32,brick)
	k.fbox(Vector3(x1,2.0,zc),R,1.6,2.6,0.03,Kit.DARK)
	k.fbox(Vector3(x0,1.6,zc-0.4),L,1.8,2.2,0.03,Kit.DARK)
	# Long walls: brick piers with fallen infill between them.
	for z in [z0+0.16,z1-0.16]:
		var bays:=4
		for i in bays+1:
			var x:float=x0+0.32+i*(x1-x0-0.64)/bays
			var top:float=h if (i+int(z>0))%3!=1 else h-1.3
			k.blk(x-0.24,x+0.24,0,top,z-0.18,z+0.18,Kit.BRICK,brick)
			if i<bays:
				var nx:float=x0+0.32+(i+1)*(x1-x0-0.64)/bays
				k.blk(x+0.24,nx-0.24,0,0.9+0.6*float((i+int(z>0))%2),z-0.14,z+0.14,Kit.BRICK,brick)
	# Steel trusses: chord, rafters and web members.
	for i in 3:
		var x:float=-2.6+i*2.6
		var steel:=Color("3c403d")
		if i==2:
			k.tube(Vector3(x,0.3,z0+0.4),Vector3(x+0.4,h-0.4,z1-0.3),0.06,steel)
			k.tube(Vector3(x+0.4,h-0.4,z1-0.3),Vector3(x-0.2,2.0,zc),0.05,steel)
			continue
		k.tube(Vector3(x,h,z0+0.2),Vector3(x,h,z1-0.2),0.05,steel)
		k.tube(Vector3(x,h,z0+0.2),Vector3(x,h+rise,zc),0.06,steel)
		k.tube(Vector3(x,h,z1-0.2),Vector3(x,h+rise,zc),0.06,steel)
		for t in [0.25,0.5,0.75]:
			var zz:float=lerpf(z0+0.2,z1-0.2,t)
			var yy:float=h+rise*(1.0-absf(zz-zc)/(zc-z0-0.2))
			k.tube(Vector3(x,h,zz),Vector3(x,yy,zz),0.025,steel)
	for side in [-1.0,1.0]:
		for t in [0.3,0.65]:
			var zz:float=lerpf(zc,z0+0.2 if side<0 else z1-0.2,t)
			var yy:float=h+rise*(1.0-t)+0.06
			k.tube(Vector3(x0+0.3,yy,zz),Vector3(0.4,yy,zz),0.035,Color("4a4c47"))
	# Surviving sheets on the street slope near the intact gable.
	var slope:float=rise/(zc-z0)
	for i in 3:
		var a:float=x0+0.4+i*0.9;var b:float=a+0.85
		var top:float=zc-0.1-0.4*float(i%2)
		k.slab([Vector3(a,h+0.12,z0+0.1),Vector3(b,h+0.12,z0+0.1),Vector3(b,h+0.12+(top-z0-0.1)*slope,top),Vector3(a,h+0.12+(top-z0-0.1)*slope,top)],0.04,sheet)
	# Fallen sheets, scorch, debris and charred crates.
	for i in 5:
		var px:float=-2.2+i*1.05;var pz:float=-0.6+0.7*float(i%3)
		var fallen:MeshInstance3D=k.blk(px-0.42,px+0.42,0.3,0.34,pz-0.6,pz+0.6,Kit.SHEET,sheet)
		fallen.rotation=Vector3(0.3*float(i%2*2-1),0.4*i,0.2)
	for p in [Vector3(x0+0.33,1.5,-0.6),Vector3(x1-0.33,1.0,1.2)]:
		k.fbox(Vector3(p.x,p.y,p.z),R if p.x<0 else L,1.4,minf(2.2,p.y*2.0),0.02,Color("2c2a26"))
	k.rubble(x0+0.5,x1-0.5,z0+0.5,z1-0.5,45,0.45,[Color("675344"),Color("3a3733"),Color("514d43")])
	for p in [Vector2(2.6,1.9),Vector2(3.1,1.4),Vector2(2.75,1.15)]:k.crate(p.x,p.y,0.55,0.0,Color("3f362b"))
	k.tube(Vector3(-0.8,0.05,1.6),Vector3(-0.8,0.95,1.6),0.28,Color("5b2f22"))
	k.rubble(x0,x1,-k.d/2+0.1,z0-0.2,18,0.2,DEBRIS)
	var sign:MeshInstance3D=k.blk(-1.6,0.2,0.08,0.13,-3.6,-3.05,Color("b8ad8f"))
	sign.rotation.y=0.15

# Stone barn/farmhouse burnt to its walls: both gables stand, rafters survive
# on one slope only, timber and tile debris inside.
static func _roofless_barn(k)->void:
	var stone:Material=k.wallmat(Kit.STONE)
	var tile:Material=k.roofmat(Kit.TERRACOTTA)
	var hd:float=k.d/2-0.25
	var x0:=-3.0;var x1:=3.0;var z0:=-1.8;var z1:=2.2;var h:=4.0;var rise:=1.8
	var zc:=(z0+z1)/2
	k.prism_x([Vector2(z0,0),Vector2(z1,0),Vector2(z1,h),Vector2(zc,h+rise),Vector2(z0,h)],x0,x0+0.36,stone)
	k.prism_x([Vector2(z0,0),Vector2(z1,0),Vector2(z1,h),Vector2(zc+0.5,h+0.9),Vector2(zc-0.4,h+1.1),Vector2(z0,h)],x1-0.36,x1,stone)
	_ragged(k,x0+0.36,x1-0.36,z0+0.18,true,h,0.9,stone,Kit.STONE,0.36)
	_ragged(k,x0+0.36,x1-0.36,z1-0.18,true,h,0.5,stone,Kit.STONE,0.36)
	k.fbox(Vector3(x0,1.1,zc),L,1.2,2.2,0.03,Kit.DARK)
	k.fbox(Vector3(x0,h+0.7,zc),L,0.45,0.6,0.03,Kit.DARK)
	k.chimney(x0+0.55,zc+0.9,h,h+2.6,Color("7d7563"),1)
	# Rear slope rafters and a patch of surviving tiles; ridge beam sags.
	k.tube(Vector3(x0+0.3,h+rise-0.05,zc),Vector3(1.4,h+rise-0.35,zc),0.07,Color("3f382c"))
	var slope:float=rise/(z1-zc)
	for i in 9:
		var x:float=x0+0.6+i*0.45
		var snap:float=1.0 if i<6 else 0.55
		var ridge_y:float=h+rise-0.05-0.3*float(i)/8.0
		k.tube(Vector3(x,h+0.05,z1-0.15),Vector3(x,lerpf(h+0.05,ridge_y,snap),lerpf(z1-0.15,zc,snap)),0.045,Color("4a4233"))
	k.slab([Vector3(x0+0.45,h+0.2,z1-0.15),Vector3(-0.9,h+0.2,z1-0.15),Vector3(-0.9,h+0.2+1.1*slope,z1-1.25),Vector3(x0+0.45,h+0.2+1.1*slope,z1-1.25)],0.06,tile)
	for i in 6:
		var z:float=z1-0.3-i*0.3
		k.tube(Vector3(x0+0.4,h+0.12+(z1-0.15-z)*slope,z),Vector3(0.6,h+0.12+(z1-0.15-z)*slope,z),0.018,Color("5b4f3b"))
	# Fallen rafters and tile debris across the floor.
	for i in 4:
		var x:float=-1.5+i*1.0
		k.tube(Vector3(x,0.3,z0+0.5),Vector3(x+0.6,2.2-0.35*i,zc+0.3),0.05,Color("3f382c"))
	k.rubble(x0+0.5,x1-0.5,z0+0.45,z1-0.45,55,0.55,[Color("7d5640"),Color("8a6048"),Color("514d43"),Color("797769")])
	# Yard remnants: woodpile, broken fence, cart.
	for i in 4:k.tube(Vector3(-2.6,0.1+i*0.15,z1+0.55),Vector3(-1.2,0.1+i*0.15,z1+0.55),0.07,Color("6e5a3e"))
	for i in 6:
		var fx:float=-0.2+i*0.6
		var post:MeshInstance3D=k.blk(fx-0.05,fx+0.05,0.05,1.0,hd-0.1,hd,Kit.TIMBER)
		post.rotation.x=0.12*float(i%3-1)
	k.blk(-0.2,1.8,0.55,0.62,hd-0.08,hd-0.02,Color("6c5d43"))
	k.blk(1.5,2.6,0.45,0.75,-2.9,-2.3,Kit.TIMBER)
	for x in [1.55,2.55]:k.tube(Vector3(x,0.32,-2.6),Vector3(x+0.05,0.32,-2.6),0.32,Color("4a3f2f"))
	k.tube(Vector3(1.45,0.6,-2.6),Vector3(0.4,0.12,-2.6),0.03,Kit.TIMBER)
	k.rubble(x0,x1,-k.d/2+0.1,z0-0.2,14,0.2,DEBRIS)

# Two-storey corner shop: the street range and its roof survive with a blast
# hole; the rear corner (towards the camera) has collapsed into a slab-and-
# rubble cone, exposing papered rooms and a hanging stair.
static func _corner_collapse(k)->void:
	var plaster:=Color("9a8463")
	var wall:Material=k.wallmat(plaster)
	var tile:Material=k.roofmat(Kit.TERRACOTTA)
	var hw:float=k.w/2-0.3;var hd:float=k.d/2-0.25
	var z0:=-2.2;var zm:=0.2;var z1:=2.4;var h:=5.6;var split:=0.6
	# Street range with hipped roof; the blast hole is on the rear slope.
	k.blk(-hw,hw,0,h,z0,zm,plaster,wall)
	k.hip_roof(-hw,hw,z0,zm,h,1.2,0.2,tile)
	var hole:=[]
	var slope:float=1.25/1.4
	for q in [Vector2(-1.9,0.15),Vector2(-0.6,0.15),Vector2(-0.8,-0.55),Vector2(-1.7,-0.55)]:
		hole.append(Vector3(q.x,h+0.0+(zm+0.2-q.y)*slope,q.y))
	k.slab(hole,0.03,k.paint(Kit.DARK))
	for x in [-1.6,-1.25,-0.9]:k.tube(Vector3(x,h+0.1,0.25),Vector3(x+0.1,h+0.75,-0.6),0.035,Color("4d4535"))
	k.fbox(Vector3(-0.6,1.25,z0),F,3.0,1.9,0.04,Kit.DARK)
	k.fbox(Vector3(-0.6,2.45,z0),F,3.4,0.35,0.07,Color("6d3b2e"))
	for x in [-2.0,0.8]:k.tube(Vector3(x,2.3,z0),Vector3(x+0.15,2.0,z0-0.85),0.02,Kit.IRON)
	k.tube(Vector3(-1.85,2.0,z0-0.85),Vector3(0.95,1.8,z0-0.85),0.02,Kit.IRON)
	for x in [-2.0,0.0,2.0]:k.window(Vector3(x,3.9,z0),F,0.6,1.1,["broken","boarded","shutter"][int(x+2.0)/2],Color("59624f"))
	k.window(Vector3(-hw,3.8,-1.0),L,0.6,1.1,"boarded")
	k.window(Vector3(-hw,1.5,-1.0),L,0.6,1.0,"broken")
	# Rear wing stands roofless behind a ragged parapet.
	k.blk(split,hw,0,h-0.4,zm,z1,plaster,wall)
	for i in 4:
		var x:float=split+0.2+i*0.62
		k.blk(x-0.15,x+0.15,h-0.4,h-0.1+0.25*float(i%2),z1-0.3,z1,plaster,wall)
	for y in [1.5,3.9]:k.window(Vector3(1.9,y,z1),B,0.6,1.0,"boarded" if y<2 else "broken")
	# Exposed interior faces, a hanging stair flight and a floor stub.
	for p in [[1.4,Color("7c6c58")],[4.0,Color("6d7b70")]]:
		k.fbox(Vector3((-hw+split)/2,p[0],zm),B,3.6,2.2,0.03,p[1])
		k.fbox(Vector3(split,p[0],(zm+z1)/2),L,2.0,2.2,0.03,p[1])
	for i in 8:
		var t:=float(i)/8.0
		k.blk(-2.7+t*1.6,-2.45+t*1.6,0.4+t*2.4,0.52+t*2.4,zm,zm+0.65,Color("8a8274"))
	k.blk(-hw,split,2.75,2.9,zm,zm+0.5,Color("6e675a"))
	# Collapsed corner: tilted floor slab, wall stubs, rubble cone and beams.
	var slab:MeshInstance3D=k.blk(-hw+0.2,split-0.2,1.1,1.28,zm+0.3,z1-0.1,Color("6e675a"))
	slab.rotation.x=-0.5
	k.blk(-hw,-hw+0.45,0,1.8,z1-0.45,z1,plaster,wall)
	k.blk(-hw,-hw+0.32,0,2.9,zm,zm+1.0,plaster,wall)
	k.blk(split-0.35,split,0,3.2,z1-0.35,z1,plaster,wall)
	k.rubble(-hw,split,zm,hd,95,1.5,DEBRIS)
	k.rubble(-hw,hw,-hd,z0,16,0.3,DEBRIS)
	for i in 3:
		var x:float=-hw+0.5+i*0.9
		k.tube(Vector3(x,0.25,hd-0.4),Vector3(x+0.3,1.9-0.3*i,zm+0.3),0.06,Color("4d4535"))
	# Rear yard behind the standing wing: bins and gas bottles.
	for x in [1.6,2.0]:k.tube(Vector3(x,0.05,z1+0.45),Vector3(x,0.75,z1+0.45),0.13,Color("707f6e"))
	k.blk(2.4,3.0,0.05,1.0,z1+0.25,z1+0.7,Color("355c46"))
	k.yard_wall(Vector2(split,hd),Vector2(hw,hd),1.1,Color("7d7563"))

# --- Battle damage (events from structure_damage.gd) -------------------------
# Scorch, holes and fallen masonry are instances of one shared box MultiMesh
# (one draw call for every mark on the map). A collapse removes that parcel's
# triangles from its batched city tile (degenerate indices, no new geometry)
# and puts down a low baked rubble mound: one small node per collapse.
const MAX_MARKS:=1536
const MARKS_PER_BUILDING:=14
const SCORCH:=Color("1c1a17")
const HOLE:=Color("0b0b0a")
const CHIP:=Color("6c675c")
const MOUND:=[Color("6f6a5e"),Color("7f786a"),Color("5d574d"),Color("8a8273"),Color("4f4a42")]

static func show_damage(art,root:Node3D,sim,event:Dictionary)->void:
	match str(event.type):
		"building_damage":_mark(root,sim,event)
		"building_collapse":_collapse(art,root,sim,event)
		"world_blast":
			var effects=root.get("effects")
			var pos:=Vector3(event.pos.x,sim.terrain.height_at(event.pos)+0.6,event.pos.y)
			if effects!=null:
				match str(event.kind):
					"collapse":effects.structure_collapse(pos)
					"crash":effects.vehicle_explosion(pos,1.0,sim.terrain.is_water(event.pos),false)
					"mortar":effects.mortar_burst(pos,sim.terrain.is_water(event.pos))
					"cook_off":effects.destroyed("ammo_depot",pos,false)

static func _marks(root:Node3D)->MultiMeshInstance3D:
	var node:=root.get_node_or_null("WorldDamageMarks") as MultiMeshInstance3D
	if node!=null:return node
	var multi:=MultiMesh.new()
	multi.transform_format=MultiMesh.TRANSFORM_3D
	multi.use_colors=true
	var box:=BoxMesh.new();box.size=Vector3.ONE
	multi.mesh=box
	multi.instance_count=MAX_MARKS
	multi.visible_instance_count=0
	node=MultiMeshInstance3D.new()
	node.name="WorldDamageMarks"
	node.multimesh=multi
	var material:=StandardMaterial3D.new()
	material.vertex_color_use_as_albedo=true
	material.roughness=1.0
	node.material_override=material
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.set_meta("by_building",{})
	root.add_child(node)
	return node

static func _add_mark(node:MultiMeshInstance3D,building:int,xf:Transform3D,color:Color)->void:
	var multi:=node.multimesh
	var used:Array=node.get_meta("by_building",{}).get(building,[])
	if used.size()>=MARKS_PER_BUILDING:return
	var slot:int=multi.visible_instance_count
	if slot>=MAX_MARKS:return
	multi.visible_instance_count=slot+1
	multi.set_instance_transform(slot,xf)
	multi.set_instance_color(slot,color)
	used.append(slot)
	var table:Dictionary=node.get_meta("by_building")
	table[building]=used

# One mark per structural hit on the face the round struck: chipped render while
# intact, scorch when damaged, a dark hole and fallen masonry once breached.
static func _mark(root:Node3D,sim,event:Dictionary)->void:
	var building:Dictionary=sim.Garrison.index(sim).buildings[int(event.building)]
	var bounds:Rect2=building.bounds
	var impact:Vector2=event.impact
	var rng:=RandomNumberGenerator.new()
	rng.seed=int(event.building)*7919+int(float(building.damage)*13.0)
	# Outward normal of the face nearest the impact.
	var gaps:=[absf(impact.x-bounds.position.x),absf(bounds.end.x-impact.x),absf(impact.y-bounds.position.y),absf(bounds.end.y-impact.y)]
	var normals:=[Vector3.LEFT,Vector3.RIGHT,Vector3.FORWARD,Vector3.BACK]
	var face:=0
	for k in 4:
		if gaps[k]<gaps[face]:face=k
	var normal:Vector3=normals[face]
	var basis:=Basis.looking_at(-normal,Vector3.UP)
	var height:float=rng.randf_range(0.9,clampf(float(building.height)-1.2,1.0,8.0))
	var spot:=Vector3(impact.x,sim.terrain.height_at(bounds.get_center())+height,impact.y)+normal*0.06+basis.x*rng.randf_range(-0.6,0.6)
	var state:int=int(event.state)
	var node:=_marks(root)
	if state<=0:
		if rng.randf()<0.5:_add_mark(node,event.building,Transform3D(basis*Basis.from_scale(Vector3(0.55,0.45,0.05)),spot),CHIP)
		return
	_add_mark(node,event.building,Transform3D(basis*Basis.from_scale(Vector3(rng.randf_range(1.0,1.6),rng.randf_range(0.8,1.3),0.05)),spot),SCORCH)
	if state>=2:
		_add_mark(node,event.building,Transform3D(basis*Basis.from_scale(Vector3(rng.randf_range(0.7,1.1),rng.randf_range(0.6,0.9),0.1)),spot+normal*0.02),HOLE)
		var foot:=Vector3(impact.x,sim.terrain.height_at(impact)+0.15,impact.y)+normal*rng.randf_range(0.5,1.3)+basis.x*rng.randf_range(-1.0,1.0)
		_add_mark(node,event.building,Transform3D(Basis(Vector3.UP,rng.randf()*TAU)*Basis.from_scale(Vector3(rng.randf_range(0.5,1.0),0.3,rng.randf_range(0.4,0.8))),foot),MOUND[rng.randi()%MOUND.size()])

static func _collapse(art,root:Node3D,sim,event:Dictionary)->void:
	var id:int=int(event.building)
	var building:Dictionary=sim.Garrison.index(sim).buildings[id]
	hide_parcel(root,sim,id)
	var node:=_marks(root)
	for slot in node.get_meta("by_building",{}).get(id,[]):
		node.multimesh.set_instance_transform(slot,Transform3D(Basis.from_scale(Vector3.ONE*0.0001),Vector3(0,-20,0)))
	var mound:=Node3D.new()
	mound.name="Rubble_%d"%id
	mound.position.y=sim.terrain.height_at(building.bounds.get_center())
	root.add_child(mound)
	rubble_mound(art,mound,building.bounds,id,int(building.floors))
	art.bake_model(mound)

# A low collapsed-masonry mound filling the footprint, with a few wall stubs.
static func rubble_mound(art,parent:Node3D,r:Rect2,index:int,floors:int=1)->void:
	var k=Kit.new(art,parent,r,"north",4111+index)
	var hw:float=k.w/2;var hd:float=k.d/2
	var top:float=clampf(0.5+0.35*floors,0.6,2.2)
	# Stepped core: each layer smaller and offset, so the heap slumps unevenly.
	for layer in 3:
		var shrink:float=0.15+layer*0.22
		var ox:float=k.rng.randf_range(-0.12,0.12)*k.w
		var oz:float=k.rng.randf_range(-0.12,0.12)*k.d
		var y0:float=top*layer/3.0
		k.blk(-hw*(1.0-shrink)+ox,hw*(1.0-shrink)+ox,y0-0.05,y0+top/3.0,-hd*(1.0-shrink)+oz,hd*(1.0-shrink)+oz,MOUND[layer%MOUND.size()])
	k.rubble(-hw,hw,-hd,hd,clampi(int(k.w*k.d*0.35),8,40),top,MOUND)
	# Broken wall stubs and a fallen slab at the edges.
	for i in 3:
		var along:float=k.rng.randf_range(-hw*0.7,hw*0.7)
		var z:float=-hd+0.2 if i%2==0 else hd-0.2
		var tall:float=k.rng.randf_range(0.8,1.6)+0.4*mini(floors,3)
		k.blk(along-k.rng.randf_range(0.5,1.2),along+k.rng.randf_range(0.5,1.2),0,tall,z-0.15,z+0.15,MOUND[(i+2)%MOUND.size()])
	var slab:MeshInstance3D=k.blk(-hw*0.5,hw*0.3,top*0.6,top*0.6+0.18,-hd*0.4,hd*0.2,MOUND[3])
	slab.rotation=Vector3(0.18,k.rng.randf_range(-0.5,0.5),-0.12)
	k.finish()

# Drop the parcel's triangles from its batched city tile: a triangle belongs to
# this parcel when its centroid, stepped 0.3 m back along the face normal, lies
# closer to this footprint than to any neighbour's (shared party walls resolve
# to their own side). Only rewritten surfaces are re-uploaded.
const PARCEL_REACH:=1.6
static func hide_parcel(root:Node3D,sim,building_id:int)->int:
	var group:=root.find_child("HarborBuildings",true,false)
	if group==null:return 0
	var buildings:Array=sim.Garrison.index(sim).buildings
	var building:Dictionary=buildings[building_id]
	var spec:Dictionary=building.spec
	if not spec.has("source_size"):return 0
	var me:=_frame(spec)
	var tile:=Vector2i(floori(me.center.x/96.0),floori(me.center.y/96.0))
	var chunk:=group.get_node_or_null("Tile_%d_%d"%[tile.x,tile.y])
	if chunk==null:return 0
	var reach:Rect2=building.bounds.grow(PARCEL_REACH+1.0)
	var neighbours:Array=[]
	for other in buildings:
		if other.id!=building_id and other.spec.has("source_size") and other.bounds.grow(PARCEL_REACH+1.0).intersects(reach):neighbours.append(_frame(other.spec))
	var removed:=0
	for mesh in chunk.get_children():
		if not mesh is MeshInstance3D or mesh.mesh==null:continue
		var arrays:Array=mesh.mesh.surface_get_arrays(0)
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var normals=arrays[Mesh.ARRAY_NORMAL]
		var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		var has_normals:bool=normals!=null and normals.size()==vertices.size()
		var changed:=false
		for t in range(0,indices.size(),3):
			var a:int=indices[t];var b:int=indices[t+1];var c:int=indices[t+2]
			if a==b and b==c:continue
			var centroid:Vector3=(vertices[a]+vertices[b]+vertices[c])/3.0
			if not reach.has_point(Vector2(centroid.x,centroid.z)):continue
			var probe:=Vector2(centroid.x,centroid.z)
			if has_normals:
				var n:Vector3=normals[a]+normals[b]+normals[c]
				var flat:=Vector2(n.x,n.z)
				if flat.length_squared()>0.0001:probe-=flat.normalized()*0.3
			var gap:float=_gap(me,probe)
			if gap>PARCEL_REACH:continue
			var mine:=true
			for other in neighbours:
				if _gap(other,probe)<gap:mine=false;break
			if not mine:continue
			indices[t+1]=a;indices[t+2]=a
			changed=true
			removed+=1
		if not changed:continue
		arrays[Mesh.ARRAY_INDEX]=indices
		var material:Material=mesh.mesh.surface_get_material(0)
		var rebuilt:=ArrayMesh.new()
		rebuilt.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		if material!=null:rebuilt.surface_set_material(0,material)
		mesh.mesh=rebuilt
	return removed

static func _frame(spec:Dictionary)->Dictionary:
	return {"center":Vector2(float(spec.position[0]),float(spec.position[1])),"half":Vector2(float(spec.source_size[0]),float(spec.source_size[1]))*0.5,"inverse":Basis(Vector3.UP,deg_to_rad(float(spec.get("rotation_degrees",0.0)))).inverse()}

# Distance from a point to a rotated footprint (0 inside).
static func _gap(frame:Dictionary,p:Vector2)->float:
	var local:Vector3=frame.inverse*Vector3(p.x-frame.center.x,0.0,p.y-frame.center.y)
	return Vector2(maxf(absf(local.x)-frame.half.x,0.0),maxf(absf(local.z)-frame.half.y,0.0)).length()
