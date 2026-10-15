extends SceneTree
func _init()->void:call_deferred("run")
func capture(battle,name:String)->void:
	battle.sync_units(0)
	battle.hud.queue_redraw()
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	print("FIELD CAPTURE ",name," ",root.get_texture().get_image().save_png("res://artifacts/field-"+name+".png"))
func run()->void:
	root.size=Vector2i(1440,900)
	preload("res://scripts/simulation.gd").scenario_selection=5
	var battle=load("res://scenes/main.tscn").instantiate();root.add_child(battle);current_scene=battle
	if "--single-shadows" in OS.get_cmdline_user_args():
		for child in battle.get_children():
			if child is DirectionalLight3D:child.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL
	battle.paused=true;battle.show_help=false;battle.effects.muted=true
	var engineer:Dictionary=battle.sim.living(0).filter(func(u):return u.kind=="engineer")[0]
	battle.selected=[engineer.id]
	battle.camera_focus=Vector3(22,0,92);battle.camera_size=48;battle.camera_zoom_target=48;battle.update_camera()
	await capture(battle,"engineer-menu")
	# Isolated actual construction: use the same build/tick APIs, suppress enemy
	# strategic events in this inspection fixture only, no teleporting builders.
	battle.set_process(false);battle.set_physics_process(false)
	battle.sim.field_ops.started=false
	var site:=Vector2(-1,-1)
	for x in range(4,36,3):
		for y in range(82,104,3):
			if battle.sim.FieldOps.can_build(battle.sim,"tactical_cover",Vector2(x,y),engineer.id):site=Vector2(x,y);break
		if site.x>=0:break
	if site.x<0:printerr("FAIL: no native fixture site");quit(1);return
	assert(battle.sim.FieldOps.build(battle.sim,"tactical_cover",site,engineer.id))
	await capture(battle,"construction")
	for i in 1800:
		battle.sim.tick(1.0/30.0);battle.sim.events.clear()
		var structures:Array=battle.sim.units.filter(func(u):return u.get("structure",false))
		if not structures.is_empty() and structures[0].build_left<=0:break
	var finished:Array=battle.sim.units.filter(func(u):return u.get("structure",false) and u.get("build_left",1.0)<=0)
	if finished.is_empty():printerr("FAIL: native construction did not complete");quit(1);return
	await capture(battle,"completed-cover")
	print("FIELD REVIEW COMPLETE")
	quit()
