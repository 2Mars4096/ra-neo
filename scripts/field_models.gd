class_name FieldModels
extends RefCounted

# Cosmetic assemblies only. Simulation owns reservations, work, cover and healing.
const P=preload("res://scripts/environment_palette.gd")
const Battlefield=preload("res://scripts/assets_battlefield.gd")
const Variants=preload("res://scripts/environment_variants.gd")
const FOOTPRINTS={
	"tactical_cover":Vector2(2.8,1.0),
	"observation_post":Vector2(2.6,2.6),
	"repair_point":Vector2(5.6,6.0),
	"aid_post":Vector2(5.6,6.0),
	"concertina_wire":Vector2(7.0,1.4),
	"tank_obstacles":Vector2(6.4,2.4),
	"fighting_trench":Vector2(7.0,2.0),
	"vehicle_berm":Vector2(6.0,6.0),
	"camouflage_net":Vector2(5.6,4.8),
	"forward_supply_point":Vector2(6.0,5.0),
	"bunker":Vector2(4.4,3.6),
	"at_gun":Vector2(4.2,4.2),
	"command_post":Vector2(5.0,4.2),
	"ammo_depot":Vector2(6.0,4.4),
}
const BUILD_SECONDS={"tactical_cover":8.0,"observation_post":10.0,"repair_point":15.0,"aid_post":12.0,"concertina_wire":6.0,"tank_obstacles":10.0,"fighting_trench":10.0,"vehicle_berm":12.0,"camouflage_net":6.0,"forward_supply_point":18.0,"bunker":22.0,"at_gun":16.0,"command_post":16.0,"ammo_depot":14.0}
const EARTH:=Color("6a5b43")
const SPOIL:=Color("5a4c38")
const PIT:=Color("2f2a22")
const RUST:=Color("5c4b3b")

# Small adapter reuses original asset builders without a Visuals/UnitModels cycle.
class AssetAdapter:
	extends RefCounted
	var models
	func _init(source):models=source
	func box(parent:Node3D,pos:Vector3,size:Vector3,color:Color)->MeshInstance3D:
		return models.box(parent,pos,size,color)
	func bake_model(_model:Node3D)->void:pass # Caller batches the completed assembly.

static func build(models,parent:Node3D,kind:String)->void:
	if not FOOTPRINTS.has(kind):return
	var art=AssetAdapter.new(models)
	var saved:Array=[models.olive,models.edge,models.canvas,models.marking]
	models.olive=P.OLIVE;models.edge=P.EDGE;models.canvas=P.CANVAS;models.marking=P.MARKING
	match kind:
		"tactical_cover":
			# Straight two-course wall over the full 2.8 m length so dragged segments
			# join into one continuous sandbag line (no L-returns between them).
			for course in 3:
				var count:=6 if course%2==0 else 5
				var y:=0.125+course*0.24
				for i in count:
					var x:=-1.4+0.234+i*0.467+(0.233 if course%2==1 else 0.0)
					models.box(parent,Vector3(x,y,0.0),Vector3(0.45,0.25,0.62-course*0.08),SANDBAG.darkened(0.035*((i+course)%3)))
			models.box(parent,Vector3(0,0.015,0),Vector3(2.8,0.03,1.0),EARTH.lightened(0.05))
		"observation_post":
			Battlefield.build(art,parent,"antenna","tripod")
			models.box(parent,Vector3(0.62,0.24,-0.65),Vector3(0.64,0.48,0.48),P.OLIVE)
			models.box(parent,Vector3(0.62,0.49,-0.65),Vector3(0.44,0.025,0.3),P.GLASS)
		"repair_point":
			Battlefield.build(art,parent,"supply_tent","lean_to")
			var tools:=Node3D.new();tools.name="Toolbox";parent.add_child(tools)
			models.box(tools,Vector3(1.15,0.28,-1.8),Vector3(1.1,0.56,0.58),P.STEEL)
			models.box(tools,Vector3(1.15,0.58,-1.8),Vector3(0.38,0.06,0.10),P.MARKING)
			for x in [0.82,1.48]:models.box(tools,Vector3(x,0.3,-2.1),Vector3(0.07,0.22,0.025),P.MARKING)
			models.tube(tools,Vector3(-1.2,0.04,-1.6),Vector3(-1.2,0.6,-1.6),0.22,P.STEEL)
			models.box(tools,Vector3(-1.2,0.63,-1.6),Vector3(0.55,0.06,0.12),P.EDGE)
		"aid_post":
			Battlefield.build(art,parent,"supply_tent","ridge")
			var sign_node:=Node3D.new();sign_node.name="MedicalMarking";parent.add_child(sign_node)
			# Muted white medical cross on a green board, above the entrance.
			models.box(sign_node,Vector3(0,2.25,-2.43),Vector3(0.8,0.68,0.06),P.OLIVE)
			models.box(sign_node,Vector3(0,2.25,-2.468),Vector3(0.17,0.5,0.025),P.SAFETY_WHITE)
			models.box(sign_node,Vector3(0,2.25,-2.469),Vector3(0.5,0.17,0.027),P.SAFETY_WHITE)
			models.box(parent,Vector3(1.16,0.22,-2.0),Vector3(0.65,0.44,0.45),P.MARKING)
		"concertina_wire":_wire(models,parent)
		"tank_obstacles":
			for x in [-2.2,0.0,2.2]:_hedgehog(models,parent,Vector3(x,0,0.1*x))
		"fighting_trench":
			# Dug bay with revetment boards, spoil parapet facing -z and sandbag lip.
			models.box(parent,Vector3(0,0.02,0.15),Vector3(6.6,0.03,1.0),PIT)
			for z in [-0.38,0.68]:models.box(parent,Vector3(0,0.12,z),Vector3(6.6,0.22,0.06),P.CANVAS.darkened(0.35))
			models.box(parent,Vector3(0,0.2,-0.72),Vector3(6.9,0.4,0.52),SPOIL)
			models.box(parent,Vector3(0,0.12,0.88),Vector3(6.4,0.22,0.22),EARTH)
			for x in [-2.0,0.6]:
				var bags:Node3D=Variants.build(art,parent,"sandbags","straight")
				bags.position=Vector3(x,0.38,-0.7);bags.scale=Vector3(1,0.6,0.55)
		"vehicle_berm":
			# U-shaped pushed-up earth: open toward +z so a vehicle reverses in.
			models.box(parent,Vector3(0,0.02,0.3),Vector3(4.2,0.03,5.0),PIT.lightened(0.15))
			models.box(parent,Vector3(0,0.55,-2.55),Vector3(5.8,1.1,0.9),EARTH)
			models.box(parent,Vector3(0,0.3,-2.0),Vector3(5.0,0.6,0.5),SPOIL)
			for x in [-2.55,2.55]:
				models.box(parent,Vector3(x,0.45,-0.3),Vector3(0.9,0.9,4.6),EARTH)
				models.box(parent,Vector3(x,0.18,2.2),Vector3(0.8,0.36,1.0),SPOIL)
		"camouflage_net":Battlefield.build(art,parent,"camouflage_net","low_drape")
		"forward_supply_point":
			# Palletised ammunition, fuel cans and a marker pole; no tent so the ground stays readable.
			for i in 4:
				var x:=-2.2+i*1.3
				models.box(parent,Vector3(x,0.07,-1.2),Vector3(1.1,0.14,1.0),Color("7a6a50"))
				models.box(parent,Vector3(x,0.42,-1.2),Vector3(1.0,0.56,0.9),P.OLIVE if i%2==0 else P.CANVAS)
			for i in 6:models.box(parent,Vector3(-2.3+i*0.42,0.27,0.6),Vector3(0.34,0.5,0.18),Color("4c5636"))
			for i in 3:models.tube(parent,Vector3(1.2+i*0.62,0,0.9),Vector3(1.2+i*0.62,0.86,0.9),0.28,P.STEEL)
			models.tube(parent,Vector3(2.35,0,-2.1),Vector3(2.35,2.8,-2.1),0.04,P.STEEL)
			models.box(parent,Vector3(2.6,2.55,-2.1),Vector3(0.46,0.34,0.02),P.SAFETY_ORANGE)
		"bunker":_bunker(models,parent)
		"at_gun":_at_gun(models,parent)
		"command_post":_command_post(models,parent)
		"ammo_depot":_ammo_depot(models,parent)
	models.olive=saved[0];models.edge=saved[1];models.canvas=saved[2];models.marking=saved[3]
	var size:Vector2=FOOTPRINTS[kind]
	parent.set_meta("local_footprint",Rect2(-size/2,size))
	parent.set_meta("field_kind",kind)

# Two helical coils along x plus pickets; thin box strands keep triangles low.
static func _wire(models,parent:Node3D)->void:
	for x in [-3.3,-1.1,1.1,3.3]:models.tube(parent,Vector3(x,0,0),Vector3(x,1.05,0),0.035,P.STEEL)
	for row in [[-0.32,0.36],[0.32,0.36],[0.0,0.92]]:
		var radius:float=0.36 if row[1]<0.5 else 0.3
		var previous:=Vector3.ZERO
		for i in 97:
			var x:=-3.4+i*0.07
			var angle:=i*0.07/0.3*TAU
			var point:=Vector3(x,row[1]+sin(angle)*radius*0.9,row[0]+cos(angle)*radius)
			if i>0:_strand(models,parent,previous,point)
			previous=point

static func _strand(models,parent:Node3D,a:Vector3,b:Vector3)->void:
	var node:MeshInstance3D=models.box(parent,(a+b)/2,Vector3(0.022,0.022,a.distance_to(b)),Color("5d6463"))
	node.basis=Basis.looking_at(b-a,Vector3.UP if absf((b-a).normalized().y)<0.95 else Vector3.RIGHT)

# Czech hedgehog: three welded angle beams crossing at mid-height.
static func _hedgehog(models,parent:Node3D,at:Vector3)->void:
	# Orthogonal beams with the cube diagonal vertical: each rises 35.26 degrees.
	# Half-length 0.875*sin(rise) plus the 0.075 radius reach 0.566 below centre.
	var centre:=at+Vector3(0,0.568,0)
	models.box(parent,at+Vector3(0,0.01,0),Vector3(0.5,0.02,0.5),SPOIL) # Scuffed ground seats the beams.
	var rise:=asin(1.0/sqrt(3.0))
	for k in 3:
		var azimuth:=k*TAU/3.0+0.3
		var direction:=Vector3(cos(azimuth)*cos(rise),sin(rise),sin(azimuth)*cos(rise))
		models.tube(parent,centre-direction*0.875,centre+direction*0.875,0.075,RUST)

const CONCRETE:=Color("8a877c")
const CONCRETE_DARK:=Color("5f5d55")
const SANDBAG:=Color("8c7f5e")

# Low concrete MG pillbox: firing slit toward -z, earth banked on the flanks,
# sandbag blast wall shielding the rear door. Fits 4.4 x 3.6.
static func _bunker(models,parent:Node3D)->void:
	models.box(parent,Vector3(0,0.65,0),Vector3(3.8,1.3,2.9),CONCRETE)
	models.box(parent,Vector3(0,1.42,0),Vector3(4.2,0.24,3.3),CONCRETE.lightened(0.04))
	models.box(parent,Vector3(0,0.86,-1.46),Vector3(2.4,0.22,0.04),Color("1d211e"))
	models.box(parent,Vector3(0,0.98,-1.5),Vector3(2.7,0.06,0.12),CONCRETE_DARK)
	for x in [-2.0,2.0]:models.box(parent,Vector3(x,0.4,0),Vector3(0.36,0.8,3.3),EARTH)
	models.box(parent,Vector3(0,0.2,-1.65),Vector3(4.2,0.4,0.28),SPOIL)
	for i in 5:models.box(parent,Vector3(-0.9+i*0.45,0.22,1.62),Vector3(0.42,0.24,0.28),SANDBAG.darkened(0.04*(i%2)))
	for i in 4:models.box(parent,Vector3(-0.7+i*0.45,0.46,1.62),Vector3(0.42,0.22,0.28),SANDBAG)
	models.box(parent,Vector3(1.2,0.55,1.44),Vector3(0.8,1.1,0.04),Color("2a2e29"))
	for i in 3:models.box(parent,Vector3(-1.2+i*1.1,1.56,0.2-i*0.4),Vector3(0.9,0.06,0.7),Color("53603f"))

# Towed anti-tank gun in a horseshoe sandbag pit, muzzle toward -z.
static func _at_gun(models,parent:Node3D)->void:
	models.box(parent,Vector3(0,0.02,0),Vector3(3.6,0.03,3.6),PIT.lightened(0.18))
	for i in 11:
		var angle:=PI*0.15+i*PI*1.7/10.0
		var at:=Vector3(cos(angle)*1.72,0.25,-sin(angle)*1.72)
		var bag:MeshInstance3D=models.box(parent,at,Vector3(0.6,0.5,0.32),SANDBAG.darkened(0.05*(i%2)))
		bag.rotation.y=angle+PI/2
	for side in [-1,1]:models.tube(parent,Vector3(side*0.62,0.42,0.1),Vector3(side*0.78,0.42,0.1),0.38,Color("2b2f2b"))
	models.box(parent,Vector3(0,0.62,0),Vector3(1.3,0.26,0.7),P.OLIVE)
	models.box(parent,Vector3(0,0.95,-0.32),Vector3(1.5,0.78,0.06),P.OLIVE)
	models.tube(parent,Vector3(0,0.86,-0.2),Vector3(0,0.86,-1.75),0.07,P.STEEL)
	models.box(parent,Vector3(0,0.86,-1.75),Vector3(0.2,0.2,0.2),P.STEEL)
	for side in [-1,1]:models.tube(parent,Vector3(side*0.25,0.55,0.25),Vector3(side*0.85,0.06,1.65),0.06,P.OLIVE)
	for i in 3:models.box(parent,Vector3(1.0+i*0.32,0.15,1.1),Vector3(0.26,0.3,0.6),Color("54583c"))

# Command post: ridge tent, radio mast with whip, map table and sandbag ring.
static func _command_post(models,parent:Node3D)->void:
	models.box(parent,Vector3(-0.4,0.75,0.1),Vector3(3.2,1.5,2.6),P.CANVAS)
	for side in [-1,1]:
		var slope:MeshInstance3D=models.box(parent,Vector3(-0.4,1.72,0.1+side*0.68),Vector3(3.3,0.06,1.55),P.CANVAS.darkened(0.08))
		slope.rotation.x=side*0.62
	models.box(parent,Vector3(-0.4,0.9,1.41),Vector3(1.0,1.6,0.03),Color("2a2e29"))
	models.tube(parent,Vector3(2.0,0,-1.5),Vector3(2.0,4.6,-1.5),0.05,P.STEEL)
	models.tube(parent,Vector3(2.0,4.6,-1.5),Vector3(2.0,5.6,-1.5),0.015,P.STEEL)
	for side in [-1,1]:models.tube(parent,Vector3(2.0,3.4,-1.5),Vector3(2.0+side*0.4,0.03,-1.5+0.9),0.012,P.STEEL)
	models.box(parent,Vector3(1.5,0.72,0.9),Vector3(1.0,0.06,0.7),Color("6b5a40"))
	models.box(parent,Vector3(1.5,0.76,0.9),Vector3(0.8,0.01,0.5),Color("c8c1a6"))
	for x in [1.1,1.9]:
		for z in [0.62,1.18]:models.box(parent,Vector3(x,0.36,z),Vector3(0.06,0.72,0.06),Color("4b3f2d"))
	for i in 9:models.box(parent,Vector3(-2.2+i*0.5,0.22,-1.85),Vector3(0.46,0.42,0.3),SANDBAG.darkened(0.04*(i%2)))

# Ammunition dump: crate stacks on pallets inside a low sandbag wall, under tarps.
static func _ammo_depot(models,parent:Node3D)->void:
	for row in 2:
		for i in 4:
			var at:=Vector3(-2.1+i*1.4,0,-0.8+row*1.6)
			models.box(parent,at+Vector3(0,0.07,0),Vector3(1.2,0.14,1.1),Color("7a6a50"))
			var height:=0.5+0.3*float((i+row)%3)
			models.box(parent,at+Vector3(0,0.14+height/2,0),Vector3(1.1,height,1.0),Color("4f5a37") if (i+row)%2==0 else Color("5d5238"))
			for j in 2:models.box(parent,at+Vector3(-0.25+j*0.5,0.16+height,0.505),Vector3(0.3,0.04,0.01),Color("c9b46a"))
	models.box(parent,Vector3(-1.4,1.25,-0.8),Vector3(2.9,0.05,1.3),P.CANVAS.darkened(0.15))
	for i in 12:models.box(parent,Vector3(-2.75+i*0.5,0.2,-2.0),Vector3(0.46,0.4,0.3),SANDBAG.darkened(0.04*(i%2)))
	for z in [-1.2,0.0,1.2]:
		for x in [-2.85,2.85]:models.box(parent,Vector3(x,0.2,z),Vector3(0.3,0.4,0.46),SANDBAG)

# Call after batching; repeat from battle sync when build_left changes. No scale
# animation: the complete reserved footprint remains legible throughout work.
static func sync_construction(model:Node3D,u:Dictionary)->void:
	var kind:String=u.kind
	if not FOOTPRINTS.has(kind):return
	var left:float=maxf(0.0,float(u.get("build_left",0.0)))
	var progress:float=clampf(1.0-left/float(BUILD_SECONDS[kind]),0.0,1.0)
	if model.get_meta("construction_progress",-1.0)==progress:return
	model.set_meta("construction_progress",progress)
	if not model.has_meta("field_meshes"):
		model.set_meta("field_meshes",model.find_children("*","MeshInstance3D",true,false))
		for mesh in model.get_meta("field_meshes"):
			mesh.set_meta("completed_material",mesh.material_override)
		var ghost:=StandardMaterial3D.new()
		ghost.albedo_color=Color(0.65,0.68,0.60,0.30)
		ghost.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		ghost.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		model.set_meta("construction_material",ghost)
	for mesh in model.get_meta("field_meshes"):
		mesh.material_override=model.get_meta("construction_material") if left>0 else mesh.get_meta("completed_material")
	var bar:MeshInstance3D=model.get_node_or_null("ConstructionProgress")
	if bar==null:
		bar=MeshInstance3D.new();bar.name="ConstructionProgress"
		var shape:=BoxMesh.new();shape.size=Vector3(1.8,0.10,0.12);bar.mesh=shape
		var paint:=StandardMaterial3D.new();paint.albedo_color=P.MARKING
		paint.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;bar.material_override=paint
		model.add_child(bar)
	bar.visible=left>0
	bar.position=Vector3(-0.9*(1-progress),4.3 if kind=="observation_post" else (1.0 if kind=="tactical_cover" else 3.0),0)
	bar.scale.x=maxf(0.001,progress)
