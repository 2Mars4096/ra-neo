extends SceneTree
func _init()->void:call_deferred("run")
func capture(name:String)->void:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	print("TOWN CAPTURE ",name," ",root.get_texture().get_image().save_png("res://artifacts/town-"+name+".png"))
func run()->void:
	root.size=Vector2i(1440,900)
	preload("res://scripts/simulation.gd").scenario_selection=5
	var battle=load("res://scenes/main.tscn").instantiate();root.add_child(battle);current_scene=battle
	battle.paused=true;battle.show_help=false;battle.effects.muted=true
	battle.camera_focus=Vector3(25,0,84);battle.camera_size=70;battle.camera_zoom_target=70;battle.update_camera()
	await capture("gameplay")
	# Inspector-only overview: reveal terrain fog for evaluating environment composition.
	battle.set_process(false)
	battle.fog_image.fill(Color(0,0,0,0));battle.fog_texture.update(battle.fog_image)
	battle.camera_focus=Vector3(75,0,54);battle.camera_size=100;battle.camera_zoom_target=100;battle.update_camera()
	await capture("inspection-overview")
	battle.camera_focus=Vector3(64,0,52);battle.camera_size=44;battle.camera_zoom_target=44;battle.update_camera()
	await capture("inspection-street")
	battle.camera_focus=Vector3(111,0,79);battle.camera_size=44;battle.camera_zoom_target=44;battle.update_camera()
	await capture("inspection-yard")
	quit()
