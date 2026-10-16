extends SceneTree
# Friendly vehicles never deadlock each other. Tanks pressed together at
# contact distance, crossing through each other, and meeting head-on or
# swapping places in a tight street (black_sea_harbor) must all reach their
# goal, or a clear spot near it, within a bound, and no tank may stay
# YIELDING for more than ~8 s at a stretch.
const Sim=preload("res://scripts/simulation.gd")
const CONTACT:=2.45*2.0+0.08 # two tank hulls touching (movement clearance)
const YIELD_LIMIT:=8.0
const NEAR_GOAL:=8.0 # "a clear spot near it"
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
	if checks==0:failures+=1;printerr("FAIL: no cases ran")
	print("VEHICLE JAM: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)

# Each entry: [start, goal, facing]. Tanks get individual orders (exact goals).
func run_case(label:String,entries:Array,limit:float,mode:String="move",dt:float=1.0/30.0)->void:
	var sim=Sim.new(false,scenario_index("black_sea_harbor"))
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
	for step in steps:
		sim.tick(dt)
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
		check(worst[i]<=YIELD_LIMIT,"%s: tank %d yields at most %.0f s at a stretch (%.1f s)" % [label,i,YIELD_LIMIT,worst[i]])
		check(worst_stall[i]<=YIELD_LIMIT,"%s: tank %d is never stuck without headway over %.0f s (%.1f s)" % [label,i,YIELD_LIMIT,worst_stall[i]])
	print(line," wall=%.0f ms" % elapsed)
