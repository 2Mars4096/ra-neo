extends SceneTree
# Middle-mouse drag on black_sea_harbor grabs the map: the ground under the
# press point stays under the pointer, the camera moves by exactly that amount,
# and no order, selection change or box-select starts. Release, a lost release
# and a press on the HUD all leave the camera alone.
const Sim=preload("res://scripts/simulation.gd")
var failures:=0
var checks:=0
var battle
var sim

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: ",label)

func harbor_index()->int:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		if configs[i].id=="black_sea_harbor":return i
	return -1

func _init()->void:
	Sim.scenario_selection=harbor_index()
	call_deferred("run")

func button(index:int,pressed:bool,p:Vector2)->void:
	var event:=InputEventMouseButton.new()
	event.button_index=index;event.pressed=pressed;event.position=p
	event.button_mask=MOUSE_BUTTON_MASK_MIDDLE if pressed and index==MOUSE_BUTTON_MIDDLE else 0
	battle._input(event)

func motion(p:Vector2,mask:int=MOUSE_BUTTON_MASK_MIDDLE)->void:
	var event:=InputEventMouseMotion.new()
	event.position=p;event.button_mask=mask
	battle._input(event)

func focus()->Vector2:
	return Vector2(battle.camera_focus.x,battle.camera_focus.z)

func orders_snapshot()->String:
	return var_to_str(sim.units.map(func(u):return [u.id,u.get("orders",[]),u.get("target",-1)]))

func drag(from:Vector2,to:Vector2,label:String)->void:
	var grabbed:Vector2=battle.ground_point(from)
	var expected:Vector2=focus()+grabbed-battle.ground_point(to)
	var orders:=orders_snapshot()
	var chosen:Array=battle.selected.duplicate()
	button(MOUSE_BUTTON_MIDDLE,true,from)
	motion(from.lerp(to,0.4))
	motion(to)
	button(MOUSE_BUTTON_MIDDLE,false,to)
	print("%s zoom=%.0f focus=%s expected=%s grab_error=%.4f m" % [label,battle.camera_size,focus(),expected,battle.ground_point(to).distance_to(grabbed)])
	check(focus().distance_to(expected)<0.01,label+": camera pans by the grabbed ground offset")
	check(battle.ground_point(to).distance_to(grabbed)<0.01,label+": grabbed ground stays under the pointer")
	check(orders_snapshot()==orders,label+": no order issued")
	check(battle.selected==chosen and not battle.dragging,label+": selection untouched, no box select")
	check(not battle.middle_panning,label+": release ends the pan")

func run()->void:
	root.size=Vector2i(1440,900)
	battle=load("res://scenes/main.tscn").instantiate()
	root.add_child(battle)
	current_scene=battle
	battle.set_process(false)
	await process_frame
	await process_frame
	sim=battle.sim
	check(sim.scenario.id=="black_sea_harbor","harbor loaded")
	battle.show_help=false
	battle.selected=battle.all_sections()
	check(not battle.selected.is_empty(),"player sections selected")
	var centre:Vector2=sim.terrain.world_size*0.5
	battle.camera_size=72.0;battle.camera_zoom_target=72.0
	battle.camera_focus=Vector3(centre.x,0,centre.y)
	battle.update_camera()
	var start:=focus()
	drag(Vector2(600,400),Vector2(720,470),"default")
	# Dragging right and down moves the view the other way: the ground follows the pointer.
	var right:=Vector2(battle.camera.global_basis.x.x,battle.camera.global_basis.x.z).normalized()
	check((focus()-start).dot(right)<-5.0,"drag right moves the view left")
	var rest:=focus()
	motion(Vector2(300,300),0)
	check(focus()==rest,"motion after release does not pan")
	battle.paused=true
	battle.camera_size=battle.MAX_ZOOM;battle.camera_zoom_target=battle.MAX_ZOOM
	battle.update_camera()
	drag(Vector2(500,600),Vector2(380,520),"far zoom paused")
	battle.paused=false
	# A lost release (motion without the middle button held) ends the grab.
	rest=focus()
	button(MOUSE_BUTTON_MIDDLE,true,Vector2(600,400))
	motion(Vector2(640,420),0)
	motion(Vector2(700,460))
	check(not battle.middle_panning and focus()==rest,"lost release stops panning")
	# The minimap and panels keep their own clicks: no grab starts there.
	button(MOUSE_BUTTON_MIDDLE,true,battle.hud.minimap.get_center())
	motion(battle.hud.minimap.get_center()+Vector2(20,10))
	button(MOUSE_BUTTON_MIDDLE,false,battle.hud.minimap.get_center()+Vector2(20,10))
	check(focus()==rest,"middle drag on the minimap does not pan")
	battle.show_help=true
	button(MOUSE_BUTTON_MIDDLE,true,Vector2(600,400))
	motion(Vector2(700,460))
	check(focus()==rest,"briefing blocks middle pan")
	button(MOUSE_BUTTON_MIDDLE,false,Vector2(700,460))
	print("MIDDLE PAN: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
