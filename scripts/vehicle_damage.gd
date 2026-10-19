extends RefCounted

# Component damage for vehicles (tank, IFV, corvette, gunship). A hit lands on
# a hull face and a zone of it (hit location, below), then either fails to
# penetrate or penetrates and may knock out one component:
#   mobility     tracks/engine: a land or sea hull cannot move (it still fires);
#                a gunship is damaged and flies slower
#   firepower    main weapon disabled
#   crew         a casualty: slower reload and target acquisition; the last
#                casualty bails the crew out (gunship: crashes)
#   catastrophic ammunition cook-off: destroyed at once
# A heavy round that does not penetrate still does harm, by zone: it can break
# a track (mobility), jam or bend the gun (firepower), smash the sights (optics:
# the gunner falls back to the auxiliary sight, less accurate) or shake the crew
# (shock: a lost aim and a slower reload). Light rounds can only scar sights.
# HP stays an overall integrity bar. Abandoned and destroyed land vehicles stay
# on the map as wrecks that block vehicles. Penetration and outcome rolls use
# a dedicated seeded RNG so they never shift the shared combat RNG stream.
#
# Hit location. A shot arriving at angle t off the hull axis strikes a face in
# proportion to its projected area: front cos(t)*A_front, side |sin(t)|*A_side,
# rear -cos(t)*A_rear (a tank hull is about twice as long as it is wide, so a
# hull yawed 20 degrees already takes about 4 in 10 hits on the side). The plate
# is met at incidence t (front), 90-t (side) or 180-t (rear): its line-of-sight
# thickness grows as 1/cos(incidence), so grazing hits on the side glance off.
# Each face is a set of zones with a share of the hits: a frontal arc is not
# uniform (glacis and turret face are strong; the lower plate, the mantlet and
# turret ring are weak spots that a fair share of hits find).
#
# Top attack. A Javelin beyond its top-attack minimum range (units.json atgm
# top_attack_min_m: 150 m in FM 3-21.71 App. F; direct attack 65 m) climbs and
# dives onto the roof, whatever the hull's facing: the shot lands on the roof
# zones (face ROOF) met at ROOF_INCIDENCE. Roofs are the thinnest plates on a
# tank (turret roof ~40-70 mm, engine deck thinner; see units.json armor_zones
# roof); rows without a roof take their thinnest face.

# Armour/crew/effect data live in the vehicle rows of units.json:
#   armor_mm [front, side, rear] (uniform plates when a row has no zones),
#   armor_zones {front|side|rear|roof: [{zone, share, mm, nonpen {effect: chance},
#     pen {effect: chance} (behind-armour effects of a penetration, _pen_effects)}]},
#   hull_area [front, side, rear], crew, nonpen_damage, damage_effects {weights}.
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
# Hull arcs from the target's facing (labels only: front within 60 degrees,
# rear within ~53). Hit location itself blends faces by projected area.
const FRONT_DOT:=0.5
const REAR_DOT:=-0.6
# Face index of the roof (zones() tables are [front, side, rear, roof]).
const ROOF:=3
# Terminal dive: the roof is met about 35 degrees off its normal (assumed).
const ROOF_INCIDENCE:=0.82
# Default projected area [front, side, rear] for rows without hull_area.
const HULL_AREA:=[1.0,1.0,1.0]
# Line-of-sight thickness grows as 1/cos(incidence) up to this factor (~78
# degrees); beyond it rods and jets glance off.
const OBLIQUITY_CAP:=5.0
# pen/armour ratio below LOW never penetrates, above LOW+SPAN always does.
const RATIO_LOW:=0.75
const RATIO_SPAN:=0.5
# Rows without zone data: a heavy round that fails to penetrate can still
# break a track.
const TRACK_HIT:=0.05
# Non-penetrating effects. Light rounds only scar sights, at this fraction of
# the zone's optics chance. Damaged sights scale the gunner's hit chance.
const LIGHT_OPTICS:=0.5
const OPTICS_ACCURACY:=0.6
# Crew shock: suppression and an extra fraction of the reload interval.
const SHOCK_SUPPRESSION:=0.7
const SHOCK_RELOAD:=0.5
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

# Hit-location table of a hull kind: [front, side, rear] zone lists. Rows
# without armor_zones are one uniform plate per face (armor_mm); their heavy
# non-penetrating hits keep the legacy track-break chance on land.
static func zones(sim,kind:String)->Array:
	if not sim.has_meta("armor_zone_cache"):sim.set_meta("armor_zone_cache",{})
	var cache:Dictionary=sim.get_meta("armor_zone_cache")
	if cache.has(kind):return cache[kind]
	var d:Dictionary=sim.definitions[kind]
	var table:Array=[]
	var authored:Dictionary=d.get("armor_zones",{})
	var legacy:Dictionary={"mobility":TRACK_HIT} if d.domain=="land" else {}
	for face in 3:
		var name:String=["front","side","rear"][face]
		var list:Array=[]
		if authored.has(name):
			for zone in authored[name]:list.append({"zone":str(zone.get("zone",name)),"share":float(zone.share),"mm":maxf(1.0,float(zone.mm)),"nonpen":zone.get("nonpen",{}),"pen":zone.get("pen",{})})
		else:list.append({"zone":name,"share":1.0,"mm":maxf(1.0,float(d.armor_mm[face])),"nonpen":legacy,"pen":{}})
		table.append(list)
	var roof:Array=[]
	for zone in authored.get("roof",[]):roof.append({"zone":str(zone.get("zone","roof")),"share":float(zone.share),"mm":maxf(1.0,float(zone.mm)),"nonpen":zone.get("nonpen",{}),"pen":zone.get("pen",{})})
	if roof.is_empty():roof.append({"zone":"roof","share":1.0,"mm":maxf(1.0,float(d.armor_mm.min())),"nonpen":legacy,"pen":{}})
	table.append(roof)
	cache[kind]=table
	return table

# Faces the shot can land on: [[face, weight, cos(incidence)], ...] with the
# weights summing to 1 (projected area seen from `source`).
static func face_weights(sim,target:Dictionary,source:Vector2)->Array:
	var offset:Vector2=source-target.pos
	if offset.length_squared()<0.0001:return [[0,1.0,1.0]]
	var axis:Vector2=target.facing.normalized()
	var direction:Vector2=offset.normalized()
	var c:float=axis.dot(direction)
	var s:float=absf(axis.cross(direction))
	var area:Array=sim.definitions[target.kind].get("hull_area",HULL_AREA)
	var result:Array=[]
	var total:=0.0
	for entry in [[0,maxf(c,0.0)*float(area[0]),c],[1,s*float(area[1]),s],[2,maxf(-c,0.0)*float(area[2]),-c]]:
		if entry[1]>0.0001:result.append(entry);total+=float(entry[1])
	for entry in result:entry[1]=float(entry[1])/total
	return result

# Faces a shot from `u` can land on: the roof alone for a top attack.
static func faces(sim,u:Dictionary,target:Dictionary)->Array:
	if u.get("attack","")=="top":return [[ROOF,1.0,ROOF_INCIDENCE]]
	return face_weights(sim,target,u.pos)

# Whether weapon row `d` attacks `target` from above at `distance` m: armoured
# land and sea hulls beyond the top-attack minimum range (game units scale
# range_m to range).
static func top_attack(sim,d:Dictionary,target:Dictionary,distance:float)->bool:
	if not d.has("top_attack_min_m") or not tracked(sim,target) or sim.definitions[target.kind].domain=="air":return false
	return distance>=float(d.top_attack_min_m)*float(d.range)/float(d.range_m)

# Chance that `pen` mm defeats a zone met at incidence cos `incidence`.
static func zone_chance(pen:float,zone:Dictionary,incidence:float)->float:
	var plate:float=float(zone.mm)*minf(1.0/maxf(incidence,0.0001),OBLIQUITY_CAP)
	return clampf((pen/plate-RATIO_LOW)/RATIO_SPAN,0.0,1.0)

# Overall penetration chance of a hit: faces by projected area, zones by share.
static func penetration_chance(sim,u:Dictionary,target:Dictionary)->float:
	if not sim.definitions[target.kind].has("armor_mm"):return 1.0
	var pen:float=penetration(sim,u,target)
	var table:Array=zones(sim,target.kind)
	var p:=0.0
	for entry in faces(sim,u,target):
		for zone in table[entry[0]]:p+=float(entry[1])*float(zone.share)*zone_chance(pen,zone,float(entry[2]))
	return clampf(p,0.0,1.0)

# One hit's location: {zone, p (its penetration chance)}.
static func roll_location(sim,u:Dictionary,target:Dictionary,rng:RandomNumberGenerator)->Dictionary:
	var options:Array=faces(sim,u,target)
	var face:Array=options[0]
	var roll:=rng.randf()
	for entry in options:
		face=entry
		roll-=float(entry[1])
		if roll<0.0:break
	var list:Array=zones(sim,target.kind)[face[0]]
	var zone:Dictionary=list[0]
	roll=rng.randf()
	for candidate in list:
		zone=candidate
		roll-=float(candidate.share)
		if roll<0.0:break
	return {"zone":zone,"p":zone_chance(penetration(sim,u,target),zone,float(face[2]))}

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
	# `amount` carries the expected scale over all locations; the hit itself
	# lands on one zone with its own penetration chance.
	var p:=penetration_chance(sim,u,target)
	var nonpen:float=float(td.get("nonpen_damage",0.1))
	var base:float=amount/(p+(1.0-p)*nonpen)
	var land:bool=td.domain=="land"
	if land:target.buttoned_until=sim.time+BUTTON_SECONDS
	var location:Dictionary=roll_location(sim,u,target,rng)
	if rng.randf()>=float(location.p):
		if land:_nonpen_effect(sim,target,location.zone,spec,rng)
		else:_event(sim,target,"ricochet",false)
		return _finish(sim,target,base*nonpen)
	var damage:float=base
	if not location.zone.pen.is_empty():return _pen_effects(sim,target,location.zone,spec,rng,damage)
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
				if _crew_hit(sim,target,damage,1):return _finish(sim,target,0.0)
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

# Crew casualties; true when the last crew member is lost (the land crew bails
# out, the hull is abandoned; an aircraft crashes).
static func _crew_hit(sim,target:Dictionary,damage:float,count:int)->bool:
	var td:Dictionary=sim.definitions[target.kind]
	target.crew=maxi(0,int(target.crew)-count)
	target.suppression=maxf(target.suppression,0.9)
	target.cooldown=maxf(float(target.cooldown),0.0)+float(td.interval)
	target.aim_time=0.0
	if target.crew>0:
		_report(sim,target,"crew","%s crew casualty" if count==1 else "%s crew casualties")
		return false
	# The hull's remaining integrity, kept for re-crewing.
	if td.domain!="air":target["abandoned_hp"]=maxf(0.0,float(target.hp)-damage)
	target.hp=0.0
	if td.domain=="air":_report(sim,target,"catastrophic","%s pilot lost · crashed")
	else:
		target.abandoned=true
		_report(sim,target,"abandoned","%s crew bailed out · vehicle abandoned")
	return true

# Behind-armour effects of a penetration, by the zone struck (units.json
# armor_zones pen {effect: chance}). Each effect is rolled independently, its
# chance scaled by the round's behind-armour effect (PENETRATION effect: a
# large HEAT jet or an APFSDS rod 1.0, autocannon 0.3), so one penetration can
# wound the crew and start a fire. "catastrophic" is stowed ammunition
# detonating (heavy rounds only): the vehicle is destroyed (rows with
# ammo_vented: the bustle's blow-off panels vent it, the crew escapes, the hull
# burns out). "crew" is one casualty, a second with SECOND_CASUALTY (heavy
# rounds). The crew field is an abstraction of a real crew (2 for a 4-man
# tank), so one casualty here is about two crewmen; WWII US data put about one
# casualty per lost five-man tank (Dupuy, 1.28 if it burned), so a crew
# compartment penetration costs about 0.5-1 abstract casualty.
const SECOND_CASUALTY:=0.15
static func _pen_effects(sim,target:Dictionary,zone:Dictionary,spec:Dictionary,rng:RandomNumberGenerator,damage:float)->float:
	var td:Dictionary=sim.definitions[target.kind]
	var scale:float=float(spec.effect)
	var rolled:Dictionary={}
	for key in zone.pen:
		if rng.randf()<float(zone.pen[key])*scale:rolled[key]=true
	if rolled.has("catastrophic") and spec.heavy:
		target.hp=0.0
		if td.get("ammo_vented",false):_report(sim,target,"catastrophic","%s ammunition fire vented · crew escaped · knocked out")
		else:_report(sim,target,"catastrophic","%s destroyed · ammunition cook-off")
		return _finish(sim,target,0.0)
	if rolled.has("crew") and _crew_hit(sim,target,damage,2 if spec.heavy and rng.randf()<SECOND_CASUALTY else 1):return _finish(sim,target,0.0)
	if rolled.has("mobility") and not target.mobility_kill:
		target.mobility_kill=true
		_report(sim,target,"mobility","%s immobilised")
	if rolled.has("firepower") and not target.firepower_kill:
		target.firepower_kill=true
		_report(sim,target,"firepower","%s main gun disabled")
	if rolled.has("fire") and float(target.get("fire_until",-1.0))<sim.time:
		target["fire_until"]=sim.time+rng.randf_range(FIRE_SECONDS.x,FIRE_SECONDS.y)
		_hazard(sim,target)
		_report(sim,target,"fire","%s on fire")
	if rolled.is_empty():_event(sim,target,"penetration")
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

# Enemy vehicles the player can see: toast the effects that change the fight
# (not crew casualties or repairs), at most one per ENEMY_NOTICE_GAP seconds.
const ENEMY_NOTICE:=["mobility","firepower","abandoned","catastrophic","fire","flooding","tail_rotor","hydraulics","sunk","crashed","forced_landing"]
const ENEMY_NOTICE_GAP:=3.0
static func _report(sim,target:Dictionary,effect:String,text:String,penetrated:bool=true)->void:
	_event(sim,target,effect,penetrated)
	var label:String=LABEL.get(target.kind,str(target.kind).capitalize())
	if target.team==0:sim.events.append({"type":"warning","text":text % label,"notice":"vehicle","effect":effect,"kind":target.kind})
	elif target.get("visible",false) and effect in ENEMY_NOTICE and sim.time>=float(sim.get_meta("enemy_vehicle_notice",-INF)):
		sim.set_meta("enemy_vehicle_notice",sim.time+ENEMY_NOTICE_GAP)
		sim.events.append({"type":"warning","text":"Enemy "+text % label.to_lower(),"notice":"low"})

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
	if d.domain!="land" or d.get("structure",false) or sim.time<float(u.get("wreck_route_at",-1.0)):return
	var legs:Array=[u.pos]
	legs.append_array(u.path.slice(0,3))
	var crossing:=false
	# A pusher drives on into light wrecks and shoves them (push_wreck).
	var can_push:bool=pusher(sim,u)
	for wreck in sim.get_meta(WRECKS):
		if can_push and not solid_wreck(sim,wreck,true):continue
		var clearance:float=float(d.radius)+float(wreck.radius)
		if u.pos.distance_to(wreck.pos)>clearance+60.0:continue
		for k in range(1,legs.size()):
			if Geometry2D.get_closest_point_to_segment(wreck.pos,legs[k-1],legs[k]).distance_to(wreck.pos)<clearance:crossing=true;break
		if crossing:break
	if not crossing:return
	u["wreck_route_at"]=sim.time+0.5
	var bodies:Array=[]
	for wreck in sim.get_meta(WRECKS):
		if can_push and not solid_wreck(sim,wreck,true):continue
		var clearance:float=float(d.radius)+float(wreck.radius)
		var gap:float=u.pos.distance_to(wreck.pos)
		if gap>clearance+60.0:continue
		# A hull already touching a wreck may still plan away from it.
		bodies.append({"pos":wreck.pos,"radius":minf(clearance+0.3,gap-0.05)})
	# A goal inside a wreck's margin can never be routed to (path() publishes no
	# edge ending inside an avoided body): the wreck came down on it after the
	# order, so the driver stops beside the wreck instead (an attack keeps its
	# target and closes on the target's side). No clear spot: skip the doomed
	# search, which tanks holding a post beside a wreck otherwise repeat.
	var goal:Vector2=u.path.back()
	var order:Dictionary=u.maneuver if not u.maneuver.is_empty() else (u.orders[0] if not u.orders.is_empty() else {})
	var attack:bool=order.get("mode","")=="attack"
	if not sim.terrain.avoids_bodies(goal,goal,bodies):
		goal=clear_goal(sim,u,goal,u.pos,not attack)
		if goal.x<0 or not sim.terrain.avoids_bodies(goal,goal,bodies):
			u["wreck_route_at"]=sim.time+3.0
			return
	var detour:Array[Vector2]=sim.terrain.path(u.pos,goal,d.domain,float(d.radius),bodies,sim.terrain.mobility_profile(u.kind))
	if detour.is_empty():
		# No way to the spot beside the wreck: retry later, not every 0.5 s.
		if goal!=u.path.back():u["wreck_route_at"]=sim.time+3.0
		return
	if goal!=u.path.back() and not attack and order.has("pos") and order.pos.distance_to(u.path.back())<1.0:
		if u.intent.get("pos")==order.pos:u.intent.pos=goal
		order.pos=goal
	u.path=detour
	# The hull's look-ahead cannot see wrecks: keep it from cutting the detour.
	u["look_ahead_at"]=sim.time+3.0

static func wrecks(sim)->Array:
	return sim.get_meta(WRECKS) if sim.has_meta(WRECKS) else []

# Land vehicles (not infantry, not structures) cannot stop in a wreck's margin.
static func wreck_bound(sim,u:Dictionary)->bool:
	var d:Dictionary=sim.definitions[u.kind]
	return u.members.is_empty() and d.domain=="land" and not d.get("structure",false)

# The wreck whose margin (hull radius + wreck radius) holds `p`, else {};
# `list` narrows the search (e.g. to wrecks_near).
static func wreck_at(sim,p:Vector2,radius:float,list:Variant=null)->Dictionary:
	for wreck in (wrecks(sim) if list==null else list):
		var clearance:float=radius+float(wreck.radius)
		if p.distance_squared_to(wreck.pos)<clearance*clearance:return wreck
	return {}

# Wrecks whose margin reaches within `reach` of `p`.
static func wrecks_near(sim,p:Vector2,radius:float,reach:float)->Array:
	return wrecks(sim).filter(func(wreck):return p.distance_to(wreck.pos)<reach+radius+float(wreck.radius))

# A goal inside a wreck's margin resolves to the nearest clear spot round the
# wreck, as a driver pulls up beside a burnt-out hull: straight out from the
# wreck through the goal, leaning toward `from` (the near side) when `near`,
# then turning round the wreck and stepping out until a spot is clear of every
# wreck and drivable. Returns `goal` when already clear, (-1,-1) when no spot.
const WRECK_STOP_SLACK:=0.35
static func clear_goal(sim,u:Dictionary,goal:Vector2,from:Vector2,near:bool=true)->Vector2:
	if not sim.has_meta(WRECKS) or not wreck_bound(sim,u):return goal
	var radius:float=float(sim.definitions[u.kind].radius)
	var wreck:Dictionary=wreck_at(sim,goal,radius)
	if wreck.is_empty():return goal
	var clearance:float=radius+float(wreck.radius)
	var away:Vector2=(goal-wreck.pos)/clearance
	if near:away+=(from-wreck.pos).normalized()*0.5
	if away.length_squared()<0.0001:away=(from-wreck.pos).normalized() if from!=wreck.pos else Vector2.RIGHT
	var heading:float=away.angle()
	for ring in 4:
		var reach:float=clearance+WRECK_STOP_SLACK+ring*1.5
		for k in 16:
			# 0, +1, -1, +2, -2, ... sixteenths of a turn round the wreck.
			var turn:int=(k+1)/2*(1 if k%2==1 else -1)
			var p:Vector2=wreck.pos+Vector2.from_angle(heading+turn*TAU/16.0)*reach
			if wreck_at(sim,p,radius).is_empty() and sim.terrain.traversable(p,"land",radius):return p
	return Vector2(-1,-1)

# movement_clear: wrecks are solid for land vehicles. A move that opens
# distance from a wreck is always allowed, so nothing is trapped against one.
static func wreck_blocks(sim,u:Dictionary,to:Vector2)->bool:
	var d:Dictionary=sim.definitions[u.kind]
	if d.domain!="land" or d.get("structure",false):return false
	var radius:float=float(d.radius)
	for wreck in sim.get_meta(WRECKS):
		var clearance:float=radius+float(wreck.radius)
		var gap:float=to.distance_squared_to(wreck.pos)
		if gap<clearance*clearance and gap<u.pos.distance_squared_to(wreck.pos):return true
	return false

# Shoving wrecks. A heavy tracked hull (a tank, ~60-70 t) can nose a LIGHT
# wreck (an IFV/AA hull ~25-30 t, a truck or harvester, a downed helicopter)
# aside at a crawl; a tank wreck is too heavy for a tank to move. Masses are
# assumed typical values for each hull class (t); unlisted kinds count as
# WRECK_DEFAULT_TONNES (heavy enough not to be shoved, too light to shove).
const TONNES:={"tank":62.0,"aa":28.0,"harvester":18.0,"helo":8.0}
const WRECK_DEFAULT_TONNES:=40.0
const PUSHER_TONNES:=50.0
const PUSHABLE_TONNES:=35.0
# A real shove runs at 1-2 m/s; on the game's compressed scale (a tank cruises
# at 5.4 u/s) that is about 1 u/s, after PUSH_DELAY s of taking up the slack.
const PUSH_SPEED:=1.0
const PUSH_DELAY:=0.6
# The wreck slews a little as it is shoved off-centre (rad/s).
const PUSH_SLEW:=0.25
# A wreck that cannot be shoved anywhere is planned round for a while.
const PUSH_STUCK_SECONDS:=4.0
# Field nav follows a shoved wreck in steps of this many units (field_ops
# sync_obstacles re-keys on WRECK_REVISION), not every tick.
const PUSH_NAV_STEP:=0.5
# A hull nosing into a wreck shoves it within PUSH_TOUCH of its margin; one
# that is already stopped shoves within PUSH_REACH, as the wreck's field nav
# block (which also holds the hull off) trails it by up to PUSH_NAV_STEP and
# its box corners stand a little proud of the margin.
const PUSH_TOUCH:=0.15
const PUSH_REACH:=PUSH_NAV_STEP+0.2
const WRECK_REVISION:="vehicle_wreck_revision"
const PUSH_NOTE_GAP:=6.0
const PUSH_SOUND_GAP:=1.5

static func tonnes(kind:String)->float:
	return float(TONNES.get(kind,WRECK_DEFAULT_TONNES))

static func light_wreck(wreck:Dictionary)->bool:
	return tonnes(str(wreck.kind))<=PUSHABLE_TONNES

# A mobile heavy tracked hull that can shove light wrecks.
static func pusher(sim,u:Dictionary)->bool:
	if not u.members.is_empty() or u.get("mobility_kill",false) or tonnes(str(u.kind))<PUSHER_TONNES:return false
	var d:Dictionary=sim.definitions[u.kind]
	return d.domain=="land" and not d.get("structure",false) and sim.terrain.mobility_profile(u.kind)=="tracked"

# Whether a wreck stops a hull's route (`can_push`: pusher(sim,u)). A pusher
# plans through a light wreck unless engineers are working on it or it was
# found jammed a moment ago.
static func solid_wreck(sim,wreck:Dictionary,can_push:bool)->bool:
	return not (can_push and light_wreck(wreck) and not wreck.has("cleared_by") and sim.time>=float(wreck.get("stuck_until",-INF)))

# Movement step (simulation hull_step / move_unit): a pusher whose step `to`
# (heading `axis`) noses into light wrecks ahead shoves the nearest aside.
# Returns PUSH_NONE, PUSH_HOLD (taking up the slack: the hull holds) or
# PUSH_SHOVE (the wreck moved: the hull may creep after it at PUSH_SPEED);
# while pushing the caller does not count the hull jammed. Off-centre wrecks go
# out to their side; a centred one to whichever side is open; straight ahead
# only when the hull has no way to slip past. A wreck that cannot move anywhere
# is marked stuck (planned round) and the hull is left blocked.
enum {PUSH_NONE,PUSH_HOLD,PUSH_SHOVE}
static func push_wreck(sim,u:Dictionary,to:Vector2,axis:Vector2,dt:float,slack:float=PUSH_TOUCH)->int:
	if not sim.has_meta(WRECKS) or u.get("reversing",false) or not pusher(sim,u):return PUSH_NONE
	var radius:float=float(sim.definitions[u.kind].radius)
	var wreck:Dictionary={}
	var nearest:=INF
	for other in sim.get_meta(WRECKS):
		var gap:float=to.distance_squared_to(other.pos)
		if gap>=u.pos.distance_squared_to(other.pos) or (other.pos-u.pos).dot(axis)<=0.0:continue
		var clearance:float=radius+float(other.radius)
		# Any heavy or unmovable wreck in the way stops the shove.
		if solid_wreck(sim,other,true):
			if gap<clearance*clearance:return PUSH_NONE
			continue
		var reach:float=clearance+slack
		if gap<reach*reach and gap<nearest:wreck=other;nearest=gap
	if wreck.is_empty():return PUSH_NONE
	var now:float=sim.time
	if int(u.get("push_id",-2))!=int(wreck.id) or now-float(u.get("push_seen",-INF))>0.5:u["push_since"]=now
	u["push_id"]=int(wreck.id)
	u["push_seen"]=now
	if now-float(u.push_since)<PUSH_DELAY:
		_pushing(sim,u,wreck,axis,false)
		return PUSH_HOLD
	var left:=Vector2(-axis.y,axis.x)
	var offset:float=(wreck.pos-u.pos).dot(left)
	var sides:Array=[signf(offset)] if absf(offset)>0.3 else [1.0,-1.0]
	var shove:float=PUSH_SPEED*dt
	for side in sides:
		var heading:Vector2=(axis*0.5+left*side).normalized()
		if _wreck_spot_clear(sim,u,wreck,wreck.pos+heading*shove):
			_move_wreck(sim,wreck,heading*shove,side*PUSH_SLEW*dt)
			_pushing(sim,u,wreck,heading,true)
			return PUSH_SHOVE
	# Straight ahead only when the hull cannot slip past (it pivots instead).
	var neighbors:Array=sim.movement_neighbors(u)
	var reach:float=maxf(0.3,radius*0.6)
	for angle in [0.55,-0.55,1.05,-1.05]:
		if sim.movement_clear(u,u.pos+axis.rotated(angle)*reach,neighbors):return PUSH_NONE
	if _wreck_spot_clear(sim,u,wreck,wreck.pos+axis*shove):
		_move_wreck(sim,wreck,axis*shove,0.0)
		_pushing(sim,u,wreck,axis,true)
		return PUSH_SHOVE
	wreck["stuck_until"]=now+PUSH_STUCK_SECONDS
	# Re-plan now: the route round it must not wait for the half-second throttle.
	u.erase("wreck_route_at")
	return PUSH_NONE

static func _pushing(sim,u:Dictionary,wreck:Dictionary,heading:Vector2,moved:bool)->void:
	u.state="PUSHING WRECK"
	u.reason="Shoving a wreck aside"
	u.speed_now=minf(float(u.speed_now),0.0 if not moved else PUSH_SPEED)
	# A shove is headway: the stall and jam clocks (simulation move_unit) must
	# not take the crawl for a jam and back the hull off mid-push.
	if u.has("stall_seen"):u.stall_at=sim.time
	if u.has("jam_seen"):u.jam_at=sim.time
	if not moved:return
	if sim.time>=float(u.get("push_sound_at",-INF)):
		u["push_sound_at"]=sim.time+PUSH_SOUND_GAP
		sim.events.append({"type":"crushed","prop":-1,"id":"wreck","heading":heading,"pos":wreck.pos,"visible":u.get("visible",true)})
	if u.team==0 and sim.time>=float(u.get("push_note_at",-INF)):
		u["push_note_at"]=sim.time+PUSH_NOTE_GAP
		sim.events.append({"type":"warning","text":"%s shoving a %s wreck aside" % [LABEL.get(u.kind,str(u.kind).capitalize()),LABEL.get(wreck.kind,str(wreck.kind).capitalize()).to_lower()],"notice":"drop"})

# A shoved wreck may not go into buildings, walls, water or off the map, nor
# into other wrecks, units or field works (a body it would close on). Kerbside
# furniture does not stop it (the wreck flattens it, like a tank).
static func _wreck_spot_clear(sim,u:Dictionary,wreck:Dictionary,p:Vector2)->bool:
	var body:float=float(wreck.radius)*0.7
	var terrain=sim.terrain
	if not terrain.inside(p) or terrain.is_water(p):return false
	# The wreck's own field nav block must not count against it.
	var blocks:Array=terrain.dynamic_blocks
	var at:int=blocks.find(wreck.get("nav_rect",Rect2())) if wreck.has("nav_rect") else -1
	if at>=0:blocks.remove_at(at)
	var saved:bool=terrain.crush_pass
	terrain.crush_pass=true
	var open:bool=terrain.traversable(p,"land",body)
	terrain.crush_pass=saved
	if at>=0:blocks.insert(at,wreck.nav_rect)
	if not open:return false
	for other in sim.get_meta(WRECKS):
		if is_same(other,wreck):continue
		var clearance:float=(float(wreck.radius)+float(other.radius))*0.7
		var gap:float=p.distance_squared_to(other.pos)
		if gap<clearance*clearance and gap<wreck.pos.distance_squared_to(other.pos):return false
	for other in sim.units:
		if other.id==u.id or not sim.alive(other) or sim.definitions[other.kind].domain!="land":continue
		if other.members.is_empty():
			var clearance:float=float(wreck.radius)+float(sim.definitions[other.kind].radius)
			var gap:float=p.distance_squared_to(other.pos)
			if gap<clearance*clearance and gap<wreck.pos.distance_squared_to(other.pos):return false
			continue
		if p.distance_squared_to(other.pos)>pow(body+8.0,2):continue
		for member in other.members:
			if member.hp<=0:continue
			var reach:float=body+float(member.get("body_radius",0.8))+0.3
			var gap:float=p.distance_squared_to(member.pos)
			if gap<reach*reach and gap<wreck.pos.distance_squared_to(member.pos):return false
	return true

static func _move_wreck(sim,wreck:Dictionary,shift:Vector2,slew:float)->void:
	wreck.pos+=shift
	wreck.facing=Vector2(wreck.facing).rotated(slew)
	for record in sim.terrain.crush_props(wreck.pos,float(wreck.radius)*0.7+0.1):
		sim.events.append({"type":"crushed","prop":record.prop,"id":record.id,"heading":shift.normalized(),"pos":record.rect.get_center(),"visible":true})
	# The dead hull carries the wreck's place (presentation, re-crewing).
	var hull:Dictionary=sim.get_unit(int(wreck.id))
	if not hull.is_empty() and hull.get("wrecked",false):
		hull.pos=wreck.pos
		hull.facing=wreck.facing
	if wreck.pos.distance_to(wreck.get("nav_at",Vector2.INF))>=PUSH_NAV_STEP:
		wreck["nav_at"]=wreck.pos
		sim.set_meta(WRECK_REVISION,int(sim.get_meta(WRECK_REVISION,0))+1)

# Engineers clearing a wreck (field_ops clear_wreck): a recovery job, longer
# for heavier hulls (assumed compressed times: a tank about 47 s, an IFV 27 s,
# a downed helicopter 15 s; field works take 4-10 s).
const CLEAR_BASE_SECONDS:=10.0
const CLEAR_SECONDS_PER_TONNE:=0.6
static func clear_seconds(wreck:Dictionary)->float:
	return CLEAR_BASE_SECONDS+CLEAR_SECONDS_PER_TONNE*tonnes(str(wreck.kind))

# The wreck whose hull lies under a ground point (within its radius + slack).
static func wreck_under(sim,pos:Vector2,slack:float=1.0)->Dictionary:
	var best:Dictionary={}
	var nearest:=INF
	for wreck in wrecks(sim):
		var gap:float=pos.distance_to(wreck.pos)
		if gap<=float(wreck.radius)+slack and gap<nearest:best=wreck;nearest=gap
	return best

static func wreck_by_id(sim,id:int)->Dictionary:
	if id<0:return {}
	for wreck in wrecks(sim):
		if int(wreck.id)==id:return wreck
	return {}

# A cleared wreck is hauled off: it stops blocking (field nav refreshed now)
# and its node hides; the scorch of its destruction stays on the ground.
static func remove_wreck(sim,wreck:Dictionary)->void:
	var list:Array=wrecks(sim)
	for k in range(list.size()-1,-1,-1):
		if is_same(list[k],wreck):list.remove_at(k)
	var hull:Dictionary=sim.get_unit(int(wreck.id))
	if not hull.is_empty():
		hull.wrecked=false
		hull["abandoned_hp"]=0.0
	if not sim.field_ops.is_empty():sim.FieldOps.sync_obstacles(sim)

# Hard cover behind a wreck: within `reach` of the hull and the hull lies
# between the position and the threat. For the infantry damage path to consult.
static func wreck_cover(sim,pos:Vector2,threat:Vector2,reach:float=3.5)->bool:
	for wreck in wrecks(sim):
		var to_wreck:Vector2=wreck.pos-pos
		if to_wreck.length()>float(wreck.radius)+reach:continue
		if to_wreck.dot(threat-pos)>0.0 and Geometry2D.get_closest_point_to_segment(wreck.pos,pos,threat).distance_to(wreck.pos)<float(wreck.radius):return true
	return false

# A land hull's non-penetrating hit: at most one effect from the struck zone's
# table (light rounds: sights only, at LIGHT_OPTICS), else a plain ricochet.
static func _nonpen_effect(sim,target:Dictionary,zone:Dictionary,spec:Dictionary,rng:RandomNumberGenerator)->void:
	var table:Dictionary=zone.nonpen
	var roll:=rng.randf()
	var effect:="ricochet"
	for key in table:
		if not spec.heavy and key!="optics":continue
		roll-=float(table[key])*(1.0 if spec.heavy else LIGHT_OPTICS)
		if roll<0.0:effect=key;break
	match effect:
		"mobility":
			if not target.mobility_kill:
				target.mobility_kill=true
				_report(sim,target,effect,"%s track broken · immobilised",false)
				return
		"firepower":
			if not target.firepower_kill:
				target.firepower_kill=true
				_report(sim,target,effect,"%s gun damaged · main gun disabled",false)
				return
		"optics":
			if not target.get("optics_kill",false):
				target["optics_kill"]=true
				target["accuracy"]=OPTICS_ACCURACY
				_report(sim,target,effect,"%s sights damaged",false)
				return
		"shock":
			var td:Dictionary=sim.definitions[target.kind]
			target.suppression=maxf(float(target.suppression),SHOCK_SUPPRESSION)
			target.cooldown=maxf(float(target.cooldown),0.0)+float(td.interval)*SHOCK_RELOAD
			target.aim_time=0.0
			_event(sim,target,effect,false)
			return
	_event(sim,target,"ricochet",false)

# Field repair (FieldOps repair-point tick, same safety rules as its hp heal):
# one knocked-out component at a time, tracks/engine first, then the main gun,
# then the sights, then each crew casualty replaced. Progress persists if the
# work is interrupted.
const REPAIR_SECONDS:={"mobility":20.0,"firepower":25.0,"optics":15.0,"crew":40.0}
static func field_repair(sim,u:Dictionary,dt:float)->void:
	if not u.has("crew") or u.abandoned:return
	var job:=""
	if u.mobility_kill:job="mobility"
	elif u.firepower_kill:job="firepower"
	elif u.get("optics_kill",false):job="optics"
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
		"optics":
			u.erase("optics_kill");u.erase("accuracy")
			_report(sim,u,"repaired_optics","%s sights replaced")
		"crew":
			u.crew=int(u.crew)+1
			_report(sim,u,"repaired_crew","%s crew replacement arrived")

# Re-crewing: an infantry section ordered to an abandoned hull (crew bailed out,
# integrity left) climbs in after RECREW_SECONDS beside it, out of heavy fire.
# Up to RECREW_CREW soldiers leave the section as the new crew (an understrength
# crew keeps the casualty penalties); an enemy hull is captured. The wreck gives
# way to a fresh unit with the hull's integrity and component damage, so the
# presentation builds a normal vehicle and the wreck bookkeeping stays simple.
const RECREW:="vehicle_recrew"
const RECREW_KINDS:=["rifle","atgm","engineer"]
const RECREW_SECONDS:=4.0
const RECREW_REACH:=4.0
const RECREW_CREW:=2
# Heavy fire pauses the work: section suppression, or hit within RECREW_QUIET s.
const RECREW_SUPPRESSION:=0.5
const RECREW_QUIET:=1.5
const RECREW_GIVE_UP:=3.0
# Wound state of a soldier who left the section as crew: hp 0, never drawn,
# never a casualty or a body.
const BOARDED:="CREW"

static func recrewable(sim,hull:Dictionary)->bool:
	return not hull.is_empty() and not sim.alive(hull) and hull.get("abandoned",false) and hull.get("wrecked",false) and float(hull.get("abandoned_hp",0.0))>0.0

# The re-crewable hull under a ground point (within its wreck radius + slack).
static func abandoned_at(sim,pos:Vector2,slack:float=1.0)->Dictionary:
	var best:Dictionary={}
	var nearest:=INF
	for wreck in wrecks(sim):
		var gap:float=pos.distance_to(wreck.pos)
		if gap>float(wreck.radius)+slack or gap>=nearest:continue
		var hull:Dictionary=sim.get_unit(int(wreck.id))
		if recrewable(sim,hull):
			best=hull
			nearest=gap
	return best

static func can_recrew(sim,section:Dictionary)->bool:
	if not sim.alive(section) or section.kind not in RECREW_KINDS or section.get("combat_ineffective",false):return false
	for member in section.members:
		if member.hp>0:return true
	return false

# Sends the nearest eligible section among `ids` to the hull. Returns 1 if sent.
static func order_recrew(sim,ids:Array,hull_id:int)->int:
	var hull:Dictionary=sim.get_unit(hull_id)
	if not recrewable(sim,hull):return 0
	var chosen:Dictionary={}
	var nearest:=INF
	for id in ids:
		var section:Dictionary=sim.get_unit(int(id))
		if not can_recrew(sim,section):continue
		var gap:float=section.pos.distance_squared_to(hull.pos)
		if gap<nearest:
			chosen=section
			nearest=gap
	if chosen.is_empty():return 0
	var away:Vector2=chosen.pos-hull.pos
	var approach:Vector2=hull.pos+(away.normalized() if away.length()>0.01 else Vector2.DOWN)*(float(sim.definitions[hull.kind].radius)+1.5)
	if sim.issue([chosen.id],approach,"move")==0:return 0
	if not sim.has_meta(RECREW):sim.set_meta(RECREW,[])
	var jobs:Array=sim.get_meta(RECREW)
	for i in range(jobs.size()-1,-1,-1):
		if int(jobs[i].section)==int(chosen.id):jobs.remove_at(i)
	jobs.append({"section":chosen.id,"hull":hull.id,"dest":chosen.orders[-1].pos if not chosen.orders.is_empty() else approach,"done":0.0,"idle":0.0})
	return 1

# Per sim tick (simulation.tick, after the unit loop).
static func tick_recrew(sim,dt:float)->void:
	if not sim.has_meta(RECREW):return
	var jobs:Array=sim.get_meta(RECREW)
	for i in range(jobs.size()-1,-1,-1):
		var job:Dictionary=jobs[i]
		var section:Dictionary=sim.get_unit(int(job.section))
		var hull:Dictionary=sim.get_unit(int(job.hull))
		# Lost, beaten to it, or redirected by a new order: drop the job.
		if not can_recrew(sim,section) or not recrewable(sim,hull) or (not section.orders.is_empty() and section.orders[-1].pos!=job.dest):
			jobs.remove_at(i)
			continue
		if section.pos.distance_to(hull.pos)>float(sim.definitions[hull.kind].radius)+RECREW_REACH:
			if section.orders.is_empty():
				job.idle=float(job.idle)+dt
				if float(job.idle)>=RECREW_GIVE_UP:
					jobs.remove_at(i)
					if section.team==0:sim.events.append({"type":"warning","text":"Section could not reach the %s" % LABEL.get(hull.kind,str(hull.kind).capitalize()),"notice":"info"})
			continue
		if float(section.suppression)>=RECREW_SUPPRESSION or sim.time-float(section.last_hit)<RECREW_QUIET:
			section.reason="Re-crewing · pinned by fire"
			continue
		job.done=float(job.done)+dt
		section.reason="Re-crewing %d%%" % int(100.0*minf(1.0,float(job.done)/RECREW_SECONDS))
		if float(job.done)>=RECREW_SECONDS:
			jobs.remove_at(i)
			var fresh:=_board(sim,section,hull)
			# AI jobs: the vehicle and what is left of the section carry on.
			if job.has("resume") and not fresh.is_empty():
				sim.issue([fresh.id],job.resume.pos,job.resume.mode)
				if sim.alive(section):sim.issue([section.id],job.resume.pos,job.resume.mode)
	if jobs.is_empty():sim.remove_meta(RECREW)

# Enemy AI (field_ops tick): a section near its own side's abandoned hull climbs
# back in (an attacking one resumes its attack afterwards); an idle section
# captures an abandoned opposing hull within ENEMY_RECREW_CAPTURE. Neither
# starts under fire. Polled every ENEMY_RECREW_PERIOD s; returns jobs started.
const ENEMY_RECREW_PERIOD:=2.0
const ENEMY_RECREW_OWN:=15.0
const ENEMY_RECREW_CAPTURE:=25.0
const ENEMY_RECREW_CALM:=0.3
const ENEMY_RECREW_QUIET:=4.0
const RECREW_AI_NEXT:="vehicle_recrew_ai_next"
static func enemy_recrew(sim,team:int=1)->int:
	if sim.has_meta(RECREW_AI_NEXT) and sim.time<float(sim.get_meta(RECREW_AI_NEXT)):return 0
	sim.set_meta(RECREW_AI_NEXT,sim.time+ENEMY_RECREW_PERIOD)
	var sent:=0
	var busy:Array=[]
	var taken:Array=[]
	for job in sim.get_meta(RECREW) if sim.has_meta(RECREW) else []:
		busy.append(int(job.section))
		taken.append(int(job.hull))
	for wreck in wrecks(sim).duplicate():
		if not wreck.get("abandoned",false) or int(wreck.id) in taken:continue
		var hull:Dictionary=sim.get_unit(int(wreck.id))
		if not recrewable(sim,hull):continue
		var own:bool=hull.team==team
		var best:Dictionary={}
		var nearest:float=pow(ENEMY_RECREW_OWN if own else ENEMY_RECREW_CAPTURE,2)
		for section in sim.units:
			if section.team!=team or int(section.id) in busy or not can_recrew(sim,section):continue
			if not own and not section.orders.is_empty():continue
			if section.get("garrison",-1)>=0 or float(section.suppression)>=ENEMY_RECREW_CALM or sim.time-float(section.last_hit)<ENEMY_RECREW_QUIET:continue
			var gap:float=section.pos.distance_squared_to(hull.pos)
			if gap<nearest:
				best=section
				nearest=gap
		if best.is_empty():continue
		var resume:Dictionary={} if best.orders.is_empty() else {"pos":best.orders[-1].pos,"mode":"attack_move" if best.orders[-1].mode=="attack" else best.orders[-1].mode}
		if order_recrew(sim,[best.id],hull.id)==0:continue
		if not resume.is_empty():sim.get_meta(RECREW)[-1]["resume"]=resume
		busy.append(int(best.id))
		sent+=1
	return sent

# Soldiers climb in: a fresh hull replaces the wreck. Returns the new vehicle.
static func _board(sim,section:Dictionary,hull:Dictionary)->Dictionary:
	var fresh:Dictionary=sim.spawn(hull.kind,section.team,hull.pos)
	if fresh.is_empty():return fresh
	var able:Array=section.members.filter(func(m):return m.hp>0)
	# Healthy soldiers first; the highest index first, so an ATGM team keeps its launcher.
	able.sort_custom(func(a,b):return a.wound==b.wound and a.index>b.index or a.wound!=b.wound and a.wound==sim.Infantry.HEALTHY)
	var crew_full:int=int(hull.get("crew_full",sim.definitions[hull.kind].get("crew",2)))
	var count:int=mini(mini(crew_full,RECREW_CREW),able.size())
	for k in count:
		var member:Dictionary=able[k]
		sim.Infantry.release(section,member)
		if member.get("cover_phase","")!="":sim.Infantry.Cover.clear(member)
		member.hp=0.0
		member.wound=BOARDED
		member.state=BOARDED
		member.target=-1
		member.aim=0.0
		member.bleed_at=INF
	sim.Infantry.publish(section)
	fresh.pos=hull.pos
	fresh.home=hull.pos
	fresh.facing=hull.facing
	fresh.hp=clampf(float(hull.abandoned_hp),1.0,float(fresh.max_hp))
	ensure_state(sim,fresh)
	fresh.crew=count
	fresh.crew_full=crew_full
	fresh.mobility_kill=hull.get("mobility_kill",false)
	fresh.firepower_kill=hull.get("firepower_kill",false)
	if hull.get("optics_kill",false):fresh["optics_kill"]=true;fresh["accuracy"]=OPTICS_ACCURACY
	# The wreck is gone: its node hides (not alive, not wrecked).
	hull.wrecked=false
	hull.abandoned_hp=0.0
	hull["recrewed_as"]=fresh.id
	var list:Array=wrecks(sim)
	for k in range(list.size()-1,-1,-1):
		if int(list[k].id)==int(hull.id):list.remove_at(k)
	# Clear the wreck from the field nav now (not at the end of the tick), so
	# the vehicle can be routed straight away.
	if not sim.field_ops.is_empty():sim.FieldOps.sync_obstacles(sim)
	var captured:bool=hull.team!=section.team
	# The bail-out was counted as a kill/loss for the hull's side; the hull is
	# back in service (either side), so revoke it. Each hull is counted once,
	# for the side that owned it when it was finally knocked out.
	if hull.team==1:sim.kills=maxi(0,sim.kills-1)
	else:sim.losses=maxi(0,sim.losses-1)
	_event(sim,fresh,"captured" if captured else "recrewed")
	# Battle remaps selection and control groups from the hull (and a section
	# that climbed in whole) to the new vehicle.
	sim.events[-1].merge({"from":hull.id,"section":section.id})
	if fresh.team==0:
		var label:String=LABEL.get(fresh.kind,str(fresh.kind).capitalize())
		sim.events.append({"type":"warning","text":("Enemy %s captured · %d crew aboard" if captured else "%s re-crewed · %d crew aboard") % [label,count],"notice":"info"})
	return fresh
