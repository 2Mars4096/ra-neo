extends SceneTree
# Headless gameplay regression for the Black Sea Harbor field operation (scenario 6).
const Sim=preload("res://scripts/simulation.gd")
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)
func _init()->void:call_deferred("run")

func harbor_index()->int:
	var presets:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for index in presets.size():
		if presets[index].get("id","")=="black_sea_harbor":return index
	return -1

# Same-layer anchors and living soldiers must not overlap a fresh arrival.
func clear_of_others(sim,unit:Dictionary)->bool:
	var d:Dictionary=sim.definitions[unit.kind]
	for other in sim.units:
		if other.id==unit.id or not sim.alive(other) or sim.collision_layer(other)!=sim.collision_layer(unit):continue
		if unit.pos.distance_to(other.pos)<float(d.radius)+float(sim.definitions[other.kind].radius):return false
		if d.domain=="land":
			for member in other.members:
				if member.hp>0 and unit.pos.distance_to(member.pos)<float(d.radius)+float(member.get("body_radius",0.8)):return false
	return true

func buy(sim,kind:String)->Dictionary:
	sim.recruit_clock=0.0
	var before:Array=sim.units.map(func(u):return u.id)
	var funds:float=sim.credits
	var ok:bool=sim.recruit(kind)
	var fresh:Array=sim.units.filter(func(u):return u.id not in before and sim.alive(u))
	check(ok and fresh.size()==1,"%s purchase deploys one unit (%s)" % [kind,sim.field_ops.get("last_purchase_error","")])
	if fresh.is_empty():return {}
	check(is_equal_approx(sim.credits,funds-float(sim.definitions[kind].cost)),"%s purchase charges its cost once" % kind)
	return fresh[0]

func run()->void:
	var index:=harbor_index()
	check(index==6,"black_sea_harbor is scenario 6")
	check(Sim.default_selection()==index and Sim.scenario_selection==index,"simulation defaults to the harbor when its config exists")
	if index<0:
		finish();return
	var config:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))[index]
	var sim=Sim.new(true,index)
	var FieldOps=sim.FieldOps

	# Mode, economy and world.
	check(not sim.field_ops.is_empty() and sim.classic.is_empty(),"harbor runs field operations without classic economy")
	check(is_equal_approx(sim.credits,float(config.get("field_supply",900.0))) and is_equal_approx(float(sim.field_ops.income_rate),float(config.get("field_income",2.0))),"single supply pool follows the authored build-up budget")
	for u in sim.units:check(not (u.kind in sim.Classic.BUILDINGS or u.kind in ["hq","harvester"]),"no classic structure or harvester: "+u.kind)
	check(sim.terrain.world_size==Vector2(1024,768),"world is 1024x768")
	check(is_equal_approx(sim.fog_cell_size(),8.0) and sim.terrain.fog_grid_size==Vector2i(128,96),"fog uses 8 m cells over the full world")
	check(sim.terrain.cell(Vector2(1023.9,767.9))==Vector2i(127,95) and sim.terrain.cell(Vector2.ZERO)==Vector2i.ZERO,"fog cells span the whole world")
	check(sim.terrain.center(Vector2i(127,95)).distance_to(Vector2(1020,764))<0.01,"fog cell centres use the shared terrain helper")

	# Objectives, forces and knowledge.
	check(sim.objectives.size()==3,"three objectives")
	for i in sim.objectives.size():
		check(sim.objectives[i].name==config.sectors[i] and sim.objectives[i].pos==Vector2(config.objectives[i][0],config.objectives[i][1]),"objective %d follows authored sector" % i)
	var player:Array=sim.living(0)
	var enemy:Array=sim.living(1).filter(func(u):return not u.get("prepared",false))
	check(player.size()==config.player_force.size(),"player force spawned: %d / %d" % [player.size(),config.player_force.size()])
	check(enemy.size()==config.enemy_force.size(),"enemy force spawned: %d / %d" % [enemy.size(),config.enemy_force.size()])
	check(sim.living(1).filter(func(u):return u.get("prepared",false)).size()==config.get("enemy_works",[]).size(),"enemy prepared works spawned")
	for record in config.player_force:
		var spot:=Vector2(record.position[0],record.position[1])
		check(player.any(func(u):return u.kind==record.kind and u.pos.distance_to(spot)<12.0),"player %s near authored %s" % [record.kind,spot])
	for domain in ["land","sea","air"]:
		check(player.any(func(u):return sim.definitions[u.kind].domain==domain),"player force includes "+domain)
	var engineer:Dictionary=player.filter(func(u):return u.kind=="engineer")[0]
	var far_enemies:Array=enemy.filter(func(u):return u.pos.distance_to(engineer.pos)>150)
	check(not far_enemies.is_empty() and far_enemies.all(func(u):return not u.visible and not u.seen_by[0]),"distant enemies start hidden")
	check(sim.visible_cells.has(sim.terrain.cell(engineer.pos)),"engineer's own cell is visible")
	check(not sim.visible_cells.has(sim.terrain.cell(sim.field_ops.enemy_insertion)),"enemy insertion starts in fog")
	check(sim.explored.size()<sim.terrain.fog_grid_size.x*sim.terrain.fog_grid_size.y/10,"only the insertion area is explored at start")
	for tile in sim.visible_cells:check(tile.x>=0 and tile.y>=0 and tile.x<128 and tile.y<96,"visible cell inside fog grid")

	# Compiled city: independent architecture entries own contiguous collision
	# rects; every district is reachable by infantry and armour on the streets.
	check(sim.terrain.blocks.size()==config.blocks.size(),"terrain loads every compiled collision rect")
	check(config.building_count==config.architecture.filter(func(a):return a.design!="rock").size(),"building_count counts architecture entries, not rects")
	check(config.architecture.all(func(a):return a.has("collision")),"every architecture entry carries a collision range")
	var start:Vector2=sim.field_ops.insertion
	var district_points:={"centre":Vector2(255,455),"hill ring":Vector2(390,398),"hillside":Vector2(362,690),"port":Vector2(632,440),"microdistrict":Vector2(1010,450),"village":Vector2(800,676),"north side":Vector2(800,150),"reserve":Vector2(990,110),"dacha":Vector2(400,101)}
	for label in district_points:
		var goal:Vector2=district_points[label]
		check(sim.terrain.traversable(goal,"land",sim.definitions.rifle.radius),"%s street point is open ground" % label)
		check(not sim.terrain.path(start,goal,"land",sim.definitions.rifle.radius,[],"infantry").is_empty(),"infantry reach the %s" % label)
	for raw in config.objectives:
		var objective:=Vector2(raw[0],raw[1])
		var goal:Vector2=sim.terrain.reachable_destination(start,objective+Vector2(0,8),"land",sim.definitions.tank.radius,"tracked")
		check(goal.x>=0 and goal.distance_to(objective)<20,"armour can approach objective %s" % objective)

	# Insertions and rally points come from scenario keys.
	check(sim.field_ops.insertion==Vector2(280,680) and sim.field_ops.sea_insertion==Vector2(80,640) and sim.field_ops.enemy_insertion==Vector2(940,120),"insertions follow field_* keys")
	check(sim.terrain.is_water(sim.field_ops.sea_insertion) and not sim.terrain.is_water(sim.field_ops.insertion),"sea insertion on water, land insertion on land")
	var boat:Dictionary=player.filter(func(u):return u.kind=="boat")[0]
	check(sim.rally_point(boat)==Vector2(80,640) and sim.rally_point(engineer)==Vector2(280,680),"player rally uses configured sea and land insertions")
	var enemy_boat:Dictionary=enemy.filter(func(u):return u.kind=="boat")[0]
	check(sim.rally_point(enemy_boat)==enemy_boat.home,"enemy ships without a sea entry rally to their own start")
	check(FieldOps.reserve_target(sim)==sim.objectives[0].pos,"reserve targets the first sector while none are held")
	sim.objectives[2].owner=0
	check(FieldOps.reserve_target(sim)==sim.objectives[2].pos,"reserve targets a sector the player publicly holds")
	sim.objectives[2].owner=1

	# Construction: a visible site near the engineer builds over real ticks.
	var site_pos:=Vector2(-1,-1)
	for ring in range(6,30,2):
		for step in 16:
			var candidate:Vector2=engineer.pos+Vector2.from_angle(step*TAU/16.0)*ring
			if FieldOps.can_build(sim,"tactical_cover",candidate,engineer.id):
				site_pos=candidate;break
		if site_pos.x>=0:break
	check(site_pos.x>=0,"found a visible buildable site near the engineer")
	if site_pos.x>=0:
		var before:float=sim.credits
		check(FieldOps.build(sim,"tactical_cover",site_pos,engineer.id) and is_equal_approx(sim.credits,before-60.0),"engineer starts cover for 60 supply")
		var site:Dictionary=sim.units.filter(func(u):return u.get("structure",false))[-1]
		for i in 1800:
			sim.tick(1.0/30.0)
			if site.build_left<=0 or sim.result!="":break
		check(sim.alive(site) and site.build_left<=0,"cover completes within 60 simulated seconds (left %.2f, engineer %s gap %.2f state %s orders %d paused %s)" % [site.build_left,engineer.pos,engineer.pos.distance_to(site.work_point),engineer.state,engineer.orders.size(),site.build_paused])
		check(sim.terrain.cover(site.pos+Vector2(0,float(sim.definitions.tactical_cover.footprint[1])/2+0.7)),"completed cover protects adjacent ground")

	# Bounded offmap purchases for land, sea and air; each arrival is physically clear.
	# Funded beyond the 900 start so all eight purchase kinds can be exercised once.
	sim.credits=5000.0
	for kind in ["rifle","engineer","tank","boat","drone","helo","aa","atgm"]:
		var unit:=buy(sim,kind)
		if unit.is_empty():continue
		var entry:Vector2=FieldOps.insertion_for(sim,kind)
		check(unit.pos.distance_to(entry)<=12.01,"%s arrives within the bounded entry ring" % kind)
		check(clear_of_others(sim,unit),"%s arrival is clear of every body on its layer" % kind)
		if kind=="boat":check(sim.terrain.is_water(unit.pos),"boat arrives on water")
	sim.recruit_clock=0.0
	var funds:float=sim.credits
	var count:int=sim.units.size()
	var saved_entry:Vector2=sim.field_ops.insertion
	sim.field_ops.insertion=Vector2(60,400)
	check(sim.recruit("rifle") and sim.units.size()==count and FieldOps.queued(sim,"rifle")==1,"blocked land entry waits in the queue without spawning")
	check(sim.field_ops.last_purchase_error=="Landing zone crowded","blocked entry explains the wait")
	check(FieldOps.cancel_queued(sim,"rifle") and is_equal_approx(sim.credits,funds),"waiting purchase can be cancelled for a full refund")
	sim.field_ops.insertion=saved_entry
	sim.credits=10.0
	check(not sim.recruit("tank") and sim.field_ops.last_purchase_error.begins_with("Need "),"insufficient supply refused with reason")
	sim.credits=funds

	# Generalized sector outcome: all three held with no enemy present.
	var outcome=Sim.new(true,index)
	for u in outcome.living(1):u.hp=0.0
	for i in 2:outcome.objectives[i].owner=0;outcome.objectives[i].progress=outcome.capture_time
	outcome.update_objectives(1.0)
	check(outcome.score_hold==0.0,"two of three sectors do not start the hold")
	outcome.objectives[2].owner=0;outcome.objectives[2].progress=outcome.capture_time
	outcome.update_objectives(1.0)
	check(outcome.score_hold>0.0,"all three sectors start the hold")

	await scene_checks(index)
	finish()

func scene_checks(index:int)->void:
	Sim.scenario_selection=index
	root.size=Vector2i(1440,900)
	var battle=load("res://scenes/main.tscn").instantiate();root.add_child(battle);current_scene=battle
	battle.effects.muted=true
	await process_frame;await process_frame
	var sim=battle.sim
	check(battle.MAX_ZOOM==220.0,"huge theatre allows zoom out to 220")
	var engineer:Dictionary=sim.living(0).filter(func(u):return u.kind=="engineer")[0]
	var focus:=Vector2(battle.camera_focus.x,battle.camera_focus.z)
	check(focus.distance_to(engineer.pos)<60.0,"camera opens near the player force: %s vs %s" % [focus,engineer.pos])
	check(battle.fog_image.get_size()==Vector2i(128,96),"fog overlay matches the full-world fog grid")
	# Pan bounds adapt to zoom and world size.
	var margin:Vector2=battle.pan_margin()
	# Every visible battlefield corner stays on the map at both extremes and zooms.
	for zoom in [48.0,72.0,140.0]:
		battle.camera_size=zoom;battle.camera_zoom_target=zoom
		for target in [Vector3(-500,0,-500),Vector3(5000,0,5000),Vector3(-500,0,5000),Vector3(5000,0,-500)]:
			battle.camera_focus=target;battle.update_camera()
			var view:Rect2=battle.view_ground_offsets()
			var seen:=Rect2(Vector2(battle.camera_focus.x,battle.camera_focus.z)+view.position,view.size)
			check(seen.position.x>=-0.05 and seen.position.y>=-0.05 and seen.end.x<=1024.05 and seen.end.y<=768.05,"view stays inside the map at zoom %s toward %s: %s" % [zoom,target,seen])
		battle.camera_focus=Vector3(5000,0,5000);battle.update_camera()
		var far:Rect2=battle.view_ground_offsets()
		check(absf(battle.camera_focus.z+far.end.y-768)<0.05,"pan reaches the south edge exactly at zoom %s" % zoom)
	battle.camera_size=72.0;battle.camera_zoom_target=72.0
	battle.show_help=false;battle.paused=true
	await process_frame
	for i in 80:
		var wheel:=InputEventMouseButton.new()
		wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN;wheel.position=Vector2(500,400);wheel.pressed=true
		battle._input(wheel)
	check(battle.camera_zoom_target==220.0,"wheel reaches the configured far limit")
	battle.camera_size=220.0;battle.camera_zoom_target=220.0
	check(battle.pan_margin().x>margin.x,"pan margin widens when zoomed out")
	battle.camera_size=72.0;battle.camera_zoom_target=72.0;battle.update_camera()
	# HUD: three badges fit the battlefield beside each other; banners avoid them.
	battle.hud.queue_redraw();await process_frame;await process_frame
	for dimensions in [Vector2i(1280,800),Vector2i(1440,900),Vector2i(1920,1080)]:
		root.size=dimensions;battle.hud.size=Vector2(dimensions)
		var badges:Array=battle.hud.objective_badges(sim)
		check(badges.size()==3,"three objective badges at %s" % dimensions)
		for i in badges.size():
			check(battle.hud.battlefield_rect().encloses(badges[i]),"badge %d inside battlefield at %s" % [i,dimensions])
			for j in range(i+1,badges.size()):check(not badges[i].intersects(badges[j]),"badges %d/%d separate at %s" % [i,j,dimensions])
	root.size=Vector2i(1440,900);battle.hud.size=Vector2(1440,900)
	battle.hud.queue_redraw();await process_frame;await process_frame
	var actions:Array=battle.hud.hits.map(func(h):return h.id)
	for kind in sim.Classic.BUILDINGS:check(not ("build:"+kind) in actions,"no classic construction button: "+kind)
	for kind in sim.FieldOps.PURCHASES:check(("buy:"+kind) in actions,"reinforcement tile: "+kind)
	# Guide offers only the current map; older scenarios stay hidden metadata.
	battle.show_help=true
	battle.hud.queue_redraw();await process_frame;await process_frame
	var selectors:Array=battle.hud.hits.filter(func(h):return h.id.begins_with("scenario:")).map(func(h):return h.id)
	check(selectors==["scenario:%d" % index],"guide lists only the harbor: %s" % [selectors])
	check(battle.hud.brief_lines.size()>=1 and " ".join(battle.hud.brief_lines)==sim.scenario.brief,"harbor brief fits the guide")
	battle.queue_free()
	await process_frame

func finish()->void:
	print("HARBOR GAMEPLAY: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
