extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
var failures:=0
func check(ok:bool,label:String)->void:
	if not ok:failures+=1;printerr("FAIL: ",label)
func _init()->void:
	for preset in [0,3]:
		var indexed=Sim.new(true,preset)
		indexed.spatial_targeting_threshold=0
		var reference=Sim.new(true,preset)
		reference.use_spatial_targeting=false
		for sim in [indexed,reference]:
			var force:Array=sim.living(0).filter(func(u):return sim.definitions[u.kind].domain=="land").map(func(u):return u.id)
			sim.issue(force,sim.objectives[0].pos,"attack_move")
		for frame in 450:
			indexed.tick(0.1);reference.tick(0.1)
			check(indexed.combat_rng.state==reference.combat_rng.state,"seeded shots match brute force")
			for i in indexed.units.size():
				var a:Dictionary=indexed.units[i];var b:Dictionary=reference.units[i]
				check(a.hp==b.hp and a.pos==b.pos and a.target==b.target and a.seen_by==b.seen_by,"combat and movement unchanged")
			check(indexed.visible_cells==reference.visible_cells and indexed.explored==reference.explored,"fog and explored terrain match exhaustive reference")
			indexed.events.clear();reference.events.clear()
	var lookup=Sim.new(true,3)
	var first:Dictionary=lookup.units[0]
	check(lookup.get_unit(first.id)==first and lookup.get_unit(-1).is_empty(),"indexed IDs resolve only registered units")
	first.hp=0
	check(lookup.get_unit(first.id).hp==0,"ID lookup preserves authoritative death state")
	# Query scaling on a synthetic town-sized distribution, not a full battle benchmark.
	var report:Array=[]
	for count in [250,500,1000,2000]:
		var sim=Sim.new(false,3)
		for i in count:
			sim.units.append({"id":i+1,"kind":"rifle","hp":100.0,"pos":Vector2((i%50)*12,(i/50)*12)})
		sim.rebuild_spatial()
		var indexed_us:Array=[];var brute_us:Array=[];var total_candidates:=0
		for q in 100:
			var origin:Vector2=sim.units[(q*17)%count].pos
			var start:=Time.get_ticks_usec()
			var nearby:Array=sim.range_candidates(origin,26)
			indexed_us.append(Time.get_ticks_usec()-start)
			start=Time.get_ticks_usec()
			var expected:Array=sim.units.filter(func(u):return sim.alive(u) and origin.distance_squared_to(u.pos)<=26*26)
			brute_us.append(Time.get_ticks_usec()-start)
			check(nearby.map(func(u):return u.id)==expected.map(func(u):return u.id),"spatial query matches exhaustive town distribution")
			total_candidates+=nearby.size()
		indexed_us.sort();brute_us.sort()
		report.append({"entities":count,"indexed_query_us_p95":indexed_us[95],"brute_query_us_p95":brute_us[95],"average_candidates":total_candidates/100.0})
	FileAccess.open("res://artifacts/spatial-scaling.json",FileAccess.WRITE).store_string(JSON.stringify({"scope":"Synthetic range queries only; not a rendered or simulated thousand-troop battle","results":report},"  "))
	print("SPATIAL TARGETING: ",failures," failures; ",JSON.stringify(report))
	quit(0 if failures==0 else 1)
