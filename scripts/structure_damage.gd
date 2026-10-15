extends RefCounted

# World damage for everything that is neither a soldier nor a vehicle hull:
# compiled city buildings, engineer field works, street furniture and trees.
#
# Buildings (Garrison.index) carry an integrity scaled by footprint, floors and
# construction. Only high explosive brings walls down; small arms chip plaster
# and pin defenders but never change the state:
#   INTACT    full garrison protection
#   DAMAGED   >=35% lost: holes and missing windows, protection reduced
#   BREACHED  >=70% lost: walls holed through, little protection and every
#             further HE round sends fragments through the rooms
#   COLLAPSED 100%: occupants are killed or thrown clear (seeded roll), the
#             collision footprint becomes a rubble field (terrain.collapse_blocks)
# Field works: small-arms-proof works (field_units.json) take nothing from
# bullets; sandbags lose protection as HE wears them down; an ammunition depot
# hit by HE may cook off in a string of secondary explosions; HE bursting near
# concertina wire cuts it. HE bursts flatten crushable street furniture and
# fell trees around the impact.
# Rolls use a dedicated seeded RNG so the shared combat stream never shifts.

const Garrison=preload("res://scripts/garrison.gd")
const VehicleDamage=preload("res://scripts/vehicle_damage.gd")

# Structural points per round against building integrity, and the burst radius
# (m) that flattens props and cuts wire. Keyed by unit kind, then combat alias.
const HE:={
	"tank":{"structure":10.0,"radius":2.2},      # 120 mm HE-frag
	"at_gun":{"structure":7.0,"radius":1.6},
	"helo":{"structure":8.0,"radius":2.0},       # 70 mm rockets
	"boat":{"structure":6.0,"radius":1.8},       # 76 mm naval gun
	"atgm":{"structure":5.0,"radius":1.3},       # tandem HEAT: a hole, little blast
	"aa":{"structure":1.5,"radius":0.7},         # 35 mm HE autocannon
	"fpv_drone":{"structure":4.0,"radius":1.6},  # RPG-type warhead
}
const INTACT:=0
const DAMAGED:=1
const BREACHED:=2
const COLLAPSED:=3
const STATE_NAMES:=["INTACT","DAMAGED","BREACHED","COLLAPSED"]
const THRESHOLDS:=[0.35,0.7,1.0]
# What reaches garrisoned soldiers, relative to an intact building, by state.
const LEAK_SMALL:=[1.0,1.4,1.9]
const LEAK_HE:=[1.0,1.15,1.3]
# Breached rooms: each structural hit has this chance per occupant of a
# fragment wound roll at lethality (round's structural points / 10).
const FRAGMENT_CHANCE:=0.3
# Blast damage (cook-off, crash) at which a soldier at the burst takes a full
# HE-class wound roll (Infantry.roll lethality 1).
const BLAST_REF:=50.0
# Integrity = (BASE + floor area x floors x PER_AREA) x construction factor.
const BASE:=20.0
const PER_AREA:=0.3
const STRENGTH:={"dacha_hut":0.6,"outbuilding":0.6,"coop_shed":0.6,"barn_long":0.6,"transit_shed":0.6,
	"garage_row":0.7,"workshop_hall":0.7,"shop_pavilion":0.7,"petrol_station":0.7,"market_hall":0.8,
	"stone_house":1.2,"panel_5":1.3,"panel_9":1.3,"point_tower":1.3,"cathedral":1.6,"fort_ruin":1.8}
const MAX_INTEGRITY:=900.0
# Rounds that miss a target still burst against the building they strike.
const STRAY:=0.8
# Fragile airframes (units.json "fragile"): a hit that connects downs them.
const FRAGILE_DOWN:=0.9
# Bullets into a bunker's embrasure slow its gunners (s added per hit).
const EMBRASURE:=0.04
# Protection of intact sandbags (damage_amount's cover factor).
const COVER_SCALE:=0.55
const STATE:="world_damage"

static func _state(sim)->Dictionary:
	if not sim.has_meta(STATE):sim.set_meta(STATE,{"cookoffs":[],"bombard":[]})
	return sim.get_meta(STATE)

static func _rng(sim)->RandomNumberGenerator:
	if not sim.has_meta("world_damage_rng"):
		var rng:=RandomNumberGenerator.new()
		rng.seed=61843
		sim.set_meta("world_damage_rng",rng)
	return sim.get_meta("world_damage_rng")

static func he_spec(sim,u:Dictionary)->Dictionary:
	if HE.has(u.kind):return HE[u.kind]
	return HE.get(sim.definitions.get(u.kind,{}).get("combat_alias",u.kind),{})

static func integrity(building:Dictionary)->float:
	var strength:float=STRENGTH.get(building.design,1.0)
	return clampf((BASE+float(building.area)*maxf(1.0,float(building.floors))*PER_AREA)*strength,12.0,MAX_INTEGRITY)

static func building_state(sim,building_id:int)->int:
	if building_id<0:return INTACT
	return int(Garrison.index(sim).buildings[building_id].state)

# Point on the building's outline facing `from` (where a round strikes).
static func wall_point(building:Dictionary,from:Vector2)->Vector2:
	var b:Rect2=building.bounds
	if b.has_point(from):return b.get_center()
	return Vector2(clampf(from.x,b.position.x,b.end.x),clampf(from.y,b.position.y,b.end.y))

# --- resolve_shot hook --------------------------------------------------------
# Called for every hit with the damage about to be applied; returns the damage
# that actually reaches the target.
static func strike(sim,u:Dictionary,target:Dictionary,amount:float)->float:
	var td:Dictionary=sim.definitions[target.kind]
	if td.get("fragile",false):
		# A small airframe rarely survives any hit that connects.
		return maxf(amount,target.hp) if _rng(sim).randf()<FRAGILE_DOWN else amount
	var he:=he_spec(sim,u)
	if Garrison.inside(target):
		var building:Dictionary=Garrison.index(sim).buildings[int(target.garrison)]
		var state:int=mini(int(building.state),BREACHED)
		if not he.is_empty():damage_building(sim,building.id,float(he.structure),u.pos,wall_point(building,u.pos),target.id)
		return amount*(LEAK_SMALL[state] if he.is_empty() else LEAK_HE[state])
	if td.get("structure",false):
		if he.is_empty():
			if not td.get("small_arms_proof",false):return amount
			if td.get("armed",false):target.cooldown=float(target.cooldown)+EMBRASURE
			return 0.0
		if td.has("cook_off") and not target.get("cooking",false):
			var after:float=target.hp-amount
			var chance:float=float(td.cook_off.chance)+0.5*(1.0-clampf(after/maxf(1.0,target.max_hp),0.0,1.0))
			if after<=0.0 or _rng(sim).randf()<chance:start_cook_off(sim,target)
		return amount
	if not target.members.is_empty() and not sim.terrain.field_cover.is_empty():return amount*sandbag_leak(sim,u,target)
	return amount

# Worn sandbags stop less: the cover factor drifts from COVER_SCALE to none as
# the work behind the soldier nearest the shooter loses integrity.
static func sandbag_leak(sim,u:Dictionary,target:Dictionary)->float:
	var cover_pos:Vector2=target.pos
	var nearest:=INF
	for member in target.members:
		if member.hp>0 and member.pos.distance_squared_to(u.pos)<nearest:
			nearest=member.pos.distance_squared_to(u.pos);cover_pos=member.pos
	for rect in sim.terrain.field_cover:
		if rect.has_point(cover_pos) or not rect.grow(1.4).has_point(cover_pos):continue
		for work in sim.units:
			if work.kind!="tactical_cover" or not sim.alive(work) or not rect.has_point(work.pos):continue
			var worn:float=1.0-clampf(work.hp/maxf(1.0,work.max_hp),0.0,1.0)
			return 1.0+(1.0/COVER_SCALE-1.0)*worn
	return 1.0

# Protection multiplier a sandbag work currently gives (1 = none).
static func sandbag_protection(work:Dictionary)->float:
	var worn:float=1.0-clampf(work.hp/maxf(1.0,work.max_hp),0.0,1.0)
	return COVER_SCALE*(1.0+(1.0/COVER_SCALE-1.0)*worn)

# --- Buildings ----------------------------------------------------------------
static func damage_building(sim,building_id:int,points:float,source:Vector2,impact:Vector2=Vector2.INF,exempt:int=-1)->void:
	if building_id<0 or points<=0.0:return
	var building:Dictionary=Garrison.index(sim).buildings[building_id]
	if int(building.state)>=COLLAPSED:return
	building.damage=float(building.damage)+points
	var fraction:float=building.damage/integrity(building)
	var state:=INTACT
	for k in THRESHOLDS.size():
		if fraction>=THRESHOLDS[k]:state=k+1
	if not impact.is_finite():impact=wall_point(building,source)
	# Fragments through holed walls.
	if state>=BREACHED and state<COLLAPSED:
		var rng:=_rng(sim)
		for u in sim.units:
			if not sim.alive(u) or int(u.get("garrison",-1))!=building_id:continue
			sim.Infantry.reconcile(u)
			for m in u.members:
				if m.hp>0 and rng.randf()<FRAGMENT_CHANCE:_wound(sim,u,m,sim.Infantry.roll("FRAGMENT",points/10.0,rng))
			sim.Infantry.publish(u)
			u.last_hit=sim.time
			if u.hp<=0.0 and u.id!=exempt:_lost(sim,u)
	sim.events.append({"type":"building_damage","building":building_id,"state":state,"fraction":fraction,"impact":impact,"source":source,"height":float(building.height),"visible":true})
	if state==int(building.state):return
	var before:int=building.state
	building.state=state
	if state>=COLLAPSED:collapse(sim,building_id,exempt)
	elif before<state and not Garrison.occupants(sim,building_id,0).is_empty():
		sim.events.append({"type":"warning","text":"Garrisoned building %s" % ("damaged · protection reduced" if state==DAMAGED else "breached · fragments inside")})

static func collapse(sim,building_id:int,exempt:int=-1)->void:
	var building:Dictionary=Garrison.index(sim).buildings[building_id]
	building.state=COLLAPSED
	building.damage=maxf(float(building.damage),integrity(building))
	var rng:=_rng(sim)
	# Taller buildings bury more of the people inside.
	var lethality:float=clampf(0.25+0.08*float(building.floors),0.3,0.8)
	var killed:=0;var survivors:=0;var player:=false
	for u in sim.units:
		if not sim.alive(u) or u.members.is_empty():continue
		var garrisoned:bool=int(u.get("garrison",-1))==building_id
		if not garrisoned and int(u.get("garrison_target",-1))!=building_id:continue
		sim.Infantry.reconcile(u)
		for m in u.members:
			if m.get("wound","")==sim.Infantry.KIA or not (garrisoned or m.get("indoors",false)):continue
			# Buried, or dug out hurt (falling masonry: fragment-class wounds).
			# The badly wounded cannot get clear and are buried more often.
			var down:bool=m.get("wound","")==sim.Infantry.SEVERE
			_wound(sim,u,m,sim.Infantry.KIA if rng.randf()<lethality+(0.35 if down else 0.0) else sim.Infantry.roll("FRAGMENT",1.0,rng))
			if m.wound==sim.Infantry.KIA:killed+=1
			else:survivors+=1
		sim.Infantry.publish(u)
		player=player or u.team==0
		Garrison.evict(sim,u)
		u.suppression=1.0
		if u.hp<=0.0 and u.id!=exempt:_lost(sim,u)
	# Fire missions on the building end with it.
	if sim.has_meta(STATE):
		for gunner in _state(sim).bombard:
			if int(gunner.get("bombard",-1))==building_id:gunner.erase("bombard");gunner.erase("bombard_move")
	var center:Vector2=building.bounds.get_center()
	sim.terrain.collapse_blocks(building.blocks,building.bounds.grow(0.6))
	sim.visibility_cache.clear()
	# Falling masonry flattens the street furniture against the walls.
	blast_props(sim,center,maxf(building.bounds.size.x,building.bounds.size.y)*0.5+1.5,center)
	sim.events.append({"type":"building_collapse","building":building_id,"pos":center,"bounds":building.bounds,"height":float(building.height),"killed":killed,"survivors":survivors,"visible":true})
	sim.events.append({"type":"world_blast","kind":"collapse","pos":center,"radius":maxf(building.bounds.size.x,building.bounds.size.y)*0.5,"visible":true})
	if player:sim.events.append({"type":"warning","text":"Building collapsed · %d buried, %d dug out" % [killed,survivors]})
	elif killed>0:sim.events.append({"type":"warning","text":"Enemy-held building collapsed"})

# One soldier hurt by masonry or blast, through the infantry wound model.
static func _wound(sim,u:Dictionary,m:Dictionary,outcome:String)->void:
	sim.Infantry.wound(u,m,outcome,sim.time,_rng(sim))
	m.suppression=minf(1.0,float(m.get("suppression",0.0))+0.6)
	if m.hp>0:m.state="BRACING"

# Kill bookkeeping for losses that do not pass through resolve_shot.
static func _lost(sim,u:Dictionary)->void:
	if u.get("lost_counted",false):return
	u["lost_counted"]=true
	sim.events.append({"type":"destroyed","kind":u.kind,"pos":u.pos,"visible":u.visible})
	if u.team==1:sim.kills+=1
	else:sim.losses+=1

# --- Street furniture, trees, wire ------------------------------------------------
static func blast_props(sim,pos:Vector2,radius:float,from:Vector2)->int:
	var records:Array=sim.terrain.crush_props(pos,radius)
	for record in records:
		var centre:Vector2=record.rect.get_center()
		var heading:Vector2=centre-pos
		if heading.length_squared()<0.0001:heading=pos-from
		sim.events.append({"type":"crushed","prop":record.prop,"id":record.id,"heading":heading.normalized(),"pos":centre,"visible":true,"cause":"blast"})
	# Collision trees fall outward from the burst (presentation via terrain.tree_felled).
	return records.size()+sim.terrain.fell_trees(pos,radius).size()

static func cut_wire(sim,pos:Vector2,radius:float)->int:
	if sim.field_ops.is_empty():return 0
	var cut:=0
	for wire in sim.units:
		if wire.kind!="concertina_wire" or not sim.alive(wire):continue
		if not sim.FieldOps.footprint(sim,wire.kind,wire.pos,wire.get("rotated",false)).grow(radius).has_point(pos):continue
		wire.hp=0.0
		wire.state="CUT"
		cut+=1
		_lost(sim,wire)
	return cut

# --- Explosions (cook-offs, crashes) ---------------------------------------------
# Indiscriminate blast: soldiers by distance (halved in cover or trenches),
# hulls and works by armour class, buildings, props and wire.
static func explosion(sim,pos:Vector2,radius:float,damage:float,structure:float,kind:String="blast",exempt:int=-1)->void:
	for other in sim.units:
		if not sim.alive(other) or other.id==exempt:continue
		var od:Dictionary=sim.definitions[other.kind]
		if od.domain=="air" and sim.unit_altitude(other)>2.0:continue
		var reach:float=radius+float(od.radius)
		if pos.distance_squared_to(other.pos)>reach*reach:continue
		if not other.members.is_empty():
			sim.Infantry.reconcile(other)
			for m in other.members:
				if m.hp<=0:continue
				var gap:float=pos.distance_to(m.pos)
				if gap>radius:continue
				var shelter:float=0.4 if Garrison.inside(other) else (0.5 if m.get("in_trench",false) or sim.terrain.cover(m.pos) else 1.0)
				var falloff:float=1.0-gap/radius
				m.suppression=minf(1.0,float(m.suppression)+0.6)
				if _rng(sim).randf()<(0.35+0.65*falloff)*shelter:
					_wound(sim,other,m,sim.Infantry.roll("HE" if falloff>0.6 else "FRAGMENT",damage/BLAST_REF*shelter*(0.4+0.6*falloff),_rng(sim)))
				elif m.state!="DOWN":m.state="BRACING"
			sim.Infantry.publish(other)
			other.last_hit=sim.time
			other.suppression=minf(1.0,other.suppression+0.5)
		else:
			var gap:float=maxf(0.0,pos.distance_to(other.pos)-float(od.radius)*0.5)
			if gap>radius:continue
			var scale:float=1.0
			if od.get("structure",false):scale=0.8
			elif od.has("armor_mm"):scale=0.15 if float(od.armor_mm[1])>=100.0 else 0.5
			var dealt:float=damage*scale*(1.0-0.7*gap/radius)
			if od.has("cook_off") and not other.get("cooking",false):start_cook_off(sim,other)
			if VehicleDamage.tracked(sim,other):dealt=VehicleDamage._finish(sim,other,dealt)
			other.hp-=dealt
			other.last_hit=sim.time
		if other.hp<=0.0:_lost(sim,other)
	var index:=Garrison.index(sim)
	for building in index.buildings:
		if int(building.state)>=COLLAPSED or not building.bounds.grow(radius).has_point(pos):continue
		var gap:float=wall_point(building,pos).distance_to(pos)
		damage_building(sim,building.id,structure*(1.0-0.6*clampf(gap/radius,0.0,1.0)),pos,wall_point(building,pos))
	blast_props(sim,pos,radius*0.6,pos)
	cut_wire(sim,pos,radius*0.5)
	sim.events.append({"type":"world_blast","kind":kind,"pos":pos,"radius":radius,"visible":true})

static func start_cook_off(sim,depot:Dictionary)->void:
	var spec:Dictionary=sim.definitions[depot.kind].get("cook_off",{})
	if spec.is_empty() or depot.get("cooking",false):return
	depot["cooking"]=true
	_state(sim).cookoffs.append({"unit":depot.id,"pos":depot.pos,"team":depot.team,"next":sim.time+0.6,"left":int(spec.blasts),"spec":spec})
	sim.events.append({"type":"warning","text":"Ammunition depot hit · cooking off"})

# --- Force-attack on a building --------------------------------------------------
# Orders HE-armed vehicles/emplacements to shell a building until it collapses
# or they get a new order. Units out of range first close to ~80% of range.
# Returns how many units accepted. (Input wiring lives in battle.gd.)
static func bombard(sim,ids:Array,building_id:int)->int:
	if building_id<0 or building_state(sim,building_id)>=COLLAPSED:return 0
	var building:Dictionary=Garrison.index(sim).buildings[building_id]
	var accepted:=0
	for id in ids:
		var u:Dictionary=sim.get_unit(int(id))
		if not sim.alive(u) or not u.members.is_empty() or he_spec(sim,u).is_empty():continue
		var d:Dictionary=sim.definitions[u.kind]
		if d.get("strike",false) or (d.get("structure",false) and not d.get("armed",false)):continue
		var aim:=wall_point(building,u.pos)
		var reach:float=float(d.range)*0.85
		u.erase("bombard_move")
		if u.pos.distance_to(aim)>reach:
			if float(d.speed)<=0.0:continue
			if sim.issue([u.id],aim+(u.pos-aim).normalized()*reach*0.8,"move")<=0:continue
			u["bombard_move"]=u.orders.back().pos
		elif not d.get("structure",false):sim.stop([u.id])
		u["bombard"]=building_id
		if not _state(sim).bombard.has(u):_state(sim).bombard.append(u)
		accepted+=1
	return accepted

static func _bombard_tick(sim,list:Array)->void:
	for i in range(list.size()-1,-1,-1):
		var u:Dictionary=list[i]
		var id:int=int(u.get("bombard",-1))
		if not sim.alive(u) or id<0 or building_state(sim,id)>=COLLAPSED:
			u.erase("bombard");u.erase("bombard_move");list.remove_at(i);continue
		if not u.orders.is_empty():
			# Any other order cancels the fire mission.
			if u.orders.size()>1 or u.orders[0].mode!="move" or not u.has("bombard_move") or u.orders[0].pos.distance_to(u.bombard_move)>0.5:
				u.erase("bombard");u.erase("bombard_move");list.remove_at(i)
			continue
		u.erase("bombard_move")
		if int(u.target)>=0 or u.cooldown>0.0 or not VehicleDamage.weapon_ready(sim,u):continue
		var building:Dictionary=Garrison.index(sim).buildings[id]
		var d:Dictionary=sim.definitions[u.kind]
		var aim:=wall_point(building,u.pos)
		if u.pos.distance_to(aim)>float(d.range):
			u.erase("bombard");list.remove_at(i);continue
		var near:Vector2=aim+(u.pos-aim).normalized()*0.3
		if d.domain!="air" and not sim.terrain.line_clear(u.pos,near):continue
		u.last_shot=sim.time
		u.cooldown=float(d.interval)
		u.state="BOMBARDING"
		var alias:String=u.kind if u.kind in ["at_gun"] else d.get("combat_alias",u.kind)
		var height:float=_rng(sim).randf_range(1.0,maxf(1.2,float(building.height)*0.7))
		sim.events.append({"type":"shot","from":u.pos,"to":aim,"kind":alias,"target_kind":"barracks","hit":true,"from_y":maxf(0.95,float(d.altitude)),"to_y":height,"visible":true})
		damage_building(sim,id,float(he_spec(sim,u).structure),u.pos,aim)

# --- Per-tick hook ------------------------------------------------------------------
# Collateral of this tick's HE rounds and FPV bursts, cook-off strings, vehicle
# hazards (fire, flooding, falling aircraft) and building fire missions.
static func tick(sim,dt:float)->void:
	_scan_impacts(sim)
	for impact in VehicleDamage.tick_hazards(sim,dt):
		explosion(sim,impact.pos,float(impact.radius),float(impact.damage),float(impact.structure),str(impact.get("kind","blast")))
	if not sim.has_meta(STATE):return
	var state:Dictionary=sim.get_meta(STATE)
	var cookoffs:Array=state.cookoffs
	for i in range(cookoffs.size()-1,-1,-1):
		var c:Dictionary=cookoffs[i]
		if sim.time<float(c.next):continue
		var depot:Dictionary=sim.get_unit(int(c.unit))
		if sim.alive(depot):
			depot.hp=0.0
			depot.state="DESTROYED"
			_lost(sim,depot)
		var rng:=_rng(sim)
		var offset:=Vector2.from_angle(rng.randf()*TAU)*rng.randf_range(0.0,2.5)
		explosion(sim,c.pos+offset,float(c.spec.radius),float(c.spec.damage),float(c.spec.structure),"cook_off",int(c.unit))
		c.left=int(c.left)-1
		c.next=sim.time+float(c.spec.interval)*rng.randf_range(0.6,1.4)
		if int(c.left)<=0:cookoffs.remove_at(i)
	if not state.bombard.is_empty():_bombard_tick(sim,state.bombard)

static func _scan_impacts(sim)->void:
	var events:Array=sim.events
	var first:=events.size()
	while first>0 and not events[first-1].has("_wd"):first-=1
	if first==events.size():return
	var fresh:Array=events.slice(first)
	for event in fresh:event["_wd"]=true
	for event in fresh:
		var spec:Dictionary={}
		var pos:Vector2
		var from:Vector2
		var hit:=true
		if event.type=="shot":
			spec=HE.get(event.kind,{})
			var struck:Dictionary=sim.definitions.get(event.get("target_kind",""),{})
			if spec.is_empty() or struck.get("domain","land")=="air":continue
			pos=event.to;from=event.from;hit=event.get("hit",true)
			# A round that strikes armour spends itself on the hull, not the street.
			if hit and struck.has("armor_mm"):continue
		elif event.type=="destroyed" and event.get("kind","")=="fpv_drone":
			spec=HE.fpv_drone
			pos=event.pos;from=event.pos;hit=false
		else:continue
		blast_props(sim,pos,float(spec.radius),from)
		cut_wire(sim,pos,float(spec.radius)+0.5)
		if not hit:
			var building:int=Garrison.building_at(sim,pos)
			if building>=0:damage_building(sim,building,float(spec.structure)*STRAY,from,pos)
