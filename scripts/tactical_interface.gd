extends RefCounted

# Contextual flat command strip. Existing move/hold/retreat controls stay in
# their established positions; all new targeting shares Esc/right-click cancel.
const Notice=preload("res://scripts/notice_feed.gd")
const LABELS:={"frag":"FRAG","smoke":"SMOKE","dig":"DIG","upgrade":"UPGRADE"}
var preview_key:=""
var preview_at:=-1000
var preview_data:Dictionary={}

static func sections(battle)->Array:
	var result:Array=[]
	for id in battle.orderable():
		var u:Dictionary=battle.sim.get_unit(int(id))
		if battle.sim.alive(u) and not u.get("combat_ineffective",false) and not u.members.is_empty():result.append(u)
	return result

static func handle(battle,action:String)->bool:
	if not action.begins_with("tactical:"):return false
	if battle.show_help or battle.menu_open() or battle.sim.result!="":return true
	var units:=sections(battle)
	if units.is_empty():return true
	var ids:Array=units.map(func(u):return u.id)
	var kind:=action.trim_prefix("tactical:")
	if kind in ["frag","smoke","dig","upgrade"]:
		battle.set_targeting("tactical",kind)
	elif kind=="backup":
		battle.cancel_targeting(false)
		var count:int=battle.sim.request_backup(ids)
		battle.notify(battle.sim.order_feedback if battle.sim.order_feedback!="" else ("Backup requested" if count>0 else "Backup unavailable"),Notice.CURSOR)
	elif kind=="reserve":
		var enabled:bool=not units.all(func(u):return u.get("reserve_enabled",false))
		var count:int=battle.sim.set_reserve(ids,enabled)
		battle.notify(("%d reserve sections available" if enabled else "%d reserve assignments ended")%count,Notice.CURSOR)
	elif kind=="auto_frag":
		var enabled:bool=not units.all(func(u):return u.get("throw_policy","manual")=="defensive")
		var count:int=battle.sim.Throwables.set_policy(battle.sim,ids,"defensive" if enabled else "manual")
		battle.notify(("%d sections may use defensive grenades" if enabled else "%d sections use manual grenades")%count,Notice.CURSOR)
	elif kind=="fire":
		var hold:bool=not units.all(func(u):return u.get("fire_policy","free")=="hold")
		var count:int=battle.sim.set_fire_policy(ids,"hold" if hold else "free")
		var message:="Holding fire" if hold else "Fire at will"
		if count==0:message="Fire order not received · radio link lost"
		elif count<ids.size():message+=" · %d / %d sections · others disconnected"%[count,ids.size()]
		battle.notify(message,Notice.CURSOR)
	return true

static func site_at(sim,point:Vector2)->int:
	var best:=-1
	var distance:=5.0
	for site in sim.units:
		if not sim.alive(site) or site.team!=0 or not site.get("field_position",false):continue
		var gap:float=site.pos.distance_to(point)
		if gap<distance:best=int(site.id);distance=gap
	return best

static func confirm(battle,point:Vector2)->void:
	var units:=sections(battle)
	var ids:Array=units.map(func(u):return u.id)
	var kind:String=battle.tactical_mode
	var count:=0
	if kind in ["frag","smoke"]:count=battle.sim.issue_throw(ids,kind,point)
	elif kind=="dig":count=battle.sim.issue_dig(ids,point)
	elif kind=="upgrade":count=battle.sim.upgrade_position(ids,site_at(battle.sim,point))
	if count>0:
		battle.notify(battle.sim.order_feedback if battle.sim.order_feedback!="" else LABELS.get(kind,kind)+" acknowledged",Notice.CURSOR)
		battle.set_targeting("")
		battle.ping()
	else:battle.notify(battle.sim.order_feedback if battle.sim.order_feedback!="" else "Action unavailable here",Notice.CURSOR)

static func status(sim,u:Dictionary)->String:
	for member in u.members:
		if not sim.Infantry.task_busy(member):continue
		if member.get("task_kind","")=="throw":return str(u.reason)
		return str(member.get("state","Preparing position")).capitalize()
	if u.has("support_task"):return str(u.reason)
	var cooperation:String=sim.Coordination.status(u)
	if cooperation!="":return cooperation
	var request:Dictionary=sim.support_requests.get("requests",{}).get(int(u.get("backup_request",-1)),{})
	if not request.is_empty() and request.phase not in sim.SupportRequests.TERMINAL:
		if int(request.sender)==int(u.id) and int(request.sender_version)==int(u.order_version) and int(request.sender_assignment)==int(u.assignment.get("id",0)):
			return str(request.reason)
	if u.get("reserve_enabled",false):return "Reserve · available for nearby backup"
	return ""

func draw(hud)->void:
	var battle=hud.battle
	var sim=battle.sim
	var units:=sections(battle)
	if units.is_empty():return
	var frag:=0
	var smoke:=0
	for u in units:
		frag+=sim.Throwables.total(u,"frag")
		smoke+=sim.Throwables.total(u,"smoke")
	var commands:Array=[
		["frag","G FRAG %d"%frag,frag>0,"Fragmentation grenade · choose a clear throw; friendlies must be outside the blast."],
		["smoke","V SMOKE %d"%smoke,smoke>0,"Optical smoke · blocks both sides' sight for 18 seconds."],
		["dig","D DIG",not sim.field_ops.is_empty(),"Prepare shallow cover on nearby soil · work time, no supply cost."],
	]
	if units.any(func(u):return u.kind=="engineer"):
		commands.append(["upgrade","U UPGRADE",not sim.field_ops.is_empty(),"Click a shallow position to reinforce it · %d supply."%int(sim.definitions.get("fighting_trench",{}).get("cost",0))])
	commands.append(["backup","B BACKUP",true,"Ask one available nearby reserve to provide support, then return."])
	commands.append(["reserve","RESERVE",true,"Allow these sections to answer nearby requests. A new order ends this assignment."])
	var auto_frag:bool=units.all(func(u):return u.get("throw_policy","manual")=="defensive")
	commands.append(["auto_frag","AUTO FRAG",true,"Allow defensive grenades at observed infantry groups with a covering teammate. Uses carried stock."])
	var hold:bool=units.all(func(u):return u.get("fire_policy","free")=="hold")
	commands.append(["fire","H FIRE FREE" if hold else "H HOLD FIRE",true,"Toggle firing permission. Explicit grenade orders permit only that throw."])
	var y:float=hud.size.y-(154.0 if hud.battlefield_ui.roster_ids.size()>1 else 50.0)
	var tutorial:Rect2=hud.battlefield_ui.tutorial_rect(hud)
	if tutorial.has_area():y=minf(y,tutorial.position.y-46.0)
	var width:float=minf(106.0,(hud.battlefield_rect().size.x-32.0)/commands.size())
	var bar:=Rect2(12,y,width*commands.size()+8,38)
	hud.console_panel(bar)
	var hovered:=""
	for i in commands.size():
		var item:Array=commands[i]
		var rect:=Rect2(16+i*width,y+5,width-4,28)
		var active:bool=battle.tactical_mode==item[0] or (item[0]=="reserve" and units.all(func(u):return u.get("reserve_enabled",false))) or (item[0]=="auto_frag" and auto_frag) or (item[0]=="fire" and hold)
		hud.button("tactical:"+item[0],item[1],rect,item[2],active)
		if rect.has_point(hud.pointer()):hovered=item[3]
	if hovered!="":
		var hint_width:float=minf(hud.battlefield_rect().size.x-24,hud.font.get_string_size(hovered,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x+20)
		hud.panel(Rect2(12,y-31,hint_width,26),hud.INK)
		hud.text_at(hud.fit_text(hovered,hint_width-16,12),Vector2(20,y-13),12,hud.WHITE)
		return
	draw_preview(hud,units)

func draw_preview(hud,units:Array)->void:
	var battle=hud.battle
	var sim=battle.sim
	var mode:String=battle.tactical_mode
	if mode.is_empty() or not hud.battlefield_rect().has_point(hud.pointer()) or hud.action_at(hud.pointer())!="":return
	var point:Vector2=battle.world_pos(hud.pointer())
	var key:="%s:%s:%d:%d:%d"%[mode,battle.selected,roundi(point.x*3),roundi(point.y*3),int(sim.throwables.get("revision",0))]
	if key!=preview_key or Time.get_ticks_msec()-preview_at>=100:
		preview_key=key;preview_at=Time.get_ticks_msec()
		preview_data={"ok":false,"reason":"No member ready","arc":[]}
		if mode in ["frag","smoke"]:
			preview_data=sim.Throwables.preview_selection(sim,units.map(func(u):return u.id),mode,point)
		elif mode=="dig":
			var reason:String=sim.FieldPositions.dig_reason(sim,units.map(func(u):return u.id),point)
			preview_data={"ok":reason.is_empty(),"reason":reason if reason!="" else "Prepare shallow cover · no supply cost","arc":[]}
		elif mode=="upgrade":
			var reason:String=sim.FieldPositions.upgrade_reason(sim,units.map(func(u):return u.id),site_at(sim,point))
			preview_data={"ok":reason.is_empty(),"reason":reason if reason!="" else "Reinforce position · %d supply"%int(sim.definitions.fighting_trench.cost),"arc":[]}
	var color:Color=hud.TEAL if preview_data.get("ok",false) else hud.RED
	var points:=PackedVector2Array()
	for vertex in preview_data.get("arc",[]):points.append(battle.screen_pos(Vector2(vertex.x,vertex.z),vertex.y,true))
	if points.size()>1:hud.cv.draw_polyline(points,color,2,true)
	var landing:Vector3=preview_data.get("landing",Vector3(point.x,sim.terrain.height_at(point),point.y))
	var center:Vector2=Vector2(landing.x,landing.z) if mode in ["frag","smoke"] and points.size()>1 else point
	if mode in ["frag","smoke"]:
		points.clear()
		for i in 49:points.append(battle.screen_pos(center+Vector2.from_angle(i*TAU/48)*float(preview_data.get("radius",4.0)),0.2))
		hud.cv.draw_polyline(points,color,1.5,true)
	else:
		var site:Dictionary=sim.get_unit(site_at(sim,point)) if mode=="upgrade" else {}
		if not site.is_empty():center=site.pos
		var rect:Rect2=sim.FieldOps.footprint(sim,"fighting_trench",center,false)
		for p in [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y),rect.position]:points.append(battle.screen_pos(p,0.15))
		hud.cv.draw_polyline(points,color,1.5,true)
	var text:String="%s · %s"%[LABELS.get(mode,mode),preview_data.get("reason","")]
	var at:Vector2=hud.pointer()+Vector2(18,21)
	var text_width:float=minf(430,hud.font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x+16)
	at.x=minf(at.x,hud.battlefield_rect().end.x-text_width-8)
	hud.panel(Rect2(at,Vector2(text_width,24)),hud.INK)
	hud.text_at(hud.fit_text(text,text_width-16,12),at+Vector2(8,17),12,color)
