extends SceneTree
const Visuals=preload("res://scripts/visuals.gd")
var camera:Camera3D
var overlay:Control
var art=Visuals.new()
var labels:Array[Dictionary]=[]
var actors:Array[Dictionary]=[]
var font:=SystemFont.new()
func _init() -> void:
	call_deferred("run")
func draw_labels() -> void:
	overlay.draw_rect(Rect2(0,0,1600,92),Color("111c22"))
	overlay.draw_string(font,Vector2(32,42),"RA / NEO     •     EQUIPMENT STUDY",HORIZONTAL_ALIGNMENT_LEFT,-1,25,Color("e6ece7"))
	overlay.draw_string(font,Vector2(32,69),"Original game models  /  Silhouette, running gear, equipment and material pass",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("96aaa8"))
	for label in labels:
		var p:Vector2=camera.unproject_position(label.pos)
		overlay.draw_string(font,p,label.text,HORIZONTAL_ALIGNMENT_CENTER,170,15,Color("d6e2da"))
func run() -> void:
	root.size=Vector2i(1600,1000)
	font.font_names=PackedStringArray(["Avenir Next","Helvetica Neue","Arial"])
	var stage:=Node3D.new()
	root.add_child(stage)
	var env:=WorldEnvironment.new()
	env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color("202a2b")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color("bbc4c7")
	env.environment.ambient_light_energy=0.6
	stage.add_child(env)
	var sun:=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-50,-32,0)
	sun.light_energy=1.0
	sun.light_color=Color("ffe9c8")
	sun.shadow_enabled=true
	stage.add_child(sun)
	art.box(stage,Vector3(0,-0.12,0),Vector3(31,0.2,25),Color("3a4240"))
	camera=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=24
	camera.position=Vector3(13,22,24)
	stage.add_child(camera)
	camera.look_at(Vector3(0,0.3,0))
	camera.current=true
	var kinds:=["tank","aa","helo","rifle","atgm","boat","drone"]
	var names:=["VANGUARD MBT","SKYGUARD IFV","KESTREL GUNSHIP","RIFLE SECTION","JAVELIN TEAM","LITTORAL CORVETTE","GHOST UAV"]
	for i in kinds.size():
		var model:Node3D=art.make_unit(stage,{"kind":kinds[i],"team":0})
		model.position=Vector3((i%3-1)*7.2,0,-6+(i/3)*6.6)
		if kinds[i]=="helo": model.position.y=1.1
		if kinds[i]=="drone": model.position.y=0.8
		model.rotation.y=-0.25
		var simulation=preload("res://scripts/simulation.gd").new(false)
		var unit=simulation.spawn(kinds[i],0,Vector2(90,60) if kinds[i]=="boat" else Vector2(15,60))
		var target=simulation.spawn("drone",1,Vector2(40,30))
		target.seen_by[0]=true
		unit.target=target.id
		actors.append({"sim":simulation,"unit":unit,"model":model.get_node("Model")})
		labels.append({"pos":model.position+Vector3(-1.7,0,2.6),"text":names[i]})
	var layer:=CanvasLayer.new()
	root.add_child(layer)
	overlay=Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(overlay)
	overlay.draw.connect(draw_labels)
	for frame in 24:
		for actor in actors:
			actor.sim.time=frame*0.1
			actor.unit.pos+=Vector2(0.17,0)
			actor.unit.last_shot=actor.sim.time if frame%9==0 else actor.unit.last_shot
			actor.unit.last_hit=actor.sim.time if frame==18 else actor.unit.last_hit
			actor.unit.suppression=0.9 if frame>16 else 0.0
			preload("res://scripts/infantry.gd").move(actor.unit,actor.sim,0.1)
			preload("res://scripts/unit_animation.gd").pose(actor.model,actor.unit,actor.sim,0.1)
		await process_frame
		await RenderingServer.frame_post_draw
		if frame in [5,12,19]:
			print("MOTION REVIEW ",root.get_texture().get_image().save_png("res://artifacts/motion-%d.png" % frame))
	quit()
