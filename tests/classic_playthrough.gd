extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const C=preload("res://scripts/classic.gd")
# Scripted player (every 4 s), combined arms against an enemy whose force is
# mostly Javelin teams (fire-and-forget, top attack, three missiles a team,
# kept for vehicles and works):
#  - economy first: two harvesters once the refinery stands, and the first two
#    purchases are Javelin teams from the barracks (ready before the factory)
#    to stop the enemy's first tank before it reaches the ore field;
#  - then tanks, with one Javelin team per two tanks;
#  - a defensive arc on the base's east side, where the enemy comes from: a
#    rifle screen forward, tanks behind it, Javelin teams in overwatch of the
#    ore field and refinery turning on enemy armour within REACT; every
#    structure and the harvester is guarded;
#  - infantry hunts Javelin teams seen in the last MEMORY s near its post or
#    the assault objective; in the assault a tank inside a known Javelin team's
#    reach that the rifles are fighting backs out of it until they clear it;
#  - Javelin teams walk back to the HQ or refinery for missiles when empty;
#  - from 180 s, once MASS tanks/rifles are ready, they attack together with
#    group orders (formation slots, no single-file jams) and keep attacking.
const BUILDS:=["refinery","power","barracks","factory"]
const MIX:=0.5
const MASS:=8
const REACT:=25.0
const GUARD:=22.0
const OVERWATCH:=Vector2(20,45)
const TANK_ARC:=[Vector2(22,40),Vector2(24,48),Vector2(22,56)]
const RIFLE_ARC:=[Vector2(30,38),Vector2(32,48),Vector2(30,57)]
const STAGING:=Vector2(58,43)
const ATGM_STANDOFF:=22.0 # Javelin range 20 m plus a margin
const MEMORY:=30.0
const HUNT:=30.0
# Smoke test, not a balance gate: the scripted player is a test bot, so its
# wins and losses are reported but not judged. Pass when every seed plays to an
# end (victory, defeat or the 900 s limit) with fighting on both sides; a crash,
# script error or a frozen match fails. Seeds: 47291 plus 1..SAMPLE-1.
# Single seed for debugging: -- --seed=N (add --diagnose for unit dumps).
const SAMPLE:=4
var javelins:Dictionary={} # enemy Javelin team id -> {pos, time} last seen

func _init()->void:
	var args:=OS.get_cmdline_user_args()
	var seeds:Array=[47291]
	for i in range(1,SAMPLE):seeds.append(i)
	for arg in args:
		if arg.begins_with("--seed="):seeds=[int(arg.trim_prefix("--seed="))]
	var started:=Time.get_ticks_msec()
	var reports:Array=[]
	var tally:={"VICTORY":0,"DEFEAT":0,"":0}
	for combat_seed in seeds:
		var report:=mission(combat_seed,"--diagnose" in args)
		reports.append(report)
		tally[report.result]=int(tally.get(report.result,0))+1
		print("CLASSIC MISSION: ",JSON.stringify(report))
	var wall:=(Time.get_ticks_msec()-started)/1000.0
	var frozen:=reports.filter(func(r):return int(r.kills)+int(r.losses)==0).size()
	var passed:bool=reports.size()==seeds.size() and frozen==0
	var summary:={"seeds":seeds.size(),"wins":tally.VICTORY,"defeats":tally.DEFEAT,"unresolved":tally[""],"frozen":frozen,"wall_s":snappedf(wall,0.1)}
	var out:=FileAccess.open("res://artifacts/classic-mission.json",FileAccess.WRITE)
	if out!=null:out.store_string(JSON.stringify({"summary":summary,"missions":reports},"  "))
	print("CLASSIC SEEDS: ",("PASS" if passed else "FAIL")," ",seeds.size()," played (",tally.VICTORY," wins, ",tally.DEFEAT," defeats, ",tally[""]," unresolved, ",frozen," frozen), wall ",snappedf(wall,0.1)," s")
	quit(0 if passed else 1)

# One scripted classic game with the given combat seed (fresh simulation and
# player memory, so a seed plays the same alone or in the sample).
func mission(combat_seed:int,diagnose:bool)->Dictionary:
	var started:=Time.get_ticks_msec()
	javelins.clear()
	var sim=Sim.new(true,4)
	sim.combat_rng.seed=combat_seed
	var clock:=0.0
	var launched:=false
	for frame in (3500 if diagnose else 9000):
		if frame%500==0:print("PROGRESS seed ",combat_seed," ",sim.time," funds ",sim.credits," bases ",C.structures(sim,0,"",false).size(),"/",C.structures(sim,1,"",false).size()," units ",sim.units.size())
		sim.tick(0.1)
		clock-=0.1
		if clock<=0:
			clock=4
			launched=play(sim,launched)
		if sim.result!="":break
	if diagnose:
		for u in sim.units:
			if sim.alive(u):print("UNIT ",u.id," team",u.team," ",u.kind," ",u.pos," orders ",u.orders," path ",u.path," cargo ",u.get("cargo",0)," reason ",u.reason," blocked ",u.blocked_time," queue ",u.get("queue",[]))
	return {"seed":combat_seed,"result":sim.result,"time":sim.time,"credits":sim.credits,"enemy_credits":sim.classic.enemy_credits,"friendly_structures":C.structures(sim,0,"",false).size(),"enemy_structures":C.structures(sim,1,"",false).size(),"kills":sim.kills,"losses":sim.losses,"wall_s":snappedf((Time.get_ticks_msec()-started)/1000.0,0.1)}

# Units in the field or queued, not counting combat-ineffective sections
# (all soldiers down: they no longer fight).
func committed(sim,kind:String)->int:
	var count:int=C.committed_count(sim,kind,0)
	for u in sim.living(0):
		if u.kind==kind and u.get("combat_ineffective",false):count-=1
	return count

# The remembered Javelin team nearest `pos` within HUNT of the unit's post or,
# in the assault, of the objective; {} when none.
func nearest_javelin(pos:Vector2,post:Vector2,front:Vector2)->Dictionary:
	var best:Dictionary={}
	for id in javelins:
		var at:Vector2=javelins[id].pos
		if at.distance_to(post)>HUNT and (front.x==INF or at.distance_to(front)>HUNT):continue
		if best.is_empty() or at.distance_to(pos)<Vector2(best.pos).distance_to(pos):best={"id":id,"pos":at}
	return best

func play(sim,launched:bool)->bool:
	for kind in BUILDS:
		if C.structures(sim,0,kind,false).is_empty():
			var site:Vector2=C.find_site(sim,kind,0)
			if site.x>=0:C.build(sim,kind,0,site)
			break
	var established:bool=not C.structures(sim,0,"factory").is_empty()
	# Two harvesters once the refinery stands: income is the army.
	if C.committed_count(sim,"harvester",0)<(2 if not C.structures(sim,0,"refinery").is_empty() else 1):C.enqueue(sim,"harvester")
	if C.committed_count(sim,"drone",0)==0:C.enqueue(sim,"drone")
	# The first two purchases are Javelin teams from the barracks (ready before
	# the factory) to cover the ore field against the enemy's first tank.
	var barracks:bool=not C.structures(sim,0,"barracks").is_empty()
	if barracks and committed(sim,"atgm")<2:C.enqueue(sim,"atgm")
	elif established and committed(sim,"atgm")<committed(sim,"tank")*MIX:C.enqueue(sim,"atgm")
	else:C.enqueue(sim,"tank")
	for scout in sim.living(0).filter(func(u):return u.kind=="drone"):
		if scout.orders.is_empty():sim.issue([scout.id],Vector2(68,9))
	if sim.time<=0:return launched
	# Enemy Javelin teams seen in the last MEMORY s.
	for enemy in sim.living(1):
		if enemy.kind=="atgm" and enemy.visible and not enemy.get("combat_ineffective",false):javelins[enemy.id]={"pos":enemy.pos,"time":sim.time}
	for id in javelins.keys():
		var known:Dictionary=sim.get_unit(id)
		if not sim.alive(known) or known.get("combat_ineffective",false) or sim.time-float(javelins[id].time)>MEMORY:javelins.erase(id)
	var mobile:Array=sim.living(0).filter(func(u):return u.kind in ["tank","rifle"] and not u.get("combat_ineffective",false) and not u.get("mobility_kill",false))
	var teams:Array=sim.living(0).filter(func(u):return u.kind=="atgm" and not u.get("combat_ineffective",false))
	# The visible enemy nearest a structure or the harvester, if any is close.
	var threat:Dictionary={}
	var best:=GUARD
	for guarded in sim.living(0).filter(func(u):return u.kind=="harvester" or sim.definitions[u.kind].get("structure",false)):
		for enemy in sim.living(1):
			if not enemy.visible or enemy.get("combat_ineffective",false) or sim.definitions[enemy.kind].get("structure",false) or sim.definitions[enemy.kind].domain!="land":continue
			var gap:float=guarded.pos.distance_to(enemy.pos)
			if gap<best:best=gap;threat=enemy
	for team in teams:
		var post:Vector2=OVERWATCH+Vector2(0,5*(int(team.id)%3)-5)
		var goal:Vector2=post
		var armour:Dictionary={}
		for enemy in sim.living(1):
			if not enemy.visible or not enemy.members.is_empty() or sim.definitions[enemy.kind].get("structure",false) or sim.definitions[enemy.kind].domain!="land":continue
			if enemy.pos.distance_to(post)<REACT and (armour.is_empty() or enemy.pos.distance_to(team.pos)<armour.pos.distance_to(team.pos)):armour=enemy
		if not armour.is_empty():goal=armour.pos
		if sim.missiles_left(team)==0:
			# Out of missiles: walk back to the HQ or refinery for more.
			var source:Dictionary=sim.supply_source(team)
			var away:Vector2=(team.pos-source.pos).normalized() if team.pos.distance_to(source.pos)>0.1 else Vector2.UP
			goal=source.pos+away*(float(source.reach)-1.5)
			if team.pos.distance_to(goal)<2.0:continue
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
		# Defensive arc on the base's east side (the enemy comes from the
		# north-east and east): tanks hold behind the rifle screen.
		var goal:Vector2=(TANK_ARC if u.kind=="tank" else RIFLE_ARC)[int(u.id)%3]
		var mode:="attack_move"
		var target:=-1
		var assault:=false
		var hunt:=nearest_javelin(u.pos,goal,group_goal if launched else Vector2.INF)
		if not threat.is_empty() and threat.pos.distance_to(u.pos)<REACT:goal=threat.pos
		elif u.kind=="rifle" and not hunt.is_empty():
			# Infantry clears known Javelin teams near the base or ahead of the assault.
			goal=hunt.pos
			if sim.get_unit(int(hunt.id)).visible:mode="attack";target=int(hunt.id)
		elif u.kind=="tank" and launched and not hunt.is_empty() and Vector2(hunt.pos).distance_to(u.pos)<ATGM_STANDOFF and mobile.any(func(r):return r.kind=="rifle" and r.pos.distance_to(hunt.pos)<12.0):
			# A known Javelin team within reach that the rifles are fighting:
			# the tank backs out of its reach until they clear it.
			goal=Vector2(hunt.pos)+(u.pos-Vector2(hunt.pos)).normalized()*ATGM_STANDOFF
			mode="move"
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
