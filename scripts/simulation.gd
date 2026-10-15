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
var use_spatial_targeting:=true
var spatial_targeting_threshold:=64
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
	command_serial+=1
	var accepted := 0
	var formation: Dictionary = {}
	var spacing: Dictionary = {}
	var slots: Array[Dictionary] = []
	for id in ids:
		var member:=get_unit(int(id))
		if alive(member):
			var md: Dictionary=definitions[member.kind]
			spacing[md.domain]=maxf(spacing.get(md.domain,0.0),crowd_radius(member.kind)*2.0+0.7)
	for id in ids:
		var u := get_unit(int(id))
		if not alive(u) or definitions[u.kind].get("structure",false):
			continue
		if comms_blocked(u):
			order_feedback="LINK LOST • Last orders continue; capture EXCHANGE to restore radio"
			continue
		var domain: String = definitions[u.kind].domain
		var radius: float = definitions[u.kind].radius
		var index: int = formation.get(domain, 0)
		formation[domain] = index + 1
		var target := destination
		if mode!="attack" and not terrain.traversable(destination,domain,radius):
			var sector_order:=false
			for obj in objectives:
				if destination.distance_to(obj.pos)<2.0 and domain=="land": sector_order=true
			if not sector_order:
				target=terrain.reachable_destination(u.pos,destination,domain,radius,terrain.mobility_profile(u.kind))
				if target.x<0:continue
				order_adjusted=true
		if mode != "attack" and ids.size() > 1:
			target += Vector2((index % 3 - 1) * spacing[domain], (index / 3) * spacing[domain])
		if not terrain.traversable(target, domain, radius):
			target = destination
		if mode == "attack":
			var enemy := get_unit(target_id)
			if not alive(enemy) or enemy.team == u.team or not contact_known(u,enemy):
				continue
			if not effective_unit(u,enemy.kind):
				order_feedback="Weapon ineffective against this target • use a suitable counter"
				continue
			# Attack orders pursue the last visible position, never hidden live positions.
			target = enemy.pos
			if not terrain.traversable(target, domain, radius):
				target = attack_position(u, enemy)
		if mode!="attack":
			target=formation_slot(target,u,slots)
			if target.x<0: continue
		var route := terrain.path(u.pos, target, domain,radius,[],terrain.mobility_profile(u.kind))
		if route.is_empty():
			continue
		if not queued:
			FieldOps.pause_builder(self,u.id)
			Director.cancel(u)
			for actor in u.members:Infantry.Cover.clear(actor)
			u.command_group=command_serial
			u.orders.clear()
			u.path.clear()
		if u.orders.size() >= 12:
			continue
		var order := {"mode":mode,"pos":target,"target":target_id}
		u.orders.append(order)
		if u.orders.size()==1:u.intent=order.duplicate()
		slots.append({"pos":target,"radius":crowd_radius(u.kind),"layer":collision_layer(u)})
		if u.orders.size() == 1:
			u.path = route
		u.state = "ADVANCING" if mode == "attack_move" else "MOVING"
		accepted += 1
	return accepted


func attack_position(u:Dictionary,enemy:Dictionary)->Vector2:
	var d:Dictionary=definitions[u.kind]
	var candidates:Array=[]
	for x in terrain.fog_grid_size.x:
		for y in terrain.fog_grid_size.y:
			var p:Vector2=terrain.center(Vector2i(x,y))
			if not terrain.traversable(p,d.domain,float(d.radius)) or p.distance_to(enemy.pos)>float(d.range)*0.9:continue
			if definitions[enemy.kind].domain!="air" and not terrain.line_clear(p,enemy.pos):continue
			candidates.append({"pos":p,"distance":p.distance_squared_to(u.pos)})
	candidates.sort_custom(func(a,b):return a.distance<b.distance)
	for candidate in candidates:
		if not terrain.path(u.pos,candidate.pos,d.domain,float(d.radius),[],terrain.mobility_profile(u.kind)).is_empty():return candidate.pos
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
		if definitions[u.kind].domain!="land":continue
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
	var processed_fields:Dictionary={}
	visible_cells.clear()
	for u in units:
		u.seen_by = [false, false]
		if alive(u):
			u.seen_by[u.team] = true
	for observer in units:
		if not alive(observer) or observer.get("build_left",0.0)>0 or comms_blocked(observer):
			continue
		var d: Dictionary = definitions[observer.kind]
		var candidates:Array=range_candidates(observer.pos,float(d.sight)*float(weather.sight_scale)) if indexed else units
		for target in candidates:
			if not alive(target) or target.team == observer.team:
				continue
			var radius := float(d.sight)*float(weather.sight_scale)+(Garrison.SIGHT_BONUS if Garrison.inside(observer) else 0.0)
			if terrain.cover(target.pos) and definitions[target.kind].domain == "land":
				radius *= 0.7
			if Garrison.inside(target) and time-float(target.get("last_shot",-100.0))>=3.0:radius*=0.6
			if definitions[target.kind].domain == "land" and time-float(target.get("last_shot",-100.0))>=3.0:radius*=terrain.concealment(target.pos)
			if observer.pos.distance_squared_to(target.pos) <= radius * radius:
				if d.domain == "air" or definitions[target.kind].domain == "air" or terrain.line_clear(observer.pos, target.pos):
					target.seen_by[observer.team] = true
		if observer.team == 0:
			var origin := terrain.cell(observer.pos)
			var sight:float=float(d.sight)*float(weather.sight_scale)
			var key := "%d:%d:%s:%.2f" % [origin.x,origin.y,observer.kind,weather.sight_scale]
			if processed_fields.has(key):continue
			processed_fields[key]=true
			if not visibility_cache.has(key):
				var field: Array[Vector2i] = []
				var r := ceili(sight / fog_cell_size())
				var source := terrain.center(origin)
				for x in range(maxi(0, origin.x-r), mini(terrain.fog_grid_size.x, origin.x+r+1)):
					for y in range(maxi(0, origin.y-r), mini(terrain.fog_grid_size.y, origin.y+r+1)):
						var tile := Vector2i(x,y)
						var p := terrain.center(tile)
						if source.distance_squared_to(p) <= sight*sight and (d.domain=="air" or terrain.line_clear(source,p)):
							field.append(tile)
				if visibility_cache.size()>=512:
					visibility_cache.clear()
				visibility_cache[key]=field
			for tile in visibility_cache[key]:
				visible_cells[tile]=true
				explored[tile]=true
	for u in units:
		u.visible = u.team == 0 or u.seen_by[0]

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

func auto_target_ok(u:Dictionary,other:Dictionary)->bool:
	return not passive_work(other) or other.get("id",-2)==ordered_target(u)

func emplacement_fire(u:Dictionary,d:Dictionary,dt:float)->void:
	u.cooldown-=dt
	var target:Dictionary=get_unit(u.target)
	if not can_fire(u,target):
		target={}
		var best:=INF
		for other in target_candidates(u):
			if can_fire(u,other) and auto_target_ok(u,other) and u.pos.distance_squared_to(other.pos)<best:
				best=u.pos.distance_squared_to(other.pos);target=other
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
	var ud:Dictionary=definitions[u.kind]
	if ud.get("structure",false) and (not ud.get("armed",false) or u.get("build_left",0.0)>0):return false
	if u.maneuver.get("phase","")=="WITHDRAW" or (not u.orders.is_empty() and u.orders[0].mode=="retreat"):return false
	if not alive(other) or u.team == other.team or not contact_known(u,other):
		return false
	if not u.get("members",[]).is_empty():
		for member in u.members:
			if member.hp<=0:continue
			var weapon:String="atgm" if u.kind=="atgm" and member.index==0 else "rifle"
			if weapon_reaches(weapon,member.pos,other):return true
		return false
	return weapon_reaches(u.kind,u.pos,other)

func weapon_reaches(weapon:String,source:Vector2,other:Dictionary) -> bool:
	if not effective_weapon(weapon,other.kind):return false
	var d:Dictionary=definitions[weapon]
	var td:Dictionary=definitions[other.kind]
	var height:float=float(d.altitude)-float(td.altitude)
	if source.distance_squared_to(other.pos)+height*height>float(d.range)*float(d.range):return false
	return d.domain=="air" or td.domain=="air" or terrain.line_clear(source,other.pos)


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
		if member.hp>0 and effective_weapon("atgm" if u.kind=="atgm" and member.index==0 else "rifle",target_kind):return true
	return false

func effective_weapon(weapon:String, target_kind:String) -> bool:
	return float(effectiveness[weapon][target_kind])>0

func shot_distance(u:Dictionary,other:Dictionary) -> float:
	var height:float=float(definitions[u.kind].altitude)-float(definitions[other.kind].altitude)
	return sqrt(u.pos.distance_squared_to(other.pos)+height*height)

func hit_chance(u:Dictionary,other:Dictionary) -> float:
	if not effective_weapon(u.kind,other.kind):return 0.0
	var chance:=0.95
	if other.kind=="drone":chance=0.72 if u.kind=="aa" else (0.16 if u.kind=="rifle" else 0.35)
	elif other.kind=="helo":chance=0.85 if u.kind=="aa" else 0.45
	var fraction:=clampf(shot_distance(u,other)/maxf(1,definitions[u.kind].range),0,1)
	chance*=lerpf(1.0,0.65,fraction*fraction)
	if other.state in ["MOVING","ADVANCING","RETREATING"]:chance*=0.65
	if u.state in ["MOVING","ADVANCING","RETREATING"]:chance*=0.7
	if u.suppression>0.6:chance*=0.55
	return clampf(chance,0.01,0.98)

func resolve_shot(u:Dictionary,target:Dictionary,scale:float) -> bool:
	if not alive(target) or not effective_weapon(u.kind,target.kind):return false
	var hit:bool=combat_rng.randf()<hit_chance(u,target)
	if hit:
		Infantry.hit(target,damage_amount(u,target)*scale,u.pos,time)
		target.last_hit=time
	# Near misses can suppress exposed people; armor never receives rifle chip damage.
	if definitions[target.kind].domain=="land" and definitions[target.kind].armor==0:
		# Sustained machine-gun fire from a bunker pins infantry harder than rifles.
		var pin:float=0.18 if u.kind=="bunker" else (0.09 if definitions[u.kind].get("combat_alias",u.kind)=="rifle" else 0.23)
		if Garrison.inside(target):pin*=Garrison.SUPPRESSION_SCALE
		target.suppression=minf(1,target.suppression+pin)
	var endpoint:Vector2=target.pos
	if not hit:endpoint+=Vector2.from_angle(combat_rng.randf()*TAU)*combat_rng.randf_range(2.5,4.5)
	events.append({"type":"shot","from":u.pos,"to":endpoint,"kind":definitions[u.kind].get("combat_alias",u.kind),"target_kind":target.kind,"hit":hit,"from_y":u.get("fire_height",maxf(0.95,definitions[u.kind].altitude)),"to_y":maxf(0.8,definitions[target.kind].altitude),"visible":u.visible or target.visible})
	if target.hp<=0:
		events.append({"type":"destroyed","kind":target.kind,"pos":target.pos,"visible":target.visible})
		if target.team==1:kills+=1;credits+=(35 if field_ops.is_empty() else 0)
		else:losses+=1
	return hit

func damage_amount(u: Dictionary, other: Dictionary) -> float:
	var d: Dictionary = definitions[u.kind]
	var td: Dictionary = definitions[other.kind]
	var damage := float(d.damage)*float(effectiveness[u.kind][other.kind])
	if other.kind in ["tank","aa"] and damage>0:
		var facing:float=other.facing.dot((u.pos-other.pos).normalized())
		damage *= 0.7 if facing>0.35 else (1.35 if facing< -0.35 else 1.0)
	var cover_pos:Vector2=other.pos
	var nearest_member:=INF
	for member in other.get("members",[]):
		if member.hp>0 and member.pos.distance_squared_to(u.pos)<nearest_member:
			nearest_member=member.pos.distance_squared_to(u.pos)
			cover_pos=member.pos
	if Garrison.inside(other):
		# Walls stop small arms; HE shells and missiles punch through windows.
		damage *= Garrison.DAMAGE_SCALE if u.kind in ["rifle","engineer","drone","helo","aa","boat"] else 0.85
	elif td.armor == 0 and td.domain == "land" and terrain.cover(cover_pos):
		damage *= 0.55
	elif td.armor > 0 and td.domain == "land" and d.domain == "land" and terrain.hull_down(other.pos,u.pos):
		damage *= 0.6
	return damage

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
			events.append({"type":"warning","text":"LINK LOST • Last orders and local defense continue" if blocked else "RADIO RESTORED • New orders available"})
		u.jammed=blocked
		var d: Dictionary = definitions[u.kind]
		if d.get("structure",false):
			if d.get("armed",false) and u.get("build_left",0.0)<=0:emplacement_fire(u,d,dt)
			continue
		u.cooldown -= dt
		u.repath -= dt
		Infantry.reconcile(u)
		var move_lap:int=Time.get_ticks_usec() if profiling else 0
		if not Garrison.inside(u) and Garrison.transit(u)=="":Infantry.move(u,self,dt)
		if profiling:_lap("infantry_move",move_lap)
		u.suppression = maxf(0, u.suppression-dt*0.12)
		var target_lap:int=Time.get_ticks_usec() if profiling else 0
		var candidates:Array=target_candidates(u)
		var target: Dictionary = {}
		if not u.orders.is_empty() and u.orders[0].mode == "attack":
			var desired := get_unit(u.orders[0].target)
			if can_fire(u, desired):
				target = desired
		if target.is_empty():
			var previous_target:=get_unit(u.target)
			if can_fire(u,previous_target) and auto_target_ok(u,previous_target):target=previous_target
		if target.is_empty():
			var distance := INF
			for other in candidates:
				if can_fire(u, other) and auto_target_ok(u,other):
					var dist: float = u.pos.distance_squared_to(other.pos)
					if dist < distance:
						target = other
						distance = dist
		u.target = target.get("id", -1)
		if u.aim_target!=u.target:
			u.aim_time=0.0
			u.aim_target=u.target
		if u.target>=0:u.aim_time+=dt
		else:u.aim_time=0.0
		var moving: bool = not u.orders.is_empty()
		if moving and u.orders[0].mode not in ["move","retreat"] and not target.is_empty():
			moving = false
		if not u.maneuver.is_empty():moving=not u.maneuver.arrived
		if Infantry.Cover.seeking(u) or u.get("regroup_active",false) or Garrison.transit(u)!="":moving=false
		if profiling:target_lap=_lap("unit_targeting",target_lap)
		if moving:
			move_unit(u, dt)
			if profiling:target_lap=_lap("move_unit",target_lap)
		elif not target.is_empty():
			u.state = "ENGAGING"
		elif u.orders.is_empty():
			if Garrison.inside(u):u.state="GARRISONED"
			elif Garrison.transit(u)!="":u.state="ENTERING" if Garrison.transit(u)=="IN" else "EXITING"
			else:u.state="SUPPRESSED" if u.suppression > 0.6 else "READY"
		if not moving:u.speed_now=move_toward(u.speed_now,0.0,dt*8.0)
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
	update_tactics(dt)
	if profiling:lap=_lap("tactics",lap)
	if not field_ops.is_empty():
		FieldOps.tick(self,dt)
		if profiling:lap=_lap("field_ops",lap)
		update_objectives(dt)
	elif classic.is_empty():
		update_objectives(dt)
		showcase_mission()
	else:Classic.tick(self,dt)
	enemy_clock -= dt
	if enemy_clock <= 0 and field_ops.is_empty() and not scenario.get("autonomy",false):
		enemy_clock = 50.0
		wave += 1
		if wave <= 4:
			var reinforcement := spawn("rifle" if wave % 2 else "tank", 1, Vector2(76, 7))
			if not reinforcement.is_empty() and not objectives.is_empty():issue([reinforcement.id], objectives[wave%objectives.size()].pos, "attack_move")
			events.append({"type":"warning","text":"Enemy reserves approaching from the north"})
	income_clock += dt
	if income_clock >= 1.0 and classic.is_empty() and field_ops.is_empty():
		income_clock -= 1.0
		credits += 2.0 + (3.0 if not objectives.is_empty() and objectives[0].owner == 0 else 0.0)
	if living(0).is_empty() and classic.is_empty():
		result = "DEFEAT"

	ticking=false

func infantry_combat(u:Dictionary,dt:float,candidates:Variant=null) -> void:
	if candidates==null:candidates=target_candidates(u)
	var eligible_by_weapon:Dictionary={}
	for member in u.members:
		if member.hp<=0:continue
		member["in_trench"]=terrain.dug_in(member.pos)
		if u.maneuver.get("phase","")=="WITHDRAW" or (not u.orders.is_empty() and u.orders[0].mode=="retreat"):
			member.state="WITHDRAWING"
			member.target=-1
			member.aim=0.0
			continue
		if member.get("cover_phase","") in ["SEEKING","SETTLING"]:
			member.state="RUNNING TO COVER" if member.cover_phase=="SEEKING" else "SETTLING IN COVER"
			member.aim=0.0
			if member.posture!="RISING" or time>=member.posture_until:
				member.posture="STANDING" if member.cover_phase=="SEEKING" and not member.in_trench else "CROUCHED"
			continue
		var weapon:String="atgm" if u.kind=="atgm" and member.index==0 else "rifle"
		var d:Dictionary=definitions[weapon]
		var target:Dictionary={}
		var nearest:=float(d.range)*float(d.range)
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
			var distance:float=member.pos.distance_squared_to(other.pos)+pow(float(definitions[other.kind].altitude),2)
			var priority:float=distance
			if not u.orders.is_empty() and u.orders[0].mode=="attack" and other.id==u.orders[0].target:priority=-1.0
			if distance<float(d.range)*float(d.range) and priority<nearest and (definitions[other.kind].domain=="air" or terrain.line_clear(member.pos,other.pos)):
				target=other;nearest=priority
		var target_id:int=target.get("id",-1)
		if member.target!=target_id:member.aim=0.0
		member.target=target_id
		if target.is_empty():
			member.aim=0.0
			if member.posture=="PRONE":
				member.posture="RISING"
				member.posture_until=time+0.45
			elif member.posture!="RISING" or time>=member.posture_until:
				# In a trench or behind cover soldiers stay down behind the parapet.
				var sheltered:bool=member.in_trench or (member.get("occupying",false) and member.get("cover_phase","") in ["SETTLING","SHELTERED"])
				member.posture="CROUCHED" if sheltered else "STANDING"
				if sheltered and member.has("hold_facing"):member.facing=member.facing.slerp(member.hold_facing,0.2).normalized()
				member.body_radius=0.8
			continue
		if scenario.get("autonomy",false):
			if member.posture=="RISING" and time<member.posture_until:
				member.aim=0.0;member.state="RISING";continue
			var pressure:float=maxf(member.suppression,u.suppression)
			var desired_posture:="STANDING" if member.travel>0.003 else "CROUCHED"
			if pressure>0.65 and member.travel<=0.003 and Infantry.prone_clear(u,member,self):desired_posture="PRONE"
			if desired_posture!=member.posture:
				member.posture=desired_posture
				member.posture_until=time+0.35
				member.aim=0.0
			if member.posture=="PRONE":member.body_radius=1.15
			elif time>=member.posture_until:member.body_radius=0.8
			if member.posture=="PRONE":member.state="PINNED";member.aim=0.0;continue
			if member.travel>0.003 or time<member.posture_until:
				member.state="SETTLING";member.aim=0.0;continue
			var direction:Vector2=(target.pos-member.pos).normalized()
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
		member.facing=(target.pos-member.pos).normalized()
		var preparation:float=0.75 if weapon=="atgm" else (0.45 if scenario.get("autonomy",false) else 0.2)+member.index*0.05
		member.state="ACQUIRING" if member.aim<preparation else "CYCLING"
		if member.cooldown>0 or member.aim<preparation:continue
		var proxy:Dictionary=u.duplicate()
		proxy.kind=weapon
		proxy.pos=member.pos
		proxy["fire_height"]=0.75 if member.posture=="CROUCHED" else 0.95
		proxy.suppression=maxf(u.suppression,member.suppression)
		resolve_shot(proxy,target,(1.0 if weapon=="atgm" else 0.25)*(0.4 if u.kind=="engineer" else 1.0))
		member.cooldown=float(d.interval)*(1.8 if proxy.suppression>0.6 else 1.0)
		member.rounds-=1
		member.last_shot=time
		member.state="FIRING"
		u.last_shot=time

func move_unit(u: Dictionary, dt: float) -> void:
	var d: Dictionary = definitions[u.kind]
	var order: Dictionary = u.maneuver if not u.maneuver.is_empty() else u.orders[0]
	if order.mode == "attack" and u.repath <= 0 and u.blocked_time<=1.5:
		var target := get_unit(order.target)
		if not alive(target):
			finish_order(u)
			return
		if contact_known(u,target) and terrain.traversable(target.pos, d.domain,float(d.radius)):
			order.pos = target.pos
			u.path = terrain.path(u.pos, order.pos, d.domain,float(d.radius),[],terrain.mobility_profile(u.kind))
		u.repath = 1.0
	while not u.path.is_empty() and u.pos.distance_to(u.path[0])<0.1:u.path.pop_front()
	if u.path.is_empty():
		finish_order(u)
		return
	if u.blocked_time>1.5 and u.repath<=0:
		var avoid:Array=[]
		for other in movement_neighbors(u):
			if other.id!=u.id and alive(other) and collision_layer(other)==collision_layer(u):
				# Detours avoid real bodies at their real size: soldiers, not squad
				# circles. Infantry anchors ignore other soldiers (they file through
				# individually) and keep one soldier-width from vehicles.
				var autonomy:bool=scenario.get("autonomy",false)
				var own:float=1.0 if autonomy and not u.members.is_empty() else float(d.radius)
				if autonomy and not other.members.is_empty():
					if u.members.is_empty():
						for member in other.members:
							if member.hp>0:avoid.append({"pos":member.pos,"radius":own+float(member.get("body_radius",0.8))+0.02})
				else:avoid.append({"pos":other.pos,"radius":own+float(definitions[other.kind].radius)+0.08})
		var detour:=terrain.path(u.pos,order.pos,d.domain,float(d.radius),avoid,terrain.mobility_profile(u.kind))
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
		if not detour.is_empty():u.path=detour
		u.repath=3.0
	var speed := float(d.speed)
	if d.domain == "land":
		speed *= terrain.ground_speed(u.pos,terrain.mobility_profile(u.kind))
	if u.suppression > 0.6:
		speed *= 0.6
	if order.mode=="retreat":speed*=1.2
	if scenario.get("autonomy",false) and u.kind in ["tank","aa","boat"]:
		var heading:Vector2=(u.path[0]-u.pos).normalized()
		u.reversing=order.mode=="retreat" and u.facing.dot(heading)<-0.35
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
	if u.blocked_time<=0:
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
	# Never drive away from the waypoint while turning toward it.
	if movement_clear(u,candidate,neighbors) and distance-candidate.distance_to(next)>-step*0.3:
		var previous:Vector2=u.pos
		u.pos=candidate
		relocate_actor(u,u,previous)
		u.blocked_time=0.0
		return true
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
	if not u.orders.is_empty():
		u.intent=u.orders[0].duplicate()
		u.path = terrain.path(u.pos, u.orders[0].pos, definitions[u.kind].domain,float(definitions[u.kind].radius),[],terrain.mobility_profile(u.kind))

func update_objectives(dt: float) -> void:
	for obj in objectives:
		var friendly := false
		var enemy := false
		for u in units:
			if not alive(u) or definitions[u.kind].get("structure",false) or definitions[u.kind].domain != "land" or u.maneuver.get("phase","")=="WITHDRAW":
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
			events.append({"type":"warning","text":obj.name+(" secured • +100 supply" if field_ops.is_empty() else " secured")})
		elif obj.progress <= 0:
			obj.owner = 1
	if not objectives.is_empty() and objectives.all(func(obj):return obj.owner==0 and not obj.get("enemy_present",false)):
		score_hold += dt
		if score_hold >= float(scenario.hold) and (not scenario.get("autonomy",false) or (counterattack_sent and time>counterattack_at+20)):
			result = "VICTORY"
	else:
		score_hold = 0

func collision_layer(u: Dictionary) -> String:
	# Non-solid field works (wire, trenches, nets) apply terrain zones, not bodies.
	if not definitions[u.kind].get("solid",true):return "field_zone"
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

func formation_slot(origin: Vector2, u: Dictionary, slots: Array[Dictionary]) -> Vector2:
	var d: Dictionary=definitions[u.kind]
	for ring in 18:
		for i in (1 if ring==0 else 16):
			var p:=origin+Vector2.from_angle(i*TAU/16.0)*ring
			if not terrain.traversable(p,d.domain,float(d.radius)): continue
			var clear:=true
			for slot in slots:
				if slot.layer==collision_layer(u) and p.distance_to(slot.pos)<crowd_radius(u.kind)+float(slot.radius)+0.3:
					clear=false
					break
			if clear and (terrain.segment_clear(u.pos,p,d.domain,float(d.radius)) or not terrain.path(u.pos,p,d.domain,float(d.radius),[],terrain.mobility_profile(u.kind)).is_empty()): return p
	return Vector2(-1,-1)

func movement_clear(u: Dictionary, to: Vector2, neighbors: Array) -> bool:
	var d: Dictionary=definitions[u.kind]
	# Vehicles cannot enter anti-tank obstacles (they may always back out).
	if d.domain=="land" and terrain.mobility_profile(u.kind) in terrain.VEHICLE_PROFILES:
		if terrain.vehicle_barrier(to,float(d.radius)*0.6) and not terrain.vehicle_barrier(u.pos,float(d.radius)*0.6):return false
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
	if not terrain.segment_clear(u.pos,to,d.domain,float(d.radius)): return false
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
	for u in units:
		if not alive(u):continue
		var key:=bucket(u)
		if not spatial.has(key):spatial[key]=[]
		spatial[key].append(u)

func target_candidates(u:Dictionary) -> Array:
	# Direct fixture/tool calls may mutate positions outside a tick. Preserve
	# their authoritative behavior; live simulation maintains the spatial index.
	if not ticking or not use_spatial_targeting or units.size()<spatial_targeting_threshold:return units
	var d:Dictionary=definitions[u.kind]
	if float(d.damage)<=0 and u.members.is_empty():return []
	var reach:float=float(d.range)
	var offset:=0.0
	for member in u.members:
		if member.hp>0:offset=maxf(offset,member.pos.distance_to(u.pos))
	return range_candidates(u.pos,reach+offset)

func range_candidates(origin:Vector2,radius:float) -> Array:
	var result:Array=[]
	for x in range(floori((origin.x-radius)/8),floori((origin.x+radius)/8)+1):
		for y in range(floori((origin.y-radius)/8),floori((origin.y+radius)/8)+1):
			for layer in 4:
				for other in spatial.get(Vector3i(x,y,layer),[]):
					if alive(other) and origin.distance_squared_to(other.pos)<=radius*radius:result.append(other)
	# Preserve insertion-order ties and seeded combat outcomes across the optimization.
	result.sort_custom(func(a,b):return a.id<b.id)
	return result

func movement_neighbors(u:Dictionary) -> Array:
	var key:=bucket(u)
	var result:Array=[]
	for x in range(key.x-1,key.x+2):
		for y in range(key.y-1,key.y+2):
			var nearby:=Vector3i(x,y,key.z)
			if spatial.has(nearby):result.append_array(spatial[nearby])
	return result

func showcase_mission() -> void:
	if not scenario.get("autonomy",false) or objectives.size()<2:return
	if counterattack_at<0 and objectives[0].owner==0:
		counterattack_at=time+12.0
		events.append({"type":"warning","text":"VILLAGE secured • Enemy counterattack approaching in 12 seconds"})
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
	events.append({"type":"warning","text":"COUNTERATTACK • Mixed enemy force moving on secured ground"})

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
			entries.append_array(actor_spatial.get(Vector2i(x,y),[]))
	return entries
