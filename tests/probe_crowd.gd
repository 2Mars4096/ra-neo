extends SceneTree
# Crowded pathing: a section ordered through a packed block of idle friendly
# sections must file through, and a 6-section group ordered to one point must
# all receive orders and arrive near it (no oversized squad circles).
const Sim=preload("res://scripts/simulation.gd")
func harbor_index()->int:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		if configs[i].id=="black_sea_harbor":return i
	return -1
func _init()->void:
	var sim=Sim.new(false,harbor_index())
	# Idle block: five sections shoulder to shoulder across the lane.
	var block:Array=[]
	for i in 5:block.append(sim.spawn("rifle",0,Vector2(300,630+i*4.0)))
	var runner:Dictionary=sim.spawn("rifle",0,Vector2(285,640))
	var tank:Dictionary=sim.spawn("tank",0,Vector2(285,655))
	var placed:=[]
	for u in block+[runner,tank]:placed.append(u.pos.round())
	print("placed ",placed)
	sim.issue([runner.id],Vector2(318,640),"move")
	sim.issue([tank.id],Vector2(318,652),"move")
	var group:Array=[]
	for i in 6:group.append(sim.spawn("rifle",0,Vector2(280+i*3.0,690)))
	var accepted:int=sim.issue(group.map(func(u):return u.id),Vector2(305,700),"move")
	print("group accepted ",accepted,"/6")
	# A tank and an ATGM section deployed on top of each other must both get out.
	var pair_tank:Dictionary=sim.spawn("tank",0,Vector2(285,720))
	var pair_atgm:Dictionary=sim.spawn("atgm",0,Vector2(285,720))
	pair_atgm.pos=pair_tank.pos+Vector2(1.5,0)
	for m in pair_atgm.members:m.pos=pair_atgm.pos+m.offset
	sim.issue([pair_tank.id,pair_atgm.id],Vector2(310,722),"move")
	for i in 900:
		sim.tick(1.0/30)
	var ok:=accepted==6
	var dr:float=runner.pos.distance_to(Vector2(318,640))
	var dt:float=tank.pos.distance_to(Vector2(318,652))
	print("runner dist=%.1f state=%s  tank dist=%.1f state=%s" % [dr,runner.state,dt,tank.state])
	if dr>4.0:ok=false
	if dt>5.0:ok=false
	for u in [pair_tank,pair_atgm]:
		var dist:float=u.pos.distance_to(Vector2(310,722))
		print("overlap pair ",u.kind," dist=%.1f orders=%d state=%s" % [dist,u.orders.size(),u.state])
		if dist>9.0:ok=false
	for u in group:
		var dist:float=u.pos.distance_to(Vector2(305,700))
		print("group unit ",u.id," dist=%.1f orders=%d" % [dist,u.orders.size()])
		if dist>9.0 or not u.orders.is_empty():ok=false
	print("CROWD: ","PASS" if ok else "FAIL")
	quit(0 if ok else 1)
