extends Control

const INK := Color("191d1b")
const PANEL := Color("242923")
const LINE := Color("51594b")
const WHITE := Color("e7e6d7")
const MUTED := Color("a5ab98")
const TEAL := Color("b8ca83")
const ORANGE := Color("dab273")
const RED := Color("df8066")
const Notice := preload("res://scripts/notice_feed.gd")
const BattlefieldInterface := preload("res://scripts/battlefield_interface.gd")
const Scenarios := preload("res://scripts/scenario_catalog.gd")
const SCENARIO_LABELS := {"coast":"COAST","fields":"FIELDS","urban":"URBAN","showcase":"SHOWCASE","classic":"SKIRMISH","riverside_town":"TOWN","black_sea_harbor":"BLACK SEA HARBOR"}
# Player-facing summaries of the effects FieldOps.tick applies.
const FIELD_FUNCTIONS := {"tactical_cover":"Infantry cover barrier once complete · T rotates","observation_post":"Raised post with 24 m sight","repair_point":"Repairs land vehicles within 10 m out of combat","aid_post":"Treats wounded living soldiers within 10 m; no revival","concertina_wire":"Slows infantry to a crawl; tracked vehicles crush it · T rotates","tank_obstacles":"Hedgehogs stop tracked and wheeled vehicles; infantry pass with cover · T rotates","fighting_trench":"Dug-in infantry cover inside the trench · T rotates","vehicle_berm":"Armoured vehicles: 40% less ground fire damage from front/sides","camouflage_net":"Land units spotted at half range; firing reveals them for 3s","forward_supply_point":"Land entry needs a connected route and no seen enemy within 18 m; otherwise uses rear","bunker":"Concrete MG pillbox: pins and cuts down infantry; needs tanks or AT fire to destroy","at_gun":"Dug-in anti-tank gun: long-range fire against armour and boats","command_post":"Radio command post: 28 m observation; enemy reserves stage from command posts","ammo_depot":"Ammunition dump: enemy counterattacks need a depot or command post"}
const FIELD_LABELS := {"tactical_cover":"COVER","observation_post":"OBS","repair_point":"REPAIR","aid_post":"AID","concertina_wire":"WIRE","tank_obstacles":"AT OBST","fighting_trench":"TRENCH","vehicle_berm":"BERM","camouflage_net":"NET","forward_supply_point":"SUPPLY","bunker":"BUNKER","at_gun":"AT GUN","command_post":"CMD POST","ammo_depot":"DEPOT"}
const FIELD_EFFECTS := {"tactical_cover":"Cover for infantry behind it","observation_post":"Observation · 24 m sight","repair_point":"Repairs vehicles within 10 m","aid_post":"Treats soldiers within 10 m","concertina_wire":"Infantry slowed · armour crushes","tank_obstacles":"Vehicles blocked · infantry cover","fighting_trench":"Infantry cover inside","vehicle_berm":"Hull-down vehicles","camouflage_net":"Half detection range","forward_supply_point":"Forward reinforcement entry","bunker":"MG fire · infantry pinned","at_gun":"Anti-tank fire","command_post":"Observation · staging","ammo_depot":"Supplies counterattacks"}
# Site conditions mirror the FieldOps.tick gates; none tells a pinned builder to move.
const SITE_STATUS := {"queued":"QUEUED · Built next · RESUME = now","paused":"PAUSED · Press RESUME to continue","lost":"BUILDER LOST · RESUME with engineer","en_route":"EN ROUTE · Engineers heading to site","off_site":"OFF SITE · Engineers short of site","pinned":"PINNED · Work resumes as fire eases","regrouping":"REGROUPING · Engineers gathering","building":"BUILDING · Engineers at work"}
const SITE_LABELS := {"queued":"QUEUED","paused":"PAUSED","lost":"NO BUILDER","en_route":"EN ROUTE","off_site":"OFF SITE","pinned":"PINNED","regrouping":"REGROUPING"}
# Building states from UnitAnimation.state shown over a selected section/vehicle.
const BUILDING_STATES := ["ENTERING","GARRISONED","GARRISON FIRING","EXITING","BOMBARDING"]
# Guide rows for field-ops scenarios: right-click and A-click special actions.
const FIELD_ORDERS := [
	["GARRISON","Infantry: right-click a building. Fire from windows; move to leave."],
	["RE-CREW","Infantry: right-click an abandoned hull to crew it or capture it."],
	["CLEAR","Engineers: right-click enemy wire, hedgehogs, sandbags or trench."],
	["SHELL","Tanks and guns: A, then click a building. Others move alongside."],
	["FPV / WORKS","FPV button, then click a seen enemy. Drag lays lines; T rotates."]]
const UNIT_NAMES := {"rifle":"RIFLE SECTION","atgm":"AT TEAM","engineer":"ENGINEERS","tank":"MAIN BATTLE TANK","drone":"SCOUT UAV","helo":"GUNSHIP","boat":"CORVETTE","aa":"AIR DEFENSE","harvester":"HARVESTER","fpv_drone":"FPV DRONE"}
var battle: Node3D
var battlefield_ui=BattlefieldInterface.new()
var scenario_entries: Array[Dictionary] = []
var preview_key := ""
var preview_reason := ""
var preview_msec := -1000
var hint_text := ""
var brief_lines: Array[String] = []
var font := SystemFont.new()
var bold := SystemFont.new()
var hits: Array[Dictionary] = []
var minimap := Rect2()
var hover := ""
var map_texture: ImageTexture
var map_background=preload("res://scripts/minimap_background.gd").new()
var map_clock := -1.0
var map_image:Image
var map_revision:=-1
var map_drawn_visible:Dictionary={}
var map_drawn_explored:=0
var blocked_regions: Array[Rect2] = []
var styles: Dictionary = {}
var portraits: Dictionary = {}
var minimap_road_cells: Dictionary = {}
# The HUD draws through three child canvases so the screen-fixed sidebar can keep
# its recorded commands between frames. World overlays (0) and the top layer (2:
# placement preview, toasts, guide, results) redraw every frame; the sidebar (1)
# redraws when the pointer or interaction state changes, else at 20 Hz for live
# values. queue_redraw() on the HUD itself still refreshes every layer at once.
const SIDEBAR_INTERVAL_MSEC := 50
class Layer extends Control:
	var hud:Control
	var part:=0
	func _draw()->void:hud.draw_layer(self,part)
var cv:CanvasItem=self
var layers:Array[Control]=[]
var layer_hits:Array=[[],[],[]]
var layer_blocked:Array=[[],[],[]]
var modal:=false
var sidebar_msec:=-100000
var sidebar_key:Array=[]
# Tests freeze or step the sidebar's refresh clock (msec); -1 follows real time.
var sidebar_clock_msec:=-1

func sidebar_clock() -> int:
	return Time.get_ticks_msec() if sidebar_clock_msec<0 else sidebar_clock_msec

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for part in 3:
		var layer:=Layer.new()
		layer.hud=self;layer.part=part
		layer.mouse_filter=Control.MOUSE_FILTER_IGNORE
		layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(layer)
		layers.append(layer)
	font.font_names = PackedStringArray(["Avenir Next","Helvetica Neue","Arial"])
	bold.font_names = font.font_names
	bold.font_weight = 700
	for kind in ["rifle","atgm","tank","drone","helo","boat","aa","harvester","engineer"]:
		var path:String="res://assets/ui/portraits/"+kind+".png"
		if ResourceLoader.exists(path):portraits[kind]=load(path)
		elif FileAccess.file_exists(path):
			var image:=Image.load_from_file(path)
			if image!=null:portraits[kind]=ImageTexture.create_from_image(image)

func text_at(text: String, p: Vector2, size_px: int = 14, color: Color = WHITE, strong: bool = false) -> void:
	cv.draw_string(bold if strong else font,p,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px,color)

func panel(r: Rect2, color: Color = PANEL) -> void:
	cv.draw_style_box(style(color),r)

func style(color: Color) -> StyleBoxFlat:
	if styles.has(color):return styles[color]
	var value := StyleBoxFlat.new()
	value.bg_color=color
	value.border_color=LINE
	value.set_border_width_all(1)
	styles[color]=value
	return value

func button(id: String, label: String, r: Rect2, enabled: bool = true, active: bool = false) -> void:
	var over := r.has_point(get_local_mouse_position())
	panel(r, Color("46513b") if active or (over and enabled) else Color("2c332c"))
	if active:cv.draw_rect(r,TEAL,false,1)
	text_at(label,r.position+Vector2(8,r.size.y/2+4),12,WHITE if enabled else MUTED,true)
	hits.append({"id":id,"rect":r,"enabled":enabled})

# Hit id under the pointer even when that button is disabled (queue removal).
func hit_id_at(p: Vector2) -> String:
	for target in hits:
		if target.rect.has_point(p):return target.id
	return ""

func action_at(p: Vector2) -> String:
	for target in hits:
		if target.rect.has_point(p):return target.id if target.enabled else "blocked"
	if battle.show_help or battle.sim.result != "":return "blocked"
	if minimap.has_point(p):return "minimap"
	for region in blocked_regions:
		if region.has_point(p):return "blocked"
	return ""

func console_panel(rect: Rect2) -> void:
	panel(rect,INK)
	# A narrow metal lip and recessed lower seam give the command console weight.
	cv.draw_line(rect.position+Vector2(2,2),rect.position+Vector2(rect.size.x-2,2),Color("626956"),1)
	cv.draw_line(rect.position+Vector2(2,rect.size.y-2),rect.end-Vector2(2,2),Color("101510"),1)
	blocked_regions.append(rect)

# Original schematic silhouettes remain readable without raster asset loads.
func equipment_icon(kind: String, center: Vector2, color: Color) -> void:
	if kind in ["rifle","atgm","engineer"]:
		cv.draw_circle(center+Vector2(-6,-8),4,color)
		cv.draw_line(center+Vector2(-6,-3),center+Vector2(-6,9),color,5)
		cv.draw_line(center+Vector2(-6,0),center+Vector2(12,-3),color,3)
		cv.draw_line(center+Vector2(-7,8),center+Vector2(-12,16),color,3)
		cv.draw_line(center+Vector2(-5,8),center+Vector2(1,16),color,3)
		if kind=="atgm":cv.draw_line(center+Vector2(-15,-5),center+Vector2(14,-5),color,5)
		elif kind=="engineer":
			# Entrenching spade over the shoulder marks the builder section.
			cv.draw_line(center+Vector2(4,16),center+Vector2(16,-12),color,2)
			cv.draw_rect(Rect2(center+Vector2(13,-19),Vector2(7,8)),color)
	elif kind in ["drone","helo"]:
		cv.draw_line(center+Vector2(-18,-5),center+Vector2(18,5),color,2)
		cv.draw_line(center+Vector2(-18,5),center+Vector2(18,-5),color,2)
		cv.draw_rect(Rect2(center-Vector2(5,8),Vector2(10,16)),color)
		if kind=="drone":
			for offset in [Vector2(-18,-5),Vector2(18,5),Vector2(-18,5),Vector2(18,-5)]:cv.draw_arc(center+offset,5,0,TAU,10,color,1)
	elif kind in ["hq","power","refinery","barracks","factory"]:
		cv.draw_rect(Rect2(center+Vector2(-18,-5),Vector2(36,20)),color)
		cv.draw_colored_polygon(PackedVector2Array([center+Vector2(-21,-5),center+Vector2(0,-17),center+Vector2(21,-5)]),color)
		cv.draw_rect(Rect2(center+Vector2(-4,5),Vector2(8,10)),INK)
	elif kind=="boat":
		cv.draw_colored_polygon(PackedVector2Array([center+Vector2(-21,-5),center+Vector2(21,-5),center+Vector2(12,9),center+Vector2(-15,9)]),color)
		cv.draw_rect(Rect2(center+Vector2(-5,-13),Vector2(12,8)),color)
	else:
		cv.draw_rect(Rect2(center+Vector2(-20,4),Vector2(40,8)),color)
		cv.draw_rect(Rect2(center+Vector2(-15,-4),Vector2(28,10)),color)
		cv.draw_rect(Rect2(center+Vector2(-5,-10),Vector2(14,7)),color)
		if kind=="harvester":
			cv.draw_rect(Rect2(center+Vector2(-15,-14),Vector2(16,12)),color)
			cv.draw_line(center+Vector2(12,5),center+Vector2(23,13),color,4)
		elif kind=="aa":
			cv.draw_line(center+Vector2(3,-8),center+Vector2(17,-17),color,3)
			cv.draw_line(center+Vector2(10,-8),center+Vector2(24,-17),color,3)
		else:cv.draw_line(center+Vector2(6,-8),center+Vector2(24,-11),color,3)

func _draw() -> void:
	sidebar_msec=-100000
	for layer in layers:layer.queue_redraw()

# Per rendered frame (battle._process): world and top layers always; the sidebar
# only when something it shows may have changed.
func frame() -> void:
	if layers.is_empty():return
	battlefield_ui.update(self)
	layers[0].queue_redraw()
	layers[2].queue_redraw()
	if sidebar_state()!=sidebar_key or sidebar_clock()-sidebar_msec>=SIDEBAR_INTERVAL_MSEC:layers[1].queue_redraw()

# Inputs that change the sidebar at once (hover, selection, modes, supply).
func sidebar_state() -> Array:
	var sim=battle.sim
	return [size,pointer(),battle.selected.hash(),battle.build_mode,battle.build_rotated,battle.attack_mode,battle.strike_mode,battle.paused,battle.show_help,sim.result,int(sim.credits)]

# Battle's dispatcher delegates only interface actions here. This layer never
# creates simulation orders, supply or tutorial success states.
func handle_action(action:String,_point:Vector2)->bool:
	return battlefield_ui.handle_action(self,action)

func observe_event(event:Dictionary)->void:
	if not is_instance_valid(battle):return
	battlefield_ui.observe_event(event,battle.sim)

func compact_layout()->bool:
	return size.y<800

func draw_layer(canvas:CanvasItem,part:int) -> void:
	if not is_instance_valid(battle):
		return
	var lap:=Time.get_ticks_usec()
	cv=canvas
	var own_hits:Array[Dictionary]=[]
	var own_blocked:Array[Rect2]=[]
	hits=own_hits
	blocked_regions=own_blocked
	if part==0:draw_world(battle.sim)
	elif part==1:
		hint_text=""
		sidebar_msec=sidebar_clock()
		sidebar_key=sidebar_state()
		draw_sidebar(battle.sim)
	else:
		modal=false
		draw_top(battle.sim)
	cv=self
	layer_hits[part]=own_hits
	layer_blocked[part]=own_blocked
	# Guide and results are modal: only their own buttons remain clickable.
	var combined_hits:Array[Dictionary]=[]
	var combined_blocked:Array[Rect2]=[]
	for i in 3:
		if not modal or i==2:combined_hits.append_array(layer_hits[i])
		combined_blocked.append_array(layer_blocked[i])
	hits=combined_hits
	blocked_regions=combined_blocked
	battle.flap("hud_layer%d" % part,lap)

func draw_world(sim) -> void:
	var w := size.x
	var h := size.y
	# Selected orders remain inspectable, including queued destinations.
	for id in battle.selected:
		var unit: Dictionary = sim.get_unit(id)
		if not sim.alive(unit):
			continue
		for member in unit.members:
			if member.hp<=0 or member.get("cover_phase","") not in ["SEEKING","SETTLING","SHELTERED"]:continue
			var shelter:Vector2=battle.screen_pos(member.cover_goal,0.25)
			cv.draw_arc(shelter,5,0,TAU,16,TEAL,1,true)
			if member.cover_phase=="SEEKING":
				var start:Vector2=battle.screen_pos(member.pos,0.25)
				for waypoint in member.cover_path:
					var next:Vector2=battle.screen_pos(waypoint,0.25)
					cv.draw_dashed_line(start,next,Color(0.68,0.76,0.48,0.7),1,4)
					start=next
		if not unit.maneuver.is_empty():
			var point:Vector2=battle.screen_pos(unit.maneuver.pos,0.3)
			cv.draw_dashed_line(battle.screen_pos(unit.pos,0.3),point,ORANGE,2,7)
			cv.draw_arc(point,7,0,TAU,20,ORANGE,2,true)
		var previous: Vector2 = battle.screen_pos(unit.pos,0.3)
		for order in unit.orders:
			var destination: Vector2 = battle.screen_pos(order.pos,0.3)
			cv.draw_dashed_line(previous,destination,Color(0.68,0.76,0.48,0.6),1.0,5.0)
			cv.draw_arc(destination,5,0,TAU,16,TEAL,1,true)
			previous=destination
	if battle.selected.size()==1:
		var unit: Dictionary = sim.get_unit(battle.selected[0])
		var radius:float=0.0
		if sim.alive(unit):radius=sim.definitions[unit.kind].sight if unit.kind in ["drone","observation_post"] else sim.definitions[unit.kind].range
		if radius>0:
			var points:=PackedVector2Array()
			for i in 65:
				points.append(battle.screen_pos(unit.pos+Vector2(cos(i*TAU/64),sin(i*TAU/64))*radius,0.2))
			cv.draw_polyline(points,Color(0.68,0.76,0.48,0.25),1,true)
	# In-world labels remain screen-sized and distinguish ownership with glyphs as well as color.
	for obj in sim.objectives:
		var p: Vector2 = battle.screen_pos(obj.pos,1)
		if battlefield_rect().has_point(p) and p.y>80:
			var label_width:float=clampf(bold.get_string_size(obj.name,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x+20,88,160)
			panel(Rect2(p+Vector2(-label_width/2,-22),Vector2(label_width,22)),INK)
			text_at(fit_bold(obj.name,label_width-20,11),p+Vector2(-label_width/2+10,-7),11,TEAL if obj.owner==0 else ORANGE,true)
	for u in sim.units:
		if not sim.alive(u) or not u.visible:
			continue
		var p: Vector2 = battle.screen_pos(battle.display_anchor(u), battle.label_height(u),true)
		if not battlefield_rect().has_point(p) or p.y<65:
			continue
		var selected: bool = battle.selected.has(u.id)
		if selected or u.hp<u.max_hp or u.team==1:
			cv.draw_rect(Rect2(p+Vector2(-15,0),Vector2(30,4)),INK)
			cv.draw_rect(Rect2(p+Vector2(-15,0),Vector2(30*maxf(0,u.hp/u.max_hp),4)),TEAL if u.team==0 else RED)
		# Inbound strike drones are tagged so the threat reads before it dives.
		if u.kind=="fpv_drone" and u.team!=0 and not selected and not BattlefieldInterface.tactical_icons(battle.camera_size):text_at("FPV",p+Vector2(-9,-7),9,RED,true)
		var status_row:=false
		var status_y:float=-40 if BattlefieldInterface.tactical_icons(battle.camera_size) else -20
		if selected:
			if not BattlefieldInterface.tactical_icons(battle.camera_size):text_at("FPV" if u.kind=="fpv_drone" else str(u.kind).to_upper(),p+Vector2(-15,-7),9,TEAL,true)
			status_row=true
			if u.suppression>0.6:
				text_at("PINNED",p+Vector2(-21,status_y),10,ORANGE,true)
			elif u.recovering:
				text_at("REPAIR +",p+Vector2(-23,status_y),10,TEAL,true)
			elif BUILDING_STATES.has(u.get("visual_state","")):
				var building_state:String=u.visual_state
				text_at(building_state,p+Vector2(-font.get_string_size(building_state,HORIZONTAL_ALIGNMENT_LEFT,-1,10).x/2,status_y),10,TEAL,true)
			else:status_row=false
		if BattlefieldInterface.tactical_icons(battle.camera_size) and (not u.get("structure",false) or BattlefieldInterface.ROLE_LABELS.has(u.kind)):
			battlefield_ui.draw_role(self,u,p)
		# Vehicle component damage (u.visible already hides unseen enemies); two
		# tags at most in the world, the full list is in the selected-unit panel.
		if u.has("crew"):
			var tags:=damage_tags(sim,u)
			if not tags.is_empty():
				var tag:String=" · ".join(tags.slice(0,2))
				var tag_y:float=(-56 if status_row else -28) if BattlefieldInterface.tactical_icons(battle.camera_size) else (-32 if status_row else -20)
				text_at(tag,p+Vector2(-font.get_string_size(tag,HORIZONTAL_ALIGNMENT_LEFT,-1,9).x/2,tag_y),9,ORANGE if u.team==0 else RED,true)
		if u.team==0 and u.suppression>0.1:
			cv.draw_rect(Rect2(p+Vector2(-15,6),Vector2(30*u.suppression,2)),ORANGE)
		if u.team==0 and float(u.get("build_left",0.0))>0:
			var progress:=build_progress(sim,u)
			var condition:=site_condition(sim,u)
			cv.draw_rect(Rect2(p+Vector2(-15,9),Vector2(30,3)),INK)
			cv.draw_rect(Rect2(p+Vector2(-15,9),Vector2(30*progress,3)),TEAL if condition=="building" else ORANGE)
			if SITE_LABELS.has(condition):
				var label:String=SITE_LABELS[condition]
				text_at(label,p+Vector2(-font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,10).x/2,25),10,ORANGE,true)
	# Abandoned hulls (dead, so skipped above) can be re-crewed or captured;
	# an enemy hull is tagged only while its ground is in sight.
	for wreck in sim.VehicleDamage.wrecks(sim):
		var hull:Dictionary=sim.get_unit(int(wreck.id))
		if not sim.VehicleDamage.recrewable(sim,hull):continue
		if hull.team!=0 and not sim.visible_cells.has(sim.terrain.cell(hull.pos)):continue
		var p:Vector2=battle.screen_pos(hull.pos,1.6)
		if not battlefield_rect().has_point(p) or p.y<65:continue
		text_at("ABANDONED",p+Vector2(-font.get_string_size("ABANDONED",HORIZONTAL_ALIGNMENT_LEFT,-1,9).x/2,0),9,MUTED,true)
	if battle.dragging and battle.drag_start.distance_to(get_local_mouse_position())>5:
		var rect := Rect2(battle.drag_start,get_local_mouse_position()-battle.drag_start).abs()
		cv.draw_rect(rect,Color(0.68,0.76,0.48,0.09))
		cv.draw_rect(rect,TEAL,false,1)
	# A compact field console keeps the central battle unobstructed.
	console_panel(Rect2(0,0,w,42))
	var game_title:=str(ProjectSettings.get_setting("application/config/name")).to_upper()
	var scenario_x:=32.0+bold.get_string_size(game_title,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x
	text_at(game_title,Vector2(16,27),16,WHITE,true)
	text_at(fit_bold(sim.scenario.name.to_upper(),maxf(0,w-814-scenario_x),12),Vector2(scenario_x,27),12,MUTED,true)
	text_at("SUPPLY  %04d" % int(sim.credits),Vector2(w-638,27),15,TEAL,true)
	text_at("%02d:%02d" % [int(sim.time)/60,int(sim.time)%60],Vector2(w-470,27),13,WHITE)
	button("region","REGION",Rect2(w-411,7,72,28))
	button("settings","SETTINGS",Rect2(w-333,7,72,28))
	button("pause","RESUME" if battle.paused else "PAUSE",Rect2(w-255,7,80,28))
	button("help","GUIDE",Rect2(w-169,7,76,28))
	button("restart","RESTART",Rect2(w-87,7,78,28))
	if not sim.classic.is_empty():
		var power:Vector2=sim.Classic.power(sim,0)
		text_at("POWER %d / %d" % [power.y,power.x],Vector2(w-798,27),12,ORANGE if power.y>power.x else MUTED)
	else:
		if not sim.field_ops.is_empty():text_at("INCOME +%s/s" % String.num(float(sim.field_ops.income_rate)+sim.FieldOps.OperationRules.income_bonus(sim)),Vector2(w-768,27),12,MUTED,true)
		var badges:=objective_badges(sim)
		for i in badges.size():
			var obj:Dictionary=sim.objectives[i]
			var badge:Rect2=badges[i]
			console_panel(badge)
			hits.append({"id":"mission:objective:%d" % i,"rect":badge,"enabled":true})
			var state_text:String="CONTESTED" if obj.get("contested",false) else ("SECURED" if obj.owner==0 else "%d%%" % int(obj.progress/sim.capture_time*100))
			var state_width:=font.get_string_size(state_text,HORIZONTAL_ALIGNMENT_LEFT,-1,10).x
			text_at(fit_bold(obj.name,badge.size.x-state_width-24,11),badge.position+Vector2(8,18),11,TEAL if obj.owner==0 else ORANGE,true)
			text_at(state_text,Vector2(badge.end.x-state_width-8,badge.position.y+18),10,MUTED)
	if sim.scenario.get("autonomy",false):
		text_at("%s  ·  Sight %d%%" % [sim.weather.label,roundi(sim.weather.sight_scale*100)],Vector2(w-530,65),11,WHITE)
	# The sector hold countdown sits under the badge row so it never covers a badge.
	if sim.terrain.compiled_map and not sim.field_ops.is_empty():battlefield_ui.draw_mission(self)
	elif sim.score_hold>0:
		console_panel(Rect2(12,86,124,24))
		text_at("HOLD  %02ds" % ceili(float(sim.scenario.hold)-sim.score_hold),Vector2(22,103),13,TEAL,true)

func draw_top(sim) -> void:
	var w := size.x
	if battle.build_mode!="" and not sim.field_ops.is_empty():draw_field_preview(sim)
	elif battle.build_mode!="":
		var world:Vector2=battle.world_pos(get_local_mouse_position())
		cv.draw_arc(battle.screen_pos(world),28,0,TAU,32,TEAL if sim.Classic.can_build(sim,battle.build_mode,0,world) else RED,2,true)
	# When the badge row reaches the centre, pause and toast banners step down one row.
	var pause_rect:=Rect2(w/2-90,50,180,30)
	var badge_row:Array=objective_badges(sim) if sim.classic.is_empty() else []
	if not badge_row.is_empty() and badge_row[-1].intersects(pause_rect.grow(6)):pause_rect.position.y=86
	var toast_y:=90.0 if pause_rect.position.y<86 else 122.0
	if sim.terrain.compiled_map and not sim.field_ops.is_empty():toast_y=maxf(toast_y,172)
	if battle.strike_mode:draw_strike_reticle(sim)
	# The attack-move / strike mode banner first, then the notice stack under it.
	if battle.attack_mode or battle.strike_mode:
		var mode:String="ATTACK-MOVE · Choose destination · Esc cancels" if battle.attack_mode else "FPV STRIKE · Click a seen enemy · vehicles first · Esc cancels"
		var width:=font.get_string_size(mode,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x+28
		console_panel(Rect2(w/2-width/2,toast_y,width,30))
		text_at(mode,Vector2(w/2-width/2+14,toast_y+20),13,ORANGE)
		toast_y+=34
	draw_notices(toast_y)
	if battle.paused and not battle.show_help and sim.result=="":
		console_panel(pause_rect)
		text_at("TACTICAL PAUSE",pause_rect.position+Vector2(21,20),13,TEAL,true)
	if battle.cursor_hint!="" and not battle.show_help and sim.result=="":draw_cursor_hint()
	if battle.notices.cursor_left>0 and not battle.show_help and sim.result=="":draw_cursor_notice()
	if not battle.show_help and sim.result=="" and not battlefield_ui.menu_open(battle):
		battlefield_ui.draw_roster(self)
		battlefield_ui.draw_tutorial(self)
		battlefield_ui.draw_enemy_hover(self)
	if battle.show_help:draw_guide()
	if sim.result!="":draw_result()

# Strike footprint at the pointer: the radius in which seen enemies are assigned.
func draw_strike_reticle(sim) -> void:
	var mouse:=pointer()
	if action_at(mouse)!="":return
	var world:Vector2=battle.world_pos(mouse)
	var center:Vector2=battle.screen_pos(world)
	var radius:float=center.distance_to(battle.screen_pos(world+Vector2(sim.FieldOps.SWARM_TARGET_RADIUS,0)))
	var color:Color=ORANGE if sim.FieldOps.strike_victims(sim,world).is_empty() else RED
	cv.draw_arc(center,radius,0,TAU,48,color,2,true)
	cv.draw_line(center-Vector2(10,0),center+Vector2(10,0),color,1)
	cv.draw_line(center-Vector2(0,10),center+Vector2(0,10),color,1)

# One badge per objective, sharing the space left of the weather readout; legacy
# two-objective maps keep the original 220 px badges at 228 px spacing.
func objective_badges(sim) -> Array[Rect2]:
	var result:Array[Rect2]=[]
	var count:int=sim.objectives.size()
	if count==0:return result
	var right:float=size.x-(540.0 if sim.scenario.get("autonomy",false) else 280.0)
	var width:=minf(220.0,(right-12.0-8.0*(count-1))/count)
	for i in count:result.append(Rect2(12+i*(width+8.0),52,width,27))
	return result

func fit_bold(value:String,width:float,pixel_size:int) -> String:
	var result:=value
	while bold.get_string_size(result,HORIZONTAL_ALIGNMENT_LEFT,-1,pixel_size).x>width and result.length()>4:
		result=result.left(result.length()-2)+"…"
	return result

func battlefield_rect() -> Rect2:
	return Rect2(0,42,size.x-268,size.y-42)

func build_progress(sim,structure:Dictionary) -> float:
	var total:=float(sim.definitions[structure.kind].get("build_seconds",1.0))
	return clampf(1.0-float(structure.get("build_left",0.0))/maxf(total,0.01),0,1)

# Derived from the same gates FieldOps.tick uses: an assigned living engineer
# anchored within 0.8 m of the work point, unsuppressed, with a living
# unsuppressed member within 3 m. Read-only; never changes the site.
func site_condition(sim,site:Dictionary) -> String:
	if float(site.get("build_left",0.0))<=0:return "complete"
	if site.get("build_paused",false) and sim.alive(sim.get_unit(site.get("queued_for",-1))):return "queued"
	if site.get("build_paused",false):return "paused"
	var engineer:Dictionary=sim.get_unit(site.get("engineer_id",-1))
	if not sim.alive(engineer):return "lost"
	var work:Vector2=site.get("work_point",site.pos)
	if engineer.pos.distance_to(work)>=0.8:return "en_route" if not engineer.orders.is_empty() else "off_site"
	if engineer.suppression>0.6:return "pinned"
	var near:Array=engineer.members.filter(func(m):return m.hp>0 and m.pos.distance_to(work)<3.0)
	if near.is_empty():return "regrouping"
	if near.all(func(m):return m.suppression>0.6):return "pinned"
	return "building"

func builder_status(sim,site:Dictionary) -> String:
	var condition:=site_condition(sim,site)
	if condition=="complete":return FIELD_EFFECTS.get(site.kind,"Operational")
	return SITE_STATUS[condition]

func engineer_status(sim,engineer:Dictionary) -> String:
	for site in sim.units:
		if sim.alive(site) and site.get("engineer_id",-1)==engineer.id and float(site.get("build_left",0.0))>0 and not site.get("build_paused",false):
			return "Assigned %s · orders pause it" % FIELD_LABELS.get(site.kind,"SITE")
	return "Ready · choose field works above"

# Empty when RESUME can run; otherwise the short reason it is disabled.
func resume_reason(sim,site:Dictionary) -> String:
	var condition:=site_condition(sim,site)
	if condition not in ["paused","lost","off_site","queued"]:return "Builder already assigned"
	if sim.FieldOps.available_engineer(sim,site.id)<0 and not sim.alive(sim.get_unit(site.get("queued_for",site.get("last_engineer_id",-1)))):return "No free engineer · buy or release one"
	return ""

func cancel_refund(sim,site:Dictionary) -> int:
	var definition:Dictionary=sim.definitions[site.kind]
	return floori(float(definition.cost)*float(site.get("build_left",0.0))/float(definition.build_seconds))

func cancel_label(refund:int) -> String:
	return "CANCEL +%d" % refund

func pointer() -> Vector2:
	return battle.pointer if battle.pointer.x>=0 else get_local_mouse_position()

# Full-length tooltip left of the sidebar; hint_text records it for tests.
func sidebar_hint(text:String,y:float) -> void:
	hint_text=text
	var x:=size.x-268
	var width:=minf(560,font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x+24)
	console_panel(Rect2(x-width-10,y,width,32))
	text_at(fit_text(text,width-20,12),Vector2(x-width,y+21),12,WHITE)

# Mirrors the cheap FieldOps.proposal preconditions so buttons explain themselves
# without per-frame route searches; site checks happen during placement.
func field_block_reason(sim,kind:String,engineer_id:int) -> String:
	if engineer_id<0:return "Select an engineer section to build"
	var cost:=float(sim.definitions[kind].cost)
	if sim.credits<cost:return "Need %d more supply" % ceili(cost-sim.credits)
	if not sim.FieldOps.engineer_available(sim,sim.get_unit(engineer_id)):return "Engineer assigned to another site"
	return ""

# Greedy word wrap at the given width; used for authored briefs in the modal.
func wrap_text(value:String,width:float,pixel_size:int) -> Array[String]:
	var lines:Array[String]=[]
	var line:=""
	for word in value.split(" ",false):
		var candidate:String=word if line=="" else line+" "+word
		if line!="" and font.get_string_size(candidate,HORIZONTAL_ALIGNMENT_LEFT,-1,pixel_size).x>width:
			lines.append(line)
			line=word
		else:line=candidate
	if line!="":lines.append(line)
	return lines

func draw_field_preview(sim) -> void:
	var kind:String=battle.build_mode
	# The last routed pointer event also drives placement in headless input tests.
	var mouse:Vector2=battle.pointer if battle.pointer.x>=0 else get_local_mouse_position()
	var world:Vector2=battle.world_pos(mouse)
	var engineer:int=battle.selected_engineer()
	# Proposal validation includes a route search, so refresh it at most five times a second.
	var key:="%s:%d:%d:%d:%d:%s" % [kind,engineer,roundi(world.x*4),roundi(world.y*4),int(sim.credits),battle.build_rotated]
	if Time.get_ticks_msec()-preview_msec>=200:
		preview_key=key
		preview_msec=Time.get_ticks_msec()
		preview_reason=sim.FieldOps.build_reason(sim,kind,world,engineer,battle.build_rotated)
	var checked:=key==preview_key
	var color:=MUTED if not checked else (TEAL if preview_reason=="" else RED)
	if battle.build_drag and sim.FieldOps.draggable(kind):
		draw_drag_preview(sim,kind,world,mouse)
		return
	var rect:Rect2=sim.FieldOps.footprint(sim,kind,world,battle.build_rotated)
	var outline:=PackedVector2Array()
	for corner in [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y),rect.position]:outline.append(battle.screen_pos(corner,0.1))
	cv.draw_colored_polygon(outline.slice(0,4),Color(color,0.18))
	cv.draw_polyline(outline,color,2,true)
	var choice:Dictionary=battle.field_choice(kind)
	var label:String="%s · %d supply · %ds" % [choice.get("name",kind),int(choice.get("cost",0)),int(choice.get("build_seconds",0))]
	var detail:String="Checking site…" if not checked else ("Click to mark site · Esc cancels" if preview_reason=="" else preview_reason)
	if kind in sim.FieldOps.ROTATABLE:detail+=" · T rotates"
	var width:=maxf(font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x,font.get_string_size(detail,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x)+20
	var at:=Vector2(clampf(mouse.x+18,0,battlefield_rect().end.x-width),clampf(mouse.y+14,48,size.y-44))
	panel(Rect2(at,Vector2(width,40)),INK)
	text_at(label,at+Vector2(10,16),11,WHITE,true)
	text_at(detail,at+Vector2(10,32),11,color)

# Dragged line/area: every planned segment outlined, with count and total cost.
func draw_drag_preview(sim,kind:String,world:Vector2,mouse:Vector2) -> void:
	var plan:Array=sim.FieldOps.drag_plan(sim,kind,battle.build_drag_start,world)
	var cost:int=sim.FieldOps.drag_cost(sim,kind,plan)
	var affordable:bool=sim.credits>=cost
	for segment in plan:
		var rect:Rect2=sim.FieldOps.footprint(sim,kind,segment.pos,segment.rotated and kind in sim.FieldOps.ROTATABLE)
		var clear:bool=sim.FieldOps.site_ground_clear(sim,kind,segment.pos,segment.rotated and kind in sim.FieldOps.ROTATABLE)
		var color:=TEAL if clear and affordable else RED
		var outline:=PackedVector2Array()
		for corner in [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y),rect.position]:outline.append(battle.screen_pos(corner,0.1))
		cv.draw_colored_polygon(outline.slice(0,4),Color(color,0.18))
		cv.draw_polyline(outline,color,2,true)
	var label:String="%d × %s · %d supply" % [plan.size(),battle.field_choice(kind).get("name",kind),cost]
	var detail:String="Release to mark the line · red segments are skipped" if affordable else "Need %d more supply" % (cost-int(sim.credits))
	var width:=maxf(font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x,font.get_string_size(detail,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x)+20
	var at:=Vector2(clampf(mouse.x+18,0,battlefield_rect().end.x-width),clampf(mouse.y+14,48,size.y-44))
	panel(Rect2(at,Vector2(width,40)),INK)
	text_at(label,at+Vector2(10,16),11,WHITE,true)
	text_at(detail,at+Vector2(10,32),11,TEAL if affordable else RED)

func fit_text(value:String,width:float,pixel_size:int) -> String:
	var result:=value
	while font.get_string_size(result,HORIZONTAL_ALIGNMENT_LEFT,-1,pixel_size).x>width and result.length()>4:
		result=result.left(result.length()-4)+"…"
	return result

func draw_sidebar(sim) -> void:
	var x:=size.x-268
	var height:=size.y
	console_panel(Rect2(x,42,268,height-42))
	# Machined outer rail, recessed instruments, and fasteners form one console.
	cv.draw_rect(Rect2(x,42,5,height-42),Color("424a45"))
	cv.draw_line(Vector2(x+5,42),Vector2(x+5,height),Color("858a77"),1)
	for y in [50.0,height-9]:
		for bolt_x in [x+12,size.x-9]:
			cv.draw_circle(Vector2(bolt_x,y),2,LINE)
			cv.draw_line(Vector2(bolt_x-1,y),Vector2(bolt_x+1,y),INK,1)
	text_at("TACTICAL DISPLAY",Vector2(x+19,65),11,MUTED,true)
	text_at("N ↑",Vector2(size.x-45,65),11,WHITE,true)
	var compact:bool=compact_layout() and not sim.field_ops.is_empty()
	minimap=Rect2(x+19,68 if compact else 74,230,100 if compact else 145)
	draw_minimap(sim)
	var production_top:float=224 if compact else 274
	cv.draw_line(Vector2(x+18,production_top-31),Vector2(size.x-18,production_top-31),LINE,1)
	text_at("PRODUCTION" if not sim.classic.is_empty() else "REINFORCEMENTS",Vector2(x+19,production_top-11),12,WHITE,true)
	var types:Array=["rifle","atgm","tank","drone","helo","boat","aa"]
	if not sim.classic.is_empty():types.append("harvester")
	elif not sim.field_ops.is_empty():types=sim.FieldOps.purchase_choices(sim)
	var names:Array=types.map(func(kind):return UNIT_NAMES.get(kind,str(sim.definitions[kind].name)))
	for i in types.size():
		var kind:String=types[i]
		var definition:Dictionary=sim.definitions[kind]
		var field_tiles:bool=not sim.field_ops.is_empty()
		var row_height:float=44 if compact else (52 if field_tiles else 67)
		var tile:=Rect2(x+18+(i%2)*119,production_top+(i/2)*row_height,113,row_height-4 if field_tiles else 61)
		var field:bool=not sim.field_ops.is_empty()
		var enabled:bool=sim.credits>=float(definition.cost) and (sim.recruit_clock<=0 or field)
		if field:enabled=enabled and sim.FieldOps.queue(sim).size()<sim.FieldOps.QUEUE_LIMIT
		if not sim.classic.is_empty():enabled=enabled and sim.Classic.production_reason(sim,kind,0)==""
		button("buy:"+kind,"",tile,enabled)
		cv.draw_rect(Rect2(tile.position+Vector2(2,2),Vector2(tile.size.x-4,minf(38,tile.size.y-12))),Color("151b19"))
		if portraits.has(kind):
			var portrait:Texture2D=portraits[kind]
			var portrait_height:=22.0 if compact else (28.0 if tile.size.y<55 else 38.0)
			var portrait_width:float=portrait_height*portrait.get_width()/portrait.get_height()
			cv.draw_texture_rect(portrait,Rect2(tile.position+Vector2((tile.size.x-portrait_width)*0.5,2),Vector2(portrait_width,portrait_height)),false,Color(1,1,1,1) if enabled else Color(0.65,0.68,0.63,1))
		else:
			cv.draw_set_transform(tile.position+Vector2(40,21),0,Vector2(1.25,1.25))
			equipment_icon(kind,Vector2.ZERO,WHITE if enabled else MUTED)
			cv.draw_set_transform(Vector2.ZERO)
		text_at(str(int(definition.cost)),tile.position+Vector2(79,16),11,TEAL if enabled else MUTED,true)
		text_at(names[i],tile.position+Vector2(5,tile.size.y-6),10,WHITE if enabled else MUTED,true)
		if not enabled:cv.draw_circle(tile.position+Vector2(102,33),2,ORANGE)
		if field:draw_queue_badge(sim,kind,tile)
		if tile.has_point(get_local_mouse_position()) and not battle.show_help:
			var hint:String=definition.role
			if not sim.classic.is_empty() and sim.Classic.production_reason(sim,kind,0)!="":hint=sim.Classic.production_reason(sim,kind,0)
			elif sim.credits<float(definition.cost):hint="Need %d more supply" % ceili(float(definition.cost)-sim.credits)
			elif field:hint=definition.role+" · click to queue · right-click removes one"
			elif sim.recruit_clock>0:hint="Deployment ready in %.1fs" % sim.recruit_clock
			var hint_width:=minf(520,font.get_string_size(hint,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x+24)
			console_panel(Rect2(x-hint_width-10,tile.position.y,hint_width,32))
			text_at(fit_text(hint,hint_width-20,12),Vector2(x-hint_width,tile.position.y+21),12,WHITE)
	if not sim.field_ops.is_empty():draw_strike_tile(sim,x)
	if not sim.classic.is_empty():
		text_at("CONSTRUCTION",Vector2(x+19,559),11,MUTED,true)
		for i in 4:
			var kind:String=sim.Classic.BUILDINGS[i]
			button("build:"+kind,kind.to_upper()+" "+str(int(sim.definitions[kind].cost)),Rect2(x+18+(i%2)*119,568+(i/2)*28,113,25))
	elif not sim.field_ops.is_empty():draw_field_works(sim,x)
	var units:Array=[]
	for id in battle.selected:
		var unit:Dictionary=sim.get_unit(id)
		if sim.alive(unit):units.append(unit)
	var y:=height-174 if compact else maxf(632,height-174)
	cv.draw_line(Vector2(x+18,y-10),Vector2(size.x-18,y-10),LINE,1)
	var heading:="SELECT YOUR FORCE"
	var detail:="Drag a box or click a section."
	var status:="Right-click to move or engage."
	if units.size()==1:
		var unit:Dictionary=units[0]
		heading=sim.definitions[unit.kind].name.to_upper()
		detail="%d / %d HP · %s" % [maxi(0,int(unit.hp)),int(unit.max_hp),unit.get("visual_state",unit.state)]
		status=unit.reason if sim.scenario.get("autonomy",false) else sim.terrain.surface_name(unit.pos)
		if sim.comms_blocked(unit):status="LINK LOST · Last objective"
		var seekers:=0
		var sheltered:=0
		for member in unit.members:
			if member.hp<=0:continue
			if member.get("cover_phase","")=="SEEKING":seekers+=1
			if member.get("cover_phase","")=="SHELTERED":sheltered+=1
		if seekers>0:status="%d seeking cover · Partners holding" % seekers
		elif sheltered>0:status="%d sheltered · Watching approach" % sheltered
		var preparing:int=unit.members.filter(func(member):return member.hp>0 and float(member.get("reload_until",0.0))>sim.time).size()
		if preparing>0 and seekers==0:status="%d reloading · %d ready" % [preparing,int(sim.Infantry.strength(unit,sim.time).ready_members)]
		if unit.get("fire_policy","free")=="hold":
			var assignment:Dictionary=unit.get("assignment",{})
			if not sim.Actions.engagement_allowed(unit,int(assignment.get("target",-1)),str(assignment.get("mode","")),assignment.get("pos",Vector2.INF)):status="Holding fire"
		if unit.hold_command and unit.reason=="Hold position · under pressure":status=unit.reason
		if sim.definitions[unit.kind].get("strike",false):status="Autonomous strike munition · no orders"
		if unit.get("structure",false) and not sim.field_ops.is_empty():
			detail="%d / %d HP · %s" % [maxi(0,int(unit.hp)),int(unit.max_hp),"UNFINISHED" if float(unit.get("build_left",0.0))>0 else "COMPLETE"]
			status=builder_status(sim,unit)
		elif battle.is_engineer(unit):status=engineer_status(sim,unit)
	elif units.size()>1:
		heading="%d SECTIONS SELECTED" % units.size()
		detail="Combined force · Shared objective"
		status="Roles and terrain guide the approach."
	text_at(fit_text(heading,234,16),Vector2(x+18,y+10),16,WHITE,true)
	text_at(fit_text(detail,234,12),Vector2(x+18,y+31),12,MUTED)
	var alert:bool=units.size()==1 and units[0].get("structure",false) and site_condition(sim,units[0]) in ["paused","lost","off_site","pinned"]
	text_at(fit_text(status,234,11),Vector2(x+18,y+50),11,ORANGE if alert else TEAL)
	# Strike drones fly their own attack and ignore orders, like fixed works.
	var mobile:bool=units.any(func(unit):return not battle.is_structure(unit) and not sim.definitions[unit.kind].get("strike",false))
	button("attack","A  ATTACK-MOVE",Rect2(x+18,y+62,232,31),mobile,battle.attack_mode)
	button("stop","S  HOLD",Rect2(x+18,y+99,113,29),mobile)
	button("retreat","R  RETREAT",Rect2(x+137,y+99,113,29),mobile)
	var tags:=damage_tags(sim,units[0]) if units.size()==1 else PackedStringArray()
	if units.size()==1 and units[0].get("structure",false) and not sim.field_ops.is_empty():
		var site:Dictionary=units[0]
		var unfinished:=float(site.get("build_left",0.0))>0
		var definition:Dictionary=sim.definitions[site.kind]
		if not unfinished:text_at("OPERATIONAL",Vector2(x+18,y+147),10,WHITE)
		else:
			# Progress, RESUME and CANCEL share one row; refunds stay visible on the button.
			text_at("%d%% · %.1fs" % [roundi(build_progress(sim,site)*100),float(site.build_left)],Vector2(x+18,y+144),10,WHITE)
			cv.draw_rect(Rect2(x+18,y+149,68,3),INK)
			cv.draw_rect(Rect2(x+18,y+149,68*build_progress(sim,site),3),TEAL if site_condition(sim,site)=="building" else ORANGE)
			var blocked:=resume_reason(sim,site)
			var resume_rect:=Rect2(x+90,y+132,70,23)
			button("resume_build","RESUME",resume_rect,blocked=="")
			var refund:=cancel_refund(sim,site)
			var cancel_rect:=Rect2(x+164,y+132,86,23)
			button("cancel_build","",cancel_rect,true)
			text_at(cancel_label(refund),cancel_rect.position+Vector2(7,16),10,WHITE,true)
			var mouse:=pointer()
			if resume_rect.has_point(mouse) and not battle.show_help:
				sidebar_hint(blocked if blocked!="" else "Resume with nearest free engineer · no charge · %d%% kept" % roundi(build_progress(sim,site)*100),y+98)
			elif cancel_rect.has_point(mouse) and not battle.show_help:
				sidebar_hint("Cancel site · refund %d of %d supply · built share is lost" % [refund,int(definition.cost)],y+98)
	elif units.size()==1 and sim.definitions[units[0].kind].get("structure",false):
		var queue:Array=units[0].get("queue",[])
		text_at("QUEUE EMPTY" if queue.is_empty() else "%s · %.0fs (%d)" % [queue[0].kind.to_upper(),queue[0].left,queue.size()],Vector2(x+18,y+147),10,WHITE)
		button("cancel_queue","CANCEL",Rect2(x+179,y+132,71,23),not queue.is_empty())
	elif not tags.is_empty():text_at(fit_text(" · ".join(tags),234,10),Vector2(x+18,y+151),10,ORANGE,true)
	else:text_at("SHIFT queue · F focus · Wheel zoom",Vector2(x+18,y+151),10,MUTED)

# Component damage the player must read (vehicle_damage.gd state), most
# important first. Infantry wounds are deliberately never labelled.
static func damage_tags(sim,u:Dictionary) -> PackedStringArray:
	var tags:=PackedStringArray()
	# Javelin teams: missiles carried (simulation.gd missile load).
	if u.kind=="atgm":
		var left:int=sim.missiles_left(u)
		tags.append("MISSILES %d/%d" % [left,int(sim.definitions.atgm.missiles)] if left>0 else "NO MISSILES · RESUPPLY")
	if not u.has("crew"):return tags
	if u.get("abandoned",false):tags.append("ABANDONED")
	if u.has("crash"):tags.append("GOING DOWN")
	if u.get("mobility_kill",false):tags.append("DAMAGED" if sim.definitions[u.kind].domain=="air" else "IMMOBILISED")
	if u.get("firepower_kill",false):tags.append("GUN OUT")
	if float(u.get("fire_until",-1.0))>sim.time:tags.append("ON FIRE")
	if float(u.get("flood_rate",0.0))>0.0:tags.append("FLOODING")
	if int(u.crew)<int(u.crew_full):tags.append("CREW %d/%d" % [int(u.crew),int(u.crew_full)])
	return tags

# Queued count badge plus a deployment timer on the unit at the head of the queue.
func draw_queue_badge(sim,kind:String,tile:Rect2) -> void:
	var count:int=sim.FieldOps.queued(sim,kind)
	if count<=0:return
	var label:="×%d" % count
	var badge:=Rect2(tile.position+Vector2(4,4),Vector2(font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x+10,16))
	cv.draw_rect(badge,Color(0.05,0.08,0.07,0.85))
	cv.draw_rect(badge,TEAL,false,1)
	text_at(label,badge.position+Vector2(5,12),11,TEAL,true)
	var items:Array=sim.FieldOps.queue(sim)
	if not items.is_empty() and items[0]==kind:
		var progress:=clampf(1.0-sim.recruit_clock/sim.FieldOps.DEPLOY_INTERVAL,0.0,1.0)
		cv.draw_rect(Rect2(tile.position+Vector2(2,tile.size.y-3),Vector2((tile.size.x-4)*progress,2)),TEAL)

# FPV strike shares the REINFORCEMENTS header row; a bar and countdown show the cooldown.
func draw_strike_tile(sim,x:float) -> void:
	var reason:String=sim.FieldOps.strike_reason(sim)
	var tile:=Rect2(x+145,198 if compact_layout() else 248,105,22)
	var cooling:float=sim.FieldOps.strike_ready_in(sim)
	button("strike:fpv","",tile,reason=="",battle.strike_mode)
	var label:="FPV STRIKE" if cooling<=0 else "FPV %ds" % ceili(cooling)
	text_at(label,tile.position+Vector2(6,15),10,WHITE if reason=="" else MUTED,true)
	var price:=str(sim.FieldOps.PLAYER_STRIKE_COST)
	text_at(price,tile.position+Vector2(tile.size.x-6-font.get_string_size(price,HORIZONTAL_ALIGNMENT_LEFT,-1,10).x,15),10,TEAL if reason=="" else MUTED,true)
	if cooling>0:
		var progress:=clampf(1.0-cooling/sim.FieldOps.PLAYER_STRIKE_COOLDOWN,0.0,1.0)
		cv.draw_rect(Rect2(tile.position+Vector2(2,tile.size.y-3),Vector2((tile.size.x-4)*progress,2)),ORANGE)
	if tile.has_point(pointer()) and not battle.show_help:
		var hint:="%d FPV drones from the forward base · strike seen enemies at a clicked point · %ds cooldown" % [sim.FieldOps.PLAYER_STRIKE_COUNT,int(sim.FieldOps.PLAYER_STRIKE_COOLDOWN)]
		sidebar_hint(reason+" · "+hint if reason!="" else hint,tile.position.y)

func draw_field_works(sim,x:float) -> void:
	var engineer:int=battle.selected_engineer()
	# Fourteen works in a three-column grid remain above the selection divider,
	# including the compact 720 px layout.
	var top:float=415 if compact_layout() else 499
	text_at("FIELD WORKS",Vector2(x+19,top-5),11,MUTED,true)
	text_at("ENGINEER SELECTED" if engineer>=0 else "SELECT ENGINEERS",Vector2(x+130,top-5),10,TEAL if engineer>=0 else ORANGE,true)
	var kinds:Array=battle.field_choices().keys()
	for i in kinds.size():
		var kind:String=kinds[i]
		var choice:Dictionary=battle.field_choice(kind)
		var reason:=field_block_reason(sim,kind,engineer)
		var tile:=Rect2(x+18+(i%3)*79,top+(i/3)*24,75,22)
		button("build:"+kind,"",tile,reason=="",battle.build_mode==kind)
		text_at(FIELD_LABELS.get(kind,kind.to_upper()),tile.position+Vector2(5,14),9,WHITE if reason=="" else MUTED,true)
		var price:=str(int(choice.get("cost",0)))
		text_at(price,tile.position+Vector2(tile.size.x-5-font.get_string_size(price,HORIZONTAL_ALIGNMENT_LEFT,-1,9).x,14),9,TEAL if reason=="" else MUTED)
		if tile.has_point(pointer()) and not battle.show_help:
			var footprint:Array=choice.get("footprint",[0,0])
			var hint:="%s · %s m · %d supply · %ds engineer work" % [FIELD_FUNCTIONS.get(kind,""),"%s×%s" % [String.num(float(footprint[0])),String.num(float(footprint[1]))],int(choice.get("cost",0)),int(choice.get("build_seconds",0))]
			if reason!="":hint=reason+" · "+hint
			sidebar_hint(hint,tile.position.y)

func map_color(sim,base:PackedColorArray,id:Vector2i,columns:int) -> Color:
	var c:Color=base[id.x+id.y*columns]
	if not sim.explored.has(id): c=Color("132630")
	elif not sim.visible_cells.has(id): c=c.darkened(0.5)
	return c

func update_map_image(sim) -> void:
	map_clock=sim.time
	var base:PackedColorArray=map_background.colors_for(sim.terrain,minimap_road_cells)
	var columns:int=sim.terrain.fog_grid_size.x
	var changed:=false
	# Repaint everything only when the background changed; otherwise only the
	# cells entering or leaving sight and newly explored ones (the tail of the
	# append-only explored keys) change colour.
	if map_texture==null or map_image==null or map_revision!=map_background.rebuilds or sim.explored.size()<map_drawn_explored:
		map_revision=map_background.rebuilds
		map_image=Image.create(columns,sim.terrain.fog_grid_size.y,false,Image.FORMAT_RGB8)
		for x in columns:
			for y in sim.terrain.fog_grid_size.y:
				map_image.set_pixel(x,y,map_color(sim,base,Vector2i(x,y),columns))
		map_drawn_visible=sim.visible_cells.duplicate()
		map_drawn_explored=sim.explored.size()
		changed=true
	else:
		if sim.explored.size()>map_drawn_explored:
			var keys:Array=sim.explored.keys()
			for i in range(map_drawn_explored,keys.size()):map_image.set_pixelv(keys[i],map_color(sim,base,keys[i],columns))
			map_drawn_explored=keys.size()
			changed=true
		for id in map_drawn_visible:
			if not sim.visible_cells.has(id):map_image.set_pixelv(id,map_color(sim,base,id,columns));changed=true
		for id in sim.visible_cells:
			if not map_drawn_visible.has(id):map_image.set_pixelv(id,map_color(sim,base,id,columns));changed=true
		if changed:map_drawn_visible=sim.visible_cells.duplicate()
	if map_texture==null: map_texture=ImageTexture.create_from_image(map_image)
	elif changed: map_texture.update(map_image)

func draw_minimap(sim) -> void:
	if map_texture==null:
		minimap_road_cells.clear()
		# Rasterize the shared transport graph once, then apply live fog below.
		for segment in sim.terrain.roads.segments:
			var direction:Vector2=(segment.b-segment.a).normalized()
			var normal:=Vector2(-direction.y,direction.x)
			var steps:=ceili(segment.a.distance_to(segment.b)*2.0)
			for i in range(steps+1):
				var center:Vector2=segment.a.lerp(segment.b,float(i)/maxi(1,steps))
				for offset in [-0.3,0.0,0.3]:
					minimap_road_cells[sim.terrain.cell(center+normal*segment.width*offset)]=true
	cv.draw_rect(minimap,Color("283d3c"))
	if map_texture==null or absf(sim.time-map_clock)>0.3:update_map_image(sim)
	cv.draw_texture_rect(map_texture,minimap,false)
	if float(sim.scenario.get("jam_radius",0))>0 and sim.objectives[0].owner==1:
		var center:Vector2=minimap.position+sim.objectives[0].pos/sim.terrain.world_size*minimap.size
		cv.draw_arc(center,float(sim.scenario.jam_radius)*minimap.size.x/sim.terrain.world_size.x,0,TAU,48,ORANGE,1.5,true)
		text_at("JAM",center+Vector2(5,-7),9,ORANGE)
	for u in sim.units:
		if sim.alive(u) and u.visible:
			var p: Vector2 = minimap.position+u.pos/sim.terrain.world_size*minimap.size
			# Field works read as squares: filled when complete, outlined while unfinished.
			if u.get("structure",false) and not sim.field_ops.is_empty():
				var complete:bool=float(u.get("build_left",0.0))<=0
				# Width applies to the outline only (Godot warns when it is given with a fill).
				cv.draw_rect(Rect2(p-Vector2(2.5,2.5),Vector2(5,5)),BattlefieldInterface.structure_color(self,u,battle.selected.has(u.id)),complete,-1.0 if complete else 1.0)
			else:cv.draw_circle(p,3 if battle.selected.has(u.id) else 2,TEAL if u.team==0 else RED)
	for obj in sim.objectives:
		var p: Vector2=minimap.position+obj.pos/sim.terrain.world_size*minimap.size
		cv.draw_rect(Rect2(p-Vector2(3,3),Vector2(6,6)),TEAL if obj.owner==0 else ORANGE,false,1)
	var zone:Dictionary=sim.scenario.get("operation",{}).get("naval_zone",{})
	if not zone.is_empty():
		var centre:Vector2=minimap.position+Vector2(float(zone.position[0]),float(zone.position[1]))/sim.terrain.world_size*minimap.size
		cv.draw_arc(centre,float(zone.radius)*minimap.size.x/sim.terrain.world_size.x,0,TAU,32,TEAL if sim.FieldOps.OperationRules.naval_ready(sim) else ORANGE,1.5,true)
		text_at("SEA",centre+Vector2(5,-6),9,MUTED)
	var footprint:=minimap_view_outline(sim)
	if footprint.size()>=3:
		footprint.append(footprint[0])
		cv.draw_polyline(footprint,WHITE,1,true)
	cv.draw_rect(minimap,LINE,false,1)
	text_at("THEATER / CLICK TO PAN",minimap.position+Vector2(0,minimap.size.y+17),9,MUTED)

# Camera view on the minimap: the ground quad under the battlefield corners,
# clipped to the minimap. Clamping corners one by one folds an overhanging view
# into a skewed triangle.
func minimap_view_outline(sim) -> PackedVector2Array:
	var quad:=PackedVector2Array()
	var inside:=true
	for pos in battle.view_ground_polygon():
		var p:Vector2=minimap.position+pos/sim.terrain.world_size*minimap.size
		inside=inside and minimap.grow(0.01).has_point(p)
		quad.append(p)
	if inside:return quad
	var frame:=PackedVector2Array([minimap.position,Vector2(minimap.end.x,minimap.position.y),minimap.end,Vector2(minimap.position.x,minimap.end.y)])
	var clipped:Array=Geometry2D.intersect_polygons(quad,frame)
	return clipped[0] if clipped.size()==1 else PackedVector2Array()

# Small action tag beside the pointer (battle.refresh_cursor_hint sets the text).
func draw_cursor_hint() -> void:
	var at:=pointer()+Vector2(16,18)
	var width:=font.get_string_size(battle.cursor_hint,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x+16
	# Drawn without console_panel: the tag follows the pointer and must not block clicks.
	panel(Rect2(at,Vector2(width,22)),INK)
	text_at(battle.cursor_hint,at+Vector2(8,16),12,ORANGE if battle.cursor_hint=="Shell" else TEAL,true)

# Notice banners (battle.notices), oldest on top: alerts orange, info white,
# low dim and smaller. They do not block clicks.
func draw_notices(y:float) -> void:
	var w:=size.x
	for item in battle.notices.banners:
		var low:bool=item.level==Notice.LOW
		var message:String=Notice.line(item)
		var size_px:=12 if low else 13
		var height:=24.0 if low else 30.0
		var width:=font.get_string_size(message,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px).x+28
		panel(Rect2(w/2-width/2,y,width,height),INK)
		cv.draw_line(Vector2(w/2-width/2+2,y+2),Vector2(w/2+width/2-2,y+2),Color("626956"),1)
		text_at(message,Vector2(w/2-width/2+14,y+height-10),size_px,ORANGE if item.level==Notice.ALERT else (MUTED if low else WHITE))
		y+=height+4

# Order acknowledgement (Notice.CURSOR): a tag under the pointer, below the action hint.
func draw_cursor_notice() -> void:
	var text:String=battle.notices.cursor_text
	var at:=pointer()+Vector2(16,18+(24 if battle.cursor_hint!="" else 0))
	var width:=font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x+14
	panel(Rect2(at,Vector2(width,20)),INK)
	text_at(text,at+Vector2(7,14),11,MUTED)

func draw_guide() -> void:
	var w:=size.x
	var h:=size.y
	cv.draw_rect(Rect2(Vector2.ZERO,size),Color(0.035,0.043,0.035,0.87))
	# Field scenarios add FIELD_ORDERS rows; the panel grows to keep them inside.
	var field:bool=not battle.sim.field_ops.is_empty()
	var extra:=FIELD_ORDERS.size()*28 if field else 0
	var r:=Rect2(w/2-350,h/2-252-extra/2,700,504+extra)
	panel(r,INK)
	var operation_label:String="REGIONAL OPERATION" if battle.campaign.active else "OPERATION  /  01"
	if battle.campaign.active and battle.campaign.data.started:operation_label+="  ·  %d IN RESERVE" % battle.campaign.parked.size()
	text_at(operation_label,r.position+Vector2(34,38),12,TEAL,true)
	text_at(battle.sim.scenario.name,r.position+Vector2(34,79),34,WHITE,true)
	var campaign_error:String=battle.campaign_status_error()
	if campaign_error!="":text_at(fit_text(campaign_error,632,12),r.position+Vector2(34,103),12,RED)
	# Long authored briefs wrap below the selector row inside the 632 px column, at most three lines.
	var briefing:String=str(battle.sim.scenario.brief)
	if field:
		var mission_brief:String=battle.sim.FieldOps.OperationRules.brief(battle.sim.scenario)
		if mission_brief!="":briefing=mission_brief
	brief_lines=wrap_text(briefing,632,13)
	if brief_lines.size()>3:
		brief_lines[2]=fit_text(" ".join(brief_lines.slice(2))+" ",632,13)
		brief_lines.resize(3)
	for i in brief_lines.size():
		text_at(brief_lines[i],r.position+Vector2(34,166+i*16),13,MUTED)
	var lines := [
		["COMMAND", "Drag a box or click a section. Right-click ground to move."],
		["ENGAGE", "Right-click a visible enemy, or A then click to attack-move."],
		["COORDINATE", "Shift queues orders. Ctrl + 1–9 assigns groups; 1–9 recalls."],
		["READ TERRAIN", "Woods protect infantry. Ridges and buildings block sight."],
		["COMBINE ARMS", "Scout with the UAV. Flank armor. Keep aircraft away from AA."],
		["SECURE", "Ground units capture. The corvette provides coastal fire support."],
		["REINFORCE", "R retreats to recover at base (costs supply). Preserve your force."]]
	if not battle.sim.classic.is_empty():
		lines[3]=["ECONOMY","Build a refinery. Harvesters collect and deliver finite resources."]
		lines[4]=["BUILD","Place structures near your base. Power supports production."]
		lines[5]=["VICTORY","Destroy all enemy base structures. Flags are not required."]
		lines[6]=["PRODUCE","Barracks: infantry. Factory: armor/UAV. HQ: harvesters."]
	elif not battle.sim.field_ops.is_empty():
		lines[3]=["SUPPLY","One supply pool, slow income. Buy sections and field works."]
		lines[4]=["ENGINEERS","Select engineers, pick a field work, click a visible site."]
		lines[5]=["BUILDERS","Sites grow with engineers on site. Orders pause; RESUME keeps work."]
		lines[6]=["SUPPORT","Aid posts treat soldiers, repair points mend vehicles. No revival."]
		lines.append_array(FIELD_ORDERS)
	for i in lines.size():
		text_at(lines[i][0],r.position+Vector2(34,224+i*28),10,TEAL,true)
		text_at(lines[i][1],r.position+Vector2(160,224+i*28),13,WHITE)
	text_at("Arrows / screen edges pan  •  Wheel zoom  •  F focus  •  Space pause  •  M mute  •  F1 guide",r.position+Vector2(34,420+extra),12,MUTED)
	# Modal buttons replace background hit targets.
	hits.clear()
	modal=true
	# Keep the legacy fixture selectors stable; regional operations are chosen on
	# their shared geography, with only the current regional operation in this row.
	# Hidden legacy scenarios keep their numeric ids and appear only while active.
	if scenario_entries.is_empty():
		var presets:Array=Scenarios.entries()
		for index in presets.size():
			var id:String=presets[index].get("id","")
			scenario_entries.append({"index":index,"label":SCENARIO_LABELS.get(id,str(presets[index].get("name",id)).to_upper()),"hidden":bool(presets[index].get("hidden",false)),"regional":presets[index].has("map_path")})
	var active:int=battle.sim.terrain.scenario_id
	var listed:=scenario_entries.filter(func(entry):return (not entry.hidden and not entry.regional) or entry.index==active)
	var count:=listed.size()
	var width:=(486.0-7.0*(count-1))/maxi(count,1)
	for i in count:
		button("scenario:"+str(listed[i].index),fit_bold(listed[i].label,width-16,12),Rect2(r.position+Vector2(34+i*(width+7.0),119),Vector2(width,25)),true,active==listed[i].index)
	button("region","REGIONAL MAP  →",Rect2(r.position+Vector2(527,119),Vector2(139,25)))
	if battle.sim.scenario.get("id","")=="black_sea_harbor":
		button("tutorial:start","DEPLOY WITH FIELD GUIDE",Rect2(r.position+Vector2(34,446+extra),Vector2(292,38)))
		button("begin","DEPLOY  →",Rect2(r.position+Vector2(334,446+extra),Vector2(332,38)))
	else:button("begin","DEPLOY  →",Rect2(r.position+Vector2(34,446+extra),Vector2(632,38)))

func draw_result() -> void:
	cv.draw_rect(Rect2(Vector2.ZERO,size),Color(0.035,0.043,0.035,0.82))
	var r:=Rect2(size.x/2-270,size.y/2-164,540,328)
	panel(r,INK)
	var sim=battle.sim
	text_at("MISSION COMPLETE" if sim.result=="VICTORY" else "FORCE LOST",r.position+Vector2(30,42),12,TEAL if sim.result=="VICTORY" else RED,true)
	text_at(sim.result,r.position+Vector2(30,94),38,WHITE,true)
	text_at(("Enemy base destroyed." if not sim.classic.is_empty() else "Sectors secured. Objective complete.") if sim.result=="VICTORY" else "Use cover, scout ahead, and reinforce before advancing.",r.position+Vector2(30,130),14,MUTED)
	text_at("%02d:%02d   /   %d enemies destroyed   /   %d sections lost" % [int(sim.time)/60,int(sim.time)%60,sim.kills,sim.losses],r.position+Vector2(30,174),14,WHITE)
	if battle.campaign.active:text_at(fit_text(battle.campaign_message,480,12),r.position+Vector2(30,201),12,TEAL)
	hits.clear()
	modal=true
	button("region","REGIONAL MAP",Rect2(r.position+Vector2(30,241),Vector2(230,46)))
	button("restart","RETRY OPERATION" if sim.result=="DEFEAT" else "REDEPLOY",Rect2(r.position+Vector2(272,241),Vector2(238,46)))
