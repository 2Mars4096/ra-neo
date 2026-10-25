extends Node3D

# Permanent battlefield remains for BattleEffects at near-constant cost. Craters, scorch and burn marks are
# stamped into world-space ground-damage tiles (0.4 m/texel, 64 m square, allocated on demand) with native
# Image.blend_rect, and each dirty tile is re-uploaded at most once per UPLOAD_INTERVAL. Each tile is one
# unshaded transparent quad just above roads and below the fresh effect decals and the fog overlay. Landed
# debris chunks persist in one static MultiMesh ring of CHUNK_CAPACITY instances (oldest replaced first).
# Nothing here is per-frame work proportional to past explosions: a frame uploads at most UPLOADS_PER_FRAME
# dirty tiles (100 KB each), each tile at most once per UPLOAD_INTERVAL, and both tiles and chunks are capped.
# A few tiles are built during mission setup, one of them drawn empty so the tile shader compiles at load
# rather than at the first crater.

# 0.4 m/texel: a 1 m crater spans 5 texels. Tiles are always magnified (~9 screen px per texel at gameplay zoom,
# >= 1.6 even at the widest), so they carry no mipmaps and are sampled with a cubic B-spline in
# shaders/effect_remains.gdshader: plain bilinear kinks every contour at texel lines, which made small crater rims read
# as blocky diamonds on screen. (0.32 m/texel would cost 15.36 MB of texture plus the same in CPU images at the tile
# cap and 56% larger uploads, for little visible gain once sampling is smooth.)
const TEXEL:=0.4
const TILE_TEXELS:=160
const TILE_SIZE:=TEXEL*TILE_TEXELS
# 96 tiles of 64 m (9.4 MB) cover a 640x640 m fight; past that the least recently stamped tile is recycled.
const MAX_TILES:=96
const UPLOAD_INTERVAL:=0.25
const UPLOADS_PER_FRAME:=2
const PREALLOCATED:=8
const HEIGHT:=0.036 # above road surfaces (<= 0.028), below fresh decals (0.045) and the fog overlay (0.055)
const CHUNK_CAPACITY:=512
const CHUNK_MIN_SIZE:=0.12
const TILE_BYTES:=TILE_TEXELS*TILE_TEXELS*4
const SHADER:=preload("res://shaders/effect_remains.gdshader")

# Mark styles
const CRATER:=0 # HE: scorched pit, lighter brown ejecta rim ring, streaky soil spray
const SCORCH:=1 # warhead burn: sunburst of soot streaks
const BURN:=2   # vehicle kill / depot: heavy oily black patch with a soot halo
const STYLES:=3
const VARIANTS:=4 # seeded outlines per style and size; each stamp also takes one of 8 mirror/rotations
const PIT_CENTRE:=Color(0.035,0.03,0.026)
const PIT_EDGE:=Color(0.11,0.09,0.068)
const RIM:=Color(0.40,0.32,0.22)
const SPRAY:=Color(0.22,0.17,0.12)
const SOOT_CENTRE:=Color(0.035,0.032,0.028)
const SOOT_EDGE:=Color(0.10,0.085,0.065)
const OIL_CENTRE:=Color(0.025,0.022,0.02)
const OIL_EDGE:=Color(0.08,0.07,0.06)
const ANGLES:=128 # samples of a brush's angular outline and streak profiles
const MIN_R:=2 # brush radius limits in texels (0.8-14 m)
const MAX_R:=35
# Brush radii (texels) built at mission setup per style: every crater (0.45-1.75 m; mortar 1.4 m) and scorch
# (1.3-3.6 m; mortar spray 2.2 m) in play, and the tank-kill burn (5 m). Other sizes (harvester and depot
# burns) are built on first use (< 1 ms).
const PREBUILT:=[[2,5],[2,9],[13,13]]

# Brushes are generated once per process and shared by every instance (tests create many).
static var brushes:={}
static var brushes_built:=0
var tiles:={} # Vector2i -> {"image","texture","node","used","dirty"}
var dirty:Array[Vector2i]=[]
var spare:Array[Dictionary]=[]
var serial:=0
var clock:=0.0
var stamps:=0
var stamp_usec_total:=0
var allocated:=0
var uploads:=0
var upload_usec_total:=0
var upload_usec_max:=0
var evicted:=0
var chunks:=MultiMesh.new()
var chunk_instance:=MultiMeshInstance3D.new()
var chunk_next:=0
var chunk_count:=0
var chunks_added:=0
# CPU copy of chunk positions (the renderer owns the instance buffer; reviews and tests read this).
var chunk_pos:=PackedVector3Array()

func _init() -> void:
	chunks.transform_format=MultiMesh.TRANSFORM_3D
	chunks.use_colors=true
	var box:=BoxMesh.new()
	box.size=Vector3.ONE
	chunks.mesh=box
	chunks.instance_count=CHUNK_CAPACITY
	chunks.visible_instance_count=0
	chunk_pos.resize(CHUNK_CAPACITY)
	var material:=StandardMaterial3D.new()
	material.vertex_color_use_as_albedo=true
	material.roughness=1.0
	chunk_instance.multimesh=chunks
	chunk_instance.material_override=material
	chunk_instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk_instance.visible=false
	add_child(chunk_instance)

# Tiles outside the map are never allocated once the map size is known.
var tile_limit:=Vector2i(-1,-1)
static var plane:PlaneMesh
var terrain:BattleTerrain=null
var relief_tiles:Dictionary={}

func set_terrain(value:BattleTerrain) -> void:
	terrain=value if value.has_elevation() else null
	relief_tiles.clear()

# Build once during battlefield setup, never in the first explosion frame.
# Flat maps retain one shared quad and pay no extra geometry cost.
func _prepare_relief() -> void:
	if terrain==null:return
	var step:=clampf(float(terrain.config.get("elevation_mesh_step",2.0)),1.0,4.0)
	var cell:Vector2=terrain.world_size/Vector2(Vector2i((terrain.world_size/step).ceil()))
	for y in tile_limit.y:
		for x in tile_limit.x:
			var key:=Vector2i(x,y)
			var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			var origin:=Vector2(key)*TILE_SIZE
			# Share the exact land grid even when an authored mesh step does not
			# divide the 64 m decal tile. The shader clips the small UV overhang.
			var low:=Vector2i((origin/cell).floor())
			var high:=Vector2i(((origin+Vector2.ONE*TILE_SIZE)/cell).ceil())
			for j in range(low.y,high.y):
				for i in range(low.x,high.x):
					var p:=Vector2(i,j)*cell-origin
					for offset in [Vector2.ZERO,cell,Vector2(0,cell.y),Vector2.ZERO,Vector2(cell.x,0),cell]:
						var point:Vector2=p+offset
						surface.set_normal(Vector3.UP);surface.set_uv(point/TILE_SIZE)
						surface.add_vertex(Vector3(point.x-TILE_SIZE/2,terrain.height_at(origin+point),point.y-TILE_SIZE/2))
			surface.index();relief_tiles[key]=surface.commit()


func set_bounds(box:AABB, world_size:Vector2) -> void:
	chunk_instance.custom_aabb=box
	tile_limit=Vector2i(ceili(world_size.x/TILE_SIZE),ceili(world_size.y/TILE_SIZE))
	_prepare_relief()
	# Generate the common brushes during mission setup (once per process) rather than at the first explosion of
	# each kind mid-fight.
	for style in STYLES:
		for variant in VARIANTS:
			for r in range(PREBUILT[style][0],PREBUILT[style][1]+1):_brush(style,r,variant)
	while allocated<mini(PREALLOCATED,tile_limit.x*tile_limit.y):spare.append(_new_tile())
	if not spare.is_empty() and tiles.is_empty():
		spare.back().node.position=Vector3(0.5*TILE_SIZE,HEIGHT,0.5*TILE_SIZE)
		spare.back().node.visible=true

# ---------------------------------------------------------------- ground damage
# Stamps a permanent mark of the given radius (metres). Cost: one cached brush plus one native blend per
# covered tile (1-4); the texture upload happens later, throttled.
func stamp(pos:Vector3, radius:float, style:int) -> void:
	var started:=Time.get_ticks_usec()
	var r:=clampi(roundi(radius/TEXEL),MIN_R,MAX_R)
	serial+=1
	var centre:=Vector2i(floori(pos.x/TEXEL),floori(pos.z/TEXEL))
	var brush:=_brush(style,r,int(_hash(centre.x,centre.y,style)*VARIANTS*8))
	var size:=brush.get_width()
	var origin:=centre-Vector2i(size/2,size/2)
	var first:=Vector2i(floori(float(origin.x)/TILE_TEXELS),floori(float(origin.y)/TILE_TEXELS))
	var last:=Vector2i(floori(float(origin.x+size-1)/TILE_TEXELS),floori(float(origin.y+size-1)/TILE_TEXELS))
	if tile_limit.x>0:
		first=first.max(Vector2i.ZERO)
		last=last.min(tile_limit-Vector2i.ONE)
	for tx in range(first.x,last.x+1):
		for ty in range(first.y,last.y+1):
			var key:=Vector2i(tx,ty)
			var tile:=_tile(key)
			tile.image.blend_rect(brush,Rect2i(0,0,size,size),origin-key*TILE_TEXELS)
			tile.used=serial
			if not tile.dirty:
				tile.dirty=true
				dirty.append(key)
	stamps+=1
	stamp_usec_total+=Time.get_ticks_usec()-started

func _tile(key:Vector2i) -> Dictionary:
	if tiles.has(key):return tiles[key]
	var tile:Dictionary
	if tiles.size()>=MAX_TILES:
		# Recycle the least recently stamped tile in place: no allocation once the cap is reached.
		var oldest:=Vector2i.ZERO
		var used:=INF
		for k in tiles:
			if tiles[k].used<used:
				used=tiles[k].used
				oldest=k
		tile=tiles[oldest]
		tiles.erase(oldest)
		dirty.erase(oldest)
		tile.image.fill(Color(0,0,0,0))
		evicted+=1
	elif not spare.is_empty():
		tile=spare.pop_back()
	else:
		tile=_new_tile()
	tile.used=serial
	tile.dirty=false
	tile.uploaded=-INF
	tile.node.mesh=relief_tiles.get(key,plane)
	tile.node.position=Vector3((key.x+0.5)*TILE_SIZE,HEIGHT,(key.y+0.5)*TILE_SIZE)
	tile.node.visible=true
	tiles[key]=tile
	return tile

func _new_tile() -> Dictionary:
	if plane==null:
		plane=PlaneMesh.new()
		plane.size=Vector2(TILE_SIZE,TILE_SIZE)
	var image:=Image.create(TILE_TEXELS,TILE_TEXELS,false,Image.FORMAT_RGBA8)
	# Unshaded alpha-blended quad sampled with a smooth cubic B-spline (4 bilinear taps, clamped edges so a mark at
	# one tile edge does not bleed onto the opposite edge): see shaders/effect_remains.gdshader.
	var material:=ShaderMaterial.new()
	material.shader=SHADER
	material.render_priority=-2
	var texture:=ImageTexture.create_from_image(image)
	material.set_shader_parameter("remains",texture)
	var node:=MeshInstance3D.new()
	node.mesh=plane
	node.material_override=material
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visible=false
	add_child(node)
	allocated+=1
	return {"image":image,"texture":texture,"node":node,"used":0,"dirty":false,"uploaded":-INF}

# Called every rendered frame by BattleEffects. Uploads up to UPLOADS_PER_FRAME dirty tiles, oldest first,
# skipping any tile uploaded less than UPLOAD_INTERVAL ago (it stays queued and its next upload covers every
# stamp since). A barrage across many tiles therefore spreads its uploads over frames instead of spiking one.
func step(dt:float) -> void:
	clock+=dt
	if dirty.is_empty():return
	var budget:=UPLOADS_PER_FRAME
	var i:=0
	while i<dirty.size() and budget>0:
		var tile:Dictionary=tiles[dirty[i]]
		if clock-tile.uploaded<UPLOAD_INTERVAL:
			i+=1
			continue
		var started:=Time.get_ticks_usec()
		tile.texture.update(tile.image)
		var spent:=Time.get_ticks_usec()-started
		upload_usec_total+=spent
		upload_usec_max=maxi(upload_usec_max,spent)
		uploads+=1
		tile.uploaded=clock
		tile.dirty=false
		dirty.remove_at(i)
		budget-=1

# Alpha of the stamped ground at a world point (tests and reviews).
func darkness_at(pos:Vector3) -> float:
	return color_at(pos).a

# Stamped colour (straight alpha) of the texel under a world point.
func color_at(pos:Vector3) -> Color:
	var t:=Vector2i(floori(pos.x/TEXEL),floori(pos.z/TEXEL))
	var key:=Vector2i(floori(float(t.x)/TILE_TEXELS),floori(float(t.y)/TILE_TEXELS))
	if not tiles.has(key):return Color(0,0,0,0)
	return tiles[key].image.get_pixelv(t-key*TILE_TEXELS)

# Brush for one stamp: generated once per (style, variant, radius in texels) directly at its final size, so even a
# 1 m crater is a round, antialiased disc rather than a downscaled square. Each stamp then picks one of the
# VARIANTS outlines and one of 8 mirror/rotations from a hash of its texel position (deterministic, and the
# same impact point always leaves the same mark); the oriented copy is a native duplicate of a <= 71 px image.
func _brush(style:int, r:int, pick:int) -> Image:
	var key:=(style*VARIANTS+pick%VARIANTS)*64+r
	if not brushes.has(key):brushes[key]=make_brush(style,pick%VARIANTS,r)
	var image:Image=brushes[key]
	var turn:=(pick/VARIANTS)%8
	if turn==0:return image
	image=image.duplicate()
	if turn&1:image.flip_x()
	if turn&2:image.flip_y()
	if turn&4:image.rotate_90(CLOCKWISE)
	return image

static func _hash(x:int, y:int, s:int) -> float:
	var h:=(x*374761393+y*668265263+s*1442695041)&0x7fffffff
	h=((h^(h>>13))*1274126177)&0x7fffffff
	return float(h&0xffff)/65535.0

# Periodic angular profile (ANGLES samples around the circle) from a few seeded harmonics, scaled to [lo, 1].
# Depends only on style and variant, so it is cached across brush sizes.
static var rings:={}
static func _ring(seed_value:int, first:int, last:int, lo:float) -> PackedFloat32Array:
	var key:=seed_value*64+first
	if rings.has(key):return rings[key]
	var ring:=PackedFloat32Array()
	ring.resize(ANGLES)
	for k in range(first,last+1):
		var amplitude:=(_hash(k,1,seed_value)*2.0-1.0)/k
		var phase:=TAU*_hash(k,2,seed_value)
		for i in ANGLES:ring[i]+=amplitude*cos(k*TAU*i/ANGLES+phase)
	var low:float=Array(ring).min()
	var high:float=Array(ring).max()
	for i in ANGLES:ring[i]=lerpf(lo,1.0,(ring[i]-low)/maxf(high-low,0.0001))
	rings[key]=ring
	return ring

# Procedural brush, (2r+1) texels square for a mark of radius r texels. e is the distance from the centre in mark
# radii divided by a seeded, noise-perturbed outline radius (0.84-1), so every outline is round but irregular
# and fades to zero inside the brush (the cleared tile around it supplies the filtered edge). Edges ramp over at
# least about one texel so bilinear magnification on screen keeps them round. CRATER: near-black scorched pit,
# a lighter brown ejecta rim ring and a faint streaky soil spray; SCORCH: soot sunburst, darkest at the centre;
# BURN: heavy oily black core with a soot halo. Only craters get the rim.
static func make_brush(style:int, variant:int, r:int) -> Image:
	brushes_built+=1
	var half:=r
	var size:=2*half+1
	var data:=PackedByteArray()
	data.resize(size*size*4)
	var seed_value:=style*31+variant*7+5
	var outline:=_ring(seed_value,2,6,0.84)
	var streaks:=_ring(seed_value+1,5,13,0.0)
	# Every edge ramps over at least one texel each side: a sharper edge on a feature only 2-4 texels across
	# reconstructs as a square or a plus under bilinear magnification.
	var px:=1.0/r # one texel in mark radii
	var soft:=maxf(0.08,px)
	for y in size:
		for x in size:
			var dx:=float(x-half)
			var dy:=float(y-half)
			var d:=sqrt(dx*dx+dy*dy)*px
			if d>=1.0:continue
			var angle:=int((atan2(dy,dx)/TAU+0.5)*ANGLES)%ANGLES
			var e:=d/outline[angle]
			if e>=1.0:continue
			var streak:=streaks[angle]
			var col:Color
			match style:
				CRATER:
					# Rim ring and spray first, then the pit composited over them (a max() of the layers would leave
					# a pale moat between pit and rim that reads as a cross on small craters).
					var pit:=(1.0-smoothstep(maxf(0.2,0.42-soft),0.46+soft,e))*0.9
					# A 2-texel crater cannot resolve a ring (it reads as a square frame): only a soft dark blob.
					var rim:=(1.0-smoothstep(0.04,maxf(0.16,1.1*soft),absf(e-0.57)))*0.6*clampf(r-2,0,1)
					var spray:=(1.0-smoothstep(0.55+0.2*streak,1.0,e))*0.32
					var under:=maxf(rim,spray)
					var ground:=SPRAY.lerp(RIM,rim/maxf(under,0.0001))
					var burnt:=PIT_CENTRE.lerp(PIT_EDGE,smoothstep(0.2,0.5,e))
					var a:=pit+under*(1.0-pit)
					col=burnt.lerp(ground,under*(1.0-pit)/maxf(a,0.0001))
					col.a=a
				SCORCH:
					var reach:=0.7+0.3*streak
					var a:=maxf((1.0-smoothstep(0.3,reach,e))*0.72,(1.0-smoothstep(maxf(0.25,0.55-soft),0.55+soft,e))*0.82)
					a=maxf(a,(1.0-smoothstep(0.45,1.0,e))*0.24)
					col=SOOT_CENTRE.lerp(SOOT_EDGE,smoothstep(0.3,0.85,e))
					col.a=a*(1.0-smoothstep(0.85,1.0,e))
				_:
					var core:=1.0-smoothstep(0.42-soft,0.66+soft,e+(streak-0.5)*0.16)
					var halo:=(1.0-smoothstep(0.55,1.0,e))*0.4
					col=OIL_CENTRE.lerp(OIL_EDGE,smoothstep(0.3,0.9,e))
					col.a=maxf(core*0.9,halo)
			var i:=(y*size+x)*4
			data[i]=roundi(col.r*255.0)
			data[i+1]=roundi(col.g*255.0)
			data[i+2]=roundi(col.b*255.0)
			data[i+3]=roundi(col.a*255.0)
	return Image.create_from_data(size,size,false,Image.FORMAT_RGBA8,data)

# ---------------------------------------------------------------- debris remnants
# A landed fragment becomes a static chunk on the ground; the oldest chunk is replaced once the ring is full.
func add_chunk(pos:Vector3, size:float, col:Color, turn:float) -> void:
	var slot:=chunk_next
	chunk_next=(chunk_next+1)%CHUNK_CAPACITY
	chunk_count=mini(chunk_count+1,CHUNK_CAPACITY)
	chunks_added+=1
	var s:=size*0.6
	var tilt:=_hash(chunks_added,7,3)*0.5-0.25
	var basis:=Basis(Vector3.UP,turn).rotated(Vector3.RIGHT,tilt)*Basis.from_scale(Vector3(s,s*0.45,s*0.75))
	chunk_pos[slot]=Vector3(pos.x,0.03+s*0.18,pos.z)
	chunks.set_instance_transform(slot,Transform3D(basis,chunk_pos[slot]))
	chunks.set_instance_color(slot,col.darkened(0.25))
	chunks.visible_instance_count=chunk_count
	chunk_instance.visible=true

func clear() -> void:
	for key in tiles:
		var tile:Dictionary=tiles[key]
		tile.image.fill(Color(0,0,0,0))
		tile.texture.update(tile.image)
		tile.node.visible=false
		spare.append(tile)
	tiles.clear()
	dirty.clear()
	chunk_next=0
	chunk_count=0
	chunks.visible_instance_count=0
	chunk_instance.visible=false

func stats() -> Dictionary:
	return {"tiles":tiles.size(),"allocated":allocated,"stamps":stamps,"stamp_usec_mean":float(stamp_usec_total)/maxi(stamps,1),"uploads":uploads,"upload_usec_mean":float(upload_usec_total)/maxi(uploads,1),"upload_usec_max":upload_usec_max,
		"evicted":evicted,"texture_bytes":allocated*TILE_BYTES,"image_bytes":allocated*TILE_BYTES,"chunks":chunk_count,"chunk_capacity":CHUNK_CAPACITY}
