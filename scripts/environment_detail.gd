class_name EnvironmentDetail
extends RefCounted

# Ground markings are flat; substantial details stay in existing building blockers.
static func build(art,parent:Node3D,terrain,architecture:Array=[])->void:
	if terrain.style!="showcase":return
	if terrain.compiled_map:
		_build_harbor(art,parent,terrain,architecture)
		return
	for index in terrain.blocks.size():
		var r:Rect2=terrain.blocks[index]
		var c:=r.get_center()
		var industrial:bool=(architecture[index].get("design","") in ["warehouse","gutted_shed"]) if index<architecture.size() else index in [3,4]
		# Paved service apron / village pavement connects buildings to the ground.
		for side in [-1.0,1.0]:
			for x in range(ceili(r.position.x),floori(r.end.x)):
				for row in 2:
					var z:float=c.y+side*(r.size.y*0.5+0.28+row*0.5)
					art.box(parent,Vector3(x+0.45,0.008,z),Vector3(0.88,0.012,0.47),Color("78776b") if industrial else Color("8c8675"))
			# Drain grates, flush with the path, not fictitious cover.
			for bar in 7:
				art.box(parent,Vector3(c.x-0.35+bar*0.11,0.019,c.y+side*(r.size.y/2+0.55)),Vector3(0.045,0.012,0.32),Color("383f3c"))
		if index<architecture.size():_frontage_link(art,parent,terrain,r,architecture[index])
	# Transport graph supplies width, route and purpose to both art and gameplay.
	for road in terrain.roads.segments:
		var a:Vector2=road.a;var b:Vector2=road.b
		var direction:Vector2=(b-a).normalized()
		var length:float=a.distance_to(b)
		var patch=art.box(parent,Vector3((a.x+b.x)/2,0.012,(a.y+b.y)/2),Vector3(road.width,0.015,length),Color("575b55").srgb_to_linear())
		patch.rotation.y=atan2(direction.x,direction.y)
		patch.material_override=art.road_material()
		for i in range(2,int(length)-1,4):
			var p:Vector2=a+direction*i
			var stripe=art.box(parent,Vector3(p.x,0.024,p.y),Vector3(0.07,0.008,0.7),Color("a6a18a"))
			stripe.rotation.y=patch.rotation.y
		_road_edges(art,parent,terrain,road)
	# Round junction caps match the capsule-shaped shared surface test.
	for name in terrain.roads.nodes:
		var p:Vector2=terrain.roads.nodes[name]
		var width:=0.0
		for road in terrain.roads.segments:
			if road.from==name or road.to==name:width=maxf(width,road.width)
		var mesh:=CylinderMesh.new();mesh.top_radius=width/2;mesh.bottom_radius=width/2;mesh.height=0.012;mesh.radial_segments=16
		var cap:=MeshInstance3D.new();cap.mesh=mesh;cap.position=Vector3(p.x,0.014,p.y)
		cap.material_override=art.road_material();parent.add_child(cap)

# Flush surfaces: these explain road use without inventing collidable obstacles.
static func _road_edges(art,parent,terrain,road:Dictionary)->void:
	var a:Vector2=road.a;var b:Vector2=road.b
	var direction:Vector2=(b-a).normalized()
	var normal:=Vector2(-direction.y,direction.x)
	var town:bool="town" in road.purpose or "high street" in road.purpose
	var industrial:bool="access" in road.purpose or "service" in road.purpose
	for distance in range(2,int(a.distance_to(b))-1):
		for side in [-1.0,1.0]:
			var edge:Vector2=a+direction*distance+normal*side*(road.width/2+0.4)
			if terrain.roads.contains(edge) or terrain.blocked(edge) or terrain.is_water(edge):continue
			var width:=0.78 if town else 0.48
			var color:=Color("706c60") if town else Color("535246")
			var slab=art.box(parent,Vector3(edge.x,0.007,edge.y),Vector3(width,0.009,0.94),color)
			slab.rotation.y=atan2(direction.x,direction.y)
			if town or industrial:
				var gutter:Vector2=edge-normal*side*0.3
				var channel=art.box(parent,Vector3(gutter.x,0.017,gutter.y),Vector3(0.10,0.006,0.94),Color("42483f"))
				channel.rotation.y=slab.rotation.y
				if distance%8==0:
					for bar in 5:
						var q:Vector2=gutter+direction*(bar-2)*0.10
						var grate=art.box(parent,Vector3(q.x,0.021,q.y),Vector3(0.25,0.006,0.05),Color("252f2c"))
						grate.rotation.y=slab.rotation.y
	# A single approach crossing on the village street; stop short of the node.
	if "high street" in road.purpose:
		var center:Vector2=b-direction*4.0
		for stripe in 7:
			var q:Vector2=center+normal*(stripe-3)*0.43
			var mark=art.box(parent,Vector3(q.x,0.026,q.y),Vector3(0.24,0.006,1.5),Color("9b9980"))
			mark.rotation.y=atan2(direction.x,direction.y)

static func _frontage_link(art,parent,terrain,r:Rect2,spec:Dictionary)->void:
	var normals:={"north":Vector2.UP,"south":Vector2.DOWN,"west":Vector2.LEFT,"east":Vector2.RIGHT}
	var normal:Vector2=normals.get(spec.get("facing","north"),Vector2.UP)
	var front:Vector2=r.get_center()+normal*r.size/2
	var best:=Vector2(INF,INF);var score:=INF
	for road in terrain.roads.segments:
		var center:Vector2=Geometry2D.get_closest_point_to_segment(front,road.a,road.b)
		var offset:=center-front
		if offset.dot(normal)<0.5 or offset.length()>14:continue
		var end:Vector2=center-offset.normalized()*(road.width/2+0.20)
		if (end-front).dot(normal)<0.4:continue
		if not terrain.segment_clear(front+offset.normalized()*0.75,end,"land",0.65):continue
		var candidate:float=offset.length()+absf(offset.cross(normal))*2.0
		if candidate<score:best=end;score=candidate
	if not best.is_finite():return
	var distance:float=front.distance_to(best)
	var count:=maxi(1,ceili(distance/0.9))
	for i in count:
		var p:Vector2=front.lerp(best,(i+0.5)/count)
		var tile=art.box(parent,Vector3(p.x,0.009,p.y),Vector3(1.2,0.009,distance/count-0.035),Color("807b6b"))
		tile.rotation.y=atan2(best.x-front.x,best.y-front.y)

# One low-resolution semantic mask, built once; RGB = town soil / freight gravel / field.
# Only appearance changes. These surfaces intentionally read as unsealed ground.
static func land_use_at(terrain,config:Dictionary,p:Vector2)->Color:
	if terrain.compiled_map:return _harbor_sample(terrain,_harbor_context(terrain,config),p)
	if terrain.scenario_id!=5 or terrain.is_water(p):return Color(0,0,0,1)
	var town:=0.0;var freight:=0.0;var farm:=0.0
	for district in config.get("districts",[]):
		var b:Array=district.bounds
		var r:=Rect2(b[0],b[1],b[2],b[3])
		var edge:=minf(minf(p.x-r.position.x,r.end.x-p.x),minf(p.y-r.position.y,r.end.y-p.y))
		var weight:=smoothstep(0.0,3.0,edge)
		match district.name:
			"Old town":town=maxf(town,weight*0.52)
			"Freight quarter":freight=maxf(freight,weight*0.68)
			"Farm approach":farm=maxf(farm,weight)
			"Southwest depot":town=maxf(town,weight*0.35)
	var road_distance:=INF
	for road in terrain.roads.segments:
		var q:Vector2=Geometry2D.get_closest_point_to_segment(p,road.a,road.b)
		road_distance=minf(road_distance,p.distance_to(q)-road.width/2)
	# Broad cultivated land stops before shoulders; no furrows through the street.
	farm*=smoothstep(1.0,3.5,road_distance)
	var architecture:Array=config.get("architecture",[])
	for i in mini(terrain.blocks.size(),architecture.size()):
		var r:Rect2=terrain.blocks[i];var spec:Dictionary=architecture[i]
		var normal:Vector2={"north":Vector2.UP,"south":Vector2.DOWN,"east":Vector2.RIGHT,"west":Vector2.LEFT}.get(spec.get("facing","north"),Vector2.UP)
		var front:Vector2=r.get_center()+normal*r.size/2
		var delta:=p-front
		var along:=absf(delta.cross(normal))
		var half_width:float=(r.size.x if normal.y!=0 else r.size.y)/2
		var across:=1.0-smoothstep(half_width,half_width+2.5,along)
		var ahead:=delta.dot(normal)
		var apron:=across*smoothstep(-1.0,0.0,ahead)*(1.0-smoothstep(3.0,8.0,ahead))
		if spec.design in ["warehouse","gutted_shed"]:freight=maxf(freight,apron*0.9)
		else:town=maxf(town,apron*0.78)
		if spec.design=="farmstead":
			var outside:float=p.distance_to(p.clamp(r.position,r.end))
			farm=maxf(farm,(1.0-smoothstep(2.0,8.0,outside))*(1.0-apron)*smoothstep(1.0,3.5,road_distance))
	# No semantic ground overwrite on the shared road itself.
	var offroad:=smoothstep(0.0,0.8,road_distance)
	return Color(town*offroad,freight*offroad,farm*offroad,1)

static func land_use_texture(terrain,config:Dictionary)->ImageTexture:
	if terrain.compiled_map:
		var resolution:=Vector2i((terrain.world_size/4.0).ceil())
		var image:=Image.create(resolution.x,resolution.y,false,Image.FORMAT_RGB8)
		var context:=_harbor_context(terrain,config)
		for z in resolution.y:
			for x in resolution.x:
				var p:Vector2=(Vector2(x,z)+Vector2.ONE*0.5)*terrain.world_size/Vector2(resolution)
				image.set_pixel(x,z,_harbor_sample(terrain,context,p))
		return ImageTexture.create_from_image(image)
	var size:Vector2i=Vector2i(terrain.world_size)
	var mask:=Image.create(size.x,size.y,false,Image.FORMAT_RGB8)
	for z in size.y:
		for x in size.x:mask.set_pixel(x,z,land_use_at(terrain,config,Vector2(x+0.5,z+0.5)))
	return ImageTexture.create_from_image(mask)

# Harbor detail uses bounded road/zone batches instead of per-metre pavers.
# Raised registry scenery is placed by HarborProps with shared terrain bounds.
# Ground zones (squares, port aprons, yards) come from the compiled scenario's
# open_spaces/urban_blocks, so buildings never need to be paired with blocks.
static func _harbor_config(terrain)->Dictionary:
	# The terrain and renderer share the exact selected config. A global harbor
	# cache leaked ground zones when loading a different regional battlefield.
	return terrain.config if terrain.compiled_map else {}

static func _poly(points:Array)->PackedVector2Array:
	var out:=PackedVector2Array()
	for p in points:out.append(Vector2(p[0],p[1]))
	return out

static func _poly_bounds(poly:PackedVector2Array)->Rect2:
	var r:=Rect2(poly[0],Vector2.ZERO)
	for p in poly:r=r.expand(p)
	return r

static func _build_harbor(art,parent:Node3D,terrain,architecture:Array)->void:
	var group:=Node3D.new();group.name="HarborGroundDetail";parent.add_child(group)
	# Legacy index-paired parcels only: compiled city buildings carry their own
	# collision indices and get no parcel border (their footprints are rotated).
	for i in mini(terrain.blocks.size(),architecture.size()):
		var spec:Dictionary=architecture[i]
		if spec.has("collision"):continue
		var r:Rect2=terrain.blocks[i]
		var apron:=Node3D.new();apron.name="Apron_%d"%i;group.add_child(apron)
		apron.position=Vector3(r.get_center().x,0,r.get_center().y)
		var size:Vector2=Vector2(spec.source_size[0],spec.source_size[1]) if spec.has("source_size") else r.size
		apron.rotation_degrees.y=float(spec.get("rotation_degrees",0.0))
		for side in [-1,1]:
			art.box(apron,Vector3(0,0.008,side*(size.y/2-0.13)),Vector3(size.x,0.012,0.24),Color("858171"))
			art.box(apron,Vector3(side*(size.x/2-0.13),0.008,0),Vector3(0.24,0.012,size.y),Color("858171"))
		art.bake_model(apron)
	for road in terrain.roads.segments:
		var a:Vector2=road.a;var b:Vector2=road.b
		var length:float=a.distance_to(b)
		var count:=maxi(1,ceili(length/64.0))
		var direction:Vector2=(b-a).normalized()
		for section in count:
			var start:Vector2=a.lerp(b,float(section)/count)
			var finish:Vector2=a.lerp(b,float(section+1)/count)
			var middle:Vector2=(start+finish)/2.0
			var span:float=start.distance_to(finish)
			var piece:=Node3D.new();piece.name="RoadSection";group.add_child(piece)
			piece.position=Vector3(middle.x,0,middle.y);piece.rotation.y=atan2(direction.x,direction.y)
			# Kerbed limestone sidewalks in town, gravel shoulders on lanes and tracks.
			var urban:bool="town" in road.purpose or "street" in road.purpose or "urban" in road.purpose or "microdistrict" in road.purpose
			var lane:bool="lane" in road.purpose or "track" in road.purpose
			# Navigation keeps the full street width; only the drawn carriageway is
			# scaled to the 0.6x building scale. The rest is pavement or verge.
			var carriage:float=_carriage_width(road)
			var shoulder:Color=Color("8f8a78") if urban else (Color("6d6955") if lane else Color("66695b"))
			art.box(piece,Vector3(0,0.007,0),Vector3(road.width+(0.6 if urban else 0.2),0.01,span),shoulder)
			if urban:
				for side in [-1,1]:art.box(piece,Vector3(side*(carriage/2+0.09),0.02,0),Vector3(0.18,0.03,span),Color("a39f8e"))
			var surface=art.box(piece,Vector3(0,0.016,0),Vector3(carriage,0.012,span),Color("575b55") if not lane else Color("6a6556"))
			surface.material_override=art.road_material()
			if road.width>=16:
				# Centre line on arterials only, stopping short of each junction.
				var half:float=float(road.width)/2.0
				var first:float=2.0+(half if section==0 else 0.0)
				var last:float=span-1.0-(half if section==count-1 else 0.0)
				var stripe:float=first
				while stripe<last:
					art.box(piece,Vector3(0,0.025,stripe-span/2),Vector3(0.10,0.006,2.0),Color("a6a18a"))
					stripe+=8.0
			art.bake_model(piece)
	# Junction caps continue the carriageway (and pavement) through bends and crossings.
	for key in terrain.roads.nodes:
		var width:=0.0;var carriage:=0.0
		for road in terrain.roads.segments:
			if road.from==key or road.to==key:
				width=maxf(width,road.width);carriage=maxf(carriage,_carriage_width(road))
		if width<=0:continue
		var p:Vector2=terrain.roads.nodes[key]
		art.cylinder(group,Vector3(p.x,0.006,p.y),width/2,0.01,Color("8f8a78"))
		var cap=art.cylinder(group,Vector3(p.x,0.016,p.y),carriage/2,0.012,Color("575b55"))
		cap.material_override=art.road_material()
	_build_harbor_zones(art,group,terrain,_harbor_config(terrain))
	_merge_flat_detail(group)

# Ground detail is flush paint, kerbs and slabs no more than 3 cm high: hundreds
# of separate pieces cost one draw each, plus a shadow-pass draw for a shadow
# under 3 cm long (below a shadow texel). None casts shadows (all still receive
# them). Surfaces whose shading does not depend on object space (world-space
# asphalt, flat standard paint) merge per material into 128 m tiles, which keeps
# frustum culling local; miniature-paint pieces sample their atlas in object
# space, so they keep their own node to look exactly the same.
const DETAIL_TILE:=128.0
static func _merge_flat_detail(group:Node3D)->void:
	var batches:Dictionary={}
	var slots:Dictionary={}
	for child in group.get_children():_collect_flat(child,Transform3D.IDENTITY,batches,slots)
	for child in group.get_children():
		if child.get_meta("merged",false):child.free()
	var keys:Array=batches.keys()
	keys.sort()
	for key in keys:
		var mesh:=MeshInstance3D.new()
		mesh.name="DetailTile_%d_%d_%d"%[key.x,key.y,key.z]
		mesh.mesh=batches[key].surface.commit()
		mesh.material_override=batches[key].material
		mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		group.add_child(mesh)

static func _mergeable(material:Material)->bool:
	if material is StandardMaterial3D:return material.albedo_texture==null
	return material is ShaderMaterial and material.shader!=null and material.shader.resource_path.ends_with("road_surface.gdshader")

# Collects mergeable meshes; returns whether the whole subtree was merged (and
# may be freed). Kept meshes stop casting their sub-texel shadows.
static func _collect_flat(node:Node,ancestor:Transform3D,batches:Dictionary,slots:Dictionary)->bool:
	if not node is Node3D:return false
	var transform:Transform3D=ancestor*node.transform
	var merged:=true
	if node is MeshInstance3D and node.mesh!=null:
		var all:bool=node.visible
		for index in node.mesh.get_surface_count():all=all and _mergeable(node.get_active_material(index))
		if not all:
			node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			merged=false
	if node is MeshInstance3D and node.mesh!=null and merged:
		var tile:=Vector2i(floori(transform.origin.x/DETAIL_TILE),floori(transform.origin.z/DETAIL_TILE))
		for index in node.mesh.get_surface_count():
			var material:Material=node.get_active_material(index)
			# Stable small index per material instance (keys sort deterministically).
			var id:int=material.get_instance_id() if material!=null else 0
			if not slots.has(id):slots[id]=slots.size()
			var slot:int=slots[id]
			var key:=Vector3i(tile.x,tile.y,slot)
			if not batches.has(key):
				var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
				batches[key]={"surface":surface,"material":material}
			var indexed:=SurfaceTool.new();indexed.create_from(node.mesh,index);indexed.index()
			batches[key].surface.append_from(indexed.commit(),0,transform)
		node.set_meta("merged_mesh",true)
	var removable:Array=[]
	for child in node.get_children():
		if _collect_flat(child,transform,batches,slots):removable.append(child)
		else:merged=false
	if not merged:
		for child in removable:child.free()
		# A merged mesh kept only as a parent: its geometry now lives in a tile.
		if node is MeshInstance3D and node.get_meta("merged_mesh",false):node.mesh=null
	node.set_meta("merged",merged)
	return merged


# Drawn asphalt width: arterials keep most of their width; town streets and
# lanes read narrower beside 0.6x-scale buildings (review: roads dominated views).
static func _carriage_width(road)->float:
	if road.width>=16:return road.width*0.75
	if "lane" in road.purpose or "track" in road.purpose:return maxf(3.2,road.width*0.55)
	return maxf(4.0,road.width*0.6)

# Flush zone detail: sett joints on squares, slab joints on port aprons, bay
# lines in microdistrict yards. One baked node per zone keeps draw calls low.
static func _build_harbor_zones(art,group:Node3D,terrain,config:Dictionary)->void:
	var zones:Array=[]
	for space in config.get("open_spaces",[]):
		if space.kind in ["square","stockyard","tank_farm","parade"]:zones.append({"kind":space.kind,"poly":_poly(space.polygon)})
	for block in config.get("urban_blocks",[]):
		if block.get("morphology","") in ["port","superblock"]:zones.append({"kind":block.morphology,"poly":_poly(block.polygon)})
	for zone in zones:
		var poly:PackedVector2Array=zone.poly
		if poly.size()<3:continue
		var r:=_poly_bounds(poly)
		var node:=Node3D.new();node.name="HarborZone_"+str(zone.kind);group.add_child(node)
		var spacing:float={"square":2.5,"port":8.0,"stockyard":8.0,"tank_farm":8.0,"parade":5.0,"superblock":0.0}[zone.kind]
		var color:Color={"square":Color("9d9682"),"port":Color("6f716b"),"stockyard":Color("6f716b"),"tank_farm":Color("6a6c66"),"parade":Color("807c70"),"superblock":Color("5f625d")}[zone.kind]
		if spacing>0.0:
			# Joint lines clipped to the zone polygon by sampling segment midpoints.
			var x:=r.position.x+spacing
			while x<r.end.x:
				var z:=r.position.y
				while z<r.end.y:
					var mid:=Vector2(x,z+spacing/2)
					if Geometry2D.is_point_in_polygon(mid,poly) and not terrain.roads.contains(mid) and not terrain.blocked(mid):
						art.box(node,Vector3(mid.x,0.011,mid.y),Vector3(0.08,0.006,spacing),color)
					z+=spacing
				x+=spacing
			var z2:=r.position.y+spacing
			while z2<r.end.y:
				var x2:=r.position.x
				while x2<r.end.x:
					var mid2:=Vector2(x2+spacing/2,z2)
					if Geometry2D.is_point_in_polygon(mid2,poly) and not terrain.roads.contains(mid2) and not terrain.blocked(mid2):
						art.box(node,Vector3(mid2.x,0.011,mid2.y),Vector3(spacing,0.006,0.08),color)
					x2+=spacing
				z2+=spacing
		else:
			# Microdistrict yards: painted parking bay lines along open asphalt.
			var c:=r.get_center()
			for k in range(-3,4):
				var p:=c+Vector2(k*3.0,0)
				if Geometry2D.is_point_in_polygon(p,poly) and not terrain.blocked(p):art.box(node,Vector3(p.x,0.012,p.y),Vector3(0.1,0.006,4.6),Color("b8b4a2"))
		art.bake_model(node)

# Spatially bucket authoring inputs once when making the 4m semantic texture.
static func _bucket(context:Dictionary,bounds:Rect2,kind:String,value)->void:
	var low:=Vector2i((bounds.position/64.0).floor())
	var high:=Vector2i((bounds.end/64.0).floor())
	for y in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):
			var key:=Vector2i(x,y)
			if not context.has(key):context[key]={"districts":[],"roads":[],"aprons":[],"zones":[]}
			context[key][kind].append(value)

# Land-use mask channels (read by the harbor ground shader in visuals.gd):
# R = paved stone (limestone setts, squares, courtyards), G = sealed industrial
# ground (port concrete aprons, microdistrict asphalt), B = cultivated soil
# (gardens, vineyards, fields). Unpainted land stays grass/scrub.
const HARBOR_SURFACE:={
	"perimeter":Color(0.55,0.0,0.0),"superblock":Color(0.10,0.42,0.0),"port":Color(0.0,0.85,0.0),
	"private":Color(0.08,0.0,0.45),"north":Color(0.08,0.0,0.40),"dacha":Color(0.0,0.0,0.55),
	"village":Color(0.0,0.0,0.35),"garages":Color(0.05,0.45,0.10),"compound":Color(0.05,0.60,0.0),
	"square":Color(0.95,0.0,0.0),"cathedral_close":Color(0.35,0.0,0.0),"hill_park":Color(0.0,0.0,0.0),
	"seafront":Color(0.25,0.0,0.0),"stockyard":Color(0.0,1.0,0.0),"tank_farm":Color(0.0,0.95,0.0),
	"parade":Color(0.0,0.90,0.0),"railway":Color(0.08,0.70,0.0),"vineyard":Color(0.0,0.0,1.0),"field":Color(0.0,0.0,0.9),
	"ravine":Color(0.0,0.0,0.6),"cemetery":Color(0.10,0.0,0.15),"courtyard":Color(0.65,0.0,0.0)}

static func _harbor_context(terrain,config:Dictionary)->Dictionary:
	var context:Dictionary={}
	var compiled:bool=config.has("city_districts")
	if compiled:
		# Later zones override earlier ones: districts < blocks < open spaces < courtyards.
		var order:=0
		for district in config.city_districts:
			var poly:=_poly(district.polygon)
			_bucket(context,_poly_bounds(poly),"zones",{"poly":poly,"surface":district.morphology,"order":order})
		order=1
		for block in config.get("urban_blocks",[]):
			var poly:=_poly(block.polygon)
			if poly.size()>=3:_bucket(context,_poly_bounds(poly),"zones",{"poly":poly,"surface":block.get("morphology",""),"order":order})
		order=2
		for space in config.get("open_spaces",[]):
			var poly:=_poly(space.polygon)
			_bucket(context,_poly_bounds(poly),"zones",{"poly":poly,"surface":space.kind,"order":order})
		for bounds in config.get("courtyards",[]):
			var r:=Rect2(bounds[0],bounds[1],bounds[2],bounds[3])
			var poly:=PackedVector2Array([r.position,Vector2(r.end.x,r.position.y),r.end,Vector2(r.position.x,r.end.y)])
			_bucket(context,r,"zones",{"poly":poly,"surface":"courtyard","order":3})
	else:
		for bounds in config.get("courtyards",[]):
			var r:=Rect2(bounds[0],bounds[1],bounds[2],bounds[3])
			_bucket(context,r,"districts",{"bounds":bounds,"type":"urban"})
		for district in config.get("districts",[]):
			var b:Array=district.bounds
			_bucket(context,Rect2(b[0],b[1],b[2],b[3]),"districts",district)
	for road in terrain.roads.segments:
		var bounds:=Rect2(road.a,Vector2.ZERO).expand(road.b).grow(road.width/2+4.0)
		_bucket(context,bounds,"roads",road)
	return context

static func _harbor_sample(terrain,context:Dictionary,p:Vector2)->Color:
	if terrain.is_water(p):return Color(0,0,0,1)
	var nearby:Dictionary=context.get(Vector2i((p/64.0).floor()),{})
	var road_distance:=INF
	for road in nearby.get("roads",[]):
		road_distance=minf(road_distance,p.distance_to(Geometry2D.get_closest_point_to_segment(p,road.a,road.b))-road.width/2)
	var offroad:=smoothstep(0.0,0.8,road_distance)
	var zones:Array=nearby.get("zones",[])
	if not zones.is_empty():
		var best:Color=Color(0,0,0);var best_order:=-1
		for zone in zones:
			if zone.order<best_order or not Geometry2D.is_point_in_polygon(p,zone.poly):continue
			if HARBOR_SURFACE.has(zone.surface):best=HARBOR_SURFACE[zone.surface];best_order=zone.order
		# Paved sidewalks fringe town streets; soil never reaches the carriageway.
		var kerb:=1.0-smoothstep(0.5,3.0,road_distance)
		var red:=maxf(best.r,kerb*0.45*float(best.r>0.0 or best.g>0.0))
		var soil:=best.b*smoothstep(1.0,3.5,road_distance)
		return Color(red*offroad,best.g*offroad,soil*offroad,1)
	var town:=0.0;var freight:=0.0;var farm:=0.0
	for district in nearby.get("districts",[]):
		var b:Array=district.bounds;var r:=Rect2(b[0],b[1],b[2],b[3])
		var edge:=minf(minf(p.x-r.position.x,r.end.x-p.x),minf(p.y-r.position.y,r.end.y-p.y))
		var weight:=smoothstep(0.0,6.0,edge)
		match district.get("type",""):
			"urban":town=maxf(town,weight*0.80)
			"industry":freight=maxf(freight,weight*0.85)
			"rural":farm=maxf(farm,weight)
			"staging":town=maxf(town,weight*0.45)
	farm*=smoothstep(1.0,3.5,road_distance)*(1.0-smoothstep(0.0,0.3,maxf(town,freight)))
	return Color(town*offroad,freight*offroad,farm*offroad,1)
