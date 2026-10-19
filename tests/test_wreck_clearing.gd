extends SceneTree
# Clearing wrecks (black_sea_harbor). A tank (~62 t) shoves a light wreck (an
# IFV/AA hull, ~28 t) out of a street at a crawl and drives on; it cannot move
# a tank wreck. Engineers clear any wreck, a tank's too, given time, and the
# street opens to tanks again. A shoved wreck never goes into buildings, water
# or units.
const Sim=preload("res://scripts/simulation.gd")
const VehicleDamage=preload("res://scripts/vehicle_damage.gd")
const FieldOps=preload("res://scripts/field_ops.gd")
# An east-west street about 13 u between the house walls: a hull's margin
# round a wreck in the middle (2.45 + 2.45 u) closes it to tanks.
const LANE:=Vector2(355,509.5)
const WEST:=Vector2(330,509.5)
const EAST:=Vector2(385,509.5)
const LANE_Y:=Vector2(503.0,517.0)
const MARGIN:=2.45+2.45
const DT:=1.0/30.0
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func scenario_index(id:String)->int:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		if configs[i].id==id:return i
	return -1

func _init()->void:
	var started:=Time.get_ticks_usec()
	basics()
	push_light()
	tank_wreck_holds()
	engineer_clears()
	never_into_buildings()
	never_into_water()
	never_into_units()
	print("WRECK CLEARING: %d checks, %d failures (%.0f ms)" % [checks,failures,(Time.get_ticks_usec()-started)/1000.0])
	quit(0 if failures==0 else 1)

func fresh()->Object:
	var sim=Sim.new(false,scenario_index("black_sea_harbor"))
	# Only the test's units: the scenario's own forces stay out of the street.
	for u in sim.units:u.hp=0.0
	sim.field_ops.income_rate=0.0
	return sim

# A real kill: the hull knocked out where it stands becomes a wreck.
func wreck(sim,kind:String,pos:Vector2)->Dictionary:
	var hull:Dictionary=sim.spawn(kind,1,pos)
	hull.pos=pos
	hull.facing=Vector2.UP
	VehicleDamage.ensure_state(sim,hull)
	hull.hp-=VehicleDamage._finish(sim,hull,hull.hp+1.0)
	check(hull.get("wrecked",false),"%s wreck placed at %s" % [kind,pos])
	FieldOps.sync_obstacles(sim)
	return VehicleDamage.wrecks(sim).back()

func tank(sim,pos:Vector2,facing:Vector2=Vector2.RIGHT)->Dictionary:
	var u:Dictionary=sim.spawn("tank",0,pos)
	u.pos=pos
	u.facing=facing
	sim.rebuild_spatial()
	return u

func path_length(points:Array,from:Vector2)->float:
	var length:=0.0
	var last:=from
	for p in points:
		length+=last.distance_to(p)
		last=p
	return length

# Independent of the push code: the wreck's body (0.7 r, as its nav block)
# clear of building/wall footprints and of water.
func ground_ok(sim,p:Vector2,body:float)->bool:
	if sim.terrain.is_water(p) or sim.terrain.blocked(p):return false
	for k in 8:
		if sim.terrain.is_water(p+Vector2.from_angle(k*TAU/8.0)*body):return false
	for rect in sim.terrain._static_candidates("solid",p,body+0.12):
		if sim.terrain.circle_rect(p,body,rect) and not sim.terrain.crushables.has(rect):return false
	return true

func basics()->void:
	var sim=fresh()
	var t:=tank(sim,WEST)
	var ifv:Dictionary=sim.spawn("aa",0,WEST+Vector2(0,20))
	check(VehicleDamage.pusher(sim,t),"basics: a tank can shove wrecks")
	check(not VehicleDamage.pusher(sim,ifv),"basics: an IFV cannot")
	var light:=wreck(sim,"aa",LANE)
	var heavy:=wreck(sim,"tank",LANE+Vector2(0,60))
	check(VehicleDamage.light_wreck(light) and not VehicleDamage.light_wreck(heavy),"basics: an IFV wreck is light, a tank wreck is not")
	check(VehicleDamage.clear_seconds(heavy)>VehicleDamage.clear_seconds(light)*1.5,"basics: a tank wreck takes clearly longer to clear (%.0f s vs %.0f s)" % [VehicleDamage.clear_seconds(heavy),VehicleDamage.clear_seconds(light)])
	# Tracked planning passes the light wreck (as crushable props), not the heavy one.
	var through:Array=sim.terrain.path(WEST,EAST,"land",2.45,[],"tracked")
	check(not through.is_empty() and path_length(through,WEST)<WEST.distance_to(EAST)*1.2,"basics: a tank route runs through the light wreck (%.1f u)" % path_length(through,WEST))
	var foot:Array=sim.terrain.path(WEST,EAST,"land",2.65,[],"infantry")
	check(foot.is_empty() or path_length(foot,WEST)>WEST.distance_to(EAST)*1.2 or foot.all(func(p):return not light.nav_rect.grow(2.6).has_point(p)),"basics: infantry still route round it")

# A tank sent down the street shoves the IFV wreck aside and drives through.
func push_light()->void:
	var sim=fresh()
	var hulk:=wreck(sim,"aa",LANE)
	var start:Vector2=hulk.pos
	var u:=tank(sim,WEST)
	var body:float=float(hulk.radius)*0.7
	check(sim.issue([u.id],EAST,"move")==1,"push_light: order accepted")
	var arrived:=-1.0
	var pushed:=-1.0
	var in_lane:=true
	var ground:=true
	var overlap:=0.0
	var shown:=false
	var noted:=false
	var fastest:=0.0
	var last:Vector2=hulk.pos
	for step in int(40.0/DT):
		sim.tick(DT)
		for event in sim.events:if event.type=="warning" and "wreck aside" in str(event.text):noted=true
		sim.events.clear()
		if u.state=="PUSHING WRECK":shown=true
		fastest=maxf(fastest,hulk.pos.distance_to(last)/DT)
		last=hulk.pos
		if pushed<0.0 and hulk.pos.distance_to(start)>0.01:pushed=sim.time
		if u.pos.x>LANE.x-8.0 and u.pos.x<LANE.x+8.0 and (u.pos.y<LANE_Y.x or u.pos.y>LANE_Y.y):in_lane=false
		if not ground_ok(sim,hulk.pos,body):ground=false
		overlap=maxf(overlap,MARGIN-u.pos.distance_to(hulk.pos))
		if "trace" in OS.get_cmdline_user_args() and step%15==0:print("t=%.1f tank %s f%s %s b%.1f p%s | wreck %s stuck %.1f" % [sim.time,u.pos.snapped(Vector2(0.01,0.01)),u.facing.snapped(Vector2(0.01,0.01)),u.state,u.blocked_time,u.path.slice(0,3).map(func(q):return q.snapped(Vector2(0.1,0.1))),hulk.pos.snapped(Vector2(0.01,0.01)),float(hulk.get("stuck_until",-1))])
		if u.orders.is_empty():arrived=sim.time;break
	var moved:float=hulk.pos.distance_to(start)
	print("  push_light: shove at %.1f s, arrive %.1f s at %s, wreck moved %.2f u to %s, worst overlap %.2f u" % [pushed,arrived,u.pos.snapped(Vector2(0.01,0.01)),moved,hulk.pos.snapped(Vector2(0.01,0.01)),overlap])
	check(pushed>0.0,"push_light: the tank shoves the wreck")
	check(shown and noted,"push_light: the shove shows (PUSHING WRECK state, toast)")
	check(fastest<=VehicleDamage.PUSH_SPEED+0.01,"push_light: the wreck moves at a crawl (%.2f u/s at most)" % fastest)
	check(moved>=2.0,"push_light: the wreck is moved out of the tank's way (%.2f u)" % moved)
	check(arrived>0.0 and u.pos.distance_to(EAST)<3.0,"push_light: the tank drives through to the far end (%.1f s, %.2f u off)" % [arrived,u.pos.distance_to(EAST)])
	check(in_lane,"push_light: the tank went down the street, not round the block")
	check(ground,"push_light: the wreck stayed on open ground")
	check(overlap<0.1,"push_light: the hull never drove into the wreck (%.2f u)" % overlap)
	check(VehicleDamage.wrecks(sim).size()==1 and sim.get_unit(int(hulk.id)).get("wrecked",false),"push_light: it is still a wreck (cover, visuals)")
	check(sim.get_unit(int(hulk.id)).pos==hulk.pos,"push_light: the hull's presentation follows the wreck")
	# Field nav follows the wreck (within one nav step).
	check(hulk.has("nav_rect") and hulk.nav_rect.get_center().distance_to(hulk.pos)<=VehicleDamage.PUSH_NAV_STEP+0.01 and sim.terrain.dynamic_blocks.has(hulk.nav_rect),"push_light: the field nav block moved with the wreck")
	check(VehicleDamage.wreck_cover(sim,hulk.pos+Vector2(0,-3.0),hulk.pos+Vector2(0,20)) or VehicleDamage.wreck_cover(sim,hulk.pos+Vector2(-3.0,0),hulk.pos+Vector2(20,0)),"push_light: the wreck still gives cover in its new spot")

# The same street sealed by a tank wreck: the tank cannot move it.
func tank_wreck_holds()->void:
	var sim=fresh()
	var hulk:=wreck(sim,"tank",LANE)
	var start:Vector2=hulk.pos
	var u:=tank(sim,WEST)
	sim.issue([u.id],EAST,"move")
	var overlap:=0.0
	var pushing:=false
	for step in int(30.0/DT):
		sim.tick(DT)
		sim.events.clear()
		overlap=maxf(overlap,MARGIN-u.pos.distance_to(hulk.pos))
		if u.state=="PUSHING WRECK":pushing=true
	print("  tank_wreck_holds: tank at %s, wreck moved %.3f u, worst overlap %.2f u" % [u.pos.snapped(Vector2(0.01,0.01)),hulk.pos.distance_to(start),overlap])
	check(hulk.pos==start,"tank_wreck_holds: the tank wreck does not move")
	check(not pushing,"tank_wreck_holds: the tank never tries to shove it")
	check(overlap<0.1,"tank_wreck_holds: the tank never drives into it (%.2f u)" % overlap)
	var through:Array=sim.terrain.path(WEST,EAST,"land",2.45,[],"tracked")
	check(through.is_empty() or path_length(through,WEST)>WEST.distance_to(EAST)*1.3,"tank_wreck_holds: tracked planning does not pass the tank wreck")

# Engineers clear a tank wreck sealing the street; then tanks can drive it.
func engineer_clears()->void:
	var sim=fresh()
	var hulk:=wreck(sim,"tank",LANE)
	var hull_id:int=int(hulk.id)
	var bodies:Array=[{"pos":hulk.pos,"radius":MARGIN+0.3}]
	var before:Array=sim.terrain.path(WEST,EAST,"land",2.45,bodies,"tracked")
	var before_length:float=path_length(before,WEST) if not before.is_empty() else INF
	var engineer:Dictionary=sim.spawn("engineer",0,WEST)
	engineer.pos=WEST
	sim.rebuild_spatial()
	check(FieldOps.clear_site(sim,hull_id,engineer.id),"engineer_clears: clear order accepted (%s)" % sim.field_ops.get("last_build_error",""))
	check(int(engineer.get("clearing_id",-1))==hull_id and hulk.has("cleared_by"),"engineer_clears: engineers assigned to the wreck")
	var cleared:=-1.0
	var progress:=""
	var limit:float=VehicleDamage.clear_seconds(hulk)+30.0
	for step in int(limit/DT):
		sim.tick(DT)
		sim.events.clear()
		if str(engineer.reason).begins_with("Clearing wreck"):progress=engineer.reason
		if VehicleDamage.wrecks(sim).is_empty():cleared=sim.time;break
	print("  engineer_clears: cleared at %.1f s (job %.0f s), last progress '%s'" % [cleared,VehicleDamage.clear_seconds(hulk),progress])
	check(cleared>=VehicleDamage.clear_seconds(hulk),"engineer_clears: the wreck is cleared, taking the full job time (%.1f s)" % cleared)
	check(progress!="","engineer_clears: progress shown on the engineers")
	check(not sim.get_unit(hull_id).get("wrecked",false),"engineer_clears: the hull is gone from the map")
	check(not sim.terrain.dynamic_blocks.has(hulk.get("nav_rect",Rect2())),"engineer_clears: the field nav block is removed")
	check(not engineer.has("clearing_id"),"engineer_clears: the engineers are free again")
	var after:Array=sim.terrain.path(WEST,EAST,"land",2.45,[],"tracked")
	var after_length:float=path_length(after,WEST) if not after.is_empty() else INF
	print("  engineer_clears: tank route %.1f u before (round the wreck), %.1f u after" % [before_length,after_length])
	check(after_length<WEST.distance_to(EAST)*1.2,"engineer_clears: a tank route runs down the street (%.1f u)" % after_length)
	check(before_length>after_length+10.0,"engineer_clears: before, the street was closed to tanks (%.1f u vs %.1f u)" % [before_length,after_length])
	# The engineers step aside; a tank drives the street.
	sim.issue([engineer.id],Vector2(340,524),"move")
	var u:=tank(sim,WEST+Vector2(-12,0))
	sim.issue([u.id],EAST,"move")
	var arrived:=-1.0
	var in_lane:=true
	for step in int(30.0/DT):
		sim.tick(DT)
		sim.events.clear()
		if u.pos.x>LANE.x-8.0 and u.pos.x<LANE.x+8.0 and (u.pos.y<LANE_Y.x or u.pos.y>LANE_Y.y):in_lane=false
		if u.orders.is_empty():arrived=sim.time;break
	check(arrived>0.0 and u.pos.distance_to(EAST)<3.0 and in_lane,"engineer_clears: a tank drives down the cleared street (%.1f s)" % arrived)

# Direct shoves (the hull held still, nosing at the wreck) for the limits.
func shove(sim,u:Dictionary,hulk:Dictionary,axis:Vector2,seconds:float,watch:Callable)->bool:
	var ok:=true
	for step in int(seconds/DT):
		sim.time+=DT
		VehicleDamage.push_wreck(sim,u,u.pos+axis*0.2,axis,DT)
		if not watch.call():ok=false
	return ok

# A wreck against the house wall is not shoved into it.
func never_into_buildings()->void:
	var sim=fresh()
	# Just off the north wall of the street, the tank nosing at it from the
	# south-west so the shove would go north into the houses.
	var hulk:=wreck(sim,"aa",Vector2(345,506.0))
	var body:float=float(hulk.radius)*0.7
	var u:=tank(sim,hulk.pos+Vector2(-MARGIN+0.05,0.6))
	var ok:=shove(sim,u,hulk,Vector2.RIGHT,8.0,func():return ground_ok(sim,hulk.pos,body))
	print("  never_into_buildings: wreck at %s" % hulk.pos.snapped(Vector2(0.01,0.01)))
	check(ok,"never_into_buildings: the wreck never enters a building or wall")

# A wreck on the quay edge is not shoved into the basin.
func never_into_water()->void:
	var sim=fresh()
	var shore:=-1.0
	for x in range(380,470):
		if sim.terrain.is_water(Vector2(x,400)):shore=float(x);break
	check(shore>0.0,"never_into_water: found the basin's west quay (x %.0f)" % shore)
	if shore<0.0:return
	var hulk:=wreck(sim,"aa",Vector2(shore-3.0,400))
	var body:float=float(hulk.radius)*0.7
	var u:=tank(sim,hulk.pos+Vector2(-MARGIN+0.05,0.0))
	var dry:=func():return not sim.terrain.is_water(hulk.pos) and range(8).all(func(k):return not sim.terrain.is_water(hulk.pos+Vector2.from_angle(k*TAU/8.0)*body))
	var ok:=shove(sim,u,hulk,Vector2.RIGHT,8.0,dry)
	print("  never_into_water: shore x %.0f, wreck at %s" % [shore,hulk.pos.snapped(Vector2(0.01,0.01))])
	check(ok,"never_into_water: the wreck never goes into the water")

# Soldiers and a vehicle beside the wreck are never run over by it.
func never_into_units()->void:
	var sim=fresh()
	var open:=Vector2(300,640)
	var hulk:=wreck(sim,"aa",open)
	var section:Dictionary=sim.spawn("rifle",0,open+Vector2(1.5,4.2))
	section.pos=open+Vector2(1.5,4.2)
	for member in section.members:member.pos=section.pos+Vector2(randf_range(-1,1),randf_range(-1,1))
	var ifv:Dictionary=sim.spawn("aa",0,open+Vector2(1.5,-5.6))
	ifv.pos=open+Vector2(1.5,-5.6)
	var u:=tank(sim,open+Vector2(-MARGIN+0.05,0.0))
	var clear_of_units:=func():
		for member in section.members:
			if member.hp>0 and hulk.pos.distance_to(member.pos)<float(hulk.radius)*0.7+float(member.get("body_radius",0.8))+0.3-0.01:return false
		return hulk.pos.distance_to(ifv.pos)>=minf(float(hulk.radius)+2.45,open.distance_to(ifv.pos))-0.01
	var ok:=shove(sim,u,hulk,Vector2.RIGHT,8.0,clear_of_units)
	print("  never_into_units: wreck at %s" % hulk.pos.snapped(Vector2(0.01,0.01)))
	check(ok,"never_into_units: the wreck never closes on the soldiers or the IFV")
