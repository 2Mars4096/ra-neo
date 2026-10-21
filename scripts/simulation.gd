class_name BattleSimulation
extends RefCounted

const Weather = preload("res://scripts/weather.gd")
var weather:Dictionary = Weather.sample(0,false)

const Classic = preload("res://scripts/classic.gd")
var classic:Dictionary={}
const FieldOps = preload("res://scripts/field_ops.gd")
const Garrison = preload("res://scripts/garrison.gd")
var field_ops:Dictionary={}

const Director = preload("res://scripts/tactical_director.gd")
const Infantry = preload("res://scripts/infantry.gd")
const VehicleDamage = preload("res://scripts/vehicle_damage.gd")
const SectionRecovery = preload("res://scripts/section_recovery.gd")
const Terrain = preload("res://scripts/terrain.gd")
static var scenario_selection:=5
var scenario:Dictionary

# Prefer the current harbor operation when its authored config exists; otherwise
# keep the established Riverside default (5), clamped to the available list.
static func _static_init() -> void:
	scenario_selection=default_selection()

static func default_selection() -> int:
	var presets=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	if not presets is Array or presets.is_empty():return 0
	for index in presets.size():
		if presets[index].get("id","")=="black_sea_harbor":return index
	return mini(5,presets.size()-1)
var terrain:BattleTerrain
var definitions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/units.json"))
var effectiveness:Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/combat.json"))
var combat_rng := RandomNumberGenerator.new()
var order_feedback := ""
var order_adjusted:=false
var units: Array[Dictionary] = []
var units_by_id:Dictionary={}
var objectives: Array[Dictionary] = []
var events: Array[Dictionary] = []
var credits := 260.0
var time := 0.0
var result := ""
var next_id := 1
var command_serial:=0
var counterattack_at:=-1.0
var counterattack_sent:=false
var counterattack_ids:Array=[]
var collision_checks := 0
var spatial: Dictionary = {}
# Units per bucket layer as of rebuild_spatial (a unit's layer never changes):
# sparse layers (sea, air) are filtered directly instead of scanning cells.
var spatial_layers:Array=[[],[],[],[]]
var use_spatial_targeting:=true
var spatial_targeting_threshold:=0
# target_candidates: [section, spread bound] for sections whose soldiers stand
# wider than SPREAD_NARROW from the anchor; wide_ids maps id -> entry index.
var wide_sections:Array=[]
var wide_ids:Dictionary={}
var spread_serial:=-1
var spatial_serial:=0 # Counts rebuild_spatial calls (once per tick).
const SPREAD_NARROW:=4.0
const SPREAD_SLACK:=1.0
const NO_UNITS:=[] # Shared read-only default for empty spatial buckets.
var use_actor_index:=true
var actor_spatial:Dictionary={}
var actor_radius_max:=1.15
var ticking:=false
var capture_time := 12.0
var score_hold := 0.0
var kills := 0
var losses := 0
var sensor_clock := 0.0
var enemy_clock := 35.0
var income_clock := 0.0
var wave := 0
var recruit_clock := 0.0
var tactical_clock := 2.0
var explored: Dictionary = {}
var visible_cells: Dictionary = {}
var visibility_cache: Dictionary = {}

func _init(populate: bool = true, preset:int=-1) -> void:
	combat_rng.seed=47291
	var presets:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	var choice:=clampi(scenario_selection if preset<0 else preset,0,presets.size()-1)
	scenario=presets[choice]
	# Authored town rooflines require separated flight bands above their tallest structures.
	for kind in scenario.get("air_altitudes",{}):
		if definitions.has(kind) and definitions[kind].domain=="air":
			definitions[kind].altitude=float(scenario.air_altitudes[kind])
	terrain=Terrain.new(choice)
	# One objective per authored sector/pole pair; legacy maps author two, the harbor three.
	objectives.clear()
	for i in mini(scenario.get("sectors",[]).size(),terrain.poles.size()):
		objectives.append({"name":scenario.sectors[i],"pos":terrain.poles[i],"progress":0.0,"owner":1})
	if scenario.get("mode","")=="classic":
		Classic.setup(self)
		objectives.clear()
		terrain.poles.clear()
		if populate:Classic.populate(self)
	elif scenario.get("mode","")=="field_ops":
		FieldOps.setup(self)
		if populate:FieldOps.populate(self)
	elif populate:
		spawn("rifle", 0, Vector2(12, 50))
		spawn("rifle", 0, Vector2(18, 54))
		spawn("atgm", 0, Vector2(12, 58))
		spawn("tank", 0, Vector2(20, 60))
		spawn("drone", 0, Vector2(17, 47))
		spawn("boat", 0, Vector2(maxf(89,terrain.shore_x+7), terrain.world_size.y-13))
		spawn("rifle", 1, objectives[0].pos+Vector2(-3,1))
		spawn("atgm" if choice==1 else "rifle", 1, Vector2(60, 27))
		spawn("tank", 1, Vector2(53, 18))
		spawn("aa", 1, Vector2(72, 24))
		spawn("rifle", 1, objectives[1].pos+Vector2(0,-3))
		spawn("atgm", 1, Vector2(77, 52))
		spawn("boat", 1, Vector2(maxf(89,terrain.shore_x+7), 20))
	update_visibility()

func spawn(kind: String, team: int, pos: Vector2) -> Dictionary:
	var d: Dictionary = definitions[kind]
	pos=spawn_position(pos,kind)
	if pos.x<0: return {}
	var u := {"id":next_id,"kind":kind,"team":team,"pos":pos,"hp":float(d.hp),"max_hp":float(d.hp),"facing":Vector2.UP if team == 0 else Vector2.DOWN,"orders":[],"path":[],"cooldown":0.0,"suppression":0.0,"visible":team == 0,"seen_by":[team == 0, team == 1],"target":-1,"repath":0.0,"state":"READY","blocked_time":0.0,"last_hit":-100.0,"recovering":false,"home":pos,"aim_time":0.0,"aim_target":-1,"last_shot":-100.0,"jammed":false,"maneuver":{},"reason":"Ready","commit_until":0.0,"next_decision":0.0,"hold_command":false,"command_group":0,"speed_now":0.0,"reversing":false,"intent":{}}
	next_id += 1
	Infantry.create(u,d)
	if d.get("strike",false):u.merge({"strike_target":-1,"altitude":float(d.altitude),"fuse":time+float(d.get("endurance",60.0))})
	if not field_ops.is_empty() and d.get("structure",false):
		u.merge({"structure":true,"build_left":0.0,"engineer_id":-1,"build_paused":false},true)
	units.append(u)
	units_by_id[u.id]=u
	if ticking and use_actor_index:index_actor_unit(u)
	return u

func get_unit(id: int) -> Dictionary:
	return units_by_id.get(id,{})

func alive(u: Dictionary) -> bool:
	return not u.is_empty() and u.hp > 0.0

func living(team: int) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for u in units:
		if u.team == team and alive(u):
			list.append(u)
	return list

func issue(ids: Array, destination: Vector2, mode: String = "move", queued: bool = false, target_id: int = -1) -> int:
	if result != "":
		return 0
	order_feedback="No route • Ground units need land, ships need water"
	order_adjusted=false
	order_resolving=0
	last_command={}
	command_serial+=1
	var accepted := 0
	var formation: Dictionary = {}
	var slots: Array[Dictionary] = []
	# What the command's units share while their targets resolve, now or
	# (past CLICK_SLOTS) at the start of later ticks: resolve_slots().
	var command:={"ids":ids,"destination":destination,"mode":mode,"queued":queued,"target":target_id,"spacing":{},"slots":slots,
		"open":{}, # formation_slot memo for this command
		"section_open":{}, # team -> the same for sections (slots include held spots)
		"held":{}, # team -> held_spots, gathered once per command
		"placed":0,"pending":0,"report":{}} # units with a target so far / still resolving
	var spacing:Dictionary=command.spacing
	var resolved:=0
	terrain.begin_path_memo()
	for id in ids:
		var member:=get_unit(int(id))
		if alive(member):
			var md: Dictionary=definitions[member.kind]
			spacing[md.domain]=maxf(spacing.get(md.domain,0.0),crowd_radius(member.kind)*2.0+0.7)
	for id in ids:
		var u := get_unit(int(id))
		if not alive(u) or definitions[u.kind].get("structure",false):
			continue
		if u.get("combat_ineffective",false):
			order_feedback=DOWNED_NOTE
			continue
		if comms_blocked(u):
			order_feedback="LINK LOST • Last orders continue; capture EXCHANGE to restore radio"
			continue
		var domain: String = definitions[u.kind].domain
		var index: int = formation.get(domain, 0)
		formation[domain] = index + 1
		# A large group's click records its orders only: past the first
		# CLICK_SLOTS units, targets (formation slots, reachability) resolve in
		# command order over the next ticks while the units hold their orders.
		if mode!="attack" and resolved>=click_slots:
			if queued and u.orders.size()>=12:continue
			if is_same(command.ids,ids):command.ids=ids.duplicate()
			if not u.members.is_empty() and domain=="land" and not command.held.has(u.team):command.held[u.team]=held_spots(u,destination,ids)
			var held_at:=destination
			if ids.size()>1:held_at+=Vector2((index % 3 - 1) * spacing[domain], (index / 3) * spacing[domain])
			if not terrain.traversable(held_at,domain,float(definitions[u.kind].radius)):held_at=destination
			# Should no target turn up, the unit carries on as before the click.
			var before:Dictionary={} if queued else order_snapshot(u)
			var waiting:=record_order(u,mode,held_at,target_id,queued,true)
			waiting["slot"]=true
			slot_queue.append({"unit":u.id,"order":waiting,"index":index,"command":command,"before":before})
			command.pending+=1
			order_resolving+=1
			accepted += 1
			continue
		resolved+=1
		var plan:=order_target(u,command,index,false)
		if plan.is_empty():continue
		if u.orders.size()>=12 and queued:continue
		var order:=record_order(u,mode,plan.pos,target_id,queued)
		slots.append({"pos":plan.pos,"radius":crowd_radius(u.kind),"layer":collision_layer(u)})
		if u.orders.size() == 1:
			if not plan.get("recovery",{}).is_empty():SectionRecovery.begin(self,u,plan.recovery)
			elif plan.planned:u.path = plan.route
			else:defer_route(u,"order")
		accepted += 1
		command.placed+=1
	terrain.end_path_memo()
	if command.pending>0:last_command=command
	return accepted

# Units of the last issue() whose targets still resolve (slot_queue); its
# return value counts them as accepted until they do.
var order_resolving:=0
var last_command:Dictionary={}

# Asks for an "order_report" event (the order toast, no alert sound) once the
# last command's queued targets have resolved: `text` • placed / `of` sections
# (the unplaced had no room or route).
func report_resolution(text:String,of:int)->void:
	if not last_command.is_empty() and last_command.pending>0:last_command.report={"text":text,"of":of}

func _slot_resolved(command:Dictionary,placed:bool)->void:
	if placed:command.placed+=1
	command.pending-=1
	if command.pending>0 or command.report.is_empty():return
	var of:int=command.report.of
	var text:String=command.report.text+" • %d / %d sections" % [command.placed,of]
	if command.placed==0:text="No route or room • 0 / %d sections" % of
	elif command.placed<of:text+=" (%d no room)" % (of-command.placed)
	events.append({"type":"order_report","text":text})

# Units a group command resolves in the click; the rest queue (slot_queue).
const CLICK_SLOTS:=8
var click_slots:=CLICK_SLOTS # (tests raise it to resolve a whole group in the click)

# Where a commanded unit goes: {"pos", "planned" (route below, or queue it),
# "route"}, or {} when it cannot go. In the click (`deferred` false) a route
# within the tick's budget is planned on the spot; resolved later, only short
# hops are, the rest join the route queue.
func order_target(u:Dictionary,command:Dictionary,index:int,deferred:bool)->Dictionary:
	# Validate from a prospective clear exit, without moving the authoritative
	# anchor. A valid command then walks the bounded wreck recovery before its
	# normal route starts; an invalid destination still changes no orders.
	var recovery:=SectionRecovery.plan(self,u,true)
	if not recovery.is_empty():
		u=u.duplicate()
		u.pos=recovery.pos
	var destination:Vector2=command.destination
	var mode:String=command.mode
	var ids:Array=command.ids
	var target_id:int=command.target
	var slots:Array[Dictionary]=command.slots
	var domain: String = definitions[u.kind].domain
	var radius: float = definitions[u.kind].radius
	var target := destination
	if mode!="attack" and not terrain.traversable(destination,domain,radius):
		var sector_order:=false
		for obj in objectives:
			if destination.distance_to(obj.pos)<2.0 and domain=="land": sector_order=true
		if not sector_order:
			# Candidate spots only need reachability, not a whole smoothed route.
			terrain.path_probe=true
			target=terrain.reachable_destination(u.pos,destination,domain,radius,terrain.mobility_profile(u.kind))
			terrain.path_probe=false
			if target.x<0:return {}
			order_adjusted=true
	if mode != "attack" and ids.size() > 1:
		target += Vector2((index % 3 - 1) * command.spacing[domain], (index / 3) * command.spacing[domain])
	if not terrain.traversable(target, domain, radius):
		target = destination
	if mode == "attack":
		var enemy := get_unit(target_id)
		if not alive(enemy) or enemy.team == u.team or not contact_known(u,enemy):
			return {}
		if not effective_unit(u,enemy.kind):
			order_feedback="Weapon ineffective against this target • use a suitable counter"
			return {}
		# Attack orders pursue the last visible position, never hidden live positions.
		target = enemy.pos
		if not terrain.traversable(target, domain, radius):
			target = attack_position(u, enemy, slots+attack_rivals(u, target_id, ids, command.queued))
	# Over the tick's route budget, validate reachability only (grid search)
	# and plan the route at the start of a later tick.
	var planned:=route_cost(u.pos,target)<=0.0 if deferred else take_route_budget(u.pos,target)
	if mode!="attack":
		terrain.path_probe=not planned
		# Sections also keep clear of spots friends already hold or head for.
		if not u.members.is_empty() and domain=="land":
			if not command.held.has(u.team):command.held[u.team]=held_spots(u,destination,ids)
			target=formation_slot(target,u,slots,command.section_open.get_or_add(u.team,{}),command.held[u.team])
		else:target=formation_slot(target,u,slots,command.open)
		terrain.path_probe=false
		if target.x<0: return {}
	var route:Array=[]
	if planned:
		route=order_route(u,target,ids)
		if route.is_empty():
			return {}
	elif mode=="attack" and not terrain.reachable(u.pos,target,domain,radius,terrain.mobility_profile(u.kind)):
		return {}
	return {"pos":target,"planned":planned,"route":route,"recovery":recovery}

# A unit whose target is still resolving (`waiting`) keeps building and its
# cover until it resolves (resolve_slots), so a unit that gets none is as it was.
func record_order(u:Dictionary,mode:String,target:Vector2,target_id:int,queued:bool,waiting:bool=false)->Dictionary:
	if not queued:
		if not waiting:u.erase(SectionRecovery.KEY)
		if not waiting:FieldOps.pause_builder(self,u.id)
		Director.cancel(u)
		if not waiting:for actor in u.members:Infantry.Cover.clear(actor)
		u.command_group=command_serial
		u.orders.clear()
		u.path.clear()
		u.erase("route_pending")
	var order := {"mode":mode,"pos":target,"target":target_id}
	u.orders.append(order)
	if u.orders.size()==1:u.intent=order.duplicate()
	u.state = "ADVANCING" if mode == "attack_move" else "MOVING"
	return order

# What a new order replaces (record_order, Director.cancel), to put back.
const SNAPSHOT_KEYS:=["orders","path","intent","state","command_group","route_pending","maneuver","reason","commit_until","next_decision","hold_command","maneuver_review","wreck_recovery"]
func order_snapshot(u:Dictionary)->Dictionary:
	var snapshot:={}
	for key in SNAPSHOT_KEYS:
		if u.has(key):snapshot[key]=u[key].duplicate() if key in ["orders","path"] else u[key]
	return snapshot

func restore_orders(u:Dictionary,snapshot:Dictionary)->void:
	for key in SNAPSHOT_KEYS:
		if snapshot.has(key):u[key]=snapshot[key]
		else:u.erase(key)
	# A route it was waiting for queues again (the queue may have dropped it).
	if u.has("route_pending") and route_waiting(u) and not route_queue.has(u.id):route_queue.append(u.id)

# Queued formation slots (issue past CLICK_SLOTS), resolved first come first
# served at the start of each tick, before queued routes and out of the same
# work cap (~SLOT_WORK checks a unit). Each resolves exactly as in the click,
# against its command's slots so far; a unit whose order was replaced or that
# died meanwhile is skipped. Without a target the unit goes back to the orders
# (and route) it had before the click, as the click turns such a unit down; a
# queued (shift) order is just dropped.
const SLOT_WORK:=8
const SLOT_QUEUE_WORK:=32
var slot_queue:Array=[]
func resolve_slots()->int:
	var work:=0
	if slot_queue.is_empty():return work
	terrain.begin_path_memo()
	while not slot_queue.is_empty() and work<SLOT_QUEUE_WORK:
		var entry:Dictionary=slot_queue.pop_front()
		var u:=get_unit(int(entry.unit))
		var order:Dictionary=entry.order
		var at:=-1
		if alive(u):
			for i in u.orders.size():
				if is_same(u.orders[i],order):at=i;break
		if at<0:
			_slot_resolved(entry.command,false)
			continue
		work+=SLOT_WORK
		var plan:=order_target(u,entry.command,entry.index,true)
		order.erase("slot")
		_slot_resolved(entry.command,not plan.is_empty())
		if plan.is_empty():
			if not entry.before.is_empty():
				restore_orders(u,entry.before)
				continue
			u.orders.remove_at(at)
			if at==0:
				u.path.clear()
				u.erase("route_pending")
				start_next_order(u)
			continue
		if not entry.before.is_empty():
			FieldOps.pause_builder(self,u.id)
			for actor in u.members:Infantry.Cover.clear(actor)
		order.pos=plan.pos
		entry.command.slots.append({"pos":plan.pos,"radius":crowd_radius(u.kind),"layer":collision_layer(u)})
		if at==0:
			u.intent=order.duplicate()
			if not plan.get("recovery",{}).is_empty():SectionRecovery.begin(self,u,plan.recovery)
			elif plan.planned:u.path=plan.route
			else:defer_route(u,"order")
	terrain.end_path_memo()
	return work

# Route planning budget. A cross-map route costs ~20 ms of GDScript, so each
# tick spends a fixed, deterministic amount of planning: ROUTE_BUDGET units
# (~ms, estimated 1 + length/40 per route) for routes planned on the spot, and
# ROUTE_QUEUE_WORK string-pull checks for queued routes, which plan
# incrementally at the start of each tick, first come first served. Routes over
# budget queue (deferrable callers) or retry next tick; an urgent caller may
# still take the first route of a tick. Short tactical hops are never deferred.
const ROUTE_BUDGET:=14.0
const ROUTE_FREE_DISTANCE:=16.0
# Queued routes per tick: string-pull checks (~0.08-0.12 ms each on long
# routes) and at most one grid search, which runs whole (not resumable) and
# only starts with room left for it, so routing stays ~10-20 ms per tick.
const ROUTE_QUEUE_WORK:=100
const ROUTE_SEARCH_WORK:=40 # a queued route's grid search, in check units
const ROUTE_SEARCHES_PER_TICK:=1
const ROUTE_WORK_PER_UNIT:=14 # string-pull checks per budget unit
var route_budget:=ROUTE_BUDGET
var route_queue:Array=[]

func route_cost(from:Vector2,to:Vector2)->float:
	var distance:=from.distance_to(to)
	return 0.0 if distance<ROUTE_FREE_DISTANCE else 1.0+distance/40.0

# Charges the budget and returns true when a route may be planned now.
func take_route_budget(from:Vector2,to:Vector2,urgent:bool=false)->bool:
	var cost:=route_cost(from,to)
	if cost<=0.0:return true
	if cost>route_budget and not (urgent and route_budget>=ROUTE_BUDGET):return false
	route_budget-=cost
	return true

# Ordered route: around standing friendlies when possible, else plain terrain.
func order_route(u:Dictionary,target:Vector2,ignore:Array=[])->Array:
	var d:Dictionary=definitions[u.kind]
	var route:Array=terrain.path(u.pos,target,d.domain,float(d.radius),standing_bodies(u,u.pos,target,ignore),terrain.mobility_profile(u.kind))
	if route.is_empty():route=terrain.path(u.pos,target,d.domain,float(d.radius),[],terrain.mobility_profile(u.kind))
	return route

# The unit holds (path empty) until its queued route is ready. mode "order"
# plans like issue(), "direct" like a resumed objective (terrain only).
func defer_route(u:Dictionary,mode:String)->void:
	u.path=[]
	u["route_pending"]={"mode":mode,"order":u.orders[0]}
	if not route_queue.has(u.id):route_queue.append(u.id)

func route_waiting(u:Dictionary)->bool:
	if u.path.is_empty() and u.maneuver.is_empty() and not u.orders.is_empty() and u.orders[0].has("slot"):return true
	var pending:Dictionary=u.get("route_pending",{})
	return not pending.is_empty() and u.path.is_empty() and u.maneuver.is_empty() and not u.orders.is_empty() and is_same(u.orders[0],pending.order)

func plan_queued_routes(spent:int=0)->void:
	var work:=ROUTE_QUEUE_WORK-spent
	var searches:=ROUTE_SEARCHES_PER_TICK
	while not route_queue.is_empty() and work>0:
		var u:=get_unit(int(route_queue[0]))
		if u.has(SectionRecovery.KEY):
			route_queue.pop_front()
			u.erase("route_pending")
			continue
		# (A target still resolving re-queues its unit once known.)
		if not alive(u) or not route_waiting(u) or u.orders[0].has("slot"):
			if not u.is_empty():u.erase("route_pending")
			route_queue.pop_front()
			continue
		var pending:Dictionary=u.route_pending
		var d:Dictionary=definitions[u.kind]
		var goal:Vector2=u.orders[0].pos
		if not pending.has("job"):
			if searches<=0 or work<ROUTE_SEARCH_WORK:break
			searches-=1
			var bodies:Array=standing_bodies(u,u.pos,goal) if pending.mode=="order" and not pending.get("terrain_only",false) else []
			pending.around=not bodies.is_empty()
			pending.job=terrain.path_job(u.pos,goal,d.domain,float(d.radius),bodies,terrain.mobility_profile(u.kind))
			work-=ROUTE_SEARCH_WORK
		var job:Dictionary=pending.job
		var before:int=job.work
		var done:=terrain.path_job_step(job,maxi(0,work))
		work-=job.work-before
		if not done:break
		if job.result.is_empty() and pending.around:
			# As issue(): without a way around standing friendlies, plan on
			# terrain (a fresh search, so it takes the next search slot).
			pending.erase("job")
			pending["terrain_only"]=true
			continue
		route_queue.pop_front()
		u.erase("route_pending")
		u.path=job.result
		# As when a route runs out: the order completes and the next one plans.
		if u.path.is_empty():finish_order(u)
	route_budget-=float(ROUTE_QUEUE_WORK-work)/ROUTE_WORK_PER_UNIT

# Firing spots a group attacking a structure must not share: friends already
# attacking it keep their spots and parked friendly hulls hold theirs, so the
# attackers spread round the target instead of converging on one cell (where
# they would cycle give-way among themselves). Returns slot-style entries.
func attack_rivals(u:Dictionary,target_id:int,ids:Array,queued:bool)->Array[Dictionary]:
	var layer:=collision_layer(u)
	var rivals:Array[Dictionary]=[]
	for other in units:
		if other.id==u.id or not alive(other) or other.team!=u.team or collision_layer(other)!=layer or definitions[other.kind].get("structure",false):continue
		# Units of this command re-plan (their spots arrive as command slots).
		if not queued and (ids.has(other.id) or ids.has(float(other.id))):continue
		if other.orders.is_empty():
			if other.maneuver.is_empty():rivals.append({"pos":other.pos,"radius":crowd_radius(other.kind),"layer":layer})
			continue
		for order in other.orders:
			if order.mode=="attack" and int(order.get("target",-1))==target_id:
				# Its spot, and where it stands (stopped short to fire).
				rivals.append({"pos":order.pos,"radius":crowd_radius(other.kind),"layer":layer})
				rivals.append({"pos":other.pos,"radius":crowd_radius(other.kind),"layer":layer})
				break
	return rivals

# A land vehicle cannot pass wrecks: spots in a wreck's margin are out, and a
# spot counts as reachable only by a route round the wrecks (the hulks of an
# earlier assault can choke or close an approach: the next one takes another).
# After WRECK_SPOT_MISSES spots with no such route the far side is taken as
# closed off: no spot.
const WRECK_SPOT_MISSES:=4
func attack_position(u:Dictionary,enemy:Dictionary,taken:Array=[])->Vector2:
	var d:Dictionary=definitions[u.kind]
	var reach:float=horizontal_reach(attack_weapon(u,enemy.kind),enemy)*0.9
	var hulks:Array=[]
	if has_meta(VehicleDamage.WRECKS) and VehicleDamage.wreck_bound(self,u):
		var span:float=u.pos.distance_to(enemy.pos)+reach+20.0
		# The margin of the movement detour round wrecks (a hull's 0.4 u
		# slack), so a spot is only taken where the drive can actually go; a
		# hull touching a wreck may still plan away from it.
		var slack:float=0.4 if u.kind in ["tank","aa","boat"] else 0.0
		var can_push:bool=VehicleDamage.pusher(self,u)
		for wreck in VehicleDamage.wrecks(self):
			if can_push and not VehicleDamage.solid_wreck(self,wreck,true):continue
			var gap:float=wreck.pos.distance_to(u.pos)
			if gap<span:hulks.append({"pos":wreck.pos,"radius":minf(float(d.radius)+float(wreck.radius)+slack,gap-0.05)})
	var misses:=0
	var candidates:Array=[]
	# Only cells within reach can qualify: scan their bounding box, not the map.
	var low:Vector2i=terrain.cell(enemy.pos-Vector2.ONE*reach)
	var high:Vector2i=terrain.cell(enemy.pos+Vector2.ONE*reach)
	for x in range(low.x,high.x+1):
		for y in range(low.y,high.y+1):
			var p:Vector2=terrain.center(Vector2i(x,y))
			if not terrain.traversable(p,d.domain,float(d.radius)) or p.distance_to(enemy.pos)>reach:continue
			if definitions[enemy.kind].domain!="air" and not terrain.line_clear(p,enemy.pos):continue
			if not hulks.is_empty() and not terrain.avoids_bodies(p,p,hulks):continue
			candidates.append({"pos":p,"distance":p.distance_squared_to(u.pos)})
	candidates.sort_custom(func(a,b):return a.distance<b.distance)
	var layer:=collision_layer(u)
	var crowd:=crowd_radius(u.kind)
	var ground:bool=definitions[enemy.kind].domain!="air"
	# A free spot first; with every spot in reach taken, the nearest one.
	for spread in ([true,false] if not taken.is_empty() else [false]):
		for candidate in candidates:
			if spread and taken.any(func(slot):return slot.layer==layer and candidate.pos.distance_to(slot.pos)<crowd+float(slot.radius)+0.7):continue
			# A hull stops up to ~0.75 u off its spot: no line of fire that a
			# corner cuts at a hand's width either side.
			if ground:
				var side:Vector2=(enemy.pos-candidate.pos).normalized().orthogonal()*0.75
				if not terrain.line_clear(candidate.pos+side,enemy.pos) or not terrain.line_clear(candidate.pos-side,enemy.pos):continue
			if not terrain.path(u.pos,candidate.pos,d.domain,float(d.radius),hulks,terrain.mobility_profile(u.kind)).is_empty():return candidate.pos
			if not hulks.is_empty():
				misses+=1
				if misses>=WRECK_SPOT_MISSES:return Vector2(-1,-1)
	return Vector2(-1,-1)


func stop(ids: Array) -> int:
	var accepted:=0
	for id in ids:
		var u := get_unit(int(id))
		if alive(u) and not definitions[u.kind].get("structure",false) and not comms_blocked(u):
			FieldOps.pause_builder(self,u.id)
			accepted+=1
			u.orders.clear()
			u.path.clear()
			Director.cancel(u)
			u.intent={}
			u.hold_command=true
			u.erase(SectionRecovery.KEY)
			u.speed_now=0.0
			u.state = "HOLDING"
	return accepted

func rally_point(u: Dictionary) -> Vector2:
	if not field_ops.is_empty():return FieldOps.rally_point(self,u)
	if definitions[u.kind].domain=="sea": return Vector2(terrain.world_size.x-5,terrain.world_size.y-10) if u.team==0 else Vector2(terrain.world_size.x-5,9)
	return Vector2(15,terrain.world_size.y-11) if u.team==0 else Vector2(terrain.shore_x-7,7)

func retreat(ids: Array) -> int:
	var groups:Dictionary={}
	for id in ids:
		var u:=get_unit(int(id))
		if not alive(u):continue
		var key:=str(u.team)+":"+str(definitions[u.kind].domain)
		if not groups.has(key):groups[key]=[]
		groups[key].append(id)
	var count:=0
	for group in groups.values():
		count+=issue(group,rally_point(get_unit(group[0])),"retreat")
	return count

func update_tactics(dt: float) -> void:
	if not field_ops.is_empty():return
	# Repair only at a safe staging area, after disengagement. Enemy recovery
	# uses the same safety rules but its own limited per-unit recovery rate.
	for u in units:
		if not alive(u) or definitions[u.kind].get("structure",false):continue
		Infantry.reconcile(u)
		u.recovering=false
		if u.pos.distance_to(rally_point(u))>10 or time-u.last_hit<6 or (not u.orders.is_empty() and not (u.maneuver.get("phase","")=="WITHDRAW" and u.maneuver.get("arrived",false))):continue
		var threatened:=false
		for other in units:
			if alive(other) and other.team!=u.team and contact_known(u,other) and not passive_work(other) and other.pos.distance_to(u.pos)<24:
				threatened=true
		if threatened or u.hp>=Infantry.capacity(u):continue
		var heal:=minf(u.max_hp-u.hp,dt*6)
		if u.team==0:
			heal=minf(heal,credits/0.25)
			if not u.members.is_empty():
				heal=Infantry.recover(u,heal)
			credits-=heal*0.25
		if heal>0:
			if u.members.is_empty():u.hp+=heal
			elif u.team==1:Infantry.recover(u,heal)
			u.suppression=maxf(0,u.suppression-dt)
			u.recovering=true
			u.state="RECOVERING"
	if scenario.get("autonomy",false):return
	tactical_clock-=dt
	if tactical_clock>0:return
	tactical_clock=3.0
	for u in living(1):
		if definitions[u.kind].domain!="land" or u.get("combat_ineffective",false):continue
		if u.hp<Infantry.capacity(u)*0.3:
			if u.orders.is_empty() and u.pos.distance_to(rally_point(u))>10:retreat([u.id])
			elif not u.orders.is_empty() and u.orders[0].mode!="retreat":retreat([u.id])
			continue
		if u.recovering and u.hp<Infantry.capacity(u)*0.8:continue
		if not u.orders.is_empty():continue
		var closest:Dictionary={}
		var distance:=26.0
		for other in living(0):
			if not other.seen_by[1] or definitions[other.kind].domain!="land":continue
			var d:float=u.pos.distance_to(other.pos)
			if d<distance:closest=other;distance=d
		if not closest.is_empty() and not can_fire(u,closest):
			issue([u.id],closest.pos,"attack_move")
		elif closest.is_empty() and u.hp>=Infantry.capacity(u)*0.8 and u.pos.distance_to(u.home)>12:
			issue([u.id],u.home,"attack_move")

func recruit(kind: String) -> bool:
	if not field_ops.is_empty():return FieldOps.purchase(self,kind)
	if not classic.is_empty():return Classic.enqueue(self,kind)
	if not definitions.has(kind) or result != "" or recruit_clock > 0:
		return false
	var d: Dictionary = definitions[kind]
	if credits < float(d.cost):
		return false
	var p := Vector2(terrain.shore_x+7, terrain.world_size.y-10) if d.domain == "sea" else Vector2(10 + (next_id % 4) * 3, terrain.world_size.y-8)
	if spawn(kind,0,p).is_empty(): return false
	credits-=float(d.cost)
	recruit_clock=3.0
	return true

func update_visibility() -> void:
	var indexed:bool=use_spatial_targeting and units.size()>=spatial_targeting_threshold
	if indexed and not ticking:rebuild_spatial()
	var site_probes:Array=FieldOps.enemy_site_probes(self) if not field_ops.is_empty() else []
	var processed_fields:Dictionary={}
	visible_cells.clear()
	# Garrison shelter per soldier: during a walked entry/exit a section sees
	# from the building once anyone is indoors, and is concealed only while
	# every living soldier is indoors. Ids of units with any / all indoors.
	var sheltered_any:Dictionary={}
	var sheltered_all:Dictionary={}
	for u in units:
		u.seen_by = [false, false]
		if alive(u):
			u.seen_by[u.team] = true
			if Garrison.inside(u):
				sheltered_any[u.id]=true;sheltered_all[u.id]=true
			elif Garrison.transit(u)!="":
				var shelter:=indoors_share(u)
				if shelter>0:sheltered_any[u.id]=true
				if shelter>1:sheltered_all[u.id]=true
	# Cover and concealment depend on the target's position only: once per
	# target per update, not per observer (terrain.cover is the costly part).
	var target_terrain:Dictionary={}
	for observer in units:
		if not alive(observer) or observer.get("build_left",0.0)>0 or comms_blocked(observer):
			continue
		var d: Dictionary = definitions[observer.kind]
		var sight_radius:float=float(d.sight)*float(weather.sight_scale)+(Garrison.SIGHT_BONUS if sheltered_any.has(observer.id) else 0.0)
		# A garrison watches every face of its building, not just from the
		# doorway anchor (the building itself would hide the other faces).
		var posts:Array=Garrison.lookouts(self,observer)
		var reach:float=sight_radius
		for post in posts:reach=maxf(reach,sight_radius+observer.pos.distance_to(post))
		var candidates:Array=range_candidates(observer.pos,reach) if indexed else units
		if observer.team==1 and not site_probes.is_empty():candidates=candidates+site_probes
		for target in candidates:
			if not alive(target) or target.team == observer.team:
				continue
			var radius := sight_radius
			var land:bool=definitions[target.kind].domain == "land"
			var ground:Array=target_terrain.get(target.id,NO_UNITS)
			if ground.is_empty() and land:
				ground=[terrain.cover(target.pos),terrain.concealment(target.pos)]
				target_terrain[target.id]=ground
			if land and ground[0]:
				radius *= 0.7
			if sheltered_all.has(target.id) and time-float(target.get("last_shot",-100.0))>=3.0:radius*=0.6
			if land and time-float(target.get("last_shot",-100.0))>=3.0:radius*=ground[1]
			if not posts.is_empty():
				if target.seen_by[observer.team]:continue
				var air:bool=definitions[target.kind].domain == "air"
				for post in posts:
					if post.distance_squared_to(target.pos) <= radius * radius and (air or terrain.line_clear(post, target.pos)):
						target.seen_by[observer.team] = true
						break
			elif observer.pos.distance_squared_to(target.pos) <= radius * radius:
				if d.domain == "air" or definitions[target.kind].domain == "air" or terrain.line_clear(observer.pos, target.pos):
					target.seen_by[observer.team] = true
		if observer.team == 0:
			var origin := terrain.cell(observer.pos)
			var sight:float=float(d.sight)*float(weather.sight_scale)
			var key := "%d:%d:%s:%.2f" % [origin.x,origin.y,observer.kind,weather.sight_scale]
			if processed_fields.has(key):continue
			processed_fields[key]=true
			if not visibility_cache.has(key):
				# Tile -> true in scan order: merged natively below, same keys
				# and insertion order as setting each tile in turn.
				var field: Dictionary = {}
				var r := ceili(sight / fog_cell_size())
				var source := terrain.center(origin)
				for x in range(maxi(0, origin.x-r), mini(terrain.fog_grid_size.x, origin.x+r+1)):
					for y in range(maxi(0, origin.y-r), mini(terrain.fog_grid_size.y, origin.y+r+1)):
						var tile := Vector2i(x,y)
						var p := terrain.center(tile)
						if source.distance_squared_to(p) <= sight*sight and (d.domain=="air" or terrain.line_clear(source,p)):
							field[tile]=true
				if visibility_cache.size()>=512:
					visibility_cache.clear()
				visibility_cache[key]=field
			visible_cells.merge(visibility_cache[key])
			explored.merge(visibility_cache[key])
	for u in units:
		u.visible = u.team == 0 or u.seen_by[0]
	if not field_ops.is_empty():FieldOps.observe_enemy_sites(self,site_probes)

# Living soldiers of a section in garrison transit that are through the wall:
# 0 none, 1 some, 2 all.
func indoors_share(u:Dictionary)->int:
	var n_in:=0
	var n_out:=0
	for m in u.members:
		if m.hp<=0:continue
		if bool(m.get("indoors",false)):n_in+=1
		else:n_out+=1
	return 0 if n_in==0 else (2 if n_out==0 else 1)

# World metres per fog cell; scenarios may author coarser fog than the legacy 2 m.
func fog_cell_size() -> float:
	return float(terrain.get("fog_cell_size")) if "fog_cell_size" in terrain else terrain.CELL

# Armed emplacements (bunkers, gun pits) hold position and engage the nearest
# known enemy in their weapon envelope; unarmed or unfinished works never fire.
# Passive field works (wire, trenches, hedgehogs, nets, berms, sandbags, posts,
# depots) never draw automatic fire; they are engaged only on an explicit
# attack order (right-click = force attack). Armed emplacements stay targets.
func passive_work(other:Dictionary)->bool:
	var od:Dictionary=definitions.get(other.get("kind",""),{})
	return od.get("structure",false) and not od.get("armed",false)

func ordered_target(u:Dictionary)->int:
	return int(u.orders[0].get("target",-1)) if not u.orders.is_empty() and u.orders[0].mode=="attack" else -1

# A tank's coax never locks onto a scout drone by itself (it would ignore armour);
# it engages scouts on order and inbound strike drones automatically.
func auto_target_ok(u:Dictionary,other:Dictionary)->bool:
	# Nobody keeps shooting a section that is only wounded men on the ground.
	if other.get("combat_ineffective",false) and other.get("id",-2)!=ordered_target(u):return false
	if passive_work(other):return other.get("id",-2)==ordered_target(u)
	if AIR_REACH.has(u.kind) and definitions[other.kind].domain=="air" and not definitions[other.kind].get("strike",false):return other.id==ordered_target(u)
	return true

func emplacement_fire(u:Dictionary,d:Dictionary,dt:float)->void:
	u.cooldown-=dt
	var target:Dictionary=get_unit(u.target)
	if not can_fire(u,target):
		target={}
		var best:=INF
		for other in target_candidates(u):
			if can_fire(u,other) and auto_target_ok(u,other) and target_priority(u,other)<best:
				best=target_priority(u,other);target=other
	u.target=target.get("id",-1)
	if target.is_empty():
		u.aim_time=0.0;u.state="READY"
		return
	if u.aim_target!=u.target:u.aim_time=0.0;u.aim_target=u.target
	u.aim_time+=dt
	u.facing=(target.pos-u.pos).normalized()
	u.state="ENGAGING"
	if u.cooldown<=0 and u.aim_time>=0.5:
		u.last_shot=time
		u.cooldown=float(d.interval)
		resolve_shot(u,target,1.0)

func can_fire(u: Dictionary, other: Dictionary) -> bool:
	if not VehicleDamage.weapon_ready(self,u):return false
	var ud:Dictionary=definitions[u.kind]
	if ud.get("structure",false) and (not ud.get("armed",false) or u.get("build_left",0.0)>0):return false
	if u.maneuver.get("phase","")=="WITHDRAW" or (not u.orders.is_empty() and u.orders[0].mode=="retreat"):return false
	if not alive(other) or u.team == other.team or not contact_known(u,other):
		return false
	if not u.get("members",[]).is_empty():
		var budget:int=soldier_checks+SECTION_CHECKS
		for member in u.members:
			if member.hp<=0:continue
			var weapon:String=section_weapon(u,member)
			if weapon_reaches(weapon,member.pos,other,mini(SOLDIER_CHECKS,budget-soldier_checks)):return true
			if soldier_checks>=budget:return false
		return false
	return weapon_reaches(u.kind,u.pos,other)

func weapon_reaches(weapon:String,source:Vector2,other:Dictionary,checks:int=SOLDIER_CHECKS) -> bool:
	if not effective_weapon(weapon,other.kind):return false
	var d:Dictionary=definitions[weapon]
	var td:Dictionary=definitions[other.kind]
	# Inlined unit_altitude/weapon_range: this runs for every candidate and soldier.
	var height:float=float(d.altitude)-float(other.get("altitude",td.altitude))
	var reach:float=AIR_REACH[weapon] if td.domain=="air" and AIR_REACH.has(weapon) else float(d.range)
	# A section is reached through one of its soldiers, not its anchor.
	if not other.get("members",[]).is_empty():
		return not aim_soldier(source,other,reach*reach-height*height,d.domain!="air" and td.domain!="air",INF,checks).is_empty()
	if source.distance_squared_to(other.pos)+height*height>reach*reach:return false
	return d.domain=="air" or td.domain=="air" or terrain.line_clear(source,other.pos)

# Per-soldier targeting. Fire at a section goes at one of its soldiers: the
# nearest able one (not down or KIA) within `reach_sq` (squared ground
# distance) and nearer than `limit` that the source has a clear line of fire
# to. At most `checks` line checks, nearest first (soldier_checks counts
# them); air weapons and aircraft need no line. Empty when none qualifies.
const SOLDIER_CHECKS:=3   # line checks per shooter and target section
const SECTION_CHECKS:=8   # per squad can_fire call (all its soldiers)
const SHOOTER_CHECKS:=6   # per soldier and tick across target sections
var soldier_checks:=0
func aim_soldier(source:Vector2,other:Dictionary,reach_sq:float,needs_line:bool,limit:float=INF,checks:int=SOLDIER_CHECKS)->Dictionary:
	var bound:float=minf(reach_sq,limit)
	var tried:=0
	for attempt in checks:
		var best:Dictionary={}
		var best_distance:=INF
		var best_bit:=0
		var bit:=1
		for member in other.members:
			if member.hp>0 and not (tried&bit):
				var distance:float=source.distance_squared_to(member.pos)
				if distance<best_distance and distance<=bound:best=member;best_distance=distance;best_bit=bit
			bit<<=1
		if best.is_empty() or not needs_line:return best
		soldier_checks+=1
		if terrain.line_clear(source,best.pos):return best
		tried|=best_bit
	return {}

# The soldier a resolved shot strikes when the caller did not choose one
# (vehicles, emplacements, direct calls): per-soldier line of fire, else the
# soldier nearest the shooter (legacy fixtures without a line) if `fallback`.
func shot_victim(u:Dictionary,target:Dictionary,fallback:bool=true) -> Dictionary:
	if target.members.is_empty():return {}
	var d:Dictionary=definitions[u.kind]
	var td:Dictionary=definitions[target.kind]
	var height:float=unit_altitude(u)-unit_altitude(target)
	var reach:float=weapon_range(u.kind,td)
	var victim:=aim_soldier(u.pos,target,reach*reach-height*height,d.domain!="air" and td.domain!="air")
	return victim if not victim.is_empty() or not fallback else Infantry.exposed_member(target,u.pos)

# Counter-UAV model. Slant range applies against air targets (altitude counts),
# so rifles only reach a high scout nearly overhead while AA covers a wide
# circle. A tank fights aircraft with its elevation-limited coaxial MG only.
const AIR_REACH:={"tank":15.0}
# Chance per shot against small UAVs: AA is the counter, small arms rarely hit
# (the low, larger FPV a little more often than the high scout), weapons not
# listed get 0.35.
const UAV_HIT:={"drone":{"aa":0.72,"rifle":0.16,"tank":0.18,"bunker":0.3},"fpv_drone":{"aa":0.72,"rifle":0.22,"tank":0.18,"bunker":0.3}}

func weapon_range(weapon:String,td:Dictionary) -> float:
	if td.domain=="air" and AIR_REACH.has(weapon):return AIR_REACH[weapon]
	return float(definitions[weapon].range)

# Aircraft hold their cruise altitude but climb over authored structures taller
# than it (terrain.air_ceiling falls off as a cone, so the climb is continuous).
# A strike drone only follows while cruising; it owns its altitude once lining up.
const AIR_GAP:=2.5
func follow_skyline(u:Dictionary,d:Dictionary)->void:
	var strike:bool=d.get("strike",false)
	if strike and u.state!="MOVING":return
	var cruise:float=float(d.altitude)
	var altitude:float=maxf(minf(float(u.get("altitude",cruise)),cruise),terrain.air_ceiling(u.pos)+AIR_GAP)
	if strike or altitude!=cruise:u["altitude"]=altitude
	elif u.has("altitude"):u.erase("altitude")

# Flight altitude of an aircraft at its cruise over `pos`.
func flight_altitude(d:Dictionary,pos:Vector2)->float:
	return maxf(float(d.altitude),terrain.air_ceiling(pos)+AIR_GAP)

# Per-unit altitude: FPV drones descend during their terminal dive.
func unit_altitude(u:Dictionary) -> float:
	return float(u.get("altitude",definitions[u.kind].altitude))

# The weapon a unit brings against this kind (squads: Javelin or rifles).
func attack_weapon(u:Dictionary,target_kind:String) -> String:
	if u.get("members",[]).is_empty():return u.kind
	return "atgm" if u.kind=="atgm" and missiles_left(u)>0 and effective_weapon("atgm",target_kind) else "rifle"

# Ground distance at which the weapon reaches this target, net of its altitude.
func horizontal_reach(weapon:String,other:Dictionary) -> float:
	var reach:float=weapon_range(weapon,definitions[other.kind])
	var height:float=float(definitions[weapon].altitude)-unit_altitude(other)
	return sqrt(maxf(1.0,reach*reach-height*height))

# Automatic target choice: nearest first, but an inbound strike drone is engaged
# before anything else and air-defence vehicles prefer aircraft.
func target_priority(u:Dictionary,other:Dictionary) -> float:
	var score:float=u.pos.distance_squared_to(other.pos)
	var od:Dictionary=definitions[other.kind]
	if od.get("strike",false):return score*0.2
	if u.kind=="aa" and od.domain=="air":return score*0.3
	return score


func comms_blocked(u:Dictionary) -> bool:
	return float(scenario.get("jam_radius",0))>0 and not objectives.is_empty() and objectives[0].owner==1 and u.team==0 and u.pos.distance_to(objectives[0].pos)<float(scenario.jam_radius)

func contact_known(u:Dictionary,other:Dictionary) -> bool:
	if not alive(other):return false
	if not comms_blocked(u):return other.seen_by[u.team]
	var d:Dictionary=definitions[u.kind]
	var sight:float=d.sight*weather.sight_scale
	if terrain.cover(other.pos) and definitions[other.kind].domain=="land":sight*=0.7
	if definitions[other.kind].domain=="land" and time-float(other.get("last_shot",-100.0))>=3.0:sight*=terrain.concealment(other.pos)
	return u.pos.distance_to(other.pos)<=sight and (d.domain=="air" or definitions[other.kind].domain=="air" or terrain.line_clear(u.pos,other.pos))

func effective_unit(u:Dictionary,target_kind:String) -> bool:
	if u.get("members",[]).is_empty():return effective_weapon(u.kind,target_kind)
	for member in u.members:
		if member.hp>0 and effective_weapon(section_weapon(u,member),target_kind):return true
	return false

func effective_weapon(weapon:String, target_kind:String) -> bool:
	return float(effectiveness[weapon][target_kind])>0

func shot_distance(u:Dictionary,other:Dictionary,victim:Dictionary={}) -> float:
	var height:float=unit_altitude(u)-unit_altitude(other)
	return sqrt(u.pos.distance_squared_to(victim.pos if not victim.is_empty() else other.pos)+height*height)

# `victim`: the soldier aimed at when the target is a section (aim_soldier).
func hit_chance(u:Dictionary,other:Dictionary,victim:Dictionary={}) -> float:
	if not effective_weapon(u.kind,other.kind):return 0.0
	var chance:=0.95
	if UAV_HIT.has(other.kind):chance=UAV_HIT[other.kind].get(u.kind,0.35)
	elif other.kind=="helo":chance=0.85 if u.kind=="aa" else 0.45
	elif not other.get("members",[]).is_empty():chance=infantry_exposure(u,other,victim)
	var fraction:=clampf(shot_distance(u,other,victim)/maxf(1,weapon_range(u.kind,definitions[other.kind])),0,1)
	chance*=lerpf(1.0,0.65,fraction*fraction)
	# A diving strike drone flies straight at its victim: little crossing motion.
	if other.state in ["MOVING","ADVANCING","RETREATING"]:chance*=0.65
	if u.state in ["MOVING","ADVANCING","RETREATING"]:chance*=0.7
	if u.suppression>0.6:chance*=0.55
	chance*=float(u.get("accuracy",1.0))
	return clampf(chance,0.01,0.98)

# Base chance for a shot at a soldier. Aimed small-arms fire must strike a
# man-sized target (RIFLE_HIT point blank, under half that at full range); HE
# needs only a near miss. Posture, cover, trench and garrison shrink the
# soldier aimed at (by default the one nearest the shooter).
const RIFLE_HIT:=0.45
func infantry_exposure(u:Dictionary,other:Dictionary,aimed:Dictionary={}) -> float:
	var exposure:=1.0
	var victim:Dictionary=aimed if not aimed.is_empty() else Infantry.exposed_member(other,u.pos)
	if not victim.is_empty():
		var posture:String=victim.get("posture","STANDING")
		if posture=="PRONE":exposure*=0.5
		elif posture=="CROUCHED":exposure*=0.75
		if victim.get("in_trench",false):exposure*=0.5
		elif terrain.cover(victim.pos) or VehicleDamage.wreck_cover(self,victim.pos,u.pos):exposure*=0.7
	if Garrison.member_indoors(other,victim):exposure*=0.6
	if definitions[u.kind].get("combat_alias",u.kind) in HE_WEAPONS:return 0.95*(0.55+0.45*exposure)
	var fraction:=clampf(shot_distance(u,other,victim)/maxf(1,weapon_range(u.kind,definitions[other.kind])),0,1)
	return RIFLE_HIT*exposure*lerpf(1.0,0.45,fraction)

# One rifle round from a squad soldier (15 x 0.25) is the reference bullet.
const BULLET_REF:=3.75
# A hit on a section wounds soldiers instead of removing HP. damage_amount's
# cover/garrison reduction becomes lethality < 1 (milder outcomes); weak rounds
# (engineer carbines) are milder too. See Infantry.OUTCOMES. `victim` is the
# soldier struck (default: the one nearest the shooter).
func infantry_hit(u:Dictionary,target:Dictionary,amount:float,scale:float,victim:Dictionary={}) -> void:
	var raw:float=float(definitions[u.kind].damage)*float(effectiveness[u.kind][target.kind])*scale
	if amount<=0.0 or raw<=0.0:return
	var he:bool=definitions[u.kind].get("combat_alias",u.kind) in HE_WEAPONS
	var lethality:float=amount/raw if he else amount/BULLET_REF
	# Infantry.strike wounds the soldier nearest its source point: the victim's own position.
	Infantry.strike(target,"HE" if he else "BULLET",lethality,victim.pos if not victim.is_empty() else u.pos,time,combat_rng)

const HE_WEAPONS:=["tank","helo","boat","aa","at_gun","atgm"]
# Against a section the shot goes at one soldier (`victim`, else shot_victim):
# range, exposure, cover, the wound and the tracer endpoint are all his.
func resolve_shot(u:Dictionary,target:Dictionary,scale:float,victim:Dictionary={}) -> bool:
	if not alive(target) or not effective_weapon(u.kind,target.kind):return false
	if victim.is_empty():victim=shot_victim(u,target)
	elif victim.hp<=0:
		# Downed earlier this tick: re-aim at another soldier in sight, or hold fire.
		victim=shot_victim(u,target,false)
		if victim.is_empty():return false
	var hit:bool=combat_rng.randf()<(guided_hit_chance(u,target,victim) if u.get("guided",false) else hit_chance(u,target,victim))
	if hit:
		var amount:float=damage_amount(u,target,victim)*scale
		# Buildings, field works, drones and sandbags: what reaches the target (structure_damage.gd).
		amount=preload("res://scripts/structure_damage.gd").strike(self,u,target,amount,victim)
		if target.members.is_empty():
			# Vehicles: penetration and component damage decide the integrity loss.
			Infantry.hit(target,VehicleDamage.strike(self,u,target,amount),u.pos,time)
		# Soldiers are wounded or killed (HE also wounds those nearby).
		else:infantry_hit(u,target,amount,scale,victim)
		target.last_hit=time
	# Near misses can suppress exposed people; armor never receives rifle chip damage.
	if definitions[target.kind].domain=="land" and definitions[target.kind].armor==0:
		# Sustained machine-gun fire from a bunker pins infantry harder than rifles.
		var pin:float=0.18 if u.kind=="bunker" else (0.09 if definitions[u.kind].get("combat_alias",u.kind)=="rifle" else 0.23)
		if Garrison.member_indoors(target,victim):pin*=Garrison.SUPPRESSION_SCALE
		# Fallen comrades shake a section: casualties raise suppression.
		if not target.members.is_empty():pin*=1.0+0.25*Infantry.casualties(target)
		target.suppression=minf(1,target.suppression+pin)
	var endpoint:Vector2=victim.pos if not victim.is_empty() else target.pos
	if not hit:endpoint+=Vector2.from_angle(combat_rng.randf()*TAU)*combat_rng.randf_range(2.5,4.5)
	# Weapons with an AIR_REACH fire their machine gun at aircraft, not the main gun.
	var shot_kind:String="rifle" if AIR_REACH.has(u.kind) and definitions[target.kind].domain=="air" else (u.kind if u.kind in ["at_gun","bunker"] else definitions[u.kind].get("combat_alias",u.kind))
	# A guided missile showed its flight at launch (launch_missile); hand back the impact.
	if u.get("guided",false):u["impact"]={"to":endpoint,"hit":hit}
	else:events.append({"type":"shot","from":u.pos,"to":endpoint,"kind":shot_kind,"target_kind":target.kind,"hit":hit,"from_y":u.get("fire_height",maxf(0.95,definitions[u.kind].altitude)),"to_y":maxf(0.8,unit_altitude(target)),"visible":u.visible or target.visible})
	if target.hp<=0:
		# A crew bail-out leaves an intact hull: presentation shows no blast.
		events.append({"type":"destroyed","kind":target.kind,"pos":target.pos,"visible":target.visible,"abandoned":target.get("abandoned",false)})
		if target.team==1:kills+=1;credits+=(35 if field_ops.is_empty() else 0)
		else:losses+=1
	return hit

# A locked seeker: the engagement success rate against vehicles; against a
# section, the aimed soldier's exposure only (the launcher's suppression and
# motion no longer matter once the missile is away).
func guided_hit_chance(u:Dictionary,target:Dictionary,victim:Dictionary) -> float:
	if target.members.is_empty():return float(definitions[u.kind].get("seeker_hit",0.94))
	var steady:Dictionary=u.duplicate()
	steady.suppression=0.0
	steady.state="READY"
	return hit_chance(steady,target,victim)

# ATGM flight. The Javelin is fire-and-forget: its seeker locks on before
# launch (infantry_combat preparation) and the missile then guides itself, so
# the gunner is free to fire, move or take cover. It flies for the real time of
# flight at the engagement range (units.json atgm flight_real, FM 3-21.71
# App. F: 1,000 m 4.6 s, 2,000 m 14.5 s; game units scale range_m to range),
# compressed by GAME_TIME_SCALE like the rest of the weapon cycle (Javelin
# reload ~20 s real, 7 s here). The seeker follows the target wherever it
# moves and strikes it at impact (resolve_shot from the launch point, so the
# hull face is the one the launcher saw) with the seeker_hit engagement success
# rate. If the target is destroyed in flight the missile comes down on its last
# position. A missile that misses bursts where it lands (miss_blast). The sim
# has no smoke yet, so nothing else breaks the lock. Armoured land and sea
# hulls beyond top_attack_min_m are hit on the roof (VehicleDamage.top_attack).
# Presentation: the launch "shot" event carries the flight time; effects.gd
# follows the entry in `missiles` (aim, done, end, hit) and audio_fx.gd voices
# the "missile_impact" event.
const GAME_TIME_SCALE:=0.35
var missiles:Array=[]

# Game seconds of flight for weapon row `d` over `distance` units.
static func missile_flight(d:Dictionary,distance:float)->float:
	var metres:float=distance*float(d.range_m)/float(d.range)
	var table:Array=d.flight_real
	var k:=1
	while k<table.size()-1 and metres>float(table[k][0]):k+=1
	var a:Array=table[k-1]
	var b:Array=table[k]
	var real:float=lerpf(float(a[1]),float(b[1]),(metres-float(a[0]))/(float(b[0])-float(a[0])))
	return maxf(0.1,real*GAME_TIME_SCALE)

func launch_missile(u:Dictionary,proxy:Dictionary,target:Dictionary,scale:float,victim:Dictionary) -> void:
	var d:Dictionary=definitions[proxy.kind]
	var aim:Vector2=victim.pos if not victim.is_empty() else target.pos
	var distance:float=proxy.pos.distance_to(aim)
	proxy["guided"]=true
	if VehicleDamage.top_attack(self,d,target,distance):proxy["attack"]="top"
	var flight:float=missile_flight(d,distance)
	var visible:bool=u.visible or target.visible
	var missile:={"shooter":u.id,"team":u.team,"target":target.id,"victim":victim,"proxy":proxy,"scale":scale,
		"from":proxy.pos,"launched":time,"flight":flight,"impact_at":time+flight,"aim":aim,"aim_y":maxf(0.8,unit_altitude(target)),
		"mode":proxy.get("attack","direct"),"target_kind":target.kind,"visible":visible,"lost":"","done":false,"hit":false,"end":aim}
	missiles.append(missile)
	events.append({"type":"shot","from":proxy.pos,"to":aim,"kind":proxy.kind,"target_kind":target.kind,"hit":true,"from_y":proxy.fire_height,"to_y":missile.aim_y,"visible":visible,"flight":flight,"guided":true,"attack":missile.mode})

# Per tick after the unit loop: the seeker follows its target; impacts that are due.
func tick_missiles() -> void:
	tick_ammo()
	for i in range(missiles.size()-1,-1,-1):
		var m:Dictionary=missiles[i]
		var target:=get_unit(int(m.target))
		if m.lost=="":
			if alive(target):m.aim=m.victim.pos if not m.victim.is_empty() and m.victim.hp>0 else target.pos
			else:m.lost="destroyed"
		if time<float(m.impact_at):continue
		missiles.remove_at(i)
		missile_impact(m,target)

# Javelin missile load. A team carries units.json atgm.missiles rounds (the CLU
# with one round on the gunner, two more on the ammunition bearer: 6.4 kg CLU,
# 15.9 kg per round). When they are spent the gunner fights with his rifle.
# Rounds are drawn only near a friendly supply source (SUPPLY_KINDS, or the
# side's rear rally point), one per resupply_real s (game time scaled), and
# not while under fire. AI-controlled sides (team 1) send an empty team back
# to the nearest source and return it to its last order when full.
const SUPPLY_KINDS:=["hq","refinery","forward_supply_point","command_post","ammo_depot"]
const SUPPLY_REACH:=5.0
const RESUPPLY_QUIET:=3.0
const AMMO_PERIOD:=0.5
var ammo_checked:=0.0

func missiles_left(u:Dictionary) -> int:
	if u.kind!="atgm":return 0
	return int(u.get("missiles",definitions.atgm.missiles))

func section_weapon(u:Dictionary,member:Dictionary) -> String:
	return "atgm" if u.kind=="atgm" and member.index==0 and missiles_left(u)>0 else "rifle"

func spend_missile(u:Dictionary) -> void:
	u["missiles"]=maxi(0,missiles_left(u)-1)
	u.erase("resupply_done")
	if u.missiles==0 and u.team==0:events.append({"type":"warning","text":"Javelin team out of missiles · resupply at HQ or a supply point","notice":"low"})

# Nearest friendly supply source: {pos, reach} (reach: distance to stand within).
func supply_source(u:Dictionary) -> Dictionary:
	var best:={"pos":rally_point(u),"reach":SUPPLY_REACH}
	var nearest:float=u.pos.distance_to(best.pos)
	for other in units:
		if other.team!=u.team or not (other.kind in SUPPLY_KINDS) or not alive(other) or float(other.get("build_left",0.0))>0:continue
		var reach:float=float(definitions[other.kind].get("radius",2.0))+SUPPLY_REACH
		var gap:float=u.pos.distance_to(other.pos)-reach
		if gap<nearest:
			nearest=gap
			best={"pos":other.pos,"reach":reach}
	return best

func tick_ammo() -> void:
	var elapsed:float=time-ammo_checked
	if elapsed<AMMO_PERIOD:return
	ammo_checked=time
	var d:Dictionary=definitions.atgm
	var load:int=int(d.missiles)
	var per_round:float=float(d.resupply_real)*GAME_TIME_SCALE
	for u in units:
		if u.kind!="atgm" or not alive(u):continue
		var left:int=missiles_left(u)
		if left>=load:continue
		var source:=supply_source(u)
		if u.pos.distance_to(source.pos)<=float(source.reach):
			if time-float(u.last_hit)<RESUPPLY_QUIET:continue
			u["resupply_done"]=float(u.get("resupply_done",0.0))+elapsed
			if float(u.resupply_done)>=per_round:
				u.resupply_done=float(u.resupply_done)-per_round
				left+=1
				u["missiles"]=left
			u.reason="Resupplying missiles %d/%d" % [left,load]
			if left>=load:
				u.erase("resupply_done")
				if u.has("resupply_resume"):
					var resume:Dictionary=u.resupply_resume
					u.erase("resupply_resume")
					# Unless re-tasked meanwhile (an order away from the source).
					if u.orders.is_empty() or Vector2(u.orders[-1].pos).distance_to(source.pos)<=float(source.reach)+2.0:issue([u.id],resume.pos,resume.mode)
			continue
		if u.team==0 or left>0 or Garrison.inside(u):continue
		# AI: an empty team heads back for rounds (re-sent if re-tasked elsewhere).
		var heading:bool=not u.orders.is_empty() and Vector2(u.orders[-1].pos).distance_to(source.pos)<=float(source.reach)+2.0
		if heading:continue
		if not u.has("resupply_resume") and not u.orders.is_empty():u["resupply_resume"]={"pos":u.orders[-1].pos,"mode":"attack_move" if u.orders[-1].mode in ["attack","attack_move"] else u.orders[-1].mode}
		var away:Vector2=u.pos-source.pos
		var stand:Vector2=source.pos+(away.normalized() if away.length()>0.01 else Vector2.DOWN)*(float(source.reach)-1.5)
		if issue([u.id],stand,"move")>0:u.reason="Out of missiles · returning to resupply"

func missile_impact(m:Dictionary,target:Dictionary) -> void:
	if m.lost=="":
		var proxy:Dictionary=m.proxy
		m.hit=resolve_shot(proxy,target,float(m.scale),m.victim)
		var impact:Dictionary=proxy.get("impact",{})
		m.end=impact.get("to",m.aim)
		m.visible=bool(m.visible) or target.visible
	else:
		# Target destroyed in flight: the missile strikes its last position
		# (the wreck, if one is left there).
		m.end=m.aim
		m.hit=target.get("wrecked",false)
	m.done=true
	events.append({"type":"missile_impact","pos":m.end,"y":float(m.aim_y) if m.hit else 0.0,"hit":m.hit,"target_kind":m.target_kind if m.hit else "","lost":m.lost,"mode":m.mode,"visible":m.visible})
	if not m.hit or m.lost!="":
		# No target struck: the warhead still bursts where the missile lands.
		var blast:Dictionary=definitions[m.proxy.kind].get("miss_blast",{})
		if not blast.is_empty():preload("res://scripts/structure_damage.gd").explosion(self,m.end,float(blast.radius),float(blast.damage),float(blast.structure),"missile")

func damage_amount(u: Dictionary, other: Dictionary, victim:Dictionary={}) -> float:
	var d: Dictionary = definitions[u.kind]
	var td: Dictionary = definitions[other.kind]
	var damage := float(d.damage)*float(effectiveness[u.kind][other.kind])
	# Vehicles: expected loss given penetration odds by weapon, hull face and range.
	if other.members.is_empty() and damage>0 and td.has("armor_mm"):damage*=VehicleDamage.expected_scale(self,u,other)
	var cover_pos:Vector2=other.pos
	var nearest_member:=INF
	if not victim.is_empty():cover_pos=victim.pos;nearest_member=-1.0
	for member in other.get("members",[]):
		if member.hp>0 and member.pos.distance_squared_to(u.pos)<nearest_member:
			nearest_member=member.pos.distance_squared_to(u.pos)
			cover_pos=member.pos
			victim=member
	if Garrison.member_indoors(other,victim):
		# Walls stop small arms; HE shells and missiles punch through windows.
		damage *= Garrison.DAMAGE_SCALE if u.kind in ["rifle","engineer","drone","helo","aa","boat"] else 0.85
	elif td.armor == 0 and td.domain == "land" and terrain.cover(cover_pos):
		damage *= 0.55
	elif td.armor > 0 and td.domain == "land" and d.domain == "land" and u.get("attack","")!="top" and terrain.hull_down(other.pos,u.pos):
		damage *= 0.6
	return damage

# HE blast at a point (FPV strike, demolition) against one section: soldiers
# within `radius` are wounded by distance; trench or cover halves the effect.
# Returns true if any soldier was caught. fpv_detonate's member loop can call
# this instead of subtracting member hp (see Infantry.publish fallback).
func infantry_blast(target:Dictionary,origin:Vector2,radius:float,lethality:float=1.0) -> bool:
	Infantry.reconcile(target)
	var struck:=false
	for member in target.members:
		if member.hp<=0:continue
		var gap:float=origin.distance_to(member.pos)
		if gap>radius:continue
		struck=true
		var falloff:=1.0-gap/radius
		var shelter:float=0.5 if member.get("in_trench",false) or terrain.cover(member.pos) else 1.0
		# Walls take most of the blast for a soldier indoors (garrison or mid-transit).
		var walls:float=0.4 if Garrison.member_indoors(target,member) else 1.0
		member.suppression=minf(1.0,member.suppression+0.6)
		member.last_hit=time
		if combat_rng.randf()<(0.35+0.65*falloff)*shelter:
			Infantry.wound(target,member,Infantry.roll("HE" if falloff>0.6 else "FRAGMENT",lethality*walls*shelter*(0.4+0.6*falloff),combat_rng),time,combat_rng)
		elif member.state!="DOWN":member.state="BRACING"
	Infantry.publish(target)
	return struck

# FPV strike drones (loitering munitions): straight-line homing on an assigned
# enemy at cruise altitude, a brief staggered hover at dive_range while the
# operator lines up (dropping to hover_altitude), then a dive and one blast that
# destroys the drone. No pathfinding; air units fly over terrain.
func fpv_strike(u:Dictionary,d:Dictionary,dt:float) -> void:
	var target:=get_unit(int(u.get("strike_target",-1)))
	if not alive(target) or target.team==u.team:
		target=fpv_retarget(u)
		u.strike_target=target.get("id",-1)
	if target.is_empty() or time>=float(u.get("fuse",INF)):
		fpv_detonate(u,d)
		return
	var offset:Vector2=target.pos-u.pos
	var distance:float=offset.length()
	var dive_range:float=float(d.dive_range)
	var hover_altitude:float=float(d.hover_altitude)
	var speed:float=float(d.speed)
	if distance>0.01:u.facing=offset/distance
	if distance<=dive_range and not u.has("dive_at"):
		u.dive_at=time+float(d.hover_seconds)+float(u.id%4)*0.35
	if u.has("dive_at") and time<float(u.dive_at):
		# Lining up: hold off at dive range and descend; nearly stationary.
		u.altitude=move_toward(float(u.altitude),hover_altitude,dt*6.0)
		speed=maxf(0.0,distance-dive_range*0.9)/dt if distance>dive_range*0.9 else 0.0
		speed=minf(speed,float(d.speed))
		u.state="ACQUIRING"
	elif u.has("dive_at"):
		speed=float(d.dive_speed)
		u.altitude=minf(float(u.altitude),lerpf(0.8,hover_altitude,clampf(distance/dive_range,0.0,1.0)))
		u.state="DIVING"
	else:
		u.state="MOVING"
	if u.state=="DIVING" and distance<=maxf(1.2,speed*dt):
		u.pos=target.pos
		fpv_detonate(u,d)
		return
	u.pos+=u.facing*minf(speed*dt,distance)
	u.speed_now=speed
	u.target=target.id

# A new lock requires current team/local knowledge, just as the initial launch
# does. A live assigned target keeps the existing flight guidance in fpv_strike;
# neither this rule nor site memory changes a Javelin already in flight.
# Nearest known ground or sea unit within 40 m (works only when no troops).
func fpv_retarget(u:Dictionary) -> Dictionary:
	var best:Dictionary={}
	var best_score:=40.0*40.0
	for other in units:
		if not alive(other) or other.team==u.team or definitions[other.kind].domain=="air" or not contact_known(u,other):continue
		var score:float=u.pos.distance_squared_to(other.pos)
		if definitions[other.kind].get("structure",false):score+=900.0
		if score<best_score:best_score=score;best=other
	return best

# One blast: damage falls off with distance; armour, cover, trenches and
# buildings soften it; air units are untouched. The drone is destroyed.
func fpv_detonate(u:Dictionary,d:Dictionary) -> void:
	u.hp=0.0
	var radius:float=float(d.blast_radius)
	var blast:float=float(d.blast_damage)
	var origin:Vector2=u.pos
	var seen:bool=u.visible or u.seen_by[0]
	for other in units:
		if not alive(other) or other.team==u.team:continue
		var od:Dictionary=definitions[other.kind]
		if od.domain=="air" or origin.distance_squared_to(other.pos)>pow(radius+float(od.radius),2):continue
		var scale:float=0.6 if float(od.armor)>0 else 1.0
		# Sections: the building factor is applied per soldier in infantry_blast.
		if other.members.is_empty() and Garrison.inside(other):scale*=0.4
		var struck:=false
		if other.members.is_empty():
			var gap:float=maxf(0.0,origin.distance_to(other.pos)-float(od.radius)*0.5)
			if gap>radius:continue
			other.hp-=blast*scale*(1.0-0.7*gap/radius)
			struck=true
		# Soldiers go through the wound model (KIA / severe / light by distance).
		else:struck=infantry_blast(other,origin,radius,scale)
		if not struck:continue
		other.last_hit=time
		if od.domain=="land" and float(od.armor)==0:other.suppression=minf(1.0,other.suppression+0.5)
		seen=seen or other.visible
		if other.hp<=0:
			events.append({"type":"destroyed","kind":other.kind,"pos":other.pos,"visible":other.visible})
			if other.team==1:kills+=1
			else:losses+=1
	events.append({"type":"destroyed","kind":u.kind,"pos":origin,"visible":seen})

# Weather re-weighting of cached nav grids, in cells per tick (~1 ms); a
# full 256x192 grid catches up in 4 ticks.
const NAV_WEIGHT_CELLS_PER_TICK:=12288
# Opt-in phase timing for profiling tools (off in play).
var profiling:=false
var profile:Dictionary={}
func _lap(key:String,started:int)->int:
	var now:=Time.get_ticks_usec()
	profile[key]=profile.get(key,0.0)+(now-started)/1000.0
	return now

func tick(dt: float) -> void:
	if result != "":
		return
	var lap:int=Time.get_ticks_usec() if profiling else 0
	rebuild_spatial()
	if use_actor_index:rebuild_actor_spatial()
	ticking=true
	time += dt
	weather=Weather.sample(time,scenario.get("autonomy",false))
	terrain.wetness=weather.wetness
	terrain.advance_navigation_weights(NAV_WEIGHT_CELLS_PER_TICK)
	route_budget=ROUTE_BUDGET
	if profiling:lap=_lap("setup+spatial",lap)
	plan_queued_routes(resolve_slots())
	if profiling:lap=_lap("route_queue",lap)
	recruit_clock = maxf(0, recruit_clock-dt)
	sensor_clock -= dt
	if profiling:lap=_lap("setup+spatial",lap)
	if sensor_clock <= 0:
		update_visibility()
		sensor_clock = 0.3
	if profiling:lap=_lap("visibility",lap)
	Director.update(self)
	if profiling:lap=_lap("director",lap)
	Garrison.tick(self,dt)
	for u in units:
		if not alive(u):
			continue
		var blocked:=comms_blocked(u)
		if blocked!=u.jammed and u.team==0:
			events.append({"type":"warning","text":"LINK LOST • Last orders and local defense continue" if blocked else "RADIO RESTORED • New orders available","notice":"info" if blocked else "low"})
		u.jammed=blocked
		var d: Dictionary = definitions[u.kind]
		if d.get("structure",false):
			if d.get("armed",false) and u.get("build_left",0.0)<=0:emplacement_fire(u,d,dt)
			continue
		if d.domain=="air" and not u.has("crash"):follow_skyline(u,d)
		if d.get("strike",false):fpv_strike(u,d,dt);continue
		u.cooldown -= dt
		u.repath -= dt
		Infantry.reconcile(u)
		if u.get("combat_ineffective",false):hold_downed(u)
		var recovering_wreck:=SectionRecovery.step(self,u,dt)
		var move_lap:int=Time.get_ticks_usec() if profiling else 0
		if not Garrison.inside(u) and Garrison.transit(u)=="":Infantry.move(u,self,dt)
		else:Garrison.tick_members(u,dt)
		if profiling:_lap("infantry_move",move_lap)
		u.suppression = maxf(0, u.suppression-dt*0.12)
		var target_lap:int=Time.get_ticks_usec() if profiling else 0
		# Vehicles list candidates only when they need a new target (the list has
		# no side effects for them beyond the per-tick wide-section refresh).
		var candidates:Variant=null
		if not u.members.is_empty():candidates=target_candidates(u)
		elif float(d.damage)>0 and spatial_targeting():refresh_wide_sections()
		var target: Dictionary = {}
		if not u.orders.is_empty() and u.orders[0].mode == "attack":
			var desired := get_unit(u.orders[0].target)
			if can_fire(u, desired):
				target = desired
		if target.is_empty():
			var previous_target:=get_unit(u.target)
			if can_fire(u,previous_target) and auto_target_ok(u,previous_target):target=previous_target
		# Nearest-priority choice (first wins ties). can_fire is the costly test,
		# so it only runs for enemies that would beat the current best and pass
		# the cheap auto_target_ok; its only side effect (VehicleDamage.weapon_ready,
		# idempotent within a tick) is applied once up front exactly as the first
		# can_fire call did (soldier_checks budgets are relative per call).
		if target.is_empty() and candidates==null:candidates=target_candidates(u)
		if target.is_empty() and not candidates.is_empty() and VehicleDamage.weapon_ready(self,u):
			var distance := INF
			for other in candidates:
				# can_fire rejects the dead: skip them before the priority tests.
				if other.team==u.team or not alive(other):continue
				var dist: float = target_priority(u,other)
				if dist < distance and auto_target_ok(u,other) and can_fire(u, other):
					target = other
					distance = dist
		u.target = target.get("id", -1)
		if u.aim_target!=u.target:
			u.aim_time=0.0
			u.aim_target=u.target
		if u.target>=0:u.aim_time+=dt
		else:u.aim_time=0.0
		var moving: bool = not u.orders.is_empty()
		if moving and u.orders[0].mode not in ["move","retreat"] and not target.is_empty() and not pressing_on(u):
			moving = false
		if not u.maneuver.is_empty():moving=not u.maneuver.arrived
		if Infantry.Cover.seeking(u) or u.get("regroup_active",false) or Garrison.transit(u)!="":moving=false
		if recovering_wreck:moving=false
		if not u.members.is_empty() and scenario.get("autonomy",false):
			if moving:u.erase("engage_halt_at");u.erase("engage_shift")
			elif target.is_empty() or recovering_wreck:u.erase("engage_shift")
			else:space_engaged(u,target,dt)
		if profiling:target_lap=_lap("unit_targeting",target_lap)
		if moving:
			move_unit(u, dt)
			if profiling:target_lap=_lap("move_unit",target_lap)
		elif recovering_wreck:pass
		elif not target.is_empty():
			u.state = "ENGAGING"
		elif u.orders.is_empty():
			if Garrison.inside(u):u.state="GARRISONED"
			elif Garrison.transit(u)!="":u.state="ENTERING" if Garrison.transit(u)=="IN" else "EXITING"
			else:u.state="SUPPRESSED" if u.suppression > 0.6 else "READY"
		if not moving and not recovering_wreck:u.speed_now=move_toward(u.speed_now,0.0,dt*8.0)
		if not u.members.is_empty():
			var combat_lap:int=Time.get_ticks_usec() if profiling else 0
			infantry_combat(u,dt,candidates)
			if profiling:_lap("infantry_combat",combat_lap)
			continue
		if not target.is_empty():
			if not moving and u.kind not in ["tank","aa","boat"]:u.facing = (target.pos-u.pos).normalized()
			var preparation:float=0.7 if u.kind in ["tank","atgm","boat"] else 0.25
			if u.aim_time<preparation:u.state="AIMING"
			if u.cooldown <= 0 and u.aim_time>=preparation:
				u.last_shot=time
				u.cooldown = float(d.interval)*(1.8 if u.suppression>0.6 else 1.0)
				resolve_shot(u,target,1.0)

	if profiling:lap=_lap("unit_loop",lap)
	tick_missiles()
	VehicleDamage.tick_recrew(self,dt)
	preload("res://scripts/structure_damage.gd").tick(self,dt)
	update_tactics(dt)
	unstack_sections()
	if profiling:lap=_lap("tactics",lap)
	if not field_ops.is_empty():
		FieldOps.tick(self,dt)
		if profiling:lap=_lap("field_ops",lap)
		update_objectives(dt)
	elif classic.is_empty():
		update_objectives(dt)
		showcase_mission()
	else:Classic.tick(self,dt)
	if profiling:lap=_lap("mission",lap)
	enemy_clock -= dt
	if enemy_clock <= 0 and field_ops.is_empty() and not scenario.get("autonomy",false):
		enemy_clock = 50.0
		wave += 1
		if wave <= 4:
			var reinforcement := spawn("rifle" if wave % 2 else "tank", 1, Vector2(76, 7))
			if not reinforcement.is_empty() and not objectives.is_empty():issue([reinforcement.id], objectives[wave%objectives.size()].pos, "attack_move")
			events.append({"type":"warning","text":"Enemy reserves approaching from the north","notice":"alert"})
	income_clock += dt
	if income_clock >= 1.0 and classic.is_empty() and field_ops.is_empty():
		income_clock -= 1.0
		credits += 2.0 + (3.0 if not objectives.is_empty() and objectives[0].owner == 0 else 0.0)
	if living(0).is_empty() and classic.is_empty():
		result = "DEFEAT"

	ticking=false

# Sections halted to fight keep about two section radii apart, so one burst or
# round cannot catch both. The later arrival (a section in cover never) shifts
# its anchor to the nearest clear spot with a line of fire to its target.
const ENGAGED_SPACING:=4.0
const SPACING_REACH:=6.0
func fight_halted(o:Dictionary)->bool:
	if o.members.is_empty() or not alive(o) or Garrison.inside(o) or Garrison.transit(o)!="" or o.has("garrison_target"):return false
	if not o.maneuver.is_empty():return o.maneuver.get("arrived",false)
	return o.orders.is_empty() or o.hold_command or int(o.target)>=0 or Infantry.Cover.seeking(o)

func holds_shelter(u:Dictionary)->bool:
	return u.members.any(func(m):return m.hp>0 and (m.get("occupying",false) or m.get("cover_phase","") in ["SETTLING","SHELTERED"]))

func space_engaged(u:Dictionary,target:Dictionary,dt:float)->void:
	var since:float=u.get_or_add("engage_halt_at",time)
	if u.hold_command or not u.maneuver.is_empty() or u.get("regroup_active",false) or Garrison.inside(u) or Garrison.transit(u)!="" or u.has("garrison_target"):
		u.erase("engage_shift");return
	if u.has("engage_shift"):
		var spot:Vector2=u.engage_shift
		# Soldiers follow the anchor in formation until they have gathered on
		# the new spot (or a few seconds pass); cover searches resume from there.
		if u.pos.distance_to(spot)<0.01:
			if time>=float(u.get("shift_until",0.0)) or u.members.all(func(m):return m.hp<=0 or m.pos.distance_to(u.pos+m.offset)<1.2):
				u.erase("engage_shift");return
		u["cover_resume_after"]=time+0.2
		var previous:Vector2=u.pos
		var old_bucket:=bucket(u)
		u.pos=u.pos.move_toward(spot,float(definitions[u.kind].speed)*terrain.ground_speed(u.pos,"infantry")*dt)
		u.facing=(target.pos-u.pos).normalized() if target.pos!=u.pos else u.facing
		var new_bucket:=bucket(u)
		if new_bucket!=old_bucket:
			spatial[old_bucket].erase(u)
			if not spatial.has(new_bucket):spatial[new_bucket]=[]
			spatial[new_bucket].append(u)
		if previous.distance_to(u.pos)<0.001 and u.pos.distance_to(spot)>=0.01:u.erase("engage_shift")
		return
	if time<float(u.get("spacing_check",0.0)):return
	u["spacing_check"]=time+0.5+float(u.id%5)*0.05
	if holds_shelter(u) or Infantry.Cover.seeking(u):return
	# Where the soldiers are: trailing ones may still be passing the other section.
	var body:=Vector2.ZERO
	var living:=0
	for member in u.members:
		if member.hp>0:body+=member.pos;living+=1
	if living==0:return
	body/=living
	var anchors:PackedVector2Array=[]
	var crowded:=false
	for other in range_candidates(u.pos,SPACING_REACH+ENGAGED_SPACING+4.0):
		if other.id==u.id or other.team!=u.team or not fight_halted(other):continue
		var at:Vector2=other.get("engage_shift",other.pos)
		anchors.append(at)
		if other.pos.distance_squared_to(u.pos)>=ENGAGED_SPACING*ENGAGED_SPACING and at.distance_squared_to(u.pos)>=ENGAGED_SPACING*ENGAGED_SPACING:continue
		# The section already there (or in cover) holds; the later one moves.
		var first:float=other.get("engage_halt_at",-INF)
		if holds_shelter(other) or first<since or (first==since and other.id<u.id):crowded=true
	if not crowded:return
	var radius:float=float(definitions[u.kind].radius)
	var center:Vector2=body if body.distance_to(u.pos)>1.5 else u.pos
	var reach:float=maxf(float(definitions.rifle.range),u.pos.distance_to(target.pos)+0.5)
	var closing:float=center.distance_to(target.pos)
	var spots:Array=[]
	for ring in [0.0,2.0,3.0,4.0,5.0,SPACING_REACH]:
		for index in (1 if ring==0.0 else 12):
			var p:Vector2=center+Vector2.from_angle(index*TAU/12+ring)*ring
			if p.distance_to(target.pos)>reach:continue
			var clear:=true
			for at in anchors:
				if p.distance_squared_to(at)<ENGAGED_SPACING*ENGAGED_SPACING:clear=false;break
			if not clear:continue
			# Fire positions sideways or back, not a rush at the enemy.
			var score:float=ring+maxf(0.0,closing-p.distance_to(target.pos)-1.0)*3.0
			spots.append({"pos":p,"score":score})
	spots.sort_custom(func(a,b):return a.score<b.score)
	for entry in spots.slice(0,10):
		var p:Vector2=entry.pos
		if not terrain.traversable(p,"land",radius) or not terrain.segment_clear(u.pos,p,"land",radius) or not terrain.line_clear(p,target.pos):continue
		# Soldiers reach their new slots without filing through the other section.
		# A trailing soldier whose current slot already lies beyond it passes
		# anyway: only a path that newly crosses the footprint counts.
		var through:=false
		for member in u.members:
			if member.hp<=0:continue
			for at in anchors:
				var gap:float=minf(Infantry.Cover.FOOTPRINT,member.pos.distance_to(at)-0.1)
				if Geometry2D.get_closest_point_to_segment(at,member.pos,p+member.offset).distance_to(at)<gap and Geometry2D.get_closest_point_to_segment(at,member.pos,u.pos+member.offset).distance_to(at)>=gap:through=true
		if through:continue
		u["engage_shift"]=p
		u["shift_until"]=time+u.pos.distance_to(p)/maxf(0.5,float(definitions[u.kind].speed))+1.0
		u.reason="Spacing out from a friendly section"
		return

func infantry_combat(u:Dictionary,dt:float,candidates:Variant=null) -> void:
	if candidates==null:candidates=target_candidates(u)
	Infantry.tick_wounds(u,time,dt,self)
	# Carrying a SEVERE casualty slows the section's advance (Infantry.move
	# records the anchor before move_unit; shortening a cleared step is safe).
	if u.has("carry_from"):
		if Infantry.carrying(u):u.pos=(u.carry_from as Vector2).lerp(u.pos,Infantry.CARRY_SCALE)
		u.erase("carry_from")
	var eligible_by_weapon:Dictionary={}
	var autonomy:bool=scenario.get("autonomy",false)
	if autonomy:Infantry.note_fire(u,time)
	var contact:bool=autonomy and Infantry.in_contact(u,time)
	for member in u.members:
		if member.hp<=0:continue
		member["in_trench"]=terrain.dug_in(member.pos)
		if u.maneuver.get("phase","")=="WITHDRAW" or (not u.orders.is_empty() and u.orders[0].mode=="retreat"):
			member.state="WITHDRAWING"
			member.target=-1
			member.aim=0.0
			continue
		if member.get("aiding",-1)>=0:
			# Buddy aid: the soldier stops fighting while treating a casualty, or
			# dragging it to shelter under fire (Infantry.tick_wounds).
			var casualty:Dictionary=u.members[member.aiding]
			var reach:float=member.pos.distance_to(casualty.pos)
			if casualty.has("drag_to") and reach<=Infantry.AID_REACH+0.6:member.state="DRAGGING"
			else:member.state="AIDING" if Garrison.inside(u) or reach<=Infantry.AID_REACH else "TO CASUALTY"
			member.target=-1
			member.aim=0.0
			if member.state in ["AIDING","DRAGGING"]:member.posture="CROUCHED"
			continue
		if member.get("cover_phase","") in ["SEEKING","SETTLING"]:
			member.state="RUNNING TO COVER" if member.cover_phase=="SEEKING" else "SETTLING IN COVER"
			member.aim=0.0
			if member.posture!="RISING" or time>=member.posture_until:
				member.posture="STANDING" if member.cover_phase=="SEEKING" and not member.in_trench else "CROUCHED"
			continue
		var weapon:String=section_weapon(u,member)
		if weapon=="atgm":
			# Missiles are kept for vehicles, works and troops in buildings; with
			# none of those in reach the gunner fights with his rifle.
			if not eligible_by_weapon.has("atgm"):
				var marks:Array=[]
				for other in candidates:
					if alive(other) and other.team!=u.team and contact_known(u,other) and effective_weapon("atgm",other.kind) and auto_target_ok(u,other) and (other.members.is_empty() or Garrison.inside(other)):marks.append(other)
				eligible_by_weapon["atgm"]=marks
			if eligible_by_weapon["atgm"].is_empty():weapon="rifle"
		var d:Dictionary=definitions[weapon]
		var target:Dictionary={}
		var victim:Dictionary={}
		var checks_left:int=soldier_checks+SHOOTER_CHECKS
		# Upper-floor windows: garrisoned soldiers out-range troops in the street.
		var range_scale:float=Garrison.RANGE_SCALE if Garrison.inside(u) else 1.0
		var nearest:=pow(float(d.range)*range_scale,2)
		# Knowledge, faction and weapon suitability are shared by this squad.
		# Position/range/line of fire remain individual and deaths are rechecked
		# after each shot, preserving sequential combat outcomes.
		if not eligible_by_weapon.has(weapon):
			var eligible:Array=[]
			for other in candidates:
				if alive(other) and other.team!=u.team and contact_known(u,other) and effective_weapon(weapon,other.kind) and auto_target_ok(u,other):eligible.append(other)
			eligible_by_weapon[weapon]=eligible
		for other in eligible_by_weapon[weapon]:
			if not alive(other):continue
			var od:Dictionary=definitions[other.kind]
			var air:bool=od.domain=="air"
			if not other.members.is_empty():
				# Sections: aim at a soldier this man can see, nearest first.
				var ordered:bool=not u.orders.is_empty() and u.orders[0].mode=="attack" and other.id==u.orders[0].target
				var budget:int=mini(SOLDIER_CHECKS,checks_left-soldier_checks)
				if budget<=0:continue
				var reach_sq:float=pow(float(d.range)*range_scale,2)
				var soldier:=aim_soldier(member.pos,other,reach_sq,true,INF if ordered else nearest,budget)
				if soldier.is_empty():continue
				target=other;victim=soldier
				nearest=-1.0 if ordered else member.pos.distance_squared_to(soldier.pos)
				continue
			var distance:float=member.pos.distance_squared_to(other.pos)
			var reach:float=float(d.range)*range_scale
			if air:
				distance+=pow(unit_altitude(other),2)
				reach=weapon_range(weapon,od)
			var priority:float=distance*(0.2 if od.get("strike",false) else 1.0)
			# Keep tracking the same aircraft instead of re-aiming at every swap.
			if air and other.id==member.target:priority*=0.5
			if not u.orders.is_empty() and u.orders[0].mode=="attack" and other.id==u.orders[0].target:priority=-1.0
			if distance<reach*reach and priority<nearest and (air or terrain.line_clear(member.pos,other.pos)):
				target=other;victim={};nearest=priority
		var target_id:int=target.get("id",-1)
		if member.target!=target_id:member.aim=0.0
		member.target=target_id
		if target.is_empty():
			member.aim=0.0
			# In a trench or any shelter soldiers stay down behind the parapet;
			# holding still in contact or alert (any cover phase) they keep low
			# too (contact drill), flat when pinned, caught in crossfire, or under
			# fire in the open with no shelter in reach.
			var phase:String=member.get("cover_phase","")
			var sheltered:bool=member.in_trench or phase=="SETTLING" or phase=="SHELTERED"
			var still:bool=autonomy and member.travel<=0.003
			var rest:String="CROUCHED" if sheltered or (still and (contact or phase!="")) else "STANDING"
			if still and (contact or maxf(member.suppression,u.suppression)>0.65) and Infantry.goes_flat(u,member,self,contact,phase):rest="PRONE"
			if member.posture=="PRONE" and rest!="PRONE":
				member.posture="RISING"
				member.posture_until=time+0.45
			elif member.posture!="RISING" or time>=member.posture_until:
				member.posture=rest
				if sheltered and member.has("hold_facing"):member.facing=member.facing.slerp(member.hold_facing,0.2).normalized()
				member.body_radius=1.15 if rest=="PRONE" else 0.8
			continue
		if autonomy:
			if member.posture=="RISING" and time<member.posture_until:
				member.aim=0.0;member.state="RISING";continue
			var pressure:float=maxf(member.suppression,u.suppression)
			var desired_posture:="STANDING" if member.travel>0.003 else "CROUCHED"
			if member.travel<=0.003 and (pressure>0.65 or contact) and Infantry.goes_flat(u,member,self,contact,member.get("cover_phase","")):desired_posture="PRONE"
			if desired_posture!=member.posture:
				member.posture=desired_posture
				member.posture_until=time+0.35
				member.aim=0.0
			if member.posture=="PRONE":member.body_radius=1.15
			elif time>=member.posture_until:member.body_radius=0.8
			# Pinned soldiers stay flat; one prone by choice (crossfire, open ground) still fires.
			if member.posture=="PRONE" and pressure>0.65:member.state="PINNED";member.aim=0.0;continue
			if member.travel>0.003 or time<member.posture_until:
				member.state="SETTLING";member.aim=0.0;continue
			var direction:Vector2=((victim.pos if not victim.is_empty() else target.pos)-member.pos).normalized()
			member.facing=member.facing.rotated(clampf(member.facing.angle_to(direction),-dt*4,dt*4))
			if member.facing.dot(direction)<0.97:member.state="TURNING";member.aim=0.0;continue
			if member.reload_until>time:
				member.state="RELOADING"
				member.aim=0.0
				continue
			if member.rounds<=0:
				member.rounds=1 if weapon=="atgm" else 6
				member.reload_until=time+(3.0 if weapon=="atgm" else 1.8)
				member.state="RELOADING"
				member.aim=0.0
				continue
		member.aim+=dt
		member.facing=((victim.pos if not victim.is_empty() else target.pos)-member.pos).normalized()
		# ATGM: the seeker lock-on before launch (target in line of sight; a new
		# target restarts it): units.json lock_real seconds at GAME_TIME_SCALE.
		var preparation:float=float(d.lock_real)*GAME_TIME_SCALE if weapon=="atgm" else (0.45 if scenario.get("autonomy",false) else 0.2)+member.index*0.05
		var hurt:bool=member.get("wound","")==Infantry.LIGHT
		if hurt:preparation*=Infantry.LIGHT_AIM
		member.state="ACQUIRING" if member.aim<preparation else "CYCLING"
		if member.cooldown>0 or member.aim<preparation:continue
		var proxy:Dictionary=u.duplicate()
		proxy.kind=weapon
		proxy.pos=member.pos
		proxy["fire_height"]=0.75 if member.posture=="CROUCHED" else (0.4 if member.posture=="PRONE" else 0.95)
		proxy.suppression=maxf(u.suppression,member.suppression)
		if hurt:proxy["accuracy"]=Infantry.LIGHT_ACCURACY
		var scale:float=(1.0 if weapon=="atgm" else 0.25)*(0.4 if u.kind=="engineer" else 1.0)
		if weapon=="atgm":
			launch_missile(u,proxy,target,scale,victim)
			spend_missile(u)
		else:resolve_shot(proxy,target,scale,victim)
		member.cooldown=float(d.interval)*(1.8 if proxy.suppression>0.6 else 1.0)
		member.rounds-=1
		member.last_shot=time
		member.state="FIRING"
		u.last_shot=time

func move_unit(u: Dictionary, dt: float) -> void:
	var mobility:float=VehicleDamage.before_move(self,u)
	if mobility<=0.0:return
	dt*=mobility
	var d: Dictionary = definitions[u.kind]
	var order: Dictionary = u.maneuver if not u.maneuver.is_empty() else u.orders[0]
	# A hull with no headway (see `stalled` below) leaves re-planning to the
	# detour, which knows the bodies and wrecks a plain chase route ignores.
	var jammed:bool=u.has("stall_at") and time-float(u.stall_seen)<=0.5 and u.pos.distance_to(u.stall_pos)<=1.5 and time-float(u.stall_at)>2.0
	if order.mode == "attack" and u.repath <= 0 and u.blocked_time<=1.5 and not jammed:
		var target := get_unit(order.target)
		if not alive(target):
			finish_order(u)
			return
		if contact_known(u,target) and terrain.traversable(target.pos, d.domain,float(d.radius)):
			# Chase a target that moved; a standing one keeps the current route
			# (re-planning it would discard detours round bodies and wrecks).
			if order.pos.distance_to(target.pos)<=1.0 and not u.path.is_empty():u.repath = 1.0
			# Over budget: keep the current route and retry next tick.
			elif take_route_budget(u.pos,target.pos,true):
				order.pos = target.pos
				u.path = terrain.path(u.pos, order.pos, d.domain,float(d.radius),[],terrain.mobility_profile(u.kind))
				u.repath = 1.0
		else:u.repath = 1.0
	if route_waiting(u):
		u.speed_now=move_toward(u.speed_now,0.0,dt*8.0)
		return
	while not u.path.is_empty() and u.pos.distance_to(u.path[0])<0.1:u.path.pop_front()
	if u.path.is_empty():
		finish_order(u)
		return
	var hull:bool=scenario.get("autonomy",false) and u.kind in ["tank","aa","boat"]
	# A jammed hull can creep a few centimetres while pivoting, which resets its
	# blocked time without making progress: no 1.5 u of headway in 2 s also stalls.
	var stalled:=false
	if hull:
		if time-float(u.get("stall_seen",-1.0))>0.5 or u.pos.distance_to(u.get("stall_pos",u.pos))>1.5:
			u["stall_pos"]=u.pos;u["stall_at"]=time
		u["stall_seen"]=time
		stalled=time-float(u.stall_at)>2.0
		# Jammed a hand's width from a waypoint (a grid centre a friend now
		# covers): steer for the next one instead of nosing into the friend.
		if (stalled or u.blocked_time>1.0) and u.path.size()>1 and u.pos.distance_to(u.path[0])<1.0:u.path.pop_front()
		# Jam clock: no 2 u of headway, kept across re-plans (which restart the
		# stall clock), so a friendly jam escalates instead of re-planning forever.
		if time-float(u.get("jam_seen",-1.0))>0.5 or u.pos.distance_to(u.get("jam_pos",u.pos))>2.0:
			u["jam_pos"]=u.pos;u["jam_at"]=time
		u["jam_seen"]=time
		var jam:float=time-float(u.jam_at)
		# In a fight the crew holds and fights; it sorts the jam out once the
		# threat passes, or after JAM_UNDER_FIRE regardless (never a permanent stall).
		if (u.blocked_time>1.5 or stalled) and jam>1.5 and (jam>JAM_UNDER_FIRE or not under_threat(u)):
			if crowded_arrival(u,order,jam):
				u.path.clear()
				finish_order(u)
				return
			if order.mode=="attack" and jam>JAM_GIVE_WAY and attack_respot(u,order):return
			if jam>JAM_GIVE_WAY and time>=float(u.get("give_way_at",0.0)):
				u["give_way_at"]=time+1.0
				if not make_way(u,true,jam>JAM_UNDER_FIRE) and jam>JAM_BACK_OFF:back_off(u)
	if (u.blocked_time>1.5 or stalled) and u.repath<=0 and take_route_budget(u.pos,order.pos,true):
		var avoid:Array=[]
		var keep_right:Array=[]
		var friend_ahead:=false
		for other in movement_neighbors(u):
			if other.id!=u.id and alive(other) and collision_layer(other)==collision_layer(u):
				# Detours avoid real bodies at their real size: soldiers, not squad
				# circles. Infantry anchors ignore other soldiers (they file through
				# individually) and keep one soldier-width from vehicles. Hulls keep
				# a margin (they cannot trace a tangent exactly).
				var autonomy:bool=scenario.get("autonomy",false)
				var own:float=1.0 if autonomy and not u.members.is_empty() else float(d.radius)+(0.4 if hull else 0.0)
				if autonomy and not other.members.is_empty():
					if u.members.is_empty():
						for member in other.members:
							if member.hp>0:avoid.append({"pos":member.pos,"radius":own+float(member.get("body_radius",0.8))+0.02})
				else:
					var clearance:float=own+float(definitions[other.kind].radius)+0.08
					avoid.append({"pos":other.pos,"radius":clearance})
					if hull and other.team==u.team and not other.orders.is_empty() and other.pos.distance_to(u.pos)<clearance+1.0 and (other.pos-u.pos).dot(u.path[0]-u.pos)>0.0:friend_ahead=true
					# Oncoming hulls each pass on their own right instead of
					# mirroring each other's swerve.
					# Final destinations, not next waypoints (which may already be swerves).
					var travel:Vector2=(u.path.back()-u.pos).normalized()
					if hull and not other.path.is_empty() and (other.path.back()-other.pos).normalized().dot(travel)<-0.5 and (other.pos-u.pos).dot(travel)>0.0:
						var left:Vector2=Vector2(travel.y,-travel.x)
						keep_right.append({"pos":other.pos+left*clearance*1.5,"radius":clearance*1.5})
		# Wrecks are solid for vehicles: a detour round a live body must not
		# squeeze past one (the wreck re-route ignores live bodies in turn).
		if u.members.is_empty() and d.domain=="land":
			var can_push:bool=VehicleDamage.pusher(self,u)
			for wreck in VehicleDamage.wrecks(self):
				if wreck.pos.distance_to(u.pos)<60.0 and VehicleDamage.solid_wreck(self,wreck,can_push):avoid.append({"pos":wreck.pos,"radius":float(d.radius)+float(wreck.radius)+(0.4 if hull else 0.0)})
		# A hull already inside a body's margin may still plan away from it.
		if hull:
			for body in avoid+keep_right:body.radius=minf(body.radius,u.pos.distance_to(body.pos)-0.05)
		var detour:Array[Vector2]=[]
		if not keep_right.is_empty():detour=terrain.path(u.pos,order.pos,d.domain,float(d.radius),avoid+keep_right,terrain.mobility_profile(u.kind))
		if detour.is_empty():detour=terrain.path(u.pos,order.pos,d.domain,float(d.radius),avoid,terrain.mobility_profile(u.kind))
		# Attack-move specifies an area. If a friendly holding that area occupies
		# its assigned formation slot, resolve a nearby clear arrival (<=6 units).
		# Explicit move/retreat and direct-attack target identity remain exact.
		if detour.is_empty() and order.mode=="attack_move" and u.blocked_time>3.0:
			var occupied:=false
			for other in movement_neighbors(u):
				if other.id!=u.id and alive(other) and other.team==u.team and other.orders.is_empty() and other.pos.distance_to(order.pos)<crowd_radius(u.kind)+crowd_radius(other.kind)+0.1:occupied=true
			if occupied:
				for ring in [2.0,4.0,6.0]:
					for index in 16:
						var arrival:Vector2=order.pos+Vector2.from_angle(index*TAU/16)*ring
						if not terrain.traversable(arrival,d.domain,float(d.radius)) or not terrain.avoids_bodies(arrival,arrival,avoid):continue
						detour=terrain.path(u.pos,arrival,d.domain,float(d.radius),avoid,terrain.mobility_profile(u.kind))
						if not detour.is_empty():break
					if not detour.is_empty():break
		# Nose to nose with a moving friend, a hull waits for right of way
		# rather than driving round the block (the friend is gone by then).
		if friend_ahead and not detour.is_empty() and _route_length(u.pos,detour)>_route_length(u.pos,u.path)*1.5+12.0:detour=[]
		if not detour.is_empty():u.path=detour
		else:make_way(u)
		u.repath=3.0
		if hull:u["stall_pos"]=u.pos;u["stall_at"]=time
	var speed := float(d.speed)
	if d.domain == "land":
		speed *= terrain.ground_speed(u.pos,terrain.mobility_profile(u.kind))
	if u.suppression > 0.6:
		speed *= 0.6
	if order.mode=="retreat":speed*=1.2
	if scenario.get("autonomy",false) and u.kind in ["tank","aa","boat"]:
		# A hull cannot stop on a point: it orbits a waypoint it misses by a hand's
		# width. Count one reached once close or passed (next leg clear), and look
		# ahead past it when the following one is in plain view. Detour waypoints
		# exist to clear bodies, so a skip must clear nearby bodies too.
		var axis:Vector2=-u.facing if u.get("reversing",false) else u.facing
		var look:bool=time>=float(u.get("look_ahead_at",0.0))
		var bodies:Array=[]
		var gathered:=false
		while u.path.size()>1:
			var gap:float=u.pos.distance_to(u.path[0])
			var passed:bool=gap<1.0 or (gap<4.0 and (u.path[0]-u.pos).dot(axis)<=0.0)
			if not passed and (not look or gap>6.0):break
			if not gathered:
				gathered=true
				for other in movement_neighbors(u):
					if other.id==u.id or not alive(other) or collision_layer(other)!=collision_layer(u):continue
					if other.members.is_empty():bodies.append({"pos":other.pos,"radius":float(d.radius)+float(definitions[other.kind].radius)+0.4})
					else:
						for member in other.members:
							if member.hp>0:bodies.append({"pos":member.pos,"radius":float(d.radius)+float(member.get("body_radius",0.8))+0.3})
			var room:float=float(d.radius)+(0.0 if passed else 0.3)
			if not passed:
				u["look_ahead_at"]=time+0.2
				look=false
			if not terrain.segment_clear(u.pos,u.path[1],d.domain,room) or not terrain.avoids_bodies(u.pos,u.path[1],bodies):break
			u.path.pop_front()
		if u.path.size()==1 and u.pos.distance_to(u.path[0])<0.75 and (u.path[0]-u.pos).dot(axis)<=0.0:
			u.path.clear()
			finish_order(u)
			return
		var heading:Vector2=(u.path[0]-u.pos).normalized()
		u.reversing=(order.mode=="retreat" or order.get("give_way",false)) and u.facing.dot(heading)<-0.35
		var desired_heading:Vector2=-heading if u.reversing else heading
		# A blocked hull steers toward its chosen clear heading for a moment.
		if time<float(u.get("avoid_until",0.0)):desired_heading=u.avoid_heading
		u.facing=Vector2.from_angle(rotate_toward(u.facing.angle(),desired_heading.angle(),dt*1.5))
		var alignment:=maxf(0.0,u.facing.dot(desired_heading))
		speed*=alignment*alignment*(0.55 if u.reversing else 1.0)
		if u.path.size()==1:speed=minf(speed,sqrt(2.0*5.0*u.pos.distance_to(u.path[0])))
		u.speed_now=move_toward(u.speed_now,speed,dt*(3.0 if speed>u.speed_now else 7.0))
		speed=u.speed_now
	else:u.speed_now=speed
	var neighbors:=movement_neighbors(u)
	var old_bucket:=bucket(u)
	var remaining := speed * dt
	# A section veers its formation slightly around other groups ahead (soft
	# cost), so soldiers pass with a gap rather than squeezing through.
	var crowd:Array=[]
	if not u.members.is_empty() and scenario.get("autonomy",false) and not u.path.is_empty():
		var ahead:Vector2=u.pos+(u.path[0]-u.pos).limit_length(6.0)
		for entry in actor_candidates(u.pos,ahead,2.5):
			if entry.unit.id!=u.id and alive(entry.unit) and entry.actor.hp>0 and entry.actor.pos.distance_to(u.pos)<8.0:crowd.append(entry.actor.pos)
	while remaining > 0 and not u.path.is_empty():
		var next: Vector2 = u.path[0]
		var distance: float = u.pos.distance_to(next)
		if distance<0.1:
			u.path.pop_front()
			continue
		var desired: Vector2=(next-u.pos).normalized()
		var step:=minf(remaining,distance)
		if scenario.get("autonomy",false) and u.kind in ["tank","aa","boat"]:
			# Hulls never slide sideways: they move only along their axis and turn
			# (or pivot in place) to change course; when jammed they back out.
			if not hull_step(u,next,distance,step,dt,neighbors):break
			remaining-=step
			if u.pos.distance_to(next)<0.1:u.path.pop_front()
			continue
		var best: Vector2=u.pos
		var best_score:=-INF
		for angle in [0.0,0.55,-0.55,1.05,-1.05,1.5,-1.5]:
			var candidate: Vector2=u.pos+desired.rotated(angle)*step
			# Rank first: a direction that cannot beat the already-clear best
			# cannot change steering. Avoid its expensive actor/terrain checks.
			var score: float=(distance-candidate.distance_to(next))-absf(angle)*0.02
			score-=0.035*(1.0-u.facing.dot((candidate-u.pos).normalized()))
			if not crowd.is_empty():
				# Penalise heading at bodies within ~2.6 m of the line ahead.
				var probe:Vector2=desired.rotated(angle)
				for body in crowd:
					var relative:Vector2=body-u.pos
					var along:float=relative.dot(probe)
					# Only bodies between us and the next waypoint matter.
					if along<=0.0 or along>minf(6.0,distance+1.0):continue
					var lateral:float=absf(relative.dot(Vector2(-probe.y,probe.x)))
					if lateral<2.6:score-=step*0.5*(1.0-lateral/2.6)*(1.0-along/6.0)
			if score>best_score and movement_clear(u,candidate,neighbors):
				best_score=score
				best=candidate
		# The crowd cost only steers; it never turns real progress into a stop.
		if best==u.pos or distance-best.distance_to(next)<=0.00001:
			if u.members.is_empty() and VehicleDamage.push_wreck(self,u,u.pos+desired*step,desired,dt,VehicleDamage.PUSH_REACH)!=VehicleDamage.PUSH_NONE:break
			u.blocked_time+=dt
			u.state="YIELDING"
			u.speed_now=0.0
			break
		if not (scenario.get("autonomy",false) and u.kind in ["tank","aa","boat"]):u.facing=(best-u.pos).normalized()
		var previous_position:Vector2=u.pos
		u.pos=best
		if u.members.is_empty():relocate_actor(u,u,previous_position)
		u.blocked_time=0.0
		remaining-=step
		if u.pos.distance_to(next)<0.1:
			u.path.pop_front()

	var new_bucket:=bucket(u)
	if new_bucket!=old_bucket:
		spatial[old_bucket].erase(u)
		if not spatial.has(new_bucket): spatial[new_bucket]=[]
		spatial[new_bucket].append(u)
	# A hull shoving a wreck this tick keeps its PUSHING WRECK state.
	if u.blocked_time<=0 and float(u.get("push_seen",-1.0))<time:
		u.state = "RETREATING" if order.mode=="retreat" else ("ADVANCING" if order.mode == "attack_move" else "MOVING")
	if u.path.is_empty():
		finish_order(u)

# One movement step for a tracked/wheeled hull or boat. Returns false when the
# hull could not advance this tick (it may still pivot or reverse).
func hull_step(u:Dictionary,next:Vector2,distance:float,step:float,dt:float,neighbors:Array)->bool:
	var axis:Vector2=-u.facing if u.reversing else u.facing
	var candidate:Vector2=u.pos+axis*step
	# Tracks flatten street furniture in the hull's way (lamps, benches, cars...).
	if definitions[u.kind].domain=="land" and terrain.mobility_profile(u.kind)=="tracked":
		for record in terrain.crush_props(candidate,float(definitions[u.kind].radius)+0.1):
			events.append({"type":"crushed","prop":record.prop,"id":record.id,"heading":axis,"pos":record.rect.get_center(),"visible":true})
		# ...and push over collision trees whose canopy the hull would hit.
		for record in terrain.fell_trees(candidate,float(definitions[u.kind].radius)+terrain.TREE_CLEARANCE+0.05,axis):
			events.append({"type":"crushed","prop":-1,"id":"tree","tree":record.index,"heading":axis,"pos":record.pos,"visible":true})
	# A tank nosing into a light wreck shoves it aside at a crawl and follows it
	# (held, not jammed, while it takes up the slack or the wreck closes it in).
	var ahead:Vector2=candidate
	var shove:int=VehicleDamage.push_wreck(self,u,ahead,axis,dt) if has_meta(VehicleDamage.WRECKS) else VehicleDamage.PUSH_NONE
	if shove==VehicleDamage.PUSH_HOLD:return false
	if shove==VehicleDamage.PUSH_SHOVE:candidate=u.pos+axis*minf(step,VehicleDamage.PUSH_SPEED*dt)
	# Never drive away from the waypoint while turning toward it.
	if movement_clear(u,candidate,neighbors) and distance-candidate.distance_to(next)>-step*0.3:
		var previous:Vector2=u.pos
		u.pos=candidate
		relocate_actor(u,u,previous)
		u.blocked_time=0.0
		return true
	if shove==VehicleDamage.PUSH_NONE and has_meta(VehicleDamage.WRECKS):shove=VehicleDamage.push_wreck(self,u,ahead,axis,dt,VehicleDamage.PUSH_REACH)
	if shove!=VehicleDamage.PUSH_NONE:return false
	u.blocked_time+=dt
	u.state="YIELDING"
	u.speed_now=0.0
	# Pick a clear heading near the route and turn toward it (pivot steer).
	if time>=float(u.get("avoid_until",0.0)):
		var desired:Vector2=(next-u.pos).normalized()
		var reach:float=maxf(step,float(definitions[u.kind].radius)*0.6)
		for angle in [0.55,-0.55,1.05,-1.05,1.5,-1.5,2.2,-2.2]:
			var direction:Vector2=desired.rotated(angle)
			if movement_clear(u,u.pos+direction*reach,neighbors):
				u["avoid_heading"]=direction
				u["avoid_until"]=time+0.9
				break
	# Jammed nose-first for a while: back out along the hull axis.
	if u.blocked_time>1.0:
		var back:Vector2=u.pos-u.facing*minf(step,0.08)
		if movement_clear(u,back,neighbors):
			var previous:Vector2=u.pos
			u.pos=back
			relocate_actor(u,u,previous)
	return false

func finish_order(u: Dictionary) -> void:
	if not u.maneuver.is_empty():
		u.maneuver.arrived=true
		u.speed_now=0.0
		u.path.clear()
		return
	u.orders.pop_front()
	u.reason="Objective reached · holding"
	u.path.clear()
	start_next_order(u)

# The next order takes over: its route now or queued (its target still
# resolving: the unit holds until resolve_slots() queues the route).
func start_next_order(u:Dictionary)->void:
	if u.orders.is_empty() or u.has(SectionRecovery.KEY):return
	u.intent=u.orders[0].duplicate()
	if u.orders[0].has("slot"):return
	if take_route_budget(u.pos,u.orders[0].pos):u.path=order_route(u,u.orders[0].pos)
	else:defer_route(u,"order")

func update_objectives(dt: float) -> void:
	for obj in objectives:
		var friendly := false
		var enemy := false
		for u in units:
			if not alive(u) or u.get("combat_ineffective",false) or definitions[u.kind].get("structure",false) or definitions[u.kind].domain != "land" or u.maneuver.get("phase","")=="WITHDRAW":
				continue
			if u.pos.distance_to(obj.pos) < float(scenario.get("capture_radius",7.0)):
				if u.team == 0 and u.suppression<=0.6 and (u.orders.is_empty() or u.orders[0].mode!="retreat"):
					friendly = true
				elif u.team==1:
					enemy = true
		obj["contested"] = friendly and enemy
		obj["enemy_present"] = enemy
		if friendly and not enemy:
			obj.progress = minf(capture_time, obj.progress+dt)
		elif enemy:
			obj.progress = maxf(0, obj.progress-dt*0.6)
		if obj.progress >= capture_time and obj.owner != 0:
			obj.owner = 0
			credits += (100 if field_ops.is_empty() else 0)
			events.append({"type":"warning","text":obj.name+(" secured • +100 supply" if field_ops.is_empty() else " secured"),"notice":"info"})
		elif obj.progress <= 0:
			obj.owner = 1
	if not objectives.is_empty() and objectives.all(func(obj):return obj.owner==0 and not obj.get("enemy_present",false)):
		score_hold += dt
		if score_hold >= float(scenario.hold):
			var reserve_resolved:bool=counterattack_sent and time>counterattack_at+20
			# Destroyed field logistics prevent an unsent reserve from ever forming.
			# An already-dispatched reserve still keeps its normal grace period.
			if not field_ops.is_empty() and not counterattack_sent:
				reserve_resolved=not FieldOps.enemy_logistics_alive(self)
			if result=="" and (not scenario.get("autonomy",false) or reserve_resolved):
				result = "VICTORY"
	else:
		score_hold = 0

# A section whose survivors are all down (Infantry.publish) is no mobile unit:
# it takes no orders (issue), drops any it had, and its anchor stays with its
# men: the centroid of the living, who crawl toward their slots round it.
const DOWNED_NOTE:="Section down · wounded cannot move"
func hold_downed(u:Dictionary)->void:
	if not u.orders.is_empty() or not u.maneuver.is_empty() or not u.path.is_empty():
		# Orders go; the intent stays as the record of its last command.
		u.orders.clear();u.path.clear();u.maneuver={}
		u.erase("route_pending")
		u.blocked_time=0.0
		u.reason=DOWNED_NOTE
	if Garrison.inside(u) or Garrison.transit(u)!="":return
	var sum:=Vector2.ZERO
	var count:=0
	for member in u.members:
		if member.get("wound","")!=Infantry.KIA:sum+=member.pos;count+=1
	if count>0:u.pos=sum/count

func collision_layer(u: Dictionary) -> String:
	# Non-solid field works (wire, trenches, nets) apply terrain zones, not bodies.
	if not definitions[u.kind].get("solid",true):return "field_zone"
	# A section whose survivors are all down lies on the ground: others step
	# past it (as they pass its downed soldiers individually under autonomy).
	if u.get("combat_ineffective",false):return "downed"
	return str(u.kind) if definitions[u.kind].domain=="air" else str(definitions[u.kind].domain)

# Footprint used against OTHER units. A squad's definition radius (2.65) is a
# conservative terrain envelope; its soldiers stand ~1.7 apart, so in a crowd the
# section occupies only its formation (≈2.0) and each soldier only his body.
const SECTION_CROWD_RADIUS:=2.0
func crowd_radius(kind:String) -> float:
	var d:Dictionary=definitions[kind]
	if scenario.get("autonomy",false) and kind in ["rifle","atgm","engineer"]:return minf(float(d.radius),SECTION_CROWD_RADIUS)
	return float(d.radius)

func location_clear(pos: Vector2, kind: String, ignore_id: int = -1) -> bool:
	var d: Dictionary=definitions[kind]
	if not terrain.traversable(pos,d.domain,float(d.radius)): return false
	var layer: String=kind if d.domain=="air" else d.domain
	for other in units:
		if not alive(other) or other.id==ignore_id or collision_layer(other)!=layer: continue
		var clearance: float=crowd_radius(kind)+crowd_radius(other.kind)+0.12
		if pos.distance_squared_to(other.pos)<clearance*clearance: return false
	return true

func spawn_position(origin: Vector2, kind: String) -> Vector2:
	if location_clear(origin,kind): return origin
	var d:Dictionary=definitions[kind]
	var valid_origin:bool=terrain.traversable(origin,d.domain,float(d.radius))
	for ring in range(1,25):
		for i in 24:
			var pos:=origin+Vector2.from_angle(i*TAU/24.0)*ring
			if not location_clear(pos,kind):continue
			# Crowding may displace a spawn, but must not teleport it across a
			# wall out of the origin's reachable region.
			if valid_origin and terrain.path(origin,pos,d.domain,float(d.radius),[],terrain.mobility_profile(kind)).is_empty():continue
			return pos
	return Vector2(-1,-1)

# `open` memoises candidate checks for one command (unchanged terrain, slots
# only added): units sent to the same spot rescan the same rings, skipping
# candidates already found taken by a slot or blocked by terrain.
# `held` spots (held_spots: friends outside this command) are kept clear too.
# A section sent to a spot a friend holds comes up beside it, as sections come
# on line: a little forward of abreast of its approach first (SECTION_RING, in
# 1/16 turns from straight ahead), then further forward, then back. Standing
# clear already, no more than SECTION_STAY farther out than the nearest free
# ring, it stays where it is: a re-sent order never shuffles sections round.
# Otherwise (a group's own slots, terrain) the rings run as for vehicles.
const SECTION_RING:=[3,-3,4,-4,2,-2,5,-5,1,-1,6,-6,0,7,-7,8]
const SECTION_STAY:=2.0
func formation_slot(origin: Vector2, u: Dictionary, slots: Array[Dictionary], open:Dictionary={}, held:Array[Dictionary]=[]) -> Vector2:
	var d: Dictionary=definitions[u.kind]
	var domain:String=d.domain
	var radius:=float(d.radius)
	var layer:=collision_layer(u)
	var crowd:=crowd_radius(u.kind)
	# A vehicle cannot stop in a wreck's margin: a spot on or beside a wreck
	# becomes the clear spot beside it on the near side, and the rings below
	# skip wreck margins too, so a group spreads its slots round the wreck.
	# Only wrecks the rings can reach are checked (none: terrain-only memo).
	var nearby:Array=[]
	if has_meta(VehicleDamage.WRECKS) and VehicleDamage.wreck_bound(self,u):
		var beside:=VehicleDamage.clear_goal(self,u,origin,u.pos)
		if beside.x>=0:origin=beside
		nearby=VehicleDamage.wrecks_near(self,origin,radius,18.0)
	var wrecked:=not nearby.is_empty()
	var known:Dictionary=open.get_or_add("terrain:%s:%s:%s" % [domain,radius,wrecked],{})
	var taken:Dictionary=open.get_or_add("slots:%s:%s" % [layer,crowd],{})
	var profile:String=terrain.mobility_profile(u.kind)
	# Probing from open ground, reachable() runs the straight-line check first.
	var probe:=terrain.path_probe and terrain.traversable(u.pos,domain,radius)
	var section:bool=not held.is_empty() and not u.members.is_empty() and not slot_clear(origin,layer,crowd,held)
	if not held.is_empty():slots=slots+held
	var ahead:float=(origin-u.pos).angle() if section and u.pos.distance_squared_to(origin)>0.0001 else 0.0
	var stay:=INF
	for ring in 18:
		if ring==1 and section and slot_clear(u.pos,layer,crowd,slots) and terrain.traversable(u.pos,domain,radius):stay=u.pos.distance_to(origin)-SECTION_STAY
		if stay<=ring:return u.pos
		for i in (1 if ring==0 else 16):
			var p:=origin+Vector2.from_angle(ahead+int(SECTION_RING[i])*TAU/16.0 if section else i*TAU/16.0)*ring
			if taken.has(p):continue
			if not slot_clear(p,layer,crowd,slots):
				taken[p]=true
				continue
			var free=known.get(p)
			if free==null:
				free=terrain.traversable(p,domain,radius) and not (wrecked and not VehicleDamage.wreck_at(self,p,radius,nearby).is_empty())
				known[p]=free
			if not free: continue
			if probe:
				if terrain.reachable(u.pos,p,domain,radius,profile): return p
			elif terrain.segment_clear(u.pos,p,domain,radius) or not terrain.path(u.pos,p,domain,radius,[],profile).is_empty(): return p
	return Vector2(-1,-1)

# Sections never stand stacked for long. Arrival spots keep orders apart, but
# two sections can still end up together (orders ending at once on one route,
# give-way spots): an idle one whose anchor stays within STACKED of another
# idle friendly section's for STACK_WAIT steps to the nearest clear spot (via
# issue: formation_slot round the held spots). Not while firing, nor while
# holding, garrisoning or regrouping; under threat only after STACK_WAIT_THREAT.
const STACKED:=3.0
const STACK_WAIT:=4.0
const STACK_WAIT_THREAT:=15.0
const STACK_CHECK:=1.0
var stack_check_at:=0.0
func unstack_sections()->void:
	if time<stack_check_at:return
	stack_check_at=time+STACK_CHECK
	var idle:Array=[]
	for u in units:
		if u.has(SectionRecovery.KEY):continue
		if u.members.is_empty() or not alive(u) or not u.orders.is_empty() or not u.maneuver.is_empty() or u.hold_command:continue
		if u.get("combat_ineffective",false) or u.get("regroup_active",false) or u.has("garrison_target") or Garrison.inside(u) or Garrison.transit(u)!="" or definitions[u.kind].domain!="land":continue
		idle.append(u)
	for u in idle:
		var below:Dictionary={}
		for other in idle:
			# (One stepping aside earlier in this pass is no longer there.)
			if other.id<u.id and other.team==u.team and other.orders.is_empty() and other.pos.distance_squared_to(u.pos)<STACKED*STACKED:
				below=other
				break
		if below.is_empty():
			u.erase("stacked_since")
			continue
		var since:float=u.get_or_add("stacked_since",time)
		if engaged(u) or time-since<(STACK_WAIT_THREAT if under_threat(u) else STACK_WAIT):continue
		u.erase("stacked_since")
		# Ordered a hand's width away from the other, it steps out that side.
		var away:Vector2=u.pos-below.pos
		away=away.normalized() if away.length_squared()>0.0001 else Vector2.from_angle(u.id)
		if issue([u.id],u.pos+away*0.25,"move")>0:u.reason="Spreading out"

func slot_clear(p:Vector2,layer:String,crowd:float,slots:Array[Dictionary])->bool:
	for slot in slots:
		if slot.layer==layer and p.distance_to(slot.pos)<crowd+float(slot.radius)+0.3:return false
	return true

# Spots near `around` that friendly sections hold or are heading for (their
# last order, unless an attack) and that parked friendly vehicles and
# structures stand on, as formation_slot entries, so a section sent there
# arrives beside them rather than on the same anchor. Units of this command
# re-plan (their spots arrive as command slots); sections bound for or inside
# a building pass through its door rather than hold it.
const HELD_REACH:=30.0
func held_spots(u:Dictionary,around:Vector2,ids:Array)->Array[Dictionary]:
	var layer:=collision_layer(u)
	var spots:Array[Dictionary]=[]
	for other in units:
		if other.team!=u.team or not alive(other) or collision_layer(other)!=layer:continue
		if ids.has(other.id) or ids.has(float(other.id)):continue
		var spot:Vector2=other.pos
		if other.members.is_empty():
			if not other.orders.is_empty() or not other.maneuver.is_empty():continue
		else:
			if other.has("garrison_target") or Garrison.inside(other) or Garrison.transit(other)!="":continue
			if not other.orders.is_empty():
				if other.orders[-1].mode=="attack":continue
				spot=other.orders[-1].pos
		if spot.distance_squared_to(around)>HELD_REACH*HELD_REACH:continue
		spots.append({"pos":spot,"radius":crowd_radius(other.kind),"layer":layer})
	return spots

func movement_clear(u: Dictionary, to: Vector2, neighbors: Array, pressed_wrecks:Array = []) -> bool:
	var d: Dictionary=definitions[u.kind]
	# Vehicles cannot enter anti-tank obstacles (they may always back out).
	if d.domain=="land" and terrain.mobility_profile(u.kind) in terrain.VEHICLE_PROFILES:
		if terrain.vehicle_barrier(to,float(d.radius)*0.6) and not terrain.vehicle_barrier(u.pos,float(d.radius)*0.6):return false
	if u.members.is_empty() and has_meta(VehicleDamage.WRECKS) and VehicleDamage.wreck_blocks(self,u,to):return false
	for member in u.members:
		if member.hp>0 and member.pos.distance_to(to)>(Infantry.Cover.LEASH if scenario.get("autonomy",false) else 1.75):return false
	if scenario.get("autonomy",false) and d.domain=="land":
		var extent:float=float(d.radius)+Infantry.Cover.LEASH+1.3
		var min_x:=minf(u.pos.x,to.x);var max_x:=maxf(u.pos.x,to.x)
		var min_y:=minf(u.pos.y,to.y);var max_y:=maxf(u.pos.y,to.y)
		var step:Vector2=to-u.pos
		var length_squared:=maxf(0.00001,step.length_squared())
		for entry in actor_candidates(u.pos,to,float(d.radius)):
			var other:Dictionary=entry.unit
			if other.id==u.id or not alive(other) or other.members.is_empty():continue
			# An infantry section's anchor is abstract: its soldiers resolve contact
			# with other sections' soldiers individually (squeeze and sidestep).
			if not u.members.is_empty():continue
			# Match the existing conservative squad broad phase, then test only
			# bodies overlapping the moving footprint's swept area.
			if other.pos.x<min_x-extent or other.pos.x>max_x+extent or other.pos.y<min_y-extent or other.pos.y>max_y+extent:continue
			var member:Dictionary=entry.actor
			if member.hp<=0:continue
			# A section anchor is one soldier-width wide against other soldiers;
			# individuals file between bodies instead of the whole formation circle.
			var clearance:=(1.0 if not u.members.is_empty() else float(d.radius))+float(member.get("body_radius",0.8))
			if member.pos.x<min_x-clearance or member.pos.x>max_x+clearance or member.pos.y<min_y-clearance or member.pos.y>max_y+clearance:continue
			# Never refuse a move that opens distance: overlapping bodies separate.
			if to.distance_squared_to(member.pos)>=u.pos.distance_squared_to(member.pos):continue
			var near:Vector2=u.pos+step*clampf((member.pos-u.pos).dot(step)/length_squared,0,1)
			if near.distance_to(member.pos)<clearance:return false
	if not terrain.segment_clear(u.pos,to,d.domain,float(d.radius),pressed_wrecks): return false
	for other in neighbors:
		if not alive(other) or other.id==u.id or collision_layer(other)!=collision_layer(u): continue
		# Two infantry sections never block each other as whole circles; their
		# soldiers' bodies are checked individually above and in Infantry.move.
		# Likewise a vehicle is checked against the soldiers themselves (actor loop
		# above), and an anchor passing a vehicle is one soldier wide.
		var squad_self:bool=not u.members.is_empty() and scenario.get("autonomy",false)
		var squad_other:bool=not other.members.is_empty() and scenario.get("autonomy",false)
		if squad_other:continue
		collision_checks+=1
		if scenario.get("autonomy",false) and to.distance_squared_to(other.pos)>=u.pos.distance_squared_to(other.pos):continue
		var clearance: float=(1.0 if squad_self else float(d.radius))+float(definitions[other.kind].radius)+0.08
		var segment: Vector2=to-u.pos
		var t:=clampf((other.pos-u.pos).dot(segment)/maxf(0.00001,segment.length_squared()),0,1)
		var nearest: Vector2=u.pos+segment*t
		if nearest.distance_squared_to(other.pos)<clearance*clearance: return false
	return true

func bucket(u:Dictionary) -> Vector3i:
	var layer:=0
	match definitions[u.kind].domain:
		"sea": layer=1
		"air": layer=2 if u.kind=="drone" else 3
	return Vector3i(floori(u.pos.x/8.0),floori(u.pos.y/8.0),layer)

func rebuild_spatial() -> void:
	spatial.clear()
	spatial_serial+=1
	for layer in spatial_layers:layer.clear()
	for u in units:
		if not alive(u):continue
		var key:=bucket(u)
		if not spatial.has(key):spatial[key]=[]
		spatial[key].append(u)
		spatial_layers[key.z].append(u)

func target_candidates(u:Dictionary) -> Array:
	# Direct fixture/tool calls may mutate positions outside a tick. Preserve
	# their authoritative behavior; live simulation maintains the spatial index.
	if not spatial_targeting():return units
	var d:Dictionary=definitions[u.kind]
	if float(d.damage)<=0 and u.members.is_empty():return []
	var reach:float=float(d.range)*(Garrison.RANGE_SCALE if Garrison.inside(u) else 1.0)
	var offset:=section_offset(u)
	# Per-soldier fire reaches a target section through its soldiers, not its
	# anchor. Buckets cover sections whose soldiers stand within SPREAD_NARROW of
	# their anchor; the few wider ones (cover runs, window posts) are listed per
	# tick with their spread. A section refreshes its entry when it queries,
	# right after moving; SPREAD_SLACK covers the anchor nudge after that query
	# (casualty carry). Extra candidates are harmless: the exhaustive path
	# considers every unit, so only missing ones would change outcomes.
	refresh_wide_sections()
	if wide_ids.has(u.id):wide_sections[wide_ids[u.id]][1]=maxf(wide_sections[wide_ids[u.id]][1],offset+SPREAD_SLACK)
	elif offset>SPREAD_NARROW:wide_ids[u.id]=wide_sections.size();wide_sections.append([u,offset+SPREAD_SLACK])
	var base:float=reach+offset
	var outer:float=base+SPREAD_NARROW+SPREAD_SLACK
	var base_sq:=base*base
	var outer_sq:=outer*outer
	var origin:Vector2=u.pos
	var result:Array=[]
	var last_id:=-1
	var ordered:=true
	# Sections are infantry: only the land layer (0) needs the wider scan.
	# Indexed entries are never empty, so `alive` reduces to the hp test.
	for layer in 4:
		var scan:float=outer if layer==0 else base
		for other in layer_candidates(origin,scan,layer):
			if other.hp<=0.0:continue
			var gap:float=origin.distance_squared_to(other.pos)
			if gap<=base_sq or (gap<=outer_sq and not other.members.is_empty() and sqrt(gap)<=base+section_offset(other)):
				result.append(other)
				if other.id<last_id:ordered=false
				last_id=other.id
	# Wide sections beyond the scan; inside it the buckets already decided.
	for entry in wide_sections:
		var other:Dictionary=entry[0]
		var gap:float=origin.distance_squared_to(other.pos)
		var bound:float=base+float(entry[1])
		if gap>outer_sq and gap<=bound*bound and alive(other):
			result.append(other)
			if other.id<last_id:ordered=false
			last_id=other.id
	# Usually already in id order (whole layer lists, one layer in reach).
	if not ordered:result.sort_custom(func(a,b):return a.id<b.id)
	return result

func spatial_targeting()->bool:
	return ticking and use_spatial_targeting and units.size()>=spatial_targeting_threshold

# Wide sections of this tick, listed by its first spatial candidate query.
func refresh_wide_sections()->void:
	if spread_serial==spatial_serial:return
	spread_serial=spatial_serial;wide_sections.clear();wide_ids.clear()
	for other in units:
		if alive(other):
			var spread:float=section_offset(other)
			if spread>SPREAD_NARROW:wide_ids[other.id]=wide_sections.size();wide_sections.append([other,spread+SPREAD_SLACK])

# Farthest living soldier from the section anchor (0 for single bodies).
func section_offset(u:Dictionary) -> float:
	var offset:=0.0
	for member in u.members:
		if member.hp>0:offset=maxf(offset,member.pos.distance_squared_to(u.pos))
	return sqrt(offset)

func range_candidates(origin:Vector2,radius:float) -> Array:
	var result:Array=[]
	var radius_sq:=radius*radius
	var last_id:=-1
	var ordered:=true
	for layer in 4:
		for other in layer_candidates(origin,radius,layer):
			if alive(other) and origin.distance_squared_to(other.pos)<=radius_sq:
				result.append(other)
				if other.id<last_id:ordered=false
				last_id=other.id
	# Preserve insertion-order ties and seeded combat outcomes across the optimization.
	if not ordered:result.sort_custom(func(a,b):return a.id<b.id)
	return result

# Units of one bucket layer whose cells overlap the square around `origin`
# (callers filter by distance and life): the cells, or the whole layer list
# when it holds fewer units than the square has cells.
func layer_candidates(origin:Vector2,radius:float,layer:int) -> Array:
	var x0:=floori((origin.x-radius)/8);var x1:=floori((origin.x+radius)/8)
	var y0:=floori((origin.y-radius)/8);var y1:=floori((origin.y+radius)/8)
	var listed:Array=spatial_layers[layer]
	if listed.size()<=(x1-x0+1)*(y1-y0+1):return listed
	var result:Array=[]
	for x in range(x0,x1+1):
		for y in range(y0,y1+1):result.append_array(spatial.get(Vector3i(x,y,layer),NO_UNITS))
	return result

func movement_neighbors(u:Dictionary) -> Array:
	var key:=bucket(u)
	var result:Array=[]
	for x in range(key.x-1,key.x+2):
		for y in range(key.y-1,key.y+2):
			var nearby:=Vector3i(x,y,key.z)
			if spatial.has(nearby):result.append_array(spatial[nearby])
	return result

# Parked bodies (no orders or maneuver) near a vehicle's new leg, as path
# exclusions: hulls plan round standing vehicles and soldiers up front instead
# of discovering them nose-first. Movers, and bodies off the direct corridor,
# are resolved on contact. Bodies on the start or goal never exclude them
# (formation/arrival logic owns that).
const STANDING_MARGIN:=0.4
const STANDING_CORRIDOR:=12.0
const STANDING_LIMIT:=40
func standing_bodies(u:Dictionary,from:Vector2,to:Vector2,ignore:Array=[])->Array:
	var d:Dictionary=definitions[u.kind]
	if not scenario.get("autonomy",false) or d.domain!="land" or not u.members.is_empty() or not d.get("solid",true):return []
	var own:float=float(d.radius)+STANDING_MARGIN
	var bounds:=Rect2(from,Vector2.ZERO).expand(to).grow(STANDING_CORRIDOR)
	var layer:=collision_layer(u)
	var result:Array=[]
	for other in units:
		if other.id==u.id or not alive(other) or not bounds.has_point(other.pos) or collision_layer(other)!=layer:continue
		if not other.orders.is_empty() or not other.maneuver.is_empty() or ignore.has(other.id) or ignore.has(float(other.id)):continue
		var bodies:Array=[]
		if other.members.is_empty():bodies.append([other.pos,float(definitions[other.kind].radius)+0.08])
		else:
			for member in other.members:
				if member.hp>0:bodies.append([member.pos,float(member.get("body_radius",0.8))+0.02])
		for body in bodies:
			var clearance:float=own+float(body[1])
			if from.distance_to(body[0])<clearance or to.distance_to(body[0])<clearance:continue
			var offset:float=Geometry2D.get_closest_point_to_segment(body[0],from,to).distance_to(body[0])
			if offset<STANDING_CORRIDOR:result.append({"pos":body[0],"radius":clearance,"offset":offset})
	if result.size()>STANDING_LIMIT:
		result.sort_custom(func(a,b):return a.offset<b.offset)
		result.resize(STANDING_LIMIT)
	return result

# A parked friend holding the only way through steps aside (RA2-style), so an
# idle unit never shuts a lane. It moves to the nearest clear spot off the
# blocked unit's next legs, then idles there; held, garrisoned and building
# units stay put. Bounded: at most six short path queries per friend.
# With `movers` (a hull jammed among friendly vehicles), moving friendly
# vehicles of lower priority (higher id: deterministic right of way) give way
# too: they back or turn off to such a spot, then resume their own orders.
# A mover in a fight is not asked (one under threat but not firing, or only
# shelling a building, is, by an `insistent` hull jammed past JAM_UNDER_FIRE).
# A hull ahead shelling a building is asked to press on to its firing spot
# (pressing_on), or from its spot to shift to one off the asker's route. An
# immobilised hull is never asked. A vehicle a hand's width from the end of
# its only order has all but arrived: a section asks it like a parked one.
# Where no spot is near, a parked friend pulls on past the end of the asker's
# next legs. A failed search is retried after GIVE_WAY_RETRY (the asker moves,
# friends clear). Returns true when a friend was asked to give way.
const JAM_GIVE_WAY:=2.5
const JAM_BACK_OFF:=4.0
const JAM_UNDER_FIRE:=12.0
const GIVE_WAY_RETRY:=2.0
func make_way(u:Dictionary,movers:bool=false,insistent:bool=false)->bool:
	if u.path.is_empty() or not scenario.get("autonomy",false):return false
	var legs:Array=[u.pos]+u.path.slice(0,2)
	var route_legs:Array=[u.pos]+u.path.slice(0,4)
	var asked:=false
	for other in movement_neighbors(u):
		if other.id==u.id or not alive(other) or other.team!=u.team or collision_layer(other)!=collision_layer(u):continue
		var od:Dictionary=definitions[other.kind]
		# An immobilised hull cannot pull over: the asker routes round it instead.
		if not other.maneuver.is_empty() or other.hold_command or od.get("structure",false) or other.has("building_id") or other.get("mobility_kill",false):continue
		# A hull stopped to shell a building short of its own firing spot,
		# ahead in the way, presses on to that spot (firing as it goes): a
		# column does not stall behind the first hulls in range in a gap.
		# One shelling from its spot in the way shifts to the nearest free
		# firing spot off the asker's route (at most once per SHIFT_EVERY).
		if movers and u.members.is_empty() and _shelling(other) and (other.pos-u.pos).dot(u.path[0]-u.pos)>0.0 and _near_legs(other.pos,legs,crowd_radius(u.kind)+crowd_radius(other.kind)+0.5):
			if _shelling_short(other):
				if time>=float(other.get("press_on_until",0.0)):other["press_on_until"]=time+PRESS_ON
			elif time>=float(other.get("shift_at",0.0)):
				other["shift_at"]=time+SHIFT_EVERY
				_shift_firing_spot(other,u,legs)
			asked=true
			continue
		if time<float(other.get("yield_until",0.0)) or time<float(other.get("give_way_retry",0.0)):continue
		var arriving:bool=not u.members.is_empty() and other.members.is_empty() and other.orders.size()==1 and other.orders[0].mode in ["move","attack_move"] and not other.orders[0].get("give_way",false) and not other.path.is_empty() and other.pos.distance_to(other.path.back())<=1.0 and not engaged(other)
		var parked:bool=other.orders.is_empty() or arriving
		if not parked:
			if not movers or other.id<u.id or not u.members.is_empty() or not other.members.is_empty() or other.orders[0].get("give_way",false) or (engaged(other) and not (insistent and shelling(other))) or (not insistent and under_threat(other)):continue
			# Only a mover ahead holds the way (one behind is just following).
			if (other.pos-u.pos).dot(u.path[0]-u.pos)<=0.0:continue
		var clearance:float=crowd_radius(u.kind)+crowd_radius(other.kind)+0.5
		if not _near_legs(other.pos,legs,clearance):continue
		# Never step aside through the unit being let past.
		var keep_off:Array=[{"pos":u.pos,"radius":minf(clearance,other.pos.distance_to(u.pos)-0.05)}]
		var found:Array=_give_way_spot(other,legs,keep_off,clearance,false,parked,route_legs)
		if found.is_empty():
			other["give_way_retry"]=time+GIVE_WAY_RETRY
			if movers:continue
			return false
		# A mover asked once is not asked again soon (no shuffling back and forth).
		other["yield_until"]=time+(6.0 if parked else 20.0)
		if parked:
			other.orders=[{"mode":"move","pos":found[0],"target":-1}]
			other.state="MOVING"
		else:give_way(other,found)
		other.path=found[1]
		other.reason="Making way"
		asked=true
		if not movers:return true
	return asked

# A hull on an attack order shelling a building; _shelling_short: stopped to
# fire while still PRESS_SLACK or more short of its firing spot, a route on.
const PRESS_ON:=6.0
const PRESS_SLACK:=2.0
const SHIFT_EVERY:=8.0
func _shelling(u:Dictionary)->bool:
	return u.members.is_empty() and not u.orders.is_empty() and u.orders[0].mode=="attack" and shelling(u)
func _shelling_short(u:Dictionary)->bool:
	return _shelling(u) and not u.path.is_empty() and u.pos.distance_to(u.orders[0].pos)>PRESS_SLACK

# The hull takes the nearest free firing spot on its target clear of `asker`'s
# next `legs` (a doorway it holds), routed round the asker, and presses on to
# it. No such spot: it stays.
func _shift_firing_spot(u:Dictionary,asker:Dictionary,legs:Array)->void:
	var enemy:=get_unit(int(u.orders[0].target))
	if not alive(enemy):return
	var d:Dictionary=definitions[u.kind]
	var layer:=collision_layer(u)
	var crowd:=crowd_radius(u.kind)
	var clearance:float=crowd+crowd_radius(asker.kind)+0.5
	var taken:=attack_rivals(u,enemy.id,[],true)
	for k in range(1,legs.size()):
		var steps:=ceili(legs[k-1].distance_to(legs[k])/2.0)
		for j in steps+1:taken.append({"pos":legs[k-1].lerp(legs[k],float(j)/maxf(1,steps)),"radius":clearance-crowd-0.7,"layer":layer})
	var spot:=attack_position(u,enemy,taken)
	if spot.x<0 or _near_legs(spot,legs,clearance) or taken.any(func(slot):return spot.distance_to(slot.pos)<crowd+float(slot.radius)+0.7):return
	var keep_off:Array=[{"pos":asker.pos,"radius":minf(clearance,u.pos.distance_to(asker.pos)-0.05)}]
	var route:=terrain.path(u.pos,spot,d.domain,float(d.radius),keep_off,terrain.mobility_profile(u.kind))
	if route.is_empty():return
	u.orders[0].pos=spot
	u.path=route
	u["press_on_until"]=time+PRESS_ON
	u.reason="Making room at the firing line"

# Asked to press on (make_way), it keeps closing on its spot while it fires.
func pressing_on(u:Dictionary)->bool:
	return time<float(u.get("press_on_until",0.0)) and _shelling_short(u)

# A jammed hull with no lower-priority friend to ask backs (or turns) off to
# the nearest clear spot off the next legs of the friendly vehicles pressing
# it, lets them pass, then resumes its order.
func back_off(u:Dictionary)->void:
	if not u.maneuver.is_empty() or u.orders.is_empty() or u.orders[0].get("give_way",false):return
	var own:float=crowd_radius(u.kind)
	var legs:Array=[]
	var keep_off:Array=[]
	for other in movement_neighbors(u):
		if other.id==u.id or not alive(other) or other.team!=u.team or collision_layer(other)!=collision_layer(u) or not other.members.is_empty():continue
		var clearance:float=own+crowd_radius(other.kind)+0.5
		if other.pos.distance_to(u.pos)>clearance+1.0:continue
		keep_off.append({"pos":other.pos,"radius":minf(clearance,other.pos.distance_to(u.pos)-0.05)})
		if not other.path.is_empty():legs.append([other.pos]+other.path.slice(0,2))
	# Only friends moving through press it: backing off for parked or
	# immobilised hulls lets nobody pass and just repeats (the detour routes
	# round them instead).
	if keep_off.is_empty() or legs.is_empty():return
	var found:Array=_give_way_spot(u,legs,keep_off,own*2.0+0.5,true)
	if found.is_empty():return
	u["yield_until"]=time+6.0
	give_way(u,found)
	u.reason="Making way"

# Firing on a building is no fight for the crew's life: a friend jammed past
# JAM_UNDER_FIRE (insistent) may ask it to pull over; it resumes firing after.
func shelling(u:Dictionary)->bool:
	var target:=get_unit(int(u.target))
	return alive(target) and definitions[target.kind].get("structure",false)

# A crew in a fight (a target, or firing in the last few seconds) holds its
# ground: it neither gives way nor backs off.
func engaged(u:Dictionary)->bool:
	return int(u.target)>=0 or time-float(u.last_shot)<3.0

# A known enemy combatant that can hurt the unit is within 25 u (the tactical
# director's danger test): the crew fights rather than shuffling for friends.
# Enemy buildings do not count, so a pile-up on a structure still resolves.
# Re-checked at most every 0.5 s per unit.
func under_threat(u:Dictionary)->bool:
	if engaged(u):return true
	if time<float(u.get("threat_until",-1.0)):return u.threat
	var threat:=false
	for other in units:
		if other.team==u.team or not alive(other) or definitions[other.kind].get("structure",false):continue
		if u.pos.distance_squared_to(other.pos)<625.0 and contact_known(u,other) and effective_unit(other,u.kind):
			threat=true
			break
	u["threat"]=threat
	u["threat_until"]=time+0.5
	return threat

# A moving vehicle pulls over to `found` [spot, route] ahead of its own orders
# (resumed on arrival), starting its blocked and jam clocks afresh.
func give_way(u:Dictionary,found:Array)->void:
	u.orders.push_front({"mode":"move","pos":found[0],"target":-1,"give_way":true})
	u.path=found[1]
	u.blocked_time=0.0
	u.erase("jam_at")
	u.erase("jam_seen")

func _route_length(from:Vector2,route:Array)->float:
	var length:=0.0
	for point in route:length+=from.distance_to(point);from=point
	return length

# Nearest clear spot 6-12 u (a mover: 3-12 u) from `other` off `legs` (one leg list, or several
# when `many`), reached by a short route clear of `keep_off`: [spot, route] or [].
# Clear means clear of friends' bodies and of the spots they are heading for.
# A `parked` friend given `far_legs` (the asker's route further on) also tries
# 14-16 u off those: it pulls on past the end of the asker's next legs.
func _give_way_spot(other:Dictionary,legs:Array,keep_off:Array,clearance:float,many:bool=false,parked:bool=false,far_legs:Array=[])->Array:
	var od:Dictionary=definitions[other.kind]
	var queries:=0
	# A moving friend just pulls over, to its own right first (as oncoming
	# hulls keep right), so it does not cut across the lane it leaves open.
	var moving:bool=not parked and not other.path.is_empty() and not other.orders.is_empty()
	var base:=0.0
	if moving:
		var travel:Vector2=other.path.back()-other.pos
		base=Vector2(-travel.y,travel.x).angle()
	var rings:Array=[3.0,4.5,6.0,8.0,10.0,12.0] if moving else [6.0,8.0,10.0,12.0]+([14.0,16.0] if not far_legs.is_empty() else [])
	# Spots friends are heading for (order and give-way spots, a section's held
	# spot, a route's end) are as taken as their bodies: friends asked to give
	# way at once never pull over onto one spot.
	var claims:Array=[]
	var crowd:=crowd_radius(other.kind)
	var layer:=collision_layer(other)
	for friend in units:
		if friend.id==other.id or friend.team!=other.team or (friend.orders.is_empty() and friend.path.is_empty()) or not alive(friend) or collision_layer(friend)!=layer:continue
		var apart:float=crowd+crowd_radius(friend.kind)+0.3
		var reach:float=float(rings.back())+apart
		for end in ([friend.orders[0].pos,friend.orders[-1].pos] if not friend.orders.is_empty() else [])+([friend.path.back()] if not friend.path.is_empty() else []):
			if end.distance_squared_to(other.pos)<reach*reach:claims.append([end,apart*apart])
	for ring in rings:
		for i in 16:
			var turn:int=i if not moving else (i+1)/2*(1 if i%2==1 else -1)
			var spot:Vector2=other.pos+Vector2.from_angle(base+turn*TAU/16)*ring
			var taken:=false
			for list in ([far_legs] if ring>12.0 else (legs if many else [legs])):
				if _near_legs(spot,list,clearance):taken=true;break
			for claim in claims:
				if spot.distance_squared_to(claim[0])<claim[1]:taken=true;break
			if taken or not terrain.avoids_bodies(other.pos,spot,keep_off) or not location_clear(spot,other.kind,other.id):continue
			var route:=terrain.path(other.pos,spot,od.domain,float(od.radius),keep_off,terrain.mobility_profile(other.kind))
			queries+=1
			if not route.is_empty() and _route_length(other.pos,route)<=ring*1.6+2.0:return [spot,route]
			if queries>=6:return []
	return []

# A hull jammed on its way to a firing spot on a structure takes the nearest
# free one instead (in reach and line of fire, clear of the spots and hulls of
# friends attacking it and of parked friends): an attack group spreads round
# the target rather than queueing behind friends stopped to fire. Never while
# it is in reach with line of fire. Per target: the first RESPOT_FREE re-spots
# RESPOT_EVERY apart, then the wait doubles, and after RESPOT_MAX it holds the
# spot it has (all spots taken: the nearest) - a hull that cannot get through
# stops cycling spots round the target. Give-way and back-off still follow
# while the jam lasts. (Committing to a spot while closing on it, or holding
# the nearest free spot early, left more tanks of a crowded attack unfired.)
const RESPOT_EVERY:=4.0
const RESPOT_FREE:=3
const RESPOT_MAX:=6
func attack_respot(u:Dictionary,order:Dictionary)->bool:
	var target_id:=int(order.get("target",-1))
	if int(u.get("respot_target",-1))!=target_id:
		u["respot_target"]=target_id;u["respots"]=0;u["respot_at"]=0.0
	var count:int=u.respots
	if count>=RESPOT_MAX or time<float(u.respot_at):return false
	u["respot_at"]=time+RESPOT_EVERY
	var enemy:=get_unit(target_id)
	var d:Dictionary=definitions[u.kind]
	if not alive(enemy) or terrain.traversable(enemy.pos,d.domain,float(d.radius)):return false
	# (It stops to fire once its gun is ready.)
	if contact_known(u,enemy) and weapon_reaches(attack_weapon(u,enemy.kind),u.pos,enemy):return false
	# Routes round friendly hulls standing still (firing, parked): a plain
	# route would lead straight back into the line of friends firing.
	var avoid:Array=[]
	for other in movement_neighbors(u):
		if other.id==u.id or not alive(other) or other.team!=u.team or collision_layer(other)!=collision_layer(u) or not other.members.is_empty() or float(other.speed_now)>0.5:continue
		var clearance:float=float(d.radius)+0.4+float(definitions[other.kind].radius)+0.08
		avoid.append({"pos":other.pos,"radius":minf(clearance,u.pos.distance_to(other.pos)-0.05)})
	var spot:=attack_position(u,enemy,attack_rivals(u,enemy.id,[],true))
	if spot.x<0:return false
	var route:=terrain.path(u.pos,spot,d.domain,float(d.radius),avoid,terrain.mobility_profile(u.kind))
	# Pressed hard against a friend there may be no way round from here yet.
	if route.is_empty():route=terrain.path(u.pos,spot,d.domain,float(d.radius),[],terrain.mobility_profile(u.kind))
	if route.is_empty():return false
	order.pos=spot
	u.path=route
	u.blocked_time=0.0
	u.respots=count+1
	u.respot_at=time+RESPOT_EVERY*pow(2.0,maxi(0,count+1-RESPOT_FREE))
	# The jam clock runs on: a crowd that still holds the hull escalates to
	# give-way and back-off as before (a new spot alone never ends a jam).
	u.reason="Taking another firing position"
	return true

# Near its goal, a hull that cannot close in takes the clear spot it is on:
# its final waypoint is a hand's width away, a friendly vehicle holds the spot,
# or friendly vehicles have pressed round it for a while.
const ARRIVE_CROWDED:=6.5
func crowded_arrival(u:Dictionary,order:Dictionary,jam:float)->bool:
	if u.path.size()==1 and u.pos.distance_to(u.path[0])<0.75:return true
	# Pulling over for a friend is no arrival (the spot is the point) until it
	# has pulled over as far as it can.
	if order.get("give_way",false):return jam>JAM_BACK_OFF
	# An attack holds while its target lives: the crowd never calls it off.
	if order.mode=="attack" and alive(get_unit(int(order.get("target",-1)))):return false
	var goal:Vector2=order.pos
	if u.pos.distance_to(goal)>ARRIVE_CROWDED:return false
	var own:float=crowd_radius(u.kind)
	for other in movement_neighbors(u):
		if other.id==u.id or not alive(other) or other.team!=u.team or collision_layer(other)!=collision_layer(u) or not other.members.is_empty():continue
		var contact:float=own+crowd_radius(other.kind)+0.6
		# A friend parked on the spot holds it; pressed for long, the hull stops.
		var held:bool=other.orders.is_empty() and other.maneuver.is_empty() and other.pos.distance_to(goal)<contact
		if held or (jam>JAM_GIVE_WAY and other.pos.distance_to(u.pos)<contact):
			return true
	return false

func _near_legs(point:Vector2,legs:Array,clearance:float)->bool:
	for k in range(1,legs.size()):
		if Geometry2D.get_closest_point_to_segment(point,legs[k-1],legs[k]).distance_to(point)<=clearance:return true
	return false

func showcase_mission() -> void:
	if not scenario.get("autonomy",false) or objectives.size()<2:return
	if counterattack_at<0 and objectives[0].owner==0:
		counterattack_at=time+12.0
		events.append({"type":"warning","text":"VILLAGE secured • Enemy counterattack approaching in 12 seconds","notice":"alert"})
	if counterattack_at<0 or time<counterattack_at or counterattack_sent:return
	counterattack_sent=true
	var force:Array=[]
	for kind in ["tank","rifle","atgm"]:
		var unit:=spawn(kind,1,Vector2(73,7))
		if not unit.is_empty():force.append(unit.id);counterattack_ids.append(unit.id)
	var destination:Vector2=objectives[0].pos
	# Respond to the captured sector and observed defenders; never hidden positions.
	for enemy in living(1):
		for friendly in living(0):
			if contact_known(enemy,friendly) and friendly.pos.distance_to(objectives[1].pos)<12:destination=objectives[1].pos
	issue(force,destination,"attack_move")
	events.append({"type":"warning","text":"COUNTERATTACK • Mixed enemy force moving on secured ground","notice":"alert"})

# Local collision index stores actual soldier bodies, not just squad anchors.
# Entries reference authoritative dictionaries; moving actors relocate immediately
# so sequential updates in the same tick see exactly the latest positions.
func rebuild_actor_spatial()->void:
	actor_spatial.clear()
	actor_radius_max=1.15
	for u in units:index_actor_unit(u)

func index_actor_unit(u:Dictionary)->void:
	if not alive(u) or definitions[u.kind].domain!="land" or not definitions[u.kind].get("solid",true):return
	actor_radius_max=maxf(actor_radius_max,float(definitions[u.kind].radius))
	for actor in ([u] if u.members.is_empty() else u.members):
		if actor.hp<=0:continue
		actor_radius_max=maxf(actor_radius_max,float(actor.get("body_radius",1.15)))
		var key:=Vector2i((actor.pos/4.0).floor())
		if not actor_spatial.has(key):actor_spatial[key]=[]
		actor_spatial[key].append({"unit":u,"actor":actor})

func relocate_actor(u:Dictionary,actor:Dictionary,old:Vector2)->void:
	if not ticking or not use_actor_index or definitions[u.kind].domain!="land":return
	var before:=Vector2i((old/4.0).floor())
	var after:=Vector2i((actor.pos/4.0).floor())
	if before==after:return
	var entries:Array=actor_spatial.get(before,[])
	for i in entries.size():
		var entry:Dictionary=entries[i]
		if entry.unit.id==u.id and entry.actor.get("index",-1)==actor.get("index",-1):
			entries.remove_at(i)
			if not actor_spatial.has(after):actor_spatial[after]=[]
			actor_spatial[after].append(entry)
			return

func actor_candidates(a:Vector2,b:Vector2,radius:float)->Array:
	var entries:Array=[]
	if not ticking or not use_actor_index:
		for u in units:
			if not alive(u) or definitions[u.kind].domain!="land":continue
			for actor in ([u] if u.members.is_empty() else u.members):
				if actor.hp>0:entries.append({"unit":u,"actor":actor})
		return entries
	var padding:=radius+actor_radius_max
	for x in range(floori((minf(a.x,b.x)-padding)/4),floori((maxf(a.x,b.x)+padding)/4)+1):
		for y in range(floori((minf(a.y,b.y)-padding)/4),floori((maxf(a.y,b.y)+padding)/4)+1):
			entries.append_array(actor_spatial.get(Vector2i(x,y),NO_UNITS))
	return entries
