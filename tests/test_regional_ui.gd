extends SceneTree
# Real modal/controller behavior: browsing keeps the existing simulation alive,
# map input cannot issue battlefield orders, and switching is a separate action.
const Sim=preload("res://scripts/simulation.gd")
const Catalog=preload("res://scripts/region_catalog.gd")
var checks:=0
var failures:=0

func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: ",label)

func _init() -> void:
	Sim.scenario_selection=Sim.default_selection()
	call_deferred("run")

func frames() -> void:
	await process_frame
	await process_frame

func run() -> void:
	root.size=Vector2i(1280,720)
	var battle=load("res://scenes/main.tscn").instantiate()
	root.add_child(battle)
	current_scene=battle
	battle.set_process(false)
	battle.set_physics_process(false)
	await frames()
	var sim_id:int=battle.sim.get_instance_id()
	var unit_ids:Array=battle.sim.units.map(func(unit):return unit.id)
	battle.ui_action("region",Vector2.ZERO)
	await frames()
	var atlas=battle.regional_map
	check(battle.region_open() and battle.menu_open(),"regional view participates in modal input/pause gates")
	check(battle.paused and battle.show_help,"browsing from briefing preserves deployment state")
	check(root.disable_3d,"opaque atlas suspends hidden 3D rendering")
	check(atlas.region_buttons.size()==4,"four coherent regional battlefields are listed")
	check(atlas.active_id=="black_sea_harbor" and atlas.selected_id==atlas.active_id,"default Harbor is selected on its regional footprint")
	check(root.gui_get_focus_owner()==atlas.region_buttons.get(atlas.selected_id),"active battlefield button receives keyboard focus")
	check(battle.sim.get_instance_id()==sim_id and battle.sim.units.map(func(unit):return unit.id)==unit_ids,"opening atlas creates no new simulation or force")
	for dimensions in [Vector2i(1120,720),Vector2i(1440,900),Vector2i(1920,1080)]:
		root.size=dimensions
		battle.update_interface_scale()
		await frames()
		var visible:Rect2=Rect2(Vector2.ZERO,atlas.size)
		check(visible.encloses(atlas.canvas.get_global_rect()),"atlas canvas fits %s" % dimensions)
		check(atlas.canvas.size.x>=390 and atlas.canvas.size.y>=290,"atlas retains usable map size at %s" % dimensions)
		check(visible.encloses(atlas.launch.get_global_rect()),"primary action visible at %s" % dimensions)
		for id in atlas.region_buttons:
			check(visible.encloses(atlas.region_buttons[id].get_global_rect()),"keyboard choice %s fits %s" % [id,dimensions])
		for item in atlas.region.battlefields:
			var point:Vector2=Catalog.bounds(item).get_center()
			var screen:Vector2=atlas.canvas.world_to_screen(point)
			check(atlas.canvas.screen_to_world(screen).distance_to(point)<0.01,"map transform is reversible for "+str(item.id))
			check(atlas.canvas.hit_at(screen)==str(item.id),"footprint selects "+str(item.id))
	var anchor:Vector2=atlas.canvas.size*0.5
	atlas.canvas.zoom_at(1.8,anchor)
	check(atlas.canvas.zoom>1,"zoom increases geographic detail")
	check(atlas.canvas.screen_to_world(anchor).distance_to(Catalog.point(atlas.region.size)*0.5)<0.1,"zoom retains the point under the pointer")
	atlas.canvas.pan=Vector2(100000,-100000)
	atlas.canvas.clamp_pan()
	check(atlas.canvas.pan.length()<10000,"pan remains bounded to the region")
	atlas.canvas.reset_view()
	check(atlas.canvas.zoom==1 and atlas.canvas.pan==Vector2.ZERO,"fit region restores full extent")
	var target:="limestone_pass"
	atlas.select_battlefield(target)
	check(atlas.selected_id==target and not atlas.launch.disabled,"selecting an inland operation enables its briefing")
	check(atlas.details_title.text!="" and atlas.summary.text!="" and atlas.features.text!="","selection has terrain, infrastructure and gameplay context")
	check(battle.sim.get_instance_id()==sim_id,"selection alone does not load the next battlefield")
	# Neither backdrop clicks nor selection controls become a move/attack command.
	var before_orders:int=battle.sim.command_serial
	var click:=InputEventMouseButton.new()
	click.button_index=MOUSE_BUTTON_RIGHT;click.pressed=true;click.position=Vector2(200,250)
	battle._input(click)
	check(battle.sim.command_serial==before_orders,"atlas pointer events cannot issue battle orders")
	var escape:=InputEventKey.new()
	escape.keycode=KEY_ESCAPE;escape.pressed=true
	battle._input(escape)
	check(not battle.region_open() and battle.show_help and battle.paused,"Esc returns to the unchanged briefing")
	check(not root.disable_3d,"closing atlas restores battlefield rendering")
	# A running battle pauses for browsing; cancel restores the exact pause state.
	battle.show_help=false;battle.paused=false;battle.sim.time=12.0
	battle.open_region()
	atlas.select_battlefield(target)
	atlas.launch.pressed.emit()
	check(atlas.confirming and atlas.cancel_switch.visible,"switch from a running operation requires an explicit confirmation")
	check(root.gui_get_focus_owner()==atlas.cancel_switch,"confirmation defaults focus to keeping the battle")
	check(battle.sim.time==12.0 and Sim.scenario_selection==Sim.default_selection(),"confirmation does not mutate active operation")
	battle._input(escape)
	check(battle.region_open() and not atlas.confirming,"first Esc cancels switching while retaining the atlas")
	battle._input(escape)
	check(not battle.region_open() and not battle.paused and not battle.show_help,"second Esc restores the running battle")
	battle.paused=true
	battle.open_region();battle.close_region()
	check(battle.paused,"an already paused battle remains paused after browsing")
	# Observe the connected deployment request without replacing this test's scene.
	battle.open_region()
	atlas.battlefield_requested.disconnect(battle.select_region_battlefield)
	var requests:Array=[]
	var record_request:=func(index:int):requests.append(index)
	atlas.battlefield_requested.connect(record_request)
	atlas.select_battlefield(target)
	atlas.launch.pressed.emit()
	atlas.launch.pressed.emit()
	check(requests==[Catalog.scenario_index(atlas.region,target)],"confirmed switch resolves the selected stable scenario index")
	battle.close_region()
	check(Catalog.battlefield(atlas.region,"missing").is_empty() and Catalog.scenario_index(atlas.region,"missing")==-1,"missing metadata cannot become an unintended scenario selection")
	var missing:Dictionary={"battlefields":[{"id":"missing","scenario_id":"black_sea_harbor","map_path":"res://resources/maps/region/absent.json"}]}
	check(Catalog.scenario_index(missing,"missing")==-1,"missing external map cannot deploy a catalog placeholder")
	# Exercise the actual signal -> scene reload -> selected external map flow.
	atlas.battlefield_requested.disconnect(record_request)
	atlas.battlefield_requested.connect(battle.select_region_battlefield)
	var old_instance:int=battle.get_instance_id()
	battle.open_region()
	atlas.select_battlefield(target)
	atlas.launch.pressed.emit()
	atlas.launch.pressed.emit()
	await frames()
	battle=current_scene
	check(battle!=null and battle.get_instance_id()!=old_instance,"confirmed regional deployment replaces the previous battlefield")
	if battle!=null:
		battle.set_process(false);battle.set_physics_process(false)
		check(battle.sim.scenario.id==target and battle.sim.terrain.scenario_id==Sim.scenario_selection,"selected external map and terrain agree after reload")
		check(battle.sim.time==0 and battle.show_help and battle.paused,"new battlefield opens at its fresh deployment briefing")
		var mission:Array=battle.hud.battlefield_ui.mission_lines(battle.sim)
		check(mission[1].contains("reserves") and not mission[1].contains("posts/depots"),"regional mission guidance describes its actual reserves instead of nonexistent logistics targets")
		check(not root.disable_3d and not battle.region_open(),"new battlefield restores normal 3D rendering and closes atlas")
		old_instance=battle.get_instance_id()
		battle.request_restart()
		await frames()
		battle=current_scene
		check(battle!=null and battle.get_instance_id()!=old_instance and battle.sim.scenario.id==target,"restart stays on the chosen regional battlefield")
	if battle!=null:battle.queue_free()
	await frames()
	print("REGIONAL UI: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)
