extends SceneTree
var battle
var failures:=0
func check(ok:bool,label:String)->void:
	if not ok:failures+=1;printerr("FAIL: ",label)
func click(point:Vector2,button:int=MOUSE_BUTTON_LEFT)->void:
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new()
		event.position=point;event.button_index=button;event.pressed=pressed
		root.push_input(event)
func press_button(id:String)->void:
	for hit in battle.hud.hits:
		if hit.id==id:
			click(hit.rect.get_center());return
	check(false,"button exists: "+id)
func _init()->void:call_deferred("run")
func run()->void:
	preload("res://scripts/simulation.gd").scenario_selection=4
	root.size=Vector2i(1440,900)
	battle=load("res://scenes/main.tscn").instantiate();root.add_child(battle);current_scene=battle
	battle.show_help=false;battle.paused=true;battle.effects.muted=true
	battle.camera_focus=Vector3(20,0,45);battle.camera_size=60;battle.update_camera()
	await process_frame;await process_frame
	press_button("build:refinery")
	check(battle.build_mode=="refinery","construction button enters placement")
	var site:Vector2=battle.sim.Classic.find_site(battle.sim,"refinery",0)
	click(battle.screen_pos(site))
	check(battle.sim.Classic.structures(battle.sim,0,"refinery",false).size()==1 and battle.build_mode=="","world click builds and exits placement")
	var hq:Dictionary=battle.sim.Classic.structures(battle.sim,0,"hq")[0]
	battle.selected=[hq.id]
	battle.hud.queue_redraw();await process_frame;await process_frame
	var funds:float=battle.sim.credits
	press_button("buy:harvester")
	check(hq.queue.size()==1 and battle.sim.credits<funds,"production button queues and charges")
	battle.hud.queue_redraw();await process_frame;await process_frame
	press_button("cancel_queue")
	check(hq.queue.is_empty() and is_equal_approx(battle.sim.credits,funds),"cancel button refunds")
	var rally:=Vector2(25,40)
	click(battle.screen_pos(rally),MOUSE_BUTTON_RIGHT)
	check(hq.rally.distance_to(rally)<0.2,"right click sets producer rally")
	print("CLASSIC INPUT: ",failures," failures")
	quit(0 if failures==0 else 1)
