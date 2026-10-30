class_name UnitModels
extends RefCounted

# Original, authored geometry. Recognition comes from proportions and major equipment,
# not an exact reproduction of any manufacturer's model or insignia.
var palette:Dictionary={}
var unit_definitions:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/units.json"))
var olive:=Color("555a40")
var edge:=Color("76785a")
var rubber:=Color("293139")
var steel:=Color("42494a")
var canvas:=Color("777057")
var glass:=Color("294d60")
var marking:=Color("bdc8b6")

func mat(color:Color, metal:float=0.0) -> Material:
	var key:=color.to_html()+str(metal)
	if palette.has(key):return palette[key]
	var shader=preload("res://shaders/miniature.gdshader")
	var m:=ShaderMaterial.new()
	m.shader=shader
	m.set_shader_parameter("material_atlas",preload("res://assets/materials/diorama-atlas.png"))
	m.set_shader_parameter("construction_atlas",preload("res://assets/materials/construction-atlas.png"))
	m.set_shader_parameter("paint",color)
	m.set_shader_parameter("finish",metal if metal>0 else (0.9 if color==glass else (0.6 if color==rubber else (0.3 if color==steel else (0.12 if color==canvas or color==Color("777057") else 0.0)))))
	palette[key]=m
	return m

func mesh_node(parent:Node3D,mesh:Mesh,p:Vector3,color:Color) -> MeshInstance3D:
	var node:=MeshInstance3D.new()
	node.mesh=mesh
	node.position=p
	node.material_override=mat(color)
	parent.add_child(node)
	return node

func box(parent:Node3D,p:Vector3,size:Vector3,color:Color) -> MeshInstance3D:
	var minimum:=minf(size.x,minf(size.y,size.z))
	if minimum>=0.09:
		var bevel:=minimum*0.12
		var w:=size.x*0.5
		var l:=size.z*0.5
		var h:=size.y*0.5
		var node:=shell(parent,[octagon(w-bevel,l-bevel,l-bevel,-h,bevel*0.25),octagon(w,l,l,-h+bevel,bevel),octagon(w,l,l,h-bevel,bevel),octagon(w-bevel,l-bevel,l-bevel,h,bevel*0.25)],color)
		node.position=p
		return node
	var mesh:=BoxMesh.new()
	mesh.size=size
	return mesh_node(parent,mesh,p,color)

func ellipsoid(parent:Node3D,p:Vector3,size:Vector3,color:Color) -> MeshInstance3D:
	var mesh:=SphereMesh.new()
	mesh.radius=0.5
	mesh.height=1
	mesh.radial_segments=12
	mesh.rings=6
	var node:=mesh_node(parent,mesh,p,color)
	node.scale=size
	return node

func tube(parent:Node3D,a:Vector3,b:Vector3,radius:float,color:Color,top:float=-1) -> MeshInstance3D:
	var mesh:=CylinderMesh.new()
	mesh.bottom_radius=radius
	mesh.top_radius=radius if top<0 else top
	mesh.height=a.distance_to(b)
	mesh.radial_segments=10
	var node:=mesh_node(parent,mesh,(a+b)/2,color)
	var direction:=(b-a).normalized()
	if absf(direction.dot(Vector3.UP))<0.999:
		node.quaternion=Quaternion(Vector3.UP,direction)
	elif direction.y<0:
		node.rotation.x=PI
	return node

func triangle(st:SurfaceTool,a:Vector3,b:Vector3,c:Vector3,normal:Vector3) -> void:
	st.set_normal(normal)
	# Godot uses clockwise front faces.
	for v in [a,c,b]:st.add_vertex(v)

func shell(parent:Node3D,rings:Array,color:Color) -> MeshInstance3D:
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count:int=rings[0].size()
	for layer in range(rings.size()-1):
		for i in count:
			var a:Vector3=rings[layer][i]
			var b:Vector3=rings[layer][(i+1)%count]
			var c:Vector3=rings[layer+1][(i+1)%count]
			var d:Vector3=rings[layer+1][i]
			var n:Vector3=(b-a).cross(d-a).normalized()
			var outward:=Vector3(a.x+b.x,0,a.z+b.z)
			if n.dot(outward)<0:n=-n
			triangle(st,a,b,c,n)
			triangle(st,a,c,d,n)
	for layer in [0,rings.size()-1]:
		var center:=Vector3.ZERO
		for p in rings[layer]:center+=p
		center/=count
		var n:=Vector3.DOWN if layer==0 else Vector3.UP
		for i in count:triangle(st,center,rings[layer][i],rings[layer][(i+1)%count],n)
	return mesh_node(parent,st.commit(),Vector3.ZERO,color)

func octagon(width:float,front:float,back:float,y:float,cut:float) -> Array:
	return [Vector3(-width+cut,y,-front),Vector3(width-cut,y,-front),Vector3(width,y,-front+cut),Vector3(width,y,back-cut),Vector3(width-cut,y,back),Vector3(-width+cut,y,back),Vector3(-width,y,back-cut),Vector3(-width,y,-front+cut)]

func rig(parent:Node3D,start:int,label:String,pivot:Vector3=Vector3.ZERO) -> Node3D:
	var children:=parent.get_children().slice(start)
	var joint:=Node3D.new()
	joint.name=label
	joint.position=pivot
	parent.add_child(joint)
	for child in children:
		parent.remove_child(child)
		joint.add_child(child)
		child.position-=pivot
	return joint

func tank(parent:Node3D,aa:bool) -> void:
	# Low hull with sloping glacis and exposed running gear, rather than a rectangular box.
	var hull=shell(parent,[octagon(0.77,1.53,1.5,0.25,0.18),octagon(0.85,1.68,1.53,0.73,0.18),octagon(0.72,1.16,1.42,0.97,0.2)],olive)
	hull.material_override=mat(olive,0.025)
	for side in [-1.0,1.0]:
		var x:float=side*0.84
		for z in [-1.28,-0.88,-0.46,0.0,0.46,0.9,1.3]:
			var wheel_start:=parent.get_child_count()
			tube(parent,Vector3(x-0.18,0.37,z),Vector3(x+0.18,0.37,z),0.31,rubber)
			tube(parent,Vector3(x+side*0.185,0.37,z),Vector3(x+side*0.21,0.37,z),0.2,olive)
			tube(parent,Vector3(x+side*0.213,0.37,z),Vector3(x+side*0.228,0.37,z),0.06,steel)
			for angle in [0.0,PI/3,2*PI/3]:
				box(parent,Vector3(x+side*0.23,0.37,z),Vector3(0.012,0.31,0.026),edge).rotation.x=angle
			rig(parent,wheel_start,"Wheel"+str(parent.get_child_count()),Vector3(x,0.37,z))
		for y in [0.07,0.67]:
			box(parent,Vector3(x,y,0),Vector3(0.42,0.12,2.8),rubber)
			for z in range(-7,8):
				box(parent,Vector3(x,y+(0.064 if y>0.5 else -0.055),z*0.19),Vector3(0.45,0.035,0.075),steel)
		for z in [-1.3,1.3]:
			box(parent,Vector3(x,0.37,z),Vector3(0.44,0.6,0.15),rubber).rotation.x=0.22 if z<0 else -0.22
		for i in 5:
			box(parent,Vector3(side*1.015,0.73,-0.95+i*0.48),Vector3(0.055,0.32,0.445),olive)
		# Forward headlights and rear mud guards.
		box(parent,Vector3(side*0.57,0.78,-1.42),Vector3(0.16,0.08,0.05),Color("b8b297"))
		box(parent,Vector3(side*0.92,0.37,1.61),Vector3(0.31,0.49,0.05),rubber)
	for i in 9:
		box(parent,Vector3(0,0.989,0.62+i*0.075),Vector3(0.85,0.027,0.032),rubber)
	# Turret ring, angled cheeks, bustle, and cylindrical main gun.
	tube(parent,Vector3(0,0.89,-0.1),Vector3(0,1.04,-0.1),0.58,steel)
	var turret_start:=parent.get_child_count()
	if aa:
		shell(parent,[octagon(0.6,0.66,0.72,1.01,0.15),octagon(0.47,0.46,0.61,1.43,0.15)],olive)
		for side in [-1.0,1.0]:
			box(parent,Vector3(side*0.62,1.38,-0.05),Vector3(0.28,0.35,0.98),canvas)
			for i in [-0.06,0.06]:
				tube(parent,Vector3(side*0.3+i,1.45,-0.42),Vector3(side*0.3+i,1.66,-1.65),0.045,steel)
		tube(parent,Vector3(0,1.4,0.35),Vector3(0,1.98,0.35),0.06,steel)
		box(parent,Vector3(0,2.02,0.35),Vector3(0.9,0.38,0.12),olive).rotation.x=-0.15
		for i in 5:box(parent,Vector3(-0.36+i*0.18,2.02,0.273),Vector3(0.012,0.3,0.015),edge)
	else:
		shell(parent,[octagon(0.76,0.93,0.96,1.0,0.28),octagon(0.61,0.67,0.78,1.35,0.23)],olive)
		box(parent,Vector3(0,1.12,1.03),Vector3(1.2,0.3,0.21),canvas)
		for side in [-1.0,1.0]:
			# Dusty armor edges and smoke grenade launchers.
			for i in 4:
				tube(parent,Vector3(side*0.62,1.2,-0.47+i*0.12),Vector3(side*0.76,1.27,-0.5+i*0.12),0.045,steel)
		box(parent,Vector3(0,1.13,-0.72),Vector3(0.42,0.3,0.42),edge)
		var gun_start:=parent.get_child_count()
		tube(parent,Vector3(0,1.17,-0.8),Vector3(0,1.17,-2.36),0.065,steel)
		tube(parent,Vector3(0,1.17,-1.4),Vector3(0,1.17,-1.73),0.09,olive)
		tube(parent,Vector3(0,1.17,-2.36),Vector3(0,1.17,-2.395),0.048,rubber)
		rig(parent,gun_start,"Gun")
		for x in [-0.28,0.29]:
			tube(parent,Vector3(x,1.34,0.1),Vector3(x,1.4,0.1),0.21,edge)
			tube(parent,Vector3(x,1.4,0.1),Vector3(x,1.43,0.1),0.14,olive)
		tube(parent,Vector3(0.3,1.4,0.1),Vector3(0.3,1.7,0.1),0.035,steel)
		box(parent,Vector3(0.3,1.71,-0.1),Vector3(0.09,0.1,0.36),steel)
		tube(parent,Vector3(0.3,1.73,-0.24),Vector3(0.3,1.73,-0.66),0.018,steel)
		tube(parent,Vector3(-0.5,1.25,0.64),Vector3(-0.5,2.05,0.64),0.012,steel)
	# Small identification panels, not luminous toy-like body paint.
	box(parent,Vector3(-0.24,1.368,-0.2),Vector3(0.13,0.012,0.29),marking)
	box(parent,Vector3(0.03,1.368,-0.2),Vector3(0.13,0.012,0.29),marking)

	rig(parent,turret_start,"Turret")

func infantry(parent:Node3D,anti_tank:bool,engineer:bool=false) -> void:
	var count:int=3 if engineer else int(unit_definitions.atgm.members if anti_tank else unit_definitions.rifle.members)
	for i in count:
		var soldier_start:=parent.get_child_count()
		var offset:Vector2=preload("res://scripts/infantry.gd").formation_offset(i,count)*0.65
		var o:=Vector3(offset.x,0,offset.y)
		var uniform:=olive if i%2==0 else canvas
		# Anatomical segments and asymmetrical ready stance.
		for side in [-1.0,1.0]:
			var leg_start:=parent.get_child_count()
			var hip:=o+Vector3(side*0.095,0.65,0)
			var knee:=hip+Vector3(0,-0.27,0)
			var ankle:=hip+Vector3(0,-0.55,0)
			tube(parent,hip,knee,0.078,uniform,0.09)
			var knee_start:=parent.get_child_count()
			tube(parent,knee,ankle,0.067,uniform,0.076)
			var foot_start:=parent.get_child_count()
			ellipsoid(parent,ankle+Vector3(0,-0.035,-0.05),Vector3(0.14,0.13,0.25),rubber)
			rig(parent,foot_start,"Foot",ankle)
			rig(parent,knee_start,"Knee",knee)
			rig(parent,leg_start,"LegL" if side<0 else "LegR",hip)

		var upper_start:=parent.get_child_count()
		ellipsoid(parent,o+Vector3(0,0.83,0),Vector3(0.36,0.48,0.25),uniform)
		box(parent,o+Vector3(0,0.88,-0.14),Vector3(0.3,0.32,0.11),canvas)
		box(parent,o+Vector3(0,0.86,0.18),Vector3(0.28,0.34,0.19),olive)
		for x in [-0.09,0.02,0.11]:box(parent,o+Vector3(x,0.82,-0.21),Vector3(0.075,0.12,0.055),olive)
		ellipsoid(parent,o+Vector3(0,1.14,-0.015),Vector3(0.19,0.25,0.2),Color("987f61"))
		ellipsoid(parent,o+Vector3(0,1.23,0),Vector3(0.26,0.18,0.26),uniform)
		box(parent,o+Vector3(0,1.155,-0.112),Vector3(0.17,0.05,0.04),rubber)
		if engineer:
			var kit_start:=parent.get_child_count()
			box(parent,o+Vector3(0,0.9,0.27),Vector3(0.34,0.4,0.20),canvas)
			for x in [-0.12,0.12]:box(parent,o+Vector3(x,0.9,0.38),Vector3(0.04,0.38,0.025),marking)
			tube(parent,o+Vector3(-0.23,0.55,0.25),o+Vector3(-0.23,1.18,0.25),0.025,canvas)
			box(parent,o+Vector3(-0.23,0.54,0.25),Vector3(0.15,0.2,0.045),steel)
			box(parent,o+Vector3(0.24,0.78,0.12),Vector3(0.16,0.18,0.16),canvas)
			rig(parent,kit_start,"EngineerKit",o)
		var weapon_start:=parent.get_child_count()
		for side in [-1.0,1.0]:
			var shoulder:=o+Vector3(side*0.19,0.99,0)
			var elbow:=o+Vector3(side*0.2,0.8,-0.1)
			var hand:=o+Vector3(0.1,0.91,-0.36 if side<0 else -0.19)
			tube(parent,shoulder,elbow,0.06,uniform)
			tube(parent,elbow,hand,0.05,uniform)
			ellipsoid(parent,hand,Vector3(0.085,0.09,0.09),rubber)
		box(parent,o+Vector3(0.11,0.91,-0.32),Vector3(0.07,0.08,0.42),steel)
		box(parent,o+Vector3(0.11,0.82,-0.29),Vector3(0.06,0.14,0.07),rubber).rotation.x=-0.25
		tube(parent,o+Vector3(0.11,0.92,-0.49),o+Vector3(0.11,0.92,-0.74),0.022,steel)
		box(parent,o+Vector3(0.11,0.99,-0.27),Vector3(0.05,0.05,0.13),rubber)
		box(parent,o+Vector3(-0.195,1.0,0),Vector3(0.012,0.08,0.11),marking)
		if anti_tank:
			var launcher_start:=parent.get_child_count()
			tube(parent,o+Vector3(0.28,1.05,0.36),o+Vector3(0.28,1.05,-0.64),0.095,olive)
			tube(parent,o+Vector3(0.28,1.05,-0.64),o+Vector3(0.28,1.05,-0.66),0.075,rubber)
			box(parent,o+Vector3(0.14,1.12,-0.28),Vector3(0.18,0.15,0.16),steel)
			rig(parent,launcher_start,"Launcher",o).visible=i==0

		rig(parent,weapon_start,"Weapon",o+Vector3(0,0.96,0))
		rig(parent,upper_start,"Upper",o)
		rig(parent,soldier_start,"Soldier"+str(i),o)

func helicopter(parent:Node3D) -> void:
	# Tandem canopy, engine nacelles, stub wings, tail boom, wheeled undercarriage.
	ellipsoid(parent,Vector3(0,0,0),Vector3(0.86,0.91,2.7),olive)
	ellipsoid(parent,Vector3(0,-0.04,-1.14),Vector3(0.65,0.55,0.8),olive)
	ellipsoid(parent,Vector3(0,0.4,-0.65),Vector3(0.65,0.58,1.48),glass)
	for z in [-1.08,-0.43,0.08]:
		tube(parent,Vector3(-0.31,0.4,z),Vector3(0,0.69,z+0.08),0.022,steel)
		tube(parent,Vector3(0,0.69,z+0.08),Vector3(0.31,0.4,z),0.022,steel)
	tube(parent,Vector3(0,0.05,0.85),Vector3(0,0.3,3.12),0.24,olive,0.075)
	for side in [-1.0,1.0]:
		ellipsoid(parent,Vector3(side*0.52,0.25,0.45),Vector3(0.42,0.45,1.25),olive)
		tube(parent,Vector3(side*0.52,0.25,0.93),Vector3(side*0.52,0.25,1.15),0.145,rubber)
		box(parent,Vector3(side*0.85,-0.1,0.12),Vector3(1.2,0.09,0.54),olive).rotation.z=side*0.08
		tube(parent,Vector3(side*1.12,-0.34,0.43),Vector3(side*1.12,-0.34,-0.34),0.17,steel)
		for i in 5:
			var a:=i*TAU/5
			tube(parent,Vector3(side*1.12+sin(a)*0.095,-0.34+cos(a)*0.095,-0.35),Vector3(side*1.12+sin(a)*0.095,-0.34+cos(a)*0.095,-0.36),0.034,rubber)
		tube(parent,Vector3(side*0.3,-0.2,-0.3),Vector3(side*0.59,-0.7,-0.45),0.035,steel)
		tube(parent,Vector3(side*0.52,-0.69,-0.45),Vector3(side*0.67,-0.69,-0.45),0.14,rubber)
	tube(parent,Vector3(0,0.22,2.35),Vector3(0,-0.38,2.5),0.027,steel)
	tube(parent,Vector3(-0.07,-0.4,2.5),Vector3(0.07,-0.4,2.5),0.1,rubber)
	var fin:=box(parent,Vector3(0,0.66,2.88),Vector3(0.09,1.03,0.5),olive)
	fin.rotation.x=-0.2
	box(parent,Vector3(0,0.27,2.62),Vector3(1.1,0.065,0.31),olive)
	for angle in [0.5,2.07]:
		var tail:=box(parent,Vector3(0.14,0.68,2.94),Vector3(0.045,0.91,0.08),rubber)
		tail.rotation.x=angle
	tube(parent,Vector3(0,0.3,0.2),Vector3(0,1.02,0.2),0.067,steel)
	var rotor:=Node3D.new()
	rotor.name="Rotor"
	rotor.position=Vector3(0,1.03,0.2)
	parent.add_child(rotor)
	for i in 4:
		var angle:=i*PI/2
		var blade:=box(rotor,Vector3(sin(angle)*1.52,0,cos(angle)*1.52),Vector3(0.14,0.035,2.8),rubber)
		blade.rotation.y=angle
		box(parent,Vector3(0.39,0.16,0.0),Vector3(0.02,0.11,0.3),marking)
	ellipsoid(parent,Vector3(0,-0.24,-1.44),Vector3(0.32,0.28,0.34),steel)
	tube(parent,Vector3(0,-0.38,-0.88),Vector3(0,-0.44,-1.6),0.035,steel)

func drone(parent:Node3D) -> void:
	ellipsoid(parent,Vector3(0,0.03,0),Vector3(0.5,0.27,0.66),olive)
	for x in [-0.75,0.75]:
		for z in [-0.68,0.68]:
			tube(parent,Vector3(x*0.12,0,z*0.13),Vector3(x,0.06,z),0.04,steel)
			tube(parent,Vector3(x,0.02,z),Vector3(x,0.18,z),0.085,steel)
			var prop_start:=parent.get_child_count()
			box(parent,Vector3(x,0.2,z),Vector3(0.76,0.02,0.06),rubber).rotation.y=0.4 if x*z>0 else -0.4
			box(parent,Vector3(x,0.205,z),Vector3(0.06,0.02,0.76),rubber).rotation.y=0.4 if x*z>0 else -0.4
			rig(parent,prop_start,"Prop"+str(parent.get_child_count()),Vector3(x,0.2,z))
	ellipsoid(parent,Vector3(0,-0.21,-0.18),Vector3(0.21,0.22,0.21),steel)
	ellipsoid(parent,Vector3(0,-0.21,-0.275),Vector3(0.13,0.13,0.04),glass)
	box(parent,Vector3(0,0.171,0),Vector3(0.16,0.02,0.3),marking)

func corvette(parent:Node3D) -> void:
	# Fine bow, flared sides, raised bridge, deck gun, radar mast and stern flight deck.
	var lower:=[Vector3(0,0.08,-2.94),Vector3(0.77,0.08,-1.65),Vector3(0.91,0.08,1.9),Vector3(0.7,0.08,2.62),Vector3(-0.7,0.08,2.62),Vector3(-0.91,0.08,1.9),Vector3(-0.77,0.08,-1.65)]
	var upper:=[Vector3(0,0.73,-3.02),Vector3(0.99,0.73,-1.68),Vector3(1.03,0.73,2.17),Vector3(0.87,0.73,2.65),Vector3(-0.87,0.73,2.65),Vector3(-1.03,0.73,2.17),Vector3(-0.99,0.73,-1.68)]
	var hull=shell(parent,[lower,upper],Color("687779"))
	hull.material_override=mat(Color("687779"),0.045)
	var deck:=upper.duplicate()
	for i in deck.size():deck[i].y=0.749
	shell(parent,[upper,deck],Color("414e51"))
	shell(parent,[octagon(0.61,0.62,1.02,0.77,0.18),octagon(0.44,0.41,0.89,1.65,0.15)],Color("8d9795"))
	for x in [-0.28,0.0,0.28]:box(parent,Vector3(x,1.54,-0.465),Vector3(0.2,0.16,0.02),glass)
	for side in [-1.0,1.0]:
		for z in [-0.22,0.03,0.28]:box(parent,Vector3(side*0.49,1.54,z),Vector3(0.02,0.15,0.18),glass)
		# Rails lie entirely inside the hull's collision envelope.
		for z in [-1.5,-0.8,0.0,0.8,1.6,2.25]:tube(parent,Vector3(side*0.88,0.75,z),Vector3(side*0.88,1.03,z),0.013,edge)
		tube(parent,Vector3(side*0.88,1.03,-1.5),Vector3(side*0.88,1.03,2.25),0.015,edge)
		ellipsoid(parent,Vector3(side*0.67,1.01,0.85),Vector3(0.28,0.26,0.62),canvas)
	tube(parent,Vector3(0,1.6,0.28),Vector3(0,3.25,0.28),0.045,steel)
	tube(parent,Vector3(-0.46,2.49,0.28),Vector3(0.46,2.49,0.28),0.026,steel)
	box(parent,Vector3(0,2.92,0.28),Vector3(0.73,0.27,0.09),olive)
	ellipsoid(parent,Vector3(0,2.19,0.52),Vector3(0.3,0.32,0.3),Color("b4b9ac"))
	var turret_start:=parent.get_child_count()
	tube(parent,Vector3(0,0.74,-1.5),Vector3(0,0.93,-1.5),0.35,steel)
	var turret:=shell(parent,[octagon(0.34,0.32,0.32,0.93,0.1),octagon(0.23,0.23,0.23,1.2,0.08)],Color("8d9795"))
	turret.position.z=-1.5
	tube(parent,Vector3(0,1.12,-1.64),Vector3(0,1.23,-2.66),0.04,steel)
	rig(parent,turret_start,"Turret",Vector3(0,0,-1.5))
	for x in [-0.43,0.43]:box(parent,Vector3(x,0.763,1.95),Vector3(0.035,0.012,0.68),marking)
	box(parent,Vector3(0,0.764,1.95),Vector3(0.86,0.012,0.035),marking)

func build(parent:Node3D,kind:String,team:int) -> void:
	olive=Color("696d58") if team==0 else Color("8c7b60")
	edge=Color("888b74") if team==0 else Color("a39173")
	canvas=Color("77755a") if team==0 else Color("6d6452")
	marking=Color("a9c6bd") if team==0 else Color("be7965")
	match kind:
		"tank":tank(parent,false)
		"aa":tank(parent,true)
		"rifle":infantry(parent,false)
		"atgm":infantry(parent,true)
		"engineer":infantry(parent,false,true)
		"tactical_cover","observation_post","repair_point","aid_post","concertina_wire","tank_obstacles","fighting_trench","vehicle_berm","camouflage_net","forward_supply_point","bunker","at_gun","command_post","ammo_depot":preload("res://scripts/field_models.gd").build(self,parent,kind)
		"helo":helicopter(parent)
		"drone":drone(parent)
		"boat":corvette(parent)
		"harvester":harvester(parent)
		"hq","power","refinery","barracks","factory":base_structure(parent,kind)

func harvester(parent:Node3D) -> void:
	shell(parent,[octagon(0.72,1.35,1.4,0.4,0.15),octagon(0.68,1.25,1.35,0.75,0.15)],olive)
	box(parent,Vector3(0,1.05,-0.75),Vector3(1.25,0.75,0.9),olive)
	box(parent,Vector3(0,1.13,-1.21),Vector3(1.05,0.38,0.025),glass)
	box(parent,Vector3(0,1.02,0.52),Vector3(1.38,0.68,1.6),canvas)
	for side in [-1,1]:
		for z in [-0.9,0.65,1.15]:tube(parent,Vector3(side*0.61,0.32,z),Vector3(side*0.83,0.32,z),0.3,rubber)

func base_structure(parent:Node3D,kind:String) -> void:
	box(parent,Vector3(0,0.2,0),Vector3(4.8,0.4,4.5),steel)
	box(parent,Vector3(0,1.25,0),Vector3(4.3,2.1,4.0),canvas)
	box(parent,Vector3(0,2.35,0),Vector3(4.5,0.15,4.2),olive)
	box(parent,Vector3(0,1.0,-2.02),Vector3(2.0,1.75,0.035),rubber)
	for x in [-1.5,1.5]:box(parent,Vector3(x,1.55,-2.04),Vector3(0.65,0.45,0.03),glass)
	box(parent,Vector3(0,2.1,-2.04),Vector3(1.6,0.18,0.04),marking)
	match kind:
		"hq":
			tube(parent,Vector3(1.2,2.4,0.7),Vector3(1.2,4.4,0.7),0.06,steel)
			box(parent,Vector3(1.2,4.3,0.7),Vector3(1.2,0.45,0.1),olive)
		"power":
			for x in [-1.0,1.0]:
				tube(parent,Vector3(x,2.4,0.4),Vector3(x,3.7,0.4),0.55,steel)
				for z in range(-6,7):box(parent,Vector3(x,3.72,z*0.1+0.4),Vector3(0.8,0.04,0.035),rubber)
		"refinery":
			for x in [-1.1,1.1]:tube(parent,Vector3(x,2.4,0.4),Vector3(x,3.9,0.4),0.7,olive)
		"factory":
			box(parent,Vector3(0,2.8,0),Vector3(3.6,0.8,2.4),steel)
			for x in range(-8,9):box(parent,Vector3(x*0.2,3.22,0),Vector3(0.035,0.025,2.3),edge)
		"barracks":box(parent,Vector3(0,2.7,0),Vector3(1.2,0.6,3.4),olive)
