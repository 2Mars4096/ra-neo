extends SceneTree
# Right-click / A-click special actions from battle.give_order on the harbor:
# mixed selections (units that cannot do the action take the normal order),
# Shift-queued garrison / re-crew / clear behind current orders, cursor action
# hints, and the guide rows that document them.
const Sim=preload("res://scripts/simulation.gd")
const VehicleDamage=preload("res://scripts/vehicle_damage.gd")
const Garrison=preload("res://scripts/garrison.gd")
const DT:=1.0/30.0
var failures:=0
var checks:=0
var battle
var sim
var fired_at:=Vector2.ZERO

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

func _init()->void:
	Sim.scenario_selection=harbor_index()
	call_deferred("run")

func make_abandoned(team:int,pos:Vector2)->Dictionary:
	var hull:Dictionary=sim.spawn("tank",team,pos)
	hull.facing=Vector2.UP
	VehicleDamage.ensure_state(sim,hull)
	hull.crew=0
	hull.abandoned=true
	hull["abandoned_hp"]=300.0
	hull.hp-=VehicleDamage._finish(sim,hull,hull.hp+1.0)
	return hull

func look_at(pos:Vector2)->void:
	battle.camera_focus=Vector3(pos.x,0,pos.y)
	battle.update_camera()

# The last order acknowledgement went to the pointer tag (notice_feed CURSOR), not a banner.
func acked_at_pointer()->bool:
	return battle.notices.cursor_left>0 and battle.notices.cursor_text==battle.toast and not battle.notices.banners.any(func(b):return b.text==battle.toast)

func spawn_near(kind:String,pos:Vector2)->Dictionary:
	var u:Dictionary=sim.spawn(kind,0,pos)
	if not u.is_empty():sim.update_visibility()
	return u

# Tick until the queued action starts (as play does after each sim tick);
# fired_at is where the section stood then.
func run_until_idle(u:Dictionary,seconds:float=30.0)->void:
	var t:=0.0
	while t<seconds and not battle.pending_actions.is_empty():
		fired_at=u.pos
		sim.tick(DT)
		battle.run_pending()
		t+=DT

# A building with a reachable doorway whose screen point resolves to itself.
func fixture_building()->Dictionary:
	var data:Dictionary=Garrison.index(sim)
	for b in data.buildings:
		var door:=Garrison.entry_point(sim,b.id,b.bounds.get_center()+Vector2(0,30))
		if door.x<0 or not sim.terrain.traversable(door+Vector2(0,8),"land",2.65) or not sim.terrain.traversable(door+Vector2(0,16),"land",3.0):continue
		if int(b.capacity)<2 or not sim.terrain.traversable(door+Vector2(0,24),"land",2.65):continue
		look_at(b.bounds.get_center())
		var p:Vector2=battle.screen_pos(b.bounds.get_center())
		var open:Vector2=battle.screen_pos(door+Vector2(0,24))
		if battle.building_under(p)==b.id and battle.hud.action_at(p)=="" and battle.building_under(open)<0:return {"building":b,"door":door,"click":p,"open":open}
	return {}

func run()->void:
	root.size=Vector2i(1440,900)
	battle=load("res://scenes/main.tscn").instantiate()
	root.add_child(battle)
	current_scene=battle
	await process_frame
	await process_frame
	sim=battle.sim
	check(not sim.field_ops.is_empty(),"harbor is a field-ops scenario")
	await guide_rows()
	battle.show_help=false
	var fix:=fixture_building()
	check(not fix.is_empty(),"fixture building with doorway on screen")
	if fix.is_empty():
		finish();return
	var b:Dictionary=fix.building
	var door:Vector2=fix.door
	var rifle:=spawn_near("rifle",door+Vector2(0,8))
	var tank:=spawn_near("tank",door+Vector2(0,16))
	battle.sync_units(0.016)
	# 1. Mixed garrison: infantry go in, the tank moves next to the building.
	battle.selected=[rifle.id,tank.id]
	battle.give_order(fix.click,false,false)
	check(int(rifle.get("garrison_target",-1))==b.id,"infantry ordered into the building")
	check(not tank.orders.is_empty() and tank.orders[0].mode=="move","tank in mixed selection moves (orders %s)" % [tank.orders])
	check(not tank.orders.is_empty() and tank.orders[-1].pos.distance_to(b.bounds.get_center())<16.0,"tank closes up beside the building")
	check(str(battle.toast).contains("entering building") and str(battle.toast).contains("1 / 1"),"mixed garrison toast: %s" % battle.toast)
	check(acked_at_pointer(),"garrison acknowledgement is a pointer tag, not a banner")
	# Cursor hints for the same selection.
	battle.pointer=fix.click
	battle.refresh_cursor_hint()
	check(battle.cursor_hint=="Garrison","hover building with infantry: %s" % battle.cursor_hint)
	battle.selected=[tank.id]
	battle.refresh_cursor_hint()
	check(battle.cursor_hint=="","tank alone gets no garrison hint: %s" % battle.cursor_hint)
	battle.attack_mode=true
	battle.refresh_cursor_hint()
	check(battle.cursor_hint=="Shell","A-mode tank over building hints Shell: %s" % battle.cursor_hint)
	battle.attack_mode=false
	battle.pointer=fix.open
	battle.selected=[rifle.id,tank.id]
	battle.refresh_cursor_hint()
	check(battle.cursor_hint=="","open ground has no hint: %s" % battle.cursor_hint)
	var started:=Time.get_ticks_usec()
	battle.pointer=fix.click
	for i in 50:battle.refresh_cursor_hint()
	var hint_ms:=(Time.get_ticks_usec()-started)/50000.0
	print("cursor hint refresh: %.3f ms" % hint_ms)
	check(hint_ms<4.0,"cursor hint refresh is cheap (%.3f ms)" % hint_ms)
	battle.hud.queue_redraw()
	await process_frame
	check(battle.hud.action_at(fix.click+Vector2(30,28))!="blocked","hint tag does not block clicks")
	# 2. Mixed shell: the tank shells, the rifle section attack-moves there.
	sim.stop([rifle.id,tank.id])
	battle.selected=[rifle.id,tank.id]
	battle.give_order(fix.click,true,false)
	check(int(tank.get("bombard",-1))==b.id,"tank in mixed selection shells the building")
	check(not rifle.orders.is_empty() and rifle.orders[0].mode=="attack_move","rifle attack-moves alongside (orders %s)" % [rifle.orders])
	check(str(battle.toast).contains("shelling the building"),"shell toast: %s" % battle.toast)
	check(acked_at_pointer(),"shell acknowledgement is a pointer tag, not a banner")
	check(not battle.attack_mode,"attack mode clears after shell order")
	sim.stop([rifle.id,tank.id])
	tank.erase("bombard")
	# 3. Shift-queued garrison: waits for the current move, then enters.
	var away:Vector2=door+Vector2(0,24)
	sim.issue([rifle.id],away,"move")
	check(not rifle.orders.is_empty(),"rifle busy with a move")
	rifle.erase("garrison_target")
	battle.selected=[rifle.id]
	battle.give_order(fix.click,false,true)
	check(not rifle.has("garrison_target") and rifle.orders.size()==1 and rifle.orders[0].pos.distance_to(away)<4.0,"queued garrison keeps the current move")
	check(battle.pending_actions.size()==1,"garrison queued behind current orders")
	check(str(battle.toast).begins_with("Queued:"),"queued toast: %s" % battle.toast)
	run_until_idle(rifle)
	check(battle.pending_actions.is_empty(),"queued action started")
	check(int(rifle.get("garrison_target",-1))==b.id or int(rifle.get("garrison",-1))==b.id,"queued garrison begins after the move")
	check(fired_at.distance_to(away)<6.0,"rifle reached the first destination first (%.1f m)" % fired_at.distance_to(away))
	# A direct order or Stop cancels a queued action.
	sim.issue([rifle.id],away+Vector2(4,0),"move")
	battle.give_order(fix.click,false,true)
	check(battle.pending_actions.size()==1,"queued again")
	battle.give_order(battle.screen_pos(away+Vector2(-4,0)),false,false)
	battle.run_pending()
	check(battle.pending_actions.is_empty(),"direct order drops the queued garrison")
	battle.give_order(fix.click,false,true)
	sim.stop([rifle.id])
	battle.run_pending()
	check(battle.pending_actions.is_empty(),"Stop drops the queued garrison")
	# Shift with an idle section acts at once.
	sim.stop([rifle.id])
	battle.give_order(fix.click,false,true)
	check(int(rifle.get("garrison_target",-1))==b.id and battle.pending_actions.is_empty(),"Shift on an idle section garrisons now")
	sim.stop([rifle.id])
	rifle.erase("garrison_target")
	# 4. Mixed re-crew and Shift-queued re-crew.
	var hull:=make_abandoned(0,door+Vector2(14,24))
	battle.sync_units(0.016)
	look_at(hull.pos)
	var hull_click:Vector2=battle.screen_pos(hull.pos)
	battle.pointer=hull_click
	battle.selected=[rifle.id,tank.id]
	battle.refresh_cursor_hint()
	check(battle.cursor_hint=="Re-crew","hover abandoned hull: %s" % battle.cursor_hint)
	sim.stop([rifle.id,tank.id])
	battle.give_order(hull_click,false,false)
	var jobs:Array=sim.get_meta(VehicleDamage.RECREW) if sim.has_meta(VehicleDamage.RECREW) else []
	check(jobs.size()==1 and int(jobs[0].section)==rifle.id,"infantry sent to re-crew")
	check(not tank.orders.is_empty(),"tank in mixed selection moves to the hull")
	check(str(battle.toast).contains("re-crew"),"re-crew toast: %s" % battle.toast)
	check(acked_at_pointer(),"re-crew acknowledgement is a pointer tag, not a banner")
	sim.stop([rifle.id,tank.id])
	sim.tick(DT)
	if sim.has_meta(VehicleDamage.RECREW):sim.remove_meta(VehicleDamage.RECREW)
	sim.issue([rifle.id],rifle.pos+Vector2(-6,0),"move")
	battle.selected=[rifle.id]
	battle.give_order(hull_click,false,true)
	check(not sim.has_meta(VehicleDamage.RECREW) and battle.pending_actions.size()==1,"re-crew queued behind the move")
	run_until_idle(rifle)
	check(sim.has_meta(VehicleDamage.RECREW) and int(sim.get_meta(VehicleDamage.RECREW)[0].hull)==hull.id,"queued re-crew starts after the move")
	sim.stop([rifle.id])
	sim.tick(DT)
	# 5. Mixed clear and Shift-queued clear of seen enemy wire.
	var engineer:=spawn_near("engineer",door+Vector2(-10,24))
	var wire:Dictionary=sim.spawn("concertina_wire",1,door+Vector2(-10,34))
	check(not wire.is_empty(),"enemy wire placed")
	if not wire.is_empty():
		wire.visible=true
		wire.seen_by[0]=true
		battle.sync_units(0.016)
		look_at(wire.pos)
		var wire_click:Vector2=battle.screen_pos(wire.pos)
		check(battle.pick(wire_click,true)==wire.id,"wire pickable")
		battle.selected=[engineer.id,rifle.id]
		battle.pointer=wire_click
		battle.refresh_cursor_hint()
		check(battle.cursor_hint=="Clear","hover enemy wire with engineers: %s" % battle.cursor_hint)
		battle.give_order(wire_click,false,false)
		check(int(engineer.get("clearing_id",-1))==wire.id,"engineers clear the wire")
		check(not rifle.orders.is_empty(),"rifle in mixed selection takes the normal order")
		check(str(battle.toast).contains("clearing"),"clear toast: %s" % battle.toast)
		sim.stop([engineer.id,rifle.id])
		engineer.erase("clearing_id");wire.erase("cleared_by")
		sim.issue([engineer.id],engineer.pos+Vector2(-5,0),"move")
		battle.selected=[engineer.id]
		battle.give_order(wire_click,false,true)
		check(not engineer.has("clearing_id") and battle.pending_actions.size()==1,"clear queued behind the move")
		run_until_idle(engineer)
		check(int(engineer.get("clearing_id",-1))==wire.id,"queued clear starts after the move")
	finish()

func guide_rows()->void:
	var hud=battle.hud
	var rows:Array=hud.FIELD_ORDERS
	var text:=" ".join(rows.map(func(row):return row[1]))
	for word in ["right-click a building","abandoned hull","capture","wire, hedgehogs, sandbags or trench","A, then click a building","FPV","Drag","T rotates"]:
		check(text.contains(word),"guide mentions: "+word)
	for row in rows:
		check(hud.font.get_string_size(row[1],HORIZONTAL_ALIGNMENT_LEFT,-1,13).x<=500,"guide row fits: "+row[0])
	battle.show_help=true
	root.size=Vector2i(1280,800)
	hud.size=Vector2(1280,800)
	hud.queue_redraw()
	await process_frame
	for hit in hud.hits:
		check(Rect2(0,0,1280,800).encloses(hit.rect),"%s fits 1280x800 with field rows" % hit.id)
	root.size=Vector2i(1440,900)
	hud.size=Vector2(1440,900)

func finish()->void:
	print("INPUT ACTIONS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
