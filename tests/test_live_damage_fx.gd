extends SceneTree
# Live damaged vehicles: burning hulls vent flame and black smoke until the fire
# is out, other damage trails thin grey smoke, flooding hulls list and throw
# spray, crashing/wrecked gunships smoke, emitters are capped and fade with the
# view, hidden enemies show nothing, and battle.gd binds without a hook.
const Sim=preload("res://scripts/simulation.gd")
const Effects=preload("res://scripts/effects.gd")
const Visuals=preload("res://scripts/visuals.gd")
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func harbor_index()->int:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		if configs[i].id=="black_sea_harbor":return i
	return -1

func _init()->void:
	Sim.scenario_selection=harbor_index()
	call_deferred("run")

# First spawnable spot on a widening ring around `near`.
func place(sim,kind:String,team:int,near:Vector2)->Dictionary:
	for ring in 12:
		for step in 8:
			var u:Dictionary=sim.spawn(kind,team,near+Vector2.RIGHT.rotated(step*TAU/8)*ring*6.0)
			if not u.is_empty():return u
	return {}

func boat_spot(sim)->Vector2:
	for u in sim.units:
		if u.kind=="boat":return u.pos+Vector2(0,30)
	return Vector2(80,640)

func advance(effects,seconds:float,dt:float=1.0/60.0)->void:
	for i in int(round(seconds/dt)):effects._process(dt)

func mode_of(effects,id:int)->int:
	for e in effects.live_emitters:
		if e.u.id==id:return e.mode
	return -1

# Live volume particles of `kind` within `reach` m (ground plane) of pos.
func near(pool,kind:int,pos:Vector2,reach:float)->int:
	var n:=0
	for i in pool.capacity:
		if pool.life[i]>0 and pool.kind[i]==kind and Vector2(pool.pos[i].x,pool.pos[i].z).distance_to(pos)<reach:n+=1
	return n

func dark_smoke(pool,pos:Vector2,reach:float)->int:
	var n:=0
	for i in pool.capacity:
		if pool.life[i]>0 and pool.kind[i]==Effects.SMOKE and pool.color[i].v<0.2 and Vector2(pool.pos[i].x,pool.pos[i].z).distance_to(pos)<reach:n+=1
	return n

func run()->void:
	var sim=Sim.new(false,harbor_index())
	var effects=Effects.new()
	root.add_child(effects)
	effects.muted=true
	var boat:Dictionary=place(sim,"boat",0,boat_spot(sim))
	var tank:Dictionary=place(sim,"tank",0,Vector2(300,640))
	var sound:Dictionary=place(sim,"tank",0,Vector2(300,660))
	var helo:Dictionary=place(sim,"helo",0,Vector2(330,640))
	check(not boat.is_empty() and not tank.is_empty() and not sound.is_empty() and not helo.is_empty(),"test units spawned")
	var boat_root:=Node3D.new();root.add_child(boat_root)
	var helo_root:=Node3D.new();root.add_child(helo_root)
	effects.watch(sim,{boat.id:boat_root,helo.id:helo_root})
	advance(effects,0.5)
	check(effects.live_emitters.is_empty(),"no live emitters while every hull is sound (%d)" % effects.live_emitters.size())

	# --- burning: flame and black smoke from the engine deck, stopping when out
	boat["fire_until"]=sim.time+30.0
	advance(effects,2.0)
	check(mode_of(effects,boat.id)==Effects.LIVE_FIRE,"burning corvette gets a fire emitter")
	var flames:=near(effects.volume,Effects.FIRE,boat.pos,4.0)
	var black:=dark_smoke(effects.volume,boat.pos,8.0)
	check(flames>=1,"burning hull shows flame (%d)" % flames)
	check(black>=4,"burning hull vents black smoke (%d)" % black)
	boat.fire_until=sim.time-1.0
	advance(effects,1.0)
	check(mode_of(effects,boat.id)<0,"fire out: emitter released")
	check(near(effects.volume,Effects.FIRE,boat.pos,4.0)==0,"fire out: no flame left after 1 s")
	effects.clear()

	# --- damaged but not burning: thin grey smoke, no fire
	tank.mobility_kill=true
	advance(effects,2.0)
	check(mode_of(effects,tank.id)==Effects.LIVE_DAMAGED,"immobilised tank trails damage smoke")
	check(mode_of(effects,sound.id)<0,"sound tank has no emitter")
	check(near(effects.volume,Effects.SMOKE,tank.pos,6.0)>=2,"damaged tank smokes")
	check(near(effects.volume,Effects.FIRE,tank.pos,6.0)==0,"damaged tank is not on fire")
	check(dark_smoke(effects.volume,tank.pos,6.0)==0,"damage smoke is grey, not black")
	tank.mobility_kill=false
	advance(effects,0.3)
	check(mode_of(effects,tank.id)<0,"repaired tank stops smoking")
	effects.clear()

	# --- battle.gd's per-vehicle damage_smoke is owned by the live emitters once bound
	var before:int=effects.volume.live
	effects.damage_smoke(Vector3(10,1,10),0.1)
	check(effects.volume.live==before,"bound: legacy damage_smoke is ignored")
	var loose=Effects.new();root.add_child(loose);loose.muted=true
	loose._process(1.0/60.0)
	loose.damage_smoke(Vector3(10,1,10),0.1)
	check(loose.volume.live>0,"unbound: legacy damage_smoke still emits")
	loose.free()

	# --- flooding: hull lists, settles and throws spray; sinking levels the root again
	boat.flood=0.5;boat.flood_rate=0.03;boat.altitude=-0.65
	advance(effects,2.0)
	check(mode_of(effects,boat.id)==Effects.LIVE_FLOOD,"flooding corvette gets a flood emitter")
	check(near(effects.volume,Effects.SPRAY,boat.pos,6.0)>=1,"flooding hull throws spray")
	var up:Vector3=boat_root.basis.y
	var tilt:=rad_to_deg(up.angle_to(Vector3.UP))
	check(tilt>5.0 and tilt<20.0,"flooding hull lists visibly (%.1f deg)" % tilt)
	boat.flood=1.0
	advance(effects,0.3)
	var full:=rad_to_deg(boat_root.basis.y.angle_to(Vector3.UP))
	check(full>tilt,"list grows as the hull fills (%.1f -> %.1f deg)" % [tilt,full])
	boat.hp=0.0
	advance(effects,0.3)
	check(boat_root.basis==Basis.IDENTITY,"sunk hull root is levelled")
	check(mode_of(effects,boat.id)<0,"sunk hull without a wreck releases its emitter")
	effects.clear()

	# --- gunship going down, then its wreck smoking for a while
	helo["crash"]="spin";helo.altitude=6.0
	advance(effects,1.0)
	check(mode_of(effects,helo.id)==Effects.LIVE_CRASH,"crashing gunship gets a crash emitter")
	check(dark_smoke(effects.volume,helo.pos,8.0)>=4,"crashing gunship trails black smoke")
	var bank:=rad_to_deg(helo_root.basis.y.angle_to(Vector3.UP))
	check(bank>10.0,"spinning gunship banks (%.1f deg)" % bank)
	helo.erase("crash");helo.hp=0.0;helo.altitude=0.0;helo["wrecked"]=true
	advance(effects,1.0)
	check(helo_root.basis==Basis.IDENTITY,"wreck root is levelled")
	check(mode_of(effects,helo.id)==Effects.LIVE_WRECK,"helo wreck smokes")
	check(near(effects.volume,Effects.SMOKE,helo.pos,6.0)>=1,"helo wreck smoke present")
	advance(effects,Effects.LIVE_WRECK_SECONDS,0.1)
	check(mode_of(effects,helo.id)<0,"helo wreck smoke ends after %d s" % Effects.LIVE_WRECK_SECONDS)
	effects.clear()

	# --- hidden enemies show nothing
	var enemy:Dictionary=place(sim,"tank",1,Vector2(300,700))
	enemy.firepower_kill=true;enemy.visible=false
	advance(effects,0.5)
	check(mode_of(effects,enemy.id)<0,"hidden damaged enemy has no emitter")
	enemy.visible=true
	advance(effects,0.3)
	check(mode_of(effects,enemy.id)==Effects.LIVE_DAMAGED,"spotted damaged enemy smokes")
	effects.clear()

	# --- cap and priority: 20 damaged tanks and one fire -> 12 emitters, the fire kept
	var crowd:Array=[]
	for i in 20:
		var t:Dictionary=place(sim,"tank",0,Vector2(260+i*5,600))
		t.mobility_kill=true
		crowd.append(t)
	# The farthest tank of the row burns: beyond the 12 nearest, but fire ranks ahead.
	var burning:Dictionary=crowd.back()
	burning["fire_until"]=sim.time+30.0
	effects.view_focus=Vector3(crowd[0].pos.x,0,crowd[0].pos.y);effects.view_radius=200.0
	var started:=Time.get_ticks_usec()
	advance(effects,4.0)
	var per_frame:=float(Time.get_ticks_usec()-started)/240.0
	check(effects.live_emitters.size()==Effects.LIVE_CAPACITY,"emitters capped at %d (%d)" % [Effects.LIVE_CAPACITY,effects.live_emitters.size()])
	check(mode_of(effects,burning.id)==Effects.LIVE_FIRE,"fire outranks nearer light damage under the cap (%.0f m out)" % burning.pos.distance_to(crowd[0].pos))
	check(mode_of(effects,crowd[18].id)<0,"farthest light damage is dropped under the cap")
	var stats:Dictionary=effects.stats()
	check(stats.volume<Effects.VOLUME_CAPACITY*0.5,"12 emitters use under half the volume pool (%d)" % stats.volume)
	# Poller alone (scan every LIVE_SCAN s + 12 emitters), with the whole harbor force in sim.units.
	var poll_started:=Time.get_ticks_usec()
	for i in 600:effects._update_live(1.0/60.0)
	var poll:=float(Time.get_ticks_usec()-poll_started)/600.0
	var scan_started:=Time.get_ticks_usec()
	for i in 100:effects._live_scan(sim)
	var scan:=float(Time.get_ticks_usec()-scan_started)/100.0
	print("LIVE FX poll: %.1f us per frame, scan %.1f us over %d units (every %.1f s)" % [poll,scan,sim.units.size(),Effects.LIVE_SCAN])
	check(poll<200.0,"poller stays cheap (%.1f us per frame)" % poll)
	print("LIVE FX: 12 emitters, %d volume / %d glow live, %.1f us per frame (effects._process total)" % [stats.volume,stats.glow,per_frame])

	# --- fade with view distance and zoom
	effects.clear()
	effects.view_focus=Vector3(300,0,620);effects.view_radius=30.0;effects.view_zoom=1.0
	check(is_equal_approx(effects.view_fade(Vector3(300,0,625)),1.0),"in view: full rate")
	var edge:float=effects.view_fade(Vector3(300+30.0,0,620))
	check(edge>0.0 and edge<1.0,"view edge: partial (%.2f)" % edge)
	check(effects.view_fade(Vector3(300+60.0,0,620))==0.0,"far outside view: nothing")
	effects.view_focus=Vector3(1000,0,1000)
	advance(effects,1.0)
	check(effects.live_emitters.is_empty(),"off-screen damage spawns no emitters")
	check(effects.volume.live==0,"off-screen damage spawns no particles (%d)" % effects.volume.live)
	effects.view_focus=Vector3(300,0,620);effects.view_radius=200.0;effects.view_zoom=Effects.LIVE_MIN_ZOOM
	advance(effects,0.3);effects.volume.clear();effects.glow.clear()
	advance(effects,2.0)
	var thin:int=effects.volume.live
	effects.view_zoom=1.0
	advance(effects,0.3);effects.volume.clear();effects.glow.clear()
	advance(effects,2.0)
	var dense:int=effects.volume.live
	check(thin<dense,"zoomed far out thins the emitters (%d < %d)" % [thin,dense])
	effects.clear()
	effects.free()

	# --- battle.gd binds through the parent: no hook, real nodes listed and levelled
	await battle_checks()
	print("LIVE DAMAGE FX: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)

func battle_checks()->void:
	root.size=Vector2i(1280,720)
	var battle=load("res://scenes/main.tscn").instantiate();root.add_child(battle);current_scene=battle
	var sim=battle.sim
	battle.paused=false;battle.show_help=false;battle.effects.muted=true
	var boat:Dictionary=place(sim,"boat",0,boat_spot(sim))
	battle.camera_focus=Vector3(boat.pos.x,0,boat.pos.y);battle.camera_size=40.0;battle.camera_zoom_target=40.0;battle.update_camera()
	await process_frame;await process_frame
	boat.flood=0.6;boat.flood_rate=0.0;boat.altitude=-0.78
	boat.fire_until=sim.time+60.0
	for i in 30:await process_frame
	var node:Node3D=battle.nodes.get(boat.id)
	check(battle.effects.live_bound,"effects binds to battle.sim through its parent")
	check(mode_of(battle.effects,boat.id)==Effects.LIVE_FIRE,"battle: burning corvette has a live emitter")
	check(battle.effects.view_radius<200.0 and battle.effects.view_radius>10.0,"battle: view radius from the camera (%.1f)" % battle.effects.view_radius)
	check(node!=null and rad_to_deg(node.basis.y.angle_to(Vector3.UP))>5.0,"battle: flooding hull node lists")
	check(node!=null and node.position.y<-0.5,"battle: flooding hull sits low (y %.2f)" % (node.position.y if node else 0.0))
	boat.hp=0.0
	for i in 20:await process_frame
	check(node.basis==Basis.IDENTITY,"battle: lost hull root levelled")
	battle.queue_free()
	await process_frame
