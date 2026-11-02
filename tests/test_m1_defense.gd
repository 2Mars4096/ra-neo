extends SceneTree

const Fixture=preload("res://tests/m1_defense_fixture.gd")
var checks:=0
var failures:=0

func _init()->void:call_deferred("run")

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func advance_until(f,condition:Callable,seconds:float)->bool:
	for frame in ceili(seconds/Fixture.DT):
		if condition.call():return true
		f.tick()
	return bool(condition.call())

func advance(f,seconds:float)->void:
	for frame in ceili(seconds/Fixture.DT):f.tick()

func run()->void:
	var f=Fixture.new()
	if not f.setup():
		check(false,"Harbor fixture setup: "+str(f.errors));finish();return
	var sim=f.sim
	var terrain=sim.terrain
	var defender:Dictionary=f.units.defender
	var reserve:Dictionary=f.units.reserve
	var engineer:Dictionary=f.units.engineer
	check(sim.scenario.id=="black_sea_harbor" and f.initial_geometry.blocks>0 and f.initial_geometry.props>0,"encounter retains the authored Harbor terrain and obstacles")
	check(sim.units.size()==4 and f.units.values().all(func(u):return u.members.size()==3),"initial forces are three real friendly sections and one opposing section")
	check(f.initial_stock.values().all(func(stock):return stock=={"frag":1,"smoke":1}),"all initial equipment comes from ordinary member creation")
	var sight_from:=Vector3(Fixture.SITE.x,1.6,Fixture.SITE.y)
	var sight_to:=Vector3(f.units.enemy.pos.x,1.6,f.units.enemy.pos.y)
	check(sim.optical_ray_clear(sight_from,sight_to),"the later smoke lane begins physically unobstructed")
	check(f.start_defense(),"digging and a nearby reserve request start through ordinary command APIs")
	if f.site.is_empty():finish();return
	var site_id:int=f.site.id
	check(f.site.position_stage==0 and f.site.position_progress==0.0,"new site begins as an uncompleted survey")
	check(sim.credits==f.initial_supply,"initial digging and existing reserve dispatch do not charge supplies")
	check(sim.request_backup([engineer.id])==1 and sim.SupportRequests.request_for(sim,engineer).id==f.request.id,"duplicate backup request keeps one existing request")
	check(advance_until(f,func():return f.metrics.frag_releases==1,8.0),"a real automatic frag prepares and releases within the opening encounter")
	check(f.metrics.combined_roles and f.metrics.covering_shots>0,"one section has separate digging, throwing and covering actors, with a real covering shot during preparation")
	check(f.metrics.worker_moved and f.site.position_progress>0.0,"the worker physically reaches the site and earns progress while its partners fight")
	check(f.stock_balances() and f.stock(defender,"frag")==2,"one released frag debits only its owning member once")
	var frag:Dictionary={}
	for projectile in sim.throwables.projectiles:
		if projectile.payload=="frag":frag=projectile;break
	check(not frag.is_empty() and frag.elapsed==0.0 and frag.pos==frag.source,"release creates a world projectile at the actual hand without a free flight step")
	var initial_enemy_hp:float=f.units.enemy.hp
	check(f.begin_smoke(),"accepted smoke orders replace the dig assignment and exercise preparation cancellation")
	check(f.metrics.smoke_cancel_unspent and f.stock(defender,"smoke")==3,"cancelling smoke preparation consumes no equipment")
	check(f.site.build_paused and not sim.FieldPositions.jobs(sim).has(defender.id),"replacement immediately releases the worker and pauses the same site")
	check(not frag.is_empty() and frag in sim.throwables.projectiles,"accepted replacement leaves the released frag in the world")
	check(advance_until(f,func():return f.metrics.smoke_releases==1,3.0),"replacement smoke reaches one actual release")
	check(f.site.position_progress==f.paused_progress,"interrupted work earns no progress while a different action owns the section")
	check(f.stock_balances() and f.stock(defender,"smoke")==2,"one successful smoke release consumes one member's item after a cancelled attempt")
	check(f.resume_work() and f.metrics.same_site,"normal digging resumes the original site after the released smoke")
	check(f.site.id==site_id and f.site.position_progress==f.paused_progress,"resuming retains the exact site and earned work")
	check(f.metrics.smoke_released_after_replacement,"resumed digging cannot cancel a released smoke projectile")
	check(advance_until(f,func():return not sim.throwables.smoke.is_empty(),4.0),"smoke reaches the ground and activates through real flight and fuse execution")
	check(f.metrics.frag_bursts==1 and f.units.enemy.hp<initial_enemy_hp,"released fragmentation survives replacement, detonates once and damages the opposing section")
	check(f.metrics.smoke_deployed==1 and sim.Throwables.blocks_sight(sim,sight_from,sight_to),"the one released smoke cloud obstructs the original firing frontage")
	check(not sim.optical_ray_clear(sight_from,sight_to) and not sim.optical_ray_clear(sight_to,sight_from),"world smoke blocks ordinary optical queries in both directions")
	check(f.site.position_progress>f.paused_progress and sim.FieldPositions.jobs(sim).has(defender.id),"real digging continues in the same encounter while the smoke effect is live")
	check(advance_until(f,func():return f.site.position_stage==1 and f.request.phase in sim.SupportRequests.TERMINAL,35.0),"hasty work and the complete reserve lifecycle finish through full simulation ticks")
	check(f.request.phase=="completed" and f.metrics.reserve_moved and f.metrics.reserve_delivered,"the delegated reserve physically moves, delivers support and returns")
	check(f.metrics.max_service>=sim.SupportRequests.SERVICE_SECONDS and f.metrics.reserve_shots>0,"delivered backup earns its sustained useful interval and fires real covering shots")
	check(f.metrics.enemy_shots>0,"the opposing section actually returns fire during smoke and reserve integration")
	check(reserve.pos.distance_to(f.reserve_home)<=1.0 and reserve.assignment==f.reserve_assignment and reserve.hold_command,"return restores the reserve's original physical guard and assignment")
	check(reserve.reserve_enabled and not sim.SupportRequests.owns_maneuver(reserve),"returned reserve retains delegation and releases its temporary maneuver")
	check(not sim.actions.claims.has("backup:provider:%d"%reserve.id) and not sim.actions.claims.has("backup:request:%d"%f.request.id),"completed service releases both exclusive broker claims")
	check(f.site.position_stage==1 and sim.terrain.cover(Fixture.SITE) and not sim.terrain.dug_in(Fixture.SITE),"completed hasty site publishes cover without reinforced protection")
	check(sim.credits==f.initial_supply and sim.units.size()==5,"hasty construction and reserve support add only the single site and spend no supplies")
	check(f.begin_upgrade(),"nearby engineer accepts and acknowledges duplicate reinforcement of the same site")
	var cost:float=sim.definitions.fighting_trench.cost
	check(sim.credits==f.initial_supply-cost and f.site.upgrade_paid,"reinforcement charges the published supply price once")
	var job:Dictionary=sim.FieldPositions.jobs(sim).get(engineer.id,{}).duplicate(true)
	check(sim.upgrade_position([engineer.id],site_id)==1 and sim.FieldPositions.jobs(sim).get(engineer.id,{})==job,"repeating paid reinforcement keeps the existing worker, action and assignment")
	check(advance_until(f,func():return f.site.position_progress>=2.0,8.0),"the engineer physically approaches and earns partial reinforcement progress")
	check(f.interrupt_upgrade(),"Hold releases the actual engineer job while preserving paid work")
	advance(f,0.6)
	check(f.site.position_progress==f.upgrade_progress and sim.credits==f.initial_supply-cost,"interrupted reinforcement neither progresses nor charges again")
	check(sim.terrain.cover(Fixture.SITE) and not sim.terrain.dug_in(Fixture.SITE),"interrupted upgrade retains hasty protection")
	check(f.resume_upgrade() and f.site.position_progress==f.upgrade_progress,"ordinary reinforcement resumes retained paid progress")
	check(sim.credits==f.initial_supply-cost,"resuming the paid upgrade has no second debit")
	check(advance_until(f,func():return f.site.position_stage==2,20.0),"resumed physical work completes the reinforced position")
	check(f.site.id==site_id and sim.units.filter(func(u):return u.get("field_position",false)).size()==1,"the entire encounter produces exactly one progressively improved site")
	check(sim.terrain.dug_in(Fixture.SITE) and is_equal_approx(f.site.max_hp,float(sim.definitions.fighting_trench.hp)),"completed work publishes reinforced protection and normal durability")
	check(sim.upgrade_position([engineer.id],site_id)==0 and sim.credits==f.initial_supply-cost,"completed reinforcement cannot be repurchased or charged again")
	check(sim.FieldPositions.jobs(sim).is_empty() and f.units.values().all(func(u):return u.members.all(func(m):return not sim.Infantry.task_busy(m))),"completed work releases all worker and throwable actor tasks")
	check(sim.throwables.preparations.is_empty() and sim.throwables.projectiles.is_empty() and sim.throwables.smoke.is_empty(),"all finite preparations, payloads and smoke effects expire naturally")
	check(sim.optical_ray_clear(sight_from,sight_to),"the original lane becomes optically clear again after smoke expires")
	check(f.metrics.frag_releases==1 and f.metrics.smoke_releases==1 and f.metrics.frag_bursts==1 and f.metrics.smoke_deployed==1,"cancellation, resumption and duplicate orders do not duplicate any world payload or effect")
	check(f.stock_balances(),"every member's final stock equals its initial stock minus authoritative releases")
	check(f.metrics.claim_samples>800 and f.metrics.claim_errors.is_empty(),"every full encounter tick preserves exclusive actor/action claims: "+str(f.metrics.claim_errors))
	check(sim.terrain==terrain and sim.scenario.id=="black_sea_harbor" and sim.result=="","the continuous encounter stays on the original Harbor terrain without forcing a mission result")
	print("HARBOR ENCOUNTER: %.2f s, %d covering shots, %d reserve shots, %d enemy shots, %.2f s useful service, %d sampled ticks"%[sim.time,f.metrics.covering_shots,f.metrics.reserve_shots,f.metrics.enemy_shots,f.metrics.max_service,f.metrics.claim_samples])
	finish()

func finish()->void:
	print("M1 DEFENSE: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
