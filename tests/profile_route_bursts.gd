extends SceneTree
# Route-planning bursts on the harbor map: an enemy assault wave launched from
# inside a simulation tick, and a 16-unit player order across the map (the
# issue() call itself, as from the UI, then the following ticks).
const Sim=preload("res://scripts/simulation.gd")
func harbor_index()->int:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		if configs[i].id=="black_sea_harbor":return i
	return -1
func stats(costs:Array)->String:
	var sorted:=costs.duplicate();sorted.sort()
	return "ticks=%d p50=%.2fms max=%.2fms over33ms=%d" % [sorted.size(),sorted[sorted.size()/2],sorted.back(),sorted.filter(func(c):return c>33.0).size()]
var sim
func timed_tick()->float:
	var before:Dictionary=sim.profile.duplicate()
	var paths:int=sim.terrain.path_calls
	var path_usec:int=sim.terrain.path_usec
	var t:=Time.get_ticks_usec()
	sim.tick(1.0/30)
	var cost:=(Time.get_ticks_usec()-t)/1000.0
	if cost>33.0:
		var parts:Array=[]
		for key in sim.profile:
			if sim.profile[key]-before.get(key,0.0)>=1.0:parts.append("%s=%.0f" % [key,sim.profile[key]-before.get(key,0.0)])
		print("SPIKE t=%.2f %.0fms paths=%d/%.0fms %s" % [sim.time,cost,sim.terrain.path_calls-paths,(sim.terrain.path_usec-path_usec)/1000.0,parts])
	return cost
func _init()->void:
	sim=Sim.new(true,harbor_index())
	sim.profiling=true
	for i in 6:sim.spawn("rifle",0,Vector2(300+i*5,640))
	for i in 2:sim.spawn("tank",0,Vector2(310+i*8,650))
	# As battle.gd prebuilds at load.
	for kind in ["rifle","tank","boat"]:
		var definition:Dictionary=sim.definitions[kind]
		sim.terrain.nav_grid(definition.domain,float(definition.radius),sim.terrain.mobility_profile(kind))
	sim.terrain.nav_grid("land",0.8,"infantry")
	# The wave launches from FieldOps.tick a few ticks into the window.
	sim.time=float(sim.field_ops.get("waves",{}).get("next",sim.scenario.enemy_waves.first))-0.1
	var costs:Array=[]
	var launched:=-1
	for i in 150:
		var before:int=sim.units.size()
		costs.append(timed_tick())
		if launched<0 and sim.units.size()>before:launched=i
	print("WAVE LAUNCH: tick=%d launch_tick=%.2fms %s" % [launched,costs[maxi(0,launched)],stats(costs)])
	var group:Array=[]
	for i in 12:group.append(sim.spawn("rifle",0,Vector2(250+(i%4)*7,600+(i/4)*7)).id)
	for i in 4:group.append(sim.spawn("tank",0,Vector2(250+i*9,630)).id)
	sim.tick(1.0/30)
	var t:=Time.get_ticks_usec()
	var accepted:int=sim.issue(group,Vector2(860,200),"move")
	var issue_ms:=(Time.get_ticks_usec()-t)/1000.0
	costs.clear()
	var moving_at:=-1
	for i in 150:
		costs.append(timed_tick())
		if moving_at<0 and group.all(func(id):return not sim.get_unit(id).path.is_empty() or sim.get_unit(id).orders.is_empty()):moving_at=i+1
	print("GROUP ORDER: accepted=%d/%d issue=%.2fms all_routed_after=%d ticks %s" % [accepted,group.size(),issue_ms,moving_at,stats(costs)])
	quit()
