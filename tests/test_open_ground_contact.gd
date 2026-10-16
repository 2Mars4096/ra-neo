extends SceneTree
# Soldiers caught in the open under effective fire get flat at once and keep
# firing prone, or move to real cover; nobody stays upright in the open. Uses
# the showcase map of the regroup mission (tests/test_regroup_recovery.gd).
const Sim=preload("res://scripts/simulation.gd")
const Infantry=preload("res://scripts/infantry.gd")
const Cover=preload("res://scripts/cover_behavior.gd")
# Open field west of the villa: no shelter inside the leash, the nearest
# reachable cover 13 u away; the enemy rifles 11.5 u off in the open.
const FIELD:=Vector2(10,34)
const FIELD_ENEMY:=Vector2(14.4,44.6)
# The regroup mission's villa contact: a wall face north of the villa (y 12.95)
# screens the section from the rifles at the villa post.
const VILLA:=Vector2(40.36,12.41)
const VILLA_ENEMY:=Vector2(34.41422,24.41421)
const DROP:=1.0
const EXPOSED_MAX:=3.0
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

func sheltering(m:Dictionary)->bool:
	return m.get("cover_phase","") in ["SEEKING","SETTLING","SHELTERED"] or m.get("occupying",false)

# A living enemy soldier that can reach the section with a clear line of fire.
func under_fire(sim,u:Dictionary,enemy:Dictionary)->bool:
	if not sim.alive(enemy) or not Cover.in_weapon_range(enemy,u,sim):return false
	return enemy.members.any(func(e):return e.hp>0 and u.members.any(func(m):return m.hp>0 and sim.terrain.line_clear(e.pos,m.pos)))

# Runs the fight; for the sections that come under fire returns the slowest
# drop after their first incoming round, the longest upright exposure in the
# open under effective fire, and whether a prone soldier fired.
func fight(sim,sections:Array,enemy:Dictionary,seconds:float)->Dictionary:
	var first_fire:={}
	var dropped:={}
	var streak:={}
	var worst:=0.0
	var prone_shot:=false
	for frame in int(seconds*30):
		sim.tick(1.0/30);sim.events.clear()
		for u in sections:
			if not first_fire.has(u.id) and float(u.get("fired_on",-100.0))>0:first_fire[u.id]=float(u.fired_on)
			if not first_fire.has(u.id):continue
			var hot:bool=under_fire(sim,u,enemy)
			for m in u.members:
				if m.hp<=0:continue
				var key:="%d:%d"%[u.id,m.index]
				if not dropped.has(key) and (m.posture=="PRONE" or sheltering(m)):dropped[key]=sim.time-first_fire[u.id]
				if m.posture=="PRONE" and sim.time-float(m.last_shot)<1.0/30+0.001:prone_shot=true
				var upright:bool=hot and m.posture!="PRONE" and not sheltering(m) and not sim.terrain.cover(m.pos)
				streak[key]=float(streak.get(key,0.0))+1.0/30 if upright else 0.0
				worst=maxf(worst,streak[key])
	var slowest:=0.0
	for u in sections:
		if not first_fire.has(u.id):continue
		for m in u.members:
			if m.hp>0:slowest=maxf(slowest,float(dropped.get("%d:%d"%[u.id,m.index],INF)))
	var first:=-1.0
	for id in first_fire:first=first_fire[id] if first<0 else minf(first,first_fire[id])
	return {"first_fire":first,"slowest_drop":slowest,"worst_exposed":worst,"prone_shot":prone_shot}

func open_field(order:String)->void:
	var sim=Sim.new(false,showcase())
	var u:Dictionary=sim.spawn("rifle",0,FIELD)
	var enemy:Dictionary=sim.spawn("rifle",1,FIELD_ENEMY)
	check(Cover._shelter_points(u,sim).is_empty(),"open field: no shelter inside the leash")
	var nearest:=INF
	for r in range(20,31):
		for i in 32:
			var q:Vector2=FIELD+Vector2.from_angle(i*TAU/32)*r*0.5
			if nearest==INF and sim.terrain.cover(q) and sim.terrain.traversable(q,"land",0.8) and not sim.terrain.path(FIELD,q,"land",0.8,[],"infantry").is_empty():nearest=r*0.5
	check(nearest>=10.0 and nearest<=15.0,"open field: reachable cover 10-15 u away (%.1f)"%nearest)
	if order!="":check(sim.issue([u.id],FIELD_ENEMY,order)==1,"open field %s accepted"%order)
	var r:=fight(sim,[u],enemy,8.0)
	print("  open field %s: first fire=%.2f slowest drop=%.2f s worst upright exposure=%.2f s prone shot=%s"%[order if order!="" else "idle",r.first_fire,r.slowest_drop,r.worst_exposed,r.prone_shot])
	check(r.first_fire>=0,"open field %s: the section comes under fire"%order)
	check(r.slowest_drop<=DROP,"open field %s: every soldier is flat or running for cover within %.1f s"%[order,DROP])
	check(r.prone_shot,"open field %s: soldiers keep firing prone"%order)
	check(r.worst_exposed<=EXPOSED_MAX,"open field %s: nobody stays upright in the open under fire"%order)

# Another friendly section crowding the open field: its soldiers lie alongside
# (they may squeeze past each other) instead of keeping this one on its feet.
func crowded_field()->void:
	var sim=Sim.new(false,showcase())
	var u:Dictionary=sim.spawn("rifle",0,FIELD)
	var neighbour:Dictionary=sim.spawn("rifle",0,FIELD+Vector2(-1.6,0))
	var enemy:Dictionary=sim.spawn("rifle",1,FIELD_ENEMY)
	# Pack the neighbour's formation as close west as soldiers of two sections
	# may stand (actor_clear's squeeze, about 1.05 u between bodies).
	for step in range(10,40):
		var shift:=Vector2(-step*0.1,0)
		if u.members.all(func(p):return u.members.all(func(q):return (p.pos+shift).distance_to(q.pos)>=1.05)):
			neighbour.pos=u.pos+shift
			for i in neighbour.members.size():neighbour.members[i].pos=u.members[i].pos+shift
			break
	var close:bool=neighbour.members.all(func(m):return sim.terrain.traversable(m.pos,"land",0.8)) and neighbour.members.any(func(m):return u.members.any(func(p):return m.pos.distance_to(p.pos)<1.95))
	check(close,"crowded field: the neighbour stands inside the prone footprint")
	# Six rifles would silence three before a shot came back: the enemy opens fire.
	for m in u.members+neighbour.members:m.cooldown=4.0
	var r:=fight(sim,[u,neighbour],enemy,6.0)
	print("  crowded field: first fire=%.2f slowest drop=%.2f s worst upright exposure=%.2f s"%[r.first_fire,r.slowest_drop,r.worst_exposed])
	check(r.first_fire>=0,"crowded field: the sections come under fire")
	check(r.slowest_drop<=DROP,"crowded field: soldiers beside another section still get flat within %.1f s"%DROP)
	check(r.worst_exposed<=EXPOSED_MAX,"crowded field: nobody stays upright in the open under fire")

# One soldier sheltering at the wall corner must not lock the rest of the face:
# squadmates pass round them to the free slots instead of lying in the open.
func villa_wall()->void:
	var sim=Sim.new(false,showcase())
	var u:Dictionary=sim.spawn("rifle",0,VILLA)
	var enemy:Dictionary=sim.spawn("rifle",1,VILLA_ENEMY)
	var r:=fight(sim,[u],enemy,12.0)
	var walled:=0
	for m in u.members:
		print("  villa wall member ",m.index," phase=",m.get("cover_phase","")," posture=",m.posture," pos=",m.pos," goal=",m.cover_goal)
		if m.hp>0 and m.get("cover_phase","") in ["SETTLING","SHELTERED"] and sim.terrain.cover(m.cover_goal):walled+=1
	var living:int=u.members.filter(func(m):return m.hp>0).size()
	print("  villa wall: first fire=%.2f slowest drop=%.2f s worst upright exposure=%.2f s screened=%d/%d"%[r.first_fire,r.slowest_drop,r.worst_exposed,walled,living])
	check(r.first_fire>=0,"villa wall: the section comes under fire")
	check(walled==living,"villa wall: every soldier reaches shelter")
	check(r.worst_exposed<=EXPOSED_MAX,"villa wall: nobody stays upright in the open under fire")

func _init()->void:
	open_field("")
	open_field("attack_move")
	crowded_field()
	villa_wall()
	print("OPEN GROUND CONTACT: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
