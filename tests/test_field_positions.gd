extends SceneTree

const Sim=preload("res://scripts/simulation.gd")
const Positions=preload("res://scripts/field_positions.gd")
const Models=preload("res://scripts/field_models.gd")
const Terrain=preload("res://scripts/terrain.gd")
const Roads=preload("res://scripts/road_network.gd")
const Elevation=preload("res://scripts/elevation.gd")
var checks:=0
var failures:=0

func _init()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func fixture():
	var sim=Sim.new(false,5)
	sim.terrain=Terrain.new(0,{"id":"position_fixture","size":[96,72],"shore_x":90,"port":false,
		"mode":"field_ops","style":"showcase","blocks":[],"woods":[],"rubble":[0,0,0,0],
		"mud":[0,0,0,0],"objectives":[],"roads":{}})
	sim.terrain.roadside_blocks.clear();sim.terrain.prop_blocks.clear();sim.terrain.trees.clear()
	sim.terrain.rebuild_static_index()
	sim.scenario.autonomy=true
	sim.objectives.clear();sim.field_ops.income_rate=0.0;sim.field_ops.started=false
	sim.field_ops.enemy_clock=1000.0;sim.enemy_clock=1000.0
	sim.credits=1000.0
	sim.spawn("rifle",0,Vector2(24,36))
	sim.rebuild_spatial();sim.rebuild_actor_spatial();sim.update_visibility()
	return sim

func advance(sim,seconds:float)->void:
	for i in ceili(seconds*30.0):sim.tick(1.0/30.0)

func create(sim,point:Vector2=Vector2(24,36))->Dictionary:
	check(Positions.issue_dig(sim,[sim.units[0].id],point)==1,"nearby infantry accept digging: "+sim.order_feedback)
	for site in sim.units:
		if site.get("field_position",false):return site
	return {}

func complete(sim,site:Dictionary)->void:
	for i in 1000:
		sim.tick(1.0/30.0)
		if float(site.build_left)<=0:break
	check(float(site.build_left)<=0,"physical work completes within bounded local fixture")

func preview_knowledge()->void:
	var sim=fixture()
	var u:Dictionary=sim.units[0]
	var point:=Vector2(29,36)
	sim.stop([u.id])
	var before:Dictionary=Positions.preview(sim,u,point)
	check(before.ok,"knowledge fixture starts with a valid dig preview")
	var hidden:Dictionary=sim.spawn("tank",1,point)
	hidden.pos=point;hidden.seen_by=[false,true]
	var assignment:Dictionary=u.assignment.duplicate(true)
	var balance:float=sim.credits
	var count:int=sim.units.size()
	check(Positions.preview(sim,u,point)==before,"hidden hostile bodies cannot change the dig preview")
	check(Positions.issue_dig(sim,[u.id],point)==0,"physical commitment rejects the hidden tank's blocked worker routes")
	check(u.assignment==assignment and sim.credits==balance and sim.units.size()==count and Positions.jobs(sim).is_empty(),"hidden physical blockage changes no order, inventory, site or supply")
	hidden.seen_by[0]=true
	check(not Positions.preview(sim,u,point).ok,"an observed blocking tank changes the preview to unavailable")
	hidden.seen_by[0]=false;hidden.pos=Vector2(60,36)
	check(Positions.preview(sim,u,point)==before,"hidden hostile movement cannot be tracked through the dig preview")
	for kind in ["fighting_trench","tactical_cover"]:
		var works=fixture()
		var worker:Dictionary=works.units[0]
		var clear:Dictionary=Positions.preview(works,worker,point)
		var site:Dictionary=works.spawn(kind,1,point)
		site.pos=point;site.seen_by=[false,true]
		works.FieldOps.sync_obstacles(works)
		var original:Dictionary=worker.assignment.duplicate(true)
		var original_count:int=works.units.size()
		check(clear.ok and Positions.preview(works,worker,point)==clear,"hidden %s cannot leak through occupancy or dynamic geometry preview"%kind)
		check(Positions.issue_dig(works,[worker.id],point)==0 and worker.assignment==original and works.units.size()==original_count,"actual %s occupancy is still enforced at commitment"%kind)
		site.seen_by[0]=true
		check(not Positions.preview(works,worker,point).ok,"known %s occupancy is reflected in the preview"%kind)

func worker_spatial_relocation()->void:
	var sim=fixture()
	var u:Dictionary=sim.units[0]
	for member in u.members.slice(1):member.hp=0.0;member.wound="KIA"
	sim.Infantry.publish(u)
	var member:Dictionary=u.members[0]
	member.pos=Vector2(23.95,36)
	check(Positions.issue_dig(sim,[u.id],Vector2(28,36))==1,"cross-bucket worker accepts a clear local approach")
	var old_cell:=Vector2i((member.pos/4.0).floor())
	sim.rebuild_actor_spatial();sim.ticking=true
	sim.time+=1.0/30.0;Positions.tick(sim,1.0/30.0)
	var new_cell:=Vector2i((member.pos/4.0).floor())
	check(new_cell!=old_cell,"work approach crosses an actor-index cell within one normal tick")
	check(sim.actor_spatial.get(new_cell,[]).any(func(entry):return entry.unit.id==u.id and entry.actor.index==member.index),"moving worker is immediately indexed at its new position")
	check(not sim.actor_spatial.get(old_cell,[]).any(func(entry):return entry.unit.id==u.id and entry.actor.index==member.index),"work movement removes the stale actor-index entry")
	sim.ticking=false

func eligibility()->void:
	var sim=fixture()
	var u:Dictionary=sim.units[0]
	sim.stop([u.id])
	var version:int=u.order_version
	var funds:float=sim.credits
	var original_count:int=sim.units.size()
	sim.terrain.roads=Roads.new({"nodes":{"a":[10,36],"b":[40,36]},"edges":[["a","b",3,"street"]]})
	check(Positions.issue_dig(sim,[u.id],u.pos)==0 and "road" in sim.order_feedback.to_lower(),"roads reject digging with a useful reason")
	check(sim.credits==funds and u.order_version==version and sim.units.size()==original_count,"rejected road placement preserves resources, units and order")
	sim.terrain.roads=Roads.new()
	sim.terrain.shore_x=25.0
	check(Positions.issue_dig(sim,[u.id],u.pos)==0,"water rejects the entire prepared footprint")
	sim.terrain.shore_x=90.0
	sim.terrain.blocks.append(Rect2(23.4,35,0.15,2))
	check(Positions.issue_dig(sim,[u.id],u.pos)==0,"thin wall inside footprint rejects digging")
	sim.terrain.blocks.clear()
	sim.terrain.elevation=Elevation.new([{"rect":[28,20,12,30],"height":5,"ramp":10}])
	check(Positions.issue_dig(sim,[u.id],u.pos)==0 and "steep" in sim.order_feedback.to_lower(),"sloped footprint rejects a rigid position")
	sim.terrain.elevation=Elevation.new()
	check(Positions.issue_dig(sim,[u.id],Vector2(60,36))==0,"distant work needs an explicit move closer")
	check(Positions.issue_dig(sim,[u.id],Vector2.INF)==0,"non-finite placement is rejected")
	check(sim.credits==funds and u.order_version==version and sim.units.size()==original_count,"all invalid sites preserve prior intent and supply")
	var preview:Dictionary=Positions.preview(sim,u,u.pos)
	check(preview.ok and preview.cost==0.0 and preview.seconds==Positions.DIG_SECONDS,"valid preview declares time-only cost")
	check(preview.rect.size==Vector2(7,2),"preview footprint matches actual existing trench bounds")

func staged_work_and_cancellation()->void:
	var sim=fixture()
	var u:Dictionary=sim.units[0]
	var funds:float=sim.credits
	var site:=create(sim)
	if site.is_empty():return
	check(site.pos==Vector2(24,36),"non-solid position is built at requested soil under its own section")
	check(site.position_stage==0 and not sim.terrain.cover(site.pos) and not sim.terrain.dug_in(site.pos),"surveyed site grants no cover or full trench protection")
	check(u.members.filter(func(m):return int(m.get("task_action",0))>0).size()==1,"exactly one soldier owns the work role")
	check(u.members.filter(func(m):return not sim.Infantry.task_busy(m)).size()==2,"other soldiers remain available to fight or cover")
	var initial_job:Dictionary=Positions.jobs(sim)[u.id].duplicate(true)
	check(Positions.issue_dig(sim,[u.id],site.pos)==1,"repeat digging acknowledges the active site")
	check(Positions.jobs(sim)[u.id]==initial_job and u.order_version==initial_job.version,"repeat digging preserves the current worker, route and assignment")
	advance(sim,4.0)
	check(site.position_progress>0 and site.build_left>0,"real local movement is followed by incremental work")
	check(not sim.terrain.cover(site.pos),"incomplete initial excavation has no full protection")
	var progress:float=site.position_progress
	var hp:float=site.hp
	sim.stop([u.id])
	check(site.build_paused and site.engineer_id==-1 and not u.has("building_id"),"new Hold command immediately releases worker")
	check(Positions.jobs(sim).is_empty() and u.members.all(func(m):return not sim.Infantry.task_busy(m)),"override releases both job and actor claims")
	advance(sim,2.0)
	check(site.position_progress==progress and site.hp==hp,"interrupted site keeps earned work and never builds itself")
	check(sim.credits==funds,"time-only digging does not spend or mint supplies")
	check(sim.FieldOps.available_engineer(sim,site.id)==u.id,"paused hasty site can resume with ordinary infantry")
	check(sim.FieldOps.resume(sim,site.id,u.id),"existing Resume surface handles infantry digging")
	check(site.position_progress==progress,"resumption retains earned progress")
	site.hp-=10.0
	complete(sim,site)
	check(site.position_stage==1 and is_equal_approx(site.max_hp,Positions.HASTY_HP),"completion publishes hasty durability")
	check(sim.terrain.cover(site.pos) and not sim.terrain.dug_in(site.pos),"hasty cover is weaker than completed reinforced trench")
	check(site.hp<site.max_hp-9.9,"completion preserves incoming damage")
	check(Positions.jobs(sim).is_empty() and u.members.all(func(m):return not sim.Infantry.task_busy(m)),"completion releases actor and site claims")
	check(sim.terrain.traversable(site.pos,"land",0.8),"prepared zone remains physically traversable")
	check(sim.credits==funds,"completed hasty work still has no supply charge")

func unsafe_and_loss()->void:
	var sim=fixture()
	var u:Dictionary=sim.units[0]
	var site:=create(sim)
	if site.is_empty():return
	advance(sim,3.0)
	var progress:float=site.position_progress
	u.suppression=0.95
	Positions.tick(sim,0.5)
	check(site.position_progress==progress and site.build_paused,"unsafe pressure pauses construction without progress")
	check(u.members.all(func(m):return not sim.Infantry.task_busy(m)),"unsafe work frees hands for normal combat")
	check(u.members.any(func(m):return sim.Infantry.readiness_available(u,m)),"pressure pause does not keep a stale actor lock")
	check(Positions.jobs(sim).has(u.id) and u.has("building_id"),"safe resumption remains attached to the same assignment")
	u.suppression=0.0
	advance(sim,1.0)
	check(site.position_progress>progress,"safe work resumes with the original valid task")
	var job:Dictionary=Positions.jobs(sim)[u.id]
	var member:Dictionary=sim.Infantry.member_by_id(u,job.member)
	member.hp=0;sim.Infantry.publish(u)
	Positions.tick(sim,0.1)
	check(site.build_paused and site.engineer_id==-1 and not u.has("building_id"),"worker casualty releases job while keeping the site")
	check(sim.FieldOps.resume(sim,site.id,u.id),"another surviving soldier can explicitly replace the lost worker")
	site.hp=0
	Positions.tick(sim,0.1);sim.FieldOps.sync_obstacles(sim)
	check(Positions.jobs(sim).is_empty() and not u.has("building_id"),"destroyed site clears its worker and claims")
	check(not sim.terrain.cover(site.pos),"destroyed hasty site leaves no protective ghost")

func upgrade_and_accounting()->void:
	var sim=fixture()
	var u:Dictionary=sim.units[0]
	var site:=create(sim)
	if site.is_empty():return
	complete(sim,site)
	var engineer:Dictionary=sim.spawn("engineer",0,site.pos+Vector2(0,6))
	sim.rebuild_spatial();sim.rebuild_actor_spatial();sim.update_visibility()
	var funds:float=sim.credits
	var cost:float=sim.definitions.fighting_trench.cost
	check(Positions.issue_upgrade(sim,[u.id],site.id)==0 and sim.credits==funds,"ordinary infantry cannot buy the engineer upgrade")
	sim.credits=0.0
	var version:int=engineer.order_version
	check(Positions.issue_upgrade(sim,[engineer.id],site.id)==0 and engineer.order_version==version,"insufficient supply rejects upgrade before changing intent")
	sim.credits=funds
	check(Positions.issue_upgrade(sim,[engineer.id],site.id)==1,"nearby engineer reinforces an occupied position: "+sim.order_feedback)
	check(sim.credits==funds-cost and site.upgrade_paid and site.position_stage==1,"upgrade charges once and preserves hasty stage")
	check(sim.terrain.cover(site.pos) and not sim.terrain.dug_in(site.pos),"upgrade preparation retains existing hasty protection")
	var initial_job:Dictionary=Positions.jobs(sim)[engineer.id].duplicate(true)
	check(Positions.issue_upgrade(sim,[engineer.id],site.id)==1,"duplicate upgrade acknowledges already assigned work")
	check(Positions.jobs(sim)[engineer.id]==initial_job and engineer.order_version==initial_job.version and sim.credits==funds-cost,"duplicate upgrade preserves worker, route, assignment and one payment")
	advance(sim,4.0)
	var progress:float=site.position_progress
	check(progress>0 and site.build_left>0,"engineer earns real partial upgrade progress")
	sim.stop([engineer.id])
	advance(sim,0.5)
	check(site.position_progress==progress and sim.terrain.cover(site.pos),"interrupted upgrade keeps work and existing cover")
	sim.credits=0.0
	check(Positions.issue_upgrade(sim,[engineer.id],site.id)==1,"paid upgrade resumes with zero supply")
	check(sim.credits==0.0 and site.position_progress==progress,"resume cannot charge twice or reset work")
	complete(sim,site)
	check(site.position_stage==2 and is_equal_approx(site.max_hp,float(sim.definitions.fighting_trench.hp)),"completed upgrade gains existing reinforced trench capacity")
	check(sim.terrain.dug_in(site.pos),"completed upgrade publishes stronger trench protection")
	check(Positions.issue_upgrade(sim,[engineer.id],site.id)==0 and sim.credits==0.0,"completed upgrade cannot be repurchased")
	var fresh=fixture()
	var unfinished:=create(fresh)
	if unfinished.is_empty():return
	advance(fresh,2.0)
	var before:float=fresh.credits
	check(fresh.FieldOps.cancel(fresh,unfinished.id),"explicit cancellation removes unfinished hasty work")
	check(fresh.credits==before and not fresh.alive(unfinished),"free work cannot mint a cancellation refund")
	check(not fresh.FieldOps.cancel(fresh,unfinished.id) and fresh.credits==before,"repeat cancellation cannot refund twice")
	var salvage=fixture()
	var free_site:=create(salvage)
	if free_site.is_empty():return
	complete(salvage,free_site)
	var clearer:Dictionary=salvage.spawn("engineer",0,free_site.pos+Vector2(0,7))
	salvage.rebuild_spatial();salvage.rebuild_actor_spatial();salvage.update_visibility()
	var balance:float=salvage.credits
	check(salvage.FieldOps.clear_site(salvage,free_site.id,clearer.id),"existing engineer clearing accepts a completed hasty position")
	check(Positions.issue_upgrade(salvage,[clearer.id],free_site.id)==0,"clearing and upgrading cannot claim the same site")
	for i in 1500:
		salvage.tick(1.0/30.0)
		if not salvage.alive(free_site):break
	check(not salvage.alive(free_site) and salvage.credits==balance,"dismantling time-only work cannot mint salvage supplies")
	var paid=fixture()
	var paid_site:=create(paid)
	if paid_site.is_empty():return
	complete(paid,paid_site)
	var builder:Dictionary=paid.spawn("engineer",0,paid_site.pos+Vector2(0,6))
	paid.rebuild_spatial();paid.rebuild_actor_spatial();paid.update_visibility()
	check(Positions.issue_upgrade(paid,[builder.id],paid_site.id)==1,"refund fixture buys one upgrade")
	advance(paid,4)
	var charged:float=paid.credits
	var refund:float=cost*paid_site.build_left/paid_site.position_total
	check(paid.FieldOps.cancel(paid,paid_site.id),"explicit cancellation can dismantle a partly upgraded site")
	check(is_equal_approx(paid.credits,charged+refund) and refund<cost,"cancellation returns only unused paid upgrade work")
	check(not paid.FieldOps.cancel(paid,paid_site.id) and is_equal_approx(paid.credits,charged+refund),"paid cancellation refunds exactly once")

func faction_and_claims()->void:
	var sim=fixture()
	var enemy:Dictionary=sim.spawn("rifle",1,Vector2(52,36))
	sim.rebuild_spatial();sim.rebuild_actor_spatial();sim.update_visibility()
	check(Positions.issue_dig(sim,[enemy.id],enemy.pos)==1,"enemy infantry use the same physical digging executor")
	var site:Dictionary=sim.units.back()
	var rival:Dictionary=sim.spawn("rifle",1,enemy.pos+Vector2(0,6))
	sim.rebuild_spatial();sim.rebuild_actor_spatial()
	var version:int=rival.order_version
	check(Positions.issue_dig(sim,[rival.id],site.pos)==0 and rival.order_version==version,"another section cannot steal a claimed work site")
	complete(sim,site)
	check(site.position_stage==1 and sim.terrain.cover(site.pos),"enemy completed work publishes identical hasty protection")
	var engineer:Dictionary=sim.spawn("engineer",1,site.pos+Vector2(6,0))
	sim.rebuild_spatial();sim.rebuild_actor_spatial()
	check(Positions.issue_upgrade(sim,[engineer.id],site.id)==0,"enemy upgrade needs an explicitly available construction budget")
	var cost:float=sim.definitions.fighting_trench.cost
	sim.field_ops["enemy_engineer_supply"]=cost
	var player_supply:float=sim.credits
	check(Positions.issue_upgrade(sim,[engineer.id],site.id)==1,"enemy upgrade uses the same bounded work after funding")
	check(sim.field_ops.enemy_engineer_supply==0.0 and sim.credits==player_supply,"enemy work consumes its authorized budget without changing player supply")
	complete(sim,site)
	check(site.position_stage==2 and sim.terrain.dug_in(site.pos),"enemy reinforcement has the same completed protection")

func replacement_releases_reserve()->void:
	var sim=fixture()
	var u:Dictionary=sim.units[0]
	sim.stop([u.id])
	check(sim.set_reserve([u.id],true)==1,"held infantry can delegate backup before a work order")
	var site:=create(sim)
	if site.is_empty():return
	check(not u.reserve_enabled and not sim.support_requests.reserves.has(u.id),"accepted digging immediately revokes the previous reserve delegation")
	complete(sim,site)
	var engineer:Dictionary=sim.spawn("engineer",0,site.pos+Vector2(0,6))
	sim.rebuild_spatial();sim.rebuild_actor_spatial();sim.update_visibility()
	sim.stop([engineer.id]);sim.set_reserve([engineer.id],true)
	var funds:float=sim.credits
	sim.credits=0.0
	check(Positions.issue_upgrade(sim,[engineer.id],site.id)==0 and engineer.reserve_enabled,"rejected unpaid upgrade preserves reserve delegation")
	sim.credits=funds
	check(Positions.issue_upgrade(sim,[engineer.id],site.id)==1,"delegated engineer accepts a funded local upgrade")
	check(not engineer.reserve_enabled and not sim.support_requests.reserves.has(engineer.id),"accepted upgrade revokes reserve delegation before work starts")
	var active=fixture()
	var provider:Dictionary=active.units[0]
	var sender:Dictionary=active.spawn("rifle",0,Vector2(40,36))
	active.stop([provider.id,sender.id])
	active.rebuild_spatial();active.rebuild_actor_spatial();active.update_visibility()
	active.set_reserve([provider.id],true)
	check(active.request_backup([sender.id])==1,"active service fixture requests real existing backup")
	active.time+=0.3
	active.SupportRequests.tick(active,0.3)
	var request:Dictionary=active.SupportRequests.request_for(active,sender)
	check(request.phase=="accepted" and request.provider==provider.id,"provider holds the backup lease before its explicit work replacement")
	check(Positions.issue_dig(active,[provider.id],provider.pos)==1,"a direct digging order supersedes accepted backup")
	check(request.phase=="cancelled" and not active.SupportRequests.owns_maneuver(provider),"work replacement immediately cancels obsolete support without a stale return")
	check(not active.actions.claims.has("backup:provider:%d"%provider.id) and not active.actions.claims.has("backup:request:%d"%request.id),"work replacement releases the previous exclusive support claims")
	check(Positions.jobs(active).has(provider.id) and not provider.reserve_enabled,"only the new work assignment remains authorized")

func work_needs_actual_cover_weapon()->void:
	var sim=fixture()
	var u:Dictionary=sim.spawn("atgm",0,Vector2(48,36))
	var gunner:Dictionary=u.members[0]
	var worker:Dictionary=u.members[1]
	var enemy:Dictionary=sim.spawn("rifle",1,Vector2(58,36))
	sim.rebuild_spatial();sim.rebuild_actor_spatial();sim.update_visibility()
	u.target=enemy.id
	gunner.readiness_weapon="atgm";gunner.rounds=1
	gunner.magazines.atgm=1;gunner.magazines.rifle=0
	check(sim.contact_known(u,enemy) and sim.weapon_reaches("atgm",gunner.pos,enemy),"work-cover fixture observes infantry within its loaded launcher's range")
	check(not Positions._safe(sim,u,worker),"a loaded launcher cannot cover digging when the actual anti-infantry rifle is empty")
	gunner.magazines.rifle=6
	check(Positions._safe(sim,u,worker),"a ready rifle with a real lane can cover its working teammate")
	gunner["hull_yield"]={"until":sim.time+1.0}
	check(not Positions._safe(sim,u,worker),"a supporter displaced by a hull cannot promise cover for digging")
	gunner.erase("hull_yield")
	enemy.pos=gunner.pos+Vector2(17,0)
	for member in enemy.members:member.pos=enemy.pos+Vector2(0,float(member.index)*1.7)
	sim.rebuild_spatial();sim.rebuild_actor_spatial();sim.update_visibility()
	check(sim.contact_known(u,enemy) and sim.weapon_reaches("atgm",gunner.pos,enemy) and not sim.weapon_reaches("rifle",gunner.pos,enemy),"range fixture separates a real launcher lane from the shorter rifle lane")
	check(not Positions._safe(sim,u,worker),"digging cannot borrow launcher range against exposed infantry")

func engineer_support_fixture()->Dictionary:
	var sim=fixture()
	var sender:Dictionary=sim.units[0]
	var engineer:Dictionary=sim.spawn("engineer",0,Vector2(40,36))
	sim.stop([sender.id,engineer.id])
	sim.rebuild_spatial();sim.rebuild_actor_spatial();sim.update_visibility()
	sim.set_reserve([engineer.id],true)
	sim.request_backup([sender.id])
	sim.time+=0.3
	sim.SupportRequests.tick(sim,0.3)
	var request:Dictionary=sim.SupportRequests.request_for(sim,sender)
	check(request.get("phase","")=="accepted" and request.provider==engineer.id,"ordinary-work fixture starts with a real engineer backup lease")
	return {"sim":sim,"engineer":engineer,"request":request}

func check_engineer_override(f:Dictionary,label:String)->void:
	var sim=f.sim
	var engineer:Dictionary=f.engineer
	check(f.request.phase=="cancelled" and not sim.SupportRequests.owns_maneuver(engineer),label+" immediately cancels the old lease without stale return motion")
	check(not engineer.reserve_enabled and not sim.support_requests.reserves.has(engineer.id),label+" revokes the old reserve delegation")
	check(not sim.actions.claims.has("backup:provider:%d"%engineer.id) and not sim.actions.claims.has("backup:request:%d"%f.request.id),label+" releases both exclusive support claims")

func ordinary_engineer_orders_release_reserve()->void:
	var f:=engineer_support_fixture()
	var sim=f.sim
	var engineer:Dictionary=f.engineer
	var version:int=engineer.order_version
	var funds:float=sim.credits
	sim.credits=0.0
	check(not sim.FieldOps.build(sim,"tactical_cover",Vector2(48,36),engineer.id),"unfunded ordinary construction is rejected before replacing support")
	check(engineer.reserve_enabled and engineer.order_version==version and f.request.phase=="accepted","rejected ordinary construction preserves delegation, order and active lease")
	sim.credits=funds
	check(sim.FieldOps.build(sim,"tactical_cover",Vector2(48,36),engineer.id),"delegated engineer accepts an ordinary paid work order")
	check_engineer_override(f,"ordinary construction")
	var site:Dictionary=sim.units.back()
	check(engineer.get("building_id",-1)==site.id and sim.credits==funds-float(sim.definitions.tactical_cover.cost),"only the accepted construction owns the engineer and incurs its single payment")
	# A player can explicitly delegate future reserve duty during paid work.
	# Internal continuation of that work is not a new replacement command.
	sim.set_reserve([engineer.id],true)
	version=engineer.order_version;funds=sim.credits
	check(sim.FieldOps.resume(sim,site.id,engineer.id,false),"an existing paid work assignment can continue through its internal resume adapter")
	check(engineer.reserve_enabled and engineer.order_version==version and sim.credits==funds,"internal work continuation retains later delegation, accepted order version and payment")
	check(sim.FieldOps.resume(sim,site.id,engineer.id),"explicit Resume is accepted for the same paid site")
	check(not engineer.reserve_enabled and engineer.order_version>version and sim.credits==funds,"explicit Resume ends delegation without charging the already paid site again")

	f=engineer_support_fixture();sim=f.sim;engineer=f.engineer
	version=engineer.order_version
	check(not sim.FieldOps.clear_site(sim,-1,engineer.id),"invalid ordinary clearing is rejected")
	check(engineer.reserve_enabled and engineer.order_version==version and f.request.phase=="accepted","rejected clearing preserves the active reserve lease")
	sim.FieldOps.spawn_prepared_works(sim,[{"kind":"tactical_cover","position":[50,36]}],0)
	site=sim.units.back()
	check(sim.FieldOps.clear_site(sim,site.id,engineer.id),"delegated engineer accepts ordinary obstacle clearing")
	check_engineer_override(f,"obstacle clearing")
	check(engineer.get("clearing_id",-1)==site.id and site.get("cleared_by",-1)==engineer.id,"accepted obstacle work owns the engineer after support ends")

	f=engineer_support_fixture();sim=f.sim;engineer=f.engineer
	version=engineer.order_version
	check(not sim.FieldOps.clear_wreck(sim,-1,engineer.id),"invalid wreck clearing is rejected")
	check(engineer.reserve_enabled and engineer.order_version==version and f.request.phase=="accepted","rejected wreck clearing preserves the active reserve lease")
	var hull:Dictionary=sim.spawn("tank",1,Vector2(52,36))
	sim.VehicleDamage.ensure_state(sim,hull)
	hull.hp-=sim.VehicleDamage._finish(sim,hull,hull.hp+1.0)
	sim.FieldOps.sync_obstacles(sim)
	check(sim.FieldOps.clear_wreck(sim,hull.id,engineer.id),"delegated engineer accepts clearing a real destroyed hull")
	check_engineer_override(f,"wreck clearing")
	check(engineer.get("clearing_id",-1)==hull.id,"accepted wreck work owns the engineer after support ends")

func visuals()->void:
	var sim=fixture()
	var site:=create(sim)
	if site.is_empty():return
	var model:=Node3D.new()
	var original:=MeshInstance3D.new();original.mesh=BoxMesh.new();model.add_child(original)
	Models.sync_construction(model,site)
	check(not original.visible and model.get_node("PositionSurvey").visible and not model.get_node("HastyEarth").visible,"survey presentation is only a marker, without finished trench mesh")
	site.position_stage=1;site.build_left=0.0
	Models.sync_construction(model,site)
	check(not original.visible and not model.get_node("PositionSurvey").visible and model.get_node("HastyEarth").visible,"hasty presentation shows shallow earth separately")
	site.position_stage=2
	Models.sync_construction(model,site)
	check(original.visible and not model.get_node("HastyEarth").visible,"completed reinforced site uses original trench presentation")
	model.free()

func run()->void:
	eligibility()
	preview_knowledge()
	worker_spatial_relocation()
	staged_work_and_cancellation()
	unsafe_and_loss()
	upgrade_and_accounting()
	faction_and_claims()
	replacement_releases_reserve()
	work_needs_actual_cover_weapon()
	ordinary_engineer_orders_release_reserve()
	visuals()
	print("FIELD POSITIONS: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
