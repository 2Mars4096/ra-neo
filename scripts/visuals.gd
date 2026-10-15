class_name BattleVisuals
extends RefCounted

var materials: Dictionary = {}
var merged_paint: ShaderMaterial
var ground_material: ShaderMaterial
var architecture_materials:Dictionary={}
const MATERIAL_ATLAS=preload("res://assets/materials/diorama-atlas.png")
const CONSTRUCTION_ATLAS=preload("res://assets/materials/construction-atlas.png")
var asphalt_material:ShaderMaterial

func road_material()->ShaderMaterial:
	if asphalt_material==null:
		asphalt_material=ShaderMaterial.new()
		asphalt_material.shader=preload("res://shaders/road_surface.gdshader")
		asphalt_material.set_shader_parameter("material_atlas",MATERIAL_ATLAS)
	return asphalt_material

var models=preload("res://scripts/unit_models.gd").new()
const BLUE := Color("72dac8")
const RED := Color("ed795b")

func material(color: Color, glow: bool = false) -> StandardMaterial3D:
	var key := color.to_html() + str(glow)
	if materials.has(key):
		return materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	if glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	materials[key] = m
	return m

func box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material(color)
	node.position = pos
	parent.add_child(node)
	return node

func cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, color: Color, top: float = -1.0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top < 0 else top
	mesh.height = height
	mesh.radial_segments = 8
	node.mesh = mesh
	node.material_override = material(color)
	node.position = pos
	parent.add_child(node)
	return node

func ring(parent: Node3D, radius: float, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius-0.055
	mesh.outer_radius = radius+0.055
	mesh.rings = 32
	mesh.ring_segments = 5
	node.mesh = mesh
	node.material_override = material(color, true)
	node.position.y = 0.13
	parent.add_child(node)
	return node

func make_world(parent: Node3D, terrain: BattleTerrain) -> void:
	if terrain.scenario_id==6:
		var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
		if configs.size()>6:make_harbor_world(parent,terrain,configs[6])
		else:push_error("Harbor scenario6 configuration is missing")
		return
	var dimensions:Vector2=terrain.world_size
	var scenario_data:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	box(parent, Vector3(dimensions.x/2,-1.1,dimensions.y/2), Vector3(dimensions.x+16,2,dimensions.y+16), Color("173e4b"))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	for x in terrain.fog_grid_size.x:
		for z in terrain.fog_grid_size.y:
			var p := terrain.center(Vector2i(x,z))
			var color := Color("787d59")
			if terrain.is_water(p):
				color = Color("205668") if x > 43 else Color("2b7180")
			elif x >= 39:
				color = Color("baaf85")
			elif terrain.cover(p):
				color = Color("526a4a")
			elif (z >= 16 and z <= 18) or (x >= 34 and x <= 35):
				color = Color("9a9679")
			color = color.lightened(rng.randf_range(-0.035,0.035))
			var a := Vector3(x*2,0,z*2)
			for v in [a, a+Vector3(0,0,2),a+Vector3(2,0,2),a,a+Vector3(2,0,2),a+Vector3(2,0,0)]:
				st.set_color(color)
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
	var ground := MeshInstance3D.new()
	ground.mesh = st.commit()
	var terrain_shader:=Shader.new()
	terrain_shader.code="""shader_type spatial;
render_mode cull_disabled;
uniform sampler2D material_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform int landscape=0;
uniform sampler2D land_use_mask : filter_linear, repeat_disable;
uniform vec2 land_use_size=vec2(144.0,108.0);
uniform float shore_x=82.0;
uniform float wetness=0.0;
uniform vec4 rubble_region;
uniform vec4 mud_region;
varying vec3 world;
float hash(vec2 p){ return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p){ vec2 i=floor(p);vec2 f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y); }
float lane_distance(vec2 p,vec2 a,vec2 b){vec2 d=b-a;return length(p-a-d*clamp(dot(p-a,d)/dot(d,d),0.0,1.0));}
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;}
void fragment(){
 vec2 p=world.xz;
 float coarse=noise(p*0.23)*0.65+noise(p*0.7)*0.25+noise(p*2.5)*0.1;
 float grain=noise(p*10.0);
 vec3 grass=mix(vec3(0.245,0.265,0.175),vec3(0.38,0.37,0.265),coarse);
 float road=1.0-smoothstep(2.45,3.2,abs(p.y-35.0)+noise(p*0.8)*0.3);
 road=max(road,1.0-smoothstep(1.6,2.15,abs(p.x-69.0)));
 vec3 color=mix(grass,vec3(0.33,0.31,0.255)*(0.85+coarse*0.2),road);
 if(landscape==1 || (landscape==3 && p.x<49.0)){
  float parcel=mod(floor(p.x/13.0)+floor(p.y/18.0),2.0);
  float furrow=smoothstep(0.35,0.6,fract(p.x*0.75));
  color=mix(vec3(0.31,0.29,0.12),vec3(0.46,0.37,0.18),parcel)*(0.86+furrow*0.14+coarse*0.12);
  float lane=1.0-smoothstep(1.5,2.5,abs(p.y-32.0));
  color=mix(color,vec3(0.39,0.34,0.25),lane);
 }
 if(landscape==2 || (landscape==3 && p.x>=49.0)){
  color=vec3(0.22,0.24,0.245)*(0.86+coarse*0.24);
  float street=max(1.0-smoothstep(3.0,4.0,abs(p.x-46.0)),1.0-smoothstep(2.8,3.7,abs(p.y-36.0)));
  color=mix(color,vec3(0.16,0.19,0.205),street);
  float marking=(1.0-smoothstep(0.06,0.14,abs(p.x-46.0)))*step(0.45,fract(p.y/4.0));
  color=mix(color,vec3(0.64,0.62,0.47),marking);
 }
 if(landscape>=3 && landscape!=5){
  float field=hash(floor((p+vec2(noise(p*0.08)*2.0,0.0))/vec2(14.0,19.0)));
  color=mix(vec3(0.31,0.30,0.17),vec3(0.39,0.34,0.22),field)*(0.87+coarse*0.18);
  // Local impact scars and compressed ground break up the cultivated surface.
  float scar=1.0-smoothstep(0.7,1.8,length(p-vec2(54.0,43.0)));
  scar=max(scar,1.0-smoothstep(0.5,1.3,length(p-vec2(60.0,48.0))));
  color=mix(color,vec3(0.16,0.145,0.12),scar*0.7);
  float furrow=sin(p.y*8.0+noise(p*0.12)*0.4);
  color*=0.96+furrow*0.04;
  float yard=step(58.0,p.x)*step(p.x,74.0)*step(37.0,p.y)*step(p.y,54.0);
  color=mix(color,vec3(0.24,0.27,0.28)*(0.9+coarse*0.15),yard);
 }
 if(landscape==5){
  vec3 use=texture(land_use_mask,p/land_use_size).rgb;
  color=grass*(0.94+coarse*0.08);
  // Muted earth and gravel, never the asphalt material or road markings.
  vec3 field=mix(vec3(0.285,0.275,0.175),vec3(0.35,0.30,0.205),coarse);
  float rows=sin(p.y*5.0)*0.025*(1.0-smoothstep(0.12,0.5,length(fwidth(p))));
  color=mix(color,field+vec3(rows),use.b);
  color=mix(color,vec3(0.355,0.315,0.255)*(0.91+coarse*0.17),use.r);
  color=mix(color,vec3(0.335,0.325,0.29)*(0.91+coarse*0.17),use.g);
 }
 float shore=smoothstep(shore_x-5.0,shore_x-1.0,p.x+noise(p*0.5)*1.2);
 color=mix(color,vec3(0.45,0.405,0.295),shore);
 vec2 rd=min(p-rubble_region.xy,rubble_region.xy+rubble_region.zw-p);
 vec2 md=min(p-mud_region.xy,mud_region.xy+mud_region.zw-p);
 float rubble_mask=smoothstep(0.0,1.2,min(rd.x,rd.y)-noise(p*1.4)*0.4);
 float mud_mask=smoothstep(0.0,1.2,min(md.x,md.y)-noise(p*1.1)*0.5);
 color=mix(color,vec3(0.26,0.25,0.21)*(0.8+coarse*0.3),rubble_mask);
 color=mix(color,vec3(0.22,0.18,0.12)*(0.9+coarse*0.2),mud_mask);
 // Gravel flecks fade at distance; broad variation remains at gameplay zoom.
 float detail=1.0-smoothstep(0.08,0.3,length(fwidth(p)));
 float stone=hash(floor(p*6.0));
 color=mix(color,color*0.65+vec3(0.12,0.11,0.09),step(0.82,stone)*detail*0.45);
 color*=0.88+grain*0.20;
 float rut=(1.0-smoothstep(0.07,0.14,abs(abs(p.y-35.0)-1.1)))*0.12;
 if(landscape<3) color*=1.0-rut;
 vec2 tile=1.0-abs(mod(p*0.16,2.0)-1.0);
 vec3 soil=texture(material_atlas,vec2(0.501,0.501)+tile*0.498).rgb;
 color*=mix(vec3(1.08),clamp(soil/vec3(0.437,0.379,0.308),vec3(0.65),vec3(1.35)),0.45);
 color=mix(vec3(dot(color,vec3(0.2126,0.7152,0.0722))),color,0.65);
 ALBEDO=color*(1.0-wetness*0.16);
 ROUGHNESS=mix(0.95,0.48,wetness);
}
"""
	var mat:=ShaderMaterial.new()
	mat.shader=terrain_shader
	mat.set_shader_parameter("material_atlas",MATERIAL_ATLAS)
	mat.set_shader_parameter("landscape",terrain.scenario_id)
	if terrain.scenario_id==5:
		mat.set_shader_parameter("land_use_mask",preload("res://scripts/environment_detail.gd").land_use_texture(terrain,scenario_data[5]))
		mat.set_shader_parameter("land_use_size",terrain.world_size)
	mat.set_shader_parameter("shore_x",terrain.shore_x)
	mat.set_shader_parameter("rubble_region",Vector4(terrain.rubble.position.x,terrain.rubble.position.y,terrain.rubble.size.x,terrain.rubble.size.y))
	mat.set_shader_parameter("mud_region",Vector4(terrain.mud.position.x,terrain.mud.position.y,terrain.mud.size.x,terrain.mud.size.y))
	ground.material_override = mat
	ground_material=mat
	parent.add_child(ground)
	var architecture:Array=scenario_data[terrain.scenario_id].get("architecture",[])
	# A readable, deliberately authored diorama: ridge, warehouse, radar and harbor.
	for i in terrain.blocks.size():
		var r: Rect2 = terrain.blocks[i]
		var middle := r.get_center()
		if i == 0 and terrain.style=="coast":
			for j in 6:
				make_rock(parent,Vector3(middle.x+sin(j*2.0)*0.1,1.15,middle.y+r.size.y*(-0.35+j*0.14)),Vector3(r.size.x*0.78,4.1+(j%3)*0.35,minf(5.8,r.size.y*0.3)),j)
		elif terrain.style=="showcase":
			var building:=Node3D.new()
			parent.add_child(building)
			var spec:Dictionary=architecture[i] if i<architecture.size() else {}
			var ruined:bool=spec.get("design","") in preload("res://scripts/parcel_kit.gd").RUINS if not spec.is_empty() else i%3==1
			if ruined:preload("res://scripts/ruined_building.gd").build(self,building,r,i,spec)
			else:preload("res://scripts/architectural_block.gd").build(self,building,r,i,spec)
			if terrain.scenario_id==5:
				preload("res://scripts/environment_variants.gd").try_warehouse_rack(self,building,r,spec)
			bake_model(building)
		elif terrain.style=="urban" or (terrain.style=="showcase" and middle.x>50):
			box(parent,Vector3(middle.x,1.65,middle.y),Vector3(r.size.x,3.3,r.size.y),Color("777d80"))
			box(parent,Vector3(middle.x,3.32,middle.y),Vector3(r.size.x,0.12,r.size.y),Color("454b50"))
			for side in [-1,1]:
				box(parent,Vector3(middle.x+side*(r.size.x*0.5-0.12),3.5,middle.y),Vector3(0.24,0.3,r.size.y),Color("90938f"))
			for floor_y in [1.1,2.4]:
				for x in range(int(r.position.x)+1,int(r.end.x),2):
					box(parent,Vector3(x,floor_y,r.end.y+0.01),Vector3(0.75,0.65,0.02),Color("243943"))
		else:
			box(parent,Vector3(middle.x,1.3,middle.y),Vector3(r.size.x,2.6,r.size.y),Color("8b8977"))
			var w:=r.size.x/2
			var l:=r.size.y/2
			var roof:=models.shell(parent,[[Vector3(-w,2.6,-l),Vector3(w,2.6,-l),Vector3(w,2.6,l),Vector3(-w,2.6,l)],[Vector3(-0.04,3.5,-l),Vector3(0.04,3.5,-l),Vector3(0.04,3.5,l),Vector3(-0.04,3.5,l)]],Color("4c595a"))
			roof.position=Vector3(middle.x,0,middle.y)
			for z in range(int(r.position.y*2),int(r.end.y*2)):
				for side in [-1.0,1.0]:
					models.tube(parent,Vector3(middle.x+side*w,2.61,z*0.5),Vector3(middle.x,3.52,z*0.5),0.018,Color("78817b"))
			for z in range(int(r.position.y)+1,int(r.end.y),2):
				for side in [-1.0,1.0]:
					box(parent,Vector3(middle.x+side*(w+0.006),1.8,z),Vector3(0.018,0.48,1),Color("314249"))
			box(parent,Vector3(middle.x,1.1,r.end.y+0.008),Vector3(2.6,2.1,0.02),Color("505c5a"))
			for y in range(1,11):
				box(parent,Vector3(middle.x,y*0.19,r.end.y+0.022),Vector3(2.6,0.015,0.018),Color("7b8278"))
	# Instanced vegetation keeps scene and draw overhead bounded.
	var tree_positions: Array[Vector3] = []
	for point in terrain.trees:
		tree_positions.append(Vector3(point.x,0,point.y))
	var fell_lookup:Array=[]
	fell_lookup.resize(tree_positions.size())
	for layer in 8:
		var mesh:Mesh
		if layer==0:
			var trunk:=CylinderMesh.new()
			trunk.radial_segments=7
			trunk.height=2.3
			trunk.bottom_radius=0.15
			trunk.top_radius=0.07
			mesh=trunk
		else:
			mesh=preload("res://scripts/foliage_mesh.gd").cluster(840+layer,layer>=5)
		var multi:=MultiMesh.new()
		multi.transform_format=MultiMesh.TRANSFORM_3D
		multi.use_colors=true
		multi.mesh=mesh
		multi.instance_count=tree_positions.size()
		for i in tree_positions.size():
			var offset:=Vector3.ZERO
			if layer>0: offset=Vector3(sin(i*2.1+layer*2.4)*0.42,2.0+(layer%4)*0.35,cos(i*1.9+layer*2.4)*0.42)
			else: offset.y=1.15
			var scale:=0.9+float(i%4)*0.04
			var placed:=Transform3D(Basis.from_scale(Vector3.ONE*scale),tree_positions[i]+offset)
			multi.set_instance_transform(i,placed)
			multi.set_instance_color(i,Color.WHITE.darkened(float(i%5)*0.025))
			if fell_lookup[i]==null:fell_lookup[i]=[]
			fell_lookup[i].append([multi,i,tree_positions[i],placed])
		var instance:=MultiMeshInstance3D.new()
		instance.multimesh=multi
		instance.material_override=material(Color("514d38") if layer==0 else [Color("303e2c"),Color("43503a"),Color("555b40")][(layer-1)%3])
		instance.material_override.vertex_color_use_as_albedo=true
		if layer>0:instance.material_override.cull_mode=BaseMaterial3D.CULL_DISABLED
		parent.add_child(instance)
	if not tree_positions.is_empty():terrain.tree_felled.connect(Callable(get_script(),"topple_tree").bind(fell_lookup))
	for z in ([41,49] if terrain.port else []):
		box(parent,Vector3(84,0.2,z),Vector3(9,0.5,2.5),Color("9c9d8e"))
	for i in (5 if terrain.port else 0):
		box(parent,Vector3(78,0.7,58+i*2),Vector3(3,1.4,1.4),Color("64777b") if i%2 else Color("b28458"))
	# Animated water uses a single surface; shoreline and navigable water stay separate.
	var water_shader:=Shader.new()
	water_shader.code="""shader_type spatial;
render_mode cull_disabled;
uniform float shore_x=82.0;
varying vec3 world_pos;
void vertex(){ world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment(){
 float wave=sin(world_pos.z*0.9+sin(world_pos.x*0.3)+TIME)*0.55+sin(world_pos.z*1.7-world_pos.x*0.4+TIME*1.3)*0.45;
 float crest=smoothstep(0.62,0.98,wave);
 float coastal=exp(-max(0.0,world_pos.x-shore_x)*0.5);
 ALBEDO=mix(vec3(0.035,0.19,0.23),vec3(0.16,0.40,0.43),coastal)+crest*0.045;
 ROUGHNESS=0.3;
 SPECULAR=0.5;
 NORMAL_MAP=vec3(0.5+wave*0.04,0.5+sin(world_pos.z+TIME)*0.03,1.0);
}
"""
	var water:=MeshInstance3D.new()
	var water_mesh:=PlaneMesh.new()
	water_mesh.size=Vector2(dimensions.x-terrain.shore_x,dimensions.y)
	water.mesh=water_mesh
	water.position=Vector3((dimensions.x+terrain.shore_x)/2,0.025,dimensions.y/2)
	var water_material:=ShaderMaterial.new()
	water_material.shader=water_shader
	water_material.set_shader_parameter("shore_x",terrain.shore_x)
	water.material_override=water_material
	parent.add_child(water)
	# Deployment is conveyed by HUD/order markers; no fixed decorative zone.
	for z in (range(4,70,5) if terrain.style=="coast" else []):
		box(parent,Vector3(69,0.025,z),Vector3(0.12,0.04,1.7),Color("c5bd94"))

	# Low rubble and churned soil are traversable surface treatments; their
	# gameplay regions come from the same terrain definitions.
	for i in 45:
		var x:float=terrain.rubble.position.x+0.3+fmod(i*3.71,terrain.rubble.size.x-0.6)
		var z:float=terrain.rubble.position.y+0.3+fmod(i*2.31,terrain.rubble.size.y-0.6)
		box(parent,Vector3(x,0.025,z),Vector3(0.3+fmod(i*0.17,0.5),0.035,0.24),Color("79776a")).rotation.y=i*0.8
	for i in 8:
		var rut_x:float=terrain.mud.position.x+1+i*2
		for j in int(terrain.mud.size.y):
			var rut_z:float=terrain.mud.position.y+0.5+j
			if terrain.on_road(Vector2(rut_x,rut_z)):continue
			box(parent,Vector3(rut_x,0.017,rut_z),Vector3(0.18,0.008,0.94),Color("34352c"))

	preload("res://scripts/environment_detail.gd").build(self,parent,terrain,architecture)
	make_footpaths(parent,terrain,scenario_data[terrain.scenario_id])
	preload("res://scripts/roadside_props.gd").build(self,parent,terrain)
	bake_model(parent)

func make_unit(parent: Node3D, u: Dictionary) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	var team := BLUE if u.team == 0 else RED
	var body := Color("526c60") if u.team == 0 else Color("8b6955")
	var dark := Color("28383b")
	var model := Node3D.new()
	model.name = "Model"
	root.add_child(model)
	if u.get("structure",false) and preload("res://scripts/field_models.gd").FOOTPRINTS.has(u.kind):
		build_field_model(model,u.kind)
		# Linear works turned during placement; footprint width/depth swap in FieldOps.
		if u.get("rotated",false):model.rotation.y=PI/2
	elif u.kind=="fpv_drone":
		# Small strike quadcopter: the scout airframe at under half size.
		var airframe:=Node3D.new()
		airframe.name="Airframe"
		airframe.scale=Vector3.ONE*0.45
		model.add_child(airframe)
		models.build(airframe,"drone",u.team)
	else:
		models.build(model,u.kind,u.team)
	bake_model(model)
	preload("res://scripts/field_models.gd").sync_construction(model,u)
	var selection := ring(root,2 if u.kind == "boat" else 1.55,team)
	selection.name = "Selection"
	selection.visible = false
	return root

func build_field_model(model:Node3D,kind:String)->void:
	preload("res://scripts/field_models.gd").build(models,model,kind)

func bake_model(model: Node3D) -> void:
	# Unit parts move as one rigid model. Merge by material rather than submit each boot and wheel.
	var batches: Dictionary = {}
	var batch_materials: Dictionary = {}
	for child in model.get_children():
		if child is Node3D and not child is MeshInstance3D:
			bake_model(child)
			continue
		if not child is MeshInstance3D:
			continue
		var source_mesh:Mesh=child.mesh
		var source_material:Material=child.material_override
		if source_material is StandardMaterial3D or (source_material is ShaderMaterial and source_material.get_shader_parameter("paint")!=null and source_material.get_shader_parameter("vertex_paint")!=true):
			var paint:Color=source_material.albedo_color if source_material is StandardMaterial3D else source_material.get_shader_parameter("paint")
			if merged_paint==null:
				merged_paint=ShaderMaterial.new()
				merged_paint.shader=preload("res://shaders/miniature.gdshader")
				merged_paint.set_shader_parameter("vertex_paint",true)
				merged_paint.set_shader_parameter("material_atlas",MATERIAL_ATLAS)
				merged_paint.set_shader_parameter("construction_atlas",CONSTRUCTION_ATLAS)
			paint=paint.srgb_to_linear().lerp(paint,0.25)
			paint.a=0.0 if source_material is StandardMaterial3D else float(source_material.get_shader_parameter("finish"))
			var colored:=ArrayMesh.new()
			for index in source_mesh.get_surface_count():
				var arrays:=source_mesh.surface_get_arrays(index)
				var colors:=PackedColorArray()
				colors.resize(arrays[Mesh.ARRAY_VERTEX].size())
				colors.fill(paint)
				arrays[Mesh.ARRAY_COLOR]=colors
				colored.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			source_mesh=colored
			source_material=merged_paint
		var key: int = source_material.get_instance_id()
		if not batches.has(key):
			var surface:=SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			batches[key]=surface
			batch_materials[key]=source_material
		# Normalize topology before merging: mixing indexed primitives with
		# unindexed authored shells otherwise leaves shell vertices unreferenced.
		var indexed:=SurfaceTool.new()
		indexed.create_from(source_mesh,0)
		indexed.index()
		batches[key].append_from(indexed.commit(),0,child.transform)
		child.free()
	for key in batches:
		var instance:=MeshInstance3D.new()
		instance.mesh=batches[key].commit()
		instance.material_override=batch_materials[key]
		instance.set_meta("fine_shadow",str(model.name) in ["Foot","Knee","Weapon","Gun"] or str(model.name).begins_with("Wheel"))
		model.add_child(instance)

func make_rock(parent:Node3D,pos:Vector3,size:Vector3,seed_value:int) -> void:
	var sphere:=SphereMesh.new()
	sphere.radius=0.5
	sphere.height=1.0
	sphere.radial_segments=11
	sphere.rings=6
	var arrays:=sphere.surface_get_arrays(0)
	var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	var surface:=SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0,indices.size(),3):
		var points:Array[Vector3]=[]
		for j in 3:
			var v:Vector3=vertices[indices[i+j]]
			var irregular:=0.83+0.14*sin(v.dot(Vector3(12.7,8.3,19.1))+seed_value*2.1)
			points.append(v*size*irregular)
		var normal:Vector3=(points[2]-points[0]).cross(points[1]-points[0]).normalized()
		surface.set_normal(normal)
		for point in points:surface.add_vertex(point)
	var node:=MeshInstance3D.new()
	node.mesh=surface.commit()
	node.position=pos
	node.material_override=material(Color("61675d").lightened((seed_value%3)*0.025))
	parent.add_child(node)

func make_showcase_building(parent:Node3D,r:Rect2,index:int) -> void:
	# Six authored families within the existing collision footprint.
	var c:=r.get_center()
	var w:=r.size.x*0.5
	var l:=r.size.y*0.5
	# Service details stay inside the building footprint and its existing collision.
	if index in [3,4]:
		for z in [-0.8,0.8]:
			box(parent,Vector3(c.x+w-0.4,3.6,c.y+z),Vector3(0.55,1.4,0.6),Color("454e48"))
			for bar in 5:box(parent,Vector3(c.x+w-0.11,3.1+bar*0.19,c.y+z),Vector3(0.035,0.035,0.5),Color("767d70"))
	var tall:=index in [1,5]
	var eave:=4.2 if tall else 2.7
	var rise:=1.45 if index!=2 else 0.85
	var plaster:Array[Color]=[Color("8d806a"),Color("747c77"),Color("796953"),Color("70736d"),Color("8c8070"),Color("998d75")]
	var wall:=box(parent,Vector3(c.x,eave/2,c.y),Vector3(r.size.x,eave,r.size.y),plaster[index%6])
	wall.material_override=architecture_material(plaster[index%6],0)
	# Stone footing, lintels and cornice establish construction scale.
	box(parent,Vector3(c.x,0.22,c.y),Vector3(r.size.x,0.44,r.size.y),Color("66695e"))
	box(parent,Vector3(c.x,eave-0.12,c.y),Vector3(r.size.x,0.16,r.size.y),Color("c0b69c"))
	if index in [3,4]:
		# Warehouse sawtooth roofs, distinct from village residences.
		for bay in 3:
			var a:float=-w+bay*r.size.x/3
			var b:float=a+r.size.x/3
			var roof=models.shell(parent,[[Vector3(a,eave,-l),Vector3(b,eave,-l),Vector3(b,eave,l),Vector3(a,eave,l)],[Vector3(a,eave+0.9,-l),Vector3(a+0.12,eave+0.9,-l),Vector3(a+0.12,eave+0.9,l),Vector3(a,eave+0.9,l)]],Color("4e5c60"))
			roof.position=Vector3(c.x,0,c.y)
			roof.material_override=architecture_material(Color("4e5c60"),2)
			box(parent,Vector3(c.x+a+0.01,eave+0.42,c.y),Vector3(0.025,0.6,r.size.y*0.86),Color("32454a"))
		box(parent,Vector3(c.x,1.15,r.end.y+0.025),Vector3(3.1,2.2,0.045),Color("414b49"))
		for row in 10:box(parent,Vector3(c.x,0.2+row*0.2,r.end.y+0.055),Vector3(3.0,0.025,0.025),Color("727973"))
	else:
		# Hipped manor / slate cottage / corrugated barn / tiled townhouse.
		var hip:=1.25 if index in [0,5] else 0.0
		var color:=Color("765543") if index in [0,5] else Color("485354")
		var roof=models.shell(parent,[[Vector3(-w,eave,-l),Vector3(w,eave,-l),Vector3(w,eave,l),Vector3(-w,eave,l)],[Vector3(-0.035,eave+rise,-l+hip),Vector3(0.035,eave+rise,-l+hip),Vector3(0.035,eave+rise,l-hip),Vector3(-0.035,eave+rise,l-hip)]],color)
		roof.position=Vector3(c.x,0,c.y)
		roof.material_override=architecture_material(color,1)
		for row in range(1,8):
			var t:=float(row)/8
			for side in [-1.0,1.0]:
				models.tube(parent,Vector3(c.x+side*w*(1-t),eave+rise*t+0.018,c.y-l+hip*t),Vector3(c.x+side*w*(1-t),eave+rise*t+0.018,c.y+l-hip*t),0.009,color.darkened(0.04))
		models.tube(parent,Vector3(c.x,eave+rise,c.y-l+hip),Vector3(c.x,eave+rise,c.y+l-hip),0.065,color.lightened(0.12))
		box(parent,Vector3(c.x+w*0.46,eave+rise*0.8,c.y+l*0.45),Vector3(0.55,1.5,0.62),Color("685c50"))
		box(parent,Vector3(c.x+w*0.46,eave+rise*0.8+0.76,c.y+l*0.45),Vector3(0.68,0.13,0.74),Color("474c49"))
	for side in [-1.0,1.0]:
		for floor_index in (2 if tall else 1):
			var y:=1.55+floor_index*1.9
			for window_index in range(1,int(r.size.x/1.7)):
				var x:=r.position.x+window_index*1.7
				if index in [3,4] and side>0:continue
				var z:float=c.y+side*l
				box(parent,Vector3(x,y,z+side*0.014),Vector3(0.82,1.04,0.025),Color("b4b09b"))
				box(parent,Vector3(x,y,z+side*0.031),Vector3(0.65,0.86,0.018),Color("263c43"))
				box(parent,Vector3(x,y,z+side*0.045),Vector3(0.045,0.86,0.02),Color("868e81"))
				box(parent,Vector3(x,y-0.49,z+side*0.055),Vector3(0.92,0.09,0.075),Color("b8af98"))
				# Recess shadow and faded shutters add construction depth within clearance padding.
				box(parent,Vector3(x,y+0.56,z+side*0.045),Vector3(0.96,0.12,0.09),Color("777565"))
				if (window_index+index)%3==0:
					for edge in [-1.0,1.0]:
						box(parent,Vector3(x+edge*0.58,y,z+side*0.035),Vector3(0.29,0.94,0.045),Color("505b50"))
		# Downpipes remain inside clearance padding.
		models.tube(parent,Vector3(c.x+w-0.18,0.3,c.y+side*(l+0.025)),Vector3(c.x+w-0.18,eave,c.y+side*(l+0.025)),0.035,Color("4f5957"))
	box(parent,Vector3(c.x-0.7,0.96,r.position.y-0.028),Vector3(0.95,1.9,0.04),Color("414a43"))

func architecture_material(color:Color,kind:int) -> ShaderMaterial:
	var key:=color.to_html()+str(kind)
	if not architecture_materials.has(key):
		var m:=ShaderMaterial.new()
		m.shader=preload("res://shaders/architecture.gdshader")
		m.set_shader_parameter("base_color",color)
		m.set_shader_parameter("surface_kind",kind)
		m.set_shader_parameter("material_atlas",MATERIAL_ATLAS)
		m.set_shader_parameter("construction_atlas",CONSTRUCTION_ATLAS)
		architecture_materials[key]=m
	return architecture_materials[key]

func make_footpaths(parent:Node3D,terrain:BattleTerrain,config:Dictionary)->void:
	# Visual guidance for the authored off-road flank; retains underlying soil/weather costs.
	for route in config.get("footpaths",[]):
		for i in range(1,route.size()):
			var a:=Vector2(route[i-1][0],route[i-1][1]);var b:=Vector2(route[i][0],route[i][1])
			var count:=maxi(1,ceili(a.distance_to(b)))
			for j in count:
				var p:Vector2=a.lerp(b,(j+0.5)/count)
				if terrain.on_road(p) or terrain.blocked(p):continue
				var path=box(parent,Vector3(p.x,0.009,p.y),Vector3(1.25,0.007,a.distance_to(b)/count+0.025),Color("625c47"))
				path.rotation.y=atan2(b.x-a.x,b.y-a.y)

# Harbor-only path: two masked surfaces, per-parcel batches, spatial vegetation
# groups and registry props. No global bake: preserve shared meshes and culling.
func make_harbor_world(parent:Node3D,terrain,config:Dictionary)->void:
	make_harbor_surfaces(parent,terrain,config)
	var architecture:Array=config.get("architecture",[])
	make_harbor_building_chunks(parent,terrain.blocks,architecture)
	# Keep roads/junctions, but suppress legacy index-paired parcel borders for
	# the new layout: its collision rectangles are not independent parcels.
	var legacy_detail:Array=[] if architecture.any(func(spec):return spec.has("collision")) else architecture
	preload("res://scripts/environment_detail.gd").build(self,parent,terrain,legacy_detail)
	for route in config.get("footpaths",[]):
		var path:=Node3D.new();path.name="HarborFootpath";parent.add_child(path)
		make_footpaths(path,terrain,{"footpaths":[route]})
		bake_model(path)
	var compiled=terrain.get("map_props")
	preload("res://scripts/harbor_props.gd").build(self,parent,{"map_props":compiled} if compiled is Array else config)
	make_harbor_trees(parent,terrain.trees,terrain)

# Buildings are authored once, then flattened into spatial/material batches.
# Bounds on each mesh come from its vertices, preserving tile frustum culling.
func make_harbor_building_chunks(parent:Node3D,blocks:Array,architecture:Array)->Node3D:
	var group:=Node3D.new();group.name="HarborBuildings";parent.add_child(group)
	var tiles:Dictionary={};var placements:Array=[]
	var staging:=Node3D.new()
	var count:int=architecture.size() if not architecture.is_empty() else blocks.size()
	for i in count:
		var spec:Dictionary=architecture[i] if i<architecture.size() else {"design":"terrace","facing":"north"}
		var bounds:Rect2
		if spec.has("collision"):
			var size:=Vector2(spec.source_size[0],spec.source_size[1])
			var center:=Vector2(spec.position[0],spec.position[1])
			bounds=Rect2(center-size/2,size)
		elif i<blocks.size():bounds=blocks[i]
		else:continue
		var building:Node3D=make_authored_building(staging,bounds,i,spec)
		var center:Vector2=bounds.get_center()
		var tile:=Vector2i(floori(center.x/96.0),floori(center.y/96.0))
		if not tiles.has(tile):tiles[tile]={"surfaces":{},"materials":{}}
		_harbor_collect_meshes(building,Transform3D.IDENTITY,tiles[tile])
		placements.append({"architecture_index":i,"spec":spec.duplicate(true),"transform":building.transform,"compiled_bounds":bounds})
		building.free()
	staging.free()
	for tile in tiles:
		var chunk:=Node3D.new();chunk.name="Tile_%d_%d"%[tile.x,tile.y];group.add_child(chunk)
		chunk.set_meta("tile",tile)
		for key in tiles[tile].surfaces:
			var mesh:=MeshInstance3D.new()
			mesh.mesh=tiles[tile].surfaces[key].commit()
			mesh.material_override=tiles[tile].materials[key]
			chunk.add_child(mesh)
	group.set_meta("placements",placements)
	return group

func _harbor_collect_meshes(node:Node3D,ancestor:Transform3D,batch:Dictionary)->void:
	var transform:Transform3D=ancestor*node.transform
	if node is MeshInstance3D and node.mesh!=null:
		for index in node.mesh.get_surface_count():
			var mat:Material=node.get_active_material(index)
			var key:int=mat.get_instance_id() if mat!=null else 0
			if not batch.surfaces.has(key):
				var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
				batch.surfaces[key]=surface;batch.materials[key]=mat
			var indexed:=SurfaceTool.new();indexed.create_from(node.mesh,index);indexed.index()
			batch.surfaces[key].append_from(indexed.commit(),0,transform)
	for child in node.get_children():
		if child is Node3D:_harbor_collect_meshes(child,transform,batch)

func make_authored_building(parent:Node3D,bounds:Rect2,index:int,spec:Dictionary)->Node3D:
	var building:=Node3D.new();building.name="Parcel_%d"%index;parent.add_child(building)
	var local_rect:=bounds
	if spec.has("source_size"):
		var size:=Vector2(float(spec.source_size[0]),float(spec.source_size[1]))
		local_rect=Rect2(-size/2,size)
		building.position=Vector3(bounds.get_center().x,0,bounds.get_center().y)
		building.rotation_degrees.y=float(spec.get("rotation_degrees",0.0))
	var ruined:bool=spec.get("design","") in preload("res://scripts/parcel_kit.gd").RUINS
	var city:bool=preload("res://scripts/city_buildings.gd").handles(str(spec.get("design","")))
	if spec.get("design","")=="rock":
		var center:=local_rect.get_center()
		make_rock(building,Vector3(center.x,2.0,center.y),Vector3(local_rect.size.x*0.88,4.0,local_rect.size.y*0.88),index)
	elif city:
		var city_spec:=spec.duplicate();if not city_spec.has("seed"):city_spec["seed"]=index
		preload("res://scripts/city_buildings.gd").build_spec(self,building,city_spec)
	else:
		var prefab:Dictionary=spec.duplicate()
		prefab["facing"]=spec.get("facing","north")
		if ruined:preload("res://scripts/ruined_building.gd").build(self,building,local_rect,index,prefab)
		else:preload("res://scripts/architectural_block.gd").build(self,building,local_rect,index,prefab)
	bake_model(building)
	if spec.has("source_size") and not city:
		# Older prefab details assume an 8m parcel. Preserve their topology in
		# narrow authored plots while keeping every balcony/roof inside bounds.
		var max_x:=0.0;var max_z:=0.0
		for mesh in building.get_children():
			if not mesh is MeshInstance3D:continue
			for surface in mesh.mesh.get_surface_count():
				for vertex in mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
					var point:Vector3=mesh.transform*vertex
					max_x=maxf(max_x,absf(point.x));max_z=maxf(max_z,absf(point.z))
		var fit:=minf(1.0,minf(local_rect.size.x/(2*maxf(max_x,0.001)),local_rect.size.y/(2*maxf(max_z,0.001))))
		if fit<1.0:
			for mesh in building.get_children():
				mesh.scale*=Vector3(fit,1,fit);mesh.position*=Vector3(fit,1,fit)
		building.set_meta("prefab_horizontal_fit",fit)
	building.set_meta("compiled_bounds",bounds)
	return building

func harbor_water_image(terrain,config:Dictionary)->Image:
	# Terrain owns classification/resolution. Never blur the red mask used for
	# clipping; only the separately sampled coast lighting is blended.
	var shared=terrain.get("water_mask")
	if shared is Image and not shared.is_empty():return shared
	var step_size:float=maxf(1.0,float(config.get("nav_cell_size",4.0)))
	var size:=Vector2i((terrain.world_size/step_size).ceil())
	var mask:=Image.create(size.x,size.y,false,Image.FORMAT_R8)
	for y in size.y:
		for x in size.x:
			var p:Vector2=(Vector2(x,y)+Vector2.ONE*0.5)*terrain.world_size/Vector2(size)
			mask.set_pixel(x,y,Color.WHITE if terrain.is_water(p) else Color.BLACK)
	return mask

func make_harbor_surfaces(parent:Node3D,terrain,config:Dictionary)->void:
	var mask:=ImageTexture.create_from_image(harbor_water_image(terrain,config))
	# The legacy semantic painter also pairs blocks by index. District and road
	# paint remains valid; omit its per-parcel aprons for independent buildings.
	var paint_config:Dictionary=config
	if config.get("architecture",[]).any(func(spec):return spec.has("collision")):
		paint_config=config.duplicate();paint_config["architecture"]=[]
	var land_use:=preload("res://scripts/environment_detail.gd").land_use_texture(terrain,paint_config)
	var common:="""shader_type spatial;
uniform sampler2D water_mask : filter_nearest, repeat_disable;
uniform vec2 world_size=vec2(1024.0,768.0);
uniform float wetness=0.0;
varying vec3 world;
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
float wet(vec2 p){return step(0.5,texture(water_mask,clamp(p/world_size,vec2(0.0),vec2(1.0))).r);}
float coast(vec2 p){
 float total=0.0;
 for(int i=1;i<=3;i++){
  float d=float(i*i)*3.0;
  total+=wet(p+vec2(d,0.0))+wet(p-vec2(d,0.0))+wet(p+vec2(0.0,d))+wet(p-vec2(0.0,d));
 }
 return total/12.0;
}
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p);vec2 f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
"""
	var land_code:="""
uniform sampler2D land_use_mask : filter_linear, repeat_disable;
uniform sampler2D material_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
void fragment(){
 vec2 p=world.xz;
 if(wet(p)>0.5){discard;}
 float n=noise(p*0.12)*0.65+noise(p*0.7)*0.35;
 vec3 use=texture(land_use_mask,p/world_size).rgb;
 vec3 color=mix(vec3(0.26,0.28,0.19),vec3(0.38,0.36,0.26),n);
 float detail=1.0-smoothstep(0.15,0.8,length(fwidth(p)));
 float rows=sin(p.y*4.0+noise(p*0.05))*0.022*detail;
 color=mix(color,vec3(0.33,0.29,0.19)*(0.88+n*0.22)+vec3(rows),use.b);
 color=mix(color,vec3(0.34,0.32,0.285)*(0.90+n*0.18),use.r);
 color=mix(color,vec3(0.29,0.30,0.28)*(0.88+n*0.22),use.g);
 color=mix(color,vec3(0.43,0.40,0.32)*(0.90+n*0.15),coast(p)*0.85);
 vec2 tile=1.0-abs(mod(p*0.16,2.0)-1.0);
 vec3 soil=texture(material_atlas,vec2(0.501)+tile*0.498).rgb;
 color*=mix(vec3(1.0),clamp(soil/vec3(0.437,0.379,0.308),vec3(0.7),vec3(1.3)),0.35);
 ALBEDO=color*(1.0-wetness*0.16);ROUGHNESS=mix(0.95,0.48,wetness);
}
"""
	var water_code:="""
void fragment(){
 vec2 p=world.xz;
 if(wet(p)<0.5){discard;}
 float near_land=1.0-coast(p);
 float wave=sin(p.y*0.9+sin(p.x*0.3)+TIME)*0.55+sin(p.y*1.7-p.x*0.4+TIME*1.3)*0.45;
 float crest=smoothstep(0.62,0.98,wave);
 ALBEDO=mix(vec3(0.035,0.12,0.155),vec3(0.13,0.28,0.29),smoothstep(0.0,0.7,near_land))+crest*0.025;
 ROUGHNESS=0.33;SPECULAR=0.5;
 NORMAL_MAP=vec3(0.5+wave*0.035,0.5+sin(p.y+TIME)*0.025,1.0);
}
"""
	for water in [false,true]:
		var surface:=MeshInstance3D.new();surface.name="HarborWater" if water else "HarborLand"
		var plane:=PlaneMesh.new();plane.size=terrain.world_size;surface.mesh=plane
		surface.position=Vector3(terrain.world_size.x/2,0.025 if water else 0.0,terrain.world_size.y/2)
		var shader:=Shader.new();shader.code=common+(water_code if water else land_code)
		var paint:=ShaderMaterial.new();paint.shader=shader
		paint.set_shader_parameter("world_size",terrain.world_size);paint.set_shader_parameter("water_mask",mask)
		if not water:
			paint.set_shader_parameter("land_use_mask",land_use);paint.set_shader_parameter("material_atlas",MATERIAL_ATLAS)
			ground_material=paint
		surface.material_override=paint
		surface.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(surface)

func make_harbor_trees(parent:Node3D,points:Array,terrain:BattleTerrain=null)->void:
	var chunks:Dictionary={}
	var owners:Dictionary={}  # chunk -> index in `points` per instance
	for t in points.size():
		var point:Vector2=points[t]
		var key:=Vector2i((point/128.0).floor())
		if not chunks.has(key):chunks[key]=[];owners[key]=[]
		chunks[key].append(point)
		owners[key].append(t)
	var fell_lookup:Array=[]
	fell_lookup.resize(points.size())
	for layer in 8:
		var mesh:Mesh
		if layer==0:
			var trunk:=CylinderMesh.new();trunk.radial_segments=7;trunk.height=2.3;trunk.bottom_radius=0.15;trunk.top_radius=0.07;mesh=trunk
		else:mesh=preload("res://scripts/foliage_mesh.gd").cluster(840+layer,layer>=5)
		var paint:StandardMaterial3D=material(Color("514d38") if layer==0 else [Color("303e2c"),Color("43503a"),Color("555b40")][(layer-1)%3])
		if layer>0:paint.cull_mode=BaseMaterial3D.CULL_DISABLED
		for key in chunks:
			var multi:=MultiMesh.new();multi.transform_format=MultiMesh.TRANSFORM_3D;multi.mesh=mesh
			multi.instance_count=chunks[key].size()
			var origin:=Vector3(key.x*128.0,0,key.y*128.0)
			for i in chunks[key].size():
				var point:Vector2=chunks[key][i]
				var offset:=Vector3(0,1.15,0) if layer==0 else Vector3(sin(i*2.1+layer*2.4)*0.42,2.0+(layer%4)*0.35,cos(i*1.9+layer*2.4)*0.42)
				var placed:=Transform3D(Basis.from_scale(Vector3.ONE*(0.9+float(i%4)*0.04)),Vector3(point.x,0,point.y)+offset-origin)
				multi.set_instance_transform(i,placed)
				var t:int=owners[key][i]
				if fell_lookup[t]==null:fell_lookup[t]=[]
				fell_lookup[t].append([multi,i,Vector3(point.x,0,point.y)-origin,placed])
			var instance:=MultiMeshInstance3D.new();instance.name="HarborTrees";instance.position=origin
			instance.multimesh=multi;instance.material_override=paint;parent.add_child(instance)
	if terrain!=null and not points.is_empty():terrain.tree_felled.connect(Callable(get_script(),"topple_tree").bind(fell_lookup))

# terrain.tree_felled: lay a felled collision tree's instances (trunk and
# foliage layers) on the ground, pivoting at the trunk base along `heading`.
# Edits existing MultiMesh transforms only, so draw cost stays flat. `lookup`
# holds, per terrain.trees index, [multimesh, instance, trunk base, transform]
# entries; the stored transform is updated (no read-back from the renderer).
static func topple_tree(index:int,heading:Vector2,lookup:Array)->void:
	if index<0 or index>=lookup.size() or lookup[index]==null:return
	var forward:=Vector3(heading.x,0,heading.y).normalized()
	if forward==Vector3.ZERO:forward=Vector3.FORWARD
	var change:=Basis(forward.cross(Vector3.UP).normalized(),-PI*0.47)
	for entry in lookup[index]:
		var multi:MultiMesh=entry[0]
		var ground:Vector3=entry[2]
		var pivot:=Transform3D(Basis.IDENTITY,ground)*Transform3D(change,Vector3.ZERO)*Transform3D(Basis.IDENTITY,-ground)
		entry[3]=pivot*Transform3D(entry[3])
		multi.set_instance_transform(int(entry[1]),entry[3])
	lookup[index]=null
