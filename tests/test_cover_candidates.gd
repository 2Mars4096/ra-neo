extends SceneTree
# Exact reference candidate list from pre-optimization 1245d23: preserve order,
# duplicates, real cover and every original clearance rejection. No timing gate.
const Sim=preload("res://scripts/simulation.gd")
const Cover=preload("res://scripts/cover_behavior.gd")
const LEASH:=10.0
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)
func compare(sim,point:Vector2,label:String)->void:
	var u:={"pos":point}
	var reference:Array=reference_points(u,sim)
	var actual:Array=Cover._shelter_points(u,sim)
	check(actual==reference,label+" exact candidate list at "+str(point))
func _init()->void:
	var sim=Sim.new(false,6)
	for origin in [Vector2(420,560),Vector2(500,680),Vector2(440,575)]:
		for i in 24:compare(sim,origin+Vector2((i%6)*6,(i/6)*6),"crowded Harbor geometry")
	var rng:=RandomNumberGenerator.new();rng.seed=15479
	for i in 80:compare(sim,Vector2(rng.randf_range(10,1014),rng.randf_range(10,758)),"Harbor distribution")
	var wall:Rect2=sim.terrain.blocks[0]
	var center:Vector2=wall.get_center()
	sim.terrain.collapse_blocks([0],wall)
	for delta in [Vector2.ZERO,Vector2(5,0),Vector2(0,5)]:compare(sim,center+delta,"collapsed wall and rubble")
	for scenario in [0,3,6]:
		var field=Sim.new(false,scenario)
		var origin:=Vector2(20,45) if scenario!=6 else Vector2(270,655)
		# Dynamic blockers do not imply cover in field mode. Rotated dimensions
		# and overlapping bodies exercise the retained physical predicates.
		var blocks:Array=[Rect2(origin,Vector2(6,2)),Rect2(origin+Vector2(4,0),Vector2(2,8))]
		field.terrain.update_field_geometry(blocks,[blocks[0]])
		field.terrain.update_field_zones([{"rect":Rect2(origin+Vector2(-3,4),Vector2(8,2)),"cover":["infantry"],"speed":{},"conceal":1.0,"front":Vector2.UP}])
		for x in 7:
			for y in 5:compare(field,origin+Vector2(x*2-4,y*2-3),"dynamic/zone fixture %d" % scenario)
		field.terrain.update_field_geometry([],[])
		field.terrain.update_field_zones([])
		compare(field,origin+Vector2(1,1),"removed works %d" % scenario)
	print("COVER CANDIDATES: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)

func reference_points(u:Dictionary,sim) -> Array:
	var points:Array[Vector2]=[]
	for ring in [1.2,2.4,3.6,5.5,7.5,9.0]:
		for index in 16:points.append(u.pos+Vector2.from_angle(index*TAU/16)*ring)
	# Sample the actual thin wall bands; coarse circular rings miss them. Yard
	# walls, cars and kiosks (hard cover props) screen as well as buildings.
	for wall in sim.terrain._static_candidates("building",u.pos,LEASH)+sim.terrain.dynamic_blocks:
		if not wall.grow(LEASH).has_point(u.pos):continue
		for x in range(ceili(wall.position.x),floori(wall.end.x)+1,1 if wall.size.x<8 else 2):
			points.append(Vector2(x,wall.position.y-1.05));points.append(Vector2(x,wall.end.y+1.05))
		for y in range(ceili(wall.position.y),floori(wall.end.y)+1,2):
			points.append(Vector2(wall.position.x-1.05,y));points.append(Vector2(wall.end.x+1.05,y))
	# Trench and hedgehog interiors are protective positions in their own right.
	for zone in sim.terrain.field_zones:
		if not ("infantry" in zone.cover) or not zone.rect.grow(LEASH).has_point(u.pos):continue
		var long_x:bool=zone.rect.size.x>=zone.rect.size.y
		var length:float=zone.rect.size.x if long_x else zone.rect.size.y
		for i in int(length/1.3):
			var t:=(i+0.5)*1.3
			points.append(zone.rect.position+(Vector2(t,zone.rect.size.y/2) if long_x else Vector2(zone.rect.size.x/2,t)))
	var shelters:Array=[]
	for point in points:
		if point.distance_to(u.pos)>LEASH:continue
		if not sim.terrain.cover(point) or not sim.terrain.traversable(point,"land",0.8):continue
		shelters.append(point)
	return shelters

