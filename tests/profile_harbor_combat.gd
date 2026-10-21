extends SceneTree
# Historical synthetic workload: extra player units plus time-jumped assault
# waves. The 30 seconds can be transit without sustained fire. It is NOT the
# normal-mission busy-combat acceptance case; use profile_harbor_busy.gd for that.
# --repeat=N also reports per-tick minima as a noise diagnostic, not a percentile
# of real frames. No renderer or GPU work is measured.
const Sim=preload("res://scripts/simulation.gd")
const FieldOps=preload("res://scripts/field_ops.gd")
const BUDGET_MS:=33.0
func harbor_index()->int:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		if configs[i].id=="black_sea_harbor":return i
	return -1
func summary(label:String,costs:Array)->String:
	var sorted:=costs.duplicate();sorted.sort()
	var total:=0.0
	for c in sorted:total+=c
	return "%s ticks=%d tick0=%.2fms mean=%.2fms p50=%.2fms p95=%.2fms max=%.2fms over%.0fms=%d" % [label,sorted.size(),costs[0],total/sorted.size(),sorted[sorted.size()/2],sorted[int(sorted.size()*0.95)],sorted.back(),BUDGET_MS,sorted.filter(func(c):return c>BUDGET_MS).size()]
# Per-tick phase costs of every run (phase -> one entry per tick).
var phase_ticks:Array=[]
# Seeded state digest (`-- --fingerprint`): optimisations must leave it unchanged.
func digest(sim)->String:
	var state:Array=[sim.combat_rng.state,sim.time,sim.kills,sim.losses]
	for u in sim.units:
		var members:Array=[]
		for m in u.members:members.append([m.pos,m.hp,m.get("cover_phase",""),m.get("posture",""),m.get("target",-1),m.get("cover_goal",Vector2.ZERO),m.get("state","")])
		state.append([u.id,u.pos,u.hp,u.target,u.state,u.path,u.orders,members,u.suppression])
	return var_to_str(state).sha256_text()
var fingerprints:Array=[]
func fight(report:bool)->Array:
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
	var phases:Dictionary={}
	phase_ticks.append(phases)
	for i in 900:
		var before:Dictionary=sim.profile.duplicate()
		var wet:float=sim.terrain.wetness
		var paths:int=sim.terrain.path_calls
		var path_usec:int=sim.terrain.path_usec
		var t:=Time.get_ticks_usec()
		sim.tick(1.0/30)
		var cost:=(Time.get_ticks_usec()-t)/1000.0
		costs.append(cost)
		for key in sim.profile:
			if not phases.has(key):
				phases[key]=PackedFloat64Array();phases[key].resize(900)
			phases[key][i]=sim.profile[key]-before.get(key,0.0)
		if fingerprinting and i%100==99:fingerprints.append(digest(sim))
		if report and cost>BUDGET_MS:
			var parts:Array=[]
			for key in sim.profile:
				var spent:float=sim.profile[key]-before.get(key,0.0)
				if spent>=1.0:parts.append("%s=%.0f" % [key,spent])
			print("SPIKE tick=%d %.0fms wet %.2f->%.2f paths=%d/%.0fms %s" % [i,cost,wet,sim.terrain.wetness,sim.terrain.path_calls-paths,(sim.terrain.path_usec-path_usec)/1000.0,parts])
	if report:
		print(summary("HARBOR COMBAT PROFILE: units=%d" % units,costs))
		print("GRIDS before fight: ",grids_before)
		print("GRIDS built during fight: ",sim.terrain.navigation.keys().filter(func(k):return k not in grids_before))
		print("PATHS: calls=%d total=%.0fms" % [sim.terrain.path_calls,sim.terrain.path_usec/1000.0])
		var keys:Array=sim.profile.keys()
		keys.sort_custom(func(a,b):return sim.profile[a]>sim.profile[b])
		for key in keys:print("PHASE %-16s total=%8.1fms per_tick=%6.2fms" % [key,sim.profile[key],sim.profile[key]/costs.size()])
	return costs
var fingerprinting:=false
func _init()->void:
	print("SCOPE: synthetic extra-force/time-jumped transit; combat activity is not asserted. CPU only, no rendered frames.")
	var repeat:=1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--repeat="):repeat=maxi(1,int(arg.get_slice("=",1)))
		if arg=="--fingerprint":fingerprinting=true
	var best:Array=fight(true)
	for f in fingerprints:print("FINGERPRINT ",f)
	fingerprints.clear()
	for run in range(1,repeat):
		var costs:Array=fight(false)
		print(summary("HARBOR COMBAT RUN %d:" % (run+1),costs))
		for i in best.size():best[i]=minf(best[i],costs[i])
	# Worst tick per phase, on the per-tick minimum over runs (filters noise).
	for key in phase_ticks[0]:
		var worst:=0.0;var at:=-1
		for i in 900:
			var low:=INF
			for phases in phase_ticks:low=minf(low,phases[key][i] if phases.has(key) else 0.0)
			if low>worst:worst=low;at=i
		print("PHASE-MAX %-16s %.2fms at tick %d (per-tick min of %d)" % [key,worst,at,repeat])
	# `-- --ticks=MS`: every tick whose per-tick minimum exceeds MS, with its top phases.
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--ticks="):continue
		for i in 900:
			if best[i]<=float(arg.get_slice("=",1)):continue
			var parts:Array=[]
			for key in phase_ticks[0]:
				var low:=INF
				for phases in phase_ticks:low=minf(low,phases[key][i] if phases.has(key) else 0.0)
				if low>=1.0 and key!="unit_loop":parts.append("%s=%.1f" % [key,low])
			print("TICK %d min=%.1fms %s" % [i,best[i],parts])
	if repeat>1:
		print(summary("HARBOR COMBAT PER-TICK MIN OF %d:" % repeat,best))
		for i in best.size():
			if best[i]>BUDGET_MS:print("PERSISTENT SPIKE tick=%d min=%.1fms" % [i,best[i]])
	quit()
