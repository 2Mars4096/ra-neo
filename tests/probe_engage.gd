extends SceneTree
# Two idle rifle sections that can see each other beyond rifle range must close
# and exchange fire on their own (both sides), within their leash.
const Sim=preload("res://scripts/simulation.gd")
func harbor_index()->int:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		if configs[i].id=="black_sea_harbor":return i
	return -1
func _init()->void:
	var sim=Sim.new(false,harbor_index())
	var a:Dictionary=sim.spawn("rifle",0,Vector2(290,640))
	var b:Dictionary=sim.spawn("rifle",1,Vector2(307,640))
	var a0:Vector2=a.pos
	for i in 450:
		sim.tick(1.0/30);sim.events.clear()
	var fa:bool=a.members.any(func(m):return m.last_shot>0)
	var fb:bool=b.members.any(func(m):return m.last_shot>0)
	print("ours fired=",fa," theirs fired=",fb," ours moved=%.1f hp a=%.0f b=%.0f" % [a.pos.distance_to(a0),a.hp,b.hp])
	var ok:bool=fa and fb and a.pos.distance_to(a0)<=15.0
	print("ENGAGE: ","PASS" if ok else "FAIL")
	quit(0 if ok else 1)
