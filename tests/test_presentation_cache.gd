extends SceneTree
# Presentation caches must be invisible: incremental fog/minimap repaints equal a
# full repaint, the cached sidebar keeps its hit targets, modal screens still own
# all clicks, and settled joints are not rewritten every frame.
const Sim=preload("res://scripts/simulation.gd")
const FieldOps=preload("res://scripts/field_ops.gd")
class Counter extends Node3D:
	var count:=0
	func _notification(what:int)->void:
		if what==NOTIFICATION_TRANSFORM_CHANGED:count+=1
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)
const REFRESH_ROUNDS:=12
func harbor_index()->int:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		if configs[i].id=="black_sea_harbor":return i
	return -1
func _init()->void:
	Sim.scenario_selection=harbor_index()
	call_deferred("run")

func full_fog(battle)->PackedByteArray:
	var image:Image=battle.fog_image.duplicate()
	for x in battle.sim.terrain.fog_grid_size.x:
		for y in battle.sim.terrain.fog_grid_size.y:image.set_pixel(x,y,battle.fog_color(Vector2i(x,y)))
	return image.get_data()

func full_map(hud,sim)->PackedByteArray:
	var base:PackedColorArray=hud.map_background.colors_for(sim.terrain,hud.minimap_road_cells)
	var columns:int=sim.terrain.fog_grid_size.x
	var image:=Image.create(columns,sim.terrain.fog_grid_size.y,false,Image.FORMAT_RGB8)
	for x in columns:
		for y in sim.terrain.fog_grid_size.y:image.set_pixel(x,y,hud.map_color(sim,base,Vector2i(x,y),columns))
	return image.get_data()

func ids(hud)->Array:
	return hud.hits.map(func(h):return h.id)

func run()->void:
	root.size=Vector2i(1920,1080)
	var battle=load("res://scenes/main.tscn").instantiate();root.add_child(battle);current_scene=battle
	var sim=battle.sim
	var hud=battle.hud
	for i in 6:sim.spawn("rifle",0,Vector2(300+i*5,640))
	for i in 2:sim.spawn("tank",0,Vector2(310+i*8,650))
	for wave in 2:
		sim.time=float(sim.field_ops.get("waves",{}).get("next",sim.scenario.enemy_waves.first))+0.1
		FieldOps.enemy_offensive(sim)
	# Push the player force into unexplored ground so exploration grows.
	var force:Array=sim.living(0).filter(func(u):return not battle.is_structure(u)).map(func(u):return u.id)
	sim.issue(force,Vector2(420,560),"move")
	battle.paused=false;battle.show_help=false;battle.effects.muted=true
	battle.selected=force.slice(0,3)
	battle.camera_focus=Vector3(330,0,630);battle.camera_size=56.0;battle.camera_zoom_target=56.0;battle.update_camera()
	await process_frame;await process_frame
	var fog_ok:=true;var map_ok:=true;var explored_start:int=sim.explored.size()
	# Rounds are bounded by count, each spanning >=7 frames and >=0.2 s of sim
	# time, so a loaded machine (slow frames) runs the same comparisons.
	var rounds:=0
	var sim_started:float=sim.time
	for _round in REFRESH_ROUNDS:
		var round_start:float=sim.time
		for i in 120:
			await process_frame
			if i>=6 and sim.time-round_start>=0.2:break
		battle.refresh_fog_pixels()
		if battle.fog_image.get_data()!=full_fog(battle):fog_ok=false
		hud.update_map_image(sim)
		if hud.map_image.get_data()!=full_map(hud,sim):map_ok=false
		rounds+=1
	check(rounds>10,"several incremental refreshes ran (%d over %.1f s of sim time)" % [rounds,sim.time-sim_started])
	check(sim.explored.size()>explored_start,"exploration grew during the run (%d -> %d)" % [explored_start,sim.explored.size()])
	check(fog_ok,"incremental fog repaint equals full repaint")
	check(map_ok,"incremental minimap repaint equals full repaint")
	# A refresh after a sensor update with nothing new is a no-op (no upload).
	battle.refresh_fog_pixels()
	check(not battle.refresh_fog_pixels(),"unchanged visibility skips the fog upload")
	# Cached sidebar: hit targets of all layers stay available every frame.
	await process_frame;await process_frame
	var visible:Array=ids(hud)
	check("pause" in visible and "restart" in visible,"top console buttons are hit targets")
	check(visible.any(func(id):return id.begins_with("buy:")),"sidebar purchase tiles are hit targets")
	check("attack" in visible and "retreat" in visible,"sidebar order buttons are hit targets")
	# Controlled clock: frozen, so the 20 Hz refresh cannot fire however slow
	# frames are; paused, so live values (supply income) hold still.
	battle.paused=true
	hud.sidebar_clock_msec=Time.get_ticks_msec()
	await process_frame;await process_frame
	var sidebar_draws:=[0]
	var counter:=func():sidebar_draws[0]+=1
	hud.layers[1].draw.connect(counter)
	for i in 6:await process_frame
	check(sidebar_draws[0]<6,"sidebar is not redrawn every frame (%d of 6)" % sidebar_draws[0])
	check(sidebar_draws[0]==0,"unchanged sidebar with no interval elapsed is not redrawn (%d)" % sidebar_draws[0])
	check(ids(hud)==visible,"hit targets persist while the sidebar is cached")
	hud.sidebar_clock_msec+=hud.SIDEBAR_INTERVAL_MSEC
	sidebar_draws[0]=0
	for i in 4:await process_frame
	check(sidebar_draws[0]==1,"live-value refresh fires once per elapsed interval (%d)" % sidebar_draws[0])
	sidebar_draws[0]=0
	battle.selected=[]
	await process_frame;await process_frame
	check("attack" in ids(hud) and sidebar_draws[0]>=1,"selection change redraws the sidebar at once (%d)" % sidebar_draws[0])
	hud.layers[1].draw.disconnect(counter)
	hud.sidebar_clock_msec=-1
	battle.paused=false
	battle.show_help=true
	hud.queue_redraw()
	await process_frame;await process_frame
	var modal:Array=ids(hud)
	check(not modal.is_empty() and modal.all(func(id):return id.begins_with("scenario:") or id in ["begin","tutorial:start"]),"guide owns all hit targets: %s" % [modal])
	check("begin" in modal and "tutorial:start" in modal,"guide offers both free and guided deployment")
	check(hud.action_at(Vector2(1800,500)) in ["blocked"]+modal,"guide blocks the battlefield")
	battle.ui_action("tutorial:start",Vector2.ZERO)
	check(not battle.show_help and hud.battlefield_ui.tutorial_active,"guided deployment closes briefing and opens the field guide")
	await process_frame;await process_frame
	check(ids(hud).any(func(id):return id.begins_with("buy:")),"closing the guide restores sidebar targets")
	# Static structures are not rewritten each frame (a same-value write still
	# re-notifies the subtree and re-sends every mesh transform).
	var structure:Dictionary=sim.spawn("bunker",0,Vector2(296,632))
	structure["build_left"]=0.0
	for i in 12:await process_frame
	check(not structure.is_empty(),"a visible finished structure exists")
	if not structure.is_empty():
		var probe:=Counter.new();probe.set_notify_transform(true)
		battle.nodes[structure.id].get_meta("model").add_child(probe)
		await process_frame;await process_frame
		probe.count=0
		for i in 6:await process_frame
		check(probe.count==0,"static structure subtree gets no transform notifications (%d)" % probe.count)
	print("PRESENTATION CACHE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)
