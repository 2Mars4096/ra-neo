extends SceneTree
# CPU cost of the simulation tick on the harbor map during a busy fight:
# full enemy defences plus two assault waves converging on a player position.
const Sim=preload("res://scripts/simulation.gd")
const FieldOps=preload("res://scripts/field_ops.gd")
func harbor_index()->int:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		if configs[i].id=="black_sea_harbor":return i
	return -1
func _init()->void:
	var sim=Sim.new(true,harbor_index())
	for i in 6:sim.spawn("rifle",0,Vector2(300+i*5,640))
	for i in 2:sim.spawn("tank",0,Vector2(310+i*8,650))
	for wave in 2:
		sim.time=float(sim.field_ops.get("waves",{}).get("next",sim.scenario.enemy_waves.first))+0.1
		FieldOps.enemy_offensive(sim)
	var units:int=sim.units.filter(func(u):return sim.alive(u)).size()
	sim.terrain.nav_grid("land",0.8,"infantry") # As battle.gd prebuilds at load.
	var grids_before:Array=sim.terrain.navigation.keys()
	sim.profiling=true
	var costs:Array=[]
	for i in 900:
		var before:Dictionary=sim.profile.duplicate()
		var wet:float=sim.terrain.wetness
		var t:=Time.get_ticks_usec()
		sim.tick(1.0/30)
		var cost:=(Time.get_ticks_usec()-t)/1000.0
		costs.append(cost)
		if cost>60.0:
			var parts:Array=[]
			for key in sim.profile:parts.append("%s=%.0f" % [key,sim.profile[key]-before.get(key,0.0)])
			print("SPIKE tick=%d %.0fms wet %.2f->%.2f %s" % [i,cost,wet,sim.terrain.wetness,parts])
	costs.sort()
	var total:=0.0
	for c in costs:total+=c
	print("HARBOR COMBAT PROFILE: units=%d ticks=%d mean=%.2fms p50=%.2fms p95=%.2fms max=%.2fms" % [units,costs.size(),total/costs.size(),costs[costs.size()/2],costs[int(costs.size()*0.95)],costs.back()])
	print("GRIDS before fight: ",grids_before)
	print("GRIDS built during fight: ",sim.terrain.navigation.keys().filter(func(k):return k not in grids_before))
	var spikes:Array=[]
	var keys:Array=sim.profile.keys()
	keys.sort_custom(func(a,b):return sim.profile[a]>sim.profile[b])
	for key in keys:print("PHASE %-16s total=%8.1fms per_tick=%6.2fms" % [key,sim.profile[key],sim.profile[key]/costs.size()])
	quit()
