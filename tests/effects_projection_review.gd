extends SceneTree
func _init()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(800,600)
	var scene:=Node3D.new();root.add_child(scene)
	var camera:=Camera3D.new();scene.add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=30
	camera.position=Vector3(0,15,15);camera.look_at(Vector3.ZERO);camera.current=true
	var effects=preload("res://scripts/effects.gd").new();scene.add_child(effects);effects.muted=true
	await process_frame;await RenderingServer.frame_post_draw
	var before:=root.get_texture().get_image()
	effects.fire("tank",Vector3(-7,1,0),Vector3(7,1,0),true,false,"tank",false)
	for i in 12:
		effects._process(1.0/60.0)
	await process_frame;await RenderingServer.frame_post_draw
	var after:=root.get_texture().get_image()
	after.save_png("res://artifacts/effects-projection.png")
	var changed:=0
	for y in after.get_height():
		for x in after.get_width():
			var a:=after.get_pixel(x,y);var b:=before.get_pixel(x,y)
			if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>0.1:changed+=1
	var passed:=changed>30 and changed<after.get_width()*after.get_height()*0.15
	print("EFFECT PROJECTION: ", "PASS" if passed else "FAIL", " changed pixels=",changed)
	quit(0 if passed else 1)
