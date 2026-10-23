extends SceneTree

const Catalog=preload("res://scripts/scenario_catalog.gd")
const Sim=preload("res://scripts/simulation.gd")
const Terrain=preload("res://scripts/terrain.gd")
const Detail=preload("res://scripts/environment_detail.gd")
const Art=preload("res://scripts/visuals.gd")
const IDS:=["bayhead_rail_valley","limestone_pass","south_inlet"]
var checks:=0
var failures:=0

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func point(value:Array)->Vector2:
	return Vector2(float(value[0]),float(value[1]))

func _init()->void:
	call_deferred("run")

func route_check(terrain,start:Vector2,goal:Vector2,domain:String,radius:float,profile:String,label:String)->void:
	var route:Array=terrain.path(start,goal,domain,radius,[],profile)
	check(not route.is_empty(),label+" exists")
	# Tracked routing deliberately crosses crushable street furniture, matching
	# hull movement. Keep solid buildings, trees and coasts blocking as usual.
	terrain.crush_pass=domain=="land" and profile=="tracked"
	var previous:=start
	for step in route:
		check(terrain.segment_clear(previous,step,domain,radius),label+" preserves swept clearance "+str(previous)+" -> "+str(step))
		for part in 8:
			check(terrain.traversable(previous.lerp(step,float(part)/7.0),domain,radius),label+" fits full body")
		previous=step
	terrain.crush_pass=false

func mission_completion(sim,id:String)->void:
	# State-based mission acceptance: clear the defending force, then capture
	# with real legal infantry bodies. No full AI battle or guessed ownership.
	for unit in sim.units:
		if unit.team==1:unit.hp=0.0
	for objective in sim.objectives:
		objective.owner=1;objective.progress=0.0
		var unit:Dictionary=sim.spawn("rifle",0,objective.pos+Vector2(0,5))
		check(not unit.is_empty(),id+" capture infantry fits the objective approach")
		if not unit.is_empty():
			check(unit.pos.distance_to(objective.pos)<float(sim.scenario.get("capture_radius",7.0)),id+" infantry is inside the real capture radius")
			check(sim.terrain.traversable(unit.pos,"land",float(sim.definitions.rifle.radius)),id+" capture body clears terrain")
	sim.score_hold=0.0
	sim.update_objectives(sim.capture_time-0.1)
	check(sim.objectives.all(func(objective):return objective.owner==1),id+" incomplete capture cannot award ownership")
	sim.update_objectives(0.1)
	check(sim.objectives.all(func(objective):return objective.owner==0 and not objective.enemy_present),id+" legal infantry secures all sectors")
	# Ownership and elapsed hold cannot bypass the dispatched reserve's grace.
	sim.score_hold=float(sim.scenario.hold)
	sim.time=sim.counterattack_at+19.9
	sim.update_objectives(0.0)
	check(sim.result=="",id+" reserve grace prevents premature victory")
	sim.time=sim.counterattack_at+20.1
	sim.score_hold=float(sim.scenario.hold)-0.5
	sim.update_objectives(0.25)
	check(sim.result=="",id+" authored hold must finish")
	sim.update_objectives(0.25)
	check(sim.result=="VICTORY",id+" captured and held operation can finish")

func run()->void:
	var legacy:Array=JSON.parse_string(FileAccess.get_file_as_string(Catalog.LEGACY_PATH))
	var descriptors:=Catalog.entries()
	check(legacy.size()==7 and descriptors.size()==legacy.size()+IDS.size(),"seven legacy plus three regional battlefields")
	for index in legacy.size():
		check(Catalog.index_for_id(str(legacy[index].id))==index,"legacy index preserved: "+str(legacy[index].id))
		check(not descriptors[index].has("blocks") and not descriptors[index].has("map_props"),"catalog summaries omit heavy geometry")
	check(Catalog.index_for_id("missing_battlefield")==-1,"unknown IDs do not silently select a different map")
	check(Sim.default_selection()==6,"existing harbor remains the default")
	for id in IDS:
		var index:=Catalog.index_for_id(id)
		check(index>=legacy.size(),"regional map in catalog: "+id)
		if index<0:continue
		var config:=Catalog.config(index)
		check(not config.is_empty() and config.get("id","")==id,"resolved map ID: "+id)
		if config.is_empty():continue
		var original_name:String=config.name
		config.name="mutated test copy"
		check(Catalog.config(index).name==original_name,"config copies cannot mutate future battles")
		var sim=Sim.new(true,index)
		var terrain=sim.terrain
		check(sim.scenario.id==id and terrain.config.id==id,"simulation and terrain resolve identical scenario")
		check(terrain.compiled_map and terrain.style=="showcase" and not terrain.port,"compiled renderer and authored physics enabled")
		check(terrain.world_size==point(sim.scenario.size),"battlefield uses authored dimensions")
		check(Detail._harbor_config(terrain).id==id,"ground zones belong to the current battlefield")
		check(not sim.field_ops.is_empty() and sim.classic.is_empty(),"shared field operations mode")
		check(sim.living(0).size()==sim.scenario.player_force.size(),"every authored player force spawns: "+id)
		var defenders:Array=sim.living(1).filter(func(unit):return not unit.get("prepared",false))
		check(defenders.size()==sim.scenario.enemy_force.size(),"every authored enemy force spawns: "+id)
		# Smaller theaters must still fit the complete scenario reserve at its
		# real entry, including when the initial defending force is present.
		sim.objectives[0].owner=0
		sim.counterattack_at=sim.time
		sim.FieldOps.tick(sim,0.0)
		check(sim.counterattack_sent and sim.counterattack_ids.size()==sim.scenario.reserve_force.size(),"every authored reserve spawns: "+id)
		check(sim.FieldOps.reserve_target(sim)==sim.objectives[0].pos,"reserve targets the captured objective")
		var dispatched_count:int=sim.units.size()
		sim.FieldOps.tick(sim,0.0)
		check(sim.units.size()==dispatched_count and sim.counterattack_ids.size()==sim.scenario.reserve_force.size(),"reserve deploys only once: "+id)
		for unit in sim.units:
			if unit.get("structure",false):continue
			var definition:Dictionary=sim.definitions[unit.kind]
			check(terrain.traversable(unit.pos,definition.domain,float(definition.radius)),"spawn fits domain and footprint: "+str(unit.kind))
		for insertion in [sim.field_ops.insertion,sim.field_ops.enemy_insertion]:
			for kind in ["rifle","tank"]:
				var radius:float=sim.definitions[kind].radius
				var profile:String=terrain.mobility_profile(kind)
				check(terrain.traversable(insertion,"land",radius),id+" land insertion fits "+kind)
				for objective in sim.objectives:
					var destination:Vector2=terrain.reachable_destination(insertion,objective.pos+Vector2(0,8),"land",radius,profile)
					check(destination.x>=0 and destination.distance_to(objective.pos)<20,id+" reachable objective approach for "+kind)
					if destination.x>=0:route_check(terrain,insertion,destination,"land",radius,profile,id+" "+kind+" objective route")
		var domains:Array=sim.scenario.get("available_domains",["land","air","sea"])
		var choices:Array=sim.FieldOps.purchase_choices(sim)
		check(("boat" in choices)==("sea" in domains),"naval purchases match battlefield access")
		if "sea" not in domains:
			var funds:float=sim.credits
			var queue_count:int=sim.FieldOps.queue(sim).size()
			check(not sim.recruit("boat"),"inland battle refuses naval purchase")
			check(sim.credits==funds and sim.FieldOps.queue(sim).size()==queue_count,"unavailable purchase neither charges nor queues")
			check(not sim.field_ops.last_purchase_error.is_empty(),"unavailable purchase explains refusal")
		else:
			var sea_entry:Vector2=sim.field_ops.sea_insertion
			check(terrain.traversable(sea_entry,"sea",float(sim.definitions.boat.radius)),"sea entry fits naval hull")
			for raw in sim.scenario.get("layout_validation",{}).get("sea_route_points",[]):
				route_check(terrain,sea_entry,point(raw),"sea",float(sim.definitions.boat.radius),"legacy",id+" naval route")
		for spec in sim.scenario.get("architecture",[]):
			if spec.get("design","")!="rock":continue
			var center:=point(spec.position)
			check(terrain.blocked(center) and not terrain.traversable(center,"land",0.8),"ridge is a shared solid obstacle")
			var reach:float=float(spec.source_size[0])*0.5+2.0
			check(not terrain.line_clear(center-Vector2(reach,0),center+Vector2(reach,0)),"ridge blocks ground sight and fire")
		# Build with the same renderer used by play. No private scenery physics
		# or legacy fixed shoreline is allowed to appear on catalog maps.
		var stage:=Node3D.new();root.add_child(stage)
		var art=Art.new();art.make_world(stage,terrain)
		check(stage.has_node("HarborLand") and stage.has_node("HarborWater"),"shared water mask renderer: "+id)
		check(stage.has_node("HarborBuildings") and stage.has_node("HarborGroundDetail"),"shared city and roads renderer: "+id)
		var placements:Array=stage.get_node("HarborBuildings").get_meta("placements",[])
		check(placements.size()==sim.scenario.architecture.size(),"all compiled architecture represented once")
		stage.free()
		mission_completion(sim,id)
	# Load original harbor after all new maps: no cached land-use dictionary leaks.
	var harbor=Terrain.new(6)
	check(Detail._harbor_config(harbor).id=="black_sea_harbor","returning to harbor restores its ground zones")
	print("REGIONAL PHYSICS: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
