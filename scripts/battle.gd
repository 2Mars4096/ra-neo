extends Node3D

const Sim = preload("res://scripts/simulation.gd")
const Visuals = preload("res://scripts/visuals.gd")
const Effects = preload("res://scripts/effects.gd")
const HUD = preload("res://scripts/hud.gd")
const Motion = preload("res://scripts/unit_animation.gd")
const StructureDamage = preload("res://scripts/structure_damage.gd")
var sim := Sim.new()
var art := Visuals.new()
var effects := Effects.new()
var harbor_props:Node3D=null
var weather_fx:=preload("res://scripts/weather_visuals.gd").new()
var atmosphere:Environment
var trail_clock := 0.0
var unit_last_positions: Dictionary = {}
var camera := Camera3D.new()
var camera_focus := Vector3(48,0,41)
const MIN_ZOOM := 24.0
# Far zoom limit for the loaded scenario: 84 on legacy maps, configurable (220
# default) on huge theatres. Kept under the original name for existing callers.
var MAX_ZOOM := 84.0
var camera_size := 72.0
var camera_zoom_target := 72.0
var selected: Array = []
var groups: Dictionary = {}
var nodes: Dictionary = {}
var objective_nodes: Array[Node3D] = []
var dragging := false
var drag_start := Vector2.ZERO
var attack_mode := false
# FPV strike targeting: armed from the reinforcement panel, the next map click aims it.
var strike_mode := false
var build_mode:=""
var build_rotated:=false
# Drag-to-install for linear works and net areas: world-space anchor while held.
var build_drag:=false
var build_drag_start:=Vector2.ZERO
var field_choice_cache:Dictionary={}
var pointer:=Vector2(-1,-1)
# Shift-queued special actions waiting for their section (see run_pending).
var pending_actions:Array[Dictionary]=[]
# Action the selection would take at the cursor ("Garrison", "Clear", ...).
var cursor_hint:=""
var hint_dirty:=false
var hint_msec:=-1000
const HINT_INTERVAL_MSEC:=100
var site_watch:Dictionary={}
var paused := true
var show_help := true
var toast := ""
var toast_time := 0.0
var hud: Control
var fx: Array[Dictionary] = []
var fog_image := Image.create(48,36,false,Image.FORMAT_RGBA8)
var fog_texture: ImageTexture
var fog_clock := 0.0
var shown_wetness:=-1.0
var shown_fog_density:=-1.0
const FOG_LIGHT:=Color("8eabb3")
var fog_drawn_visible:Dictionary={}
var fog_drawn_explored:=0
var marker: Node3D
var marker_time := 0.0
var sound := AudioStreamPlayer.new()
var screenshot_path := ""
var capture_frames := 0
var benchmark_frames: Array[float] = []
var benchmark := false
var benchmark_ready:=false
var presentation_costs:Array[float]=[]
var engine_costs:Array[float]=[]
var bench_started := 0
var sim_costs: Array[float] = []
var previous_frame_usec := 0
var render_history:Dictionary = {}
var contact_shadows:MultiMeshInstance3D
var contact_shadow_count:=0
# Opt-in presentation timing for headless profiling tools (off in play).
var profiling_frames:=false
var frame_profile:Dictionary={}
func flap(key:String,started:int)->int:
	var now:=Time.get_ticks_usec()
	if profiling_frames:frame_profile[key]=frame_profile.get(key,0.0)+(now-started)/1000.0
	return now

func _ready() -> void:
	if huge_world():MAX_ZOOM=float(sim.scenario.get("camera_max_zoom",220.0))
	camera_focus=Vector3(sim.terrain.world_size.x/2,0,sim.terrain.world_size.y/2+5)
	if not sim.classic.is_empty():
		var headquarters:Array=sim.Classic.structures(sim,0,"hq")
		if not headquarters.is_empty():camera_focus=Vector3(headquarters[0].pos.x,0,headquarters[0].pos.y)
	elif not sim.field_ops.is_empty():
		# Open on the insertion force, preferring the engineer who starts field works.
		var force:Array=sim.living(0).filter(func(u):return not is_structure(u))
		var engineers:Array=force.filter(func(u):return is_engineer(u))
		if not engineers.is_empty():camera_focus=Vector3(engineers[0].pos.x,0,engineers[0].pos.y)
		elif not force.is_empty():
			var centre:=Vector2.ZERO
			for u in force:centre+=u.pos
			centre/=force.size()
			camera_focus=Vector3(centre.x,0,centre.y)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	atmosphere=env
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("18313d")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b8c3cc")
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-32,0)
	sun.light_color = Color("fff8ee")
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.78
	# One orthogonal shadow map instead of four cascades: the RTS camera looks at a
	# shallow band, and four splits re-drew the whole city four times per frame.
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 120
	add_child(sun)
	for kind in ["rifle","tank","boat"]:
		var definition: Dictionary=sim.definitions[kind]
		sim.terrain.nav_grid(definition.domain,float(definition.radius),sim.terrain.mobility_profile(kind))
	# Individual soldiers route on a 0.8 m grid (cover, regroup, trench and wire
	# detours). Building it lazily froze the first firefight for ~0.35 s.
	sim.terrain.nav_grid("land",0.8,"infantry")
	art.make_world(self,sim.terrain)
	if not sim.classic.is_empty():
		for field in sim.classic.fields:
			var deposit:=Node3D.new();add_child(deposit)
			deposit.position=Vector3(field.pos.x,0,field.pos.y)
			art.ring(deposit,3.3,Color("b59b59"))
			for i in 9:art.make_rock(deposit,Vector3(sin(i*2.4)*2,0.3,cos(i*2.4)*2),Vector3(0.65,0.6,0.7),i)
	add_child(effects)
	effects.set_world_bounds(sim.terrain.world_size,sim.terrain.shore_x)
	audio=preload("res://scripts/audio_fx.gd").new();audio.setup(sim,effects);add_child(audio)
	add_child(weather_fx)
	add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 300
	camera.current = true
	update_camera()
	for obj in sim.objectives:
		var root := Node3D.new()
		add_child(root)
		root.position = Vector3(obj.pos.x,0,obj.pos.y)
		art.ring(root,6.8,Color("f0ba75"))
		art.cylinder(root,Vector3(0,2.7,0),0.1,5.4,Color("c3c8b6"))
		art.box(root,Vector3(0.9,4.5,0),Vector3(1.8,0.8,0.09),Color("f0ba75"))
		objective_nodes.append(root)
	marker = Node3D.new()
	add_child(marker)
	art.ring(marker,1.5,Visuals.BLUE)
	marker.visible = false
	setup_fog()
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = HUD.new()
	hud.battle = self
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(hud)
	add_child(sound)
	sound.volume_db = -19
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			screenshot_path=arg.trim_prefix("--capture=")
			show_help=false
			paused=true
			selected=[1,2,3,4,5]
		if arg=="--benchmark":
			Engine.max_fps=0 # Benchmark work without the normal-play pacing limit.
			get_window().content_scale_size=Vector2i(1920,1080)
			get_window().content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
			benchmark=true
			show_help=false
			paused=false
			bench_started=Time.get_ticks_msec()
			for i in 22:
				sim.spawn("rifle",0,Vector2(8+(i%5)*4,38+(i/5)*4))
			sim.issue(sim.living(0).map(func(u): return u.id),Vector2(46,22),"attack_move")
	sync_units(0)
	if benchmark:prepare_benchmark_clock.call_deferred()

func request_zoom(factor:float) -> void:
	if not is_finite(factor) or factor<=0:return
	camera_zoom_target=clampf(camera_zoom_target*factor,MIN_ZOOM,MAX_ZOOM)

func advance_zoom(dt:float) -> void:
	camera_size=lerpf(camera_size,camera_zoom_target,1.0-exp(-14.0*maxf(dt,0)))
	if absf(camera_size-camera_zoom_target)<0.005:camera_size=camera_zoom_target
	camera.size=camera_size

func huge_world() -> bool:
	return sim.terrain.world_size.x>=256 or sim.terrain.world_size.y>=256

# Legacy maps keep fixed 12/8 m edge margins. Huge theatres scale the margin with
# zoom so a wide view does not show large areas beyond the world edge.
func pan_margin() -> Vector2:
	if not huge_world():return Vector2(12,8)
	var limit:Vector2=sim.terrain.world_size/2
	return Vector2(minf(limit.x,maxf(12,camera_size*0.5)),minf(limit.y,maxf(8,camera_size*0.35)))

# Ground-plane extent of the visible battlefield (excluding the sidebar and top
# bar) relative to the focus. The tilted orthographic view is a parallelogram
# that is not centred on the focus, so huge theatres clamp with its real corners.
func view_ground_offsets() -> Rect2:
	camera.size=camera_size
	camera.position=camera_focus+Vector3(26,64,46)
	camera.look_at(camera_focus,Vector3.UP)
	var view:Rect2=Rect2(Vector2.ZERO,get_viewport().get_visible_rect().size)
	if is_instance_valid(hud) and hud.size.x>268:view=hud.battlefield_rect()
	var bounds:=Rect2()
	var first:=true
	for corner in [view.position,Vector2(view.end.x,view.position.y),view.end,Vector2(view.position.x,view.end.y)]:
		var origin:Vector3=camera.project_ray_origin(corner)
		var direction:Vector3=camera.project_ray_normal(corner)
		if absf(direction.y)<0.001:continue
		var hit:Vector3=origin-direction*(origin.y/direction.y)
		var offset:=Vector2(hit.x-camera_focus.x,hit.z-camera_focus.z)
		if first:bounds=Rect2(offset,Vector2.ZERO);first=false
		else:bounds=bounds.expand(offset)
	return bounds

func clamp_focus() -> void:
	if huge_world():
		var extent:=view_ground_offsets()
		var world:Vector2=sim.terrain.world_size
		for axis in [0,1]:
			var low:float=-extent.position[axis]
			var high:float=world[axis]-extent.end[axis]
			var value:float=camera_focus.x if axis==0 else camera_focus.z
			value=(low+high)*0.5 if low>high else clampf(value,low,high)
			if axis==0:camera_focus.x=value
			else:camera_focus.z=value
		return
	var margin:=pan_margin()
	camera_focus.x=clampf(camera_focus.x,margin.x,sim.terrain.world_size.x-margin.x)
	camera_focus.z=clampf(camera_focus.z,margin.y,sim.terrain.world_size.y-margin.y)

func update_camera() -> void:
	clamp_focus()
	camera.size=camera_size
	camera.position=camera_focus+Vector3(26,64,46)
	camera.look_at(camera_focus,Vector3.UP)
	camera.position+=camera_shake()

# Brief screen-plane jolt from nearby blasts (effects.gd scales it by blast size and distance from the focus).
func camera_shake() -> Vector3:
	return effects.camera_shake(camera_focus,camera_size,camera.basis)

func screen_pos(p: Vector2, height: float = 0) -> Vector2:
	return camera.unproject_position(Vector3(p.x,height,p.y))

func world_pos(p: Vector2) -> Vector2:
	var origin:=camera.project_ray_origin(p)
	var direction:=camera.project_ray_normal(p)
	var ground=Plane(Vector3.UP,0).intersects_ray(origin,direction)
	if ground==null:
		return Vector2(-1,-1)
	return Vector2(ground.x,ground.z)

var _wreck_material:StandardMaterial3D
func show_wreck(node:Node3D,u:Dictionary)->void:
	node.set_meta("wreck_shown",true)
	if _wreck_material==null:
		_wreck_material=StandardMaterial3D.new()
		_wreck_material.albedo_color=Color(0.07,0.065,0.06)
		_wreck_material.roughness=1.0
	node.position=Vector3(u.pos.x,0.0,u.pos.y)
	var model:Node3D=node.get_meta("model")
	model.rotation.y=atan2(-u.facing.x,-u.facing.y)
	model.rotation.z=0.06
	for mesh in model.find_children("*","MeshInstance3D",true,false):mesh.material_override=_wreck_material
	var selection:Node3D=node.get_meta("selection")
	selection.visible=false

func altitude(u: Dictionary) -> float:
	# Strike drones carry a live altitude while they dive.
	return float(u.get("altitude",sim.definitions[u.kind].altitude))

func is_structure(u: Dictionary) -> bool:
	return bool(u.get("structure",false)) or bool(sim.definitions.get(u.get("kind",""),{}).get("structure",false))

func is_engineer(u: Dictionary) -> bool:
	return sim.alive(u) and u.kind=="engineer" and not is_structure(u)

func selected_engineer() -> int:
	for id in selected:
		if is_engineer(sim.get_unit(id)):return id
	return -1

func all_sections() -> Array:
	return sim.living(0).filter(func(u):return sim.field_ops.is_empty() or not is_structure(u)).map(func(u): return u.id)

# Field structures are fixed emplacements, so movement commands skip them.
func orderable() -> Array:
	if sim.field_ops.is_empty():return selected
	return selected.filter(func(id):return not is_structure(sim.get_unit(id)))

func setup_fog() -> void:
	fog_image=Image.create(sim.terrain.fog_grid_size.x,sim.terrain.fog_grid_size.y,false,Image.FORMAT_RGBA8)
	update_fog_pixels()
	fog_texture=ImageTexture.create_from_image(fog_image)
	var shader := Shader.new()
	shader.code="""shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform sampler2D fog_map : filter_linear, repeat_disable;
void fragment() { vec4 f = texture(fog_map, UV); ALBEDO=vec3(0.055,0.058,0.052); ALPHA=f.a; }
"""
	var material:=ShaderMaterial.new()
	material.shader=shader
	material.set_shader_parameter("fog_map",fog_texture)
	var plane:=MeshInstance3D.new()
	var mesh:=PlaneMesh.new()
	mesh.size=sim.terrain.world_size
	plane.mesh=mesh
	plane.position=Vector3(sim.terrain.world_size.x/2,0.055,sim.terrain.world_size.y/2)
	plane.material_override=material
	plane.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(plane)

func update_fog_pixels() -> void:
	for x in sim.terrain.fog_grid_size.x:
		for y in sim.terrain.fog_grid_size.y:
			fog_image.set_pixel(x,y,fog_color(Vector2i(x,y)))
	fog_drawn_visible=sim.visible_cells.duplicate()
	fog_drawn_explored=sim.explored.size()

func fog_color(id:Vector2i) -> Color:
	# Neutral shroud: unexplored ground stays legible as land, never reads as water.
	return Color(0,0,0,0.0 if sim.visible_cells.has(id) else (0.34 if sim.explored.has(id) else 0.58))

# Play-time fog refresh: only cells entering or leaving sight, and newly explored
# ones, change, so repaint those instead of the whole grid. Explored cells are only
# ever appended, so new ones are the tail of its insertion-ordered keys. Returns
# whether the texture needs an upload.
func refresh_fog_pixels() -> bool:
	if sim.explored.size()<fog_drawn_explored:
		update_fog_pixels()
		return true
	var changed:=false
	if sim.explored.size()>fog_drawn_explored:
		var keys:Array=sim.explored.keys()
		for i in range(fog_drawn_explored,keys.size()):fog_image.set_pixelv(keys[i],fog_color(keys[i]))
		fog_drawn_explored=keys.size()
		changed=true
	for id in fog_drawn_visible:
		if not sim.visible_cells.has(id):fog_image.set_pixelv(id,fog_color(id));changed=true
	for id in sim.visible_cells:
		if not fog_drawn_visible.has(id):fog_image.set_pixelv(id,fog_color(id));changed=true
	if changed:fog_drawn_visible=sim.visible_cells.duplicate()
	return changed

func _physics_process(dt: float) -> void:
	if benchmark or (not paused and not show_help):
		var start:=Time.get_ticks_usec()
		# Pre-tick poses for render interpolation, refreshed in place each tick.
		for unit in sim.units:
			if not sim.alive(unit):
				render_history.erase(unit.id)
				continue
			var history:Dictionary=render_history.get(unit.id,{})
			if history.is_empty():
				history={"pos":unit.pos,"members":[]}
				render_history[unit.id]=history
			history.pos=unit.pos
			var members:Array=history.members
			members.resize(unit.members.size())
			for i in members.size():members[i]=unit.members[i].pos
		sim.tick(dt)
		if not pending_actions.is_empty():run_pending()
		if benchmark and benchmark_ready and Time.get_ticks_msec()-bench_started>2000:
			sim_costs.append((Time.get_ticks_usec()-start)/1000.0)

func _process(dt: float) -> void:
	var presentation_started:=Time.get_ticks_usec() if benchmark else 0
	var lap:=Time.get_ticks_usec()
	advance_zoom(dt)
	weather_fx.sync(sim.weather,sim.time)
	# Material and environment writes re-send render state; only write changes.
	if shown_wetness!=sim.weather.wetness:
		shown_wetness=sim.weather.wetness
		art.ground_material.set_shader_parameter("wetness",shown_wetness)
	effects.wind=Vector3(sim.weather.wind.x,0,sim.weather.wind.y)
	var fog_on:bool=sim.weather.rain>0.01
	if atmosphere.fog_enabled!=fog_on:atmosphere.fog_enabled=fog_on
	if atmosphere.fog_light_color!=FOG_LIGHT:atmosphere.fog_light_color=FOG_LIGHT
	var density:float=sim.weather.rain*0.0004
	if shown_fog_density!=density:
		shown_fog_density=density
		atmosphere.fog_density=density
	toast_time=maxf(0,toast_time-dt)
	if hint_dirty and Time.get_ticks_msec()-hint_msec>=HINT_INTERVAL_MSEC:refresh_cursor_hint()
	marker_time=maxf(0,marker_time-dt)
	marker.visible=marker_time>0
	if marker.visible:
		marker.scale=Vector3.ONE*(1+(1-marker_time)*0.8)
	if not show_help and sim.result=="":
		var movement:=Vector2.ZERO
		if Input.is_physical_key_pressed(KEY_LEFT): movement.x-=1
		if Input.is_physical_key_pressed(KEY_RIGHT): movement.x+=1
		if Input.is_physical_key_pressed(KEY_UP): movement.y-=1
		if Input.is_physical_key_pressed(KEY_DOWN): movement.y+=1
		var mouse:=get_viewport().get_mouse_position()
		var view:=get_viewport().get_visible_rect().size
		var over_battlefield:bool=hud.action_at(mouse)==""
		if over_battlefield and mouse.y>0 and mouse.y<view.y:
			if mouse.x>=0 and mouse.x<10: movement.x-=1
			if mouse.x<=view.x and mouse.x>view.x-10: movement.x+=1
		if over_battlefield and mouse.x>0 and mouse.x<view.x:
			if mouse.y>=0 and mouse.y<10: movement.y-=1
			if mouse.y>view.y-10 and mouse.y<view.y: movement.y+=1
		var right:=Vector2(camera.global_basis.x.x,camera.global_basis.x.z).normalized()
		var down:=Vector2(-right.y,right.x)
		# Huge theatres pan proportionally faster when zoomed out; legacy speed is unchanged.
		var speed:=32.0*(maxf(1.0,camera_size/72.0) if huge_world() else 1.0)
		var pan:Vector2=(right*movement.x+down*movement.y)*dt*speed
		camera_focus.x+=pan.x
		camera_focus.z+=pan.y
		update_camera()
	lap=flap("pre_sync",lap)
	sync_units(dt)
	lap=flap("sync_units",lap)
	trail_clock-=dt
	if trail_clock<=0:
		trail_clock=0.13
		if not paused and not show_help:
			for unit in sim.units:
				if not sim.alive(unit) or not unit.visible: continue
				var old: Vector2=unit_last_positions.get(unit.id,unit.pos)
				if old.distance_to(unit.pos)>0.12 and unit.kind in ["tank","aa","boat"]:
					effects.dust(Vector3(unit.pos.x,0.15,unit.pos.y),unit.facing,unit.kind=="boat")
				unit_last_positions[unit.id]=unit.pos
				if unit.hp<unit.max_hp*0.4 and unit.kind in ["tank","aa","helo","boat"]:
					effects.damage_smoke(Vector3(unit.pos.x,altitude(unit)+1,unit.pos.y),unit.hp/unit.max_hp)
	lap=flap("trails",lap)
	consume_events()
	if audio!=null:audio.frame(dt,camera_focus,camera.global_basis,camera_size,benchmark or (not paused and not show_help))
	lap=flap("events",lap)
	for i in range(fx.size()-1,-1,-1):
		fx[i].life-=dt
		if fx[i].life<=0:
			fx[i].node.queue_free()
			fx.remove_at(i)
	fog_clock-=dt
	if fog_clock<=0:
		if refresh_fog_pixels():fog_texture.update(fog_image)
		fog_clock=0.3
	lap=flap("fog",lap)
	for i in objective_nodes.size():
		var show_capture_radius:=false
		for id in selected:
			var unit:Dictionary=sim.get_unit(id)
			if sim.alive(unit) and unit.pos.distance_squared_to(sim.objectives[i].pos)<196:
				show_capture_radius=true
				break
		objective_nodes[i].get_child(0).visible=show_capture_radius
		var owner:int=sim.objectives[i].owner
		if objective_nodes[i].get_meta("owner",-999)!=owner:
			var col:=Visuals.BLUE if owner==0 else Color("f0ba75")
			objective_nodes[i].get_child(0).material_override=art.material(col,true)
			objective_nodes[i].set_meta("owner",owner)
	for id in selected:
		if not sim.alive(sim.get_unit(id)):
			selected=selected.filter(func(alive_id): return sim.alive(sim.get_unit(alive_id)))
			break
	if build_mode!="" and not sim.field_ops.is_empty() and selected_engineer()<0:
		build_mode=""
		notify("Placement cancelled • no living engineer selected")
	if not sim.field_ops.is_empty():watch_sites()
	hud.frame()
	lap=flap("post",lap)
	if screenshot_path!="":
		capture_frames+=1
		if capture_frames==12:
			capture.call_deferred()
	if benchmark and benchmark_ready:
		var now:=Time.get_ticks_usec()
		if previous_frame_usec>0 and Time.get_ticks_msec()-bench_started>2000:
			benchmark_frames.append((now-previous_frame_usec)/1000.0)
			presentation_costs.append((now-presentation_started)/1000.0)
			engine_costs.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
		previous_frame_usec=now
		if Time.get_ticks_msec()-bench_started>20000:
			write_benchmark()

func sync_units(dt: float) -> void:
	if contact_shadows==null:_make_contact_shadows()
	contact_shadow_count=0
	var required:=0
	for unit in sim.units:required+=unit.members.size()
	if required>contact_shadows.multimesh.instance_count:
		contact_shadows.multimesh.instance_count=required*2
	for u in sim.units:
		if not nodes.has(u.id):
			nodes[u.id]=art.make_unit(self,u)
			nodes[u.id].set_meta("model",nodes[u.id].get_node("Model"))
			nodes[u.id].set_meta("selection",nodes[u.id].get_node("Selection"))
			if not u.members.is_empty():nodes[u.id].set_meta("infantry_shadow_meshes",nodes[u.id].get_node("Model").find_children("*","MeshInstance3D",true,false))
			nodes[u.id].set_meta("fine_shadow_meshes",nodes[u.id].find_children("*","MeshInstance3D",true,false).filter(func(mesh):return mesh.get_meta("fine_shadow",false)))
		var node: Node3D=nodes[u.id]
		# Destroyed/abandoned vehicles stay on the map as dark burnt-out wrecks.
		if not sim.alive(u) and u.get("wrecked",false):
			node.visible=true
			if not node.has_meta("wreck_shown"):show_wreck(node,u)
			continue
		# A lost boat that was on screen slips under over SINK_SECONDS of sim time, then hides.
		if u.kind=="boat" and not sim.alive(u):
			sink_boat(node,u)
			continue
		# Fallen soldiers of a destroyed section stay where they fell.
		node.visible=(sim.alive(u) or sim.Infantry.has_remains(u)) and u.visible
		if not node.visible:
			continue
		var distant_shadows:=camera_size>45.0
		if not node.has_meta("distant_shadows") or node.get_meta("distant_shadows")!=distant_shadows:
			for mesh in node.get_meta("infantry_shadow_meshes",node.get_meta("fine_shadow_meshes",[])):
				mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if distant_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			node.set_meta("distant_shadows",distant_shadows)
		var fraction:=1.0 if paused or show_help else Engine.get_physics_interpolation_fraction()
		var history:Dictionary=render_history.get(u.id,{})
		var display_pos:Vector2=u.pos
		var model: Node3D=node.get_meta("model")
		# One interpolated-member array per model, refilled in place each frame.
		if not model.has_meta("display_members"):model.set_meta("display_members",[])
		var display_members:Array=model.get_meta("display_members")
		display_members.resize(0 if history.is_empty() else u.members.size())
		if not history.is_empty():
			display_pos=(history.pos as Vector2).lerp(u.pos,fraction)
			for i in u.members.size():
				display_members[i]=(history.members[i] as Vector2).lerp(u.members[i].pos,fraction)
		if garrisoned(u):display_pos=display_anchor(u)
		Motion.set_position(node,Vector3(display_pos.x,altitude(u),display_pos.y))
		model.set_meta("display_pos",display_pos)
		if distant_shadows and not u.members.is_empty():
			for i in u.members.size():
				if u.members[i].hp<=0:continue
				var p:Vector2=display_members[i] if i<display_members.size() else u.members[i].pos
				contact_shadows.multimesh.set_instance_transform(contact_shadow_count,Transform3D(Basis.IDENTITY,Vector3(p.x+0.16,0.045,p.y+0.10)))
				contact_shadow_count+=1
		var heading:=atan2(-u.facing.x,-u.facing.y)
		if u.get("structure",false) and not sim.field_ops.is_empty():
			# Keep the placement turn (rotated linear works) instead of resetting it.
			var placed:=Vector3(0,PI/2 if u.get("rotated",false) else 0.0,0)
			if model.rotation!=placed:model.rotation=placed
			preload("res://scripts/field_models.gd").sync_construction(model,u)
		elif u.kind in ["tank","aa"]:
			Motion.set_rotation_axis(model,1,rotate_toward(model.rotation.y,heading,dt*1.8))
		else:Motion.set_rotation_axis(model,1,lerp_angle(model.rotation.y,heading,minf(1,dt*10)))
		var selection_node:Node3D=node.get_meta("selection")
		selection_node.visible=selected.has(u.id)
		Motion.set_position_axis(selection_node,1,0.13-altitude(u))
		# A garrisoned section's ring encircles its building.
		var ring_scale:=1.0
		if garrisoned(u):
			var bounds:Rect2=sim.Garrison.index(sim).buildings[u.garrison].bounds
			ring_scale=(maxf(bounds.size.x,bounds.size.y)*0.5+1.2)/1.55
		var ring:=Vector3(ring_scale,1.0,ring_scale)
		if selection_node.scale!=ring:selection_node.scale=ring
		var pose_lap:int=Time.get_ticks_usec() if profiling_frames else 0
		Motion.pose(model,u,sim,(1.0/30.0 if not model.has_meta("previous") else 0.0) if paused else maxf(dt,0.0001))
		if profiling_frames:flap("pose",pose_lap)

	contact_shadows.multimesh.visible_instance_count=contact_shadow_count
	contact_shadows.visible=camera_size>45.0 and contact_shadow_count>0

# Settles stern-first and drops SINK_DEPTH below where it died; no new nodes or
# materials, and hidden for good once under, so draw cost stays flat. Frozen while paused.
const SINK_SECONDS:=3.0
const SINK_DEPTH:=3.2
const SINK_TRIM:=0.32
func sink_boat(node:Node3D,u:Dictionary)->void:
	if not node.has_meta("sink_from"):
		if not node.visible:return # died unseen or already gone
		# Keeps the flooding list it died with; effects.gd stops posing a root once it carries sink_from.
		var forward:=Vector3(u.facing.x,0,u.facing.y)
		var trim_axis:=forward.normalized().cross(Vector3.UP) if forward.length_squared()>0.0001 else Vector3.RIGHT
		node.set_meta("sink_from",[float(sim.time),node.position,node.basis,trim_axis])
		node.get_meta("selection").visible=false
	if not node.visible:return
	var start:Array=node.get_meta("sink_from")
	var t:=clampf((float(sim.time)-float(start[0]))/SINK_SECONDS,0.0,1.0)
	if t>=1.0:
		node.visible=false
		return
	Motion.set_position(node,(start[1] as Vector3)+Vector3.DOWN*SINK_DEPTH*t*t)
	Motion.set_basis(node,Basis(start[3],SINK_TRIM*t)*(start[2] as Basis))

func _make_contact_shadows()->void:
	contact_shadows=MultiMeshInstance3D.new()
	contact_shadows.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad:=PlaneMesh.new();quad.size=Vector2(0.85,1.05)
	var batch:=MultiMesh.new();batch.transform_format=MultiMesh.TRANSFORM_3D;batch.mesh=quad
	batch.instance_count=256;batch.visible_instance_count=0
	contact_shadows.multimesh=batch
	var material:=ShaderMaterial.new();var shader:=Shader.new()
	shader.code="""shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
void fragment(){float d=length((UV-vec2(0.5))*2.0);ALBEDO=vec3(0.035,0.04,0.035);ALPHA=(1.0-smoothstep(0.15,1.0,d))*0.30;}
"""
	material.shader=shader;contact_shadows.material_override=material
	add_child(contact_shadows)

# Procedural sound layer (scripts/audio_fx.gd), created in _ready.
var audio:Node3D=null
func consume_events() -> void:
	for event in sim.events:
		if event.type=="destroyed" and event.get("abandoned",false):continue
		if audio!=null:audio.event(event)
		if event.type in ["warning","order_report"]:
			notify(event.text)
		elif event.type=="crushed":
			if harbor_props==null:harbor_props=find_child("HarborProps",true,false)
			if harbor_props!=null:preload("res://scripts/harbor_props.gd").crush(harbor_props,int(event.prop),event.heading)
		elif event.type in ["building_damage","building_collapse","world_blast"]:
			preload("res://scripts/ruined_building.gd").show_damage(art,self,sim,event)
		elif event.type=="shot" and event.visible:
			# Presentation only: effects apply each weapon's barrel offset, tracer cadence and impact surface.
			var a:=Vector3(event.from.x,float(event.from_y),event.from.y)
			var b:=Vector3(event.to.x,float(event.to_y),event.to.y)
			effects.fire(event.kind,a,b,event.get("hit",true),sim.terrain.is_water(event.to),event.get("target_kind",""),sim.terrain.is_water(event.from))
		elif event.type=="vehicle_damage" and event.team==0 and event.effect in ["recrewed","captured"]:
			remap_recrew(event)
		elif event.type=="destroyed" and event.visible:
			var kind:String=event.get("kind","")
			var height:=maxf(0.7,float(sim.definitions[kind].altitude)) if sim.definitions.has(kind) else 0.7
			effects.destroyed(kind,Vector3(event.pos.x,height,event.pos.y),sim.terrain.is_water(event.pos))
	sim.events.clear()

# A re-crewed or captured vehicle is a new unit: wherever its old hull or the
# boarding section was (selection, control groups), the vehicle joins, and the
# hull (and a section that climbed in whole) drops out.
func remap_recrew(event:Dictionary)->void:
	var fresh:int=int(event.unit)
	var section:int=int(event.get("section",-1))
	var gone:Array=[int(event.get("from",-1))]
	if not sim.alive(sim.get_unit(section)):gone.append(section)
	selected=recrew_list(selected,fresh,[section]+gone,gone)
	for key in groups:groups[key]=recrew_list(groups[key],fresh,[section]+gone,gone)

func recrew_list(list:Array,fresh:int,sources:Array,gone:Array)->Array:
	if not sources.any(func(id):return list.has(id)):return list
	var out:Array=list.filter(func(id):return not gone.has(id))
	if not out.has(fresh):out.append(fresh)
	return out

func notify(message: String) -> void:
	toast=message
	toast_time=4

func ping() -> void:
	if audio!=null:audio.ui("order")

func pick(p: Vector2, enemy: bool = false) -> int:
	var best:=-1
	var distance:=24.0
	for u in sim.units:
		if not sim.alive(u) or not u.visible or (u.team==0 if enemy else u.team!=0):
			continue
		for projected in click_points(u):
			var d:=p.distance_to(projected)
			if d<distance:
				best=u.id
				distance=d
	# Garrisoned soldiers are hidden inside: clicking their building selects them.
	if best<0 and not enemy and not sim.field_ops.is_empty():
		var building:int=building_under(p)
		if building>=0:
			for u in sim.Garrison.occupants(sim,building,0):return u.id
	return best

func garrisoned(u:Dictionary)->bool:
	return u.get("garrison",-1)>=0

# Where a unit is shown: a garrisoned section at its building's centre.
func display_anchor(u:Dictionary)->Vector2:
	if garrisoned(u):return sim.Garrison.index(sim).buildings[u.garrison].bounds.get_center()
	return u.pos

# Label height: above the roof for a garrisoned section.
func label_height(u:Dictionary)->float:
	if garrisoned(u):return float(sim.Garrison.index(sim).buildings[u.garrison].height)+1.0
	return altitude(u)+2.4

# Screen points that select a unit: its anchor and every living soldier, so a
# click on any visible soldier picks the section even when it is spread out.
func click_points(u:Dictionary) -> Array:
	var points:Array=[screen_pos(display_anchor(u),altitude(u)+0.8)]
	for member in u.members:
		if member.hp>0:points.append(screen_pos(member.pos,0.8))
	return points

# City building under the cursor: test the view ray at roof heights first so a
# click on a roof selects that building, not the ground behind it.
func building_under(p:Vector2) -> int:
	var origin:=camera.project_ray_origin(p)
	var direction:=camera.project_ray_normal(p)
	if absf(direction.y)<0.001:return -1
	for height in [12.0,9.0,6.0,3.0,0.5]:
		var hit:Vector3=origin+direction*((float(height)-origin.y)/direction.y)
		var building:int=sim.Garrison.building_at(sim,Vector2(hit.x,hit.z))
		if building>=0:return building
	return -1

func give_order(p: Vector2, attack: bool, queued: bool) -> void:
	if selected.is_empty():
		notify("Select a section first")
		return
	var enemy:=pick(p,true)
	var destination:=world_pos(p)
	if not sim.classic.is_empty() and selected.size()==1:
		var facility:Dictionary=sim.get_unit(selected[0])
		if sim.definitions[facility.kind].get("structure",false):
			facility.rally=destination
			notify("Production rally point set")
			return
	var ids:=orderable()
	if ids.is_empty():
		notify("Field structures are fixed • select a section to move")
		attack_mode=false
		return
	# Sections whose survivors are all down cannot move or fight: say so and
	# order the rest (they stay selectable).
	var downed:Array=ids.filter(func(id):return sim.get_unit(id).get("combat_ineffective",false))
	var downed_note:=""
	if not downed.is_empty():
		downed_note=sim.DOWNED_NOTE if downed.size()==1 else "%d sections down · wounded cannot move" % downed.size()
		if downed.size()==ids.size():
			notify(downed_note)
			attack_mode=false
			return
		ids=ids.filter(func(id):return not downed.has(id))
	# Right-click special actions (re-crew, clear, resume, garrison) and A-click
	# shelling go to the sections able to do them; the rest of a mixed selection
	# takes the normal order to the clicked point. Shift queues the action behind
	# a busy section's current orders (pending_actions).
	var note:=""
	var plan:=special_plan(p,enemy,attack,ids)
	if not plan.is_empty():
		var now:Array=plan.units.filter(func(id):return not queued or sim.get_unit(id).orders.is_empty())
		var later:Array=plan.units.filter(func(id):return not now.has(id))
		var acted:Array=run_action(plan,now) if not now.is_empty() else []
		for id in later:pending_actions.append({"action":plan.action,"target":plan.target,"unit":id,"group":int(sim.get_unit(id).command_group)})
		var rest:Array=ids.filter(func(id):return not plan.units.has(id))
		if acted.is_empty() and later.is_empty():
			note=action_failure(plan)
			if note!="" and rest.is_empty():
				notify(note)
				attack_mode=false
				return
		else:
			note=action_note(plan,acted.size(),later.size())
			if rest.is_empty():
				notify(note)
				ping()
				attack_mode=false
				return
		if note!="":ids=ids.filter(func(id):return not acted.has(id) and not later.has(id))
		# A building's interior has no route: the others close up at its approach.
		if plan.action in ["garrison","shell"]:
			var approach:=building_approach(int(plan.target),ids)
			if approach.x>=0:destination=approach
	var lead:=note+" • " if note!="" else ""
	var mode:="attack" if enemy>=0 else ("attack_move" if attack else "move")
	# Immobilised hulls (tracks/engine out) cannot move: say so and move the rest.
	var stuck:Array=[] if mode=="attack" else ids.filter(func(id):return sim.get_unit(id).get("mobility_kill",false) and sim.definitions[sim.get_unit(id).kind].domain!="air")
	var stuck_note:=""
	if not stuck.is_empty():
		var hull:Dictionary=sim.get_unit(stuck[0])
		stuck_note=("%s immobilised · cannot move" % sim.VehicleDamage.LABEL.get(hull.kind,str(hull.kind).capitalize())) if stuck.size()==1 else "%d vehicles immobilised · cannot move" % stuck.size()
		if stuck.size()==ids.size():
			notify(lead+stuck_note)
			attack_mode=false
			return
		ids=ids.filter(func(id):return not stuck.has(id))
	var before:=active_sites()
	var count:=sim.issue(ids,destination,mode,queued,enemy)
	if count==0:
		notify(lead+sim.order_feedback)
	else:
		if sim.order_adjusted:
			for id in ids:
				var ordered:Dictionary=sim.get_unit(id)
				if sim.alive(ordered) and not ordered.orders.is_empty():
					destination=ordered.orders[-1].pos
					break
		marker.position=Vector3(destination.x,0.1,destination.y)
		marker_time=1.0
		var status:=lead+("Nearest accessible position" if sim.order_adjusted else ("Queued" if queued else "Order confirmed"))
		# A large group's last targets resolve over the next ticks: the real count follows.
		if sim.order_resolving>0:sim.report_resolution(status,ids.size())
		notify((lead+"Order issued • resolving %d…" % sim.order_resolving if sim.order_resolving>0 else status+" • %d / %d sections" % [count,ids.size()])+release_note(before))
		if stuck_note!="":notify(lead+stuck_note+" • %d / %d moving" % [count,ids.size()+stuck.size()])
		if downed_note!="":notify(lead+downed_note+" • %d / %d moving" % [count,ids.size()+stuck.size()+downed.size()])
		ping()
	attack_mode=false

# The special action a click at p gives the selection (re-crew, clear, resume,
# shell, garrison; first match wins) or {} for a plain move/attack. units are
# the sections that would carry it out; label is the cursor hint.
func special_plan(p:Vector2,enemy:int,attack:bool,ids:Array) -> Dictionary:
	if enemy<0 and not attack:
		var hull:Dictionary=sim.VehicleDamage.abandoned_at(sim,world_pos(p))
		if not hull.is_empty():
			var crew:=-1
			var nearest:=INF
			for id in ids:
				var section:Dictionary=sim.get_unit(id)
				if sim.VehicleDamage.can_recrew(sim,section) and section.pos.distance_squared_to(hull.pos)<nearest:
					crew=id
					nearest=section.pos.distance_squared_to(hull.pos)
			if crew>=0:return {"action":"recrew","target":hull.id,"units":[crew],"label":"Capture" if hull.team!=0 else "Re-crew","name":sim.VehicleDamage.LABEL.get(hull.kind,str(hull.kind).capitalize()),"enemy":hull.team!=0}
	if sim.field_ops.is_empty():return {}
	if not attack:
		var engineers:Array=ids.filter(func(id):return sim.get_unit(id).kind=="engineer")
		var work_id:=enemy if enemy>=0 else pick(p)
		var work:Dictionary=sim.get_unit(work_id) if work_id>=0 and not engineers.is_empty() else {}
		var unfinished:bool=not work.is_empty() and work.team==0 and float(work.get("build_left",0.0))>0
		if not work.is_empty() and not unfinished and sim.FieldOps.can_clear(sim,work):
			return {"action":"clear","target":work_id,"units":engineers.slice(0,1),"label":"Clear","name":HUD.FIELD_LABELS.get(work.kind,"obstacle")}
		if enemy<0 and unfinished and is_structure(work):
			return {"action":"resume","target":work_id,"units":engineers.slice(0,1),"label":"Build"}
	if enemy>=0:return {}
	var building:int=building_under(p)
	if building<0:return {}
	var able:Array=ids.filter(func(id):return can_shell(sim.get_unit(id))) if attack else ids.filter(func(id):return sim.Garrison.can_garrison(sim,sim.get_unit(id)))
	if able.is_empty():return {}
	return {"action":"shell" if attack else "garrison","target":building,"units":able,"label":"Shell" if attack else "Garrison"}

# Open ground beside a building for the given sections: the doorway nearest
# their centre, wide enough for the largest of them.
func building_approach(building:int,ids:Array) -> Vector2:
	var centre:=Vector2.ZERO
	var radius:=0.0
	for id in ids:
		var u:Dictionary=sim.get_unit(id)
		centre+=u.pos
		radius=maxf(radius,float(sim.definitions[u.kind].radius))
	if ids.is_empty():return Vector2(-1,-1)
	return sim.Garrison.entry_point(sim,building,centre/ids.size(),radius)

# HE-armed mobile units StructureDamage.bombard accepts.
func can_shell(u:Dictionary) -> bool:
	if not sim.alive(u) or not u.members.is_empty() or StructureDamage.he_spec(sim,u).is_empty():return false
	var d:Dictionary=sim.definitions[u.kind]
	return not d.get("strike",false) and not d.get("structure",false) and float(d.speed)>0.0

# Carries out a special action now; returns the sections that took it.
func run_action(plan:Dictionary,units:Array) -> Array:
	var target:int=int(plan.target)
	match plan.action:
		"recrew":return units.slice(0,1) if sim.VehicleDamage.order_recrew(sim,units.slice(0,1),target)>0 else []
		"clear":return units.slice(0,1) if sim.FieldOps.clear_site(sim,target,int(units[0])) else []
		"resume":return units.slice(0,1) if sim.FieldOps.resume(sim,target,int(units[0])) else []
		"shell":
			StructureDamage.bombard(sim,units,target)
			return units.filter(func(id):return int(sim.get_unit(id).get("bombard",-1))==target)
		"garrison":
			sim.Garrison.order(sim,units,target)
			return units.filter(func(id):return int(sim.get_unit(id).get("garrison_target",-1))==target)
	return []

func action_note(plan:Dictionary,now:int,later:int) -> String:
	var queued:=" · %d after current orders" % later if later>0 else ""
	match plan.action:
		"recrew":
			var text:=("capture the enemy %s" if plan.enemy else "re-crew the %s") % plan.name
			return "Section moving to "+text if now>0 else "Queued: "+text+" after current orders"
		"clear":return "Engineers clearing %s" % plan.name if now>0 else "Queued: engineers clear %s after current orders" % plan.name
		"resume":return "Engineers resuming construction" if now>0 else "Queued: engineers resume construction after current orders"
		"shell":
			if now==0:return "Queued: %d unit%s shell the building after current orders" % [later,"" if later==1 else "s"]
			return "%d unit%s shelling the building" % [now,"" if now==1 else "s"]+queued
	if now==0:return "Queued: %d section%s enter the building after current orders" % [later,"" if later==1 else "s"]
	return "%d section%s entering building • fire from windows · move to leave" % [now,"" if now==1 else "s"]+queued

# Refusal toast; "" lets the click fall through to a normal order for everyone.
func action_failure(plan:Dictionary) -> String:
	match plan.action:
		"garrison":return "Building full or no doorway reachable"
		"clear":return str(sim.field_ops.get("last_build_error","Cannot clear this"))
		"resume":return str(sim.field_ops.get("last_build_error","Cannot resume this site"))
	return ""

# Shift-queued special actions start once the section's orders run out. A new
# direct order (new command group), Stop (orders and intent cleared) or death
# drops them. Polled per sim tick; the list is usually empty.
func run_pending() -> void:
	for i in range(pending_actions.size()-1,-1,-1):
		var job:Dictionary=pending_actions[i]
		var u:Dictionary=sim.get_unit(int(job.unit))
		if not sim.alive(u) or int(u.command_group)!=int(job.group) or (u.orders.is_empty() and u.intent.is_empty()):
			pending_actions.remove_at(i)
			continue
		if not u.orders.is_empty():continue
		pending_actions.remove_at(i)
		if run_action(job,[job.unit]).is_empty():
			var reason:=action_failure(job)
			notify(reason if reason!="" else "Queued action no longer possible")

# Cursor action hint for the hovered target, recomputed on input at most every
# HINT_INTERVAL_MSEC (never per frame on its own).
func refresh_cursor_hint() -> void:
	hint_dirty=false
	hint_msec=Time.get_ticks_msec()
	cursor_hint=""
	if selected.is_empty() or show_help or sim.result!="" or build_mode!="" or strike_mode or dragging or pointer.x<0 or hud.action_at(pointer)!="":return
	# Downed sections (survivors all down) take no actions.
	var ids:=orderable().filter(func(id):return not sim.get_unit(id).get("combat_ineffective",false))
	if ids.is_empty():return
	cursor_hint=str(special_plan(pointer,pick(pointer,true),attack_mode,ids).get("label",""))

func ui_action(action: String, p: Vector2) -> void:
	match action:
		"begin":
			show_help=false
			paused=false
			if not sim.classic.is_empty():notify("Build a refinery near your HQ; harvest resources, then build power and production.")
			elif not sim.field_ops.is_empty():notify("Select the engineers to build field works • Buy reinforcements with supply")
			else:notify("Scout first. Ground sections capture sectors.")
		"help": show_help=true
		"pause": paused=not paused
		"restart": get_tree().reload_current_scene()
		"attack":
			attack_mode=true
			strike_mode=false
		"stop":
			var before:=active_sites()
			var stopped:=sim.stop(orderable())
			notify("Stop acknowledged by %d / %d sections • disconnected units keep orders" % [stopped,orderable().size()]+release_note(before))
		"retreat":
			attack_mode=false
			var before:=active_sites()
			var withdrawn:=sim.retreat(orderable())
			notify(("Withdrawing %d sections • Recovery at landing zone costs supply" if sim.field_ops.is_empty() else "Withdrawing %d sections • Heal at aid posts and repair points") % withdrawn+release_note(before))
		"all": selected=all_sections()
		"minimap":
			var target: Vector2=(p-hud.minimap.position)/hud.minimap.size*sim.terrain.world_size
			camera_focus=Vector3(target.x,0,target.y)
		_:
			if action.begins_with("scenario:"):
				Sim.scenario_selection=int(action.trim_prefix("scenario:"))
				get_tree().reload_current_scene()
			elif action.begins_with("build:") and not sim.field_ops.is_empty():
				var kind:=action.trim_prefix("build:")
				attack_mode=false
				strike_mode=false
				if selected_engineer()<0:
					build_mode=""
					notify("Select a living engineer section to build")
				else:
					build_mode=kind
					build_rotated=false
					notify("Place %s • %s • Esc cancels" % [field_choice(kind).get("name",kind.capitalize()),HUD.FIELD_FUNCTIONS.get(kind,"")])
			elif action.begins_with("build:"):
				build_mode=action.trim_prefix("build:")
				attack_mode=false
				notify("Place "+build_mode+" near your base • Esc cancels")
			elif action=="cancel_build" and selected.size()==1:
				var site:Dictionary=sim.get_unit(selected[0])
				var refund:int=hud.cancel_refund(sim,site) if sim.alive(site) and site.get("structure",false) else 0
				if sim.FieldOps.cancel(sim,selected[0]):
					notify("%s cancelled • %d supply refunded" % [HUD.FIELD_LABELS.get(site.kind,"Site"),refund])
					selected.clear()
				else:notify("Only unfinished field structures can be cancelled")
			elif action=="resume_build" and selected.size()==1:
				var site:Dictionary=sim.get_unit(selected[0])
				if sim.FieldOps.resume(sim,selected[0]):
					notify("%s resumed • engineers en route • no charge" % HUD.FIELD_LABELS.get(site.kind,"Site"))
					ping()
				else:notify(build_error("Unable to resume construction"))
			elif action=="cancel_queue" and selected.size()==1:
				sim.Classic.cancel(sim,sim.get_unit(selected[0]))
			elif action=="strike:fpv" and not sim.field_ops.is_empty():
				var reason:String=sim.FieldOps.strike_reason(sim)
				strike_mode=reason==""
				if strike_mode:
					attack_mode=false
					build_mode=""
				notify("FPV strike armed • click a seen enemy • Esc cancels" if strike_mode else reason)
			elif action.begins_with("buy:"):
				var kind:=action.trim_prefix("buy:")
				if sim.recruit(kind):
					if not sim.field_ops.is_empty():
						var waiting:int=sim.FieldOps.queue(sim).size()
						if sim.field_ops.get("last_deployed",false) and waiting==0:
							notify("Reinforcement deployed at %s" % ("forward supply point" if sim.field_ops.get("last_entry_forward",false) else "landing zone"))
						else:notify("%s queued • %d waiting • right-click tile to remove" % [HUD.UNIT_NAMES.get(kind,kind.capitalize()),waiting])
					else:notify("Production queued")
					ping()
				elif not sim.classic.is_empty():notify(sim.Classic.production_reason(sim,kind,0))
				else:notify(recruit_reason(kind))

# Aim at the clicked enemy, else at the point; a miss keeps targeting armed.
func launch_strike(p:Vector2) -> void:
	var target:=pick(p,true)
	var aim:Vector2=sim.get_unit(target).pos if target>=0 else world_pos(p)
	var ids:Array=sim.FieldOps.player_strike(sim,aim,target)
	if ids.is_empty():
		notify(str(sim.field_ops.get("last_purchase_error","FPV strike unavailable")))
		if sim.FieldOps.strike_reason(sim)!="":strike_mode=false
		return
	strike_mode=false
	notify("FPV STRIKE LAUNCHED • %d drones • %d supply" % [ids.size(),sim.FieldOps.PLAYER_STRIKE_COST])
	ping()

func place_field_structure(site:Vector2) -> void:
	var engineer:=selected_engineer()
	if engineer<0:
		build_mode=""
		notify("Placement cancelled • select a living engineer section")
		return
	if sim.FieldOps.build(sim,build_mode,site,engineer,build_rotated):
		notify("%s site marked • engineers stay on site to build" % HUD.FIELD_LABELS.get(build_mode,"Field"))
		build_mode=""
		ping()
	# Commit can fail on bodies the preview may not reveal; report the sim's result.
	else:notify(build_error("Site unavailable"))

# A short drag (or click) places one piece honouring T rotation; a long drag lays a line or area.
func finish_field_drag(release:Vector2) -> void:
	if build_mode=="" or sim.field_ops.is_empty():return
	if release.distance_to(build_drag_start)<1.5:
		place_field_structure(build_drag_start)
		return
	var engineer:=selected_engineer()
	if engineer<0:
		build_mode="";notify("Placement cancelled • select a living engineer section")
		return
	var plan:Array=sim.FieldOps.drag_plan(sim,build_mode,build_drag_start,release)
	var count:int=sim.FieldOps.build_many(sim,build_mode,plan,engineer)
	if count>0:
		notify("%d × %s marked • %d supply • engineers build them in turn" % [count,HUD.FIELD_LABELS.get(build_mode,"Field"),count*int(sim.definitions[build_mode].cost)])
		build_mode=""
		ping()
	else:notify(build_error("Line blocked or insufficient supply"))

func build_error(fallback:String) -> String:
	var message:String=str(sim.field_ops.get("last_build_error",""))
	return message if message!="" else fallback

# Unfinished sites with a builder assigned, before an order may release it.
func active_sites() -> Array:
	if sim.field_ops.is_empty():return []
	return sim.units.filter(func(u):return sim.alive(u) and u.get("structure",false) and float(u.get("build_left",0.0))>0 and not u.get("build_paused",false)).map(func(u):return u.id)

func release_note(before:Array) -> String:
	var paused:Array=before.filter(func(id):return sim.get_unit(id).get("build_paused",false))
	if paused.is_empty():return ""
	if paused.size()==1:return " • %s site paused, RESUME later" % HUD.FIELD_LABELS.get(sim.get_unit(paused[0]).kind,"Field")
	return " • %d sites paused, RESUME later" % paused.size()

# Announce builder loss and completion once per change; pauses are announced by the order.
func watch_sites() -> void:
	for u in sim.units:
		if not u.get("structure",false) or not sim.alive(u):continue
		var condition:String=hud.site_condition(sim,u)
		var previous:String=site_watch.get(u.id,"")
		site_watch[u.id]=condition
		if previous=="" or previous==condition:continue
		if condition=="lost":notify("%s builder lost • select site, RESUME" % HUD.FIELD_LABELS.get(u.kind,"Field"))
		elif condition=="complete":notify("%s complete" % HUD.FIELD_LABELS.get(u.kind,"Field"))

# Cached once: build_choices() parses its resource file on every call.
func field_choices() -> Dictionary:
	if field_choice_cache.is_empty() and not sim.field_ops.is_empty():field_choice_cache=sim.FieldOps.build_choices()
	return field_choice_cache

func field_choice(kind:String) -> Dictionary:
	return field_choices().get(kind,{})

func recruit_reason(kind:String) -> String:
	var cost:=float(sim.definitions.get(kind,{}).get("cost",0))
	if sim.credits<cost:return "Need %d more supply" % ceili(cost-sim.credits)
	if sim.recruit_clock>0:return "Deployment ready in %.1fs" % sim.recruit_clock
	return "Unable to deploy reinforcement"

func _input(event: InputEvent) -> void:
	if benchmark:return
	if not is_instance_valid(hud):
		return
	if event is InputEventMouse:pointer=event.position
	if event is InputEventMouse or event is InputEventKey:hint_dirty=true
	if event is InputEventMagnifyGesture:
		if not show_help and sim.result=="" and hud.action_at(event.position)=="":
			request_zoom(1.0/maxf(event.factor,0.01))
		return
	if event is InputEventMouseButton:
		var p: Vector2=event.position
		if event.pressed:
			var action: String=hud.action_at(p)
			# Queue removal works on greyed tiles too (e.g. when supply is spent).
			if event.button_index==MOUSE_BUTTON_RIGHT and hud.hit_id_at(p).begins_with("buy:"):action=hud.hit_id_at(p)
			if action!="":
				if action.begins_with("buy:") and event.button_index==MOUSE_BUTTON_RIGHT and not sim.field_ops.is_empty():
					var kind:=action.trim_prefix("buy:")
					if sim.FieldOps.cancel_queued(sim,kind):notify("%s removed from queue • %d supply refunded" % [HUD.UNIT_NAMES.get(kind,kind.capitalize()),int(sim.definitions[kind].cost)])
					else:notify("No %s queued" % HUD.UNIT_NAMES.get(kind,kind))
					return
				if action=="minimap" and event.button_index==MOUSE_BUTTON_RIGHT:
					var target: Vector2=(p-hud.minimap.position)/hud.minimap.size*sim.terrain.world_size
					var before:=active_sites()
					var count:=sim.issue(orderable(),target,"attack_move" if attack_mode else "move",event.shift_pressed)
					if sim.order_resolving>0:sim.report_resolution("Minimap order",count)
					notify(("Minimap order • resolving %d…" % sim.order_resolving if sim.order_resolving>0 else "Minimap order • %d sections" % count)+release_note(before))
					attack_mode=false
				if event.button_index==MOUSE_BUTTON_LEFT:
					ui_action(action,p)
				return
			if event.button_index==MOUSE_BUTTON_WHEEL_UP:
				if not show_help and sim.result=="":request_zoom(pow(0.90,maxf(event.factor,0.1)))
			elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN:
				if not show_help and sim.result=="":request_zoom(pow(1.0/0.90,maxf(event.factor,0.1)))
			elif event.button_index==MOUSE_BUTTON_LEFT:
				if strike_mode:
					launch_strike(p)
					return
				if build_mode!="" and not sim.field_ops.is_empty():
					if sim.FieldOps.draggable(build_mode) and selected_engineer()>=0:
						build_drag=true
						build_drag_start=world_pos(p)
					else:place_field_structure(world_pos(p))
					return
				if build_mode!="":
					if sim.Classic.build(sim,build_mode,0,world_pos(p)):
						notify("Construction started")
						build_mode=""
					else:notify("Placement blocked, too far from base, busy construction, or insufficient funds")
					return
				if attack_mode:
					give_order(p,true,event.shift_pressed)
				else:
					drag_start=p
					dragging=true
			elif event.button_index==MOUSE_BUTTON_RIGHT and strike_mode:
				strike_mode=false
				notify("FPV strike cancelled")
			elif event.button_index==MOUSE_BUTTON_RIGHT:
				give_order(p,false,event.shift_pressed)
		elif event.button_index==MOUSE_BUTTON_LEFT and build_drag:
			build_drag=false
			finish_field_drag(world_pos(p))
		elif event.button_index==MOUSE_BUTTON_LEFT and dragging:
			dragging=false
			if not event.shift_pressed:
				selected.clear()
			if p.distance_to(drag_start)<6:
				var id:=pick(p)
				if id>=0:
					if selected.has(id): selected.erase(id)
					else: selected.append(id)
			else:
				var rectangle:=Rect2(drag_start,p-drag_start).abs()
				for u in sim.living(0):
					# Box selection gathers sections; click a field structure to inspect it.
					if not sim.field_ops.is_empty() and is_structure(u):continue
					if rectangle.has_point(screen_pos(display_anchor(u),altitude(u))) and not selected.has(u.id):
						selected.append(u.id)
	if event is InputEventKey and event.pressed and not event.echo:
		if sim.result!="":
			if event.keycode==KEY_ENTER: get_tree().reload_current_scene()
			return
		if event.keycode==KEY_ESCAPE:
			if build_mode!="":
				build_mode=""
				notify("Placement cancelled")
			elif strike_mode:
				strike_mode=false
				notify("FPV strike cancelled")
			elif show_help: show_help=false
			elif attack_mode: attack_mode=false
			else: paused=not paused
			return
		if show_help:
			if event.keycode==KEY_ENTER: ui_action("begin",Vector2.ZERO)
			return
		match event.keycode:
			KEY_T:
				if build_mode in sim.FieldOps.ROTATABLE and not sim.field_ops.is_empty():
					build_rotated=not build_rotated
					notify("Placement turned %s" % ("across" if build_rotated else "along"))
			KEY_A:
				attack_mode=not selected.is_empty()
				if attack_mode:strike_mode=false
			KEY_S:
				var before:=active_sites()
				var stopped:=sim.stop(orderable())
				notify("Stop acknowledged by %d / %d sections" % [stopped,orderable().size()]+release_note(before))
			KEY_R: ui_action("retreat",Vector2.ZERO)
			KEY_SPACE: paused=not paused
			KEY_F:
				if not selected.is_empty():
					var focus:=Vector2.ZERO
					for id in selected: focus+=sim.get_unit(id).pos
					focus/=selected.size()
					camera_focus=Vector3(focus.x,0,focus.y)
			KEY_F1: show_help=true
			KEY_M:
				effects.muted=not effects.muted
				sound.volume_db=-80 if effects.muted else -19
				if audio!=null:audio.set_muted(effects.muted)
				notify("Audio muted" if effects.muted else "Audio enabled")
			KEY_TAB: selected=all_sections()
		if event.keycode>=KEY_1 and event.keycode<=KEY_9:
			var key:int=event.keycode-KEY_0
			if event.ctrl_pressed or event.meta_pressed:
				groups[key]=selected.duplicate()
				notify("Control group %d assigned" % key)
			elif groups.has(key):
				selected=groups[key].filter(func(id): return sim.alive(sim.get_unit(id)))

func capture() -> void:
	await RenderingServer.frame_post_draw
	var error:=get_viewport().get_texture().get_image().save_png(screenshot_path)
	print("CAPTURE ",screenshot_path," status=",error)
	get_tree().quit(error)

func prepare_benchmark_clock()->void:
	# First-frame shader/pipeline compilation is startup, not steady-state gameplay.
	await RenderingServer.frame_post_draw
	bench_started=Time.get_ticks_msec()
	previous_frame_usec=0
	benchmark_frames.clear();sim_costs.clear();presentation_costs.clear();engine_costs.clear()
	benchmark_ready=true

func write_benchmark() -> void:
	benchmark=false
	benchmark_frames.sort()
	sim_costs.sort();presentation_costs.sort();engine_costs.sort()
	var data:={"presentation_script_ms_p95":presentation_costs[int(presentation_costs.size()*0.95)] if not presentation_costs.is_empty() else 0,"engine_process_ms_p95":engine_costs[int(engine_costs.size()*0.95)] if not engine_costs.is_empty() else 0,"static_memory_mb":Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0,"texture_memory_mb":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)/1048576.0,"vsync_mode":DisplayServer.window_get_vsync_mode(),"msaa_mode":get_viewport().msaa_3d,"render_fps_cap":Engine.max_fps,"physics_hz":Engine.physics_ticks_per_second,"scenario":sim.scenario.name,"weather":sim.weather.label,"simulation_seconds":sim.time,"simulation_samples":sim_costs.size(),"engine":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"frames":benchmark_frames.size(),"frame_ms_p50":benchmark_frames[int(benchmark_frames.size()*0.5)],"frame_ms_p95":benchmark_frames[int(benchmark_frames.size()*0.95)],"simulation_ms_p95":sim_costs[int(sim_costs.size()*0.95)] if not sim_costs.is_empty() else 0,"groups":sim.units.size(),"viewport":str(get_viewport().get_visible_rect().size),"measurement":"Monotonic wall-clock between rendered process frames; first frame excluded; 20s run with first 2s discarded; editor binary, windowed", "window_pixels":str(get_window().size),"render_pixels":str(get_viewport().get_texture().get_size()),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"visible_members":sim.living(0).reduce(func(n,u): return n+(u.members.filter(func(m):return m.hp>0).size() if not u.members.is_empty() else 1),0)}
	var file:=FileAccess.open("res://artifacts/benchmark.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(data,"  "))
	print(JSON.stringify(data))
	get_tree().quit()

func _exit_tree() -> void:
	sound.stop()
