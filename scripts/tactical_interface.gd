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
	var seen:Dictionary={}
	for id in battle.orderable():
		if seen.has(int(id)):continue
		seen[int(id)]=true
		var u:Dictionary=battle.sim.get_unit(int(id))
		if battle.sim.alive(u) and u.team==0 and not u.get("combat_ineffective",false) and not u.members.is_empty():result.append(u)
	return result

# Selection-level availability is shared by buttons and shortcuts. Target
# geometry, actor readiness and commitment remain the executors' responsibility.
static func command_reason(sim,units:Array,kind:String)->String:
	if units.is_empty():return "Select an infantry section"
	if kind in ["dig","upgrade"] and sim.field_ops.is_empty():return "Field work unavailable"
	if kind=="upgrade" and not units.any(func(u):return u.kind=="engineer"):return "Select an engineer"
	if kind in ["frag","smoke"] and not units.any(func(u):return sim.Throwables.total(u,kind)>0):return "No %s grenades left"%kind
	return ""

static func policy_sections(sim,units:Array)->Array:
	var connected:Array=units.filter(func(u):return not sim.comms_blocked(u))
	return units if connected.is_empty() else connected

static func receipt(sim,units:Array,count:int,success:String,failure:String)->String:
	var disconnected:int=units.filter(func(u):return sim.comms_blocked(u)).size()
	if count==0:return failure+(" · radio link lost" if disconnected==units.size() and not failure.to_lower().contains("radio") else "")
	if count==units.size():return success
	var result:="%s · %d / %d sections"%[success,count,units.size()]
	if disconnected==units.size()-count:return result+" · others disconnected"
	if disconnected>0:result+=" · %d disconnected"%disconnected
	return result+" · %d unavailable"%(units.size()-count-disconnected)

static func handle(battle,action:String)->bool:
	if not action.begins_with("tactical:"):return false
	if battle.show_help or battle.menu_open() or battle.region_open() or battle.sim.result!="":return true
	var units:=sections(battle)
	var kind:=action.trim_prefix("tactical:")
	var reason:=command_reason(battle.sim,units,kind)
	if reason!="":battle.notify(reason,Notice.CURSOR);return true
	var ids:Array=units.map(func(u):return u.id)
	var connected:=policy_sections(battle.sim,units)
	if kind in ["frag","smoke","dig","upgrade"]:
		battle.set_targeting("tactical",kind)
	elif kind=="backup":
		battle.cancel_targeting(false)
		var count:int=battle.sim.request_backup(ids)
		var failure:String=str(connected[0].get("backup_status","Backup unavailable"))
		battle.notify(receipt(battle.sim,units,count,"Backup requested",failure),Notice.CURSOR)
	elif kind=="reserve":
		var enabled:bool=not connected.all(func(u):return u.get("reserve_enabled",false))
		var count:int=battle.sim.set_reserve(ids,enabled)
		battle.notify(receipt(battle.sim,units,count,"Reserve delegated" if enabled else "Reserve assignment ended","Reserve order not received"),Notice.CURSOR)
	elif kind=="auto_frag":
		var enabled:bool=not connected.all(func(u):return u.get("throw_policy","manual")=="defensive")
		var count:int=battle.sim.Throwables.set_policy(battle.sim,ids,"defensive" if enabled else "manual")
		battle.notify(receipt(battle.sim,units,count,"Auto Frag enabled" if enabled else "Manual grenades","Grenade policy not received"),Notice.CURSOR)
	elif kind=="fire":
		var hold:bool=not connected.all(func(u):return u.get("fire_policy","free")=="hold")
		var count:int=battle.sim.set_fire_policy(ids,"hold" if hold else "free")
		battle.notify(receipt(battle.sim,units,count,"Holding fire" if hold else "Fire at will","Fire order not received"),Notice.CURSOR)
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
	var reason:=command_reason(battle.sim,units,kind)
	if reason!="":battle.notify(reason,Notice.CURSOR);return
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
	var job:Dictionary=sim.FieldPositions.jobs(sim).get(int(u.id),{})
	if not job.is_empty() and int(job.version)==int(u.order_version) and int(job.assignment)==int(u.assignment.get("id",0)):
		var site:Dictionary=sim.get_unit(int(job.site))
		if sim.alive(site) and int(u.get("building_id",-1))==int(site.id):
			if site.get("build_paused",false):return "Work paused · %.0fs remaining"%ceilf(float(site.build_left))
			var actor:Dictionary=sim.Infantry.member_by_id(u,str(job.member))
			var activity:String=str(actor.get("state","Moving to position")).capitalize()
			return "%s · %.0fs remaining"%[activity,ceilf(float(site.build_left))]
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
	if u.get("reserve_enabled",false):return "Reserve delegated"
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
		["frag","G FRAG %d"%frag,"Fragmentation grenade · choose a clear throw; friendlies must be outside the blast."],
		["smoke","V SMOKE %d"%smoke,"Optical smoke · blocks both sides' sight for 18 seconds."],
	]
	if not sim.field_ops.is_empty():
		commands.append(["dig","D DIG","Prepare shallow cover on nearby soil · work time, no supply cost."])
		if units.any(func(u):return u.kind=="engineer"):
			commands.append(["upgrade","U UPGRADE","Reinforce a shallow position · %d supply once; paid work resumes free."%int(sim.definitions.get("fighting_trench",{}).get("cost",0))])
	commands.append(["backup","B BACKUP","Ask one available nearby reserve to provide support, then return."])
	commands.append(["reserve","RESERVE","Allow these sections to answer nearby requests. A new order ends this assignment."])
	var auto_frag:bool=units.all(func(u):return u.get("throw_policy","manual")=="defensive")
	commands.append(["auto_frag","AUTO FRAG","Allow defensive grenades at observed infantry groups with a covering teammate. Uses carried stock."])
	var hold:bool=units.all(func(u):return u.get("fire_policy","free")=="hold")
	var connected:=policy_sections(sim,units)
	var will_free:bool=connected.all(func(u):return u.get("fire_policy","free")=="hold")
	commands.append(["fire","H FIRE FREE" if will_free else "H HOLD FIRE","Toggle firing permission. Explicit grenade orders permit only that throw."])
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
		var reason:=command_reason(sim,units,item[0])
		hud.button("tactical:"+item[0],item[1],rect,reason.is_empty(),active)
		var values:Array=[]
		if item[0]=="reserve":values=units.map(func(u):return u.get("reserve_enabled",false))
		elif item[0]=="auto_frag":values=units.map(func(u):return u.get("throw_policy","manual")=="defensive")
		elif item[0]=="fire":values=units.map(func(u):return u.get("fire_policy","free")=="hold")
		var mixed:bool=values.has(true) and values.has(false)
		if mixed:hud.cv.draw_line(rect.position+Vector2(4,rect.size.y-3),rect.position+Vector2(rect.size.x-4,rect.size.y-3),hud.ORANGE,2)
		if rect.has_point(hud.pointer()):hovered=reason if reason!="" else (("Mixed selection · " if mixed else "")+str(item[2]))
	if hovered!="":
		var hint_width:float=minf(hud.battlefield_rect().size.x-24,hud.font.get_string_size(hovered,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x+20)
		hud.panel(Rect2(12,y-31,hint_width,26),hud.INK)
		hud.text_at(hud.fit_text(hovered,hint_width-16,12),Vector2(20,y-13),12,hud.WHITE)
		return
	draw_preview(hud,units)

# Structured work previews retain the executor's snapped footprint and paid
# cost. A resumed site must not advertise a new footprint or another charge.
static func target_preview(sim,units:Array,mode:String,point:Vector2)->Dictionary:
	var ids:Array=units.map(func(u):return u.id)
	if mode in ["frag","smoke"]:return sim.Throwables.preview_selection(sim,ids,mode,point)
	var site_id:=site_at(sim,point)
	var plan:Dictionary={"ok":false,"arc":[],"reason":"No member ready"}
	for u in units:
		plan=sim.FieldPositions.preview(sim,u,point) if mode=="dig" else sim.FieldPositions.upgrade_preview(sim,u,site_id)
		if not plan.ok:continue
		if mode=="dig":plan.reason="Resume shallow cover · no supply cost" if int(plan.site_id)>=0 else "Prepare shallow cover · no supply cost"
		else:plan.reason="Resume reinforcement · no supply cost" if float(plan.cost)==0 else "Reinforce position · %d supply"%int(plan.cost)
		return plan
	plan.reason=sim.FieldPositions.dig_reason(sim,ids,point) if mode=="dig" else sim.FieldPositions.upgrade_reason(sim,ids,site_id)
	return plan

func draw_preview(hud,units:Array)->void:
	var battle=hud.battle
	var sim=battle.sim
	var mode:String=battle.tactical_mode
	if mode.is_empty() or not hud.battlefield_rect().has_point(hud.pointer()) or hud.action_at(hud.pointer())!="":return
	# Top-layer drawing has its own hit list; existing opaque world/sidebar
	# panels and the guide still own input when the layers are combined.
	for part in 2:
		for region in hud.layer_blocked[part]:
			if region.has_point(hud.pointer()):return
	if hud.battlefield_ui.tutorial_rect(hud).has_point(hud.pointer()):return
	var point:Vector2=battle.world_pos(hud.pointer())
	var key:="%s:%s:%d:%d:%d"%[mode,battle.selected,roundi(point.x*3),roundi(point.y*3),int(sim.throwables.get("revision",0))]
	if key!=preview_key or Time.get_ticks_msec()-preview_at>=100:
		preview_key=key;preview_at=Time.get_ticks_msec()
		preview_data=target_preview(sim,units,mode,point)
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
		var rect:Rect2=preview_data.get("rect",sim.FieldOps.footprint(sim,"fighting_trench",center,false))
		for p in [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y),rect.position]:points.append(battle.screen_pos(p,0.15))
		hud.cv.draw_polyline(points,color,1.5,true)
	# A rejection from commitment may know more than the preview. Show that
	# acknowledgement alone until it expires, keeping the aiming geometry.
	if battle.notices.cursor_left>0:return
	var text:String="%s · %s"%[LABELS.get(mode,mode),preview_data.get("reason","")]
	var at:Vector2=hud.pointer()+Vector2(18,21)
	var text_width:float=minf(430,hud.font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x+16)
	at.x=clampf(at.x,8,hud.battlefield_rect().end.x-text_width-8)
	at.y=clampf(at.y,hud.battlefield_rect().position.y+8,hud.battlefield_rect().end.y-32)
	hud.panel(Rect2(at,Vector2(text_width,24)),hud.INK)
	hud.text_at(hud.fit_text(text,text_width-16,12),at+Vector2(8,17),12,color)
