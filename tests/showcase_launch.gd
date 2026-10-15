extends SceneTree
func _init()->void:
	preload("res://scripts/simulation.gd").scenario_selection=3
	call_deferred("launch")
func launch()->void:
	var battle=load("res://scenes/main.tscn").instantiate()
	root.add_child(battle)
	current_scene=battle
	if "--benchmark" in OS.get_cmdline_user_args():battle.sim.time=45.0
