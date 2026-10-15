extends SceneTree
# Per-soldier targeting: fire at a section resolves against one of its
# soldiers (nearest able one with a clear line of fire), never its anchor. A
# section whose soldiers are all behind a wall cannot be engaged even when its
# anchor point is in the open; an exposed soldier of the same section can be,
# and only he is struck (rifles and a tank's gun alike).
const Sim=preload("res://scripts/simulation.gd")
const Infantry=preload("res://scripts/infantry.gd")
const WALL:=Rect2(8,35,8,6)
# Shooters 5 m north of the wall; the target section 1.5 m south of it.
const SHOOTERS:=[Vector2(10,30),Vector2(12,30),Vector2(14,30)]
const HIDDEN:=[Vector2(9.5,42.5),Vector2(12,42.5),Vector2(14.5,42.5)]
const EXPOSED:=Vector2(20,41)  # beyond the wall's east end, in the open
const TANK:=Vector2(12,26)
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func field():
	var sim=Sim.new(false,0)
	sim.scenario=sim.scenario.duplicate(true)
	sim.scenario.jam_radius=0
	sim.terrain.style="showcase"
	sim.terrain.dynamic_blocks.append(WALL)
	sim.terrain.rubble=Rect2()
	sim.combat_rng.seed=5
	return sim

# The target section: anchor in the open at EXPOSED, soldiers at `spots`.
func section(sim)->Dictionary:
	var u:Dictionary=sim.spawn("rifle",1,EXPOSED)
	u.cooldown=100000.0
	for m in u.members:m.cooldown=100000.0
	sim.stop([u.id])
	return u

func pin(u:Dictionary,anchor:Vector2,spots:Array)->void:
	u.pos=anchor
	for i in u.members.size():u.members[i].pos=spots[i]

func wounded(u:Dictionary,indices:Array)->int:
	var count:=0
	for i in indices:
		if u.members[i].get("wound",Infantry.HEALTHY)!=Infantry.HEALTHY:count+=1
	return count

# Run `seconds` of combat, re-pinning bodies every tick (no one walks round
# the wall). Returns the shot events fired at the target.
func fight(sim,pinned:Array,target:Dictionary,seconds:float)->Array:
	var shots:Array=[]
	for i in int(seconds*30):
		for p in pinned:pin(p[0],p[1],p[2])
		target.seen_by=[true,true]
		sim.tick(1.0/30)
		for e in sim.events:
			if e.type=="shot" and e.get("target_kind","")=="rifle":shots.append(e)
		sim.events.clear()
	return shots

func hidden_section()->void:
	var sim=field()
	var target:=section(sim)
	var squad:Dictionary=sim.spawn("rifle",0,Vector2(12,30))
	var tank:Dictionary=sim.spawn("tank",0,TANK)
	pin(target,EXPOSED,HIDDEN);pin(squad,Vector2(12,30),SHOOTERS);tank.pos=TANK
	sim.update_visibility()
	target.seen_by=[true,true]
	check(sim.terrain.line_clear(SHOOTERS[2],EXPOSED),"fixture: the anchor point is in the open")
	for s in SHOOTERS:
		for h in HIDDEN:check(not sim.terrain.line_clear(s,h),"fixture: wall hides %s from %s" % [h,s])
	check(not sim.can_fire(squad,target),"rifles cannot engage a section whose soldiers are all behind the wall")
	check(not sim.can_fire(tank,target),"tank cannot engage a section whose soldiers are all behind the wall")
	check(not sim.can_fire(target,squad),"symmetric: the hidden section cannot engage the rifles either")
	var shots:=fight(sim,[[target,EXPOSED,HIDDEN],[squad,Vector2(12,30),SHOOTERS]],target,6.0)
	print("  hidden section: shots at it %d, wounded %d/3" % [shots.size(),wounded(target,[0,1,2])])
	check(shots.is_empty(),"no rounds are fired at soldiers nobody can see")
	check(wounded(target,[0,1,2])==0,"no hidden soldier is hit")

func exposed_soldier()->void:
	var sim=field()
	var spots:=[EXPOSED,HIDDEN[1],HIDDEN[2]]
	var target:=section(sim)
	var squad:Dictionary=sim.spawn("rifle",0,Vector2(12,30))
	pin(target,EXPOSED,spots);pin(squad,Vector2(12,30),SHOOTERS)
	sim.update_visibility()
	target.seen_by=[true,true]
	check(sim.can_fire(squad,target),"rifles engage the section through its exposed soldier")
	var shots:=fight(sim,[[target,EXPOSED,spots],[squad,Vector2(12,30),SHOOTERS]],target,12.0)
	var to_exposed:=shots.filter(func(e):return e.hit and (e.to as Vector2).distance_to(EXPOSED)<0.5).size()
	var hits:=shots.filter(func(e):return e.hit).size()
	print("  exposed soldier vs rifles: shots %d hits %d (all at him %d), exposed wounded %d, hidden wounded %d" % [shots.size(),hits,to_exposed,wounded(target,[0]),wounded(target,[1,2])])
	check(not shots.is_empty(),"rifles fire at the exposed soldier")
	check(hits>0 and to_exposed==hits,"every hit lands on the exposed soldier's position")
	check(wounded(target,[0])==1,"the exposed soldier is hit")
	check(wounded(target,[1,2])==0,"his comrades behind the wall are untouched")
	# Once he is down the rest of the section is out of reach again.
	check(not sim.can_fire(squad,target),"exposed soldier down: the section behind the wall is no longer engageable")

func vehicle_fire()->void:
	var sim=field()
	var spots:=[EXPOSED,HIDDEN[0],HIDDEN[1]]
	var target:=section(sim)
	var tank:Dictionary=sim.spawn("tank",0,TANK)
	pin(target,EXPOSED,spots);tank.pos=TANK
	check(sim.terrain.line_clear(TANK,EXPOSED) and not sim.terrain.line_clear(TANK,HIDDEN[0]) and not sim.terrain.line_clear(TANK,HIDDEN[1]),"fixture: tank sees only the exposed soldier")
	target.seen_by=[true,true]
	check(sim.can_fire(tank,target),"tank engages the section through its exposed soldier")
	var shots:=fight(sim,[[target,EXPOSED,spots]],target,8.0)
	var hits:=shots.filter(func(e):return e.hit)
	var at_exposed:=hits.filter(func(e):return (e.to as Vector2).distance_to(EXPOSED)<0.5).size()
	print("  tank vs section: shots %d hits %d (at exposed %d), exposed wounded %d, hidden wounded %d" % [shots.size(),hits.size(),at_exposed,wounded(target,[0]),wounded(target,[1,2])])
	check(not hits.is_empty() and at_exposed==hits.size(),"tank rounds strike the visible soldier, not the anchor or a hidden man")
	check(wounded(target,[0])==1,"the visible soldier is hit by the tank")
	check(wounded(target,[1,2])==0,"soldiers behind the wall take nothing (beyond fragment radius)")

# Without a line to any soldier, a direct resolve_shot (fixtures, legacy
# callers) still resolves against the soldier nearest the shooter.
func legacy_fallback()->void:
	var sim=field()
	var target:=section(sim)
	pin(target,EXPOSED,HIDDEN)
	var shooter:Dictionary=sim.spawn("rifle",0,Vector2(12,30))
	var proxy:Dictionary=shooter.duplicate();proxy.kind="rifle";proxy.pos=Vector2(12,30)
	var hit:=false
	for i in 200:
		if sim.resolve_shot(proxy,target,0.25):hit=true;break
	check(hit and target.members[1].wound!=Infantry.HEALTHY,"direct resolve_shot without a line falls back to the nearest soldier")

func _init()->void:
	print("hidden section:");hidden_section()
	print("exposed soldier:");exposed_soldier()
	print("vehicle fire:");vehicle_fire()
	print("legacy fallback:");legacy_fallback()
	print("SOLDIER TARGETING: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)
