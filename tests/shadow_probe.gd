extends SceneTree
func _init()->void:
	var light:=DirectionalLight3D.new()
	print("DIRECTIONAL MODE ",light.directional_shadow_mode)
	for name in ClassDB.class_get_integer_constant_list("DirectionalLight3D"):
		if "SHADOW" in name:print(name,"=",ClassDB.class_get_integer_constant("DirectionalLight3D",name))
	light.free();quit()
