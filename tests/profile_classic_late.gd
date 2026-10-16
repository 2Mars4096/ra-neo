extends SceneTree
# CPU cost of the simulation tick late in a crowded classic match.
# Plays the classic_playthrough scripted player at 10 Hz up to `--warm=S`
# seconds (default 400), then times `--window=N` ticks (default 300) at the
# game's 30 Hz with the same player still acting every 4 s.
# The match is seeded, so `--fingerprint` digests let optimisations prove they
# leave the game state unchanged (one digest after warm-up, one after the window).
const Sim=preload("res://scripts/simulation.gd")
const C=preload("res://scripts/classic.gd")
const BUDGET_MS:=33.0
# Scripted player: a copy of tests/classic_playthrough.gd play().
const BUILDS:=["refinery","power","barracks","factory"]
const MIX:=0.5
const MASS:=8
const REACT:=25.0
const GUARD:=22.0
const OVERWATCH:=Vector2(22,42)
const STAGING:=Vector2(58,43)

func digest(sim)->String:
	var state:Array=[sim.combat_rng.state,sim.time,sim.kills,sim.losses,sim.credits,sim.visible_cells.keys(),sim.explored.keys()]
	for u in sim.units:
		var members:Array=[]
		for m in u.members:members.append([m.pos,m.hp,m.get("cover_phase",""),m.get("posture",""),m.get("target",-1),m.get("cover_goal",Vector2.ZERO),m.get("state","")])
		state.append([u.id,u.pos,u.hp,u.target,u.state,u.path,u.orders,members,u.suppression,u.get("cargo",0.0),u.visible,u.seen_by])
	return var_to_str(state).sha256_text()

func live_units(sim)->int:
	return sim.units.filter(func(u):return sim.alive(u) and not sim.definitions[u.kind].get("structure",false)).size()

func _init()->void:
	var warm:=400.0
	var window:=300
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--warm="):warm=float(arg.get_slice("=",1))
		if arg.begins_with("--window="):window=maxi(1,int(arg.get_slice("=",1)))
	var sim=Sim.new(true,4)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--threshold="):sim.spatial_targeting_threshold=int(arg.get_slice("=",1))
	var clock:=0.0
	var launched:=false
	var started:=Time.get_ticks_usec()
	# `--profile-warm`: phase totals over the whole 10 Hz warm-up (the classic test's own cadence).
	sim.profiling="--profile-warm" in OS.get_cmdline_user_args()
	var segment:=Time.get_ticks_usec()
	var segment_live:=0
	var segment_ticks:=0
	while sim.time<warm-0.05 and sim.result=="":
		segment_live+=live_units(sim);segment_ticks+=1
		sim.tick(0.1)
		if segment_ticks==500:
			print("WARM %.0fs: live=%.1f ms_per_sim_s=%.0f" % [sim.time,float(segment_live)/segment_ticks,(Time.get_ticks_usec()-segment)/1000.0/(segment_ticks*0.1)])
			segment=Time.get_ticks_usec();segment_live=0;segment_ticks=0
		clock-=0.1
		if clock<=0:
			clock=4
			launched=play(sim,launched)
	print("WARM-UP: t=%.1fs wall=%.1fs live=%d result='%s'" % [sim.time,(Time.get_ticks_usec()-started)/1e6,live_units(sim),sim.result])
	print("FINGERPRINT warm ",digest(sim))
	if sim.profiling:
		var keys:Array=sim.profile.keys()
		keys.sort_custom(func(a,b):return sim.profile[a]>sim.profile[b])
		for key in keys:print("WARM-PHASE %-18s total=%8.0fms per_sim_s=%6.1fms" % [key,sim.profile[key],sim.profile[key]/sim.time])
		print("WARM PATHS: calls=%d total=%.0fms" % [sim.terrain.path_calls,sim.terrain.path_usec/1000.0])
		sim.profile.clear()
	sim.profiling=true
	var paths_start:int=sim.terrain.path_calls
	var path_usec_start:int=sim.terrain.path_usec
	var costs:Array=[]
	var lives:=0
	for i in window:
		if sim.result!="":break
		lives+=live_units(sim)
		var before:Dictionary=sim.profile.duplicate()
		var paths:int=sim.terrain.path_calls
		var path_usec:int=sim.terrain.path_usec
		var grids:int=sim.terrain.navigation.size()
		var t:=Time.get_ticks_usec()
		sim.tick(1.0/30)
		var cost:=(Time.get_ticks_usec()-t)/1000.0
		costs.append(cost)
		if cost>BUDGET_MS:
			var parts:Array=[]
			for key in sim.profile:
				var spent:float=sim.profile[key]-before.get(key,0.0)
				if spent>=1.0:parts.append("%s=%.0f" % [key,spent])
			print("SPIKE tick=%d %.0fms paths=%d/%.0fms grids %d->%d %s" % [i,cost,sim.terrain.path_calls-paths,(sim.terrain.path_usec-path_usec)/1000.0,grids,sim.terrain.navigation.size(),parts])
		clock-=1.0/30
		if clock<=0:
			clock=4
			launched=play(sim,launched)
	print("FINGERPRINT window ",digest(sim))
	var sorted:=costs.duplicate();sorted.sort()
	var total:=0.0
	for c in sorted:total+=c
	var live:=float(lives)/maxf(1,costs.size())
	print("CLASSIC LATE PROFILE: t=%.1fs live=%.1f ticks=%d mean=%.2fms p50=%.2fms p95=%.2fms max=%.2fms over%.0fms=%d ms_per_sim_s=%.0f per_unit=%.3fms" % [sim.time,live,sorted.size(),total/sorted.size(),sorted[sorted.size()/2],sorted[int(sorted.size()*0.95)],sorted.back(),BUDGET_MS,sorted.filter(func(c):return c>BUDGET_MS).size(),total/sorted.size()*30,total/sorted.size()/maxf(1,live)])
	print("PATHS: calls=%d total=%.0fms" % [sim.terrain.path_calls-paths_start,(sim.terrain.path_usec-path_usec_start)/1000.0])
	var keys:Array=sim.profile.keys()
	keys.sort_custom(func(a,b):return sim.profile[a]>sim.profile[b])
	for key in keys:print("PHASE %-18s per_tick=%6.3fms" % [key,sim.profile[key]/costs.size()])
	var kinds:Dictionary={}
	for u in sim.units:
		if sim.alive(u):kinds[u.kind]=kinds.get(u.kind,0)+1
	print("LIVE KINDS ",kinds," units listed (live+dead)=",sim.units.size())
	if "--bench" in OS.get_cmdline_user_args():bench(sim)
	quit()

# `--bench`: repeat side-effect-free helpers on the late state; the minimum of
# several rounds filters other processes' noise.
func timed(label:String,rounds:int,body:Callable)->void:
	var best:=INF
	for r in 5:
		var t:=Time.get_ticks_usec()
		for i in rounds:body.call()
		best=minf(best,(Time.get_ticks_usec()-t)/1000.0/rounds)
	print("BENCH %-26s %.4fms" % [label,best])

func bench(sim)->void:
	sim.profiling=false
	sim.ticking=true
	var armed:Array=sim.units.filter(func(u):return sim.alive(u) and not sim.definitions[u.kind].get("structure",false))
	timed("rebuild_spatial",200,func():sim.rebuild_spatial())
	timed("rebuild_actor_spatial",200,func():sim.rebuild_actor_spatial())
	timed("target_candidates(all)",50,func():
		for u in armed:sim.target_candidates(u))
	timed("can_fire(all pairs)",20,func():
		for u in armed:
			for other in armed:
				if other.team!=u.team:sim.can_fire(u,other))
	var pairs:Array=[]
	for u in armed:
		for other in armed:
			if other.team!=u.team:pairs.append([u,other])
	print("BENCH pairs=",pairs.size()," fireable=",pairs.filter(func(p):return sim.can_fire(p[0],p[1])).size()," seen=",pairs.filter(func(p):return sim.contact_known(p[0],p[1])).size())
	timed("weapon_ready(all)",200,func():
		for u in armed:sim.VehicleDamage.weapon_ready(sim,u))
	timed("contact_known(pairs)",50,func():
		for p in pairs:sim.contact_known(p[0],p[1]))
	timed("target_priority(pairs)",50,func():
		for p in pairs:sim.target_priority(p[0],p[1]))
	timed("auto_target_ok(pairs)",50,func():
		for p in pairs:sim.auto_target_ok(p[0],p[1]))
	timed("can_fire(pairs)",50,func():
		for p in pairs:sim.can_fire(p[0],p[1]))
	timed("movement_neighbors(all)",200,func():
		for u in armed:sim.movement_neighbors(u))
	timed("movement_clear(all,step)",50,func():
		for u in armed:sim.movement_clear(u,u.pos+u.facing*0.2,sim.movement_neighbors(u)))
	timed("visibility(cached)",20,func():sim.update_visibility())
	timed("classic sync_obstacles",200,func():C.sync_obstacles(sim))
	timed("classic power x2",200,func():
		C.power(sim,0);C.power(sim,1))
	timed("living x2",200,func():
		sim.living(0);sim.living(1))
	timed("line_clear(all pairs)",20,func():
		for u in armed:
			for other in armed:sim.terrain.line_clear(u.pos,other.pos))
	timed("traversable(all)",200,func():
		for u in armed:sim.terrain.traversable(u.pos,"land",2.0))
	sim.ticking=false

func play(sim,launched:bool)->bool:
	for kind in BUILDS:
		if C.structures(sim,0,kind,false).is_empty():
			var site:Vector2=C.find_site(sim,kind,0)
			if site.x>=0:C.build(sim,kind,0,site)
			break
	var established:bool=not C.structures(sim,0,"factory").is_empty()
	if C.committed_count(sim,"harvester",0)<1:C.enqueue(sim,"harvester")
	if C.committed_count(sim,"drone",0)==0:C.enqueue(sim,"drone")
	if established and C.committed_count(sim,"atgm",0)<C.committed_count(sim,"tank",0)*MIX:C.enqueue(sim,"atgm")
	else:C.enqueue(sim,"tank")
	for scout in sim.living(0).filter(func(u):return u.kind=="drone"):
		if scout.orders.is_empty():sim.issue([scout.id],Vector2(68,9))
	if sim.time<=0:return launched
	var mobile:Array=sim.living(0).filter(func(u):return u.kind in ["tank","rifle"] and not u.get("combat_ineffective",false) and not u.get("mobility_kill",false))
	var teams:Array=sim.living(0).filter(func(u):return u.kind=="atgm" and not u.get("combat_ineffective",false))
	var threat:Dictionary={}
	var best:=GUARD
	for guarded in sim.living(0).filter(func(u):return u.kind in ["harvester","refinery"]):
		for enemy in sim.living(1):
			if not enemy.visible or enemy.get("combat_ineffective",false) or sim.definitions[enemy.kind].get("structure",false) or sim.definitions[enemy.kind].domain!="land":continue
			var gap:float=guarded.pos.distance_to(enemy.pos)
			if gap<best:best=gap;threat=enemy
	for team in teams:
		var post:Vector2=OVERWATCH+Vector2(4*(int(team.id)%3)-4,0)
		var goal:Vector2=threat.pos if not threat.is_empty() and threat.pos.distance_to(post)<REACT else post
		if not team.orders.is_empty() and team.get("policy_goal",Vector2.INF).distance_to(goal)<3:continue
		if team.orders.is_empty() and team.pos.distance_to(goal)<6:continue
		team.policy_goal=goal
		sim.issue([team.id],goal,"attack_move")
	if not launched and sim.time>=180 and mobile.size()>=MASS:launched=true
	if launched and mobile.size()<MASS/2:launched=false
	var group_goal:=STAGING
	var group_target:=-1
	var targets:Array=C.structures(sim,1,"",false).filter(func(u):return u.visible)
	if launched and not targets.is_empty():
		var centre:=Vector2.ZERO
		for u in mobile:centre+=u.pos
		centre/=maxf(1,mobile.size())
		var nearest:Dictionary=targets[0]
		for t in targets:if t.pos.distance_to(centre)<nearest.pos.distance_to(centre):nearest=t
		group_goal=nearest.pos;group_target=nearest.id
	var group:Array=[]
	for u in mobile:
		var goal:Vector2=Vector2(16+6*(int(u.id)%3),29)
		var mode:="attack_move"
		var target:=-1
		var assault:=false
		if not threat.is_empty() and threat.pos.distance_to(u.pos)<REACT:goal=threat.pos
		elif launched and (group_target<0 or sim.effective_unit(u,sim.get_unit(group_target).kind)):
			goal=group_goal
			assault=true
			if group_target>=0:mode="attack";target=group_target
		var key:=str(mode,goal.snapped(Vector2(4,4)),target)
		if u.get("policy_key","")==key and not (u.orders.is_empty() and u.pos.distance_to(goal)>12):continue
		u.policy_key=key
		if assault:group.append(u.id)
		else:sim.issue([u.id],goal,mode,false,target)
	if not group.is_empty():sim.issue(group,group_goal,"attack" if group_target>=0 else "attack_move",false,group_target)
	return launched
