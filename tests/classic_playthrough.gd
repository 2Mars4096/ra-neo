extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const C=preload("res://scripts/classic.gd")
# Scripted player (every 4 s), played for the current damage model: tank guns
# defeat a tank's front only through weak zones and ATGM teams are deadly but
# slow-firing and fragile in the open, so
#  - production mixes one Javelin team per two tanks;
#  - the Javelin teams hold overwatch over the harvester and refinery, the
#    tanks screen north of the ore field, and anything near a visible enemy
#    threatening the economy turns on it;
#  - from 180 s, once MASS tanks/rifles are ready, they attack together with
#    group orders (formation slots, no single-file jams) and keep attacking.
const BUILDS:=["refinery","power","barracks","factory"]
const MIX:=0.5
const MASS:=8
const REACT:=25.0
const GUARD:=22.0
const OVERWATCH:=Vector2(22,42)
const STAGING:=Vector2(58,43)

func _init()->void:
	var sim=Sim.new(true,4)
	var clock:=0.0
	var launched:=false
	for frame in (3500 if "--diagnose" in OS.get_cmdline_user_args() else 9000):
		if frame%500==0:print("PROGRESS ",sim.time," funds ",sim.credits," bases ",C.structures(sim,0,"",false).size(),"/",C.structures(sim,1,"",false).size()," units ",sim.units.size())
		sim.tick(0.1)
		clock-=0.1
		if clock<=0:
			clock=4
			launched=play(sim,launched)
		if sim.result!="":break
	if "--diagnose" in OS.get_cmdline_user_args():
		for u in sim.units:
			if sim.alive(u):print("UNIT ",u.id," team",u.team," ",u.kind," ",u.pos," orders ",u.orders," path ",u.path," cargo ",u.get("cargo",0)," reason ",u.reason," blocked ",u.blocked_time," queue ",u.get("queue",[]))
	var report:={"result":sim.result,"time":sim.time,"credits":sim.credits,"enemy_credits":sim.classic.enemy_credits,"friendly_structures":C.structures(sim,0,"",false).size(),"enemy_structures":C.structures(sim,1,"",false).size(),"kills":sim.kills,"losses":sim.losses}
	FileAccess.open("res://artifacts/classic-mission.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("CLASSIC MISSION: ",JSON.stringify(report))
	quit(0 if sim.result=="VICTORY" else 1)

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
	# The visible enemy nearest the harvester or refinery, if any is close.
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
	# The assault: the visible enemy structure nearest the force, else staging.
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
			# Rifles cannot harm buildings: they keep the screen.
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
