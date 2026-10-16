extends SceneTree
# Headless audio checks. The dummy audio driver makes no sound, so this asserts structure: the library
# builds within budget, voice pools and per-category caps hold under a large fight, unit loops go to the
# nearest units only, mute silences everything and the battle scene wires events through.
const Sim=preload("res://scripts/simulation.gd")
const AudioFX=preload("res://scripts/audio_fx.gd")
var checks:=0
var errors:=0

func check(value:bool,label:String) -> void:
	checks+=1
	if not value:
		errors+=1
		printerr("FAIL: ",label)

func harbor_index()->int:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		if configs[i].id=="black_sea_harbor":return i
	return -1

func _init() -> void:
	call_deferred("run")

func run() -> void:
	library_checks()
	var sim=Sim.new(false,harbor_index())
	var audio=AudioFX.new()
	audio.setup(sim,null)
	root.add_child(audio)
	var focus:=Vector3(300,0,640)
	audio.frame(1.0/60,focus,Basis(),72.0)
	pool_checks(audio,focus)
	loop_checks(audio,sim,focus)
	cost_checks(audio,focus)
	mute_checks(audio,focus)
	audio.free()
	world_blast_checks(sim)
	await battle_checks()
	print("AUDIO: ",checks," checks, ",errors," failures")
	quit(1 if errors else 0)

func library_checks() -> void:
	var started:=Time.get_ticks_usec()
	var audio=AudioFX.new()
	var built_ms:=(Time.get_ticks_usec()-started)/1000.0
	var stats:Dictionary=audio.stats()
	var seconds:=0.0
	for name in audio.streams:seconds+=audio.streams[name].get_length()
	print("AUDIO synth: %.1f ms for %d sounds, %d samples (%.2f s of audio); construct %.1f ms; calibration loop %.1f ms (reference %.0f)" % [stats.synth_ms,stats.sounds,stats.samples,seconds,built_ms,calibration_ms(),CALIBRATION_REFERENCE_MS])
	var synth_cost:=synthesis_cost_ms(float(stats.synth_ms))
	check(synth_cost<SYNTH_BUDGET_MS,"synthesis stays under %d ms (%.1f)" % [SYNTH_BUDGET_MS,synth_cost])
	check(int(stats.sounds)>=30,"library has weapon, impact, explosion, loop and UI sounds (%d)" % stats.sounds)
	for name in ["rifle","mg","autocannon","tank","at_gun","atgm","rockets","dirt","metal","masonry","splash","boom_s","boom_m","boom_l","crunch","wire","engine","tracks","rotor","buzz","boat","march","work","wind","distant","distant_pop","ui_order","ui_warn","ui_click","ui_deploy"]:
		var stream:AudioStreamWAV=audio.streams.get(name)
		check(stream!=null and stream.data.size()>200 and stream.get_length()>0.03,"sound %s synthesized" % name)
	for name in ["engine","tracks","rotor","buzz","boat","march","work","wind"]:
		var stream:AudioStreamWAV=audio.streams[name]
		check(stream.loop_mode==AudioStreamWAV.LOOP_FORWARD and stream.loop_end*2==stream.data.size(),"%s loops over its whole buffer" % name)
	for kind in AudioFX.FIRE:check(audio.streams.has(AudioFX.FIRE[kind][0]),"weapon %s has a fire sound" % kind)
	var total:=0
	for category in AudioFX.CATEGORY_CAPS:total+=int(AudioFX.CATEGORY_CAPS[category])
	check(total>=AudioFX.ONE_SHOT_VOICES,"category caps cover the shared pool")
	audio.free()

# Wall-clock synthesis time balloons when other processes load the machine. A
# fast first build passes as-is; otherwise the build is repeated between runs of
# a fixed per-sample calibration loop (same op mix as the synth inner loops) and
# the median synth/calibration ratio is scaled to the quiet reference machine.
const SYNTH_BUDGET_MS:=150.0
const CALIBRATION_SAMPLES:=262144
# Unloaded dev Mac: synthesis ~95 ms; under load synthesis ran a median 2.4-3.6x
# (mean 2.9x) the calibration loop, so the loop is ~33 ms there and the 150 ms
# budget is ~4.5x calibration (the same headroom as 150 over 95 ms).
const CALIBRATION_REFERENCE_MS:=33.0

func calibration_ms() -> float:
	var noise:=RandomNumberGenerator.new();noise.seed=11
	var out:=PackedFloat32Array();out.resize(CALIBRATION_SAMPLES)
	var started:=Time.get_ticks_usec()
	var lp:=0.0;var low:=0.0;var phase:=0.0;var previous:=0.0;var envelope:=1.0
	var inv:=1.0/CALIBRATION_SAMPLES
	for i in CALIBRATION_SAMPLES:
		var w:=noise.randf()*2.0-1.0
		lp+=(w-lp)*lerpf(0.4,0.1,i*inv)
		low+=(w-low)*0.03
		phase+=0.05
		var value:=(w-previous)*0.5+lp*2.0*envelope+sin(phase)*0.3+low*1.4
		envelope*=0.9999
		previous=w
		out[i]=clampf(value,-1.0,1.0)
	return (Time.get_ticks_usec()-started)/1000.0

func synthesis_cost_ms(first_ms:float) -> float:
	if first_ms<SYNTH_BUDGET_MS:return first_ms
	var ratios:Array[float]=[]
	var raw:Array[float]=[first_ms]
	var before:=calibration_ms()
	for i in 5:
		var audio=AudioFX.new()
		raw.append(float(audio.stats().synth_ms))
		audio.free()
		var after:=calibration_ms()
		ratios.append(raw[-1]/((before+after)*0.5))
		before=after
	ratios.sort();raw.sort()
	print("AUDIO synth under load: fastest of %d builds %.1f ms; median %.2fx calibration -> %.1f ms on the reference machine" % [raw.size(),raw[0],ratios[2],ratios[2]*CALIBRATION_REFERENCE_MS])
	return minf(raw[0],ratios[2]*CALIBRATION_REFERENCE_MS)

func shot(kind:String, from:Vector2, to:Vector2, hit:bool, target:String, visible:bool=true) -> Dictionary:
	return {"type":"shot","from":from,"to":to,"kind":kind,"target_kind":target,"hit":hit,"from_y":1.0,"to_y":0.8,"visible":visible}

func pool_checks(audio, focus:Vector3) -> void:
	var rng:=RandomNumberGenerator.new();rng.seed=7
	var kinds:=["rifle","rifle","rifle","bunker","aa","tank","boat","at_gun","atgm","helo","drone"]
	var targets:=["rifle","tank","bunker","helo","aa","engineer","ammo_depot"]
	var centre:=Vector2(focus.x,focus.z)
	var worst:=0
	var worst_category:={}
	var over_cap:=false
	var started:=Time.get_ticks_usec()
	for i in 540:
		var event:Dictionary
		if i%27==26:
			var kind:String=["tank","aa","boat","helo","fpv_drone","ammo_depot","bunker","concertina_wire","rifle","hq"][i%10]
			event={"type":"destroyed","kind":kind,"pos":centre+Vector2(rng.randf_range(-40,40),rng.randf_range(-30,30)),"visible":true}
		else:
			var from:=centre+Vector2(rng.randf_range(-45,45),rng.randf_range(-35,35))
			event=shot(kinds[i%kinds.size()],from,from+Vector2(rng.randf_range(-30,30),rng.randf_range(-30,30)),rng.randf()<0.5,targets[i%targets.size()],i%9!=0)
		audio.event(event)
		if i%20==19:audio.frame(1.0/60,focus,Basis(),72.0)
		var stats:Dictionary=audio.stats()
		worst=maxi(worst,int(stats.voices))
		for category in stats.by_category:
			worst_category[category]=maxi(int(worst_category.get(category,0)),int(stats.by_category[category]))
			if int(stats.by_category[category])>int(AudioFX.CATEGORY_CAPS[category]):over_cap=true
	var event_ms:=(Time.get_ticks_usec()-started)/1000.0
	var counters:Dictionary=audio.stats().counters
	print("AUDIO burst: 500 shots + 40 kills in %.1f ms; peak voices %d/%d; per category %s; counters %s" % [event_ms,worst,AudioFX.ONE_SHOT_VOICES,worst_category,counters])
	check(worst<=AudioFX.ONE_SHOT_VOICES,"active one-shot voices stay within the pool (%d)" % worst)
	check(worst>=6,"a big fight actually uses several voices (%d)" % worst)
	check(not over_cap,"no category exceeds its cap")
	check(int(counters.played)>20,"sounds were played (%d)" % counters.played)
	check(int(counters.throttled)+int(counters.capped)>int(counters.played),"most of a 500-shot burst is throttled or capped")
	check(audio.pending.size()<=AudioFX.PENDING_CAPACITY,"delayed impacts stay bounded")
	# Hidden shots feed the distant bed instead of the positional pool.
	for i in 30:
		audio.frame(1.0/30,focus,Basis(),72.0)
		audio.event(shot("tank",centre+Vector2(300,0),centre+Vector2(320,0),false,"tank",true))
		audio.event(shot("rifle",centre+Vector2(5,0),centre+Vector2(15,0),false,"rifle",false))
	check(int(audio.stats().counters.distant)>0,"off-screen and fogged combat plays distant gunfire")
	for i in 400:audio.frame(1.0/60,focus,Basis(),72.0)
	check(audio.active_voices()==0 and audio.pending.is_empty(),"voices and delayed sounds drain after the fight")
	# A nearer explosion replaces the farthest one when its category is full.
	var played:=0
	for i in 8:
		audio.last_start.clear()
		if audio.play_at("boom_m",focus+Vector3(40-i*5,0,0)):played+=1
	check(audio.active_in("explosion")<=int(AudioFX.CATEGORY_CAPS.explosion),"explosion cap holds when nearer blasts replace farther ones")
	check(int(audio.stats().counters.stolen)+int(audio.stats().counters.capped)>0 or played<=4,"a full category steals or drops")
	check(not audio.play_at("rifle",focus+Vector3(500,0,0)),"sounds far outside the view are culled")

func loop_checks(audio, sim, focus:Vector3) -> void:
	var centre:=Vector2(focus.x,focus.z)
	var spawned:=[]
	for i in 12:
		var u:Dictionary=sim.spawn("tank",0,centre+Vector2.from_angle(i*0.9)*(8.0+i*5.0))
		if not u.is_empty():spawned.append(u)
	for i in 3:
		var u:Dictionary=sim.spawn("rifle",0,centre+Vector2(-10+i*6,12))
		if not u.is_empty():spawned.append(u)
	check(spawned.size()>=12,"loop test units spawned (%d)" % spawned.size())
	audio.frame(1.0/60,focus,Basis(),72.0)
	audio.pick_loops(0.25)
	var expected:=nearest(audio,sim,focus,"vehicle",int(AudioFX.LOOP_SLOTS.vehicle),false)
	var got:Array=audio.loop_ids("vehicle")
	got.sort();expected.sort()
	check(got==expected,"engine loops go to the nearest %d vehicles %s (got %s)" % [AudioFX.LOOP_SLOTS.vehicle,expected,got])
	check(got.size()<=int(AudioFX.LOOP_SLOTS.vehicle),"vehicle loops stay within their slots")
	check(audio.loop_ids("tracks").is_empty() and audio.loop_ids("march").is_empty(),"stationary units have no track or footstep loops")
	# Move everything a little: tracks and footsteps follow the nearest movers.
	for u in spawned:u.pos+=Vector2(1.5,0)
	audio.pick_loops(0.25)
	var tracks:Array=audio.loop_ids("tracks")
	check(tracks.size()==int(AudioFX.LOOP_SLOTS.tracks),"track squeal for the nearest moving tanks (%d)" % tracks.size())
	for id in tracks:check(sim.get_unit(id).kind=="tank","track loop is on a tracked vehicle")
	check(audio.loop_ids("march").size()>=1 and audio.loop_ids("march").size()<=int(AudioFX.LOOP_SLOTS.march),"footsteps for the nearest marching sections")
	var moved:=Vector3(focus.x+400,0,focus.z)
	audio.frame(1.0/60,moved,Basis(),72.0)
	audio.pick_loops(0.25)
	for group in AudioFX.LOOP_SLOTS:
		for id in audio.loop_ids(group):check(Vector2(sim.get_unit(id).pos.x-moved.x,sim.get_unit(id).pos.y-moved.z).length()<=audio.hear,"loop %s units stay within hearing after the camera moves" % group)
	audio.frame(1.0/60,focus,Basis(),72.0)
	audio.pick_loops(0.25)
	var active:=0
	for group in AudioFX.LOOP_SLOTS:active+=audio.loop_ids(group).size()
	var cap:=0
	for group in AudioFX.LOOP_SLOTS:cap+=int(AudioFX.LOOP_SLOTS[group])
	check(active<=cap,"all unit loops within %d slots (%d)" % [cap,active])
	# Pausing fades the loops out and releases their voices.
	for i in 90:audio.frame(1.0/30,focus,Basis(),72.0,false)
	var paused_loops:=0
	for group in AudioFX.LOOP_SLOTS:paused_loops+=audio.loop_ids(group).size()
	check(paused_loops==0,"paused battle releases unit loops (%d left)" % paused_loops)
	audio.frame(1.0/60,focus,Basis(),72.0)
	audio.pick_loops(0.25)
	# A unit that dies loses its loop on the next frame.
	var victim:int=audio.loop_ids("vehicle")[0]
	sim.get_unit(victim).hp=0.0
	audio.frame(1.0/60,focus,Basis(),72.0)
	check(not audio.loop_ids("vehicle").has(victim),"a destroyed vehicle's engine loop stops")

func nearest(audio, sim, focus:Vector3, group:String, count:int, moving:bool) -> Array:
	var list:=[]
	for u in sim.units:
		if u.hp<=0.0 or (u.team!=0 and not u.visible) or not AudioFX.LOOPS.has(u.kind) or AudioFX.LOOPS[u.kind][0]!=group:continue
		var d:float=Vector2(u.pos.x-focus.x,u.pos.y-focus.z).length()
		if d<=audio.hear:list.append([d,u.id])
	list.sort_custom(func(a,b):return a[0]<b[0])
	return list.slice(0,count).map(func(entry):return entry[1])

func cost_checks(audio, focus:Vector3) -> void:
	var started:=Time.get_ticks_usec()
	for i in 600:audio.frame(1.0/60,focus,Basis(),72.0)
	var per_frame:=(Time.get_ticks_usec()-started)/600.0
	var loops:=0
	for group in AudioFX.LOOP_SLOTS:loops+=audio.loop_ids(group).size()
	print("AUDIO frame: %.1f us per frame with %d unit loops (includes loop re-pick every %.2f s over %d units)" % [per_frame,loops,AudioFX.LOOP_PICK_SECONDS,audio.sim.units.size()])
	check(per_frame<500.0,"per-frame audio update is cheap (%.1f us)" % per_frame)

func mute_checks(audio, focus:Vector3) -> void:
	audio.set_muted(true)
	check(not audio.play_at("boom_l",focus),"muted layer plays nothing")
	audio.frame(1.0/60,focus,Basis(),72.0)
	var loops:=0
	for group in AudioFX.LOOP_SLOTS:loops+=audio.loop_ids(group).size()
	check(loops==0 and audio.active_voices()==0 and not audio.ambience.playing,"mute stops loops, voices and ambience")
	audio.set_muted(false)
	audio.last_start.clear()
	check(audio.play_at("boom_l",focus),"unmuted layer plays again")

# World blasts (StructureDamage.explosion): the enemy mortar has its own whistle and crump, a collapse is voiced
# only by its building_collapse rumble, a cook-off string by the depot.
const FieldOps=preload("res://scripts/field_ops.gd")
func world_blast_checks(sim) -> void:
	var audio=AudioFX.new()
	audio.setup(sim,null)
	root.add_child(audio)
	for name in ["mortar","whistle"]:
		var stream:AudioStreamWAV=audio.streams.get(name)
		check(stream!=null and stream.data.size()>200,"sound %s synthesized" % name)
	check(absf(audio.streams.whistle.get_length()-AudioFX.WHISTLE_LEAD)<0.02,"whistle lasts the %.2f s lead" % AudioFX.WHISTLE_LEAD)
	var focus:=Vector3(300,0,640)
	var centre:=Vector2(focus.x,focus.z)
	var step:=func(dt:float, running:bool=true):audio.frame(dt,focus,Basis(),72.0,running)
	step.call(1.0/60)
	# A real salvo: rounds queued by FieldOps.enemy_mortar whistle down, then burst as world_blast "mortar".
	var rng:=RandomNumberGenerator.new();rng.seed=1
	sim.events.clear()
	var land:=centre
	for k in 40:
		if not sim.terrain.is_water(land):break
		land=centre+Vector2(rng.randf_range(-30,30),rng.randf_range(-30,30))
	sim.field_ops["mortar"]={"next":sim.time+1000.0,"rounds":[{"at":sim.time+2.0,"pos":land}],"rng":rng}
	var impact:float=sim.time+2.0
	step.call(1.0/60)
	check(not audio.last_start.has("whistle"),"no whistle while the round is still high")
	sim.time=impact-0.5
	step.call(1.0/60,false)
	check(not audio.last_start.has("whistle"),"no whistle while the game is paused")
	step.call(1.0/60)
	check(audio.last_start.has("whistle") and float(audio.last_start.whistle)==audio.clock,"incoming round whistles before impact")
	var whistle_at:float=audio.clock
	step.call(0.1)
	check(float(audio.last_start.whistle)==whistle_at,"each round whistles once")
	sim.time=impact
	FieldOps.enemy_mortar(sim)
	var blasts:Array=sim.events.filter(func(e):return e.type=="world_blast")
	check(blasts.size()==1 and blasts[0].kind=="mortar","enemy mortar bursts as world_blast kind mortar")
	var booms:={}
	for name in ["boom_s","boom_m","boom_l"]:booms[name]=float(audio.last_start.get(name,-1.0))
	for e in sim.events:audio.event(e)
	sim.events.clear()
	check(audio.last_start.has("mortar") and float(audio.last_start.mortar)>whistle_at,"the mortar crump follows its whistle")
	check(booms.keys().all(func(n):return float(audio.last_start.get(n,-1.0))==booms[n]),"a mortar bomb is not voiced as a vehicle kill")
	for i in 60:step.call(1.0/60)
	check(float(audio.last_start.get("dirt",-1.0))>float(audio.last_start.mortar),"soil rains down after the crump")
	sim.field_ops.erase("mortar")
	# Collapse: exactly the events structure_damage.gd emits; only the rumble plays.
	for i in 120:step.call(1.0/60)
	audio.last_start.clear()
	var played:int=audio.counters.played
	audio.event({"type":"building_collapse","building":7,"pos":centre+Vector2(4,-4),"bounds":Rect2(centre+Vector2(-2,-8),Vector2(12,8)),"height":9.0,"killed":0,"survivors":0,"visible":true})
	audio.event({"type":"world_blast","kind":"collapse","pos":centre+Vector2(4,-4),"radius":6.0,"visible":true})
	for i in 30:step.call(1.0/60)
	check(audio.last_start.has("rumble") and audio.counters.played>played,"a collapse rumbles")
	check(not audio.last_start.has("boom_l") and not audio.last_start.has("boom_m") and not audio.last_start.has("mortar"),"a collapse plays no tank-kill or blast sound")
	for i in 120:step.call(1.0/60)
	audio.last_start.clear()
	audio.event({"type":"world_blast","kind":"cook_off","pos":centre,"radius":4.0,"visible":true})
	check(audio.last_start.is_empty(),"cook-off world blasts are voiced by the depot, not here")
	audio.event({"type":"world_blast","kind":"crash","pos":centre,"radius":5.0,"visible":true})
	check(audio.last_start.has("boom_l"),"an airframe crash booms")
	var heat:float=audio.distant_heat
	audio.event({"type":"world_blast","kind":"mortar","pos":centre+Vector2(200,0),"radius":3.0,"visible":true})
	check(audio.distant_heat>heat,"a far mortar bomb is heard as distant combat")
	audio.free()

func battle_checks() -> void:
	root.size=Vector2i(1280,720)
	var battle=load("res://scenes/main.tscn").instantiate();root.add_child(battle);current_scene=battle
	await process_frame;await process_frame
	check(battle.audio!=null and battle.audio.is_inside_tree(),"battle creates the audio layer")
	var audio=battle.audio
	battle.paused=false;battle.show_help=false
	var focus:Vector3=battle.camera_focus
	var centre:=Vector2(focus.x,focus.z)
	battle.sim.events.append(shot("tank",centre,centre+Vector2(12,4),true,"tank"))
	battle.sim.events.append({"type":"destroyed","kind":"tank","pos":centre+Vector2(12,4),"visible":true})
	battle.sim.events.append({"type":"warning","text":"test warning"})
	var before:int=audio.stats().counters.played
	var ui_before:int=audio.stats().counters.ui
	battle.consume_events()
	await process_frame
	check(int(audio.stats().counters.played)>before,"battle events reach the audio layer")
	check(int(audio.stats().counters.ui)>ui_before,"warnings chime")
	# A collapse through battle (ruined_building.show_damage) relays no fake vehicle kill to the audio layer.
	for i in 600:
		if audio.pending.is_empty():break
		audio.frame(1.0/60,focus,Basis(),72.0)
	audio.frame(1.0,focus,Basis(),72.0)
	audio.last_start.clear()
	battle.sim.events.append({"type":"world_blast","kind":"collapse","pos":centre+Vector2(6,0),"radius":6.0,"visible":true})
	battle.consume_events()
	var booms:=["boom_s","boom_m","boom_l"]
	check(not booms.any(func(n):return audio.last_start.has(n) or audio.pending.any(func(item):return item[1]==n)),"a collapse blast through battle is not voiced as a tank kill")
	battle.ping()
	check(int(audio.stats().counters.ui)>ui_before+1,"order ping goes through the audio layer")
	var key:=InputEventKey.new();key.keycode=KEY_M;key.physical_keycode=KEY_M;key.pressed=true
	battle._input(key)
	check(battle.effects.muted and audio.silent() and audio.active_voices()==0,"M mutes the audio layer")
	battle._input(key)
	check(not battle.effects.muted and not audio.silent(),"M again unmutes")
	for i in 5:await process_frame
	battle.queue_free()
	for i in 5:await process_frame
