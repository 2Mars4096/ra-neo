extends SceneTree
# Tanks never slide sideways, crush a lamp in their way, engineers clear an
# enemy hedgehog belt, and a garrisoned rifle section fires from its windows.
const Sim=preload("res://scripts/simulation.gd")
const FieldOps=preload("res://scripts/field_ops.gd")
const Garrison=preload("res://scripts/garrison.gd")
func harbor_index()->int:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		if configs[i].id=="black_sea_harbor":return i
	return -1
func _init()->void:
	var ok:=true
	var sim=Sim.new(false,harbor_index())
	# 1) Tank drives along the boulevard through the lamp at (290.6,699).
	var tank:Dictionary=sim.spawn("tank",0,Vector2(278,699.2))
	tank.facing=Vector2.RIGHT
	var before_count:int=sim.terrain.crushables.size()
	print("tank order ",sim.issue([tank.id],Vector2(305,699.2),"move"))
	var drift:=0.0;var crushed:=0
	for i in 600:
		var before:Vector2=tank.pos;var facing:Vector2=tank.facing
		sim.tick(1.0/30)
		for e in sim.events:if e.type=="crushed":crushed+=1
		sim.events.clear()
		var step:Vector2=tank.pos-before
		if step.length()>0.0001:drift=maxf(drift,absf(step.normalized().cross(facing))*step.length())
	var dist:float=tank.pos.distance_to(Vector2(305,699.2))
	print("tank dist=%.1f crushed=%d crushables %d->%d max_lateral_step=%.4f" % [dist,crushed,before_count,sim.terrain.crushables.size(),drift])
	if drift>0.02:print("FAIL drift");ok=false
	if crushed<1:print("FAIL no crush");ok=false
	if dist>4.0:print("FAIL tank arrival");ok=false
	# 2) Engineers clear an enemy hedgehog belt.
	var engineer:Dictionary=sim.spawn("engineer",0,Vector2(300,640))
	var belt:Dictionary=sim.spawn("tank_obstacles",1,Vector2(312,640))
	belt["build_left"]=0.0
	sim.update_visibility()
	var ordered:bool=FieldOps.clear_site(sim,belt.id,engineer.id)
	print("clear order ",ordered," err='",sim.field_ops.get("last_build_error",""),"'")
	for i in 900:
		sim.tick(1.0/30);sim.events.clear()
		if not sim.alive(belt):break
	print("belt alive=",sim.alive(belt)," hp=%.1f engineer=%s" % [belt.hp,engineer.state])
	if not ordered or sim.alive(belt):print("FAIL clear");ok=false
	# 3) A garrisoned rifle section fires on an enemy in the open.
	var g=Sim.new(false,harbor_index())
	var data:Dictionary=Garrison.index(g)
	var rifle:Dictionary={}
	var target:Dictionary={}
	for b in data.buildings:
		var c:Vector2=b.bounds.get_center()
		if c.distance_to(Vector2(300,640))>120:continue
		var door:=Garrison.entry_point(g,b.id,c+Vector2(0,30))
		if door.x<0:continue
		rifle=g.spawn("rifle",0,door+(door-c).normalized()*2.0)
		if Garrison.order(g,[rifle.id],b.id)<1:continue
		for i in 600:
			g.tick(1.0/30);g.events.clear()
			if Garrison.inside(rifle):break
		var out:Vector2=(door-c).normalized()
		target=g.spawn("rifle",1,door+out*6.0)
		break
	var shots:=0
	if not rifle.is_empty() and Garrison.inside(rifle):
		for i in 300:
			g.update_visibility()
			g.tick(1.0/30)
			for e in g.events:if e.type=="shot" and e.get("unit",-2)==rifle.id:shots+=1
			for e in g.events:if e.type=="shot" and e.from.distance_to(rifle.pos)<40 and e.to.distance_to(target.pos)<4:shots+=0
			g.events.clear()
	if not rifle.is_empty():
		print("known=",g.contact_known(rifle,target)," can_fire=",g.can_fire(rifle,target)," target_dist=%.1f" % rifle.pos.distance_to(target.pos)," state=",rifle.state," hold=",rifle.hold_command)
		for m in rifle.members:print("  m",m.index," pos=",m.pos.round()," state=",m.state," posture=",m.posture," travel=",m.travel," target=",m.target," phase=",m.get("cover_phase","")," los=",g.terrain.line_clear(m.pos,target.pos)," dist=%.1f" % m.pos.distance_to(target.pos))
	var fired:bool=not rifle.is_empty() and rifle.members.any(func(m):return m.last_shot>0)
	print("garrison inside=",(not rifle.is_empty()) and Garrison.inside(rifle)," fired=",fired," target hp=%.0f" % (target.get("hp",-1.0)))
	if not fired:print("FAIL garrison fire");ok=false
	print("TANK CRUSH CLEAR: ","PASS" if ok else "FAIL")
	quit(0 if ok else 1)
