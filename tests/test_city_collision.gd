extends SceneTree
# Real emitted colliders and rendered ground faces agree, while placement
# margins and low steps/docks do not masquerade as protective walls.
const Body=preload("res://scripts/city_building_geometry.gd")
const City=preload("res://scripts/city_buildings.gd")
const Terrain=preload("res://scripts/terrain.gd")
const Art=preload("res://scripts/visuals.gd")
const Sim=preload("res://scripts/simulation.gd")
const Garrison=preload("res://scripts/garrison.gd")
var checks:=0
var failures:Array[String]=[]

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok and not failures.has(label):failures.append(label);printerr("FAIL: ",label)

func world(spec:Dictionary,p:Vector2)->Vector2:
	return Vector2(float(spec.position[0]),float(spec.position[1]))+p.rotated(-deg_to_rad(float(spec.rotation_degrees)))

func distance_to_pieces(p:Vector2,pieces:Array)->float:
	var best:=INF
	for piece in pieces:
		var r:Rect2=piece.rect
		best=minf(best,p.distance_to(p.clamp(r.position,r.end)))
	return best

func isolated(data:Dictionary,spec:Dictionary):
	var blocks:Array=[]
	var low:Array=[]
	var first:int=int(spec.collision[0])
	for k in range(first,first+int(spec.collision[1])):
		blocks.append(data.blocks[k])
	# JSON numbers are floats; Array.has uses strict Variant typing.
	for raw in data.low_obstacle_blocks:
		var k:=int(raw)
		if k>=first and k<first+int(spec.collision[1]):low.append(k-first)
	return Terrain.new(6,{"size":[1024,768],"nav_cell_size":4,"fog_cell_size":8,
		"style":"showcase","mode":"field_ops","port":false,"shore_x":1024,
		"blocks":blocks,"low_obstacle_blocks":low,"woods":[],"objectives":[],
		"rubble":[0,0,0,0],"mud":[0,0,0,0]})

func verify_building(data:Dictionary,spec:Dictionary)->void:
	var terrain=isolated(data,spec)
	var pieces:Array=Body.ground_pieces(spec)
	var wall:Rect2=pieces[0].rect
	var name:String="%s @ %s"%[spec.design,spec.position]
	# Centers are measured from the physical wall, not from source_size.
	for normal in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
		var face:Vector2=wall.get_center()+normal*wall.size/2
		var clear:Vector2=face+normal*1.12
		if distance_to_pieces(clear,pieces.slice(1))<1.12:continue
		check(terrain.traversable(world(spec,clear),"land",0.8),name+" wall-side standing clearance "+str(normal))
		check(terrain.cover(world(spec,clear)),name+" actual wall grants cover "+str(normal))
		check(not terrain.traversable(world(spec,face-normal*0.2),"land",0.1),name+" wall body remains solid "+str(normal))
		check(not terrain.line_clear(world(spec,clear),world(spec,wall.get_center())),name+" wall blocks shots "+str(normal))
	# Test both the indexed and brute-force paths: a visible low step/dock
	# blocks walking, but a shot passing over it is not stopped by a wall.
	for piece in pieces:
		if piece.wall:continue
		var low:Rect2=piece.rect
		var front:=low.get_center().y<wall.get_center().y
		var z:float=low.position.y+0.2 if front else low.end.y-0.2
		var a:=world(spec,Vector2(low.position.x-0.5,z))
		var b:=world(spec,Vector2(low.end.x+0.5,z))
		var outside:=world(spec,Vector2(low.get_center().x,low.position.y-0.95 if front else low.end.y+0.95))
		for indexed in [true,false]:
			terrain.use_static_index=indexed
			check(not terrain.traversable(world(spec,low.get_center()),"land",0.1),name+" low piece blocks locomotion "+str(indexed))
			check(terrain.line_clear(a,b),name+" low piece does not block a shot "+str(indexed))
			check(not terrain.cover(outside),name+" low piece has no wall cover halo "+str(indexed))

func inspect_ground_faces(node:Node3D,pieces:Array,label:String,xf:Transform3D=Transform3D.IDENTITY)->void:
	if node is MeshInstance3D:
		for surface in node.mesh.get_surface_count():
			var arrays:Array=node.mesh.surface_get_arrays(surface)
			var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var indices=arrays[Mesh.ARRAY_INDEX]
			var count:int=indices.size() if indices!=null and not indices.is_empty() else vertices.size()
			for i in range(0,count,3):
				var triangle:Array[Vector3]=[]
				for j in 3:triangle.append(xf*vertices[indices[i+j] if indices!=null and not indices.is_empty() else i+j])
				var low:=minf(triangle[0].y,minf(triangle[1].y,triangle[2].y))
				var high:=maxf(triangle[0].y,maxf(triangle[1].y,triangle[2].y))
				# Ground-connected wall/post faces, excluding roofs, balconies,
				# ground skirts and damage rubble. Small facade trim can protrude.
				if low>0.25 or high<2.0:continue
				for p in triangle:
					check(distance_to_pieces(Vector2(p.x,p.z),pieces)<=0.18,label+" rendered ground wall/post agrees with body profile")
	for child in node.get_children():
		if child is Node3D:inspect_ground_faces(child,pieces,label,xf*child.transform)

func _init()->void:call_deferred("run")

func run()->void:
	var all:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	var data:Dictionary=all[6]
	var terrain=Terrain.new(6)
	# This fails against the old parcel blocker: the rear rendered facade is
	# z=153.55, but the old invisible blocker extended to z=154.75.
	check(terrain.traversable(Vector2(730,154.6),"land",0.8),"regression: a soldier can reach the panel facade")
	check(terrain.cover(Vector2(730,154.6)),"regression: the reachable panel facade grants cover")
	var panel:Dictionary=data.architecture.filter(func(s):return s.design=="panel_5" and Vector2(s.position[0],s.position[1])==Vector2(735,150))[0]
	# Nearby street furniture legitimately grants its own cover in the full
	# map; isolate the building to test removal of its former parcel halo.
	check(not isolated(data,panel).cover(Vector2(730,155.8)),"regression: empty parcel margin no longer grants distant wall cover")
	var low_ids:Dictionary={}
	for raw in data.low_obstacle_blocks:
		var k:=int(raw)
		check(raw==k and k>=0 and k<data.blocks.size() and not low_ids.has(k),"low obstacle indices are unique valid integers")
		low_ids[k]=true
	var seen:Dictionary={}
	var owners:=0
	var rotated:=0
	for spec in data.architecture:
		if spec.design=="rock":continue
		var pieces:Array=Body.ground_pieces(spec)
		var lows:Array=pieces.filter(func(p):return not p.wall)
		for k in range(int(spec.collision[0]),int(spec.collision[0])+int(spec.collision[1])):
			if not low_ids.has(k):continue
			owners+=1
			var row:Array=data.blocks[k]
			var rect:=Rect2(row[0],row[1],row[2],row[3])
			for corner in [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]:
				var local:Vector2=(corner-Vector2(spec.position[0],spec.position[1])).rotated(deg_to_rad(float(spec.rotation_degrees)))
				check(distance_to_pieces(local,lows)<=0.151,"low index belongs to its owner's step/dock")
		if pieces.is_empty():
			check(spec.collision_geometry=="parcel_fallback","custom families declare conservative fallback")
			continue
		if seen.has(spec.design):continue
		seen[spec.design]=true
		if absf(fposmod(float(spec.rotation_degrees)+45,90)-45)>0.01:rotated+=1
		verify_building(data,spec)
	check(owners==low_ids.size() and owners>0,"every low piece belongs to one destructible architecture range")
	check(seen.size()==14 and rotated>0,"all supported families and rotated bodies exercised")
	var art=Art.new()
	for design in Body.data().families:
		for damage in [0,2]:
			var spec:=City.normalized(City.sample(design));spec.damage=damage
			var model:=Node3D.new()
			City.build_spec(art,model,spec)
			inspect_ground_faces(model,Body.ground_pieces(spec),str(design)+" damage "+str(damage))
			model.free()
	# Ownership must survive the new piece counts: collapse clears every wall
	# and low obstacle belonging to the building, without removing neighbours.
	var sim=Sim.new(false,6)
	var buildings:Array=Garrison.index(sim).buildings
	var chosen:Dictionary=buildings.filter(func(b):return b.design=="stone_house" and b.spec.damage<2)[0]
	var other:Rect2=sim.terrain.blocks[0]
	sim.terrain.collapse_blocks(chosen.blocks,chosen.bounds)
	for k in chosen.blocks:check(sim.terrain.blocks[k].size==Vector2.ZERO,"collapse removes all owned wall/low pieces")
	check(sim.terrain.blocks[0]==other,"collapse preserves unrelated building blocks")
	print("CITY COLLISION TESTS: %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
