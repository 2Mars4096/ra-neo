extends SceneTree
func _init()->void:call_deferred("run")
func run()->void:
	preload("res://scripts/simulation.gd").scenario_selection=2
	root.size=Vector2i(1440,900)
	var battle=load("res://scenes/main.tscn").instantiate()
	root.add_child(battle)
	current_scene=battle
	battle.effects.muted=true
	battle.show_help=false
	battle.paused=true
	var squad=battle.sim.spawn("rifle",0,Vector2(46,26))
	battle.selected=[squad.id]
	battle.sim.tick(0.033)
	battle.sync_units(0.033)
	battle.camera_focus=Vector3(46,0,29)
	battle.update_camera()
	battle.update_fog_pixels()
	battle.fog_texture.update(battle.fog_image)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	print("COMBAT REVIEW ",root.get_texture().get_image().save_png("res://artifacts/combat-relationships.png"))
	quit()
