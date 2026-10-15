extends "res://tests/parcel_review.gd"
const City=preload("res://scripts/assets_city.gd")
const Library=preload("res://scripts/asset_library.gd")
const Props=preload("res://scripts/harbor_props.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);printerr("FAIL: ",label)
func _init()->void:call_deferred("run")
func count_meshes(node:Node)->int:
	var n:int=1 if node is MeshInstance3D or node is MultiMeshInstance3D else 0
	for child in node.get_children():n+=count_meshes(child)
	return n
func run()->void:
	var art=preload("res://scripts/visuals.gd").new()
	var stage:=Node3D.new();root.add_child(stage)
	var specs:=City.specs();check(specs.size()==38,"38 city assets")
	var image:=Image.create(1600,1200,false,Image.FORMAT_RGB8);image.fill(Color("34372e"))
	var depth:=PackedFloat32Array();depth.resize(1600*1200);depth.fill(1e9)
	var ids:Array=[]
	for n in specs.size():
		var spec:Dictionary=specs[n];var id:String=spec.kind+"."+spec.variant
		ids.append(id)
		var model:Node3D=Library.build(art,stage,id)
		check(model!=null,"build "+id)
		if model==null:continue
		var f:Array=spec.footprint;var allowed:=Rect2(f[0],f[1],f[2],f[3])
		# Only overhead visuals exceed trunk/rail-leg collision. No blocker grows.
		if spec.kind=="tree":allowed=allowed.grow(3.1)
		elif spec.kind=="lamp":allowed=allowed.grow(1.15)
		elif spec.kind=="portal_crane":allowed=allowed.expand(Vector2(0,10.2))
		var bounds:=Library.render_bounds(model)
		check(allowed.grow(0.05).encloses(Rect2(bounds.position.x,bounds.position.z,bounds.size.x,bounds.size.z)),"horizontal bounds "+id+" "+str(bounds))
		check(bounds.position.y>=-0.05 and bounds.end.y<=float(spec.height)+0.06,"height "+id+" "+str(bounds.end.y))
		check(bounds.size.length()>0.1,"visible "+id)
		check(model.get_meta("local_footprint")==Rect2(f[0],f[1],f[2],f[3]),"collision contract "+id)
		check(model.get_child_count()<=4,"baked material count "+id)
		var scale:float=minf(37.0,160.0/maxf(bounds.size.y,maxf(bounds.size.x,bounds.size.z)))
		var offset:=Vector2((n%8)*200+100,floori(n/8.0)*240+140)
		render(model,image,depth,bounds.get_center(),scale,offset)
		print("CITY REVIEW tile ",n," ",id)
		if id in ["portal_crane.rail","tree.crimean_pine","tree.plane_street","vineyard.trellis_row","pergola.grape","monument.statue","monument.column"]:
			var closeup:=Image.create(720,720,false,Image.FORMAT_RGB8);closeup.fill(Color("34372e"))
			var close_depth:=PackedFloat32Array();close_depth.resize(720*720);close_depth.fill(1e9)
			render(model,closeup,close_depth,bounds.get_center(),minf(65,530/maxf(bounds.size.x,maxf(bounds.size.y,bounds.size.z))),Vector2(360,360))
			check(closeup.save_png("res://artifacts/city-decor-"+spec.variant+".png")==OK,"save closeup "+id)
		model.free()
	check(image.save_png("res://artifacts/city-decor-contact.png")==OK,"save CPU review")
	# Large repeats: metadata remains 400 entries, renderer stays <=20 nodes.
	var placements:Array=[]
	var repeated:=["tree.plane_street","car.boxy_sedan","portal_crane.rail","kiosk.newspaper","water_tower.farm"]
	for i in 400:placements.append({"asset_id":repeated[i%5],"position":[(i%20)*12,floori(i/20.0)*12],"rotation_degrees":(i%4)*90,"elevation":float(i%3)})
	var props:Node3D=Props.build(art,stage,{"map_props":placements})
	check(count_meshes(props)<=20,"400 placements <=20 render nodes")
	check(props.get_meta("placements").size()==400,"placement metadata retained")
	check(Props.build(art,stage,{})==props,"idempotent integration")
	var total:=0
	for batch in props.get_children():
		check(batch is MultiMeshInstance3D,"instanced batch")
		var matching:Array=props.get_meta("placements").filter(func(e):return e.asset_id==batch.get_meta("asset_id"))
		check(batch.multimesh.instance_count==matching.size(),"instance count")
		# Dummy headless RenderingServer cannot read back MultiMesh transforms.
		# Validate retained CPU placement contract; native GPU validation is separate.
		for entry in matching:
			check(entry.transform.origin==Vector3(entry.pos.x,entry.elevation,entry.pos.y),"placement metadata origin")
			check(entry.compiled_bounds==entry.registry_bounds,"placement collision bounds")
		total+=batch.multimesh.instance_count
	print("CITY INSTANCING: 400 placements, ",count_meshes(props)," render nodes, ",total," surface instances")
	# Collision ranges are deliberately unrelated to the architecture count.
	var blocks:Array=[Rect2(10,10,3,3),Rect2(13,10,3,3),Rect2(16,10,3,3)]
	var architecture:Array=[]
	for i in 600:architecture.append({"design":"stone_house","source_size":[8,7],"position":[10+(i%30)*12,10+floori(i/30.0)*12],"rotation_degrees":30,"floors":1,"variant":i%4,"palette":i%4,"damage":0,"seed":i,"district":"test","collision":[0,3]})
	var buildings:Node3D=art.make_harbor_building_chunks(stage,blocks,architecture)
	check(buildings.get_meta("placements").size()==600,"independent architecture, not three collision rectangles")
	check(buildings.get_child_count()>1 and buildings.get_child_count()<=20,"96-unit spatial tiles")
	check(count_meshes(buildings)<180,"600 buildings batched by material/tile")
	for entry in buildings.get_meta("placements"):
		check(entry.transform.origin.is_equal_approx(Vector3(entry.spec.position[0],0,entry.spec.position[1])),"authored center")
	print("CITY BUILDING BATCHES: 600 buildings, ",buildings.get_child_count()," tiles, ",count_meshes(buildings)," meshes")
	buildings.free()
	var legacy:Node3D=art.make_harbor_building_chunks(stage,[Rect2(20,20,10,10)],[{"design":"terrace","facing":"north"}])
	check(legacy.get_meta("placements").size()==1 and count_meshes(legacy)>0,"legacy index paired architecture")
	# Exercise the real world entry point with independent architecture and the
	# current map terrain. Road detail must survive removal of index-paired aprons.
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	var config:Dictionary=configs[6].duplicate(true)
	config["architecture"]=architecture.slice(0,2)
	var terrain=preload("res://scripts/terrain.gd").new(6)
	var world:=Node3D.new();stage.add_child(world)
	art.make_harbor_world(world,terrain,config)
	check(world.get_node("HarborBuildings").get_meta("placements").size()==2,"full world iterates independent architecture")
	check(world.has_node("HarborGroundDetail") and world.get_node("HarborGroundDetail").get_child_count()>0,"new-contract road detail retained")
	stage.free()
	print("ASSETS CITY: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
