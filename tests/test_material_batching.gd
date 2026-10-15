extends SceneTree
func _init()->void:
	var art=preload("res://scripts/visuals.gd").new()
	var world:=Node3D.new()
	var model:=Node3D.new();world.add_child(model)
	art.models.box(model,Vector3.ZERO,Vector3.ONE,art.models.rubber)
	art.bake_model(model)
	var before:PackedColorArray=model.get_child(0).mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	art.bake_model(world)
	var after:PackedColorArray=model.get_child(0).mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var valid:=before.size()==after.size() and before.size()>0
	for color in after:
		valid=valid and color.is_equal_approx(before[0]) and absf(color.a-0.6)<0.01
	world.free()
	if not valid:printerr("FAIL: repeated batching changed paint/finish")
	print("MATERIAL BATCHING: ","PASS" if valid else "FAIL")
	quit(0 if valid else 1)
