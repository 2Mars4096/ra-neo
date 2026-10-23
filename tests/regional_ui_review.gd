extends SceneTree
# A native-render capture fixture for the same atlas the player opens from the
# deployment briefing. Run with a real display/renderer, never --headless.
const Sim=preload("res://scripts/simulation.gd")

func _init() -> void:
	Sim.scenario_selection=Sim.default_selection()
	call_deferred("run")

func run() -> void:
	root.size=Vector2i(1440,900)
	var battle=load("res://scenes/main.tscn").instantiate()
	root.add_child(battle)
	current_scene=battle
	battle.set_process(false)
	battle.set_physics_process(false)
	battle.open_region()
	battle.regional_map.select_battlefield("limestone_pass")
	battle.regional_map.region_buttons["limestone_pass"].grab_focus()
	for i in 6:await process_frame
	await RenderingServer.frame_post_draw
	var destination:="/tmp/for-every-dawn-region.png"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):destination=arg.trim_prefix("--capture=")
	var image:=root.get_texture().get_image()
	var error:=image.save_png(destination)
	print("REGION REVIEW: ",destination," (",error,")")
	quit(0 if error==OK else 1)
