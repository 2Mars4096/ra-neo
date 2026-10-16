extends RefCounted

const Garrison=preload("res://scripts/garrison.gd")
const StructureDamage=preload("res://scripts/structure_damage.gd")

const KINDS=["tactical_cover","observation_post","repair_point","aid_post","concertina_wire","tank_obstacles","fighting_trench","vehicle_berm","camouflage_net","forward_supply_point","bunker","at_gun","command_post","ammo_depot"]
# Linear works may be turned 90 degrees during placement.
const ROTATABLE=["tactical_cover","concertina_wire","tank_obstacles","fighting_trench"]
# A forward supply point only receives reinforcements when no seen enemy is this close.
const FORWARD_SAFE_RADIUS:=18.0
const PURCHASES=["rifle","atgm","engineer","tank","aa","drone","helo","boat"]

static func build_choices()->Dictionary:
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/field_units.json"))
	data.erase("engineer")
	return data

static func setup(sim)->void:
	var extra:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/field_units.json"))
	sim.definitions.merge(extra)
	for kind in sim.definitions:
		if not sim.definitions[kind].has("combat_alias"):sim.definitions[kind]["combat_alias"]=kind
		if not sim.definitions[kind].has("render_alias"):sim.definitions[kind]["render_alias"]=kind
	var original:Dictionary=sim.effectiveness.duplicate(true)
	for weapon in sim.definitions:
		sim.effectiveness[weapon]={}
		for target in sim.definitions:
			var wa:String=sim.definitions[weapon].get("combat_alias",weapon)
			var ta:String=sim.definitions[target].get("combat_alias",target)
			var multiplier:float=original[wa][ta]
			if sim.definitions[weapon].get("structure",false) and not sim.definitions[weapon].get("armed",false):multiplier=0.0
			elif target in KINDS:multiplier=0.25 if wa=="rifle" else (0.0 if wa in ["drone","fpv_drone"] else 0.8)
			sim.effectiveness[weapon][target]=multiplier
	# Strike drones cruise in the scout drone's authored flight band (rooflines).
	if sim.definitions.has("fpv_drone") and sim.scenario.get("air_altitudes",{}).has("drone"):
		sim.definitions.fpv_drone.altitude=maxf(float(sim.definitions.fpv_drone.altitude),float(sim.scenario.air_altitudes.drone))
	var config:Dictionary=sim.scenario
	var insertion:=point(config.get("field_insertion",config.get("insertion",[14,97])))
	sim.credits=float(config.get("field_supply",900.0))
	sim.field_ops={"income_rate":float(config.get("field_income",2.0)),"insertion":insertion,
		"sea_insertion":point(config.get("field_sea_insertion",[sim.terrain.shore_x+7,insertion.y])),
		"enemy_insertion":point(config.get("field_enemy_insertion",config.get("enemy_insertion",[114,12]))),
		"enemy_sea_insertion":point(config.get("field_enemy_sea_insertion",[-1,-1])),
		"started":false,"obstacle_key":"","last_build_error":"","last_purchase_error":""}

static func point(value)->Vector2:
	if value is Vector2:return value
	return Vector2(float(value[0]),float(value[1]))

# Force records accept {"kind","position"|"pos"} dictionaries or [kind,[x,y]] / [kind,x,y] arrays.
static func force_records(records:Array)->Array:
	var result:Array=[]
	for record in records:
		if record is Dictionary:result.append({"kind":str(record.kind),"pos":point(record.get("position",record.get("pos")))})
		elif record.size()==2:result.append({"kind":str(record[0]),"pos":point(record[1])})
		else:result.append({"kind":str(record[0]),"pos":Vector2(float(record[1]),float(record[2]))})
	return result

static func legacy_player_force(sim)->Array:
	return ["rifle","rifle","engineer","tank","drone"].map(func(kind):return {"kind":kind,"pos":sim.field_ops.insertion})

static func legacy_enemy_force()->Array:
	var result:Array=[]
	for spot in [Vector2(56,48),Vector2(108,71),Vector2(114,12)]:
		for kind in ["rifle","atgm","tank"]:result.append({"kind":kind,"pos":spot})
	return result

static func populate(sim)->void:
	var config:Dictionary=sim.scenario
	var player:Array=force_records(config.player_force) if config.has("player_force") else legacy_player_force(sim)
	var enemy:Array=force_records(config.enemy_force) if config.has("enemy_force") else legacy_enemy_force()
	for record in player:sim.spawn(record.kind,0,record.pos)
	for record in enemy:sim.spawn(record.kind,1,record.pos)
	spawn_prepared_works(sim,config.get("enemy_works",[]),1)
	sim.field_ops.started=true
	# One-off garrison site scoring (building index, doorways, window rays) at
	# load rather than in the first battle tick. Terrain is final here.
	if not sim.objectives.is_empty() and not sim.scenario.get("architecture",[]).is_empty():garrison_sites(sim)

# Authored prepared positions (trenches, wire, bunkers, gun pits, command posts)
# start complete for their side; they are ordinary destructible field works.
static func spawn_prepared_works(sim,records:Array,team:int)->void:
	for record in records:
		var kind:String=str(record.kind)
		if not sim.definitions.has(kind):continue
		var unit:Dictionary=sim.spawn(kind,team,point(record.position))
		if unit.is_empty():continue
		unit.merge({"structure":true,"build_left":0.0,"engineer_id":-1,"build_paused":false,"rotated":bool(record.get("rotated",false)),"prepared":true},true)
		unit.hp=unit.max_hp
		unit.state="READY"
	if not records.is_empty():sync_obstacles(sim)

# Drag-to-install. Linear works lay segments along the dominant drag axis
# (RA2-style walls); nets tile the dragged rectangle. Each segment is an
# ordinary site paid at commit; one engineer section builds them in order.
const DRAG_LINE:=["tactical_cover","concertina_wire","tank_obstacles","fighting_trench"]
const DRAG_AREA:=["camouflage_net"]
const DRAG_LIMIT:=12

static func draggable(kind:String)->bool:
	return kind in DRAG_LINE or kind in DRAG_AREA

static func drag_plan(sim,kind:String,a:Vector2,b:Vector2)->Array:
	var size:Array=sim.definitions[kind].footprint
	var result:Array=[]
	if kind in DRAG_AREA:
		var w:float=float(size[0]);var d:float=float(size[1])
		var nx:=maxi(1,roundi(absf(b.x-a.x)/w)+1);var nz:=maxi(1,roundi(absf(b.y-a.y)/d)+1)
		for i in nx:
			for j in nz:
				if result.size()<DRAG_LIMIT:result.append({"pos":a+Vector2(signf(b.x-a.x)*i*w,signf(b.y-a.y)*j*d),"rotated":false})
		return result
	var delta:=b-a
	var along_x:=absf(delta.x)>=absf(delta.y)
	var length:float=float(size[0]) # Long axis of a linear work.
	var span:=absf(delta.x) if along_x else absf(delta.y)
	var count:=clampi(roundi(span/length)+1,1,DRAG_LIMIT)
	var step:=Vector2(signf(delta.x) if delta.x!=0 else 1.0,0) if along_x else Vector2(0,signf(delta.y) if delta.y!=0 else 1.0)
	for i in count:result.append({"pos":a+step*length*i,"rotated":not along_x})
	return result

static func drag_cost(sim,kind:String,plan:Array)->int:
	return int(sim.definitions[kind].cost)*plan.size()

# Commit a dragged plan: the first valid segment starts now, later ones wait as
# paid, queued sites for the same engineer. Invalid segments are skipped (not charged).
static func build_many(sim,kind:String,plan:Array,engineer_id:int)->int:
	var built:=0
	var first:=-1
	for segment in plan:
		var rotated:bool=segment.rotated and kind in ROTATABLE
		if first<0:
			if build(sim,kind,segment.pos,engineer_id,rotated):
				first=sim.units.back().id;built+=1
			continue
		if sim.credits<float(sim.definitions[kind].cost):break
		if not occupied_clear(sim,segment.pos,kind,false,[],footprint(sim,kind,segment.pos,rotated)) or not site_ground_clear(sim,kind,segment.pos,rotated):continue
		var unit:Dictionary=sim.spawn(kind,0,segment.pos)
		if unit.is_empty():continue
		unit.merge({"structure":true,"build_left":float(sim.definitions[kind].build_seconds),"engineer_id":-1,"last_engineer_id":engineer_id,"queued_for":engineer_id,"work_point":segment.pos,"build_paused":true,"rotated":rotated},true)
		unit.hp=unit.max_hp*0.2
		unit.state="QUEUED"
		sim.credits-=float(sim.definitions[kind].cost)
		built+=1
	if built>0:sync_obstacles(sim)
	return built

# After a site completes, the same engineers move on to their next queued segment.
static func continue_queue(sim,engineer:Dictionary)->void:
	var best:Dictionary={}
	for site in sim.units:
		if not sim.alive(site) or site.get("queued_for",-1)!=engineer.id or site.get("build_left",0.0)<=0:continue
		if best.is_empty() or site.pos.distance_squared_to(engineer.pos)<best.pos.distance_squared_to(engineer.pos):best=site
	if best.is_empty():return
	best.erase("queued_for")
	if not resume(sim,best.id,engineer.id):best["queued_for"]=engineer.id

# Enemy offensive: escalating two-pronged waves aimed at the player's forward
# base. A drone scouts ahead; the main body attack-moves straight in while a
# flanking group detours wide to arrive from the side; a wave that loses 70% of
# its strength withdraws to regroup. Waves need living enemy logistics.
static func wave_target(sim)->Vector2:
	var forward:=forward_point(sim)
	if forward.x>=0:return forward
	var works:Array=sim.units.filter(func(u):return sim.alive(u) and u.team==0 and u.get("structure",false))
	if not works.is_empty():
		var sum:=Vector2.ZERO
		for u in works:sum+=u.pos
		return sum/works.size()
	return sim.field_ops.insertion

static func wave_composition(index:int)->Array:
	var kinds:Array=["drone"]
	for i in 3+index:kinds.append("rifle")
	for i in 1+index/2:kinds.append("atgm")
	for i in mini(4,1+(index+1)/2):kinds.append("tank")
	if index%3==2:kinds.append("aa")
	if index>=3:kinds.append("helo")
	return kinds

# Aggressive defence: idle enemy defenders strike seen player units that come
# within 30 u of their post, then return to it once the threat is gone.
static func local_counterattacks(sim,state:Dictionary)->void:
	if sim.time<float(state.get("local_next",0.0)):return
	state.local_next=sim.time+2.0
	var wave:Array=state.get("active",[])
	for defender in sim.units:
		if not sim.alive(defender) or defender.team!=1 or defender.get("structure",false) or defender.id in wave:continue
		if sim.definitions[defender.kind].domain!="land" or defender.get("garrison_role",false):continue
		if not defender.has("post"):defender["post"]=defender.pos
		var threat:Dictionary={}
		var best:=30.0*30.0
		for intruder in sim.units:
			if not sim.alive(intruder) or intruder.team!=0 or intruder.get("structure",false) or not intruder.seen_by[1]:continue
			var d:float=intruder.pos.distance_squared_to(defender.post)
			if d<best:best=d;threat=intruder
		if not threat.is_empty() and defender.orders.is_empty():
			sim.issue([defender.id],threat.pos,"attack_move")
		elif threat.is_empty() and defender.orders.is_empty() and defender.pos.distance_to(defender.post)>8.0:
			sim.issue([defender.id],defender.post,"move")

# Enemy defenders hold buildings. Up to half of the idle rifle/ATGM sections
# posted at an objective take a garrison role and walk into intact buildings
# within GARRISON_RADIUS of it that look toward the player's landing side (the
# rest stay out for local counterattacks). A role section thrown out by a
# collapse, or whose entry failed, takes the next intact building near it, or
# drops the role when none is. Wave attackers and the counterattack reserve
# never garrison. Decided every GARRISON_INTERVAL seconds; sites are scored once.
const GARRISON_RADIUS:=40.0
const GARRISON_INTERVAL:=4.0
const GARRISON_POST_RADIUS:=45.0  # sections spawned this close to an objective defend it
const GARRISON_REACH:=50.0        # a section walks at most this far to a building
const GARRISON_PER_BUILDING:=2
const GARRISON_SHARE:=0.5
const GARRISON_SIGHT:=25.0        # field-of-fire rays from the approach-facing windows
const GARRISON_ORDERS:=2          # entry orders (routes) per decision; the rest follow next tick

static func enemy_garrisons(sim)->void:
	if sim.objectives.is_empty() or sim.time<float(sim.field_ops.get("garrison_next",0.0)):return
	sim.field_ops["garrison_next"]=sim.time+GARRISON_INTERVAL
	# Each entry order plans a route: in play a decision sends a few, and when
	# more are due it runs again next tick instead of planning them all at once.
	var orders_left:=GARRISON_ORDERS if sim.ticking else 1<<30
	var sites:Array=garrison_sites(sim)
	var excluded:Array=sim.field_ops.get("waves",{}).get("active",[])+sim.counterattack_ids
	# Sections per building: enemy claims (inside, entering, bound for) and player presence.
	var claims:Dictionary={}
	var player:Dictionary={}
	for u in sim.units:
		if not sim.alive(u) or u.members.is_empty():continue
		for key in ["garrison","garrison_target"]:
			var b:int=int(u.get(key,-1))
			if b<0:continue
			if u.team==1:claims[b]=int(claims.get(b,0))+1
			else:player[b]=true
	var buildings:Array=Garrison.index(sim).buildings
	var open:=func(b:int)->bool:
		return int(buildings[b].state)==0 and not player.has(b) and int(claims.get(b,0))<mini(GARRISON_PER_BUILDING,int(buildings[b].capacity))
	for i in sim.objectives.size():
		var objective:Vector2=sim.objectives[i].pos
		var role:Array=[];var idle:Array=[];var infantry:=0
		for u in sim.units:
			if not sim.alive(u) or u.team!=1 or u.kind not in ["rifle","atgm"] or u.members.is_empty() or u.id in excluded:continue
			if u.home.distance_to(objective)>GARRISON_POST_RADIUS:continue
			infantry+=1
			if u.get("garrison_role",false):role.append(u)
			elif u.orders.is_empty() and u.maneuver.is_empty() and sim.time-float(u.get("garrison_fail",-100.0))>20.0:idle.append(u)
		var held:=role.size()
		# Role sections outside and idle (evicted by a collapse, or entry failed) re-garrison or rejoin the QRF.
		for u in role:
			if Garrison.inside(u) or Garrison.transit(u)!="" or u.has("garrison_target") or not u.orders.is_empty():continue
			if orders_left<=0:
				sim.field_ops.garrison_next=sim.time
				return
			orders_left-=1
			var b:=nearest_site(sim,u,sites[i],open)
			if b<0 or Garrison.order(sim,[u.id],b)==0:
				u.erase("garrison_role");held-=1
			else:claims[b]=int(claims.get(b,0))+1
		var quota:=ceili(infantry*GARRISON_SHARE)
		while held<quota and not idle.is_empty():
			# Best (section, site) pair: field of fire first, then a short walk.
			var best_u:Dictionary={};var best_b:=-1;var best_score:=-INF
			for u in idle:
				for site in sites[i]:
					if not open.call(site.id):continue
					var walk:float=u.pos.distance_to(site.center)
					if walk>GARRISON_REACH:continue
					var score:float=float(site.score)-walk/GARRISON_REACH
					if score>best_score:best_score=score;best_u=u;best_b=site.id
			if best_b<0:break
			if orders_left<=0:
				sim.field_ops.garrison_next=sim.time
				return
			orders_left-=1
			idle.erase(best_u)
			if Garrison.order(sim,[best_u.id],best_b)==0:
				best_u["garrison_fail"]=sim.time
				continue
			best_u["garrison_role"]=true
			claims[best_b]=int(claims.get(best_b,0))+1
			held+=1

static func nearest_site(sim,u:Dictionary,sites:Array,open:Callable)->int:
	var best:=-1;var best_score:=-INF
	for site in sites:
		var walk:float=u.pos.distance_to(site.center)
		if walk>GARRISON_REACH or not open.call(site.id):continue
		var score:float=float(site.score)-walk/GARRISON_REACH*2.0
		if score>best_score:best_score=score;best=site.id
	return best

# Enemy mortar team at a command post or ammunition depot: every
# MORTAR_INTERVAL s it drops a short HE salvo on the largest cluster of player
# infantry it can see within range, after a warning. Rounds scatter (own seeded
# RNG, so the combat stream never shifts) and burst through
# StructureDamage.explosion. Losing the posts and depots silences it.
const MORTAR_FIRST:=60.0
const MORTAR_INTERVAL:=45.0
const MORTAR_RANGE:=260.0
const MORTAR_MIN_SECTIONS:=2      # sections within MORTAR_CLUSTER of each other
const MORTAR_CLUSTER:=15.0
const MORTAR_ROUNDS:=3
const MORTAR_FLIGHT:=4.0          # warning to first impact
const MORTAR_SPACING:=1.2
const MORTAR_SCATTER:=9.0
const MORTAR_RADIUS:=3.0
const MORTAR_DAMAGE:=30.0
const MORTAR_STRUCTURE:=6.0

static func enemy_mortar(sim)->void:
	var state:Dictionary=sim.field_ops.get("mortar",{})
	if state.is_empty():
		var rng:=RandomNumberGenerator.new();rng.seed=7177
		state={"next":MORTAR_FIRST,"rounds":[],"rng":rng}
		sim.field_ops["mortar"]=state
	while not state.rounds.is_empty() and sim.time>=float(state.rounds[0].at):
		var shell:Dictionary=state.rounds.pop_front()
		StructureDamage.explosion(sim,shell.pos,MORTAR_RADIUS,MORTAR_DAMAGE,MORTAR_STRUCTURE,"mortar")
	if sim.time<float(state.next):return
	state.next=sim.time+MORTAR_INTERVAL*0.25
	var tubes:Array=sim.units.filter(func(u):return sim.alive(u) and u.team==1 and u.kind in ["command_post","ammo_depot"] and u.get("build_left",0.0)<=0)
	if tubes.is_empty():return
	var best:=Vector2(-1,-1);var most:=MORTAR_MIN_SECTIONS-1
	var seen:Array=sim.units.filter(func(u):return sim.alive(u) and u.team==0 and not u.members.is_empty() and u.seen_by[1] and tubes.any(func(t):return t.pos.distance_to(u.pos)<=MORTAR_RANGE))
	for u in seen:
		var count:=0;var centre:=Vector2.ZERO
		for other in seen:
			if u.pos.distance_squared_to(other.pos)<MORTAR_CLUSTER*MORTAR_CLUSTER:count+=1;centre+=other.pos
		if count<=most:continue
		# Danger close: never on a cluster tangled with own troops.
		centre/=count
		if sim.units.any(func(o):return sim.alive(o) and o.team==1 and not o.get("structure",false) and sim.definitions[o.kind].domain=="land" and o.pos.distance_squared_to(centre)<(MORTAR_SCATTER+MORTAR_RADIUS+4.0)**2):continue
		most=count;best=centre
	if best.x<0:return
	state.next=sim.time+MORTAR_INTERVAL
	var rng:RandomNumberGenerator=state.rng
	for k in MORTAR_ROUNDS:
		var p:Vector2=best+Vector2.RIGHT.rotated(rng.randf()*TAU)*MORTAR_SCATTER*sqrt(rng.randf())
		state.rounds.append({"at":sim.time+MORTAR_FLIGHT+k*MORTAR_SPACING,"pos":p})
	sim.events.append({"type":"warning","text":"Incoming mortar fire"})

# Per objective, the buildings within GARRISON_RADIUS that have a doorway,
# best first. Score: share of clear sight lines from the windows facing the
# player's landing zone, plus a bonus for standing forward on that side.
static func garrison_sites(sim)->Array:
	if sim.has_meta("enemy_garrison_sites"):return sim.get_meta("enemy_garrison_sites")
	var result:Array=[]
	var buildings:Array=Garrison.index(sim).buildings
	for objective in sim.objectives:
		var sites:Array=[]
		var approach:Vector2=(sim.field_ops.insertion-objective.pos).normalized()
		for building in buildings:
			var bounds:Rect2=building.bounds
			var nearest:=Vector2(clampf(objective.pos.x,bounds.position.x,bounds.end.x),clampf(objective.pos.y,bounds.position.y,bounds.end.y))
			if nearest.distance_to(objective.pos)>GARRISON_RADIUS:continue
			var center:Vector2=bounds.get_center()
			if Garrison.entry_point(sim,building.id,center+approach*bounds.size.length()).x<0:continue
			# The window post on the approach face, and five rays fanned toward the approach.
			var outline:Rect2=bounds.grow(0.9)
			var post:=Vector2(clampf(center.x+approach.x*1000.0,outline.position.x,outline.end.x),clampf(center.y+approach.y*1000.0,outline.position.y,outline.end.y))
			var clear:=0
			for angle in [-0.6,-0.3,0.0,0.3,0.6]:
				if sim.terrain.line_clear(post,post+approach.rotated(angle)*GARRISON_SIGHT):clear+=1
			var forward:float=clampf((center-objective.pos).dot(approach)/GARRISON_RADIUS,-1.0,1.0)
			sites.append({"id":building.id,"center":center,"score":clear/5.0*2.0+forward*0.5+minf(float(building.floors),4.0)*0.1})
		sites.sort_custom(func(a,b):return a.score>b.score)
		result.append(sites)
	sim.set_meta("enemy_garrison_sites",result)
	return result

static func enemy_offensive(sim)->void:
	var plan:Dictionary=sim.scenario.get("enemy_waves",{})
	if plan.is_empty() or not sim.field_ops.started:return
	var state:Dictionary=sim.field_ops.get("waves",{})
	if state.is_empty():
		state={"next":float(plan.get("first",150.0)),"index":0,"active":[],"strength":0.0}
		sim.field_ops["waves"]=state
	if not state.active.is_empty():follow_recrew(sim,state)
	# Withdraw a broken wave so it does not trickle into the defence one unit at a time.
	if not state.active.is_empty():
		var alive:Array=state.active.filter(func(id):return sim.alive(sim.get_unit(id)))
		var hp:=0.0
		for id in alive:hp+=float(sim.get_unit(id).hp)
		if alive.is_empty() or hp<state.strength*0.3:
			if not alive.is_empty():sim.issue(alive,sim.field_ops.enemy_insertion,"retreat")
			sim.events.append({"type":"warning","text":"Enemy assault broken • survivors falling back"})
			state.active=[]
	local_counterattacks(sim,state)
	swarm_strikes(sim,state,plan)
	if not state.get("warned",false) and sim.time>=state.next-20.0 and state.index<int(plan.get("max_wave",8)) and enemy_logistics_alive(sim):
		state.warned=true
		sim.events.append({"type":"warning","text":"Enemy assault forming in the north-east • ~20 s"})
	if sim.time<state.next or state.index>=int(plan.get("max_wave",8)) or not enemy_logistics_alive(sim):return
	state.warned=false
	state.next=sim.time+float(plan.get("interval",120.0))
	var target:=wave_target(sim)
	var origin:Vector2=sim.field_ops.enemy_insertion
	var main:Array=[];var flank:Array=[];var scouts:Array=[]
	for kind in wave_composition(state.index):
		var unit:Dictionary=sim.spawn(kind,1,origin)
		if unit.is_empty():continue
		if kind=="drone":scouts.append(unit.id)
		elif kind in ["rifle","atgm"] and flank.size()<main.size()/2+1:flank.append(unit.id)
		else:main.append(unit.id)
	state.index+=1
	if not state.has("swarm_next"):state.swarm_next=sim.time+float(plan.get("interval",120.0))*0.5
	# From the second wave on, an FPV swarm strikes ahead of the assault.
	if state.index>=2:launch_swarm(sim,target,mini(8,4+state.index/2))
	state.active=main+flank+scouts
	state.target=target
	state.recrew={}
	state.strength=0.0
	for id in state.active:state.strength+=float(sim.get_unit(id).hp)
	sim.issue(scouts,target,"attack_move")
	sim.issue(main,target,"attack_move")
	# Flank: a waypoint 70 u off the direct axis on the side with a reachable route.
	var axis:Vector2=(target-origin).normalized()
	for side in [1,-1]:
		var waypoint:Vector2=origin.lerp(target,0.6)+Vector2(-axis.y,axis.x)*70.0*side
		waypoint=Vector2(clampf(waypoint.x,8,sim.terrain.world_size.x-8),clampf(waypoint.y,8,sim.terrain.world_size.y-8))
		if sim.terrain.is_water(waypoint) or not sim.terrain.traversable(waypoint,"land",2.65):continue
		sim.issue(flank,waypoint,"move")
		sim.issue(flank,target,"attack_move",true)
		break
	if flank.size()>0 and sim.get_unit(flank[0]).orders.is_empty():sim.issue(flank,target,"attack_move")
	sim.events.append({"type":"warning","text":"ENEMY ASSAULT WAVE %d • %d units inbound" % [state.index,state.active.size()]})

# Re-crew follows the wave: a vehicle boarded by a wave section joins the wave
# (its integrity adds to the wave's strength, while the boarders have already
# left the section's hp) and takes up the wave's attack if it has no orders.
# Open re-crew jobs of wave sections are remembered (section -> hull); when one
# closes and the hull was boarded, that section crewed it.
static func follow_recrew(sim,state:Dictionary)->void:
	var jobs:Array=sim.get_meta(sim.VehicleDamage.RECREW) if sim.has_meta(sim.VehicleDamage.RECREW) else []
	if jobs.is_empty() and state.get("recrew",{}).is_empty():return
	var open:Dictionary={}
	for job in jobs:open[int(job.section)]=int(job.hull)
	var pending:Dictionary=state.get("recrew",{})
	for section_id in pending:
		if open.get(section_id,-1)==pending[section_id]:continue
		var fresh:Dictionary=sim.get_unit(int(sim.get_unit(pending[section_id]).get("recrewed_as",-1)))
		if not sim.alive(fresh) or fresh.team!=1 or fresh.id in state.active:continue
		state.active.append(fresh.id)
		state.strength+=float(fresh.hp)
		if fresh.orders.is_empty() and state.has("target"):sim.issue([fresh.id],state.target,"attack_move")
	var next:Dictionary={}
	for section_id in open:
		if section_id in state.active:next[section_id]=open[section_id]
	state.recrew=next

# FPV swarms: groups of 4-8 loitering munitions fly straight in from the
# launcher's side and dive on assigned units. Between assault waves the enemy
# strikes the densest cluster of player units it can see. AA and massed rifles
# are the counter. Live drones per side are capped to keep the sim cheap.
const SWARM_LIVE_LIMIT:=16
const SWARM_STANDOFF:=90.0
const SWARM_TARGET_RADIUS:=30.0

static func swarm_strikes(sim,state:Dictionary,plan:Dictionary)->void:
	if sim.time<float(state.get("swarm_next",INF)):return
	state.swarm_next=sim.time+float(plan.get("interval",120.0))
	if state.index>=int(plan.get("max_wave",8)) or not enemy_logistics_alive(sim):return
	var aim:=densest_cluster(sim,0)
	if aim.x>=0:launch_swarm(sim,aim,4)

# Centre of the largest group of seen, mobile units of a team; (-1,-1) if none.
static func densest_cluster(sim,team:int)->Vector2:
	var seen:Array=sim.units.filter(func(u):return sim.alive(u) and u.team==team and not u.get("structure",false) and u.seen_by[1-team] and sim.definitions[u.kind].domain!="air")
	var best:=Vector2(-1,-1)
	var most:=0
	for u in seen:
		var count:=0
		for other in seen:
			if u.pos.distance_squared_to(other.pos)<15.0*15.0:count+=1
		if count>most:most=count;best=u.pos
	return best

# Launch count strike drones from the attacker's side toward aim. Vehicles near
# the aim point are preferred targets, then squads, then works. Returns ids.
static func launch_swarm(sim,aim:Vector2,count:int,team:int=1)->Array:
	var victims:Array=sim.units.filter(func(u):return sim.alive(u) and u.team!=team and sim.definitions[u.kind].domain!="air" and u.pos.distance_to(aim)<SWARM_TARGET_RADIUS)
	if victims.is_empty():return []
	victims.sort_custom(func(a,b):return swarm_rank(a,aim)<swarm_rank(b,aim))
	var live:int=sim.units.filter(func(u):return sim.alive(u) and u.team==team and u.kind=="fpv_drone").size()
	count=mini(count,SWARM_LIVE_LIMIT-live)
	var home:Vector2=sim.field_ops.enemy_insertion if team==1 else sim.field_ops.insertion
	var axis:Vector2=home-aim
	var origin:Vector2=aim+axis.normalized()*minf(axis.length(),SWARM_STANDOFF)
	var ids:=spawn_swarm(sim,origin,victims,count,team)
	if not ids.is_empty() and team==1:
		sim.events.append({"type":"warning","text":"FPV SWARM INBOUND • %d strike drones • AA and massed rifles can shoot them down" % ids.size()})
	return ids

# Player FPV strike: bought from the reinforcement panel, aimed with a map click
# and paid only on launch. Drones fly in from the forward supply point (else the
# landing zone), at most PLAYER_STRIKE_STANDOFF out, and only at enemies the
# player can see near the click; the clicked unit, then vehicles, come first.
const PLAYER_STRIKE_COST:=150
const PLAYER_STRIKE_COUNT:=5
const PLAYER_STRIKE_COOLDOWN:=60.0
const PLAYER_STRIKE_STANDOFF:=150.0

static func strike_ready_in(sim)->float:
	return maxf(0.0,float(sim.field_ops.get("strike_ready_at",0.0))-sim.time)

# "" when a strike may be aimed now, else the reason it cannot.
static func strike_reason(sim)->String:
	if sim.field_ops.is_empty() or sim.result!="":return "FPV strike unavailable"
	if strike_ready_in(sim)>0:return "FPV strike ready in %ds" % ceili(strike_ready_in(sim))
	if sim.credits<PLAYER_STRIKE_COST:return "Need %d more supply" % ceili(PLAYER_STRIKE_COST-sim.credits)
	return ""

static func strike_victims(sim,aim:Vector2,target_id:int=-1)->Array:
	var victims:Array=sim.units.filter(func(u):return sim.alive(u) and u.team==1 and u.seen_by[0] and sim.definitions[u.kind].domain!="air" and u.pos.distance_to(aim)<SWARM_TARGET_RADIUS)
	victims.sort_custom(func(a,b):return swarm_rank(a,aim)-(1000.0 if a.id==target_id else 0.0)<swarm_rank(b,aim)-(1000.0 if b.id==target_id else 0.0))
	return victims

# Charges supply and starts the cooldown only when drones actually launch.
static func player_strike(sim,aim:Vector2,target_id:int=-1)->Array:
	sim.field_ops.last_purchase_error=strike_reason(sim)
	if sim.field_ops.last_purchase_error!="":return []
	var victims:=strike_victims(sim,aim,target_id)
	if victims.is_empty():return purchase_fail_array(sim,"No visible enemy near the target")
	var live:int=sim.units.filter(func(u):return sim.alive(u) and u.team==0 and u.kind=="fpv_drone").size()
	var count:=mini(PLAYER_STRIKE_COUNT,SWARM_LIVE_LIMIT-live)
	if count<=0:return purchase_fail_array(sim,"Strike drones already airborne")
	var home:=forward_point(sim)
	if home.x<0:home=sim.field_ops.insertion
	var axis:Vector2=home-aim
	var origin:Vector2=aim+axis.normalized()*minf(axis.length(),PLAYER_STRIKE_STANDOFF)
	var ids:=spawn_swarm(sim,origin,victims,count,0)
	if ids.is_empty():return purchase_fail_array(sim,"Strike launch failed")
	sim.credits-=PLAYER_STRIKE_COST
	sim.field_ops["strike_ready_at"]=sim.time+PLAYER_STRIKE_COOLDOWN
	return ids

static func purchase_fail_array(sim,message:String)->Array:
	sim.field_ops.last_purchase_error=message
	return []

static func spawn_swarm(sim,origin:Vector2,victims:Array,count:int,team:int)->Array:
	var ids:Array=[]
	for i in count:
		var drone:Dictionary=sim.spawn("fpv_drone",team,origin+Vector2.from_angle(i*TAU/maxf(1,count))*2.5)
		if drone.is_empty():continue
		drone.strike_target=victims[i%victims.size()].id
		ids.append(drone.id)
	return ids

static func swarm_rank(u:Dictionary,aim:Vector2)->float:
	var rank:float=u.pos.distance_to(aim)
	if u.get("structure",false):rank+=60.0
	elif u.members.is_empty():rank-=15.0
	return rank

# The enemy counterattack is staged from its command post or ammunition depot;
# with both destroyed the reserve never forms. Maps without them keep the old rule.
static func enemy_logistics_alive(sim)->bool:
	var authored:bool=sim.scenario.get("enemy_works",[]).any(func(w):return str(w.kind) in ["command_post","ammo_depot"])
	if not authored:return true
	return sim.units.any(func(u):return sim.alive(u) and u.team==1 and u.kind in ["command_post","ammo_depot"])

# Offmap entries are bounded to a small ring around the configured insertion
# and must clear every living body on the same layer, including soldiers.
static func entry_position(sim,kind:String,origin:Vector2,safe_forward:bool=false)->Vector2:
	var d:Dictionary=sim.definitions[kind]
	for ring in range(0,7):
		for index in (1 if ring==0 else 12):
			var candidate:Vector2=origin+Vector2.from_angle(index*TAU/12.0)*ring*2.0
			if not sim.terrain.inside(candidate) or not sim.location_clear(candidate,kind):continue
			if d.domain=="land" and not occupied_clear(sim,candidate,kind,false):continue
			if safe_forward and sim.units.any(func(enemy):return sim.alive(enemy) and enemy.team==1 and enemy.seen_by[0] and not enemy.get("structure",false) and enemy.pos.distance_to(candidate)<FORWARD_SAFE_RADIUS):continue
			return candidate
	return Vector2(-1,-1)

static func insertion_for(sim,kind:String,team:int=0)->Vector2:
	if sim.definitions[kind].domain=="sea":
		if team==1 and sim.field_ops.enemy_sea_insertion.x>=0:return sim.field_ops.enemy_sea_insertion
		return sim.field_ops.sea_insertion
	if team==0 and sim.definitions[kind].domain=="land":
		var forward:=forward_point(sim)
		if forward.x>=0:return forward
	return sim.field_ops.insertion if team==0 else sim.field_ops.enemy_insertion

# Newest completed, unthreatened forward supply point; (-1,-1) when none.
static func forward_point(sim)->Vector2:
	var best:Dictionary={}
	for site in sim.units:
		if not sim.alive(site) or site.team!=0 or site.kind!="forward_supply_point" or site.get("build_left",0.0)>0:continue
		var threatened:=false
		for enemy in sim.units:
			if sim.alive(enemy) and enemy.team==1 and enemy.seen_by[0] and not enemy.get("structure",false) and enemy.pos.distance_to(site.pos)<FORWARD_SAFE_RADIUS:
				threatened=true
				break
		if not threatened and (best.is_empty() or site.id>best.id):best=site
	if best.is_empty():return Vector2(-1,-1)
	var rect:=footprint(sim,best.kind,best.pos,best.get("rotated",false))
	return best.pos+Vector2(0,rect.size.y/2+4.0)

# Purchases queue: supply is paid on click, units deploy one at a time every
# DEPLOY_INTERVAL seconds, and a crowded entry waits instead of failing.
const QUEUE_LIMIT:=12
const DEPLOY_INTERVAL:=3.0

static func queue(sim)->Array:
	if not sim.field_ops.has("queue"):sim.field_ops["queue"]=[]
	return sim.field_ops.queue

static func queued(sim,kind:String)->int:
	return queue(sim).count(kind)

static func purchase(sim,kind:String)->bool:
	sim.field_ops.last_purchase_error=""
	sim.field_ops["last_entry_forward"]=false
	sim.field_ops["last_deployed"]=false
	if sim.result!="" or kind not in PURCHASES:return purchase_fail(sim,"Reinforcements unavailable")
	if queue(sim).size()>=QUEUE_LIMIT:return purchase_fail(sim,"Queue full (%d)" % QUEUE_LIMIT)
	if sim.credits<float(sim.definitions[kind].cost):return purchase_fail(sim,"Need %d more supply" % ceili(float(sim.definitions[kind].cost)-sim.credits))
	sim.credits-=float(sim.definitions[kind].cost)
	queue(sim).append(kind)
	process_queue(sim)
	return true

# Right-click cancel: removes the newest queued unit of this kind with a full refund.
static func cancel_queued(sim,kind:String)->bool:
	var items:=queue(sim)
	for i in range(items.size()-1,-1,-1):
		if items[i]==kind:
			items.remove_at(i)
			sim.credits+=float(sim.definitions[kind].cost)
			return true
	return false

# Deploy the head of the queue when the interval has elapsed and its entry is clear.
static func process_queue(sim)->void:
	var items:=queue(sim)
	if items.is_empty() or sim.recruit_clock>0 or sim.result!="":return
	var kind:String=items[0]
	if deploy(sim,kind):
		items.remove_at(0)
		sim.field_ops.last_deployed=true
		sim.events.append({"type":"reinforcement","kind":kind,"forward":sim.field_ops.get("last_entry_forward",false)})

static func deploy(sim,kind:String)->bool:
	var origin:=insertion_for(sim,kind)
	var forward:bool=sim.definitions[kind].domain=="land" and origin!=sim.field_ops.insertion
	var pos:=entry_position(sim,kind,origin,forward)
	# A forward depot shortens deployment, but cannot bypass a disconnected route.
	if forward:
		if pos.x<0 or sim.terrain.path(sim.field_ops.insertion,pos,"land",float(sim.definitions[kind].radius),[],sim.terrain.mobility_profile(kind)).is_empty():
			pos=entry_position(sim,kind,sim.field_ops.insertion)
			forward=false
	if pos.x<0:return purchase_fail(sim,"Sea lane crowded" if sim.definitions[kind].domain=="sea" else "Landing zone crowded")
	var unit:Dictionary=sim.spawn(kind,0,pos)
	if unit.is_empty() or unit.pos.distance_to(pos)>0.01:
		if not unit.is_empty():unit.hp=0.0
		return purchase_fail(sim,"Landing zone crowded")
	sim.recruit_clock=DEPLOY_INTERVAL
	sim.field_ops.last_entry_forward=forward
	return true

static func purchase_fail(sim,message:String)->bool:
	sim.field_ops.last_purchase_error=message
	return false

# Reserve composition and entry come from scenario metadata. The objective is
# chosen from public sector ownership, never from hidden player positions.
static func reserve_records(sim)->Array:
	if sim.scenario.has("reserve_force"):return force_records(sim.scenario.reserve_force)
	return ["tank","rifle","atgm"].map(func(kind):return {"kind":kind,"pos":sim.field_ops.enemy_insertion})

static func reserve_target(sim)->Vector2:
	for objective in sim.objectives:
		if objective.owner==0:return objective.pos
	return sim.objectives[0].pos if not sim.objectives.is_empty() else sim.field_ops.insertion

# Enemy ships without an authored sea entry fall back to their own start, never
# to the player's sea lane.
static func rally_point(sim,u:Dictionary)->Vector2:
	if u.team==1 and sim.definitions[u.kind].domain=="sea" and sim.field_ops.enemy_sea_insertion.x<0:return u.home
	return insertion_for(sim,u.kind,u.team)

static func footprint(sim,kind:String,pos:Vector2,rotated:bool=false)->Rect2:
	var size:Array=sim.definitions[kind].footprint
	var dimensions:=Vector2(size[1],size[0]) if rotated and kind in ROTATABLE else Vector2(size[0],size[1])
	return Rect2(pos-dimensions/2,dimensions)

# Preview occupancy follows team-0 knowledge. Commit checks all physical bodies
# separately, so moving a placement ghost cannot scan hidden enemy positions.
static func known_occupant(unit:Dictionary)->bool:
	return unit.team==0 or unit.get("seen_by",[false,false])[0]

static func occupied_clear(sim,pos:Vector2,kind:String,known_only:bool,ignore:Array=[],rect:Rect2=Rect2())->bool:
	var radius:float=sim.definitions[kind].radius
	if not sim.terrain.traversable(pos,"land",radius):return false
	for unit in sim.units:
		if unit.id in ignore or not sim.alive(unit) or sim.definitions[unit.kind].domain!="land":continue
		if known_only and not known_occupant(unit):continue
		var clearance:float=radius+float(sim.definitions[unit.kind].radius)+0.12
		if rect.has_area():
			if sim.terrain.circle_rect(unit.pos,float(sim.definitions[unit.kind].radius)+0.12,rect):return false
		elif pos.distance_squared_to(unit.pos)<clearance*clearance:return false
		for member in unit.members:
			if member.hp<=0:continue
			var body_radius:float=float(member.get("body_radius",0.8))+0.1
			if rect.has_area():
				if sim.terrain.circle_rect(member.pos,body_radius,rect):return false
			elif pos.distance_to(member.pos)<radius+body_radius:return false
	return true

static func valid_site(sim,structure_id:int)->bool:
	var site:Dictionary=sim.get_unit(structure_id)
	return not sim.field_ops.is_empty() and sim.result=="" and sim.alive(site) and site.team==0 and site.kind in KINDS and site.get("build_left",0.0)>0

static func engineer_available(sim,engineer:Dictionary,structure_id:int=-1)->bool:
	if not sim.alive(engineer) or engineer.team!=0 or engineer.kind!="engineer" or sim.comms_blocked(engineer):return false
	if not engineer.members.any(func(member):return member.hp>0):return false
	for site in sim.units:
		if site.id!=structure_id and sim.alive(site) and site.get("engineer_id",-1)==engineer.id and site.get("build_left",0.0)>0 and not site.get("build_paused",false):return false
	return true

# UI query: eligibility and nearest distance only. Reachability is checked by
# resume, not repeatedly by a menu draw. Ties retain simulation insertion order.
static func available_engineer(sim,structure_id:int)->int:
	if not valid_site(sim,structure_id):return -1
	var site:Dictionary=sim.get_unit(structure_id)
	var busy:Dictionary={}
	for other in sim.units:
		if other.id!=structure_id and sim.alive(other) and other.get("build_left",0.0)>0 and not other.get("build_paused",false):busy[other.get("engineer_id",-1)]=true
	var nearest:=-1
	var distance:=INF
	for engineer in sim.units:
		if not sim.alive(engineer) or engineer.team!=0 or engineer.kind!="engineer" or busy.has(engineer.id) or sim.comms_blocked(engineer):continue
		if not engineer.members.any(func(member):return member.hp>0):continue
		var gap:float=engineer.pos.distance_squared_to(site.pos)
		if gap<distance:nearest=engineer.id;distance=gap
	return nearest

# A conservative temporary circle encloses the reserved footprint and engineer
# radius. Existing reservations stay in terrain; only the site's unit record is
# ignored for work-point body checks. Never remove the site's physical blocker.
static func work_plan(sim,kind:String,pos:Vector2,engineer:Dictionary,known_only:bool=true,structure_id:int=-1,rotated:bool=false)->Dictionary:
	var rect:=footprint(sim,kind,pos,rotated)
	var radius:float=sim.definitions.engineer.radius
	var avoid:Array=[{"pos":pos,"radius":rect.size.length()*0.5+radius+0.27}]
	var candidates:Array[Vector2]=[]
	# Non-solid works use small body radii, so stand clear of the whole footprint.
	var reach:float=float(sim.definitions[kind].radius)+radius+0.5
	if not sim.definitions[kind].get("solid",true):reach=rect.size.length()*0.5+radius+0.5
	# Wider rings rescue sites hemmed in by trees, walls or neighbouring segments.
	for ring in [0.0,1.5,3.0]:
		for index in 16:candidates.append(pos+Vector2.from_angle((index+ring)*TAU/16.0)*(reach+ring))
	# Preserve near-side-first routing for both initial work and manual resume.
	candidates.sort_custom(func(a,b):return a.distance_squared_to(engineer.pos)<b.distance_squared_to(engineer.pos))
	for work in candidates:
		if not occupied_clear(sim,work,"engineer",known_only,[engineer.id,structure_id]):continue
		var route:Array=sim.terrain.path(engineer.pos,work,"land",radius,avoid,"infantry")
		if not route.is_empty():return {"reason":"","work_point":work,"route":route}
	return {"reason":"No clear engineer work route"}

static func proposal(sim,kind:String,pos:Vector2,engineer_id:int,rotated:bool=false)->Dictionary:
	if sim.field_ops.is_empty() or sim.result!="":return {"reason":"Field operations unavailable"}
	if kind not in KINDS:return {"reason":"Unknown field structure"}
	var engineer:Dictionary=sim.get_unit(engineer_id)
	if not sim.alive(engineer) or engineer.team!=0 or engineer.kind!="engineer":return {"reason":"Select a living engineer section"}
	if sim.comms_blocked(engineer):return {"reason":"Engineer link unavailable"}
	if sim.credits<float(sim.definitions[kind].cost):return {"reason":"Insufficient supply"}
	if not engineer_available(sim,engineer):return {"reason":"Engineer assigned to another site"}
	if not sim.visible_cells.has(sim.terrain.cell(pos)):return {"reason":"Site must be currently visible"}
	if not occupied_clear(sim,pos,kind,true,[],footprint(sim,kind,pos,rotated)):return {"reason":"Site obstructed"}
	if not site_ground_clear(sim,kind,pos,rotated):return {"reason":"Site obstructed"}
	return work_plan(sim,kind,pos,engineer,true,-1,rotated)

# Works occupy their whole footprint: no buildings, water or other field works.
static func site_ground_clear(sim,kind:String,pos:Vector2,rotated:bool)->bool:
	var rect:=footprint(sim,kind,pos,rotated)
	for corner in [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y),rect.get_center()]:
		if not sim.terrain.inside(corner) or sim.terrain.is_water(corner) or sim.terrain.blocked(corner):return false
	# Rectangle intersection catches thin walls wholly between corner samples.
	for blocker in sim.terrain._static_candidates("solid",rect.get_center(),rect.size.length()*0.5):
		if blocker.intersects(rect):return false
	# Sweep the reservation in strips; coast checks include thin polygon edges.
	var strips:=maxi(1,ceili(rect.size.x/0.4))
	for i in strips+1:
		var x:float=lerpf(rect.position.x,rect.end.x,float(i)/strips)
		if not sim.terrain.segment_clear(Vector2(x,rect.position.y),Vector2(x,rect.end.y),"land",0.21):return false
	for other in sim.units:
		if sim.alive(other) and other.get("structure",false) and footprint(sim,other.kind,other.pos,other.get("rotated",false)).intersects(rect):return false
	return true

static func build_reason(sim,kind:String,pos:Vector2,engineer_id:int,rotated:bool=false)->String:
	return proposal(sim,kind,pos,engineer_id,rotated).reason

static func can_build(sim,kind:String,pos:Vector2,engineer_id:int,rotated:bool=false)->bool:
	return build_reason(sim,kind,pos,engineer_id,rotated)==""

static func fail(sim,message:String)->bool:
	if not sim.field_ops.is_empty():sim.field_ops.last_build_error=message
	return false

static func assign_builder(sim,site:Dictionary,engineer:Dictionary,plan:Dictionary)->void:
	var previous:Dictionary=sim.get_unit(site.get("engineer_id",-1))
	if not previous.is_empty() and previous.id!=engineer.id and previous.get("building_id",-1)==site.id:
		# Stop only the superseded construction assignment, not unrelated orders.
		sim.stop([previous.id])
		previous.erase("building_id")
	sim.Director.cancel(engineer)
	for member in engineer.members:sim.Infantry.Cover.clear(member)
	engineer.orders=[{"mode":"move","pos":plan.work_point,"target":-1}]
	engineer.intent=engineer.orders[0].duplicate()
	engineer.path=plan.route
	engineer["building_id"]=site.id
	site.engineer_id=engineer.id
	site["last_engineer_id"]=engineer.id
	site.work_point=plan.work_point
	site.build_paused=false
	site.state="UNDER CONSTRUCTION"
	sim.field_ops.last_build_error=""

static func build(sim,kind:String,pos:Vector2,engineer_id:int,rotated:bool=false)->bool:
	rotated=rotated and kind in ROTATABLE
	var plan:=proposal(sim,kind,pos,engineer_id,rotated)
	if plan.reason!="":return fail(sim,plan.reason)
	# Full physical validation only at commitment. Do not identify hidden units,
	# relocate the requested site, or charge/spawn anything on rejection.
	if not occupied_clear(sim,pos,kind,false,[],footprint(sim,kind,pos,rotated)) or not occupied_clear(sim,plan.work_point,"engineer",false,[engineer_id]):return fail(sim,"Site unavailable")
	var unit:Dictionary=sim.spawn(kind,0,pos)
	if unit.is_empty():return fail(sim,"Site unavailable")
	unit.merge({"structure":true,"build_left":float(sim.definitions[kind].build_seconds),"engineer_id":engineer_id,"work_point":plan.work_point,"build_paused":false,"rotated":rotated},true)
	unit.hp=unit.max_hp*0.2
	assign_builder(sim,unit,sim.get_unit(engineer_id),plan)
	sim.credits-=float(sim.definitions[kind].cost)
	sync_obstacles(sim)
	return true

# Explicit orders pause and release the builder, but preserve the paid site.
# Returning to the work point does not resume automatically; Resume is explicit.
static func pause_builder(sim,engineer_id:int)->void:
	if sim.field_ops.is_empty():return
	var engineer:Dictionary=sim.get_unit(engineer_id)
	if not engineer.is_empty():
		engineer.erase("building_id")
		# A new order also abandons any obstacle clearing in progress.
		var clearing:Dictionary=sim.get_unit(engineer.get("clearing_id",-1))
		if not clearing.is_empty():clearing.erase("cleared_by")
		engineer.erase("clearing_id")
	# A segment of a dragged line rejoins that line's queue; a single site waits for RESUME.
	var in_line:bool=sim.units.any(func(s):return sim.alive(s) and s.get("queued_for",-1)==engineer_id and s.get("build_left",0.0)>0)
	for unit in sim.units:
		if sim.alive(unit) and unit.get("engineer_id",-1)==engineer_id and unit.get("build_left",0.0)>0:
			unit.build_paused=true
			unit["last_engineer_id"]=engineer_id
			unit.engineer_id=-1
			unit.state="CONSTRUCTION PAUSED"
			if in_line:unit["queued_for"]=engineer_id

# Engineers clear (breach) a field work: enemy wire, hedgehogs, sandbags or a
# trench, or take down their own work for a partial refund. Armed emplacements
# must be destroyed in combat instead.
const CLEARABLE:=["concertina_wire","tank_obstacles","tactical_cover","fighting_trench","vehicle_berm","camouflage_net"]
const CLEAR_SECONDS:={"concertina_wire":6.0,"tank_obstacles":9.0,"tactical_cover":6.0,"fighting_trench":8.0,"vehicle_berm":10.0,"camouflage_net":4.0}

static func can_clear(sim,site:Dictionary)->bool:
	return sim.alive(site) and str(site.kind) in CLEARABLE

static func clear_site(sim,site_id:int,engineer_id:int)->bool:
	var site:Dictionary=sim.get_unit(site_id)
	var engineer:Dictionary=sim.get_unit(engineer_id)
	if not can_clear(sim,site):return fail(sim,"Only wire, obstacles, sandbags, berms, nets and trenches can be cleared")
	if not sim.alive(engineer) or engineer.kind!="engineer" or engineer.team!=0 or sim.comms_blocked(engineer):return fail(sim,"Select a living engineer section")
	if site.team!=0 and not sim.contact_known(engineer,site):return fail(sim,"Obstacle not currently spotted")
	var plan:=work_plan(sim,site.kind,site.pos,engineer,true,site.id,site.get("rotated",false))
	if plan.reason!="":return fail(sim,"No route to the obstacle")
	pause_builder(sim,engineer.id)
	sim.Director.cancel(engineer)
	for member in engineer.members:sim.Infantry.Cover.clear(member)
	engineer.orders=[{"mode":"move","pos":plan.work_point,"target":-1}]
	engineer.intent=engineer.orders[0].duplicate()
	engineer.path=plan.route
	engineer.hold_command=false
	engineer["clearing_id"]=site.id
	site["cleared_by"]=engineer.id
	site["clear_point"]=plan.work_point
	sim.field_ops.last_build_error=""
	return true

# Enemy assault units jammed against the player's obstacles breach them by
# fire, then resume their wave order (pushed back behind the breach).
static func enemy_breach(sim)->void:
	if int(sim.time*2.0)%2!=0:return
	for u in sim.units:
		if not sim.alive(u) or u.team!=1 or u.orders.is_empty() or float(u.get("blocked_time",0.0))<2.5:continue
		if u.orders[0].mode=="attack":continue
		var best:Dictionary={};var distance:=8.0
		for site in sim.units:
			if not sim.alive(site) or site.team!=0 or not can_clear(sim,site):continue
			var d:float=site.pos.distance_to(u.pos)
			if d<distance and sim.effective_unit(u,site.kind):distance=d;best=site
		if best.is_empty():continue
		u.orders.push_front({"mode":"attack","pos":best.pos,"target":best.id})
		u.path=sim.terrain.path(u.pos,best.pos,sim.definitions[u.kind].domain,float(sim.definitions[u.kind].radius),[],sim.terrain.mobility_profile(u.kind))
		if u.path.is_empty():u.path=[best.pos]
		u.blocked_time=0.0

# Per tick: engineers on site wear the work down; it is removed when cleared.
static func progress_clearing(sim,dt:float)->void:
	for site in sim.units:
		if not sim.alive(site) or not site.has("cleared_by"):continue
		var engineer:Dictionary=sim.get_unit(site.cleared_by)
		if not sim.alive(engineer) or engineer.get("clearing_id",-1)!=site.id:
			site.erase("cleared_by");continue
		var point:Vector2=site.get("clear_point",site.pos)
		var working:bool=engineer.orders.is_empty() and engineer.pos.distance_to(point)<1.5 and engineer.suppression<=0.6
		working=working and engineer.members.any(func(m):return m.hp>0 and m.pos.distance_to(point)<3.5)
		if not working:continue
		engineer.state="CLEARING"
		site.state="BEING CLEARED"
		site.hp-=float(site.max_hp)*dt/float(CLEAR_SECONDS.get(site.kind,8.0))
		if site.hp<=0:
			site.hp=0.0
			site.state="CLEARED"
			engineer.erase("clearing_id")
			if site.team==0:sim.credits+=float(sim.definitions[site.kind].cost)*0.5
			sim.events.append({"type":"warning","text":"%s cleared by engineers" % str(sim.definitions[site.kind].get("name",site.kind)).capitalize()})
			sim.events.append({"type":"destroyed","kind":site.kind,"pos":site.pos,"visible":true})

static func resume(sim,structure_id:int,engineer_id:int=-1)->bool:
	if not valid_site(sim,structure_id):return fail(sim,"Site unavailable")
	var site:Dictionary=sim.get_unit(structure_id)
	if engineer_id<0:engineer_id=available_engineer(sim,structure_id)
	# No idle section: take the section this site is queued for (or last built it)
	# and swap its current segment back into its queue rather than refusing.
	if engineer_id<0:engineer_id=switch_builder(sim,site)
	var engineer:Dictionary=sim.get_unit(engineer_id)
	if not engineer_available(sim,engineer,structure_id):return fail(sim,"No available engineer")
	site.erase("queued_for")
	var plan:=work_plan(sim,site.kind,site.pos,engineer,true,structure_id,site.get("rotated",false))
	if plan.reason!="":return fail(sim,"Unable to reach work point")
	if not occupied_clear(sim,plan.work_point,"engineer",false,[engineer_id,structure_id]):return fail(sim,"Work point unavailable")
	assign_builder(sim,site,engineer,plan)
	return true

static func switch_builder(sim,site:Dictionary)->int:
	var engineer:Dictionary=sim.get_unit(site.get("queued_for",site.get("last_engineer_id",-1)))
	if not sim.alive(engineer) or engineer.team!=0 or engineer.kind!="engineer" or sim.comms_blocked(engineer):return -1
	for other in sim.units:
		if other.id!=site.id and sim.alive(other) and other.get("engineer_id",-1)==engineer.id and other.get("build_left",0.0)>0 and not other.get("build_paused",false):
			pause_builder(sim,engineer.id)
			other["queued_for"]=engineer.id
	return engineer.id

# Engineers left idle (no orders, not building) pick up their queued segments.
static func idle_engineers_continue(sim)->void:
	for engineer in sim.units:
		if not sim.alive(engineer) or engineer.team!=0 or engineer.kind!="engineer" or engineer.has("building_id") or engineer.has("clearing_id") or not engineer.orders.is_empty():continue
		if sim.units.any(func(s):return sim.alive(s) and s.get("queued_for",-1)==engineer.id and s.get("build_left",0.0)>0):
			continue_queue(sim,engineer)

static func cancel(sim,structure_id:int)->bool:
	var unit:Dictionary=sim.get_unit(structure_id)
	if sim.field_ops.is_empty() or sim.result!="" or not sim.alive(unit) or unit.team!=0 or unit.kind not in KINDS or unit.get("build_left",0.0)<=0:return fail(sim,"Site unavailable")
	var definition:Dictionary=sim.definitions[unit.kind]
	sim.credits+=float(definition.cost)*unit.build_left/float(definition.build_seconds)
	unit.hp=0.0
	unit.state="CANCELLED"
	var engineer:Dictionary=sim.get_unit(unit.engineer_id)
	if sim.alive(engineer) and engineer.get("building_id",-1)==unit.id:
		engineer.erase("building_id")
		if not unit.build_paused:sim.stop([engineer.id])
	sync_obstacles(sim)
	sim.field_ops.last_build_error=""
	return true

static func sync_obstacles(sim)->void:
	var structures:Array=sim.units.filter(func(u):return sim.alive(u) and u.get("structure",false))
	# New wrecks must change the key too, so they block routes immediately.
	var key:String=str(structures.map(func(u):return [u.id,u.get("build_left",0.0)<=0]))+"|"+str(sim.VehicleDamage.wrecks(sim).size())
	if key==sim.field_ops.obstacle_key:return
	sim.field_ops.obstacle_key=key
	var blocks:Array=[]
	var covers:Array=[]
	var zones:Array=[]
	for unit in structures:
		var rect:=footprint(sim,unit.kind,unit.pos,unit.get("rotated",false))
		var definition:Dictionary=sim.definitions[unit.kind]
		if definition.get("solid",true):blocks.append(rect)
		elif unit.build_left<=0:
			var zone:Dictionary=definition.get("zone",{})
			zones.append({"rect":rect,"speed":zone.get("speed",{}),"cover":zone.get("cover",[]),"conceal":float(zone.get("conceal",1.0)),"dug":unit.kind=="fighting_trench","front":Vector2.LEFT if unit.get("rotated",false) else Vector2.UP})
		if unit.kind=="tactical_cover" and unit.build_left<=0:covers.append(rect)
	# Burnt-out and abandoned vehicles block the road for everyone (local nav
	# refresh only) and give hard cover to infantry beside them.
	for wreck in sim.VehicleDamage.wrecks(sim):
		var half:float=float(wreck.radius)*0.7
		var rect:=Rect2(wreck.pos-Vector2(half,half),Vector2(half,half)*2.0)
		blocks.append(rect);covers.append(rect)
	var changed:bool=sim.terrain.update_field_geometry(blocks,covers)
	if sim.terrain.update_field_zones(zones) or changed:sim.visibility_cache.clear()

# Tracked vehicles of either side flatten wire they drive across.
static func crush_wire(sim,wire:Dictionary)->void:
	var rect:=footprint(sim,wire.kind,wire.pos,wire.get("rotated",false))
	for vehicle in sim.units:
		if not sim.alive(vehicle) or vehicle.get("structure",false) or sim.definitions[vehicle.kind].domain!="land":continue
		if sim.terrain.mobility_profile(vehicle.kind)!="tracked":continue
		if rect.grow(float(sim.definitions[vehicle.kind].radius)*0.5).has_point(vehicle.pos):
			wire.hp=0.0
			wire.state="CRUSHED"
			sim.events.append({"type":"warning","text":"Wire crushed by armour"})
			return

static func tick(sim,dt:float)->void:
	if sim.result!="":return
	sim.credits+=dt*float(sim.field_ops.income_rate)
	process_queue(sim)
	enemy_offensive(sim)
	enemy_garrisons(sim)
	enemy_mortar(sim)
	# Enemy infantry re-crew their abandoned hulls and capture the player's.
	sim.VehicleDamage.enemy_recrew(sim)
	idle_engineers_continue(sim)
	progress_clearing(sim,dt)
	enemy_breach(sim)
	for unit in sim.units:
		if not sim.alive(unit) or not unit.get("structure",false):continue
		if unit.build_left>0:
			var engineer:Dictionary=sim.get_unit(unit.engineer_id)
			unit.state="QUEUED" if unit.has("queued_for") else "CONSTRUCTION PAUSED"
			if unit.build_paused or not sim.alive(engineer):continue
			var working:bool=engineer.pos.distance_to(unit.work_point)<0.8 and engineer.suppression<=0.6
			working=working and engineer.members.any(func(m):return m.hp>0 and m.pos.distance_to(unit.work_point)<3.0 and m.suppression<=0.6)
			if not working:continue
			var used:float=minf(dt,unit.build_left)
			unit.build_left=maxf(0,unit.build_left-used)
			unit.hp=minf(unit.max_hp,unit.hp+unit.max_hp*0.8*used/float(sim.definitions[unit.kind].build_seconds))
			unit.state="BUILDING" if unit.build_left>0 else "READY"
			if unit.build_left<=0:
				engineer.erase("building_id")
				continue_queue(sim,engineer)
			continue
		if unit.kind=="concertina_wire":crush_wire(sim,unit)
		if unit.kind not in ["aid_post","repair_point"]:continue
		for ally in sim.units:
			if not sim.alive(ally) or ally.team!=unit.team or ally.get("structure",false) or sim.definitions[ally.kind].domain!="land":continue
			if ally.pos.distance_to(unit.pos)>10 or sim.time-ally.last_hit<6 or ally.suppression>0.6:continue
			if not sim.terrain.line_clear(unit.pos,ally.pos):continue
			if unit.kind=="aid_post" and not ally.members.is_empty():sim.Infantry.recover(ally,dt*6)
			elif unit.kind=="repair_point" and ally.members.is_empty():
				ally.hp=minf(ally.max_hp,ally.hp+dt*6)
				sim.VehicleDamage.field_repair(sim,ally,dt)
	sync_obstacles(sim)
	if sim.field_ops.started:
		if sim.counterattack_at<0 and sim.objectives.any(func(objective):return objective.owner==0):sim.counterattack_at=sim.time+12
		if sim.counterattack_at>=0 and sim.time>=sim.counterattack_at and not sim.counterattack_sent and enemy_logistics_alive(sim):
			sim.counterattack_sent=true
			var force:Array=[]
			for record in reserve_records(sim):
				var enemy:Dictionary=sim.spawn(record.kind,1,record.pos)
				if not enemy.is_empty():force.append(enemy.id);sim.counterattack_ids.append(enemy.id)
			sim.issue(force,reserve_target(sim),"attack_move")
		if sim.living(0).filter(func(u):return not u.get("structure",false)).is_empty():sim.result="DEFEAT"
