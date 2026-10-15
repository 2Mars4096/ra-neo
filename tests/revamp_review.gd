extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
func _init()->void:call_deferred("run")
func capture(label:String)->void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var prefix:="metal" if RenderingServer.get_current_rendering_method()=="mobile" else "revamp"
	print("REVAMP CAPTURE ",label," ",root.get_texture().get_image().save_png("res://artifacts/"+prefix+"-"+label+".png"))
func run()->void:
	root.size=Vector2i(1440,900)
	for scenario in [3,4]:
		Sim.scenario_selection=scenario
		var battle=load("res://scenes/main.tscn").instantiate()
		root.add_child(battle);current_scene=battle
		battle.effects.muted=true;battle.show_help=false;battle.paused=true
		battle.camera_focus=Vector3(36,0,36);battle.camera_size=60;battle.camera_zoom_target=battle.camera_size;battle.update_camera()
		battle.selected=[1,2,3,4]
		await capture("tactical" if scenario==3 else "classic")
		battle.camera_focus=Vector3(28,0,32);battle.camera_size=32;battle.camera_zoom_target=battle.camera_size;battle.update_camera()
		await capture("detail-"+str(scenario))
		battle.show_help=true
		await capture("briefing-"+str(scenario))
		battle.queue_free()
		await process_frame
	print("REVAMP REVIEW COMPLETE")
	quit()
