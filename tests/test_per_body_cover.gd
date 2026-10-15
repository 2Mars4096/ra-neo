extends SceneTree
# Per-soldier consistency of the damage side systems: sandbag wear leak, the
# HE impact point on a garrisoned building, wreck cover and garrison posture
# all follow the soldier actually struck (the victim threaded through
# resolve_shot), not the section centre or the soldier nearest the shooter.
const Sim=preload("res://scripts/simulation.gd")
const SD=preload("res://scripts/structure_damage.gd")
const VehicleDamage=preload("res://scripts/vehicle_damage.gd")
const Garrison=preload("res://scripts/garrison.gd")
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

const BASE:=Vector2(300,640)

func open_ground(sim,near:Vector2,radius:float=4.0)->Vector2:
	for ring in range(0,30):
		for i in 16:
			var p:Vector2=near+Vector2.from_angle(i*TAU/16.0)*ring*2.0
			if sim.terrain.traversable(p,"land",radius) and not sim.terrain.is_water(p):return p
	return Vector2(-1,-1)

func _init()->void:
	sandbags()
	garrison_impact()
	wreck_cover()
	print("PER-BODY COVER: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)

# A half-worn sandbag work: the soldier behind it gets its (reduced) protection,
# a squadmate in the open gets none, whichever of them is nearer the shooter.
func sandbags()->void:
	var sim=Sim.new(false,scenario_index("black_sea_harbor"))
	var bag_pos:Vector2=open_ground(sim,BASE+Vector2(40,0),6.0)
	var bags:Dictionary=sim.spawn("tactical_cover",0,bag_pos)
	bags.build_left=0.0
	sim.FieldOps.sync_obstacles(sim)
	bags.hp=bags.max_hp*0.5
	var squad:Dictionary=sim.spawn("rifle",0,bag_pos+Vector2(0,3))
	var shooter:Dictionary=sim.spawn("rifle",1,bag_pos+Vector2(0,-12))
	var covered:Dictionary=squad.members[0]
	var exposed:Dictionary=squad.members[1]
	for m in squad.members:m.pos=bag_pos+Vector2(-8,9)
	covered.pos=bag_pos+Vector2(0,1.4)
	# Open ground nearer the shooter than the man behind the bags.
	exposed.pos=bag_pos+Vector2(6,-4)
	check(sim.terrain.cover(covered.pos) and not sim.terrain.cover(exposed.pos),"one soldier behind sandbags, one in the open")
	var worn:float=1.0+(1.0/SD.COVER_SCALE-1.0)*0.5
	var leak_covered:float=SD.sandbag_leak(sim,shooter,squad,covered)
	var leak_exposed:float=SD.sandbag_leak(sim,shooter,squad,exposed)
	var leak_nearest:float=SD.sandbag_leak(sim,shooter,squad)
	print("SANDBAG leak (half worn): victim behind bags %.2f, victim in open %.2f, no victim (nearest) %.2f" % [leak_covered,leak_exposed,leak_nearest])
	check(is_equal_approx(leak_covered,worn),"worn bags leak to the soldier behind them (%.2f)" % leak_covered)
	check(leak_exposed==1.0,"no sandbag factor for a victim in the open")
	check(leak_nearest==leak_exposed,"without a victim the legacy nearest-soldier rule applies")
	check(is_equal_approx(SD.strike(sim,shooter,squad,1.0,covered),worn) and SD.strike(sim,shooter,squad,1.0,exposed)==1.0,"strike passes the victim to the sandbag leak")
	# Net damage per victim matches damage_amount's per-soldier cover factor.
	var net_covered:float=sim.damage_amount(shooter,squad,covered)*SD.strike(sim,shooter,squad,1.0,covered)
	var net_exposed:float=sim.damage_amount(shooter,squad,exposed)*SD.strike(sim,shooter,squad,1.0,exposed)
	print("SANDBAG net damage per hit: behind bags %.2f, in open %.2f" % [net_covered,net_exposed])
	check(net_covered<net_exposed*0.85 and net_covered>net_exposed*SD.COVER_SCALE,"half-worn bags still protect their soldier, less than intact ones")
	# Reverse: the man behind the bags is nearest, the victim stands in the open farther back.
	exposed.pos=bag_pos+Vector2(7,9)
	check(not sim.terrain.cover(exposed.pos),"rear soldier in the open")
	check(SD.sandbag_leak(sim,shooter,squad)>1.0 and SD.sandbag_leak(sim,shooter,squad,exposed)==1.0,"the victim's position decides, not the soldier nearest the shooter")

# An HE round on a garrison bursts on the wall at the struck soldier's window.
func garrison_impact()->void:
	var sim=Sim.new(false,scenario_index("black_sea_harbor"))
	var block:Dictionary={}
	for building in Garrison.index(sim).buildings:
		if SD.integrity(building)>=400.0 and Garrison.entry_point(sim,building.id,building.bounds.get_center()+Vector2(0,40)).x>=0:block=building;break
	check(not block.is_empty(),"found a large building")
	if block.is_empty():return
	var door:Vector2=Garrison.entry_point(sim,block.id,block.bounds.get_center()+Vector2(0,40))
	var holders:Dictionary=sim.spawn("rifle",0,door)
	holders["garrison_door"]=door
	Garrison.enter(sim,holders,block.id)
	var gun:={"kind":"tank","pos":block.bounds.get_center()+Vector2(0,40),"team":1}
	var far:Dictionary={}
	for m in holders.members:
		if m.hp>0 and (far.is_empty() or m.pos.distance_squared_to(gun.pos)>far.pos.distance_squared_to(gun.pos)):far=m
	sim.events.clear()
	SD.strike(sim,gun,holders,1.0,far)
	SD.strike(sim,gun,holders,1.0)
	var impacts:Array=sim.events.filter(func(e):return e.type=="building_damage").map(func(e):return e.impact)
	check(impacts.size()==2,"both HE rounds strike the building")
	if impacts.size()<2:return
	var at_window:Vector2=SD.wall_point(block,far.pos)
	print("GARRISON HE impact: victim's window %s (victim %.1f m off), no victim %s" % [str(impacts[0]),impacts[0].distance_to(far.pos),str(impacts[1])])
	check(impacts[0].distance_to(at_window)<0.01 and impacts[0].distance_to(far.pos)<2.0,"round bursts at the struck soldier's window")
	check(impacts[1].distance_to(SD.wall_point(block,gun.pos))<0.01,"without a victim the wall facing the gun is struck")
	# Garrison posture is per soldier too: a prone defender is the smaller target.
	var rifles:Dictionary=sim.spawn("rifle",1,gun.pos)
	var prone:Dictionary=holders.members[0]
	var crouched:Dictionary=holders.members[1]
	prone.posture="PRONE";crouched.posture="CROUCHED"
	crouched.pos=prone.pos
	var e_prone:float=sim.infantry_exposure(rifles,holders,prone)
	var e_crouched:float=sim.infantry_exposure(rifles,holders,crouched)
	check(is_equal_approx(e_prone/e_crouched,0.5/0.75),"garrison exposure follows the aimed soldier's posture (%.3f vs %.3f)" % [e_prone,e_crouched])

# A wreck shields the soldier behind it only; his squadmate on the shooter's
# side of the hull is unaffected, and the struck soldier is the one that counts.
func wreck_cover()->void:
	var sim=Sim.new(false,scenario_index("classic"))
	var spot:=Vector2(-1,-1)
	for x in range(10,86,2):
		for y in range(10,62,2):
			var p:=Vector2(x,y)
			if spot.x<0 and not sim.terrain.cover(p) and not sim.terrain.cover(p+Vector2(4,0)) and not sim.terrain.cover(p+Vector2(-2.5,0)) and sim.terrain.traversable(p,"land",1.0) and sim.terrain.line_clear(p,p+Vector2(18,0)):spot=p
	check(spot.x>=0,"open ground for the wreck test")
	if spot.x<0:return
	var shooter:Dictionary=sim.spawn("rifle",1,spot+Vector2(18,0))
	var squad:Dictionary=sim.spawn("rifle",0,spot+Vector2(-2.5,0))
	shooter.state="READY"
	for m in squad.members:m.pos=spot+Vector2(-2.5,0);m.posture="STANDING";m.in_trench=false
	var behind:Dictionary=squad.members[0]
	var front:Dictionary=squad.members[1]
	front.pos=spot+Vector2(4,0)
	var behind_open:float=sim.infantry_exposure(shooter,squad,behind)
	var front_open:float=sim.infantry_exposure(shooter,squad,front)
	var hull:Dictionary=sim.spawn("tank",1,spot)
	hull.facing=Vector2.UP
	hull.hp-=VehicleDamage._finish(sim,hull,hull.hp+1.0)
	var behind_wreck:float=sim.infantry_exposure(shooter,squad,behind)
	var front_wreck:float=sim.infantry_exposure(shooter,squad,front)
	var nearest:float=sim.infantry_exposure(shooter,squad)
	print("WRECK exposure: soldier behind %.3f -> %.3f, soldier in front %.3f -> %.3f, no victim %.3f" % [behind_open,behind_wreck,front_open,front_wreck,nearest])
	check(is_equal_approx(behind_wreck,behind_open*0.7),"wreck covers the soldier behind it")
	check(is_equal_approx(front_wreck,front_open),"no wreck cover for the soldier on the shooter's side")
	check(is_equal_approx(nearest,front_wreck),"without a victim the soldier nearest the shooter is used")
