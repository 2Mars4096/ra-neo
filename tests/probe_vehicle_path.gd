extends SceneTree
# Vehicles take the obvious route through clear gaps on black_sea_harbor.
# City pairs: driven distance / shortest footprint-clear route (1 u reference
# grid at the true hull radius). Unit pairs: driven distance / straight line
# past parked, oncoming and grouped vehicles. Also reports arrival time.
const Sim=preload("res://scripts/simulation.gd")
const RADIUS:=2.45
# Start/goal pairs through city streets, yards and building gaps.
const CITY:=[
	[Vector2(639,564),Vector2(554,526)],[Vector2(1005,562),Vector2(902,490)],
	[Vector2(326,673),Vector2(378,631)],[Vector2(320,697),Vector2(441,646)],
	[Vector2(386,551),Vector2(341,448)],[Vector2(860,507),Vector2(752,501)],
	[Vector2(659,365),Vector2(670,456)],[Vector2(526,366),Vector2(631,431)],
	[Vector2(932,657),Vector2(841,634)],[Vector2(274,102),Vector2(384,85)],
	[Vector2(913,393),Vector2(879,400)],[Vector2(993,412),Vector2(844,394)],
	[Vector2(897,468),Vector2(842,471)],[Vector2(804,389),Vector2(897,430)],
	[Vector2(519,507),Vector2(581,502)],[Vector2(494,507),Vector2(563,538)],
	[Vector2(869,472),Vector2(863,359)],[Vector2(943,184),Vector2(914,50)]]
var reference:AStarGrid2D
var failures:Array[String]=[]

func harbor_index()->int:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		if configs[i].id=="black_sea_harbor":return i
	return -1

func build_reference(t)->void:
	reference=AStarGrid2D.new()
	reference.region=Rect2i(Vector2i.ZERO,Vector2i(t.world_size))
	reference.cell_size=Vector2.ONE
	reference.offset=Vector2(0.5,0.5)
	reference.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	reference.update()
	t.crush_pass=true
	for x in int(t.world_size.x):
		for y in int(t.world_size.y):
			var p:=Vector2(x+0.5,y+0.5)
			reference.set_point_solid(Vector2i(x,y),t.is_water(p) or not t.traversable(p,"land",RADIUS))
	t.crush_pass=false

# Shortest footprint-clear length: fine grid path, then greedy string pulling.
func shortest(t,a:Vector2,b:Vector2)->float:
	var cells:PackedVector2Array=reference.get_point_path(Vector2i(a.floor()),Vector2i(b.floor()))
	if cells.is_empty():return -1.0
	var raw:Array[Vector2]=[a]
	for p in cells:raw.append(p)
	raw.append(b)
	t.crush_pass=true
	var origin:=a;var index:=1;var length:=0.0
	while index<raw.size():
		var furthest:=index
		for next in range(index+1,raw.size()):
			if t.segment_clear(origin,raw[next],"land",RADIUS):furthest=next
		length+=origin.distance_to(raw[furthest]);origin=raw[furthest];index=furthest+1
	t.crush_pass=false
	return length

# Drives every mover to its goal; returns per-mover [distance, seconds or -1].
func drive(sim,movers:Array,limit:float)->Array:
	var travelled:Array=[];var arrival:Array=[];var last:Array=[]
	for u in movers:travelled.append(0.0);arrival.append(-1.0);last.append(u.pos)
	for i in int(limit*30):
		sim.tick(1.0/30);sim.events.clear()
		var done:=true
		for k in movers.size():
			var u:Dictionary=movers[k]
			travelled[k]+=last[k].distance_to(u.pos);last[k]=u.pos
			if arrival[k]<0 and u.orders.is_empty():arrival[k]=(i+1)/30.0
			done=done and arrival[k]>=0
		if done:break
	var out:Array=[]
	for k in movers.size():out.append([travelled[k],arrival[k]])
	return out

func _init()->void:
	var started:=Time.get_ticks_msec()
	var index:=harbor_index()
	var base=Sim.new(false,index)
	build_reference(base.terrain)
	var ratios:Array[float]=[]
	var times:Array[float]=[]
	for kind in ["tank","aa"]:
		var speed:float=float(base.definitions[kind].speed)
		for pair in CITY:
			var a:Vector2=pair[0];var b:Vector2=pair[1]
			var best:=shortest(base.terrain,a,b)
			var sim=Sim.new(false,index)
			var u:Dictionary=sim.spawn(kind,0,a)
			u.facing=(b-a).normalized()
			if best<0 or sim.issue([u.id],b,"move")!=1:
				failures.append("%s %s->%s no order" % [kind,a,b]);continue
			var result:Array=drive(sim,[u],90.0)[0]
			var ratio:float=result[0]/best
			ratios.append(ratio)
			if result[1]<0:failures.append("%s %s->%s did not arrive (%.1f left)" % [kind,a,b,u.pos.distance_to(b)])
			else:times.append(result[1]/(best/speed))
			print("CITY %s %s->%s shortest=%.1f drove=%.1f ratio=%.3f t=%.1fs (straight-run %.1fs)" % [kind,a,b,best,result[0],ratio,result[1],best/speed])
	var unit_ratios:Array[float]=[]
	for scenario in ["parked_gap","blocker","head_on","group","infantry_lane"]:
		var sim=Sim.new(false,index)
		var movers:Array=[];var goals:Array=[]
		var start:=Vector2(235,100);var goal:=Vector2(235,15)
		match scenario:
			"parked_gap":
				sim.spawn("tank",0,Vector2(228.5,58));sim.spawn("tank",0,Vector2(241.5,58))
			"blocker":
				sim.spawn("tank",0,Vector2(235,58))
			"head_on":
				var other:Dictionary=sim.spawn("tank",0,goal)
				other.facing=Vector2.DOWN
				sim.issue([other.id],start,"move")
				movers.append(other);goals.append([goal,start])
			"infantry_lane":
				sim.spawn("rifle",0,Vector2(240.5,58))
		if scenario=="group":
			var ids:Array=[]
			for x in [227.0,235.0,243.0]:
				var member:Dictionary=sim.spawn("tank",0,Vector2(x,100))
				member.facing=Vector2.UP;ids.append(member.id)
			sim.issue(ids,goal,"move")
			for id in ids:
				var member:Dictionary=sim.get_unit(id)
				movers.append(member);goals.append([member.pos,member.orders[0].pos if not member.orders.is_empty() else goal])
		else:
			var u:Dictionary=sim.spawn("tank",0,start)
			u.facing=Vector2.UP
			sim.issue([u.id],goal,"move")
			movers.append(u);goals.append([start,goal])
		var results:Array=drive(sim,movers,60.0)
		for k in movers.size():
			var straight:float=goals[k][0].distance_to(goals[k][1])
			var ratio:float=results[k][0]/straight
			unit_ratios.append(ratio)
			if results[k][1]<0:failures.append("%s mover %d did not arrive (%.1f left)" % [scenario,k,movers[k].pos.distance_to(goals[k][1])])
			print("UNITS %s mover=%d straight=%.1f drove=%.1f ratio=%.3f t=%.1fs" % [scenario,k,straight,results[k][0],ratio,results[k][1]])
	var all:Array[float]=ratios+unit_ratios
	var mean:=0.0
	for r in all:mean+=r
	mean/=maxf(1,all.size())
	var worst:float=all.max()
	var time_mean:=0.0
	for r in times:time_mean+=r
	time_mean/=maxf(1,times.size())
	var city_mean:=0.0
	for r in ratios:city_mean+=r
	city_mean/=maxf(1,ratios.size())
	print("VEHICLE PATH city_mean=%.3f city_max=%.3f units_max=%.3f time_vs_straight_run=%.3f (%d ms)" % [city_mean,ratios.max(),unit_ratios.max(),time_mean,Time.get_ticks_msec()-started])
	if mean>1.03:failures.append("mean ratio %.3f > 1.03" % mean)
	if worst>1.10:failures.append("max ratio %.3f > 1.10" % worst)
	for f in failures:printerr("FAIL: ",f)
	print("VEHICLE PATH: ratio_mean=%.3f ratio_max=%.3f %s" % [mean,worst,"PASS" if failures.is_empty() else "FAIL"])
	quit(0 if failures.is_empty() else 1)
