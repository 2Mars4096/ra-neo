extends SceneTree
# Bombard and damage feedback (scripts/structure_damage.gd, audio_fx.gd,
# vehicle_damage.gd _report, garrison.gd exit memory):
#   1. a tank ordered to shell a building from a spot without a line to the
#      wall drives to a firing position and shells it;
#   2. with no firing position the order is refused with a warning; a unit that
#      loses its line and is out of re-plans gives up with the same warning;
#   3. building hits and collapses have their own sounds;
#   4. visible enemy vehicle component effects toast, rate-limited;
#   5. soldiers through the wall mid entry/exit get the building's leak factor
#      and are caught by its collapse.
const Sim=preload("res://scripts/simulation.gd")
const SD=preload("res://scripts/structure_damage.gd")
const VehicleDamage=preload("res://scripts/vehicle_damage.gd")
const Garrison=preload("res://scripts/garrison.gd")
const AudioFX=preload("res://scripts/audio_fx.gd")
const Body=preload("res://scripts/city_building_geometry.gd")
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func harbor_index()->int:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		if configs[i].id=="black_sea_harbor":return i
	return -1

func warnings(sim,text:String)->int:
	return sim.events.filter(func(e):return e.type=="warning" and text in str(e.text)).size()

func axis_aligned_body(building:Dictionary)->bool:
	# Collider count includes low porch/dock pieces and decomposition strips;
	# use the authored transform and physical wall shape for this fixture.
	var spec:Dictionary=building.spec
	return absf(fposmod(float(spec.rotation_degrees)+45.0,90.0)-45.0)<=0.001 and Body.ground_pieces(spec).filter(func(piece):return piece.wall).size()==1

# A spot within `reach` of the building's wall, open for `u`, with no line to the wall.
func blind_spot(sim,u:Dictionary,building:Dictionary,reach:float)->Vector2:
	var radius:float=float(sim.definitions[u.kind].radius)
	var center:Vector2=building.bounds.get_center()
	var half:float=maxf(building.bounds.size.x,building.bounds.size.y)*0.5
	for ring in [reach*0.5,reach*0.7,reach*0.35,reach*0.85]:
		for i in 36:
			var p:Vector2=center+Vector2.from_angle(i*TAU/36.0)*(half+ring)
			if p.distance_to(SD.wall_point(building,p))>reach:continue
			if not sim.terrain.traversable(p,"land",radius) or sim.terrain.is_water(p):continue
			if not SD.fire_line(sim,u,building,p):return p
	return Vector2.INF

func _init()->void:
	var harbor:=harbor_index()
	check(harbor>=0,"Harbor scenario exists")
	if harbor<0:quit(1);return
	bombard_checks(harbor)
	audio_checks()
	enemy_toast_checks(harbor)
	transit_checks(harbor)
	print("BOMBARD FEEDBACK: ",checks," checks, ",failures," failures")
	quit(1 if failures>0 else 0)

# --- 1/2. Firing positions -----------------------------------------------------------
func bombard_checks(harbor:int)->void:
	var sim=Sim.new(false,harbor)
	var tank:Dictionary=sim.spawn("tank",0,Vector2(300,640))
	var reach:float=float(sim.definitions.tank.range)*0.85
	var building:Dictionary={}
	var start:=Vector2.INF
	var spot:=Vector2.INF
	var search_us:=0
	var total_us:=0
	var searched:=0
	var none:=0
	# Prefer a blind spot whose firing position is a real drive away.
	for candidate in Garrison.index(sim).buildings:
		if not axis_aligned_body(candidate) or SD.integrity(candidate)>120.0:continue
		var p:=blind_spot(sim,tank,candidate,reach)
		if not p.is_finite():continue
		tank.pos=p
		var t0:=Time.get_ticks_usec()
		var found:=SD.firing_position(sim,tank,candidate,reach)
		var took:=Time.get_ticks_usec()-t0
		search_us=maxi(search_us,took);total_us+=took
		searched+=1
		if not found.is_finite():none+=1
		elif building.is_empty() or (start.distance_to(spot)<8.0 and p.distance_to(found)>start.distance_to(spot)):
			building=candidate;start=p;spot=found
		if searched>=40 or (not building.is_empty() and start.distance_to(spot)>=8.0):break
	print("BOMBARD search over %d blind spots: %d without a firing position, mean %.2f ms, worst %.2f ms" % [searched,none,total_us/1000.0/maxi(1,searched),search_us/1000.0])
	# Cost sweep: firing-position searches from the far side of the map (long or failing routes).
	var sweep:=0;var sweep_us:=0;var sweep_worst:=0;var sweep_none:=0
	tank.pos=Vector2(300,640)
	# The first route query builds the tracked nav grid (as any first tank route does).
	var warm:=Time.get_ticks_usec()
	SD.firing_position(sim,tank,Garrison.index(sim).buildings[0],reach)
	print("BOMBARD first search (builds the tracked nav grid once) %.1f ms" % ((Time.get_ticks_usec()-warm)/1000.0))
	for candidate in Garrison.index(sim).buildings:
		if sweep>=60:break
		if not axis_aligned_body(candidate):continue
		var t0:=Time.get_ticks_usec()
		if not SD.firing_position(sim,tank,candidate,reach).is_finite():sweep_none+=1
		var took:=Time.get_ticks_usec()-t0
		sweep+=1;sweep_us+=took;sweep_worst=maxi(sweep_worst,took)
	print("BOMBARD cost sweep: %d buildings from %s, %d without a firing position, mean %.2f ms, worst %.2f ms" % [sweep,str(tank.pos),sweep_none,sweep_us/1000.0/maxi(1,sweep),sweep_worst/1000.0])
	check(sweep_worst<20000,"worst firing-position search on a built grid stays small (%.2f ms)" % (sweep_worst/1000.0))
	check(not building.is_empty(),"found a building with a blind spot in range and a firing position (%d searched)" % searched)
	if building.is_empty():return
	print("BOMBARD %s #%d: blind start %s (%.1f m from wall), firing position %s (%.1f m from wall), search %.2f ms (worst of %d)" % [building.design,building.id,str(start),start.distance_to(SD.wall_point(building,start)),str(spot),spot.distance_to(SD.wall_point(building,spot)),search_us/1000.0,searched])
	check(not SD.fire_line(sim,tank,building,start),"the start spot has no line to the wall (the old order parked here silently)")
	check(SD.fire_line(sim,tank,building,spot) and spot.distance_to(SD.wall_point(building,spot))<=reach,"the firing position has a line to the wall within weapon range")
	check(search_us<30000,"firing-position search is cheap (%.2f ms)" % (search_us/1000.0))
	tank.pos=start
	check(SD.bombard(sim,[tank.id],building.id)==1,"tank accepts the fire mission from the blind spot")
	check(not tank.orders.is_empty() and tank.has("bombard_move"),"tank is sent to the firing position")
	var shots:=0
	var first_shot:=-1.0
	var arrived:=-1.0
	var damage_before:float=float(building.damage)
	for i in 30*40:
		sim.tick(1.0/30)
		if arrived<0.0 and tank.orders.is_empty():arrived=sim.time
		for e in sim.events:
			if e.type=="shot" and e.kind=="tank" and e.get("target_kind","")=="barracks":
				shots+=1
				if first_shot<0.0:first_shot=sim.time
		sim.events.clear()
		if shots>=2:break
	print("BOMBARD moved %.1f m, arrived %.1f s, first round at %.1f s, %d rounds, re-plans %d, building damage %.0f -> %.0f" % [start.distance_to(tank.pos),arrived,first_shot,shots,int(tank.get("bombard_replans",0)),damage_before,float(building.damage)])
	check(shots>=2 and float(building.damage)>damage_before,"tank reaches a firing position and shells the building (%d rounds)" % shots)
	check(SD.fire_line(sim,tank,building,tank.pos),"tank fires from a spot with a line to the wall")

	# No firing position: an emplacement cannot move off its blind spot.
	var s2=Sim.new(false,harbor)
	var gun:Dictionary=s2.spawn("at_gun",0,Vector2(300,640))
	var gun_spot:=Vector2.INF
	var gun_building:Dictionary={}
	for candidate in Garrison.index(s2).buildings:
		if not axis_aligned_body(candidate):continue
		gun_spot=blind_spot(s2,gun,candidate,float(s2.definitions.at_gun.range)*0.85)
		if gun_spot.is_finite():
			gun_building=candidate
			break
	check(gun_spot.is_finite(),"found a blind spot for an anti-tank gun")
	if gun_spot.is_finite():
		gun.pos=gun_spot
		s2.events.clear()
		check(SD.bombard(s2,[gun.id],gun_building.id)==0,"emplacement without a line refuses the fire mission")
		check(warnings(s2,SD.NO_POSITION)==1,"player told: '%s'" % SD.NO_POSITION)
		check(not gun.has("bombard"),"no silent fire mission is left behind")

	# Out of re-plans and off the line: the mission ends with the warning.
	var s3=Sim.new(false,harbor)
	var b3:Dictionary=Garrison.index(s3).buildings[building.id]
	var t3:Dictionary=s3.spawn("tank",0,spot)
	t3.pos=spot
	check(SD.bombard(s3,[t3.id],b3.id)==1 and t3.orders.is_empty(),"tank already on a firing position stays and fires")
	t3.pos=start
	t3.bombard_replans=SD.BOMBARD_REPLANS
	s3.events.clear()
	for i in 10:s3.tick(1.0/30)
	check(not t3.has("bombard") and warnings(s3,SD.NO_POSITION)==1,"tank off the line with no re-plans left gives up and says so")

# --- 3. Building sounds --------------------------------------------------------------
func audio_checks()->void:
	var audio=AudioFX.new()
	for name in ["thud","debris","rumble"]:
		var stream:AudioStreamWAV=audio.streams.get(name)
		check(stream!=null and stream.get_length()>0.3,"sound %s synthesized" % name)
	var focus:=Vector3(100,0,100)
	audio.frame(1.0/60,focus,Basis(),72.0)
	var played:int=audio.counters.played
	audio.event({"type":"building_damage","building":7,"state":0,"fraction":0.1,"impact":Vector2(104,98),"source":Vector2(90,90),"height":6.0,"visible":true})
	check(audio.last_start.has("thud") and audio.counters.played>played,"a building hit thuds")
	check(not audio.last_start.has("debris"),"a hit that does not change the state has no debris")
	audio.frame(0.5,focus,Basis(),72.0)
	audio.event({"type":"building_damage","building":7,"state":1,"fraction":0.4,"impact":Vector2(104,98),"source":Vector2(90,90),"height":6.0,"visible":true})
	for i in 30:audio.frame(1.0/60,focus,Basis(),72.0)
	check(audio.last_start.has("debris"),"a hit that holes the building to its next state drops debris")
	# A round still in flight: the thud waits for its impact.
	audio.frame(1.0,focus,Basis(),72.0)
	audio.event({"type":"shot","from":Vector2(70,100),"to":Vector2(110,104),"kind":"tank","target_kind":"barracks","hit":true,"from_y":1.0,"to_y":2.0,"visible":true})
	var thud_before:float=float(audio.last_start.get("thud",-1.0))
	audio.event({"type":"building_damage","building":8,"state":0,"fraction":0.1,"impact":Vector2(110,104),"source":Vector2(70,100),"height":6.0,"visible":true})
	check(float(audio.last_start.get("thud",-1.0))==thud_before and audio.pending.any(func(item):return item[1]=="thud"),"thud is timed with the round's impact")
	for i in 60:audio.frame(1.0/60,focus,Basis(),72.0)
	audio.frame(2.0,focus,Basis(),72.0)
	var booms:float=float(audio.last_start.get("boom_l",-1.0))
	audio.event({"type":"building_collapse","building":7,"pos":Vector2(104,96),"bounds":Rect2(98,92,12,8),"height":9.0,"killed":0,"survivors":0,"visible":true})
	# The collapse blast arrives as a world_blast in the same frame; it has no sound of its own.
	audio.event({"type":"world_blast","kind":"collapse","pos":Vector2(104,96),"visible":true})
	check(audio.last_start.has("rumble") and float(audio.last_start.rumble)==audio.clock,"a collapse rumbles")
	check(float(audio.last_start.get("boom_l",-1.0))==booms and not audio.pending.any(func(item):return item[1]=="boom_l"),"the collapse is not voiced as a tank kill")
	for i in 120:audio.frame(1.0/60,focus,Basis(),72.0)
	check(float(audio.last_start.get("debris",-1.0))>float(audio.last_start.rumble),"rubble pours down after the collapse")
	var distant:float=audio.distant_heat
	audio.event({"type":"building_collapse","building":9,"pos":Vector2(300,100),"bounds":Rect2(295,95,10,10),"height":9.0,"visible":true})
	check(audio.distant_heat>distant,"a far collapse is heard as distant combat")
	audio.free()

# --- 4. Enemy vehicle toasts -------------------------------------------------------------
func enemy_toast_checks(harbor:int)->void:
	var sim=Sim.new(false,harbor)
	var enemy:Dictionary=sim.spawn("tank",1,Vector2(300,640))
	enemy.visible=true
	VehicleDamage.ensure_state(sim,enemy)
	sim.events.clear()
	VehicleDamage._report(sim,enemy,"mobility","%s immobilised")
	check(warnings(sim,"Enemy tank immobilised")==1,"visible enemy tank immobilised is toasted")
	VehicleDamage._report(sim,enemy,"firepower","%s main gun disabled")
	check(warnings(sim,"Enemy")==1,"a second toast within %.0f s is held back" % VehicleDamage.ENEMY_NOTICE_GAP)
	sim.time+=VehicleDamage.ENEMY_NOTICE_GAP+0.1
	VehicleDamage._report(sim,enemy,"crew","%s crew casualty")
	check(warnings(sim,"Enemy")==1,"enemy crew casualties are not toasted")
	VehicleDamage._report(sim,enemy,"abandoned","%s crew bailed out · vehicle abandoned")
	check(warnings(sim,"Enemy tank crew bailed out")==1,"enemy crew bail-out toasted after the gap")
	sim.time+=VehicleDamage.ENEMY_NOTICE_GAP+0.1
	var hidden:Dictionary=sim.spawn("tank",1,Vector2(320,640))
	VehicleDamage.ensure_state(sim,hidden)
	VehicleDamage._report(sim,hidden,"mobility","%s immobilised")
	check(warnings(sim,"Enemy")==2,"damage to an unseen enemy is not toasted")
	var own:Dictionary=sim.spawn("tank",0,Vector2(340,640))
	VehicleDamage._report(sim,own,"mobility","%s immobilised")
	check(warnings(sim,"Tank immobilised")==1,"player vehicles still warn every time")
	# A burst of real hits at one instant: at most one enemy toast.
	var s2=Sim.new(false,harbor)
	var shooter:Dictionary=s2.spawn("tank",0,Vector2(300,640))
	var toasts:=0
	for n in 6:
		var target:Dictionary=s2.spawn("tank",1,Vector2(314,640+n*8))
		target.visible=true
		target.facing=Vector2.LEFT
		VehicleDamage.ensure_state(s2,target)
		for i in 40:
			if target.hp>0.0:VehicleDamage.strike(s2,shooter,target,s2.damage_amount(shooter,target))
	toasts=s2.events.filter(func(e):return e.type=="warning" and str(e.text).begins_with("Enemy")).size()
	var effects:int=s2.events.filter(func(e):return e.type=="vehicle_damage" and e.effect in VehicleDamage.ENEMY_NOTICE).size()
	print("ENEMY TOASTS: %d notable effects on 6 enemy tanks in one instant -> %d toast(s)" % [effects,toasts])
	check(effects>1 and toasts==1,"a burst of enemy damage gives one toast (%d effects)" % effects)

# --- 5. Garrison transit leak ------------------------------------------------------------
func sides(squad:Dictionary)->Array:
	var living:Array=squad.members.filter(func(m):return m.hp>0)
	var m_in:Array=living.filter(func(m):return m.get("indoors",false))
	var m_out:Array=living.filter(func(m):return not m.get("indoors",false))
	return [] if m_in.is_empty() or m_out.is_empty() else [m_in[0],m_out[0]]

func leak_pair(sim,squad:Dictionary,building:Dictionary,pair:Array,label:String)->void:
	var rifle:={"kind":"rifle","pos":squad.pos+Vector2(12,0),"team":1,"suppression":0.0,"state":"HOLDING","members":[],"visible":true}
	var state:int=building.state
	building.state=SD.BREACHED
	var leak_in:float=SD.strike(sim,rifle,squad,1.0,pair[0])
	var leak_out:float=SD.strike(sim,rifle,squad,1.0,pair[1])
	building.state=state
	print("%s walk, breached building: rifle leak indoors %.2f, outside %.2f" % [label,leak_in,leak_out])
	check(is_equal_approx(leak_in,SD.LEAK_SMALL[SD.BREACHED]),"%s: soldier through the wall gets the breached leak factor (%.2f)" % [label,leak_in])
	check(is_equal_approx(leak_out,1.0),"%s: soldier outside gets no building factor (%.2f)" % [label,leak_out])

func transit_checks(harbor:int)->void:
	var sim=Sim.new(false,harbor)
	var building:Dictionary={}
	var door:=Vector2(-1,-1)
	for candidate in Garrison.index(sim).buildings:
		if candidate.design!="stone_house" or not axis_aligned_body(candidate) or int(candidate.spec.damage)!=0:continue
		door=Garrison.entry_point(sim,candidate.id,candidate.bounds.get_center()+Vector2(0,30))
		if door.x>=0:building=candidate;break
	check(not building.is_empty(),"found an axis-aligned stone house with a reachable doorway")
	if building.is_empty():return
	var squad:Dictionary=sim.spawn("rifle",0,door+Vector2(0,6))
	check(Garrison.order(sim,[squad.id],building.id)==1,"garrison order accepted")
	var entry:=false
	for i in 600:
		sim.tick(1.0/30)
		if not entry and Garrison.transit(squad)=="IN" and not sides(squad).is_empty():
			leak_pair(sim,squad,building,sides(squad),"entry");entry=true
		if Garrison.inside(squad):break
	check(entry and Garrison.inside(squad),"entry walk seen, section inside")
	sim.issue([squad.id],door+Vector2(0,14),"move")
	sim.tick(1.0/30)
	check(int(squad.get("garrison_exit",-1))==building.id,"leaving section remembers the building")
	var exit:=false
	for i in 120:
		if Garrison.transit(squad)=="OUT" and not sides(squad).is_empty():
			leak_pair(sim,squad,building,sides(squad),"exit");exit=true;break
		sim.tick(1.0/30)
	check(exit,"exit walk seen with soldiers on both sides of the wall")
	for i in 300:
		sim.tick(1.0/30)
		if Garrison.transit(squad)=="":break
	check(Garrison.transit(squad)=="" and not squad.has("garrison_exit"),"exit memory cleared once everyone is out")
	# A collapse while the section files out catches those still inside.
	var s2=Sim.new(false,harbor)
	var b2:Dictionary=Garrison.index(s2).buildings[building.id]
	var squad2:Dictionary=s2.spawn("rifle",0,door)
	squad2["garrison_door"]=door
	Garrison.enter(s2,squad2,b2.id)
	Garrison.leave(s2,squad2)
	var living:int=squad2.members.filter(func(m):return m.hp>0).size()
	SD.collapse(s2,b2.id)
	var hurt:int=squad2.members.filter(func(m):return m.hp<=0 or m.get("wound",s2.Infantry.HEALTHY)!=s2.Infantry.HEALTHY).size()
	print("COLLAPSE during exit: %d of %d soldiers inside hurt or killed" % [hurt,living])
	check(hurt>0 and not squad2.has("garrison_exit") and Garrison.transit(squad2)=="","collapse during the exit walk catches the soldiers inside and ends the walk")
