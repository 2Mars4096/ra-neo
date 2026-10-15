extends SceneTree
# Normal initial roster: no stress spawning, normal60 FPS cap/default VSync.
# The same harness can run against the saved pre-field-ops snapshot.
func _init()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1440,900)
	root.content_scale_size=Vector2i(1920,1080)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	Engine.max_fps=60
	preload("res://scripts/simulation.gd").scenario_selection=5
	var battle=load("res://scenes/main.tscn").instantiate();root.add_child(battle);current_scene=battle
	if "--single-shadows" in OS.get_cmdline_user_args():
		for child in battle.get_children():
			if child is DirectionalLight3D:child.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL
	battle.camera_focus=Vector3(25,0,84);battle.camera_size=70;battle.camera_zoom_target=70;battle.update_camera()
	battle.paused=false;battle.show_help=false;battle.effects.muted=true
	battle.benchmark=true
	battle.prepare_benchmark_clock.call_deferred()
