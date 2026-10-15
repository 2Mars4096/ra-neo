extends RefCounted

# Component damage for vehicles (tank, IFV, corvette, gunship). A hit either
# fails to penetrate (ricochet: little integrity loss, the crew buttons up) or
# penetrates and may knock out one component:
#   mobility     tracks/engine: a land or sea hull cannot move (it still fires);
#                a gunship is damaged and flies slower
#   firepower    main weapon disabled
#   crew         a casualty: slower reload and target acquisition; the last
#                casualty bails the crew out (gunship: crashes)
#   catastrophic ammunition cook-off: destroyed at once
# HP stays an overall integrity bar. Abandoned and destroyed land vehicles stay
# on the map as wrecks that block vehicles. Penetration and outcome rolls use
# a dedicated seeded RNG so they never shift the shared combat RNG stream.

# Armour/crew/effect data live in the vehicle rows of units.json:
#   armor_mm [front, side, rear], crew, nonpen_damage, damage_effects {weights}.
# Weapon penetration (RHA-equivalent at point blank and at maximum range),
# chance that a penetration knocks out a component, and whether it can cook
# off ammunition. Keyed by unit kind first, then by combat alias.
const PENETRATION:={
	"rifle":{"near":12.0,"far":9.0,"effect":0.06,"heavy":false},
	"bunker":{"near":18.0,"far":14.0,"effect":0.1,"heavy":false},
	"aa":{"near":70.0,"far":45.0,"effect":0.3,"heavy":false},
	"boat":{"near":140.0,"far":130.0,"effect":0.7,"heavy":true},
	"tank":{"near":620.0,"far":520.0,"effect":1.0,"heavy":true},
	"at_gun":{"near":520.0,"far":440.0,"effect":1.0,"heavy":true},
	"atgm":{"near":700.0,"far":700.0,"effect":1.0,"heavy":true},
	"helo":{"near":600.0,"far":600.0,"effect":0.6,"heavy":true},
}
const NO_PENETRATION:={"near":0.0,"far":0.0,"effect":0.0,"heavy":false}
# Hull arcs from the target's facing: front within 60 degrees, rear within ~53.
const FRONT_DOT:=0.5
const REAR_DOT:=-0.6
# pen/armour ratio below LOW never penetrates, above LOW+SPAN always does.
const RATIO_LOW:=0.75
const RATIO_SPAN:=0.5
# A heavy round that fails to penetrate can still break a track.
const TRACK_HIT:=0.05
const BUTTON_SECONDS:=4.0
# Per missing crew member: extra reload (fraction of interval) and acquisition.
const RELOAD_PENALTY:=0.6
const ACQUIRE_PENALTY:=0.6
const BUTTONED_ACQUIRE:=0.4
# A damaged gunship flies at this fraction of its speed.
const DAMAGED_FLIGHT:=0.6
const WRECKS:="vehicle_wrecks"
# Hazards that run on after the hit (tick_hazards):
#   fire       (corvette) burns integrity until the crew puts it out; a small
#              chance per second that it reaches the magazine
#   flooding   (corvette) water comes in at flood_rate (hull volume per s); the
#              pumps cut the rate in proportion to surviving crew; a full hull sinks
#   tail_rotor (gunship) spins down and crashes: destroyed, blast on impact
#   hydraulics (gunship) controlled forced landing: out of action, crew safe
const HAZARDS:="vehicle_hazards"
const FIRE_SECONDS:=Vector2(9.0,16.0)
const FIRE_DPS:=5.0
const MAGAZINE_RISK:=0.01
const FLOOD_RATE:=Vector2(0.025,0.045)
const PUMP_RATE:=0.0018
const FLOOD_DRAFT:=1.3
const CRASH_DESCENT:=4.5
const LANDING_DESCENT:=2.2
const CRASH_BLAST:={"radius":4.0,"damage":45.0,"structure":5.0}
const LABEL:={"tank":"Tank","aa":"Skyguard","boat":"Corvette","helo":"Gunship"}

static func tracked(sim,u:Dictionary)->bool:
	return u.members.is_empty() and sim.definitions[u.kind].has("armor_mm")

static func _rng(sim)->RandomNumberGenerator:
	if not sim.has_meta("vehicle_damage_rng"):
		var rng:=RandomNumberGenerator.new()
		rng.seed=90217
		sim.set_meta("vehicle_damage_rng",rng)
	return sim.get_meta("vehicle_damage_rng")

static func weapon_spec(sim,u:Dictionary)->Dictionary:
	if PENETRATION.has(u.kind):return PENETRATION[u.kind]
	return PENETRATION.get(sim.definitions[u.kind].get("combat_alias",u.kind),NO_PENETRATION)

# 0 front, 1 side, 2 rear: the hull face the shot arrives on.
static func facing_index(target:Dictionary,source:Vector2)->int:
	var offset:Vector2=source-target.pos
	if offset.length_squared()<0.0001:return 0
	var dot:float=target.facing.dot(offset.normalized())
	return 0 if dot>=FRONT_DOT else (2 if dot<=REAR_DOT else 1)

static func penetration(sim,u:Dictionary,target:Dictionary)->float:
	var spec:Dictionary=weapon_spec(sim,u)
	var reach:float=maxf(1.0,sim.weapon_range(u.kind,sim.definitions[target.kind]))
	var fraction:float=clampf(sim.shot_distance(u,target)/reach,0.0,1.0)
	return lerpf(float(spec.near),float(spec.far),fraction)

static func penetration_chance(sim,u:Dictionary,target:Dictionary)->float:
	var armour:Array=sim.definitions[target.kind].get("armor_mm",[])
	if armour.is_empty():return 1.0
	var plate:float=maxf(1.0,float(armour[facing_index(target,u.pos)]))
	return clampf((penetration(sim,u,target)/plate-RATIO_LOW)/RATIO_SPAN,0.0,1.0)

# Expected integrity loss per hit as a fraction of the weapon's damage; used by
# damage_amount so estimates (and the rear-weaker-than-front rule) stay honest.
static func expected_scale(sim,u:Dictionary,target:Dictionary)->float:
	var p:=penetration_chance(sim,u,target)
	return p+(1.0-p)*float(sim.definitions[target.kind].get("nonpen_damage",0.1))

static func ensure_state(sim,u:Dictionary)->void:
	if u.has("crew"):return
	var crew:int=int(sim.definitions[u.kind].get("crew",2))
	u.merge({"crew":crew,"crew_full":crew,"mobility_kill":false,"firepower_kill":false,"abandoned":false,"buttoned_until":-100.0,"reload_mark":float(u.get("last_shot",-100.0)),"aim_mark":-1},true)

# Called from resolve_shot for a vehicle that was hit. `amount` is the expected
# damage from damage_amount (times the shot's scale). Rolls penetration and a
# component effect and returns the integrity damage to apply to target.hp.
static func strike(sim,u:Dictionary,target:Dictionary,amount:float)->float:
	if amount<=0.0 or not tracked(sim,target):return amount
	ensure_state(sim,target)
	var td:Dictionary=sim.definitions[target.kind]
	var spec:Dictionary=weapon_spec(sim,u)
	var rng:=_rng(sim)
	var p:=penetration_chance(sim,u,target)
	var nonpen:float=float(td.get("nonpen_damage",0.1))
	var base:float=amount/(p+(1.0-p)*nonpen)
	var land:bool=td.domain=="land"
	if land:target.buttoned_until=sim.time+BUTTON_SECONDS
	if rng.randf()>=p:
		var damage:float=base*nonpen
		var effect:="ricochet"
		if land and spec.heavy and not target.mobility_kill and rng.randf()<TRACK_HIT:
			effect="mobility"
			target.mobility_kill=true
			_report(sim,target,effect,"%s track broken · immobilised",false)
		else:_event(sim,target,effect,false)
		return _finish(sim,target,damage)
	var damage:float=base
	if rng.randf()<float(spec.effect):
		var effect:String=_pick(rng,td.get("damage_effects",{}),spec.heavy)
		match effect:
			"catastrophic":
				target.hp=0.0
				_report(sim,target,effect,"%s destroyed · ammunition cook-off" if td.domain!="air" else "%s destroyed")
				return _finish(sim,target,0.0)
			"mobility":
				if not target.mobility_kill:
					target.mobility_kill=true
					_report(sim,target,effect,"%s damaged · flying slow" if td.domain=="air" else "%s immobilised")
			"firepower":
				if not target.firepower_kill:
					target.firepower_kill=true
					_report(sim,target,effect,"%s weapons disabled" if td.domain=="air" else "%s main gun disabled")
			"crew":
				target.crew=maxi(0,int(target.crew)-1)
				target.suppression=maxf(target.suppression,0.9)
				target.cooldown=maxf(float(target.cooldown),0.0)+float(td.interval)
				target.aim_time=0.0
				if target.crew<=0:
					target.hp=0.0
					if td.domain=="air":_report(sim,target,"catastrophic","%s pilot lost · crashed")
					else:
						target.abandoned=true
						_report(sim,target,"abandoned","%s crew bailed out · vehicle abandoned")
					return _finish(sim,target,0.0)
				_report(sim,target,effect,"%s crew casualty")
			"fire":
				if float(target.get("fire_until",-1.0))<sim.time:
					var missing:int=int(target.crew_full)-int(target.crew)
					target["fire_until"]=sim.time+rng.randf_range(FIRE_SECONDS.x,FIRE_SECONDS.y)*(1.0+0.5*missing)
					_hazard(sim,target)
					_report(sim,target,effect,"%s on fire")
			"flooding":
				target["flood_rate"]=float(target.get("flood_rate",0.0))+rng.randf_range(FLOOD_RATE.x,FLOOD_RATE.y)
				target["flood"]=float(target.get("flood",0.0))
				_hazard(sim,target)
				_report(sim,target,effect,"%s holed below the waterline · flooding")
			"tail_rotor","hydraulics":
				if not target.has("crash"):
					target["crash"]="spin" if effect=="tail_rotor" else "landing"
					_hazard(sim,target)
					_report(sim,target,effect,"%s tail rotor hit · going down" if effect=="tail_rotor" else "%s hydraulics hit · forced landing")
	return _finish(sim,target,damage)

static func _hazard(sim,target:Dictionary)->void:
	if not sim.has_meta(HAZARDS):sim.set_meta(HAZARDS,[])
	var list:Array=sim.get_meta(HAZARDS)
	if not list.has(target):list.append(target)

# Per tick (via structure_damage.tick): fires, flooding and falling aircraft.
# Returns ground impacts [{pos,radius,damage,structure,team}] for the caller's
# blast model.
static func tick_hazards(sim,dt:float)->Array:
	var impacts:Array=[]
	if not sim.has_meta(HAZARDS):return impacts
	var list:Array=sim.get_meta(HAZARDS)
	var rng:=_rng(sim)
	for i in range(list.size()-1,-1,-1):
		var u:Dictionary=list[i]
		var active:=false
		if sim.alive(u) and u.has("crash"):
			active=true
			_descend(sim,u,dt,impacts)
		if sim.alive(u) and u.has("fire_until"):
			if sim.time<float(u.fire_until):
				active=true
				u.hp-=FIRE_DPS*dt
				if rng.randf()<MAGAZINE_RISK*dt:
					u.hp=0.0
					_report(sim,u,"catastrophic","%s fire reached the magazine · destroyed")
				elif u.hp<=0.0:_report(sim,u,"destroyed","%s burnt out")
				if u.hp<=0.0:_lost(sim,u)
			else:
				u.erase("fire_until")
				_event(sim,u,"fire_out")
		if sim.alive(u) and u.has("flood"):
			var pumps:float=float(u.get("crew",1))/maxf(1.0,float(u.get("crew_full",1)))
			u.flood_rate=maxf(0.0,float(u.flood_rate)-PUMP_RATE*pumps*dt)
			u.flood=float(u.flood)+float(u.flood_rate)*dt
			# The hull settles visibly as it fills.
			u["altitude"]=-FLOOD_DRAFT*minf(1.0,float(u.flood))
			if float(u.flood)>=1.0:
				u.hp=0.0
				_report(sim,u,"sunk","%s flooded and sank")
				_lost(sim,u)
			elif float(u.flood_rate)>0.0:active=true
		if not active or not sim.alive(u):list.remove_at(i)
	return impacts

static func _descend(sim,u:Dictionary,dt:float,impacts:Array)->void:
	var spin:bool=u.crash=="spin"
	u["altitude"]=maxf(0.0,float(u.get("altitude",sim.definitions[u.kind].altitude))-(CRASH_DESCENT if spin else LANDING_DESCENT)*dt)
	if spin:u.facing=u.facing.rotated(dt*5.0)
	u.state="GOING DOWN"
	if float(u.altitude)>0.0:return
	u.hp=0.0
	var water:bool=sim.terrain.is_water(u.pos)
	if spin:
		impacts.append({"pos":u.pos,"radius":CRASH_BLAST.radius,"damage":CRASH_BLAST.damage,"structure":CRASH_BLAST.structure,"team":u.team,"kind":"crash"})
		_report(sim,u,"crashed","%s crashed")
	else:
		_report(sim,u,"forced_landing","%s forced down · crew safe" if not water else "%s ditched at sea")
		u["lost_quiet"]=true
	if not water:
		# The airframe stays where it came down and blocks vehicles like a wreck.
		if not sim.has_meta(WRECKS):sim.set_meta(WRECKS,[])
		u["wrecked"]=true
		sim.get_meta(WRECKS).append({"id":u.id,"kind":u.kind,"team":u.team,"pos":u.pos,"facing":u.facing,"radius":float(sim.definitions[u.kind].radius)*0.7,"abandoned":not spin})
	_lost(sim,u)

# Bookkeeping for a loss that did not come from resolve_shot.
static func _lost(sim,u:Dictionary)->void:
	if u.get("lost_counted",false):return
	u["lost_counted"]=true
	if not u.get("lost_quiet",false):sim.events.append({"type":"destroyed","kind":u.kind,"pos":u.pos,"visible":u.visible})
	if u.team==1:sim.kills+=1
	else:sim.losses+=1

static func _pick(rng:RandomNumberGenerator,weights:Dictionary,heavy:bool)->String:
	var total:=0.0
	for key in weights:
		if heavy or key!="catastrophic":total+=float(weights[key])
	var roll:=rng.randf()*total
	for key in weights:
		if not heavy and key=="catastrophic":continue
		roll-=float(weights[key])
		if roll<0.0:return key
	return "crew"

# Integrity loss that empties the bar also destroys the vehicle (wreck).
static func _finish(sim,target:Dictionary,damage:float)->float:
	if target.hp-damage<=0.0:
		if target.hp>0.0:_event(sim,target,"destroyed")
		var land:bool=sim.definitions[target.kind].domain=="land"
		if land and not sim.terrain.is_water(target.pos):
			if not sim.has_meta(WRECKS):sim.set_meta(WRECKS,[])
			target["wrecked"]=true
			sim.get_meta(WRECKS).append({"id":target.id,"kind":target.kind,"team":target.team,"pos":target.pos,"facing":target.facing,"radius":float(sim.definitions[target.kind].radius),"abandoned":target.get("abandoned",false)})
			_event(sim,target,"wreck")
		return maxf(damage,target.hp)
	return damage

static func _event(sim,target:Dictionary,effect:String,penetrated:bool=true)->void:
	sim.events.append({"type":"vehicle_damage","unit":target.id,"kind":target.kind,"team":target.team,"effect":effect,"penetrated":penetrated,"pos":target.pos,"visible":target.visible})

static func _report(sim,target:Dictionary,effect:String,text:String,penetrated:bool=true)->void:
	_event(sim,target,effect,penetrated)
	if target.team==0:sim.events.append({"type":"warning","text":text % LABEL.get(target.kind,str(target.kind).capitalize())})

# can_fire gate. A knocked-out gun cannot fire. An injured crew reloads and
# acquires more slowly, and a buttoned-up crew acquires more slowly; both are
# applied once per shot / per new target, so the check stays idempotent.
static func weapon_ready(sim,u:Dictionary)->bool:
	if not u.has("crew"):return true
	if u.firepower_kill or u.abandoned or u.has("crash"):return false
	var missing:int=int(u.crew_full)-int(u.crew)
	if missing>0 and float(u.get("last_shot",-100.0))>float(u.reload_mark):
		u.reload_mark=u.last_shot
		u.cooldown=float(u.cooldown)+float(sim.definitions[u.kind].interval)*RELOAD_PENALTY*missing
	var aim_target:int=int(u.get("aim_target",-1))
	if aim_target!=int(u.aim_mark):
		u.aim_mark=aim_target
		var delay:float=ACQUIRE_PENALTY*missing+(BUTTONED_ACQUIRE if sim.time<float(u.buttoned_until) else 0.0)
		if aim_target>=0 and delay>0.0:u.aim_time=float(u.aim_time)-delay
	return true

# move_unit entry: 0 = immobilised (orders dropped, it stays put and fights),
# otherwise the speed scale (a damaged gunship flies slower). Vehicles whose
# next legs cross a wreck re-plan round it (at most once a second).
static func before_move(sim,u:Dictionary)->float:
	if u.has("crash"):
		u.orders.clear()
		u.path.clear()
		u.speed_now=0.0
		return 0.0
	if not u.get("mobility_kill",false):
		if sim.has_meta(WRECKS) and u.members.is_empty() and not u.path.is_empty():_route_round_wrecks(sim,u)
		# A flooding hull wallows: slower as it fills.
		return 1.0-0.6*clampf(float(u.get("flood",0.0)),0.0,1.0)
	if sim.definitions[u.kind].domain=="air":return DAMAGED_FLIGHT
	u.orders.clear()
	u.path.clear()
	if not u.maneuver.is_empty():u.maneuver.arrived=true
	u.speed_now=0.0
	u.state="IMMOBILISED"
	u.reason="Immobilised · still firing"
	return 0.0

static func _route_round_wrecks(sim,u:Dictionary)->void:
	var d:Dictionary=sim.definitions[u.kind]
	if d.domain!="land" or d.get("structure",false):return
	var legs:Array=[u.pos]
	legs.append_array(u.path.slice(0,3))
	var bodies:Array=[]
	var crossing:=false
	for wreck in sim.get_meta(WRECKS):
		var clearance:float=float(d.radius)+float(wreck.radius)
		var gap:float=u.pos.distance_to(wreck.pos)
		if gap>clearance+60.0:continue
		# A hull already touching a wreck may still plan away from it.
		bodies.append({"pos":wreck.pos,"radius":minf(clearance+0.3,gap-0.05)})
		for k in range(1,legs.size()):
			if not crossing and Geometry2D.get_closest_point_to_segment(wreck.pos,legs[k-1],legs[k]).distance_to(wreck.pos)<clearance:crossing=true
	if not crossing or sim.time<float(u.get("wreck_route_at",-1.0)):return
	u["wreck_route_at"]=sim.time+0.5
	var detour:Array[Vector2]=sim.terrain.path(u.pos,u.path.back(),d.domain,float(d.radius),bodies,sim.terrain.mobility_profile(u.kind))
	if detour.is_empty():return
	u.path=detour
	# The hull's look-ahead cannot see wrecks: keep it from cutting the detour.
	u["look_ahead_at"]=sim.time+3.0

static func wrecks(sim)->Array:
	return sim.get_meta(WRECKS) if sim.has_meta(WRECKS) else []

# movement_clear: wrecks are solid for land vehicles. A move that opens
# distance from a wreck is always allowed, so nothing is trapped against one.
static func wreck_blocks(sim,u:Dictionary,to:Vector2)->bool:
	var d:Dictionary=sim.definitions[u.kind]
	if d.domain!="land" or d.get("structure",false):return false
	for wreck in sim.get_meta(WRECKS):
		var clearance:float=float(d.radius)+float(wreck.radius)
		var gap:float=to.distance_squared_to(wreck.pos)
		if gap<clearance*clearance and gap<u.pos.distance_squared_to(wreck.pos):return true
	return false

# Hard cover behind a wreck: within `reach` of the hull and the hull lies
# between the position and the threat. For the infantry damage path to consult.
static func wreck_cover(sim,pos:Vector2,threat:Vector2,reach:float=3.5)->bool:
	for wreck in wrecks(sim):
		var to_wreck:Vector2=wreck.pos-pos
		if to_wreck.length()>float(wreck.radius)+reach:continue
		if to_wreck.dot(threat-pos)>0.0 and Geometry2D.get_closest_point_to_segment(wreck.pos,pos,threat).distance_to(wreck.pos)<float(wreck.radius):return true
	return false

# Field repair (FieldOps repair-point tick, same safety rules as its hp heal):
# one knocked-out component at a time, tracks/engine first, then the main gun,
# then each crew casualty replaced. Progress persists if the work is interrupted.
const REPAIR_SECONDS:={"mobility":20.0,"firepower":25.0,"crew":40.0}
static func field_repair(sim,u:Dictionary,dt:float)->void:
	if not u.has("crew") or u.abandoned:return
	var job:=""
	if u.mobility_kill:job="mobility"
	elif u.firepower_kill:job="firepower"
	elif int(u.crew)<int(u.crew_full):job="crew"
	if job.is_empty():
		u.erase("repair_job");u.erase("repair_done")
		return
	if u.get("repair_job","")!=job:
		u["repair_job"]=job
		u["repair_done"]=0.0
	u.repair_done=float(u.repair_done)+dt
	if float(u.repair_done)<float(REPAIR_SECONDS[job]):return
	u.erase("repair_job");u.erase("repair_done")
	match job:
		"mobility":
			u.mobility_kill=false
			if u.state=="IMMOBILISED":u.state="READY";u.reason="Repaired"
			_report(sim,u,"repaired_mobility","%s tracks repaired · mobile again")
		"firepower":
			u.firepower_kill=false
			_report(sim,u,"repaired_firepower","%s main gun repaired")
		"crew":
			u.crew=int(u.crew)+1
			_report(sim,u,"repaired_crew","%s crew replacement arrived")
