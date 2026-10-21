extends SceneTree
# Reproduction of the normal Harbor policy's first rejected healthy-section
# command (225.5 s tank death, 234 s order). This is a staged collision fixture,
# not a playthrough: the anchor and two healthy bodies are the captured values.
# The same behavioral test runs against the old runtime without the new helper.
const Sim=preload("res://scripts/simulation.gd")
const Terrain=preload("res://scripts/terrain.gd")
const VehicleDamage=preload("res://scripts/vehicle_damage.gd")
const FieldOps=preload("res://scripts/field_ops.gd")
const Garrison=preload("res://scripts/garrison.gd")
const DT:=1.0/30.0
const ANCHOR:=Vector2(318.308807373047,352.877899169922)
const BODIES:=[Vector2(317.873016357422,352.895935058594),Vector2(319.158813476562,352.027893066406)]
const HULL:=Vector2(316.360443115234,349.854217529297)
const GOAL:=Vector2(334.4,342)
var checks:=0
var failures:=0
var harbor:=-1
var static_terrain:RefCounted

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		if failures<=40:printerr("FAIL: ",label)

func _init()->void:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for index in configs.size():
		if configs[index].id=="black_sea_harbor":harbor=index
	check(harbor>=0,"public Harbor scenario exists")
	if harbor<0:quit(1);return
	static_terrain=Terrain.new(harbor)
	retained_support()
	fresh_order("move")
	fresh_order("attack_move")
	retreat_order()
	queued_order()
	deferred_orders()
	stop_and_replace()
	hold_and_invalid_orders()
	blocked_controls()
	garrison_intent()
	second_wreck()
	print("WRECK SECTION RECOVERY: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)

func fresh()->Dictionary:
	var sim=Sim.new(false,harbor)
	var u:Dictionary=sim.spawn("atgm",0,ANCHOR)
	u.pos=ANCHOR
	for index in u.members.size():
		u.members[index].pos=BODIES[index]
		u.members[index].hp=52.5
	sim.rebuild_spatial()
	check(sim.terrain.traversable(u.pos,"land",sim.definitions.atgm.radius),"fixture: original section envelope is clear")
	check(u.members.all(func(m):return sim.terrain.traversable(m.pos,"land",float(m.body_radius))),"fixture: original healthy bodies are clear")
	return {"sim":sim,"u":u}

func wreck(sim,pos:Vector2=HULL)->Dictionary:
	var hull:Dictionary=sim.spawn("tank",1,Vector2(300,640))
	hull.pos=pos
	hull.facing=Vector2.UP
	VehicleDamage.ensure_state(sim,hull)
	hull.hp-=VehicleDamage._finish(sim,hull,hull.hp+1.0)
	FieldOps.sync_obstacles(sim)
	check(hull.get("wrecked",false) and hull.hp<=0.0,"fixture: real tank knockout creates wreck")
	return VehicleDamage.wrecks(sim).back()

func pressed_fixture(sim,u:Dictionary,hulk:Dictionary)->void:
	check(hulk.nav_rect.size.is_equal_approx(Vector2(3.43,3.43)),"fixture: wreck retains tank navigation footprint")
	check(not sim.terrain.traversable(u.pos,"land",sim.definitions.atgm.radius),"fixture: wreck invalidates conservative section envelope")
	check(sim.terrain.traversable(u.pos,"land",0.8),"fixture: abstract anchor remains a physical body width from wreck")
	check(u.members.all(func(m):return sim.terrain.traversable(m.pos,"land",float(m.body_radius))),"fixture: wreck has not clipped either actual soldier")

func positions(u:Dictionary)->Array:
	return [u.pos,u.members.map(func(m):return m.pos)]

func gap(pos:Vector2,rect:Rect2)->float:
	return pos.distance_to(pos.clamp(rect.position,rect.end))

# Observe only public state and ordinary ticks. Every actual movement segment
# keeps static terrain and body collision, speed, and the existing section leash.
func follows_order(sim,u:Dictionary,hulk:Dictionary,label:String,extra_block:Rect2=Rect2())->void:
	var radius:float=sim.definitions.atgm.radius
	var speed:float=sim.definitions.atgm.speed
	var original_group:int=u.command_group
	var intended:Dictionary=u.intent.duplicate(true)
	var original_goal:Vector2=intended.get("pos",GOAL)
	var original_distance:float=u.pos.distance_to(original_goal)
	var closest_distance:=original_distance
	var original_head:Dictionary=u.orders[0] if not u.orders.is_empty() else {}
	var clear_at:=-1.0
	var safe_static:=true
	var safe_bodies:=true
	var safe_speed:=true
	var safe_leash:=true
	var opens_wreck:=true
	var protects_other:=true
	var kept_intent:=true
	var kept_group:=true
	for frame in 240:
		var before:Vector2=u.pos
		var bodies:Array=u.members.map(func(m):return m.pos)
		var was_clear:bool=sim.terrain.traversable(before,"land",radius)
		var was_head:bool=not u.orders.is_empty() and is_same(u.orders[0],original_head)
		var retreating:bool=not u.orders.is_empty() and u.orders[0].mode=="retreat"
		sim.tick(DT)
		safe_speed=safe_speed and before.distance_to(u.pos)<=speed*(1.2 if retreating and was_clear else 1.0)*DT+0.002
		safe_static=safe_static and static_terrain.segment_clear(before,u.pos,"land",radius)
		closest_distance=minf(closest_distance,u.pos.distance_to(original_goal))
		if clear_at<0.0:
			opens_wreck=opens_wreck and gap(u.pos,hulk.nav_rect)+0.0001>=gap(before,hulk.nav_rect)
			if sim.terrain.traversable(u.pos,"land",radius):clear_at=(frame+1)*DT
		elif was_clear:
			safe_static=safe_static and sim.terrain.segment_clear(before,u.pos,"land",radius)
		for index in u.members.size():
			var member:Dictionary=u.members[index]
			safe_bodies=safe_bodies and sim.terrain.segment_clear(bodies[index],member.pos,"land",float(member.body_radius))
			safe_speed=safe_speed and bodies[index].distance_to(member.pos)<=speed*1.3*DT+0.002
			safe_leash=safe_leash and member.pos.distance_to(u.pos)<=sim.Infantry.Cover.LEASH+0.002
		if extra_block.size!=Vector2.ZERO:
			protects_other=protects_other and not sim.terrain.circle_rect(u.pos,radius+sim.terrain.OBSTACLE_MARGIN,extra_block)
		if not u.orders.is_empty() and is_same(u.orders[0],original_head):kept_intent=kept_intent and u.intent==intended
		elif was_head:kept_intent=kept_intent and closest_distance<1.0
		kept_group=kept_group and u.command_group==original_group
	check(clear_at>=0.0 and clear_at<=3.0,"%s: leaves wreck envelope within three seconds (%.2f s)" % [label,clear_at])
	check(closest_distance<original_distance-3.0,"%s: resumes progress toward original player goal" % label)
	check(safe_static,"%s: full section radius still respects static terrain and normal route collision" % label)
	check(safe_bodies,"%s: actual soldier movement never crosses wreck or static collision" % label)
	check(safe_speed,"%s: anchor and bodies move at bounded ordinary speed, without teleporting" % label)
	check(safe_leash,"%s: anchor stays within the existing soldier leash" % label)
	check(opens_wreck,"%s: every egress step opens or retains distance from the initially overlapping wreck" % label)
	check(protects_other,"%s: an unrelated second wreck is never waived" % label)
	check(kept_intent and kept_group,"%s: player intent and command group survive recovery" % label)
	print("  %s: clear=%.2f s, goal distance %.2f -> %.2f, state %s" % [label,clear_at,original_distance,u.pos.distance_to(original_goal),u.state])

func retained_support()->void:
	var f:=fresh();var sim=f.sim;var u:Dictionary=f.u
	check(sim.issue([u.id],GOAL,"attack_move")==1,"support: valid pre-wreck player command")
	u.path=[]
	u.maneuver={"mode":"maneuver","phase":"SUPPORT","arrived":true,"pos":ANCHOR,"deadline":20.0,"progress_at":0.0,"progress_pos":ANCHOR}
	u.next_decision=20.0
	var orders:Array=u.orders.duplicate(true)
	var hulk:=wreck(sim)
	pressed_fixture(sim,u,hulk)
	check(u.orders==orders,"support: geometry update retains the existing attack-move order")
	follows_order(sim,u,hulk,"arrived SUPPORT")

func fresh_order(mode:String)->void:
	var f:=fresh();var sim=f.sim;var u:Dictionary=f.u
	sim.stop([u.id])
	var hulk:=wreck(sim)
	pressed_fixture(sim,u,hulk)
	var before:=positions(u)
	check(sim.issue([u.id],GOAL,mode)==1,"fresh %s: healthy section accepts command after wreck appears" % mode)
	check(positions(u)==before,"fresh %s: route validation does not move anchor or bodies" % mode)
	check(not u.orders.is_empty() and u.orders[0].mode==mode and not u.hold_command,"fresh %s: new command replaces Hold" % mode)
	follows_order(sim,u,hulk,"fresh "+mode)

func retreat_order()->void:
	var f:=fresh();var sim=f.sim;var u:Dictionary=f.u
	sim.stop([u.id])
	var hulk:=wreck(sim)
	var before:=positions(u)
	check(sim.retreat([u.id])==1,"retreat: ordinary retreat command accepts the healthy section")
	check(positions(u)==before,"retreat: command planning does not teleport")
	check(not u.orders.is_empty() and u.orders[0].mode=="retreat" and not u.hold_command,"retreat: keeps retreat mode and releases Hold")
	follows_order(sim,u,hulk,"ordinary retreat")

func queued_order()->void:
	var f:=fresh();var sim=f.sim;var u:Dictionary=f.u
	check(sim.issue([u.id],GOAL,"attack_move")==1,"queue: initial command accepted")
	var first:Dictionary=u.orders[0].duplicate()
	var group:int=u.command_group
	var hulk:=wreck(sim)
	var before:=positions(u)
	check(sim.issue([u.id],Vector2(350,360),"move",true)==1,"queue: follow-up command accepted during recovery")
	check(u.orders.size()==2 and u.orders[0]==first and u.orders[1].mode=="move","queue: current command and queued tail retain precedence")
	check(u.command_group==group and positions(u)==before,"queue: appending an order neither teleports nor replaces current command group")
	follows_order(sim,u,hulk,"queued follow-up")

func deferred_orders()->void:
	for valid in [true,false]:
		var f:=fresh();var sim=f.sim;var u:Dictionary=f.u
		sim.issue([u.id],GOAL,"attack_move")
		var hulk:=wreck(sim)
		var prior:Dictionary=u.intent.duplicate()
		var prior_group:int=u.command_group
		var before:=positions(u)
		# Force the ordinary large-group deferred-slot path with one unit.
		sim.click_slots=0
		var destination:Vector2=GOAL if valid else Vector2(160,295)
		check(sim.issue([u.id],destination,"move")==1,"deferred: command initially queues for normal slot validation")
		check(positions(u)==before,"deferred: recording a pending command does not teleport")
		sim.tick(DT)
		if valid:
			check(not u.orders.is_empty() and not u.orders[0].has("slot") and u.orders[0].mode=="move","deferred: valid replacement resolves and keeps its new mode")
		else:
			check(u.intent==prior and u.command_group==prior_group,"deferred: invalid replacement restores the prior recovery order and command group")
		follows_order(sim,u,hulk,"deferred valid" if valid else "deferred invalid restores prior")

func stop_and_replace()->void:
	var f:=fresh();var sim=f.sim;var u:Dictionary=f.u
	sim.issue([u.id],GOAL,"attack_move")
	var hulk:=wreck(sim)
	sim.tick(DT)
	check(sim.stop([u.id])==1,"stop: accepted while clearing wreck")
	var stopped:Vector2=u.pos
	for frame in 15:sim.tick(DT)
	check(u.pos==stopped and u.hold_command and u.orders.is_empty(),"stop: interrupts recovery immediately and keeps explicit Hold")
	var before:=positions(u)
	check(sim.issue([u.id],GOAL,"move")==1,"stop: later valid replacement command is accepted")
	check(positions(u)==before,"stop: replacement validation does not teleport")
	follows_order(sim,u,hulk,"replacement after Stop")

func hold_and_invalid_orders()->void:
	var f:=fresh();var sim=f.sim;var u:Dictionary=f.u
	sim.stop([u.id])
	wreck(sim)
	var before:=positions(u)
	for frame in 15:sim.tick(DT)
	check(u.pos==before[0] and u.hold_command,"hold: new wreck does not override explicit Hold")
	# A missing hostile target must reject even when an egress could exist.
	var state:Dictionary=sim.order_snapshot(u)
	check(sim.issue([u.id],GOAL,"attack",false,99999)==0,"invalid: missing attack target stays rejected")
	check(sim.order_snapshot(u)==state and positions(u)==before,"invalid: rejected command preserves Hold, orders, and all positions")
	check(sim.issue([u.id],Vector2(160,295),"move")==0,"invalid: sea destination remains unreachable for infantry")
	check(u.hold_command and u.orders.is_empty() and u.pos==before[0],"invalid: rejected sea order does not arm an escape")

func blocked_controls()->void:
	for variant in ["static","other_dynamic","body","vehicle"]:
		var f:=fresh();var sim=f.sim;var u:Dictionary=f.u
		if variant=="vehicle":
			u.hp=0.0
			u=sim.spawn("tank",0,Vector2(300,640));u.pos=ANCHOR
		sim.stop([u.id])
		var hulk:=wreck(sim)
		if variant=="static":
			# Bodies remain clear; only the conservative envelope overlaps a wall.
			sim.terrain.blocks.append(Rect2(ANCHOR+Vector2(2.2,-0.7),Vector2(0.2,1.4)))
			sim.terrain.rebuild_static_index()
		elif variant=="other_dynamic":
			var block:=Rect2(ANCHOR+Vector2(2.2,-0.7),Vector2(0.2,1.4))
			sim.terrain.update_field_geometry([hulk.nav_rect,block],[hulk.nav_rect])
		elif variant=="body":u.members[0].pos=hulk.nav_rect.get_center()
		if variant in ["static","other_dynamic"]:
			check(u.members.all(func(m):return sim.terrain.traversable(m.pos,"land",float(m.body_radius))),"negative %s: actual bodies are clear, so the additional envelope collision is decisive" % variant)
		sim.rebuild_spatial()
		var before:=positions(u)
		check(sim.issue([u.id],GOAL,"move")==0,"negative %s: cannot use a wreck exception to bypass unrelated collision" % variant)
		check(positions(u)==before and u.hold_command,"negative %s: failed planning leaves authoritative state in place" % variant)

func garrison_intent()->void:
	var f:=fresh();var sim=f.sim;var u:Dictionary=f.u
	var buildings:Array=Garrison.index(sim).buildings
	var accepted:=false
	for building in buildings:
		if Garrison.order(sim,[u.id],building.id)==1:accepted=true;break
	check(accepted,"garrison: ordinary entry order can be staged before wreck")
	if not accepted:return
	var orders:Array=u.orders.duplicate(true)
	var path:Array=u.path.duplicate()
	var target:int=u.garrison_target
	wreck(sim)
	check(u.orders==orders and u.path==path and u.garrison_target==target,"garrison: obstacle update preserves an active building-entry route")
	var before:=positions(u)
	check(sim.issue([u.id],GOAL,"move")==0,"garrison: special wreck egress does not redirect building-entry movement")
	check(positions(u)==before and u.orders==orders,"garrison: failed replacement retains the entry order and positions")

func second_wreck()->void:
	var f:=fresh();var sim=f.sim;var u:Dictionary=f.u
	sim.stop([u.id])
	var second:=wreck(sim,ANCHOR+Vector2(0,6))
	check(not sim.terrain.circle_rect(u.pos,sim.definitions.atgm.radius+sim.terrain.OBSTACLE_MARGIN,second.nav_rect),"second wreck: initially outside section envelope")
	var hulk:=wreck(sim)
	check(sim.issue([u.id],GOAL,"move")==1,"second wreck: a clear alternate egress still accepts the order")
	follows_order(sim,u,hulk,"second wreck remains solid",second.nav_rect)
