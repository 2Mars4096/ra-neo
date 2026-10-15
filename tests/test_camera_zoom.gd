extends SceneTree
var failures:Array[String]=[]
var checks:=0
func _init()->void:call_deferred("run")
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message);printerr("FAIL: ",message)
func wheel(battle,button:int,p:Vector2)->void:
	var event:=InputEventMouseButton.new()
	event.button_index=button;event.position=p;event.pressed=true
	battle._input(event)
func run()->void:
	root.size=Vector2i(1440,900)
	var battle=load("res://scenes/main.tscn").instantiate()
	root.add_child(battle)
	battle.set_process(false);battle.set_physics_process(false)
	await process_frame
	var p:=Vector2(600,400)
	wheel(battle,MOUSE_BUTTON_WHEEL_UP,p)
	check(battle.camera_zoom_target==72.0,"briefing blocks zoom")
	battle.show_help=false;battle.paused=true
	await process_frame
	wheel(battle,MOUSE_BUTTON_WHEEL_UP,p)
	check(battle.camera_zoom_target<72.0,"wheel up zooms in while paused")
	var target:float=battle.camera_zoom_target
	battle.advance_zoom(1.0/60.0)
	check(battle.camera_size<72.0 and battle.camera_size>target,"zoom interpolates instead of snapping")
	wheel(battle,MOUSE_BUTTON_WHEEL_DOWN,p)
	check(is_equal_approx(battle.camera_zoom_target,72.0),"wheel down reverses wheel up")
	for i in 80:wheel(battle,MOUSE_BUTTON_WHEEL_UP,p)
	check(battle.camera_zoom_target==battle.MIN_ZOOM,"near limit")
	for i in 80:wheel(battle,MOUSE_BUTTON_WHEEL_DOWN,p)
	check(battle.camera_zoom_target==battle.MAX_ZOOM,"far limit")
	var pinch:=InputEventMagnifyGesture.new()
	pinch.factor=1.2;pinch.position=p;battle._input(pinch)
	check(battle.camera_zoom_target<battle.MAX_ZOOM,"pinch magnifies")
	var old:float=battle.camera_zoom_target
	wheel(battle,MOUSE_BUTTON_WHEEL_UP,battle.hud.minimap.get_center())
	check(battle.camera_zoom_target==old,"minimap scrolling does not zoom or issue orders")
	battle.sim.result="VICTORY"
	wheel(battle,MOUSE_BUTTON_WHEEL_UP,p)
	check(battle.camera_zoom_target==old,"terminal screen blocks zoom")
	battle.request_zoom(NAN)
	check(battle.camera_zoom_target==old,"invalid gesture cannot corrupt camera")
	battle.camera_zoom_target=40; battle.camera_size=72
	for i in 60:battle.advance_zoom(1.0/60.0)
	var sixty:float=battle.camera_size
	battle.camera_size=72
	for i in 30:battle.advance_zoom(1.0/30.0)
	check(is_equal_approx(battle.camera_size,sixty),"smoothing independent of frame rate")
	print("CAMERA ZOOM: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
