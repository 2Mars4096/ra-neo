extends SceneTree
# Enemy defenders garrison buildings near their objectives (field_ops.enemy_garrisons):
# sites near each objective, half the local infantry walks in, fire from the
# windows, re-garrison after a collapse, wave attackers never garrison, cheap.
const Sim=preload("res://scripts/simulation.gd")
const FieldOps=preload("res://scripts/field_ops.gd")
const Garrison=preload("res://scripts/garrison.gd")
const StructureDamage=preload("res://scripts/structure_damage.gd")
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func harbor_index()->int:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		if configs[i].id=="black_sea_harbor":return i
	return -1

func run(sim,seconds:float)->void:
	for i in int(seconds*30.0):sim.tick(1.0/30)

func defenders(sim)->Array:
	return sim.units.filter(func(u):return sim.alive(u) and u.team==1 and u.kind in ["rifle","atgm"] and not u.members.is_empty())

func gap(building:Dictionary,p:Vector2)->float:
	var b:Rect2=building.bounds
	return Vector2(clampf(p.x,b.position.x,b.end.x),clampf(p.y,b.position.y,b.end.y)).distance_to(p)

func _init()->void:
	var sim=Sim.new(true,harbor_index())
	var buildings:Array=Garrison.index(sim).buildings
	var t0:=Time.get_ticks_usec()
	var sites:Array=FieldOps.garrison_sites(sim)
	var site_us:=Time.get_ticks_usec()-t0
	check(sites.size()==sim.objectives.size(),"sites scored for every objective")
	for i in sites.size():
		check(not sites[i].is_empty(),"objective %d has garrison sites (%d)" % [i,sites[i].size()])
		check(sites[i].all(func(s):return gap(buildings[s.id],sim.objectives[i].pos)<=FieldOps.GARRISON_RADIUS),"objective %d sites within %.0f m" % [i,FieldOps.GARRISON_RADIUS])
		print("objective %d %s: %d sites, best score %.2f" % [i,sim.objectives[i].pos,sites[i].size(),sites[i][0].score if not sites[i].is_empty() else -1.0])

	# Setup: the first decision sends defenders toward buildings; they are inside within ~30 s.
	run(sim,1.0)
	var bound:Array=defenders(sim).filter(func(u):return u.get("garrison_role",false))
	check(not bound.is_empty(),"defenders assigned to buildings at setup (%d)" % bound.size())
	run(sim,30.0)
	var inside:Array=defenders(sim).filter(func(u):return Garrison.inside(u))
	print("after 31 s: %d sections garrisoned, %d with the role" % [inside.size(),defenders(sim).filter(func(u):return u.get("garrison_role",false)).size()])
	for i in sim.objectives.size():
		var objective:Vector2=sim.objectives[i].pos
		var local:Array=defenders(sim).filter(func(u):return u.home.distance_to(objective)<=FieldOps.GARRISON_POST_RADIUS)
		var held:Array=local.filter(func(u):return Garrison.inside(u))
		check(not held.is_empty(),"objective %d: defenders hold a building (%d of %d sections)" % [i,held.size(),local.size()])
		check(local.filter(func(u):return u.get("garrison_role",false)).size()<=ceili(local.size()*FieldOps.GARRISON_SHARE),"objective %d: at most half the local infantry garrisons" % i)
		check(local.size()-held.size()>=1,"objective %d: a section stays out for counterattacks" % i)
		check(held.all(func(u):return gap(buildings[int(u.garrison)],objective)<=FieldOps.GARRISON_RADIUS),"objective %d: garrisoned buildings near the objective" % i)
	var per_building:Dictionary={}
	for u in inside:per_building[int(u.garrison)]=int(per_building.get(int(u.garrison),0))+1
	check(per_building.values().all(func(n):return n<=FieldOps.GARRISON_PER_BUILDING),"no more than %d enemy sections per building" % FieldOps.GARRISON_PER_BUILDING)
	check(inside.all(func(u):return int(buildings[int(u.garrison)].state)==0 and u.members.all(func(m):return m.hp<=0 or m.get("indoors",false))),"garrisons sit in intact buildings with soldiers indoors")

	# Windows fire: a player section in the open near an enemy-held building is
	# engaged from the windows, and the defenders stay inside rather than sallying.
	var fired:=false
	if not inside.is_empty():
		var holder:Dictionary=inside[0]
		var building:Dictionary=buildings[int(holder.garrison)]
		var center:Vector2=building.bounds.get_center()
		var target:Dictionary={}
		for k in 24:
			var dir:=Vector2.RIGHT.rotated(TAU*k/24.0)
			var p:Vector2=center+dir*(maxf(building.bounds.size.x,building.bounds.size.y)*0.5+11.0)
			if not sim.terrain.traversable(p,"land",2.65) or sim.terrain.is_water(p):continue
			if not holder.members.any(func(m):return m.hp>0 and sim.terrain.line_clear(m.pos,p)):continue
			target=sim.spawn("rifle",0,p)
			if not target.is_empty() and target.pos.distance_to(p)<2.0:break
			if not target.is_empty():target.hp=0
			target={}
		check(not target.is_empty(),"player fixture in the open beside an enemy-held building")
		if not target.is_empty():
			target.hold_command=true
			var before:float=target.hp
			run(sim,10.0)
			fired=target.hp<before or target.suppression>0.3
			check(fired,"garrisoned enemy fires from the windows (hp %.0f->%.0f, supp %.2f)" % [before,target.hp,target.suppression])
			check(Garrison.inside(holder),"garrison holds the building under contact (state %s)" % holder.state)
			target.hp=0

	# Collapse: survivors are thrown out and take another nearby building, or rejoin the QRF.
	var holders:Array=defenders(sim).filter(func(u):return Garrison.inside(u))
	if not holders.is_empty():
		var victim:Dictionary=holders[0]
		var lost:int=int(victim.garrison)
		StructureDamage.collapse(sim,lost)
		check(not sim.alive(victim) or not Garrison.inside(victim),"collapse evicts the garrison")
		if sim.alive(victim):
			sim.field_ops.garrison_next=0.0
			run(sim,0.2)
			var next:int=int(victim.get("garrison_target",victim.get("garrison",-1)))
			var near:bool=FieldOps.nearest_site(sim,victim,sites[0]+sites[1]+sites[2],func(b):return int(buildings[b].state)==0)>=0
			print("evicted section %d: role %s, next building %d (lost %d)" % [victim.id,victim.get("garrison_role",false),next,lost])
			check(next!=lost,"never re-enters the collapsed building")
			if victim.get("combat_ineffective",false):
				# The seeded collapse leaves this ATGM section with a severely
				# wounded survivor. Alive/selectable does not mean able to walk.
				check(next<0 and victim.orders.is_empty() and not victim.get("garrison_role",false),"downed collapse survivors do not receive impossible garrison orders")
				# Positive control: normal medical recovery makes the same
				# survivor able to enter an available nearby building again.
				sim.Infantry.recover(victim,victim.max_hp*3.0)
				check(not victim.get("combat_ineffective",false),"medical treatment restores an able collapse survivor")
				sim.field_ops.garrison_next=0.0
				run(sim,0.2)
				next=int(victim.get("garrison_target",victim.get("garrison",-1)))
				check(next>=0 and next!=lost and int(buildings[next].state)==0,"recovered collapse survivor re-garrisons an intact nearby building")
			else:
				check((next>=0 and int(buildings[next].state)==0) or (not near and not victim.get("garrison_role",false)),"able evicted section re-garrisons a nearby intact building")
		else:print("evicted section buried in the collapse; re-garrison path not exercised here")

	# Wave attackers and the counterattack reserve never garrison.
	var war=Sim.new(true,harbor_index())
	war.time=float(war.scenario.enemy_waves.first)+0.1
	FieldOps.enemy_offensive(war)
	var wave:Array=war.field_ops.waves.active.duplicate()
	check(not wave.is_empty(),"wave fixture spawned")
	# Park the wave on an objective so only the exclusion keeps it out of buildings.
	for id in wave:
		var u:Dictionary=war.get_unit(id)
		u.home=war.objectives[0].pos;u.orders=[];u.path=[]
	war.field_ops.garrison_next=0.0
	FieldOps.enemy_garrisons(war)
	check(wave.all(func(id):var u:Dictionary=war.get_unit(id);return not u.get("garrison_role",false) and not u.has("garrison_target")),"wave attackers are never garrisoned")

	# Mortar: a seen cluster of player infantry in range draws a warned HE salvo.
	var fire=Sim.new(true,harbor_index())
	var post:Dictionary=fire.units.filter(func(u):return u.team==1 and u.kind=="command_post")[0]
	var aim:=Vector2(-1,-1)
	for k in 36:
		var p:Vector2=post.pos+Vector2.RIGHT.rotated(TAU*k/36.0)*120.0
		if not fire.terrain.traversable(p,"land",2.65) or fire.terrain.is_water(p):continue
		if fire.units.any(func(o):return o.team==1 and not o.get("structure",false) and o.pos.distance_to(p)<30.0):continue
		aim=p;break
	check(aim.x>=0,"open ground in mortar range for the cluster fixture")
	var cluster:Array=[]
	for offset in [Vector2.ZERO,Vector2(6,0),Vector2(0,6)]:
		var s:Dictionary=fire.spawn("rifle",0,aim+offset)
		if not s.is_empty():s.seen_by=[true,true];cluster.append(s)
	fire.time=FieldOps.MORTAR_FIRST
	for s in cluster.slice(1):s.seen_by=[true,false]
	FieldOps.enemy_mortar(fire)
	check(fire.field_ops.mortar.rounds.is_empty(),"a single section draws no mortar fire")
	for s in cluster:s.seen_by=[true,true]
	fire.events.clear()
	fire.time=float(fire.field_ops.mortar.next)
	FieldOps.enemy_mortar(fire)
	check(fire.events.any(func(e):return e.type=="warning" and e.text=="Incoming mortar fire"),"warning toast before the salvo")
	check(fire.field_ops.mortar.rounds.size()==FieldOps.MORTAR_ROUNDS,"salvo of %d rounds queued" % FieldOps.MORTAR_ROUNDS)
	var hp_before:float=cluster.reduce(func(a,s):return a+s.hp,0.0)
	var supp_before:float=cluster.reduce(func(a,s):return a+s.suppression,0.0)
	fire.events.clear()
	fire.time+=FieldOps.MORTAR_FLIGHT+FieldOps.MORTAR_SPACING*FieldOps.MORTAR_ROUNDS
	FieldOps.enemy_mortar(fire)
	var blasts:Array=fire.events.filter(func(e):return e.type=="world_blast")
	check(blasts.size()==FieldOps.MORTAR_ROUNDS and blasts.all(func(e):return e.pos.distance_to(aim)<FieldOps.MORTAR_SCATTER+8.0),"rounds burst around the cluster (%d)" % blasts.size())
	var hp_after:float=cluster.reduce(func(a,s):return a+s.hp,0.0)
	var supp_after:float=cluster.reduce(func(a,s):return a+s.suppression,0.0)
	print("mortar salvo: cluster hp %.0f->%.0f, suppression %.2f->%.2f" % [hp_before,hp_after,supp_before,supp_after])
	check(hp_after<hp_before or supp_after>supp_before+0.3,"salvo hurts or pins the cluster")
	for u in fire.units:
		if u.team==1 and u.kind in ["command_post","ammo_depot"]:u.hp=0
	fire.time=float(fire.field_ops.mortar.next)+1.0
	FieldOps.enemy_mortar(fire)
	check(fire.field_ops.mortar.rounds.is_empty(),"losing posts and depots silences the mortar")

	# Cost: one decision over the whole harbor force.
	var bench=Sim.new(true,harbor_index())
	FieldOps.garrison_sites(bench)
	bench.field_ops.garrison_next=0.0
	var first:=Time.get_ticks_usec()
	FieldOps.enemy_garrisons(bench)
	first=Time.get_ticks_usec()-first
	var total:=0
	for k in 20:
		bench.field_ops.garrison_next=0.0
		var s:=Time.get_ticks_usec()
		FieldOps.enemy_garrisons(bench)
		total+=Time.get_ticks_usec()-s
	print("site scoring once: %d us; first decision (orders %d sections): %d us; steady decision avg: %d us (every %.0f s)" % [site_us,defenders(bench).filter(func(u):return u.get("garrison_role",false)).size(),first,total/20,FieldOps.GARRISON_INTERVAL])
	check(total/20<5000,"a decision costs under 5 ms")
	print("ENEMY GARRISON: ",checks," checks, ",failures," failures")
	quit(1 if failures>0 else 0)
