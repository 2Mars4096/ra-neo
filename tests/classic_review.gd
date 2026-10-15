extends SceneTree
func _init()->void:call_deferred("run")
func run()->void:
	preload("res://scripts/simulation.gd").scenario_selection=4
	root.size=Vector2i(1440,900)
	var battle=load("res://scenes/main.tscn").instantiate();root.add_child(battle);current_scene=battle
	battle.effects.muted=true
	battle.show_help=false;battle.paused=true
	battle.camera_focus=Vector3(24,0,47);battle.camera_size=50;battle.camera_zoom_target=battle.camera_size;battle.update_camera()
	for kind in ["refinery","power","barracks"]:
		var site:Vector2=battle.sim.Classic.find_site(battle.sim,kind,0)
		assert(battle.sim.Classic.build(battle.sim,kind,0,site))
		for i in 140:battle.sim.tick(0.1)
	battle.sim.recruit("rifle")
	battle.selected=[battle.sim.Classic.structures(battle.sim,0,"barracks")[0].id]
	battle.sync_units(0.1);battle.update_fog_pixels();battle.fog_texture.update(battle.fog_image)
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	print("CLASSIC REVIEW ",root.get_texture().get_image().save_png("res://artifacts/classic.png"))
	quit()
