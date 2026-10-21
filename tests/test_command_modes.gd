extends SceneTree
# End-to-end input regressions: a legal construction click must become an attack
# after A; cancel must not spend supply or replace orders, even on the minimap.
const Sim=preload("res://scripts/simulation.gd")
var battle
var checks:=0
var failures:=0

func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: ",label)

func _init() -> void:
	var scenarios:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in scenarios.size():
		if scenarios[i].id=="black_sea_harbor":Sim.scenario_selection=i
	call_deferred("run")

func key(code:Key) -> void:
	var event:=InputEventKey.new()
	event.keycode=code;event.pressed=true
	battle._input(event)

func click(p:Vector2,button:int=MOUSE_BUTTON_LEFT,pressed:bool=true) -> void:
	var event:=InputEventMouseButton.new()
	event.button_index=button;event.pressed=pressed;event.position=p
	battle._input(event)

func run() -> void:
	root.size=Vector2i(1440,900)
	battle=load("res://scenes/main.tscn").instantiate()
	battle.settings_path="user://test-command-settings.cfg"
	root.add_child(battle);current_scene=battle
	battle.set_process(false);battle.set_physics_process(false)
	await process_frame;await process_frame
	battle.show_help=false;battle.paused=true
	battle.hud.queue_redraw()
	await process_frame;await process_frame
	var sim=battle.sim
	var engineer:Dictionary=sim.living(0).filter(func(u):return u.kind=="engineer")[0]
	battle.selected=[engineer.id]
	var site:=Vector2(-1,-1)
	for ring in range(4,25):
		for step in 16:
			var point:Vector2=engineer.pos+Vector2.from_angle(step*TAU/16.0)*ring
			var screen:Vector2=battle.screen_pos(point)
			if battle.hud.action_at(screen)!="" or not battle.hud.battlefield_rect().has_point(screen):continue
			if sim.FieldOps.can_build(sim,"observation_post",battle.world_pos(screen),engineer.id):
				site=screen;break
		if site.x>=0:break
	check(site.x>=0,"found legal visible construction site")
	if site.x<0:finish();return
	var funds:float=sim.credits
	var unit_count:int=sim.units.size()
	battle.ui_action("build:observation_post",Vector2.ZERO)
	key(KEY_A)
	check(battle.attack_mode and battle.build_mode=="" and not battle.strike_mode,"A replaces construction with attack targeting")
	click(site)
	check(sim.credits==funds and sim.units.size()==unit_count,"A-click does not accidentally buy an observation post")
	check(not engineer.orders.is_empty() and engineer.orders[0].mode=="attack_move","A-click issues the intended attack-move")
	for mode in ["build:observation_post","attack","strike:fpv"]:
		battle.ui_action(mode,Vector2.ZERO)
		var before:=var_to_str(engineer.orders)
		click(site,MOUSE_BUTTON_RIGHT)
		check(not battle.attack_mode and not battle.strike_mode and battle.build_mode=="",mode+": right-click cancels")
		check(var_to_str(engineer.orders)==before and sim.credits==funds,mode+": cancel does not move or charge")
	# Minimap orders must not bypass the armed-command cancellation gate.
	battle.ui_action("build:observation_post",Vector2.ZERO)
	var before:=var_to_str(engineer.orders)
	click(battle.hud.minimap.get_center(),MOUSE_BUTTON_RIGHT)
	check(battle.build_mode=="" and var_to_str(engineer.orders)==before,"right-click minimap cancels placement without a move")
	battle.ui_action("strike:fpv",Vector2.ZERO)
	battle.ui_action("build:tactical_cover",Vector2.ZERO)
	check(battle.build_mode=="tactical_cover" and not battle.strike_mode and not battle.attack_mode,"field build replaces strike")
	click(site)
	check(battle.build_drag,"linear placement starts a drag")
	key(KEY_A)
	check(battle.attack_mode and not battle.build_drag and not battle.dragging,"A clears unfinished build drag")
	click(site,MOUSE_BUTTON_LEFT,false)
	check(sim.credits==funds and sim.units.size()==unit_count,"late release cannot commit cancelled build drag")
	battle.ui_action("build:tactical_cover",Vector2.ZERO)
	click(site)
	key(KEY_ESCAPE)
	click(site,MOUSE_BUTTON_LEFT,false)
	check(battle.paused and not battle.build_drag and battle.build_mode=="" and sim.credits==funds,"Esc cancels drag without toggling tactical pause")
	battle.ui_action("attack",Vector2.ZERO)
	battle.ui_action("strike:fpv",Vector2.ZERO)
	check(battle.strike_mode and not battle.attack_mode and battle.build_mode=="","strike replaces attack")
	key(KEY_S)
	check(not battle.strike_mode and not battle.attack_mode and battle.build_mode=="","Stop clears targeted command")
	# The opaque top rail / sidebar previously made top and right scrolling impossible.
	battle.window_focused=true;battle.pointer_in_window=true
	var view:=Vector2(1440,900)
	for sample in [[Vector2(700,5),Vector2.UP],[Vector2(1435,450),Vector2.RIGHT],[Vector2(5,450),Vector2.LEFT],[Vector2(700,895),Vector2.DOWN]]:
		check(battle.edge_pan_direction(sample[0],view)==sample[1],"screen edge pans "+str(sample[1]))
	check(battle.edge_pan_direction(Vector2(1435,5),view)==Vector2(1,-1),"screen corner supports diagonal pan")
	check(battle.edge_pan_direction(Vector2(1435,450),view,true)==Vector2.ZERO,"clicking a sidebar control suppresses edge pan")
	check(battle.edge_pan_direction(Vector2(1440,450),view)==Vector2.ZERO,"pointer outside the window does not pan")
	battle.settings.set_value("edge_scroll",false)
	check(battle.edge_pan_direction(Vector2(5,450),view)==Vector2.ZERO,"edge scrolling can be disabled")
	battle.settings.set_value("edge_scroll",true)
	battle.release_pointer()
	check(battle.edge_pan_direction(Vector2(5,450),view)==Vector2.ZERO,"losing window focus stops edge scrolling")
	battle.window_focused=true;battle.pointer_in_window=true
	battle.middle_panning=true
	check(battle.edge_pan_direction(Vector2(5,450),view)==Vector2.ZERO,"map grab suppresses edge pan")
	battle.middle_panning=false
	# Restart is a real modal; neither simulation nor command input can leak through.
	sim.time=5.0;battle.paused=false
	battle.ui_action("restart",Vector2.ZERO)
	check(battle.menu_open() and battle.menu.mode=="restart" and battle.paused,"live restart asks before discarding the match")
	before=var_to_str(engineer.orders)
	key(KEY_A);click(site,MOUSE_BUTTON_RIGHT)
	battle._physics_process(1.0/30.0)
	check(sim.time==5.0 and var_to_str(engineer.orders)==before and not battle.attack_mode,"restart dialog blocks simulation and command input")
	check(battle.edge_pan_direction(Vector2(5,450),view)==Vector2.ZERO,"restart dialog blocks edge scrolling")
	key(KEY_ESCAPE)
	check(not battle.menu_open() and not battle.paused,"cancel restart restores running state")
	battle.paused=true
	battle.request_restart();battle.close_menu()
	check(battle.paused,"cancel restart preserves an existing tactical pause")
	finish()

func finish() -> void:
	print("COMMAND MODES: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
