extends Node3D
# Procedural battlefield audio. Every sound is synthesized once at load into an AudioStreamWAV (no audio
# files) and replayed through fixed voice pools:
#   - ONE_SHOT_VOICES positional voices for weapons, impacts, explosions and props, with per-category caps
#     and per-sound minimum intervals so a large fight cannot stack hundreds of sounds;
#   - LOOP_SLOTS per-unit loops (engines, rotors, drones, tracks, footsteps, construction) given only to the
#     nearest units around the camera focus and re-picked a few times per second;
#   - DISTANT_VOICES muffled voices for combat outside the view or under fog, one ambience bed and UI voices.
# Positional voices are AudioStreamPlayer3D heard by an AudioListener3D that floats above the camera focus
# (higher when zoomed out), so distance lowers volume and the built-in air-absorption shelf dulls far sounds.
# battle.gd owns the hooks: setup() before add_child, event() per sim event, frame() once per rendered frame.
const Effects:=preload("res://scripts/effects.gd")

const MASTER_DB:=-4.0
const ONE_SHOT_VOICES:=16
const DISTANT_VOICES:=2
const UI_VOICES:=2
const CATEGORY_CAPS:={"small":5,"heavy":4,"launch":2,"impact":4,"explosion":4,"misc":2}
const PRIORITY:={"small":0,"impact":1,"misc":1,"launch":2,"heavy":3,"explosion":4}
const LOOP_SLOTS:={"vehicle":6,"tracks":2,"march":2,"work":2}
const LOOP_PICK_SECONDS:=0.25
const PENDING_CAPACITY:=48
# sound -> category, level relative to MASTER_DB and minimum seconds between two starts of that sound.
const SOUNDS:={
	"rifle":{"cat":"small","db":-10.0,"gap":0.045},
	"mg":{"cat":"small","db":-9.0,"gap":0.16},
	"autocannon":{"cat":"heavy","db":-8.0,"gap":0.12},
	"tank":{"cat":"heavy","db":-3.0,"gap":0.1},
	"at_gun":{"cat":"heavy","db":-4.0,"gap":0.1},
	"atgm":{"cat":"launch","db":-8.0,"gap":0.2},
	"rockets":{"cat":"launch","db":-7.0,"gap":0.18},
	"dirt":{"cat":"impact","db":-13.0,"gap":0.06},
	"metal":{"cat":"impact","db":-14.0,"gap":0.07},
	"masonry":{"cat":"impact","db":-13.0,"gap":0.08},
	"splash":{"cat":"impact","db":-12.0,"gap":0.1},
	"boom_s":{"cat":"explosion","db":-6.0,"gap":0.08},
	"boom_m":{"cat":"explosion","db":-3.0,"gap":0.1},
	"boom_l":{"cat":"explosion","db":0.0,"gap":0.15},
	"crunch":{"cat":"misc","db":-8.0,"gap":0.1},
	"thud":{"cat":"impact","db":-8.0,"gap":0.12},
	"debris":{"cat":"impact","db":-9.0,"gap":0.35},
	"rumble":{"cat":"explosion","db":-1.0,"gap":0.8},
	"wire":{"cat":"misc","db":-10.0,"gap":0.15},
}
# shot kind -> [sound, pitch, db offset]
const FIRE:={"rifle":["rifle",1.0,0.0],"drone":["rifle",1.3,-3.0],"bunker":["mg",1.0,0.0],"aa":["autocannon",1.0,0.0],
	"tank":["tank",1.0,0.0],"boat":["tank",1.35,-2.0],"at_gun":["at_gun",1.0,0.0],"atgm":["atgm",1.0,0.0],"helo":["rockets",1.0,0.0]}
# unit kind -> [loop group, stream, pitch, db]
const LOOPS:={"tank":["vehicle","engine",1.0,-10.0],"aa":["vehicle","engine",1.2,-11.0],"harvester":["vehicle","engine",0.9,-11.0],
	"helo":["vehicle","rotor",1.0,-9.0],"drone":["vehicle","buzz",1.0,-17.0],"fpv_drone":["vehicle","buzz",1.35,-13.0],"boat":["vehicle","boat",1.0,-10.0],
	"rifle":["march","march",1.0,-21.0],"atgm":["march","march",0.95,-21.0],"engineer":["march","march",1.05,-21.0]}
const TRACKED:=["tank","aa","harvester"]
const SITE_STATES:=["BUILDING"]
const WORK_STATES:=["CLEARING"]
const FIELD_DESTROYED:={"concertina_wire":["wire",1.0,0.0],"camouflage_net":["crunch",1.3,-4.0],"fighting_trench":["dirt",0.6,6.0],
	"vehicle_berm":["dirt",0.55,6.0],"tank_obstacles":["crunch",0.8,0.0],"tactical_cover":["crunch",0.9,0.0],"ammo_depot":["boom_l",0.9,2.0]}

var sim=null
var effects=null
var muted:=false
var master_db:=MASTER_DB
var clock:=0.0
var streams:Dictionary={}
var synth_ms:=0.0
var synth_samples:=0
var rng:=RandomNumberGenerator.new()
var listener:=AudioListener3D.new()
var focus:=Vector3.ZERO
var zoom:=72.0
var hear:=80.0
var live:=true
# One-shot voice pool: parallel arrays indexed by voice.
var voices:Array[AudioStreamPlayer3D]=[]
var voice_cat:Array[String]=[]
var voice_until:PackedFloat32Array=PackedFloat32Array()
var voice_dist:PackedFloat32Array=PackedFloat32Array()
var last_start:Dictionary={}
var pending:Array=[] # [due, sound, pos, pitch, db, impact]
var loop_slots:Dictionary={} # group -> Array of slot dictionaries
var loop_clock:=0.0
var loop_positions:Dictionary={}
var distant:Array[AudioStreamPlayer3D]=[]
var distant_next:=0
var distant_clock:=0.0
var distant_heat:=0.0
var distant_heavy:=0.0
var distant_pos:=Vector3.ZERO
var ambience:=AudioStreamPlayer.new()
var ui_players:Array[AudioStreamPlayer]=[]
var ui_next:=0
var was_silent:=false
var building_states:Dictionary={} # building id -> last heard damage state
var collapse_heard:Dictionary={} # collapse centre -> clock
var counters:={"played":0,"throttled":0,"capped":0,"stolen":0,"culled":0,"distant":0,"ui":0}

func setup(simulation, effect_layer=null) -> void:
	sim=simulation
	effects=effect_layer

func _init() -> void:
	rng.seed=2207
	var started:=Time.get_ticks_usec()
	build_library()
	synth_ms=(Time.get_ticks_usec()-started)/1000.0
	for i in ONE_SHOT_VOICES:
		var player:=_spatial()
		voices.append(player)
		voice_cat.append("")
	voice_until.resize(ONE_SHOT_VOICES)
	voice_dist.resize(ONE_SHOT_VOICES)
	for i in DISTANT_VOICES:distant.append(_spatial())
	for group in LOOP_SLOTS:
		var slots:Array=[]
		for i in LOOP_SLOTS[group]:slots.append({"player":_spatial(),"id":-1,"db":-60.0,"pitch":1.0,"base_db":0.0,"base_pitch":1.0,"speed":0.0})
		loop_slots[group]=slots
	for i in UI_VOICES:
		var player:=AudioStreamPlayer.new()
		ui_players.append(player)
		add_child(player)
	ambience.stream=streams.wind
	add_child(ambience)
	add_child(listener)

func _spatial() -> AudioStreamPlayer3D:
	var player:=AudioStreamPlayer3D.new()
	player.attenuation_model=AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.panning_strength=0.6
	# Air absorption: the high shelf deepens as distance attenuation grows, so far sounds are duller.
	player.attenuation_filter_cutoff_hz=2400.0
	player.attenuation_filter_db=-30.0
	add_child(player)
	return player

func _ready() -> void:
	listener.make_current()
	_place_listener()

func silent() -> bool:
	return muted or (effects!=null and effects.muted)

func set_muted(value:bool) -> void:
	muted=value
	if silent():_stop_all()

func _stop_all() -> void:
	for player in voices:player.stop()
	for player in distant:player.stop()
	for group in loop_slots:
		for slot in loop_slots[group]:
			slot.player.stop();slot.id=-1;slot.db=-60.0
	ambience.stop()
	pending.clear()
	voice_until.fill(0.0)

# ---------------------------------------------------------------- per-frame update
# focus: camera ground focus; view: camera basis (listener orientation); size: orthographic camera size.
func frame(dt:float, view_focus:Vector3, view:Basis, size:float, running:bool=true) -> void:
	clock+=dt
	focus=view_focus
	zoom=maxf(size,1.0)
	hear=zoom*1.15
	live=running
	if silent():
		if not was_silent:_stop_all()
		was_silent=true
		return
	was_silent=false
	listener.basis=view.orthonormalized()
	_place_listener()
	if not ambience.playing and is_inside_tree():ambience.play(rng.randf()*2.0)
	var wind:float=sim.weather.wind.length() if sim!=null else 0.0
	ambience.volume_db=master_db-27.0+clampf(wind/8.0,0.0,1.0)*6.0+clampf((zoom-40.0)/120.0,0.0,1.0)*4.0
	_run_pending()
	_update_distant(dt)
	loop_clock-=dt
	if loop_clock<=0.0 and live:
		loop_clock=LOOP_PICK_SECONDS
		pick_loops(LOOP_PICK_SECONDS)
	_update_loops(dt)

func _place_listener() -> void:
	listener.position=focus+Vector3.UP*(12.0+zoom*0.45)

func _ear_distance(pos:Vector3) -> float:
	return pos.distance_to(listener.position)

func _ground_distance(pos:Vector3) -> float:
	return Vector2(pos.x-focus.x,pos.z-focus.z).length()

func _attenuate(player:AudioStreamPlayer3D, reach:float) -> void:
	var height:=12.0+zoom*0.45
	player.unit_size=height*0.8
	player.max_distance=sqrt(height*height+reach*reach)

# ---------------------------------------------------------------- sim events
func event(e:Dictionary) -> void:
	if silent():return
	match String(e.get("type","")):
		"shot":_shot(e)
		"destroyed":_destroyed(e)
		"crushed":
			var p:Vector2=e.get("pos",Vector2.ZERO)
			play_at("crunch",Vector3(p.x,0.5,p.y),rng.randf_range(0.85,1.1))
		"warning":ui("warn")
		"reinforcement":ui("deploy")
		"building_damage":_building_hit(e)
		"building_collapse":_building_collapse(e)

func _shot(e:Dictionary) -> void:
	var kind:String=e.get("kind","rifle")
	if kind=="fpv_drone":return # The dive is the buzz loop; the strike arrives as a destroyed event.
	var from:Vector2=e.from
	var to:Vector2=e.to
	var a:=Vector3(from.x,float(e.get("from_y",1.0)),from.y)
	var b:=Vector3(to.x,float(e.get("to_y",0.8)),to.y)
	var spec:Array=FIRE.get(kind,FIRE.rifle)
	var weapon:Dictionary=Effects.WEAPONS.get(kind,Effects.WEAPONS.rifle)
	var heavy:bool=weapon["class"] in ["cannon","naval","atgun","missile","rocket"]
	if not bool(e.get("visible",true)) or _ground_distance(a)>hear:
		_distant(a,1.0 if heavy else 0.25,heavy)
		return
	play_at(spec[0],a,float(spec[1])*rng.randf_range(0.95,1.05),float(spec[2]))
	# The impact lands when the round arrives, matching the visible projectile.
	var water:bool=sim!=null and sim.terrain.is_water(to)
	var surface:=_surface(bool(e.get("hit",true)),water,String(e.get("target_kind","")),b,heavy)
	var delay:=a.distance_to(b)/maxf(float(weapon.speed),1.0)
	_impact(surface,b,heavy,delay)

func _surface(hit:bool, water:bool, target_kind:String, to:Vector3, heavy:bool) -> String:
	if hit:
		if Effects.TARGET_SURFACE.has(target_kind):return Effects.TARGET_SURFACE[target_kind]
		if to.y>1.6:return "air"
		return "armor" if heavy else "soft"
	if to.y>1.6:return "sky"
	return "water" if water else "ground"

func _impact(surface:String, pos:Vector3, heavy:bool, delay:float) -> void:
	if heavy:
		match surface:
			"armor":
				_later(delay,"metal",pos,0.55,6.0,true)
				_later(delay,"boom_s",pos,1.1,-4.0,true)
			"structure":
				_later(delay,"masonry",pos,0.8,4.0,true)
				_later(delay,"boom_s",pos,1.0,-3.0,true)
			"water":_later(delay,"splash",pos,0.8,3.0,true)
			"sky":pass
			_:_later(delay,"boom_s",pos,rng.randf_range(0.95,1.2),-2.0,true)
		return
	match surface:
		"armor","air":_later(delay,"metal",pos,rng.randf_range(1.0,1.3),0.0,true)
		"structure":if rng.randf()<0.5:_later(delay,"masonry",pos,1.4,-4.0,true)
		"water":if rng.randf()<0.4:_later(delay,"splash",pos,1.7,-6.0,true)
		"ground","earth":if rng.randf()<0.35:_later(delay,"dirt",pos,1.6,-6.0,true)

# Masonry under HE: a deep thud and falling plaster where the round strikes the
# wall, timed with the round's own impact; a louder crack and a debris trickle
# when the hit holes the building to its next damage state.
func _building_hit(e:Dictionary) -> void:
	var id:int=int(e.get("building",-1))
	var state:int=int(e.get("state",0))
	var worse:=state>int(building_states.get(id,0))
	building_states[id]=state
	var p:Vector2=e.get("impact",Vector2.ZERO)
	var pos:=Vector3(p.x,clampf(float(e.get("height",3.0))*0.4,1.0,4.0),p.y)
	if _ground_distance(pos)>hear:
		_distant(pos,1.0,true)
		return
	var due:=_impact_due(p)
	var weight:=clampf(float(e.get("fraction",0.0)),0.0,1.0)
	_later(due,"thud",pos,rng.randf_range(0.9,1.1)-0.15*weight,-2.0+3.0*weight)
	if worse:
		_later(due+0.05,"masonry",pos,0.6,6.0)
		_later(due+0.15,"debris",pos,rng.randf_range(1.0,1.15),-3.0)

# A building coming down: a long low rumble, a masonry crack and the rubble
# pouring down after it; taller buildings rumble deeper and louder.
func _building_collapse(e:Dictionary) -> void:
	var p:Vector2=e.get("pos",Vector2.ZERO)
	building_states[int(e.get("building",-1))]=3
	collapse_heard[p]=clock
	var pos:=Vector3(p.x,1.5,p.y)
	if _ground_distance(pos)>hear:
		_distant(pos,3.0,true)
		return
	var tall:=clampf((float(e.get("height",4.0))-3.0)/15.0,0.0,1.0)
	var due:=_impact_due(p,maxf(4.0,float(e.get("bounds",Rect2()).size.length())*0.5))
	_later(due,"masonry",pos,0.5,8.0)
	_later(due,"rumble",pos,1.0-0.25*tall,2.0*tall)
	_later(due+0.25,"debris",pos,0.85,2.0)
	_later(due+1.1,"debris",pos,0.7,0.0)
	_later(due+1.6,"crunch",pos,0.6,2.0)

# When the round in flight toward `at` lands (its pending impact sound), else now.
func _impact_due(at:Vector2, near:float=2.5) -> float:
	var due:=clock
	for item in pending:
		if item[5] and Vector2(item[2].x-at.x,item[2].z-at.y).length()<near:due=maxf(due,float(item[0]))
	return due-clock

func _destroyed(e:Dictionary) -> void:
	var kind:String=e.get("kind","")
	var p:Vector2=e.get("pos",Vector2.ZERO)
	var pos:=Vector3(p.x,0.7,p.y)
	if kind in Effects.INFANTRY:return
	# The collapse blast is relayed as a vehicle kill (ruined_building.gd); the
	# collapse already has its own sound.
	if collapse_heard.has(p):
		var heard:float=collapse_heard[p]
		collapse_heard.erase(p)
		if heard==clock:return
	if not bool(e.get("visible",true)) or _ground_distance(pos)>hear:
		_distant(pos,2.0,true)
		return
	# Wait for the killing round still in flight; its own impact sound is replaced by the blast.
	var due:=clock
	for i in range(pending.size()-1,-1,-1):
		var item:Array=pending[i]
		if item[5] and Vector2(item[2].x-pos.x,item[2].z-pos.z).length()<2.5:
			due=maxf(due,float(item[0]))
			pending.remove_at(i)
	var wait:=due-clock
	var water:bool=sim!=null and sim.terrain.is_water(p)
	match kind:
		"drone":_later(wait,"boom_s",pos,1.3,0.0)
		"fpv_drone":
			_later(wait,"boom_m",pos,1.2,0.0)
			_later(wait,"metal",pos,1.4,-2.0)
		"helo":
			_later(wait,"boom_m",pos,0.9,2.0)
			_later(wait+0.9,"boom_s",pos,0.8,0.0)
		"tank","aa","harvester","boat","":
			_later(wait,"boom_l",pos,rng.randf_range(0.95,1.05),0.0)
			_later(wait+rng.randf_range(0.35,0.55),"boom_s",pos,1.2,-4.0)
			if kind=="tank":
				for when in [rng.randf_range(0.8,1.1),rng.randf_range(1.5,2.1),rng.randf_range(2.6,3.4)]:_later(wait+when,"boom_s",pos,rng.randf_range(1.2,1.5),-6.0)
		_:
			if kind in Effects.STRUCTURES:
				_later(wait,"boom_l",pos,0.85,0.0)
				_later(wait+0.3,"crunch",pos,0.7,4.0)
			elif FIELD_DESTROYED.has(kind):
				var spec:Array=FIELD_DESTROYED[kind]
				_later(wait,spec[0],pos,float(spec[1]),float(spec[2]))
				if kind=="ammo_depot":
					_later(wait+0.6,"boom_m",pos,1.1,0.0)
					_later(wait+1.4,"boom_m",pos,0.95,-2.0)
			else:_later(wait,"boom_m",pos,1.0,0.0)
	if water and kind!="boat":_later(wait,"splash",pos,0.7,2.0)
	elif kind=="boat":_later(wait+0.1,"splash",pos,0.6,4.0)

func _later(delay:float, sound:String, pos:Vector3, pitch:float, db:float, impact:bool=false) -> void:
	if delay<=0.004:
		play_at(sound,pos,pitch,db)
		return
	if pending.size()>=PENDING_CAPACITY:pending.pop_front()
	pending.append([clock+delay,sound,pos,pitch,db,impact])

func _run_pending() -> void:
	var i:=0
	while i<pending.size():
		var item:Array=pending[i]
		if float(item[0])<=clock:
			pending.remove_at(i)
			play_at(item[1],item[2],item[3],item[4])
		else:i+=1

# ---------------------------------------------------------------- one-shot voices
func active_voices() -> int:
	var count:=0
	for i in ONE_SHOT_VOICES:if voice_until[i]>clock:count+=1
	return count

func active_in(category:String) -> int:
	var count:=0
	for i in ONE_SHOT_VOICES:if voice_until[i]>clock and voice_cat[i]==category:count+=1
	return count

# Starts a positional one-shot. Returns false when throttled, capped, culled or muted.
func play_at(sound:String, pos:Vector3, pitch:float=1.0, db:float=0.0) -> bool:
	if silent() or not SOUNDS.has(sound):return false
	var spec:Dictionary=SOUNDS[sound]
	if clock-float(last_start.get(sound,-INF))<float(spec.gap):
		counters.throttled+=1
		return false
	var reach:=hear*(1.5 if spec.cat=="explosion" else 1.0)
	if _ground_distance(pos)>reach:
		counters.culled+=1
		return false
	var category:String=spec.cat
	var dist:=_ear_distance(pos)
	var slot:=-1
	if active_in(category)>=int(CATEGORY_CAPS[category]):
		# Category full: only a clearly nearer sound replaces the farthest one of its kind.
		var farthest:=-1
		for i in ONE_SHOT_VOICES:
			if voice_until[i]>clock and voice_cat[i]==category and (farthest<0 or voice_dist[i]>voice_dist[farthest]):farthest=i
		if farthest<0 or dist>voice_dist[farthest]*0.8:
			counters.capped+=1
			return false
		slot=farthest
	if slot<0:
		for i in ONE_SHOT_VOICES:
			if voice_until[i]<=clock:
				slot=i
				break
	if slot<0:
		# Pool full: steal the lowest-priority, soonest-ending voice that does not outrank this sound.
		var rank:int=PRIORITY[category]
		for i in ONE_SHOT_VOICES:
			if int(PRIORITY[voice_cat[i]])>rank:continue
			if slot<0 or int(PRIORITY[voice_cat[i]])<int(PRIORITY[voice_cat[slot]]) or (PRIORITY[voice_cat[i]]==PRIORITY[voice_cat[slot]] and voice_until[i]<voice_until[slot]):slot=i
		if slot<0:
			counters.capped+=1
			return false
		counters.stolen+=1
	var stream:AudioStreamWAV=streams[sound]
	pitch=clampf(pitch*rng.randf_range(0.96,1.04),0.3,3.0)
	var player:=voices[slot]
	player.stream=stream
	player.position=pos
	player.pitch_scale=pitch
	player.volume_db=master_db+float(spec.db)+db
	_attenuate(player,reach)
	if player.is_inside_tree():player.play()
	voice_cat[slot]=category
	voice_until[slot]=clock+stream.get_length()/pitch
	voice_dist[slot]=dist
	last_start[sound]=clock
	counters.played+=1
	return true

# ---------------------------------------------------------------- distant combat
func _distant(pos:Vector3, weight:float, heavy:bool) -> void:
	if _ground_distance(pos)>hear*5.0:return
	distant_heat=minf(distant_heat+weight,12.0)
	if heavy:distant_heavy=minf(distant_heavy+weight,12.0)
	distant_pos=pos

func _update_distant(dt:float) -> void:
	var fade:=exp(-dt*1.2)
	distant_heat*=fade
	distant_heavy*=fade
	distant_clock-=dt
	if distant_clock>0.0 or distant_heat<0.2:return
	distant_clock=rng.randf_range(0.12,0.45)/clampf(sqrt(distant_heat),1.0,2.5)
	var heavy:=rng.randf()<distant_heavy/maxf(distant_heat,0.001)
	var player:=distant[distant_next]
	distant_next=(distant_next+1)%DISTANT_VOICES
	# Placed toward the fighting at the edge of hearing so it pans that way and stays muffled.
	var offset:=Vector3(distant_pos.x-focus.x,0,distant_pos.z-focus.z)
	if offset.length()>hear*0.95:offset=offset.normalized()*hear*0.95
	player.stream=streams.distant if heavy else streams.distant_pop
	player.position=focus+offset
	player.pitch_scale=rng.randf_range(0.8,1.15) if heavy else rng.randf_range(0.85,1.4)
	player.volume_db=master_db-17.0+clampf(distant_heat/6.0,0.0,1.0)*5.0+(2.0 if heavy else 0.0)
	_attenuate(player,hear*1.2)
	if player.is_inside_tree():player.play()
	counters.distant+=1

# ---------------------------------------------------------------- unit loops
# Re-picks which units own the loop slots: the nearest qualifying units around the focus, per group.
func pick_loops(elapsed:float) -> void:
	if sim==null:return
	var best:Dictionary={}
	for group in LOOP_SLOTS:best[group]=[]
	var positions:Dictionary={}
	var limit:=hear*hear
	for u in sim.units:
		if u.hp<=0.0:continue
		if u.team!=0 and not u.visible:continue
		var kind:String=u.kind
		var group:=""
		if LOOPS.has(kind):group=LOOPS[kind][0]
		elif u.get("structure",false) and String(u.state) in SITE_STATES:group="work"
		if kind=="engineer" and String(u.state) in WORK_STATES:group="work"
		if group=="":continue
		var p:Vector2=u.pos
		var d2:=Vector2(p.x-focus.x,p.y-focus.z).length_squared()
		if d2>limit:continue
		positions[u.id]=p
		var speed:=0.0
		if loop_positions.has(u.id):speed=p.distance_to(loop_positions[u.id])/maxf(elapsed,0.001)
		if group=="march" and speed<0.4:continue
		_offer(best[group],int(LOOP_SLOTS[group]),d2,u,speed)
		if kind in TRACKED and speed>0.6:_offer(best.tracks,int(LOOP_SLOTS.tracks),d2,u,speed)
	loop_positions=positions
	for group in LOOP_SLOTS:_assign(group,best[group])

func _offer(list:Array, capacity:int, d2:float, u:Dictionary, speed:float) -> void:
	if list.size()>=capacity and d2>=float(list[-1][0]):return
	var at:=list.size()
	for i in list.size():
		if d2<float(list[i][0]):
			at=i
			break
	list.insert(at,[d2,u,speed])
	if list.size()>capacity:list.pop_back()

func _assign(group:String, chosen:Array) -> void:
	var slots:Array=loop_slots[group]
	var wanted:Dictionary={}
	for entry in chosen:wanted[entry[1].id]=entry
	for slot in slots:
		if slot.id>=0 and not wanted.has(slot.id):
			slot.player.stop()
			slot.id=-1
		elif slot.id>=0:
			slot.speed=float(wanted[slot.id][2])
			wanted.erase(slot.id)
	for id in wanted:
		var entry:Array=wanted[id]
		var u:Dictionary=entry[1]
		for slot in slots:
			if slot.id>=0:continue
			var spec:Array=_loop_spec(group,u)
			slot.id=id
			slot.speed=float(entry[2])
			slot.base_pitch=float(spec[1])*rng.randf_range(0.97,1.03)
			slot.base_db=float(spec[2])
			slot.db=-40.0
			slot.player.stream=streams[spec[0]]
			slot.player.volume_db=master_db-40.0
			slot.player.position=_unit_point(u)
			_attenuate(slot.player,hear)
			if slot.player.is_inside_tree():slot.player.play(rng.randf()*float(streams[spec[0]].get_length())*0.9)
			break
	for slot in slots:if slot.id>=0:_attenuate(slot.player,hear)

func _loop_spec(group:String, u:Dictionary) -> Array:
	match group:
		"tracks":return ["tracks",1.0 if u.kind=="tank" else 1.15,-17.0]
		"work":return ["work",1.0,-15.0]
	var spec:Array=LOOPS[u.kind]
	return [spec[1],spec[2],spec[3]]

func _unit_point(u:Dictionary) -> Vector3:
	var height:=float(u.get("altitude",0.0))
	if height<=0.0 and sim!=null and sim.definitions.has(u.kind):height=float(sim.definitions[u.kind].get("altitude",0.0))
	return Vector3(u.pos.x,maxf(height,0.8),u.pos.y)

func _update_loops(dt:float) -> void:
	var blend:=1.0-exp(-dt*5.0)
	for group in loop_slots:
		for slot in loop_slots[group]:
			if slot.id<0:continue
			var u:Dictionary=sim.get_unit(slot.id)
			if u.is_empty() or u.hp<=0.0:
				slot.player.stop()
				slot.id=-1
				continue
			slot.player.position=_unit_point(u)
			var top:=maxf(float(sim.definitions[u.kind].get("speed",5.0)),1.0) if sim.definitions.has(u.kind) else 5.0
			var move:=clampf(float(slot.speed)/top,0.0,1.0)
			var target_db:float=slot.base_db
			var target_pitch:float=slot.base_pitch
			match group:
				"vehicle":
					if u.kind in ["helo","drone","fpv_drone"]:
						target_pitch*=1.0+move*0.12+(0.25 if u.state=="DIVING" else 0.0)
					else:
						target_pitch*=0.85+move*0.3
						target_db+=lerpf(-6.0,0.0,move)
				"tracks":target_db+=lerpf(-10.0,0.0,move)
			if not live:target_db=-60.0
			slot.db=lerpf(float(slot.db),target_db,blend)
			if not live and slot.db<-50.0:
				# Paused: release the faded voice; the next pick after resuming restarts it.
				slot.player.stop()
				slot.id=-1
				continue
			slot.pitch=lerpf(float(slot.pitch),target_pitch,blend)
			slot.player.volume_db=master_db+float(slot.db)
			slot.player.pitch_scale=maxf(float(slot.pitch),0.3)

func loop_ids(group:String) -> Array:
	var ids:=[]
	for slot in loop_slots[group]:if slot.id>=0:ids.append(slot.id)
	return ids

# ---------------------------------------------------------------- interface sounds
func ui(sound:String) -> void:
	if silent() or not streams.has("ui_"+sound):return
	var player:=ui_players[ui_next]
	ui_next=(ui_next+1)%UI_VOICES
	player.stream=streams["ui_"+sound]
	player.volume_db=master_db+{"order":-15.0,"warn":-14.0,"click":-16.0,"deploy":-13.0}.get(sound,-15.0)
	counters.ui+=1
	if player.is_inside_tree():player.play()

func stats() -> Dictionary:
	var by_category:={}
	for category in CATEGORY_CAPS:by_category[category]=active_in(category)
	var loops:={}
	for group in loop_slots:loops[group]=loop_ids(group)
	return {"voices":active_voices(),"by_category":by_category,"loops":loops,"pending":pending.size(),"synth_ms":synth_ms,"samples":synth_samples,"sounds":streams.size(),"counters":counters.duplicate()}

func _exit_tree() -> void:
	_stop_all()
	for player in ui_players:player.stop()

# ---------------------------------------------------------------- synthesis
func build_library() -> void:
	var hi:=22050
	var mid:=16000
	var lo:=11025
	# Weapons.
	var crack:=_burst(hi,0.16,{"crack":1.0,"crack_tau":0.006,"body":0.55,"body_tau":0.035,"lp":0.35,"lp_end":0.08,"tone":0.25,"f0":420.0,"f1":160.0,"tone_tau":0.02,"rumble":0.25,"rumble_tau":0.06})
	streams.rifle=_wav(crack,hi)
	var mg:=_silence(hi,0.46)
	for n in 4:_mix(mg,_burst(hi,0.15,{"crack":1.0,"crack_tau":0.005,"body":0.6,"body_tau":0.03,"lp":0.3,"lp_end":0.1,"tone":0.3,"f0":360.0,"f1":150.0,"tone_tau":0.02,"rumble":0.3,"rumble_tau":0.05}),hi,n*0.085+rng.randf_range(0.0,0.008),rng.randf_range(0.8,1.0))
	streams.mg=_wav(mg,hi)
	var ac:=_silence(mid,0.42)
	for n in 3:_mix(ac,_burst(mid,0.2,{"crack":0.8,"crack_tau":0.006,"body":0.8,"body_tau":0.05,"lp":0.25,"lp_end":0.06,"tone":0.7,"f0":220.0,"f1":90.0,"tone_tau":0.04,"rumble":0.4,"rumble_tau":0.09}),mid,n*0.075,1.0-n*0.08)
	streams.autocannon=_wav(ac,mid)
	streams.tank=_wav(_burst(lo,1.1,{"crack":0.7,"crack_tau":0.008,"body":1.0,"body_tau":0.16,"lp":0.5,"lp_end":0.03,"tone":1.2,"f0":110.0,"f1":38.0,"tone_tau":0.2,"sweep_tau":0.05,"rumble":1.0,"rumble_tau":0.45}),lo)
	streams.at_gun=_wav(_burst(lo,0.75,{"crack":1.0,"crack_tau":0.006,"body":0.9,"body_tau":0.09,"lp":0.6,"lp_end":0.05,"tone":0.8,"f0":160.0,"f1":55.0,"tone_tau":0.1,"sweep_tau":0.03,"rumble":0.6,"rumble_tau":0.3}),lo)
	var atgm:=_whoosh(mid,1.0,0.03,0.35,0.06,0.45,0.5)
	_mix(atgm,_burst(mid,0.25,{"crack":0.6,"crack_tau":0.01,"body":0.8,"body_tau":0.05,"lp":0.3,"lp_end":0.05,"tone":0.5,"f0":120.0,"f1":60.0,"tone_tau":0.06}),mid,0.0,0.8)
	streams.atgm=_wav(atgm,mid)
	var rockets:=_silence(mid,0.7)
	for n in 2:_mix(rockets,_whoosh(mid,0.5,0.08,0.4,0.02,0.18,0.3),mid,n*0.14,1.0)
	streams.rockets=_wav(rockets,mid)
	# Impacts.
	streams.dirt=_wav(_burst(lo,0.32,{"crack":0.3,"crack_tau":0.004,"body":1.0,"body_tau":0.05,"lp":0.25,"lp_end":0.04,"tone":0.6,"f0":90.0,"f1":45.0,"tone_tau":0.05,"crackle":0.4,"crackle_rate":0.004}),lo)
	var metal:=_ring(hi,0.38,[[1840.0,1.0,0.09],[2710.0,0.7,0.06],[4130.0,0.5,0.035],[5600.0,0.3,0.02]],0.7)
	streams.metal=_wav(metal,hi)
	streams.masonry=_wav(_burst(hi,0.42,{"crack":0.9,"crack_tau":0.004,"body":0.7,"body_tau":0.09,"lp":0.45,"lp_end":0.12,"tone":0.3,"f0":140.0,"f1":70.0,"tone_tau":0.05,"crackle":1.0,"crackle_rate":0.003}),hi)
	streams.splash=_wav(_splash(mid,0.6),mid)
	# Buildings: wall thud, rubble trickle and collapse rumble (low content, low rates).
	streams.thud=_wav(_burst(lo,0.5,{"crack":0.45,"crack_tau":0.004,"body":1.0,"body_tau":0.07,"lp":0.3,"lp_end":0.04,"tone":0.9,"f0":95.0,"f1":42.0,"tone_tau":0.08,"sweep_tau":0.03,"rumble":0.5,"rumble_tau":0.18,"crackle":0.9,"crackle_rate":0.004}),lo)
	streams.debris=_wav(_debris(lo,1.8),lo)
	streams.rumble=_wav(_rumble(6000,2.8),6000)
	# Explosions: one recipe, longer and darker with size.
	streams.boom_s=_wav(_boom(lo,0.7,0.6),lo)
	streams.boom_m=_wav(_boom(lo,1.3,1.0),lo)
	streams.boom_l=_wav(_boom(lo,2.4,1.6),lo)
	streams.distant=_wav(_burst(8000,1.1,{"body":1.0,"body_tau":0.18,"lp":0.08,"lp_end":0.015,"tone":0.8,"f0":60.0,"f1":32.0,"tone_tau":0.25,"rumble":1.0,"rumble_tau":0.4,"attack":0.02}),8000)
	streams.distant_pop=_wav(_burst(8000,0.28,{"body":1.0,"body_tau":0.04,"lp":0.2,"lp_end":0.05,"tone":0.4,"f0":120.0,"f1":70.0,"tone_tau":0.04,"attack":0.004}),8000)
	# Props.
	streams.crunch=_wav(_burst(mid,0.45,{"crack":0.5,"crack_tau":0.005,"body":0.6,"body_tau":0.12,"lp":0.4,"lp_end":0.1,"tone":0.4,"f0":110.0,"f1":60.0,"tone_tau":0.06,"crackle":1.4,"crackle_rate":0.006}),mid)
	var wire:=_silence(hi,0.32)
	_mix(wire,_ring(hi,0.2,[[3150.0,0.8,0.02],[5200.0,0.5,0.012],[880.0,0.6,0.09]],0.9),hi,0.0,1.0)
	_mix(wire,_ring(hi,0.2,[[2900.0,0.8,0.02],[4800.0,0.5,0.012],[760.0,0.6,0.08]],0.9),hi,0.11,0.85)
	streams.wire=_wav(wire,hi)
	# Loops.
	streams.engine=_wav(_engine(lo,1.0,35.0),lo,true)
	streams.tracks=_wav(_tracks(mid,1.0),mid,true)
	streams.rotor=_wav(_rotor(lo,1.0),lo,true)
	streams.buzz=_wav(_buzz(mid,1.0),mid,true)
	streams.boat=_wav(_boat(lo,1.0),lo,true)
	streams.march=_wav(_march(lo,1.2),lo,true)
	streams.work=_wav(_work(mid,2.0),mid,true)
	streams.wind=_wav(_wind(8000,3.0),8000,true)
	# Interface: the order ping keeps its original tone.
	var ping:=_silence(hi,1100.0/hi)
	for i in ping.size():ping[i]=sin(i*TAU*620/22050.0)*(1-i/1100.0)
	streams.ui_order=_wav(ping,hi,false,2800.0/32767.0)
	var warn:=_silence(hi,0.5)
	_mix(warn,_ring(hi,0.3,[[880.0,1.0,0.12],[1760.0,0.25,0.06]],0.0),hi,0.0,1.0)
	_mix(warn,_ring(hi,0.36,[[660.0,1.0,0.16],[1320.0,0.25,0.08]],0.0),hi,0.14,1.0)
	streams.ui_warn=_wav(warn,hi,false,0.5)
	streams.ui_click=_wav(_ring(hi,0.05,[[2100.0,0.6,0.008]],1.0,0.002),hi,false,0.4)
	var deploy:=_silence(hi,0.3)
	_mix(deploy,_ring(hi,0.15,[[520.0,1.0,0.05]],0.2),hi,0.0,1.0)
	_mix(deploy,_ring(hi,0.18,[[780.0,1.0,0.07]],0.2),hi,0.08,1.0)
	streams.ui_deploy=_wav(deploy,hi,false,0.5)

func _silence(rate:int, seconds:float) -> PackedFloat32Array:
	var out:=PackedFloat32Array()
	out.resize(int(rate*seconds))
	return out

func _mix(target:PackedFloat32Array, source:PackedFloat32Array, rate:int, at:float, gain:float) -> void:
	var offset:=int(at*rate)
	var count:=mini(source.size(),target.size()-offset)
	for i in count:target[offset+i]+=source[i]*gain

# Percussive building block: a high-passed crack, a low-passed noise body whose cutoff falls over time,
# a pitch-swept tone (thump), a slow rumble tail and optional debris crackle. Every part decays exponentially.
func _burst(rate:int, seconds:float, p:Dictionary) -> PackedFloat32Array:
	var out:=_silence(rate,seconds)
	var n:=out.size()
	var dt:=1.0/rate
	var e_crack:float=p.get("crack",0.0)
	var k_crack:=exp(-dt/float(p.get("crack_tau",0.01)))
	var e_body:float=p.get("body",0.0)
	var k_body:=exp(-dt/float(p.get("body_tau",0.1)))
	var lp0:float=p.get("lp",0.2)
	var lp1:float=p.get("lp_end",lp0)
	var e_tone:float=p.get("tone",0.0)
	var k_tone:=exp(-dt/float(p.get("tone_tau",0.1)))
	var f0:float=p.get("f0",80.0)
	var f1:float=p.get("f1",f0)
	var sweep:=1.0
	var k_sweep:=exp(-dt/float(p.get("sweep_tau",float(p.get("tone_tau",0.1))*0.5)))
	var e_rumble:float=p.get("rumble",0.0)
	var k_rumble:=exp(-dt/float(p.get("rumble_tau",0.3)))
	var crackle:float=p.get("crackle",0.0)
	var crackle_rate:float=p.get("crackle_rate",0.0)
	var attack:=maxf(float(p.get("attack",0.0015)),dt)
	var lp:=0.0
	var previous:=0.0
	var low:=0.0
	var low2:=0.0
	var phase:=0.0
	var grain:=0.0
	var grain_k:=exp(-dt/0.004)
	var inv:=1.0/n
	for i in n:
		var w:=rng.randf()*2.0-1.0
		lp+=(w-lp)*lerpf(lp0,lp1,i*inv)
		low+=(w-low)*0.03
		low2+=(low-low2)*0.03
		phase+=TAU*(f1+(f0-f1)*sweep)*dt
		var value:=e_crack*(w-previous)*0.5+e_body*lp*2.0+e_tone*sin(phase)+e_rumble*low2*14.0
		if crackle>0.0:
			if rng.randf()<crackle_rate:grain=rng.randf_range(0.4,1.0)
			value+=grain*w*crackle*e_body*2.0
			grain*=grain_k
		previous=w
		out[i]=value*minf(1.0,i*dt/attack)
		e_crack*=k_crack
		e_body*=k_body
		e_tone*=k_tone
		e_rumble*=k_rumble
		sweep*=k_sweep
	return out

# Explosion: flash crack, a bright body that darkens as it rolls, sub-bass thump, a long rumble tail with
# slow surges and debris crackle that thins out.
func _boom(rate:int, seconds:float, size:float) -> PackedFloat32Array:
	var out:=_burst(rate,seconds,{"crack":0.8,"crack_tau":0.006,"body":1.0,"body_tau":0.12*size,"lp":0.55,"lp_end":0.02,"tone":1.1,"f0":90.0,"f1":28.0,"tone_tau":0.22*size,"sweep_tau":0.05,"rumble":1.0,"rumble_tau":0.45*size,"crackle":0.5,"crackle_rate":0.002,"attack":0.003})
	var dt:=1.0/rate
	var surge:=0.0
	var target:=1.0
	for i in out.size():
		if i%int(rate*0.12)==0:target=rng.randf_range(0.7,1.3)
		surge+=(target-surge)*0.002
		out[i]*=lerpf(1.0,surge,minf(1.0,i*dt/0.3))
	return out

# Falling rubble: grains of grit and the odd chunk landing, thinning out.
func _debris(rate:int, seconds:float) -> PackedFloat32Array:
	var out:=_silence(rate,seconds)
	var dt:=1.0/rate
	var lp:=0.0
	var grain:=0.0
	var grain_k:=exp(-dt/0.006)
	for i in out.size():
		var t:=i*dt
		var density:=0.012*exp(-t/0.9)+0.0015
		if rng.randf()<density:grain=rng.randf_range(0.3,1.0)*exp(-t/1.4)
		var w:=rng.randf()*2.0-1.0
		lp+=(w-lp)*0.35
		out[i]=lp*grain*1.8
		grain*=grain_k
	for n in 7:
		var at:=rng.randf_range(0.0,seconds*0.7)
		_mix(out,_burst(rate,0.18,{"body":1.0,"body_tau":0.03,"lp":0.25,"lp_end":0.06,"tone":0.6,"f0":120.0,"f1":60.0,"tone_tau":0.03}),rate,at,0.7*exp(-at/1.2))
	return out

# Collapse: sub-bass groan that swells briefly and rolls away with slow surges.
func _rumble(rate:int, seconds:float) -> PackedFloat32Array:
	var out:=_burst(rate,seconds,{"crack":0.3,"crack_tau":0.01,"body":0.7,"body_tau":0.45,"lp":0.12,"lp_end":0.02,"tone":0.8,"f0":60.0,"f1":24.0,"tone_tau":0.9,"sweep_tau":0.4,"rumble":1.0,"rumble_tau":1.3,"crackle":0.4,"crackle_rate":0.003,"attack":0.12})
	var dt:=1.0/rate
	var surge:=1.0
	var target:=1.0
	for i in out.size():
		if i%int(rate*0.2)==0:target=rng.randf_range(0.6,1.35)
		surge+=(target-surge)*0.003
		out[i]*=surge*minf(1.0,(1.0-i*dt/seconds)*1.6)
	return out

func _ring(rate:int, seconds:float, partials:Array, click:float, click_tau:float=0.003) -> PackedFloat32Array:
	var out:=_silence(rate,seconds)
	var dt:=1.0/rate
	for partial in partials:
		var step:float=TAU*float(partial[0])*dt
		var e:float=partial[1]
		var k:=exp(-dt/float(partial[2]))
		var phase:=rng.randf()*TAU
		for i in out.size():
			out[i]+=sin(phase)*e
			phase+=step
			e*=k
	if click>0.0:
		var e:=click
		var k:=exp(-dt/click_tau)
		for i in out.size():
			out[i]+=(rng.randf()*2.0-1.0)*e
			e*=k
			if e<0.0005:break
	return out

# Rocket motor: band-limited noise whose band rises, with a fast attack, a hold and a fading tail.
func _whoosh(rate:int, seconds:float, lp0:float, lp1:float, attack:float, hold:float, release:float) -> PackedFloat32Array:
	var out:=_silence(rate,seconds)
	var n:=out.size()
	var dt:=1.0/rate
	var a:=0.0
	var b:=0.0
	var floor_lp:=0.0
	var roar:=1.0
	for i in n:
		var t:=i*dt
		var w:=rng.randf()*2.0-1.0
		var c:=lerpf(lp0,lp1,minf(1.0,t/(attack+hold)))
		a+=(w-a)*c
		b+=(a-b)*c
		floor_lp+=(b-floor_lp)*0.01
		if i%64==0:roar=rng.randf_range(0.75,1.15)
		var env:=minf(1.0,t/attack) if t<attack+hold else maxf(0.0,1.0-(t-attack-hold)/release)
		out[i]=(b-floor_lp)*env*roar*3.0
	return out

func _splash(rate:int, seconds:float) -> PackedFloat32Array:
	var out:=_burst(rate,seconds,{"crack":0.3,"crack_tau":0.004,"body":1.0,"body_tau":0.16,"lp":0.5,"lp_end":0.12,"tone":0.5,"f0":120.0,"f1":60.0,"tone_tau":0.05,"crackle":0.9,"crackle_rate":0.01,"attack":0.01})
	# Falling water: a second, softer wash after the plume.
	var dt:=1.0/rate
	var lp:=0.0
	for i in out.size():
		var t:=i*dt
		lp+=(rng.randf()*2.0-1.0-lp)*0.3
		out[i]+=lp*0.5*maxf(0.0,sin(PI*clampf((t-0.12)/0.45,0.0,1.0)))
	return out

# Loops are built a little longer than needed and cross-faded back into their start, so noise seams vanish;
# tonal parts use whole cycles per loop.
func _seam(buffer:PackedFloat32Array, rate:int, seconds:float, fade:float) -> PackedFloat32Array:
	var n:=int(rate*seconds)
	var f:=mini(int(rate*fade),buffer.size()-n)
	for i in f:
		var w:=float(i)/f
		buffer[i]=buffer[i]*w+buffer[n+i]*(1.0-w)
	buffer.resize(n)
	return buffer

func _engine(rate:int, seconds:float, fire_hz:float) -> PackedFloat32Array:
	var out:=_silence(rate,seconds+0.1)
	var dt:=1.0/rate
	# One firing period of the harmonic stack, replayed by index (rate/fire_hz must be whole).
	var amps:=[1.0,0.75,0.55,0.4,0.28,0.2,0.12]
	var period:=int(round(rate/fire_hz))
	var cycle:=PackedFloat32Array()
	cycle.resize(period)
	for h in amps.size():
		var phase:=rng.randf()*TAU
		for i in period:cycle[i]+=sin(TAU*(h+1)*i/period+phase)*amps[h]
	var lp:=0.0
	var clatter:=0.0
	for i in out.size():
		var t:=i*dt
		var value:=cycle[i%period]
		var pulse:=0.5+0.5*sin(TAU*fire_hz*t)
		lp+=(rng.randf()*2.0-1.0-lp)*0.12
		clatter+=(rng.randf()*2.0-1.0-clatter)*0.5
		out[i]=value*0.35+lp*pulse*pulse*1.6+clatter*0.05*(0.6+0.4*sin(TAU*4.0*t))
	return _seam(out,rate,seconds,0.1)

func _tracks(rate:int, seconds:float) -> PackedFloat32Array:
	var out:=_silence(rate,seconds+0.08)
	var dt:=1.0/rate
	for n in 8:
		_mix(out,_ring(rate,0.12,[[900.0+rng.randf_range(-60,60),0.7,0.025],[1370.0,0.5,0.018],[2230.0,0.35,0.012]],0.8,0.004),rate,n/8.0+rng.randf_range(0.0,0.02),rng.randf_range(0.6,1.0))
	var lp:=0.0
	for i in out.size():
		var t:=i*dt
		lp+=(rng.randf()*2.0-1.0-lp)*0.08
		var squeal:=sin(TAU*1800.0*t+3.0*sin(TAU*3.0*t))*0.12*maxf(0.0,sin(TAU*2.0*t))
		out[i]+=squeal+lp*0.5
	return _seam(out,rate,seconds,0.08)

func _rotor(rate:int, seconds:float) -> PackedFloat32Array:
	var out:=_silence(rate,seconds+0.1)
	var dt:=1.0/rate
	var blade:=18.0
	var lp:=0.0
	var hiss:=0.0
	for i in out.size():
		var t:=i*dt
		var into:=fmod(t*blade,1.0)/blade
		var slap:=exp(-into/0.014)
		lp+=(rng.randf()*2.0-1.0-lp)*0.25
		hiss+=(rng.randf()*2.0-1.0-hiss)*0.6
		out[i]=lp*slap*1.6+sin(TAU*blade*t)*0.25*slap+sin(TAU*1210.0*t)*0.03+hiss*0.06
	return _seam(out,rate,seconds,0.1)

func _buzz(rate:int, seconds:float) -> PackedFloat32Array:
	var out:=_silence(rate,seconds+0.05)
	var dt:=1.0/rate
	var lp:=0.0
	for i in out.size():
		var t:=i*dt
		var saw:=fmod(t*190.0,1.0)*2.0-1.0+fmod(t*197.0,1.0)*2.0-1.0+(fmod(t*412.0,1.0)*2.0-1.0)*0.4
		lp+=(saw-lp)*0.35
		out[i]=lp*(0.85+0.15*sin(TAU*7.0*t))+(rng.randf()*2.0-1.0)*0.04
	return _seam(out,rate,seconds,0.05)

func _boat(rate:int, seconds:float) -> PackedFloat32Array:
	var out:=_silence(rate,seconds+0.15)
	var dt:=1.0/rate
	var lp:=0.0
	var wash:=0.0
	for i in out.size():
		var t:=i*dt
		var motor:=sin(TAU*24.0*t)+sin(TAU*48.0*t+1.1)*0.6+sin(TAU*72.0*t+2.0)*0.35
		lp+=(rng.randf()*2.0-1.0-lp)*0.1
		wash+=(rng.randf()*2.0-1.0-wash)*0.35
		out[i]=motor*0.3+lp*0.8*(0.6+0.4*sin(TAU*24.0*t))+wash*0.25*(0.6+0.4*sin(TAU*1.0*t))
	return _seam(out,rate,seconds,0.15)

func _march(rate:int, seconds:float) -> PackedFloat32Array:
	var out:=_silence(rate,seconds+0.05)
	for at in [0.02,0.17,0.31,0.45,0.6,0.74,0.88,1.03]:
		_mix(out,_burst(rate,0.09,{"crack":0.2,"crack_tau":0.003,"body":1.0,"body_tau":0.02,"lp":0.35,"lp_end":0.15,"tone":0.2,"f0":110.0,"f1":70.0,"tone_tau":0.02,"crackle":0.6,"crackle_rate":0.02}),rate,at+rng.randf_range(0.0,0.03),rng.randf_range(0.5,1.0))
	return _seam(out,rate,seconds,0.05)

func _work(rate:int, seconds:float) -> PackedFloat32Array:
	var out:=_silence(rate,seconds+0.05)
	for at in [0.1,0.52,1.72]:
		_mix(out,_ring(rate,0.3,[[1250.0,0.8,0.05],[2930.0,0.5,0.03],[4310.0,0.3,0.02]],0.9),rate,at,1.0)
		_mix(out,_burst(rate,0.15,{"body":1.0,"body_tau":0.03,"lp":0.3,"lp_end":0.1,"tone":0.6,"f0":150.0,"f1":80.0,"tone_tau":0.03}),rate,at,0.8)
	# Shovel scrape then a dirt drop.
	var dt:=1.0/rate
	var a:=0.0
	var b:=0.0
	var start:=int(0.9*rate)
	var length:=int(0.45*rate)
	for i in length:
		var w:=rng.randf()*2.0-1.0
		a+=(w-a)*0.45
		b+=(a-b)*0.08
		out[start+i]+=(a-b)*0.9*sin(PI*i/length)
	_mix(out,_burst(rate,0.25,{"body":1.0,"body_tau":0.05,"lp":0.2,"lp_end":0.05,"tone":0.4,"f0":90.0,"f1":50.0,"tone_tau":0.05,"crackle":0.8,"crackle_rate":0.01}),rate,1.42,0.7)
	return _seam(out,rate,seconds,0.05)

func _wind(rate:int, seconds:float) -> PackedFloat32Array:
	var out:=_silence(rate,seconds+0.5)
	var dt:=1.0/rate
	var a:=0.0
	var b:=0.0
	var c:=0.0
	var traffic:=0.0
	for i in out.size():
		var t:=i*dt
		var w:=rng.randf()*2.0-1.0
		a+=(w-a)*0.05
		b+=(a-b)*0.05
		c+=(w-c)*0.2
		traffic+=(b-traffic)*0.02
		var gust:=0.65+0.25*sin(TAU*t/3.0)+0.1*sin(TAU*t+1.3)
		out[i]=b*6.0*gust+(c-a)*0.25*gust*gust+sin(TAU*50.0*t)*0.02+sin(TAU*100.0*t)*0.012+traffic*4.0
	return _seam(out,rate,seconds,0.5)

# Normalizes to `peak` and packs two signed 16-bit samples per int so the bytes are produced natively.
func _wav(buffer:PackedFloat32Array, rate:int, loop:bool=false, peak:float=0.9) -> AudioStreamWAV:
	var top:=0.0001
	for v in buffer:top=maxf(top,absf(v))
	var scale:=peak*32767.0/top
	# Even length: two samples per packed int; a dropped last sample is inaudible, also at a loop seam.
	if buffer.size()%2==1:buffer.resize(buffer.size()-1)
	var n:=buffer.size()
	var packed:=PackedInt32Array()
	packed.resize(buffer.size()/2)
	for j in packed.size():
		var first:=int(buffer[j*2]*scale)
		var second:=int(buffer[j*2+1]*scale)
		packed[j]=(first&0xFFFF)|(second<<16)
	var stream:=AudioStreamWAV.new()
	stream.format=AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate=rate
	stream.data=packed.to_byte_array()
	if loop:
		stream.loop_mode=AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin=0
		stream.loop_end=n
	synth_samples+=n
	return stream
