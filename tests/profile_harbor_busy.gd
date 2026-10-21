extends SceneTree
# Instrumented simulation CPU, reached through ordinary commands and purchases.
# A measured window is valid only after sustained real shots and two-sided
# contact. No time jumps, extra spawns, teleports, fog, damage or economy writes.
# No renderer is instantiated: these values are NOT rendered frame times/FPS.
# -- --seconds=30 --warmup-limit=300 --seed=47291 --report=/tmp/harbor-busy.json
const Sim=preload("res://scripts/simulation.gd")
const Policy=preload("res://tests/fixtures/harbor_pressure_policy.gd")
const DT:=1.0/30.0
const COMMAND_TICKS:=180
const RECENT_SECONDS:=10.0
const MIN_WARMUP:=60.0
const MIN_RECENT_SHOTS:=20
const MIN_SHOOTERS_PER_TEAM:=2
const MIN_ACTIVE_CONTACTS:=4
const MIN_MEASURED_SHOTS_PER_SECOND:=2.0
const MIN_CONTACT_SHARE:=0.5
var seconds:=30.0
var warmup_limit:=300.0
var combat_seed:=47291
var report_path:="res://artifacts/harbor-busy-cpu.json"
var failures:Array=[]
var recent_shots:Array=[]
var event_counts:Dictionary={}
var fingerprints:Array=[]
var first_shot:=-1.0

func require(ok:bool,message:String)->void:
	if not ok:failures.append(message);printerr("FAIL: ",message)

func _init()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seconds="):seconds=float(arg.trim_prefix("--seconds="))
		elif arg.begins_with("--warmup-limit="):warmup_limit=float(arg.trim_prefix("--warmup-limit="))
		elif arg.begins_with("--seed="):combat_seed=int(arg.trim_prefix("--seed="))
		elif arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
	require(seconds>=10 and seconds<=120,"measurement duration must be 10–120 seconds")
	require(warmup_limit>=MIN_WARMUP and warmup_limit<=900,"warm-up limit must be 60–900 seconds")
	if not failures.is_empty():quit(1);return
	call_deferred("run")

func warm_navigation(sim)->void:
	# Exactly the grids battle.gd prepares at mission load; setup is separate.
	for kind in ["rifle","tank","boat"]:
		var definition:Dictionary=sim.definitions[kind]
		sim.terrain.nav_grid(definition.domain,float(definition.radius),sim.terrain.mobility_profile(kind))
	sim.terrain.nav_grid("land",0.8,"infantry")

func consume(sim)->int:
	var shots:=0
	for event in sim.events:
		var type:String=event.type
		event_counts[type]=int(event_counts.get(type,0))+1
		if type=="shot":
			shots+=1
			recent_shots.append(sim.time)
			if first_shot<0:first_shot=sim.time
	while not recent_shots.is_empty() and float(recent_shots[0])<sim.time-RECENT_SECONDS:recent_shots.pop_front()
	sim.events.clear()
	return shots

func contact(sim)->Dictionary:
	var shooters:=[[],[]]
	var contacts:=[[],[]]
	for u in sim.units:
		if not sim.alive(u):continue
		if float(u.last_shot)>=sim.time-RECENT_SECONDS:shooters[u.team].append(u.id)
		if sim.alive(sim.get_unit(u.target)):contacts[u.team].append(u.id)
	return {"shots_last_10s":recent_shots.size(),"recent_shooters":shooters,
		"active_contacts":contacts,"contact_count":contacts[0].size()+contacts[1].size()}

func admitted(sim,state:Dictionary)->bool:
	return sim.time>=MIN_WARMUP-DT*0.5 and state.shots_last_10s>=MIN_RECENT_SHOTS and state.recent_shooters[0].size()>=MIN_SHOOTERS_PER_TEAM and state.recent_shooters[1].size()>=MIN_SHOOTERS_PER_TEAM and state.contact_count>=MIN_ACTIVE_CONTACTS

func force_state(sim)->Dictionary:
	var teams:=[{},{}]
	var members:=[0,0]
	var orders:Array=[]
	for u in sim.units:
		if not sim.alive(u):continue
		teams[u.team][u.kind]=int(teams[u.team].get(u.kind,0))+1
		for m in u.members:
			if m.hp>0:members[u.team]+=1
		if u.team==0:orders.append({"id":u.id,"kind":u.kind,"pos":u.pos,"orders":u.orders.duplicate(true),"state":u.state})
	return {"seconds":sim.time,"units_by_team_kind":teams,"living_soldiers":members,
		"visible_enemies":sim.living(1).filter(func(u):return u.visible).size(),
		"supply":sim.credits,"kills":sim.kills,"losses":sim.losses,
		"objectives":sim.objectives.duplicate(true),"player_orders":orders,"contact":contact(sim)}

func fingerprint(sim)->String:
	# Timers, pending orders/routes, soldiers, RNG and mission state are included.
	# Profiling clocks/caches are excluded. Serialization is outside timed ticks.
	return var_to_str([sim.time,sim.combat_rng.state,sim.credits,sim.result,sim.kills,sim.losses,
		sim.score_hold,sim.objectives,sim.units,sim.field_ops,sim.missiles,
		sim.route_queue,sim.slot_queue,sim.explored.keys(),sim.visible_cells.keys(),
		sim.terrain.dynamic_blocks,sim.terrain.field_zones]).sha256_text()

func distribution(values:Array)->Dictionary:
	if values.is_empty():return {"samples":0}
	var ordered:Array=values.duplicate();ordered.sort()
	var total:=0.0
	for value in ordered:total+=value
	return {"samples":ordered.size(),"mean_ms":total/ordered.size(),
		"p50_ms":ordered[floori((ordered.size()-1)*0.50)],"p95_ms":ordered[floori((ordered.size()-1)*0.95)],
		"p99_ms":ordered[floori((ordered.size()-1)*0.99)],"max_ms":ordered.back(),
		"ticks_over_33_333ms":ordered.filter(func(value):return value>1000.0/30.0).size()}

func run()->void:
	var started:=Time.get_ticks_usec()
	var sources:Dictionary={}
	for name in ["simulation","terrain","cover_behavior","infantry","field_ops"]:sources[name]=FileAccess.get_sha256("res://scripts/%s.gd" % name)
	sources["policy"]=FileAccess.get_sha256("res://tests/fixtures/harbor_pressure_policy.gd")
	var sim=Sim.new(true,Sim.default_selection())
	sim.combat_rng.seed=combat_seed
	require(sim.scenario.id=="black_sea_harbor" and not sim.scenario.hidden,"public authored Harbor is selected")
	require(sim.credits==3200 and sim.field_ops.income_rate==6,"authored test economy is unchanged")
	require(sim.living(0).size()==sim.scenario.player_force.size(),"authored starting force only")
	warm_navigation(sim)
	var setup_ms:float=(Time.get_ticks_usec()-started)/1000.0
	var policy=Policy.new()
	var tick:=0
	var gate:Dictionary={}
	while sim.time<warmup_limit and sim.result=="":
		if tick%COMMAND_TICKS==0:policy.play(sim)
		sim.tick(DT);tick+=1
		consume(sim)
		if tick%30==0:
			fingerprints.append({"tick":tick,"sha256":fingerprint(sim)})
			gate=contact(sim)
			if admitted(sim,gate):break
		if tick%900==0:print("HARBOR BUSY WARMUP: ",JSON.stringify({"seconds":sim.time,"shots":event_counts.get("shot",0),"contact":contact(sim),"own":sim.living(0).size(),"enemy":sim.living(1).size()}))
	var before:=force_state(sim)
	var warmup_wall_ms:float=(Time.get_ticks_usec()-started)/1000.0-setup_ms
	require(not gate.is_empty() and admitted(sim,gate),"warm-up reached sustained two-sided combat before its limit")
	var costs:Array=[]
	var phase_costs:Dictionary={}
	var spikes:Array=[]
	var shots:=0
	var contact_ticks:=0
	var measure_ticks:=roundi(seconds/DT)
	var paths_before:int=sim.terrain.path_calls
	var path_usec_before:int=sim.terrain.path_usec
	var grids_before:Array=sim.terrain.navigation.keys()
	if failures.is_empty():
		sim.profiling=true
		for measured in measure_ticks:
			if tick%COMMAND_TICKS==0:policy.play(sim)
			sim.profile.clear()
			var stamp:=Time.get_ticks_usec()
			sim.tick(DT);tick+=1
			var cost:float=(Time.get_ticks_usec()-stamp)/1000.0
			costs.append(cost)
			for key in phase_costs:phase_costs[key].append(0.0)
			for key in sim.profile:
				if not phase_costs.has(key):
					phase_costs[key]=[];phase_costs[key].resize(costs.size());phase_costs[key].fill(0.0)
				phase_costs[key][-1]=sim.profile[key]
			shots+=consume(sim)
			if contact(sim).contact_count>=MIN_ACTIVE_CONTACTS:contact_ticks+=1
			if tick%30==0:fingerprints.append({"tick":tick,"sha256":fingerprint(sim)})
			if cost>1000.0/30.0:spikes.append({"tick":tick,"seconds":sim.time,"cpu_ms":cost,"phases_ms":sim.profile.duplicate()})
			if sim.result!="":break
		require(costs.size()==measure_ticks,"full requested CPU window measured")
		require(shots>=seconds*MIN_MEASURED_SHOTS_PER_SECOND,"measurement contains sustained real shots")
		require(contact_ticks>=measure_ticks*MIN_CONTACT_SHARE,"at least half the measured ticks have four active contacts")
	require(absf(sim.time-tick*DT)<0.0001,"all mission time comes from fixed 30 Hz ticks")
	var phases:Dictionary={}
	for key in phase_costs:phases[key]=distribution(phase_costs[key])
	var report:Dictionary={"schema":1,"scope":"Instrumented headless simulation CPU only; no renderer, GPU or input-device measurement.",
		"engine":Engine.get_version_info(),"os":OS.get_name(),"cpu":OS.get_processor_name(),
		"processor_count":OS.get_processor_count(),"seed":combat_seed,"fixed_dt":DT,
		"scenario_sha256":FileAccess.get_sha256("res://resources/scenarios.json"),
		"source_sha256":sources,"timing_note":"Elapsed time around synchronous CPU work includes OS scheduling. Run paired serial comparisons without competing workloads; setup, reporting and command APIs are outside tick timing.",
		"setup_ms":setup_ms,"warmup_wall_ms":warmup_wall_ms,"first_shot_seconds":first_shot,
		"admission":{"minimum_warmup_seconds":MIN_WARMUP,"minimum_shots_last_10s":MIN_RECENT_SHOTS,"minimum_recent_shooters_per_team":MIN_SHOOTERS_PER_TEAM,"minimum_active_contacts":MIN_ACTIVE_CONTACTS,"observed":gate},
		"before":before,"after":force_state(sim),"measurement":{"requested_seconds":seconds,"shots":shots,"ticks_with_four_contacts":contact_ticks,"cpu_tick":distribution(costs),"nested_cpu_phases":phases,
			"phase_note":"Phases are nested: cover_find_slot is inside cover_update, inside infantry_move, inside unit_loop. Do not add all phase totals.","path_calls":sim.terrain.path_calls-paths_before,"path_cpu_ms":(sim.terrain.path_usec-path_usec_before)/1000.0,"grids_added":sim.terrain.navigation.keys().filter(func(key):return key not in grids_before)},
		"rendered_frame_ms":null,"rendered_frames_measured":0,"gpu_frame_ms":null,
		"policy":"combined-public-objectives","policy_stats":policy.stats,"commands":policy.actions,"command_api_costs":policy.api_costs,
		"events":event_counts,"fingerprints":fingerprints,"spikes":spikes,"valid_busy_window":failures.is_empty(),"failures":failures}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(report_path.get_base_dir()))
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:require(false,"report file can be written")
	else:file.store_string(JSON.stringify(report,"  ")+"\n");file.close()
	print("HARBOR BUSY CPU: ",JSON.stringify({"valid":failures.is_empty(),"from_seconds":before.seconds,"to_seconds":sim.time,"shots":shots,"contact_ticks":contact_ticks,"cpu_tick":distribution(costs),"report":ProjectSettings.globalize_path(report_path)}))
	print("RENDERED FRAMES: not measured; headless simulation CPU is not frame time or FPS.")
	quit(0 if failures.is_empty() else 1)
