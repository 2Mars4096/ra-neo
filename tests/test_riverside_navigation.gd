extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Classic=preload("res://scripts/classic.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)
func _init()->void:call_deferred("run")
func run()->void:
	var sim=preload("res://tests/fixtures/legacy_riverside.gd").create(true)
	check(sim.scenario.id=="riverside_town","real authored sixth map loaded")
	check(sim.terrain.world_size==Vector2(144,108) and sim.terrain.shore_x==128,"authored extent and shore")
	check(Classic.structures(sim,0,"hq")[0].pos==Vector2(10,97),"player HQ authored-map home")
	check(Classic.structures(sim,1,"hq")[0].pos==Vector2(114,9),"enemy HQ authored-map home")
	var attacker:Dictionary=sim.living(1).filter(func(u):return u.kind=="rifle")[0]
	var base_approach:Vector2=Classic.known_base_approach(sim,attacker,0)
	check(base_approach.x>=0 and base_approach.distance_to(Vector2(10,97))<=10.01,"real expanded-map enemy fallback reaches disclosed HQ sight neighborhood")
	check(sim.classic.fields.size()==4 and sim.classic.fields[0].pos==Vector2(24,86) and sim.classic.fields[1].pos==Vector2(104,22),"authored deposits loaded")
	var sites:Array=[]
	for team in 2:
		var planned:Vector2=Classic.find_site(sim,"refinery",team)
		check(planned.x>=0 and Classic.can_build(sim,"refinery",team,planned),"automatic refinery search reaches real base %s"%team)
		# Separate collect/unload zones to prove actual trips, not stationary
		# cargo cycling where their generous gameplay radii overlap.
		var site:Vector2=Vector2(6,86) if team==0 else Vector2(116,26)
		sites.append(site)
		check(site.x>=0 and Classic.build(sim,"refinery",team,site),"real refinery construction team %s"%team)
	# Economy isolation: leave units/tactics intact, suppress strategic attack waves
	# and purchases so deliveries and production are attributable to this fixture.
	sim.classic.ai_clock=100000;sim.classic.attack_clock=100000
	var delivered:Dictionary={0:0,1:0}
	var delivered_by_unit:Dictionary={}
	var original_haulers:Array=sim.units.filter(func(u):return u.kind=="harvester").map(func(u):return u.id)
	var previous_cargo:Dictionary={}
	var previous_pos:Dictionary={}
	var loaded_travel:Dictionary={}
	var moving_deliveries:Dictionary={}
	var produced:=false
	for frame in 1800:
		sim.tick(0.1);sim.events.clear()
		for u in sim.units:
			if u.kind!="harvester":continue
			if previous_cargo.get(u.id,0.0)>0 and previous_pos.has(u.id):loaded_travel[u.id]=loaded_travel.get(u.id,0.0)+u.pos.distance_to(previous_pos[u.id])
			if previous_cargo.get(u.id,0.0)>100 and u.get("cargo",0.0)==0:
				if loaded_travel.get(u.id,0.0)>1.0:moving_deliveries[u.id]=moving_deliveries.get(u.id,0)+1
				loaded_travel[u.id]=0.0
				delivered[u.team]+=1
				delivered_by_unit[u.id]=delivered_by_unit.get(u.id,0)+1
			previous_cargo[u.id]=u.get("cargo",0.0)
			previous_pos[u.id]=u.pos
		if frame==150:
			for team in 2:check(Classic.build(sim,"barracks",team,Classic.find_site(sim,"barracks",team)),"real barracks site team %s"%team)
		if frame==400:
			for team in 2:check(Classic.enqueue(sim,"rifle",team),"real barracks paid infantry queue team %s"%team)
		if frame==250:
			check(Classic.enqueue(sim,"harvester",0),"HQ accepts paid production")
		if Classic.committed_count(sim,"harvester",0)>=2 and Classic.structures(sim,0,"hq")[0].queue.is_empty():produced=true
	for u in sim.units:
		if u.kind=="harvester":print("HAUL ",u.id," pos=",u.pos," cargo=",u.get("cargo",0)," orders=",u.orders," path=",u.path," blocked=",u.blocked_time)
	check(delivered[0]>=2 and delivered[1]>=2,"both original harvesters complete repeated deposit/refinery trips")
	check(produced,"paid queue deploys a real harvester")
	for id in original_haulers:check(moving_deliveries.get(id,0)>=2,"original harvester repeated moving delivery trips %s"%id)
	check(moving_deliveries.keys().any(func(id):return id not in original_haulers and moving_deliveries[id]>=1),"newly produced harvester completes a moving delivery")
	for team in 2:check(sim.living(team).filter(func(u):return u.kind=="rifle").size()>=3,"real infantry deployment team %s"%team)
	print("RIVERSIDE ECONOMY sites=",sites," deliveries=",delivered," produced=",produced)
	var terrain=sim.terrain
	for radius in [0.8,1.9,2.65]:
		var origin:=Vector2(18,97)
		var goal:=Vector2(114,20)
		var route:Array=terrain.path(origin,goal,"land",radius,[],"infantry" if radius!=1.9 else "wheeled")
		check(not route.is_empty(),"town-spanning route radius %s"%radius)
		for point in route:
			check(terrain.segment_clear(origin,point,"land",radius),"long-route swept clearance")
			origin=point
	var travel=preload("res://tests/fixtures/legacy_riverside.gd").create(false)
	travel.classic.ai_clock=100000;travel.classic.attack_clock=100000
	var truck=travel.spawn("harvester",0,Vector2(18,97))
	check(travel.issue([truck.id],Vector2(114,20),"move")==1,"long journey order accepted")
	for frame in 1800:
		var before:Vector2=truck.pos
		travel.tick(0.1);travel.events.clear()
		check(before.distance_to(truck.pos)<0.7 and travel.terrain.segment_clear(before,truck.pos,"land",1.9),"real long journey is continuous and clears terrain")
	check(truck.orders.is_empty() and truck.pos.distance_to(Vector2(114,20))<0.2,"real harvester traverses town under one explicit move")
	var roads:Dictionary=sim.scenario.roads
	for edge in roads.edges:
		var a:Array=roads.nodes[edge[0]];var b:Array=roads.nodes[edge[1]]
		var start:=Vector2(a[0],a[1])
		# Base-road node lies inside the HQ clearance apron: start at its
		# nearby legal road point, as deployment does. Keep authored geometry.
		if not terrain.traversable(start,"land",1.9):
			start=terrain.reachable_destination(Vector2(18,97),start,"land",1.9,"wheeled")
		var route:Array=terrain.path(start,Vector2(b[0],b[1]),"land",1.9,[],"wheeled")
		check(not route.is_empty(),"road connection "+str(edge[0])+" to "+str(edge[1]))
	var scout=sim.spawn("drone",0,Vector2(120,96))
	sim.update_visibility()
	check(sim.visible_cells.has(Vector2i(60,48)),"real far-map fog revelation")
	var battle=load("res://scripts/battle.gd").new()
	battle.sim=sim;root.add_child(battle.camera);battle.setup_fog()
	check(battle.fog_image.get_size()==Vector2i(72,54),"real fog image extent")
	var hud=load("res://scripts/hud.gd").new()
	hud.minimap=Rect2(0,0,240,180);battle.hud=hud
	battle.ui_action("minimap",Vector2(200,160))
	check(battle.camera_focus.is_equal_approx(Vector3(120,0,96)),"real minimap far-region click")
	battle.request_zoom(0.1);battle.advance_zoom(1.0)
	check(battle.camera_zoom_target>=battle.MIN_ZOOM,"real map near zoom bounded")
	battle.request_zoom(100);battle.advance_zoom(1.0)
	check(battle.camera_zoom_target<=battle.MAX_ZOOM,"real map far zoom bounded")
	hud.free();battle.effects.flashes.free();battle.effects.explosion_audio.free();battle.camera.free();battle.effects.free();battle.weather_fx.free();battle.sound.free();battle.free()
	FileAccess.open("res://artifacts/riverside-navigation.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"deliveries":delivered,"production":produced,"deliveries_by_unit":delivered_by_unit,"moving_deliveries":moving_deliveries,"native_visual_review":false},"  "))
	print("RIVERSIDE NAVIGATION: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
