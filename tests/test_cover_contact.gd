extends SceneTree
# Real soldier approaches to field works: their protected destinations must
# agree with terrain clearance, actor collision and the visible arrival state.
const Sim=preload("res://scripts/simulation.gd")
const Cover=preload("res://scripts/cover_behavior.gd")
const Infantry=preload("res://scripts/infantry.gd")
const BASE:=Vector2(312,640)
const STEP:=1.0/30.0
var failures:=0
var checks:=0
var harbor:=-1

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func fixture():
	var sim=Sim.new(false,harbor)
	sim.objectives.clear()
	sim.field_ops.enemy_insertion=BASE+Vector2(0,-100)
	return sim

func work(sim,kind:String,pos:Vector2,rotated:bool=false)->Dictionary:
	sim.FieldOps.spawn_prepared_works(sim,[{"kind":kind,"position":pos,"rotated":rotated}],0)
	return sim.units.back()

func footprint(sim,site:Dictionary)->Rect2:
	return sim.FieldOps.footprint(sim,site.kind,site.pos,site.get("rotated",false))

func edge_distance(point:Vector2,rect:Rect2)->float:
	return point.distance_to(point.clamp(rect.position,rect.end))

func check_slot_spacing(slots:Array,label:String)->void:
	var separated:=true
	for i in slots.size():
		for j in range(i+1,slots.size()):separated=separated and slots[i].distance_to(slots[j])>=1.6
	check(separated,label+" reserved positions fit separate standing bodies")

func advance(sim,squad:Dictionary,seconds:float,label:String)->void:
	var clear:=true
	var separated:=true
	var honest_arrival:=true
	for frame in roundi(seconds/STEP):
		sim.tick(STEP)
		for m in squad.members:
			if m.hp<=0:continue
			clear=clear and sim.terrain.traversable(m.pos,"land",m.body_radius)
			if m.get("cover_phase","")=="SHELTERED":honest_arrival=honest_arrival and m.pos.distance_to(m.cover_goal)<=0.21
			for peer in squad.members:
				if peer.index>m.index and peer.hp>0:separated=separated and m.pos.distance_to(peer.pos)>=1.54
		sim.events.clear()
	check(sim.result=="",label+" runs all requested ticks")
	check(clear,label+" soldiers never enter solid scenery")
	check(separated,label+" soldier bodies remain separated")
	check(honest_arrival,label+" sheltered state follows actual arrival")

func sheltered(sim,member:Dictionary)->bool:
	return member.hp>0 and member.get("cover_phase","")=="SHELTERED" and sim.terrain.cover(member.pos)

func _init()->void:
	var presets:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in presets.size():
		if presets[i].id=="black_sea_harbor":harbor=i;break
	check(harbor>=0,"Harbor fixture exists")
	if harbor<0:quit(1);return
	for rotated in [false,true]:sandbag_arrival(rotated)
	adjoining_sandbags()
	flank_approach()
	for rotated in [false,true]:destroyed_trench(rotated)
	partial_occupation()
	shared_work_reservations()
	work_outside_leash()
	collision_controls()
	print("COVER CONTACT: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)

func sandbag_arrival(rotated:bool)->void:
	var sim=fixture()
	var rear:=Vector2.RIGHT if rotated else Vector2.DOWN
	sim.field_ops.enemy_insertion=BASE-rear*100.0
	var bags:=work(sim,"tactical_cover",BASE,rotated)
	var squad:Dictionary=sim.spawn("rifle",0,BASE+rear*6.0)
	var rect:=footprint(sim,bags)
	var label:="rotated sandbag" if rotated else "normal sandbag"
	check(bags.pos==BASE and squad.pos==BASE+rear*6.0,label+" fixture spawns at requested positions")
	var slots:Array=Cover.work_slots(squad,sim,-rear)
	check(slots.size()>=2,label+" offers at least two face positions")
	check_slot_spacing(slots,label)
	check(slots.all(func(p):return sim.terrain.traversable(p,"land",0.8)),label+" face positions clear the standing body")
	check(slots.all(func(p):return sim.terrain.cover(p) and edge_distance(p,rect)<=1.2),label+" face positions are close and protected")
	advance(sim,squad,12.0,label)
	var close:int=squad.members.filter(func(m):return sheltered(sim,m) and edge_distance(m.pos,rect)<=1.2).size()
	check(close>=2,label+" at least two soldiers naturally settle close to the wall (%d)" % close)
	check(not squad.members.any(func(m):return m.get("cover_phase","")=="SEEKING" and m.get("cover_blocked",0.0)>2.1),label+" has no indefinitely blocked cover runner")
	print("SANDBAG ",label," close sheltered=",close)

func adjoining_sandbags()->void:
	var sim=fixture()
	var left:=work(sim,"tactical_cover",BASE)
	var right:=work(sim,"tactical_cover",BASE+Vector2(2.8,0))
	# Seed two contiguous static works before any soldiers exist. The generic
	# spawn-circle clearance otherwise moves the second structure away.
	right.pos=BASE+Vector2(2.8,0)
	right.home=right.pos
	sim.field_ops.obstacle_key=""
	sim.FieldOps.sync_obstacles(sim)
	var squad:Dictionary=sim.spawn("rifle",0,BASE+Vector2(1.4,6))
	check(left.pos==BASE and right.pos.distance_to(BASE+Vector2(2.8,0))<0.001,"contiguous static sandbag fixture retains its authored spacing")
	var protected_faces:Array=[footprint(sim,left),footprint(sim,right)]
	var clear:=true
	var separated:=true
	var reservations_fit:=true
	var cover_decisions:=0
	var paths_before:int=sim.terrain.path_calls
	for frame in 480:
		sim.tick(STEP)
		for m in squad.members:
			clear=clear and sim.terrain.traversable(m.pos,"land",m.body_radius)
			for peer in squad.members:
				if peer.index<=m.index:continue
				separated=separated and m.pos.distance_to(peer.pos)>=1.54
				if m.get("cover_phase","") in ["SEEKING","SETTLING","SHELTERED"] and peer.get("cover_phase","") in ["SEEKING","SETTLING","SHELTERED"]:
					reservations_fit=reservations_fit and m.cover_goal.distance_to(peer.cover_goal)>=1.6
		for event in sim.events:
			if event.get("type","")=="decision" and event.get("phase","")=="COVER":cover_decisions+=1
		sim.events.clear()
	check(sim.result=="" and sim.time>=15.99,"adjoining-work fixture runs sixteen seconds")
	check(clear and separated,"adjoining works preserve terrain clearance and separate bodies")
	check(reservations_fit,"active goals on adjoining works leave room for separate soldiers")
	check(squad.members.all(func(m):return sheltered(sim,m) and protected_faces.any(func(rect):return edge_distance(m.pos,rect)<=1.2)),"all three soldiers naturally settle close to adjoining works")
	check(not Cover.seeking(squad),"adjoining works leave no stalled cover runner")
	check(cover_decisions<=6 and sim.terrain.path_calls-paths_before<=36,"adjoining works settle with bounded decisions and routes")

func flank_approach()->void:
	var sim=fixture()
	sim.field_ops.enemy_insertion=BASE+Vector2(-70,-70)
	var bags:=work(sim,"tactical_cover",BASE)
	var squad:Dictionary=sim.spawn("rifle",0,BASE+Vector2(6,0))
	# Previously the first route waypoint was terrain-clear but inside the
	# sandbag's additional actor circle. The soldier stood SEEKING indefinitely.
	advance(sim,squad,12.0,"sandbag flank approach")
	var rect:=footprint(sim,bags)
	var close:int=squad.members.filter(func(m):return sheltered(sim,m) and edge_distance(m.pos,rect)<=1.2).size()
	# Which soldier can safely approach first depends on the squadmate detour.
	check(close>=2,"flank approach fills both close protected wall positions (%d)" % close)
	check(not squad.members.any(func(m):return m.get("cover_phase","")=="SEEKING" and m.get("cover_blocked",0.0)>2.1),"flank approach does not stall at a terrain-valid waypoint")

func destroyed_trench(rotated:bool)->void:
	var sim=fixture()
	var rear:=Vector2.RIGHT if rotated else Vector2.DOWN
	sim.field_ops.enemy_insertion=BASE-rear*100.0
	var trench:=work(sim,"fighting_trench",BASE,rotated)
	var squad:Dictionary=sim.spawn("rifle",0,BASE+rear*6.0)
	var label:="rotated trench" if rotated else "normal trench"
	check_slot_spacing(Cover.work_slots(squad,sim,-rear),label)
	advance(sim,squad,6.0,label+" arrival")
	check(squad.members.all(func(m):return sheltered(sim,m)),label+" soldiers naturally settle before destruction")
	trench.hp=0.0
	sim.FieldOps.sync_obstacles(sim)
	advance(sim,squad,12.0,label+" destruction")
	check(not squad.members.any(func(m):return m.get("occupying",false) and not sim.terrain.cover(m.cover_goal)),label+" destruction clears unprotected occupation")
	check(not squad.members.any(func(m):return m.get("cover_phase","")=="SHELTERED" and not sim.terrain.cover(m.pos)),label+" destruction cannot leave false sheltered bodies")

func partial_occupation()->void:
	var sim=fixture()
	var left:=work(sim,"fighting_trench",BASE)
	var right:=work(sim,"fighting_trench",BASE+Vector2(8,0))
	var squad:Dictionary=sim.spawn("rifle",0,BASE+Vector2(4,6))
	advance(sim,squad,8.0,"two-trench arrival")
	var left_rect:=footprint(sim,left)
	var right_rect:=footprint(sim,right)
	var displaced:Array=squad.members.filter(func(m):return sheltered(sim,m) and left_rect.has_point(m.pos))
	var retained:Array=squad.members.filter(func(m):return sheltered(sim,m) and right_rect.has_point(m.pos))
	check(not displaced.is_empty() and not retained.is_empty(),"natural occupation splits between two separate works")
	var retained_goals:Array=retained.map(func(m):return m.cover_goal)
	left.hp=0.0
	sim.FieldOps.sync_obstacles(sim)
	advance(sim,squad,16.0,"partial trench destruction")
	check(not displaced.is_empty() and displaced.all(func(m):return sheltered(sim,m)),"displaced soldiers can acquire new shelter while squadmates occupy surviving work")
	var kept:=not retained.is_empty()
	for i in retained.size():kept=kept and sheltered(sim,retained[i]) and retained[i].cover_goal==retained_goals[i]
	check(kept,"valid occupants keep their surviving shelter")

func shared_work_reservations()->void:
	var sim=fixture()
	work(sim,"fighting_trench",BASE)
	var first:Dictionary=sim.spawn("rifle",0,BASE+Vector2(0,6))
	advance(sim,first,6.0,"first section at shared trench")
	check(first.members.all(func(m):return sheltered(sim,m)),"first section naturally occupies the shared trench")
	var second:Dictionary=sim.spawn("rifle",0,BASE+Vector2(4,8))
	var reservations_fit:=true
	var bodies_fit:=true
	var decisions:=0
	var paths_before:int=sim.terrain.path_calls
	for frame in 300:
		sim.tick(STEP)
		for member in first.members:
			for peer in second.members:
				bodies_fit=bodies_fit and member.pos.distance_to(peer.pos)>=1.54
				if member.get("cover_phase","") in ["SEEKING","SETTLING","SHELTERED"] and peer.get("cover_phase","") in ["SEEKING","SETTLING","SHELTERED"]:
					reservations_fit=reservations_fit and member.cover_goal.distance_to(peer.cover_goal)>=1.6
		for event in sim.events:
			if event.get("type","")=="decision" and event.get("phase","")=="COVER":decisions+=1
		sim.events.clear()
	check(reservations_fit and bodies_fit,"nearby sections reserve separate work goals and retain body clearance")
	check(second.members.any(func(m):return sheltered(sim,m)),"another section can naturally fill remaining shared-work space")
	check(sim.result=="" and decisions<=6 and sim.terrain.path_calls-paths_before<=36,"shared-work searches remain bounded while valid occupants stay put")

func work_outside_leash()->void:
	var sim=fixture()
	sim.field_ops.enemy_insertion=Vector2(300,500)
	var bags:=work(sim,"tactical_cover",Vector2(300,665))
	var squad:Dictionary=sim.spawn("rifle",0,Vector2(300,677))
	check(bags.pos==Vector2(300,665) and squad.pos==Vector2(300,677),"leash fixture spawns at requested positions")
	check(Cover.work_slots(squad,sim,Vector2.UP).all(func(p):return p.distance_to(squad.pos)<=Cover.LEASH),"work positions stay inside the soldier leash")
	var bounded_goals:=true
	var bounded_waypoints:=true
	var cover_decisions:=0
	var paths_before:int=sim.terrain.path_calls
	for frame in 300:
		sim.tick(STEP)
		for m in squad.members:
			if m.cover_goal!=Vector2.ZERO:bounded_goals=bounded_goals and m.cover_goal.distance_to(squad.pos)<=Cover.LEASH
			for point in m.cover_path:bounded_waypoints=bounded_waypoints and point.distance_to(squad.pos)<=Cover.LEASH
		for event in sim.events:
			if event.get("type","")=="decision" and event.get("phase","")=="COVER":cover_decisions+=1
		sim.events.clear()
	check(sim.result=="" and sim.time>=9.99,"leash fixture runs ten seconds")
	check(bounded_goals,"occupation never assigns an unreachable goal beyond the leash")
	check(bounded_waypoints,"occupation routes never leave the leash")
	# Allow two normal searches, each considering three soldiers and up to six
	# routes apiece. Reassigning invalid works on every threat scan exceeded both.
	check(cover_decisions<=6,"out-of-reach work does not cause repeated manning decisions (%d)" % cover_decisions)
	check(sim.terrain.path_calls-paths_before<=36,"out-of-reach work keeps route attempts bounded (%d)" % (sim.terrain.path_calls-paths_before))

func collision_controls()->void:
	var sim=fixture()
	work(sim,"tactical_cover",BASE)
	var squad:Dictionary=sim.spawn("rifle",0,BASE+Vector2(0,6))
	var member:Dictionary=squad.members[0]
	member.pos=BASE+Vector2(0,3)
	var face:=BASE+Vector2(0,1.45)
	check(sim.terrain.segment_clear(member.pos,face,"land",0.8),"close wall face control is terrain-clear")
	sim.rebuild_actor_spatial();sim.ticking=true
	for indexed in [true,false]:
		sim.use_actor_index=indexed
		check(Infantry.actor_clear(squad,member,face,sim),"rectangular field-work clearance matches terrain (indexed=%s)" % indexed)
		check(not Infantry.actor_clear(squad,member,BASE+Vector2(0,-3),sim),"solid wall still blocks crossing (indexed=%s)" % indexed)
	sim.ticking=false
	var mobile=fixture()
	var section:Dictionary=mobile.spawn("rifle",0,BASE+Vector2(0,6))
	var tank:Dictionary=mobile.spawn("tank",0,BASE)
	check(tank.pos==BASE,"mobile actor control spawns in open ground")
	var soldier:Dictionary=section.members[0]
	var into_tank:=BASE+Vector2(0,2.5)
	check(mobile.terrain.segment_clear(soldier.pos,into_tank,"land",0.8),"mobile actor control has no terrain blocker")
	mobile.rebuild_actor_spatial();mobile.ticking=true
	for indexed in [true,false]:
		mobile.use_actor_index=indexed
		check(not Infantry.actor_clear(section,soldier,into_tank,mobile),"mobile vehicle retains body clearance (indexed=%s)" % indexed)
		check(Infantry.actor_clear(section,soldier,soldier.pos+Vector2(0,0.08),mobile),"a safe step away from the vehicle remains possible (indexed=%s)" % indexed)
		check(not Infantry.actor_clear(section,soldier,section.members[1].pos,mobile),"squadmate body clearance remains intact (indexed=%s)" % indexed)
	mobile.ticking=false
