extends SceneTree
# Realistic infantry damage: per-soldier wound states, outcome tables per
# weapon class, bleed-out, buddy aid, aid-post treatment, persistent bodies,
# and measured time-to-incapacitate (printed against the pre-wound baseline).
const Sim=preload("res://scripts/simulation.gd")
const Infantry=preload("res://scripts/infantry.gd")
const Art=preload("res://scripts/visuals.gd")
const Motion=preload("res://scripts/unit_animation.gd")
var failures:Array[String]=[]
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures.append(label)
		printerr("FAIL: ",label)

func harbor_index()->int:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		if configs[i].id=="black_sea_harbor":return i
	return -1

func reset(u:Dictionary)->void:
	for m in u.members:
		m.hp=m.max_hp;m.wound=Infantry.HEALTHY;m.bleed_at=INF;m.aid=0.0;m.stable=false;m.treat=0.0;m.medic=-1;m.aiding=-1;m.state="HOLDING"
	Infantry.publish(u)

func shares(counts:Dictionary,n:int)->String:
	return "KIA %.2f SEVERE %.2f LIGHT %.2f" % [counts.KIA/float(n),counts.SEVERE/float(n),counts.LIGHT/float(n)]

# Outcome of the first hit on a fresh section, through sim.infantry_hit.
func first_hit(sim,shooter:Dictionary,target:Dictionary,scale:float,n:int)->Dictionary:
	var counts:={"KIA":0,"SEVERE":0,"LIGHT":0,"others":0}
	for i in n:
		reset(target)
		var victim:Dictionary=Infantry.exposed_member(target,shooter.pos)
		sim.infantry_hit(shooter,target,sim.damage_amount(shooter,target)*scale,scale)
		counts[victim.wound]+=1
		for m in target.members:
			if m!=victim and m.wound!=Infantry.HEALTHY:counts.others+=1
	return counts

func distributions()->void:
	var sim=Sim.new(false,harbor_index())
	sim.combat_rng.seed=7
	var n:=4000
	var rng:=RandomNumberGenerator.new();rng.seed=11
	for row in [["BULLET",1.0,[0.25,0.40]],["HE",1.0,[0.55,0.35]],["FRAGMENT",1.0,[0.10,0.35]]]:
		var counts:={"KIA":0,"SEVERE":0,"LIGHT":0}
		for i in n:counts[Infantry.roll(row[0],row[1],rng)]+=1
		print("  roll %-8s %s" % [row[0],shares(counts,n)])
		check(absf(counts.KIA/float(n)-row[2][0])<0.03 and absf(counts.SEVERE/float(n)-row[2][1])<0.03,"outcome table "+row[0])
	# Full path: shooter proxies at 8 m from a section in the open.
	var target:Dictionary=sim.spawn("rifle",1,Vector2(300,640))
	var rifle:Dictionary=sim.spawn("rifle",0,Vector2(292,640))
	var proxy:Dictionary=rifle.duplicate();proxy.kind="rifle"
	var open_bullet:=first_hit(sim,proxy,target,0.25,n)
	print("  rifle bullet, open:      ",shares(open_bullet,n))
	check(absf(open_bullet.KIA/float(n)-0.25)<0.03 and absf(open_bullet.SEVERE/float(n)-0.40)<0.03 and open_bullet.others==0,"rifle hit in the open: ~25/40/35, one soldier")
	var engineer:=first_hit(sim,proxy,target,0.1,n)
	print("  engineer carbine, open:  ",shares(engineer,n))
	check(engineer.KIA<open_bullet.KIA*0.6,"weaker rounds are milder")
	var tank:Dictionary=sim.spawn("tank",0,Vector2(286,646))
	var he:=first_hit(sim,tank,target,1.0,n)
	print("  tank HE primary, open:   ",shares(he,n)," fragment wounds per shot %.2f" % (he.others/float(n)))
	check((he.KIA+he.SEVERE)/float(n)>0.85,"HE primary mostly KIA/SEVERE")
	check(he.others>n*0.3,"HE fragments wound neighbours")
	var helo:Dictionary=sim.spawn("helo",0,Vector2(290,632))
	var rocket:=first_hit(sim,helo,target,1.0,n)
	print("  helo HE primary, open:   ",shares(rocket,n))
	check((rocket.KIA+rocket.SEVERE)/float(n)>0.85,"helo fire lethal to infantry")
	# Cover shifts outcomes milder (damage_amount cover factor 0.55) and is harder to hit.
	var exposed_chance:float=sim.hit_chance(proxy,target)
	var covered:Dictionary=sim.spawn("rifle",1,Vector2(300,650))
	var cover_found:=false
	for x in range(40,560,3):
		for y in range(40,760,3):
			var p:=Vector2(x,y)
			if sim.terrain.cover(p) and sim.terrain.traversable(p,"land",0.8):
				covered.pos=p
				for m in covered.members:m.pos=p+m.offset*0.3
				cover_found=sim.terrain.cover(covered.members[0].pos) and sim.terrain.cover(covered.members[1].pos) and sim.terrain.cover(covered.members[2].pos)
				if cover_found:break
		if cover_found:break
	check(cover_found,"cover fixture found")
	var cover_shooter:Dictionary=proxy.duplicate();cover_shooter.pos=covered.pos+Vector2(8,0)
	var in_cover:=first_hit(sim,cover_shooter,covered,0.25,n)
	print("  rifle bullet, in cover:  ",shares(in_cover,n))
	check(in_cover.KIA<open_bullet.KIA*0.75 and in_cover.LIGHT>open_bullet.LIGHT,"cover shifts outcomes milder")
	var shooter_open:Dictionary=proxy.duplicate();shooter_open.pos=target.pos+Vector2(-8,0)
	reset(target);reset(covered)
	var cover_chance:float=sim.hit_chance(cover_shooter,covered)
	var open_chance:float=sim.hit_chance(shooter_open,target)
	print("  hit chance at 8 m: open %.2f cover %.2f" % [open_chance,cover_chance])
	check(cover_chance<open_chance*0.8,"cover lowers the chance of being hit")
	# Posture and range bands.
	var postures:Array=[]
	for posture in ["STANDING","CROUCHED","PRONE"]:
		for m in target.members:m.posture=posture
		postures.append(sim.hit_chance(shooter_open,target))
	for m in target.members:m.posture="STANDING"
	print("  posture hit chance standing/crouched/prone: %.2f / %.2f / %.2f" % postures)
	check(postures[0]>postures[1] and postures[1]>postures[2],"smaller posture is harder to hit")
	var bands:Array=[]
	for gap in [3.0,10.0,13.0]:
		shooter_open.pos=target.pos+Vector2(-gap,0)
		bands.append(sim.hit_chance(shooter_open,target))
	print("  rifle hit chance at 3/10/13 m: %.2f / %.2f / %.2f" % bands)
	check(bands[0]>bands[1] and bands[1]>bands[2],"range bands")
	var light:Dictionary=shooter_open.duplicate();light["accuracy"]=Infantry.LIGHT_ACCURACY
	check(sim.hit_chance(light,target)<bands[2]*0.8,"wounded shooter less accurate")
	check(sim.hit_chance(tank,target)>bands[0]*1.5,"HE far more likely to hit than aimed rifle fire")
	# Second light wound -> SEVERE.
	reset(target)
	var m0:Dictionary=target.members[0]
	Infantry.wound(target,m0,Infantry.LIGHT,sim.time,sim.combat_rng)
	check(m0.wound==Infantry.LIGHT and is_equal_approx(m0.hp,m0.max_hp*Infantry.LIGHT_SHARE),"LIGHT keeps half a soldier on the bar")
	Infantry.wound(target,m0,Infantry.LIGHT,sim.time,sim.combat_rng)
	check(m0.wound==Infantry.SEVERE and m0.hp==0 and m0.bleed_at>=sim.time+45 and m0.bleed_at<=sim.time+90,"second LIGHT becomes SEVERE with a 45-90 s bleed timer")
	Infantry.publish(target)
	check(is_equal_approx(target.hp,target.members[1].max_hp*2),"section bar = combat-effective soldiers")

func lone_section(scenario:int)->Array:
	var sim=Sim.new(false,scenario)
	var u:Dictionary=sim.spawn("rifle",0,Vector2(300,640))
	return [sim,u]

func bleeding_and_aid()->void:
	# Under fire (no aid possible): bleeds out between 45 and 90 s.
	var pair:=lone_section(harbor_index())
	var sim=pair[0];var u:Dictionary=pair[1]
	var casualty:Dictionary=u.members[1]
	Infantry.wound(u,casualty,Infantry.SEVERE,sim.time,sim.combat_rng)
	Infantry.publish(u)
	var started:float=sim.time
	var died:=-1.0
	for i in 100*30:
		u.last_hit=sim.time
		sim.tick(1.0/30);sim.events.clear()
		if casualty.wound==Infantry.KIA:died=sim.time-started;break
	print("  bleed-out under fire after %.1f s" % died)
	check(died>=45.0 and died<=90.5,"untreated SEVERE bleeds out in 45-90 s")
	check(sim.alive(u) and u.members.filter(func(m):return m.hp>0).size()==2,"section fights on with two")
	# Quiet: a buddy reaches the casualty and stops the bleeding after ~8 s of aid.
	pair=lone_section(harbor_index())
	sim=pair[0];u=pair[1]
	casualty=u.members[2]
	casualty.pos+=Vector2(2.0,1.0)
	Infantry.wound(u,casualty,Infantry.SEVERE,sim.time,sim.combat_rng)
	Infantry.publish(u)
	var stable_at:=-1.0
	var medic_seen:=false
	var no_fire_while_aiding:=true
	for i in 120*30:
		sim.tick(1.0/30);sim.events.clear()
		for m in u.members:
			if m.get("aiding",-1)>=0:
				medic_seen=true
				if m.state=="FIRING":no_fire_while_aiding=false
		if casualty.stable and stable_at<0:stable_at=sim.time
	print("  buddy aid stabilised the casualty at %.1f s" % stable_at)
	check(medic_seen and no_fire_while_aiding,"a squadmate gives buddy aid")
	check(stable_at>=Infantry.AID_SECONDS and stable_at<=Infantry.AID_SECONDS+8.0,"buddy aid takes ~8 s")
	check(casualty.wound==Infantry.SEVERE and casualty.bleed_at==INF and sim.time>90.0,"aided casualty survives past the bleed window (still SEVERE)")
	check(u.members.all(func(m):return m.get("aiding",-1)<0),"medic released after aid")
	# Heavy fire interrupts aid.
	pair=lone_section(harbor_index())
	sim=pair[0];u=pair[1]
	casualty=u.members[0]
	Infantry.wound(u,casualty,Infantry.SEVERE,sim.time,sim.combat_rng)
	Infantry.publish(u)
	for i in 20*30:
		u.suppression=0.9
		sim.tick(1.0/30);sim.events.clear()
	check(casualty.aid==0.0 and not casualty.stable,"no buddy aid under heavy fire")

func aid_post_and_bodies()->void:
	# Aid post semantics (field_ops calls Infantry.recover(ally, dt*6)).
	var pair:=lone_section(harbor_index())
	var sim=pair[0];var u:Dictionary=pair[1]
	var severe:Dictionary=u.members[0]
	var dead:Dictionary=u.members[1]
	Infantry.wound(u,severe,Infantry.SEVERE,sim.time,sim.combat_rng)
	Infantry.wound(u,dead,Infantry.KIA,sim.time,sim.combat_rng)
	Infantry.publish(u)
	var t:=0.0
	var light_at:=-1.0
	var healthy_at:=-1.0
	while t<60.0:
		Infantry.recover(u,6.0/30.0);t+=1.0/30.0
		if light_at<0 and severe.wound==Infantry.LIGHT:light_at=t
		if healthy_at<0 and severe.wound==Infantry.HEALTHY:healthy_at=t
	print("  aid post: SEVERE->LIGHT %.1f s, ->HEALTHY %.1f s" % [light_at,healthy_at])
	check(light_at>8.0 and light_at<20.0,"aid post treats SEVERE back to LIGHT over time")
	check(healthy_at>light_at,"treated soldier recovers fully afterwards")
	check(dead.wound==Infantry.KIA and dead.hp==0,"aid post never resurrects the dead")
	check(is_equal_approx(u.hp,Infantry.capacity(u)),"recover() still tops up to capacity")
	# Real aid post in a field-ops fixture.
	var field=Sim.new(false,5)
	field.terrain.blocks.clear();field.terrain.roadside_blocks.clear();field.terrain.trees.clear();field.terrain.poles.clear()
	field.terrain.navigation.clear()
	var section:Dictionary=field.spawn("rifle",0,Vector2(14,97))
	field.spawn("aid_post",0,Vector2(23,97))
	Infantry.wound(section,section.members[2],Infantry.SEVERE,field.time,field.combat_rng)
	Infantry.publish(section)
	for i in 25*30:field.tick(1.0/30);field.events.clear()
	check(section.members[2].wound in [Infantry.LIGHT,Infantry.HEALTHY],"field aid post treats a SEVERE casualty")
	# Bodies persist, are never targeted, and the section dies when none can fight.
	pair=lone_section(harbor_index())
	sim=pair[0];u=pair[1]
	var enemy:Dictionary=sim.spawn("rifle",1,Vector2(308,640))
	enemy["hold_command"]=true;u["hold_command"]=true
	var shooter:Dictionary=enemy.duplicate();shooter.kind="rifle"
	Infantry.wound(u,u.members[0],Infantry.KIA,sim.time,sim.combat_rng)
	var body:Vector2=u.members[0].pos
	for i in 200:
		sim.infantry_hit(shooter,u,3.75,0.25)
		if not sim.alive(u) or u.get("combat_ineffective",false):break
	check(u.members[0].wound==Infantry.KIA,"body stays KIA")
	check(not sim.alive(u) or u.get("combat_ineffective",false),"section out of the fight once no soldier can fight (survivors keep it selectable)")
	check(u.members.all(func(m):return m.wound in [Infantry.SEVERE,Infantry.KIA] and m.hp==0),"every record is a casualty, none removed")
	check(Infantry.has_remains(u),"remains reported for presentation")
	for i in 90:sim.tick(1.0/30);sim.events.clear()
	check(u.members[0].pos==body,"KIA body never moves")
	check(not sim.can_fire(enemy,u) or not sim.auto_target_ok(enemy,u),"knocked-out section is not auto-targeted")
	# Within a living section a corpse is never the soldier struck or selectable.
	pair=lone_section(harbor_index())
	sim=pair[0];u=pair[1]
	Infantry.wound(u,u.members[0],Infantry.KIA,sim.time,sim.combat_rng)
	var near:Dictionary=sim.spawn("rifle",1,u.members[0].pos+Vector2(0,-6))
	check(Infantry.exposed_member(u,near.pos)!=u.members[0],"shots strike the living, not bodies")
	check(u.members[0].hp<=0,"click selection ignores bodies (hp 0)")
	check(sim.alive(u),"section with survivors still alive")

func carrying()->void:
	var displacement:Array=[]
	for wounded in [false,true]:
		var pair:=lone_section(harbor_index())
		var sim=pair[0];var u:Dictionary=pair[1]
		if wounded:
			Infantry.wound(u,u.members[2],Infantry.SEVERE,sim.time,sim.combat_rng)
			Infantry.publish(u)
		var start:Vector2=u.pos
		sim.issue([u.id],start+Vector2(0,-30),"move")
		for i in 3*30:sim.tick(1.0/30);sim.events.clear()
		displacement.append(u.pos.distance_to(start))
		if wounded:
			check(u.members[2].pos.distance_to(u.pos)<4.0,"casualty carried along with the section")
	print("  3 s march: %.1f m healthy, %.1f m carrying a casualty" % displacement)
	check(displacement[1]<displacement[0]*0.75 and displacement[1]>displacement[0]*0.4,"carrying wounded slows the section")
	# LIGHT walks ~25% slower.
	var pair:=lone_section(harbor_index())
	var sim=pair[0];var u:Dictionary=pair[1]
	Infantry.wound(u,u.members[1],Infantry.LIGHT,sim.time,sim.combat_rng)
	var slow:Dictionary=u.members[1]
	var fast:Dictionary=u.members[0]
	var a:Vector2=slow.pos;var b:Vector2=fast.pos
	for m in [slow,fast]:m.offset+=Vector2(0,-8)
	for i in 30:sim.tick(1.0/30);sim.events.clear()
	check(slow.pos.distance_to(a)<fast.pos.distance_to(b)*0.85,"LIGHT soldier walks slower")

# Mean over seeds: first soldier down and section incapacitated.
func duel(kind:String,gap:float,seed:int)->Array:
	var sim=Sim.new(false,harbor_index())
	sim.combat_rng.seed=seed
	var attacker:Dictionary=sim.spawn(kind,0,Vector2(300-gap,640))
	var rifle:Dictionary=sim.spawn("rifle",1,Vector2(300,640))
	rifle["hold_command"]=true;attacker["hold_command"]=true
	# A distant reserve keeps the sim running (no DEFEAT) if the attacker falls.
	sim.spawn("rifle",0,Vector2(120,700))["hold_command"]=true
	var first:=INF
	for i in 60*30:
		sim.tick(1.0/30);sim.events.clear()
		# First soldier down on either side (the rifle duel is symmetric).
		if first==INF and (rifle.members.any(func(m):return m.hp<=0) or attacker.get("members",[]).any(func(m):return m.hp<=0)):first=sim.time
		if not sim.alive(rifle) or rifle.get("combat_ineffective",false) or (kind=="rifle" and (not sim.alive(attacker) or attacker.get("combat_ineffective",false))):return [first,sim.time]
	return [first,INF]

func timing()->void:
	# Measured on the pre-wound baseline (HEAD c69074d) with this same duel():
	var before:={"rifle":[12.57,"48.1 s in 5/6"],"tank":[4.70,"7.1 s in 6/6"],"helo":[3.38,"5.1 s in 6/6"]}
	for row in [["rifle",10.0],["tank",15.0],["helo",12.0]]:
		var first:=0.0;var dead:=0.0;var n:=6;var finished:=0
		for k in n:
			var r:=duel(row[0],row[1],100+k)
			first+=minf(r[0],60.0)
			if r[1]<INF:dead+=r[1];finished+=1
		first/=n
		var dead_mean:=dead/maxi(1,finished)
		print("  %s vs rifle section at %d m: first man down %.1f s (before %.1f), first section incapacitated %s (before %s)" % [row[0],int(row[1]),first,before[row[0]][0],("%.1f s in %d/%d" % [dead_mean,finished,n]),str(before[row[0]][1])])
		if row[0]=="rifle":check(first<=5.0,"rifle section in the open at 10 m loses a man within a few seconds")
		else:check(first<=4.0 and finished==n and dead_mean<=12.0,row[0]+" clearly lethal to infantry")

func blast()->void:
	var sim=Sim.new(false,harbor_index())
	sim.combat_rng.seed=5
	var u:Dictionary=sim.spawn("rifle",1,Vector2(300,640))
	var counts:={"KIA":0,"SEVERE":0,"LIGHT":0,"HEALTHY":0}
	var n:=600
	for i in n:
		reset(u)
		sim.infantry_blast(u,u.members[0].pos,4.0)
		counts[u.members[0].wound]+=1
	print("  point blast on a soldier: KIA %.2f SEVERE %.2f LIGHT %.2f unhurt %.2f" % [counts.KIA/float(n),counts.SEVERE/float(n),counts.LIGHT/float(n),counts.HEALTHY/float(n)])
	check((counts.KIA+counts.SEVERE)/float(n)>0.8,"blast at a soldier's feet is mostly KIA/SEVERE")
	reset(u)
	check(not sim.infantry_blast(u,u.pos+Vector2(20,0),4.0) and u.members.all(func(m):return m.wound==Infantry.HEALTHY),"blast outside radius harmless")

func presentation()->void:
	var stage:=Node3D.new()
	root.add_child(stage)
	for scenario in [0,harbor_index()]:
		var sim=Sim.new(false,scenario)
		var u:Dictionary=sim.spawn("rifle",0,Vector2(300,640) if scenario>0 else Vector2(15,60))
		var visual:Node3D=Art.new().make_unit(stage,u)
		var model:Node3D=visual.get_node("Model")
		Infantry.wound(u,u.members[0],Infantry.SEVERE,sim.time,sim.combat_rng)
		Infantry.wound(u,u.members[1],Infantry.KIA,sim.time,sim.combat_rng)
		Infantry.wound(u,u.members[2],Infantry.LIGHT,sim.time,sim.combat_rng)
		Infantry.publish(u)
		for frame in 30:
			sim.time+=0.1
			Motion.pose(model,u,sim,0.1)
		var soldiers:Array=[model.get_node("Soldier0"),model.get_node("Soldier1"),model.get_node("Soldier2")]
		check(soldiers.all(func(s):return s.visible),"wounded and dead soldiers stay visible")
		var upper:Array=soldiers.map(func(s):return (s.get_node("Upper") as Node3D).rotation)
		check(absf(upper[0].x+PI/2)<0.1 and absf(upper[1].x+PI/2)<0.1,"SEVERE and KIA lie on the ground")
		check(upper[1].z>upper[0].z,"KIA rolled further than SEVERE")
		check(upper[2].x<-0.15 and upper[2].x>-0.6,"LIGHT hunches but stays up")
		var meshes:Array=soldiers[1].find_children("*","MeshInstance3D",true,false)
		check(not meshes.is_empty() and meshes.all(func(m):return m.material_override==Motion.corpse_material),"KIA body darkened")
		check(soldiers[0].find_children("*","MeshInstance3D",true,false).all(func(m):return m.material_override!=Motion.corpse_material),"wounded soldier keeps live paint")
		# Treated back to LIGHT: stands again.
		Infantry.recover(u,u.members[0].max_hp*Infantry.TREAT_SHARE)
		for frame in 20:
			sim.time+=0.1
			Motion.pose(model,u,sim,0.1)
		check(u.members[0].wound==Infantry.LIGHT and (soldiers[0].get_node("Upper") as Node3D).rotation.x>-0.6,"treated casualty gets up")
		visual.free()
	stage.free()

func _init()->void:call_deferred("run")
func run()->void:
	print("distributions:")
	distributions()
	print("bleeding and aid:")
	bleeding_and_aid()
	print("aid post and bodies:")
	aid_post_and_bodies()
	print("carrying:")
	carrying()
	print("blast helper:")
	blast()
	print("presentation:")
	presentation()
	print("time to incapacitate:")
	timing()
	print("WOUNDS: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
