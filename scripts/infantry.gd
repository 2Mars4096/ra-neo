class_name InfantryActors
extends RefCounted
const Cover=preload("res://scripts/cover_behavior.gd")

static func formation_offset(index:int,count:int)->Vector2:
	if count==3:
		return [Vector2(0,-0.98),Vector2(-0.85,0.49),Vector2(0.85,0.49)][index]
	return Vector2((index%2)*1.7-0.85,(index/2)*1.7-0.85)

static func create(u:Dictionary,d:Dictionary) -> void:
	u["members"]=[]
	if u.kind not in ["rifle","atgm","engineer"]:return
	for i in int(d.members):
		var offset:=formation_offset(i,int(d.members))
		u.members.append({"index":i,"offset":offset,"pos":u.pos+offset,"hp":float(d.hp)/int(d.members),"max_hp":float(d.hp)/int(d.members),"cooldown":i*0.19,"target":-1,"aim":0.0,"suppression":0.0,"last_hit":-100.0,"last_shot":-100.0,"facing":u.facing,"state":"HOLDING","travel":0.0,"phase":i*1.7,"cover_goal":Vector2.ZERO,"cover_until":0.0,"rounds":6 if not (u.kind=="atgm" and i==0) else 1,"reload_until":0.0,"speed":0.0,"posture":"STANDING","body_radius":0.8,"posture_until":0.0,"wound":HEALTHY,"bleed_at":INF,"aid":0.0,"stable":false,"treat":0.0,"medic":-1,"aiding":-1})
	u["member_hp_snapshot"]=u.hp

static func reconcile(u:Dictionary) -> void:
	if u.members.is_empty():return
	# External setup/tests and legacy squad recovery remain compatible. Combat
	# updates members directly and immediately publishes the new aggregate.
	if not is_equal_approx(u.hp,float(u.member_hp_snapshot)):
		var total:=0.0
		for member in u.members:total+=member.hp
		if total>0:
			for member in u.members:member.hp=minf(member.max_hp,member.hp*u.hp/total)
	publish(u)

# Section HP bar = sum of combat-effective soldiers: HEALTHY counts max_hp (or a
# legacy partial value), LIGHT at most LIGHT_SHARE*max_hp, SEVERE and KIA zero.
# The section is destroyed once no soldier can fight (every one SEVERE or KIA).
static func publish(u:Dictionary) -> void:
	u.hp=0.0
	for member in u.members:
		# Legacy/external damage (tests, FPV blast) that zeroes a soldier still
		# produces a wound state, never a vanished record.
		if member.hp<=0 and member.get("wound",HEALTHY) in [HEALTHY,LIGHT]:external_down(member)
		u.hp+=member.hp
	# A section whose survivors are all badly wounded still exists: it stays
	# selectable and visible but cannot fight (it ends when the last man dies).
	u["combat_ineffective"]=false
	if u.hp<=0.0 and u.members.any(func(m):return m.get("wound",HEALTHY)==SEVERE):
		u.hp=INEFFECTIVE_HP
		u["combat_ineffective"]=true
	u.member_hp_snapshot=u.hp

# --- Wounds ------------------------------------------------------------------
# Per-soldier states. hp is the soldier's combat-effective share of the bar.
const HEALTHY:="HEALTHY"
const LIGHT:="LIGHT"      # walks slower, aims slower and less accurately
const SEVERE:="SEVERE"    # down: no fire, crawls; bleeds out unless aided
const KIA:="KIA"          # body stays where it fell; never targeted or selected
const LIGHT_SHARE:=0.5
const INEFFECTIVE_HP:=0.01  # bar value of a section with only SEVERE survivors
const LIGHT_SPEED:=0.75
const LIGHT_AIM:=1.5
const LIGHT_ACCURACY:=0.75
const BLEED_MIN:=45.0
const BLEED_SPAN:=45.0
const AID_SECONDS:=8.0
const AID_REACH:=1.2
const AID_QUIET:=2.5      # seconds since the section was last hit
const AID_SUPPRESSION:=0.5
const TREAT_SHARE:=1.35   # aid-post HP (x max_hp) to treat SEVERE back to LIGHT
const CRAWL_SPEED:=0.3
const CARRY_SCALE:=0.6    # section speed while carrying a SEVERE casualty
const FRAGMENT_RADIUS:=3.2
# [KIA, SEVERE] probabilities for an unprotected hit; the remainder is LIGHT.
# Lethality < 1 (cover, garrison, trench, weak rounds) shifts outcomes milder.
const OUTCOMES:={"BULLET":[0.25,0.40],"HE":[0.55,0.35],"FRAGMENT":[0.10,0.35]}

static func casualties(u:Dictionary) -> int:
	var count:=0
	for member in u.members:
		if member.get("wound",HEALTHY) in [SEVERE,KIA]:count+=1
	return count

# Bodies and downed soldiers remain on the ground after their section is gone.
static func has_remains(u:Dictionary) -> bool:
	for member in u.members:
		if member.get("wound",HEALTHY) in [SEVERE,KIA]:return true
	return false

# A SEVERE casualty slows its section while an able soldier is left to carry it.
static func carrying(u:Dictionary) -> bool:
	var wounded:=false
	var bearer:=false
	for member in u.members:
		if member.get("wound",HEALTHY)==SEVERE:wounded=true
		elif member.hp>0:bearer=true
	return wounded and bearer

static func roll(kind:String,lethality:float,rng:RandomNumberGenerator) -> String:
	var table:Array=OUTCOMES[kind]
	var l:=clampf(lethality,0.1,1.3)
	var kia:float=float(table[0])*l
	var severe:float=float(table[1])*sqrt(l)
	var r:=rng.randf()
	if r<kia:return KIA
	if r<kia+severe:return SEVERE
	return LIGHT

# Applies one outcome; a second LIGHT wound becomes SEVERE.
static func wound(u:Dictionary,member:Dictionary,outcome:String,now:float,rng:RandomNumberGenerator) -> void:
	var state:String=member.get("wound",HEALTHY)
	if state in [SEVERE,KIA] and outcome!=KIA:return
	if outcome==LIGHT and state==LIGHT:outcome=SEVERE
	member.last_hit=now
	if outcome==LIGHT:
		member.wound=LIGHT
		member.hp=minf(member.hp,member.max_hp*LIGHT_SHARE)
		member.state="BRACING"
		return
	member.wound=outcome
	member.hp=0.0
	member.aid=0.0
	member.treat=0.0
	member.stable=false
	member.bleed_at=now+BLEED_MIN+BLEED_SPAN*rng.randf() if outcome==SEVERE else INF
	member.state="DOWN" if outcome==SEVERE else "KIA"
	member.target=-1
	member.aim=0.0
	release(u,member)
	Cover.clear(member)

# Ends any buddy-aid pairing that involves this soldier.
static func release(u:Dictionary,member:Dictionary) -> void:
	if member.get("aiding",-1)>=0:
		var casualty:Dictionary=u.members[member.aiding]
		if casualty.get("medic",-1)==member.index:casualty.medic=-1
	if member.get("medic",-1)>=0:
		var medic:Dictionary=u.members[member.medic]
		if medic.get("aiding",-1)==member.index:medic.aiding=-1
	member.aiding=-1
	member.medic=-1

static func external_down(member:Dictionary) -> void:
	member.hp=0.0
	var hit_at:float=float(member.get("last_hit",-100.0))
	# Scripted removals (never hit) leave a body; combat damage is 55% KIA.
	var h:=fposmod(hit_at*37.0+float(member.index)*0.618,1.0)
	if hit_at<0.0 or h<0.55:
		member.wound=KIA
		member.state="KIA"
		member.bleed_at=INF
	else:
		member.wound=SEVERE
		member.state="DOWN"
		member.bleed_at=hit_at+BLEED_MIN+BLEED_SPAN*fposmod(h*7.3,1.0)
	member["aid"]=0.0
	member["stable"]=false
	member["treat"]=0.0
	if not member.has("medic"):member["medic"]=-1
	if not member.has("aiding"):member["aiding"]=-1
	member.target=-1

# The soldier a shot from `source` most likely strikes: nearest able one.
static func exposed_member(u:Dictionary,source:Vector2) -> Dictionary:
	var chosen:Dictionary={}
	var nearest:=INF
	for member in u.members:
		if member.hp<=0:continue
		var distance:float=source.distance_squared_to(member.pos)
		if distance<nearest:chosen=member;nearest=distance
	return chosen

# One hit on a section. Bullets wound the struck soldier; HE also throws
# fragments that may wound others within FRAGMENT_RADIUS, by distance.
static func strike(u:Dictionary,kind:String,lethality:float,source:Vector2,now:float,rng:RandomNumberGenerator) -> void:
	reconcile(u)
	var victim:=exposed_member(u,source)
	if victim.is_empty():return
	var sheltered:=lethality
	if victim.get("in_trench",false):sheltered*=0.55
	wound(u,victim,roll(kind,sheltered,rng),now,rng)
	victim.suppression=minf(1,victim.suppression+0.45)
	if kind=="HE":
		for member in u.members:
			if member==victim or member.hp<=0:continue
			var gap:float=member.pos.distance_to(victim.pos)
			if gap>FRAGMENT_RADIUS:continue
			var falloff:=1.0-gap/FRAGMENT_RADIUS
			member.suppression=minf(1,member.suppression+0.45)
			member.last_hit=now
			var shelter:=0.55 if member.get("in_trench",false) else 1.0
			if rng.randf()<0.75*falloff*shelter:wound(u,member,roll("FRAGMENT",lethality*shelter*(0.5+0.5*falloff),rng),now,rng)
			elif member.state!="DOWN":member.state="BRACING"
	publish(u)

# Bleed-out and buddy aid (called once per tick for a living section).
static func tick_wounds(u:Dictionary,now:float,dt:float) -> void:
	var quiet:bool=now-float(u.last_hit)>=AID_QUIET and u.suppression<=AID_SUPPRESSION and (u.orders.is_empty() or u.orders[0].mode!="retreat")
	var garrisoned:bool=u.get("garrison",-1)>=0
	for casualty in u.members:
		if casualty.get("wound",HEALTHY)!=SEVERE:continue
		if not casualty.stable and now>=float(casualty.bleed_at):
			# Died of wounds.
			casualty.wound=KIA
			casualty.state="KIA"
			casualty.bleed_at=INF
			release(u,casualty)
			continue
		if casualty.stable:continue
		var medic:Dictionary=u.members[casualty.medic] if casualty.medic>=0 else {}
		if not medic.is_empty() and (medic.hp<=0 or not quiet or medic.suppression>AID_SUPPRESSION):
			release(u,casualty)
			medic={}
		if not quiet:continue
		if medic.is_empty():
			var best:=INF
			for member in u.members:
				if member.hp<=0 or member.get("aiding",-1)>=0 or member.suppression>AID_SUPPRESSION:continue
				if member.get("cover_phase","") in ["SEEKING","SETTLING"]:continue
				var distance:float=member.pos.distance_squared_to(casualty.pos)
				if distance<best:best=distance;medic=member
			if medic.is_empty():continue
			casualty.medic=medic.index
			medic.aiding=casualty.index
		if garrisoned or medic.pos.distance_to(casualty.pos)<=AID_REACH:
			casualty.aid+=dt
			medic.state="AIDING"
			if casualty.aid>=AID_SECONDS:
				# Bleeding stopped: still SEVERE and out of the fight, but no longer dying.
				casualty.stable=true
				casualty.bleed_at=INF
				release(u,casualty)

static func move(u:Dictionary,sim,dt:float) -> void:
	if not u.members.is_empty() and sim.scenario.get("autonomy",false):update_regroup(u,sim)
	# The threat scan (line-of-fire checks against every nearby enemy) runs ~3x a
	# second per section, staggered by id, instead of every 30 Hz tick. A new
	# order still clears stale cover immediately.
	var ordered:bool=u.get("cover_command",-1)!=u.command_group
	if ordered or sim.time>=u.get("cover_next",0.0):
		u["cover_command"]=u.command_group
		u["cover_next"]=sim.time+0.3+float(u.id%5)*0.02
		Cover.update(u,sim)
	u["carry_from"]=u.pos
	# Caught in the open (crossfire, or under fire with no shelter in reach):
	# spread to prone spacing.
	var open_spread:bool=u.get("crossfire",false) or in_contact(u,sim.time)
	for member in u.members:
		if member.hp<=0:
			if member.get("wound","")==SEVERE:move_casualty(u,member,sim,dt)
			continue
		member.cooldown-=dt
		member.suppression=maxf(0,member.suppression-dt*0.12)
		var offset:Vector2=member.offset
		# Once spread, a soldier keeps the wider slot while still in the open
		# (the contact window may lapse between bursts): shrinking it back would
		# stand the soldier up and walk them off their firing position mid-fight.
		var spread:bool=caught_open(member,sim.time) and (open_spread or member.get("spread",false))
		member["spread"]=spread
		# Under fire with no cover phase (regrouping, holding): prone spacing too,
		# once the contact drill's first drop is over.
		spread=spread or (open_spread and sim.time>=float(u.get("drill_until",0.0)) and uncovered(u,member,member.get("cover_phase","")))
		if spread:offset*=1.5
		var desired:Vector2=u.pos+offset
		if member.get("aiding",-1)>=0:
			# Buddy aid: kneel beside the casualty; no shelter moves meanwhile.
			var casualty:Dictionary=u.members[member.aiding]
			if member.get("cover_phase","")!="":Cover.clear(member)
			member.cover_until=maxf(member.cover_until,sim.time+1.0)
			var away:Vector2=member.pos-casualty.pos
			desired=casualty.pos+(away.normalized() if away.length()>0.01 else Vector2.RIGHT)*0.8
			if member.pos.distance_to(casualty.pos)<=AID_REACH:desired=member.pos
		elif sim.scenario.get("autonomy",false):
			var phase:String=member.get("cover_phase","")
			if u.hold_command:desired=member.pos
			elif u.get("regroup_active",false):desired=regroup_destination(u,member,sim,desired)
			elif phase=="OVERWATCH":desired=member.pos
			elif phase in ["SEEKING","SETTLING","SHELTERED"]:
				while not member.cover_path.is_empty() and member.pos.distance_to(member.cover_path[0])<0.15:member.cover_path.pop_front()
				desired=member.cover_goal if member.cover_path.is_empty() else member.cover_path[0]
			elif member.pos.distance_to(desired)>0.3:
				desired=regroup_destination(u,member,sim,desired)
		var old:Vector2=member.pos
		# A soldier already on its spot has no step to take; every use of the
		# speed below then yields the same result for 0 (no terrain lookup).
		var speed:float=0.0 if desired==old else float(sim.definitions[u.kind].speed)*(1.04+member.index*0.035)*sim.terrain.ground_speed(old,"infantry")
		if member.suppression>0.6:speed*=0.75
		if member.get("wound","")==LIGHT:speed*=LIGHT_SPEED
		if member.get("cover_phase","")=="SEEKING":speed*=1.2
		if not u.orders.is_empty() and u.orders[0].mode=="retreat":speed*=1.2
		if sim.scenario.get("autonomy",false):
			speed=minf(speed,sqrt(2.0*12.0*old.distance_to(desired)))
			member.speed=move_toward(member.speed,speed,dt*14.0)
			speed=member.speed
		if sim.scenario.get("autonomy",false) and member.posture=="PRONE":
			# Recover from the ground before moving; preserve the larger footprint.
			if desired.distance_to(old)>0.2:
				member.posture="RISING"
				member.posture_until=sim.time+0.45
			else:speed=0.0
		if member.get("posture","")=="RISING" and sim.time<member.posture_until:speed=0.0
		# Up off the ground: the standing footprint again. Combat only resets it
		# for soldiers with a target, so one rising to run for cover kept the
		# prone 1.15 m body and stuck in gaps a runner fits through.
		elif member.posture!="PRONE":member.body_radius=0.8
		var next:Vector2=old.move_toward(desired,speed*dt)
		# Anticipatory avoidance: sidestep soldiers/vehicles a few metres ahead and
		# ease off when someone is right in front, instead of shoving through.
		if sim.scenario.get("autonomy",false) and speed>0.0 and old.distance_to(desired)>0.3:
			var heading:Vector2=(desired-old).normalized()
			var steer:Vector3=avoidance(u,member,old,heading,sim,old.distance_to(desired))
			if steer.z>0.0:
				var adjusted:Vector2=(heading+Vector2(steer.x,steer.y)).normalized()
				if adjusted.dot(heading)>0.2:
					speed*=1.0-0.45*steer.z
					next=old+adjusted*minf(speed*dt,old.distance_to(desired))
		# A stationary actor has no proposed displacement to validate.
		if speed>0.0 and desired!=old:
			# actor_clear re-tests this step at the (wider) body radius. A step
			# under one sample spacing tests only `next` at both radii, and
			# terrain clearance only tightens with radius, so there the narrow
			# test cannot change the outcome: skip it.
			var autonomy:bool=sim.scenario.get("autonomy",false)
			var implied:bool=autonomy and float(member.get("body_radius",0.8))>=0.42 and old.distance_to(next)<=0.35
			var clear:bool=implied or sim.terrain.segment_clear(old,next,"land",0.42)
			for other in u.members:
				# Squadmates keep a shoulder's width but may always step apart.
				if other.index!=member.index and other.hp>0 and next.distance_to(other.pos)<1.3 and next.distance_to(other.pos)<old.distance_to(other.pos):clear=false
			if sim.scenario.get("autonomy",false):clear=clear and actor_clear(u,member,next,sim)
			if clear:member.pos=next
			elif sim.scenario.get("autonomy",false):
				# Individual local steering; retain the chosen cover slot.
				for angle in [0.65,-0.65,1.2,-1.2]:
					var step:Vector2=old+(desired-old).normalized().rotated(angle)*minf(speed*dt,old.distance_to(desired))
					if actor_clear(u,member,step,sim):member.pos=step;break
		sim.relocate_actor(u,member,old)
		member.travel=old.distance_to(member.pos)
		member["regroup_blocked"]=member.get("regroup_blocked",0.0)+dt if member.travel<0.001 and old.distance_to(desired)>0.3 else 0.0
		if member.get("cover_phase","")=="SEEKING":
			member.cover_blocked=member.get("cover_blocked",0.0)+dt if member.travel<0.001 else 0.0
			if member.pos.distance_to(member.cover_goal)<0.2:
				member.cover_phase="SETTLING"
				member["cover_settle_until"]=sim.time+0.45
				member.cover_until=sim.time+4.0
		if member.get("cover_phase","")=="SETTLING" and sim.time>=member.cover_settle_until:
			member.cover_phase="SHELTERED"
			member.cover_deadline=sim.time+8.0
		member.phase+=member.travel*(6.5 if sim.scenario.get("autonomy",false) else 3.0)
		if member.travel>0.001:
			member.facing=(member.pos-old).normalized()
			member.state="MARCHING"
		else:member.state="HOLDING"
		# Preserve the squad's conservative navigation envelope. The leader
		# waits for stragglers instead of dragging soldiers through obstacles.

# A SEVERE casualty: carried with a moving section (at the carry pace), or
# crawling slowly back toward its slot; otherwise it lies still. KIA never move.
static func move_casualty(u:Dictionary,member:Dictionary,sim,dt:float) -> void:
	var old:Vector2=member.pos
	var desired:Vector2=u.pos+member.offset
	var gap:float=old.distance_to(desired)
	member.travel=0.0
	var moving:bool=not u.orders.is_empty() or not u.maneuver.is_empty()
	var speed:=0.0
	if moving and carrying(u) and gap>1.0:
		speed=float(sim.definitions[u.kind].speed)*CARRY_SCALE*sim.terrain.ground_speed(old,"infantry")
		member.state="CARRIED"
	elif gap>2.5 and member.get("medic",-1)<0:
		speed=CRAWL_SPEED
		member.state="CRAWLING"
	else:
		member.state="DOWN"
		return
	var next:Vector2=old.move_toward(desired,speed*dt)
	if not sim.terrain.segment_clear(old,next,"land",0.42):return
	member.pos=next
	member.travel=old.distance_to(next)
	if member.travel>0.001:member.facing=(next-old).normalized()

# Return paths are local, footprint-checked, throttled and tied to the current
# command. A squad pauses before the leash goes taut so actors can round walls.
static func update_regroup(u:Dictionary,sim) -> void:
	var command:int=u.command_group
	if u.get("regroup_command",-1)!=command or u.hold_command:
		u["regroup_command"]=command
		u["regroup_active"]=false
		for member in u.members:
			member["regroup_path"]=[]
			member["regroup_after"]=0.0
	if u.hold_command:return
	if u.pos.distance_to(u.get("regroup_progress_pos",u.pos))>1.0 or not u.has("regroup_progress_at"):
		u["regroup_progress_pos"]=u.pos
		u["regroup_progress_at"]=sim.time
	var stalled_cover:bool=Cover.seeking(u) and sim.time-u.regroup_progress_at>8.0
	# Under fire a soldier holding shelter inside the leash is where Cover put
	# them: pulling the section together would walk everyone into the open.
	# (Fire, not mere enemy knowledge: a known but silent enemy would keep the
	# section split while its anchor waits on the leash.)
	var contact:bool=in_contact(u,sim.time)
	var spread:=0.0
	for member in u.members:
		if member.hp>0 and not (contact and held_shelter(u,member)):spread=maxf(spread,member.pos.distance_to(u.pos))
	if u.get("regroup_active",false):
		if spread<2.8:
			u.regroup_active=false
			u["regroup_count"]=u.get("regroup_count",0)+1
			u["cover_resume_after"]=sim.time+6.0
			u.regroup_progress_at=sim.time
			u.reason="Section reunited · resuming orders"
		# Seeking already pauses the anchor. Let valid shelter trips finish; only
		# recover them when progress times out, rather than at the return threshold.
	elif (not u.orders.is_empty() or not u.maneuver.is_empty()) and ((spread>7.5 and not Cover.seeking(u)) or (stalled_cover and spread>2.8)):
		u["regroup_active"]=true
		u.reason="Regrouping separated soldiers"
		for member in u.members:
			Cover.clear(member)
			member["regroup_path"]=[]
			member["regroup_after"]=0.0

static func held_shelter(u:Dictionary,member:Dictionary) -> bool:
	return member.get("occupying",false) or (member.get("cover_phase","") in ["SETTLING","SHELTERED"] and member.cover_goal.distance_to(u.pos)<=Cover.LEASH)

static func regroup_destination(u:Dictionary,member:Dictionary,sim,goal:Vector2) -> Vector2:
	var route:Array=member.get("regroup_path",[])
	if goal.distance_to(member.get("regroup_goal",goal))>1.0:
		route=[];member["regroup_after"]=0.0
	while not route.is_empty() and member.pos.distance_to(route[0])<0.15:route.pop_front()
	var radius:float=member.get("body_radius",0.8)
	# The obstruction test only matters once the re-plan timer allows a search.
	if sim.time>=member.get("regroup_after",0.0) and (member.get("regroup_blocked",0.0)>0.5 or not sim.terrain.segment_clear(member.pos,goal,"land",radius)):
		member["regroup_after"]=sim.time+1.0
		member["regroup_goal"]=goal
		var avoid:Array=[]
		for entry in sim.actor_candidates(member.pos,goal,Cover.LEASH):
			var other:Dictionary=entry.unit;var peer:Dictionary=entry.actor
			if not sim.alive(other) or peer.hp<=0 or (other.id==u.id and not other.members.is_empty() and peer.index==member.index):continue
			var clearance:float=radius+(float(sim.definitions[other.kind].radius) if other.members.is_empty() else float(peer.get("body_radius",0.8)))-0.04
			# Match actor_clear: soldiers of other sections squeeze past shoulder to shoulder.
			if not other.members.is_empty() and other.id!=u.id:clearance*=0.7
			avoid.append({"pos":peer.pos,"radius":clearance})
		var candidate:Array=sim.terrain.path(member.pos,goal,"land",radius,avoid,"infantry")
		if candidate.is_empty():
			# Tight formations can have a clear exact slot but an occupied nearest
			# grid centre. Approach through a nearby clear centre, checking the
			# final edge as well; never remove peers from avoidance to make it fit.
			var approaches:Array=[]
			var cell:Vector2=goal.floor()+Vector2(0.5,0.5)
			for x in range(-2,3):
				for y in range(-2,3):
					var point:Vector2=cell+Vector2(x,y)
					if point.distance_to(u.pos)>Cover.LEASH or point.distance_to(goal)>3.0:continue
					if not sim.terrain.segment_clear(point,goal,"land",radius) or not sim.terrain.avoids_bodies(point,goal,avoid):continue
					approaches.append({"pos":point,"cost":member.pos.distance_to(point)+point.distance_to(goal)})
			approaches.sort_custom(func(a,b):return a.cost<b.cost)
			for approach in approaches.slice(0,8):
				candidate=sim.terrain.path(member.pos,approach.pos,"land",radius,avoid,"infantry")
				if not candidate.is_empty():
					candidate.append(goal)
					break
		var length:=0.0
		var previous:Vector2=member.pos
		var bounded:=not candidate.is_empty()
		for point in candidate:
			if point.distance_to(u.pos)>Cover.LEASH:bounded=false
			length+=previous.distance_to(point);previous=point
		if bounded and length<=28.0:route=candidate
	member["regroup_path"]=route
	return goal if route.is_empty() else route[0]

static func hit(u:Dictionary,amount:float,source:Vector2,now:float) -> void:
	reconcile(u)
	if u.members.is_empty():
		u.hp-=amount
		return
	var chosen:Dictionary={}
	var nearest:=INF
	for member in u.members:
		if member.hp<=0:continue
		var distance:float=source.distance_squared_to(member.pos)
		if distance<nearest:chosen=member;nearest=distance
	if chosen.is_empty():return
	chosen.hp=maxf(0,chosen.hp-amount)
	chosen.last_hit=now
	chosen.suppression=minf(1,chosen.suppression+0.35)
	chosen.state="DOWN" if chosen.hp<=0 else "BRACING"
	# Legacy HP damage: a hit worth a whole soldier kills outright.
	if chosen.hp<=0 and amount>=chosen.max_hp*0.9:
		external_down(chosen)
		chosen.wound=KIA;chosen.state="KIA";chosen.bleed_at=INF
	publish(u)

# High explosive (shells, rockets, missiles, autocannon): the soldier nearest
# the shooter takes the full hit and others within the blast radius take
# fragment damage, so HE fire breaks up a section instead of chipping one man.
static func blast(u:Dictionary,amount:float,source:Vector2,now:float,radius:float=3.2) -> void:
	reconcile(u)
	if u.members.is_empty():
		u.hp-=amount
		return
	var primary:Dictionary={}
	var nearest:=INF
	for member in u.members:
		if member.hp<=0:continue
		var d:float=source.distance_squared_to(member.pos)
		if d<nearest:primary=member;nearest=d
	if primary.is_empty():return
	for member in u.members:
		if member.hp<=0:continue
		var gap:float=member.pos.distance_to(primary.pos)
		if member!=primary and gap>radius:continue
		var share:float=1.0 if member==primary else 0.6*(1.0-0.5*gap/radius)
		member.hp=maxf(0,member.hp-amount*share)
		member.last_hit=now
		member.suppression=minf(1,member.suppression+0.45)
		member.state="DOWN" if member.hp<=0 else "BRACING"
	publish(u)

static func capacity(u:Dictionary) -> float:
	if u.members.is_empty():return u.max_hp
	var total:=0.0
	for member in u.members:
		if member.hp>0:total+=member.max_hp
	return total

# Medical recovery (aid post / rally point). Treatment goes to SEVERE
# casualties first: TREAT_SHARE*max_hp of care returns one to LIGHT. Living
# soldiers then heal; a LIGHT soldier healed to full is HEALTHY again. The dead
# are never resurrected. Returns the HP-equivalent of care given.
static func recover(u:Dictionary,amount:float) -> float:
	var restored:=0.0
	for member in u.members:
		if member.get("wound",HEALTHY)!=SEVERE or restored>=amount:continue
		var care:=minf(amount-restored,member.max_hp*TREAT_SHARE-float(member.get("treat",0.0)))
		member.treat=float(member.get("treat",0.0))+care
		member.stable=true
		member.bleed_at=INF
		restored+=care
		if member.treat>=member.max_hp*TREAT_SHARE-0.001:
			release(u,member)
			member.wound=LIGHT
			member.treat=0.0
			member.hp=member.max_hp*LIGHT_SHARE
			member.state="HOLDING"
			member.posture="STANDING"
	for member in u.members:
		if member.hp<=0 or restored>=amount:continue
		var heal:=minf(amount-restored,member.max_hp-member.hp)
		member.hp+=heal
		restored+=heal
		if member.get("wound",HEALTHY)==LIGHT and member.hp>=member.max_hp-0.001:member.wound=HEALTHY
	publish(u)
	return restored

static func actor_clear(u:Dictionary,member:Dictionary,to:Vector2,sim) -> bool:
	if not sim.terrain.segment_clear(member.pos,to,"land",member.get("body_radius",0.8)):return false
	if to.distance_to(u.pos)>Cover.LEASH:return false
	var body_radius:float=member.get("body_radius",0.8)
	var min_x:=minf(member.pos.x,to.x)
	var max_x:=maxf(member.pos.x,to.x)
	var min_y:=minf(member.pos.y,to.y)
	var max_y:=maxf(member.pos.y,to.y)
	for entry in sim.actor_candidates(member.pos,to,body_radius):
		var other:Dictionary=entry.unit
		var peer:Dictionary=entry.actor
		if not sim.alive(other) or peer.hp<=0:continue
		# Retain the original squad broad-phase contract exactly.
		if other.pos.x<min_x-12.5 or other.pos.x>max_x+12.5 or other.pos.y<min_y-12.5 or other.pos.y>max_y+12.5:continue
		if other.members.is_empty():
			# Stepping away from a vehicle is always allowed (no mutual lock).
			if to.distance_squared_to(other.pos)>=member.pos.distance_squared_to(other.pos):continue
			if segment_distance(member.pos,to,other.pos)<float(sim.definitions[other.kind].radius)+body_radius:return false
		else:
			if other.id==u.id and peer.index==member.index:continue
			# Soldiers of another section may squeeze past (shoulder to shoulder).
			var clearance:=body_radius+float(peer.get("body_radius",0.8))-0.05
			if other.id!=u.id:clearance*=0.7
			if peer.pos.x<min_x-clearance or peer.pos.x>max_x+clearance or peer.pos.y<min_y-clearance or peer.pos.y>max_y+clearance:continue
			# Never block a step that opens distance: interleaved soldiers can always
			# separate instead of locking each other in place.
			var before:float=member.pos.distance_to(peer.pos)
			var after:float=to.distance_to(peer.pos)
			if after>=before:continue
			# Jammed against another section: brush past it as a last resort, but
			# shoulders never pass through each other.
			if other.id!=u.id and member.get("regroup_blocked",0.0)>0.8 and to.distance_to(peer.pos)>=0.65:continue
			if segment_distance(member.pos,to,peer.pos)<clearance:return false
	return true

# Lateral steering for one soldier. Looks AVOID_AHEAD metres down its heading
# for bodies of other sections (and vehicles) inside a comfortable passing
# lane; returns (steer.x, steer.y, urgency 0..1). Everyone passes on their own
# right when a body is dead ahead, so two oncoming soldiers sidestep apart
# instead of mirroring each other.
const AVOID_AHEAD:=3.5
static func avoidance(u:Dictionary,member:Dictionary,from:Vector2,heading:Vector2,sim,remaining:float=AVOID_AHEAD) -> Vector3:
	var right:=Vector2(-heading.y,heading.x)
	var body:float=member.get("body_radius",0.8)
	var push:=Vector2.ZERO
	var urgency:=0.0
	for entry in sim.actor_candidates(from,from+heading*AVOID_AHEAD,body+0.5):
		var other:Dictionary=entry.unit
		var peer:Dictionary=entry.actor
		if other.id==u.id or not sim.alive(other) or peer.hp<=0:continue
		var relative:Vector2=peer.pos-from
		var ahead:float=relative.dot(heading)
		# Bodies beyond our own slot are not in the way (arrival crowds).
		if ahead<-0.2 or ahead>minf(AVOID_AHEAD,remaining+body):continue
		var lane:float=body+(float(sim.definitions[other.kind].radius)+0.6 if other.members.is_empty() else float(peer.get("body_radius",0.8))+0.35)
		var lateral:float=relative.dot(right)
		if absf(lateral)>=lane:continue
		# Someone walking the same way at a similar pace is not an obstacle.
		var peer_motion:Vector2=peer.get("facing",Vector2.ZERO)*(1.0 if peer.get("travel",0.0)>0.001 else 0.0)
		if peer_motion.dot(heading)>0.7 and ahead>body*2.0:continue
		var side:float=-signf(lateral) if absf(lateral)>0.12 else 1.0
		var weight:float=(1.0-maxf(ahead,0.0)/AVOID_AHEAD)*(1.0-absf(lateral)/lane)
		push+=right*side*weight*1.6
		urgency=maxf(urgency,weight)
	return Vector3(push.x,push.y,urgency)

static func choose_cover(u:Dictionary,member:Dictionary,sim) -> Vector2:
	var best:Vector2=Vector2.ZERO
	var score:float=INF
	for ring in [1.2,2.4,3.6]:
		for index in 12:
			var candidate:Vector2=u.pos+Vector2.from_angle(index*TAU/12)*ring
			if not sim.terrain.cover(candidate) or not actor_clear(u,member,candidate,sim):continue
			var reserved:=false
			for peer in u.members:
				if peer.index!=member.index and peer.hp>0 and peer.cover_goal!=Vector2.ZERO and candidate.distance_to(peer.cover_goal)<1.6:reserved=true
			if reserved:continue
			var cost:float=member.pos.distance_squared_to(candidate)
			if cost<score:score=cost;best=candidate
	return best

static func segment_distance(a:Vector2,b:Vector2,point:Vector2) -> float:
	var delta:=b-a
	return (a+delta*clampf((point-a).dot(delta)/maxf(0.00001,delta.length_squared()),0,1)).distance_to(point)

const PRONE_ROOM:=1.35
static func prone_clear(u:Dictionary,member:Dictionary,sim) -> bool:
	if not sim.terrain.traversable(member.pos,"land",1.15):return false
	for other in sim.units:
		if not sim.alive(other) or sim.definitions[other.kind].domain!="land":continue
		if other.members.is_empty():
			if member.pos.distance_to(other.pos)<1.15+float(sim.definitions[other.kind].radius):return false
		else:
			# Soldiers lie down shoulder to shoulder: a squadmate in the next slot
			# (open-ground spacing is 1.5 u) or a neighbouring section, which may
			# stand as close as actor_clear's squeeze, only blocks when bodies
			# would touch; it must not keep a soldier caught in the open upright.
			var room:float=PRONE_ROOM if other.id==u.id else 1.0
			for peer in other.members:
				if peer.hp>0 and not (other.id==u.id and peer.index==member.index) and member.pos.distance_to(peer.pos)<room:return false
	return true

# Incoming fire (a near miss or hit raises section suppression) stamps
# u.fired_on: the contact drill keeps soldiers low and Cover delays the rush.
const CONTACT_LOW:=4.0
static func note_fire(u:Dictionary,now:float) -> void:
	if u.suppression>float(u.get("pressure_seen",0.0))+0.01 or float(u.last_hit)>float(u.get("hit_seen",-100.0)):u["fired_on"]=now
	u["pressure_seen"]=u.suppression
	u["hit_seen"]=u.last_hit

# A soldier holding still goes flat under heavy suppression, or in contact when
# caught in the open (no shelter within the leash: EXPOSED; or Cover is idle
# for the section, e.g. regrouping or holding, so no shelter is being taken) or
# in crossfire while not (yet) sheltered, where there is room. Callers pre-check
# the cheap conditions; the room check scans every soldier, so a failed one is
# retried twice a second.
static func goes_flat(u:Dictionary,member:Dictionary,sim,contact:bool,phase:String) -> bool:
	if not (maxf(member.suppression,u.suppression)>0.65 or (contact and not member.get("in_trench",false) and (caught_open(member,sim.time) or uncovered(u,member,phase) or (u.get("crossfire",false) and phase!="SETTLING" and phase!="SHELTERED")))):return false
	if member.posture=="PRONE":return true
	if sim.time<float(member.get("prone_retry",0.0)):return false
	if prone_clear(u,member,sim):return true
	member["prone_retry"]=sim.time+0.5
	return false

# No shelter within the leash (Cover marks EXPOSED). The contact drill and
# bounding turn such soldiers to OVERWATCH; they stay in the open meanwhile.
const OPEN_MEMORY:=2.5
static func caught_open(member:Dictionary,now:float) -> bool:
	var phase:String=member.get("cover_phase","")
	if phase=="EXPOSED":
		member["open_at"]=now
		return true
	return phase=="OVERWATCH" and now-float(member.get("open_at",-100.0))<OPEN_MEMORY

# Holding no shelter and not running for one: no cover phase, or overwatching
# in the open while a squadmate rushes (fire and movement: the waiting element
# fires lying down). Not manning works, not in a building or on a work site
# (those keep their own postures).
static func uncovered(u:Dictionary,member:Dictionary,phase:String) -> bool:
	return (phase=="" or phase=="OVERWATCH") and not member.get("occupying",false) and u.get("garrison",-1)<0 and not u.has("building_id")

# Recent incoming fire or lingering suppression: the section is in contact.
static func in_contact(u:Dictionary,now:float) -> bool:
	return now-float(u.get("fired_on",-100.0))<CONTACT_LOW or u.suppression>0.2
