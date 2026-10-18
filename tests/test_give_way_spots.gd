extends SceneTree
# Friends asked to give way at the same time never get the same spot. A tank
# jammed on an open lane (black_sea_harbor) asks every parked friend in its way
# to clear at once (make_way with movers): for each pair of blockers (tanks,
# a tank and a section, two sections) on a grid along the lane, the two
# give-way spots are at least a body apart (the spot search skips spots
# friends are already heading for, not only where they stand). Then a few
# pairs, asked at once, run on in full: the asker gets through, and nobody
# ends stacked (the blockers never stand on one spot).
const Sim=preload("res://scripts/simulation.gd")
const OPEN:=Vector2(300,640)
const FROM:=Vector2(-12,0) # within movement_neighbors reach of the blockers
const TO:=Vector2(30,0)
const PAIRS:=[["tank","tank"],["tank","rifle"],["rifle","atgm"]]
const MIN_BOTH:=20 # pairs both asked at once, so the sweep means something
# Pairs that shared a give-way spot before spots friends head for were skipped.
const FULL:=[["tank","tank",Vector2(-6,3),Vector2(0,0)],["tank","rifle",Vector2(0,0),Vector2(-6,3)],["rifle","atgm",Vector2(-6,3),Vector2(-3,0)]]
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
	sweep()
	for entry in FULL:run_full(entry[0],entry[1],OPEN+entry[2],OPEN+entry[3])
	if checks==0:failures+=1;printerr("FAIL: no cases ran")
	print("GIVE WAY SPOTS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)

func asker(sim)->Dictionary:
	var tank:Dictionary=sim.spawn("tank",0,OPEN+FROM)
	tank.facing=Vector2.RIGHT
	sim.rebuild_spatial()
	check(sim.issue([tank.id],OPEN+TO,"move")==1 and not tank.path.is_empty(),"asker accepts its move")
	return tank

func remove(sim,u:Dictionary)->void:
	sim.units.erase(u)
	sim.units_by_id.erase(u.id)

# One sim; each blocker pair is spawned on the lane, both asked at once, then
# removed.
func sweep()->void:
	var sim=Sim.new(false,scenario_index("black_sea_harbor"))
	var tank:Dictionary=asker(sim)
	var places:Array=[]
	for x in [-6,-3,0,3]:
		for y in [-3,0,3]:places.append(OPEN+Vector2(x,y))
	for kinds in PAIRS:
		var crowd:float=sim.crowd_radius(kinds[0])+sim.crowd_radius(kinds[1])
		var both:=0;var shared:=0;var closest:=INF
		for a in places:
			for b in places:
				if a.distance_to(b)<crowd+0.2:continue
				var first:Dictionary=sim.spawn(kinds[0],0,a)
				var second:Dictionary=sim.spawn(kinds[1],0,b)
				if first.is_empty() or second.is_empty() or first.pos!=a or second.pos!=b:
					if not first.is_empty():remove(sim,first)
					if not second.is_empty():remove(sim,second)
					continue
				sim.rebuild_spatial()
				sim.make_way(tank,true)
				if first.orders.size()==1 and second.orders.size()==1:
					both+=1
					var gap:float=first.orders[0].pos.distance_to(second.orders[0].pos)
					if gap<crowd+0.12:shared+=1
					closest=minf(closest,gap)
				remove(sim,first);remove(sim,second)
		sim.rebuild_spatial()
		print("%s+%s: both asked %d, sharing a spot %d, closest spots %.1f u apart" % [kinds[0],kinds[1],both,shared,closest])
		check(both>=MIN_BOTH,"%s+%s: at least %d pairs both asked at once (%d)" % [kinds[0],kinds[1],MIN_BOTH,both])
		check(shared==0,"%s+%s: no two blockers asked at once share a give-way spot (%d did, closest %.1f u)" % [kinds[0],kinds[1],shared,closest])

# The pair runs in full: the asker reaches its goal, both blockers settle
# apart and never stand stacked on one spot.
func run_full(kind_a:String,kind_b:String,a:Vector2,b:Vector2)->void:
	var label:="%s+%s at %s %s" % [kind_a,kind_b,a-OPEN,b-OPEN]
	var sim=Sim.new(false,scenario_index("black_sea_harbor"))
	var tank:Dictionary=asker(sim)
	var first:Dictionary=sim.spawn(kind_a,0,a)
	var second:Dictionary=sim.spawn(kind_b,0,b)
	sim.rebuild_spatial()
	var crowd:float=sim.crowd_radius(kind_a)+sim.crowd_radius(kind_b)
	var asked:bool=sim.make_way(tank,true) and first.orders.size()==1 and second.orders.size()==1
	var stacked:=0.0;var arrived:=-1.0
	for step in 30*30:
		sim.tick(1.0/30);sim.events.clear()
		if first.orders.is_empty() and second.orders.is_empty() and first.pos.distance_to(second.pos)<crowd:stacked+=1.0/30
		if arrived<0 and tank.orders.is_empty():arrived=sim.time
	var gap:float=first.pos.distance_to(second.pos)
	print("  %s: asked=%s asker arrived %.1f s, blockers %.1f u apart, stacked %.1f s" % [label,asked,arrived,gap,stacked])
	check(asked,"%s: both blockers are asked to give way at once" % label)
	check(arrived>=0.0 and tank.pos.distance_to(OPEN+TO)<8.0,"%s: the asker gets through (%.1f s)" % [label,arrived])
	check(first.orders.is_empty() and second.orders.is_empty(),"%s: both blockers settle" % label)
	check(gap>=crowd,"%s: the blockers end at least a body apart (%.1f u)" % [label,gap])
	check(stacked==0.0,"%s: the blockers never stand stacked (%.1f s)" % [label,stacked])
	for u in [first,second]:
		var apart:float=sim.crowd_radius("tank")+sim.crowd_radius(u.kind)
		check(tank.pos.distance_to(u.pos)>=apart,"%s: the asker ends clear of the %s (%.1f u)" % [label,u.kind,tank.pos.distance_to(u.pos)])
