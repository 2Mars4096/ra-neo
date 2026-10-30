extends SceneTree
# Existing economy and vehicle executors must defer expensive work without
# turning budget pressure into failed navigation, lost cargo or a lost wave.
const Sim=preload("res://scripts/simulation.gd")
const Classic=preload("res://scripts/classic.gd")
const VehicleDamage=preload("res://scripts/vehicle_damage.gd")
var checks:=0
var failures:=0

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func _init()->void:
	wreck_detour()
	long_route_service()
	recrew_deferral()
	economy_deferral()
	reserve_deferral()
	print("RUNTIME PLANNING: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func wreck_detour()->void:
	var sim=Sim.new(false,0)
	var hull:Dictionary=sim.spawn("aa",0,Vector2(20,62))
	check(not hull.is_empty(),"vehicle fixture exists")
	hull.orders=[{"mode":"move","pos":Vector2(42,62),"target":-1}]
	hull.path=[Vector2(42,62)]
	sim.set_meta(VehicleDamage.WRECKS,[{"id":-1,"kind":"tank","team":0,"pos":Vector2(30,62),"facing":Vector2.RIGHT,"radius":2.45,"abandoned":false}])
	var route:Array=hull.path.duplicate()
	var paths:int=sim.terrain.path_calls
	sim.terrain.planning.begin_tick(1,{"routes":0})
	VehicleDamage.before_move(sim,hull)
	check(hull.path==route and not hull.has("wreck_route_at"),"denied wreck detour preserves route and retry eligibility")
	check(sim.terrain.path_calls==paths,"denied wreck detour starts no path search")
	sim.terrain.planning.begin_tick(2,{"routes":1})
	VehicleDamage.before_move(sim,hull)
	check(hull.has("wreck_route_at") and sim.terrain.path_calls==paths+1,"admitted wreck detour performs one bounded path query")
	sim.terrain.planning.end_tick()

func long_route_service()->void:
	var sim=Sim.new(false,0)
	sim.route_budget=0.0
	sim.terrain.planning.begin_tick(1,{"routes":0})
	check(not sim.take_route_budget(Vector2.ZERO,Vector2(600,0),true,20,"expensive_retry"),"expensive live request defers when shared capacity is exhausted")
	check(sim.terrain.planning.snapshot().pending==1,"long request ages in the shared queue despite exhausted legacy estimate")
	sim.terrain.planning.begin_tick(2,{"routes":1})
	check(sim.take_route_budget(Vector2.ZERO,Vector2(600,0),true,20,"expensive_retry"),"aged live route receives service independent of legacy distance estimate")
	sim.terrain.planning.end_tick()

func recrew_deferral()->void:
	var sim=Sim.new(false,0)
	var hull:Dictionary=sim.spawn("tank",0,Vector2(30,62))
	VehicleDamage.ensure_state(sim,hull)
	hull.crew=0;hull.abandoned=true;hull.abandoned_hp=300.0
	hull.hp-=VehicleDamage._finish(sim,hull,hull.hp+1.0)
	var section:Dictionary=sim.spawn("rifle",0,Vector2(24,62))
	check(VehicleDamage.order_recrew(sim,[section.id],hull.id)==1,"recrew preparation is accepted")
	section.pos=hull.pos+Vector2(-3.5,0)
	var job:Dictionary=sim.get_meta(VehicleDamage.RECREW)[0]
	job.done=VehicleDamage.RECREW_SECONDS
	var before:float=section.hp
	var count:int=sim.units.size()
	sim.terrain.planning.begin_tick(1,{"formation":0})
	VehicleDamage.tick_recrew(sim,1.0/30.0)
	check(sim.has_meta(VehicleDamage.RECREW) and sim.units.size()==count and section.hp==before,"denied boarding deployment preserves job and soldiers")
	check(hull.get("wrecked",false) and not hull.has("recrewed_as"),"pending deployment keeps original abandoned hull")
	sim.terrain.planning.begin_tick(2,{"formation":1})
	VehicleDamage.tick_recrew(sim,1.0/30.0)
	check(hull.has("recrewed_as") and sim.units.size()==count+1 and section.hp<before,"ready boarding retries and commits once admitted")
	sim.terrain.planning.end_tick()

func economy_deferral()->void:
	var sim=Sim.new(true,Sim.Scenarios.index_for_id("classic"))
	sim.classic.ai_clock=1e9;sim.classic.attack_clock=1e9
	var site:Vector2=Classic.find_site(sim,"refinery",0)
	var refinery:Dictionary=sim.spawn("refinery",0,site)
	Classic.sync_obstacles(sim);Classic.update_intel(sim,0)
	var truck:Dictionary=sim.living(0).filter(func(u):return u.kind=="harvester")[0]
	truck.cargo=0.0;truck.haul="COLLECT"
	var paths:int=sim.terrain.path_calls
	var supply:float=sim.credits
	var deposits:String=var_to_str(sim.classic.fields)
	sim.terrain.planning.begin_tick(1,{"routes":0})
	Classic.harvest(sim,truck,1.0/30.0)
	check(sim.terrain.path_calls==paths and truck.orders.is_empty(),"denied ore approach does no route work and retains idle orders")
	check(not truck.has("ore_skip") and not truck.has("haul_repath_at"),"ore budget denial does not blacklist a deposit or start failure backoff")
	check(truck.cargo==0 and sim.credits==supply and var_to_str(sim.classic.fields)==deposits,"pending collection conserves cargo supply and ore")
	truck.cargo=120.0;truck.haul="RETURN"
	Classic.harvest(sim,truck,1.0/30.0)
	check(truck.cargo==120.0 and sim.credits==supply and not truck.get("dock_unload",false),"pending delivery does not unload cargo at a distance")
	check(not truck.has("haul_repath_at") and sim.terrain.path_calls==paths,"denied delivery has no failed-route delay or query")
	Classic.stage(sim,truck,refinery)
	check(not truck.get("dock_wait",false) and sim.terrain.path_calls==paths,"denied staging does not claim a dock or fabricate an approach")
	sim.terrain.planning.end_tick()
	Classic.harvest(sim,truck,1.0/30.0)
	check(not truck.orders.is_empty() and truck.cargo==120.0,"delivery retries successfully when planning is available")
	check(truck.haul=="RETURN" and sim.credits==supply,"route acceptance preserves still-carried cargo")

func reserve_deferral()->void:
	var sim=Sim.new(false,3)
	sim.scenario=sim.scenario.duplicate(true);sim.scenario.autonomy=true
	sim.objectives[0].owner=0
	sim.counterattack_at=0.0;sim.time=20.0
	sim.terrain.planning.begin_tick(1,{"formation":0})
	sim.showcase_mission()
	check(not sim.counterattack_sent and sim.counterattack_ids.is_empty(),"denied reserve placement preserves dispatch and promised force")
	sim.terrain.planning.begin_tick(2,{"formation":8})
	sim.showcase_mission()
	check(sim.counterattack_sent and sim.counterattack_ids.size()==3,"reserve retries once capacity is available")
	var ids:Array=sim.counterattack_ids.duplicate()
	sim.showcase_mission()
	check(sim.counterattack_ids==ids,"completed reserve dispatch never duplicates units")
	sim.terrain.planning.end_tick()
