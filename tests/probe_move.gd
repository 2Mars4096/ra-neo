extends SceneTree
# Diagnostic: does a rifle section obey move orders on the harbor map, alone and
# after manning a sandbag line?
const Sim=preload("res://scripts/simulation.gd")
const FieldOps=preload("res://scripts/field_ops.gd")
func harbor_index()->int:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		if configs[i].id=="black_sea_harbor":return i
	return -1
func report(sim,u:Dictionary,label:String)->void:
	print(label," pos=",u.pos," orders=",u.orders.map(func(o):return [o.mode,o.pos])," state=",u.state," members=",u.members.map(func(m):return [m.pos.round(),m.get("cover_phase",""),m.get("occupying",false)]))
func _init()->void:
	var sim=Sim.new(true,harbor_index())
	var u:Dictionary=sim.spawn("rifle",0,Vector2(300,640))
	var start:Vector2=u.pos
	var accepted:int=sim.issue([u.id],u.pos+Vector2(30,0),"move")
	print("plain move accepted=",accepted," feedback=",sim.order_feedback)
	for i in 150:sim.tick(1.0/30)
	report(sim,u,"after 5s plain")
	print("moved ",start.distance_to(u.pos))
	# Sandbag line next to the section, completed, then a new move order.
	var v:Dictionary=sim.spawn("rifle",0,Vector2(300,660))
	FieldOps.spawn_prepared_works(sim,[{"kind":"tactical_cover","position":[300,665]},{"kind":"tactical_cover","position":[302.8,665]}],0)
	for i in 120:sim.tick(1.0/30)
	report(sim,v,"after manning")
	var from:Vector2=v.pos
	accepted=sim.issue([v.id],v.pos+Vector2(0,-25),"move")
	print("move from works accepted=",accepted," feedback=",sim.order_feedback)
	for i in 150:sim.tick(1.0/30)
	report(sim,v,"after 5s from works")
	print("moved ",from.distance_to(v.pos))
	quit()
