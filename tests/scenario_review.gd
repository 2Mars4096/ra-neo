extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
func _init() -> void:call_deferred("run")
func run() -> void:
	root.size=Vector2i(1440,900)
	for preset in 3:
		Sim.scenario_selection=preset
		var battle=load("res://scenes/main.tscn").instantiate()
		root.add_child(battle)
		current_scene=battle
		battle.effects.muted=true
		battle.show_help=false
		battle.paused=true
		# Authoring survey: reveal terrain for comparison, not a gameplay claim.
		for x in 48:
			for y in 36:
				battle.sim.visible_cells[Vector2i(x,y)]=true
		battle.update_fog_pixels()
		battle.fog_texture.update(battle.fog_image)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		print("SCENARIO RENDER ",root.get_texture().get_image().save_png("res://artifacts/scenario-%d.png" % preset))
		battle.free()
	Sim.scenario_selection=0
	quit()
