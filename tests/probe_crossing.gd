extends SceneTree
# Two rifle sections ordered through each other (and two ordered to the same
# spot) must not lock: every soldier keeps moving to its destination.
const Sim=preload("res://scripts/simulation.gd")
func harbor_index()->int:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		if configs[i].id=="black_sea_harbor":return i
	return -1
func _init()->void:
	var sim=Sim.new(false,harbor_index())
	var a:Dictionary=sim.spawn("rifle",0,Vector2(290,640))
	var b:Dictionary=sim.spawn("rifle",0,Vector2(320,640))
	sim.issue([a.id],Vector2(325,640),"move")
	sim.issue([b.id],Vector2(285,640),"move")
	var c:Dictionary=sim.spawn("rifle",0,Vector2(300,670))
	var d:Dictionary=sim.spawn("rifle",0,Vector2(304,674))
	sim.issue([c.id,d.id],Vector2(330,690),"move")
	# Gracefulness: how close soldiers of different sections come and for how
	# long they squeeze (< 1.3 apart, i.e. inside comfortable passing distance).
	var closest:=INF
	var squeeze_ticks:=0
	var arrived_at:=-1.0
	for i in 600:
		sim.tick(1.0/30)
		for x in a.members:
			for y in b.members:
				if x.hp<=0 or y.hp<=0:continue
				var gap:float=x.pos.distance_to(y.pos)
				closest=minf(closest,gap)
				if gap<1.3:squeeze_ticks+=1
		if arrived_at<0 and a.pos.distance_to(Vector2(325,640))<1.0 and b.pos.distance_to(Vector2(285,640))<1.0:arrived_at=(i+1)/30.0
		if i%100==99:print("t=",(i+1)/30.0," A ",a.pos.round()," ",a.members.map(func(m):return [m.pos.round(),m.state])," B ",b.pos.round()," ",b.members.map(func(m):return [m.pos.round(),m.state]))
	print("GRACE closest=%.2f squeeze_ticks=%d crossing_time=%.1f" % [closest,squeeze_ticks,arrived_at])
	var ok:=true
	for pair in [[a,Vector2(325,640)],[b,Vector2(285,640)]]:
		var u:Dictionary=pair[0]
		var dist:float=u.pos.distance_to(pair[1])
		print("crossing unit ",u.id," dist_to_goal=%.1f orders=%d" % [dist,u.orders.size()])
		if dist>4.0:ok=false
	for u in [c,d]:
		var dist:float=u.pos.distance_to(Vector2(330,690))
		print("shared unit ",u.id," dist_to_goal=%.1f orders=%d" % [dist,u.orders.size()])
		if dist>9.0:ok=false
	print("CROSSING: ","PASS" if ok else "FAIL")
	quit(0 if ok else 1)
