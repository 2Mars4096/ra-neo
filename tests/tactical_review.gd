extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
func _init()->void:call_deferred("run")
func run()->void:
	Sim.scenario_selection=3
	root.size=Vector2i(1440,900)
	var battle=load("res://scenes/main.tscn").instantiate()
	root.add_child(battle);current_scene=battle
	battle.effects.muted=true;battle.show_help=false;battle.paused=true
	battle.set_process(false);battle.set_process_input(false);battle.effects.set_process(false)
	battle.sim.issue([1,2,3,4],battle.sim.objectives[0].pos,"attack_move")
	battle.sim.issue([5],Vector2(36,28))
	battle.selected=[1,2,3,4]
	battle.camera_focus=Vector3(32,0,36);battle.camera_size=52
	battle.camera_zoom_target=52;battle.update_camera()
	var observations:Array=[]
	var decisions:Array=[]
	for frame in 1801:
		if frame>0:
			battle.sim.tick(1.0/30.0)
			for event in battle.sim.events:
				if event.type=="decision":decisions.append({"time":battle.sim.time,"unit":event.unit,"phase":event.phase,"reason":event.reason,"destination":[event.pos.x,event.pos.y]})
			battle.consume_events()
			battle.effects._process(1.0/30.0)
		battle.sync_units(1.0/30.0)
		for unit in battle.sim.units:
			if battle.nodes.has(unit.id):preload("res://scripts/unit_animation.gd").pose(battle.nodes[unit.id].get_node("Model"),unit,battle.sim,1.0/30.0)
		if frame in [0,300,750,1350,1800]:
			var snapshot:={"time":battle.sim.time,"units":[]}
			for id in battle.selected:
				var unit:Dictionary=battle.sim.get_unit(id)
				var members:Array=[]
				for actor in unit.members:members.append({"position":[actor.pos.x,actor.pos.y],"posture":actor.get("posture",""),"cover_phase":actor.get("cover_phase",""),"hp":actor.hp})
				snapshot.units.append({"id":id,"position":[unit.pos.x,unit.pos.y],"state":unit.state,"reason":unit.reason,"hp":unit.hp,"members":members})
			observations.append(snapshot)
			battle.update_fog_pixels();battle.fog_texture.update(battle.fog_image)
			battle.weather_fx.sync(battle.sim.weather,battle.sim.time)
			battle.hud.queue_redraw()
			await process_frame;await process_frame;await RenderingServer.frame_post_draw
			var file:="res://artifacts/tactical-review-%02d.png"%roundi(battle.sim.time)
			print("TACTICAL CAPTURE ",file," ",root.get_texture().get_image().save_png(file))
	var file:=FileAccess.open("res://artifacts/tactical-review.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"simulation_hz":30,"render_note":"Paused inspection snapshots from a manually advanced deterministic mission; not a real-time performance test or video.","observations":observations,"decisions":decisions},"  "))
	print("TACTICAL REVIEW COMPLETE")
	quit()
