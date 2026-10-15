extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
var checks:=0
var failures:Array[String]=[]
func _init()->void:call_deferred("run")
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message);printerr("FAIL: ",message)
func route_safe(terrain,origin:Vector2,route:Array,radius:float)->bool:
	for point in route:
		var count:=maxi(1,ceili(origin.distance_to(point)/0.025))
		for step in range(count+1):
			if not terrain.traversable(origin.lerp(point,float(step)/count),"land",radius):return false
		origin=point
	return not route.is_empty()
func run()->void:
	# Road between the parcels (24,17,7,7) and (24,29,7,7).
	var gap:=Vector2(27.5,26.5)
	for kind in ["rifle","atgm","tank"]:
		var sim=Sim.new(false,3)
		var u=sim.spawn(kind,0,Vector2(39,26.5))
		var radius:float=sim.definitions[kind].radius
		check(not sim.terrain.blocked(gap),"gap center is outside architecture")
		check(sim.terrain.traversable(gap,"land",0.8),"individual soldier fits road gap")
		check(not sim.terrain.traversable(gap,"land",radius),"full footprint cannot fit gap: "+kind)
		check(sim.issue([u.id],gap)==1,"obstructed gap click gets safe nearby destination: "+kind)
		if not u.orders.is_empty():
			var destination:Vector2=u.orders[0].pos
			check(destination.distance_to(gap)<=6.0,"destination remains near click: "+kind)
			check(route_safe(sim.terrain,u.pos,u.path,radius),"route is densely clearance sampled: "+kind)
			for i in 300:
				sim.tick(1.0/30.0)
				check(sim.terrain.traversable(u.pos,"land",radius),"movement stays clear: "+kind)
				for actor in u.members:
					check(sim.terrain.traversable(actor.pos,"land",float(actor.body_radius)),"soldier stays clear: "+kind)
			check(u.pos.distance_to(destination)<0.3,"unit arrives at resolved destination: "+kind)
		check(sim.issue([u.id],Vector2(27.5,23))==0,"enclosed rear yard stays blocked")
		check(sim.issue([u.id],Vector2(77,26.5))==0,"water click is not projected onto land")
		check(sim.issue([u.id],Vector2(-1,26.5))==0,"off-map click rejected")
		var deployed=sim.spawn(kind,0,gap)
		check(not deployed.is_empty(),"gap deployment finds safe space: "+kind)
		if not deployed.is_empty():
			check(sim.location_clear(deployed.pos,kind,deployed.id),"deployment reserves full footprint: "+kind)
			check(not sim.terrain.path(deployed.pos,Vector2(40,40),"land",radius).is_empty(),"deployed unit can leave gap area: "+kind)
	# A thin dividing wall: nearest free formation/spawn positions across it
	# are geometrically clear but unreachable from the unit/origin.
	var split=Sim.new(false,1)
	split.terrain.blocks.clear();split.terrain.blocks.append(Rect2(20,0,0.3,72))
	split.terrain.trees.clear();split.terrain.poles.clear();split.terrain.port=false
	split.terrain.navigation.clear()
	var unit=split.spawn("tank",0,Vector2(17.4,30))
	var slot:Vector2=split.formation_slot(Vector2(24,30),unit,[])
	check(slot.x>=0 and slot.x<20,"formation fallback skips disconnected free point")
	check(not split.terrain.path(unit.pos,slot,"land",2.45).is_empty(),"formation fallback reachable")
	# Fill the left side locally so the nearest clear deployment candidate is right of wall.
	split.spawn("tank",0,Vector2(12,30))
	for y in [24.5,35.5]:split.spawn("tank",0,Vector2(17.4,y))
	var legacy_spawn:=Vector2(-1,-1)
	for ring in range(1,25):
		for i in 24:
			var candidate:=Vector2(17.4,30)+Vector2.from_angle(i*TAU/24.0)*ring
			if split.location_clear(candidate,"tank"):
				legacy_spawn=candidate
				break
		if legacy_spawn.x>=0:break
	check(legacy_spawn.x>20,"fixture reproduces old deployment fallback crossing wall")
	var spawn_point:Vector2=split.spawn_position(Vector2(17.4,30),"tank")
	check(spawn_point.x>=0 and spawn_point.x<20,"deployment does not jump dividing wall")
	check(not split.terrain.path(Vector2(17.4,30),spawn_point,"land",2.45).is_empty(),"deployment remains connected to valid origin")
	var terrain=split.terrain
	check(terrain.path(Vector2(20.1,30),Vector2(17.4,30),"land",0.8).is_empty(),"route cannot escape from inside solid architecture")
	var excluded:Array=[{"pos":Vector2(10,50),"radius":2.0}]
	check(terrain.path(Vector2(10,40),Vector2(10,50),"land",0.8,excluded).is_empty(),"route cannot publish an excluded endpoint")
	print("GAP NAVIGATION: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
