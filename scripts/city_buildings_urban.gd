extends RefCounted
# Local, width-driven architecture. No placement, collision or runtime state.
const Kit = preload("res://scripts/parcel_kit.gd")

static func build(art, parent:Node3D, spec:Dictionary)->void:
	var b = Builder.new(art,parent,spec)
	b.construct()
	b.k.finish()

class Builder:
	var k
	var w:float
	var d:float
	var h:float
	var floors:int
	var variant:int
	var damage:int
	var design:String
	var wall:Color
	var roof:Color
	var trim:=Kit.TRIM
	var soviet:bool
	func _init(art,parent:Node3D,s:Dictionary)->void:
		w=float(s.source_size[0]);d=float(s.source_size[1])
		floors=int(s.floors);h=floors*2.7
		variant=int(s.variant)%4;damage=int(s.damage);design=str(s.design)
		soviet=design in ["panel_5","panel_9","point_tower","school","kindergarten","shop_pavilion"]
		var colors:Array=[Color("c7c0a8"),Color("b8aa87"),Kit.OCHRE,Color("d1ccb9")]
		if soviet:colors=[Kit.CONCRETE,Color("aa9675"),Color("999c92"),Color("b0aca0")]
		wall=colors[int(s.palette)%4]
		roof=[Kit.TERRACOTTA,Kit.SLATE,Color("79604e"),Kit.SHEET][variant]
		k=Kit.new(art,parent,Rect2(-w/2,-d/2,w,d),"north",int(s.seed))
	func box(x0:float,x1:float,y0:float,y1:float,z0:float,z1:float,c:Color)->void:
		k.blk(x0,x1,y0,y1,z0,z1,c)
	# Thin facade quads avoid dozens of hidden triangles per repeated window.
	func face(p:Vector3,n:Vector3,ww:float,hh:float,c:Color,offset:float=0.02)->void:
		var u:=Vector3(n.z,0,-n.x)*ww/2
		var v:=Vector3.UP*hh/2
		p+=n*offset
		k.solid([[p-u-v,p+u-v,p+u+v,p-u+v]],k.paint(c))
	func window(p:Vector3,n:Vector3,ww:float,hh:float,key:int)->void:
		face(p,n,ww+0.20,hh+0.18,trim)
		var broken:=damage>0 and (key+variant)%4==0
		face(p,n,ww,hh,Kit.DARK if broken else Kit.GLASS,0.035)
		if broken:face(p+Vector3(0,hh*0.2,0),n,ww*0.4,hh*0.25,Kit.GLASS,0.05)
		else:face(p,n,0.065,hh,trim,0.05)
	func facade(a:Vector3,b:Vector3,n:Vector3,height:float,classic:bool)->void:
		var length:=a.distance_to(b)
		var bays:=maxi(1,int(length/(2.7+variant*0.17)))
		var step:=length/bays
		var levels:=maxi(1,int(round(height/2.7)))
		if design=="market_hall":levels=1
		for j in levels:
			for i in bays:
				if damage==2 and j==levels-1:continue
				var p:=a.lerp(b,(i+0.5)/bays)+Vector3.UP*(height-1.0 if design=="market_hall" else j*2.7+1.55)
				window(p,n,step*0.82 if design=="school" else minf(1.15 if classic else 1.65,step*0.65),1.55 if classic else 1.25,i+j*7)
				if damage>0 and (i+j*3+variant)%11==0:
					face(p+Vector3.UP*0.7,n,1.7,0.4,Color("504b40"),0.018)
		if classic:
			for i in range(1,bays,2):
				var ph:=maxf(0.3,height-(3.0 if damage==2 else 0.3))
				var p:=a.lerp(b,float(i)/bays)+Vector3.UP*ph/2
				k.fbox(p,n,0.22,ph,0.14,trim)
			for y in [0.5,1.0,1.5,2.1,2.65]:face(a.lerp(b,0.5)+Vector3.UP*y,n,length,0.045,wall.darkened(0.18))
		else:
			for j in range(1,levels):face(a.lerp(b,0.5)+Vector3.UP*(j*2.7),n,length,0.045,wall.darkened(0.25))
			var joint_height:=maxf(0.1,height-(3.0 if damage==2 else 0.0))
			for i in range(1,bays):face(a.lerp(b,float(i)/bays)+Vector3.UP*joint_height/2,n,0.035,maxf(0.1,joint_height),wall.darkened(0.22))
	# Rectangular hollow shell; broken top follows bay-sized masonry remnants.
	func mass(x0:float,x1:float,z0:float,z1:float,height:float,classic:bool=true,pitched:bool=true)->void:
		box(x0,x1,0,0.18,z0,z1,wall.darkened(0.3))
		for edge in [[Vector3(x0,0,z0),Vector3(x1,0,z0),Vector3.FORWARD],[Vector3(x1,0,z1),Vector3(x0,0,z1),Vector3.BACK],[Vector3(x1,0,z0),Vector3(x1,0,z1),Vector3.RIGHT],[Vector3(x0,0,z1),Vector3(x0,0,z0),Vector3.LEFT]]:
			var a:Vector3=edge[0];var b:Vector3=edge[1];var n:Vector3=edge[2]
			var count:=maxi(1,int(a.distance_to(b)/2.5))
			for i in count:
				var aa:=a.lerp(b,float(i)/count);var bb:=a.lerp(b,float(i+1)/count)
				var top:=height
				if damage==2:top=height-k.rng.randf_range(0.7,minf(3.0,height-0.5))
				var center:Vector3=(aa+bb)/2-n*0.16+Vector3.UP*top/2
				k.fbox(center,-n,aa.distance_to(bb)+0.01,top,0.30,wall,k.wallmat(wall))
			facade(a,b,n,height,classic)
			if damage<2:
				for i in count:
					if damage==1 and i%4==1:continue
					k.fbox(a.lerp(b,(i+0.5)/count)+Vector3.UP*(height-0.12),n,a.distance_to(b)/count,0.24,0.23,trim)
		if damage==2:
			k.rubble(x0+0.5,x1-0.5,z0+0.5,z1-0.5,18,height,[wall,Kit.STONE,roof])
			return
		if pitched:
			if damage==0 and design in ["classic_row","stalin_block"]:return # One continuous roof spans the courtyard gateway.
			if damage==0:k.hip_roof(x0-0.22,x1+0.22,z0-0.22,z1+0.22,height,1.1+variant*0.22,0,k.roofmat(roof))
			else:
				# Separate roof strips leave actual holes over the open shell.
				var strips:=maxi(4,int((x1-x0)/2))
				for i in strips:
					if i%4==1 or k.rng.randf()<0.14:continue
					var a:=lerpf(x0,x1,float(i)/strips);var b:=lerpf(x0,x1,float(i+1)/strips)
					k.gable_roof(a,b,z0,z1,height,1.2,"x",0,k.roofmat(roof))
		else:
			if damage==0:box(x0,x1,height-0.08,height,z0,z1,Kit.SLATE)
			else:
				box(x0,x0+(x1-x0)*0.35,height-0.08,height,z0,z1,Kit.SLATE)
				box(x0+(x1-x0)*0.6,x1,height-0.08,height,z0,z1,Kit.SLATE)
			for e in [[x0,x1,z0,z0+0.16],[x0,x1,z1-0.16,z1],[x0,x0+0.16,z0,z1],[x1-0.16,x1,z0,z1]]:
				box(e[0],e[1],height,height+0.38,e[2],e[3],wall)
	func arch(x:float,z:float,width:float,height:float,depth:float)->void:
		# Real opening: voussoir ring, with no solid infill behind it.
		var radius:=width/2
		for side in [-1,1]:box(x+side*radius-0.17,x+side*radius+0.17,0,height-radius,z,z+depth,trim)
		for i in 6:
			var a:=PI*i/6;var b:=PI*(i+1)/6
			k.prism_z([Vector2(x+cos(a)*radius,height-radius+sin(a)*radius),Vector2(x+cos(b)*radius,height-radius+sin(b)*radius),Vector2(x+cos(b)*(radius+0.32),height-radius+sin(b)*(radius+0.32)),Vector2(x+cos(a)*(radius+0.32),height-radius+sin(a)*(radius+0.32))],z,z+depth,k.paint(trim))
	func balcony(x:float,z:float,y:float,width:float,balusters:bool=false)->void:
		box(x-width/2,x+width/2,y,y+0.12,z,z+0.8,trim)
		box(x-width/2,x+width/2,y+0.85,y+0.94,z+0.68,z+0.8,trim)
		var glazed:=not balusters and int(absf(x)*3+y+variant)%4==0
		if glazed:
			box(x-width/2,x+width/2,y+0.12,y+1.9,z+0.68,z+0.78,wall)
			face(Vector3(x,y+1.35,z+0.79),Vector3.BACK,width-0.18,0.85,Kit.GLASS)
		elif balusters:
			for i in 5:box(x-width/2+0.1+i*(width-0.2)/4,x-width/2+0.18+i*(width-0.2)/4,y+0.12,y+0.85,z+0.7,z+0.78,trim)
		else:box(x-width/2,x+width/2,y+0.12,y+0.82,z+0.68,z+0.78,wall.lightened(0.1))
	func entrance(x:float,z:float)->void:
		k.door(Vector3(x,0.06,z),Vector3.FORWARD,1.1,2.1,Kit.DARK)
		box(x-1,x+1,2.25,2.4,z-0.75,z+0.1,trim)
	func construct()->void:
		var x0:=-w/2+0.6;var x1:=w/2-0.6;var z0:=-d/2+1.0;var z1:=d/2-1.2
		match design:
			"classic_row","stalin_block":
				# Perimeter-block rows fill their plot so neighbours meet at a party wall,
				# and a street-parallel gable makes adjoining rows read as one roofline.
				# Only some rows carry the courtyard gateway arch.
				x0=-w/2+0.3;x1=w/2-0.3;z0=-d/2+0.4;z1=d/2-1.0 # Roof eaves and rear balconies stay in the plot.
				var gateway:=design=="stalin_block" or variant==0
				var gap:=2.2 if design=="classic_row" else 3.6
				var rise:=1.1+variant*0.22
				if gateway:
					mass(x0,-gap/2,z0,z1,h)
					mass(gap/2,x1,z0,z1,h)
					if damage<2:
						box(-gap/2,gap/2,3.0,h,z0,z1,wall)
				else:mass(x0,x1,z0,z1,h)
				if damage==0:
					k.gable_roof(x0,x1,z0,z1,h+0.03,rise,"x",0.12,k.roofmat(roof))
					var zc:=(z0+z1)/2
					for xe in [x0,x1]:
						k.solid([[Vector3(xe,h,z0),Vector3(xe,h,z1),Vector3(xe,h+rise,zc),Vector3(xe,h+rise,zc)],[Vector3(xe,h,z1),Vector3(xe,h,z0),Vector3(xe,h+rise,zc),Vector3(xe,h+rise,zc)]],k.paint(wall))
				elif damage==1 and gateway:k.hip_roof(-gap/2,gap/2,z0-0.22,z1+0.22,h,rise,0,k.roofmat(roof))
				if damage<2 and gateway:
					for z in [z0,z1]:
						var normal:=Vector3.FORWARD if z==z0 else Vector3.BACK
						for j in range(1,floors):window(Vector3(0,j*2.7+1.55,z),normal,1.15,1.55,j)
				if gateway:
					for z in [z0-0.12,z1-0.2]:arch(0,z,gap,2.9,0.3)
				for x in [-w*0.3,w*0.3]:
					if damage<2:balcony(x,z1,3.0,2.0, true)
				if variant%2==0:
					for i in maxi(2,int(w/4)):
						var x:=lerpf(x0+1.2,x1-1.2,float(i)/maxf(1,int(w/4)-1))
						if absf(x)<gap/2+1:continue
						for z in [z0-0.15,z1+0.05]:arch(x,z,1.5,2.4,0.15)
			"classic_corner":
				var wing:=minf(w,d)*0.39
				mass(x0,x1,z0,z0+wing,h)
				mass(x0,x0+wing,z0+wing+0.05,z1,h)
				if damage<2:balcony(x1-2,z0+wing,3,2,true)
				chamfer_corner(x0,z0,1.6)
			"panel_5","panel_9","point_tower":
				mass(x0,x1,z0,z1,h,false,false)
				var bays:=maxi(2,int(w/3.6))
				for i in bays:
					var x:=lerpf(x0+1.3,x1-1.3,float(i)/maxi(1,bays-1))
					if i%3==0:entrance(x,z0)
					if i%3==1:continue
					for j in range(1,floors-(1 if damage==2 else 0)):balcony(x,z1,j*2.7,1.8)
				if design!="panel_5" and damage<2:
					for i in maxi(1,int(w/18)):
						var x:=x0+3+i*16
						box(x-1.5,x+1.5,h,h+1.3+variant*0.15,-1,1+variant*0.3,wall.darkened(0.1))
			"school","kindergarten":
				var wing:=w*0.23
				var low:=h if design=="school" else h-0.5
				mass(x0,x0+wing,z0,z1,low,false,false)
				mass(x1-wing,x1,z0,z1,low,false,false)
				var cross_z:=z0 if variant%2==0 else -2.5
				mass(x0+wing+0.05,x1-wing-0.05,cross_z,cross_z+5,low,false,false)
				entrance(0,cross_z)
				if design=="kindergarten" and damage<2:
					for x in [x0+wing+0.4,x1-wing-2.3]:
						box(x,x+1.9,2.2,2.35,3,z1,roof)
						for z in [3.0,z1-0.1]:box(x+0.1,x+0.23,0,2.2,z,z+0.1,trim)
			"shop_pavilion":
				mass(x0,x1,z0,z1,h,false,false)
				for z in [z0,z1]:
					var normal:=Vector3.FORWARD if z==z0 else Vector3.BACK
					for i in maxi(3,int(w/3)):
						window(Vector3(lerpf(x0+1.3,x1-1.3,(i+0.5)/maxi(3,int(w/3))),1.4,z),normal,2,1.9,i)
					k.fbox(Vector3(0,2.5,z),normal,w-2,0.38,0.22,roof)
				entrance(0,z0)
			"market_hall":
				mass(x0,x1,z0+2,z1-2,5.4,false)
				if damage<2:mass(x0+2,x1-2,-1.2,1.2,7.2,false)
				for side in [-1,1]:
					var z:=z0 if side<0 else z1-1.5
					for i in maxi(4,int(w/4)):
						var x:=lerpf(x0+1,x1-2,float(i)/maxi(1,int(w/4)-1))
						box(x,x+1.4,0,0.8,z,z+1.4,wall)
						if damage<2:box(x-0.1,x+1.5,2.3,2.45,z,z+1.5,roof if i%2 else trim)
			"civic_hall":
				mass(x0,x1,z0+4,z1-3.7,h)
				portico(-w*0.28,w*0.28,z0+0.8,z0+4,h-0.6)
				if damage<2:k.prism_z([Vector2(-w*0.3,h),Vector2(w*0.3,h),Vector2(0,h+2)],z0+0.5,z0+4,k.wallmat(trim))
				steps(-w*0.3,w*0.3,z0-0.6,z0+0.8,false)
				portico(-w*0.28,w*0.28,z1-3.3,z1-0.8,h-0.6)
				steps(-w*0.3,w*0.3,z1-0.4,d/2-0.1,true)
				if damage<2:k.prism_z([Vector2(-w*0.3,h),Vector2(w*0.3,h),Vector2(0,h+2)],z1-3.5,z1-0.5,k.wallmat(trim))
			"colonnade_landing":
				portico(x0,x1,z0+0.1,z0+2.7,6.3)
				steps(x0,x1,z0+2.9,d/2-0.1,true)
				if damage<2:arch(0,z0+2.6,2.6,6.1,0.3)
			"cathedral":cathedral(x0,x1,z0,z1)
	func steps(a:float,b:float,z0:float,z1:float,descending:bool)->void:
		for i in 5:
			var z:=lerpf(z0,z1,float(i)/5)
			box(a,b,0,0.12*(5-i if descending else i+1),z,lerpf(z0,z1,float(i+1)/5),trim)
	func portico(a:float,b:float,z0:float,z1:float,height:float)->void:
		var count:=maxi(4,int((b-a)/3))
		if count%2==1:count+=1
		for z in [z0,z1]:
			for i in count:
				var x:=lerpf(a+0.4,b-0.4,float(i)/(count-1))
				var top:=height if damage<2 else height*(0.45+0.4*float(i%3)/2)
				k.tube(Vector3(x,0.3,z),Vector3(x,top,z),0.23,trim)
				box(x-0.37,x+0.37,0,0.3,z-0.37,z+0.37,trim)
				box(x-0.37,x+0.37,top-0.15,top,z-0.37,z+0.37,trim)
		if damage<2:
			if damage==0:
				box(a,b,height,height+0.45,z0-0.4,z1+0.4,trim)
				box(a,b,height+0.45,height+0.6,z0-0.4,z1+0.4,roof)
			else:
				for i in count-1:
					if i==count/2:continue
					var left:=lerpf(a,b,float(i)/(count-1));var right:=lerpf(a,b,float(i+1)/(count-1))
					box(left,right,height,height+0.4,z0-0.4,z1+0.4,trim)
					box(left,right,height+0.4,height+0.6,z0-0.4,z1+0.4,roof)
		else:k.rubble(a+0.5,b-0.5,z0,z1,12,height,[wall,trim])
	func cathedral(_x0:float,_x1:float,z0:float,z1:float)->void:
		# Narrow nave and short transepts support a square crossing and tall drum.
		# Landmark heights are independent of the residential storey count.
		wall=wall.lerp(Color("e4dfcc"),0.72)
		roof=Color("536e62")
		var half:=w*0.175
		var crossing:=1.0
		var apse_z:=z1-3.0
		church_shell(-half,half,z0+4.8,apse_z,7.2)
		church_shell(-w*0.39,w*0.39,-1.7,3.7,7.8)
		church_shell(-half-0.35,half+0.35,crossing-half-0.35,crossing+half+0.35,10.6)
		# Faceted semicircular sanctuary projects toward +z, visible to the camera.
		var radius:=minf(half,2.8)
		for i in 6:
			var a:=PI*i/6;var b:=PI*(i+1)/6
			var p:=Vector3(cos(a)*radius,0,apse_z+sin(a)*radius)
			var q:=Vector3(cos(b)*radius,0,apse_z+sin(b)*radius)
			var n:=Vector3(cos((a+b)/2),0,sin((a+b)/2))
			var top:float=6.6 if damage<2 else 4.0+k.rng.randf()*1.4
			wall_segment(p,q,n,0,top)
			if damage<2 or i%2==0:arched_window((p+q)/2+Vector3.UP*1.8,n,0.8,1.8 if damage==2 else 3.0,i)
			if damage<2 and not (damage==1 and i==2):
				k.solid([[Vector3(p.x,6.6,p.z),Vector3(q.x,6.6,q.z),Vector3(0,8.3,apse_z)]],k.roofmat(roof))
		# Street-side bell tower: open belfry above the masonry shaft.
		var bell_z:=z0+2.4
		church_shell(-2.1,2.1,bell_z-2.1,bell_z+2.1,11.2)
		if damage==2:return
		for x in [-1.65,1.65]:
			for z in [bell_z-1.65,bell_z+1.65]:box(x-0.3,x+0.3,11.2,15.6,z-0.3,z+0.3,wall)
		box(-2.15,2.15,15.5,16.0,bell_z-2.15,bell_z+2.15,trim)
		# A suspended bell reads through the open belfry.
		k.tube(Vector3(0,13.5,bell_z),Vector3(0,14.3,bell_z),0.55,Kit.IRON)
		dome(Vector3(0,16.0,bell_z),2.25,4.1)
		church_cross(Vector3(0,20.1,bell_z),1.5)
		var drum_radius:=half*0.77
		for i in 10:
			var a:=TAU*i/10;var b:=TAU*(i+1)/10
			var p:=Vector3(cos(a)*drum_radius,0,crossing+sin(a)*drum_radius)
			var q:=Vector3(cos(b)*drum_radius,0,crossing+sin(b)*drum_radius)
			var n:=Vector3(cos((a+b)/2),0,sin((a+b)/2))
			wall_segment(p,q,n,10.6,15.2)
			arched_window((p+q)/2+Vector3.UP*11.1,n,0.8,3.2,i)
		dome(Vector3(0,15.2,crossing),drum_radius*1.25,4.7)
		church_cross(Vector3(0,19.9,crossing),1.5)
		if variant>=2:
			for x in [-half,half]:
				for z in [crossing+half]:
					k.tube(Vector3(x,10.6,z),Vector3(x,11.6,z),0.65,wall,k.wallmat(wall))
					dome(Vector3(x,11.6,z),0.9,1.7)
					church_cross(Vector3(x,13.3,z),0.65)
	func church_cross(p:Vector3,height:float)->void:
		box(p.x-0.07,p.x+0.07,p.y,p.y+height,p.z-0.07,p.z+0.07,trim)
		box(p.x-height*0.28,p.x+height*0.28,p.y+height*0.68,p.y+height*0.68+0.12,p.z-0.07,p.z+0.07,trim)
		box(p.x-height*0.15,p.x+height*0.15,p.y+height*0.87,p.y+height*0.87+0.08,p.z-0.06,p.z+0.06,trim)
	func wall_segment(p:Vector3,q:Vector3,n:Vector3,bottom:float,top:float)->void:
		var a:=p+Vector3.UP*bottom;var b:=q+Vector3.UP*bottom
		var c:=q+Vector3.UP*top;var e:=p+Vector3.UP*top
		var inset:=-n*0.28
		var faces:=[[a,b,c,e],[a+inset,e+inset,c+inset,b+inset],[e,c,c+inset,e+inset]]
		if damage==2:faces.append_array([[a,e,e+inset,a+inset],[b,b+inset,c+inset,c]])
		k.solid(faces,k.wallmat(wall))
	func arched_window(p:Vector3,n:Vector3,width:float,height:float,key:int)->void:
		var along:=Vector3(n.z,0,-n.x)
		for layer in 2:
			var radius:=width/2+(0.16 if layer==0 else 0.0)
			var bottom:=-0.12 if layer==0 else 0.0
			var center:=p+n*(0.035+layer*0.025)
			var points:=[center-along*radius+Vector3.UP*bottom,center+along*radius+Vector3.UP*bottom]
			for i in 5:
				var angle:=PI*i/4
				points.append(center+along*cos(angle)*radius+Vector3.UP*(height-width/2+sin(angle)*radius))
			k.solid([points],k.paint(trim if layer==0 else Kit.DARK if damage>0 and key%3==0 else Kit.GLASS))
		if damage==0:face(p+Vector3.UP*(height*0.45),n,0.07,height*0.9,trim,0.08)
		elif key%3==0:face(p+Vector3.UP*(height*0.85),n,width*0.4,0.45,Kit.GLASS,0.08)
	func church_shell(x0:float,x1:float,z0:float,z1:float,top:float)->void:
		box(x0,x1,0,0.2,z0,z1,wall.darkened(0.3))
		for edge in [[Vector3(x0,0,z0),Vector3(x1,0,z0),Vector3.FORWARD],[Vector3(x1,0,z1),Vector3(x0,0,z1),Vector3.BACK],[Vector3(x1,0,z0),Vector3(x1,0,z1),Vector3.RIGHT],[Vector3(x0,0,z1),Vector3(x0,0,z0),Vector3.LEFT]]:
			var a:Vector3=edge[0];var b:Vector3=edge[1];var n:Vector3=edge[2]
			var bays:=maxi(1,int(a.distance_to(b)/3.6))
			for i in bays:
				var p:=a.lerp(b,float(i)/bays);var q:=a.lerp(b,float(i+1)/bays)
				wall_segment(p,q,n,0,top if damage<2 else top-k.rng.randf_range(1.2,3.3))
				arched_window((p+q)/2+Vector3.UP*(1.2 if damage==2 else 2.0),n,1.05,1.8 if damage==2 else 3.7,i)
				if damage<2 and not (damage==1 and i%3==1):k.fbox((p+q)/2+Vector3.UP*(top-0.15),n,p.distance_to(q),0.3,0.16,trim)
				if damage==1 and i%3==1:face((p+q)/2+Vector3.UP*6.0,n,1.5,1.0,Color("514b41"))
		if damage==2:
			k.rubble(x0+0.4,x1-0.4,z0+0.4,z1-0.4,8,top,[wall,Kit.STONE])
		elif damage==0:k.hip_roof(x0-0.15,x1+0.15,z0-0.15,z1+0.15,top,0.8,0,k.roofmat(roof))
		else:
			for i in [0,2]:k.gable_roof(lerpf(x0,x1,i/3.0),lerpf(x0,x1,(i+1)/3.0),z0,z1,top,0.8,"x",0,k.roofmat(roof))
	func dome(center:Vector3,radius:float,height:float)->void:
		# Onion profile: narrow neck, rounded shoulder, drawn-out pointed crown.
		var rings:=[Vector2(0.65,0),Vector2(1,0.28),Vector2(0.91,0.48),Vector2(0.53,0.72),Vector2(0.18,0.91),Vector2(0.01,1)]
		for j in range(rings.size()-1):
			for i in 12:
				if damage==1 and i in [2,3] and j in [1,2]:continue
				var points:=[]
				for q in [[i,j],[i,j+1],[i+1,j+1],[i+1,j]]:
					var r:Vector2=rings[q[1]];var angle:float=TAU*q[0]/12
					points.append(center+Vector3(cos(angle)*r.x*radius,r.y*height,sin(angle)*r.x*radius))
				k.solid([points],k.roofmat(roof if variant%2==0 else Color("a58a48")))

	func chamfer_corner(x:float,z:float,cut:float)->void:
		# Project just the outer corner onto a diagonal plane. All other bays
		# retain their dimensions; roof and cornice follow the same chamfer.
		for piece in k.pivot.get_children():
			if not piece is MeshInstance3D:continue
			var arrays:Array=piece.mesh.surface_get_arrays(0)
			var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var changed:=false
			for i in vertices.size():
				var p:Vector3=piece.transform*vertices[i]
				var delta:float=x+z+cut-p.x-p.z
				if delta>0:
					p+=Vector3(delta/2,0,delta/2)
					vertices[i]=piece.transform.affine_inverse()*p
					changed=true
			if changed:
				arrays[Mesh.ARRAY_VERTEX]=vertices
				var mesh:=ArrayMesh.new()
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
				var surface:=SurfaceTool.new()
				surface.create_from(mesh,0)
				surface.generate_normals()
				piece.mesh=surface.commit()
