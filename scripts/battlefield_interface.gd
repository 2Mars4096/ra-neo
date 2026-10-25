extends RefCounted
# Read-only battlefield presentation. Commands remain battle/simulation-owned;
# these actions only select/focus, page the roster or opt into the field guide.
const ROLE_LABELS := {"rifle":"INF","atgm":"AT","engineer":"ENG","tank":"MBT","aa":"AA","drone":"UAV","helo":"AIR","boat":"SEA","fpv_drone":"FPV","bunker":"MG","at_gun":"AT GUN","command_post":"CMD","ammo_depot":"DEPOT"}
const ROLE_HINTS := {
	"rifle":"Suppress infantry and protect AT teams. Rifles cannot damage armour.",
	"atgm":"Three anti-tank missiles. Resupply at rear staging or a friendly supply post.",
	"tank":"Break through infantry positions. Support with scouts; watch AT teams and exposed rear armour.",
	"aa":"Protect your force from aircraft and drones. Light armour needs ground support.",
	"drone":"Unarmed reconnaissance. Even rifle fire can disable it; avoid enemy AA.",
	"helo":"Mobile anti-armour support. Enemy AA can deny its approach.",
	"boat":"Coastal fire support; confined to navigable water.",
	"engineer":"Build support and clear obstacles. Keep the section behind the assault.",
	"tactical_cover":"Sandbag cover protects nearby infantry. Engineers can clear enemy barriers.",
	"observation_post":"Raised observation position with 24 m sight.",
	"repair_point":"Repairs nearby land vehicles after they disengage from combat.",
	"aid_post":"Treats living wounded soldiers nearby after they disengage from combat.",
	"concertina_wire":"Slows infantry to a crawl. Tracked vehicles crush it; engineers can clear it.",
	"tank_obstacles":"Blocks tracked and wheeled vehicles. Infantry can pass; engineers can clear it.",
	"fighting_trench":"Dug-in cover protects infantry inside. Engineers can clear it.",
	"vehicle_berm":"Protects armoured vehicles from ground fire to their front and sides.",
	"camouflage_net":"Hides land units until closer observation. Firing reveals them for three seconds.",
	"forward_supply_point":"Forward reinforcement entry and missile resupply. Land access requires a safe connected route.",
	"bunker":"Anti-infantry emplacement. Attack with armour or anti-tank fire.",
	"at_gun":"Long-range anti-armour position. Scout it and approach with supporting infantry.",
	"command_post":"Enemy logistics: destroying every command post and depot stops new reserves.",
	"ammo_depot":"Enemy logistics: destroying every command post and depot stops new reserves."}
var roster_ids:Array=[]
var roster_page:=0
var last_selection:Array=[]
var hover_id:=-1
var hover_checked:=-1000
var last_alert:Dictionary={}
var tutorial_active:=false
var tutorial_started:=false
var tutorial_step:=0
var tutorial_scout:=-1
var scout_origin:=Vector2.ZERO
var scout_explored:=0
var scout_command:=0
var scout_ordered:=false
var tutorial_command:=0

func update(hud)->void:
	var battle=hud.battle
	var sim=battle.sim
	if battle.selected!=last_selection:
		if battle.selected.size()>1:
			roster_ids=battle.selected.duplicate()
			roster_page=0
		elif battle.selected.is_empty() or (battle.selected.size()==1 and not roster_ids.has(battle.selected[0])):
			roster_ids=[]
		last_selection=battle.selected.duplicate()
	roster_ids=roster_ids.filter(func(id):return sim.alive(sim.get_unit(id)))
	if tutorial_active and not battle.show_help and not menu_open(battle) and sim.result=="":update_tutorial(battle)

func menu_open(battle)->bool:
	return battle.has_method("menu_open") and battle.menu_open()

static func critical_state(sim,u:Dictionary)->String:
	if u.get("combat_ineffective",false):return "UNAVAILABLE"
	if u.get("mobility_kill",false):return "IMMOBILISED"
	if u.get("firepower_kill",false):return "GUN OUT"
	if u.suppression>0.6:return "PINNED"
	if u.kind=="atgm":
		var left:int=sim.missiles_left(u)
		return "AT %d/%d" % [left,int(sim.definitions.atgm.missiles)] if left>0 else "RESUPPLY"
	if float(u.get("fire_until",-1.0))>sim.time:return "ON FIRE"
	if float(u.get("flood_rate",0.0))>0:return "FLOODING"
	if u.get("regroup_active",false):return "REGROUPING"
	if int(u.get("garrison",-1))>=0:return "GARRISON"
	if u.get("recovering",false):return "RECOVERING"
	if not u.orders.is_empty() and u.orders[0].mode=="retreat":return "RETREATING"
	if u.orders.is_empty() and sim.time-float(u.get("last_shot",-100))>2:return "READY"
	return str(u.get("visual_state",u.state))

static func role_label(kind:String)->String:
	return ROLE_LABELS.get(kind,kind.left(3).to_upper())

static func tactical_icons(zoom:float)->bool:
	return zoom>=100.0

func draw_role(hud,u:Dictionary,p:Vector2)->void:
	var color:Color=hud.TEAL if u.team==0 else hud.RED
	var label:=role_label(u.kind)
	var width:float=maxf(28,hud.bold.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x+10)
	var r:=Rect2(p+Vector2(-width/2,-22),Vector2(width,17))
	hud.panel(r,hud.INK)
	hud.cv.draw_rect(r,color,false,1)
	hud.text_at(label,r.position+Vector2(5,12),11,color,true)

static func structure_color(hud,u:Dictionary,selected:bool)->Color:
	return hud.WHITE if selected else (hud.TEAL if u.team==0 else hud.RED)

func roster_rect(hud)->Rect2:
	return Rect2(12,hud.size.y-110,minf(840,hud.battlefield_rect().size.x-24),98)

func roster_columns(hud)->int:
	return maxi(1,mini(6,floori((roster_rect(hud).size.x-18)/136.0)))

func draw_roster(hud)->void:
	if roster_ids.size()<2:return
	var sim=hud.battle.sim
	var r:=roster_rect(hud)
	hud.console_panel(r)
	var columns:=roster_columns(hud)
	var pages:=ceili(float(roster_ids.size())/columns)
	roster_page=clampi(roster_page,0,pages-1)
	hud.text_at("SELECTION  ·  %d sections" % roster_ids.size(),r.position+Vector2(12,19),12,hud.WHITE,true)
	hud.text_at("Click to isolate  ·  F to locate",r.position+Vector2(208,19),11,hud.MUTED)
	if hud.battle.selected.size()==1:
		hud.button("roster:all","BACK TO GROUP",Rect2(r.end.x-164,r.position.y+4,152,21))
	elif pages>1:
		hud.button("roster:prev","<",Rect2(r.end.x-112,r.position.y+4,26,21),roster_page>0)
		hud.text_at("%d/%d" % [roster_page+1,pages],Vector2(r.end.x-78,r.position.y+19),11,hud.MUTED)
		hud.button("roster:next",">",Rect2(r.end.x-38,r.position.y+4,26,21),roster_page<pages-1)
	var width:float=(r.size.x-24-(columns-1)*6)/columns
	for slot in columns:
		var index:int=roster_page*columns+slot
		if index>=roster_ids.size():break
		var u:Dictionary=sim.get_unit(roster_ids[index])
		var card:=Rect2(r.position+Vector2(12+slot*(width+6),29),Vector2(width,59))
		var active:bool=hud.battle.selected.has(u.id)
		hud.panel(card,Color("3b4632") if active else hud.PANEL)
		# Focus target precedes the containing card in hit order.
		hud.button("roster:focus:%d" % u.id,"F",Rect2(card.end.x-26,card.position.y+4,22,21))
		hud.hits.append({"id":"roster:select:%d" % u.id,"rect":Rect2(card.position,Vector2(card.size.x-30,card.size.y)),"enabled":true})
		hud.text_at("%s  #%d" % [role_label(u.kind),u.id],card.position+Vector2(7,17),12,hud.TEAL if active else hud.WHITE,true)
		var health:float=clampf(u.hp/maxf(u.max_hp,1.0),0,1)
		var line:=Rect2(card.position+Vector2(7,25),Vector2(width-14,4))
		hud.cv.draw_rect(line,hud.INK)
		hud.cv.draw_rect(Rect2(line.position,Vector2(line.size.x*health,4)),hud.RED if health<0.3 else hud.TEAL)
		var state:=critical_state(sim,u)
		var urgent:bool=state in ["UNAVAILABLE","IMMOBILISED","GUN OUT","PINNED","RESUPPLY","ON FIRE","FLOODING"]
		hud.text_at(hud.fit_text("%d%% · %s" % [roundi(health*100),state],width-14,11),card.position+Vector2(7,46),11,hud.ORANGE if urgent else hud.MUTED)

func enemy_under_pointer(hud)->Dictionary:
	var battle=hud.battle
	var sim=battle.sim
	var point:Vector2=hud.pointer()
	if not hud.battlefield_rect().has_point(point):return {}
	# During top-layer drawing, action_at sees only that layer's active list.
	# Previously recorded world/sidebar panels still obscure the battlefield.
	for part in 2:
		for region in hud.layer_blocked[part]:
			if region.has_point(point):return {}
	if battle.show_help or sim.result!="" or menu_open(battle) or hud.action_at(point)!="" or battle.dragging or battle.build_mode!="" or battle.strike_mode:
		return {}
	if Time.get_ticks_msec()-hover_checked>=100:
		hover_id=battle.pick(point,true)
		hover_checked=Time.get_ticks_msec()
	var u:Dictionary=sim.get_unit(hover_id)
	# Revalidate visibility on every draw, even inside the hover throttle window.
	if not sim.alive(u) or u.team==0 or not u.visible:return {}
	var close:=false
	for at in battle.click_points(u):
		if point.distance_to(at)<24:close=true;break
	return u if close else {}

func draw_enemy_hover(hud)->void:
	var u:=enemy_under_pointer(hud)
	if u.is_empty():return
	var sim=hud.battle.sim
	var width:float=minf(360,hud.battlefield_rect().size.x-24)
	var role:String=ROLE_HINTS.get(u.kind,str(sim.definitions[u.kind].role))
	var lines:Array=hud.wrap_text(role,width-24,12)
	var height:float=43+lines.size()*16
	var point:Vector2=hud.pointer()+Vector2(18,30)
	point.x=clampf(point.x,12,hud.battlefield_rect().end.x-width-12)
	point.y=clampf(point.y,150,hud.size.y-height-12)
	var r:=Rect2(point,Vector2(width,height))
	# A tooltip follows the pointer and never consumes a battlefield click.
	hud.panel(r,hud.INK)
	hud.text_at(hud.fit_text(str(sim.definitions[u.kind].name).to_upper()+" · ENEMY",width-24,13),point+Vector2(12,20),13,hud.RED,true)
	hud.text_at("HP %d / %d" % [maxi(0,int(u.hp)),int(u.max_hp)],point+Vector2(12,37),11,hud.MUTED)
	for i in lines.size():hud.text_at(lines[i],point+Vector2(12,55+i*16),12,hud.WHITE)

func mission_lines(sim)->Array[String]:
	var secured:int=sim.objectives.filter(func(obj):return obj.owner==0 and not obj.get("contested",false)).size()
	var hold:int=ceili(float(sim.scenario.hold))
	var first:="SECURE %d/%d  ·  Hold all for %ds" % [secured,sim.objectives.size(),hold]
	if sim.score_hold>0:first="HOLD %ds remaining  ·  %d/%d sectors clear" % [maxi(0,ceili(float(sim.scenario.hold)-sim.score_hold)),secured,sim.objectives.size()]
	var authored_logistics:bool=sim.scenario.get("enemy_works",[]).any(func(work):return str(work.kind) in ["command_post","ammo_depot"])
	var second:="Secure the approaches and hold every sector."
	if authored_logistics:
		second="Optional: destroy all enemy posts/depots to stop new waves."
		if not sim.FieldOps.enemy_logistics_alive(sim):second="Enemy logistics neutralised · already deployed forces remain."
	elif not sim.FieldOps.reserve_records(sim).is_empty():
		second="Enemy reserve deployed · secure and hold every sector." if sim.counterattack_sent else "Taking a sector brings enemy reserves. Prepare support."
	var operation_status:String=sim.FieldOps.OperationRules.status(sim)
	if operation_status!="":second=operation_status
	return [first,second]

func draw_mission(hud)->void:
	var sim=hud.battle.sim
	if not sim.terrain.compiled_map or sim.field_ops.is_empty():return
	var r:=Rect2(12,86,minf(420,hud.battlefield_rect().size.x-24),48)
	hud.console_panel(r)
	var lines:=mission_lines(sim)
	hud.text_at(hud.fit_text(lines[0],r.size.x-20,13),r.position+Vector2(10,19),13,hud.TEAL,true)
	hud.text_at(hud.fit_text(lines[1],r.size.x-20,11),r.position+Vector2(10,37),11,hud.MUTED)
	var brief:String=sim.FieldOps.OperationRules.brief(sim.scenario)
	if brief!="" and r.has_point(hud.pointer()):hud.sidebar_hint(brief,r.end.y+8)
	if not last_alert.is_empty() and sim.time-float(last_alert.time)<25.0:
		hud.button("alert:focus","LOCATE  "+hud.fit_text(last_alert.text,r.size.x-94,11),Rect2(r.position+Vector2(0,52),Vector2(r.size.x,25)))

func observe_event(event:Dictionary,sim)->void:
	if not event.has("pos") or not event.pos is Vector2:return
	var label:=""
	if event.type=="warning" and event.get("notice","") in ["alert","info"]:
		label=str(event.get("text","Alert"))
	elif event.type=="vehicle_damage" and int(event.get("team",-1))==0 and event.get("effect","") in ["mobility","firepower","abandoned","flooding","catastrophic","tail_rotor","forced_landing"]:
		label=role_label(str(event.kind))+" · "+str(event.effect).replace("_"," ")
	elif event.type=="destroyed" and event.get("visible",false):
		# Older destruction events do not carry team/id. Resolve only an exact
		# friendly loss; never infer a hidden enemy position from an event.
		for u in sim.units:
			if u.team==0 and not sim.alive(u) and u.kind==event.get("kind","") and u.pos.distance_squared_to(event.pos)<0.01:
				label=role_label(u.kind)+" lost";break
	if label!="":last_alert={"text":label,"pos":event.pos,"time":sim.time}

func start_tutorial(battle)->void:
	tutorial_active=true
	tutorial_started=true
	tutorial_step=0
	tutorial_scout=-1
	scout_ordered=false
	tutorial_command=int(battle.sim.command_serial)

func update_tutorial(battle)->void:
	var sim=battle.sim
	if tutorial_step==0:
		for id in battle.selected:
			var u:Dictionary=sim.get_unit(id)
			if sim.alive(u) and u.team==0 and u.kind=="drone":
				tutorial_scout=id;scout_origin=u.pos;scout_explored=sim.explored.size();scout_command=int(u.command_group)
				tutorial_step=1;break
	elif tutorial_step==1:
		var scout:Dictionary=sim.get_unit(tutorial_scout)
		if not sim.alive(scout):tutorial_step=0;return
		if int(scout.command_group)>scout_command and not scout.orders.is_empty():scout_ordered=true
		if scout_ordered and scout.pos.distance_to(scout_origin)>=8.0 and sim.explored.size()>scout_explored:tutorial_step=2
	elif tutorial_step==2:
		# Actual accepted attack-move orders on a deliberately selected mixed
		# ground force. No test-only state injection or automatic combat orders.
		var infantry:=false
		var support:=false
		for id in battle.selected:
			var u:Dictionary=sim.get_unit(id)
			if not sim.alive(u) or int(u.command_group)<=tutorial_command:continue
			if not u.orders.any(func(order):return order.mode=="attack_move"):continue
			if u.kind=="rifle":infantry=true
			if u.kind in ["tank","atgm"]:support=true
		if infantry and support:tutorial_step=3
	elif tutorial_step==3:
		if sim.objectives.any(func(obj):return obj.owner==0 and not obj.get("contested",false)):tutorial_step=4
	elif tutorial_step==4:
		if sim.units.any(func(u):return u.team==0 and sim.alive(u) and u.kind in ["aid_post","repair_point","forward_supply_point"] and float(u.get("build_left",1.0))<=0):tutorial_step=5

func tutorial_text()->Array:
	var steps:Array=[
		["1 / 5 · SELECT YOUR SCOUT","Select the UAV. It reveals threats; even rifle fire can disable it."],
		["2 / 5 · SCOUT AHEAD","Right-click the UAV into unexplored ground. Keep it clear of enemy rifles and AA."],
		["3 / 5 · COMBINE YOUR FORCE","Select rifles with a tank or AT team. Press A, then click an approach; use the scout to avoid frontal AT fire."],
		["4 / 5 · TAKE A SECTOR","Clear defenders, then move ground troops onto a flag. Pin infantry, flank armour and preserve your force."],
		["5 / 5 · ESTABLISH SUPPORT","Select engineers and finish an Aid, Repair or Supply point. Aid heals surviving soldiers; Repair mends vehicles; Supply reloads AT."],
		["OPENING COMPLETE","Secure all three sectors and hold them uncontested for 90 seconds. Enemy logistics are an optional target."]]
	return steps[clampi(tutorial_step,0,5)]

func draw_tutorial(hud)->void:
	var battle=hud.battle
	if battle.sim.scenario.get("id","")!="black_sea_harbor":return
	var bottom:float=roster_rect(hud).position.y-8 if roster_ids.size()>1 else hud.size.y-12
	if not tutorial_active:
		hud.button("tutorial:start","FIELD GUIDE",Rect2(12,bottom-27,122,27))
		return
	var width:float=minf(460,hud.battlefield_rect().size.x-24)
	var content:=tutorial_text()
	var lines:Array=hud.wrap_text(content[1],width-24,12)
	var height:float=43+lines.size()*17
	var r:=Rect2(12,bottom-height,width,height)
	hud.console_panel(r)
	hud.text_at(content[0],r.position+Vector2(12,20),12,hud.TEAL,true)
	hud.button("tutorial:hide","HIDE",Rect2(r.end.x-62,r.position.y+5,50,21))
	for i in lines.size():hud.text_at(lines[i],r.position+Vector2(12,42+i*17),12,hud.WHITE)

func focus(battle,pos:Vector2)->void:
	battle.camera_focus=Vector3(pos.x,0,pos.y)
	battle.update_camera()

func handle_action(hud,action:String)->bool:
	var battle=hud.battle
	if not is_instance_valid(battle):return false
	var sim=battle.sim
	if action=="roster:prev":roster_page=maxi(0,roster_page-1)
	elif action=="roster:next":roster_page+=1
	elif action=="roster:all":battle.selected=roster_ids.filter(func(id):return sim.alive(sim.get_unit(id)))
	elif action.begins_with("roster:select:") or action.begins_with("roster:focus:"):
		var id:=int(action.get_slice(":",2))
		var u:Dictionary=sim.get_unit(id)
		if sim.alive(u) and u.team==0:
			battle.selected=[id]
			if action.begins_with("roster:focus:"):focus(battle,battle.display_anchor(u))
	elif action.begins_with("mission:objective:"):
		var index:=int(action.get_slice(":",2))
		if index>=0 and index<sim.objectives.size():focus(battle,sim.objectives[index].pos)
	elif action=="alert:focus":
		if not last_alert.is_empty():focus(battle,last_alert.pos)
	elif action=="tutorial:start":
		if not tutorial_started:start_tutorial(battle)
		else:tutorial_active=true
		if battle.show_help:battle.ui_action("begin",Vector2.ZERO)
	elif action=="tutorial:hide":tutorial_active=false
	else:return false
	hud.queue_redraw()
	return true
