extends SceneTree
func _init()->void:
	preload("res://scripts/simulation.gd").scenario_selection=4
	call_deferred("launch")
func launch()->void:
	var battle=load("res://scenes/main.tscn").instantiate()
	root.add_child(battle)
	current_scene=battle
