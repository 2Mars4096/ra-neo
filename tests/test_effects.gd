extends SceneTree
const Effects=preload("res://scripts/effects.gd")
var checks:=0
var errors:=0
var evidence:={}

func check(value:bool,label:String) -> void:
	checks+=1
	if not value:
		errors+=1
		printerr("FAIL: ",label)

func _init() -> void:
	call_deferred("run")

func fresh() -> Node:
	var effects=Effects.new()
	root.add_child(effects)
	effects.muted=true
	return effects

func release(effects) -> void:
	effects.clear()
	effects.free()

func live(pool, kind:int=-1) -> int:
	var count:=0
	for i in pool.capacity:
		if pool.life[i]>0.0 and (kind<0 or pool.kind[i]==kind):count+=1
	return count

func shown(pool, kind:int) -> int:
	var count:=0
	for i in pool.capacity:
		if pool.life[i]>0.0 and pool.delay[i]<=0.0 and pool.kind[i]==kind:count+=1
	return count

func advance(effects, seconds:float, dt:float=1.0/60.0) -> void:
	for i in int(round(seconds/dt)):effects._process(dt)

func run() -> void:
	shader_checks()
	signature_checks()
	tracer_checks()
	impact_checks()
	staging_checks()
	lifecycle_checks()
	budget_checks()
	bounds_checks()
	determinism_checks()
	legacy_checks()
	projection_checks()
	integration_checks()
	FileAccess.open("res://artifacts/effects-budget.json",FileAccess.WRITE).store_string(JSON.stringify(evidence,"  "))
	print("EFFECTS TESTS: ",checks," checks, ",errors," failures")
	quit(1 if errors else 0)

func shader_checks() -> void:
	# The headless dummy renderer still parses Godot shading language, so syntax/type errors fail here.
	var expected:={"res://shaders/effect_volume.gdshader":["noise_tex","sun_dir"],"res://shaders/effect_glow.gdshader":["brightness"],"res://shaders/effect_ground.gdshader":["noise_tex"]}
	for path in expected:
		var names:=[]
		for uniform in (load(path) as Shader).get_shader_uniform_list():names.append(uniform.name)
		for name in expected[path]:check(name in names,"%s compiles and exposes %s"%[path,name])

func signature_checks() -> void:
	var counts:={}
	for weapon in ["rifle","aa","tank","boat","atgm","helo"]:
		var effects=fresh()
		var from:=Vector3(10,0.95,10)
		var to:=Vector3(30,0.8,10)
		effects.fire(weapon,from,to,true,false,"rifle",weapon=="boat")
		var behind:=0
		for i in effects.volume.capacity:
			if effects.volume.life[i]>0 and effects.volume.vel[i].x<-1.0:behind+=1
		var flash_size:=0.0
		var tongue:=0.0
		for i in effects.glow.capacity:
			if effects.glow.life[i]<=0:continue
			if effects.glow.kind[i]==Effects.FLASH:flash_size=maxf(flash_size,effects.glow.size0[i])
			if effects.glow.kind[i]==Effects.STREAK:tongue=maxf(tongue,effects.glow.size0[i])
		counts[weapon]={"smoke":live(effects.volume,Effects.SMOKE),"fire":live(effects.volume,Effects.FIRE),"spray":live(effects.volume,Effects.SPRAY),"flash":live(effects.glow,Effects.FLASH),"streak":live(effects.glow,Effects.STREAK),"dust_ring":live(effects.ground,Effects.DUST_RING),"foam_ring":live(effects.ground,Effects.FOAM_RING),"rearward":behind,"flash_size":snappedf(flash_size,0.01),"flame_length":snappedf(tongue,0.01)}
		release(effects)
	evidence["muzzle_signatures"]=counts
	check(counts.rifle.fire==0 and counts.rifle.dust_ring==0 and counts.rifle.smoke<=1,"rifle muzzle is a small flash, not a blast")
	check(counts.rifle.flash==1 and counts.rifle.streak==1,"rifle muzzle has a star and short flame tongue")
	check(counts.tank.dust_ring==1 and counts.tank.smoke>=10 and counts.tank.fire==1,"tank blast lifts ground dust and propellant smoke")
	check(counts.boat.foam_ring==1 and counts.boat.spray>=5 and counts.boat.dust_ring==0,"naval gun disturbs water instead of soil")
	check(counts.atgm.rearward>=8 and counts.atgm.fire==0 and counts.tank.rearward==0,"ATGM launch throws backblast behind the firer")
	check(counts.rifle.flash_size<counts.aa.flash_size and counts.aa.flash_size<counts.boat.flash_size and counts.boat.flash_size<counts.tank.flash_size,"flash scale rises from rifle to autocannon, naval gun and tank")
	check(counts.helo.flash==1,"helicopter salvo launches one rocket per frame-step")
	check(counts.aa.flash==1,"AA burst starts with a single round flash")
	var distinct:={}
	for weapon in counts:distinct[JSON.stringify(counts[weapon])]=true
	check(distinct.size()==counts.size(),"every weapon has a distinct muzzle signature")
	# Burst weapons deliver later rounds with their own flashes.
	var effects=fresh()
	effects.fire("aa",Vector3(0,1.5,0),Vector3(20,13,0),false,false,"helo")
	check(effects.projectiles.size()==3,"AA burst queues three rounds")
	var flashes:=0
	for frame in 18:
		effects._process(1.0/60.0)
		flashes+=shown(effects.glow,Effects.FLASH)
	check(flashes>=3,"each AA round shows its own muzzle flash")
	release(effects)

func tracer_checks() -> void:
	var effects=fresh()
	var tracers:=0
	for i in 40:
		effects.fire("rifle",Vector3(0,0.95,i),Vector3(20,0.8,i),true,false,"rifle")
		if effects.projectiles.back().tracer:tracers+=1
	check(tracers==10,"one rifle round in four is a tracer")
	effects.clear()
	effects.tracer_counts.clear()
	for i in 3:effects.fire("rifle",Vector3(0,0.95,i),Vector3(40,0.8,i),true,false,"rifle")
	advance(effects,4.0/60.0)
	check(effects.projectiles.size()==3 and shown(effects.glow,Effects.STREAK)==0,"ball rounds are invisible in flight once the muzzle flash ends")
	effects.fire("rifle",Vector3(0,0.95,4),Vector3(40,0.8,4),true,false,"rifle")
	effects._process(1.0/60.0)
	var longest:=0.0
	for i in effects.glow.capacity:
		if effects.glow.life[i]>0 and effects.glow.kind[i]==Effects.STREAK and effects.glow.life[i]<0.001:longest=maxf(longest,effects.glow.size0[i])
	check(longest>0.8 and longest<4.1,"tracer is a short streak, not a beam: %.2f"%longest)
	release(effects)

func impact_checks() -> void:
	var effects=fresh()
	var from:=Vector3(0,0.95,0)
	var direction:=Vector3(1,0,0)
	effects.bullet_strike(Vector3(20,0.8,0),direction)
	var toward:=0
	var dust_puffs:=0
	for i in effects.volume.capacity:
		if effects.volume.life[i]>0 and effects.volume.kind[i]==Effects.SMOKE:
			dust_puffs+=1
			if effects.volume.vel[i].x<0:toward+=1
	check(dust_puffs==1 and toward==1,"rifle ground strike sprays back toward the shooter")
	check(live(effects.glow)==0,"rifle strikes in soil do not flash")
	effects.clear()
	var travel:float=effects.fire("rifle",from,Vector3(20,0.8,0),false,false,"rifle")
	check(is_equal_approx(effects.projectiles[0].b.y,Effects.FLOOR),"misses land on the ground, not mid-air")
	advance(effects,travel+0.05)
	check(live(effects.volume,Effects.SMOKE)>=1,"miss produces a dust strike after visual travel")
	effects.clear()
	effects.fire("rifle",from,Vector3(20,0.8,0),false,true,"rifle")
	advance(effects,0.2)
	check(live(effects.volume,Effects.SPRAY)>=1 and live(effects.ground,Effects.FOAM_RING)==1 and live(effects.ground,Effects.DUST_RING)==0,"rifle miss on water splashes")
	effects.clear()
	effects.water_strike(Vector3(40,0,0),1.0)
	var peak:=0.0
	for frame in 90:
		effects._process(1.0/60.0)
		for i in effects.volume.capacity:
			if effects.volume.life[i]>0 and effects.volume.kind[i]==Effects.SPRAY:peak=maxf(peak,effects.volume.pos[i].y)
	evidence["heavy_splash_peak"]=peak
	check(peak>2.5 and peak<7.0,"shell splash rises as a column: %.2f"%peak)
	advance(effects,3.0)
	check(live(effects.volume,Effects.SPRAY)==0,"splash water falls back and expires")
	effects.clear()
	effects.armor_hit(Vector3(20,1,0),direction,1.0)
	var rebound:=0
	var sparks:=0
	for i in effects.glow.capacity:
		if effects.glow.life[i]>0 and effects.glow.kind[i]==Effects.STREAK:
			sparks+=1
			if effects.glow.vel[i].x<0:rebound+=1
	check(sparks>=10 and rebound*2>sparks,"armour sparks rebound toward the incoming side")
	check(live(effects.ground,Effects.SCORCH)==0,"armour hit leaves no ground scorch")
	effects.clear()
	effects.fire("aa",Vector3(0,1.5,0),Vector3(20,13,0),false,false,"helo")
	advance(effects,0.5)
	check(live(effects.volume,Effects.SMOKE)>=3 and live(effects.ground)==0,"AA misses airburst as flak, not ground impacts")
	release(effects)

func staging_checks() -> void:
	var effects=fresh()
	var pos:=Vector3(30,0.7,30)
	effects.destroyed("tank",pos)
	check(shown(effects.glow,Effects.FLASH)==1,"explosion opens with a flash")
	var rolling:=0
	for i in effects.volume.capacity:
		if effects.volume.life[i]>0 and effects.volume.kind[i]==Effects.SMOKE and effects.volume.delay[i]>=0.15:rolling+=1
	check(rolling==9,"rolling smoke waits behind the fireball")
	check(live(effects.volume,Effects.FIRE)==4 and live(effects.volume,Effects.DEBRIS)==9,"fireball lobes and debris are present")
	check(live(effects.ground,Effects.SCORCH)==1 and live(effects.ground,Effects.DUST_RING)==1,"blast ring and scorch are laid")
	effects._process(0.05) # first rendered frame
	effects._process(0.05)
	effects._process(0.05)
	check(shown(effects.glow,Effects.FLASH)==0,"core flash lasts about 0.1 s")
	advance(effects,0.6)
	check(shown(effects.volume,Effects.SMOKE)>=15,"rolling smoke and ground dust are visible after the flash")
	var bounced:=false
	for frame in 120:
		effects._process(1.0/60.0)
		for i in effects.volume.capacity:
			if effects.volume.life[i]>0 and effects.volume.kind[i]==Effects.DEBRIS and effects.volume.pos[i].y<0.05 and effects.volume.vel[i].y>0:bounced=true
	check(bounced,"debris lands and bounces")
	check(effects.emitters.size()==1,"wreck keeps burning")
	advance(effects,12.0)
	check(effects.emitters.is_empty(),"wreck fire burns out")
	check(live(effects.ground,Effects.SCORCH)==1,"scorch outlasts the smoke")
	advance(effects,40.0,0.1)
	check(live(effects.volume)+live(effects.glow)+live(effects.ground)==0,"all explosion layers expire")
	# Killing ATGM in flight: the explosion waits for arrival instead of preceding the missile.
	effects.clear()
	var travel:float=effects.fire("atgm",Vector3(0,0.95,30),pos,true,false,"tank")
	effects.destroyed("tank",pos)
	check(effects.cues.size()==1 and live(effects.ground,Effects.SCORCH)==0,"kill explosion is deferred to missile arrival")
	var exploded_at:=-1.0
	var elapsed:=0.0
	while elapsed<travel+0.5:
		effects._process(1.0/60.0)
		elapsed+=1.0/60.0
		if exploded_at<0 and live(effects.ground,Effects.SCORCH)>0:exploded_at=elapsed
	evidence["atgm_travel"]=travel
	evidence["atgm_explosion_at"]=exploded_at
	check(exploded_at>=travel-0.02 and exploded_at<travel+0.05,"explosion follows missile arrival")
	# Infantry casualty is never a vehicle explosion.
	effects.clear()
	effects.destroyed("rifle",Vector3(5,0.3,5))
	check(live(effects.glow)==0 and live(effects.ground)==0 and live(effects.volume,Effects.FIRE)==0,"infantry casualty shows dust only")
	# Helicopter: airburst at altitude, then wreck impact on the ground after the fall.
	effects.clear()
	effects.destroyed("helo",Vector3(20,13,20))
	check(live(effects.ground)==0 and effects.cues.size()==1,"helicopter breaks up in the air first")
	advance(effects,1.8)
	check(live(effects.ground,Effects.SCORCH)==1 and effects.emitters.size()==1,"wreck strikes the ground after falling")
	effects.clear()
	effects.destroyed("boat",Vector3(80,0.4,20),true)
	check(live(effects.ground,Effects.SCORCH)==0 and live(effects.volume,Effects.SPRAY)>=10,"sinking boat raises water, not scorch")
	effects.clear()
	effects.destroyed("factory",Vector3(50,0,50))
	check(effects.cues.size()==3,"structure collapse adds staggered secondary blasts")
	release(effects)

func lifecycle_checks() -> void:
	var effects=fresh()
	# A one-frame flash still renders when the frame time exceeds its life.
	effects.flash(Vector3.ZERO,0.4,0.035)
	effects._process(0.05)
	check(effects.glow.visible_count==1,"short flash renders at least one frame at 20 fps")
	effects._process(0.05)
	check(effects.glow.visible_count==0 and live(effects.glow)==0,"short flash is then released")
	effects.smoke(Vector3.ZERO,Vector3.UP,0.5,1.0,1.0,Color.WHITE,1.0,0.0,0.5)
	effects._process(0.3)
	var slot:=-1
	for i in effects.volume.capacity:
		if effects.volume.life[i]>0:slot=i
	check(effects.volume.visible_count==0 and effects.volume.age[slot]==0.0,"delayed particles neither show nor age")
	effects._process(0.3)
	check(effects.volume.visible_count==1 and effects.volume.age[slot]==0.0 and effects.volume.pos[slot]==Vector3.ZERO,"delayed particle is born at its authored state")
	advance(effects,1.2)
	check(live(effects.volume)==0 and effects.volume.free_slots.size()==Effects.VOLUME_CAPACITY,"expired slots return to the free list")
	for i in 180:effects.fire("atgm",Vector3(0,1,i*0.1),Vector3(30,1,i*0.1),true)
	check(effects.projectiles.size()==Effects.PROJECTILE_CAPACITY,"projectile presentation has a hard budget")
	advance(effects,3.0,0.05)
	check(effects.projectiles.is_empty(),"projectiles complete and release their slots")
	# MultiMesh buffer rows: 12 transform floats (row-major 3x4), RGBA, then custom kind/turn/age/seed.
	effects.streak(Vector3(1,2,3),Vector3(0,1,1),2.0,0.1,0.05,Color.WHITE)
	effects._process(0.01)
	var buffer:PackedFloat32Array=effects.glow.buffer
	var back:Vector3=Effects.DEFAULT_VIEW.z
	var along:=Vector3(buffer[0],buffer[4],buffer[8])
	var side:=Vector3(buffer[1],buffer[5],buffer[9])
	check(buffer[3]==1.0 and buffer[7]==2.0 and buffer[11]==3.0 and along.is_equal_approx(Vector3(0,1,1).normalized()*2.0) and is_equal_approx(side.length(),0.1) and absf(side.dot(back))<0.0001 and absf(side.dot(along))<0.0001,"streak runs along its world axis and widens across the view")
	check(buffer[16]==Effects.STREAK and buffer[15]==1.0,"kind travels in custom data")
	effects.clear()
	effects.flash(Vector3(4,5,6),0.5,0.1)
	effects._process(0.01)
	effects._process(0.01)
	buffer=effects.glow.buffer
	var card_x:=Vector3(buffer[0],buffer[4],buffer[8])
	var card_y:=Vector3(buffer[1],buffer[5],buffer[9])
	var size:=card_x.length()
	var pulled:=Vector3(buffer[3],buffer[7],buffer[11])-Vector3(4,5,6)
	check(absf(card_x.dot(back))<0.0001 and absf(card_y.dot(back))<0.0001 and absf(card_x.dot(card_y))<0.0001 and is_equal_approx(size,card_y.length()) and size>0.5,"flash card faces the battle camera with square world size")
	check(pulled.normalized().is_equal_approx(back) and is_equal_approx(pulled.length(),size*0.5) and buffer[16]==Effects.FLASH and buffer[18]>0.0,"flash card is pulled toward the camera and reports age")
	# Flames draw after smoke in the shared volume MultiMesh, including when the pool is nearly full.
	for fill in [2,Effects.VOLUME_CAPACITY]:
		effects.clear()
		for i in fill:
			if i%5==0 or i==0:effects.fireball(Vector3(i*0.1,1,0),Vector3.ZERO,0.5,1.0,2.0,0.0,Effects.ESSENTIAL)
			else:effects.smoke(Vector3(i*0.1,1,0),Vector3.ZERO,0.5,1.0,2.0,Color.WHITE,1.0,0.0,0.0,Effects.ESSENTIAL)
		effects._process(0.01)
		var rows:PackedFloat32Array=effects.volume.buffer
		var order:=[]
		var xs:={}
		for r in effects.volume.visible_count:
			order.append(int(rows[r*20+16]))
			xs[snappedf(rows[r*20+3],0.01)]=true
		var fires:=order.count(Effects.FIRE)
		check(effects.volume.visible_count==fill and fires==live(effects.volume,Effects.FIRE) and order.slice(order.size()-fires).count(Effects.FIRE)==fires and xs.size()==fill,"fire rows pack after smoke without loss (%d live)"%fill)
	effects.clear()
	for i in 150:effects.cue(1.0,func():pass)
	check(effects.cues.size()==Effects.CUE_CAPACITY and effects.dropped_cues==150-Effects.CUE_CAPACITY,"cue list is bounded")
	advance(effects,1.1,0.1)
	check(effects.cues.is_empty(),"cues fire and clear")
	for i in 20:effects.add_emitter(Vector3(i,0,0),5.0,1.0,false)
	check(effects.emitters.size()==Effects.EMITTER_CAPACITY,"wreck fires are bounded")
	release(effects)

func budget_checks() -> void:
	var effects=fresh()
	# Typical busy skirmish: ~60 rifle, 6 cannon and 3 AA/ATGM shots per second plus a vehicle kill every 2 s.
	var typical:Array[float]=[]
	var typical_visible:=0
	for frame in 600:
		if frame%2==0:
			for i in 2:effects.fire("rifle",Vector3(i*3,0.95,0),Vector3(i*3+2,0.8,22),frame%6==0,false,"rifle")
		if frame%10==0:effects.fire("tank",Vector3(30,1,0),Vector3(32,0.8,24),frame%20==0,false,"tank")
		if frame%20==0:effects.fire(["aa","atgm"][frame/20%2],Vector3(40,1,0),Vector3(44,0.8,20),true,false,"tank")
		if frame%120==0:effects.destroyed("tank",Vector3(20+frame%60,0.7,30))
		var started:=Time.get_ticks_usec()
		effects._process(1.0/60.0)
		if frame>=120:typical.append((Time.get_ticks_usec()-started)/1000.0)
		typical_visible=maxi(typical_visible,effects.stats().visible)
	typical.sort()
	evidence["typical_update_ms_p50"]=typical[typical.size()/2]
	evidence["typical_update_ms_p95"]=typical[int(typical.size()*0.95)]
	evidence["typical_visible_instances_max"]=typical_visible
	check(typical_visible<Effects.CAPACITY*0.8,"typical combat stays below pool saturation")
	effects.clear()
	for i in 60:effects.vehicle_explosion(Vector3(i%10*8,0.7,i/10*8),1.0,i%7==0,true)
	for i in 400:effects.fire(["rifle","aa","tank","atgm","boat","helo"][i%6],Vector3(i%20*4,1,0),Vector3(i%20*4,0.8,25),i%3!=0,i%5==0,["rifle","tank","helo"][i%3])
	check(effects.volume.live<=Effects.VOLUME_CAPACITY and effects.glow.live<=Effects.GLOW_CAPACITY and effects.ground.live<=Effects.GROUND_CAPACITY,"pools never exceed capacity")
	check(effects.volume.multimesh.instance_count==Effects.VOLUME_CAPACITY and effects.volume.buffer.size()==Effects.VOLUME_CAPACITY*20,"instance buffers are fixed size")
	check(effects.volume.free_slots.size()+effects.volume.live==Effects.VOLUME_CAPACITY,"free list and live count agree under overload")
	check(effects.stats().dropped>0,"optional detail is thinned under saturation")
	var worst:=0
	var samples:Array[float]=[]
	for frame in 240:
		if frame%4==0:
			for i in 12:effects.fire(["rifle","aa","tank"][i%3],Vector3(i*4,1,0),Vector3(i*4,0.8,25),i%2==0,false,"rifle")
		if frame%30==0:effects.vehicle_explosion(Vector3(frame%90,0.7,40),1.0,false,true)
		var started:=Time.get_ticks_usec()
		effects._process(1.0/60.0)
		samples.append((Time.get_ticks_usec()-started)/1000.0)
		worst=maxi(worst,effects.stats().visible)
	samples.sort()
	evidence["saturated_update_ms_p50"]=samples[samples.size()/2]
	evidence["saturated_update_ms_p95"]=samples[int(samples.size()*0.95)]
	evidence["saturated_visible_instances_max"]=worst
	evidence["capacity"]=effects.stats().capacity
	evidence["method"]="Headless CPU cost of BattleEffects._process with all three pools saturated by repeated explosions and 180 shots/s; excludes GPU fill cost."
	check(worst<=Effects.CAPACITY,"visible instances bounded")
	# Essential beats survive saturation by recycling.
	var before:int=effects.volume.recycled
	effects.vehicle_explosion(Vector3(5,0.7,5))
	check(effects.volume.recycled>before or effects.volume.free_slots.size()>0,"essential explosion layers still spawn when full")
	advance(effects,60.0,0.1)
	check(effects.stats().visible==0 and effects.volume.live==0 and effects.glow.live==0 and effects.ground.live==0,"saturated pools drain completely")
	release(effects)

func bounds_checks() -> void:
	var effects=fresh()
	for corner in [Vector3(4,0.7,4),Vector3(138,0.7,102)]:
		effects.clear()
		effects.vehicle_explosion(corner)
		effects._process(1.0/60.0)
		check(effects.volume.instance.visible and effects.volume.instance.custom_aabb.has_point(corner),"volume bounds follow content at %s"%corner)
		check(effects.ground.instance.custom_aabb.has_point(Vector3(corner.x,Effects.DECAL_HEIGHT,corner.z)),"decal bounds follow content at %s"%corner)
	effects.clear()
	effects._process(1.0/60.0)
	check(not effects.volume.instance.visible and not effects.glow.instance.visible and not effects.ground.instance.visible,"idle pools draw nothing")
	# Riverside Town (144x108, shore 128): far-corner content stays visible and a stray far-off fragment cannot
	# inflate the culling box beyond the padded map.
	effects.set_world_bounds(Vector2(144,108),128.0)
	effects.vehicle_explosion(Vector3(140,0.7,104),1.0,true)
	effects.debris(Vector3(140,1,104),Vector3(400,0,0),0.1,0.5,Effects.METAL,false)
	effects._process(0.25)
	var box:AABB=effects.volume.instance.custom_aabb
	check(box.has_point(Vector3(140,0.7,104)) and box.end.x<=144+8.01,"world bounds cap culling at the map edge: %s"%box)
	check(effects.is_water_at(Vector3(130,0,50)) and not effects.is_water_at(Vector3(120,0,50)),"shore line separates water from land")
	release(effects)

func snapshot(effects) -> Array:
	var state:=[]
	for pool in [effects.volume,effects.glow,effects.ground]:
		for i in pool.capacity:
			if pool.life[i]>0:state.append([i,pool.pos[i],pool.age[i],pool.kind[i]])
	return state

func determinism_checks() -> void:
	var runs:=[]
	for n in 2:
		var effects=fresh()
		effects.reseed(77)
		effects.fire("tank",Vector3(0,1,0),Vector3(20,0.8,3),false,false,"tank")
		effects.destroyed("aa",Vector3(12,0.7,12))
		advance(effects,0.7)
		runs.append(snapshot(effects))
		release(effects)
	check(runs[0]==runs[1] and not runs[0].is_empty(),"seeded effects are deterministic for capture fixtures")

func card_pixels(camera:Camera3D, pool, row:int, column:int) -> float:
	var b:PackedFloat32Array=pool.buffer
	var o:=row*20
	var origin:=Vector3(b[o+3],b[o+7],b[o+11])
	var half:=Vector3(b[o+column],b[o+4+column],b[o+8+column])*0.5
	return camera.unproject_position(origin-half).distance_to(camera.unproject_position(origin+half))

# Projects CPU-built cards through an orthographic camera placed like the battle camera. This proves the
# intended on-screen sizes; it does not exercise the GPU (the native capture fixture does).
func projection_checks() -> void:
	var effects=fresh()
	var camera:=Camera3D.new()
	root.add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=36.0
	camera.far=300.0
	var focus:=Vector3(60,0,50)
	camera.position=focus+Vector3(26,64,46)
	camera.look_at(focus,Vector3.UP)
	camera.make_current()
	var ppu:float=root.get_visible_rect().size.y/camera.size
	var sizes:={}
	for spec in [["rifle_flash",0.36],["tank_flash",1.5],["explosion_flash",4.2]]:
		effects.clear()
		var p:=focus+Vector3(0,1,0)
		effects.flash(p,spec[1],0.2)
		effects._process(1.0/60.0)
		var wide:=card_pixels(camera,effects.glow,0,0)
		var tall:=card_pixels(camera,effects.glow,0,1)
		var centre:=camera.unproject_position(Vector3(effects.glow.buffer[3],effects.glow.buffer[7],effects.glow.buffer[11]))
		sizes[spec[0]]=snappedf(wide,0.1)
		check(absf(wide-spec[1]*ppu)<0.5 and absf(tall-wide)<0.5,"%s card spans %.1f px (expected %.1f)"%[spec[0],wide,spec[1]*ppu])
		check(centre.distance_to(camera.unproject_position(p))<0.5,"%s stays over its source on screen after the depth pull"%spec[0])
	evidence["flash_card_pixels"]=sizes
	evidence["pixels_per_metre"]=ppu
	effects.clear()
	effects.ember(focus,Vector3.ZERO,0.001,0.2)
	effects._process(1.0/60.0)
	check(card_pixels(camera,effects.glow,0,0)>=Effects.MIN_PIXELS-0.01,"tiny glow never drops below the minimum pixel size")
	effects.clear()
	effects.smoke(focus,Vector3.ZERO,2.0,2.0,1.0,Color.WHITE)
	effects._process(1.0/60.0)
	check(absf(card_pixels(camera,effects.volume,0,0)-2.0*ppu)<0.5 and absf(card_pixels(camera,effects.volume,0,1)-2.0*ppu)<0.5,"spun smoke card keeps its screen size")
	effects.clear()
	effects.streak(focus+Vector3(0,1,0),Vector3(1,0,0),3.0,0.08,0.2,Color.WHITE)
	effects._process(1.0/60.0)
	var length_px:=card_pixels(camera,effects.glow,0,0)
	var expected_px:=camera.unproject_position(focus+Vector3(1.5,1,0)).distance_to(camera.unproject_position(focus+Vector3(-1.5,1,0)))
	check(absf(length_px-expected_px)<0.5 and card_pixels(camera,effects.glow,0,1)>=maxf(0.08*ppu,Effects.MIN_PIXELS*0.75)-0.05,"tracer ribbon keeps its projected length and a visible width")
	# Every live card in a busy frame stays far smaller than the screen (guards against runaway quads).
	effects.clear()
	effects.vehicle_explosion(focus+Vector3(0,0.7,0))
	effects.fire("tank",focus+Vector3(-10,1,0),focus+Vector3(5,0.8,3),false)
	effects._process(1.0/60.0)
	var largest:=0.0
	for pool in [effects.volume,effects.glow]:
		for row in pool.visible_count:largest=maxf(largest,maxf(card_pixels(camera,pool,row,0),card_pixels(camera,pool,row,1)))
	evidence["largest_card_pixels_at_detonation"]=snappedf(largest,0.1)
	check(largest<ppu*6.0,"no card exceeds 6 m on screen at detonation: %.0f px"%largest)
	camera.free()
	release(effects)

# battle.gd consume_events() -> fire()/destroyed() on the 144x108 Riverside map (shore 128).
func integration_checks() -> void:
	var Sim=load("res://scripts/simulation.gd")
	var previous:int=Sim.scenario_selection
	Sim.scenario_selection=5
	var battle=load("res://scenes/main.tscn").instantiate()
	root.add_child(battle)
	Sim.scenario_selection=previous
	battle.set_process(false)
	battle.set_physics_process(false)
	battle.effects.set_process(false)
	var effects=battle.effects
	effects.muted=true
	var sim=battle.sim
	check(sim.terrain.world_size==Vector2(144,108) and is_equal_approx(effects.shore_x,128.0) and effects.world_box.end.x>=144.0,"battle passes Riverside bounds and shore to effects")
	# Real shot events carry the target kind.
	var shooter:Dictionary=sim.spawn("tank",0,Vector2(60,60))
	var armour:Dictionary=sim.spawn("tank",1,Vector2(70,60))
	sim.events.clear()
	if not shooter.is_empty() and not armour.is_empty():
		sim.resolve_shot(shooter,armour,0.0)
		var shots:Array=sim.events.filter(func(e):return e.type=="shot")
		check(not shots.is_empty() and shots[0].get("target_kind","")=="tank","simulation shot events carry target_kind")
	else:
		check(false,"integration spawn points accepted")
	sim.events.clear()
	effects.clear()
	var event:={"type":"shot","from":Vector2(130,40),"to":Vector2(134,60),"kind":"boat","target_kind":"boat","hit":false,"from_y":0.95,"to_y":0.8,"visible":true}
	sim.events.append(event)
	battle.consume_events()
	check(live(effects.ground,Effects.FOAM_RING)>=1 and live(effects.ground,Effects.DUST_RING)==0,"boat beyond shore fires with a water blast through battle")
	var start:Vector3=effects.projectiles[0].a
	check(absf(start.distance_to(Vector3(130,0.95,40))-float(Effects.WEAPONS.boat.barrel))<0.01,"battle no longer double-applies the barrel offset")
	effects.clear()
	sim.events.append({"type":"shot","from":Vector2(60,60),"to":Vector2(70,60),"kind":"rifle","target_kind":"tank","hit":true,"from_y":0.95,"to_y":0.8,"visible":true})
	battle.consume_events()
	advance(effects,0.1)
	check(live(effects.glow,Effects.STREAK)>=2 and live(effects.volume,Effects.DEBRIS)==0,"rifle hit on armour ricochets as sparks")
	effects.clear()
	var helo_height:float=float(sim.definitions.helo.altitude)
	sim.events.append({"type":"destroyed","kind":"helo","pos":Vector2(100,50),"visible":true})
	battle.consume_events()
	var airborne:=0
	for i in effects.volume.capacity:
		if effects.volume.life[i]>0 and effects.volume.pos[i].y>helo_height*0.6:airborne+=1
	check(airborne>0 and live(effects.ground,Effects.SCORCH)==0 and effects.cues.size()==1,"helicopter kill bursts at flight altitude before crashing")
	effects.clear()
	sim.events.append({"type":"destroyed","kind":"rifle","pos":Vector2(60,60),"visible":true})
	battle.consume_events()
	check(live(effects.glow)==0 and live(effects.volume,Effects.FIRE)==0,"infantry casualty through battle is not an explosion")
	effects.damage_smoke(Vector3(60,2,60),0.1)
	check(live(effects.volume,Effects.SMOKE)>=1,"damage smoke entry point used by battle draws")
	root.remove_child(battle)
	battle.free()

func legacy_checks() -> void:
	var effects=fresh()
	effects.muzzle(Vector3.ZERO,Vector3.RIGHT,true)
	effects.projectile(Vector3.ZERO,Vector3(20,0.8,0),"tank",false,true)
	effects.impact(Vector3(5,0.3,5),false)
	effects.explosion(Vector3(10,0.7,10))
	effects.emit(Vector3(2,1,2),Vector3(0.25,0.8,0.1),0.45,1.2,Color(0.22,0.23,0.22,0.35),0.5)
	effects.dust(Vector3(1,0.15,1),Vector2(0,1),false)
	effects.dust(Vector3(80,0.15,1),Vector2(1,0),true)
	effects.damage_smoke(Vector3(3,1,3),0.1)
	check(live(effects.volume)>0 and live(effects.glow)>0 and effects.projectiles.size()==1,"legacy entry points remain usable")
	advance(effects,60.0,0.1)
	check(live(effects.volume)+live(effects.glow)+live(effects.ground)==0 and effects.projectiles.is_empty(),"legacy effects expire")
	release(effects)
	# Current battle.gd order: muzzle(a,dir,heavy) then projectile(a,b,kind,...) with a already pushed along the barrel.
	# The pair must reproduce the weapon-specific signature of fire(), not a generic heavy/light blast.
	var legacy:={}
	for weapon in ["rifle","tank","boat","atgm"]:
		effects=fresh()
		effects.set_world_bounds(Vector2(144,108),128.0)
		var from:=Vector3(130 if weapon=="boat" else 60,0.95,50)
		var to:=Vector3(from.x-20,0.8,50)
		var heavy:bool=weapon in ["tank","boat","atgm","helo"]
		var direction:=(to-from).normalized()
		var a:=from+direction*(2.2 if heavy else 0.6)
		effects.muzzle(a,direction,heavy)
		effects.projectile(a,to,weapon,false,true)
		var behind:=0
		for i in effects.volume.capacity:
			if effects.volume.life[i]>0 and effects.volume.vel[i].x>1.0:behind+=1
		legacy[weapon]={"dust_ring":live(effects.ground,Effects.DUST_RING),"foam_ring":live(effects.ground,Effects.FOAM_RING),"fire":live(effects.volume,Effects.FIRE),"rearward":behind,"start":effects.projectiles[0].a,"a":a}
		effects._process(1.0/60.0)
		check(effects.pending_muzzles.is_empty() and live(effects.glow,Effects.FLASH)<=1,"legacy %s muzzle is drawn once"%weapon)
		release(effects)
	evidence["legacy_pairing"]=legacy
	check(legacy.rifle.fire==0 and legacy.rifle.dust_ring==0,"legacy rifle stays a small flash")
	check(legacy.tank.dust_ring==1 and legacy.tank.fire==1,"legacy tank keeps the cannon blast")
	check(legacy.boat.foam_ring==1 and legacy.boat.dust_ring==0,"legacy naval gun beyond the shore disturbs water")
	check(legacy.atgm.fire==0 and legacy.atgm.rearward>=8,"legacy ATGM shows backblast instead of a cannon blast")
	check(legacy.tank.start.is_equal_approx(legacy.tank.a) and legacy.rifle.start.is_equal_approx(legacy.rifle.a),"legacy rounds start at the caller's muzzle point")
	# An unpaired muzzle still renders on the next frame.
	effects=fresh()
	effects.muzzle(Vector3(5,1,5),Vector3.RIGHT,true)
	effects._process(1.0/60.0)
	check(effects.pending_muzzles.is_empty() and live(effects.ground,Effects.DUST_RING)==1,"unpaired legacy muzzle falls back to a heavy blast")
	effects.clear()
	# Legacy explosion() also waits for the killing round in flight.
	effects.projectile(Vector3(0,0.95,0),Vector3(30,0.8,0),"atgm",false,true)
	effects.explosion(Vector3(30,0.7,0))
	check(effects.cues.size()==1 and live(effects.ground,Effects.SCORCH)==0,"legacy explosion is deferred to missile arrival")
	release(effects)
