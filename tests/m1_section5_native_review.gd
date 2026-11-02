extends SceneTree

# Render the real Harbor HUD and route InputEvents through its ordinary battle
# handler. This is a deterministic command/layout review, not a human playtest.
const Sim=preload("res://scripts/simulation.gd")
const Campaign=preload("res://scripts/regional_campaign.gd")
const DT:=1.0/30.0
const SOURCES:=["scripts/battle.gd","scripts/hud.gd","scripts/battlefield_interface.gd",
	"scripts/tactical_interface.gd","scripts/field_positions.gd","scripts/throwables.gd",
	"scripts/support_requests.gd","tests/m1_section5_native_review.gd"]
var battle
var failures:=0
var checks:=0
var captures:Array=[]
var output_dir:="res://artifacts/m1-section5-native"

func _init()->void:
	if DisplayServer.get_name()=="headless":
		printerr("M1 SECTION 5 NATIVE requires a graphics display");quit(1);return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):output_dir=argument.trim_prefix("--output=")
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))!=OK:
		printerr("M1 SECTION 5 NATIVE cannot create output folder");quit(1);return
	call_deferred("run")

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func key(code:Key)->void:
	var event:=InputEventKey.new()
	event.keycode=code;event.pressed=true;battle._input(event)
	event.pressed=false;battle._input(event)

func point(at:Vector2)->void:
	var event:=InputEventMouseMotion.new()
	event.position=at;battle._input(event)

func click(at:Vector2,button:int=MOUSE_BUTTON_LEFT)->void:
	var event:=InputEventMouseButton.new()
	event.position=at;event.button_index=button;event.pressed=true;battle._input(event)
	event.pressed=false;battle._input(event)

func step()->void:
	battle.sim.tick(DT);battle.consume_events();battle.notices.advance(DT)

func button_label(id:String)->String:
	var units:Array=battle.TacticalInterface.sections(battle)
	var kind:=id.trim_prefix("tactical:")
	if kind in ["frag","smoke"]:
		var stock:=0
		for unit in units:stock+=battle.sim.Throwables.total(unit,kind)
		return ("G FRAG %d" if kind=="frag" else "V SMOKE %d")%stock
	if kind=="fire":
		var connected:Array=battle.TacticalInterface.policy_sections(battle.sim,units)
		return "H FIRE FREE" if connected.all(func(unit):return unit.fire_policy=="hold") else "H HOLD FIRE"
	return {"dig":"D DIG","upgrade":"U UPGRADE","backup":"B BACKUP","reserve":"RESERVE","auto_frag":"AUTO FRAG"}.get(kind,"")

func refresh()->void:
	battle.hud.battlefield_ui.update(battle.hud)
	battle.sim.update_visibility()
	for frame in 5:
		battle.sync_units(0.1);battle.tactical_effects.sync(battle.sim)
	if battle.refresh_fog_pixels():battle.fog_texture.update(battle.fog_image)
	battle.hud.queue_redraw()
	for frame in 4:await process_frame
	await RenderingServer.frame_post_draw

func capture(name:String,expected_buttons:int,expected_preview:String="")->void:
	await refresh()
	var hud=battle.hud
	var buttons:Array=hud.hits.filter(func(hit):return str(hit.id).begins_with("tactical:"))
	var guide:Rect2=hud.battlefield_ui.tutorial_rect(hud)
	var roster:Rect2=hud.battlefield_ui.roster_rect(hud)
	check(buttons.size()==expected_buttons,"contextual command count for "+name)
	var geometry:Array=[]
	for button in buttons:
		check(Rect2(Vector2.ZERO,hud.size).encloses(button.rect),"button inside viewport: "+name+" "+button.id)
		check(not button.rect.intersects(guide),"button clear of Field Guide: "+name+" "+button.id)
		if hud.battlefield_ui.roster_ids.size()>1:
			check(not button.rect.intersects(roster),"button clear of roster: "+name+" "+button.id)
		var label:=button_label(button.id)
		var label_width:float=hud.bold.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x
		check(label_width+16<=button.rect.size.x,"bold label and padding fit button: "+name+" "+button.id)
		geometry.append({"id":button.id,"rect":str(button.rect),"enabled":button.enabled,"label":label,"label_width":label_width})
	if not expected_preview.is_empty():
		check(battle.tactical_mode==expected_preview,"target mode for "+name)
		check(not hud.tactical_ui.preview_data.is_empty(),"target preview drawn for "+name)
	var path:=output_dir.path_join(name+".jpg")
	check(root.get_texture().get_image().save_jpg(path,0.9)==OK,"capture "+name)
	var selected:Array=[]
	for id in battle.selected:
		var unit:Dictionary=battle.sim.get_unit(id)
		selected.append({"id":id,"kind":unit.kind,"status":battle.TacticalInterface.status(battle.sim,unit),
			"reason":unit.reason,"frag":battle.sim.Throwables.total(unit,"frag"),"smoke":battle.sim.Throwables.total(unit,"smoke")})
	captures.append({"name":name,"path":path,"window_pixels":str(root.size),"render_pixels":str(root.get_texture().get_size()),
		"hud_points":str(hud.size),"requested_ui_scale":battle.settings.values.ui_scale,"time":battle.sim.time,
		"mode":battle.tactical_mode,"preview_ok":hud.tactical_ui.preview_data.get("ok",false) if expected_preview!="" else null,
		"preview_reason":hud.tactical_ui.preview_data.get("reason","") if expected_preview!="" else "",
		"cursor_notice":battle.notices.cursor_text if battle.notices.cursor_left>0 else "",
		"guide":str(guide),"roster":str(roster),"buttons":geometry,"selected":selected})
	print("M1 SECTION 5 CAPTURE ",path)

func aim_point(unit:Dictionary,payload:String)->Vector2:
	for distance in [12.0,15.0,17.0,10.0]:
		for direction in 36:
			var world:Vector2=unit.pos+Vector2.from_angle(direction*TAU/36)*float(distance)
			var screen:Vector2=battle.screen_pos(world)
			if screen.y<100 or screen.y>battle.hud.size.y-280:continue
			if not battle.hud.battlefield_rect().has_point(screen) or battle.hud.action_at(screen)!="":continue
			if battle.sim.Throwables.preview(battle.sim,unit,payload,battle.world_pos(screen)).ok:return screen
	return Vector2.INF

func soil_point(unit:Dictionary)->Vector2:
	for radius in [0.0,3.0,5.0,7.0]:
		for index in (1 if radius==0.0 else 24):
			var world:Vector2=unit.pos+Vector2.from_angle(index*TAU/24)*float(radius)
			if battle.sim.FieldPositions.dig_reason(battle.sim,[unit.id],world,false)=="":return world
	return Vector2.INF

func work_input(engineer:Dictionary)->void:
	var sim=battle.sim
	battle.selected=[engineer.id]
	battle.hud.battlefield_ui.tutorial_active=false
	var world:Vector2=soil_point(engineer)
	if not world.is_finite():
		# Harbor insertion is paved: normal right-click movement reaches soil.
		var origin:Vector2=engineer.pos
		for radius in [16.0,24.0,32.0]:
			for index in 24:
				var destination:Vector2=origin+Vector2.from_angle(index*TAU/24)*float(radius)
				if sim.FieldPositions._ground_reason(sim,destination)!="":continue
				if not sim.terrain.traversable(destination,"land",float(sim.definitions.engineer.radius),[],"infantry"):continue
				battle.camera_focus=Vector3(destination.x,sim.terrain.height_at(destination),destination.y)
				battle.camera_size=50;battle.camera_zoom_target=50;battle.update_camera()
				await refresh()
				var screen:Vector2=battle.screen_pos(destination)
				if battle.hud.action_at(screen)!="":continue
				click(screen,MOUSE_BUTTON_RIGHT)
				for tick in 900:
					step()
					if engineer.orders.is_empty():break
				key(KEY_S)
				for tick in 15:step()
				world=soil_point(engineer)
				if world.is_finite():break
			if world.is_finite():break
	check(world.is_finite(),"native engineer reaches diggable Harbor soil through ordinary movement")
	if not world.is_finite():return
	battle.camera_focus=Vector3(world.x,sim.terrain.height_at(world),world.y)
	battle.camera_size=23;battle.camera_zoom_target=23;battle.update_camera()
	await refresh()
	key(KEY_D);point(battle.screen_pos(world))
	await capture("07-dig-preview",8,"dig")
	check(battle.hud.tactical_ui.preview_data.get("ok",false),"native dig preview accepts reachable soil")
	var funds:float=sim.credits
	click(battle.screen_pos(world))
	var sites:Array=sim.units.filter(func(u):return u.get("field_position",false))
	check(battle.tactical_mode.is_empty() and sites.size()==1,"native D click creates exactly one survey")
	check(sim.credits==funds,"native digging has no supply charge")
	if sites.size()!=1:return
	var site:Dictionary=sites[0]
	for tick in 240:
		step()
		if float(site.position_progress)>=1.0:break
	point(Vector2(30,100))
	await capture("08-digging-status",8)
	check(battle.TacticalInterface.status(sim,engineer).contains("remaining"),"selected working engineer shows remaining work")
	for tick in 900:
		step()
		if site.position_stage==1:break
	check(site.position_stage==1,"native dig command finishes real shallow cover")
	key(KEY_U);point(battle.screen_pos(site.pos))
	await capture("09-upgrade-preview",8,"upgrade")
	check(battle.hud.tactical_ui.preview_data.get("ok",false),"native U preview accepts completed shallow cover")
	funds=sim.credits
	click(battle.screen_pos(site.pos))
	check(battle.tactical_mode.is_empty() and is_equal_approx(funds-sim.credits,float(sim.definitions.fighting_trench.cost)),"native U click pays the upgrade price once")
	for tick in 90:
		step()
		if float(site.position_progress)>=1.0:break
	point(Vector2(30,100))
	await capture("10-reinforcing-status",8)
	check(site.position_stage==1 and site.build_left>0,"reinforcement status retains the existing shallow cover while work proceeds")

func run()->void:
	root.size=Vector2i(1280,800)
	Campaign.enabled=false
	Sim.scenario_selection=Sim.Scenarios.index_for_id("black_sea_harbor")
	battle=load("res://scenes/main.tscn").instantiate()
	battle.settings_path="user://m1-section5-native-settings.cfg"
	root.add_child(battle);current_scene=battle
	battle.set_process(false);battle.set_physics_process(false);battle.effects.muted=true
	battle.close_region();battle.ui_action("begin",Vector2.ZERO)
	battle.show_help=false;battle.paused=true
	var sim=battle.sim
	var rifle:Dictionary=sim.living(0).filter(func(u):return u.kind=="rifle")[0]
	var engineer:Dictionary=sim.living(0).filter(func(u):return u.kind=="engineer")[0]
	sim.stop([rifle.id,engineer.id])
	battle.camera_focus=Vector3(rifle.pos.x,sim.terrain.height_at(rifle.pos),rifle.pos.y)
	battle.camera_size=42;battle.camera_zoom_target=42;battle.update_camera()
	battle.selected=[rifle.id,engineer.id]
	battle.hud.battlefield_ui.tutorial_active=true
	point(Vector2(30,100))
	await capture("01-minimum-strip",8)
	var target:Vector2=aim_point(rifle,"smoke")
	check(target.is_finite(),"Harbor has a visible valid smoke target clear of UI")
	if target.is_finite():
		key(KEY_V);point(target)
		await capture("02-smoke-preview",8,"smoke")
		check(battle.hud.tactical_ui.preview_data.get("ok",false),"smoke arc and effect-area preview is accepted")
		var stock:int=sim.Throwables.total(rifle,"smoke")
		click(target)
		check(battle.tactical_mode.is_empty() and sim.throwables.preparations.size()==1,"native input confirms exactly one smoke preparation")
		check(sim.Throwables.total(rifle,"smoke")==stock,"native preparation retains stock until release")
		key(KEY_S);sim.tick(DT);battle.consume_events()
		check(sim.throwables.preparations.is_empty() and sim.Throwables.total(rifle,"smoke")==stock,"native Hold cancels preparation without spending")
	battle.selected=[rifle.id]
	await refresh()
	key(KEY_G);point(battle.screen_pos(rifle.pos))
	check(battle.notices.cursor_left<=0,"new targeting suppresses stale Stop acknowledgement")
	await capture("03-rejected-frag",7,"frag")
	check(not battle.hud.tactical_ui.preview_data.get("ok",true),"frag at the section's feet has a rejected preview")
	var frag:int=sim.Throwables.total(rifle,"frag")
	click(battle.screen_pos(rifle.pos))
	check(battle.tactical_mode=="frag" and sim.throwables.preparations.is_empty() and sim.Throwables.total(rifle,"frag")==frag,"rejected native frag keeps targeting and inventory")
	check(battle.notices.cursor_left>0,"rejected confirmation produces active feedback")
	await capture("03b-rejected-frag-feedback",7,"frag")
	key(KEY_ESCAPE)
	check(battle.tactical_mode.is_empty() and battle.paused,"native Escape cancels gesture and preserves pause")
	# Exercise actual strip clicks, including the visible policy state.
	battle.selected=[rifle.id,engineer.id]
	await refresh()
	var reserve:Array=battle.hud.hits.filter(func(hit):return hit.id=="tactical:reserve")
	check(reserve.size()==1,"native strip exposes reserve command")
	if not reserve.is_empty():click(reserve[0].rect.get_center())
	check(rifle.reserve_enabled and engineer.reserve_enabled,"native reserve button delegates selected sections")
	key(KEY_H)
	check(rifle.fire_policy=="hold" and engineer.fire_policy=="hold","native H toggles actual fire policy")
	root.size=Vector2i(1600,900)
	battle.settings.values.ui_scale=1.0;battle.update_interface_scale();battle.update_camera()
	point(Vector2(30,100))
	await capture("04-wide-policy-state",8)
	# Largest user setting is intentionally capped by the existing minimum
	# logical layout; verify the compact branch at both physical resolutions.
	battle.settings.values.ui_scale=1.5;battle.update_interface_scale();battle.update_camera()
	await capture("05-wide-largest-ui",8)
	root.size=Vector2i(1280,800);battle.update_interface_scale();battle.update_camera()
	await capture("06-minimum-largest-ui",8)
	# Review a single section's active work status at the largest compact UI.
	await work_input(engineer)
	var hashes:Dictionary={}
	for source in SOURCES:hashes[source]=FileAccess.get_sha256("res://"+source)
	var report:=FileAccess.open(output_dir.path_join("review.json"),FileAccess.WRITE)
	check(report!=null,"native metadata opens")
	if report!=null:report.store_string(JSON.stringify({"engine":Engine.get_version_info().string,"adapter":RenderingServer.get_video_adapter_name(),
		"checks":checks,"failures":failures,"source_sha256":hashes,"captures":captures,
		"note":"Harbor native rendering and ordinary InputEvent handler checks at supported window sizes and largest UI setting. Campaign persistence disabled. Screenshots remain local. No hardware performance or human-playtest claim."},"  "))
	print("M1 SECTION 5 NATIVE: %d captures, %d checks, %d failures"%[captures.size(),checks,failures])
	battle.queue_free();await process_frame;await process_frame
	quit(1 if failures else 0)
