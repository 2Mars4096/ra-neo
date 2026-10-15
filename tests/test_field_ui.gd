extends SceneTree
# Headless input/UI regression for field operations on Riverside (scenario 5).
var battle
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)
func click(point:Vector2,button:int=MOUSE_BUTTON_LEFT)->void:
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new()
		event.position=point;event.button_index=button;event.pressed=pressed
		root.push_input(event)
func key(code:Key)->void:
	var event:=InputEventKey.new()
	event.keycode=code;event.physical_keycode=code;event.pressed=true
	root.push_input(event)
func hover(point:Vector2)->void:
	var event:=InputEventMouseMotion.new();event.position=point;root.push_input(event)
	await redraw()
# Placement validation refreshes at most every 200 ms; wait it out in real time.
func hover_site(point:Vector2)->void:
	await hover(point)
	await create_timer(0.25).timeout
	await redraw()
func hit(id:String)->Dictionary:
	for target in battle.hud.hits:
		if target.id==id:return target
	return {}
func press_button(id:String)->void:
	var target:=hit(id)
	check(not target.is_empty(),"button exists: "+id)
	if not target.is_empty():click(target.rect.get_center())
func redraw()->void:
	battle.hud.queue_redraw();await process_frame;await process_frame
func layout_ok(label:String)->void:
	for dimensions in [Vector2i(1280,800),Vector2i(1920,1080),Vector2i(1440,900)]:
		root.size=dimensions;battle.hud.size=Vector2(dimensions)
		await redraw()
		var hits:Array=battle.hud.hits
		for i in hits.size():
			check(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(hits[i].rect),"%s %s fits %s" % [label,hits[i].id,dimensions])
			for j in range(i+1,hits.size()):check(not hits[i].rect.intersects(hits[j].rect),"%s %s / %s do not overlap" % [label,hits[i].id,hits[j].id])
func structures()->Array:
	return battle.sim.units.filter(func(u):return battle.sim.alive(u) and u.get("structure",false))
# Status lines are drawn with fit_text at 234 px / 11 px; equality means no ellipsis.
func untruncated(text:String)->bool:
	return battle.hud.fit_text(text,234,11)==text
func place_members(unit:Dictionary,centre:Vector2,offset:float)->void:
	for i in unit.members.size():unit.members[i].pos=centre+Vector2.from_angle(i*TAU/3.0)*offset
func _init()->void:call_deferred("run")
func run()->void:
	var Sim=preload("res://scripts/simulation.gd")
	Sim.scenario_selection=5
	root.size=Vector2i(1440,900)
	battle=load("res://scenes/main.tscn").instantiate();root.add_child(battle);current_scene=battle
	battle.effects.muted=true
	await process_frame;await process_frame
	var sim=battle.sim
	var hud=battle.hud
	check(not sim.field_ops.is_empty() and sim.classic.is_empty(),"scenario 5 runs field operations without classic economy")
	var engineers:Array=sim.living(0).filter(func(u):return u.kind=="engineer")
	check(engineers.size()==1,"one starting engineer section")
	var engineer:Dictionary=engineers[0]
	var focus:=Vector2(battle.camera_focus.x,battle.camera_focus.z)
	# Camera focus is clamped 12/8 m inside the world edge, like normal panning.
	var size:Vector2=sim.terrain.world_size
	var expected_focus:=Vector2(clampf(engineer.pos.x,12,size.x-12),clampf(engineer.pos.y,8,size.y-8))
	check(focus.distance_to(expected_focus)<1.0 and focus.distance_to(size/2)>30,"camera opens on the engineer at the insertion, not map centre: %s vs %s" % [focus,engineer.pos])

	# Guide lists playable scenarios; the hidden legacy skirmish keeps its id but is not offered.
	await layout_ok("guide")
	var presets:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for index in presets.size():
		var listed:=not hit("scenario:%d" % index).is_empty()
		# Hidden scenarios stay listed only while active (this test runs hidden Riverside).
		check(listed==(not presets[index].get("hidden",false) or index==5),"guide listing for scenario %d follows hidden flag" % index)
	check(hit("scenario:5").get("enabled",false),"current Riverside selector present")
	# The long Riverside brief wraps inside the 632 px modal column without losing words.
	check(sim.scenario.brief.length()>200,"Riverside brief is the long paragraph under review")
	check(hud.brief_lines.size()>1 and hud.brief_lines.size()<=3,"brief wraps to 2-3 lines: %d" % hud.brief_lines.size())
	check(" ".join(hud.brief_lines)==sim.scenario.brief,"wrapped brief keeps every word")
	for line in hud.brief_lines:check(hud.font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x<=632,"brief line fits modal: "+line)
	# Brief baselines start at modal+166 (13 px text), below selectors and above the first row at +224.
	var selector_bottom:float=hit("scenario:5").rect.end.y
	var modal_top:float=hud.size.y/2-252
	check(selector_bottom<modal_top+166-13,"brief starts below scenario selectors")
	check(modal_top+166+16*(hud.brief_lines.size()-1)+4<modal_top+224-10,"brief ends above guide rows")
	press_button("begin");await process_frame
	check(not battle.show_help and "engineers" in battle.toast,"deploy briefing points at engineers")
	battle.paused=true
	await redraw()

	# Single supply pool: offmap reinforcements, no power/factory/refinery construction.
	var actions:Array=hud.hits.map(func(h):return h.id)
	for kind in sim.Classic.BUILDINGS:check(not ("build:"+kind) in actions,"no classic construction: "+kind)
	check(not "buy:harvester" in actions,"no harvester economy")
	for kind in sim.FieldOps.PURCHASES:check(("buy:"+kind) in actions,"reinforcement tile: "+kind)
	for kind in sim.FieldOps.build_choices():check(("build:"+kind) in actions,"field work button: "+kind)
	check(not hit("build:tactical_cover").enabled,"field works disabled until engineers selected")
	check(hud.field_block_reason(sim,"tactical_cover",-1)=="Select an engineer section to build","disabled field works explain the builder requirement")
	var funds:float=sim.credits
	var count:int=sim.living(0).size()
	press_button("buy:engineer");await process_frame
	check(is_equal_approx(sim.credits,funds-120.0) and sim.living(0).size()==count+1,"engineer purchase charges 120 and deploys a section")
	check(battle.toast=="Reinforcement deployed at landing zone","purchase confirmation message")
	var spare:Dictionary=sim.living(0).filter(func(u):return u.kind=="engineer" and u.id!=engineer.id)[0]
	await redraw()
	check(hit("buy:rifle").enabled,"reinforcements can be queued during the deployment interval")
	battle.ui_action("buy:rifle",Vector2.ZERO)
	battle.ui_action("buy:rifle",Vector2.ZERO)
	check(sim.FieldOps.queued(sim,"rifle")==2 and battle.toast.contains("queued"),"repeat clicks queue units: "+battle.toast)
	await redraw()
	var rifle_tile:Rect2=hit("buy:rifle").rect
	var right:=InputEventMouseButton.new();right.button_index=MOUSE_BUTTON_RIGHT;right.pressed=true;right.position=rifle_tile.get_center()
	battle._input(right)
	check(sim.FieldOps.queued(sim,"rifle")==1 and battle.toast.contains("removed"),"right-click removes one queued unit: "+battle.toast)
	sim.FieldOps.cancel_queued(sim,"rifle")
	sim.recruit_clock=0.0
	var saved:float=sim.credits
	sim.credits=10.0
	battle.ui_action("buy:tank",Vector2.ZERO)
	check(battle.toast.begins_with("Need ") and battle.toast.ends_with("more supply"),"purchase failure explains supply: "+battle.toast)
	sim.credits=saved

	# Engineer selection exposes priced field works and enters placement.
	battle.selected=[engineer.id]
	await layout_ok("engineer")
	for kind in sim.FieldOps.build_choices():check(hit("build:"+kind).get("enabled",false),"engineer enables "+kind)
	press_button("build:tactical_cover");await process_frame
	check(battle.build_mode=="tactical_cover" and "Esc cancels" in battle.toast,"field work button enters placement preview")
	key(KEY_ESCAPE);await process_frame
	check(battle.build_mode=="" and battle.toast=="Placement cancelled","Esc cancels unplaced preview")
	check(structures().is_empty() and is_equal_approx(sim.credits,saved),"cancelled preview builds nothing")
	press_button("build:observation_post");await process_frame
	battle.selected.clear()
	await process_frame
	check(battle.build_mode=="" and "no living engineer" in battle.toast,"preview closes without a selected engineer")
	battle.selected=[engineer.id]
	await redraw()

	# Invalid placement keeps the preview and reports the authoritative failure.
	press_button("build:tactical_cover");await process_frame
	var blocked_screen:Vector2=battle.screen_pos(engineer.members[0].pos)
	click(blocked_screen);await process_frame
	check(battle.toast==sim.field_ops.get("last_build_error","") and battle.toast!="","blocked placement shows FieldOps last_build_error: "+battle.toast)
	check(battle.build_mode=="tactical_cover" and structures().is_empty() and is_equal_approx(sim.credits,saved),"blocked placement keeps preview without charge")

	# Find a visible site the preview accepts.
	var site_screen:=Vector2(-1,-1)
	for ring in range(4,18):
		for step in 16:
			var candidate:Vector2=engineer.pos+Vector2.from_angle(step*TAU/16.0)*ring
			var screen:Vector2=battle.screen_pos(candidate)
			if not hud.battlefield_rect().has_point(screen) or hud.action_at(screen)!="":continue
			if sim.FieldOps.can_build(sim,"tactical_cover",battle.world_pos(screen),engineer.id):
				site_screen=screen;break
		if site_screen.x>=0:break
	check(site_screen.x>=0,"found a visible valid site near the engineer")
	if site_screen.x<0:
		finish();return
	var site_world:Vector2=battle.world_pos(site_screen)

	# An unseen enemy on the site: the preview stays clean, the commit fails with the sim's message.
	var hidden:Dictionary=sim.spawn("rifle",1,site_world)
	check(not hidden.is_empty() and not hidden.seen_by[0],"hidden enemy placed unseen on the site")
	await hover_site(site_screen)
	check(hidden.pos.distance_to(site_world)<3.0,"hidden enemy stands on the proposed footprint")
	check(hud.preview_reason=="","preview does not reveal the hidden occupant: "+hud.preview_reason)
	click(site_screen);await process_frame
	check(structures().is_empty() and is_equal_approx(sim.credits,saved),"hidden-occupancy commit builds and charges nothing")
	check(battle.toast!="" and battle.toast==sim.field_ops.get("last_build_error","x"),"commit failure reports last_build_error, not an empty preview reason: "+battle.toast)
	hidden.hp=0.0
	for member in hidden.members:member.hp=0.0

	# A valid click builds with the selected engineer.
	await hover_site(site_screen)
	check(hud.preview_reason=="","placement preview validates the hovered site")
	click(site_screen);await process_frame
	var built:Array=structures()
	check(built.size()==1 and battle.build_mode=="","valid click builds and exits placement")
	check("site marked" in battle.toast,"construction start message: "+battle.toast)
	check(is_equal_approx(sim.credits,saved-60.0),"construction charges 60 supply")
	if built.is_empty():
		finish();return
	var site:Dictionary=built[0]
	check(site.engineer_id==engineer.id and site.build_left>0,"structure records selected engineer and remaining work")
	check(hud.field_block_reason(sim,"aid_post",engineer.id)=="Engineer assigned to another site","assigned engineer explains why another site is unavailable")
	await redraw()
	check(not hit("build:aid_post").get("enabled",true),"assigned engineer cannot start a second site")
	var assigned:String=hud.engineer_status(sim,engineer)
	check(assigned=="Assigned COVER · orders pause it" and untruncated(assigned),"engineer panel warns orders pause its site: "+assigned)

	# Site status follows the actual FieldOps.tick gates.
	battle.selected=[site.id]
	await layout_ok("structure")
	var work:Vector2=site.work_point
	check(not hit("resume_build").enabled and hit("cancel_build").enabled,"RESUME disabled while builder assigned; CANCEL available")
	await hover(hit("resume_build").rect.get_center())
	check(hud.hint_text=="Builder already assigned","disabled RESUME explains why")
	# Conditions are probed by placing the paused section; the game never ticks here.
	var home:Vector2=engineer.pos
	var orders:Array=engineer.orders.duplicate(true)
	engineer.pos=work+Vector2(6,0)
	if engineer.orders.is_empty():engineer.orders=[{"mode":"move","pos":work,"target":-1}]
	check(hud.site_condition(sim,site)=="en_route","assigned engineer with orders away from work point is en route")
	engineer.pos=work;place_members(engineer,work,0.6)
	check(hud.site_condition(sim,site)=="building","engineer anchored with unsuppressed members is building")
	engineer.suppression=0.9
	check(hud.site_condition(sim,site)=="pinned","suppressed engineer at work point is pinned")
	engineer.suppression=0.0
	for member in engineer.members:member.suppression=0.9
	check(hud.site_condition(sim,site)=="pinned","all nearby members suppressed is pinned")
	for member in engineer.members:member.suppression=0.0
	place_members(engineer,work,5.0)
	check(hud.site_condition(sim,site)=="regrouping","anchor at site without members in reach is regrouping")
	engineer.pos=work+Vector2(4,0);engineer.orders=[]
	check(hud.site_condition(sim,site)=="off_site","idle engineer away from work point is off site")
	engineer.pos=home;engineer.orders=orders;place_members(engineer,home,0.6)
	for condition in hud.SITE_STATUS:
		var text:String=hud.SITE_STATUS[condition]
		check(untruncated(text),"status not truncated: "+text)
		if condition=="pinned":check(not ("move" in text.to_lower() or "reach" in text.to_lower() or "order" in text.to_lower()),"pinned status gives no move instruction")
	for kind in hud.FIELD_EFFECTS:check(untruncated(hud.FIELD_EFFECTS[kind]),"effect not truncated: "+hud.FIELD_EFFECTS[kind])
	check(hud.bold.get_string_size(hud.cancel_label(140),HORIZONTAL_ALIGNMENT_LEFT,-1,10).x<=hit("cancel_build").rect.size.x-14,"largest CANCEL refund label fits its button")
	click(battle.screen_pos(engineer.pos+Vector2(-6,4)),MOUSE_BUTTON_RIGHT);await process_frame
	check(battle.toast.begins_with("Field structures are fixed"),"order to a structure explains it is fixed")

	# A new order releases the builder; the paid site and its progress remain.
	site.build_left=4.0
	var funds_before:float=sim.credits
	battle.selected=[engineer.id]
	var ground:Vector2=battle.screen_pos(engineer.pos+Vector2(-8,-6))
	click(ground,MOUSE_BUTTON_RIGHT);await process_frame
	check(site.build_paused and site.engineer_id==-1 and is_equal_approx(site.build_left,4.0),"new order releases builder and keeps site work")
	check("COVER site paused, RESUME later" in battle.toast,"order toast says the site paused: "+battle.toast)
	check(is_equal_approx(sim.credits,funds_before),"release charges nothing")
	check(hud.engineer_status(sim,engineer)=="Ready · choose field works above","released engineer is free")
	battle.selected=[site.id]
	await redraw()
	check(hud.builder_status(sim,site)=="PAUSED · Press RESUME to continue","paused site explains resume")
	check(hit("resume_build").get("enabled",false),"RESUME enabled with a free engineer")
	await hover(hit("resume_build").rect.get_center())
	check(hud.hint_text=="Resume with nearest free engineer · no charge · 50% kept","RESUME tooltip: "+hud.hint_text)
	await hover(hit("cancel_build").rect.get_center())
	check(hud.hint_text=="Cancel site · refund 30 of 60 supply · built share is lost","CANCEL tooltip shows full refund: "+hud.hint_text)
	var nearest:int=sim.FieldOps.available_engineer(sim,site.id)
	press_button("resume_build");await process_frame
	check(not site.build_paused and site.engineer_id==nearest and nearest>=0,"RESUME assigns the nearest free engineer")
	check(is_equal_approx(sim.credits,funds_before) and is_equal_approx(site.build_left,4.0),"RESUME charges nothing and keeps progress")
	check(battle.toast=="COVER resumed • engineers en route • no charge","resume confirmation: "+battle.toast)

	# Stop (S) also releases; losing the assigned builder is announced and recoverable.
	battle.selected=[nearest]
	key(KEY_S);await process_frame
	check(site.build_paused and "site paused" in battle.toast,"Stop releases builder and says so: "+battle.toast)
	battle.selected=[site.id]
	await redraw()
	press_button("resume_build");await process_frame
	var builder:Dictionary=sim.get_unit(site.engineer_id)
	builder.hp=0.0
	await process_frame
	check(hud.site_condition(sim,site)=="lost","dead builder leaves site without builder")
	check(battle.toast=="COVER builder lost • select site, RESUME","builder loss announced: "+battle.toast)
	await redraw()
	check(hit("resume_build").get("enabled",false),"RESUME enabled while another engineer is free")
	var other:Dictionary=spare if builder.id==engineer.id else engineer
	other.hp=0.0
	await redraw()
	check(not hit("resume_build").get("enabled",true),"RESUME disabled when no engineer is available")
	await hover(hit("resume_build").rect.get_center())
	check(hud.hint_text=="No free engineer · buy or release one","disabled RESUME explains missing engineer")
	battle.ui_action("resume_build",Vector2.ZERO)
	check(battle.toast==sim.field_ops.get("last_build_error","x") and battle.toast!="","failed resume reports last_build_error: "+battle.toast)

	# Cancel refunds the unbuilt share and says how much.
	var before_cancel:float=sim.credits
	press_button("cancel_build");await process_frame
	check(not sim.alive(site) and battle.toast=="COVER cancelled • 30 supply refunded","cancel removes site and reports refund: "+battle.toast)
	check(is_equal_approx(sim.credits,before_cancel+30.0),"cancel refunds the unbuilt share")
	check(battle.selected.is_empty(),"cancelled site leaves selection")
	battle.ui_action("cancel_build",Vector2.ZERO)
	battle.selected=[site.id]
	battle.ui_action("cancel_build",Vector2.ZERO)
	check(battle.toast=="Only unfinished field structures can be cancelled","invalid cancel explains failure")
	finish()

func finish()->void:
	print("FIELD UI: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
