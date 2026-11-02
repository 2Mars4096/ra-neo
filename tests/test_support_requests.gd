extends SceneTree

const Sim=preload("res://scripts/simulation.gd")
const Support=preload("res://scripts/support_requests.gd")
const Infantry=preload("res://scripts/infantry.gd")
const Terrain=preload("res://scripts/terrain.gd")
const DT:=1.0/30.0
var checks:=0
var failures:=0

func _init()->void:call_deferred("run")

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func field():
	var sim=Sim.new(false,0)
	sim.scenario=sim.scenario.duplicate(true)
	sim.scenario.autonomy=true
	sim.scenario.jam_radius=0.0
	sim.enemy_clock=100000.0
	sim.tactical_clock=100000.0
	sim.terrain.style="showcase"
	return sim

func fixture()->Dictionary:
	var sim=field()
	var sender:Dictionary=sim.spawn("rifle",0,Vector2(20,54))
	var reserve:Dictionary=sim.spawn("rifle",0,Vector2(12,66))
	sim.stop([sender.id,reserve.id])
	return {"sim":sim,"sender":sender,"reserve":reserve}

func step_broker(sim,seconds:float=0.3)->void:
	sim.time+=seconds
	sim.action_tick+=1
	sim.route_budget=sim.ROUTE_BUDGET
	sim.actions.begin_tick(sim.action_tick)
	Support.tick(sim,seconds)

func dispatch(f:Dictionary)->Dictionary:
	Support.set_reserve(f.sim,[f.reserve.id],true)
	Support.request_backup(f.sim,[f.sender.id])
	step_broker(f.sim)
	return Support.request_for(f.sim,f.sender)

func move_section(u:Dictionary,point:Vector2)->void:
	var delta:Vector2=point-u.pos
	u.pos=point
	for member in u.members:member.pos+=delta;member.travel=0.0

func delegation_and_competition()->void:
	var f:=fixture()
	var sim=f.sim
	var credits:float=sim.credits
	check(not f.reserve.get("reserve_enabled",false),"a section is not a reserve by default")
	check(Support.request_backup(sim,[f.sender.id])==1,"connected infantry can request nearby backup")
	step_broker(sim)
	check(Support.request_for(sim,f.sender).phase=="unavailable","unassigned guards are not silently dispatched")
	check(f.reserve.hold_command and f.reserve.maneuver.is_empty(),"unavailable request preserves the explicit guard")
	check(sim.credits==credits and sim.units.size()==2,"request neither purchases nor spawns troops")
	check(Support.request_backup(sim,[f.sender.id])==0,"unavailable requests back off repeated calls")
	sim.time+=Support.RETRY_SECONDS
	var other:Dictionary=sim.spawn("rifle",0,Vector2(20,62))
	sim.stop([other.id])
	var version:int=f.reserve.order_version
	var assignment:int=f.reserve.assignment.id
	check(Support.set_reserve(sim,[f.reserve.id],true)==1,"explicit Reserve authorizes an existing held section")
	check(f.reserve.hold_command and f.reserve.order_version==version and f.reserve.assignment.id==assignment,"delegation alone does not replace the current hold assignment")
	Support.request_backup(sim,[f.sender.id,other.id])
	var first:Dictionary=Support.request_for(sim,f.sender)
	var next_id:int=sim.support_requests.next_id
	Support.request_backup(sim,[f.sender.id])
	check(sim.support_requests.next_id==next_id,"duplicate calls merge without extending the request or generating a second token")
	step_broker(sim)
	var second:Dictionary=Support.request_for(sim,other)
	check(first.provider==f.reserve.id and first.phase=="accepted","the first request acknowledges one eligible reserve")
	check(second.provider==-1 and second.phase=="unavailable","a second section cannot claim the same reserve")
	check(sim.actions.claims.has("backup:request:%d"%first.id) and sim.actions.claims.has("backup:provider:%d"%f.reserve.id),"accepted service holds both exclusive claims")
	check(f.reserve.order_version==version and f.reserve.assignment.id==assignment,"temporary support retains its parent assignment identity")
	check(sim.credits==credits and sim.units.size()==3,"matching still spends no resources and creates no units")

func capability_and_real_usefulness()->void:
	var f:=fixture()
	var sim=f.sim
	f.reserve.fire_policy="hold"
	var req:=dispatch(f)
	check(req.phase=="unavailable" and not Support.owns_maneuver(f.reserve),"Hold fire cannot be overridden by a backup request")
	f=fixture();sim=f.sim
	for member in f.reserve.members:member.rounds=0
	req=dispatch(f)
	check(req.phase=="unavailable","a section with no loaded supporter is not counted as ready backup")
	f=fixture();sim=f.sim
	f.reserve.members[0]["task_action"]=123
	req=dispatch(f)
	check(req.phase=="unavailable","an actor preparing a throw or work task is not borrowed")
	f=fixture();sim=f.sim
	f.reserve["garrison"]=12
	req=dispatch(f)
	check(req.phase=="unavailable","an occupied garrison is not stripped for a nearby call")
	f=fixture();sim=f.sim
	f.reserve.hp=0.0
	f.reserve=sim.spawn("atgm",0,Vector2(12,66))
	sim.stop([f.reserve.id])
	var operator:Dictionary=f.reserve.members[0]
	operator.readiness_weapon="rifle";operator.rounds=6;operator.magazines.atgm=0
	sim.spawn("tank",1,Vector2(20,43))
	sim.update_visibility()
	req=dispatch(f)
	check(req.observation.kind=="tank" and req.phase=="unavailable","a loaded rifle does not disguise an empty specialist launcher against armor")
	f=fixture();sim=f.sim
	req=dispatch(f)
	move_section(f.reserve,Vector2(14,50))
	req.origin=Vector2(20,50)
	req.observation={"id":-1,"kind":"rifle","pos":Vector2(24,50),"observed_at":sim.time,"source":"sensor"}
	check(Support.useful(sim,f.reserve,req),"loaded members in range with a real firing lane can provide support")
	for member in f.reserve.members:member.aiding=1
	check(not Support.useful(sim,f.reserve,req),"being stationary while treating casualties is not useful covering support")
	for member in f.reserve.members:member.aiding=-1;member.reload_until=sim.time+2.0
	check(not Support.useful(sim,f.reserve,req),"reloading supporters cannot complete the request")
	for member in f.reserve.members:Infantry.cancel_readiness(member)
	sim.terrain.update_field_geometry([Rect2(18,44,2,20)],[])
	check(not Support.useful(sim,f.reserve,req),"arrival behind an obstructing wall does not count as delivered backup")

func observation_snapshot()->void:
	var f:=fixture()
	var sim=f.sim
	var enemy:Dictionary=sim.spawn("rifle",1,Vector2(20,43))
	sim.update_visibility()
	var fact:Dictionary=sim.context.team_contact(0,enemy.id,sim.time)
	check(not fact.is_empty(),"snapshot fixture acquires a real sensor contact")
	Support.request_backup(sim,[f.sender.id])
	var req:Dictionary=Support.request_for(sim,f.sender)
	var observed:Vector2=req.observation.pos
	move_section(enemy,Vector2(65,60))
	sim.time+=1.0;sim.update_visibility()
	check(req.observation.pos==observed and req.observation.id==enemy.id,"request preserves the copied observation instead of tracking hidden motion")
	check(req.observation.observed_at==fact.observed_at,"copied threat retains its real observation timestamp")
	f.sender.facing=Vector2.RIGHT
	check(req.origin==Vector2(20,54),"request origin does not follow later requester movement or facing")

func specialist_support_uses_actual_weapon()->void:
	var f:=fixture()
	var sim=f.sim
	f.reserve.hp=0.0
	f.reserve=sim.spawn("atgm",0,Vector2(12,66))
	sim.stop([f.reserve.id])
	var operator:Dictionary=f.reserve.members[0]
	for member in f.reserve.members:member.rounds=0
	operator.readiness_weapon="atgm";operator.rounds=1
	operator.magazines.atgm=1;operator.magazines.rifle=0
	sim.spawn("rifle",1,Vector2(20,43))
	sim.update_visibility()
	var req:=dispatch(f)
	check(req.observation.kind=="rifle" and req.phase=="unavailable","a loaded launcher cannot disguise an empty rifle for infantry backup")
	sim.time+=Support.RETRY_SECONDS
	operator.readiness_weapon="rifle";operator.rounds=6
	operator.magazines.rifle=6;operator.magazines.atgm=0
	Support.request_backup(sim,[f.sender.id])
	step_broker(sim)
	req=Support.request_for(sim,f.sender)
	check(req.phase=="accepted","a loaded specialist rifle can answer infantry backup while its launcher is empty")
	move_section(f.reserve,Vector2(14,50))
	operator.pos=Vector2(14,50)
	operator.readiness_weapon="atgm";operator.rounds=1
	operator.magazines.atgm=1;operator.magazines.rifle=6
	req.origin=Vector2(20,50)
	req.observation={"id":-1,"kind":"rifle","pos":Vector2(30,50),"observed_at":sim.time,"source":"sensor"}
	check(sim.optical_ray_clear(Vector3(14,1.6,50),Vector3(30,1.6,50)),"specialist-range fixture has an unobstructed copied frontage")
	check(not Support.useful(sim,f.reserve,req),"launcher range cannot count as rifle support for exposed infantry")
	check(not Support._point_useful(sim,f.reserve,req,Vector2(14,50)),"support placement uses the same rifle range as delivered support")
	req.observation.pos=Vector2(24,50)
	check(Support.useful(sim,f.reserve,req),"loaded specialist rifle provides useful nearby infantry support")
	req.observation.kind="tank";req.observation.pos=Vector2(30,50)
	check(Support.useful(sim,f.reserve,req),"loaded launcher retains its longer useful support range against armor")
	req.observation.kind="";req.observation.source="requested_frontage"
	check(not Support.useful(sim,f.reserve,req),"an unobserved frontage does not invent a launcher target or its longer firing range")

func replacement_and_losses()->void:
	var f:=fixture()
	var sim=f.sim
	var req:=dispatch(f)
	check(sim.issue([f.reserve.id],Vector2(24,66))==1,"player replacement for responding reserve is accepted")
	var version:int=f.reserve.order_version
	var assignment:Dictionary=f.reserve.assignment.duplicate(true)
	step_broker(sim)
	check(req.phase=="cancelled" and not Support.owns_maneuver(f.reserve),"a new order revokes the responder's exclusive service")
	check(not f.reserve.reserve_enabled and f.reserve.assignment==assignment,"new orders disable reserve delegation and retain their own intent")
	step_broker(sim,Support.LEASE_SECONDS+1.0)
	check(f.reserve.order_version==version and f.reserve.assignment==assignment,"late support completion never restores the superseded assignment")
	check(not sim.actions.claims.has("backup:provider:%d"%f.reserve.id),"retasking releases the provider claim")
	f=fixture();sim=f.sim;req=dispatch(f)
	step_broker(sim)
	f.reserve.hp=0.0
	step_broker(sim)
	check(req.phase=="cancelled" and sim.actions.active(f.reserve,"support").is_empty(),"a lost responder cancels the accepted task and releases its action")
	check(not Support.owns_maneuver(f.reserve),"dead responders retain no support ownership")
	check(f.reserve.maneuver.is_empty() and f.reserve.path.is_empty(),"a dead responder cannot leave an owned movement executor running")
	f=fixture();sim=f.sim;req=dispatch(f)
	check(sim.issue([f.sender.id],Vector2(27,58))==1,"requester can replace its objective")
	step_broker(sim)
	check(req.phase=="cancelled" and not Support.owns_maneuver(f.reserve),"acknowledged cancellation returns an unmoved reserve without stale work")
	check(f.reserve.hold_command,"return restores the authorized reserve's original hold")

func alternate_weapon_dispatch()->void:
	for armored in [false,true]:
		var f:=fixture()
		var sim=f.sim
		f.reserve.hp=0.0
		f.reserve=sim.spawn("atgm",0,Vector2(12,66))
		sim.stop([f.reserve.id])
		for member in f.reserve.members:
			member.rounds=0
			member.magazines.rifle=0
		var operator:Dictionary=f.reserve.members[0]
		operator.readiness_weapon="rifle" if armored else "atgm"
		operator.rounds=0
		operator.magazines.atgm=1 if armored else 0
		operator.magazines.rifle=0 if armored else 6
		var enemy_kind:String="tank" if armored else "rifle"
		sim.spawn(enemy_kind,1,Vector2(20,43))
		sim.update_visibility()
		var magazines:Dictionary=operator.magazines.duplicate(true)
		var missiles:int=sim.missiles_left(f.reserve)
		var req:=dispatch(f)
		check(req.observation.kind==enemy_kind and req.phase=="accepted" and req.provider==f.reserve.id,"backup dispatch selects the loaded alternate weapon against "+enemy_kind)
		check(operator.rounds==0 and operator.readiness_weapon==("rifle" if armored else "atgm") and operator.magazines==magazines and sim.missiles_left(f.reserve)==missiles,"backup eligibility preserves current weapon and both inventories against "+enemy_kind)
		move_section(f.reserve,Vector2(20,50))
		check(Support.useful(sim,f.reserve,req),"delivered support uses the same loaded alternate weapon against "+enemy_kind)
		operator.reload_weapon=operator.readiness_weapon;operator.reload_until=sim.time+2.0
		check(not Support.useful(sim,f.reserve,req),"active reload still suspends alternate-weapon backup against "+enemy_kind)
		check(operator.reload_until==sim.time+2.0 and operator.magazines==magazines,"support review preserves active reload and inventory against "+enemy_kind)
	var f:=fixture()
	var sim=f.sim
	f.reserve.hp=0.0
	f.reserve=sim.spawn("atgm",0,Vector2(12,66))
	sim.stop([f.reserve.id])
	for member in f.reserve.members:member.rounds=0
	var operator:Dictionary=f.reserve.members[0]
	operator.readiness_weapon="atgm";operator.rounds=0;operator.magazines.rifle=6
	operator.reload_weapon="atgm";operator.reload_until=sim.time+2.0
	sim.spawn("rifle",1,Vector2(20,43));sim.update_visibility()
	var req:=dispatch(f)
	check(req.phase=="unavailable" and not Support.owns_maneuver(f.reserve),"backup dispatch does not cancel a live launcher reload to borrow the rifle")

func radio_lease()->void:
	var f:=fixture()
	var sim=f.sim
	var req:=dispatch(f)
	var expires:float=req.lease_until
	# Separate by more than local signalling range after acceptance. The jam
	# is real scenario communications state, not a forged provider flag.
	move_section(f.reserve,Vector2(12,70))
	sim.scenario.jam_radius=100.0
	sim.objectives.clear();sim.objectives.append({"owner":1,"pos":Vector2(20,54)})
	check(sim.comms_blocked(f.sender) and sim.comms_blocked(f.reserve),"fixture genuinely loses radio after acknowledgement")
	Support.cancel_for_unit(sim,f.sender)
	step_broker(sim,0.3)
	check(req.get("cancel_pending",false) and req.phase not in Support.TERMINAL,"unacknowledged cancellation retains the accepted lease")
	check(sim.actions.claims.has("backup:provider:%d"%f.reserve.id),"radio loss does not free a provider for duplicate service")
	check(req.lease_until==expires,"failed communication cannot silently renew the lease")
	sim.time=expires
	Support.tick(sim,DT)
	check(req.phase in ["return_pending","returning","awaiting_ack"] or req.phase in Support.TERMINAL,"provider stops exclusive service at its locally known expiry")
	check(not req.get("cancel_pending",false),"expired lease clears its unresolved cancellation")
	f=fixture();sim=f.sim;req=dispatch(f)
	# A nearby provider and requester can acknowledge locally despite jamming.
	move_section(f.reserve,Vector2(14,60))
	sim.scenario.jam_radius=100.0
	sim.objectives.clear();sim.objectives.append({"owner":1,"pos":Vector2(20,54)})
	Support.cancel_for_unit(sim,f.sender)
	check(not req.get("cancel_pending",false) and req.phase=="return_pending","nearby signalling acknowledges cancellation without a radio link")

func delivery_and_return()->void:
	var f:=fixture()
	var sim=f.sim
	var home:Vector2=f.reserve.pos
	var version:int=f.reserve.order_version
	var assignment:int=f.reserve.assignment.id
	var req:=dispatch(f)
	var delivered:=false
	var moved:=false
	for tick in 750:
		sim.tick(DT)
		moved=moved or f.reserve.pos.distance_to(home)>3.0
		delivered=delivered or req.phase=="delivering"
		if req.phase in Support.TERMINAL:break
	check(moved and delivered,"actual simulation moves the reserve into a supporting role")
	check(req.phase=="completed" and float(req.service_time)>=Support.SERVICE_SECONDS,"completion requires a sustained useful-support interval")
	check(f.reserve.pos.distance_to(home)<=1.0,"completed backup returns to the reserved position")
	check(f.reserve.hold_command and f.reserve.order_version==version and f.reserve.assignment.id==assignment,"return restores hold without inventing or replacing the assignment")
	check(not Support.owns_maneuver(f.reserve) and sim.actions.active(f.reserve,"support").is_empty(),"return releases both broker and action ownership")
	check(f.reserve.reserve_enabled,"unchanged delegated reserve is available after returning")
	check(sim.units.size()==2,"the live support lifecycle preserves actual force count")

func blocked_and_bounded()->void:
	var f:=fixture()
	var sim=f.sim
	var req:=dispatch(f)
	for attempt in 12:
		step_broker(sim)
		if req.phase=="en_route":break
	check(req.phase=="en_route","blocked-route fixture receives a real support route")
	# Do not execute movement; a stale route must time out, not report success.
	step_broker(sim,6.0)
	check(req.phase=="return_pending" and req.outcome=="unavailable","no-progress timeout reports blocked support")
	step_broker(sim)
	check(req.phase=="unavailable" and req.service_time==0.0,"a blocked responder at home releases its claim without claiming delivery")
	check(not sim.actions.claims.has("backup:provider:%d"%f.reserve.id),"failure releases exclusive provider ownership")
	sim.time+=Support.HISTORY_SECONDS+1.0
	Support.tick(sim,DT)
	check(sim.support_requests.requests.is_empty() and sim.support_requests.retry_after.is_empty(),"terminal history and retries expire instead of growing without bound")

func useful_short_arrival()->void:
	var f:=fixture()
	var sim=f.sim
	var req:=dispatch(f)
	for attempt in 12:
		step_broker(sim)
		if req.phase=="en_route":break
	check(req.phase=="en_route","short-arrival fixture has a real planned supporting position")
	if req.phase!="en_route":return
	move_section(f.reserve,req.position+Vector2(0,1.5))
	var actual:Vector2=f.reserve.pos
	check(Support.useful(sim,f.reserve,req),"nearby physical stop already has loaded actors and a useful lane")
	step_broker(sim)
	check(req.phase=="delivering" and req.actual_position==actual,"a useful body-level stop can complete arrival without inventing its planned coordinates")
	check(f.reserve.path.is_empty() and f.reserve.maneuver.pos==actual,"support stops the obsolete remaining leg at its real position")

func provisional_replacement()->void:
	var f:=fixture()
	var sim=f.sim
	var req:=dispatch(f)
	var version:int=f.reserve.order_version
	var assignment:Dictionary=f.reserve.assignment.duplicate(true)
	var support_action:Dictionary=sim.actions.active(f.reserve,"support")
	sim.click_slots=0
	check(sim.issue([f.reserve.id],Vector2(98,66))==1 and f.reserve.orders[0].has("slot"),"unresolved group placement is represented as a provisional order")
	check(f.reserve.reserve_enabled and Support.owns_maneuver(f.reserve) and sim.actions.valid(f.reserve,support_action,sim.time),"pending placement preserves the accepted reserve delegation and action lease")
	sim.resolve_slots()
	check(f.reserve.assignment==assignment and f.reserve.order_version==version,"rejected water destination restores the reserve's accepted assignment")
	check(f.reserve.reserve_enabled and req.phase=="accepted" and sim.actions.valid(f.reserve,support_action,sim.time),"rejected placement does not cancel existing support")
	sim.click_slots=0
	check(sim.issue([f.reserve.id],Vector2(24,66))==1 and f.reserve.orders[0].has("slot"),"reachable replacement can also await group placement")
	check(f.reserve.reserve_enabled and req.phase=="accepted","reachable but unresolved command still preserves delegation")
	sim.resolve_slots()
	check(f.reserve.order_version>version and f.reserve.assignment.pos==Vector2(24,66),"successful resolution accepts the actual replacement order")
	check(not f.reserve.reserve_enabled and not Support.owns_maneuver(f.reserve) and req.phase=="cancelled","accepted resolution cancels old support and revokes reserve authority")
	check(sim.actions.active(f.reserve,"support").is_empty(),"accepted deferred replacement releases the exclusive service action")

func clearing_waits_before_reserve(wreck:bool)->void:
	var sim=field()
	sim.terrain=Terrain.new(0,{"id":"reserve_clearing_fixture","size":[96,72],"shore_x":90,"port":false,
		"mode":"field_ops","style":"showcase","blocks":[],"woods":[],"rubble":[0,0,0,0],
		"mud":[0,0,0,0],"objectives":[],"roads":{}})
	sim.terrain.roadside_blocks.clear();sim.terrain.prop_blocks.clear();sim.terrain.trees.clear()
	sim.terrain.rebuild_static_index()
	sim.objectives.clear()
	sim.FieldOps.setup(sim)
	var sender:Dictionary=sim.spawn("rifle",0,Vector2(24,36))
	var engineer:Dictionary=sim.spawn("engineer",0,Vector2(40,36))
	var site:Dictionary
	var label:String="wreck clearing" if wreck else "obstacle clearing"
	var accepted:bool
	if wreck:
		var hull:Dictionary=sim.spawn("tank",1,Vector2(52,36))
		sim.VehicleDamage.ensure_state(sim,hull)
		hull.hp-=sim.VehicleDamage._finish(sim,hull,hull.hp+1.0)
		sim.FieldOps.sync_obstacles(sim)
		accepted=sim.FieldOps.clear_wreck(sim,hull.id,engineer.id)
		site=sim.VehicleDamage.wreck_by_id(sim,hull.id)
	else:
		sim.FieldOps.spawn_prepared_works(sim,[{"kind":"tactical_cover","position":[50,36]}],0)
		site=sim.units.back()
		accepted=sim.FieldOps.clear_site(sim,site.id,engineer.id)
	check(accepted,label+" fixture accepts a real engineer work order")
	if not accepted:return
	# Arrive at the executor's real work point. No queued movement remains,
	# but the accepted clearing job still owns the otherwise-ready section.
	move_section(engineer,site.clear_point)
	engineer.orders.clear();engineer.path.clear()
	sim.rebuild_spatial();sim.rebuild_actor_spatial();sim.update_visibility()
	var version:int=engineer.order_version
	var assignment:Dictionary=engineer.assignment.duplicate(true)
	if wreck:
		sim.FieldOps.progress_wreck_clearing(sim,0.1)
		check(float(site.get("clear_done",0.0))>0,label+" makes actual progress before a backup call")
	else:
		var hp:float=site.hp
		sim.FieldOps.progress_clearing(sim,0.1)
		check(site.hp<hp,label+" makes actual progress before a backup call")
	check(Support.set_reserve(sim,[engineer.id],true)==1,label+" permits explicit future reserve delegation")
	Support.request_backup(sim,[sender.id]);step_broker(sim)
	var request:Dictionary=Support.request_for(sim,sender)
	check(request.phase=="unavailable" and not Support.owns_maneuver(engineer),label+" cannot be borrowed while its current job is unfinished")
	check(engineer.reserve_enabled and engineer.get("clearing_id",-1)==site.id and engineer.order_version==version and engineer.assignment==assignment,label+" retains both the work assignment and newly authorized reserve flag")
	if wreck:sim.FieldOps.progress_wreck_clearing(sim,sim.VehicleDamage.clear_seconds(site)+1.0)
	else:sim.FieldOps.progress_clearing(sim,float(sim.FieldOps.CLEAR_SECONDS[site.kind])+1.0)
	check(not engineer.has("clearing_id") and engineer.reserve_enabled,label+" completion releases the worker without erasing future reserve duty")
	step_broker(sim,Support.RETRY_SECONDS+0.1)
	check(Support.request_backup(sim,[sender.id])==1,label+" allows a fresh request after the earlier unavailable result")
	step_broker(sim)
	request=Support.request_for(sim,sender)
	check(request.phase=="accepted" and request.provider==engineer.id,label+" becomes eligible for backup after ordinary work completion")

func run()->void:
	delegation_and_competition()
	capability_and_real_usefulness()
	observation_snapshot()
	specialist_support_uses_actual_weapon()
	alternate_weapon_dispatch()
	replacement_and_losses()
	radio_lease()
	delivery_and_return()
	blocked_and_bounded()
	useful_short_arrival()
	provisional_replacement()
	clearing_waits_before_reserve(false)
	clearing_waits_before_reserve(true)
	print("SUPPORT REQUESTS: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
