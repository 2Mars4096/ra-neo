extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
func _init()->void:call_deferred("run")
func run()->void:
	Sim.scenario_selection=3
	root.size=Vector2i(1440,900)
	var battle=load("res://scenes/main.tscn").instantiate()
	root.add_child(battle)
	current_scene=battle
	battle.effects.muted=true
	battle.show_help=false
	battle.paused=true
	battle.sim.issue([1,2,3,4],battle.sim.objectives[0].pos,"attack_move")
	battle.sim.issue([5],Vector2(36,28))
	battle.selected=[1,2,3,4]
	battle.camera_focus=Vector3(38,0,35)
	battle.camera_size=62
	battle.camera_zoom_target=battle.camera_size;battle.update_camera()
	for frame in 600:
		battle.sim.tick(0.1)
		battle.sync_units(0.1)
		battle.consume_events()
		if frame in [0,80,160,299,599]:
			battle.update_fog_pixels()
			battle.fog_texture.update(battle.fog_image)
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			print("SHOWCASE FRAME ",frame," ",root.get_texture().get_image().save_png("res://artifacts/showcase-%d.png" % frame))
	print("SHOWCASE REVIEW COMPLETE")
	quit()
