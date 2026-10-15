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
	print("AUDIO synth: %.1f ms for %d sounds, %d samples (%.2f s of audio); construct %.1f ms" % [stats.synth_ms,stats.sounds,stats.samples,seconds,built_ms])
	check(float(stats.synth_ms)<150.0,"synthesis stays under 150 ms (%.1f)" % stats.synth_ms)
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
