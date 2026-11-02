extends SceneTree

const Sim=preload("res://scripts/simulation.gd")
const Positions=preload("res://scripts/field_positions.gd")
const Terrain=preload("res://scripts/terrain.gd")
var checks:=0
var failures:=0

func _init()->void:call_deferred("run")

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func fixture()->Dictionary:
	var sim=Sim.new(false,5)
	sim.terrain=Terrain.new(0,{"id":"position_order_fixture","size":[96,72],"shore_x":90,"port":false,
		"mode":"field_ops","style":"showcase","blocks":[],"woods":[],"rubble":[0,0,0,0],
		"mud":[0,0,0,0],"objectives":[],"roads":{}})
	sim.terrain.roadside_blocks.clear();sim.terrain.prop_blocks.clear();sim.terrain.trees.clear()
	sim.terrain.rebuild_static_index()
	sim.scenario.autonomy=true
	sim.objectives.clear();sim.field_ops.income_rate=0.0;sim.field_ops.started=false
	sim.field_ops.enemy_clock=1000.0;sim.enemy_clock=1000.0
	sim.credits=1000.0
	var neighbor:Dictionary=sim.spawn("rifle",0,Vector2(24,36))
	var worker:Dictionary=sim.spawn("rifle",0,Vector2(28.3,36))
	# Anchors can converge while actual soldiers are still spread along their
	# route. Keep the separate, physically valid bodies from the initial spawn.
	worker.pos=Vector2(26.5,36)
	sim.rebuild_spatial();sim.rebuild_actor_spatial();sim.update_visibility()
	return {"sim":sim,"neighbor":neighbor,"worker":worker}

func advance(sim,seconds:float)->void:
	for i in ceili(seconds*30.0):sim.tick(1.0/30.0)

func begin_work(f:Dictionary)->Dictionary:
	var sim=f.sim
	var worker:Dictionary=f.worker
	check(sim.issue_dig([worker.id],Vector2(29.5,38))==1,"crowded anchors retain a physically valid local dig route")
	return sim.get_unit(int(worker.get("building_id",-1)))

func quiet_spacing_keeps_work()->void:
	var f:=fixture()
	var sim=f.sim
	var worker:Dictionary=f.worker
	var site:=begin_work(f)
	if site.is_empty():return
	var version:int=worker.order_version
	var original:Vector2=worker.pos
	advance(sim,6.0)
	check(worker.order_version==version and worker.orders.is_empty(),"ordinary crowd timeout cannot replace accepted digging with a Move order")
	check(Positions.jobs(sim).has(worker.id) and not site.build_paused,"digging remains assigned after the automatic unstack timeout")
	check(worker.pos==original and site.position_progress>0,"quiet spacing retains the work anchor while physical work advances")
	advance(sim,24.0)
	check(site.position_stage==1 and float(site.build_left)<=0.0,"crowded section completes its real 18-second local position")
	check(not Positions.jobs(sim).has(worker.id) and not worker.has("building_id"),"completed work releases the temporary spacing exemption")
	check(worker.members.all(func(member):return not sim.Infantry.task_busy(member)),"completion releases all actor tasks")

func engagement_spacing_keeps_work()->void:
	var f:=fixture()
	var sim=f.sim
	var worker:Dictionary=f.worker
	var site:=begin_work(f)
	if site.is_empty():return
	var enemy:Dictionary=sim.spawn("rifle",1,Vector2(38,36))
	sim.rebuild_spatial();sim.rebuild_actor_spatial();sim.update_visibility()
	f.neighbor["engage_halt_at"]=0.0;worker["engage_halt_at"]=1.0
	var original:Vector2=worker.pos
	var version:int=worker.order_version
	sim.space_engaged(worker,enemy,0.1)
	sim.space_engaged(worker,enemy,0.1)
	check(not worker.has("engage_shift") and worker.pos==original,"engagement spacing cannot silently move an active work anchor")
	check(worker.order_version==version and Positions.jobs(sim).has(worker.id),"contact spacing retains work assignment and actor ownership")
	# This guard is not a hard Hold: an accepted new player command still ends
	# the job immediately and retains the already earned site for later Resume.
	check(sim.issue([worker.id],Vector2(34,44),"move")==1,"explicit player movement still replaces local work")
	check(worker.order_version>version and not Positions.jobs(sim).has(worker.id),"player Move immediately releases the old work assignment")
	check(site.build_paused and int(site.engineer_id)==-1 and not worker.has("building_id"),"replaced job leaves a resumable unowned site")
	check(worker.members.all(func(member):return not sim.Infantry.task_busy(member)),"player replacement releases the worker without stranded task markers")

func ordinary_spacing_still_runs()->void:
	var f:=fixture()
	var sim=f.sim
	var worker:Dictionary=f.worker
	worker["stacked_since"]=0.0;sim.time=10.0
	var version:int=worker.order_version
	sim.unstack_sections()
	check(worker.order_version>version and not worker.orders.is_empty(),"ordinary idle sections still spread after the crowd timeout")
	f=fixture();sim=f.sim;worker=f.worker
	var enemy:Dictionary=sim.spawn("rifle",1,Vector2(38,36))
	sim.rebuild_spatial();sim.rebuild_actor_spatial();sim.update_visibility()
	f.neighbor["engage_halt_at"]=0.0;worker["engage_halt_at"]=1.0
	var original:Vector2=worker.pos
	sim.space_engaged(worker,enemy,0.1)
	sim.space_engaged(worker,enemy,0.1)
	check(worker.has("engage_shift") and worker.pos!=original,"ordinary fighting sections still move to a less crowded firing position")

func run()->void:
	quiet_spacing_keeps_work()
	engagement_spacing_keeps_work()
	ordinary_spacing_still_runs()
	print("FIELD POSITION ORDERS: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
