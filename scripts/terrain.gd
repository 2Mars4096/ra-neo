class_name BattleTerrain
extends RefCounted

const SIZE := Vector2(96, 72)
const DOCKS:Array[Rect2]=[Rect2(79.5,39.75,9,2.5),Rect2(79.5,47.75,9,2.5)]
const CELL := 2.0
const GRID := Vector2i(48, 36)
# Constants remain legacy defaults; runtime consumers use these instance sizes.
var world_size:Vector2=SIZE
var fog_grid_size:Vector2i=GRID
var nav_size:Vector2i=Vector2i(SIZE)
var nav_cell_size:=1.0
var fog_cell_size:=2.0
var water_polygons:Array[PackedVector2Array]=[]
# 1-world-unit texels, row-major y*width+x, center-sampled 0/255 R8.
# Boundary texels use exact polygon queries for simulation, never mask rounding.
var water_mask:Image
var water_mask_data:=PackedByteArray()
var water_mask_size:=Vector2i.ZERO
var water_mask_cell_size:=1.0
var _water_boundary:=PackedByteArray()
var _coast_edges:Array=[]
var _coast_index:Dictionary={}
var map_props:Array=[]
var prop_blocks:Array[Rect2]=[]
var water_blocks:Array[Rect2]=[]
var static_cover:Array[Rect2]=[]
var use_static_index:=true
var _static_index:Dictionary={}
var _static_counts:Array=[]
const SPATIAL_CELL:=32.0
var field_mode:=false
var roads=preload("res://scripts/road_network.gd").new()
var scenario_id:=0
var style:="coast"
var port:=true
var shore_x:=82.0
var wetness:=0.0
var navigation: Dictionary = {}
var navigation_wetness_bucket:=-1
var navigation_weights:Dictionary={}
var navigation_weight_epoch:=0
var navigation_weight_wetness:=0.0
var navigation_weights_initialized:=false
# Per-cell soil class cache and per-profile layer progress (columns built).
var navigation_surface:=PackedByteArray()
var navigation_surface_columns:=0
var navigation_weight_columns:Dictionary={}
# Set once a simulation drives advance_navigation_weights() each tick.
var incremental_weights:=false
var dynamic_blocks:Array[Rect2]=[]
var field_cover:Array[Rect2]=[]
# Completed non-solid engineer works: {rect, speed:{profile:x}, cover:[classes], conceal}.
var field_zones:Array[Dictionary]=[]
var field_zone_buckets:Dictionary={}
const FIELD_ZONE_CELL:=8.0
var roadside_props:Array[Dictionary]=[]
var roadside_blocks:Array[Rect2]=[]
var architecture:Array=[]
var rubble:=Rect2(8,28,18,8)
var mud:=Rect2(48,55,18,9)
var trees: Array[Vector2] = []
var poles: Array[Vector2] = [Vector2(46,22),Vector2(74,46)]
var land := AStarGrid2D.new()
var sea := AStarGrid2D.new()
var blocks: Array[Rect2] = [Rect2(32, 26, 8, 20), Rect2(54, 40, 8, 14), Rect2(64, 10, 8, 8), Rect2(72, 30, 6, 6)]
var woods: Array[Rect2] = [Rect2(20, 12, 10, 14), Rect2(40, 44, 10, 16), Rect2(58, 22, 10, 10)]

func _init(preset:int=0, config_override:Dictionary={}) -> void:
	scenario_id=preset
	var definitions:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	var config:Dictionary=definitions[clampi(preset,0,definitions.size()-1)] if config_override.is_empty() else config_override
	var dimensions:Array=config.get("size",[96,72])
	world_size=Vector2(dimensions[0],dimensions[1])
	nav_cell_size=maxf(0.25,float(config.get("nav_cell_size",1.0)))
	fog_cell_size=maxf(0.25,float(config.get("fog_cell_size",2.0)))
	fog_grid_size=Vector2i((world_size/fog_cell_size).ceil())
	nav_size=Vector2i((world_size/nav_cell_size).ceil())
	field_mode=config.get("mode","")=="field_ops"
	map_props=config.get("map_props",[]).duplicate(true)
	architecture=config.get("architecture",[])
	for r in config.get("prop_blocks",[]):prop_blocks.append(Rect2(r[0],r[1],r[2],r[3]))
	_index_crushables()
	# Built at load (~20 ms on the harbor), not on an aircraft's first tick.
	if not architecture.is_empty() or not map_props.is_empty():_build_air_ceiling()
	for r in config.get("water_blocks",[]):water_blocks.append(Rect2(r[0],r[1],r[2],r[3]))
	for r in config.get("static_cover",[]):static_cover.append(Rect2(r[0],r[1],r[2],r[3]))
	for polygon in config.get("water_polygons",[]):
		var points:=PackedVector2Array()
		for point in polygon:points.append(Vector2(point[0],point[1]))
		if points.size()>=3:water_polygons.append(points)
	style=config.get("style","coast")
	roads=preload("res://scripts/road_network.gd").new(config.get("roads",{}))
	port=config.get("port",true)
	shore_x=float(config.get("shore_x",82.0))
	roadside_props=preload("res://scripts/roadside_props.gd").layout(scenario_id)
	for prop in roadside_props:
		roadside_blocks.append(preload("res://scripts/roadside_props.gd").footprint(prop))
	poles.clear()
	for point in config.get("objectives",[[46,22],[74,46]]):poles.append(Vector2(point[0],point[1]))
	blocks.clear();woods.clear()
	for r in config.blocks:blocks.append(Rect2(r[0],r[1],r[2],r[3]))
	for r in config.woods:woods.append(Rect2(r[0],r[1],r[2],r[3]))
	rubble=Rect2(config.rubble[0],config.rubble[1],config.rubble[2],config.rubble[3])
	mud=Rect2(config.mud[0],config.mud[1],config.mud[2],config.mud[3])
	# Trees and collision share the same authored positions. Keep navigable lanes through cover.
	for forest in woods:
		for side in [1.0,forest.size.x-1.0]:
			for z in range(1,int(forest.size.y),4):
				trees.append(forest.position+Vector2(side,float(z)))
	rebuild_static_index(false)
	_rebuild_water_mask()
	for grid in [land, sea]:
		grid.region = Rect2i(Vector2i.ZERO, fog_grid_size)
		grid.cell_size = Vector2.ONE*fog_cell_size
		grid.offset=Vector2.ONE*fog_cell_size*0.5
		grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		grid.update()
	for x in fog_grid_size.x:
		for y in fog_grid_size.y:
			var id := Vector2i(x, y)
			var p := center(id)
			land.set_point_solid(id, is_water(p) or blocked(p))
			sea.set_point_solid(id, not is_water(p))
			land.set_point_weight_scale(id, 1.0/ground_speed(p))

func center(id: Vector2i) -> Vector2:
	return (Vector2(id)+Vector2.ONE*0.5)*fog_cell_size

func cell(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(p.x / fog_cell_size), 0, fog_grid_size.x - 1), clampi(int(p.y / fog_cell_size), 0, fog_grid_size.y - 1))

func nav_center(id:Vector2i)->Vector2:
	return (Vector2(id)+Vector2.ONE*0.5)*nav_cell_size

func nav_cell(p:Vector2)->Vector2i:
	return Vector2i((p/nav_cell_size).floor())

func is_water(p: Vector2) -> bool:
	if water_polygons.is_empty():return p.x>=shore_x
	var id:=Vector2i((p/water_mask_cell_size).floor())
	if id.x<0 or id.y<0 or id.x>=water_mask_size.x or id.y>=water_mask_size.y:return _water_exact(p)
	var offset:=id.y*water_mask_size.x+id.x
	return _water_exact(p) if _water_boundary[offset]!=0 else water_mask_data[offset]!=0

func blocked(p: Vector2) -> bool:
	for r in _static_candidates("solid",p,0.0):
		if r.has_point(p):return true
	return false

func cover(p: Vector2,include_field:bool=true) -> bool:
	for rect in (field_cover if include_field else []):
		if rect.grow(1.4).has_point(p) and not rect.has_point(p):return true
	if include_field:
		for zone in _field_zones_at(p):
			if "infantry" in zone.cover and zone.rect.has_point(p):return true
	if style=="showcase":
		for building in _static_candidates("building",p,1.4):
			if building.grow(1.4).has_point(p) and not building.has_point(p):return true
		for building in (dynamic_blocks if not field_mode else []):
			if building.grow(1.4).has_point(p) and not building.has_point(p):return true
	if rubble.has_point(p):return true
	for r in _static_candidates("cover",p,0.0):
		if r.has_point(p):
			return true
	return false

func on_road(p:Vector2) -> bool:
	return roads.contains(p)

# Multipliers are explicit game balance approximations, not vehicle specifications.
const MOBILITY:Dictionary={
	"infantry":{"open":1.0,"mud":0.72,"rough":0.82,"wet_open":0.08,"wet_mud":0.15,"wet_rough":0.08},
	"tracked":{"open":0.88,"mud":0.62,"rough":0.65,"wet_open":0.08,"wet_mud":0.25,"wet_rough":0.10},
	"wheeled":{"open":0.72,"mud":0.30,"rough":0.42,"wet_open":0.16,"wet_mud":0.45,"wet_rough":0.20}}

func mobility_profile(kind:String)->String:
	if kind in ["rifle","atgm","engineer"]:return "infantry"
	if kind=="harvester":return "wheeled"
	return "tracked"

func ground_speed(p:Vector2,profile:String="default") -> float:
	var zone:=1.0
	for item in _field_zones_at(p):
		if item.rect.has_point(p):zone=minf(zone,float(item.speed.get(profile,1.0)))
	return zone*_base_ground_speed(p,profile)

func _base_ground_speed(p:Vector2,profile:String) -> float:
	return _surface_speed(_surface_class(p),profile)

# Soil class (index into SURFACES). Classifying is the costly part of ground
# speed; navigation caches it per cell so weather re-weights are table lookups.
const SURFACES:=["road","mud","rough","open"]
func _surface_class(p:Vector2)->int:
	if on_road(p):return 0
	if mud.has_point(p):return 1
	return 2 if cover(p,false) else 3

func _surface_speed(surface:int,profile:String)->float:
	if surface==0:return 1.0
	if not MOBILITY.has(profile):
		if surface==1:return 0.5*(1.0-wetness*0.25)
		return (0.7 if surface==2 else 1.0)*(1.0-wetness*0.12)
	var factors:Dictionary=MOBILITY[profile]
	var name:String=SURFACES[surface]
	return float(factors[name])*(1.0-wetness*float(factors["wet_"+name]))

# Detection multiplier for land units under engineer camouflage.
func concealment(p:Vector2) -> float:
	var factor:=1.0
	for zone in _field_zones_at(p):
		if zone.rect.has_point(p):factor=minf(factor,float(zone.get("conceal",1.0)))
	return factor

func _field_zones_at(p:Vector2)->Array:
	return field_zone_buckets.get(Vector2i(floori(p.x/FIELD_ZONE_CELL),floori(p.y/FIELD_ZONE_CELL)),[])

# Anti-tank works physically exclude vehicles (tracked/wheeled); infantry pass.
const VEHICLE_PROFILES:=["tracked","wheeled"]
func vehicle_barrier(p:Vector2,radius:float=0.0) -> bool:
	if field_zones.is_empty():return false
	for zone in field_zones:
		if not zone.rect.grow(radius).has_point(p):continue
		if float(zone.speed.get("tracked",1.0))<=0.05 or float(zone.speed.get("wheeled",1.0))<=0.05:return true
	return false

# A zone is a navigation barrier for a profile when it all but stops it
# (wire for infantry, hedgehogs for vehicles). Units may still crawl through
# when no route exists, but planners route around.
const BARRIER_SPEED:=0.2
var barrier_zones:Dictionary={}
func profile_barrier(p:Vector2,reach:float,profile:String) -> bool:
	for rect in barrier_zones.get(profile,[]):
		if rect.grow(reach).has_point(p):return true
	return false

# Navigation solidity for a land cell, including profile-specific barriers. A
# barrier blocks every cell its rectangle touches (thin wire would otherwise
# slip between 4 u cell centres).
func _land_cell_solid(point:Vector2,radius:float,profile:String) -> bool:
	var saved:=crush_pass
	crush_pass=profile=="tracked"
	var solid:=not traversable(point,"land",radius)
	crush_pass=saved
	if solid:return true
	return profile_barrier(point,radius+nav_cell_size*0.5,profile)

# Coarse vehicle grids: a cell whose centre is too close to geometry stays open
# when one of its sub-points fits the hull. Paths then pass through that point
# (the cell's anchor), so 4 u cells no longer close gaps a vehicle fits through.
const ANCHOR_ROOM:=0.5
const SHORTCUT_ROOM:=0.3
const ANCHOR_OFFSETS:=[Vector2(1,0),Vector2(-1,0),Vector2(0,1),Vector2(0,-1),Vector2(1,1),Vector2(-1,1),Vector2(1,-1),Vector2(-1,-1)]
func _refresh_land_cell(grid:AStarGrid2D,id:Vector2i,radius:float,profile:String)->void:
	var point:=nav_center(id)
	var anchors:Dictionary=grid.get_meta("anchors",{})
	anchors.erase(id)
	var solid:=_land_cell_solid(point,radius,profile)
	if solid and nav_cell_size>=2.0 and profile in VEHICLE_PROFILES and not profile_barrier(point,radius+nav_cell_size*0.5,profile):
		var spacing:=nav_cell_size/3.0
		var reach:=spacing*1.415
		var saved:=crush_pass
		crush_pass=profile=="tracked"
		# Clearance changes by at most the offset, so a centre that fails at
		# radius-reach rules out every sub-point (one cheap test for wall cells).
		# Prefer a sub-point with room to spare so routes keep off the walls.
		if radius<=reach+0.01 or traversable(point,"land",radius-reach):
			var fit:=Vector2.INF
			for offset in ANCHOR_OFFSETS:
				var candidate:Vector2=point+offset*spacing
				if not traversable(candidate,"land",radius):continue
				if traversable(candidate,"land",radius+ANCHOR_ROOM):fit=candidate;break
				if not fit.is_finite():fit=candidate
			if fit.is_finite():anchors[id]=fit;solid=false
		crush_pass=saved
	grid.set_point_solid(id,solid)

func _anchor(anchors:Dictionary,id:Vector2i)->Vector2:
	return anchors.get(id,nav_center(id))

# Field zones that protect infantry standing inside them (trench, hedgehog belt).
func zone_cover(p:Vector2) -> bool:
	for zone in _field_zones_at(p):
		if "infantry" in zone.cover and zone.rect.has_point(p):return true
	return false

# Dug fighting positions: soldiers inside crouch below the parapet.
func dug_in(p:Vector2) -> bool:
	for zone in _field_zones_at(p):
		if zone.get("dug",false) and zone.rect.has_point(p):return true
	return false

func hull_down(p:Vector2,threat:Vector2=Vector2(INF,INF)) -> bool:
	for zone in _field_zones_at(p):
		if "vehicle" not in zone.cover or not zone.rect.has_point(p):continue
		# U-shaped earthworks protect front/sides, never the open rear approach.
		if threat.is_finite() and (threat-p).normalized().dot(zone.get("front",Vector2.UP))< -0.35:continue
		return true
	return false

# Replace completed field zones; only navigation weights inside changed rects
# are recomputed, never collision solids (zones are not blockers).
func update_field_zones(zones:Array)->bool:
	# Rubble of collapsed buildings persists under whatever works are built.
	_zone_input=zones
	if not rubble_zones.is_empty():zones=zones+rubble_zones
	var changed:Array[Rect2]=[]
	var keys:=zones.map(func(z):return [z.rect,z.speed,z.cover,z.get("conceal",1.0),z.get("front",Vector2.UP)])
	var old:=field_zones.map(func(z):return [z.rect,z.speed,z.cover,z.get("conceal",1.0),z.get("front",Vector2.UP)])
	if keys==old:return false
	for zone in zones+field_zones:
		if not changed.has(zone.rect):changed.append(zone.rect)
	field_zones.clear()
	field_zone_buckets.clear()
	barrier_zones.clear()
	for source in zones:
		for profile in ["infantry","tracked","wheeled"]:
			if float(source.speed.get(profile,1.0))<=BARRIER_SPEED:
				if not barrier_zones.has(profile):barrier_zones[profile]=[]
				barrier_zones[profile].append(source.rect)
	for source in zones:
		var zone:Dictionary=source.duplicate(true)
		field_zones.append(zone)
		for x in range(floori(zone.rect.position.x/FIELD_ZONE_CELL),floori(zone.rect.end.x/FIELD_ZONE_CELL)+1):
			for y in range(floori(zone.rect.position.y/FIELD_ZONE_CELL),floori(zone.rect.end.y/FIELD_ZONE_CELL)+1):
				var key:=Vector2i(x,y)
				if not field_zone_buckets.has(key):field_zone_buckets[key]=[]
				field_zone_buckets[key].append(zone)
	if navigation_weights.is_empty():return true
	var affected:Dictionary={}
	for rect in changed:
		var bounds:Rect2=rect.grow(nav_cell_size)
		for x in range(maxi(0,floori(bounds.position.x/nav_cell_size)),mini(nav_size.x,ceili(bounds.end.x/nav_cell_size))):
			for y in range(maxi(0,floori(bounds.position.y/nav_cell_size)),mini(nav_size.y,ceili(bounds.end.y/nav_cell_size))):
				affected[Vector2i(x,y)]=true
	var live_wetness:=wetness
	wetness=navigation_weight_wetness
	for profile in navigation_weights:
		var layer:PackedFloat32Array=navigation_weights[profile]
		for cell_id in affected:layer[cell_id.x*nav_size.y+cell_id.y]=1.0/maxf(0.001,ground_speed(nav_center(cell_id),profile))
		navigation_weights[profile]=layer
	wetness=live_wetness
	for key in navigation:
		if str(key).get_slice(":",0)!="land":continue
		var profile:=str(key).get_slice(":",2)
		if not navigation_weights.has(profile):continue
		var grid:AStarGrid2D=navigation[key]
		var layer:PackedFloat32Array=navigation_weights[profile]
		for cell_id in affected:grid.set_point_weight_scale(cell_id,layer[cell_id.x*nav_size.y+cell_id.y])
		if profile in ["infantry","tracked","wheeled"]:
			var radius:float=grid.get_meta("navigation_radius")
			for rect in changed:
				var bounds:Rect2=rect.grow(radius+0.27+nav_cell_size)
				for x in range(maxi(0,floori(bounds.position.x/nav_cell_size)),mini(nav_size.x,ceili(bounds.end.x/nav_cell_size))):
					for y in range(maxi(0,floori(bounds.position.y/nav_cell_size)),mini(nav_size.y,ceili(bounds.end.y/nav_cell_size))):
						_refresh_land_cell(grid,Vector2i(x,y),radius+0.15,profile)
	return true

func surface_name(p:Vector2) -> String:
	if is_water(p):return "WATER"
	for zone in rubble_zones:
		if zone.rect.has_point(p):return "RUBBLE · COVER · VEHICLES SLOWED"
	if on_road(p):return "FIRM ROAD · ALL WEATHER"
	if mud.has_point(p):return "WET MUD · VERY SLOW" if wetness>0.3 else "SOFT GROUND · SLOW"
	if rubble.has_point(p):return "RUINS · COVER"
	for zone in field_zones:
		if zone.rect.has_point(p) and "vehicle" in zone.cover:return "HULL-DOWN BERM"
		if zone.rect.has_point(p) and float(zone.get("conceal",1.0))<1.0:return "CAMOUFLAGED"
		if zone.rect.has_point(p) and float(zone.speed.get("infantry",1.0))<0.5:return "WIRE · INFANTRY SLOWED"
	if cover(p) and not cover(p,false):return "FIELD COVER"
	if cover(p,false):return "TERRAIN · COVER"
	return "OPEN GROUND"

func inside(p: Vector2) -> bool:
	return Rect2(Vector2(1, 1), world_size - Vector2(2, 2)).has_point(p)

func default_radius(domain: String) -> float:
	return 3.3 if domain=="sea" else (1.55 if domain=="air" else 1.8)

func traversable(p: Vector2, domain: String, radius: float = -1) -> bool:
	if radius<0: radius=default_radius(domain)
	if p.x<radius or p.y<radius or p.x>world_size.x-radius or p.y>world_size.y-radius:
		return false
	if domain=="air":
		return true
	if domain=="sea":
		if water_polygons.is_empty():
			if p.x<shore_x+radius:return false
		elif not _coast_clear(p,radius,true):return false
		for rect in _static_candidates("water",p,radius):
			if circle_rect(p,radius,rect):return false
		# Piers are physical obstacles for vessels, not decorative geometry.
		if port:
			for dock in DOCKS:
				if circle_rect(p,radius,dock): return false
		return true
	if water_polygons.is_empty():
		if p.x>shore_x-radius:return false
	elif not _coast_clear(p,radius,false):return false
	var pole_distance_squared:=pow(radius+0.15,2)
	for pole in poles:
		if p.distance_squared_to(pole)<pole_distance_squared:return false
	if port:
		for dock in DOCKS:
			if circle_rect(p,radius,dock):return false
	for rect in _static_candidates("solid",p,radius+0.12):
		if circle_rect(p,radius+0.12,rect) and not (crush_pass and crushables.has(rect)):return false
	for rect in dynamic_blocks:
		if circle_rect(p,radius+0.12,rect):return false
	var tree_distance_squared:=pow(radius+1.2,2)
	for tree in _static_candidates("tree",p,radius+1.2):
		if p.distance_squared_to(tree)<tree_distance_squared:return false
	# Container stacks at the quay.
	if port and circle_rect(p,radius,Rect2(76.5,57.3,3,9.4)): return false
	return true

func circle_rect(p: Vector2, radius: float, rect: Rect2) -> bool:
	return p.distance_squared_to(p.clamp(rect.position,rect.end)) < radius*radius

# Apply physical field reservations without discarding cached obstacle grids.
# Call outside an in-flight path query (path's local exclusions are synchronous).
# Rectangle order/duplicates do not change their physical union.
func update_field_geometry(blocks:Array,covers:Array)->bool:
	var next_blocks:Array[Rect2]=[]
	var next_covers:Array[Rect2]=[]
	for rect in blocks:
		if not next_blocks.has(rect):next_blocks.append(rect)
	for rect in covers:
		if not next_covers.has(rect):next_covers.append(rect)
	var changed:Array[Rect2]=[]
	for rect in dynamic_blocks:
		if not next_blocks.has(rect) and not changed.has(rect):changed.append(rect)
	for rect in next_blocks:
		if not dynamic_blocks.has(rect):changed.append(rect)
	var cover_changed:=false
	for rect in field_cover:
		if not next_covers.has(rect):cover_changed=true
	for rect in next_covers:
		if not field_cover.has(rect):cover_changed=true
	dynamic_blocks=next_blocks
	field_cover=next_covers
	if not changed.is_empty():
		for key in navigation:
			if str(key).get_slice(":",0)!="land":continue
			var grid:AStarGrid2D=navigation[key]
			# Cache keys round radii for lookup; use the actual radius with
			# which this grid was built, never a rounded reconstruction.
			var radius:float=grid.get_meta("navigation_radius")
			var affected:Dictionary={}
			for rect in changed:
				# nav_grid adds .15, traversable adds .12 for rectangles; anchors
				# reach a further sub-cell diagonal.
				var bounds:Rect2=rect.grow(radius+0.27+nav_cell_size*0.48)
				for x in range(maxi(0,floori(bounds.position.x/nav_cell_size)),mini(nav_size.x,ceili(bounds.end.x/nav_cell_size))):
					for y in range(maxi(0,floori(bounds.position.y/nav_cell_size)),mini(nav_size.y,ceili(bounds.end.y/nav_cell_size))):
						affected[Vector2i(x,y)]=true
			var grid_profile:=str(key).get_slice(":",2)
			for cell_id in affected:
				_refresh_land_cell(grid,cell_id,radius+0.15,grid_profile)
	# Field cover changes protection, not the underlying soil/road firmness.
	# Other showcase scenarios derive surface roughness from dynamic blocks.
	if not changed.is_empty() and style=="showcase" and not field_mode:
		navigation_weights.clear()
		navigation_surface_columns=0
		navigation_weights_initialized=false
		navigation_weight_epoch+=1
		navigation_weight_wetness=wetness
		navigation_wetness_bucket=int(wetness*4)
	return not changed.is_empty()

# Surface classes of nav columns [0,end). Reset navigation_surface_columns
# whenever soil/cover geometry changes; weather alone never invalidates it.
func _surface_upto(end:int)->void:
	if navigation_surface.size()!=nav_size.x*nav_size.y:
		navigation_surface.resize(nav_size.x*nav_size.y);navigation_surface_columns=0
	for x in range(navigation_surface_columns,end):
		for y in nav_size.y:navigation_surface[x*nav_size.y+y]=_surface_class(nav_center(Vector2i(x,y)))
	navigation_surface_columns=maxi(navigation_surface_columns,end)

# Weight layer of a profile with columns [0,end) priced at the band's wetness
# sample: a table lookup per cell, exact ground_speed inside field zones.
func _weight_layer_upto(profile:String,end:int)->PackedFloat32Array:
	var weights:PackedFloat32Array
	if navigation_weights.has(profile):weights=navigation_weights[profile]
	else:
		weights.resize(nav_size.x*nav_size.y)
		navigation_weight_columns[profile]=0
	var start:int=navigation_weight_columns.get(profile,0)
	navigation_weights_initialized=true
	if start>=end:
		navigation_weights[profile]=weights
		return weights
	_surface_upto(end)
	# All lazily requested profiles use the same wetness sample as the first
	# query of this band, preserving the previous eager refresh's weights.
	var live_wetness:=wetness
	wetness=navigation_weight_wetness
	var inverse:=PackedFloat64Array()
	for surface in SURFACES.size():inverse.append(1.0/_surface_speed(surface,profile))
	var rows:=nav_size.y
	for x in range(start,end):
		for i in range(x*rows,x*rows+rows):weights[i]=inverse[navigation_surface[i]]
	for zone in field_zones:
		var rect:Rect2=zone.rect
		for x in range(maxi(start,floori(rect.position.x/nav_cell_size)),mini(end,ceili(rect.end.x/nav_cell_size)+1)):
			for y in range(maxi(0,floori(rect.position.y/nav_cell_size)),mini(rows,ceili(rect.end.y/nav_cell_size)+1)):
				var point:=nav_center(Vector2i(x,y))
				if rect.has_point(point):weights[x*rows+y]=1.0/ground_speed(point,profile)
	wetness=live_wetness
	navigation_weights[profile]=weights
	navigation_weight_columns[profile]=end
	return weights

func _navigation_weight_layer(profile:String)->PackedFloat32Array:
	return _weight_layer_upto(profile,nav_size.x)

# Copy layer columns [resume,end) into a cached grid; complete at nav_size.x.
func _refresh_grid_weights(grid:AStarGrid2D,profile:String,end:int)->void:
	if grid.get_meta("weight_epoch",-1)==navigation_weight_epoch:return
	var start:=_grid_weight_column(grid)
	if start<end:
		var weights:=_weight_layer_upto(profile,end)
		var rows:=nav_size.y
		for x in range(start,end):
			for y in rows:grid.set_point_weight_scale(Vector2i(x,y),weights[x*rows+y])
	if end>=nav_size.x:grid.set_meta("weight_epoch",navigation_weight_epoch)
	else:
		grid.set_meta("weight_pending",navigation_weight_epoch)
		grid.set_meta("weight_column",maxi(start,end))

func _grid_weight_column(grid:AStarGrid2D)->int:
	return grid.get_meta("weight_column",0) if grid.get_meta("weight_pending",-1)==navigation_weight_epoch else 0

func _sync_weight_band(domain:String)->void:
	var explicit:=navigation_weights.is_empty() and navigation_weights_initialized
	if explicit:navigation_surface_columns=0
	var bucket:=int(wetness*4)
	if bucket!=navigation_wetness_bucket:
		navigation_wetness_bucket=bucket
		navigation_weights.clear()
		navigation_weights_initialized=false
		navigation_weight_epoch+=1
		navigation_weight_wetness=wetness
	# Explicit weight-cache invalidation also starts a coherent new sample.
	elif domain=="land" and explicit:
		navigation_weight_epoch+=1
		navigation_weight_wetness=wetness
		navigation_weights_initialized=false

# Simulation tick hook. Weather bands re-weight cached land grids a fixed number
# of cells per tick (deterministic, never a whole-map stall inside one unit's
# query). Until a grid catches up, paths price its remaining columns with the
# previous band; solids are always current, so routes stay valid.
const SURFACE_COST:=32 # classifying a cell costs ~32 weight writes
func advance_navigation_weights(cells:int)->void:
	incremental_weights=true
	_sync_weight_band("land")
	var columns:=maxi(1,cells/maxi(1,nav_size.y))
	for key in navigation:
		if str(key).get_slice(":",0)!="land":continue
		var grid:AStarGrid2D=navigation[key]
		if grid.get_meta("weight_epoch",-1)==navigation_weight_epoch:continue
		var start:=_grid_weight_column(grid)
		var end:=mini(nav_size.x,start+columns)
		if navigation_surface_columns<end:
			_surface_upto(mini(end,navigation_surface_columns+maxi(1,columns/SURFACE_COST)))
			end=mini(end,navigation_surface_columns)
			columns=0
		if end>start:_refresh_grid_weights(grid,str(key).get_slice(":",2),end)
		columns-=end-start
		if columns<=0:return

func nav_grid(domain: String, radius: float, profile:String="default") -> AStarGrid2D:
	return _nav_grid(domain,radius,profile,true)

# current=false (ticking simulations) returns a cached grid mid weather refresh.
func _nav_grid(domain:String,radius:float,profile:String,current:bool)->AStarGrid2D:
	_ensure_static_index()
	if domain!="land":profile="default"
	_sync_weight_band(domain)
	var key:="%s:%.2f:%s" % [domain,radius,profile]
	if navigation.has(key):
		var cached:AStarGrid2D=navigation[key]
		if domain=="land" and current:_refresh_grid_weights(cached,profile,nav_size.x)
		return cached
	var weights:=_navigation_weight_layer(profile) if domain=="land" else PackedFloat32Array()
	var grid:=AStarGrid2D.new()
	grid.region=Rect2i(Vector2i.ZERO,nav_size)
	grid.cell_size=Vector2.ONE*nav_cell_size
	grid.offset=Vector2.ONE*nav_cell_size*0.5
	grid.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	grid.set_meta("anchors",{})
	for x in nav_size.x:
		for y in nav_size.y:
			var p:=nav_center(Vector2i(x,y))
			if domain=="land":_refresh_land_cell(grid,Vector2i(x,y),radius+0.15,profile)
			else:grid.set_point_solid(Vector2i(x,y),not traversable(p,domain,radius+0.15))
			grid.set_point_weight_scale(Vector2i(x,y),weights[x*nav_size.y+y] if domain=="land" else 1.0)
	grid.set_meta("weight_epoch",navigation_weight_epoch)
	grid.set_meta("navigation_radius",radius)
	navigation[key]=grid
	return grid

func segment_clear(a: Vector2, b: Vector2, domain: String, radius: float) -> bool:
	# Exact continuous coastline guard, including thin headlands between samples.
	if domain!="air" and not water_polygons.is_empty():
		if not _coast_clear(a,radius,domain=="sea") or not _coast_clear(b,radius,domain=="sea"):return false
		for edge in _coast_candidates(Rect2(a,b-a).abs().grow(radius)):
			if _segment_distance_squared(a,b,edge[0],edge[1])<radius*radius or Geometry2D.segment_intersects_segment(a,b,edge[0],edge[1])!=null:return false
	# Consecutive footprint circles overlap when samples are at most ~0.9 radius
	# apart, so no obstacle can slip between them; 0.35 m spacing was ~7x the work
	# for a section footprint and caused 100-300 ms path-smoothing stalls.
	var spacing:=maxf(0.35,radius*0.9)
	var steps:=maxi(1,ceili(a.distance_to(b)/spacing))
	for i in range(1,steps+1):
		if not traversable(a.lerp(b,float(i)/steps),domain,radius): return false
	return true

func nearest_cell(p: Vector2, grid: AStarGrid2D, domain: String, radius: float) -> Vector2i:
	return _nearest_open(p,nav_cell(p),grid,grid.get_meta("anchors",{}),domain,radius,[])

# Of the open cells in the 7x7 block around base, the one whose anchor is
# nearest p (earliest in x-major scan order on ties) and reachable from p in a
# clear straight line past `avoid`. Line checks run nearest-first and stop at
# the first success: the same cell as testing every candidate, for a fraction
# of the segment samples.
func _nearest_open(p:Vector2,base:Vector2i,grid:AStarGrid2D,anchors:Dictionary,domain:String,radius:float,avoid:Array)->Vector2i:
	var ids:Array[Vector2i]=[]
	var distances:=PackedFloat64Array()
	for x in range(base.x-3,base.x+4):
		for y in range(base.y-3,base.y+4):
			var id:=Vector2i(x,y)
			if not grid.is_in_boundsv(id) or grid.is_point_solid(id): continue
			ids.append(id);distances.append(p.distance_squared_to(_anchor(anchors,id)))
	while true:
		var pick:=-1
		var nearest:=INF
		for i in distances.size():
			if distances[i]<nearest:nearest=distances[i];pick=i
		if pick<0:return Vector2i(-1,-1)
		var point:=_anchor(anchors,ids[pick])
		if avoids_bodies(p,point,avoid) and segment_clear(p,point,domain,radius):return ids[pick]
		distances[pick]=INF
	return Vector2i(-1,-1)

# Project a click in open ground that is too tight for a whole unit. Never turn
# a click inside a solid parcel, water, or outside the map into an implicit move.
func reachable_destination(from:Vector2, desired:Vector2, domain:String, radius:float, profile:String="default") -> Vector2:
	if not inside(desired):return Vector2(-1,-1)
	if domain!="land":return Vector2(-1,-1)
	if is_water(desired) or blocked(desired):return Vector2(-1,-1)
	for rect in dynamic_blocks:
		if rect.has_point(desired):return Vector2(-1,-1)
	# In a batch every unit of a group scans the same candidates: memoise their
	# terrain checks (only reachability depends on `from`).
	var known:Dictionary=destination_memo.get_or_add("%s:%s" % [domain,radius],{}) if path_memo_active else {}
	for ring in range(0,13):
		for i in (1 if ring==0 else 32):
			var candidate:=desired+Vector2.from_angle(i*TAU/32.0)*(ring*0.5)
			var open=known.get(candidate)
			if open==null:
				open=traversable(candidate,domain,radius)
				known[candidate]=open
			if not open:continue
			if not path(from,candidate,domain,radius,[],profile).is_empty():return candidate
	return Vector2(-1,-1)

func path(from: Vector2, to: Vector2, domain: String, radius: float = -1, avoid:Array = [], profile:String="default") -> Array[Vector2]:
	if path_probe and avoid.is_empty():
		var reach:Array[Vector2]=[]
		if reachable(from,to,domain,radius,profile):reach.append(to)
		return reach
	var key:=[from,to,domain,radius,profile]
	var memo:=path_memo_active and avoid.is_empty()
	if memo and path_memo.has(key):return path_memo[key].duplicate()
	# Tracked vehicles plan straight through crushable street furniture.
	crush_pass=domain=="land" and profile=="tracked"
	var started:=Time.get_ticks_usec()
	var planned:=_path(from,to,domain,radius,avoid,profile)
	path_usec+=Time.get_ticks_usec()-started;path_calls+=1
	crush_pass=false
	if memo:path_memo[key]=planned.duplicate()
	return planned

# Opt-in reuse of identical obstacle-free queries while the caller guarantees
# that terrain and grids do not change (one command batch).
var path_memo_active:=false
var path_memo:Dictionary={}
func begin_path_memo()->void:
	path_memo_active=true;path_memo.clear();path_links.clear();path_link_memo.clear();destination_memo.clear()
func end_path_memo()->void:
	path_memo_active=false;path_memo.clear();path_links.clear();path_link_memo.clear();destination_memo.clear()

# While set, obstacle-free path() calls only answer reachability ([to] or []):
# lets a caller validate a destination now and plan the real route later.
var path_probe:=false
# Planning statistics for profiling tools.
var path_calls:=0
var path_usec:=0

# Grid-search reachability without route smoothing (~1 ms instead of ~20 ms
# for a cross-map route). Agrees with path() except in rare cases where a found
# cell chain cannot be string-pulled.
func reachable(from:Vector2,to:Vector2,domain:String,radius:float=-1,profile:String="default")->bool:
	if radius<0: radius=default_radius(domain)
	crush_pass=domain=="land" and profile=="tracked"
	var found:=_reachable(from,to,domain,radius,profile)
	crush_pass=false
	return found

func _reachable(from:Vector2,to:Vector2,domain:String,radius:float,profile:String)->bool:
	if not traversable(from,domain,radius) or not traversable(to,domain,radius):return false
	if domain=="air" or segment_clear(from,to,domain,radius):return true
	var grid:=_nav_grid(domain,radius,profile,not incremental_weights)
	if not path_memo_active:
		var start:=nearest_cell(from,grid,domain,radius)
		var end:=nearest_cell(to,grid,domain,radius)
		if start.x<0 or end.x<0:return false
		return not grid.get_id_path(start,end).is_empty()
	# Within a batch the grid is fixed, so connectivity is transitive: link both
	# ends to a cell of a route found earlier with short searches instead of a
	# cross-map one (exact). When only one end links to a route, the ends lie
	# in different components: no full search (each failed one explores the
	# whole start component, ~3 ms on the harbor map). Nearest cells and link
	# answers repeat across a group's queries: memoised for the batch.
	var memo:Dictionary=path_link_memo.get_or_add(grid,{})
	var start:=_memo_cell(from,grid,domain,radius,memo)
	var end:=_memo_cell(to,grid,domain,radius,memo)
	if start.x<0 or end.x<0:return false
	var links:Array=path_links.get_or_add(grid,[])
	for i in links.size():
		var linked:=_memo_linked(grid,start,i,links,memo)
		if linked!=_memo_linked(grid,end,i,links,memo):return false
		if linked:return true
	var ids:=grid.get_id_path(start,end)
	if ids.is_empty():return false
	var cells:=PackedVector2Array()
	for id in ids:cells.append(Vector2(id))
	links.append(cells)
	return true

var path_links:Dictionary={}
var path_link_memo:Dictionary={}
var destination_memo:Dictionary={}
func _memo_cell(p:Vector2,grid:AStarGrid2D,domain:String,radius:float,memo:Dictionary)->Vector2i:
	var cell=memo.get(p)
	if cell==null:
		cell=nearest_cell(p,grid,domain,radius)
		memo[p]=cell
	return cell
func _memo_linked(grid:AStarGrid2D,id:Vector2i,link:int,links:Array,memo:Dictionary)->bool:
	var key:=Vector3i(id.x,id.y,link)
	var linked=memo.get(key)
	if linked==null:
		linked=_linked(grid,id,links[link])
		memo[key]=linked
	return linked
func _linked(grid:AStarGrid2D,id:Vector2i,cells:PackedVector2Array)->bool:
	var best:=Vector2.ZERO
	var nearest:=INF
	for cell in cells:
		var distance:=Vector2(id).distance_squared_to(cell)
		if distance<nearest:nearest=distance;best=cell
	return nearest==0.0 or not grid.get_id_path(id,Vector2i(best)).is_empty()

func _path(from: Vector2, to: Vector2, domain: String, radius: float = -1, avoid:Array = [], profile:String="default") -> Array[Vector2]:
	var job:=_path_begin(from,to,domain,radius,avoid,profile)
	_path_smooth(job,-1)
	return job.result

# Resumable planning for budgeted callers. path_job() runs the grid search;
# path_job_step() string-pulls with at most `work` look-ahead segment checks
# per call. A job finished on unchanged terrain yields exactly path()'s route;
# edges published in a later step are checked against the terrain of that step.
func path_job(from:Vector2,to:Vector2,domain:String,radius:float=-1,avoid:Array=[],profile:String="default")->Dictionary:
	crush_pass=domain=="land" and profile=="tracked"
	var started:=Time.get_ticks_usec()
	var job:=_path_begin(from,to,domain,radius,avoid,profile)
	path_usec+=Time.get_ticks_usec()-started;path_calls+=1
	crush_pass=false
	return job

func path_job_step(job:Dictionary,work:int)->bool:
	if job.done:return true
	crush_pass=job.domain=="land" and job.profile=="tracked"
	var started:=Time.get_ticks_usec()
	job.edges.clear() # terrain may have changed since the last step
	_path_smooth(job,work)
	path_usec+=Time.get_ticks_usec()-started
	crush_pass=false
	return job.done

func _path_begin(from: Vector2, to: Vector2, domain: String, radius: float, avoid:Array, profile:String) -> Dictionary:
	var result: Array[Vector2] = []
	var job:={"done":true,"result":result,"work":0}
	if radius<0: radius=default_radius(domain)
	if not traversable(from,domain,radius) or not traversable(to,domain,radius): return job
	var direct_clear:bool=(domain=="air" or segment_clear(from,to,domain,radius)) and avoids_bodies(from,to,avoid)
	# Hulls cannot trace a line exactly (and footprints are sampled), so vehicle
	# shortcuts keep a margin. Every published edge still clears the true radius.
	var room:=radius+(SHORTCUT_ROOM if domain=="land" and profile in VEHICLE_PROFILES else 0.0)
	var direct_roomy:bool=direct_clear and (room==radius or segment_clear(from,to,domain,room))
	if direct_roomy and (domain!="land" or segment_travel_cost(from,to,domain,profile)<=from.distance_to(to)*1.01):
		result.append(to)
		return job
	var grid:=_nav_grid(domain,radius,profile,not incremental_weights)
	var start:=nearest_cell(from,grid,domain,radius)
	var end:=nearest_cell(to,grid,domain,radius)
	if start.x<0 or end.x<0:
		if direct_clear:result.append(to)
		return job
	var anchors:Dictionary=grid.get_meta("anchors",{})
	var changed:Array[Vector2i]=[]
	for body in avoid:
		for x in range(maxi(0,floori((body.pos.x-body.radius)/nav_cell_size)),mini(nav_size.x,ceili((body.pos.x+body.radius)/nav_cell_size))):
			for y in range(maxi(0,floori((body.pos.y-body.radius)/nav_cell_size)),mini(nav_size.y,ceili((body.pos.y+body.radius)/nav_cell_size))):
				var id:=Vector2i(x,y)
				if id==start or id==end or grid.is_point_solid(id):continue
				if _anchor(anchors,id).distance_to(body.pos)<body.radius:
					grid.set_point_solid(id,true);changed.append(id)
	# The nearest cell center can be inside a neighboring body even when the
	# actual position is clear. Pick a reachable center before asking AStar.
	if not avoid.is_empty():
		var safe_start:=_nearest_open(from,start,grid,anchors,domain,radius,avoid)
		if safe_start.x<0:
			for id in changed:grid.set_point_solid(id,false)
			if direct_clear:result.append(to)
			return job
		start=safe_start
	var ids:Array[Vector2i]=[]
	var raw: Array[Vector2]=[]
	# Edge checks repeat across anchor re-plans and smoothing: memoise them.
	var edges:Dictionary={}
	# An anchored cell can link to a neighbour across thin geometry. When such an
	# edge fails, close its anchored cells for this query and plan again.
	var skip:=0 if anchors.is_empty() else 2
	for attempt in 5:
		ids=grid.get_id_path(start,end)
		raw.clear()
		for id in ids:raw.append(_anchor(anchors,id))
		raw.append(to)
		if ids.is_empty() or anchors.is_empty():break
		var failed:=_first_blocked_edge(from,raw,domain,radius,avoid,skip,edges)
		if failed<0:break
		var closed:=false
		# Last attempt: plan on cell centres only (the conservative grid).
		for k in (range(ids.size()) if attempt==3 else [failed-1,failed]):
			if k<0 or k>=ids.size() or ids[k]==start or ids[k]==end or not anchors.has(ids[k]):continue
			grid.set_point_solid(ids[k],true);changed.append(ids[k]);closed=true
		if attempt==3:
			for id in anchors:
				if id!=start and id!=end and not grid.is_point_solid(id):grid.set_point_solid(id,true);changed.append(id)
		if not closed:break
	for id in changed:grid.set_point_solid(id,false)
	if ids.is_empty():
		if direct_clear:result.append(to)
		return job
	job.merge({"done":false,"raw":raw,"origin":from,"index":0,"from":from,"to":to,"domain":domain,"radius":radius,"room":room,"avoid":avoid,"profile":profile,"skip":skip,"direct_clear":direct_clear,"direct_roomy":direct_roomy,"edges":edges},true)
	return job

# String-pull only where the whole footprint clears geometry. work<0: finish.
func _path_smooth(job:Dictionary,work:int)->void:
	if job.done:return
	var result:Array[Vector2]=job.result
	var raw:Array[Vector2]=job.raw
	var from:Vector2=job.from
	var to:Vector2=job.to
	var domain:String=job.domain
	var radius:float=job.radius
	var room:float=job.room
	var avoid:Array=job.avoid
	var profile:String=job.profile
	var skip:int=job.skip
	var origin:Vector2=job.origin
	var index:int=job.index
	var spent:=0
	while index<raw.size():
		if work>=0 and spent>=work:
			job.origin=origin;job.index=index;job.work+=spent
			return
		# Grid cells alone do not certify their connecting edges (or dynamic
		# exclusions at the end cell). Never publish an unchecked first edge.
		# Anchored routes may step over a node whose own edge clips a corner.
		index=_reach(origin,raw,index,domain,radius,avoid,skip,job.edges)
		spent+=1
		if index<0:
			result.clear()
			if job.direct_clear:result.append(to)
			job.done=true;job.work+=spent
			return
		var furthest:=index
		var raw_costs:Array[float]=[segment_travel_cost(origin,raw[index],domain,profile)]
		# Bounded look-ahead keeps smoothing linear in route length. Find the
		# visible stretch, then price shortcuts from its far end back: the first
		# acceptable one is the furthest (as pricing every node found), and most
		# nodes skip the sampled travel-cost check.
		var visible:=index
		for next in range(index+1,mini(raw.size(),index+17)):
			if origin.distance_to(raw[next])>60.0:break
			raw_costs.append(raw_costs.back()+segment_travel_cost(raw[next-1],raw[next],domain,profile))
			spent+=1
			if not segment_clear(origin,raw[next],domain,room) or not avoids_bodies(origin,raw[next],avoid): break
			visible=next
		for next in range(visible,index,-1):
			if segment_travel_cost(origin,raw[next],domain,profile)<=raw_costs[next-index]*1.025:
				furthest=next
				break
		# Section envelopes are not rigid (soldiers step individually): only
		# hulls and default-profile routes are made exact.
		if profile!="infantry":spent+=_publish(result,origin,raw,index,furthest,domain,radius,avoid)
		else:result.append(raw[furthest])
		origin=raw[furthest]
		index=furthest+1
	if job.direct_roomy:
		var route_cost:=0.0
		var previous:=from
		for point in result:
			route_cost+=segment_travel_cost(previous,point,domain,profile);previous=point
		if segment_travel_cost(from,to,domain,profile)<=route_cost:
			result.clear();result.append(to)
	job.done=true;job.work+=spent

# Planning keeps the sampled clearance the nav grid is built with (an exact
# test there rejects cell chains the grid reports as connected and drops the
# route). Published edges are then made exact: a shortcut whose swept footprint
# clips a corner between samples bends at the skipped grid nodes instead (grid
# nodes carry +0.15 m clearance, so adjacent ones never clip). Never rejects:
# if no node helps, the sampled edge stands. Appends to result; returns checks.
func _publish(result:Array[Vector2],origin:Vector2,raw:Array[Vector2],first:int,last:int,domain:String,radius:float,avoid:Array)->int:
	var checks:=1
	var start:=origin
	while not _sweep_clear(start,raw[last],domain,radius):
		var pick:=-1
		for j in range(last-1,first-1,-1):
			checks+=1
			if segment_clear(start,raw[j],domain,radius) and _sweep_clear(start,raw[j],domain,radius) and avoids_bodies(start,raw[j],avoid):
				pick=j;break
		if pick<0:break
		result.append(raw[pick])
		start=raw[pick];first=pick+1
	result.append(raw[last])
	return checks

# Corner/point sweep for a segment whose samples already clear (see
# _corners_clear); skipped when the waist between samples is under 1 cm.
func _sweep_clear(a:Vector2,b:Vector2,domain:String,radius:float)->bool:
	if domain=="air":return true
	var steps:=maxi(1,ceili(a.distance_to(b)/maxf(0.35,radius*0.9)))
	var half:=a.distance_to(b)/steps*0.5
	if half*half<radius*radius-(radius-0.01)*(radius-0.01):return true
	return _corners_clear(a,b,domain,radius)

# Between segment_clear samples the footprint circles leave a waist where an
# obstacle corner, tree or pole can slip up to r-sqrt(r^2-(step/2)^2) inside
# the swept radius (26 cm for a 2.45 m hull). Samples (closer than any margin)
# catch every crossing, so testing corners and points against the whole segment
# makes the sweep exact. Obstacles the start footprint already touches keep
# sampled semantics, so a unit pressed against one can leave it.
func _corners_clear(a:Vector2,b:Vector2,domain:String,radius:float)->bool:
	var box:=Rect2(a,Vector2.ZERO).expand(b)
	var middle:=(a+b)*0.5
	var reach:=a.distance_to(b)*0.5
	var rects:Array=[]
	if domain=="sea":
		rects.append([_static_candidates("water",middle,reach+radius),radius])
	else:
		rects.append([_static_candidates("solid",middle,reach+radius+0.12),radius+0.12])
		rects.append([dynamic_blocks,radius+0.12])
		if port:rects.append([[Rect2(76.5,57.3,3,9.4)],radius])
	if port:rects.append([DOCKS,radius])
	for group in rects:
		var margin:float=group[1]
		var limit:=margin*margin
		for rect in group[0]:
			if not rect.grow(margin).intersects(box,true) or circle_rect(a,margin,rect):continue
			if crush_pass and crushables.has(rect):continue
			for corner in [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]:
				if Geometry2D.get_closest_point_to_segment(corner,a,b).distance_squared_to(corner)<limit:return false
	if domain=="sea":return true
	for points in [[_static_candidates("tree",middle,reach+radius+1.2),radius+1.2],[poles,radius+0.15]]:
		var limit:float=points[1]*points[1]
		for point in points[0]:
			if a.distance_squared_to(point)<limit:continue
			if Geometry2D.get_closest_point_to_segment(point,a,b).distance_squared_to(point)<limit:return false
	return true

# First raw node at or up to `skip` nodes after index reachable from origin
# with a clear footprint, or -1. `edges` memoises results for one query.
func _reach(origin:Vector2,raw:Array[Vector2],index:int,domain:String,radius:float,avoid:Array,skip:int,edges:Dictionary)->int:
	for next in range(index,mini(raw.size(),index+skip+1)):
		var key:=Vector4(origin.x,origin.y,raw[next].x,raw[next].y)
		var clear:bool
		if edges.has(key):clear=edges[key]
		else:
			clear=segment_clear(origin,raw[next],domain,radius) and avoids_bodies(origin,raw[next],avoid)
			edges[key]=clear
		if clear:return next
	return -1

# Index of the first raw node that cannot be reached from the route so far,
# or -1 when the whole chain clears geometry and avoided bodies.
func _first_blocked_edge(from:Vector2,raw:Array[Vector2],domain:String,radius:float,avoid:Array,skip:int,edges:Dictionary)->int:
	var previous:=from
	var index:=0
	while index<raw.size():
		var next:=_reach(previous,raw,index,domain,radius,avoid,skip,edges)
		if next<0:return index
		previous=raw[next];index=next+1
	return -1

func segment_travel_cost(a:Vector2,b:Vector2,domain:String="land",profile:String="default")->float:
	var length:=a.distance_to(b)
	if domain!="land":return length
	var samples:=maxi(1,ceili(length/minf(2.0,maxf(0.75,nav_cell_size*0.5))))
	var cost:=0.0
	for i in samples:cost+=length/samples/maxf(0.1,ground_speed(a.lerp(b,(i+0.5)/samples),profile))
	return cost

func line_clear(a: Vector2, b: Vector2) -> bool:
	var steps := maxi(1, ceili(a.distance_to(b) / 0.8))
	if steps<2:return true
	# Samples lie in the segment's box: rects missing it never hold one, so
	# filter them once per line instead of per sample (same answer).
	var box:=Rect2(a,Vector2.ZERO).expand(b).grow(0.01)
	var dynamic:Array[Rect2]=[]
	for rect in dynamic_blocks:
		if rect.intersects(box,true) and not rect.has_point(a) and not rect.has_point(b):dynamic.append(rect)
	# Unindexed (small) layouts list every solid per query: filter those too.
	var listed:=_static_unindexed()
	var solids:Array[Rect2]=[]
	if listed:
		for rect in _static_candidates("solid",a,0.0):
			if rect.intersects(box,true):solids.append(rect)
		if solids.is_empty() and dynamic.is_empty():return true
	for i in range(1, steps):
		var p:=a.lerp(b,float(i)/steps)
		if listed:
			for rect in solids:
				if rect.has_point(p):return false
		elif blocked(p):return false
		for rect in dynamic:
			if rect.has_point(p):return false
	return true

func avoids_bodies(a:Vector2,b:Vector2,bodies:Array) -> bool:
	for body in bodies:
		var direction:=b-a
		var fraction:=clampf((body.pos-a).dot(direction)/maxf(0.00001,direction.length_squared()),0,1)
		if (a+direction*fraction).distance_to(body.pos)<body.radius:return false
	return true

# After same-length in-place edits of static arrays, callers MUST invoke this
# API. Length changes are detected automatically; field edits use their API.
# Solid props big enough to hide behind (yard walls, fences, cars, kiosks,
# containers); thin posts such as lamps and bollards do not count.
# Street furniture a tracked vehicle flattens by driving into it (RA2-style).
# Walls, sheds, containers and buildings stay solid.
const CRUSHABLE:=["lamp","trolley_pole","bench","fence","tree","broken_tree","laundry_line","bus_stop","dumpster","kiosk","playground","pergola","haystack","car","pickup"]
var crushables:Dictionary={}  # prop_blocks rect -> {"block":int,"prop":int,"id":String}
var crush_pass:=false  # set while planning for tracked vehicles

func _index_crushables()->void:
	crushables.clear()
	var by_bounds:Dictionary={}
	for i in map_props.size():
		var prop:Dictionary=map_props[i]
		if prop.get("collision","")!="solid" or prop.get("domain","land")=="sea":continue
		var id:String=str(prop.get("id",prop.get("asset_id","")))
		if id.get_slice(".",0) not in CRUSHABLE or not prop.has("bounds"):continue
		var b:Array=prop.bounds
		by_bounds["%.2f,%.2f,%.2f,%.2f" % [b[0],b[1],b[2],b[3]]]={"prop":i,"id":id}
	for k in prop_blocks.size():
		var r:Rect2=prop_blocks[k]
		var key:="%.2f,%.2f,%.2f,%.2f" % [r.position.x,r.position.y,r.size.x,r.size.y]
		if by_bounds.has(key):crushables[r]={"block":k,"prop":by_bounds[key].prop,"id":by_bounds[key].id}

# Flattens crushable props touching a circle; returns their records. Only the
# affected navigation cells are refreshed (no global rebuild stall).
func crush_props(center:Vector2,radius:float)->Array:
	if crushables.is_empty():return []
	var hit:Array=[]
	for rect in _static_candidates("solid",center,radius+0.3):
		if crushables.has(rect) and circle_rect(center,radius+0.12,rect):hit.append(rect)
	if hit.is_empty():return []
	var records:Array=[]
	for rect in hit:
		var info:Dictionary=crushables[rect]
		crushables.erase(rect)
		# Keep array sizes stable so the static index is not rebuilt wholesale.
		prop_blocks[info.block]=Rect2(-9999,-9999,0,0)
		for kind in ["solid","building"]:
			var buckets:Dictionary=_static_index.get(kind,{})
			for x in range(floori(rect.position.x/SPATIAL_CELL),floori(rect.end.x/SPATIAL_CELL)+1):
				for y in range(floori(rect.position.y/SPATIAL_CELL),floori(rect.end.y/SPATIAL_CELL)+1):
					var bucket:Array=buckets.get(Vector2i(x,y),[])
					bucket.erase(rect)
		info["rect"]=rect
		records.append(info)
	_refresh_land_cells(hit)
	return records

func _refresh_land_cells(rects:Array)->void:
	for key in navigation:
		if str(key).get_slice(":",0)!="land":continue
		var grid:AStarGrid2D=navigation[key]
		var radius:float=grid.get_meta("navigation_radius")
		var profile:=str(key).get_slice(":",2)
		for rect in rects:
			var bounds:Rect2=rect.grow(radius+0.27+nav_cell_size*0.48)
			for x in range(maxi(0,floori(bounds.position.x/nav_cell_size)),mini(nav_size.x,ceili(bounds.end.x/nav_cell_size))):
				for y in range(maxi(0,floori(bounds.position.y/nav_cell_size)),mini(nav_size.y,ceili(bounds.end.y/nav_cell_size))):
					_refresh_land_cell(grid,Vector2i(x,y),radius+0.15,profile)

# A collapsed building: its collision rectangles leave the static index (array
# sizes stay stable, as in crush_props) and a rubble field zone takes their
# place: cover and slow going for infantry, slow for tracks, a planning barrier
# for wheels. Only navigation cells around the building are refreshed.
var rubble_zones:Array[Dictionary]=[]
var _zone_input:Array=[]
const RUBBLE_SPEED:={"infantry":0.55,"tracked":0.35,"wheeled":0.1}
func collapse_blocks(indices:Array,area:Rect2)->Array:
	var removed:Array=[]
	for k in indices:
		if k<0 or k>=blocks.size() or blocks[k].size==Vector2.ZERO:continue
		var rect:Rect2=blocks[k]
		blocks[k]=Rect2(-9999,-9999,0,0)
		for kind in ["solid","building"]:
			var buckets:Dictionary=_static_index.get(kind,{})
			for x in range(floori(rect.position.x/SPATIAL_CELL),floori(rect.end.x/SPATIAL_CELL)+1):
				for y in range(floori(rect.position.y/SPATIAL_CELL),floori(rect.end.y/SPATIAL_CELL)+1):
					var bucket:Array=buckets.get(Vector2i(x,y),[])
					bucket.erase(rect)
		removed.append(rect)
	rubble_zones.append({"rect":area,"speed":RUBBLE_SPEED.duplicate(),"cover":["infantry"],"conceal":1.0,"front":Vector2.UP,"rubble":true})
	update_field_zones(_zone_input if not _zone_input.is_empty() else field_zones.filter(func(z):return not z.get("rubble",false)))
	_refresh_land_cells(removed+[area])
	return removed

func hard_cover_props()->Array:
	return prop_blocks.filter(func(r):return maxf(r.size.x,r.size.y)>=1.5)

func rebuild_static_index(invalidate_navigation:bool=true)->void:
	_static_index.clear()
	var sets:Dictionary={"solid":blocks+roadside_blocks+prop_blocks,"building":blocks+hard_cover_props(),"cover":woods+static_cover,"tree":trees,"water":water_blocks}
	for kind in sets:
		var buckets:Dictionary={}
		for value in sets[kind]:
			var bounds:=Rect2(value,Vector2.ZERO) if value is Vector2 else Rect2(value)
			for x in range(floori(bounds.position.x/SPATIAL_CELL),floori(bounds.end.x/SPATIAL_CELL)+1):
				for y in range(floori(bounds.position.y/SPATIAL_CELL),floori(bounds.end.y/SPATIAL_CELL)+1):
					var id:=Vector2i(x,y)
					if not buckets.has(id):buckets[id]=[]
					buckets[id].append(value)
		_static_index[kind]=buckets
	_static_counts=[blocks.size(),roadside_blocks.size(),prop_blocks.size(),woods.size(),static_cover.size(),trees.size(),water_blocks.size()]
	if invalidate_navigation:
		navigation.clear();navigation_weights.clear()
	navigation_surface_columns=0

func _ensure_static_index()->void:
	if _static_counts.is_empty() or _static_counts[0]!=blocks.size() or _static_counts[1]!=roadside_blocks.size() or _static_counts[2]!=prop_blocks.size() or _static_counts[3]!=woods.size() or _static_counts[4]!=static_cover.size() or _static_counts[5]!=trees.size() or _static_counts[6]!=water_blocks.size():rebuild_static_index()

func _static_unindexed()->bool:
	return not use_static_index or blocks.size()+roadside_blocks.size()+prop_blocks.size()+trees.size()+woods.size()+static_cover.size()+water_blocks.size()<64

func _static_candidates(kind:String,p:Vector2,radius:float)->Array:
	# Tiny mutable legacy fixtures keep exhaustive semantics, including in-place
	# replacements. Large layouts use deterministic indexes, not per-query hashes.
	if _static_unindexed():
		match kind:
			"solid":return blocks+roadside_blocks+prop_blocks
			"building":return blocks+hard_cover_props()
			"cover":return woods+static_cover
			"tree":return trees
			"water":return water_blocks
	_ensure_static_index()
	var first:=Vector2i(((p-Vector2.ONE*radius)/SPATIAL_CELL).floor())
	var last:=Vector2i(((p+Vector2.ONE*radius)/SPATIAL_CELL).floor())
	var buckets:Dictionary=_static_index[kind]
	if first==last:return buckets.get(first,[])
	var found:Dictionary={}
	for x in range(first.x,last.x+1):
		for y in range(first.y,last.y+1):
			for value in buckets.get(Vector2i(x,y),[]):found[value]=true
	return found.keys()

func _water_exact(p:Vector2)->bool:
	# Explicit zero-width polygon boundary belongs to water. Avoid Godot's
	# tolerant boundary classification here: it hides narrow coastline probes.
	for polygon in water_polygons:
		var inside_polygon:=false
		for i in polygon.size():
			var a:Vector2=polygon[i];var b:Vector2=polygon[(i+1)%polygon.size()]
			var edge:=b-a;var offset:=p-a
			if edge.length_squared()>0 and edge.cross(offset)==0 and offset.dot(edge)>=0 and offset.dot(edge)<=edge.length_squared():return true
			if (a.y>p.y)!=(b.y>p.y) and p.x<(b.x-a.x)*(p.y-a.y)/(b.y-a.y)+a.x:inside_polygon=not inside_polygon
		if inside_polygon:return true
	return false

func _coast_candidates(bounds:Rect2)->Array:
	var found:Dictionary={}
	for x in range(floori(bounds.position.x/SPATIAL_CELL),floori(bounds.end.x/SPATIAL_CELL)+1):
		for y in range(floori(bounds.position.y/SPATIAL_CELL),floori(bounds.end.y/SPATIAL_CELL)+1):
			for index in _coast_index.get(Vector2i(x,y),[]):found[index]=true
	var result:Array=[]
	for index in found:result.append(_coast_edges[index])
	return result

func _coast_clear(p:Vector2,radius:float,water:bool)->bool:
	if is_water(p)!=water:return false
	for edge in _coast_candidates(Rect2(p-Vector2.ONE*radius,Vector2.ONE*radius*2)):
		if Geometry2D.get_closest_point_to_segment(p,edge[0],edge[1]).distance_squared_to(p)<radius*radius:return false
	return true

func _segment_distance_squared(a:Vector2,b:Vector2,c:Vector2,d:Vector2)->float:
	if Geometry2D.segment_intersects_segment(a,b,c,d)!=null:return 0.0
	return minf(minf(Geometry2D.get_closest_point_to_segment(a,c,d).distance_squared_to(a),Geometry2D.get_closest_point_to_segment(b,c,d).distance_squared_to(b)),minf(Geometry2D.get_closest_point_to_segment(c,a,b).distance_squared_to(c),Geometry2D.get_closest_point_to_segment(d,a,b).distance_squared_to(d)))

# Generated once at construction. Geometry is authoritative at boundaries;
# mask centers are shared with presentation, nearest filtering recommended.
func _rebuild_water_mask()->void:
	water_mask_size=Vector2i((world_size/water_mask_cell_size).ceil())
	water_mask_data.resize(water_mask_size.x*water_mask_size.y);water_mask_data.fill(0)
	_water_boundary.resize(water_mask_data.size());_water_boundary.fill(0)
	_coast_edges.clear();_coast_index.clear()
	var edges:Array=[]
	if water_polygons.is_empty():
		for y in water_mask_size.y:
			for x in range(maxi(0,ceili(shore_x/water_mask_cell_size-0.5)),water_mask_size.x):water_mask_data[y*water_mask_size.x+x]=255
	else:
		for polygon in water_polygons:
			for i in polygon.size():edges.append([polygon[i],polygon[(i+1)%polygon.size()]])
			# Scanline rasterization avoids a polygon test per map texel.
			for y in water_mask_size.y:
				var scan:float=(y+0.5)*water_mask_cell_size
				var crossings:Array[float]=[]
				for i in polygon.size():
					var a:Vector2=polygon[i];var b:Vector2=polygon[(i+1)%polygon.size()]
					if (a.y<=scan and b.y>scan) or (b.y<=scan and a.y>scan):crossings.append(a.x+(scan-a.y)*(b.x-a.x)/(b.y-a.y))
				crossings.sort()
				for i in range(0,crossings.size()-1,2):
					for x in range(maxi(0,ceili(crossings[i]/water_mask_cell_size-0.5)),mini(water_mask_size.x,ceili(crossings[i+1]/water_mask_cell_size-0.5))):water_mask_data[y*water_mask_size.x+x]=255
		for edge in edges:
			var a:Vector2=edge[0];var b:Vector2=edge[1]
			var steps:=maxi(1,ceili(a.distance_to(b)/(water_mask_cell_size*0.5)))
			for i in steps:
				var bounds:=Rect2(a.lerp(b,float(i)/steps),Vector2.ZERO).expand(a.lerp(b,float(i+1)/steps)).grow(0.0001)
				for x in range(maxi(0,floori(bounds.position.x/water_mask_cell_size)),mini(water_mask_size.x, floori(bounds.end.x/water_mask_cell_size)+1)):
					for y in range(maxi(0,floori(bounds.position.y/water_mask_cell_size)),mini(water_mask_size.y,floori(bounds.end.y/water_mask_cell_size)+1)):_water_boundary[y*water_mask_size.x+x]=1
			# Split at all polygon intersections, then retain union boundary only.
			# Overlapping ocean/bay polygons therefore have no artificial seam.
			var cuts:Array[float]=[0.0,1.0]
			var direction:=b-a
			if direction.length_squared()<0.00000001:continue
			for other in edges:
				var crossing=Geometry2D.segment_intersects_segment(a,b,other[0],other[1])
				if crossing!=null:cuts.append(clampf((Vector2(crossing)-a).dot(direction)/direction.length_squared(),0,1))
				for endpoint in other:
					if Geometry2D.get_closest_point_to_segment(endpoint,a,b).distance_squared_to(endpoint)<0.00000001:cuts.append(clampf((endpoint-a).dot(direction)/direction.length_squared(),0,1))
			cuts.sort()
			var normal:=direction.normalized().orthogonal()*0.0001
			for i in range(cuts.size()-1):
				if cuts[i+1]-cuts[i]<0.000001:continue
				var mid:=a.lerp(b,(cuts[i]+cuts[i+1])*0.5)
				if _water_exact(mid+normal)==_water_exact(mid-normal):continue
				var start:=a.lerp(b,cuts[i]);var finish:=a.lerp(b,cuts[i+1])
				var index:=_coast_edges.size();_coast_edges.append([start,finish])
				var bounds:=Rect2(start,finish-start).abs()
				for x in range(floori(bounds.position.x/SPATIAL_CELL),floori(bounds.end.x/SPATIAL_CELL)+1):
					for y in range(floori(bounds.position.y/SPATIAL_CELL),floori(bounds.end.y/SPATIAL_CELL)+1):
						var id:=Vector2i(x,y)
						if not _coast_index.has(id):_coast_index[id]=[]
						_coast_index[id].append(index)
	water_mask=Image.create_from_data(water_mask_size.x,water_mask_size.y,false,Image.FORMAT_R8,water_mask_data)

# Collision trees (`trees`) felled by a tracked hull driving into one or by a
# nearby HE burst. As in crush_props the array keeps its size (a felled entry
# moves off-map) so the static index is edited in place, and only the
# navigation cells round each trunk are refreshed. tree_felled lets the
# presentation topple the instanced tree (index into `trees`, fall direction).
signal tree_felled(index:int,heading:Vector2)
const FELLED_TREE:=Vector2(-9999,-9999)
const TREE_CLEARANCE:=1.2  # traversable(): land movers keep radius+1.2 from a trunk
func fell_trees(center:Vector2,radius:float,heading:Vector2=Vector2.ZERO)->Array:
	if trees.is_empty():return []
	var hit:Array[Vector2]=[]
	for tree in _static_candidates("tree",center,radius):
		if tree.distance_squared_to(center)<radius*radius:hit.append(tree)
	if hit.is_empty():return []
	var records:Array=[]
	var cleared:Array=[]
	var buckets:Dictionary=_static_index.get("tree",{})
	for tree in hit:
		var index:int=trees.find(tree)
		if index<0:continue
		trees[index]=FELLED_TREE
		var bucket:Array=buckets.get(Vector2i((tree/SPATIAL_CELL).floor()),[])
		bucket.erase(tree)
		# Away from the hull's travel, or outward from the burst.
		var fall:Vector2=heading if heading.length_squared()>0.0001 else tree-center
		fall=fall.normalized() if fall.length_squared()>0.0001 else Vector2.UP
		records.append({"index":index,"pos":tree,"heading":fall})
		cleared.append(Rect2(tree,Vector2.ZERO).grow(TREE_CLEARANCE))
		tree_felled.emit(index,fall)
	if not cleared.is_empty():_refresh_land_cells(cleared)
	return records

# Air ceiling: top height of authored tall structures (buildings by family and
# floors, registry props by asset height), so aircraft can climb over a skyline
# that no single cruise altitude clears. Each footprint is grown by the largest
# overhang (crane jib, tree crowns) plus one cell, so bilinear samples anywhere
# over a structure read at least its top; past that the ceiling falls off as a
# cone (AIR_SLOPE m per m) so flight altitude stays continuous. Built at load;
# maps with nothing above AIR_MIN_TOP pay one empty check per query.
const AIR_CELL:=4.0
const AIR_MIN_TOP:=6.0
const AIR_OVERHANG:=7.0
const AIR_SLOPE:=0.7
var _air_ceiling:=PackedFloat32Array()
var _air_size:=Vector2i.ZERO
var _air_built:=false

func air_ceiling(p:Vector2)->float:
	if not _air_built:_build_air_ceiling()
	if _air_ceiling.is_empty():return 0.0
	var g:Vector2=p/AIR_CELL-Vector2(0.5,0.5)
	var x0:=clampi(floori(g.x),0,_air_size.x-1);var y0:=clampi(floori(g.y),0,_air_size.y-1)
	var x1:=mini(x0+1,_air_size.x-1);var y1:=mini(y0+1,_air_size.y-1)
	var fx:=clampf(g.x-x0,0.0,1.0);var fy:=clampf(g.y-y0,0.0,1.0)
	var top:=lerpf(_air_ceiling[y0*_air_size.x+x0],_air_ceiling[y0*_air_size.x+x1],fx)
	var bottom:=lerpf(_air_ceiling[y1*_air_size.x+x0],_air_ceiling[y1*_air_size.x+x1],fx)
	return lerpf(top,bottom,fy)

# [footprint, top] for every authored structure at least AIR_MIN_TOP tall.
func air_obstacles()->Array:
	var result:Array=[]
	var City=preload("res://scripts/city_buildings.gd")
	for spec in architecture:
		var design:String=str(spec.get("design",""))
		var floors:int=int(spec.get("floors",1))
		var top:float=City.height_cap(design,floors) if City.handles(design) else (4.0 if design=="rock" else floors*3.2+1.5)
		if top<AIR_MIN_TOP or not spec.has("source_size"):continue
		var size:=Vector2(float(spec.source_size[0]),float(spec.source_size[1]))
		var yaw:=deg_to_rad(float(spec.get("rotation_degrees",0.0)))
		var extent:=Vector2(absf(size.x*cos(yaw))+absf(size.y*sin(yaw)),absf(size.x*sin(yaw))+absf(size.y*cos(yaw)))
		result.append([Rect2(Vector2(float(spec.position[0]),float(spec.position[1]))-extent/2,extent),top])
	if not map_props.is_empty():
		var Library=preload("res://scripts/asset_library.gd")
		# One library read: footprint()/find() deep-copy every entry per call.
		var specs:Dictionary={}
		for entry in Library.entries():specs[entry.id]=entry
		for prop in map_props:
			var spec:Dictionary=specs.get(str(prop.get("id",prop.get("asset_id",""))),{})
			if spec.is_empty():continue
			var top:float=float(spec.get("height",0.0))+float(prop.get("elevation",0.0))
			if top<AIR_MIN_TOP:continue
			var point=prop.get("position",prop.get("pos",[0,0]))
			var pos:Vector2=point if point is Vector2 else Vector2(point[0],point[1])
			var yaw:float=float(prop.get("yaw",deg_to_rad(float(prop.get("rotation_degrees",0.0)))))
			var f:Array=spec.footprint
			var bounds:=Rect2(pos+Vector2(float(f[0]),float(f[1])).rotated(-yaw),Vector2.ZERO)
			for corner in [Vector2(f[0],f[1]),Vector2(float(f[0])+float(f[2]),f[1]),Vector2(float(f[0])+float(f[2]),float(f[1])+float(f[3])),Vector2(f[0],float(f[1])+float(f[3]))]:
				bounds=bounds.expand(pos+corner.rotated(-yaw))
			result.append([bounds,top])
	return result

func _build_air_ceiling()->void:
	_air_built=true
	var obstacles:=air_obstacles()
	if obstacles.is_empty():return
	_air_size=Vector2i((world_size/AIR_CELL).ceil())
	_air_ceiling.resize(_air_size.x*_air_size.y)
	_air_ceiling.fill(0.0)
	for obstacle in obstacles:
		var area:Rect2=obstacle[0].grow(AIR_OVERHANG+AIR_CELL)
		var low:=Vector2i((area.position/AIR_CELL-Vector2(0.5,0.5)).ceil()).max(Vector2i.ZERO)
		var high:=Vector2i((area.end/AIR_CELL-Vector2(0.5,0.5)).floor()).min(_air_size-Vector2i.ONE)
		for y in range(low.y,high.y+1):
			for x in range(low.x,high.x+1):
				var i:=y*_air_size.x+x
				_air_ceiling[i]=maxf(_air_ceiling[i],obstacle[1])
	# Two-pass chamfer cone: each cell keeps max(own, neighbour - slope*distance).
	var step:=AIR_SLOPE*AIR_CELL;var diagonal:=step*sqrt(2.0)
	var w:=_air_size.x
	for y in _air_size.y:
		for x in w:
			var i:=y*w+x;var v:=_air_ceiling[i]
			if x>0:v=maxf(v,_air_ceiling[i-1]-step)
			if y>0:
				v=maxf(v,_air_ceiling[i-w]-step)
				if x>0:v=maxf(v,_air_ceiling[i-w-1]-diagonal)
				if x<w-1:v=maxf(v,_air_ceiling[i-w+1]-diagonal)
			_air_ceiling[i]=v
	for y in range(_air_size.y-1,-1,-1):
		for x in range(w-1,-1,-1):
			var i:=y*w+x;var v:=_air_ceiling[i]
			if x<w-1:v=maxf(v,_air_ceiling[i+1]-step)
			if y<_air_size.y-1:
				v=maxf(v,_air_ceiling[i+w]-step)
				if x<w-1:v=maxf(v,_air_ceiling[i+w+1]-diagonal)
				if x>0:v=maxf(v,_air_ceiling[i+w-1]-diagonal)
			_air_ceiling[i]=v
