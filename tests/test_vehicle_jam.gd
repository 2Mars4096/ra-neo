extends SceneTree
# Friendly vehicles never deadlock each other. Tanks pressed together at
# contact distance, crossing through each other, and meeting head-on or
# swapping places in a tight street (black_sea_harbor) must all reach their
# goal, or a clear spot near it, within a bound, and no tank may stay
# YIELDING for more than ~8 s at a stretch.
const Sim=preload("res://scripts/simulation.gd")
const VehicleDamage=preload("res://scripts/vehicle_damage.gd")
const CONTACT:=2.45*2.0+0.08 # two tank hulls touching (movement clearance)
const YIELD_LIMIT:=8.0
const NEAR_GOAL:=8.0 # "a clear spot near it"
const UNDER_FIRE_LIMIT:=20.0
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func scenario_index(id:String)->int:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		if configs[i].id==id:return i
	return -1

func _init()->void:
	var open:=Vector2(300,640)
	# 1. Four tanks pressed in a square, each crossing to the opposite corner.
	var square:Array=[]
	for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
		square.append([open+corner*CONTACT*0.5,open-corner*18.0,(-corner).normalized()])
	run_case("pressed_square",square,70.0)
	# 2. Four tanks nose to tail at contact, the two halves swapping ends.
	var swap:Array=[]
	for i in 4:
		var pos:=open+Vector2((i-1.5)*CONTACT,0)
		var east:=i<2
		swap.append([pos,open+Vector2(30 if east else -30,(i-1.5)*1.0),Vector2.RIGHT if east else Vector2.LEFT])
	run_case("pressed_swap",swap,70.0)
	# 3. Head-on pairs in a two-lane street (12.5 u wide, running east-west).
	var street:=Vector2(355,506)
	var head_on:Array=[]
	for i in 2:
		head_on.append([street+Vector2(-22-i*7.0,0),street+Vector2(26+i*7.0,0),Vector2.RIGHT])
		head_on.append([street+Vector2(22+i*7.0,0),street+Vector2(-26-i*7.0,0),Vector2.LEFT])
	run_case("street_head_on",head_on,70.0)
	# 4. Pressed together in the street: the front pair turns back through the rear pair.
	var reverse:Array=[]
	for i in 4:
		var pos:=street+Vector2((i-1.5)*CONTACT,0)
		var east:=i<2
		reverse.append([pos,street+Vector2(28 if east else -28,0),Vector2.LEFT if east else Vector2.RIGHT])
	run_case("street_pressed_reverse",reverse,80.0)
	# 5. Two groups of three crossing at right angles over the same spot.
	var plaza:=Vector2(290,600)
	var cross:Array=[]
	for i in 3:
		cross.append([plaza+Vector2(-25,(i-1)*CONTACT),plaza+Vector2(25,(i-1)*CONTACT),Vector2.RIGHT])
		cross.append([Vector2(282+(i-1)*CONTACT,565),Vector2(282+(i-1)*CONTACT,604),Vector2.DOWN])
	run_case("plaza_cross",cross,60.0)
	# 6. Ordinary orders: four tanks sent one by one to the very same spot.
	var yard:=Vector2(300,662)
	for mode in ["move","attack_move"]:
		var same:Array=[]
		for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
			same.append([yard+corner*12.0,yard,(-corner).normalized()])
		run_case("same_goal_"+mode,same,60.0,mode)
		run_case("same_goal_"+mode+"_dt0.1",same,60.0,mode,0.1)
	# 7. Four pressed nose to tail, each sent on its own to one spot ahead.
	var column:Array=[]
	for i in 4:column.append([open+Vector2(-12-i*CONTACT,0),open+Vector2(12,0),Vector2.RIGHT])
	run_case("pressed_same_goal",column,60.0)
	run_case("pressed_same_goal_dt0.1",column,60.0,"attack_move",0.1)
	# 8. The same-goal jam within sight of an enemy tank: the crews fight first
	# (no shuffling under fire) but still sort the jam out within a bound.
	var fired:Array=[]
	for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
		fired.append([yard+corner*12.0,yard,(-corner).normalized()])
	run_case("same_goal_under_fire",fired,60.0,"move",1.0/30.0,yard+Vector2(0,-24))
	# 9. A pressed block of six tanks given one group attack on an enemy
	# structure (classic map, enemy HQ): they spread to distinct firing spots
	# round it and all fire, with no give-way cycle among themselves.
	run_group_attack(1.0/30.0)
	run_group_attack(0.1)
	# 10. Few firing spots: tanks attack the enemy HQ (a corner of the classic
	# map) past immobilised friends standing on the near side of its firing
	# ring, under normal fog. With two such friends every tank fires; with
	# three, walling off the near side, a tank that cannot get through still
	# changes its firing spot at most Sim.RESPOT_MAX times (it used to cycle
	# spots for as long as the attack lasted).
	run_limited_attack(5,1.0/30.0,2)
	run_limited_attack(5,0.1,2)
	run_limited_attack(4,0.1,3,false)
	# 11. A twelve-tank column attacks the enemy HQ from the west, where the
	# wrecks of an earlier assault (classic seed 8 at 300 s) leave one narrow
	# lane: the column takes spots it can reach round the wrecks, and hulls
	# stopped to fire in the lane press on to their spots or shift aside, so
	# the column flows through instead of gridlocking in the lane. Over four
	# column placements and both steps, at least CHOKE_SHARE of the tanks fire
	# within the limit, and at least CHOKE_RUN of twelve in every run.
	var through:=0;var sent:=0
	for dt in [1.0/30.0,0.1]:
		for offset in CHOKE_OFFSETS:
			var result:Array=run_choked_column(dt,offset)
			through+=result[0];sent+=result[1]
	check(through>=ceili(sent*CHOKE_SHARE),"choked_column: at least %d%% of the tanks fire (%d/%d)" % [roundi(CHOKE_SHARE*100),through,sent])
	print("choked_column: %d/%d tanks fired" % [through,sent])
	if checks==0:failures+=1;printerr("FAIL: no cases ran")
	print("VEHICLE JAM: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)

# Each entry: [start, goal, facing]. Tanks get individual orders (exact goals).
# `enemy_at`: an enemy tank there, seen and fired at but harmless (never
# reloads, never hurt), so the tanks fight under threat while they sort the jam.
func run_case(label:String,entries:Array,limit:float,mode:String="move",dt:float=1.0/30.0,enemy_at:Vector2=Vector2.INF)->void:
	var sim=Sim.new(false,scenario_index("black_sea_harbor"))
	var enemy:Dictionary={}
	if enemy_at!=Vector2.INF:
		enemy=sim.spawn("tank",1,enemy_at)
		enemy.hold_command=true
	var tanks:Array=[]
	var goals:Array=[]
	for entry in entries:
		var tank:Dictionary=sim.spawn("tank",0,entry[0])
		tank.pos=entry[0]
		tank.facing=entry[2]
		tanks.append(tank)
	sim.rebuild_spatial()
	for i in tanks.size():
		check(sim.issue([tanks[i].id],entries[i][1],mode)==1,"%s: tank %d accepts its move" % [label,i])
		goals.append(tanks[i].orders[0].pos if not tanks[i].orders.is_empty() else entries[i][1])
	# YIELDING streak, and a stall clock: time with orders but no 1.5 u of
	# headway (a hull pivoting or creeping in place flips its state each tick).
	var streak:Array=[];var worst:Array=[];var arrived:Array=[]
	var anchor:Array=[];var stall:Array=[];var worst_stall:Array=[]
	for tank in tanks:
		streak.append(0.0);worst.append(0.0);arrived.append(-1.0)
		anchor.append(tank.pos);stall.append(0.0);worst_stall.append(0.0)
	var trace:bool=label in OS.get_cmdline_user_args()
	var steps:=int(limit/dt)
	var start_ms:=Time.get_ticks_usec()
	var under_fire:=0.0
	for step in steps:
		if not enemy.is_empty():
			enemy.hp=enemy.max_hp
			enemy.cooldown=999.0
			enemy.visible=true
			enemy.seen_by=[true,true]
		sim.tick(dt)
		if not enemy.is_empty():
			for tank in tanks:
				if sim.under_threat(tank):under_fire+=dt/tanks.size();break
		var done:=true
		for i in tanks.size():
			var tank:Dictionary=tanks[i]
			if tank.state=="YIELDING":streak[i]+=dt
			else:streak[i]=0.0
			worst[i]=maxf(worst[i],streak[i])
			if tank.orders.is_empty() or tank.pos.distance_to(anchor[i])>1.5:
				anchor[i]=tank.pos;stall[i]=0.0
			else:stall[i]+=dt
			worst_stall[i]=maxf(worst_stall[i],stall[i])
			if arrived[i]<0 and tank.orders.is_empty() and tank.pos.distance_to(goals[i])<=NEAR_GOAL:arrived[i]=(step+1)*dt
			if arrived[i]<0:done=false
		if trace and step%int(round(1.0/dt))==0:
			print("t=%.0f " % sim.time,tanks.map(func(t):return "%d %s %s f%s b%.1f p%d %s" % [t.id,t.pos.snapped(Vector2(0.1,0.1)),t.state,t.facing.snapped(Vector2(0.01,0.01)),t.blocked_time,t.path.size(),t.path.slice(0,2)]))
		if done:break
	var elapsed:=(Time.get_ticks_usec()-start_ms)/1000.0
	var line:="%s:" % label
	for i in tanks.size():
		var tank:Dictionary=tanks[i]
		line+=" [%d arrive=%.1f gap=%.1f yield=%.1f stall=%.1f %s]" % [i,arrived[i],tank.pos.distance_to(goals[i]),worst[i],worst_stall[i],tank.state]
		check(arrived[i]>=0.0,"%s: tank %d reaches its goal or a clear spot near it within %.0f s (gap %.1f, state %s)" % [label,i,limit,tank.pos.distance_to(goals[i]),tank.state])
		# Under fire the jam waits for the fight first (JAM_UNDER_FIRE).
		var bound:float=YIELD_LIMIT if enemy.is_empty() else UNDER_FIRE_LIMIT
		check(worst[i]<=bound,"%s: tank %d yields at most %.0f s at a stretch (%.1f s)" % [label,i,bound,worst[i]])
		check(worst_stall[i]<=bound,"%s: tank %d is never stuck without headway over %.0f s (%.1f s)" % [label,i,bound,worst_stall[i]])
	if not enemy.is_empty():
		check(under_fire>1.0,"%s: the tanks are under threat (%.1f s)" % [label,under_fire])
		line+=" under_fire=%.1f" % under_fire
	print(line," wall=%.0f ms" % elapsed)

func run_group_attack(dt:float)->void:
	var label:="group_attack_structure_dt%.2f" % dt
	var sim=Sim.new(true,scenario_index("classic"))
	var hq:Dictionary={}
	for u in sim.units:
		if u.team==1 and u.kind=="hq":hq=u
		elif u.team==1:u.hp=0.0
	check(not hq.is_empty() and not sim.terrain.traversable(hq.pos,"land",2.45),"%s: fixture has an enemy structure" % label)
	var tanks:Array=[]
	for i in 6:
		var start:=Vector2(28+(i%2)*CONTACT,8+(i/2)*CONTACT)
		var tank:Dictionary=sim.spawn("tank",0,start)
		tank.pos=start
		tank.facing=Vector2.RIGHT
		tanks.append(tank)
	sim.rebuild_spatial()
	hq.seen_by=[true,true];hq.visible=true
	var ids:Array=tanks.map(func(t):return t.id)
	check(sim.issue(ids,hq.pos,"attack",false,hq.id)==tanks.size(),"%s: every tank accepts the group attack" % label)
	var spots:Array=tanks.map(func(t):return t.orders[0].pos if not t.orders.is_empty() else Vector2.INF)
	var closest:=INF
	for i in spots.size():
		for j in range(i+1,spots.size()):closest=minf(closest,spots[i].distance_to(spots[j]))
	check(closest>=sim.crowd_radius("tank")*2.0,"%s: firing spots are distinct (closest %.1f u apart)" % [label,closest])
	var streak:Array=[];var worst:Array=[];var anchor:Array=[];var stall:Array=[];var worst_stall:Array=[];var fired:Array=[]
	for tank in tanks:
		streak.append(0.0);worst.append(0.0);anchor.append(tank.pos);stall.append(0.0);worst_stall.append(0.0);fired.append(-1.0)
	var limit:=90.0
	for step in int(limit/dt):
		hq.hp=hq.max_hp;hq.seen_by=[true,true];hq.visible=true
		sim.classic.enemy_credits=0.0
		sim.tick(dt);sim.events.clear()
		var done:=true
		for i in tanks.size():
			var tank:Dictionary=tanks[i]
			if tank.state=="YIELDING" and tank.blocked_time>0:streak[i]+=dt
			else:streak[i]=0.0
			worst[i]=maxf(worst[i],streak[i])
			# Firing from its spot is no stall.
			if tank.orders.is_empty() or tank.state=="ENGAGING" or tank.pos.distance_to(anchor[i])>1.5:
				anchor[i]=tank.pos;stall[i]=0.0
			else:stall[i]+=dt
			worst_stall[i]=maxf(worst_stall[i],stall[i])
			if fired[i]<0 and tank.target==hq.id and float(tank.last_shot)>0:fired[i]=sim.time
			if fired[i]<0:done=false
		if done:break
	var line:="%s: closest_spots=%.1f" % [label,closest]
	for i in tanks.size():
		line+=" [%d fired=%.1f yield=%.1f stall=%.1f %s]" % [i,fired[i],worst[i],worst_stall[i],tanks[i].state]
		check(fired[i]>=0.0,"%s: tank %d reaches a firing spot and fires within %.0f s" % [label,i,limit])
		check(worst[i]<=YIELD_LIMIT,"%s: tank %d yields at most %.0f s at a stretch (%.1f s)" % [label,i,YIELD_LIMIT,worst[i]])
		check(worst_stall[i]<=YIELD_LIMIT*2.0,"%s: tank %d is never stuck without headway over %.0f s (%.1f s)" % [label,i,YIELD_LIMIT*2.0,worst_stall[i]])
	print(line)

func run_limited_attack(count:int,dt:float,blockers:int,all_fire:bool=true)->void:
	var label:="limited_spots_attack_%d_b%d_dt%.2f" % [count,blockers,dt]
	var sim=Sim.new(true,scenario_index("classic"))
	var hq:Dictionary={}
	for u in sim.units:
		if u.team==1 and u.kind=="hq":hq=u
		elif u.team==1:u.hp=0.0
	check(not hq.is_empty() and not sim.terrain.traversable(hq.pos,"land",2.45),"%s: fixture has an enemy structure" % label)
	var tanks:Array=[]
	for i in count:
		var start:=Vector2(28+(i%2)*CONTACT,8+(i/2)*CONTACT)
		var tank:Dictionary=sim.spawn("tank",0,start)
		tank.pos=start
		tank.facing=Vector2.RIGHT
		tanks.append(tank)
	# Immobilised friends (they hold and cannot give way) on the near side of
	# the ring, 19 u out: west to south-west of the HQ.
	for k in blockers:
		var stuck:Dictionary=sim.spawn("tank",0,hq.pos+Vector2.from_angle(PI*(0.75+0.25*k/maxf(1,blockers-1)))*19.0)
		stuck.mobility_kill=true
		stuck.hold_command=true
	sim.rebuild_spatial()
	# Sighted for the order; normal fog from then on.
	hq.seen_by=[true,true];hq.visible=true
	check(sim.issue(tanks.map(func(t):return t.id),hq.pos,"attack",false,hq.id)==tanks.size(),"%s: every tank accepts the group attack" % label)
	# Changes of each tank's firing spot (a structure never moves: only a
	# re-spot moves it).
	var last:Array=[];var respots:Array=[];var fired:Array=[]
	for tank in tanks:last.append(Vector2.INF);respots.append(0);fired.append(-1.0)
	var limit:=150.0
	for step in int(limit/dt):
		hq.hp=hq.max_hp
		sim.classic.enemy_credits=0.0
		sim.tick(dt);sim.events.clear()
		var done:=true
		for i in tanks.size():
			var tank:Dictionary=tanks[i]
			if not tank.orders.is_empty() and tank.orders[0].mode=="attack":
				if last[i]!=Vector2.INF and tank.orders[0].pos!=last[i]:respots[i]+=1
				last[i]=tank.orders[0].pos
			if fired[i]<0 and tank.target==hq.id and float(tank.last_shot)>0:fired[i]=sim.time
			if fired[i]<0:done=false
		if done:break
	var line:="%s:" % label
	for i in tanks.size():
		line+=" [%d fired=%.1f respots=%d %s]" % [i,fired[i],respots[i],tanks[i].state]
		if all_fire:check(fired[i]>=0.0,"%s: tank %d fires on the HQ within %.0f s" % [label,i,limit])
		check(respots[i]<=Sim.RESPOT_MAX,"%s: tank %d changes its firing spot at most %d times (%d)" % [label,i,Sim.RESPOT_MAX,respots[i]])
	print(line)

const SEED8_WRECKS:=[Vector2(30.65,30.63),Vector2(54.21,56.66),Vector2(28.95,23.88),Vector2(43.71,56.77),Vector2(41.05,21.05),Vector2(36.45,41.38),Vector2(41.08,15.32),Vector2(32.53,13.37)]
const CHOKE_OFFSETS:=[Vector2(0,0),Vector2(2,3),Vector2(0,8),Vector2(4,14)]
const CHOKE_SHARE:=0.67
const CHOKE_RUN:=6
# Returns [tanks that fired, tanks sent].
func run_choked_column(dt:float,offset:Vector2)->Array:
	var label:="choked_column_%d_%d_dt%.2f" % [offset.x,offset.y,dt]
	var sim=Sim.new(true,scenario_index("classic"))
	var hq:Dictionary={}
	for u in sim.units:
		if u.team==1 and u.kind=="hq":hq=u
		elif u.team==1:u.hp=0.0
	var hulks:Array=[]
	for at in SEED8_WRECKS:hulks.append({"id":-1,"kind":"tank","team":1,"pos":at,"facing":Vector2.RIGHT,"radius":2.45,"abandoned":false})
	sim.set_meta(VehicleDamage.WRECKS,hulks)
	var tanks:Array=[]
	for i in 12:
		var start:=Vector2(8+(i%3)*CONTACT,4+(i/3)*CONTACT)+offset
		var tank:Dictionary=sim.spawn("tank",0,start)
		tank.pos=start
		tank.facing=Vector2.RIGHT
		tanks.append(tank)
	sim.rebuild_spatial()
	hq.seen_by=[true,true];hq.visible=true
	check(sim.issue(tanks.map(func(t):return t.id),hq.pos,"attack",false,hq.id)==tanks.size(),"%s: every tank accepts the group attack" % label)
	var fired:Array=[]
	for tank in tanks:fired.append(-1.0)
	var limit:=180.0
	for step in int(limit/dt):
		hq.hp=hq.max_hp
		sim.classic.enemy_credits=0.0
		sim.tick(dt);sim.events.clear()
		var done:=true
		for i in tanks.size():
			if fired[i]<0 and tanks[i].target==hq.id and float(tanks[i].last_shot)>0:fired[i]=sim.time
			if fired[i]<0:done=false
		if done:break
	var through:=fired.filter(func(f):return f>=0.0).size()
	var line:="%s: %d/%d fired" % [label,through,tanks.size()]
	for i in tanks.size():line+=" [%d %.1f]" % [i,fired[i]]
	print(line)
	check(through>=CHOKE_RUN,"%s: at least %d of %d tanks fire within %.0f s (%d)" % [label,CHOKE_RUN,tanks.size(),limit,through])
	return [through,tanks.size()]
