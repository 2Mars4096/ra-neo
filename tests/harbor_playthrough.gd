extends SceneTree
# Full authored Black Sea Harbor with fixed 30 Hz ticks and ordinary player
# command/purchase APIs only. This bot is evidence of a simulation outcome,
# not human playability, balance, renderer performance or input-device QA.
# No extra spawn, HP/objective/resource writes, time jumps or fog overrides.
# -- --policy=combined|armor|reckless --seed=47291 --seconds=1500
# --expect=terminal|victory|defeat --observe (report an unfinished run, not PASS)
# --stop-on-rejection requires --observe; captures navigation after stopping.
# --watch-unit=ID records the first blocked anchor transition in observations.
const Sim=preload("res://scripts/simulation.gd")
const ReleaseInfo=preload("res://scripts/release_info.gd")
const OrderDiagnostics=preload("res://tests/fixtures/harbor_order_diagnostics.gd")
const DT:=1.0/30.0
const PERIOD:=6.0
const MIX:={"combined":["tank","rifle","atgm","tank","rifle","aa"],
	"armor":["tank","tank","tank","rifle","aa"]}
var policy:="combined"
var combat_seed:=47291
var limit:=1500.0
var expectation:="terminal"
var observe:=false
var stop_on_rejection:=false
var watch_unit:=-1
var revision:="unspecified"
var checks:=0
var failures:=0
var stats:Dictionary={}
var assigned:Dictionary={}
var purchase_index:=0
var captures:Dictionary={}
var stages:Array=[]
var actions:Array=[]
var last_goal:=-1
var first_rejection:Dictionary={}
var first_blocked_anchor:Dictionary={}

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: ",label)

func _init()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--policy="):policy=arg.trim_prefix("--policy=")
		elif arg.begins_with("--seed="):combat_seed=int(arg.trim_prefix("--seed="))
		elif arg.begins_with("--seconds="):limit=float(arg.trim_prefix("--seconds="))
		elif arg.begins_with("--expect="):expectation=arg.trim_prefix("--expect=")
		elif arg.begins_with("--revision="):revision=arg.trim_prefix("--revision=")
		elif arg=="--observe":observe=true
		elif arg=="--stop-on-rejection":stop_on_rejection=true
		elif arg.begins_with("--watch-unit="):watch_unit=int(arg.trim_prefix("--watch-unit="))
	check(policy in ["combined","armor","reckless"],"recognized policy")
	check(expectation in ["terminal","victory","defeat"],"recognized expected outcome")
	check(limit>0 and limit<=3600,"simulation limit is in (0, 3600] seconds")
	check(not stop_on_rejection or observe,"rejection-stop diagnostics require observation mode")
	check(watch_unit<0 or observe,"anchor-watch diagnostics require observation mode")
	if failures>0:quit(1);return
	call_deferred("run")

func run()->void:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	var index:int=configs.find_custom(func(config):return config.id=="black_sea_harbor")
	check(index>=0 and index==Sim.default_selection(),"public default is the actual Harbor operation")
	if failures>0:quit(1);return
	var sim=Sim.new(true,index)
	sim.combat_rng.seed=combat_seed
	check(sim.scenario.id=="black_sea_harbor" and not sim.scenario.hidden,"active, public Harbor")
	check(sim.credits==3200.0 and sim.field_ops.income_rate==6.0,"authored 3,200 starting supply / +6 income unchanged")
	check(sim.living(0).size()==sim.scenario.player_force.size(),"authored starting army only")
	check(sim.objectives.size()==3 and sim.scenario.hold==90,"all three objectives and full hold remain required")
	stats={"orders":0,"sections_ordered":0,"sections_rejected":0,"purchases":{},"spent":0,
		"accepted_by_unit":{},"rejected_by_unit":{},
		"purchase_rejections":{},"first_combat_seconds":-1.0,"first_move_seconds":-1.0,"events":{}}
	var starting:Dictionary={}
	for unit in sim.living(0):starting[unit.id]=unit.pos
	var started:=Time.get_ticks_msec()
	var policy_hash:=FileAccess.get_sha256("res://tests/harbor_playthrough.gd")
	var source_hashes:Dictionary={}
	for source in DirAccess.get_files_at("res://scripts"):
		if source.ends_with(".gd"):source_hashes[source]=FileAccess.get_sha256("res://scripts/"+source)
	var data_hashes:Dictionary={}
	for source in DirAccess.get_files_at("res://resources"):
		if source.ends_with(".json"):data_hashes[source]=FileAccess.get_sha256("res://resources/"+source)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	var path:="res://artifacts/harbor-%s-%d%s.json" % [policy,combat_seed,"-rejection" if stop_on_rejection else ""]
	var steps:=int(ceil(limit/DT))
	for step in steps:
		if step%int(PERIOD/DT)==0:play(sim)
		if stop_on_rejection and not first_rejection.is_empty():break
		var before:Dictionary={}
		if watch_unit>=0 and first_blocked_anchor.is_empty():before=OrderDiagnostics.anchor(sim,watch_unit)
		sim.tick(DT)
		if not before.is_empty():
			var unit:Dictionary=sim.get_unit(watch_unit)
			if sim.alive(unit) and not sim.terrain.traversable(unit.pos,sim.definitions[unit.kind].domain,float(sim.definitions[unit.kind].radius)):
				first_blocked_anchor={"before_tick":before,"after_tick":OrderDiagnostics.anchor(sim,watch_unit)}
				print("HARBOR BLOCKED ANCHOR: ",JSON.stringify({"seconds":sim.time,"id":watch_unit,"pos":[unit.pos.x,unit.pos.y]}))
		for event in sim.events:
			var kind:String=event.type
			stats.events[kind]=int(stats.events.get(kind,0))+1
		if stats.first_combat_seconds<0 and sim.kills+sim.losses>0:stats.first_combat_seconds=sim.time
		if stats.first_move_seconds<0:
			for id in starting:
				if sim.get_unit(id).pos.distance_to(starting[id])>5.0:
					stats.first_move_seconds=sim.time
					break
		for i in sim.objectives.size():
			if sim.objectives[i].owner==0 and not captures.has(str(i)):captures[str(i)]=sim.time
		sim.events.clear() # consume presentation events, as battle.gd does
		if step%1800==0:
			stages.append(stage(sim))
			print("HARBOR PROGRESS: ",JSON.stringify(stages[-1]))
			var checkpoint:=FileAccess.open(path.trim_suffix(".json")+"-checkpoint.json",FileAccess.WRITE)
			if checkpoint!=null:
				checkpoint.store_string(JSON.stringify({"revision":revision,"policy":policy,"seed":combat_seed,
					"seconds":sim.time,"complete":false,"snapshot":ReleaseInfo.snapshot(sim,"policy-checkpoint")},"  "))
				checkpoint.close()
		if sim.result!="":break
	# The outcome must be earned by the live mission. A time limit is unresolved,
	# never a successful full-mission pass. --observe writes useful failed-policy
	# evidence without advertising a test pass.
	check(stats.sections_ordered>0,"ordinary command API accepted player orders")
	check(stats.first_move_seconds>=0,"authored units moved through simulation")
	check(stats.first_combat_seconds>=0,"live combat produced a kill/loss")
	if policy!="reckless":check(stats.purchases.size()>0,"normal paid reinforcements were used")
	check(absf(sim.credits-(3200.0+6.0*sim.time-float(stats.spent)))<0.01,"all supply accounted for by authored income and ordinary purchases")
	if sim.result=="VICTORY":
		check(sim.objectives.all(func(o):return o.owner==0 and not o.get("enemy_present",false)) and sim.score_hold>=90.0,"earned victory retains all three sectors and full uncontested hold")
	if not observe:
		check(sim.result!="","mission reached a terminal outcome before the limit")
		if expectation!="terminal":check(sim.result==expectation.to_upper(),"mission reached expected "+expectation)
	# Route probes can populate navigation caches and consume work. Run detailed
	# diagnosis only after the stopped observational trace, never during a match.
	if stop_on_rejection and not first_rejection.is_empty():
		first_rejection["navigation"]=OrderDiagnostics.navigation(sim,first_rejection)
	var report:Dictionary={"schema":1,"policy":policy,"combat_seed":combat_seed,"fixed_step":DT,
		"revision":revision,"source_sha256":source_hashes,"runtime_json_sha256":data_hashes,
		"starting_supply":3200,"income_per_second":6,"limit_seconds":limit,
		"result":sim.result if sim.result!="" else "UNRESOLVED","seconds":sim.time,
		"hold_seconds":sim.score_hold,"first_captures":captures,"kills":sim.kills,"losses":sim.losses,
		"supply_remaining":sim.credits,"waves_dispatched":sim.field_ops.get("waves",{}).get("index",0),
		"reserve_dispatched":sim.counterattack_sent,"stats":stats,"actions":actions,"stages":stages,
		"first_rejection":first_rejection,"stopped_on_rejection":stop_on_rejection and not first_rejection.is_empty(),
		"watch_unit":watch_unit,"first_blocked_anchor":first_blocked_anchor,
		"starting_army_outcomes":initial_outcomes(sim,starting),
		"command_counts":"Immediate issue() admissions/rejections; admitted large-group targets may resolve on later ticks.",
		"policy_sha256":policy_hash,
		"final":ReleaseInfo.snapshot(sim,"automated-harbor-policy"),
		"wall_seconds":(Time.get_ticks_msec()-started)/1000.0,
		"scenario_sha256":data_hashes["scenarios.json"],
		"scope":"Simulation command playthrough; no renderer/input-device/human-balance acceptance.",
		"passed":not observe and failures==0}
	var file:=FileAccess.open(path,FileAccess.WRITE)
	check(file!=null,"portable playthrough report opened")
	if file!=null:file.store_string(JSON.stringify(report,"  ")+"\n");file.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path.trim_suffix(".json")+"-checkpoint.json"))
	print("HARBOR OUTCOME: %s seed=%d result=%s sim=%.1fs kills=%d losses=%d captures=%s wall=%.1fs report=%s" % [policy,combat_seed,report.result,sim.time,sim.kills,sim.losses,JSON.stringify(captures),report.wall_seconds,ProjectSettings.globalize_path(path)])
	if observe:print("HARBOR OBSERVATION: complete=%s, %d checks, %d failures (not an acceptance pass)" % [sim.result!="",checks,failures])
	else:print("HARBOR PLAYTHROUGH: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)

func stage(sim)->Dictionary:
	return {"seconds":snappedf(sim.time,0.1),"own":sim.living(0).size(),"enemy":sim.living(1).size(),
		"captures":sim.objectives.map(func(o):return o.owner),"progress":sim.objectives.map(func(o):return snappedf(o.progress,0.1)),
		"hold":snappedf(sim.score_hold,0.1),"kills":sim.kills,"losses":sim.losses,"supply":int(sim.credits)}

func effective(sim,unit:Dictionary)->bool:
	return sim.alive(unit) and not unit.get("structure",false) and not unit.get("combat_ineffective",false) and not unit.get("mobility_kill",false)

func initial_outcomes(sim,starting:Dictionary)->Array:
	var outcomes:Array=[]
	for id in starting:
		var unit:Dictionary=sim.get_unit(id)
		outcomes.append({"id":id,"kind":unit.kind,"alive":sim.alive(unit),"hp":unit.hp,
			"pos":[unit.pos.x,unit.pos.y],"distance_from_start":unit.pos.distance_to(starting[id]),
			"state":unit.state,"reason":unit.reason,"orders":OrderDiagnostics.plain(unit.orders),
			"accepted_orders":stats.accepted_by_unit.get(id,0),"rejected_orders":stats.rejected_by_unit.get(id,0)})
	return outcomes

func order(sim,units:Array,goal:Vector2,mode:String="attack_move",force:bool=false)->void:
	var ids:Array=[]
	for unit in units:
		if not effective(sim,unit):continue
		var previous:Dictionary=assigned.get(unit.id,{})
		var changed:bool=previous.is_empty() or Vector2(previous.goal).distance_to(goal)>3.0 or previous.mode!=mode
		var idle:bool=unit.orders.is_empty() and unit.pos.distance_to(goal)>6.0
		var stalled:bool=float(unit.get("blocked_time",0.0))>12.0 and sim.time-float(previous.get("time",-100))>=18
		if force or changed or idle or stalled:
			ids.append(unit.id)
			assigned[unit.id]={"goal":goal,"mode":mode,"time":sim.time}
	if ids.is_empty():return
	var accepted:int=sim.issue(ids,goal,mode)
	stats.orders+=1
	stats.sections_ordered+=accepted
	stats.sections_rejected+=ids.size()-accepted
	var rejected:Array=[]
	for id in ids:
		if sim.get_unit(id).get("command_group",-1)==sim.command_serial:
			stats.accepted_by_unit[id]=int(stats.accepted_by_unit.get(id,0))+1
		else:
			stats.rejected_by_unit[id]=int(stats.rejected_by_unit.get(id,0))+1
			rejected.append(id)
	if actions.size()<2000:actions.append({"seconds":sim.time,"type":"order","mode":mode,"ids":ids,"goal":[goal.x,goal.y],"accepted":accepted,"rejected_ids":rejected})
	if accepted<ids.size() and first_rejection.is_empty():
		first_rejection=OrderDiagnostics.capture(sim,ids,goal,mode,accepted)
		print("HARBOR REJECTION: ",JSON.stringify({"seconds":sim.time,"ids":first_rejection.rejected_ids,"feedback":sim.order_feedback}))

func play(sim)->void:
	var own:Array=sim.living(0)
	var combat:Array=own.filter(func(unit):return effective(sim,unit) and unit.kind!="engineer" and sim.definitions[unit.kind].domain=="land")
	var goal_index:=1 # Old Town is the nearest public sector to the insertion.
	for candidate in [1,0,2]:
		if sim.objectives[candidate].owner!=0:
			goal_index=candidate
			break
		goal_index=2
	var goal:Vector2=sim.objectives[goal_index].pos
	if goal_index!=last_goal:
		last_goal=goal_index
		print("HARBOR OBJECTIVE: ",sim.time," ",sim.objectives[goal_index].name)
	# The two sensible policies share navigation and purchase cadence; only
	# reinforcement mix differs. Neither reads hidden enemy positions.
	if policy!="reckless":
		var mix:Array=MIX[policy]
		var committed:int=combat.size()+sim.FieldOps.queue(sim).size()
		while committed<22 and sim.FieldOps.queue(sim).size()<6:
			var kind:String=mix[purchase_index%mix.size()]
			if sim.credits<float(sim.definitions[kind].cost):break
			if not sim.recruit(kind):
				var reason:String=sim.field_ops.last_purchase_error
				stats.purchase_rejections[reason]=int(stats.purchase_rejections.get(reason,0))+1
				break
			purchase_index+=1
			committed+=1
			stats.purchases[kind]=int(stats.purchases.get(kind,0))+1
			stats.spent+=int(sim.definitions[kind].cost)
			actions.append({"seconds":sim.time,"type":"purchase","kind":kind,"cost":sim.definitions[kind].cost})
	order(sim,combat,goal)
	if stop_on_rejection and not first_rejection.is_empty():return
	# Scouts observe from the approach side; gunships accompany the attack.
	var approach:Vector2=(sim.field_ops.insertion-goal).normalized()
	order(sim,own.filter(func(unit):return unit.kind=="drone"),goal+approach*26,"move")
	if stop_on_rejection and not first_rejection.is_empty():return
	order(sim,own.filter(func(unit):return unit.kind=="helo"),goal+approach*12)
	if stop_on_rejection and not first_rejection.is_empty():return
	# The public map shows the open western sea and inner-harbor channel.
	# Water waypoints are ordinary orders, not path/position mutations.
	var boats:Array=own.filter(func(unit):return unit.kind=="boat")
	for boat in boats:
		var sea_goal:=Vector2(160,295)
		if boat.pos.y<330:sea_goal=Vector2(330,290)
		if boat.pos.x>300:sea_goal=Vector2(650,285)
		order(sim,[boat],sea_goal)
		if stop_on_rejection and not first_rejection.is_empty():return
	if policy=="reckless":
		order(sim,own.filter(func(unit):return unit.kind=="engineer"),goal,"move")
