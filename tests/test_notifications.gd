extends SceneTree
# Player notifications (scripts/notice_feed.gd): levels, repeat merging (×N),
# the on-screen cap, display times, chimes only for fresh alerts, and the battle
# routing of sim warnings and order acknowledgements.
# `-- --count=harbor` / `assault` (harbor with two enemy waves on a player
# position) / `classic` plays 300 s through the battle with a scripted player
# and prints the message counts before (every message a toast, every warning a
# chime) and after (banners, cursor tags, chimes).
const Sim=preload("res://scripts/simulation.gd")
const Notice=preload("res://scripts/notice_feed.gd")
const DT:=1.0/30.0
var failures:=0
var checks:=0
var battle

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: ",label)

func scenario_index(id:String)->int:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		if configs[i].id==id:return i
	return -1

func _init()->void:
	var count:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--count="):count=arg.get_slice("=",1)
	Sim.scenario_selection=scenario_index("classic" if count=="classic" else "black_sea_harbor")
	call_deferred("run",count)

func run(count:String)->void:
	if count=="":feed_checks()
	root.size=Vector2i(1440,900)
	battle=load("res://scenes/main.tscn").instantiate()
	root.add_child(battle)
	current_scene=battle
	await process_frame
	await process_frame
	battle.show_help=false
	battle.paused=true # this script ticks the sim itself
	if count!="":
		count_play(count)
	else:
		battle_checks()
		# A drawn frame with banners and a pointer tag up (draw_notices, draw_cursor_notice).
		battle.notify("Incoming mortar fire",Notice.ALERT)
		battle.pointer=Vector2(700,450)
		battle.hud.queue_redraw()
		await process_frame
		await process_frame
		print("NOTIFICATIONS: %d checks, %d failures" % [checks,failures])
	battle.queue_free()
	await process_frame
	quit(1 if failures>0 else 0)

func run_feed(feed,seconds:float)->void:
	var t:=0.0
	while t<seconds-0.0001:
		feed.advance(0.1)
		t+=0.1

# --- 1. Feed rules ------------------------------------------------------------------
func feed_checks()->void:
	var feed=Notice.new()
	# Repeats merge into one banner with a count; only the first chimes.
	var chimes:=0
	for i in 3:
		if feed.push("Incoming mortar fire",Notice.ALERT):chimes+=1
		run_feed(feed,1.0)
	check(feed.banners.size()==1 and int(feed.banners[0].count)==3,"three repeats merge into one banner")
	check(Notice.line(feed.banners[0])=="Incoming mortar fire ×3","merged banner reads 'x3': %s" % Notice.line(feed.banners[0]))
	check(chimes==1,"a merged repeat does not chime again (%d chimes)" % chimes)
	# Numbers do not split a repeat; the newest text is shown.
	feed.push("Order failed • 2 / 4",Notice.INFO)
	feed.push("Order failed • 3 / 4",Notice.INFO)
	check(feed.banners.size()==2 and feed.banners[1].text=="Order failed • 3 / 4" and int(feed.banners[1].count)==2,"repeats differing only in numbers merge, newest text kept")
	# Display time by level.
	feed.clear()
	feed.push("low",Notice.LOW);feed.push("info",Notice.INFO);feed.push("alert",Notice.ALERT)
	run_feed(feed,2.1)
	check(feed.banners.map(func(b):return b.text)==["info","alert"],"low banner gone after 2 s")
	run_feed(feed,1.5)
	check(feed.banners.map(func(b):return b.text)==["alert"],"info banner gone after 3.5 s")
	run_feed(feed,1.5)
	check(feed.banners.is_empty(),"alert banner gone after 5 s")
	# Cap: at most MAX_BANNERS; low never pushes out info or alerts, alerts push out low first.
	feed.clear()
	for i in 3:feed.push("info %s" % "abc"[i],Notice.INFO)
	feed.push("low x",Notice.LOW)
	check(feed.banners.size()==Notice.MAX_BANNERS and not feed.banners.any(func(b):return b.text=="low x"),"low notice refused when the stack is full of info")
	feed.clear()
	feed.push("low a",Notice.LOW);feed.push("info b",Notice.INFO);feed.push("low c",Notice.LOW)
	feed.push("alert d",Notice.ALERT)
	check(feed.banners.map(func(b):return b.text)==["info b","low c","alert d"],"an alert pushes out the oldest low banner: %s" % [feed.banners.map(func(b):return b.text)])
	# Cursor tags and drops never take a banner slot.
	feed.clear()
	feed.push("Order confirmed • 4 / 4 sections",Notice.CURSOR)
	feed.push("Wire crushed by armour",Notice.DROP)
	check(feed.banners.is_empty() and feed.cursor_text=="Order confirmed • 4 / 4 sections" and feed.cursor_left>0,"order acknowledgement is a cursor tag")
	check(feed.latest=="Order confirmed • 4 / 4 sections","a dropped notice is not the latest text")
	run_feed(feed,1.6)
	check(feed.cursor_left<=0,"cursor tag fades after 1.5 s")
	# An alert repeated just after its banner expired still does not chime twice.
	feed.clear()
	var chimed:bool=feed.push("short alert",Notice.ALERT)
	feed.banners.clear()
	run_feed(feed,1.0)
	check(chimed and not feed.push("short alert",Notice.ALERT),"same alert within %.0f s chimes once" % Notice.MERGE_SECONDS)
	# Sim event levels: default alert; vehicle effects by table; first loss per kind alerts.
	check(feed.event_level({"type":"warning","text":"x"})==Notice.ALERT,"a warning without a level is an alert")
	check(feed.event_level({"notice":"vehicle","effect":"crew","kind":"tank"})==Notice.DROP,"crew casualty dropped (panel shows CREW n/m)")
	check(feed.event_level({"notice":"vehicle","effect":"mobility","kind":"tank"})==Notice.INFO,"immobilised is an info banner")
	check(feed.event_level({"notice":"vehicle","effect":"catastrophic","kind":"tank"})==Notice.ALERT,"first tank lost alerts")
	check(feed.event_level({"notice":"vehicle","effect":"catastrophic","kind":"tank"})==Notice.INFO,"second tank lost is info")
	check(feed.event_level({"notice":"vehicle","effect":"sunk","kind":"boat"})==Notice.ALERT,"first corvette lost alerts")

# --- 2. Battle routing --------------------------------------------------------------
func battle_checks()->void:
	var sim=battle.sim
	var audio=battle.audio
	battle.notices.clear()
	var ui_before:int=audio.stats().counters.ui if audio!=null else 0
	sim.events.append({"type":"warning","text":"Wire crushed by armour","notice":"drop"})
	sim.events.append({"type":"warning","text":"Wreck cleared by engineers","notice":"low"})
	battle.consume_events()
	check(battle.notices.banners.size()==1 and battle.notices.banners[0].level==Notice.LOW,"dropped warning not shown, low shown dim")
	if audio!=null:check(int(audio.stats().counters.ui)==ui_before,"low and dropped warnings do not chime")
	for i in 3:sim.events.append({"type":"warning","text":"Incoming mortar fire","notice":"alert"})
	battle.consume_events()
	var mortar:Array=battle.notices.banners.filter(func(b):return b.text=="Incoming mortar fire")
	check(mortar.size()==1 and int(mortar[0].count)==3,"three mortar warnings in a tick: one banner ×3")
	if audio!=null:check(int(audio.stats().counters.ui)==ui_before+1,"one chime for the merged alert (%d)" % (int(audio.stats().counters.ui)-ui_before))
	# Order acknowledgements: a pointer tag, not a banner; battle.toast keeps the text.
	battle.notices.clear()
	var ids:Array=battle.all_sections().filter(func(id):return sim.definitions[sim.get_unit(id).kind].domain=="land" and not sim.get_unit(id).get("structure",false))
	battle.selected=ids.slice(0,1)
	var unit:Dictionary=sim.get_unit(battle.selected[0])
	var target:Vector2=unit.pos+Vector2(6,0)
	battle.camera_focus=Vector3(target.x,0,target.y)
	battle.update_camera()
	battle.give_order(battle.screen_pos(target),false,false)
	check(battle.notices.banners.is_empty() and battle.notices.cursor_left>0 and str(battle.toast).contains("Order confirmed"),"order confirmation is a cursor tag: '%s'" % battle.toast)
	# A failed order is a banner.
	battle.selected=[]
	battle.give_order(battle.screen_pos(target),false,false)
	check(battle.notices.banners.is_empty() and battle.toast=="Select a section first","empty-selection click is a cursor tag only")
	battle.notices.clear()
	sim.events.append({"type":"order_report","text":"Order confirmed • 17 / 40 sections (23 no room)"})
	sim.events.append({"type":"warning","text":"Section could not reach the Tank","notice":"info"})
	battle.consume_events()
	check(battle.notices.banners.size()==2 and battle.notices.banners.all(func(b):return b.level==Notice.INFO),"'no room' report and 'could not reach' are info banners")
	# The HUD draws the stack (smoke: no script error on a frame with banners and a tag).
	battle.notify("Order confirmed • 1 / 1 sections",Notice.CURSOR)
	battle.hud.queue_redraw()

# --- 3. Counts over a scripted 300 s game --------------------------------------------
var raw_by_key:={}
func count_play(mode:String)->void:
	var sim=battle.sim
	battle.notices=Notice.new()
	battle.notices.record=[]
	battle.effects.muted=true
	if mode=="assault":
		# profile_harbor_combat's fight: a player position and two enemy assault waves.
		for i in 6:sim.spawn("rifle",0,Vector2(300+i*5,640))
		for i in 2:sim.spawn("tank",0,Vector2(310+i*8,650))
		for wave in 2:
			sim.time=float(sim.field_ops.get("waves",{}).get("next",sim.scenario.enemy_waves.first))+0.1
			sim.FieldOps.enemy_offensive(sim)
	var events_warn:=[0]
	var start_time:float=sim.time
	var ticks:=int(300.0/DT)
	var started:=Time.get_ticks_msec()
	for tick in ticks:
		var t:float=tick*DT
		if mode=="classic":classic_player(sim,tick,t)
		else:harbor_player(sim,tick,t)
		sim.tick(DT)
		if not battle.pending_actions.is_empty():battle.run_pending()
		for event in sim.events:
			if event.type=="warning":events_warn[0]+=1
		battle.consume_events()
		if not sim.field_ops.is_empty():battle.watch_sites()
		battle.notices.advance(DT)
		if sim.result!="":break
	var stats:Dictionary=battle.notices.stats
	var offered:Array=stats.offered
	var total:int=offered.reduce(func(a,b):return a+b,0)
	print("COUNT %s: %.0f s played, %d ms wall, result '%s'" % [mode,sim.time-start_time,Time.get_ticks_msec()-started,sim.result])
	print("COUNT %s BEFORE: toasts=%d chimes=%d" % [mode,total,events_warn[0]])
	print("COUNT %s AFTER: banners=%d (alert %d, info %d, low %d offered) merged=%d evicted=%d refused=%d cursor_tags=%d dropped=%d chimes=%d" % [mode,stats.banners,offered[Notice.ALERT],offered[Notice.INFO],offered[Notice.LOW],stats.merged,stats.evicted,stats.refused,stats.cursor,offered[Notice.DROP],stats.chimes])
	# Per message type (numbers stripped): level and count.
	var by_key:={}
	for entry in battle.notices.record:
		var key:String="%s|%s" % [["ALERT","INFO","LOW","CURSOR","DROP"][entry[0]],Notice.key_of(entry[1])]
		by_key[key]=int(by_key.get(key,0))+1
	var keys:Array=by_key.keys()
	keys.sort_custom(func(a,b):return by_key[a]>by_key[b])
	for key in keys:print("  TYPE %4d  %s" % [by_key[key],key])

func harbor_player(sim,tick:int,t:float)->void:
	if tick%int(6.0/DT)==3:
		var land:Array=battle.all_sections().filter(func(id):var u=sim.get_unit(id);return not u.get("structure",false) and sim.definitions[u.kind].domain=="land" and u.kind!="engineer")
		if land.is_empty():return
		# Alternate: everyone to the front, then the vehicles alone.
		var group:Array=land if (tick/int(6.0/DT))%2==0 else land.filter(func(id):return sim.get_unit(id).has("crew"))
		if group.is_empty():group=land
		var goal:Vector2=front(sim)
		battle.selected=group
		battle.camera_focus=Vector3(goal.x,0,goal.y)
		battle.update_camera()
		battle.give_order(battle.screen_pos(goal),true,false)
	if tick%int(30.0/DT)==10:battle.ui_action("buy:"+("rifle" if (tick/int(30.0/DT))%2==0 else "tank"),Vector2.ZERO)

# The nearest unsecured objective to the player's force, else the enemy insertion.
func front(sim)->Vector2:
	var own:Array=sim.living(0)
	var centre:=Vector2.ZERO
	for u in own:centre+=u.pos
	if not own.is_empty():centre/=own.size()
	var best:=Vector2(-1,-1)
	for obj in sim.objectives:
		if obj.owner==0:continue
		if best.x<0 or centre.distance_to(obj.pos)<centre.distance_to(best):best=obj.pos
	if best.x<0:best=sim.field_ops.get("enemy_insertion",centre+Vector2(40,0))
	# Advance in 40 m bounds, as a player does.
	return centre+(best-centre).limit_length(40.0)

const BUILDS:=["refinery","power","barracks","factory"]
func classic_player(sim,tick:int,t:float)->void:
	if tick%int(4.0/DT)==1:
		for kind in BUILDS:
			if not sim.Classic.structures(sim,0,kind,false).is_empty():continue
			var site:Vector2=sim.Classic.find_site(sim,kind,0)
			if site.x<0 or sim.credits<float(sim.definitions[kind].cost):break
			battle.ui_action("build:"+kind,Vector2.ZERO)
			battle.camera_focus=Vector3(site.x,0,site.y)
			battle.update_camera()
			click(battle.screen_pos(site))
			break
	if tick%int(10.0/DT)==2:
		var kind:String=["rifle","tank","harvester","rifle","atgm"][(tick/int(10.0/DT))%5]
		battle.ui_action("buy:"+kind,Vector2.ZERO)
	if tick%int(8.0/DT)==5:
		var army:Array=sim.living(0).filter(func(u):return not sim.definitions[u.kind].get("structure",false) and u.kind!="harvester").map(func(u):return u.id)
		if army.is_empty():return
		# classic_playthrough's defensive arc, then its assault staging point.
		var goal:=Vector2(30,48) if t<180.0 else Vector2(58,43)
		battle.selected=army
		battle.camera_focus=Vector3(goal.x,0,goal.y)
		battle.update_camera()
		battle.give_order(battle.screen_pos(goal),true,false)

func click(point:Vector2)->void:
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new()
		event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
		battle._input(event)
