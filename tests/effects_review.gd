extends SceneTree
# Deterministic native review of firing, impact and destruction effects in the accepted Canal Watch scene.
# Native:   Godot --path . --script tests/effects_review.gd   (writes artifacts/effects-review-*.png)
#           Scenes A-C stage effects directly; scene D (Riverside Town) goes through battle.consume_events().
#           Scene E is a close-up explosion review: every blast kind detonates at the centre of the frame at
#           gameplay zoom (camera size 40) and is captured at t = 0.05, 0.25, 0.6, 1.5 and 4 s after detonation,
#           next to a reference tank and rifle squad. Its contact sheet is artifacts/effects-review-e-sheet.png
#           (rows = kinds, columns = times). Add `-- --only-e` to run scene E alone.
#           Scene F stages 300 mixed impacts and 7 kills around one spot, lets every transient layer expire and
#           captures the permanent remains (ground-damage tiles and landed debris chunks) at close and wide zoom.
#           It prints "EFFECTS REMAINS" with the measured per-frame effects cost and texture upload cost (the
#           native numbers are the meaningful ones). `-- --only-f` runs scene F alone.
# Headless: runs the same timeline and writes artifacts/effects-review.json plus flat-disc layout proxies.
const Sim=preload("res://scripts/simulation.gd")
const DT:=1.0/60.0
var battle
var headless:=DisplayServer.get_name()=="headless"
var captures:Array=[]
var images:Array[Image]=[]
var miss_rng:=RandomNumberGenerator.new()
var e_images:Array[Image]=[]
const E_TIMES:=[0.05,0.25,0.6,1.5,4.0]
const E_ZOOM:=40.0
# What each capture instant should show, printed with every scene-E capture.
const E_STAGE:={0.05:"core flash + fireball birth, shock ring starting",0.25:"fireball at peak, shock ring at full radius, debris and sparks launching",
	0.6:"fireball rolling up and darkening, debris arcs, dust skirt",1.5:"fireball turned to smoke, column rising, debris landing",4.0:"lingering column or wreck fire; permanent crater/scorch/burn mark under the fading fresh scorch; landed debris chunks"}

func _init() -> void:
	call_deferred("run")

func place(kind:String, team:int, pos:Vector2) -> Dictionary:
	var unit:Dictionary=battle.sim.spawn(kind,team,pos)
	if unit.is_empty():return unit
	unit.visible=true
	unit.seen_by=[true,true]
	return unit

func aim(shooter:Dictionary, target:Dictionary) -> void:
	shooter.target=target.id
	shooter.facing=(target.pos-shooter.pos).normalized()

# Mirrors the integration requested from battle.gd consume_events for one shot event.
func shoot(shooter:Dictionary, target:Dictionary, hit:bool, origin:Vector2=Vector2.INF) -> void:
	var from_xz:Vector2=shooter.pos if origin==Vector2.INF else origin
	var endpoint:Vector2=target.pos
	if not hit:endpoint+=Vector2.from_angle(miss_rng.randf()*TAU)*miss_rng.randf_range(2.5,4.5)
	var from:=Vector3(from_xz.x,float(shooter.get("fire_height",maxf(0.95,battle.altitude(shooter)))),from_xz.y)
	var to:=Vector3(endpoint.x,maxf(0.8,battle.altitude(target)),endpoint.y)
	battle.effects.fire(shooter.kind,from,to,hit,battle.sim.terrain.is_water(endpoint),target.kind,battle.sim.terrain.is_water(from_xz))
	shooter.last_shot=battle.sim.time

func volley(squad:Dictionary, target:Dictionary, hits:int) -> void:
	for i in squad.members.size():
		shoot(squad,target,i<hits,squad.members[i].pos)
		squad.members[i].last_shot=battle.sim.time

# Effects defer the blast until a killing round in flight arrives; the model is removed separately.
func kill(target:Dictionary) -> void:
	battle.effects.destroyed(target.kind,Vector3(target.pos.x,maxf(0.7,battle.altitude(target)),target.pos.y),battle.sim.terrain.is_water(target.pos))

func remove(target:Dictionary) -> void:
	target.hp=0.0
	for member in target.get("members",[]):member.hp=0.0

func frame(seconds:float) -> void:
	for step in int(round(seconds/DT)):
		battle.sim.time+=DT
		battle.effects._process(DT)
		battle.sync_units(DT)

func frame_to(stamp:Dictionary, seconds:float) -> void:
	frame(seconds-float(stamp.t))
	stamp.t=seconds

func view(focus:Vector3, size:float) -> void:
	battle.camera_focus=focus
	battle.camera_size=size
	battle.camera_zoom_target=size
	battle.update_camera()

func capture(name:String, note:String) -> void:
	battle.sim.update_visibility()
	battle.update_fog_pixels()
	battle.fog_texture.update(battle.fog_image)
	battle.hud.queue_redraw()
	var record:={"name":name,"scenario":battle.sim.terrain.scenario_id,"time":battle.effects.time,"camera_size":battle.camera_size,"note":note,"stats":battle.effects.stats(),"volume_bounds":str(battle.effects.volume.instance.custom_aabb) if battle.effects.volume.instance.visible else "hidden"}
	if not headless:
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var image:=root.get_texture().get_image()
		record["status"]=image.save_png("res://artifacts/effects-review-%s.png"%name)
		images.append(image)
	else:
		record["proxy"]=layout_proxy(name)
	captures.append(record)
	print("EFFECTS CAPTURE ",name," visible=",record.stats.visible)

# Headless-only layout proxy: flat discs at projected particle positions/sizes over unit markers.
# It checks scale, placement and timing; it does not represent shader appearance or lighting.
func layout_proxy(name:String) -> String:
	var scale:=0.5
	var image:=Image.create(720,450,false,Image.FORMAT_RGBA8)
	image.fill(Color(0.24,0.26,0.2))
	var ppu:float=900.0/battle.camera_size*scale
	for unit in battle.sim.units:
		if not battle.sim.alive(unit):continue
		var bodies:Array=unit.members.map(func(m):return m.pos) if not unit.members.is_empty() else [unit.pos]
		for body in bodies:
			var s:Vector2=battle.camera.unproject_position(Vector3(body.x,battle.altitude(unit),body.y))*scale
			var radius:float=(0.3 if not unit.members.is_empty() else (1.6 if unit.kind in ["tank","aa","boat","helo"] else 0.6))*ppu
			disc(image,s,radius,Color(0.1,0.14,0.32,0.9) if unit.team==0 else Color(0.45,0.3,0.1,0.9),false,0.0)
	var effects=battle.effects
	for layer in [[effects.ground,0.63,false],[effects.volume,1.0,false],[effects.glow,1.0,true]]:
		var pool=layer[0]
		for i in pool.capacity:
			if pool.life[i]<=0.0 or pool.delay[i]>0.0:continue
			var t:float=pool.age[i]/pool.life[i]
			var size:float=lerpf(pool.size0[i],pool.size1[i],1.0-(1.0-t)*(1.0-t))
			var col:Color=pool.color[i]
			if pool==effects.volume and pool.kind[i]==effects.FIRE:col=Color(1.0,0.6,0.2).lerp(Color(0.15,0.12,0.1),t)
			col.a*=1.0-t*0.6
			var s:Vector2=battle.camera.unproject_position(pool.pos[i])*scale
			if pool.flags[i]&effects.AXIAL:
				var ahead:Vector2=battle.camera.unproject_position(pool.pos[i]+pool.axis[i]*size*0.5)*scale
				var behind:Vector2=battle.camera.unproject_position(pool.pos[i]-pool.axis[i]*size*0.5)*scale
				for k in 9:disc(image,behind.lerp(ahead,k/8.0),maxf(1.0,pool.width[i]*ppu*0.5),col,true,layer[1])
			else:
				disc(image,s,maxf(1.0,size*ppu*0.5),col,layer[2],layer[1])
	var path:="res://artifacts/effects-proxy-%s.png"%name
	image.save_png(path)
	return path

func disc(image:Image, centre:Vector2, radius:float, col:Color, additive:bool, squash:float) -> void:
	var ry:=radius*(squash if squash>0.0 else 1.0)
	for y in range(int(centre.y-ry),int(centre.y+ry)+1):
		if y<0 or y>=image.get_height():continue
		for x in range(int(centre.x-radius),int(centre.x+radius)+1):
			if x<0 or x>=image.get_width():continue
			var d:=Vector2((x-centre.x)/radius,(y-centre.y)/maxf(ry,0.5)).length()
			if d>1.0:continue
			var a:=col.a*(1.0-d*d)
			var base:=image.get_pixel(x,y)
			image.set_pixel(x,y,Color(minf(1,base.r+col.r*a),minf(1,base.g+col.g*a),minf(1,base.b+col.b*a)) if additive else base.lerp(Color(col.r,col.g,col.b),a))

func open(selection:int) -> void:
	if battle:
		root.remove_child(battle)
		battle.free()
	Sim.scenario_selection=selection
	battle=load("res://scenes/main.tscn").instantiate()
	root.add_child(battle)
	current_scene=battle
	battle.effects.muted=true
	battle.show_help=false
	battle.paused=false
	battle.set_process(false)
	battle.set_physics_process(false)
	battle.set_process_input(false)
	battle.effects.set_process(false)
	battle.effects.reseed(2026)
	miss_rng.seed=2026
	battle.selected=[]

# Pushes a real simulation-shaped event through battle.consume_events(), so the capture shows whichever
# integration battle.gd currently uses (legacy muzzle/projectile/explosion or fire/destroyed).
func shot_event(shooter:Dictionary, target:Dictionary, hit:bool) -> void:
	var endpoint:Vector2=target.pos
	if not hit:endpoint+=Vector2.from_angle(miss_rng.randf()*TAU)*miss_rng.randf_range(2.5,4.5)
	battle.sim.events.append({"type":"shot","from":shooter.pos,"to":endpoint,"kind":shooter.kind,"hit":hit,"from_y":shooter.get("fire_height",maxf(0.95,battle.altitude(shooter))),"to_y":maxf(0.8,battle.altitude(target)),"visible":true,"target_kind":target.kind})
	shooter.last_shot=battle.sim.time

func destroyed_event(target:Dictionary) -> void:
	battle.sim.events.append({"type":"destroyed","kind":target.kind,"pos":target.pos,"visible":true})

# Scene E. Impacts go through fire() for their real surface routing, then land at once (the muzzle and flight
# are cleared); kills go through destroyed(). Shake is disabled so frames stay aligned.
const E_KINDS:=[
	["tank_he","tank HE shell on soil (R 2.5 m)"],
	["atgm_soil","ATGM on soft ground (R 1.5 m)"],
	["atgm_armor","ATGM on a tank hull (R 1.8 m)"],
	["at_gun_ap","AT gun AP round on armour (kinetic, no fireball)"],
	["fpv","FPV drone strike on soil (R 1.3 m)"],
	["masonry","tank HE on a bunker face (R 2.2 m)"],
	["vehicle_kill","tank kill (R 5 m) with cook-offs and wreck fire"],
	["bunker","bunker collapse (R 3.1 m)"],
	["depot","ammo depot cook-off chain (R 6.5 m)"],
	["water","tank shell into water"],
]

func explosion_review() -> void:
	open(3)
	battle.effects.shake_enabled=false
	var spot:=Vector2(55,63)
	var water_spot:=Vector2(86,24)
	if not battle.sim.terrain.is_water(water_spot):push_warning("scene E water spot is not water")
	place("tank",0,spot+Vector2(-9,-5))
	place("rifle",0,spot+Vector2(-8,5))
	battle.sim.update_visibility()
	battle.sync_units(5.0)
	for k in E_KINDS.size():
		var kind:String=E_KINDS[k][0]
		var at:Vector2=water_spot if kind=="water" else spot
		battle.effects.clear()
		battle.effects.reseed(3000+k)
		var target:={}
		if kind in ["atgm_armor","at_gun_ap","vehicle_kill"]:
			target=place("tank",1,at)
			battle.sim.update_visibility()
			battle.sync_units(5.0)
		view(Vector3(at.x,0,at.y),E_ZOOM)
		var ground:=Vector3(at.x,0.8,at.y)
		var from:=Vector3(at.x-24,0.95,at.y+8)
		match kind:
			"tank_he":land(battle.effects.fire("tank",from,ground,false,false,"rifle"))
			"atgm_soil":land(battle.effects.fire("atgm",from,ground,false,false,"rifle"))
			"atgm_armor":land(battle.effects.fire("atgm",from,ground,true,false,"tank"))
			"at_gun_ap":land(battle.effects.fire("at_gun",from,ground,true,false,"tank"))
			"fpv":land(battle.effects.fire("fpv_drone",Vector3(at.x-6,6,at.y+2),ground,true,false,"rifle"))
			"masonry":land(battle.effects.fire("tank",from,Vector3(at.x,1.0,at.y),true,false,"bunker"))
			"vehicle_kill":battle.effects.destroyed("tank",Vector3(at.x,0.7,at.y))
			"bunker":battle.effects.destroyed("bunker",Vector3(at.x,0.7,at.y))
			"depot":battle.effects.destroyed("ammo_depot",Vector3(at.x,0.7,at.y))
			"water":land(battle.effects.fire("tank",from,ground,false,true,"boat"))
		if kind=="vehicle_kill" and not target.is_empty():
			# The hull becomes a burnt-out wreck under the blast, as in a real kill.
			remove(target)
			target.wrecked=true
		var clock:={"t":0.0}
		for stamp in E_TIMES:
			frame_to(clock,stamp)
			var name:="e%02d-%s-t%s"%[k+1,kind,str(stamp)]
			var note:="%s | t=%.2f s after detonation | expect: %s"%[E_KINDS[k][1],stamp,E_STAGE[stamp]]
			print("EFFECTS E kind=",kind," t=",stamp," file=artifacts/effects-review-",name,".png")
			await capture(name,note)
			if not headless:e_images.append(images.pop_back())
		if not target.is_empty():
			remove(target)
			target.wrecked=false
			battle.sync_units(DT)
	if not headless and not e_images.is_empty():
		var columns:=E_TIMES.size()
		var sheet:=Image.create(columns*384,E_KINDS.size()*240,false,Image.FORMAT_RGBA8)
		for i in e_images.size():
			var tile:Image=e_images[i].duplicate()
			tile.convert(Image.FORMAT_RGBA8)
			tile.resize(384,240,Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(tile,Rect2i(0,0,384,240),Vector2i(i%columns*384,i/columns*240))
		print("EFFECTS E sheet rows=",E_KINDS.map(func(e):return e[0])," columns t=",E_TIMES," status=",sheet.save_png("res://artifacts/effects-review-e-sheet.png"))

# Lands the first queued round immediately at its target, as if the flight had just ended.
func land(_travel:float) -> void:
	var shot:Dictionary=battle.effects.projectiles[0]
	battle.effects.clear()
	battle.effects._arrive(shot)

func run() -> void:
	root.size=Vector2i(1440,900)
	if "--only-e" in OS.get_cmdline_user_args():
		await explosion_review()
		finish()
		return
	if "--only-f" in OS.get_cmdline_user_args():
		await remains_review()
		finish()
		return
	open(3)
	# Scene A: firing line on open ground south of the village.
	var rifles:=place("rifle",0,Vector2(46,66))
	var enemy_rifles:=place("rifle",1,Vector2(56,67))
	var tank:=place("tank",0,Vector2(48,58))
	var enemy_tank:=place("tank",1,Vector2(64,67))
	var aa:=place("aa",0,Vector2(50,71))
	var helo:=place("helo",1,Vector2(60,57))
	var javelin:=place("atgm",0,Vector2(44,61))
	for pair in [[rifles,enemy_rifles],[tank,enemy_tank],[aa,helo],[javelin,enemy_tank]]:aim(pair[0],pair[1])
	battle.sim.update_visibility()
	battle.sync_units(5.0)
	view(Vector3(55,0,63),36)
	var clock:={"t":0.0}
	volley(rifles,enemy_rifles,2)
	shoot(tank,enemy_tank,true)
	frame_to(clock,DT)
	await capture("a0-muzzle","t=0: rifle stars and tongues, tank blast with ground dust fan and propellant smoke")
	frame_to(clock,0.05)
	shoot(aa,helo,false)
	frame_to(clock,0.1)
	var travel:float=battle.effects.fire("atgm",Vector3(javelin.pos.x,0.95,javelin.pos.y),Vector3(enemy_tank.pos.x,0.8,enemy_tank.pos.y),true,false,"tank")
	javelin.last_shot=battle.sim.time
	kill(enemy_tank)
	await capture("a1-flight","t=0.1: one rifle tracer, AA rounds, armour sparks, rifle dirt strikes, ATGM backblast")
	frame_to(clock,0.3)
	volley(rifles,enemy_rifles,1)
	frame_to(clock,0.4)
	await capture("a2-missile","t=0.4: ATGM trail, flak puffs, tank smoke drifting, second volley")
	var arrival:=0.1+travel
	frame_to(clock,arrival)
	remove(enemy_tank)
	frame_to(clock,arrival+0.02)
	await capture("a3-detonation","kill: brief core flash and fireball lobes")
	frame_to(clock,arrival+0.35)
	await capture("a4-fireball","+0.35 s: fireball cooling, sparks and debris arcs, ground dust ring")
	frame_to(clock,arrival+1.2)
	await capture("a5-rolling","+1.2 s: rolling soot, radial ground dust, scorch")
	view(Vector3(55,0,60),64)
	await capture("a5-gameplay-zoom","same instant at wide gameplay zoom (64)")
	view(Vector3(55,0,63),36)
	frame_to(clock,arrival+4.0)
	await capture("a6-wreck","+4 s: wreck fire, smoke column drifting with breeze")
	# Scene B: shore and water strikes.
	battle.effects.clear()
	var shore_rifles:=place("rifle",0,Vector2(72,30))
	var shore_tank:=place("tank",0,Vector2(73,24))
	var boat:=place("boat",0,Vector2(86,40))
	var enemy_boat:=place("boat",1,Vector2(88,22))
	for pair in [[shore_rifles,enemy_boat],[shore_tank,enemy_boat],[boat,enemy_boat]]:aim(pair[0],pair[1])
	battle.sim.update_visibility()
	battle.sync_units(5.0)
	view(Vector3(80,0,32),36)
	clock.t=0.0
	for i in shore_rifles.members.size():
		var member:Dictionary=shore_rifles.members[i]
		battle.effects.fire("rifle",Vector3(member.pos.x,0.95,member.pos.y),Vector3(82+i*0.7,0.8,27+i*0.9),false,true,"boat")
	battle.effects.fire("tank",Vector3(shore_tank.pos.x,1.0,shore_tank.pos.y),Vector3(84,0.8,20),false,true,"boat")
	shoot(boat,enemy_boat,true)
	kill(enemy_boat)
	frame_to(clock,0.03)
	await capture("b0-water-fire","t=0: rifle and shell misses into water, naval gun foam ring")
	frame_to(clock,0.15)
	remove(enemy_boat)
	frame_to(clock,0.3)
	await capture("b1-splash-rise","+0.3 s: bullet spouts, shell column rising, boat kill fireball")
	frame_to(clock,0.9)
	await capture("b2-splash-fall","+0.9 s: columns collapsing, foam rings, oil smoke")
	frame_to(clock,2.6)
	await capture("b3-foam","+2.6 s: foam ring and burning hull smoke over water")
	# Scene C: helicopter shot down over land.
	battle.effects.clear()
	var gunship:=place("helo",1,Vector2(50,44))
	var sky_guard:=place("aa",0,Vector2(42,50))
	aim(sky_guard,gunship)
	battle.sim.update_visibility()
	battle.sync_units(5.0)
	view(Vector3(48,0,46),36)
	clock.t=0.0
	shoot(sky_guard,gunship,true)
	frame_to(clock,0.15)
	kill(gunship)
	remove(gunship)
	frame_to(clock,0.2)
	await capture("c0-airburst","AA hits then airburst at altitude with falling smoking fragments")
	frame_to(clock,1.95)
	await capture("c1-crash","wreck strikes ground after the fall")
	# Scene D: Riverside Town (144x108, shore 128) far-east shore through battle.consume_events().
	open(5)
	var land_tank:=place("tank",0,Vector2(116,60))
	var land_rifles:=place("rifle",0,Vector2(119,68))
	var river_boat:=place("boat",0,Vector2(134,58))
	var hostile_tank:=place("tank",1,Vector2(122,80))
	var hostile_boat:=place("boat",1,Vector2(138,78))
	var actors:=[land_tank,land_rifles,river_boat,hostile_tank,hostile_boat]
	if actors.any(func(u):return u.is_empty()):
		push_warning("Riverside effects scene skipped: a spawn point was rejected")
	else:
		for pair in [[land_tank,hostile_tank],[land_rifles,hostile_tank],[river_boat,hostile_boat],[hostile_tank,land_tank]]:aim(pair[0],pair[1])
		battle.sim.update_visibility()
		battle.sync_units(5.0)
		view(Vector3(128,0,70),36)
		clock.t=0.0
		shot_event(land_tank,hostile_tank,true)
		shot_event(land_rifles,hostile_tank,false)
		shot_event(river_boat,hostile_boat,true)
		shot_event(hostile_tank,land_tank,false)
		battle.consume_events()
		frame_to(clock,DT)
		await capture("d0-events-fire","Riverside via consume_events: tank blast on land, naval gun on water, rifle star")
		frame_to(clock,0.3)
		await capture("d1-events-impacts","+0.3 s: armour sparks, shell miss on land, rifle strike")
		destroyed_event(hostile_tank)
		destroyed_event(hostile_boat)
		battle.consume_events()
		remove(hostile_tank)
		remove(hostile_boat)
		frame_to(clock,0.36)
		await capture("d2-events-kill","vehicle and boat kills at the far-east shore")
		frame_to(clock,1.5)
		view(Vector3(128,0,70),64)
		await capture("d3-events-rolling","+1.2 s at gameplay zoom: soot columns near the 144 m map edge stay drawn")
	await explosion_review()
	await remains_review()
	finish()

# Scene F: permanent remains after a sustained fight. Effects are stepped directly so the timing covers only
# BattleEffects._process (including stamping and throttled tile uploads), not unit sync.
func remains_review() -> void:
	open(3)
	battle.effects.shake_enabled=false
	var spot:=Vector3(55,0,63)
	place("tank",0,Vector2(spot.x-12,spot.z-6))
	battle.sim.update_visibility()
	battle.sync_units(5.0)
	var fx=battle.effects
	var rng:=RandomNumberGenerator.new()
	rng.seed=4242
	var weapons:=["tank","atgm","fpv_drone","at_gun","aa","rifle"]
	var costs:Array[float]=[]
	var impacts:=0
	for frame in 600:
		if frame%2==0:
			var weapon:String=weapons[impacts%weapons.size()]
			var to:=spot+Vector3(rng.randf_range(-22,22),0.8,rng.randf_range(-16,16))
			fx.fire(weapon,to+Vector3(-30,0.2,12),to,false,false,"rifle")
			impacts+=1
		if frame%90==45:fx.destroyed("ammo_depot" if frame==405 else "tank",spot+Vector3(rng.randf_range(-15,15),0.7,rng.randf_range(-10,10)))
		var started:=Time.get_ticks_usec()
		fx._process(DT)
		costs.append((Time.get_ticks_usec()-started)/1000.0)
		if frame==300:
			view(spot,40.0)
			await capture("f0-remains-midfight","mid-fight: fresh blasts over accumulating craters, scorch and burn marks")
	for i in 900:fx._process(0.1)
	view(spot,40.0)
	var stats:Dictionary=fx.remains.stats()
	await capture("f1-remains-close","90 s after the fight, all transient effects gone: %d permanent marks in %d tiles, %d landed chunks"%[stats.stamps,stats.tiles,stats.chunks])
	view(spot,64.0)
	await capture("f2-remains-wide","same remains at wide gameplay zoom (64)")
	costs.sort()
	print("EFFECTS REMAINS impacts=",impacts," marks=",stats.stamps," tiles=",stats.tiles," texture_bytes=",stats.texture_bytes," chunks=",stats.chunks,
		" uploads=",stats.uploads," upload_usec_mean=",snappedf(stats.upload_usec_mean,0.1)," upload_usec_max=",stats.upload_usec_max,
		" effects_ms_p50=",costs[costs.size()/2]," effects_ms_p95=",costs[int(costs.size()*0.95)]," effects_ms_max=",costs.back()," native=",not headless)

func finish() -> void:
	var report:={"scenario":"Canal Watch + Riverside Town","viewport":[1440,900],"timestep":DT,"native_images":not headless,"renderer":RenderingServer.get_video_adapter_name(),"captures":captures,"note":"Paused deterministic staging; effects advanced manually at 60 Hz. Not a performance measurement."}
	if not headless and not images.is_empty():
		var sheet:=Image.create(4*480,int(ceil(images.size()/4.0))*300,false,Image.FORMAT_RGBA8)
		for i in images.size():
			var tile:Image=images[i].duplicate()
			tile.convert(Image.FORMAT_RGBA8)
			tile.resize(480,300,Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(tile,Rect2i(0,0,480,300),Vector2i(i%4*480,i/4*300))
		report["sheet_status"]=sheet.save_png("res://artifacts/effects-review-sheet.png")
	FileAccess.open("res://artifacts/effects-review.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("EFFECTS REVIEW COMPLETE native=",not headless)
	quit()
