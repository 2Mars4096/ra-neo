extends SceneTree
# A section whose survivors are all down (combat-ineffective: every living
# soldier SEVERE) is no mobile unit: it drops queued orders when it goes down,
# refuses move/attack orders (with player feedback), its anchor stays with its
# crawling men, and neither the tactical director nor the enemy AI orders it.
# It stays alive and selectable.
const Sim=preload("res://scripts/simulation.gd")
const Infantry=preload("res://scripts/infantry.gd")
const DT:=0.1
var failures:=0
var checks:=0

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: ",label)

func harbor_index()->int:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		if configs[i].id=="black_sea_harbor":return i
	return -1

# Combat outcome on every soldier: the first killed, the rest down (no bleed-out
# during the test so the section lives).
func down_section(sim,u:Dictionary)->void:
	for member in u.members:
		Infantry.wound(u,member,Infantry.KIA if member.index==0 else Infantry.SEVERE,sim.time,sim.combat_rng)
		member.bleed_at=INF
	Infantry.publish(u)

func living_centroid(u:Dictionary)->Vector2:
	var sum:=Vector2.ZERO
	var count:=0
	for member in u.members:
		if member.wound!=Infantry.KIA:sum+=member.pos;count+=1
	return sum/count

func _init()->void:
	call_deferred("run")

func run()->void:
	field_checks()
	enemy_ai_checks()
	await battle_checks()
	print("DOWNED SECTION: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)

func field_checks()->void:
	var sim=Sim.new(false,0)
	sim.scenario=sim.scenario.duplicate(true)
	sim.scenario.autonomy=true
	var section:Dictionary=sim.spawn("rifle",0,Vector2(18,55))
	var enemy:Dictionary=sim.spawn("rifle",1,Vector2(18,40))
	enemy.cooldown=1e9
	for member in enemy.members:member.cooldown=1e9
	sim.issue([section.id],Vector2(18,20),"attack_move")
	sim.issue([section.id],Vector2(30,20),"move",true)
	for frame in 5:sim.tick(DT);sim.events.clear()
	check(section.orders.size()==2,"fixture: section has a current and a queued order (%d)" % section.orders.size())
	# Hit while spread out: the wounded lie apart and crawl together.
	section.members[1].pos=section.pos+Vector2(-5,0)
	section.members[2].pos=section.pos+Vector2(5,0)
	down_section(sim,section)
	check(section.combat_ineffective and sim.alive(section),"all survivors down: combat-ineffective but alive")
	sim.tick(DT);sim.events.clear()
	check(section.orders.is_empty() and section.path.is_empty() and section.maneuver.is_empty() and section.blocked_time==0.0,"going down drops current and queued orders, route and maneuver")
	check(section.reason==sim.DOWNED_NOTE,"reason explains the section is down: %s" % section.reason)
	check(not sim.route_queue.has(section.id) or not section.has("route_pending"),"no route stays pending")
	check(sim.issue([section.id],Vector2(18,20),"move")==0 and sim.order_feedback==sim.DOWNED_NOTE,"move order refused with feedback: %s" % sim.order_feedback)
	sim.update_visibility()
	check(sim.issue([section.id],enemy.pos,"attack",false,enemy.id)==0 and section.orders.is_empty(),"attack order refused")
	check(sim.retreat([section.id])==0,"retreat order refused")
	var start:Vector2=section.pos
	var spread_before:float=section.members[1].pos.distance_to(section.members[2].pos)
	var worst_gap:=0.0
	var worst_step:=0.0
	var planned:=false
	var previous:Vector2=section.pos
	for frame in 150:
		sim.tick(DT);sim.events.clear()
		worst_gap=maxf(worst_gap,section.pos.distance_to(living_centroid(section)))
		worst_step=maxf(worst_step,section.pos.distance_to(previous))
		previous=section.pos
		planned=planned or not section.maneuver.is_empty() or not section.orders.is_empty()
	print("DOWNED EVIDENCE: anchor moved %.2f in 15 s, max step %.3f, max gap to living centroid %.4f" % [start.distance_to(section.pos),worst_step,worst_gap])
	var spread_after:float=section.members[1].pos.distance_to(section.members[2].pos)
	print("DOWNED EVIDENCE: wounded %.2f apart -> %.2f (crawling to the section)" % [spread_before,spread_after])
	check(spread_after<spread_before-2.0,"the wounded crawl together round the anchor")
	# The anchor follows before the men move each tick: at most one crawl step behind.
	check(worst_gap<=Infantry.CRAWL_SPEED*DT+0.001,"anchor stays on the centroid of its living soldiers")
	check(worst_step<=Infantry.CRAWL_SPEED*DT+0.001,"anchor never runs ahead of crawling men (max step %.3f)" % worst_step)
	check(not planned,"tactical director never orders a downed section (enemy in contact)")
	check(sim.alive(section) and section.combat_ineffective,"section remains (still selectable) while its wounded live")

# Enemy AI (non-autonomous update_tactics) does not order its downed sections.
func enemy_ai_checks()->void:
	var sim=Sim.new(false,0)
	var downed:Dictionary=sim.spawn("rifle",1,Vector2(18,40))
	var player:Dictionary=sim.spawn("rifle",0,Vector2(18,55))
	player.cooldown=1e9
	for member in player.members:member.cooldown=1e9
	down_section(sim,downed)
	var ordered:=false
	for frame in 70:
		sim.tick(DT);sim.events.clear()
		ordered=ordered or not downed.orders.is_empty()
	check(not sim.scenario.get("autonomy",false) and sim.field_ops.is_empty(),"fixture: classic enemy AI active")
	check(not ordered,"enemy AI does not order its downed section")

func battle_checks()->void:
	Sim.scenario_selection=harbor_index()
	root.size=Vector2i(1440,900)
	var battle=load("res://scenes/main.tscn").instantiate()
	root.add_child(battle)
	current_scene=battle
	await process_frame
	await process_frame
	var sim=battle.sim
	battle.show_help=false
	var anchor:Vector2=sim.living(0).filter(func(u):return sim.definitions[u.kind].domain=="land")[0].pos
	var downed:Dictionary=sim.spawn("rifle",0,anchor+Vector2(6,0))
	var able:Dictionary=sim.spawn("rifle",0,anchor+Vector2(-6,0))
	down_section(sim,downed)
	battle.camera_focus=Vector3(anchor.x,0,anchor.y)
	battle.update_camera()
	battle.sync_units(0.016)
	var click:Vector2=battle.screen_pos(anchor+Vector2(0,-10))
	battle.selected=[downed.id]
	battle.give_order(click,false,false)
	check(downed.orders.is_empty() and str(battle.toast)==sim.DOWNED_NOTE,"ordering a downed section alone: refused with toast (%s)" % battle.toast)
	check(battle.selected==[downed.id],"downed section stays selected")
	battle.attack_mode=true
	battle.give_order(click,true,false)
	check(downed.orders.is_empty() and not battle.attack_mode,"attack-move refused too")
	battle.selected=[downed.id,able.id]
	battle.give_order(click,false,false)
	check(downed.orders.is_empty() and not able.orders.is_empty(),"mixed selection: the able section moves, the downed one stays")
	check(str(battle.toast).contains(sim.DOWNED_NOTE) and str(battle.toast).contains("1 / 2 moving"),"mixed selection toast: %s" % battle.toast)
	battle.selected=[downed.id]
	battle.pointer=click
	battle.refresh_cursor_hint()
	check(battle.cursor_hint=="","no action hint for a downed section: '%s'" % battle.cursor_hint)
