extends "res://tests/showcase_launch.gd"
func launch()->void:
	super.launch()
	for child in current_scene.get_children():
		if child is DirectionalLight3D:
			child.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL
			print("SHADOW DIAGNOSTIC: one orthographic map, distance=",child.directional_shadow_max_distance)
