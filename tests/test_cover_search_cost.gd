extends SceneTree
# Cover search cost per tick on black_sea_harbor (CoverBehavior.update, which
# includes every find_slot call and its route planning):
# - after test_hitches' 40-unit cross-map order, with the navigation grids
#   battle.gd builds at load (rifle/tank/boat plus the 0.8 m soldier grid);
# - 24 sections coming under contact on the same tick (every alert search at
#   once), where sections must still reach cover within ~1-2 s.
# The 0.8 m soldier grid built lazily by the first cover route costs ~160 ms
# on its own: that, not a burst of searches, is the large-order spike when a
# simulation skips battle.gd's warm-up. It is reported here, not asserted.
const Sim=preload("res://scripts/simulation.gd")
const BUDGET_MS:=25.0
const TAKE_COVER_S:=2.0
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

# The grids battle.gd builds while loading a battle.
func warm(sim)->void:
	for kind in ["rifle","tank","boat"]:
		var definition:Dictionary=sim.definitions[kind]
		sim.terrain.nav_grid(definition.domain,float(definition.radius),sim.terrain.mobility_profile(kind))
	sim.terrain.nav_grid("land",0.8,"infantry")

# Ticks `count` times with phase timing; returns the worst cover ms per tick.
func run(sim,count:int,each:Callable=Callable())->Vector2:
	sim.profiling=true
	var worst:=0.0
	var at:=0
	for i in count:
		sim.profile.clear()
		sim.tick(1.0/30);sim.events.clear()
		var cost:float=sim.profile.get("cover_update",0.0)
		if cost>worst:worst=cost;at=i+1
		if each.is_valid():each.call()
	sim.profiling=false
	return Vector2(worst,at)

func large_order()->void:
	var sim=Sim.new(false,harbor_index())
	warm(sim)
	var group:Array=[]
	for i in 30:group.append(sim.spawn("rifle",0,Vector2(250+(i%4)*7,600+(i/4)*7)).id)
	for i in 10:group.append(sim.spawn("tank",0,Vector2(250+(i%6)*9,680+(i/6)*9)).id)
	var accepted:int=sim.issue(group,Vector2(860,200),"move")
	var worst:=run(sim,150)
	print("  large order: accepted %d/40, worst cover search %.1f ms (tick %d of 150)"%[accepted,worst.x,worst.y])
	check(worst.x<=BUDGET_MS,"40-unit order: cover search stays under %.0f ms per tick (%.1f)"%[BUDGET_MS,worst.x])
	# The same order without the soldier grid warm-up: the first cover route builds it.
	var lazy=Sim.new(false,harbor_index())
	for kind in ["rifle","tank"]:
		var definition:Dictionary=lazy.definitions[kind]
		lazy.terrain.nav_grid(definition.domain,float(definition.radius),lazy.terrain.mobility_profile(kind))
	var lazy_group:Array=[]
	for i in 30:lazy_group.append(lazy.spawn("rifle",0,Vector2(250+(i%4)*7,600+(i/4)*7)).id)
	for i in 10:lazy_group.append(lazy.spawn("tank",0,Vector2(250+(i%6)*9,680+(i/6)*9)).id)
	lazy.issue(lazy_group,Vector2(860,200),"move")
	var cold:=run(lazy,30)
	print("  large order without the 0.8 m soldier grid warm-up: worst cover search %.1f ms (tick %d) [informational]"%[cold.x,cold.y])

func contact_burst(origin:Vector2)->void:
	var sim=Sim.new(false,harbor_index())
	warm(sim)
	var ours:Array=[]
	for i in 24:ours.append(sim.spawn("rifle",0,origin+Vector2((i%6)*6,(i/6)*6)))
	for i in 4:sim.spawn("rifle",1,origin+Vector2(i*8,-14)).hold_command=true
	var first:={}
	var worst:=run(sim,150,func():
		for u in ours:
			if not first.has(u.id) and u.members.any(func(m):return m.hp>0 and m.get("cover_phase","") in ["SEEKING","SETTLING","SHELTERED"]):first[u.id]=sim.time)
	var times:Array=first.values();times.sort()
	var latest:float=times.back() if not times.is_empty() else INF
	print("  contact burst at %s: worst cover search %.1f ms (tick %d), %d/24 sections started for cover, latest at %.1f s"%[origin,worst.x,worst.y,first.size(),latest])
	check(worst.x<=BUDGET_MS,"contact burst %s: cover search stays under %.0f ms per tick (%.1f)"%[origin,BUDGET_MS,worst.x])
	check(first.size()>=8,"contact burst %s: sections take cover (%d)"%[origin,first.size()])
	check(latest<=TAKE_COVER_S,"contact burst %s: every section that takes cover starts within %.1f s (%.1f)"%[origin,TAKE_COVER_S,latest])

func _init()->void:
	large_order()
	for origin in [Vector2(420,560),Vector2(500,680),Vector2(440,575)]:contact_burst(origin)
	print("COVER SEARCH COST: %d checks, %d failures"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)
