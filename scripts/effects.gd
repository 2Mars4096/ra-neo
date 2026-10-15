class_name BattleEffects
extends Node3D

# Cosmetic combat presentation only: nothing here feeds damage, hit resolution or simulation trajectories.
# Three fixed MultiMesh pools (volume smoke/debris/spray/fire, additive glow, flat ground marks), a bounded
# projectile queue, a bounded cue list for staged timing and a few sustained wreck-fire emitters.

const VOLUME_CAPACITY:=480
const GLOW_CAPACITY:=256
const GROUND_CAPACITY:=48
const CAPACITY:=VOLUME_CAPACITY+GLOW_CAPACITY+GROUND_CAPACITY
const PROJECTILE_CAPACITY:=128
const CUE_CAPACITY:=96
const EMITTER_CAPACITY:=12
const FLOOR:=0.03
const DECAL_HEIGHT:=0.045
const BREEZE:=Vector3(0.28,0,0.12)
# Fixed battle camera direction (offset 26,64,46 from its focus); replaced by the live camera when present.
static var DEFAULT_VIEW:=Basis.looking_at(-Vector3(26,64,46),Vector3.UP)
# Cards and streaks never shrink below this many screen pixels, so distant flashes still read.
const MIN_PIXELS:=2.0

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
}
const TARGET_SURFACE:={"rifle":"soft","atgm":"soft","tank":"armor","aa":"armor","boat":"armor","harvester":"armor","helo":"air","drone":"air","hq":"structure","power":"structure","refinery":"structure","barracks":"structure","factory":"structure"}
const STRUCTURES:=["hq","power","refinery","barracks","factory"]

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
	var buffer:=PackedFloat32Array()
	var live:=0
	var visible_count:=0
	var dropped:=0
	var recycled:=0
	var steal_cursor:=0
	var bounds:=AABB()
	var limit:=AABB()
	var front_kind:=-1

	func _init(count:int, is_flat:bool) -> void:
		capacity=count
		flat=is_flat
		pos.resize(count);vel.resize(count);axis.resize(count);color.resize(count)
		age.resize(count);life.resize(count);size0.resize(count);size1.resize(count);width.resize(count)
		drag.resize(count);gravity.resize(count);rot.resize(count);spin.resize(count);delay.resize(count)
		timer.resize(count);variant.resize(count);kind.resize(count);flags.resize(count)
		buffer.resize(count*STRIDE)
		for i in count:free_slots.append(count-1-i)
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
		return slot

	func spawn(p:Vector3, v:Vector3, k:int, s0:float, s1:float, duration:float, c:Color, drag_rate:float, fall:float, wait:float, priority:int, bits:int, turn:float, turn_rate:float, variety:float) -> int:
		var i:=alloc(priority)
		if i<0:return -1
		pos[i]=p;vel[i]=v;kind[i]=k;size0[i]=s0;size1[i]=s1
		life[i]=maxf(duration,0.0001);age[i]=0.0;color[i]=c;drag[i]=drag_rate;gravity[i]=fall
		delay[i]=maxf(wait,0.0);flags[i]=bits|FRESH;rot[i]=turn;spin[i]=turn_rate;variant[i]=variety
		timer[i]=0.0;axis[i]=Vector3.ZERO;width[i]=0.0
		return i

	func kill(i:int) -> void:
		life[i]=0.0
		free_slots.append(i)
		live-=1

	func clear() -> void:
		for i in capacity:
			if life[i]>0.0:kill(i)
		visible_count=0
		multimesh.visible_instance_count=0
		if instance:instance.visible=false

	func step(dt:float, wind:Vector3, owner:Object) -> void:
		var n:=0
		var f:=0
		var lo:=Vector3(INF,INF,INF)
		var hi:=Vector3(-INF,-INF,-INF)
		var margin:=0.0
		for i in capacity:
			var duration:=life[i]
			if duration<=0.0:continue
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
				kill(i)
				continue
			age[i]=a
			var p:=pos[i]
			if h>0.0:
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
				if bits&TRAIL:
					timer[i]+=h
					if timer[i]>=0.07:
						timer[i]=0.0
						owner.call("_trail_puff",p,1.0-a/duration)
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
				var x_axis:=right*s
				var y_axis:=up*s
				if spin_cards:
					var c:=cos(rot[i])
					var sn:=sin(rot[i])
					x_axis=(right*c+up*sn)*s
					y_axis=(up*c-right*sn)*s
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
var muted:=false
var flashes:=AudioStreamPlayer.new()
var explosion_audio:=AudioStreamPlayer.new()
var shot_stream:AudioStreamWAV
var explosion_stream:AudioStreamWAV
var sound_clock:=0.0
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
var shore_x:=INF
# Legacy muzzle() calls wait here for the paired projectile() that names the weapon.
var pending_muzzles:Array[Dictionary]=[]

func _init() -> void:
	rng.seed=814
	# Instances in one MultiMesh draw in buffer order; flames stay in front of the soot they feed.
	volume.front_kind=FIRE
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

func reseed(value:int) -> void:
	rng.seed=value
	tracer_counts.clear()

# Call once after the terrain exists: effects.set_world_bounds(sim.terrain.world_size, sim.terrain.shore_x).
# Culling boxes still follow live content; this caps them to the padded map and lets legacy calls infer water.
func set_world_bounds(world_size:Vector2, shore:float=INF) -> void:
	world_box=AABB(Vector3(-8,-2,-8),Vector3(world_size.x+16,62,world_size.y+16))
	shore_x=shore
	for pool in [volume,glow,ground]:pool.limit=world_box

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
	flashes.volume_db=-23
	explosion_audio.volume_db=-18
	shot_stream=make_sound(0.13,100)
	explosion_stream=make_sound(0.65,48)
	flashes.stream=shot_stream
	explosion_audio.stream=explosion_stream

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

func make_sound(duration:float, frequency:float) -> AudioStreamWAV:
	var stream:=AudioStreamWAV.new()
	stream.format=AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate=22050
	var count:=int(22050*duration)
	var data:=PackedByteArray()
	data.resize(count*2)
	var filtered:=0.0
	for i in count:
		var t:=float(i)/count
		filtered=lerpf(filtered,rng.randf_range(-1,1),0.12)
		var value:float=(filtered*0.7+sin(i*TAU*frequency/22050.0)*0.3)*pow(1-t,2)*20000
		data.encode_s16(i*2,int(value))
	stream.data=data
	return stream

func _audible() -> bool:
	return not muted and DisplayServer.get_name()!="headless" and is_inside_tree()

func _shot_sound(weapon_class:String) -> void:
	if not _audible():return
	var heavy:=weapon_class in ["cannon","naval"]
	if sound_clock>0 and not heavy:return
	flashes.pitch_scale={"small":1.4,"autocannon":1.15,"cannon":0.6,"naval":0.7,"missile":0.85,"rocket":1.0}.get(weapon_class,1.0)
	flashes.play()
	sound_clock=0.12

func _boom(scale:float) -> void:
	if not _audible():return
	explosion_audio.pitch_scale=clampf(1.25-scale*0.3,0.7,1.4)
	explosion_audio.play()

# ---------------------------------------------------------------- primitives
func _jitter(radius:float, vertical:float=-1.0) -> Vector3:
	return Vector3(rng.randf_range(-radius,radius),rng.randf_range(-radius,radius) if vertical<0 else rng.randf_range(-vertical,vertical),rng.randf_range(-radius,radius))

func _flat(direction:Vector3) -> Vector3:
	var f:=Vector3(direction.x,0,direction.z)
	return f.normalized() if f.length_squared()>0.0001 else Vector3.FORWARD

func smoke(pos:Vector3, vel:Vector3, size0:float, size1:float, life:float, col:Color, drag:float=1.5, lift:float=0.0, delay:float=0.0, priority:int=NORMAL) -> int:
	return volume.spawn(pos,vel,SMOKE,size0,size1,life,col,drag,-lift,delay,priority,WIND,rng.randf()*TAU,rng.randf_range(-0.6,0.6),rng.randf())

func fireball(pos:Vector3, vel:Vector3, size0:float, size1:float, life:float, delay:float=0.0, priority:int=ESSENTIAL) -> int:
	return volume.spawn(pos,vel,FIRE,size0,size1,life,Color(1,1,1,1),2.2,-1.2,delay,priority,0,rng.randf()*TAU,rng.randf_range(-1.2,1.2),rng.randf())

func debris(pos:Vector3, vel:Vector3, size:float, life:float, col:Color, bounce:bool=true, trail:bool=false, priority:int=NORMAL) -> int:
	var bits:=(BOUNCE if bounce else GROUND_KILL)|(TRAIL if trail else 0)
	return volume.spawn(pos,vel,DEBRIS,size,size,life,col,0.0,9.8,0.0,priority,bits,rng.randf()*TAU,rng.randf_range(-9,9),rng.randf())

func spray(pos:Vector3, vel:Vector3, size0:float, size1:float, life:float, delay:float=0.0, priority:int=NORMAL) -> int:
	return volume.spawn(pos,vel,SPRAY,size0,size1,life,SPRAY_WHITE,0.35,9.8,delay,priority,GROUND_KILL,rng.randf()*TAU,rng.randf_range(-1,1),rng.randf())

func flash(pos:Vector3, size:float, life:float, col:Color=FLAME, delay:float=0.0, priority:int=ESSENTIAL) -> int:
	return glow.spawn(pos,Vector3.ZERO,FLASH,size,size*1.15,life,col,0.0,0.0,delay,priority,0,rng.randf()*TAU,0.0,rng.randf())

func ember(pos:Vector3, vel:Vector3, size:float, life:float, col:Color=FLAME, priority:int=NORMAL) -> int:
	return glow.spawn(pos,vel,EMBER,size,size*0.7,life,col,1.5,-0.6,0.0,priority,0,0.0,0.0,rng.randf())

# Axial glow: tracer bodies, flame tongues and sparks. Position is the streak centre.
func streak(pos:Vector3, direction:Vector3, length:float, thickness:float, life:float, col:Color, vel:Vector3=Vector3.ZERO, fall:float=0.0, priority:int=NORMAL, delay:float=0.0) -> int:
	var bits:=AXIAL|(ALIGN if vel!=Vector3.ZERO else 0)|(GROUND_KILL if fall>0 else 0)
	var i:=glow.spawn(pos,vel,STREAK,length,length*0.6 if vel!=Vector3.ZERO else length,life,col,0.0,fall,delay,priority,bits,0.0,0.0,rng.randf())
	if i>=0:
		glow.axis[i]=direction.normalized() if direction.length_squared()>0.0001 else Vector3.RIGHT
		glow.width[i]=thickness
	return i

func sparks(pos:Vector3, count:int, speed:float, bias:Vector3, life:float, priority:int=NORMAL) -> void:
	for n in count:
		var v:=(_jitter(1.0).normalized()+bias).normalized()*rng.randf_range(speed*0.5,speed)
		if v.y<0:v.y=-v.y*0.5
		streak(pos,v,rng.randf_range(0.25,0.45),0.045,rng.randf_range(life*0.5,life),SPARK,v,9.8,priority)

func decal(pos:Vector3, kind:int, size0:float, size1:float, life:float, col:Color, priority:int=NORMAL) -> int:
	return ground.spawn(Vector3(pos.x,DECAL_HEIGHT+(0.004 if kind!=SCORCH else 0.0),pos.z),Vector3.ZERO,kind,size0,size1,life,col,0.0,0.0,0.0,priority,0,rng.randf()*TAU,0.0,rng.randf())

func cue(delay:float, action:Callable) -> bool:
	if cues.size()>=CUE_CAPACITY:
		dropped_cues+=1
		return false
	cues.append({"at":time+delay,"action":action})
	return true

func _trail_puff(pos:Vector3, strength:float) -> void:
	smoke(pos,Vector3(0,0.4,0),0.18,0.7*strength+0.25,0.9,Color(SOOT,0.5),1.8,0.0,0.0,OPTIONAL)

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
	_shot_sound(weapon_class)
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
		"cannon","naval":
			var heavy:=weapon_class=="cannon"
			var k:=1.0 if heavy else 0.75
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
					var thickness:float={"small":0.05,"autocannon":0.075,"cannon":0.09,"naval":0.08}.get(weapon_class,0.05)
					var col:=TRACER if weapon_class!="cannon" else Color(1.0,0.78,0.5)
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
	match String(shot["class"]):
		"small":
			match surface:
				"ground":bullet_strike(p,direction)
				"water":water_strike(p,0.35)
				"soft":soft_strike(p,direction)
				"armor","structure":ricochet(p,direction,0.4)
				"air":air_hit(p,0.4)
		"autocannon":
			match surface:
				"ground","soft":he_burst(p,direction,0.4)
				"water":water_strike(p,0.6)
				"armor","structure":armor_hit(p,direction,0.6)
				"air":air_hit(p,0.75)
				"sky":flak(p)
		"cannon","naval":
			match surface:
				"ground","soft":he_burst(p,direction,1.0)
				"water":water_strike(p,1.0)
				"armor":armor_hit(p,direction,1.0)
				"structure":armor_hit(p,direction,1.0);he_burst(p,direction,0.6)
				"air":air_hit(p,1.0)
		"missile","rocket":
			var k:=1.0 if shot["class"]=="missile" else 0.75
			match surface:
				"ground","soft":he_burst(p,direction,0.9*k)
				"water":water_strike(p,0.85*k)
				"armor","structure":armor_hit(p,direction,1.2*k)
				"air","sky":air_hit(p,1.1*k)

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
	# Shell or missile: a tall collapsing column, mist and a widening foam ring.
	var height:=sqrt(scale)
	var count:=int(round(6+8*scale))
	for n in count:
		var lift:=rng.randf_range(6.0,10.0)*height
		spray(p+_jitter(0.35*scale,0.0),_jitter(0.7*scale,0.0)+Vector3(0,lift,0),0.3*scale,0.85*scale,rng.randf_range(1.4,1.9),rng.randf()*0.08,ESSENTIAL if n<4 else NORMAL)
	for n in 3:
		smoke(p+Vector3(0,0.5,0)+_jitter(0.5),Vector3(0,rng.randf_range(0.8,1.6),0)+_jitter(0.4),0.6*scale,2.2*scale,rng.randf_range(1.3,1.8),Color(SPRAY_WHITE,0.42),1.8,0.0,0.2)
	decal(p,FOAM_RING,0.6*scale,4.2*scale,1.8,Color(FOAM,0.75))
	if scale>=0.6:decal(p,FOAM_RING,0.4,2.6*scale,2.8,Color(FOAM,0.5),OPTIONAL)

# High-explosive ground burst: brief flash, dirt fountain, dust column, blast ring and a scorch.
func he_burst(pos:Vector3, direction:Vector3, scale:float) -> void:
	var p:=Vector3(pos.x,maxf(pos.y,FLOOR)+0.1,pos.z)
	var g:=Vector3(pos.x,FLOOR,pos.z)
	flash(p+Vector3(0,0.2,0),1.1*scale+0.4,0.06,Color(1.0,0.8,0.48))
	if scale>=0.6:fireball(p+Vector3(0,0.3,0),Vector3(0,1.5,0),0.6*scale,1.6*scale,0.25)
	var back:=-_flat(direction)*0.5
	for n in int(round(3+5*scale)):
		debris(g+Vector3(0,0.1,0),back+_jitter(1.6*scale,0.0)+Vector3(0,rng.randf_range(4.5,8.0)*sqrt(scale),0),rng.randf_range(0.08,0.16)*(0.6+scale*0.5),rng.randf_range(0.9,1.4),SOIL,false,false,NORMAL if n<3 else OPTIONAL)
	for n in int(round(2+3*scale)):
		smoke(g+Vector3(0,0.35,0)+_jitter(0.4*scale,0.0),Vector3(0,rng.randf_range(1.4,3.0)*scale,0)+_jitter(0.6),0.5*scale,rng.randf_range(1.9,2.7)*scale,rng.randf_range(1.6,2.6),Color(DUST.darkened(0.12),0.62),1.6,0.2,rng.randf()*0.08,NORMAL if n<2 else OPTIONAL)
	if scale>=0.6:sparks(p,int(4*scale),8.0,Vector3.UP*0.6,0.4,OPTIONAL)
	decal(g,DUST_RING,0.5,4.0*scale,0.5,Color(DUST,0.5))
	decal(g,SCORCH,1.4*scale+0.4,1.6*scale+0.5,30.0,Color(SCORCH_COLOR,0.55),OPTIONAL)

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
	if kind in ["rifle","atgm"]:
		# A casualty is not an explosion: a little dust where the last soldier fell.
		for n in 2:smoke(Vector3(pos.x,0.25,pos.z)+_jitter(0.4,0.0),Vector3(0,0.3,0)+_jitter(0.3,0.0),0.3,0.9,0.9,Color(DUST,0.45),2.0)
		return
	if kind=="drone":
		air_burst(pos,0.45,false)
		return
	if kind=="helo":
		air_burst(pos,1.0,true)
		return
	if kind in STRUCTURES:
		structure_collapse(pos)
		return
	vehicle_explosion(Vector3(pos.x,maxf(pos.y,0.4),pos.z),1.15 if kind=="harvester" else 1.0,water,kind=="tank")

# Staged vehicle kill: flash, fireball lobes, sparks and debris at once; ground dust, then rolling soot,
# then a sustained wreck fire. Tanks add brief ammunition cook-off pops.
func vehicle_explosion(pos:Vector3, scale:float=1.0, water:bool=false, cook_off:bool=false) -> void:
	var g:=Vector3(pos.x,FLOOR,pos.z)
	_boom(scale)
	flash(pos+Vector3(0,0.6,0),4.2*scale,0.09,Color(1.0,0.86,0.55))
	for n in 4:
		fireball(pos+Vector3(0,0.4,0)+_jitter(0.6*scale,0.3),Vector3(0,rng.randf_range(1.2,2.4),0)+_jitter(1.2*scale,0.0),0.9*scale,rng.randf_range(2.6,3.4)*scale,rng.randf_range(0.45,0.7),n*0.03)
	sparks(pos+Vector3(0,0.5,0),int(16*scale),12.0*scale,Vector3.UP*0.8,1.1,ESSENTIAL)
	for n in int(9*scale):
		debris(pos+Vector3(0,0.4,0),_jitter(4.0*scale,0.0)+Vector3(0,rng.randf_range(4,9),0),rng.randf_range(0.12,0.28)*scale,rng.randf_range(1.4,2.2),METAL if n%2==0 else SOOT,not water,n<3)
	if water:
		water_strike(g,1.1*scale)
	else:
		decal(g,DUST_RING,1.0*scale,7.0*scale,0.45,Color(DUST,0.6),ESSENTIAL)
		decal(g,SCORCH,3.0*scale,3.4*scale,45.0,Color(SCORCH_COLOR,0.7),ESSENTIAL)
		for n in 10:
			var out:=Vector3.FORWARD.rotated(Vector3.UP,n*TAU/10+rng.randf_range(-0.2,0.2))
			smoke(g+Vector3(0,0.25,0)+out*0.8*scale,out*rng.randf_range(4.0,7.0)*scale,0.6*scale,rng.randf_range(2.4,3.0)*scale,rng.randf_range(1.6,2.6),Color(DUST,0.55),2.2,0.05,0.06)
	for n in 9:
		smoke(pos+Vector3(0,0.8,0)+_jitter(0.7*scale,0.3),Vector3(0,rng.randf_range(1.5,2.6),0)+_jitter(0.6),1.0*scale,rng.randf_range(3.2,4.0)*scale,rng.randf_range(3.5,5.5),Color(SOOT,0.78),0.6,1.0,0.15+n*0.05,ESSENTIAL)
	add_emitter(g,9.0 if cook_off else 6.5,scale,water)
	if cook_off:
		for when in [rng.randf_range(0.6,0.9),rng.randf_range(1.3,2.0)]:
			cue(when,_cook_off.bind(pos+Vector3(0,0.7,0)))

func _cook_off(pos:Vector3) -> void:
	flash(pos,1.2,0.05,Color(1.0,0.8,0.45),0.0,NORMAL)
	sparks(pos,6,8.0,Vector3.UP,0.7)
	smoke(pos,Vector3(0,1.2,0),0.4,1.6,2.2,Color(SOOT,0.6),1.0,0.6)

# Aircraft or UAV destroyed in flight: airburst, burning fragments falling, and a ground impact on landing.
func air_burst(pos:Vector3, scale:float, crash:bool) -> void:
	_boom(scale*0.8)
	flash(pos,3.2*scale,0.08,Color(1.0,0.86,0.55))
	for n in (3 if scale>0.7 else 1):
		fireball(pos+_jitter(0.5*scale),_jitter(1.4*scale),0.7*scale,2.6*scale,rng.randf_range(0.4,0.6))
	sparks(pos,int(round(14*scale)),11.0*scale,Vector3.ZERO,0.9)
	for n in int(round(8*scale))+2:
		debris(pos,_jitter(3.5*scale,0.0)+Vector3(0,rng.randf_range(0.5,3.5),0),rng.randf_range(0.08,0.22)*scale+0.04,rng.randf_range(2.0,3.0),METAL if n%2 else SOOT,false,n<3 and crash)
	for n in (5 if scale>0.7 else 2):
		smoke(pos+_jitter(0.5*scale),_jitter(0.5),0.8*scale,3.0*scale,rng.randf_range(2.8,4.0),Color(SOOT,0.72),0.8,0.4,0.1+n*0.05)
	if crash:
		var fall:=sqrt(2.0*maxf(pos.y,0.5)/9.8)
		cue(fall,vehicle_explosion.bind(Vector3(pos.x,0.4,pos.z),0.7,false,false))

func structure_collapse(pos:Vector3) -> void:
	vehicle_explosion(Vector3(pos.x,0.8,pos.z),1.5,false,false)
	for n in 3:
		var offset:=Vector3.FORWARD.rotated(Vector3.UP,n*TAU/3+rng.randf())*rng.randf_range(1.2,2.6)
		cue(0.35+n*0.45,he_burst.bind(Vector3(pos.x,0.6,pos.z)+offset,Vector3.DOWN,0.8))
	for n in 8:
		smoke(Vector3(pos.x,0.4,pos.z)+_jitter(2.2,0.0),Vector3(0,0.6,0)+_jitter(0.8,0.0),1.2,3.6,rng.randf_range(3.0,4.5),Color(DUST.darkened(0.2),0.6),1.2,0.4,0.3+n*0.1)
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
			ember(p+Vector3(0,0.5,0)+_jitter(0.45*k,0.2),Vector3(0,0.8,0),rng.randf_range(0.7,1.1)*k,rng.randf_range(0.22,0.34),Color(1.0,0.6,0.25,0.75),OPTIONAL)
			if rng.randf()<0.5:fireball(p+Vector3(0,0.45,0)+_jitter(0.35*k,0.1),Vector3(0,1.0,0),0.35*k,0.85*k,0.38,0.0,OPTIONAL)
		e.smoke_clock-=dt
		if e.smoke_clock<=0:
			e.smoke_clock=lerpf(0.28,0.7,f)
			smoke(p+Vector3(0,0.9,0)+_jitter(0.35*k,0.1),Vector3(0,rng.randf_range(1.2,1.9),0),0.5*k,rng.randf_range(2.4,3.0)*k,rng.randf_range(3.0,4.2),Color(SOOT.lerp(GREY_SMOKE,f),0.66*(1.0-f*0.5)),0.8,0.9,0.0,OPTIONAL)

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
func damage_smoke(pos:Vector3, hp_fraction:float) -> void:
	var severe:=hp_fraction<0.2
	smoke(pos,Vector3(0.1,0.9,0.05),0.35,1.5 if severe else 1.1,1.6 if severe else 1.2,Color(SOOT if severe else GREY_SMOKE,0.5 if severe else 0.38),1.0,0.5,0.0,OPTIONAL)
	if severe and rng.randf()<0.4:ember(pos+Vector3(0,-0.2,0),Vector3(0,0.5,0),0.5,0.2,Color(1.0,0.6,0.25,0.6),OPTIONAL)

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
	sound_clock=maxf(0,sound_clock-dt)
	if not pending_muzzles.is_empty():_flush_muzzles()
	var due:Array[Callable]=[]
	for i in range(cues.size()-1,-1,-1):
		if float(cues[i].at)<=time:
			due.push_front(cues[i].action)
			cues.remove_at(i)
	for action in due:action.call()
	_update_emitters(dt)
	_update_projectiles(dt)
	var drift:=wind+BREEZE
	_sync_view()
	volume.step(dt,drift,self)
	glow.step(dt,drift,self)
	ground.step(dt,drift,self)

func stats() -> Dictionary:
	return {"volume":volume.live,"glow":glow.live,"ground":ground.live,"visible":volume.visible_count+glow.visible_count+ground.visible_count,"projectiles":projectiles.size(),"cues":cues.size(),"emitters":emitters.size(),"dropped":volume.dropped+glow.dropped+ground.dropped,"recycled":volume.recycled+glow.recycled+ground.recycled,"capacity":{"volume":VOLUME_CAPACITY,"glow":GLOW_CAPACITY,"ground":GROUND_CAPACITY,"projectiles":PROJECTILE_CAPACITY,"cues":CUE_CAPACITY,"emitters":EMITTER_CAPACITY}}

func clear() -> void:
	volume.clear();glow.clear();ground.clear()
	projectiles.clear();cues.clear();emitters.clear();pending_muzzles.clear()

func _exit_tree() -> void:
	flashes.stop()
	explosion_audio.stop()
	flashes.stream=null
	explosion_audio.stream=null
