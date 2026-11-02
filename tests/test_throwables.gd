extends SceneTree

const Sim=preload("res://scripts/simulation.gd")
const Throws=preload("res://scripts/throwables.gd")
const GarrisonSystem=preload("res://scripts/garrison.gd")
const Elevation=preload("res://scripts/elevation.gd")
const DT:=1.0/30.0
const SOURCE:=Vector2(18,62)
const TARGET:=Vector2(30,62)
var checks:=0
var failures:=0

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func _init()->void:call_deferred("run")

func run()->void:
	inventory()
	preparation_and_orders()
	mixed_selection()
	capability_interruptions()
	friendly_crossing()
	released_ownership()
	fire_permission()
	walls_and_collision()
	alternate_thrower()
	exposure()
	smoke_lifetime()
	visibility_and_memory()
	seeker_semantics()
	capacity_and_bad_input()
	defensive_policy()
	stale_automatic_cleanup()
	deterministic_replay()
	print("THROWABLES: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)

func field():
	var sim=Sim.new(false,0)
	sim.tactical_clock=10000.0;sim.enemy_clock=10000.0
	sim.scenario.autonomy=false
	sim.combat_rng.seed=31
	return sim

func step(sim,seconds:float)->void:
	for tick in ceili(seconds/DT):
		sim.time+=DT
		Throws.tick(sim,DT)

func move_section(u:Dictionary,to:Vector2)->void:
	var delta:Vector2=to-u.pos
	u.pos=to
	for member in u.members:member.pos+=delta

func count_events(sim,type:String)->int:
	return sim.events.filter(func(e):return e.type==type).size()

func mixed_selection()->void:
	for payload in ["frag","smoke"]:
		var sim=field()
		var first:Dictionary=sim.spawn("rifle",0,SOURCE)
		var second:Dictionary=sim.spawn("rifle",0,SOURCE+Vector2(0,-7))
		var tank:Dictionary=sim.spawn("tank",0,Vector2(10,45))
		sim.stop([first.id,second.id,tank.id])
		var ids:Array=[tank.id,first.id,second.id,first.id]
		var assignments:Dictionary={}
		for unit in [first,second,tank]:assignments[unit.id]=unit.assignment.duplicate(true)
		check(Throws.preview(sim,first,payload,TARGET).ok and Throws.preview(sim,second,payload,TARGET).ok,"both selected infantry sections have a valid %s throw"%payload)
		var plan:Dictionary=Throws.preview_selection(sim,ids,payload,TARGET)
		check(plan.ok and plan.unit==first.id,"mixed preview skips the incapable vehicle and chooses the first eligible section")
		check(sim.issue_throw(ids,payload,TARGET)==1 and sim.throwables.preparations.size()==1,"one mixed-selection command reserves one %s payload, not a volley"%payload)
		check(sim.throwables.preparations[0].unit==plan.unit and sim.throwables.preparations[0].member==plan.member.member_id,"committed section and actor agree with the displayed preview")
		check(first.assignment!=assignments[first.id] and second.assignment==assignments[second.id] and tank.assignment==assignments[tank.id],"only the throwing section replaces its assignment")
		step(sim,1.2)
		check(count_events(sim,"throw_release")==1 and Throws.total(first,payload)==2 and Throws.total(second,payload)==3,"one mixed-selection release consumes exactly one item across the selection")
		check(second.assignment==assignments[second.id] and tank.assignment==assignments[tank.id],"unselected throwers retain their assignments through release")
		for member in first.members:member.throwables[payload]=0
		var fallback:Dictionary=Throws.preview_selection(sim,ids,payload,TARGET)
		check(fallback.ok and fallback.unit==second.id,"an exhausted first section falls through to the next eligible section")
		check(sim.issue_throw(ids,payload,TARGET)==1 and sim.throwables.preparations.size()==1 and sim.throwables.preparations[0].unit==second.id,"fallback commitment still creates only one preparation")
		sim.stop([second.id]);step(sim,0.1)
		for member in second.members:member.throwables[payload]=0
		var first_order:Dictionary=first.assignment.duplicate(true)
		var second_order:Dictionary=second.assignment.duplicate(true)
		check(sim.issue_throw(ids,payload,TARGET)==0 and sim.throwables.preparations.is_empty(),"a wholly incapable mixed selection creates no preparation")
		check(first.assignment==first_order and second.assignment==second_order,"rejected mixed selection preserves every accepted assignment")

func inventory()->void:
	var sim=field()
	var u:Dictionary=sim.spawn("rifle",0,SOURCE)
	check(Throws.total(u,"frag")==3 and Throws.total(u,"smoke")==3,"new rifle section has one frag and smoke per member")
	u.members[0].throwables={}
	u.members[1].throwables.frag=0
	u.members[2].hp=0.0;u.members[2].wound="KIA"
	Throws.ensure_unit(u)
	check(u.members[0].throwables.is_empty() and u.members[1].throwables.frag==0,"explicit empty and spent inventory survive ensure")
	check(Throws.total(u,"frag")==0,"fallen member's remaining equipment is not available")
	u.members[2].erase("throwables")
	Throws.ensure_unit(u)
	check(u.members[2].throwables.frag==0 and u.members[2].throwables.smoke==0,"legacy dead member does not acquire equipment")
	check(Throws.total(sim.spawn("tank",0,Vector2(12,52)),"frag")==0,"vehicles have no invented throwing inventory")

func preparation_and_orders()->void:
	var sim=field()
	var u:Dictionary=sim.spawn("rifle",0,SOURCE)
	var plan:Dictionary=Throws.preview(sim,u,"frag",TARGET)
	check(plan.ok and plan.arc.size()>5 and plan.radius==4.0,"valid throw offers an authoritative arc and blast preview")
	check(sim.issue_throw([u.id,u.id],"frag",TARGET)==1,"duplicate section IDs reserve only one throw")
	check(Throws.total(u,"frag")==3 and sim.throwables.preparations.size()==1,"preparation reserves the item without consuming it")
	var member:Dictionary=plan.member
	check(Throws.busy(sim,u,member) and member.task_kind=="throw","chosen member owns a task action during preparation")
	check(sim.actions.claims.has("actor:%d:%s"%[u.id,member.member_id]),"throw reserves the same actor claim as field work")
	step(sim,0.5)
	check(sim.throwables.projectiles.is_empty() and Throws.total(u,"frag")==3,"time must pass before a grenade leaves the hand")
	check(sim.stop([u.id])==1,"new hold command is accepted during preparation")
	step(sim,0.1)
	check(sim.throwables.preparations.is_empty() and sim.throwables.projectiles.is_empty(),"replacement command cancels unreleased work")
	check(Throws.total(u,"frag")==3 and sim.actions.claims.is_empty(),"cancellation releases claims without spending or refunding an item")
	check(not member.has("task_action"),"cancelled member returns to ordinary roles")

func capability_interruptions()->void:
	for failure in ["death","suppression","movement"]:
		var sim=field()
		var u:Dictionary=sim.spawn("rifle",0,SOURCE)
		var member:Dictionary=Throws.preview(sim,u,"frag",TARGET).member
		check(sim.issue_throw([u.id],"frag",TARGET)==1,"prepare before %s"%failure)
		if failure=="death":member.hp=0.0;member.wound="KIA";sim.Infantry.publish(u)
		elif failure=="suppression":member.suppression=0.9
		else:member.pos+=Vector2(2,0)
		step(sim,1.5)
		check(sim.throwables.projectiles.is_empty() and sim.throwables.preparations.is_empty(),"%s prevents release"%failure)
		check(member.throwables.frag==1 and sim.actions.claims.is_empty(),"%s clears reservation without consuming equipment"%failure)

func friendly_crossing()->void:
	for team in [0,1]:
		var sim=field()
		var u:Dictionary=sim.spawn("rifle",team,SOURCE)
		var ally:Dictionary=sim.spawn("rifle",team,Vector2(13,54))
		check(sim.issue_throw([u.id],"frag",TARGET)==1,"team %d begins a clear throw"%team)
		step(sim,0.5)
		move_section(ally,TARGET+Vector2(0,2))
		step(sim,0.8)
		check(Throws.total(u,"frag")==3 and sim.throwables.projectiles.is_empty(),"team %d rechecks allies immediately before release"%team)
		check(u.last_action.reason=="friendlies_near_throw","friendly-risk rejection has a concrete reason")
		check(sim.issue_throw([u.id],"frag",TARGET)==0,"current friendly exposure also rejects the initial command")

func released_ownership()->void:
	var sim=field()
	var u:Dictionary=sim.spawn("rifle",0,SOURCE)
	var target:Dictionary=sim.spawn("rifle",1,TARGET)
	sim.update_visibility()
	check(sim.issue_throw([u.id],"frag",TARGET)==1,"throw at a visible opposing section is accepted")
	step(sim,1.15)
	check(sim.throwables.projectiles.size()==1 and Throws.total(u,"frag")==2,"release creates exactly one world object and consumes one item")
	check(sim.actions.claims.is_empty() and sim.throwables.preparations.is_empty(),"release frees the actor and inventory reservations")
	var projectile:Dictionary=sim.throwables.projectiles[0]
	var id:int=projectile.id
	sim.stop([u.id])
	for member in u.members:member.hp=0.0;member.wound="KIA"
	sim.Infantry.publish(u)
	step(sim,2.0)
	check(sim.throwables.projectiles.is_empty() and count_events(sim,"grenade_burst")==1,"thrower's death and new order cannot delete the released object")
	check(target.last_hit>0.0 and target.members.any(func(m):return m.last_hit>0.0),"blast reaches exposed opposing people through the wound/suppression path")
	check(int(sim.throwables.next_id)==id+1,"spent object ID is never reused")
	step(sim,3.0)
	check(count_events(sim,"grenade_burst")==1,"an expired grenade never activates twice")
	# Friendly entry after release is physical friendly fire, not immunity.
	var after=field()
	var shooter:Dictionary=after.spawn("rifle",1,SOURCE)
	var friendly:Dictionary=after.spawn("rifle",1,Vector2(12,52))
	check(after.issue_throw([shooter.id],"frag",TARGET)==1,"second faction can release the same payload")
	step(after,1.15)
	move_section(friendly,TARGET)
	step(after,2.0)
	check(friendly.last_hit>0.0,"friendly troops entering after release receive the same physical blast")

func fire_permission()->void:
	var sim=field()
	var u:Dictionary=sim.spawn("rifle",0,SOURCE)
	sim.set_fire_policy([u.id],"hold")
	check(sim.issue_throw([u.id],"frag",TARGET)==1,"explicit throw grants one scoped release under Hold fire")
	step(sim,1.15)
	check(Throws.total(u,"frag")==2 and u.assignment.permission_used,"successful throw consumes its scoped engagement permission")
	check(not sim.engagement_allowed(u,99),"throw permission grants no rifle attack")
	check(not sim.Actions.engagement_allowed(u,-1,"throw",TARGET),"a consumed explicit throw cannot authorize a second grenade")
	var revoke=field()
	var other:Dictionary=revoke.spawn("rifle",0,SOURCE)
	check(revoke.issue_throw([other.id],"smoke",TARGET)==1,"smoke starts before an explicit Hold fire interruption")
	revoke.set_fire_policy([other.id],"hold")
	step(revoke,1.2)
	check(Throws.total(other,"smoke")==3 and revoke.throwables.projectiles.is_empty(),"new Hold fire cancels an unreleased throw")

func walls_and_collision()->void:
	var sim=field()
	var u:Dictionary=sim.spawn("rifle",0,SOURCE)
	var wall:=Rect2(24.0,57.0,0.07,10.0)
	sim.terrain.blocks.append(wall);sim.terrain.rebuild_static_index()
	var blocked:Dictionary=Throws.preview(sim,u,"frag",TARGET)
	check(not blocked.ok and blocked.collision and blocked.reason=="Throw trajectory blocked","a thin wall blocks the swept preview without tunnelling")
	check(sim.issue_throw([u.id],"frag",TARGET)==0 and u.order_version==0,"impossible trajectory consumes no item and replaces no order")
	var dynamic=field()
	var thrower:Dictionary=dynamic.spawn("rifle",0,SOURCE)
	check(dynamic.issue_throw([thrower.id],"frag",TARGET)==1,"open trajectory accepted before geometry changes")
	step(dynamic,1.15)
	dynamic.terrain.blocks.append(wall);dynamic.terrain.rebuild_static_index()
	step(dynamic,0.5)
	var projectile:Dictionary=dynamic.throwables.projectiles[0] if not dynamic.throwables.projectiles.is_empty() else {}
	check(not projectile.is_empty() and projectile.landed and projectile.pos.x<wall.position.x,"released grenade collides with newly created thin geometry")
	step(dynamic,2.0)
	var burst:Array=dynamic.events.filter(func(e):return e.type=="grenade_burst")
	check(burst.size()==1 and burst[0].pos.x<wall.position.x,"activation occurs on the actual near side of the wall")
	var displayed:Array=dynamic.events.filter(func(e):return e.type=="world_blast" and e.get("kind","")=="grenade")
	check(displayed.size()==1 and float(displayed[0].height)>1.0 and is_equal_approx(float(displayed[0].height),float(burst[0].height)),"wall impact presentation retains the same elevated blast origin as damage")
	# An unseen physical body must not appear in an aiming preview.
	var hidden=field()
	var actor:Dictionary=hidden.spawn("rifle",0,SOURCE)
	var first:Dictionary=Throws.preview(hidden,actor,"smoke",TARGET)
	var obstacle:Dictionary=hidden.spawn("tank",1,TARGET)
	obstacle.seen_by=[false,true]
	var second:Dictionary=Throws.preview(hidden,actor,"smoke",TARGET)
	check(first.arc==second.arc and first.landing==second.landing,"preview cannot leak an unseen unit through predicted collision")

func alternate_thrower()->void:
	var sim=field()
	var u:Dictionary=sim.spawn("rifle",0,SOURCE)
	u.members[0].pos=Vector2(20,62)
	u.members[1].pos=Vector2(18,59)
	u.members[2].pos=Vector2(18,65)
	sim.terrain.blocks.append(Rect2(24,61.3,0.07,1.4));sim.terrain.rebuild_static_index()
	var obstructed:Dictionary=Throws._preview_flight(sim,Throws._origin(sim,u.members[0]),Vector3(TARGET.x,0.09,TARGET.y),2.8,u.id,u.members[0].member_id,u.team)
	check(obstructed.collision and not Throws._useful_landing(obstructed,TARGET,4.0),"closest member's arc is physically blocked by the short wall")
	var plan:Dictionary=Throws.preview(sim,u,"frag",TARGET)
	check(plan.ok and plan.member.index==1 and not plan.collision,"a settled teammate with a clear arc can take the throw around the wall")
	check(sim.issue_throw([u.id],"frag",TARGET)==1,"section throw succeeds through the available member without moving the squad")
	step(sim,1.2)
	check(u.members[0].throwables.frag==1 and u.members[1].throwables.frag==0 and u.members[2].throwables.frag==1,"only the selected alternate thrower's inventory is consumed")
	check(sim.throwables.projectiles.size()==1 and count_events(sim,"throw_release")==1,"alternate selection releases exactly one physical grenade")
	step(sim,2.0)
	var bursts:Array=sim.events.filter(func(e):return e.type=="grenade_burst")
	check(bursts.size()==1 and bursts[0].pos.distance_to(TARGET)<0.15,"the released alternate trajectory reaches the displayed target")

func exposure()->void:
	var sim=field()
	var near:Dictionary=sim.spawn("rifle",1,Vector2(27,62))
	var far:Dictionary=sim.spawn("rifle",1,Vector2(33,62))
	var wall:=Rect2(30,57,0.1,10)
	sim.terrain.blocks.append(wall);sim.terrain.rebuild_static_index()
	Throws._blast(sim,Vector3(29,0.12,62),6.0)
	check(near.members.any(func(m):return m.last_hit>=0.0),"blast affects exposed bodies on its side of the wall")
	check(far.members.all(func(m):return m.last_hit<0.0 and m.suppression==0.0),"solid wall blocks damage and suppression per member")
	var elevated=field()
	var higher:Dictionary=elevated.spawn("rifle",1,TARGET)
	elevated.terrain.elevation=Elevation.new([{"rect":[29.0,58.0,4.0,8.0],"height":8.0,"ramp":4.0}])
	Throws._blast(elevated,Vector3(27,0.12,62),4.0)
	check(higher.members.all(func(m):return m.last_hit<0.0),"blast radius includes vertical separation on raised ground")
	var indoor=field()
	indoor.scenario.blocks=[[30.0,59.0,2.0,6.0]]
	indoor.scenario.architecture=[{"design":"stone_house","collision":[0,1],"floors":1,"source_size":[2.0,6.0]}]
	indoor.terrain.blocks.assign([Rect2(30,59,2,6)])
	indoor.terrain.rebuild_static_index()
	if indoor.has_meta("garrison_index"):indoor.remove_meta("garrison_index")
	var occupants:Dictionary=indoor.spawn("rifle",1,Vector2(27,62))
	occupants.garrison=0
	occupants.members[0].pos=Vector2(29.3,62)
	occupants.members[1].pos=Vector2(32.7,62)
	occupants.members[2].pos=Vector2(32.7,63)
	Throws._blast(indoor,Vector3(27.5,0.12,62),6.0)
	check(occupants.members[0].suppression>0 and occupants.members[0].suppression<0.4,"exposed garrison aperture has reduced blast exposure")
	check(occupants.members[1].suppression==0 and occupants.members[2].suppression==0,"garrison's far-side occupants receive no through-wall suppression")

func smoke_lifetime()->void:
	var sim=field()
	var u:Dictionary=sim.spawn("rifle",0,SOURCE)
	check(sim.issue_throw([u.id],"smoke",TARGET)==1,"smoke is an independent finite payload")
	step(sim,2.5)
	check(Throws.total(u,"smoke")==2 and sim.throwables.smoke.size()==1,"smoke inventory spent once and a world volume activates")
	var cloud:Dictionary=sim.throwables.smoke[0]
	var a:=Vector3(23,1.5,62);var b:=Vector3(37,1.5,62)
	check(Throws.blocks_sight(sim,a,b) and Throws.blocks_sight(sim,b,a),"optical smoke is reciprocal and owner-independent")
	check(not Throws.blocks_sight(sim,a+Vector3.UP*5,b+Vector3.UP*5),"sight above the physical cloud is clear")
	check(not Throws.blocks_sight(sim,a+Vector3(0,0,5),b+Vector3(0,0,5)),"sight outside the cylinder is clear")
	check(Throws.blocks_sight(sim,cloud.pos+Vector3.UP,a),"an observer inside smoke has no clear line through it")
	var revision:int=sim.throwables.revision
	sim.visibility_cache["sentinel"]={}
	sim.time=float(cloud.expires)
	Throws.tick(sim,DT)
	check(sim.throwables.smoke.is_empty() and not Throws.blocks_sight(sim,a,b),"smoke expires in simulation time and clears its occlusion")
	check(sim.throwables.revision==revision+1 and sim.visibility_cache.is_empty() and sim.sensor_clock==0.0,"expiry invalidates optical caches and requests sensing refresh")

func cloud(sim,point:Vector2)->void:
	sim.throwables.smoke.append({"id":99,"pos":Vector3(point.x,sim.terrain.height_at(point),point.y),"radius":4.5,"height":4.0,"born":sim.time,"expires":sim.time+18.0,"team":0})
	Throws._smoke_changed(sim)

func visibility_and_memory()->void:
	var sim=field()
	var a:Dictionary=sim.spawn("rifle",0,SOURCE)
	var b:Dictionary=sim.spawn("rifle",1,TARGET)
	sim.update_visibility()
	check(a.seen_by[1] and b.seen_by[0] and sim.can_fire(a,b),"opposing sections can initially observe and engage")
	var known:Array=sim.context.team_snapshot(0,sim.time)
	cloud(sim,Vector2(24,62))
	sim.update_visibility()
	check(not a.seen_by[1] and not b.seen_by[0],"smoke interrupts current team observation for both factions")
	check(not sim.can_fire(a,b) and not sim.can_fire(b,a),"ordinary optical weapons cannot acquire through the smoke")
	check(sim.context.team_snapshot(0,sim.time)==known,"smoke preserves the actual last observation instead of erasing knowledge")
	move_section(b,TARGET+Vector2(1,0))
	sim.time+=0.4;sim.update_visibility()
	var memory:Array=sim.context.team_snapshot(0,sim.time)
	check(not memory.is_empty() and memory[0].pos==known[0].pos,"unseen movement cannot update remembered contact coordinates")
	check(not sim.visible_cells.has(sim.terrain.cell(TARGET)),"fog visibility uses the same smoke rule as combat")
	sim.time=19.0;Throws.tick(sim,DT);sim.update_visibility()
	check(b.seen_by[0] and a.seen_by[1],"normal observation resumes after smoke dissipates")

func seeker_semantics()->void:
	var sim=field()
	var u:Dictionary=sim.spawn("atgm",0,SOURCE)
	var target:Dictionary=sim.spawn("tank",1,TARGET+Vector2(4,0))
	sim.update_visibility()
	var proxy:Dictionary=u.duplicate()
	proxy.fire_height=1.0
	sim.launch_missile(u,proxy,target,1.0,{})
	check(sim.missiles.size()==1,"missile is launched with an acquired target")
	cloud(sim,Vector2(25,62));sim.update_visibility()
	check(not sim.can_fire(u,target),"new optical lock is blocked by deployed smoke")
	var missile:Dictionary=sim.missiles[0]
	sim.time=float(missile.impact_at)+0.01
	sim.tick_missiles()
	check(missile.done and missile.lost=="","released fire-and-forget missile retains its declared seeker semantics")

func capacity_and_bad_input()->void:
	var sim=field()
	var u:Dictionary=sim.spawn("rifle",0,SOURCE)
	for pair in [["unknown",TARGET],["frag",Vector2.INF],["smoke",Vector2(91,62)],["frag",Vector2(75,62)]]:
		check(sim.issue_throw([u.id],pair[0],pair[1])==0,"invalid payload/range/terrain refuses without starting")
	check(u.order_version==0 and Throws.total(u,"frag")==3 and Throws.total(u,"smoke")==3,"invalid requests preserve orders and all inventory")
	for i in Throws.MAX_SMOKE:cloud(sim,Vector2(24,62))
	check(sim.issue_throw([u.id],"smoke",TARGET)==0,"smoke cap rejects before consuming an item")
	check(sim.throwables.preparations.is_empty(),"capacity rejection leaves no unfinishable action")
	var claimed=field()
	var section:Dictionary=claimed.spawn("rifle",0,SOURCE)
	var other:Dictionary=claimed.spawn("rifle",0,Vector2(12,52))
	claimed.stop([section.id])
	var assignment:Dictionary=section.assignment.duplicate(true)
	for member in section.members:
		claimed.actions.begin(other,"fixture",claimed.time,{"channel":"claim_%s"%member.member_id,"claims":["actor:%d:%s"%[section.id,member.member_id]]})
	check(claimed.issue_throw([section.id],"frag",TARGET)==0 and section.assignment==assignment,"shared actor-claim rejection preserves the accepted order")
	var full=field()
	var occupied:Dictionary=full.spawn("rifle",0,SOURCE)
	full.stop([occupied.id])
	var before:Dictionary=occupied.assignment.duplicate(true)
	for index in full.actions.MAX_ACTIONS:full.actions.actions[index]={}
	check(full.issue_throw([occupied.id],"frag",TARGET)==0 and occupied.assignment==before,"global action-capacity rejection happens before replacing orders")

func automatic_step(sim,seconds:float)->void:
	for index in ceili(seconds/DT):
		sim.action_tick+=1
		sim.actions.begin_tick(sim.action_tick,{"decisions":32,"line_checks":256})
		sim.time+=DT
		sim.update_visibility()
		Throws.tick(sim,DT)

func defensive_policy()->void:
	var sim=field()
	var u:Dictionary=sim.spawn("rifle",0,SOURCE)
	var enemy:Dictionary=sim.spawn("rifle",1,TARGET)
	sim.stop([u.id])
	var assignment:Dictionary=u.assignment.duplicate(true)
	automatic_step(sim,0.7)
	check(sim.throwables.preparations.is_empty() and Throws.total(u,"frag")==3,"default manual policy never throws automatically")
	check(Throws.set_policy(sim,[u.id],"defensive")==1,"defensive grenades require explicit delegation")
	automatic_step(sim,0.7)
	check(sim.throwables.preparations.size()==1,"delegated settled section recognizes a useful observed infantry cluster")
	check(u.assignment==assignment and u.orders.is_empty(),"automatic throw is a child action preserving the defense assignment")
	if not sim.throwables.preparations.is_empty():
		var job:Dictionary=sim.throwables.preparations[0]
		var partner:Dictionary=sim.Infantry.member_by_id(u,job.coverer)
		check(not partner.is_empty() and partner.cover_for==job.member,"automatic throw has a loaded covering partner")
	automatic_step(sim,1.2)
	check(Throws.total(u,"frag")==2 and count_events(sim,"throw_release")==1,"automatic opportunity completes through the normal single-consumption release")
	check(u.assignment==assignment and u.throw_policy=="defensive","successful child throw retains original assignment and policy")
	automatic_step(sim,2.0)
	check(count_events(sim,"throw_release")==1,"minimum release spacing prevents a grenade spam loop")
	for restriction in ["hold_fire","moving","hidden","single_enemy","no_partner"]:
		var denied=field()
		var defender:Dictionary=denied.spawn("rifle",0,SOURCE)
		var target:Dictionary=denied.spawn("rifle",1,TARGET)
		denied.stop([defender.id])
		Throws.set_policy(denied,[defender.id],"defensive")
		if restriction=="hold_fire":denied.set_fire_policy([defender.id],"hold")
		elif restriction=="moving":denied.issue([defender.id],Vector2(18,52),"move")
		elif restriction=="hidden":cloud(denied,Vector2(24,62))
		elif restriction=="single_enemy":
			for member in target.members.slice(1):member.hp=0.0;member.wound="KIA"
			denied.Infantry.publish(target)
		else:
			for member in defender.members.slice(0,2):member.reload_until=1000.0
		automatic_step(denied,2.0)
		check(denied.throwables.preparations.is_empty() and Throws.total(defender,"frag")==3,"defensive policy respects %s"%restriction)
	var cancelled=field()
	var shooter:Dictionary=cancelled.spawn("rifle",0,SOURCE)
	cancelled.spawn("rifle",1,TARGET)
	cancelled.stop([shooter.id]);Throws.set_policy(cancelled,[shooter.id],"defensive")
	automatic_step(cancelled,0.7)
	check(cancelled.throwables.preparations.size()==1,"auto throw prepares before replacement command")
	cancelled.issue([shooter.id],Vector2(18,52),"move")
	automatic_step(cancelled,1.5)
	check(Throws.total(shooter,"frag")==3 and cancelled.throwables.projectiles.is_empty(),"a new player move interrupts automatic preparation without consumption")
	var revoked=field()
	var waiting:Dictionary=revoked.spawn("rifle",0,SOURCE)
	revoked.spawn("rifle",1,TARGET)
	revoked.stop([waiting.id]);Throws.set_policy(revoked,[waiting.id],"defensive")
	automatic_step(revoked,0.7)
	check(Throws.set_policy(revoked,[waiting.id],"manual")==1 and revoked.throwables.preparations.is_empty(),"turning delegation off cancels its uncommitted action immediately")
	automatic_step(revoked,1.5)
	check(Throws.total(waiting,"frag")==3 and revoked.throwables.projectiles.is_empty(),"manual policy does not replay old grenade work")
	var handover=field()
	var team:Dictionary=handover.spawn("rifle",0,SOURCE)
	handover.spawn("rifle",1,TARGET)
	handover.stop([team.id]);Throws.set_policy(handover,[team.id],"defensive")
	automatic_step(handover,0.7)
	check(handover.throwables.preparations.size()==1,"automatic throw enters preparation before a support handover")
	if not handover.throwables.preparations.is_empty():
		var job:Dictionary=handover.throwables.preparations[0]
		var initial:Dictionary=handover.Infantry.member_by_id(team,str(job.coverer))
		initial.reload_until=1000.0
		handover.Coordination.review(team,handover)
		var thrower:Dictionary=handover.Infantry.member_by_id(team,str(job.member))
		var replacement:String=thrower.get("covered_by","")
		check(not replacement.is_empty() and replacement!=str(initial.member_id),"a ready teammate can replace the unavailable coverer")
		automatic_step(handover,1.2)
		check(Throws.total(team,"frag")==2,"throw follows a valid reciprocal replacement supporter through release")
		check(team.members.all(func(m):return str(m.get("cover_for","")).is_empty()) and handover.actions.claims.is_empty(),"throw completion releases replacement support markers and claims immediately")
	var budgeted=field()
	for i in 5:
		var section:Dictionary=budgeted.spawn("rifle",0,Vector2(12+i*7,62))
		Throws.set_policy(budgeted,[section.id],"defensive")
		section.throw_next_review=0.0
	budgeted.actions.begin_tick(1,{"decisions":32,"line_checks":256})
	budgeted.time=1.0;budgeted.update_visibility();Throws.tick(budgeted,DT)
	check(int(budgeted.actions.work_used.get("decisions",0))==Throws.AUTO_CHECKS_PER_TICK,"registered defenders share a bounded round-robin decision budget")

func stale_automatic_cleanup()->void:
	var sim=field()
	var u:Dictionary=sim.spawn("rifle",0,SOURCE)
	var enemy:Dictionary=sim.spawn("rifle",1,TARGET)
	sim.stop([u.id]);Throws.set_policy(sim,[u.id],"defensive")
	automatic_step(sim,0.7)
	check(sim.throwables.preparations.size()==1,"automatic throw exists before a new covering assignment")
	if sim.throwables.preparations.is_empty():return
	var job:Dictionary=sim.throwables.preparations[0]
	var member:Dictionary=sim.Infantry.member_by_id(u,str(job.member))
	check(sim.issue([u.id],Vector2(18,53),"attack_move")==1,"accepted retasking cancels the old automatic throw")
	check(sim.Coordination.begin_bound(u,member,sim,enemy,{"pos":Vector2(22,62),"screened":false}),"the former thrower receives a new covering partner under the replacement order")
	member.cover_phase="SEEKING"
	var partner_id:String=member.get("covered_by","")
	var partner:Dictionary=sim.Infantry.member_by_id(u,partner_id)
	if partner.is_empty():return
	var support_id:int=sim.actions.active(u,"member:%s:support"%partner.member_id).get("id",-1)
	# Real ticks can create a cover route before expired throw jobs are swept.
	# Cleanup of the old job must not revoke the replacement order's support.
	step(sim,DT)
	check(sim.throwables.preparations.is_empty() and Throws.total(u,"frag")==3,"stale preparation retires without releasing or consuming a grenade")
	check(member.get("covered_by","")==partner_id and member.get("support_threat",-1)==enemy.id and partner.get("cover_for","")==member.member_id,"old throw cleanup preserves both sides of the new covering assignment")
	check(sim.actions.active(u,"member:%s:support"%partner.member_id).get("id",-1)==support_id,"old throw cleanup does not complete the replacement support action")

func deterministic_replay()->void:
	var results:Array=[]
	for replay in 2:
		var sim=field()
		var u:Dictionary=sim.spawn("rifle",0,SOURCE)
		var enemy:Dictionary=sim.spawn("rifle",1,TARGET)
		sim.update_visibility()
		sim.issue_throw([u.id],"frag",TARGET)
		var preparation:Dictionary=sim.throwables.preparations[0]
		var remaining:float=preparation.left
		Throws.tick(sim,0.0)
		check(preparation.left==remaining and Throws.total(u,"frag")==3,"paused action neither progresses nor consumes inventory")
		step(sim,4.0)
		results.append({"stock":Throws.total(u,"frag"),"hp":enemy.hp,"wounds":enemy.members.map(func(m):return [m.hp,m.wound,m.suppression]),"bursts":sim.events.filter(func(e):return e.type=="grenade_burst")})
	check(results[0]==results[1],"identical seeds and fixed ticks preserve throwable flight, casualty and consumption outcomes")
