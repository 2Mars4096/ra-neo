extends SceneTree
const Terrain=preload("res://scripts/terrain.gd")
const Visuals=preload("res://scripts/visuals.gd")
const Detail=preload("res://scripts/environment_detail.gd")
const Library=preload("res://scripts/environment_variants.gd")
const Architecture=preload("res://scripts/architectural_block.gd")
var checks:=0
var failures:Array[String]=[]
func _init()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok and not failures.has(label):failures.append(label);printerr("FAIL: ",label)
func run()->void:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	var config:Dictionary=configs[5]
	var terrain=Terrain.new(5)
	var baseline=Terrain.new(5)
	var art=Visuals.new()
	check(Detail.land_use_at(terrain,config,Vector2(12,60)).b>0.8,"farm district distinct")
	check(Detail.land_use_at(terrain,config,Vector2(94,77)).g>0.5,"freight district gravel")
	check(Detail.land_use_at(terrain,config,Vector2(52,32)).r>0.4,"old town soil")
	for road in terrain.roads.segments:
		for i in 11:
			var p:Vector2=road.a.lerp(road.b,i/10.0)
			var c:Color=Detail.land_use_at(terrain,config,p)
			check(c.r+c.g+c.b<0.001,"road center excluded from unsealed treatment")
	var mask:ImageTexture=Detail.land_use_texture(terrain,config)
	check(mask.get_size()==terrain.world_size,"mask follows scenario extent")
	for z in range(0,int(terrain.world_size.y),3):
		for x in range(0,int(terrain.world_size.x),3):
			var p:=Vector2(x+0.5,z+0.5)
			var c:Color=Detail.land_use_at(terrain,config,p)
			check(c.r>=0 and c.r<=1 and c.g>=0 and c.g<=1 and c.b>=0 and c.b<=1,"bounded weights")
			check(terrain.traversable(p,"land",0.8)==baseline.traversable(p,"land",0.8),"navigation unchanged")
			if terrain.is_water(p):check(c.r+c.g+c.b==0,"water excluded")
	var stage:=Node3D.new();root.add_child(stage)
	var integrated:=0
	for i in config.architecture.size():
		var spec:Dictionary=config.architecture[i]
		if spec.design!="warehouse":continue
		var parcel:Rect2=terrain.blocks[i]
		var building:=Node3D.new();stage.add_child(building)
		Architecture.build(art,building,parcel,i,spec)
		var original:Array[AABB]=[]
		for part in building.get_children():original.append(part.transform*part.mesh.get_aabb())
		var rack:Node3D=Library.try_warehouse_rack(art,building,parcel,spec)
		if rack!=null:
			integrated+=1
			var min_y:=INF
			for mesh in rack.get_children():
				for vertex in mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
					var p:Vector3=rack.transform*mesh.transform*vertex
					min_y=minf(min_y,p.y)
					check(parcel.grow(-0.12).has_point(Vector2(p.x,p.z)),"rack wholly in existing blocker")
					for box in original:
						if box.end.y<=0.921:continue # Supporting dock surface.
						check(not box.has_point(p),"rack clears existing wall/door/stock geometry")
			check(absf(min_y-0.92)<0.001,"rack grounded on dock")
			check(Library.try_warehouse_rack(art,building,parcel,spec)==null,"second rack fails closed")
		building.free()
	check(integrated<=2,"bounded warehouse subset")
	# Exercise actual integration / shader resource construction without native rendering.
	art.make_world(stage,terrain)
	check(art.ground_material.get_shader_parameter("land_use_mask")!=null,"actual world binds mask")
	stage.free()
	print("TOWN LAND USE: ",checks," checks, ",failures.size()," failures; racks integrated: ",integrated)
	quit(0 if failures.is_empty() else 1)
