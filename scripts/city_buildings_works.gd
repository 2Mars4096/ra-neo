extends RefCounted
# Original procedural works families. No world transform or collision ownership.
const Kit=preload("res://scripts/parcel_kit.gd")
const Geometry=preload("res://scripts/city_building_geometry.gd")

static func build(art,parent:Node3D,spec:Dictionary)->void:
	var b:=Works.new(art,parent,spec)
	b.construct()
	b.k.finish()

class Works:
	var k
	var w:float
	var d:float
	var floors:int
	var variant:int
	var damage:int
	var design:String
	var wall:Color
	var roof:Color
	var metal:Color
	var wm:Material
	var rm:Material
	func _init(art,parent:Node3D,s:Dictionary)->void:
		w=float(s.source_size[0]);d=float(s.source_size[1])
		floors=int(s.get("floors",1));variant=int(s.get("variant",0));damage=int(s.get("damage",0));design=s.design
		k=Kit.new(art,parent,Rect2(-w/2,-d/2,w,d),"north",int(s.get("seed",0)))
		var palette:int=int(s.get("palette",0))%4
		wall=[Kit.STONE,Kit.CREAM,Kit.OCHRE,Kit.RENDER][palette]
		roof=[Kit.TERRACOTTA,Color("70503c"),Color("885c43"),Color("66564b")][palette]
		metal=[Kit.SHEET,Color("66706b"),Color("666b70"),Color("796a59")][palette]
		wm=k.wallmat(wall);rm=k.roofmat(roof)
	func box(x:float,y:float,z:float,sx:float,sy:float,sz:float,c:Color,mat:Material=null)->void:
		k.blk(x-sx/2,x+sx/2,y,y+sy,z-sz/2,z+sz/2,c,mat)
	func beam(a:Vector3,b:Vector3,radius:float,color:Color)->void:
		var node:MeshInstance3D=k.art.box(k.pivot,(a+b)/2,Vector3(radius*2,a.distance_to(b),radius*2),color)
		var direction:Vector3=(b-a).normalized()
		var axis:=Vector3.UP.cross(direction)
		if axis.length()>0.0001:node.basis=Basis(axis.normalized(),acos(clampf(Vector3.UP.dot(direction),-1,1)))
	func window_at(p:Vector3,n:Vector3,shutters:bool=false)->void:
		var broken:bool=damage>0 and k.rng.randf()<0.45
		k.fbox(p,n,0.91,1.21,0.03,Kit.TRIM)
		k.fbox(p,n,0.75,1.05,0.04,Kit.DARK if broken else Kit.GLASS)
		k.fbox(p+Vector3(0.12 if broken else 0,0.2 if broken else 0,0),n,0.22 if broken else 0.045,0.35 if broken else 1.05,0.055,Kit.GLASS if broken else Kit.TRIM)
		k.fbox(p-Vector3(0,0.6,0),n,1.0,0.08,0.10,Kit.TRIM)
		if shutters:
			var along:=Vector3(-n.z,0,n.x)
			for side in [-1,1]:
				k.fbox(p+along*side*0.55,n,0.26,1.05,0.06,metal)
				k.fbox(p+along*side*0.55,n,0.22,0.045,0.08,metal.darkened(0.2))
	func shell(x0:float,x1:float,z0:float,z1:float,h:float)->void:
		# Hollow, segmented perimeter; ruined sections have uneven surviving heights.
		var thickness:=2.0*float(Geometry.profile(design).get("wall_outset",0.11))
		box((x0+x1)/2,0,(z0+z1)/2,x1-x0,0.16,z1-z0,Kit.CONCRETE)
		for z in [z0,z1]:
			var count:=maxi(1,int((x1-x0)/3.2))
			var step:float=(x1-x0)/count
			for i in count:
				var top:float=h if damage<2 else h*[0.35,0.8,0.5,0.22][(i+variant)%4]
				box(x0+(i+0.5)*step,0,z,step,top,thickness,wall,wm)
		for x in [x0,x1]:
			box(x,0,(z0+z1)/2,thickness,h if damage<2 else h*0.65,z1-z0,wall,wm)
		if damage>0:
			for i in 3:
				box(x1-0.6-i*0.36,0.25,z1+0.125,0.38,h*(0.25+i*0.09),0.025,Color("49483f"))
	func gable(x0:float,x1:float,z0:float,z1:float,h:float,rise:float,tile:bool=false)->void:
		var mat:Material=rm if tile else k.metalmat(metal)
		var count:=maxi(2,int(ceil((x1-x0)/3.0)))
		var step:float=(x1-x0)/count
		var mid:float=(z0+z1)/2
		if damage<2:
			for x in [x0+0.12,x1-0.12]:
				k.prism_x([Vector2(z0,h-0.1),Vector2(z1,h-0.1),Vector2(mid,h+rise)],x-0.08,x+0.08,wm)
		for i in count:
			for side in 2:
				if damage==1 and (i+side+variant)%mini(5,count)==0:continue
				if damage==2:
					if (i+side+variant)%3==0:continue
					var a:float=x0+i*step+0.3;var b:float=a+step-0.6
					var edge:float=lerpf(mid,z0 if side==0 else z1,0.85)
					k.slab([Vector3(a,0.3,edge),Vector3(b,0.3,edge),Vector3(b,0.8+(i%2)*0.4,mid),Vector3(a,0.8,mid)],0.09,mat)
					continue
				var a:float=x0+i*step;var b:float=a+step-0.025
				var z:float=z0 if side==0 else z1
				k.slab([Vector3(a,h,z),Vector3(b,h,z),Vector3(b,h+rise,mid),Vector3(a,h+rise,mid)],0.10,mat)
		# Structural trusses remain exposed through missing roof sheets.
		for i in range(1,count,2):
			var x:float=x0+i*step
			if damage==2 and i%3==0:continue
			var y:float=h if damage<2 else 0.35
			for z in [z0+0.2,z1-0.2]:
				beam(Vector3(x,y,z),Vector3(x,y+rise,mid),0.045,Kit.IRON)
	func flat(x0:float,x1:float,z0:float,z1:float,h:float)->void:
		var count:=maxi(2,int((x1-x0)/3.2))
		for i in count:
			if damage==2 or (damage==1 and i%mini(5,count)==variant%mini(5,count)):continue
			var step:float=(x1-x0)/count
			box(x0+(i+0.5)*step,h,(z0+z1)/2,step-0.025,0.18,z1-z0,Kit.CONCRETE)
	func finish_damage()->void:
		if damage==0:return
		k.rubble(-w*0.4,w*0.4,-d*0.36,d*0.36,18 if damage==2 else 6,0,[wall,Kit.CONCRETE,roof])
		if damage==2:
			for i in 4:
				var x:float=-w*0.25+i*w/6
				k.lean_roof(x-0.55,x+0.55,-0.8,0.7,0.6,0.2,k.metalmat(metal.darkened(0.2)))
	func construct()->void:
		match design:
			"stone_house","outbuilding","dacha_hut":house()
			"garage_row":garages()
			"transit_shed","workshop_hall","barn_long","coop_shed":hall()
			"port_admin","barracks":office()
			"gatehouse":booth()
			"petrol_station":petrol()
			"slipway":slip()
			"fort_ruin":fort()
		finish_damage()
	func house()->void:
		var body:=Geometry.shell_rect(design,Vector2(w,d))
		var x0:float=body.position.x;var x1:float=body.end.x
		var z0:float=body.position.y;var z1:float=body.end.y
		var h:float=floors*2.7
		shell(x0,x1,z0,z1,h)
		if design=="stone_house":
			if damage==0:k.hip_roof(x0-0.15,x1+0.15,z0-0.15,z1+0.15,h,1.25,0,rm)
			else:
				# Individual hip slopes permit genuine missing roof sections.
				var a:=Vector3(x0-0.15,h,z0-0.15);var b:=Vector3(x1+0.15,h,z0-0.15)
				var c:=Vector3(x1+0.15,h,z1+0.15);var e:=Vector3(x0-0.15,h,z1+0.15)
				var r0:=Vector3(x0+1.1,h+1.25,(z0+z1)/2);var r1:=Vector3(x1-1.1,h+1.25,(z0+z1)/2)
				if damage==1:
					k.slab([a,b,r1,r0],0.1,rm);k.slab([c,e,r0,r1],0.1,rm)
					k.solid([[e,a,r0],[e-Vector3(0,0.1,0),a,r0]],rm)
		elif design=="outbuilding":
			if damage<2:
				var count:=maxi(2,int(w))
				for i in count:
					if damage==1 and i==variant%count:continue
					k.lean_roof(x0+i*(x1-x0)/count,x0+(i+1)*(x1-x0)/count,z1+0.15,z0-0.15,h+0.65,h,k.metalmat(metal))
		else:
			gable(x0-0.15,x1+0.15,z0-0.15,z1+0.15,h,1.35,true)
			if damage<2:window_at(Vector3(x1+0.12,h+0.35,(z0+z1)/2),Vector3.RIGHT)
		if damage<2:
			for f in floors:
				for z in [z0-0.12,z1+0.12]:
					for i in maxi(1,int((x1-x0)/2.6)):
						var x:float=x0+1.0+i*2.6
						window_at(Vector3(x,f*2.7+1.45,z),Vector3(0,0,-1 if z<0 else 1),design=="stone_house")
				window_at(Vector3(x1+0.12,f*2.7+1.45,(z0+z1)/2),Vector3.RIGHT,design=="stone_house")
			k.door(Vector3(x1-0.65,0.06,z0-0.13),Vector3.FORWARD,0.8,2.0,Kit.TIMBER,false)
			var porch:=Geometry.porch_rect(design,Vector2(w,d))
			var details:Dictionary=Geometry.profile(design).porch
			box(porch.get_center().x,0,porch.get_center().y,porch.size.x,float(details.height),porch.size.y,Kit.CONCRETE)
			for side in [-1,1]:box(side*float(details.post_side),float(details.height),z0-float(details.post_front_offset),float(details.post_size),float(details.post_height),float(details.post_size),Kit.TIMBER)
			k.lean_roof(-1.1,1.1,z0,z0-1.1,2.65,2.4,k.metalmat(metal))
			k.chimney(x0+0.65,z1-0.65,h,h+1.7,Kit.BRICK,1)
			# Visible plinth and occasional exposed limestone patches.
			box(0,0.15,z1+0.13,x1-x0,0.3,0.05,wall.darkened(0.22))
			if variant%2==0:
				for i in 4:box(x0+0.4+i*0.5,0.55+(i%2)*0.2,z1+0.14,0.43,0.18,0.04,Kit.STONE)
	func garages()->void:
		var count:=maxi(1,int(round(w/3.2)));var step:float=(w-0.4)/count
		var z0:float=-d/2+0.4;var z1:float=d/2-0.35
		box(0,0,0,w-0.5,0.12,d-0.7,Kit.CONCRETE)
		box(0,0,z1,w-0.5,2.65,0.2,wall,wm)
		for i in count:
			var x:float=-w/2+0.2+(i+0.5)*step
			var h:float=2.6 if damage<2 else 1.1+(i%3)*0.45
			box(x-step/2+0.1,0,(z0+z1)/2,0.2,h,z1-z0,wall,wm)
			if damage==2:continue
			var color:Color=[metal,Color("596762"),Color("66524a"),Color("596775")][(i+variant)%4]
			box(x,0.1,z0,step-0.25,2.25,0.08,Kit.DARK)
			var open:bool=(i+variant)%5==0
			box(x,1.7 if open else 0.12,z0-0.06,step-0.32,0.65 if open else 2.2,0.08,color)
			if not open:
				box(x,0.12,z0-0.12,0.045,2.2,0.04,Kit.IRON)
				box(x+0.15,1.1,z0-0.15,0.16,0.07,0.03,Kit.TRIM)
			if (i+variant)%3==0:box(x-0.6,0.2,z0-0.13,0.6,0.35,0.02,Color("72503a"))
			if damage==0 or i%4!=variant:
				box(x,2.65,(z0+z1)/2,step-0.02,0.19,z1-z0+0.25,Kit.CONCRETE)
				if (i+variant)%4==1:box(x,2.845,0,step-0.3,0.025,2.4,Kit.SHEET)
			box(x-step/2+0.1,0,z1+0.12,0.17,2.6,0.12,wall.darkened(0.22))
			box(x,2.05,z1+0.13,0.7,0.22,0.04,Kit.DARK)
		box(w/2-0.3,0,(z0+z1)/2,0.2,2.65 if damage<2 else 1.4,z1-z0,wall,wm)
	func hall()->void:
		if design=="barn_long":
			wall=Kit.BRICK;wm=k.wallmat(wall)
		elif design=="coop_shed":
			wall=metal;wm=k.metalmat(wall)
		var port:bool=design in ["transit_shed","workshop_hall"]
		var workshop:bool=design=="workshop_hall"
		var h:float=7.5 if port else 3.6
		var rise:float=(1.65+0.1*variant) if port else (1.2+0.1*variant)
		var body:=Geometry.shell_rect(design,Vector2(w,d))
		var x0:float=body.position.x;var x1:float=body.end.x
		var z0:float=body.position.y;var z1:float=body.end.y
		shell(x0,x1,z0,z1,h)
		gable(x0-0.2,x1+0.2,z0-0.2,z1+0.2,h,rise)
		var bays:=maxi(2,int((w-1)/5.5));var step:float=(x1-x0)/bays
		var dock_details:Dictionary=Geometry.profile(design).dock
		for dock in Geometry.dock_rects(design,Vector2(w,d)):
			box(dock.get_center().x,float(dock_details.base),dock.get_center().y,dock.size.x,float(dock_details.height),dock.size.y,Kit.CONCRETE)
		for z in [z0-0.15,z1+0.15]:
			var n:=Vector3(0,0,-1 if z<0 else 1)
			for i in bays:
				var x:float=x0+(i+0.5)*step
				if damage==2:continue
				if design=="barn_long" and i%2==0:
					k.fbox(Vector3(x,2.4,z),n,1.2,0.55,0.08,Kit.DARK)
					continue
				var dh:float=5.2 if workshop else (3.4 if port else 2.7)
				k.fbox(Vector3(x,dh/2+0.5,z),n,3.4,dh,0.06,Kit.DARK)
				k.fbox(Vector3(x,dh/2+0.65,z),n,3.1,dh-0.4,0.09,Kit.TIMBER if design=="barn_long" else metal)
				for j in 4:k.fbox(Vector3(x,0.9+j*(dh-0.5)/4,z),n,3.1,0.035,0.12,metal.darkened(0.3))
				box(x-step/2+0.12,0.45,z,0.2,h-0.45,0.3,wall.darkened(0.18))
				if design=="coop_shed":
					for dx in [-2.1,2.1]:k.fbox(Vector3(x+dx,h/2,z),n,0.05,h-0.4,0.13,metal.lightened(0.12))
				if port: k.fbox(Vector3(x,h-0.85,z),n,2.6,0.65,0.08,Kit.DARK if damage>0 and i%3==0 else Kit.GLASS)
		if workshop and damage<2:
			box(0,h+1.3,0,w-3,0.9,2.6,wall,wm)
			for z in [-1.32,1.32]:box(0,h+1.5,z,w-4,0.5,0.06,Kit.GLASS)
			flat(-w/2+1.3,w/2-1.3,-1.5,1.5,h+2.25)
		if damage<2:
			for z in [-d*0.22,0,d*0.22]:window_at(Vector3(x1+0.13,h-1.3,z),Vector3.RIGHT)
	func office()->void:
		var body:=Geometry.shell_rect(design,Vector2(w,d))
		var x0:float=body.position.x;var x1:float=body.end.x;var z0:float=body.position.y;var z1:float=body.end.y
		var h:float=floors*2.7
		shell(x0,x1,z0,z1,h)
		if design=="barracks":gable(x0-0.15,x1+0.15,z0-0.15,z1+0.15,h,1.3,true)
		else:flat(x0-0.15,x1+0.15,z0-0.15,z1+0.15,h)
		if damage==2:return
		var count:=int((w-2)/3.05)
		for f in floors:
			for z in [z0-0.12,z1+0.12]:
				for i in count:window_at(Vector3(x0+1.3+i*(w-3)/count,1.45+f*2.7,z),Vector3(0,0,-1 if z<0 else 1))
			for z in [-d*0.25,0,d*0.25]:window_at(Vector3(x1+0.12,1.45+f*2.7,z),Vector3.RIGHT)
			box(0,f*2.7+0.1,z1+0.14,w-0.8,0.12,0.07,Kit.TRIM)
		k.door(Vector3(0,0.06,z0-0.12),Vector3.FORWARD,1.5,2.1,Kit.TIMBER)
		box(0,2.3,z0-0.25,2.5,0.12,0.65,Kit.CONCRETE)
		if design=="port_admin":
			for x in [-3.0,0.0,3.0]:box(x,h,z1-0.65,0.09,1.6,0.09,Kit.IRON)
			for y in [h+0.6,h+1.6]:box(0,y,z1-0.65,6.2,0.08,0.08,Kit.IRON)
			for i in 5:box(-2.4+i*1.2,h+0.8,z1-0.64,0.65,0.65,0.08,metal)
	func booth()->void:
		var body:=Geometry.shell_rect(design,Vector2(w,d))
		var x0:float=body.position.x;var x1:float=body.end.x;var z0:float=body.position.y;var z1:float=body.end.y
		shell(x0,x1,z0,z1,2.7);flat(x0-0.2,x1+0.2,z0-0.2,z1+0.2,2.75)
		if damage<2:
			for z in [z0-0.12,z1+0.12]:window_at(Vector3(0,1.6,z),Vector3(0,0,-1 if z<0 else 1))
			window_at(Vector3(x1+0.12,1.6,0),Vector3.RIGHT)
			k.door(Vector3(x0-0.12,0.06,0),Vector3.LEFT,0.8,2,metal,false)
	func petrol()->void:
		var z:float=d/2-2.0
		shell(-w/2+0.5,-w*0.05,z-1.3,z+1.3,2.6)
		flat(-w/2+0.3,-w*0.05+0.2,z-1.5,z+1.5,2.65)
		if damage<2:
			for side in [-1.0,1.0]:
				for i in 2:window_at(Vector3(-w/2+1.5+i*2.0,1.45,z+side*1.42),Vector3(0,0,side))
			window_at(Vector3(-w*0.05+0.12,1.45,z),Vector3.RIGHT)
		var front:float=-d/2+2.2
		for x in [-w*0.3,0,w*0.3]:
			box(x,0,front,0.18,3.8 if damage<2 else 1.8,0.18,Kit.CONCRETE)
			box(x,0.1,front-0.55,1.6,0.16,0.8,Kit.CONCRETE)
			box(x,0.26,front-0.55,0.55,1.05,0.5,metal)
			box(x,0.95,front-0.82,0.4,0.23,0.04,Kit.DARK)
			box(x+0.4,0.5,front-0.55,0.06,0.7,0.08,Kit.IRON)
		flat(-w/2+0.35,w/2-0.35,front-1.8,front+1.5,3.9)
		if damage<2:box(0,3.85,front-1.8,w-0.7,0.35,0.1,Color("7e4438"))
	func slip()->void:
		var x0:float=-w/2+0.5;var x1:float=w/2-0.5
		k.prism_x([Vector2(-d/2+0.4,0.1),Vector2(d/2-0.4,0.1),Vector2(d/2-0.4,0.25),Vector2(-d/2+0.4,1.35)],x0,x1,k.wallmat(Kit.CONCRETE))
		# Parallel slip lanes repeat across the frontage; all descend waterward.
		var lanes:=maxi(2,int(w/10))
		for i in lanes:
			var x:float=-w/2+(i+0.5)*w/lanes
			for dx in [-1.0,1.0]:beam(Vector3(x+dx,1.42,-d/2+0.6),Vector3(x+dx,0.32,d/2-0.6),0.055,Kit.IRON)
			for j in 4:box(x,0.6+j*0.15,d*0.3-j*d*0.19,2.5,0.12,0.16,Kit.TIMBER)
		var cx:float=-w/2+(variant%lanes+0.5)*w/lanes
		for z in [-1.4,1.4]:box(cx,0.9,z,3.1,0.4,0.3,Kit.IRON)
		if damage==2:return
		# Small open workboat hull, bow pointing to +z, on a steel cradle.
		var ring:=[Vector3(cx-1.15,2.5,-2.4),Vector3(cx+1.15,2.5,-2.4),Vector3(cx+1.3,2.5,1.4),Vector3(cx,2.5,3.1),Vector3(cx-1.3,2.5,1.4)]
		for i in ring.size():
			var a:Vector3=ring[i];var b:Vector3=ring[(i+1)%ring.size()]
			var aa:=Vector3(cx+(a.x-cx)*0.45,1.3,a.z*0.8);var bb:=Vector3(cx+(b.x-cx)*0.45,1.3,b.z*0.8)
			k.slab([a,b,bb,aa],0.08,k.metalmat(metal))
		box(cx,1.35,0,1,0.12,3.8,Kit.TIMBER)
		if damage==0:box(cx,2.3,-0.8,1.45,0.14,0.35,Kit.TIMBER)
	func fort()->void:
		var radius:float=minf(w,d)*0.41
		var n:=18
		for i in n:
			if i in [3+variant,4+variant] or (damage>0 and i%5==variant):continue
			var a:float=TAU*i/n;var b:float=TAU*(i+1)/n
			var h:float=1.4+(i%3)*0.35
			if damage==2:h*=0.6
			var p:=Vector3(cos(a)*radius,0,sin(a)*radius);var q:=Vector3(cos(b)*radius,0,sin(b)*radius)
			var r:=Vector3(cos(b)*(radius-1.2),0,sin(b)*(radius-1.2));var s:=Vector3(cos(a)*(radius-1.2),0,sin(a)*(radius-1.2))
			k.slab([p+Vector3.UP*h,q+Vector3.UP*h,r+Vector3.UP*h,s+Vector3.UP*h],h,wm)
			box(p.x,0,p.z,0.55,h+0.25,0.55,Kit.STONE)
		for x in [-radius*0.4,radius*0.4]:
			for i in 10:
				var a:float=TAU*i/10;var b:float=TAU*(i+1)/10
				beam(Vector3(x+cos(a)*2.3,0.5,sin(a)*2.3),Vector3(x+cos(b)*2.3,0.5,sin(b)*2.3),0.32,wall)
			box(x,0.05,0,2.7,0.12,2.7,Kit.DARK)
		for i in 12:
			var a:float=i*2.399;var r:float=radius*(0.55+0.2*(i%3)/2.0)
			box(cos(a)*r,0.03,sin(a)*r,1.0,0.16,0.8,Color("515c3a"))
		for i in 4:
			var a:float=i*1.8+variant*0.2
			k.plant(Vector3(cos(a)*radius*0.7,0.5,sin(a)*radius*0.7),0.4,77+i,Color("515c3a"))
		k.rubble(-radius*0.8,radius*0.8,-radius*0.8,radius*0.8,22,0,[wall,Kit.STONE])
