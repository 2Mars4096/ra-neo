extends SceneTree
# Refinery dock (classic skirmish). Found in the classic seed sweep (seed 14,
# from ~240 s): a returning harvester was sent onto the spot where another
# harvester stood at the ore edge beside the refinery, and the two jammed
# (across 28 seeds two harvesters were sent to one spot for ~14000 ticks).
# Now harvesters queue for the refinery dock:
#  1. two or three harvesters delivering at the same time all unload in turn
#     within a bound, one unloading at a time, the others at their own dock or
#     staging spots; no two are ever sent to one spot, stop where another is
#     headed, or overlap;
#  2. the dock is freed after each unload and never deadlocks over a long run;
#  3. a returning harvester is never routed onto a harvester parked at the ore
#     edge beside the refinery (the seed-14 layout);
#  4. idle harvesters (deposits exhausted) leave the dock for distinct spots.
const Sim=preload("res://scripts/simulation.gd")
const C=preload("res://scripts/classic.gd")
const HULL:=3.8 # two harvester radii
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
	simultaneous(2)
	simultaneous(3)
	long_run()
	parked_at_ore_edge()
	idle_off_dock()
	print("HARVESTER DOCK: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)

# Quiet economy: enemy AI idle, enemy units gone, a ready refinery near the
# west deposit; only harvesters on the friendly side.
func economy()->Object:
	var sim=Sim.new(true,scenario_index("classic"))
	sim.classic.ai_clock=1e9
	sim.classic.attack_clock=1e9
	for u in sim.units:
		if not sim.definitions[u.kind].get("structure",false) and (u.team==1 or u.kind!="harvester"):u.hp=0.0
	var site:Vector2=C.find_site(sim,"refinery",0)
	check(site.x>=0,"refinery site found")
	sim.spawn("refinery",0,site)
	C.sync_obstacles(sim)
	return sim

func harvesters(sim)->Array:
	return sim.living(0).filter(func(u):return u.kind=="harvester")

func refinery(sim)->Dictionary:
	return C.structures(sim,0,"refinery")[0]

# `count` harvesters, full, spread round the west deposit; the starting one
# is moved there too.
func fleet(sim,count:int)->Array:
	var field:Vector2=sim.classic.fields[0].pos
	var spots:=[field+Vector2(-6,-3),field+Vector2(7,-3),field+Vector2(0,-8)]
	var list:Array=harvesters(sim)
	list[0].pos=sim.spawn_position(spots[0],"harvester")
	for i in range(1,count):list.append(sim.spawn("harvester",0,sim.spawn_position(spots[i],"harvester")))
	for h in list:
		h.cargo=120.0;h.haul="RETURN"
		h.orders.clear();h.path.clear()
	return list

# Runs `seconds`; returns {loads: id -> unload times, min_gap, same_spot,
# dock_shared, worst_wait}. Spacing is checked between harvesters that are
# both stopped (orders done), and between order destinations.
func run(sim,seconds:float)->Dictionary:
	var list:Array=harvesters(sim)
	var loads:Dictionary={}
	var previous:Dictionary={}
	var stats:={"loads":loads,"min_gap":INF,"min_move_gap":INF,"same_spot":0,"dock_shared":0,"stopped_on_dock":0}
	var ref:=refinery(sim)
	var started:=Time.get_ticks_usec()
	for frame in int(seconds/0.1):
		sim.tick(0.1)
		for h in list:
			var cargo:float=h.get("cargo",0.0)
			if previous.get(h.id,0.0)>0 and cargo==0 and h.get("haul","")=="COLLECT":loads.get_or_add(h.id,[]).append(sim.time)
			previous[h.id]=cargo
		var unloading:=0
		for i in list.size():
			var a:Dictionary=list[i]
			if not sim.alive(a):continue
			if a.get("haul","")=="RETURN" and a.pos.distance_to(ref.pos)<C.DOCK_REACH and a.get("dock_unload",false):unloading+=1
			for j in range(i+1,list.size()):
				var b:Dictionary=list[j]
				if not sim.alive(b):continue
				var gap:float=a.pos.distance_to(b.pos)
				stats.min_move_gap=minf(stats.min_move_gap,gap)
				if a.orders.is_empty() and b.orders.is_empty():stats.min_gap=minf(stats.min_gap,gap)
				if not a.orders.is_empty() and not b.orders.is_empty() and Vector2(a.orders.back().pos).distance_to(b.orders.back().pos)<HULL:stats.same_spot+=1
				# A stopped harvester right where another is headed blocks it.
				if a.orders.is_empty() and not b.orders.is_empty() and a.pos.distance_to(b.orders.back().pos)<HULL:stats.stopped_on_dock+=1
				if b.orders.is_empty() and not a.orders.is_empty() and b.pos.distance_to(a.orders.back().pos)<HULL:stats.stopped_on_dock+=1
		if unloading>1:stats.dock_shared+=1
	stats["ms"]=(Time.get_ticks_usec()-started)/1000.0
	return stats

# 1. Two or three full harvesters reach the refinery at the same time.
func simultaneous(count:int)->void:
	var sim=economy()
	var list:=fleet(sim,count)
	var stats:=run(sim,60.0)
	var firsts:Array=[]
	for h in list:firsts.append(stats.loads[h.id][0] if stats.loads.has(h.id) else INF)
	firsts.sort()
	print("SIMULTANEOUS %d: first unloads at %s, min gap stopped %.2f moving %.2f, same-spot ticks %d, stopped-on-destination ticks %d, shared-dock ticks %d (%.0f ms)" % [count,str(firsts),stats.min_gap,stats.min_move_gap,stats.same_spot,stats.stopped_on_dock,stats.dock_shared,stats.ms])
	check(firsts.back()<=12.0*count,"all %d harvesters unload in turn within %.0f s (last %.1f s)" % [count,12.0*count,firsts.back()])
	check(stats.dock_shared==0,"one harvester unloads at the dock at a time (%d)" % count)
	check(stats.same_spot==0,"no two harvesters are sent to one spot (%d)" % count)
	check(stats.stopped_on_dock==0,"no harvester stops where another is headed (%d)" % count)
	check(stats.min_gap>=HULL,"stopped harvesters never overlap (%d: %.2f)" % [count,stats.min_gap])
	check(stats.min_move_gap>=HULL-0.6,"harvesters never drive into each other (%d: %.2f)" % [count,stats.min_move_gap])

# 2. Three harvesters work the west deposit for four minutes: every one keeps
# unloading (the dock is freed and never deadlocks). The deposit is enlarged to
# last; the east one, beside the enemy HQ, is enemy territory they keep out of.
func long_run()->void:
	var sim=economy()
	sim.classic.fields[0].remaining=20000.0
	sim.classic.fields[1].remaining=0.0
	var list:=fleet(sim,3)
	var stats:=run(sim,240.0)
	var counts:Array=list.map(func(h):return stats.loads.get(h.id,[]).size())
	var gaps:=0.0
	for h in list:
		var times:Array=stats.loads.get(h.id,[])
		for k in range(1,times.size()):gaps=maxf(gaps,times[k]-times[k-1])
	print("LONG RUN: loads per harvester %s, longest gap between unloads %.1f s, min gap stopped %.2f moving %.2f, same-spot ticks %d, stopped-on-destination ticks %d, shared-dock ticks %d (%.0f ms)" % [str(counts),gaps,stats.min_gap,stats.min_move_gap,stats.same_spot,stats.stopped_on_dock,stats.dock_shared,stats.ms])
	check(counts.min()>=6,"every harvester keeps unloading over 240 s (%s)" % str(counts))
	check(gaps<=60.0,"no harvester waits a minute between unloads (%.1f s)" % gaps)
	check(stats.dock_shared==0,"one harvester at the dock at a time over the long run")
	check(stats.same_spot==0,"no two harvesters sent to one spot over the long run")
	check(stats.stopped_on_dock==0,"no harvester stops where another is headed over the long run (%d ticks)" % stats.stopped_on_dock)
	check(stats.min_gap>=HULL,"stopped harvesters never overlap over the long run (%.2f)" % stats.min_gap)

# 3. The seed-14 layout: one harvester stopped at the ore edge beside the
# refinery, another returning full past it.
func parked_at_ore_edge()->void:
	var sim=economy()
	var list:=fleet(sim,2)
	var ref:=refinery(sim)
	var field:Vector2=sim.classic.fields[0].pos
	# Stand point on the outer ore ring nearest the refinery.
	var edge:Vector2=field+(ref.pos-field).normalized()*C.ORE_RINGS[-1][0]
	list[0].pos=edge;list[0].cargo=40.0;list[0].haul="COLLECT";list[0].ore_cell=edge
	list[1].pos=sim.spawn_position(field+Vector2(0,-8),"harvester")
	var stats:=run(sim,30.0)
	print("ORE EDGE: unloads %s, min gap stopped %.2f moving %.2f, same-spot ticks %d, stopped-on-destination ticks %d" % [str(stats.loads),stats.min_gap,stats.min_move_gap,stats.same_spot,stats.stopped_on_dock])
	check(stats.loads.has(list[1].id),"returning harvester unloads past the one at the ore edge")
	check(stats.stopped_on_dock==0,"returning harvester is never sent onto the one at the ore edge")
	check(stats.min_move_gap>=HULL-0.6,"the two never drive into each other (%.2f)" % stats.min_move_gap)

# 4. Deposits run dry while three harvesters are bunched at the refinery: the
# idle ones leave the dock for distinct spots.
func idle_off_dock()->void:
	var sim=economy()
	var list:=fleet(sim,3)
	var ref:=refinery(sim)
	var stats:=run(sim,20.0)
	for field in sim.classic.fields:field.remaining=0.0
	stats=run(sim,40.0)
	var near:=0
	for h in list:
		if h.pos.distance_to(ref.pos)<C.DOCK_REACH+float(sim.definitions.harvester.radius):near+=1
	print("IDLE: harvesters %s, reasons %s, min gap stopped %.2f, %d left on the dock" % [str(list.map(func(h):return h.pos.snapped(Vector2(0.1,0.1)))),str(list.map(func(h):return h.reason)),stats.min_gap,near])
	check(near==0,"idle harvesters leave the refinery dock (%d still on it)" % near)
	check(stats.min_gap>=HULL,"idle harvesters park apart (%.2f)" % stats.min_gap)
	check(list.all(func(h):return h.orders.is_empty()),"idle harvesters come to rest")
