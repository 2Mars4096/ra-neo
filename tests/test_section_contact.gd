extends SceneTree
# Section reaction to contact on the showcase map (the regroup mission's map):
# casualties under fire stop an attack-move (consolidate) unless the order is an
# explicit move; buddy aid is given in the open only without incoming fire, and
# under fire the casualty is dragged to cover first; a section with no cover in
# reach under sustained fire bounds to real cover unless holding.
const Sim=preload("res://scripts/simulation.gd")
const Infantry=preload("res://scripts/infantry.gd")
# Open field west of the villa: no shelter inside the leash, cover 13 u away.
const FIELD:=Vector2(10,34)
const FIELD_ENEMY:=Vector2(14.4,44.6)
# North of the villa: open ground with the villa's north wall face (y 12.95)
# about 4 u south, screened from rifles at the villa post.
const YARD:=Vector2(44.5,8.8)
const VILLA_ENEMY:=Vector2(34.41422,24.41421)
# Pause until incoming fire has stopped this long; bound after this much
# sustained fire (TacticalQUIET / BOUND_AFTER).
const QUIET:=6.0
const SUSTAINED:=7.0
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func showcase()->int:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		if configs[i].id=="showcase":return i
	return -1

func field()->Object:
	var sim=Sim.new(false,showcase())
	# A friendly unit far off keeps the mission running if a section is lost.
	sim.spawn("rifle",0,Vector2(12,90))
	return sim

func step(sim,seconds:float,each:Callable=Callable())->void:
	for i in int(round(seconds*30)):
		sim.tick(1.0/30);sim.events.clear()
		if each.is_valid():each.call()

func silence(enemy:Dictionary)->void:
	enemy.cooldown=100000.0
	for m in enemy.members:m.cooldown=100000.0

# An anti-tank section advancing on a tank loses its launcher to the tank's
# fire: with an attack-move it stops and consolidates; with a move it goes on.
func consolidate(order:String)->void:
	var sim=field()
	var u:Dictionary=sim.spawn("atgm",0,Vector2(10,28))
	var tank:Dictionary=sim.spawn("tank",1,Vector2(12,47))
	sim.stop([tank.id])
	check(sim.issue([u.id],Vector2(10,62),order)==1,"%s order accepted"%order)
	var hit:=-1.0
	for i in 300:
		sim.tick(1.0/30);sim.events.clear()
		if float(u.get("fired_on",-100.0))>0:hit=sim.time;break
	check(hit>0,"%s: the tank opens fire on the section"%order)
	# The launcher is killed; the surviving rifleman cannot hurt the tank, which
	# then holds its fire so the section survives to show what it does next.
	Infantry.wound(u,u.members[0],Infantry.KIA,sim.time,sim.combat_rng);Infantry.publish(u)
	silence(tank)
	u.last_hit=sim.time
	var start:Vector2=u.pos
	step(sim,1.0)
	var phase:String=u.maneuver.get("phase","")
	step(sim,3.0)
	var advanced:float=u.pos.distance_to(start)
	print("  %s: casualty at %.1f s, phase after 1 s=%s, anchor moved %.1f u in 4 s"%[order,hit,phase,advanced])
	if order=="attack_move":
		check(phase=="CONSOLIDATE","attack-move: casualties under fire consolidate within 1 s")
		check(advanced<1.0,"attack-move: the anchor stops advancing toward the threat")
		var resumed:=-1.0
		var held:Vector2=u.pos
		for i in 20*30:
			sim.tick(1.0/30);sim.events.clear()
			if resumed<0 and u.maneuver.is_empty():resumed=sim.time-hit
		print("  attack-move: resumed %.1f s after the casualty, now %.1f u on"%[resumed,u.pos.distance_to(held)])
		check(resumed>=QUIET and resumed<=QUIET+4.0,"attack-move: resumes once incoming fire has stopped for a while")
		var carried:bool=(u.orders.size()==1 and u.orders[0].mode=="attack_move") or (u.orders.is_empty() and u.pos.distance_to(Vector2(10,62))<3.0)
		check(carried and u.pos.distance_to(held)>2.0,"attack-move: the original order carries on")
	else:
		check(phase=="","explicit move: no consolidation")
		check(advanced>3.0,"explicit move: the section keeps moving as ordered")

# Buddy aid: a casualty lying in the open under fire is dragged to the wall
# (no aid while it lies in the open under fire), then treated there.
func drag_to_cover()->void:
	var sim=field()
	var u:Dictionary=sim.spawn("rifle",0,YARD)
	var enemy:Dictionary=sim.spawn("rifle",1,VILLA_ENEMY)
	var casualty:Dictionary=u.members[1]
	var in_open:bool=not sim.terrain.cover(casualty.pos)
	check(in_open and sim.terrain.line_clear(VILLA_ENEMY,casualty.pos),"drag fixture: the casualty-to-be stands in the open in the enemy's sight")
	var fired:=-1.0
	for i in 300:
		sim.tick(1.0/30);sim.events.clear()
		if float(u.get("fired_on",-100.0))>0:fired=sim.time;break
	check(fired>0,"drag fixture: the section comes under fire")
	Infantry.wound(u,casualty,Infantry.SEVERE,sim.time,sim.combat_rng);Infantry.publish(u)
	var open_aid:=false
	var dragged:=-1.0
	var covered:=-1.0
	var aid_seen:=0.0
	for i in 40*30:
		var before:float=casualty.aid
		var under_fire:bool=sim.time-float(u.get("fired_on",-100.0))<Infantry.AID_QUIET
		var was_open:bool=not sim.terrain.cover(casualty.pos)
		sim.tick(1.0/30);sim.events.clear()
		if casualty.wound!=Infantry.SEVERE:break
		if casualty.aid>before and under_fire and was_open and not sim.terrain.cover(casualty.pos):open_aid=true
		if dragged<0 and casualty.get("state","")=="DRAGGED":dragged=sim.time-fired
		if covered<0 and sim.terrain.cover(casualty.pos):covered=sim.time-fired
		aid_seen=maxf(aid_seen,casualty.aid)
		if casualty.stable:break
	print("  drag: dragged at %.1f s, in cover at %.1f s, stable=%s aid=%.1f wound=%s enemy hp=%.0f"%[dragged,covered,casualty.stable,aid_seen,casualty.wound,enemy.hp])
	check(not open_aid,"no aid is given in the open while rounds come in")
	check(dragged>=0 and covered>=0,"the casualty is dragged into cover")
	check(casualty.stable,"the casualty is treated and stabilised")

# No cover within drag reach and the fire keeps coming: nobody kneels in the
# open over the casualty; the section fights on.
func no_aid_in_open()->void:
	var sim=field()
	var u:Dictionary=sim.spawn("rifle",0,FIELD)
	var enemy:Dictionary=sim.spawn("rifle",1,FIELD_ENEMY)
	var casualty:Dictionary=u.members[1]
	Infantry.wound(u,casualty,Infantry.SEVERE,sim.time,sim.combat_rng);Infantry.publish(u)
	var open_aid:=false
	var aiding_under_fire:=0.0
	for i in 12*30:
		var before:float=casualty.aid
		# Fire the section already knew of when it stepped (aid is applied before
		# the tick's own incoming rounds are noted).
		var under_fire:bool=sim.time-float(u.get("fired_on",-100.0))<Infantry.AID_QUIET
		sim.tick(1.0/30);sim.events.clear()
		if under_fire and casualty.aid>before:open_aid=true
		if under_fire and u.members.any(func(m):return m.hp>0 and m.get("state","") in ["AIDING","DRAGGING"]):aiding_under_fire+=1.0/30
	print("  open field casualty: aid under fire=%s, aiding/dragging under fire %.1f s, enemy hp=%.0f"%[open_aid,aiding_under_fire,enemy.hp])
	check(float(u.get("fired_on",-100.0))>0,"open-field aid fixture comes under fire")
	check(not open_aid and aiding_under_fire==0.0,"no buddy aid in the open under fire")

# Sustained fire with no cover inside the leash: prone first, then a bound to
# the cover 13 u away. The section holds its own fire so the enemy keeps
# shooting (as from beyond its reach).
func bound(hold:bool)->void:
	var sim=field()
	var u:Dictionary=sim.spawn("rifle",0,FIELD)
	var enemy:Dictionary=sim.spawn("rifle",1,FIELD_ENEMY)
	if hold:sim.stop([u.id])
	var first:=-1.0
	var prone:=-1.0
	var bound_at:=-1.0
	var sheltered:=-1.0
	for i in 30*30:
		for m in u.members:m.cooldown=maxf(m.cooldown,10.0)
		sim.tick(1.0/30);sim.events.clear()
		if first<0 and float(u.get("fired_on",-100.0))>0:first=sim.time
		if first<0:continue
		if prone<0 and u.members.all(func(m):return m.hp<=0 or m.posture=="PRONE" or m.get("cover_phase","") in ["SEEKING","SETTLING","SHELTERED"]):prone=sim.time-first
		if bound_at<0 and u.maneuver.get("phase","")=="BOUND":bound_at=sim.time-first
		if sheltered<0 and u.members.any(func(m):return m.hp>0 and m.get("cover_phase","") in ["SETTLING","SHELTERED"]):sheltered=sim.time-first
	var label:="hold" if hold else "idle"
	print("  %s: first fire %.1f s, prone %.1f s, bound %.1f s, sheltered %.1f s, anchor %.1f u from start, living %d"%[label,first,prone,bound_at,sheltered,u.pos.distance_to(FIELD),u.members.filter(func(m):return m.hp>0).size()])
	check(first>0,"%s: the section comes under sustained fire"%label)
	check(prone>=0 and prone<=1.0,"%s: prone (or running for cover) within 1 s"%label)
	if hold:
		check(bound_at<0 and u.pos.distance_to(FIELD)<1.0,"hold: the section holds its ground (no bound)")
	else:
		check(bound_at>=SUSTAINED-0.5 and bound_at<=SUSTAINED+3.0,"idle: bounds to cover after sustained fire, not at once")
		check(sheltered>bound_at and u.pos.distance_to(FIELD)>8.0,"idle: the section reaches real cover beyond the leash")

func _init()->void:
	consolidate("attack_move")
	consolidate("move")
	drag_to_cover()
	no_aid_in_open()
	bound(false)
	bound(true)
	print("SECTION CONTACT: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
