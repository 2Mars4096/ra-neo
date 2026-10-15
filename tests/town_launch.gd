extends SceneTree
func _init()->void:
	preload("res://scripts/simulation.gd").scenario_selection=5
	call_deferred("launch")
func launch()->void:
	var battle=load("res://scenes/main.tscn").instantiate()
	root.add_child(battle);current_scene=battle
	battle.camera_focus=Vector3(25,0,84);battle.camera_zoom_target=70;battle.camera_size=70;battle.update_camera()
