class_name BattleEffects
extends Node3D

# Cosmetic combat presentation only: nothing here feeds damage, hit resolution or simulation trajectories.
# Three fixed MultiMesh pools (volume smoke/debris/spray/fire, additive glow, flat ground marks), a bounded
# projectile queue, a bounded cue list for staged timing and a few sustained wreck-fire emitters.

const VOLUME_CAPACITY:=480
const GLOW_CAPACITY:=256
const GROUND_CAPACITY:=64
const CAPACITY:=VOLUME_CAPACITY+GLOW_CAPACITY+GROUND_CAPACITY
const PROJECTILE_CAPACITY:=128
const CUE_CAPACITY:=96
const EMITTER_CAPACITY:=12
# Live debris cards across all explosions; further fragments are skipped rather than recycling smoke slots.
const DEBRIS_CAP:=64
const FLOOR:=0.03
const DECAL_HEIGHT:=0.045
const BREEZE:=Vector3(0.28,0,0.12)
# Fixed battle camera direction (offset 26,64,46 from its focus); replaced by the live camera when present.
static var DEFAULT_VIEW:=Basis.looking_at(-Vector3(26,64,46),Vector3.UP)
# Cards and streaks never shrink below this many screen pixels, so distant flashes still read.
const MIN_PIXELS:=2.0
# Camera shake: a few recent blasts, summed as trauma (capped at 1) and raised to 1.5. Peak offset is this
# fraction of the view height (about 14 px at 900 px), so it feels the same at every zoom; it fades out over
# SHAKE_REACH view heights from the camera focus.
const SHAKE_CAPACITY:=8
const SHAKE_PEAK:=0.016
const SHAKE_REACH:=1.1

# Volume kinds
const SMOKE:=0
const DEBRIS:=1
const SPRAY:=2
const FIRE:=3
# Glow kinds
const FLASH:=0
const STREAK:=1
const EMBER:=2
# Ground kinds
const SCORCH:=0
const DUST_RING:=1
const FOAM_RING:=2

# Particle flags
const FRESH:=1
const BOUNCE:=2
const ALIGN:=4
const WIND:=8
const GROUND_KILL:=16
const TRAIL:=32
const AXIAL:=64
const STILL:=128 # no velocity, gravity or spin: motion integration is skipped (flashes, blooms, decals)

# Priorities: optional detail is thinned first under load; essential beats are allowed to recycle slots.
const OPTIONAL:=0
const NORMAL:=1
const ESSENTIAL:=2

const DUST:=Color(0.63,0.56,0.42)
const SOIL:=Color(0.27,0.22,0.16)
const PROPELLANT:=Color(0.80,0.79,0.74)
const SOOT:=Color(0.16,0.15,0.14)
const GREY_SMOKE:=Color(0.44,0.43,0.41)
const SPRAY_WHITE:=Color(0.86,0.93,0.95)
const FOAM:=Color(0.90,0.95,0.95)
const FLAME:=Color(1.0,0.66,0.30)
const TRACER:=Color(1.0,0.42,0.16)
const SPARK:=Color(1.0,0.70,0.30)
const SCORCH_COLOR:=Color(0.07,0.065,0.055)
const METAL:=Color(0.25,0.26,0.24)

# Presentation-only weapon profiles. barrel offsets the muzzle from the event origin; speed is visual travel.
const WEAPONS:={
	"rifle":{"class":"small","barrel":0.6,"speed":190.0,"tracer_every":4,"rounds":1,"gap":0.0},
	"drone":{"class":"small","barrel":0.3,"speed":190.0,"tracer_every":4,"rounds":1,"gap":0.0},
	"aa":{"class":"autocannon","barrel":1.5,"speed":170.0,"tracer_every":2,"rounds":3,"gap":0.075},
	"tank":{"class":"cannon","barrel":2.2,"speed":280.0,"tracer_every":1,"rounds":1,"gap":0.0},
	"boat":{"class":"naval","barrel":1.6,"speed":220.0,"tracer_every":1,"rounds":1,"gap":0.0},
	"atgm":{"class":"missile","barrel":0.5,"speed":32.0,"tracer_every":0,"rounds":1,"gap":0.0},
	"helo":{"class":"rocket","barrel":0.9,"speed":75.0,"tracer_every":0,"rounds":2,"gap":0.14},
	# Field emplacements and loitering munitions, used when an event names them instead of their combat alias.
	"bunker":{"class":"small","barrel":0.4,"speed":200.0,"tracer_every":2,"rounds":2,"gap":0.06},
	"at_gun":{"class":"atgun","barrel":1.9,"speed":320.0,"tracer_every":1,"rounds":1,"gap":0.0},
	"fpv_drone":{"class":"fpv","barrel":0.0,"speed":28.0,"tracer_every":0,"rounds":1,"gap":0.0},
}
const TARGET_SURFACE:={"rifle":"soft","atgm":"soft","engineer":"soft","tank":"armor","aa":"armor","boat":"armor","harvester":"armor","helo":"air","drone":"air","fpv_drone":"air","hq":"structure","power":"structure","refinery":"structure","barracks":"structure","factory":"structure",
	"bunker":"structure","command_post":"structure","ammo_depot":"structure","observation_post":"structure","tactical_cover":"structure","at_gun":"armor","tank_obstacles":"armor",
	"fighting_trench":"earth","vehicle_berm":"earth","concertina_wire":"soft","camouflage_net":"soft","repair_point":"soft","aid_post":"soft","forward_supply_point":"soft"}
const STRUCTURES:=["hq","power","refinery","barracks","factory"]
const INFANTRY:=["rifle","atgm","engineer"]
# Kinds that get the full vehicle kill; "" is the legacy kind-less explosion(). Unknown kinds get a small blast.
const VEHICLES:=["tank","aa","boat","harvester",""]
const Explosions:=preload("res://scripts/effects_explosions.gd")
const Remains:=preload("res://scripts/effects_remains.gd")

class Pool extends RefCounted:
	const STRIDE:=20
	var capacity:int
	var flat:bool
	# Camera-facing cards are built here in world space, not in a skip_vertex_transform shader: the
	# Compatibility renderer does not expose per-instance transforms through MODEL_MATRIX like Forward+.
	var spin_cards:=false
	var pull:=0.0
	var right:=Vector3.RIGHT
	var up:=Vector3.UP
	var back:=Vector3.BACK
	var min_size:=0.0
	var multimesh:=MultiMesh.new()
	var instance:MultiMeshInstance3D
	var pos:=PackedVector3Array()
	var vel:=PackedVector3Array()
	var axis:=PackedVector3Array()
	var color:=PackedColorArray()
	var age:=PackedFloat32Array()
	var life:=PackedFloat32Array()
	var size0:=PackedFloat32Array()
	var size1:=PackedFloat32Array()
	var width:=PackedFloat32Array()
	var drag:=PackedFloat32Array()
	var gravity:=PackedFloat32Array()
	var rot:=PackedFloat32Array()
	var spin:=PackedFloat32Array()
	var delay:=PackedFloat32Array()
	var timer:=PackedFloat32Array()
	var variant:=PackedFloat32Array()
	var kind:=PackedByteArray()
	var flags:=PackedByteArray()
	var free_slots:=PackedInt32Array()
	# Live particles per kind, so individual layers (debris) can be capped inside a shared pool.
	var kind_live:=PackedInt32Array()
	var buffer:=PackedFloat32Array()
	var live:=0
	var visible_count:=0
	var dropped:=0
	var recycled:=0
	var steal_cursor:=0
	# Highest slot that may be live; step() scans only up to it. Free slots are reused lowest-first (LIFO).
	var top:=-1
	var spawned_top:=-1 # highest slot allocated while step() runs (trail puffs spawn mid-scan)
	var bounds:=AABB()
	var limit:=AABB()
	var front_kind:=-1
	# Bouncing particles of this kind report where they come to rest when they expire (debris remnants).
	var rest_kind:=-1

	func _init(count:int, is_flat:bool) -> void:
		capacity=count
		flat=is_flat
		pos.resize(count);vel.resize(count);axis.resize(count);color.resize(count)
		age.resize(count);life.resize(count);size0.resize(count);size1.resize(count);width.resize(count)
		drag.resize(count);gravity.resize(count);rot.resize(count);spin.resize(count);delay.resize(count)
		timer.resize(count);variant.resize(count);kind.resize(count);flags.resize(count)
		buffer.resize(count*STRIDE)
		for i in count:free_slots.append(count-1-i)
		kind_live.resize(8)
		multimesh.transform_format=MultiMesh.TRANSFORM_3D
		multimesh.use_colors=true
		multimesh.use_custom_data=true
		if flat:
			var plane:=PlaneMesh.new()
			plane.size=Vector2.ONE
			multimesh.mesh=plane
		else:
			var quad:=QuadMesh.new()
			quad.size=Vector2.ONE
			multimesh.mesh=quad
		multimesh.instance_count=count
		multimesh.visible_instance_count=0

	func alloc(priority:int) -> int:
		if free_slots.is_empty():
			if priority<ESSENTIAL:
				dropped+=1
				return -1
			var stolen:=steal_cursor
			steal_cursor=(steal_cursor+1)%capacity
			recycled+=1
			return stolen
		if priority==OPTIONAL and live>capacity*0.7:
			dropped+=1
			return -1
		var slot:=free_slots[free_slots.size()-1]
		free_slots.resize(free_slots.size()-1)
		live+=1
		if slot>top:top=slot
		if slot>spawned_top:spawned_top=slot
		return slot

	func spawn(p:Vector3, v:Vector3, k:int, s0:float, s1:float, duration:float, c:Color, drag_rate:float, fall:float, wait:float, priority:int, bits:int, turn:float, turn_rate:float, variety:float) -> int:
		var i:=alloc(priority)
		if i<0:return -1
		if life[i]>0.0:kind_live[kind[i]]-=1 # recycled slot
		kind_live[k]+=1
		pos[i]=p;vel[i]=v;kind[i]=k;size0[i]=s0;size1[i]=s1
		life[i]=maxf(duration,0.0001);age[i]=0.0;color[i]=c;drag[i]=drag_rate;gravity[i]=fall
		if v==Vector3.ZERO and fall==0.0 and turn_rate==0.0 and (bits&(TRAIL|WIND))==0:bits|=STILL
		delay[i]=maxf(wait,0.0);flags[i]=bits|FRESH;rot[i]=turn;spin[i]=turn_rate;variant[i]=variety
		timer[i]=0.0;axis[i]=Vector3.ZERO;width[i]=0.0
		return i

	func kill(i:int) -> void:
		kind_live[kind[i]]-=1
		life[i]=0.0
		free_slots.append(i)
		live-=1

	func clear() -> void:
		for i in capacity:
			if life[i]>0.0:kill(i)
		top=-1
		visible_count=0
		multimesh.visible_instance_count=0
		if instance:instance.visible=false

	func step(dt:float, wind:Vector3, owner:Object) -> void:
		var n:=0
		var f:=0
		var lo:=Vector3(INF,INF,INF)
		var hi:=Vector3(-INF,-INF,-INF)
		var margin:=0.0
		var highest:=-1
		spawned_top=-1
		for i in top+1:
			var duration:=life[i]
			if duration<=0.0:continue
			highest=i
			var h:=dt
			if delay[i]>0.0:
				delay[i]-=dt
				if delay[i]>0.0:continue
				h=0.0 # A delayed particle is born at its authored state on the frame it appears.
			var bits:=flags[i]
			if bits&FRESH:
				flags[i]=bits&~FRESH
				h=0.0 # Every particle renders at least once, even one-frame flashes at low frame rates.
			var a:=age[i]+h
			if a>=duration:
				if kind[i]==rest_kind and (bits&BOUNCE)!=0:owner.call("_debris_rest",pos[i],size0[i],color[i],rot[i])
				kill(i)
				continue
			age[i]=a
			var p:=pos[i]
			if h>0.0 and (bits&STILL)==0:
				var v:=vel[i]
				v.y-=gravity[i]*h
				var k:=drag[i]
				if k>0.0:
					var target:=wind if (bits&WIND)!=0 else Vector3.ZERO
					v+=(target-v)*minf(1.0,k*h)
				p+=v*h
				if p.y<FLOOR and v.y<0.0:
					if bits&BOUNCE:
						p.y=FLOOR
						v=Vector3(v.x*0.45,-v.y*0.28,v.z*0.45)
						spin[i]*=0.5
					elif bits&GROUND_KILL:
						kill(i)
						continue
				pos[i]=p
				vel[i]=v
				rot[i]+=spin[i]*h
				if bits&ALIGN and v.length_squared()>0.0001:axis[i]=v.normalized()
				if bits&TRAIL and p.y>0.35:
					timer[i]+=h
					if timer[i]>=0.1:
						timer[i]=0.0
						owner.call("_trail_puff",p,1.0-a/duration,color[i])
			var t:=a/duration
			var s:=lerpf(size0[i],size1[i],1.0-(1.0-t)*(1.0-t))
			# Front-kind rows are packed from the buffer end and moved after the rest, so they draw last.
			var front:=kind[i]==front_kind
			var o:=(capacity-1-f)*STRIDE if front else n*STRIDE
			# Rows are row-major 3x4: basis X, Y, Z columns interleaved with the origin.
			if bits&AXIAL:
				# Ribbon along the world axis, widened across the view so tracers and sparks face the camera.
				var along:=axis[i]*s
				var flat_along:=along-back*along.dot(back)
				var seen:=flat_along.length()
				if seen<min_size*2.0:
					along+=(flat_along/seen if seen>0.0001 else right)*(min_size*2.0-seen)
				var side:=back.cross(along)
				side=side.normalized() if side.length_squared()>0.000001 else up
				var w:=maxf(width[i],min_size*0.75)
				buffer[o]=along.x;buffer[o+1]=side.x*w;buffer[o+2]=back.x*w;buffer[o+3]=p.x
				buffer[o+4]=along.y;buffer[o+5]=side.y*w;buffer[o+6]=back.y*w;buffer[o+7]=p.y
				buffer[o+8]=along.z;buffer[o+9]=side.z*w;buffer[o+10]=back.z*w;buffer[o+11]=p.z
			elif flat:
				# Off-diagonal zeros never change in the flat pool; only rotation/scale/origin are rewritten.
				var c:=cos(rot[i])*s
				var sn:=sin(rot[i])*s
				buffer[o]=c;buffer[o+2]=sn;buffer[o+3]=p.x
				buffer[o+5]=s;buffer[o+7]=p.y
				buffer[o+8]=-sn;buffer[o+10]=c;buffer[o+11]=p.z
			else:
				s=maxf(s,min_size)
				var x_axis:Vector3
				var y_axis:Vector3
				if spin_cards:
					var c:=cos(rot[i])*s
					var sn:=sin(rot[i])*s
					x_axis=right*c+up*sn
					y_axis=up*c-right*sn
				else:
					x_axis=right*s
					y_axis=up*s
				var z_axis:=back*s
				# Pull the card toward the camera so ground-level puffs are not sliced by terrain.
				var q:=p+z_axis*pull
				buffer[o]=x_axis.x;buffer[o+1]=y_axis.x;buffer[o+2]=z_axis.x;buffer[o+3]=q.x
				buffer[o+4]=x_axis.y;buffer[o+5]=y_axis.y;buffer[o+6]=z_axis.y;buffer[o+7]=q.y
				buffer[o+8]=x_axis.z;buffer[o+9]=y_axis.z;buffer[o+10]=z_axis.z;buffer[o+11]=q.z
			var col:=color[i]
			buffer[o+12]=col.r;buffer[o+13]=col.g;buffer[o+14]=col.b;buffer[o+15]=col.a
			buffer[o+16]=kind[i];buffer[o+17]=rot[i]/TAU;buffer[o+18]=t;buffer[o+19]=variant[i]
			lo=lo.min(p)
			hi=hi.max(p)
			margin=maxf(margin,s)
			if front:f+=1
			else:n+=1
		top=maxi(highest,spawned_top)
		# Rows already inside the target range stay; reads come from rows >= capacity-f, writes land below it.
		var dst:=n
		for r in range(maxi(capacity-f,n+f),capacity):
			for c in STRIDE:buffer[dst*STRIDE+c]=buffer[r*STRIDE+c]
			dst+=1
		n+=f
		visible_count=n
		if n>0:
			# Bounds follow live content, so culling works on any map size without a fixed world box.
			margin+=0.5
			bounds=AABB(lo-Vector3.ONE*margin,hi-lo+Vector3.ONE*margin*2.0)
			# A stray fragment far off the map must not inflate the box; keep it inside the padded world.
			if limit.has_volume() and bounds.intersects(limit):bounds=bounds.intersection(limit)
		commit()

	func commit() -> void:
		multimesh.visible_instance_count=visible_count
		if visible_count>0:
			multimesh.buffer=buffer
		if instance:
			instance.visible=visible_count>0
			if visible_count>0:instance.custom_aabb=bounds

var wind:=Vector3.ZERO
# audio_fx.gd stays silent while this is set; tests set it to keep battles quiet.
var muted:=false
# Sound lives in audio_fx.gd. These idle players remain only for callers that still free them by name.
var flashes:=AudioStreamPlayer.new()
var explosion_audio:=AudioStreamPlayer.new()
var rng:=RandomNumberGenerator.new()
var time:=0.0
var volume:=Pool.new(VOLUME_CAPACITY,false)
var glow:=Pool.new(GLOW_CAPACITY,false)
var ground:=Pool.new(GROUND_CAPACITY,true)
var projectiles:Array[Dictionary]=[]
var cues:Array[Dictionary]=[]
var emitters:Array[Dictionary]=[]
var tracer_counts:Dictionary={}
var dropped_cues:=0
var noise_texture:ImageTexture
var world_box:=AABB()
var world_rect:=Rect2() # unpadded map, for permanent marks
var shore_x:=INF
# Legacy muzzle() calls wait here for the paired projectile() that names the weapon.
var pending_muzzles:Array[Dictionary]=[]
# Recent blasts that shake the camera (see camera_shake()); review captures switch this off for still frames.
var shake_enabled:=true
var shake_pos:=PackedVector3Array()
var shake_strength:=PackedFloat32Array()
var shake_age:=PackedFloat32Array()
# Permanent craters/scorch (tiled ground-damage textures) and landed debris chunks; see effects_remains.gd.
var remains:=Remains.new()
# Live damaged vehicles (see "live vehicle damage" below).
var live_sim=null # explicit watch(); otherwise the parent's `sim` (battle.gd)
var live_nodes:Dictionary={} # unit id -> root Node3D, for the hull damage pose
var live_emitters:Array[Dictionary]=[]
var live_bound:=false
var _live_clock:=0.0
var _live_wreck_seen:Dictionary={} # unit id -> effects time the wreck was first seen
var _live_tilts:Dictionary={} # unit id -> root Node3D carrying a damage pose
var _live_tilt_units:Array[Dictionary]=[]
var live_paused:=false # explicit pause for watch() hosts; battle.gd's own `paused` is read from the parent
# Ground point under the view centre, ground radius of the view (INF: no culling) and a zoom LOD factor.
var view_focus:=Vector3.ZERO
var view_radius:=INF
var view_zoom:=1.0

func _init() -> void:
	rng.seed=814
	# Instances in one MultiMesh draw in buffer order; flames stay in front of the soot they feed.
	volume.front_kind=FIRE
	volume.rest_kind=DEBRIS
	add_child(remains)
	volume.spin_cards=true
	volume.pull=0.45
	glow.pull=0.5
	set_view(DEFAULT_VIEW,0.0)

# Orientation used for camera-facing cards (Camera3D basis: x right, y up, z back toward the viewer) and the
# smallest card size in world units. _process copies the active camera every frame; tests may set it directly.
func set_view(view:Basis, smallest:float) -> void:
	for pool in [volume,glow]:
		pool.right=view.x.normalized()
		pool.up=view.y.normalized()
		pool.back=view.z.normalized()
		pool.min_size=smallest

func _sync_view() -> void:
	var camera:=get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera==null:return
	var smallest:=0.0
	var height:=get_viewport().get_visible_rect().size.y
	if camera.projection==Camera3D.PROJECTION_ORTHOGONAL and height>0.0:
		smallest=MIN_PIXELS*camera.size/height
	set_view(camera.global_basis,smallest)
	var look:=-camera.global_basis.z
	if camera.projection==Camera3D.PROJECTION_ORTHOGONAL and look.y<-0.05 and height>0.0:
		var aspect:=get_viewport().get_visible_rect().size.x/height
		view_focus=camera.global_position+look*(-camera.global_position.y/look.y)
		view_radius=0.5*camera.size*maxf(aspect,1.0/-look.y)
		view_zoom=clampf(LIVE_FULL_ZOOM/camera.size,LIVE_MIN_ZOOM,1.0)

func reseed(value:int) -> void:
	rng.seed=value
	tracer_counts.clear()

# Call once after the terrain exists: effects.set_world_bounds(sim.terrain.world_size, sim.terrain.shore_x).
# Culling boxes still follow live content; this caps them to the padded map and lets legacy calls infer water.
func set_world_bounds(world_size:Vector2, shore:float=INF) -> void:
	world_box=AABB(Vector3(-8,-2,-8),Vector3(world_size.x+16,62,world_size.y+16))
	world_rect=Rect2(Vector2.ZERO,world_size)
	shore_x=shore
	for pool in [volume,glow,ground]:pool.limit=world_box
	remains.set_bounds(world_box,world_size)

func is_water_at(pos:Vector3) -> bool:
	return pos.x>=shore_x

func _ready() -> void:
	noise_texture=make_noise_texture()
	var specs:=[[volume,"res://shaders/effect_volume.gdshader",1],[glow,"res://shaders/effect_glow.gdshader",2],[ground,"res://shaders/effect_ground.gdshader",-1]]
	for spec in specs:
		var pool:Pool=spec[0]
		var material:=ShaderMaterial.new()
		material.shader=load(spec[1])
		material.render_priority=spec[2]
		if pool!=glow:material.set_shader_parameter("noise_tex",noise_texture)
		pool.instance=MultiMeshInstance3D.new()
		pool.instance.multimesh=pool.multimesh
		pool.instance.material_override=material
		pool.instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pool.instance.visible=false
		add_child(pool.instance)
	add_child(flashes)
	add_child(explosion_audio)

# Seamless value noise generated natively by the engine; no external texture asset.
static func make_noise_texture() -> ImageTexture:
	var noise:=FastNoiseLite.new()
	noise.seed=814
	noise.noise_type=FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency=0.035
	noise.fractal_type=FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves=3
	var image:=noise.get_seamless_image(128,128)
	image.convert(Image.FORMAT_L8)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

# Explosion sound now comes from the destroyed event in audio_fx.gd; kept for effects_explosions.gd callers.
func _boom(_scale:float) -> void:
	pass

# ---------------------------------------------------------------- primitives
func _jitter(radius:float, vertical:float=-1.0) -> Vector3:
	return Vector3(rng.randf_range(-radius,radius),rng.randf_range(-radius,radius) if vertical<0 else rng.randf_range(-vertical,vertical),rng.randf_range(-radius,radius))

func _flat(direction:Vector3) -> Vector3:
	var f:=Vector3(direction.x,0,direction.z)
	return f.normalized() if f.length_squared()>0.0001 else Vector3.FORWARD

func smoke(pos:Vector3, vel:Vector3, size0:float, size1:float, life:float, col:Color, drag:float=1.5, lift:float=0.0, delay:float=0.0, priority:int=NORMAL) -> int:
	return volume.spawn(pos,vel,SMOKE,size0,size1,life,col,drag,-lift,delay,priority,WIND,rng.randf()*TAU,rng.randf_range(-0.6,0.6),rng.randf())

# drag and lift default to the original small-fireball motion; large blasts pass a stronger lift so the
# fireball rolls upward while the shader cools it from white through orange into soot.
# tint multiplies the shader's white-orange-soot ramp: darker red-brown for outer lobes, near-black for the
# smoky lobes mixed into a big fireball.
func fireball(pos:Vector3, vel:Vector3, size0:float, size1:float, life:float, delay:float=0.0, priority:int=ESSENTIAL, drag:float=2.2, lift:float=1.2, tint:Color=Color(1,1,1,1)) -> int:
	return volume.spawn(pos,vel,FIRE,size0,size1,life,tint,drag,-lift,delay,priority,0,rng.randf()*TAU,rng.randf_range(-1.6,1.6),rng.randf())

func debris(pos:Vector3, vel:Vector3, size:float, life:float, col:Color, bounce:bool=true, trail:bool=false, priority:int=NORMAL) -> int:
	if volume.kind_live[DEBRIS]>=DEBRIS_CAP:
		volume.dropped+=1
		return -1
	var bits:=(BOUNCE if bounce else GROUND_KILL)|(TRAIL if trail else 0)
	return volume.spawn(pos,vel,DEBRIS,size,size,life,col,0.0,9.8,0.0,priority,bits,rng.randf()*TAU,rng.randf_range(-9,9),rng.randf())

func spray(pos:Vector3, vel:Vector3, size0:float, size1:float, life:float, delay:float=0.0, priority:int=NORMAL) -> int:
	return volume.spawn(pos,vel,SPRAY,size0,size1,life,SPRAY_WHITE,0.35,9.8,delay,priority,GROUND_KILL,rng.randf()*TAU,rng.randf_range(-1,1),rng.randf())

func flash(pos:Vector3, size:float, life:float, col:Color=FLAME, delay:float=0.0, priority:int=ESSENTIAL) -> int:
	return glow.spawn(pos,Vector3.ZERO,FLASH,size,size*1.15,life,col,0.0,0.0,delay,priority,0,rng.randf()*TAU,0.0,rng.randf())

func ember(pos:Vector3, vel:Vector3, size:float, life:float, col:Color=FLAME, priority:int=NORMAL) -> int:
	return glow.spawn(pos,vel,EMBER,size,size*0.7,life,col,1.5,-0.6,0.0,priority,0,0.0,0.0,rng.randf())

# Soft additive light spill over the ground and nearby models, standing in for a dynamic light: a light in the
# Compatibility renderer costs an extra pass per lit mesh and new shader variants on first use.
# Capped so the largest blast (a structure) cannot cover the screen.
const BLOOM_MAX:=24.0
func bloom(pos:Vector3, size:float, life:float, col:Color=Color(1.0,0.55,0.22,0.32), priority:int=NORMAL, delay:float=0.0) -> int:
	var s:=minf(size,BLOOM_MAX)
	return glow.spawn(pos,Vector3.ZERO,EMBER,s,s*1.1,life,col,0.0,0.0,delay,priority,0,0.0,0.0,rng.randf())

# Axial glow: tracer bodies, flame tongues and sparks. Position is the streak centre.
func streak(pos:Vector3, direction:Vector3, length:float, thickness:float, life:float, col:Color, vel:Vector3=Vector3.ZERO, fall:float=0.0, priority:int=NORMAL, delay:float=0.0) -> int:
	var bits:=AXIAL|(ALIGN if vel!=Vector3.ZERO else 0)|(GROUND_KILL if fall>0 else 0)
	var i:=glow.spawn(pos,vel,STREAK,length,length*0.6 if vel!=Vector3.ZERO else length,life,col,0.0,fall,delay,priority,bits,0.0,0.0,rng.randf())
	if i>=0:
		glow.axis[i]=direction.normalized() if direction.length_squared()>0.0001 else Vector3.RIGHT
		glow.width[i]=thickness
	return i

# size scales streak length and width: 1 for bullet ricochets, 2-2.5 for the fragments of a big blast.
func sparks(pos:Vector3, count:int, speed:float, bias:Vector3, life:float, priority:int=NORMAL, size:float=1.0) -> void:
	for n in count:
		var v:=(_jitter(1.0).normalized()+bias).normalized()*rng.randf_range(speed*0.5,speed)
		if v.y<0:v.y=-v.y*0.5
		streak(pos,v,rng.randf_range(0.25,0.45)*size,0.045*sqrt(size),rng.randf_range(life*0.5,life),SPARK,v,9.8,priority)

func decal(pos:Vector3, kind:int, size0:float, size1:float, life:float, col:Color, priority:int=NORMAL) -> int:
	return ground.spawn(Vector3(pos.x,DECAL_HEIGHT+(0.004 if kind!=SCORCH else 0.0),pos.z),Vector3.ZERO,kind,size0,size1,life,col,0.0,0.0,0.0,priority,0,rng.randf()*TAU,0.0,rng.randf())

func cue(delay:float, action:Callable) -> bool:
	if cues.size()>=CUE_CAPACITY:
		dropped_cues+=1
		return false
	cues.append({"at":time+delay,"action":action})
	return true

# Debris trail puff, tinted by the fragment: brown soil leaves dust, pale masonry leaves masonry dust and dark
# hull fragments leave soot.
func _trail_puff(pos:Vector3, strength:float, tint:Color=SOOT) -> void:
	var col:=SOOT
	if tint.r-tint.b>0.08:col=DUST.darkened(0.1)
	elif tint.get_luminance()>0.35:col=tint.lightened(0.3)
	smoke(pos,Vector3(0,0.3,0),0.22,0.9*strength+0.3,0.6,Color(col,0.5),1.8,0.0,0.0,OPTIONAL)

# ---------------------------------------------------------------- permanent remains
# Stamps a permanent crater/scorch/burn mark (Remains.CRATER/SCORCH/BURN) of radius metres. Never on water
# or off the map once bounds are known.
func mark(pos:Vector3, radius:float, style:int) -> void:
	if is_water_at(pos) or (world_rect.has_area() and not world_rect.has_point(Vector2(pos.x,pos.z))):return
	remains.stamp(pos,radius,style)

# A bouncing fragment expired on the ground: keep it as a static chunk unless it is a chip or over water.
func _debris_rest(pos:Vector3, size:float, col:Color, turn:float) -> void:
	if size<Remains.CHUNK_MIN_SIZE or pos.y>0.6 or is_water_at(pos):return
	remains.add_chunk(pos,size,col,turn)

# ---------------------------------------------------------------- camera shake
# Registers a blast for camera shake. strength is 1 for a vehicle kill, ~0.35 for a tank HE round; small arms
# never call this. The oldest entry is replaced when full.
func shake(pos:Vector3, strength:float) -> void:
	if strength<=0.0:return
	if shake_pos.size()>=SHAKE_CAPACITY:
		var oldest:=0
		for i in shake_age.size():
			if shake_age[i]>shake_age[oldest]:oldest=i
		shake_pos.remove_at(oldest);shake_strength.remove_at(oldest);shake_age.remove_at(oldest)
	shake_pos.append(pos);shake_strength.append(minf(strength,1.5));shake_age.append(0.0)

func _update_shake(dt:float) -> void:
	for i in range(shake_age.size()-1,-1,-1):
		shake_age[i]+=dt
		if shake_age[i]>=_shake_duration(shake_strength[i]):
			shake_pos.remove_at(i);shake_strength.remove_at(i);shake_age.remove_at(i)

static func _shake_duration(strength:float) -> float:
	return 0.22+0.3*strength

# Camera-space offset to add to the camera position this frame. Scaled by blast size, ground distance from the
# camera focus and view height; zero at a blast's first instant (so unprocessed effects never offset the view)
# and capped at SHAKE_PEAK of the view height.
func camera_shake(focus:Vector3, view_size:float, view:Basis) -> Vector3:
	if not shake_enabled or shake_age.is_empty():return Vector3.ZERO
	var trauma:=0.0
	for i in shake_age.size():
		var a:=shake_age[i]
		var d:=Vector2(shake_pos[i].x-focus.x,shake_pos[i].z-focus.z).length()
		var near:=clampf(1.0-d/(view_size*SHAKE_REACH),0.0,1.0)
		var fade:=1.0-a/_shake_duration(shake_strength[i])
		trauma+=shake_strength[i]*near*minf(1.0,a/0.025)*fade*fade
	trauma=minf(trauma,1.0)
	if trauma<=0.0:return Vector3.ZERO
	var amount:=trauma*sqrt(trauma)*SHAKE_PEAK*view_size
	# Deterministic jitter with a near-constant magnitude, so the peak tracks trauma rather than noise phase.
	var angle:=time*41.0+sin(time*13.0)*2.0
	var wobble:=Vector2(cos(angle),sin(angle*1.37))*(0.8+0.2*sin(time*71.0))
	wobble=wobble.limit_length(1.0)
	return (view.x.normalized()*wobble.x+view.y.normalized()*wobble.y)*amount

# ---------------------------------------------------------------- firing
# Integration entry point: one call per visible "shot" event. Returns the presentation travel time.
func fire(weapon:String, from:Vector3, to:Vector3, hit:bool=true, water:bool=false, target_kind:String="", launch_water:bool=false) -> float:
	var profile:Dictionary=WEAPONS.get(weapon,WEAPONS.rifle)
	var direction:=to-from
	if direction.length_squared()<0.0001:direction=Vector3.FORWARD
	direction=direction.normalized()
	var start:=from+direction*float(profile.barrel)
	var surface:=_surface(hit,water,target_kind,to,String(profile["class"]))
	var end:=to
	if surface in ["ground","water"]:end.y=FLOOR
	elif surface=="sky" and profile["class"]!="autocannon":end=to+direction*6.0
	var side:=_flat(direction).cross(Vector3.UP)
	var travel:=0.0
	for round_index in int(profile.rounds):
		var a:=start
		var b:=end
		if profile["class"]=="rocket":a+=side*(0.45 if round_index%2==0 else -0.45)
		if round_index>0 and not hit:b+=_jitter(0.9,0.0)
		elif round_index>0:b+=_jitter(0.35,0.2)
		var speed:=float(profile.speed)
		var duration:=a.distance_to(b)/speed
		var every:=int(profile.tracer_every)
		var tracer:=false
		if every>0:
			tracer_counts[weapon]=int(tracer_counts.get(weapon,0))+1
			tracer=int(tracer_counts[weapon])%every==0 or every==1
		var shot:={"a":a,"b":b,"dir":(b-a).normalized(),"weapon":weapon,"class":profile["class"],"age":0.0,"delay":round_index*float(profile.gap),"duration":maxf(duration,0.02),"surface":surface,"tracer":tracer,"round":round_index,"launched":false,"trail":0.0,"last":a,"loft":minf(4.0,a.distance_to(b)*0.12) if profile["class"]=="missile" else 0.0,"water_launch":launch_water,"speed":speed}
		_queue(shot)
		if round_index==0:
			_launch(shot)
		travel=maxf(travel,shot.delay+shot.duration)
	return travel

func _surface(hit:bool, water:bool, target_kind:String, to:Vector3, weapon_class:String) -> String:
	if hit:
		if TARGET_SURFACE.has(target_kind):return TARGET_SURFACE[target_kind]
		if to.y>1.6:return "air"
		return "soft" if weapon_class in ["small","autocannon"] else "armor"
	if to.y>1.6:return "sky"
	return "water" if water else "ground"

func _queue(shot:Dictionary) -> void:
	if projectiles.size()>=PROJECTILE_CAPACITY:projectiles.pop_front()
	projectiles.append(shot)

func _launch(shot:Dictionary) -> void:
	shot.launched=true
	_muzzle(String(shot.weapon),shot.a,shot.dir,int(shot.round),bool(shot.water_launch))

func _muzzle(weapon:String, pos:Vector3, direction:Vector3, round_index:int, on_water:bool) -> void:
	var weapon_class:String=WEAPONS.get(weapon,WEAPONS.rifle)["class"]
	var flat:=_flat(direction)
	match weapon_class:
		"small":
			# Brief star and short forward tongue; a faint wisp only on some rounds.
			flash(pos,0.36,0.035,Color(1.0,0.8,0.48))
			streak(pos+direction*0.22,-direction,0.45,0.16,0.035,FLAME,Vector3.ZERO,0.0,NORMAL)
			if rng.randf()<0.5:smoke(pos+direction*0.2,direction*1.1+Vector3(0,0.35,0),0.1,0.5,0.6,Color(PROPELLANT,0.28),2.4,0.2,0.0,OPTIONAL)
		"autocannon":
			flash(pos,0.62,0.04,Color(1.0,0.76,0.4))
			streak(pos+direction*0.45,-direction,0.9,0.28,0.04,FLAME)
			smoke(pos+direction*0.3,direction*2.0+Vector3(0,0.4,0),0.2,0.85,0.8,Color(PROPELLANT,0.3),2.2,0.2,0.0,OPTIONAL)
		"cannon","naval","atgun":
			var heavy:=weapon_class!="naval"
			var k:float={"cannon":1.0,"naval":0.75,"atgun":0.8}[weapon_class]
			# Blast: white-hot core, forward flame tongue and a short-lived fireball ahead of the muzzle.
			flash(pos,1.5*k,0.06,Color(1.0,0.82,0.5))
			streak(pos+direction*1.3*k,-direction,2.6*k,0.9*k,0.07,FLAME,Vector3.ZERO,0.0,ESSENTIAL)
			fireball(pos+direction*0.7*k,direction*2.0,0.5*k,1.3*k,0.2)
			# Propellant gas: decelerating puffs along the bore axis, then drifting.
			for n in (5 if heavy else 4):
				var speed:=rng.randf_range(4.0,11.0)*k
				smoke(pos+direction*rng.randf_range(0.3,1.2),direction*speed+_jitter(0.8)+Vector3(0,0.6,0),0.5*k,rng.randf_range(2.0,2.7)*k,rng.randf_range(1.8,2.8),Color(PROPELLANT,0.55),3.0,0.15,0.0,NORMAL if n<3 else OPTIONAL)
			# Overpressure lifts ground dust or water in a forward fan below the muzzle.
			var base:=Vector3(pos.x,0.18,pos.z)+flat*0.6
			if on_water or not heavy:
				decal(base,FOAM_RING,0.8,3.6*k,0.8,Color(FOAM,0.7))
				for n in 5:
					var out:=(flat.rotated(Vector3.UP,rng.randf_range(-1.6,1.6)))
					spray(base,out*rng.randf_range(1.5,3.0)+Vector3(0,rng.randf_range(1.5,2.6),0),0.18,0.45,0.9)
			else:
				decal(base,DUST_RING,0.8,5.0,0.5,Color(DUST,0.55))
				for n in 6:
					var out:=(flat.rotated(Vector3.UP,rng.randf_range(-1.75,1.75)))
					smoke(base+out*0.4,out*rng.randf_range(3.0,6.5)+Vector3(0,0.5,0),0.55,rng.randf_range(2.0,2.8),rng.randf_range(1.3,2.0),Color(DUST,0.5),2.5,0.1,0.0,NORMAL if n<3 else OPTIONAL)
			# Bore-evacuator / breech puff as the barrel runs out of recoil (~0.24 s animation).
			smoke(pos-direction*0.4,Vector3(0,0.5,0)+direction*0.3,0.3,1.1,1.3,Color(GREY_SMOKE,0.45),1.5,0.2,0.22)
		"missile":
			# Launch flash, rearward backblast cone and dust behind the firer.
			flash(pos,0.6,0.05,Color(1.0,0.8,0.5))
			streak(pos-direction*0.8,direction,1.4,0.5,0.06,FLAME)
			for n in 6:
				smoke(pos-direction*rng.randf_range(0.3,1.0),-direction*rng.randf_range(4.0,8.0)+_jitter(1.0)+Vector3(0,0.4,0),0.4,rng.randf_range(1.4,2.0),rng.randf_range(1.1,1.7),Color(PROPELLANT,0.5),3.0,0.1)
			for n in 4:
				var out:=(-flat).rotated(Vector3.UP,rng.randf_range(-0.9,0.9))
				smoke(Vector3(pos.x,0.18,pos.z)-flat*1.2,out*rng.randf_range(2.0,4.0),0.4,1.8,rng.randf_range(1.2,1.8),Color(DUST,0.45),2.5,0.1)
		"rocket":
			flash(pos,0.55,0.05,Color(1.0,0.8,0.5))
			streak(pos-direction*0.5,direction,0.9,0.3,0.05,FLAME)
			smoke(pos-direction*0.4,-direction*2.0+Vector3(0,-0.3,0),0.3,1.2,0.9,Color(PROPELLANT,0.45),2.4)

func _update_projectiles(dt:float) -> void:
	for i in range(projectiles.size()-1,-1,-1):
		var shot:Dictionary=projectiles[i]
		if not shot.launched:
			shot.delay-=dt
			if shot.delay>0:continue
			_launch(shot)
			continue
		shot.age+=dt
		var progress:=minf(1.0,shot.age/float(shot.duration))
		var a:Vector3=shot.a
		var b:Vector3=shot.b
		var p:=a.lerp(b,progress)+Vector3.UP*float(shot.loft)*4.0*progress*(1.0-progress)
		var last:Vector3=shot.last
		var moved:=p-last
		var heading:Vector3=moved.normalized() if moved.length_squared()>0.000001 else shot.dir
		match String(shot["class"]):
			"fpv":
				# Loitering munition on its terminal dive: only a small motor glint is visible.
				ember(p,Vector3.ZERO,0.28,0.0001,Color(1.0,0.45,0.3,0.8),NORMAL)
			"missile","rocket":
				var missile:bool=shot["class"]=="missile"
				ember(p,Vector3.ZERO,0.55 if missile else 0.42,0.0001,Color(1.0,0.82,0.55),ESSENTIAL)
				var spacing:=0.32 if missile else 0.45
				var travelled:float=float(shot.trail)+moved.length()
				var emitted:=0
				while travelled>=spacing and emitted<8:
					travelled-=spacing
					emitted+=1
					var q:=p-heading*travelled
					# Puffs spread and wander as they age so the trail breaks up instead of reading as a beam.
					smoke(q,_jitter(0.35)+Vector3(0,0.15,0),0.22,rng.randf_range(0.8,1.2) if missile else 0.7,rng.randf_range(1.1,1.8) if missile else 0.8,Color(0.86,0.85,0.81,rng.randf_range(0.26,0.38)),1.2,0.05,0.0,NORMAL if missile else OPTIONAL)
				shot.trail=travelled
			_:
				if shot.tracer:
					var weapon_class:String=shot["class"]
					var length:=clampf(float(shot.speed)*dt*1.15,0.9,4.0)
					var thickness:float={"small":0.05,"autocannon":0.075,"cannon":0.09,"naval":0.08,"atgun":0.1}.get(weapon_class,0.05)
					var col:=TRACER if not weapon_class in ["cannon","atgun"] else Color(1.0,0.78,0.5)
					streak(p-heading*length*0.5,heading,length,thickness,0.0001,Color(col,0.8 if weapon_class=="small" else 1.0),Vector3.ZERO,0.0,NORMAL)
		shot.last=p
		if progress>=1.0:
			projectiles.remove_at(i)
			_arrive(shot)

# ---------------------------------------------------------------- impacts
func _arrive(shot:Dictionary) -> void:
	var p:Vector3=shot.b
	var direction:Vector3=shot.dir
	var surface:String=shot.surface
	if surface=="earth":surface="ground" # trenches and berms read as soil
	match String(shot["class"]):
		"small":
			match surface:
				"ground":bullet_strike(p,direction)
				"water":water_strike(p,0.35)
				"soft":soft_strike(p,direction)
				"armor":ricochet(p,direction,0.4)
				"structure":Explosions.masonry_hit(self,p,direction,0.2)
				"air":air_hit(p,0.4)
		"autocannon":
			match surface:
				"ground","soft":he_burst(p,direction,0.4)
				"water":water_strike(p,0.6)
				"armor":armor_hit(p,direction,0.6)
				"structure":
					flash(p,0.6,0.04,Color(1.0,0.8,0.5),0.0,NORMAL)
					Explosions.masonry_hit(self,p,direction,0.45)
				"air":air_hit(p,0.75)
				"sky":flak(p)
		"cannon","naval":
			match surface:
				"ground","soft":he_burst(p,direction,1.0)
				"water":water_strike(p,1.0)
				"armor":armor_hit(p,direction,1.0)
				"structure":Explosions.shell_on_masonry(self,p,direction,1.0)
				"air":air_hit(p,1.0)
		"atgun":
			match surface:
				"armor":Explosions.ap_strike(self,p,direction,1.0)
				"structure":
					Explosions.ap_strike(self,p,direction,0.7)
					Explosions.masonry_hit(self,p,direction,0.8)
				"ground","soft":Explosions.ap_ground(self,p,direction)
				"water":water_strike(p,0.7)
				"air","sky":air_hit(p,0.7)
		"missile","rocket":
			var k:=1.0 if shot["class"]=="missile" else 0.75
			match surface:
				"ground","soft":Explosions.missile_burst(self,p,direction,0.9*k,false)
				"water":water_strike(p,0.85*k)
				"armor":Explosions.missile_burst(self,p,direction,1.1*k,true)
				"structure":
					Explosions.missile_burst(self,p,direction,k,true)
					Explosions.masonry_hit(self,p,direction,0.8*k)
				"air","sky":air_hit(p,1.1*k)
		"fpv":
			Explosions.drone_strike(self,p,surface=="water",surface=="armor")

# Rifle round into soil: a small dirt spurt thrown back toward the shooter, no flash.
func bullet_strike(pos:Vector3, direction:Vector3) -> void:
	var p:=Vector3(pos.x,FLOOR+0.05,pos.z)
	var back:=-_flat(direction)
	smoke(p,back*rng.randf_range(0.5,1.1)+Vector3(0,rng.randf_range(1.8,2.6),0),0.14,0.55,0.55,Color(DUST,0.62),2.6,-2.5)
	for n in 2:
		debris(p,back*rng.randf_range(0.3,1.2)+_jitter(0.7,0.0)+Vector3(0,rng.randf_range(2.0,3.4),0),0.07,0.7,SOIL,false,false,OPTIONAL)

func soft_strike(pos:Vector3, direction:Vector3) -> void:
	smoke(pos+Vector3(0,-0.2,0),direction*0.5+Vector3(0,0.4,0),0.12,0.4,0.35,Color(DUST,0.45),3.0,0.0,0.0,OPTIONAL)

func ricochet(pos:Vector3, direction:Vector3, scale:float) -> void:
	flash(pos,0.35*scale+0.15,0.03,Color(1,0.86,0.6),0.0,NORMAL)
	sparks(pos,3,7.0,-direction*0.6+Vector3.UP*0.4,0.25,OPTIONAL)

func water_strike(pos:Vector3, scale:float) -> void:
	var p:=Vector3(pos.x,FLOOR,pos.z)
	if scale<0.5:
		# Thin bullet splash with a short-lived ring.
		for n in 3:spray(p,_jitter(0.3,0.0)+Vector3(0,rng.randf_range(2.6,3.6),0),0.1,0.2,0.75,0.0,OPTIONAL if n>0 else NORMAL)
		decal(p,FOAM_RING,0.2,0.9,0.6,Color(FOAM,0.6),OPTIONAL)
		return
	# Shell or missile: a tall collapsing column, white mist rolling out low, a fast foam ring and a slow one.
	var height:=sqrt(scale)
	var count:=int(round(6+8*scale))
	for n in count:
		var lift:=rng.randf_range(6.0,10.0)*height
		spray(p+_jitter(0.5*scale,0.0),_jitter(1.0*scale,0.0)+Vector3(0,lift,0),0.5*scale,1.5*scale,rng.randf_range(1.4,1.9),rng.randf()*0.08,ESSENTIAL if n<4 else NORMAL)
	for n in 5:
		var out:=Vector3.FORWARD.rotated(Vector3.UP,n*TAU/5+rng.randf_range(-0.3,0.3))
		smoke(p+Vector3(0,0.4,0)+out*0.6*scale,out*rng.randf_range(3.0,4.5)*scale+Vector3(0,0.3,0),0.8*scale,3.0*scale,rng.randf_range(1.6,2.2),Color(SPRAY_WHITE,0.5),2.4,0.0,0.12,NORMAL if n%2==0 else OPTIONAL)
	decal(p,FOAM_RING,0.8*scale,8.0*scale,0.5,Color(FOAM,0.8))
	decal(p,FOAM_RING,0.6*scale,5.0*scale,2.4,Color(FOAM,0.6),OPTIONAL if scale<0.6 else NORMAL)
	if scale>=0.6:shake(p,0.2*scale)

# High-explosive ground burst. Autocannon-sized rounds (scale < 0.6) stay a small flash and dirt kick; shells
# get the full layering around R = 2.5*scale (tank HE R = 2.5 m): flash, short fireball, a narrow dirt geyser
# that stalls and hangs (the read that separates HE from a missile), shock ring and dust skirt, clods in arcs,
# a lingering brown dust column and a scorch.
func he_burst(pos:Vector3, direction:Vector3, scale:float) -> void:
	var p:=Vector3(pos.x,maxf(pos.y,FLOOR)+0.1,pos.z)
	var g:=Vector3(pos.x,FLOOR,pos.z)
	var back:=-_flat(direction)*0.5
	if scale<0.6:
		flash(p+Vector3(0,0.2,0),1.4*scale+0.5,0.05,Color(1.0,0.8,0.48))
		for n in int(round(3+5*scale)):
			debris(g+Vector3(0,0.1,0),back+_jitter(1.6*scale,0.0)+Vector3(0,rng.randf_range(4.5,8.0)*sqrt(scale),0),rng.randf_range(0.1,0.18)*(0.6+scale*0.5),rng.randf_range(0.9,1.4),SOIL,false,false,NORMAL if n<3 else OPTIONAL)
		for n in int(round(2+3*scale)):
			smoke(g+Vector3(0,0.35,0)+_jitter(0.4*scale,0.0),Vector3(0,rng.randf_range(1.4,3.0)*scale,0)+_jitter(0.6),0.6*scale,rng.randf_range(2.4,3.2)*scale,rng.randf_range(1.6,2.6),Color(DUST.darkened(0.12),0.66),1.6,0.2,rng.randf()*0.08,NORMAL if n<2 else OPTIONAL)
		decal(g,DUST_RING,0.5,4.5*scale,0.5,Color(DUST,0.5))
		decal(g,SCORCH,1.4*scale+0.4,1.6*scale+0.5,3.0,Color(SCORCH_COLOR,0.55),OPTIONAL)
		mark(g,0.4+0.6*scale,Remains.CRATER)
		return
	var r:=2.5*scale
	var c:=p+Vector3(0,0.3*r,0)
	Explosions.core_flash(self,c,g,r,Color(1.0,0.88,0.62))
	fireball(c,Vector3(0,0.7*r,0),1.0*r,2.8*r,0.5,0.0,ESSENTIAL,1.8,0.9*r,Explosions.ball_tint(rng))
	ember(c,Vector3(0,0.6*r,0),1.4*r,0.22,Explosions.CORE_GLOW,ESSENTIAL)
	fireball(c+back*0.4*r,back*r+Vector3(0,0.8*r,0),0.5*r,1.7*r,0.42,0.02,NORMAL,2.4,0.8*r,Explosions.LOBE_EDGE*rng.randf_range(0.85,1.0))
	# Soil thrown through the flame: a dark brown lobe mixed into the fire layer.
	fireball(c+_jitter(0.3*r,0.0)+Vector3(0,0.2*r,0),Vector3(0,0.9*r,0)+_jitter(0.4*r,0.0),0.6*r,1.5*r,0.45,0.05,NORMAL,2.0,0.8*r,Color(0.42,0.31,0.22,0.95))
	# Geyser: dark soil puffs launched fast and nearly straight up, braking hard so they stall high.
	for n in 3:
		smoke(g+Vector3(0,0.3+n*0.3*r,0)+_jitter(0.12*r,0.0),back*0.6+Vector3(0,rng.randf_range(2.6,4.0)*r,0)+_jitter(0.2*r,0.0),0.5*r,rng.randf_range(1.0,1.3)*r,rng.randf_range(1.8,2.6),Color(SOIL.lerp(DUST,0.35),0.85),2.0,0.0,n*0.02,NORMAL if n==0 else OPTIONAL)
	Explosions.shockwave(self,g,r,DUST,4)
	Explosions.debris_arcs(self,g+Vector3(0,0.15,0),r,6,[SOIL,SOIL.darkened(0.25)],0,false)
	Explosions.column(self,g,r,2,Color(DUST.darkened(0.15),0.74),3.2)
	sparks(c,int(4*scale),11.0,Vector3.UP*0.6,0.5,OPTIONAL,1.6)
	Explosions.scorch(self,g,r,4.0,0.6,OPTIONAL)
	mark(g,1.2*r,Remains.SCORCH)
	mark(g,0.7*r,Remains.CRATER)
	shake(c,0.35*scale)

# Enemy mortar round landing (world_blast kind "mortar"); recipe in effects_explosions.gd.
func mortar_burst(pos:Vector3, water:bool=false) -> void:
	Explosions.mortar_burst(self,pos,water)

# Armour strike: hard white flash and a spark fan rebounding off the plate; heavy hits leave a dark puff.
func armor_hit(pos:Vector3, direction:Vector3, scale:float) -> void:
	flash(pos,0.7*scale+0.2,0.05,Color(1.0,0.92,0.72))
	sparks(pos,int(round(5+7*scale)),9.0*scale+3.0,-direction*0.7+Vector3.UP*0.5,0.5)
	smoke(pos,Vector3(0,0.8,0)+_jitter(0.4),0.35*scale,1.5*scale,1.4,Color(SOOT,0.6),1.4,0.4,0.04)
	if scale>=0.9:
		for n in 3:debris(pos,-direction*2.0+_jitter(2.0,0.0)+Vector3(0,rng.randf_range(2,4),0),0.08,1.0,METAL)

func air_hit(pos:Vector3, scale:float) -> void:
	flash(pos,0.9*scale+0.2,0.05,Color(1.0,0.86,0.58))
	sparks(pos,int(round(3+5*scale)),7.0,Vector3.ZERO,0.5)
	smoke(pos,_jitter(0.3),0.3*scale,1.3*scale,1.6,Color(SOOT,0.62),1.2,0.1,0.03)

# Proximity-fused autocannon round past an aircraft: small flash then a dark flak puff.
func flak(pos:Vector3) -> void:
	flash(pos,0.45,0.04,Color(1.0,0.8,0.5),0.0,NORMAL)
	smoke(pos,_jitter(0.2),0.25,0.95,1.8,Color(SOOT,0.58),1.0,0.0,0.03,OPTIONAL)

# ---------------------------------------------------------------- destruction
# Integration entry point for visible "destroyed" events. Waits for an in-flight killing round to land.
func destroyed(kind:String, pos:Vector3, water:bool=false) -> void:
	var wait:=_pending_arrival(pos)
	if wait>0.0:
		cue(wait,_destroy_now.bind(kind,pos,water))
	else:
		_destroy_now(kind,pos,water)

func _pending_arrival(pos:Vector3) -> float:
	var wait:=0.0
	for shot in projectiles:
		var b:Vector3=shot.b
		if shot.surface in ["ground","water","sky"]:continue
		if Vector2(b.x-pos.x,b.z-pos.z).length()<2.5:
			wait=maxf(wait,float(shot.delay)+float(shot.duration)-float(shot.age))
	return wait

func _destroy_now(kind:String, pos:Vector3, water:bool) -> void:
	if kind in INFANTRY:
		# A casualty is not an explosion: a little dust where the last soldier fell.
		for n in 2:smoke(Vector3(pos.x,0.25,pos.z)+_jitter(0.4,0.0),Vector3(0,0.3,0)+_jitter(0.3,0.0),0.3,0.9,0.9,Color(DUST,0.45),2.0)
		return
	if kind=="drone":
		air_burst(pos,0.45,false)
		return
	if kind=="helo":
		air_burst(pos,1.0,true,water)
		return
	if kind=="fpv_drone":
		Explosions.drone_strike(self,pos,water,false)
		return
	if kind in STRUCTURES:
		structure_collapse(pos)
		return
	if Explosions.FIELD_WORKS.has(kind):
		Explosions.field_work_destroyed(self,kind,pos,water)
		return
	if kind in VEHICLES:
		vehicle_explosion(Vector3(pos.x,maxf(pos.y,0.4),pos.z),1.15 if kind=="harvester" else 1.0,water,kind=="tank")
		return
	Explosions.generic_blast(self,pos,water)

# Staged vehicle kill around R = 5*scale (a tank kill is a 5 m fireball): white core flash, fireball lobes rolling
# up into black smoke, shock ring and dust skirt, hull fragments in arcs with smoke trails, a thick black column
# and a sustained wreck fire. Every hull vents a fuel flare; tanks then cook off their ammunition.
func vehicle_explosion(pos:Vector3, scale:float=1.0, water:bool=false, cook_off:bool=false) -> void:
	var r:=minf(5.0*scale,6.5)
	var g:=Vector3(pos.x,FLOOR,pos.z)
	var c:=pos+Vector3(0,0.25*r,0)
	Explosions.core_flash(self,c,g,r,Color(1.0,0.9,0.68))
	Explosions.fireball_layer(self,c,r,4,1.0,2)
	sparks(c,int(18*scale),3.0*r+2.0,Vector3.UP*0.8,1.1,ESSENTIAL,2.4)
	for n in 4:ember(c+_jitter(0.3*r,0.2*r),Vector3(0,rng.randf_range(2.0,4.0),0)+_jitter(1.5,0.0),rng.randf_range(0.5,0.8),rng.randf_range(1.4,2.2),Color(1.0,0.55,0.22,0.9),OPTIONAL)
	Explosions.debris_arcs(self,pos+Vector3(0,0.4,0),r,int(10*scale),[METAL,SOOT],3,not water)
	Explosions.smoke_handoff(self,c,r,3,Color(Explosions.BLACK_SMOKE,0.88),1.0,4.5)
	Explosions.column(self,g,r,6,Color(SOOT,0.86),5.5,ESSENTIAL)
	shake(c,scale)
	if water:
		water_strike(g,1.1*scale)
	else:
		Explosions.shockwave(self,g,r,DUST,8,ESSENTIAL)
		Explosions.scorch(self,g,r,7.0,0.72,ESSENTIAL)
		mark(g,1.0*r,Remains.BURN)
		Explosions.heat(self,g,r,3.0)
	# Wreck fire and a black column that keeps rising for roughly 10-14 s after the kill.
	add_emitter(g,11.0 if cook_off else 9.5,scale,water)
	cue(rng.randf_range(0.35,0.55),_cook_off.bind(pos+Vector3(0,0.6,0)+_jitter(0.5*scale,0.0)))
	if cook_off:
		for when in [rng.randf_range(0.8,1.1),rng.randf_range(1.5,2.1),rng.randf_range(2.6,3.4)]:
			cue(when,_cook_off.bind(pos+Vector3(0,0.7,0)+_jitter(0.4,0.0)))

# Secondary pop (fuel flare or ammunition cook-off), R = 1.2 m.
func _cook_off(pos:Vector3) -> void:
	var r:=1.2
	flash(pos,3.0*r,0.05,Color(1.0,0.8,0.45),0.0,NORMAL)
	bloom(pos,4.0*r,0.2,Color(1.0,0.55,0.22,0.3),OPTIONAL)
	fireball(pos+Vector3(0,0.2,0),Vector3(0,1.4*r,0)+_jitter(0.6,0.0),0.8*r,2.4*r,0.4,0.0,NORMAL,1.8,0.9*r,Explosions.LOBE_HOT.lerp(Explosions.LOBE_EDGE,rng.randf()))
	sparks(pos,8,10.0,Vector3.UP,0.8,NORMAL,1.8)
	smoke(pos,Vector3(0,1.4,0),0.8*r,2.4*r,2.6,Color(SOOT,0.7),1.0,0.6,0.12)
	shake(pos,0.12)

# Aircraft or UAV destroyed in flight (R = 3*scale): airburst, burning fragments falling, and a ground impact on
# landing.
func air_burst(pos:Vector3, scale:float, crash:bool, water:bool=false) -> void:
	var r:=3.0*scale
	flash(pos,3.0*r,0.07,Color(1.0,0.88,0.62))
	bloom(pos,2.2*r,0.1,Explosions.CORE,ESSENTIAL)
	fireball(pos,_jitter(0.3*r),1.0*r,2.6*r,rng.randf_range(0.6,0.8),0.0,ESSENTIAL,1.8,0.5*r,Explosions.ball_tint(rng))
	for n in (2 if scale>0.7 else 0):
		fireball(pos+_jitter(0.4*r),_jitter(1.0*r),0.5*r,1.7*r,rng.randf_range(0.45,0.6),n*0.03,NORMAL,2.4,0.4*r,Explosions.LOBE_EDGE*rng.randf_range(0.85,1.0))
	sparks(pos,int(round(14*scale))+2,4.0*r+3.0,Vector3.ZERO,0.9,NORMAL,1.0+scale)
	for n in int(round(8*scale))+2:
		debris(pos,_jitter(3.5*scale+0.5,0.0)+Vector3(0,rng.randf_range(0.5,3.5),0),rng.randf_range(0.12,0.3)*scale+0.06,rng.randf_range(2.0,3.0),METAL if n%2 else SOOT,false,n<3 and crash)
	for n in (5 if scale>0.7 else 2):
		smoke(pos+_jitter(0.4*r),_jitter(0.3*r),1.0*r,rng.randf_range(2.2,2.7)*r,rng.randf_range(3.0,4.2),Color(SOOT,0.8),0.8,0.12*r,0.15+n*0.05)
	shake(pos,0.5*scale)
	if crash:
		var fall:=sqrt(2.0*maxf(pos.y,0.5)/9.8)
		cue(fall,vehicle_explosion.bind(Vector3(pos.x,0.4,pos.z),0.7,water,false))

func structure_collapse(pos:Vector3) -> void:
	vehicle_explosion(Vector3(pos.x,0.8,pos.z),1.5,false,false)
	for n in 3:
		var offset:=Vector3.FORWARD.rotated(Vector3.UP,n*TAU/3+rng.randf())*rng.randf_range(1.2,2.6)
		cue(0.35+n*0.45,he_burst.bind(Vector3(pos.x,0.6,pos.z)+offset,Vector3.DOWN,0.8))
	for n in 8:
		smoke(Vector3(pos.x,0.6,pos.z)+_jitter(3.0,0.0),Vector3(0,0.8,0)+_jitter(1.2,0.0),2.4,6.5,rng.randf_range(3.5,5.0),Color(DUST.darkened(0.2),0.7),1.2,0.6,0.3+n*0.1)
	add_emitter(Vector3(pos.x,FLOOR,pos.z),14.0,1.4,false)

# Sustained wreck fire. A small fixed set; the oldest is replaced when full.
func add_emitter(pos:Vector3, duration:float, scale:float, water:bool) -> void:
	if emitters.size()>=EMITTER_CAPACITY:emitters.pop_front()
	emitters.append({"pos":pos,"age":0.0,"duration":duration,"scale":scale,"water":water,"fire_clock":0.4,"smoke_clock":0.6})

func _update_emitters(dt:float) -> void:
	for i in range(emitters.size()-1,-1,-1):
		var e:Dictionary=emitters[i]
		e.age+=dt
		var f:=float(e.age)/float(e.duration)
		if f>=1.0:
			emitters.remove_at(i)
			continue
		var p:Vector3=e.pos
		var k:float=e.scale
		e.fire_clock-=dt
		if f<0.6 and e.fire_clock<=0:
			e.fire_clock=rng.randf_range(0.16,0.28)
			ember(p+Vector3(0,0.6,0)+_jitter(0.6*k,0.2),Vector3(0,0.9,0),rng.randf_range(1.0,1.6)*k,rng.randf_range(0.22,0.34),Color(1.0,0.6,0.25,0.8),OPTIONAL)
			if rng.randf()<0.5:fireball(p+Vector3(0,0.55,0)+_jitter(0.5*k,0.1),Vector3(0,1.3,0),0.6*k,1.5*k,0.45,0.0,OPTIONAL)
			# Firelight flicker on the ground around the burning hull.
			if rng.randf()<0.35:bloom(p+Vector3(0,0.4,0),rng.randf_range(3.2,4.2)*k,0.22,Color(1.0,0.5,0.2,rng.randf_range(0.16,0.26)),OPTIONAL)
		e.smoke_clock-=dt
		if e.smoke_clock<=0:
			# Thick black column: large slow puffs that keep rising and spreading, greying as the fire dies.
			e.smoke_clock=lerpf(0.3,0.7,f)
			smoke(p+Vector3(0,1.2,0)+_jitter(0.5*k,0.1),Vector3(0,rng.randf_range(1.5,2.3),0),0.9*k,rng.randf_range(3.8,4.6)*k,rng.randf_range(3.8,5.0),Color(Explosions.BLACK_SMOKE.lerp(GREY_SMOKE,f),0.84*(1.0-f*0.45)),0.8,1.1,0.0,OPTIONAL)

# ---------------------------------------------------------------- movement and damage presentation
func dust(pos:Vector3, direction:Vector2, sea:bool) -> void:
	var forward:=Vector3(direction.x,0,direction.y)
	if forward.length_squared()<0.0001:forward=Vector3.FORWARD
	forward=forward.normalized()
	var side:=forward.cross(Vector3.UP)
	if sea:
		# Stern wash and a light bow spray.
		decal(pos-forward*1.9,FOAM_RING,0.7,2.4,1.4,Color(FOAM,0.55),OPTIONAL)
		for s in [-1,1]:spray(Vector3(pos.x,FLOOR+0.05,pos.z)+forward*1.7+side*s*0.4,side*s*1.2+Vector3(0,1.3,0),0.12,0.3,0.5,0.0,OPTIONAL)
		return
	for s in [-1,1]:
		smoke(Vector3(pos.x,0.2,pos.z)-forward*1.7+side*s*0.75,-forward*0.4+Vector3(0,0.35,0)+_jitter(0.15,0.0),0.35,1.5,1.1,Color(DUST,0.3),1.8,0.0,0.0,OPTIONAL)

# hp_fraction below 0.4 smokes grey; below 0.2 adds dark smoke and flickering fire.
# Once a simulation is bound the live-damage emitters own this (capped and view-faded); the call is ignored.
func damage_smoke(pos:Vector3, hp_fraction:float) -> void:
	if live_bound:return
	var severe:=hp_fraction<0.2
	smoke(pos,Vector3(0.1,0.9,0.05),0.35,1.5 if severe else 1.1,1.6 if severe else 1.2,Color(SOOT if severe else GREY_SMOKE,0.5 if severe else 0.38),1.0,0.5,0.0,OPTIONAL)
	if severe and rng.randf()<0.4:ember(pos+Vector3(0,-0.2,0),Vector3(0,0.5,0),0.5,0.2,Color(1.0,0.6,0.25,0.6),OPTIONAL)

# ---------------------------------------------------------------- live vehicle damage
# Persistent cues on vehicles that are damaged but still in play, polled from the simulation (battle.gd's `sim`
# and `nodes`, found through the parent; tests call watch()). Every LIVE_SCAN s a scan keeps at most LIVE_CAPACITY
# emitters, fires and sinking hulls first and then nearest the view centre. Each emitter spawns a few OPTIONAL
# particles from the shared pools on its own clocks (no nodes; under load the pools shed them first), slower and
# fainter towards the view edge or when zoomed far out. Burning hulls vent flame and black smoke from the engine
# deck until the fire is out; other damage trails thin grey smoke; flooding hulls throw spray at the waterline and
# list (visuals.gd damage_pose); crashing gunships trail smoke and wrecked ones smoke for LIVE_WRECK_SECONDS.
const LIVE_CAPACITY:=12
const LIVE_SCAN:=0.2
const LIVE_WRECK_SECONDS:=30.0
const LIVE_KINDS:=["tank","aa","boat","helo","harvester"]
const LIVE_DAMAGED:=0
const LIVE_FLOOD:=1
const LIVE_WRECK:=2
const LIVE_CRASH:=3
const LIVE_FIRE:=4
# Ranking head start in metres of view distance.
const LIVE_RANK:=[0.0,40.0,20.0,60.0,60.0]
# Below this ortho size emitters run at full rate; zoomed further out they thin to LIVE_MIN_ZOOM.
const LIVE_FULL_ZOOM:=90.0
const LIVE_MIN_ZOOM:=0.35
var _visuals_script:GDScript

# Binds a simulation explicitly (tests and hosts without a `sim` property); nodes maps unit id to its root node.
func watch(sim, nodes:Dictionary={}) -> void:
	live_sim=sim
	live_nodes=nodes

func _live_host():
	if live_sim!=null:return live_sim
	var host:=get_parent()
	if host==null:return null
	var sim=host.get("sim")
	if not (sim is Object) or not sim.has_method("alive"):return null
	var nodes=host.get("nodes")
	if nodes is Dictionary:live_nodes=nodes
	return sim

# 1 inside the view, falling to 0 just beyond its edge, times the zoom LOD.
func view_fade(pos:Vector3) -> float:
	if view_radius==INF:return view_zoom
	var d:=Vector2(pos.x-view_focus.x,pos.z-view_focus.z).length()
	return (1.0-smoothstep(view_radius*0.85,view_radius*1.3,d))*view_zoom

func _live_mode(sim, u:Dictionary) -> int:
	if not sim.alive(u):
		if u.kind!="helo" or not u.get("wrecked",false):return -1
		if not _live_wreck_seen.has(u.id):_live_wreck_seen[u.id]=time
		return LIVE_WRECK if time-float(_live_wreck_seen[u.id])<LIVE_WRECK_SECONDS else -1
	if not u.visible:return -1
	if float(u.get("fire_until",-1.0))>float(sim.time):return LIVE_FIRE
	if u.has("crash"):return LIVE_CRASH
	if float(u.get("flood",0.0))>0.0:return LIVE_FLOOD
	if not (u.kind in LIVE_KINDS or u.has("crew")):return -1
	if float(u.hp)<float(u.max_hp)*0.4 or u.get("mobility_kill",false) or u.get("firepower_kill",false) or int(u.get("crew",0))<int(u.get("crew_full",0)):return LIVE_DAMAGED
	return -1

func _live_scan(sim) -> void:
	var ranked:Array=[]
	_live_tilt_units.clear()
	for u in sim.units:
		if not u.members.is_empty() or u.get("structure",false):continue
		if sim.alive(u) and (u.has("crash") or float(u.get("flood",0.0))>0.0):_live_tilt_units.append(u)
		var mode:=_live_mode(sim,u)
		if mode<0:continue
		var fade:=view_fade(Vector3(u.pos.x,0,u.pos.y))
		if fade<=0.01:continue
		var d:=Vector2(u.pos.x-view_focus.x,u.pos.y-view_focus.z).length() if view_radius!=INF else 0.0
		ranked.append([d-float(LIVE_RANK[mode]),u,mode,fade])
	if ranked.size()>LIVE_CAPACITY:
		ranked.sort_custom(func(a,b):return a[0]<b[0])
		ranked.resize(LIVE_CAPACITY)
	var previous:={}
	for e in live_emitters:previous[e.u.id]=e
	live_emitters.clear()
	for entry in ranked:
		var u:Dictionary=entry[1]
		var e:Dictionary=previous.get(u.id,{"u":u,"puff":rng.randf_range(0.0,0.3),"flame":0.0,"spray":0.0})
		e.u=u
		e.mode=entry[2]
		e.fade=entry[3]
		live_emitters.append(e)

func _update_live(dt:float) -> void:
	var sim=_live_host()
	live_bound=sim!=null
	if sim==null:
		live_emitters.clear()
		return
	_live_clock-=dt
	if _live_clock<=0.0:
		_live_clock=LIVE_SCAN
		_live_scan(sim)
	_update_live_tilts()
	if live_paused or _host_paused():return # particles already out finish; no new ones while the battle is paused
	for e in live_emitters:_live_emit(sim,e,dt)

# battle.gd's pause (and help overlay) freezes the sim; its benchmark runs regardless.
func _host_paused() -> bool:
	var host:=get_parent()
	if host==null or host.get("benchmark")==true:return false
	return host.get("paused")==true or host.get("show_help")==true

# Damage pose on flooding and falling hulls; roots that no longer qualify are levelled once.
func _update_live_tilts() -> void:
	if _live_tilt_units.is_empty() and _live_tilts.is_empty():return
	var posed:={}
	for u in _live_tilt_units:
		var root=live_nodes.get(u.id)
		if not is_instance_valid(root) or not (root is Node3D) or root.has_meta("sink_from"):continue # battle.gd sinks it
		if _visuals_script==null:_visuals_script=load("res://scripts/visuals.gd")
		_visuals_script.apply_damage_pose(root,u)
		posed[u.id]=root
	_reset_live_tilts(posed)
	_live_tilts=posed

func _reset_live_tilts(keep:Dictionary) -> void:
	for id in _live_tilts:
		if keep.has(id):continue
		var root=_live_tilts[id]
		if is_instance_valid(root) and not root.has_meta("sink_from"):_visuals_script.apply_damage_pose(root,{}) # levels the root and its selection ring
	if keep.is_empty():_live_tilts={}

func _live_emit(sim, e:Dictionary, dt:float) -> void:
	var u:Dictionary=e.u
	var definition:Dictionary=sim.definitions.get(u.kind,{})
	var radius:=float(definition.get("radius",1.5))
	var facing:Vector2=u.facing if u.facing.length_squared()>0.0001 else Vector2.UP
	var back:=-Vector3(facing.x,0,facing.y).normalized()
	var mode:int=e.mode
	var fade:float=e.fade
	var alpha:=0.45+0.55*fade
	var slow:=1.0/maxf(fade,0.25)
	var height:=0.0 if mode==LIVE_WRECK else float(u.get("altitude",definition.get("altitude",0.0)))
	# Engine deck: the rear third of the hull, just above the deck.
	var deck:=Vector3(u.pos.x,height+0.45*radius+0.4,u.pos.y)+back*0.35*radius
	e.puff-=dt
	match mode:
		LIVE_FIRE:
			if float(u.get("fire_until",-1.0))<=float(sim.time):return # out since the last scan
			e.flame-=dt
			if e.flame<=0.0:
				e.flame=rng.randf_range(0.16,0.26)*slow
				if rng.randf()<0.6:fireball(deck+_jitter(0.25*radius,0.05),Vector3(0,1.1,0),0.3*radius,0.85*radius,0.42,0.0,OPTIONAL,2.0,0.9)
				else:ember(deck+_jitter(0.25*radius,0.05),Vector3(0,0.9,0),0.55*radius,0.28,Color(1.0,0.6,0.25,0.8*alpha),OPTIONAL)
				if rng.randf()<0.25:bloom(deck,2.4*radius,0.22,Color(1.0,0.5,0.2,0.2*alpha),OPTIONAL)
			if e.puff<=0.0:
				e.puff=rng.randf_range(0.28,0.38)*slow
				smoke(deck+Vector3(0,0.35,0)+_jitter(0.2*radius,0.05),Vector3(0,rng.randf_range(1.3,1.9),0),0.4*radius,rng.randf_range(1.7,2.1)*radius,rng.randf_range(2.8,3.6),Color(Explosions.BLACK_SMOKE,0.78*alpha),0.9,0.9,0.0,OPTIONAL)
		LIVE_CRASH:
			if e.puff<=0.0:
				var spin:bool=u.get("crash","")=="spin"
				e.puff=(0.08 if spin else 0.14)*slow
				smoke(deck+_jitter(0.15,0.1),Vector3(0,0.3,0),0.35,1.6 if spin else 1.2,1.8,Color(SOOT if spin else GREY_SMOKE,(0.72 if spin else 0.5)*alpha),1.2,0.3,0.0,OPTIONAL)
				if spin and rng.randf()<0.3:ember(deck,Vector3(0,0.4,0),0.5,0.2,Color(1.0,0.6,0.25,0.7*alpha),OPTIONAL)
		LIVE_FLOOD:
			if float(u.get("flood_rate",0.0))>0.0:
				e.spray-=dt
				if e.spray<=0.0:
					e.spray=rng.randf_range(0.24,0.34)*slow
					var side:=Vector3(-back.z,0,back.x)*(1.0 if rng.randf()<0.5 else -1.0)
					var waterline:=Vector3(u.pos.x,FLOOR+0.05,u.pos.y)+back*rng.randf_range(-0.3,0.4)*radius+side*0.45*radius
					spray(waterline,side*rng.randf_range(0.6,1.1)+Vector3(0,rng.randf_range(0.9,1.4),0),0.1,0.32,0.5,0.0,OPTIONAL)
					if rng.randf()<0.2:decal(waterline,FOAM_RING,0.6,1.6*radius,1.4,Color(FOAM,0.45*alpha),OPTIONAL)
			if e.puff<=0.0:
				e.puff=rng.randf_range(0.55,0.7)*slow
				smoke(deck,Vector3(0.1,0.8,0.05),0.3,1.1,1.3,Color(GREY_SMOKE,0.3*alpha),1.0,0.45,0.0,OPTIONAL)
		LIVE_WRECK:
			if e.puff<=0.0:
				var calm:=clampf((time-float(_live_wreck_seen.get(u.id,time)))/LIVE_WRECK_SECONDS,0.0,1.0)
				var quiet:bool=u.get("lost_quiet",false) # forced landing: no fire, lighter smoke
				e.puff=rng.randf_range(0.45,0.6)*slow*(1.0+calm)
				smoke(Vector3(u.pos.x,0.6,u.pos.y)+_jitter(0.3*radius,0.05),Vector3(0,rng.randf_range(0.9,1.3),0),0.4,rng.randf_range(1.6,2.2),rng.randf_range(2.2,3.0),Color(GREY_SMOKE if quiet else SOOT,(0.42 if quiet else 0.62)*alpha*(1.0-0.6*calm)),0.9,0.7,0.0,OPTIONAL)
		_:
			if e.puff<=0.0:
				var severe:=float(u.hp)<float(u.max_hp)*0.2
				e.puff=(0.26 if severe else 0.42)*slow
				smoke(deck,Vector3(0.1,0.85,0.05),0.3,1.4 if severe else 1.0,1.6 if severe else 1.2,Color(SOOT if severe else GREY_SMOKE,(0.48 if severe else 0.32)*alpha),1.0,0.45,0.0,OPTIONAL)
				if severe and rng.randf()<0.4:ember(deck,Vector3(0,0.5,0),0.5,0.2,Color(1.0,0.6,0.25,0.6*alpha),OPTIONAL)

# ---------------------------------------------------------------- legacy entry points
# Kept so current callers keep working until integration moves to fire()/destroyed()/damage_smoke().
func emit(pos:Vector3, velocity:Vector3, size:float, life:float, color:Color, growth:float=0.0, gravity:float=0.0, delay:float=0.0) -> void:
	volume.spawn(pos,velocity,SMOKE,size,size+growth*life,life,color,0.0 if gravity!=0.0 else 0.6,gravity,delay,OPTIONAL,WIND,rng.randf()*TAU,rng.randf_range(-0.6,0.6),rng.randf())

# The old caller only knows heavy/light here, so the signature is deferred until projectile() names the weapon.
func muzzle(pos:Vector3, direction:Vector3, heavy:bool) -> void:
	if pending_muzzles.size()>=8:_flush_muzzles()
	pending_muzzles.append({"pos":pos,"dir":direction.normalized(),"heavy":heavy})

# Old callers pass a muzzle point already pushed out along the barrel; fire() re-applies the profile barrel,
# so step back by it to keep the authored muzzle point. Returns the presentation travel time.
func projectile(a:Vector3, b:Vector3, kind:String, water:bool, hit:bool=true) -> float:
	for i in pending_muzzles.size():
		if pending_muzzles[i].pos.is_equal_approx(a):
			pending_muzzles.remove_at(i)
			break
	var profile:Dictionary=WEAPONS.get(kind,WEAPONS.rifle)
	var direction:=(b-a).normalized() if a.distance_squared_to(b)>0.0001 else Vector3.FORWARD
	return fire(kind,a-direction*float(profile.barrel),b,hit,water,"",is_water_at(a))

func _flush_muzzles() -> void:
	for pending in pending_muzzles:
		_muzzle("tank" if pending.heavy else "rifle",pending.pos,pending.dir,0,is_water_at(pending.pos))
	pending_muzzles.clear()

func impact(pos:Vector3, heavy:bool, water:bool=false) -> void:
	if water:water_strike(pos,1.0 if heavy else 0.35)
	elif heavy:he_burst(pos,Vector3.DOWN,1.0)
	else:bullet_strike(pos,Vector3.DOWN)

# Kind-less vehicle kill; still waits for a killing round in flight. Prefer destroyed(kind,...).
func explosion(pos:Vector3, water:bool=false) -> void:
	destroyed("",pos,water)

# ---------------------------------------------------------------- frame update
func _process(dt:float) -> void:
	time+=dt
	if not pending_muzzles.is_empty():_flush_muzzles()
	var due:Array[Callable]=[]
	for i in range(cues.size()-1,-1,-1):
		if float(cues[i].at)<=time:
			due.push_front(cues[i].action)
			cues.remove_at(i)
	for action in due:action.call()
	_update_emitters(dt)
	_update_projectiles(dt)
	if not shake_age.is_empty():_update_shake(dt)
	remains.step(dt)
	var drift:=wind+BREEZE
	_sync_view()
	_update_live(dt)
	volume.step(dt,drift,self)
	glow.step(dt,drift,self)
	ground.step(dt,drift,self)

func stats() -> Dictionary:
	return {"volume":volume.live,"glow":glow.live,"ground":ground.live,"shakes":shake_age.size(),"remains":remains.stats(),"visible":volume.visible_count+glow.visible_count+ground.visible_count,"projectiles":projectiles.size(),"cues":cues.size(),"emitters":emitters.size(),"live_emitters":live_emitters.size(),"dropped":volume.dropped+glow.dropped+ground.dropped,"recycled":volume.recycled+glow.recycled+ground.recycled,"capacity":{"volume":VOLUME_CAPACITY,"glow":GLOW_CAPACITY,"ground":GROUND_CAPACITY,"projectiles":PROJECTILE_CAPACITY,"cues":CUE_CAPACITY,"emitters":EMITTER_CAPACITY,"live_emitters":LIVE_CAPACITY}}

func clear() -> void:
	volume.clear();glow.clear();ground.clear()
	projectiles.clear();cues.clear();emitters.clear();pending_muzzles.clear()
	shake_pos.clear();shake_strength.clear();shake_age.clear()
	remains.clear()
	live_emitters.clear()
	_live_wreck_seen.clear()
	_reset_live_tilts({})
