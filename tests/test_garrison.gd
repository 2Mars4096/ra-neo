extends SceneTree
# Infantry garrisons: enter a city building, fire from windows, take less damage, leave on order.
const Sim=preload("res://scripts/simulation.gd")
const Garrison=preload("res://scripts/garrison.gd")
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)
# One soldier through the wall, one still outside: protection is per soldier
# (damage, exposure, suppression), while the section itself is not yet/no longer inside.
func sides(squad:Dictionary)->Array:
	var living:Array=squad.members.filter(func(m):return m.hp>0)
	var m_in:Array=living.filter(func(m):return m.get("indoors",false))
	var m_out:Array=living.filter(func(m):return not m.get("indoors",false))
	return [] if m_in.is_empty() or m_out.is_empty() else [m_in[0],m_out[0]]
func compare_sides(sim,squad:Dictionary,pair:Array,label:String)->void:
	var door:Vector2=squad.get("garrison_door",squad.pos)
	var wall:Vector2=squad.get("garrison_wall",door)
	var outward:Vector2=(door-wall).normalized() if door.distance_to(wall)>0.01 else Vector2.RIGHT
	var shooter:={"id":-99,"kind":"rifle","team":1,"pos":door+outward*12.0,"state":"HOLDING","suppression":0.0,"visible":false}
	var d_in:float=sim.damage_amount(shooter,squad,pair[0])
	var d_out:float=sim.damage_amount(shooter,squad,pair[1])
	var base:float=float(sim.definitions.rifle.damage)*float(sim.effectiveness.rifle[squad.kind])
	check(is_equal_approx(d_in,base*Garrison.DAMAGE_SCALE) and d_in<d_out*0.7,"%s: soldier indoors takes garrison damage (%.2f vs %.2f)" % [label,d_in,d_out])
	var e_in:float=sim.infantry_exposure(shooter,squad,pair[0])
	var e_out:float=sim.infantry_exposure(shooter,squad,pair[1])
	check(e_in<e_out,"%s: soldier indoors is harder to hit (%.3f vs %.3f)" % [label,e_in,e_out])
	# Zero-scale shots: suppression only, no wounds.
	var before:float=squad.suppression
	squad.suppression=0.0
	sim.resolve_shot(shooter,squad,0.0,pair[0])
	var s_in:float=squad.suppression
	squad.suppression=0.0
	sim.resolve_shot(shooter,squad,0.0,pair[1])
	var s_out:float=squad.suppression
	squad.suppression=before
	check(s_in<s_out*0.5,"%s: fire at the soldier indoors pins less (%.3f vs %.3f)" % [label,s_in,s_out])
	print("%s walk (indoors vs outside): damage %.2f vs %.2f, exposure %.3f vs %.3f, pin %.3f vs %.3f" % [label,d_in,d_out,e_in,e_out,s_in,s_out])
	check(not Garrison.inside(squad),"%s: section-level state stays outside" % label)
func harbor_index()->int:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		if configs[i].id=="black_sea_harbor":return i
	return -1
func _init()->void:
	var sim=Sim.new(false,harbor_index())
	var data:Dictionary=Garrison.index(sim)
	check(data.buildings.size()>=400,"city buildings indexed (%d)" % data.buildings.size())
	# Pick a building with a reachable doorway near open ground.
	var squad:Dictionary={}
	var building:Dictionary={}
	for b in data.buildings:
		var door:=Garrison.entry_point(sim,b.id,b.bounds.get_center()+Vector2(0,30))
		if door.x<0:continue
		var start:=door+Vector2(0,6)
		if not sim.terrain.traversable(start,"land",2.65):continue
		squad=sim.spawn("rifle",0,start)
		if not squad.is_empty() and squad.pos.distance_to(start)<1.0:building=b;break
		if not squad.is_empty():squad.hp=0
		squad={}
	check(not building.is_empty(),"fixture building with a doorway")
	if building.is_empty():
		print("GARRISON: ",checks," checks, ",failures," failures");quit(1);return
	check(Garrison.building_at(sim,building.rects[0].get_center())==building.id,"building lookup by point")
	check(Garrison.order(sim,[squad.id],building.id)==1,"garrison order accepted")
	var entry_checked:=false
	for i in 600:
		sim.tick(1.0/30)
		if not entry_checked and Garrison.transit(squad)=="IN" and not sides(squad).is_empty():
			compare_sides(sim,squad,sides(squad),"entry");entry_checked=true
		if Garrison.inside(squad):break
	check(entry_checked,"entry walk seen with soldiers on both sides of the wall")
	if not Garrison.inside(squad):print("DEBUG pos ",squad.pos," door ",squad.get("garrison_door")," target ",squad.get("garrison_target")," orders ",squad.orders," state ",squad.state)
	check(Garrison.inside(squad) and squad.state=="GARRISONED","section enters the building")
	check(squad.members.all(func(m):return m.hp<=0 or building.bounds.grow(1.0).has_point(m.pos)),"soldiers posted at the windows")
	var shooter:Dictionary=sim.spawn("rifle",1,squad.pos+Vector2(10,0))
	if not shooter.is_empty():
		var inside:=sim.damage_amount(shooter,squad)
		var outside_unit:Dictionary=sim.spawn("rifle",0,squad.pos+Vector2(-12,0))
		if not outside_unit.is_empty():
			check(inside<sim.damage_amount(shooter,outside_unit)*0.5,"garrison takes far less damage than troops outside")
	check(Garrison.order(sim,[sim.spawn("rifle",0,squad.pos+Vector2(0,8)).get("id",-1)],building.id)<=int(building.capacity)-1,"capacity respected")
	var away:Vector2=(squad.pos-building.bounds.get_center()).normalized()
	var issued:int=sim.issue([squad.id],squad.pos+away*8.0,"move")
	var orders_after:int=squad.orders.size()
	sim.tick(1.0/30)
	if Garrison.inside(squad):print("DEBUG leave issued=",issued," orders_after_issue=",orders_after," orders_now=",squad.orders," hold=",squad.hold_command," state=",squad.state)
	check(not Garrison.inside(squad),"a move order leaves the building")
	var exit_checked:=false
	for i in 60:
		if Garrison.transit(squad)=="OUT" and not sides(squad).is_empty():
			compare_sides(sim,squad,sides(squad),"exit");exit_checked=true;break
		sim.tick(1.0/30)
	check(exit_checked,"exit walk seen with soldiers on both sides of the wall")
	# Halt beside a building: soldiers take wall/corner cover facing the enemy side.
	for i in 300:sim.tick(1.0/30)
	var covered:int=squad.members.filter(func(m):return m.hp>0 and sim.terrain.cover(m.pos)).size()
	if covered<2:
		print("DEBUG halt orders=",squad.orders.size()," hold=",squad.hold_command," resume_after=",squad.get("cover_resume_after",0.0)," t=",sim.time," pos=",squad.pos," bdist=",building.bounds.get_center().distance_to(squad.pos))
		for m in squad.members:print("  m ",m.pos," phase=",m.get("cover_phase","")," occ=",m.get("occupying",false)," cover=",sim.terrain.cover(m.pos))
		var phantom_dir:Vector2=(sim.field_ops.get("enemy_insertion",Vector2.ZERO)-squad.pos).normalized()
		var phantom:={"pos":squad.pos+phantom_dir*35.0,"members":[]}
		print("  slot=",Sim.Infantry.Cover.find_slot(squad,squad.members[0],sim,phantom,[phantom]))
	check(squad.members.all(func(m):return not m.get("indoors",false)),"nobody stays sheltered after the exit walk")
	check(covered>=2,"halted section takes cover against buildings (%d of 3)" % covered)
	check(squad.members.any(func(m):return m.hp>0 and m.posture=="CROUCHED"),"soldiers in cover crouch")
	print("GARRISON: ",checks," checks, ",failures," failures")
	quit(1 if failures>0 else 0)
