extends SceneTree
# Native harbor frame benchmark at normal play pacing (60 FPS cap), camera over
# the densest district. Writes artifacts/benchmark.json (battle.write_benchmark).
# Optional user arg: --focus=x,z,zoom  (default old town 340,455,56).
func _init()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1440,900)
	root.content_scale_size=Vector2i(1920,1080)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	Engine.max_fps=60
	var focus:=Vector3(340,0,455);var zoom:=56.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--focus="):
			var parts:=arg.trim_prefix("--focus=").split(",")
			focus=Vector3(float(parts[0]),0,float(parts[1]));zoom=float(parts[2])
	var battle=load("res://scenes/main.tscn").instantiate();root.add_child(battle);current_scene=battle
	if "--single-shadows" in OS.get_cmdline_user_args():
		for child in battle.get_children():
			if child is DirectionalLight3D:child.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL
	battle.camera_focus=focus;battle.camera_size=zoom;battle.camera_zoom_target=zoom;battle.update_camera()
	battle.paused=false;battle.show_help=false;battle.effects.muted=true
	battle.benchmark=true
	battle.prepare_benchmark_clock.call_deferred()
