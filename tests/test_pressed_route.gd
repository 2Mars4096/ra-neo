extends SceneTree
# A tank pressed against friendly hulls still gets a route away from them.
# Planning: two or three tanks in contact (black_sea_harbor open ground), each
# plans to a goal on the far side with the others as full-margin avoided
# bodies (inside whose margin it already stands). Every route must exist, clear
# the terrain, and never come closer to a body than the start already is.
# Simulation: the same pressed groups, each tank ordered to the far side,
# all reach their goal within a bound.
const Sim=preload("res://scripts/simulation.gd")
const R:=2.45 # tank hull radius
const CONTACT:=R*2.0+0.08 # two hulls touching (movement clearance)
const MARGIN:=R+0.4+R+0.08 # hull-detour clearance (wider than contact)
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

func _init()->void:
	var sim=Sim.new(false,scenario_index("black_sea_harbor"))
	var open:=Vector2(300,640)
	var routes:=0;var planned:=0;var worst_ms:=0.0;var total_ms:=0.0
	sim.terrain.path(open,open+Vector2(0,22),"land",R,[],"tracked") # builds the grid
	for k in 16:
		for j in 4:
			var a:=open+Vector2(j*0.31,j*0.23) # sub-cell offsets
			var dir:=Vector2.from_angle(k*TAU/16)
			# A pair in contact, and a third tank touching the first from the side.
			var groups:=[[a,a+dir*CONTACT],[a,a+dir*CONTACT,a-dir.rotated(0.9)*CONTACT]]
			for group in groups:
				for i in group.size():
					var from:Vector2=group[i]
					var away:Vector2=(from-(group[0] if i>0 else group[1])).normalized()
					var bodies:Array=[]
					for n in group.size():
						if n!=i:bodies.append({"pos":group[n],"radius":MARGIN})
					# Far side of the contact, straight away, and to either flank.
					for goal in [from-away*22.0,from+away*22.0,from+away.orthogonal()*22.0,from-away.orthogonal()*22.0]:
						if sim.terrain.path(from,goal,"land",R,[],"tracked").is_empty():continue
						routes+=1
						var started:=Time.get_ticks_usec()
						var route:Array=sim.terrain.path(from,goal,"land",R,bodies,"tracked")
						var ms:=(Time.get_ticks_usec()-started)/1000.0
						worst_ms=maxf(worst_ms,ms);total_ms+=ms
						var label:="k=%d j=%d group=%d tank=%d goal=%s" % [k,j,group.size(),i,goal.snapped(Vector2(0.01,0.01))]
						if route.is_empty():
							check(false,"%s: a pressed tank plans a route away" % label)
							continue
						planned+=1
						check(_route_ok(sim.terrain,from,route,bodies),"%s: the route clears terrain and never closes on a body" % label)
						check(route.back().distance_to(goal)<0.01,"%s: the route ends at the goal" % label)
	check(routes>=300,"enough reachable planning cases (%d)" % routes)
	print("planning: %d/%d routes, mean %.2f ms, slowest %.1f ms" % [planned,routes,total_ms/maxi(1,routes),worst_ms])
	# Unmodified caller records: the shrink is local to the query.
	var body:={"pos":open+Vector2(CONTACT,0),"radius":MARGIN}
	sim.terrain.path(open,open-Vector2(22,0),"land",R,[body],"tracked")
	check(is_equal_approx(float(body.radius),MARGIN),"avoided body records are not modified")
	# A goal inside a body's margin is still never routed to.
	var far:={"pos":open+Vector2(0,20),"radius":MARGIN}
	check(sim.terrain.path(open,open+Vector2(1,20),"land",R,[far],"tracked").is_empty(),"no route ends inside an avoided body")
	# Simulation: pressed groups each drive to the far side.
	run_case("pair_swap",[[open,open+Vector2(24,0)],[open+Vector2(CONTACT,0),open+Vector2(-24,0)]],45.0)
	run_case("trio_outward_inward",[
		[open,open+Vector2(26,0)],
		[open+Vector2(CONTACT,0),open+Vector2(-22,0)],
		[open+Vector2(0,CONTACT),open+Vector2(0,-24)]],60.0)
	print("PRESSED ROUTE: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)

# Each edge clears the terrain and stays at least as far from every body as
# the start (bodies the start does not touch keep their full margin).
func _route_ok(terrain,from:Vector2,route:Array,bodies:Array)->bool:
	var previous:=from
	# Tracked hulls plan through crushable street furniture.
	terrain.crush_pass=true
	for point in route:
		if not terrain.segment_clear(previous,point,"land",R):terrain.crush_pass=false;return false
		for body in bodies:
			var keep:float=minf(body.radius,from.distance_to(body.pos)-0.05)
			var dist:float=Geometry2D.get_closest_point_to_segment(body.pos,previous,point).distance_to(body.pos)
			if dist<keep-0.001:terrain.crush_pass=false;return false
		previous=point
	terrain.crush_pass=false
	return true

# Each entry: [start, goal]. Tanks face their goal and get individual orders.
func run_case(label:String,entries:Array,limit:float)->void:
	var sim=Sim.new(false,scenario_index("black_sea_harbor"))
	var tanks:Array=[]
	for entry in entries:
		var tank:Dictionary=sim.spawn("tank",0,entry[0])
		tank.pos=entry[0]
		tank.facing=(entry[1]-entry[0]).normalized()
		tanks.append(tank)
	sim.rebuild_spatial()
	var goals:Array=[]
	for i in tanks.size():
		check(sim.issue([tanks[i].id],entries[i][1],"move")==1,"%s: tank %d accepts its move" % [label,i])
		goals.append(tanks[i].orders[0].pos if not tanks[i].orders.is_empty() else entries[i][1])
	var arrived:Array=[]
	for tank in tanks:arrived.append(-1.0)
	var dt:=1.0/30.0
	var closest:=INF
	for step in int(limit/dt):
		sim.tick(dt)
		var done:=true
		for i in tanks.size():
			for n in range(i+1,tanks.size()):closest=minf(closest,tanks[i].pos.distance_to(tanks[n].pos))
			if arrived[i]<0 and tanks[i].orders.is_empty() and tanks[i].pos.distance_to(goals[i])<=4.0:arrived[i]=(step+1)*dt
			if arrived[i]<0:done=false
		if done:break
	var line:="%s:" % label
	for i in tanks.size():
		line+=" [%d arrive=%.1f gap=%.1f %s]" % [i,arrived[i],tanks[i].pos.distance_to(goals[i]),tanks[i].state]
		check(arrived[i]>=0.0,"%s: tank %d reaches its goal within %.0f s (gap %.1f, state %s)" % [label,i,limit,tanks[i].pos.distance_to(goals[i]),tanks[i].state])
	# Hulls never drive through each other (small overlap from pushing is allowed).
	check(closest>R*2.0-0.5,"%s: hulls never pass through each other (closest %.2f)" % [label,closest])
	print(line," closest=%.2f" % closest)
