extends SceneTree
# Black Sea Harbor compiled layout contract (tools/build_harbor_map.py,
# docs/harbor-city-design.md): independent architecture entries with oriented
# collision, morphology setbacks, land use, decor registry and route checks.
const Terrain=preload("res://scripts/terrain.gd")
const Library=preload("res://scripts/asset_library.gd")
const City=preload("res://scripts/city_buildings.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok and not failures.has(label):
		failures.append(label)
		if failures.size()<41:printerr("FAIL: ",label)
func rect(a:Array)->Rect2:return Rect2(a[0],a[1],a[2],a[3])
func vec(a:Array)->Vector2:return Vector2(a[0],a[1])
func _init()->void:call_deferred("run")

# Godot yaw: local x,z rotate by -yaw in the world x,z plane (Vector2.rotated).
func obb(spec:Dictionary)->PackedVector2Array:
	var size:=vec(spec.source_size);var c:=vec(spec.position);var yaw:=-deg_to_rad(float(spec.rotation_degrees))
	var out:=PackedVector2Array()
	for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:out.append(c+(corner*size/2).rotated(yaw))
	return out
func obb_distance(spec:Dictionary,p:Vector2)->float:
	var local:Vector2=(p-vec(spec.position)).rotated(deg_to_rad(float(spec.rotation_degrees)))
	var half:=vec(spec.source_size)/2
	return Vector2(maxf(absf(local.x)-half.x,0),maxf(absf(local.y)-half.y,0)).length()
func poly_bounds(poly:PackedVector2Array)->Rect2:
	var r:=Rect2(poly[0],Vector2.ZERO)
	for p in poly:r=r.expand(p)
	return r
func separation(a:PackedVector2Array,b:PackedVector2Array)->float:
	var best:=-INF
	for poly in [a,b]:
		for i in poly.size():
			var edge:Vector2=poly[(i+1)%poly.size()]-poly[i]
			var n:=Vector2(-edge.y,edge.x).normalized()
			var amin:=INF;var amax:=-INF;var bmin:=INF;var bmax:=-INF
			for p in a:amin=minf(amin,p.dot(n));amax=maxf(amax,p.dot(n))
			for p in b:bmin=minf(bmin,p.dot(n));bmax=maxf(bmax,p.dot(n))
			best=maxf(best,maxf(bmin-amax,amin-bmax))
	return best
func poly_segment_distance(poly:PackedVector2Array,a:Vector2,b:Vector2)->float:
	if Geometry2D.is_point_in_polygon(a,poly) or Geometry2D.is_point_in_polygon(b,poly):return 0.0
	var best:=INF
	for i in poly.size():
		var c:Vector2=poly[i];var d:Vector2=poly[(i+1)%poly.size()]
		if Geometry2D.segment_intersects_segment(a,b,c,d)!=null:return 0.0
		var pair:=Geometry2D.get_closest_points_between_segments(a,b,c,d)
		best=minf(best,pair[0].distance_to(pair[1]))
	return best
func rect_poly(r:Rect2)->PackedVector2Array:
	return PackedVector2Array([r.position,Vector2(r.end.x,r.position.y),r.end,Vector2(r.position.x,r.end.y)])
func road_gap(terrain,poly:PackedVector2Array,street:String="")->float:
	var best:=INF
	var bounds:=poly_bounds(poly).grow(30)
	for segment in terrain.roads.segments:
		if street!="" and segment.from.rsplit(":",true,1)[0]!=street:continue
		if street=="" and not bounds.intersects(Rect2(segment.a,Vector2.ZERO).expand(segment.b)):continue
		best=minf(best,poly_segment_distance(poly,segment.a,segment.b)-segment.width/2)
	return best

func run()->void:
	var all:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	check(all.size()==7,"scenario appended at index6")
	for i in 6:check(all[i].hidden,"trial scenario hidden %d"%i)
	var data:Dictionary=all[6]
	check(data.id=="black_sea_harbor" and data.mode=="field_ops" and not data.hidden,"sole current field scenario")
	check(data.resource_fields.is_empty(),"no deposit economy")
	var lv:Dictionary=data.layout_validation
	var terrain=Terrain.new(6)
	check(terrain.world_size==Vector2(1024,768) and terrain.nav_size==Vector2i(256,192) and terrain.fog_grid_size==Vector2i(128,96),"coarse huge-map dimensions")
	check(data.objectives.size()==3 and data.sectors.size()==3,"three objectives")
	check(terrain.blocks.size()==data.blocks.size(),"terrain loads every collision rect")

	# ---- architecture contract: independent entries, contiguous collision ranges.
	var buildings:Array=[];var polys:Array=[]
	var used:=PackedInt32Array();used.resize(data.blocks.size())
	var designs:Dictionary={}
	for spec in data.architecture:
		for key in ["design","position","rotation_degrees","source_size","collision"]:check(spec.has(key),"architecture field "+key)
		var first:int=spec.collision[0];var count:int=spec.collision[1]
		check(count>=1 and count<=int(lv.collision_rects_max) and first>=0 and first+count<=data.blocks.size(),"collision range bounded %s"%[spec.position])
		for k in range(first,mini(first+count,data.blocks.size())):used[k]+=1
		if spec.design=="rock":
			check(spec.get("terrain_feature","")=="hill" and count==1,"rock entry is one axis-aligned hill rect")
			continue
		buildings.append(spec);polys.append(obb(spec))
		designs[spec.design]=designs.get(spec.design,0)+1
		for key in ["floors","variant","palette","damage","seed","district"]:check(spec.has(key),"building field "+key)
		check(City.handles(spec.design),"design dispatched by CityBuildings: "+spec.design)
		if City.handles(spec.design):
			var row:Dictionary=City.DESIGNS[spec.design]
			var size:=vec(spec.source_size)
			check(size.x>=row.w[0]-0.01 and size.x<=row.w[1]+0.01 and size.y>=row.d[0]-0.01 and size.y<=row.d[1]+0.01,"%s size %s inside design range"%[spec.design,size])
			check(int(spec.floors)>=row.floors[0] and int(spec.floors)<=row.floors[1],"%s floors in range"%spec.design)
		check(int(spec.variant) in [0,1,2,3] and int(spec.palette) in [0,1,2,3] and int(spec.damage) in [0,1,2],"variant/palette/damage domains")
	check(used.count(1)==used.size(),"every collision rect belongs to exactly one entry")
	check(data.building_count==buildings.size() and buildings.size()>=450 and buildings.size()<=700,"450-700 buildings (%d)"%buildings.size())
	check(data.map_props.size()>=1500,"1500+ decor placements (%d)"%data.map_props.size())
	check(designs.size()>=20,"broad family use (%d designs)"%designs.size())

	# ---- oriented collision: <=6 rects covering the footprint with <=1 u excess.
	var excess_max:float=float(lv.collision_excess_max)
	var worst_excess:=0.0
	for spec in buildings:
		var first:int=spec.collision[0];var count:int=spec.collision[1]
		var rects:Array=[]
		for k in range(first,first+count):rects.append(rect(data.blocks[k]))
		for r in rects:
			for corner in rect_poly(r):worst_excess=maxf(worst_excess,obb_distance(spec,corner))
			check(Rect2(0,0,1024,768).encloses(r),"collision rect within map %s"%[spec.position])
		var size:=vec(spec.source_size);var yaw:=-deg_to_rad(float(spec.rotation_degrees))
		var steps:=Vector2i(ceili(size.x/0.5),ceili(size.y/0.5))
		var covered:=true
		for ix in steps.x+1:
			for iz in steps.y+1:
				var local:=Vector2(-size.x/2+size.x*ix/steps.x,-size.y/2+size.y*iz/steps.y)
				var p:=vec(spec.position)+local.rotated(yaw)
				if not rects.any(func(r):return r.grow(0.001).has_point(p)):covered=false;break
			if not covered:break
		check(covered,"collision covers oriented footprint %s %s"%[spec.design,spec.position])
		var axis_aligned:=is_zero_approx(fmod(absf(float(spec.rotation_degrees))+0.0005,90.0)-0.0005)
		check(count==1 or not axis_aligned,"axis-aligned building uses one rect")
		for corner in obb(spec)+PackedVector2Array([vec(spec.position)]):check(not terrain.is_water(corner),"building on land %s"%[spec.position])
	check(worst_excess<=excess_max+0.001,"collision excess <=1 u (worst %.3f)"%worst_excess)

	# ---- no overlaps (spatially bucketed SAT on oriented footprints).
	var grid:Dictionary={}
	for i in polys.size():
		var b:=poly_bounds(polys[i])
		for x in range(floori(b.position.x/32),floori(b.end.x/32)+1):
			for z in range(floori(b.position.y/32),floori(b.end.y/32)+1):
				var key:=Vector2i(x,z);if not grid.has(key):grid[key]=[]
				grid[key].append(i)
	var overlaps:=0;var seen:Dictionary={}
	for key in grid:
		var ids:Array=grid[key]
		for a in ids.size():
			for b in range(a+1,ids.size()):
				var pair:=Vector2i(mini(ids[a],ids[b]),maxi(ids[a],ids[b]))
				if seen.has(pair):continue
				seen[pair]=true
				if separation(polys[pair.x],polys[pair.y])<-0.01:overlaps+=1;if overlaps<4:printerr("overlap ",buildings[pair.x].position," ",buildings[pair.y].position)
	check(overlaps==0,"no building overlaps (%d)"%overlaps)

	# ---- road clearance, frontage setback and district land use.
	var limits:Dictionary=lv.setback_limits
	var allowed:={"centre":["classic_row","classic_corner","stalin_block","civic_hall","cathedral","colonnade_landing","market_hall"],
		"hillside":["stone_house","outbuilding","dacha_hut","garage_row"],"ravine":["garage_row","outbuilding","dacha_hut"],
		"port":["transit_shed","workshop_hall","port_admin","gatehouse","slipway"],
		"micro":["panel_5","panel_9","point_tower","school","kindergarten","shop_pavilion","garage_row"],
		"village":["stone_house","outbuilding","dacha_hut","barn_long","coop_shed"],"north":["stone_house","outbuilding","dacha_hut","panel_5","shop_pavilion"],
		"dacha":["dacha_hut","outbuilding"],"reserve":["barracks","workshop_hall","gatehouse"],"green":["petrol_station","outbuilding"],"headland":["fort_ruin"]}
	var district_polys:Dictionary={}
	for d in data.city_districts:
		var poly:=PackedVector2Array()
		for p in d.polygon:poly.append(vec(p))
		district_polys[d.id]=poly
	for i in buildings.size():
		var spec:Dictionary=buildings[i];var poly:PackedVector2Array=polys[i]
		check(road_gap(terrain,poly)>=float(lv.building_road_clearance)-0.01,"building clear of carriageway %s %s"%[spec.design,spec.position])
		var first:int=spec.collision[0]
		for k in range(first,first+int(spec.collision[1])):check(road_gap(terrain,rect_poly(rect(data.blocks[k])))>=-0.01,"collision rect off carriageway %s"%[spec.position])
		if spec.has("street"):
			var gap:=road_gap(terrain,poly,spec.street)
			var lim:Array=limits.get(spec.design,limits.get(spec.get("morphology",""),[0.0,60.0]))
			check(gap>=lim[0]-0.05 and gap<=lim[1]+0.05,"%s fronts %s within setback %s (%.2f)"%[spec.design,spec.street,lim,gap])
		check(allowed.has(spec.district) and spec.design in allowed[spec.district],"land use: %s allowed in %s"%[spec.design,spec.district])
		if district_polys.has(spec.district):
			var c:=vec(spec.position);var poly2:PackedVector2Array=district_polys[spec.district]
			var inside:=Geometry2D.is_point_in_polygon(c,poly2)
			if not inside:
				var near:=INF
				for k in poly2.size():near=minf(near,c.distance_to(Geometry2D.get_closest_point_to_segment(c,poly2[k],poly2[(k+1)%poly2.size()])))
				inside=near<=15.0
			check(inside,"%s stands in its district %s"%[spec.design,spec.district])
	check(not buildings.any(func(s):return s.design=="transit_shed" and s.district=="centre"),"no transit_shed in the historic centre")
	check(not buildings.any(func(s):return s.design=="panel_9" and s.district=="hillside"),"no panel_9 in the private sector")
	check(designs.get("point_tower",0)<=1 and designs.get("cathedral",0)==1,"landmarks are rare")
	var cathedral:Array=buildings.filter(func(s):return s.design=="cathedral")
	check(not cathedral.is_empty() and vec(cathedral[0].position).distance_to(vec(data.objectives[1]))<45,"cathedral on the OLD TOWN hilltop square")
	for kind in ["classic_row","stone_house","panel_5","transit_shed","garage_row","dacha_hut","barn_long"]:check(designs.get(kind,0)>0,"district family present: "+kind)
	var no_build:=["square","hill_park","cemetery","vineyard","tank_farm","parade","stockyard"]
	for space in data.open_spaces:
		if not space.kind in no_build:continue
		var poly:=PackedVector2Array()
		for p in space.polygon:poly.append(vec(p))
		for spec in buildings:
			if spec.get("landmark",false):continue
			check(not Geometry2D.is_point_in_polygon(vec(spec.position),poly),"open space kept open: "+space.name)

	# ---- clustered damage near objectives and the freight front.
	var hot:Array=lv.damage_hotspots.map(func(p):return vec(p))
	var near_count:=0;var near_damaged:=0;var far_damaged:=0
	for spec in buildings:
		var d:=INF
		for h in hot:d=minf(d,vec(spec.position).distance_to(h))
		if d<=60:near_count+=1;near_damaged+=int(int(spec.damage)>0)
		elif d>75:far_damaged+=int(int(spec.damage)>0)
	var fraction:=float(near_damaged)/maxf(1,near_count)
	check(far_damaged==0,"no damage away from the fighting (%d)"%far_damaged)
	check(fraction>=0.08 and fraction<=0.30,"10-20%% damage cluster near objectives (%.2f of %d)"%[fraction,near_count])

	# ---- decor: registry footprints, domains and blockers.
	var registry:Dictionary={}
	for bundle in ["city","street","rural","waterfront","battlefield"]:
		for spec in JSON.parse_string(FileAccess.get_file_as_string("res://resources/assets_%s.json"%bundle)):registry[spec.kind+"."+spec.variant]=spec
	var solid_count:=0;var sea_count:=0;var flat_count:=0
	var prop_ids:Dictionary={}
	for i in data.map_props.size():
		var prop:Dictionary=data.map_props[i];var bounds:=rect(prop.bounds)
		prop_ids[prop.id]=true
		var spec:Dictionary=registry.get(prop.id,Library.find(prop.id))
		check(not spec.is_empty(),"registered prop "+prop.id)
		if spec.is_empty():continue
		var f:Array=spec.footprint;var local:=Rect2(f[0],f[1],f[2],f[3]);var yaw:=-deg_to_rad(float(prop.rotation_degrees))
		var expected:=Rect2(vec(prop.position)+local.position.rotated(yaw),Vector2.ZERO)
		for corner in rect_poly(local):expected=expected.expand(vec(prop.position)+corner.rotated(yaw))
		check(bounds.grow(0.0002).encloses(expected) and bounds.size.distance_to(expected.size)<0.001,"registry footprint matches prop %d"%i)
		check(Rect2(0,0,1024,768).encloses(bounds) and not prop.cover and not prop.context.is_empty(),"prop bounds/cover/context %d"%i)
		for corner in rect_poly(bounds)+PackedVector2Array([bounds.get_center()]):check(terrain.is_water(corner)==(prop.domain=="sea"),"prop matches land/water domain %d"%i)
		if prop.collision=="flat":
			flat_count+=1
		elif prop.domain=="sea":sea_count+=1
		else:
			solid_count+=1
			check(road_gap(terrain,rect_poly(bounds))>=-0.01,"solid decor off carriageway %s %s"%[prop.id,prop.position])
	check(solid_count==data.prop_blocks.size() and sea_count==data.water_blocks.size() and flat_count>0,"compiled blocker lists exact")
	var block_grid:Dictionary={}
	for k in data.blocks.size():
		var r:=rect(data.blocks[k])
		for x in range(floori(r.position.x/32),floori(r.end.x/32)+1):
			for z in range(floori(r.position.y/32),floori(r.end.y/32)+1):
				var key:=Vector2i(x,z);if not block_grid.has(key):block_grid[key]=[]
				block_grid[key].append(r)
	var clashes:=0
	for prop in data.map_props:
		var bounds:=rect(prop.bounds)
		for r in block_grid.get(Vector2i(floori(bounds.get_center().x/32),floori(bounds.get_center().y/32)),[]):
			if bounds.intersects(r):clashes+=1
	check(clashes==0,"decor clear of building collision (%d)"%clashes)
	for id in ["tree.plane_street","wall.stone_yard","portal_crane.rail","rail_siding.straight","vineyard.trellis_row","playground.frame","tank.fuel_storage","tree.poplar","tree.cypress"]:check(prop_ids.has(id),"district decor present: "+id)

	# ---- roads keep a conservative infantry corridor; primaries stay >=16 u.
	for segment in terrain.roads.segments:
		var street:String=segment.from.rsplit(":",true,1)[0]
		check(segment.width>=6,"connected street width "+segment.from)
		if street in lv.primary_streets:check(segment.width>=float(lv.primary_road_min_width),"primary road width "+street)
		var direction:Vector2=(segment.b-segment.a).normalized()
		var normal:=Vector2(-direction.y,direction.x)
		var steps:=ceili(segment.a.distance_to(segment.b)/4)
		for step in range(steps+1):
			for offset in [0.0,maxf(0.0,segment.width/2-3.6),minf(0.0,-segment.width/2+3.6)]:
				var point:Vector2=segment.a.lerp(segment.b,float(step)/steps)+normal*offset
				if terrain.poles.any(func(p):return p.distance_to(point)<3.3):continue
				if terrain.is_water(point):continue
				check(terrain.traversable(point,"land",2.65),"road corridor clear "+segment.from+" @ "+str(point))

	# ---- route connectivity: land and sea route points reachable by navigation.
	var insertion:=vec(data.field_insertion)
	check(terrain.traversable(insertion,"land",2.65),"player insertion clear")
	var defs:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/units.json"))
	defs.merge(JSON.parse_string(FileAccess.get_file_as_string("res://resources/field_units.json")))
	for force in [data.player_force,data.enemy_force]:
		for unit in force:check(terrain.traversable(vec(unit.position),defs[unit.kind].domain,defs[unit.kind].radius),"authored force start clear "+unit.kind+" "+str(unit.position))
	var previous:=insertion
	for raw in lv.land_route_points:
		var point:=vec(raw)
		check(not terrain.path(previous,point,"land",2.65,[],"infantry").is_empty(),"bayhead land leg "+str(point))
		previous=point
	for raw in data.objectives:
		var objective:=vec(raw);var reachable:=false
		for direction in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
			var point:Vector2=objective+direction*5
			if terrain.traversable(point,"land",2.65) and not terrain.path(insertion,point,"land",2.65,[],"infantry").is_empty():reachable=true;break
		check(reachable,"ground reachable objective "+str(objective))
	var sea_insertion:=vec(data.field_sea_insertion)
	check(terrain.traversable(sea_insertion,"sea",3.3),"sea insertion clear")
	previous=sea_insertion
	for raw in lv.sea_route_points:
		var point:=vec(raw)
		check(terrain.traversable(point,"sea",20),"forty-unit sea channel "+str(point))
		check(not terrain.path(previous,point,"sea",3.3).is_empty(),"sea corridor connected "+str(point))
		previous=point
	for point in [Vector2(460,350),Vector2(460,400),Vector2(460,450),Vector2(460,500)]:check(terrain.traversable(point,"sea",20),"south inlet forty-unit channel "+str(point))
	check(not terrain.path(sea_insertion,Vector2(460,500),"sea",3.3).is_empty(),"south inlet navigable from open sea")
	var support:=vec(lv.boat_support_point)
	check(terrain.traversable(support,"sea",3.3) and support.distance_to(vec(data.objectives[0]))<=29,"coastal objective in plausible boat support range")
	check(terrain.line_clear(support,vec(data.objectives[0])),"coastal support sight line")
	print("HARBOR LAYOUT TESTS: ",checks," checks, ",failures.size()," failures")
	quit(1 if not failures.is_empty() else 0)
