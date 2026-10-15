class_name RoadsideProps
extends RefCounted

# Original generic silhouettes; no brands, live lights, physics bodies or traffic.
# Local footprints include mirrors, bumpers and lamp heads, not only the chassis.
static func layout(scenario:int)->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	var rows:Array=[]
	if scenario==3:
		rows=[["sedan",35,14,0,"71817b"],["service",51,56,90,"b8b3a0"],
			["lamp",36.3,9,90,"505b58"],["lamp",43.7,43,-90,"505b58"],["lamp",60,47.3,0,"505b58"]]
	elif scenario==4:
		rows=[["sedan",26,55,90,"7f6260"],["service",56,65,90,"b8b3a0"],
			["lamp",40.3,12,90,"505b58"],["lamp",43.7,40,-90,"505b58"],["lamp",28,63.7,180,"505b58"]]
	elif scenario==5:
		rows=[["sedan",31,49,90,"71817b"],["service",104,79,0,"a6a08d"],
			["sedan",86,59.5,90,"7f6260"],["service",104,33,0,"858c87"],
			["lamp",44,49,0,"505b58"],["lamp",68,59,0,"505b58"],["lamp",104,59,0,"505b58"],
			["lamp",76,34,0,"505b58"],["lamp",44,80,0,"505b58"],
			["pallets",102,87,0,"81735d"],["drums",102,82,0,"65776c"],["reel",103,94,0,"786c58"],
			["cabinet",119,75,0,"79817b"],["bench",86,50,90,"776d58"],["bin",84,50,0,"546a5b"],
			["bollard",127.2,72,0,"575d5c"],["bollard",127.2,80,0,"575d5c"],["bollard",127.2,94,0,"575d5c"],
			["pallets",116,44,90,"81735d"],["drums",119,45,0,"6c7776"],["reel",115,75,90,"786c58"]]
	for row in rows:
		result.append({"kind":row[0],"pos":Vector2(row[1],row[2]),"yaw":deg_to_rad(float(row[3])),"color":Color(row[4])})
	if scenario==5:
		# Land-side edge: every stone stays at/before shore_x=128. Sea
		# clearance remains honest without adding obstacles in navigable water.
		# The northern loading apron keeps a five-unit bank opening at
		# y29.5..34.5, preserving the adjacent base's vehicle exit sweep.
		for bay in [[16.0,26.0],[26.12,29.5],[34.5,46.0],[46.12,56.0],
			[56.12,66.0],[66.12,78.0],[78.12,90.0],[90.12,102.0]]:
			result.append({"kind":"quay_bay","pos":Vector2(127.5,(bay[0]+bay[1])/2.0),"yaw":0.0,"color":Color("929183"),"length":bay[1]-bay[0]})
		for prop in result:
			if prop.kind=="bollard":prop["elevation"]=0.56
	return result

static func local_footprint(kind:String,length:float=12.0)->Rect2:
	if kind=="quay_bay":return Rect2(-0.6,-length/2.0,1.1,length)
	if kind=="lamp":return Rect2(-0.25,-0.4,0.5,1.0)
	if kind=="pallets":return Rect2(-0.85,-0.7,1.7,1.4)
	if kind=="drums":return Rect2(-0.85,-0.65,1.7,1.3)
	if kind=="reel":return Rect2(-0.75,-0.6,1.5,1.2)
	if kind=="cabinet":return Rect2(-0.55,-0.4,1.1,0.8)
	if kind=="bench":return Rect2(-0.9,-0.5,1.8,1.0)
	if kind=="bin":return Rect2(-0.4,-0.4,0.8,0.8)
	if kind=="bollard":return Rect2(-0.3,-0.3,0.6,0.6)
	return Rect2(-1.1,-2.4 if kind=="service" else -2.2,2.2,4.8 if kind=="service" else 4.4)

static func footprint(prop:Dictionary)->Rect2:
	var local:=local_footprint(prop.kind,float(prop.get("length",12.0)))
	var bounds:=Rect2(prop.pos,Vector2.ZERO)
	for corner in [local.position,Vector2(local.end.x,local.position.y),local.end,Vector2(local.position.x,local.end.y)]:
		# Godot's Y rotation maps local (x,z) to this clockwise 2D rotation.
		bounds=bounds.expand(prop.pos+corner.rotated(-float(prop.yaw)))
	return bounds

static func build(art,parent:Node3D,terrain)->Node3D:
	# Idempotent integration: one static family per terrain scene parent.
	if parent.has_node("RoadsideProps"):return parent.get_node("RoadsideProps")
	var group:=Node3D.new();group.name="RoadsideProps";parent.add_child(group)
	for prop in terrain.roadside_props:
		var model:=Node3D.new();group.add_child(model)
		model.name=prop.kind
		model.position=Vector3(prop.pos.x,float(prop.get("elevation",0.0)),prop.pos.y);model.rotation.y=prop.yaw
		if prop.kind=="quay_bay":_quay_bay(art,model,float(prop.length),prop.color)
		elif prop.kind=="lamp":_lamp(art,model)
		elif prop.kind not in ["sedan","service"]:_furniture(art,model,prop.kind,prop.color)
		else:_car(art,model,prop.kind=="service",prop.color)
		art.bake_model(model)
	return group

# Two original masonry courses and individually jointed coping slabs, sized
# explicitly in world units. Expansion gaps separate bays; no scaled meshes.
static func _quay_bay(art,parent:Node3D,length:float,stone:Color)->void:
	art.box(parent,Vector3(0,0.20,0),Vector3(0.90,0.40,length),stone.darkened(0.22))
	for course in 2:
		var offset:float=-0.9 if course==1 else 0.0
		for index in range(ceili(length/1.8)+1):
			var start:=maxf(-length/2.0,-length/2.0+offset+index*1.8)
			var end:=minf(length/2.0,-length/2.0+offset+(index+1)*1.8)
			if end-start<0.04:continue
			art.box(parent,Vector3(0,0.10+course*0.20,(start+end)/2.0),Vector3(0.96,0.184,end-start-0.018),stone.darkened(0.04 if (index+course)%2 else 0.0))
	var slabs:=ceili(length/2.0)
	var spacing:=length/slabs
	for index in slabs:
		art.box(parent,Vector3(-0.05,0.48,-length/2.0+(index+0.5)*spacing),Vector3(1.10,0.16,spacing-0.018),Color("b0aa94"))

static func _lamp(art,parent:Node3D)->void:
	var steel:=Color("505b58")
	art.box(parent,Vector3(0,0.08,0),Vector3(0.42,0.16,0.42),Color("858578"))
	art.models.tube(parent,Vector3(0,0.16,0),Vector3(0,3.55,0),0.085,steel,0.055)
	art.models.tube(parent,Vector3(0,3.5,0),Vector3(0,3.65,0.25),0.055,steel)
	art.box(parent,Vector3(0,3.68,0.22),Vector3(0.4,0.16,0.66),steel)
	# Pale diffuser is solid geometry; no per-lamp Light3D or emission/shadow cost.
	art.box(parent,Vector3(0,3.59,0.24),Vector3(0.31,0.025,0.49),Color("d6d2b1"))
	art.box(parent,Vector3(0,0.6,-0.07),Vector3(0.14,0.28,0.055),Color("70766b"))

static func _car(art,parent:Node3D,service:bool,paint:Color)->void:
	var length:=4.5 if service else 4.1
	var rubber:Color=art.models.rubber
	var glass:Color=art.models.glass
	art.models.box(parent,Vector3(0,0.60,0),Vector3(1.82,0.54,length),paint)
	art.box(parent,Vector3(0,0.32,0),Vector3(1.5,0.16,length-0.6),art.models.steel)
	for side in [-1.0,1.0]:
		for z in [-1.35,1.35]:
			art.models.tube(parent,Vector3(side*0.79,0.35,z),Vector3(side*0.98,0.35,z),0.34,rubber)
			art.models.tube(parent,Vector3(side*0.98,0.35,z),Vector3(side*1.005,0.35,z),0.17,Color("9b9c90"))
		art.box(parent,Vector3(side*0.97,1.08,-0.83),Vector3(0.16,0.13,0.25),paint)
	if service:
		art.models.box(parent,Vector3(0,1.24,0.45),Vector3(1.73,1.16,3.0),paint)
		art.box(parent,Vector3(0,1.24,-1.07),Vector3(1.42,0.62,0.035),glass)
		for side in [-1.0,1.0]:
			art.box(parent,Vector3(side*0.87,1.26,-0.66),Vector3(0.025,0.58,0.72),glass)
			art.box(parent,Vector3(side*0.875,0.99,0.75),Vector3(0.025,0.13,2.1),Color("a38548"))
			art.box(parent,Vector3(side*0.48,1.91,0.5),Vector3(0.06,0.13,2.45),art.models.steel)
		art.box(parent,Vector3(0,1.23,1.96),Vector3(0.035,1.0,0.025),art.models.steel)
		for z in [-0.55,1.55]:art.box(parent,Vector3(0,1.93,z),Vector3(1.3,0.055,0.08),Color("94998f"))
	else:
		# Sloping windshield/rear glass and a separate roof form a three-box sedan.
		art.models.shell(parent,[[Vector3(-0.83,0.85,-1.05),Vector3(0.83,0.85,-1.05),Vector3(0.83,0.85,1.08),Vector3(-0.83,0.85,1.08)],
			[Vector3(-0.66,1.48,-0.59),Vector3(0.66,1.48,-0.59),Vector3(0.66,1.48,0.65),Vector3(-0.66,1.48,0.65)]],glass)
		art.models.box(parent,Vector3(0,1.5,0.03),Vector3(1.38,0.09,1.31),paint)
		for side in [-1.0,1.0]:
			art.models.tube(parent,Vector3(side*0.83,0.85,0.10),Vector3(side*0.66,1.48,0.10),0.043,paint)
			art.box(parent,Vector3(side*0.92,0.76,0.15),Vector3(0.025,0.045,0.24),Color("b6b7aa"))
	for end in [-1.0,1.0]:
		art.box(parent,Vector3(0,0.45,end*(length/2+0.025)),Vector3(1.78,0.16,0.10),art.models.rubber)
		art.box(parent,Vector3(0,0.63,end*(length/2+0.015)),Vector3(0.39,0.14,0.035),Color("b9b8a3"))
		for side in [-1.0,1.0]:art.box(parent,Vector3(side*0.63,0.75,end*(length/2+0.015)),Vector3(0.34,0.17,0.035),Color("d7d5b7") if end<0 else Color("8e4235"))
	art.box(parent,Vector3(0,0.77,-length/2-0.02),Vector3(0.66,0.12,0.035),art.models.rubber)

static func _furniture(art,parent:Node3D,kind:String,color:Color)->void:
	if kind=="pallets":
		for level in 4:
			for rail in 5:art.box(parent,Vector3(-0.64+rail*0.32,0.13+level*0.16,0),Vector3(0.27,0.06,1.25),color)
			for x in [-0.6,0.6]:art.box(parent,Vector3(x,0.07+level*0.16,0),Vector3(0.13,0.10,1.18),color.darkened(0.15))
	elif kind=="drums":
		for x in [-0.42,0.42]:
			art.models.tube(parent,Vector3(x,0.04,0),Vector3(x,1.0,0),0.31,color)
			for y in [0.10,0.88]:art.models.tube(parent,Vector3(x,y-0.025,0),Vector3(x,y+0.025,0),0.325,color.darkened(0.30))
			art.box(parent,Vector3(x,0.51,-0.312),Vector3(0.25,0.22,0.012),Color("b3aa81"))
	elif kind=="reel":
		art.models.tube(parent,Vector3(-0.4,0.56,0),Vector3(0.4,0.56,0),0.43,Color("393c36"))
		for x in [-0.5,0.5]:
			art.models.tube(parent,Vector3(x-0.055,0.56,0),Vector3(x+0.055,0.56,0),0.55,color)
			art.models.tube(parent,Vector3(x-0.06,0.56,0),Vector3(x+0.06,0.56,0),0.10,Color("393c36"))
	elif kind=="cabinet":
		art.box(parent,Vector3(0,0.70,0),Vector3(0.85,1.4,0.62),color)
		art.box(parent,Vector3(0,0.74,-0.32),Vector3(0.72,1.15,0.018),color.darkened(0.1))
		for row in 5:art.box(parent,Vector3(0,1.01-row*0.07,-0.335),Vector3(0.5,0.025,0.012),Color("333b34"))
	elif kind=="bench":
		for z in [-0.2,0.0,0.2]:art.box(parent,Vector3(0,0.48,z),Vector3(1.65,0.09,0.15),color)
		for y in [0.73,0.94]:art.box(parent,Vector3(0,y,0.28),Vector3(1.65,0.13,0.08),color)
		for x in [-0.62,0.62]:art.box(parent,Vector3(x,0.23,0),Vector3(0.1,0.46,0.48),Color("373f39"))
	elif kind=="bin":
		art.box(parent,Vector3(0,0.42,0),Vector3(0.65,0.84,0.65),color)
		art.box(parent,Vector3(0,0.86,0),Vector3(0.71,0.07,0.71),color.darkened(0.2))
	elif kind=="bollard":
		art.models.tube(parent,Vector3(0,0,0),Vector3(0,0.63,0),0.16,color)
		art.models.tube(parent,Vector3(-0.25,0.51,0),Vector3(0.25,0.51,0),0.09,color)
