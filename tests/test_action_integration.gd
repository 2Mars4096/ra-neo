extends SceneTree

const Sim=preload("res://scripts/simulation.gd")
const Campaign=preload("res://scripts/regional_campaign.gd")
const Director=preload("res://scripts/tactical_director.gd")
const GarrisonSystem=preload("res://scripts/garrison.gd")
const Ops=preload("res://scripts/field_ops.gd")
const Structure=preload("res://scripts/structure_damage.gd")
const DT:=1.0/30.0
var checks:=0
var failures:=0
var paths:Array[String]=[]

func _init()->void:call_deferred("run")

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: ",label)

func field():
	var sim=Sim.new(false,0)
	sim.tactical_clock=100000.0
	sim.enemy_clock=100000.0
	return sim

func move_section(u:Dictionary,pos:Vector2)->void:
	var delta:Vector2=pos-u.pos
	u.pos=pos
	for member in u.members:member.pos+=delta

func orders_and_old_results()->void:
	var sim=field()
	var tank:Dictionary=sim.spawn("tank",0,Vector2(20,62))
	check(sim.issue([tank.id],Vector2(28,62))==1,"ordinary move is accepted")
	var version:int=tank.order_version
	var assignment:int=tank.assignment.id
	var first:Dictionary=tank.orders[0]
	check(sim.issue([tank.id],Vector2(36,62),"move",true)==1,"shift-queued movement is accepted")
	check(tank.order_version==version and tank.assignment.id==assignment and is_same(tank.orders[0],first),"queueing preserves the currently executing assignment")
	sim.finish_order(tank)
	check(tank.order_version==version and tank.assignment.id!=assignment and tank.assignment.pos==Vector2(36,62),"next queued command activates without inventing a player replacement")
	var next_assignment:Dictionary=tank.assignment.duplicate(true)
	check(sim.issue([tank.id],Vector2(98,62))==0,"invalid sea destination rejects a land-unit order")
	check(tank.assignment==next_assignment and tank.order_version==version,"rejected movement leaves accepted intent intact")
	# Defer the next route, then replace it before the route worker can finish.
	sim.route_budget=-1.0
	check(sim.issue([tank.id],Vector2(52,62))==1 and tank.has("route_pending"),"long move can be accepted while its route is pending")
	sim.route_budget=sim.ROUTE_BUDGET
	check(sim.issue([tank.id],Vector2(20,54))==1,"replacement for pending route is accepted")
	var replacement:Dictionary=tank.assignment.duplicate(true)
	var route:Array=tank.path.duplicate(true)
	sim.plan_queued_routes()
	check(tank.assignment==replacement and tank.path==route,"obsolete queued route cannot overwrite the replacement's route or assignment")
	check(not tank.has("route_pending"),"obsolete pending work is removed")

func provisional_orders()->void:
	var sim=field()
	var tank:Dictionary=sim.spawn("tank",0,Vector2(20,62))
	sim.issue([tank.id],Vector2(30,62))
	var accepted:Dictionary=tank.assignment.duplicate(true)
	var old_orders:Array=tank.orders.duplicate(true)
	var old_action:Dictionary=sim.actions.observe_existing(tank,"weapon","aim",sim.time,{"unit":99},"aiming")
	sim.click_slots=0
	check(sim.issue([tank.id],Vector2(98,62))==1 and tank.orders[0].has("slot"),"large-group path records a provisional unresolved slot")
	check(tank.assignment==accepted and sim.actions.valid(tank,old_action,sim.time),"unresolved placement does not cancel accepted ownership")
	sim.resolve_slots()
	check(tank.orders==old_orders and tank.assignment==accepted,"failed provisional placement restores accepted orders and assignment")
	check(sim.actions.valid(tank,old_action,sim.time),"failed provisional placement preserves the old action")
	check(sim.issue([tank.id],Vector2(32,62))==1,"valid replacement can await slot resolution")
	sim.resolve_slots()
	check(tank.order_version==int(accepted.version)+1 and old_action.phase=="cancelled","successful provisional resolution cancels old work exactly when accepted")
	check(sim.issue([tank.id],Vector2(36,62))==1,"another provisional command enters the queue")
	sim.click_slots=8
	check(sim.issue([tank.id],Vector2(20,55))==1,"new direct command supersedes the unresolved slot")
	var replacement:Dictionary=tank.assignment.duplicate(true)
	sim.resolve_slots()
	check(tank.assignment==replacement and tank.orders[0].pos==replacement.pos,"late slot resolution cannot revive a superseded command")

func provisional_attack_execution()->void:
	for lost in [false,true]:
		var sim=field()
		var tank:Dictionary=sim.spawn("tank",0,Vector2(20,62))
		var target:Dictionary=sim.spawn("tank",1,Vector2(35,62))
		target.seen_by[0]=true
		sim.issue([tank.id],Vector2(20,52))
		var accepted:Dictionary=tank.assignment.duplicate(true)
		var previous_orders:Array=tank.orders.duplicate(true)
		var previous_route:Array=tank.path.duplicate(true)
		var origin:Vector2=tank.pos
		# Leave routes available: a deferred attack must not bypass the denied
		# placement by launching the ordinary pursuit path from move_unit.
		sim.terrain.planning.begin_tick(1,{"formation":0,"routes":8})
		check(sim.issue([tank.id],target.pos,"attack",false,target.id)==1 and tank.orders[0].has("slot"),"attack can wait for bounded placement without accepting ownership")
		if lost:target.hp=0.0
		sim.move_unit(tank,0.25)
		check(tank.pos==origin and tank.path.is_empty() and tank.orders.size()==1 and tank.orders[0].has("slot"),"unresolved attack cannot pursue or finish while its target is %s"%("dead" if lost else "alive"))
		check(tank.assignment==accepted,"unresolved attack execution cannot change or revoke the accepted assignment")
		sim.terrain.planning.begin_tick(2)
		sim.resolve_slots()
		if lost:
			check(tank.orders==previous_orders and tank.path==previous_route and tank.assignment==accepted and not tank.has("provisional_before"),"dead provisional attack restores the original accepted movement and permission")
		else:
			check(tank.order_version==int(accepted.version)+1 and tank.assignment.target==target.id and not tank.orders[0].has("slot"),"live provisional attack takes ownership only after destination acceptance")

func queued_after_rejected_replacement()->void:
	for pending in [false,true]:
		var sim=field()
		var tank:Dictionary=sim.spawn("tank",0,Vector2(20,62))
		sim.issue([tank.id],Vector2(30,62))
		var accepted:Dictionary=tank.assignment.duplicate(true)
		var previous:Dictionary=tank.orders[0]
		sim.click_slots=0
		sim.issue([tank.id],Vector2(98,62))
		var rejected:Dictionary=tank.orders[0]
		sim.click_slots=0 if pending else 8
		check(sim.issue([tank.id],Vector2(36,62),"move",true)==1,"Shift order after provisional replacement is accepted")
		var queued:Dictionary=tank.orders[1]
		check(queued.has("slot")==pending,"queued-tail fixture exercises %s placement"%("pending" if pending else "resolved"))
		sim.resolve_slots()
		check(tank.orders.size()==2 and is_same(tank.orders[0],previous) and is_same(tank.orders[1],queued) and not tank.orders.has(rejected),"rejection restores accepted parent and retains later Shift order exactly once")
		check(not queued.has("slot") and tank.assignment==accepted,"retained queued result resolves without changing the current parent's ownership")
		sim.finish_order(tank)
		check(tank.orders.size()==1 and is_same(tank.orders[0],queued) and tank.assignment.pos==Vector2(36,62) and tank.order_version==accepted.version,"retained Shift order executes after its original parent without inventing a replacement version")
	# If the old state was idle, a retained shift order becomes the head and
	# must activate immediately instead of sitting without a route forever.
	var idle=field()
	var held:Dictionary=idle.spawn("tank",0,Vector2(20,62))
	idle.stop([held.id])
	idle.click_slots=0
	idle.issue([held.id],Vector2(98,62))
	idle.click_slots=8
	idle.issue([held.id],Vector2(30,62),"move",true)
	idle.resolve_slots()
	check(held.orders.size()==1 and held.assignment.mode=="move" and held.assignment.pos==Vector2(30,62) and not held.path.is_empty(),"rejection from an idle accepted state activates its later valid Shift order")
	for nested_accepts in [false,true]:
		var nested=field()
		var unit:Dictionary=nested.spawn("tank",0,Vector2(20,62))
		nested.issue([unit.id],Vector2(30,62))
		var original:Dictionary=unit.orders[0]
		var ownership:Dictionary=unit.assignment.duplicate(true)
		nested.click_slots=0
		nested.issue([unit.id],Vector2(98,62))
		nested.issue([unit.id],Vector2(36,62),"move",true)
		var queued:Dictionary=unit.orders[1]
		nested.issue([unit.id],Vector2(24,54) if nested_accepts else Vector2(98,55))
		for attempt in 4:nested.resolve_slots()
		if nested_accepts:
			check(unit.orders.size()==1 and unit.assignment.pos==Vector2(24,54) and unit.order_version==int(ownership.version)+1 and nested.slot_queue.is_empty(),"accepted newer replacement discards superseded saved tail without duplicate or orphan slots")
		else:
			check(unit.orders.size()==2 and is_same(unit.orders[0],original) and is_same(unit.orders[1],queued) and not queued.has("slot") and unit.assignment==ownership and nested.slot_queue.is_empty(),"rejected nested replacement restores accepted parent and resolves its saved pending tail")

func provisional_attack_permission()->void:
	var sim=Sim.new(false,5)
	sim.terrain.blocks.clear();sim.terrain.roadside_blocks.clear();sim.terrain.trees.clear();sim.terrain.poles.clear();sim.terrain.navigation.clear()
	var tank:Dictionary=sim.spawn("tank",0,Vector2(14,97))
	var original:Dictionary=sim.spawn("observation_post",1,Vector2(28,97))
	var replacement:Dictionary=sim.spawn("observation_post",1,Vector2(28,88))
	original.seen_by[0]=true;replacement.seen_by[0]=true
	sim.stop([tank.id])
	check(sim.select_combat_target(tank).is_empty(),"passive works are not an automatic combat target")
	sim.terrain.planning.begin_tick(1,{"formation":0,"routes":8})
	sim.issue([tank.id],original.pos,"attack",false,original.id)
	check(tank.orders[0].has("slot") and sim.ordered_target(tank)==-1 and sim.select_combat_target(tank).is_empty(),"unresolved attack cannot authorize fire against passive works")
	sim.terrain.planning.end_tick()
	sim.resolve_slots()
	sim.set_fire_policy([tank.id],"hold")
	check(sim.issue([tank.id],original.pos,"attack",false,original.id)==1 and sim.select_combat_target(tank).get("id",-1)==original.id,"accepted explicit attack scopes Hold fire to its passive target")
	var accepted:Dictionary=tank.assignment.duplicate(true)
	sim.terrain.planning.begin_tick(2,{"formation":0,"routes":8})
	sim.issue([tank.id],replacement.pos,"attack",false,replacement.id)
	check(tank.orders[0].has("slot") and sim.ordered_target(tank)==original.id and tank.assignment==accepted,"provisional replacement preserves the previous accepted explicit target")
	check(sim.select_combat_target(tank).get("id",-1)==original.id and not sim.engagement_allowed(tank,replacement.id),"retained explicit permission cannot leak to the unresolved replacement")
	replacement.hp=0.0
	sim.terrain.planning.end_tick()
	sim.resolve_slots()
	check(sim.ordered_target(tank)==original.id and tank.assignment==accepted,"rejected attack replacement keeps the original scoped fire permission")

func maneuver_assignment()->void:
	var sim=field()
	var tank:Dictionary=sim.spawn("tank",0,Vector2(20,62))
	check(sim.issue([tank.id],Vector2(38,62),"attack_move")==1,"parent attack-move is accepted")
	var assignment:Dictionary=tank.assignment.duplicate(true)
	check(Director.plan(sim,tank,Vector2(20,56),"FLANK","Local firing position",1.0),"director can plan an internal reposition")
	check(tank.assignment==assignment and tank.order_version==assignment.version,"internal maneuver preserves parent assignment and permission scope")
	var old_action:Dictionary=sim.actions.active(tank,"movement")
	Director.resume(sim,tank)
	check(old_action.phase=="completed" and tank.assignment==assignment and tank.orders[0].mode=="attack_move","completed maneuver resumes the same objective")
	check(Director.plan(sim,tank,Vector2(25,57),"FLANK","Second local firing position",1.0),"a second internal reposition can use the same objective")
	var second:Dictionary=sim.actions.active(tank,"movement")
	check(sim.stop([tank.id])==1,"hard Hold replaces local maneuver")
	check(tank.hold_command and tank.maneuver.is_empty() and tank.orders.is_empty() and second.phase=="cancelled","Hold cancels old maneuver immediately")
	check(tank.order_version==int(assignment.version)+1 and sim.actions.claims.is_empty(),"Hold changes ownership and releases the maneuver claim")
	# Pulling over for a friendly hull is another child move, not a received order.
	sim.issue([tank.id],Vector2(38,62),"attack_move")
	assignment=tank.assignment.duplicate(true)
	var pull_over:=Vector2(20,56)
	var pull_route:Array=sim.terrain.path(tank.pos,pull_over,"land",float(sim.definitions.tank.radius),[],sim.terrain.mobility_profile(tank.kind))
	check(not pull_route.is_empty(),"give-way fixture has a physical route")
	sim.give_way(tank,[pull_over,pull_route])
	sim.finish_order(tank)
	check(tank.assignment==assignment and tank.orders[0].mode=="attack_move","finishing a give-way child preserves the accepted parent assignment")

func scoped_fire()->void:
	var sim=field()
	var tank:Dictionary=sim.spawn("tank",0,Vector2(20,62))
	var first:Dictionary=sim.spawn("tank",1,Vector2(32,62))
	var second:Dictionary=sim.spawn("tank",1,Vector2(34,56))
	sim.update_visibility()
	check(sim.set_fire_policy([tank.id],"hold")==1,"Hold fire is accepted")
	check(sim.issue([tank.id],first.pos,"attack",false,first.id)==1,"explicit target can be ordered under Hold fire")
	check(sim.engagement_allowed(tank,first.id) and not sim.engagement_allowed(tank,second.id),"only the designated target receives firing permission")
	check(sim.issue([tank.id],second.pos,"attack",true,second.id)==1,"second explicit target can be queued")
	check(not sim.engagement_allowed(tank,second.id),"queued attack does not grant early permission")
	sim.set_fire_policy([tank.id],"hold")
	sim.finish_order(tank)
	check(tank.orders[0].target==second.id and not sim.engagement_allowed(tank,second.id),"renewed Hold fire revokes already queued attack permission")
	check(sim.issue([tank.id],second.pos,"attack",false,second.id)==1 and sim.engagement_allowed(tank,second.id),"fresh explicit target has a fresh scoped grant")
	sim.finish_order(tank)
	check(tank.orders.is_empty() and not sim.engagement_allowed(tank,second.id),"completed explicit attack returns to standing Hold fire")
	sim.issue([tank.id],first.pos,"attack",false,first.id)
	var before:Dictionary=tank.assignment.duplicate(true)
	check(sim.issue([tank.id],Vector2(50,62),"attack",false,9999)==0 and tank.assignment==before,"invalid target cannot replace or broaden a valid attack grant")
	sim.stop([tank.id])
	check(not sim.engagement_allowed(tank,first.id) and tank.fire_policy=="hold","Hold position replaces attack permission while preserving Hold fire")

func garrison_override()->void:
	for replacement in ["move","hold"]:
		var sim=field()
		var bounds:=Rect2(30,43,8,6)
		sim.terrain.dynamic_blocks.append(bounds)
		sim.terrain.navigation.clear()
		sim.set_meta("garrison_index",{"buildings":[{"id":0,"bounds":bounds,"rects":[bounds],"capacity":2,"state":0}],"owner":{}})
		var squad:Dictionary=sim.spawn("rifle",0,Vector2(34,60))
		check(GarrisonSystem.order(sim,[squad.id],0)==1,"garrison approach accepted before "+replacement)
		var door:Vector2=squad.garrison_door
		move_section(squad,door)
		if replacement=="move":check(sim.issue([squad.id],door+Vector2(0,10))==1,"replacement move from doorway is accepted")
		else:check(sim.stop([squad.id])==1,"replacement Hold at doorway is accepted")
		var accepted:Dictionary=squad.assignment.duplicate(true)
		GarrisonSystem.tick(sim,DT)
		check(GarrisonSystem.transit(squad)=="" and not squad.has("garrison_target") and squad.assignment==accepted,"old doorway approach cannot overwrite accepted "+replacement)
		check(squad.hold_command==(replacement=="hold"),"doorway interruption preserves the replacement position policy")

func queued_work_hold()->void:
	var sim=Sim.new(false,5)
	sim.terrain.blocks.clear();sim.terrain.roadside_blocks.clear();sim.terrain.trees.clear();sim.terrain.poles.clear();sim.terrain.navigation.clear()
	var engineer:Dictionary=sim.spawn("engineer",0,Vector2(14,97))
	sim.update_visibility()
	engineer.members[0].rounds=0
	sim.Infantry.update_readiness(engineer,engineer.members[0],sim.time,"rifle")
	check(engineer.members[0].reload_until>0.0,"builder fixture starts a real empty-weapon reload")
	var plan:Array=[{"pos":Vector2(24,97),"rotated":false},{"pos":Vector2(31,97),"rotated":false}]
	check(Ops.build_many(sim,"concertina_wire",plan,engineer.id)==2,"paid two-segment work queue is created")
	check(engineer.members[0].reload_until==0.0 and engineer.members[0].rounds==0,"accepted build movement cancels preparation without inventing rounds")
	sim.stop([engineer.id])
	var version:int=engineer.order_version
	var assignment:Dictionary=engineer.assignment.duplicate(true)
	Ops.idle_engineers_continue(sim)
	check(engineer.hold_command and not engineer.has("building_id") and engineer.orders.is_empty(),"hard Hold prevents queued field work from restarting")
	check(engineer.order_version==version and engineer.assignment==assignment,"queued work cannot replace a hard-Hold assignment")
	var queued:Array=sim.units.filter(func(u):return u.get("queued_for",-1)==engineer.id)
	check(not queued.is_empty() and Ops.resume(sim,queued[0].id,engineer.id),"manual Resume can explicitly restore the paid work")
	check(engineer.has("building_id") and not engineer.hold_command and engineer.order_version==version+1,"manual work resume replaces Hold through a new explicit order")

func interrupted_entry_hold(late_hold:bool=false)->void:
	var sim=field()
	var bounds:=Rect2(30,43,8,6)
	sim.terrain.dynamic_blocks.append(bounds)
	sim.terrain.navigation.clear()
	sim.set_meta("garrison_index",{"buildings":[{"id":0,"bounds":bounds,"rects":[bounds],"capacity":2,"state":0}],"owner":{}})
	var squad:Dictionary=sim.spawn("rifle",0,Vector2(34,60))
	GarrisonSystem.order(sim,[squad.id],0)
	move_section(squad,squad.garrison_door)
	GarrisonSystem.tick(sim,DT)
	for i in 100:
		GarrisonSystem.tick(sim,DT)
		if squad.members.any(func(m):return m.get("indoors",false)):break
	check(GarrisonSystem.transit(squad)=="IN" and squad.members.any(func(m):return m.get("indoors",false)),"entry fixture reaches a real mixed inside/outside transition")
	if late_hold:
		check(sim.issue([squad.id],squad.garrison_door+Vector2(0,10))==1,"replacement move starts an exit before a later Stop")
		GarrisonSystem.tick(sim,DT)
		check(GarrisonSystem.transit(squad)=="OUT","soldiers are still physically exiting when Stop arrives")
	sim.stop([squad.id])
	var version:int=squad.order_version
	for i in 180:
		GarrisonSystem.tick(sim,DT)
		if GarrisonSystem.transit(squad)=="":break
	check(GarrisonSystem.transit(squad)=="" and not GarrisonSystem.inside(squad) and squad.members.all(func(m):return not m.get("indoors",false)),"Stop during entry walks already-entered members back out")
	check(squad.hold_command and squad.order_version==version and squad.assignment.mode=="hold","completed exit preserves the replacement hard Hold")

func released_effects()->void:
	var sim=field()
	var gunner:Dictionary=sim.spawn("atgm",0,Vector2(30,62))
	var target:Dictionary=sim.spawn("tank",1,Vector2(46,62))
	sim.set_fire_policy([target.id],"hold")
	sim.update_visibility()
	for i in 180:
		sim.tick(DT)
		if not sim.missiles.is_empty():break
	check(not sim.missiles.is_empty(),"existing infantry executor releases a missile before cancellation")
	if not sim.missiles.is_empty():
		var missile:Dictionary=sim.missiles[0]
		var left:int=sim.missiles_left(gunner)
		sim.stop([gunner.id]);sim.set_fire_policy([gunner.id],"hold")
		for member in gunner.members:member.hp=0.0;member.wound=sim.Infantry.KIA
		sim.Infantry.publish(gunner);sim.sync_action_state(gunner)
		check(sim.actions.owners.get(gunner.id,{}).is_empty() and sim.missiles.size()==1,"lost actor releases actions without erasing its airborne missile")
		sim.events.clear()
		sim.time=float(missile.impact_at)+DT
		sim.tick_missiles()
		check(missile.done and sim.events.any(func(e):return e.type=="missile_impact"),"released missile resolves after Stop, Hold fire and gunner loss")
		check(sim.missiles_left(gunner)==left,"cancellation never refunds the released missile")
	var strike=Sim.new(false,5)
	var victim:Dictionary=strike.spawn("tank",1,Vector2(40,90))
	strike.spawn("drone",0,Vector2(40,86))
	strike.update_visibility()
	strike.credits=400.0
	var ids:Array=Ops.player_strike(strike,victim.pos,victim.id)
	check(ids.size()==Ops.PLAYER_STRIKE_COUNT,"paid strike creates the released FPV group")
	var paid:float=strike.credits
	strike.stop(ids);strike.set_fire_policy(ids,"hold")
	var hp:float=victim.hp
	for i in 600:
		strike.time+=DT
		for id in ids:
			var drone:Dictionary=strike.get_unit(id)
			if strike.alive(drone):strike.fpv_strike(drone,strike.definitions.fpv_drone,DT)
		if ids.all(func(id):return not strike.alive(strike.get_unit(id))):break
	check(not ids.is_empty() and ids.all(func(id):return not strike.alive(strike.get_unit(id))) and victim.hp<hp,"released FPVs finish their existing flight after later unit commands")
	check(strike.credits==paid and paid==400.0-Ops.PLAYER_STRIKE_COST,"later cancellation does not refund a committed strike")

func save_path(label:String)->String:
	var path:="/tmp/for-every-dawn-action-%s-%s.json"%[OS.get_process_id(),label]
	paths.append(path)
	return path

func restored_team(campaign,record:Dictionary)->Dictionary:
	var sim=field()
	var team:Dictionary=sim.spawn("atgm",0,Vector2(30,62))
	campaign.restore_unit(sim,team,record)
	return {"sim":sim,"team":team}

func readiness_campaign_roundtrip()->void:
	var sim=field()
	var team:Dictionary=sim.spawn("atgm",0,Vector2(30,62))
	team.missiles=2
	team.members[0].rounds=0
	team.members[1].rounds=2
	sim.Infantry.update_readiness(team,team.members[0],sim.time,"atgm")
	sim.sync_action_state(team)
	var campaign=Campaign.new()
	campaign.data.started=true
	campaign.data.supply=217.25
	campaign.data.roster=campaign.snapshot(sim)
	var path:=save_path("partial-magazines")
	check(campaign.save_state(path)==OK,"partial magazines save through the real campaign writer")
	var loaded=Campaign.new()
	check(loaded.load_state(path)==OK and loaded.data.version==2,"campaign reload accepts the inventory-aware schema")
	var record:Dictionary=loaded.data.roster[0]
	check(record.members[0].magazines.atgm==0 and record.members[1].magazines.rifle==2 and record.damage.missiles==2,"save retains empty launcher, partial rifle and remaining missile supply")
	check(not record.has("assignment") and not record.members[0].has("reload_until"),"operational persistence does not serialize transient actions")
	for pass_index in 2:
		var world:=restored_team(loaded,record)
		var veteran:Dictionary=world.team
		check(veteran.members[0].rounds==0 and veteran.members[1].rounds==2 and veteran.missiles==2,"transfer %d does not refill or duplicate weapons"%pass_index)
		check(veteran.members[0].reload_until==0.0 and veteran.assignment.is_empty(),"transfer %d resets only temporary work"%pass_index)
		check(veteran.assigned_hp==team.assigned_hp and veteran.assigned_members==team.assigned_members,"transfer %d retains original-strength accounting"%pass_index)
		record=loaded.snapshot(world.sim)[0]
	# A missing specialist remains a loss after save, restore and another save.
	team.members[0].hp=0.0;team.members[0].wound=sim.Infantry.KIA
	sim.Infantry.publish(team)
	loaded.data.roster=loaded.snapshot(sim)
	check(loaded.data.roster[0].equipment.is_empty() and loaded.save_state(path)==OK,"lost launcher is recorded as an authoritative empty inventory")
	var reloaded=Campaign.new()
	check(reloaded.load_state(path)==OK,"lost-equipment save reloads")
	var after:=restored_team(reloaded,reloaded.data.roster[0])
	check(after.team.members[0].wound=="KIA" and not after.sim.Infantry.strength(after.team,after.sim.time).launcher_available,"restoring does not replace the fallen launcher holder")
	check(after.team.members[1].rounds==2 and after.sim.section_weapon(after.team,after.team.members[1])=="rifle","survivor retains partial ammunition without inheriting a free launcher")
	var stable:Array=reloaded.snapshot(after.sim)
	check(stable[0].equipment.is_empty() and stable[0].members[0].magazines.atgm==0,"another snapshot cannot recreate lost equipment or loaded ammunition")
	var invalid:Dictionary=reloaded.data.duplicate(true)
	invalid.roster[0].members[1].member_id=invalid.roster[0].members[0].member_id
	check(not Campaign.valid(invalid),"duplicate persisted soldier identities are rejected")
	invalid=reloaded.data.duplicate(true)
	invalid.roster[0].equipment={"launcher":{"id":"launcher","holder":invalid.roster[0].members[0].member_id}}
	check(not Campaign.valid(invalid),"save validation refuses equipment assigned to a lost soldier")
	invalid=reloaded.data.duplicate(true)
	invalid.roster[0].erase("equipment")
	check(not Campaign.valid(invalid),"new-format missing inventory cannot silently receive default equipment")

func legacy_campaign_migration()->void:
	var sim=field()
	var team:Dictionary=sim.spawn("atgm",0,Vector2(30,62))
	team.members[0].hp=0.0;team.members[0].wound=sim.Infantry.KIA
	sim.Infantry.publish(team)
	var campaign=Campaign.new()
	var legacy:Dictionary=Campaign.fresh()
	legacy.version=1;legacy.started=true;legacy.supply=93.0
	legacy.roster=campaign.snapshot(sim)
	for record in legacy.roster:
		for key in ["assigned_hp","assigned_members","equipment"]:record.erase(key)
		for member in record.members:
			for key in ["member_id","magazines","readiness_weapon"]:member.erase(key)
	var retry:Dictionary=legacy.duplicate(true)
	retry.erase("retry")
	legacy.retry=retry
	check(Campaign.valid(legacy),"historical version-1 casualty records remain valid input")
	var path:=save_path("migration")
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy));file.close()
	check(campaign.load_state(path)==OK,"version-1 save loads through the real migration path")
	check(campaign.data.version==2 and campaign.data.retry.version==2 and Campaign.valid(campaign.data),"both current state and retry checkpoint migrate to valid version 2")
	check(campaign.data.roster[0].equipment.is_empty() and campaign.data.retry.roster[0].equipment.is_empty(),"migration does not replace a launcher lost before inventories were recorded")
	check(campaign.data.roster[0].assigned_members==2 and campaign.data.roster[0].assigned_hp==float(sim.definitions.atgm.hp),"legacy migration reconstructs assigned strength independently of survivors")
	check(Campaign.upgrade_state(campaign.data)==campaign.data,"repeated migration cannot restock an already migrated inventory")
	check(campaign.save_state(path)==OK,"migrated state can be written as version 2")
	var loaded=Campaign.new()
	var read_ok:bool=loaded.load_state(path)==OK
	check(read_ok and loaded.data.roster.size()==1 and loaded.data.roster[0].equipment.is_empty() and loaded.data.roster[0].members[0].wound=="KIA" and int(loaded.data.roster[0].members[1].magazines.rifle)==6 and int(loaded.data.roster[0].members[0].magazines.atgm)==0,"migrated casualties and inventory survive another disk round trip")
	check(loaded.retry(path)==OK and loaded.data.version==2 and loaded.data.roster[0].equipment.is_empty(),"explicit retry uses the migrated checkpoint without inventing equipment")

func field_work_admission()->void:
	var sim=Sim.new(false,5)
	sim.terrain.blocks.clear();sim.terrain.roadside_blocks.clear();sim.terrain.trees.clear();sim.terrain.poles.clear();sim.terrain.navigation.clear()
	Ops.spawn_prepared_works(sim,[{"kind":"forward_supply_point","position":Vector2(30,85)}],0)
	sim.update_visibility()
	var before:int=sim.units.size()
	sim.credits=500.0
	sim.terrain.planning.begin_tick(1,{"routes":0})
	check(Ops.purchase(sim,"rifle"),"forward reinforcement purchase accepts payment while planning is busy")
	var paid:float=sim.credits
	check(Ops.queue(sim)==["rifle"] and sim.units.size()==before and sim.field_ops.last_purchase_error=="","denied connectivity check keeps purchase queued without a false placement failure")
	sim.terrain.planning.begin_tick(2,{"routes":1})
	Ops.process_queue(sim)
	check(Ops.queue(sim).is_empty() and sim.units.size()==before+1 and sim.field_ops.last_entry_forward,"admitted connectivity check deploys at the forward site")
	check(sim.credits==paid,"deferred deployment charges the purchase only once")
	sim.terrain.planning.end_tick()
	var breach=Sim.new(false,5)
	breach.terrain.blocks.clear();breach.terrain.roadside_blocks.clear();breach.terrain.trees.clear();breach.terrain.poles.clear();breach.terrain.navigation.clear()
	var attacker:Dictionary=breach.spawn("tank",1,Vector2(14,97))
	Ops.spawn_prepared_works(breach,[{"kind":"tactical_cover","position":Vector2(21,97)}],0)
	breach.update_visibility()
	breach.issue([attacker.id],Vector2(35,97),"attack_move")
	attacker.blocked_time=3.0
	var parent:Dictionary=attacker.assignment.duplicate(true)
	var orders:Array=attacker.orders.duplicate(true)
	var route:Array=attacker.path.duplicate(true)
	breach.terrain.planning.begin_tick(1,{"routes":0})
	Ops.enemy_breach(breach)
	check(attacker.orders==orders and attacker.path==route and attacker.blocked_time==3.0,"denied breach planning preserves current orders, route and retry state")
	breach.terrain.planning.begin_tick(2,{"routes":1})
	Ops.enemy_breach(breach)
	check(attacker.orders.size()==orders.size()+1 and attacker.orders[0].mode=="attack","admitted breach adds one temporary combat order")
	check(attacker.assignment==parent,"breach preserves the wave's persistent assignment")
	breach.terrain.planning.end_tick()
	breach.finish_order(attacker)
	check(attacker.assignment==parent and attacker.orders==orders,"completed breach returns to the original wave without a replacement assignment")

func hard_hold_under_pressure()->void:
	var sim=field()
	sim.scenario=sim.scenario.duplicate(true);sim.scenario.autonomy=true
	var squad:Dictionary=sim.spawn("rifle",0,Vector2(20,62))
	var threat:Dictionary=sim.spawn("tank",1,Vector2(34,62))
	for index in [0,1]:squad.members[index].hp=0.0;squad.members[index].wound=sim.Infantry.KIA
	sim.Infantry.publish(squad)
	squad.suppression=0.95
	sim.stop([squad.id]);sim.set_fire_policy([squad.id],"hold")
	sim.update_visibility()
	check(sim.contact_known(squad,threat),"hard-Hold fixture receives a real known threat")
	var assignment:Dictionary=squad.assignment.duplicate(true)
	Director.update(sim)
	check(squad.hold_command and squad.maneuver.is_empty() and squad.path.is_empty() and squad.assignment==assignment,"severe suppression and depletion cannot turn hard Hold into a retreat")
	check(squad.reason=="Hold position · under pressure" and not sim.engagement_allowed(squad,threat.id),"hard Hold reports pressure while standing Hold fire remains authoritative")

func bombard_permission()->void:
	for cancellation in ["hold_fire","stop","replacement","queued"]:
		var sim=field()
		var bounds:=Rect2(48,53,6,8)
		var building:={"id":0,"design":"stone_house","bounds":bounds,"rects":[bounds],"capacity":2,"state":0,"damage":0.0,"area":48.0,"floors":2,"height":8.0,"blocks":[]}
		sim.set_meta("garrison_index",{"buildings":[building],"owner":{}})
		var tank:Dictionary=sim.spawn("tank",0,Vector2(20,62))
		sim.set_fire_policy([tank.id],"hold")
		check(Structure.bombard(sim,[tank.id],0)==1 and not tank.orders.is_empty(),"explicit building attack owns a real firing-position approach under Hold fire")
		var assignment:Dictionary=tank.assignment.duplicate(true)
		check(assignment.mode=="bombard" and not sim.engagement_allowed(tank,0),"building permission cannot authorize an unrelated unit with the same numeric ID")
		if cancellation=="queued":sim.issue([tank.id],Vector2(26,62),"move",true)
		var destination:Vector2=tank.orders[0].pos
		sim.rebuild_spatial()
		for step in 600:
			if tank.orders.is_empty() or tank.orders[0].get("bombard_approach",-1)!=0:break
			sim.move_unit(tank,DT)
		check(tank.pos.distance_to(destination)<1.0,"bombard approach reaches its real firing position")
		if cancellation=="queued":
			check(tank.assignment.id!=assignment.id and tank.assignment.mode=="move","player-queued movement takes ownership after the bombard approach")
		else:
			check(tank.assignment==assignment and not tank.assignment.permission_revoked,"finished internal approach retains the scoped building assignment")
			Structure._bombard_tick(sim,Structure._state(sim).bombard)
			check(float(building.damage)>0.0,"accepted building attack releases a round under its scoped Hold-fire permission")
		var damage:float=building.damage
		if cancellation=="hold_fire":sim.set_fire_policy([tank.id],"hold")
		elif cancellation=="stop":sim.stop([tank.id])
		elif cancellation=="replacement":sim.issue([tank.id],Vector2(26,62))
		tank.cooldown=0.0;sim.events.clear()
		Structure._bombard_tick(sim,Structure._state(sim).bombard)
		check(float(building.damage)==damage and not tank.has("bombard"),"%s cancels further building releases and removes the old fire mission"%cancellation)

func field_continuation_admission()->void:
	var sim=Sim.new(false,5)
	sim.terrain.blocks.clear();sim.terrain.roadside_blocks.clear();sim.terrain.trees.clear();sim.terrain.poles.clear();sim.terrain.navigation.clear()
	var engineer:Dictionary=sim.spawn("engineer",0,Vector2(14,97))
	sim.update_visibility()
	var segments:Array=[{"pos":Vector2(24,97),"rotated":false},{"pos":Vector2(31,97),"rotated":false}]
	check(Ops.build_many(sim,"concertina_wire",segments,engineer.id)==2,"continuation fixture pays for both line segments")
	var first:Dictionary=sim.get_unit(engineer.building_id)
	first.build_left=0.0
	engineer.erase("building_id");engineer.orders=[];engineer.path=[]
	var queued:Dictionary=sim.units.filter(func(u):return u.get("queued_for",-1)==engineer.id)[0]
	var assignment:Dictionary=engineer.assignment.duplicate(true)
	var paid:float=sim.credits
	sim.terrain.planning.begin_tick(1,{"routes":0})
	Ops.idle_engineers_continue(sim)
	check(queued.get("queued_for",-1)==engineer.id and not engineer.has("building_id") and engineer.assignment==assignment,"denied continuation preserves the paid queue and current assignment")
	check(sim.credits==paid and sim.field_ops.last_build_error=="","denied work-point planning neither charges again nor reports a route failure")
	sim.terrain.planning.begin_tick(2,{"routes":1})
	Ops.idle_engineers_continue(sim)
	check(engineer.get("building_id",-1)==queued.id and not queued.has("queued_for") and sim.credits==paid,"admitted continuation starts the same paid segment exactly once")

func deferred_bombard_replan()->void:
	var sim=field()
	var bounds:=Rect2(48,53,6,8)
	var building:={"id":0,"design":"stone_house","bounds":bounds,"rects":[bounds],"capacity":2,"state":0,"damage":0.0,"area":48.0,"floors":2,"height":8.0,"blocks":[]}
	sim.set_meta("garrison_index",{"buildings":[building],"owner":{}})
	var tank:Dictionary=sim.spawn("tank",0,Vector2(36,62))
	check(Structure.bombard(sim,[tank.id],0)==1 and tank.orders.is_empty(),"replan fixture begins at a legitimate firing position")
	var assignment:Dictionary=tank.assignment.duplicate(true)
	tank.pos=Vector2(20,62)
	sim.terrain.planning.begin_tick(1,{"formation":0})
	Structure._bombard_tick(sim,Structure._state(sim).bombard)
	check(tank.has("bombard") and tank.bombard_replans==0 and tank.assignment==assignment and tank.orders.is_empty(),"denied firing-position replan preserves its task, attempt count and permission")
	check(float(building.damage)==0.0 and not sim.events.any(func(e):return e.type=="warning" and e.get("text","")==Structure.NO_POSITION),"budget denial neither releases a shot nor claims the firing position is impossible")
	sim.terrain.planning.begin_tick(2,{"formation":1})
	Structure._bombard_tick(sim,Structure._state(sim).bombard)
	check(tank.has("bombard") and tank.bombard_replans==1 and not tank.orders.is_empty() and tank.assignment==assignment,"admitted replan adds an internal approach while retaining the building scope")

func spawn_batch_admission()->void:
	var wave=Sim.new(false,6)
	Ops.spawn_prepared_works(wave,[{"kind":"command_post","position":wave.field_ops.enemy_insertion+Vector2(30,30)}],1)
	wave.spawn("rifle",0,wave.field_ops.insertion)
	wave.field_ops.started=true
	wave.time=float(wave.scenario.enemy_waves.first)+0.1
	var before:int=wave.units.size()
	wave.terrain.planning.begin_tick(1,{"formation":0})
	Ops.enemy_offensive(wave)
	check(wave.field_ops.waves.index==0 and wave.units.size()==before and wave.field_ops.waves.next==float(wave.scenario.enemy_waves.first),"denied wave admission retains its due schedule and full composition")
	wave.terrain.planning.begin_tick(2,{"formation":1})
	Ops.enemy_offensive(wave)
	check(wave.field_ops.waves.index==1 and wave.field_ops.waves.active.size()==Ops.wave_composition(0).size(),"admitted wave spawns its complete authored batch once")
	var reserve=Sim.new(false,5)
	reserve.spawn("rifle",0,reserve.field_ops.insertion)
	reserve.field_ops.started=true
	reserve.counterattack_at=0.0;reserve.time=1.0
	before=reserve.units.size()
	reserve.terrain.planning.begin_tick(1,{"formation":0})
	Ops.tick(reserve,0.0)
	check(not reserve.counterattack_sent and reserve.counterattack_ids.is_empty() and reserve.units.size()==before,"denied reserve admission leaves promised unit records unconsumed")
	reserve.terrain.planning.begin_tick(2,{"formation":1})
	Ops.tick(reserve,0.0)
	check(reserve.counterattack_sent and reserve.counterattack_ids.size()==Ops.reserve_records(reserve).size(),"admitted reserve spawns its complete promised batch once")

func run()->void:
	orders_and_old_results()
	provisional_orders()
	provisional_attack_execution()
	queued_after_rejected_replacement()
	provisional_attack_permission()
	maneuver_assignment()
	scoped_fire()
	garrison_override()
	queued_work_hold()
	interrupted_entry_hold()
	interrupted_entry_hold(true)
	released_effects()
	readiness_campaign_roundtrip()
	legacy_campaign_migration()
	field_work_admission()
	hard_hold_under_pressure()
	bombard_permission()
	field_continuation_admission()
	deferred_bombard_replan()
	spawn_batch_admission()
	for path in paths:
		for suffix in ["",".bak",".tmp"]:
			if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("ACTION INTEGRATION: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
