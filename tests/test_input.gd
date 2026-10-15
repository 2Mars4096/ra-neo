extends SceneTree
var failures:Array[String]=[]
var checks:=0
var battle

func check(value: bool, message: String) -> void:
	checks+=1
	if not value:
		failures.append(message)
		printerr("FAIL: ",message)

func click(p: Vector2, button: int = MOUSE_BUTTON_LEFT, shift: bool = false) -> void:
	var press:=InputEventMouseButton.new()
	press.position=p
	press.button_index=button
	press.pressed=true
	press.shift_pressed=shift
	root.push_input(press)
	var release:=InputEventMouseButton.new()
	release.position=p
	release.button_index=button
	release.shift_pressed=shift
	root.push_input(release)

func key(code: Key, ctrl: bool = false) -> void:
	var event:=InputEventKey.new()
	event.keycode=code
	event.pressed=true
	event.ctrl_pressed=ctrl
	root.push_input(event)
	var release:=InputEventKey.new()
	release.keycode=code
	root.push_input(release)

func _init() -> void:
	preload("res://scripts/simulation.gd").scenario_selection=0
	call_deferred("run")

func run() -> void:
	root.size=Vector2i(1440,900)
	battle=load("res://scenes/main.tscn").instantiate()
	root.add_child(battle)
	current_scene=battle
	await process_frame
	await process_frame
	check(battle.show_help and battle.paused,"briefing starts paused")
	key(KEY_ENTER)
	check(not battle.show_help and not battle.paused,"Enter deploys from briefing")
	key(KEY_SPACE)
	check(battle.paused,"Space pauses")
	var p:Vector2=battle.screen_pos(battle.sim.get_unit(1).pos,0.8)
	click(p)
	check(battle.selected==[1],"world click selects friendly section")
	key(KEY_1,true)
	check(battle.groups.get(1,[])==[1],"Ctrl+1 assigns group")
	key(KEY_TAB)
	check(battle.selected.size()==6,"Tab selects all six starting sections")
	key(KEY_1)
	check(battle.selected==[1],"1 recalls group")
	var destination:Vector2=battle.screen_pos(Vector2(24,46))
	click(destination,MOUSE_BUTTON_RIGHT)
	check(battle.sim.get_unit(1).orders.size()==1,"right click issues move")
	click(battle.screen_pos(Vector2(26,46)),MOUSE_BUTTON_RIGHT,true)
	check(battle.sim.get_unit(1).orders.size()==2,"Shift right click queues move")
	key(KEY_S)
	check(battle.sim.get_unit(1).orders.is_empty(),"S stops section")
	key(KEY_R)
	check(battle.sim.get_unit(1).orders[0].mode=="retreat","R issues withdrawal")
	key(KEY_S)
	key(KEY_A)
	check(battle.attack_mode,"A arms attack-move")
	click(destination)
	check(not battle.sim.get_unit(1).orders.is_empty() and battle.sim.get_unit(1).orders[0].mode=="attack_move","A left click issues attack-move")
	check(not battle.attack_mode,"attack-move mode clears after issue")
	key(KEY_A)
	key(KEY_ESCAPE)
	check(not battle.attack_mode and battle.paused,"Escape cancels attack mode without unpausing")
	battle.selected.clear()
	var start:=Vector2(INF,INF)
	var end:=Vector2(-INF,-INF)
	for id in [1,2,3,4]:
		var projected:Vector2=battle.screen_pos(battle.sim.get_unit(id).pos)
		start=start.min(projected-Vector2(10,10))
		end=end.max(projected+Vector2(10,10))
	var press:=InputEventMouseButton.new()
	press.position=start
	press.button_index=MOUSE_BUTTON_LEFT
	press.pressed=true
	root.push_input(press)
	var release:=InputEventMouseButton.new()
	release.position=end
	release.button_index=MOUSE_BUTTON_LEFT
	root.push_input(release)
	check(battle.selected.size()>=4,"drag box selects ground force")
	battle.sim.result="VICTORY"
	key(KEY_A)
	check(not battle.attack_mode,"terminal screen blocks command hotkeys")
	key(KEY_ENTER)
	await process_frame
	await process_frame
	check(current_scene!=battle,"Enter on terminal screen reloads scene")
	check(current_scene.sim.time==0 and current_scene.sim.result=="" and current_scene.sim.living(0).size()==6,"restart resets mission state")
	# Legacy fields/urban maps are hidden fixtures; test_hud_layout checks the guide lists only playable theatres.
	current_scene.ui_action("scenario:0",Vector2.ZERO)
	await process_frame
	await process_frame
	print("INPUT TESTS: ",checks," checks, ",failures.size()," failures")
	quit(1 if not failures.is_empty() else 0)
