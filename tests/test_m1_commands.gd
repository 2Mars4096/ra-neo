extends SceneTree

const Sim=preload("res://scripts/simulation.gd")
var battle
var checks:=0
var failures:=0

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func key(code:Key)->void:
	var event:=InputEventKey.new()
	event.keycode=code;event.pressed=true
	battle._input(event)

func click(at:Vector2,button:int=MOUSE_BUTTON_LEFT)->void:
	var event:=InputEventMouseButton.new()
	event.position=at;event.button_index=button;event.pressed=true
	battle._input(event)

func _init()->void:
	Sim.scenario_selection=Sim.Scenarios.index_for_id("black_sea_harbor")
	call_deferred("run")

func check_fire_feedback(u:Dictionary)->void:
	var sim=battle.sim
	var peer:Dictionary=sim.living(0).filter(func(unit):return unit.kind=="engineer")[0]
	var previous_policy:String=peer.get("fire_policy","free")
	var had_jam:bool=sim.scenario.has("jam_radius")
	var previous_jam:float=sim.scenario.get("jam_radius",0.0)
	var objective:Dictionary=sim.objectives[0]
	var previous_owner:int=objective.owner
	var previous_pos:Vector2=objective.pos
	sim.set_fire_policy([peer.id],"free")
	sim.scenario["jam_radius"]=0.5;objective.owner=1;objective.pos=u.pos
	check(sim.comms_blocked(u) and not sim.comms_blocked(peer),"radio fixture disconnects only one selected infantry section")
	battle.selected=[u.id]
	key(KEY_H)
	check(u.fire_policy=="free","a disconnected section rejects Hold fire")
	check(battle.notices.cursor_text.contains("not received") and battle.notices.cursor_text.contains("radio link lost"),"rejected fire order reports radio loss instead of success")
	battle.selected=[u.id,peer.id]
	key(KEY_H)
	check(u.fire_policy=="free" and peer.fire_policy=="hold","mixed selection applies Hold fire only to its connected section")
	check(battle.notices.cursor_text.contains("Holding fire") and battle.notices.cursor_text.contains("1 / 2") and battle.notices.cursor_text.contains("disconnected"),"partial Hold fire acknowledgement identifies the accepted count and disconnected remainder")
	sim.scenario.jam_radius=0.0;sim.set_fire_policy([u.id,peer.id],"hold");sim.scenario.jam_radius=0.5
	battle.selected=[u.id]
	key(KEY_H)
	check(u.fire_policy=="hold" and battle.notices.cursor_text.contains("not received"),"disconnected Fire at will keeps Hold fire and reports rejection")
	battle.selected=[u.id,peer.id]
	key(KEY_H)
	check(u.fire_policy=="hold" and peer.fire_policy=="free","mixed selection releases fire only for its connected section")
	check(battle.notices.cursor_text.contains("Fire at will") and battle.notices.cursor_text.contains("1 / 2") and battle.notices.cursor_text.contains("disconnected"),"partial Fire at will acknowledgement does not claim every section received it")
	if had_jam:sim.scenario.jam_radius=previous_jam
	else:sim.scenario.erase("jam_radius")
	objective.owner=previous_owner;objective.pos=previous_pos
	sim.set_fire_policy([u.id],"free");sim.set_fire_policy([peer.id],previous_policy)
	battle.selected=[u.id]

func run()->void:
	root.size=Vector2i(1280,800)
	battle=load("res://scenes/main.tscn").instantiate()
	battle.settings_path="user://m1-command-settings.cfg"
	root.add_child(battle);current_scene=battle
	battle.set_process(false);battle.set_physics_process(false)
	battle.close_region();battle.show_help=false;battle.paused=true
	var sim=battle.sim
	var u:Dictionary=sim.living(0).filter(func(unit):return unit.kind=="rifle")[0]
	battle.selected=[u.id]
	battle.camera_focus=Vector3(u.pos.x,0,u.pos.y)
	battle.camera_size=42;battle.camera_zoom_target=42;battle.update_camera()
	battle.hud.queue_redraw()
	await process_frame;await process_frame
	var before:Dictionary=u.assignment.duplicate(true)
	var inventory:int=sim.Throwables.total(u,"smoke")
	key(KEY_G)
	check(battle.tactical_mode=="frag" and not battle.attack_mode and battle.build_mode=="","G arms fragmentation targeting exclusively")
	key(KEY_V)
	check(battle.tactical_mode=="smoke","V switches the pending payload without issuing an order")
	key(KEY_ESCAPE)
	check(battle.tactical_mode.is_empty() and battle.paused,"Esc cancels targeting without changing pause")
	check(u.assignment==before and sim.Throwables.total(u,"smoke")==inventory,"cancel leaves current assignment and inventory unchanged")
	key(KEY_D)
	click(battle.hud.minimap.get_center(),MOUSE_BUTTON_RIGHT)
	check(battle.tactical_mode.is_empty() and u.assignment==before,"right-click minimap cancels digging without moving the section")
	key(KEY_V);key(KEY_A)
	check(battle.tactical_mode.is_empty() and battle.attack_mode,"ordinary attack targeting supersedes smoke")
	key(KEY_V);key(KEY_S)
	check(battle.tactical_mode.is_empty() and u.hold_command,"Hold clears new targeting and remains authoritative")
	key(KEY_H)
	check(u.fire_policy=="hold","H grants a visible hold-fire policy")
	check(battle.notices.cursor_text=="Holding fire","connected Hold fire keeps its successful acknowledgement")
	key(KEY_H)
	check(u.fire_policy=="free","H toggles firing permission back")
	check(battle.notices.cursor_text=="Fire at will","connected Fire at will keeps its successful acknowledgement")
	check_fire_feedback(u)
	battle.ui_action("tactical:reserve",Vector2.ZERO)
	check(u.reserve_enabled,"Reserve is explicitly delegated through the command strip")
	key(KEY_S)
	check(not u.reserve_enabled,"a subsequent Hold revokes reserve delegation")
	check(u.throw_policy=="manual","grenade autonomy starts undelegated")
	battle.ui_action("tactical:auto_frag",Vector2.ZERO)
	check(u.throw_policy=="defensive","Auto frag grants a deliberate bounded defensive policy")
	battle.ui_action("tactical:auto_frag",Vector2.ZERO)
	check(u.throw_policy=="manual","Auto frag toggle returns to manual control")
	var found:=Vector2.INF
	var other_thrower:Dictionary={}
	for distance in [10.0,14.0,17.0]:
		for direction in 24:
			var point:Vector2=u.pos+Vector2.from_angle(direction*TAU/24)*distance
			var screen:Vector2=battle.screen_pos(point)
			if not battle.hud.battlefield_rect().has_point(screen) or battle.hud.action_at(screen)!="":continue
			if not sim.Throwables.preview(sim,u,"smoke",battle.world_pos(screen)).ok:continue
			for candidate in sim.living(0):
				if candidate.id!=u.id and sim.Throwables.preview(sim,candidate,"smoke",battle.world_pos(screen)).ok:
					other_thrower=candidate;break
			if not other_thrower.is_empty():found=screen;break
		if found.is_finite():break
	check(found.is_finite(),"authored Harbor has a visible smoke aim point usable by two selected sections")
	if found.is_finite():
		battle.selected=[u.id,other_thrower.id]
		var other_assignment:Dictionary=other_thrower.assignment.duplicate(true)
		var other_stock:int=sim.Throwables.total(other_thrower,"smoke")
		var funds:float=sim.credits
		var count:int=sim.units.size()
		key(KEY_V);click(found)
		check(battle.tactical_mode.is_empty() and not battle.dragging,"accepted click exits targeting without starting selection drag")
		check(sim.throwables.preparations.size()==1,"ordinary UI input starts exactly one throw preparation")
		check(sim.throwables.preparations[0].unit==u.id and other_thrower.assignment==other_assignment and sim.Throwables.total(other_thrower,"smoke")==other_stock,"mixed UI targeting uses the previewed section and leaves the other section's orders and stock intact")
		check(sim.credits==funds and sim.units.size()==count,"grenade input cannot purchase structures or units")
		check(sim.Throwables.total(u,"smoke")==inventory,"UI preparation reserves but does not prematurely spend a grenade")
		key(KEY_S)
		sim.tick(1.0/30.0)
		check(sim.throwables.preparations.is_empty() and sim.Throwables.total(u,"smoke")==inventory,"new Hold cancels preparation without losing inventory")
	battle.selected=[u.id]
	key(KEY_B)
	check(sim.SupportRequests.request_for(sim,u).get("phase","")=="requested","B creates a real request rather than spawning reinforcements")
	var request:Dictionary=sim.SupportRequests.request_for(sim,u)
	check(battle.TacticalInterface.status(sim,u)==request.reason,"selected requester shows its active backup request after the acknowledgement")
	var requests:int=sim.support_requests.requests.size()
	key(KEY_B)
	check(sim.support_requests.requests.size()==requests,"repeat backup input merges with the existing request")
	key(KEY_S)
	check(request.phase in sim.SupportRequests.TERMINAL,"an accepted new Hold cancels the request through ordinary input")
	check(battle.TacticalInterface.status(sim,u)!=request.reason,"terminal backup history cannot replace the requester's current selection status")
	battle.show_help=true
	key(KEY_G);battle.ui_action("tactical:dig",Vector2.ZERO)
	check(battle.tactical_mode.is_empty(),"guide blocks tactical hotkeys and actions")
	battle.show_help=false
	battle.selected=[]
	key(KEY_V)
	check(battle.tactical_mode.is_empty(),"no selection cannot arm an unusable action")
	battle.selected=[u.id]
	battle.hud.queue_redraw()
	await process_frame;await process_frame
	var buttons:Array=battle.hud.hits.filter(func(hit):return str(hit.id).begins_with("tactical:"))
	check(buttons.size()>=6,"selected infantry expose the compact tactical command strip")
	for button in buttons:
		check(Rect2(Vector2.ZERO,battle.hud.size).encloses(button.rect),"tactical control stays inside minimum-size viewport: "+button.id)
		check(not button.rect.intersects(battle.hud.battlefield_ui.tutorial_rect(battle.hud)),"tactical control does not overlap Field Guide: "+button.id)
	var engineer:Dictionary=sim.living(0).filter(func(unit):return unit.kind=="engineer")[0]
	battle.selected=[u.id,engineer.id]
	battle.hud.battlefield_ui.tutorial_active=true
	battle.hud.battlefield_ui.update(battle.hud)
	battle.hud.queue_redraw()
	await process_frame;await process_frame
	buttons=battle.hud.hits.filter(func(hit):return str(hit.id).begins_with("tactical:"))
	check(buttons.size()==8,"mixed infantry and engineer selection exposes all eight contextual actions")
	for button in buttons:
		check(not button.rect.intersects(battle.hud.battlefield_ui.tutorial_rect(battle.hud)) and not button.rect.intersects(battle.hud.battlefield_ui.roster_rect(battle.hud)),"tactical strip fits above active tutorial and group roster: "+button.id)
	print("M1 COMMANDS: %d checks, %d failures"%[checks,failures])
	battle.queue_free();await process_frame;await process_frame
	quit(1 if failures else 0)
