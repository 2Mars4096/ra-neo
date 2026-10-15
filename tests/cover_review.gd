extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
func _init()->void:call_deferred("run")
func run()->void:
	Sim.scenario_selection=3
	root.size=Vector2i(1440,900)
	var battle=load("res://scenes/main.tscn").instantiate()
	root.add_child(battle);current_scene=battle
	battle.effects.muted=true;battle.show_help=false;battle.paused=true
	for node in battle.nodes.values():node.queue_free()
	battle.nodes.clear()
	battle.sim=Sim.new(false,3)
	var squad=battle.sim.spawn("rifle",0,Vector2(17,33))
	var enemy=battle.sim.spawn("rifle",1,Vector2(17,21))
	for actor in enemy.members:actor.cooldown=1000
	battle.selected=[squad.id]
	battle.camera_focus=Vector3(17,0,31);battle.camera_size=40
	battle.camera_zoom_target=battle.camera_size;battle.update_camera()
	for frame in 121:
		battle.sim.tick(0.1);battle.sync_units(0.1);battle.consume_events()
		for unit in battle.sim.units:
			preload("res://scripts/unit_animation.gd").pose(battle.nodes[unit.id].get_node("Model"),unit,battle.sim,0.1)
		if frame in [0,10,30,60,120]:
			battle.update_fog_pixels();battle.fog_texture.update(battle.fog_image)
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			print("COVER FRAME ",frame," ",root.get_texture().get_image().save_png("res://artifacts/cover-%d.png" % frame))
	print("COVER REVIEW COMPLETE");quit()
