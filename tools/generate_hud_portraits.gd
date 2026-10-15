extends SceneTree
# Offline-only portrait rendering. Gameplay loads the resulting PNGs once;
# no preview scene or SubViewport runs in a live match.
const KINDS := ["rifle","atgm","tank","drone","helo","boat","aa","harvester","engineer"]
var art=preload("res://scripts/visuals.gd").new()

func _init() -> void:
	call_deferred("run")

func bounds_of(node:Node3D) -> AABB:
	var bounds:=AABB()
	if node is MeshInstance3D:bounds=node.global_transform*node.get_aabb()
	for child in node.get_children():
		if child is Node3D:
			var child_bounds:=bounds_of(child)
			if child_bounds.size!=Vector3.ZERO:bounds=child_bounds if bounds.size==Vector3.ZERO else bounds.merge(child_bounds)
	return bounds

func run() -> void:
	if DisplayServer.get_name()=="headless":
		printerr("HUD portraits require native rendering; headless gameplay uses vector fallback.")
		quit(1)
		return
	root.size=Vector2i(320,192)
	var stage:=Node3D.new()
	root.add_child(stage)
	var environment:=WorldEnvironment.new()
	environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color("202824")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color("d4dfdc")
	environment.environment.ambient_light_energy=0.75
	stage.add_child(environment)
	var key:=DirectionalLight3D.new()
	key.rotation_degrees=Vector3(-45,-38,0)
	key.light_energy=1.4
	key.light_color=Color("fff0d7")
	stage.add_child(key)
	var fill:=DirectionalLight3D.new()
	fill.rotation_degrees=Vector3(-30,130,0)
	fill.light_energy=0.6
	fill.light_color=Color("c8d9e4")
	stage.add_child(fill)
	var camera:=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	stage.add_child(camera)
	camera.current=true
	DirAccess.make_dir_recursive_absolute("res://assets/ui/portraits")
	for kind in KINDS:
		var model:=Node3D.new()
		stage.add_child(model)
		art.models.build(model,kind,0)
		# A close individual figure makes infantry equipment readable in a small slot.
		if kind in ["rifle","atgm","engineer"]:
			for child in model.get_children():
				if child.name.begins_with("Soldier") and child.name!="Soldier0":child.free()
		art.bake_model(model)
		var bounds:=bounds_of(model)
		var focus:=bounds.get_center()
		camera.size=maxf(bounds.size.length()*0.85,1.7)
		camera.position=focus+Vector3(7,5,9)
		camera.look_at(focus)
		var camera_space:=camera.global_transform.affine_inverse()
		var horizontal:=0.0
		var vertical:=0.0
		for corner in 8:
			var local:Vector3=camera_space*bounds.get_endpoint(corner)
			horizontal=maxf(horizontal,absf(local.x))
			vertical=maxf(vertical,absf(local.y))
		camera.size=maxf(vertical*2.0,horizontal*2.0/(320.0/192.0))*1.10
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var error:=root.get_texture().get_image().save_png("res://assets/ui/portraits/"+kind+".png")
		if error!=OK:
			printerr("Portrait save failed: ",kind," error ",error)
			quit(1)
			return
		model.free()
	print("HUD PORTRAITS: generated ",KINDS.size()," original equipment renders")
	quit()
