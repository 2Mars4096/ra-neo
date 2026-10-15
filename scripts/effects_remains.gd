extends Node3D

# Permanent battlefield remains for BattleEffects at near-constant cost. Craters, scorch and burn marks are
# stamped into world-space ground-damage tiles (0.5 m/texel, 64 m square, allocated on demand) with native
# Image.blend_rect, and each dirty tile is re-uploaded at most once per UPLOAD_INTERVAL. Each tile is one
# unshaded transparent quad just above roads and below the fresh effect decals and the fog overlay. Landed
# debris chunks persist in one static MultiMesh ring of CHUNK_CAPACITY instances (oldest replaced first).
# Nothing here is per-frame work proportional to past explosions: a frame uploads at most UPLOADS_PER_FRAME
# dirty tiles (64 KB each), each tile at most once per UPLOAD_INTERVAL, and both tiles and chunks are capped.
# A few tiles are built during mission setup, one of them drawn empty so the tile shader compiles at load
# rather than at the first crater.

const TEXEL:=0.5
const TILE_TEXELS:=128
const TILE_SIZE:=TEXEL*TILE_TEXELS
# 96 tiles of 64 m cover a 640x640 m fight; past that the least recently stamped tile is recycled.
const MAX_TILES:=96
const UPLOAD_INTERVAL:=0.25
const UPLOADS_PER_FRAME:=2
const PREALLOCATED:=8
const HEIGHT:=0.036 # above road surfaces (<= 0.028), below fresh decals (0.045) and the fog overlay (0.055)
const CHUNK_CAPACITY:=512
const CHUNK_MIN_SIZE:=0.12
const TILE_BYTES:=TILE_TEXELS*TILE_TEXELS*4

# Mark styles
const CRATER:=0 # HE: dark pit, pale ejecta rim, streaky soil spray
const SCORCH:=1 # warhead burn: sunburst of soot streaks
const BURN:=2   # vehicle kill / depot: heavy oily black patch with a soot halo
const STYLES:=3
const VARIANTS:=3
const BASE:=40 # base brush resolution; stamps resample it to their size

# Base brushes are generated once per process and shared by every instance (tests create many).
static var base_brushes:={}
var sized:={}
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

func set_bounds(box:AABB, world_size:Vector2) -> void:
	chunk_instance.custom_aabb=box
	tile_limit=Vector2i(ceili(world_size.x/TILE_SIZE),ceili(world_size.y/TILE_SIZE))
	# Generate every base brush during mission setup (~3 ms each, once per process) rather than at the first
	# explosion of each kind mid-fight.
	for style in STYLES:
		for variant in VARIANTS:
			if not base_brushes.has(style*VARIANTS+variant):base_brushes[style*VARIANTS+variant]=make_brush(style,variant)
	while allocated<mini(PREALLOCATED,tile_limit.x*tile_limit.y):spare.append(_new_tile())
	if not spare.is_empty() and tiles.is_empty():
		spare.back().node.position=Vector3(0.5*TILE_SIZE,HEIGHT,0.5*TILE_SIZE)
		spare.back().node.visible=true

# ---------------------------------------------------------------- ground damage
# Stamps a permanent mark of the given radius (metres). Cost: one cached brush plus one native blend per
# covered tile (1-4); the texture upload happens later, throttled.
func stamp(pos:Vector3, radius:float, style:int) -> void:
	var started:=Time.get_ticks_usec()
	var r:=clampi(roundi(radius/TEXEL),1,28)
	serial+=1
	var brush:=_brush(style,r,serial%VARIANTS)
	var size:=brush.get_width()
	var origin:=Vector2i(floori(pos.x/TEXEL)-size/2,floori(pos.z/TEXEL)-size/2)
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
	tile.node.position=Vector3((key.x+0.5)*TILE_SIZE,HEIGHT,(key.y+0.5)*TILE_SIZE)
	tile.node.visible=true
	tiles[key]=tile
	return tile

func _new_tile() -> Dictionary:
	if plane==null:
		plane=PlaneMesh.new()
		plane.size=Vector2(TILE_SIZE,TILE_SIZE)
	var image:=Image.create(TILE_TEXELS,TILE_TEXELS,false,Image.FORMAT_RGBA8)
	var material:=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode=BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR
	material.render_priority=-2
	var texture:=ImageTexture.create_from_image(image)
	material.albedo_texture=texture
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
	var t:=Vector2i(floori(pos.x/TEXEL),floori(pos.z/TEXEL))
	var key:=Vector2i(floori(float(t.x)/TILE_TEXELS),floori(float(t.y)/TILE_TEXELS))
	if not tiles.has(key):return 0.0
	return tiles[key].image.get_pixelv(t-key*TILE_TEXELS).a

func _brush(style:int, r:int, variant:int) -> Image:
	var key:=(style*VARIANTS+variant)*64+r
	if sized.has(key):return sized[key]
	var base_key:=style*VARIANTS+variant
	if not base_brushes.has(base_key):base_brushes[base_key]=make_brush(style,variant)
	var image:Image=base_brushes[base_key].duplicate()
	image.resize(2*r+1,2*r+1,Image.INTERPOLATE_BILINEAR)
	sized[key]=image
	return image

static func _hash(x:int, y:int, s:int) -> float:
	var h:=(x*374761393+y*668265263+s*1442695041)&0x7fffffff
	h=((h^(h>>13))*1274126177)&0x7fffffff
	return float(h&0xffff)/65535.0

static func _noise(x:float, y:float, s:int) -> float:
	var ix:=floori(x)
	var iy:=floori(y)
	var fx:=x-ix
	var fy:=y-iy
	fx=fx*fx*(3.0-2.0*fx)
	fy=fy*fy*(3.0-2.0*fy)
	return lerpf(lerpf(_hash(ix,iy,s),_hash(ix+1,iy,s),fx),lerpf(_hash(ix,iy+1,s),_hash(ix+1,iy+1,s),fx),fy)

# Procedural base brush (BASE x BASE, RGBA). d is distance from centre in brush radii.
static func make_brush(style:int, variant:int) -> Image:
	var image:=Image.create(BASE,BASE,false,Image.FORMAT_RGBA8)
	var seed_value:=style*31+variant*7+5
	var half:=(BASE-1)*0.5
	for y in BASE:
		for x in BASE:
			var dx:=(x-half)/half
			var dy:=(y-half)/half
			var d:=sqrt(dx*dx+dy*dy)
			if d>=1.0:continue
			var n:=_noise(x*0.22,y*0.22,seed_value)*0.65+_noise(x*0.6,y*0.6,seed_value+1)*0.35
			# Angular streaks: ejecta and soot fingers radiating from the centre.
			var angle:=atan2(dy,dx)/TAU+0.5
			var streak:=_noise(angle*14.0,0.5,seed_value+2)
			var edge:=d+(n-0.5)*0.35
			var col:=Color(0,0,0,0)
			match style:
				CRATER:
					var pit:=1.0-smoothstep(0.34,0.46,edge)
					var rim:=smoothstep(0.34,0.46,edge)*(1.0-smoothstep(0.58,0.74,edge))
					var spray:=(1.0-smoothstep(0.55,1.0,d-(streak-0.5)*0.5))*smoothstep(0.5,0.62,edge)
					var pit_col:=Color(0.12,0.095,0.07).lerp(Color(0.07,0.06,0.05),1.0-edge)
					var rim_col:=Color(0.40,0.33,0.24)*(0.85+0.3*n)
					col=pit_col.lerp(rim_col,rim/(pit+rim+0.0001))
					var a:=maxf(pit*0.86,rim*0.55)
					if spray*0.34>a:
						col=Color(0.20,0.16,0.11)
						a=spray*0.34
					col.a=a
				SCORCH:
					var reach:=0.55+0.45*streak
					var a:=(1.0-smoothstep(reach*0.45,reach,edge))*0.72
					a=maxf(a,(1.0-smoothstep(0.0,0.5,edge))*0.8)
					col=Color(0.045,0.04,0.035).lerp(Color(0.10,0.085,0.065),smoothstep(0.2,0.8,edge))
					col.a=a*(0.85+0.15*n)
				_:
					var core:=1.0-smoothstep(0.45,0.7,edge+(streak-0.5)*0.25)
					var halo:=(1.0-smoothstep(0.6,1.0,d+(n-0.5)*0.2))*0.38
					col=Color(0.03,0.028,0.026).lerp(Color(0.08,0.07,0.06),smoothstep(0.3,0.9,edge))
					col.a=maxf(core*0.88,halo)
			image.set_pixel(x,y,col)
	return image

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
