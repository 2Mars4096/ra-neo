extends SceneTree
var battle
func _init() -> void:
	call_deferred("run")
func capture(name: String) -> void:
	battle.update_fog_pixels()
	battle.fog_texture.update(battle.fog_image)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var status:=root.get_texture().get_image().save_png("res://artifacts/"+name+".png")
	print("RENDER ",name," status=",status)
func run() -> void:
	root.size=Vector2i(1440,900)
	battle=load("res://scenes/main.tscn").instantiate()
	root.add_child(battle)
	current_scene=battle
	battle.effects.muted=true
	await capture("briefing")
	battle.ui_action("begin",Vector2.ZERO)
	battle.paused=true
	battle.selected=[1,2,3,4,5]
	var latency:Array[float]=[]
	for sample in 10:
		var event:=InputEventMouseButton.new()
		event.button_index=MOUSE_BUTTON_RIGHT
		event.pressed=true
		event.position=battle.screen_pos(Vector2(46,22) if sample%2==0 else Vector2(24,44))
		var start:=Time.get_ticks_usec()
		root.push_input(event,true)
		await RenderingServer.frame_post_draw
		latency.append((Time.get_ticks_usec()-start)/1000.0)
	latency.sort()
	FileAccess.open("res://artifacts/input-latency.json",FileAccess.WRITE).store_string(JSON.stringify({"samples":latency,"p95_ms":latency[9],"method":"Synthetic viewport right-click to next completed render; 5 selected sections; warm navigation grids; not physical mouse/display latency"},"  "))
	battle.sim.issue([1,2,3,4],Vector2(46,22),"attack_move")
	battle.sim.issue([5],Vector2(41,24))
	battle.sim.recruit("helo")
	battle.sim.issue([14],Vector2(48,29),"attack_move")
	await capture("orders")
	var recent_shots:Array=[]
	for i in 130:
		battle.sim.tick(0.1)
		for event in battle.sim.events:
			if event.type=="shot" and event.visible:
				recent_shots.append(event.duplicate())
				if recent_shots.size()>3: recent_shots.pop_front()
		battle.sim.events.clear()
	battle.sim.update_visibility()
	battle.camera_focus=Vector3(50,0,31)
	battle.camera_size=57
	battle.update_camera()
	battle.selected=[4]
	battle.sync_units(1)
	await capture("combat")
	battle.sim.events.assign(recent_shots)
	battle.consume_events()
	battle.effects.explosion(Vector3(51,0.7,24))
	await capture("effects")
	battle.sim.result="VICTORY"
	await capture("victory")
	battle.sim.result="DEFEAT"
	await capture("defeat")
	print("RENDER REVIEW COMPLETE")
	quit()
