extends SceneTree
# Time for a helicopter / tank to destroy a rifle section in the open, and a
# garrisoned section engaging an enemy ~16 m from its windows.
const Sim=preload("res://scripts/simulation.gd")
const Garrison=preload("res://scripts/garrison.gd")
func harbor_index()->int:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		if configs[i].id=="black_sea_harbor":return i
	return -1
func kill_time(kind:String)->float:
	var sim=Sim.new(false,harbor_index())
	# Helo at harbor altitude 13 reaches ~15.2 m over ground: start 1 m inside it.
	sim.spawn(kind,0,Vector2(286,640))
	var rifle:Dictionary=sim.spawn("rifle",1,Vector2(300,640))
	rifle["hold_command"]=true
	for i in 1800:
		sim.tick(1.0/30);sim.events.clear()
		if not sim.alive(rifle) or rifle.get("combat_ineffective",false):return sim.time
	return INF
func _init()->void:
	var ok:=true
	for kind in ["helo","tank"]:
		var t:float=kill_time(kind)
		print(kind," kills rifle section in %.1f s" % t)
		if t>40.0:ok=false
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
		target=g.spawn("rifle",1,door+out*13.0)
		target["hold_command"]=true
		break
	for i in 300:
		g.tick(1.0/30);g.events.clear()
	var fired:bool=not rifle.is_empty() and rifle.members.any(func(m):return m.last_shot>0)
	var near:=INF
	if not target.is_empty():
		for m in rifle.members:near=minf(near,m.pos.distance_to(target.pos))
	print("garrison fired=",fired," nearest window to enemy=%.1f m enemy hp=%.0f" % [near,target.get("hp",0.0)])
	if not fired:ok=false
	print("LETHALITY: ","PASS" if ok else "FAIL")
	quit(0 if ok else 1)
