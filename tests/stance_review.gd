extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Art=preload("res://scripts/visuals.gd")
const Motion=preload("res://scripts/unit_animation.gd")
func _init()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1200,700)
	var stage:=Node3D.new();root.add_child(stage)
	var env:=WorldEnvironment.new();env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color("26353a")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_energy=0.5
	stage.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-50,-30,0);sun.shadow_enabled=true;stage.add_child(sun)
	var art=Art.new()
	art.box(stage,Vector3(0,-0.12,0),Vector3(12,0.2,7),Color("3e4840"))
	var sim=Sim.new(false,3)
	for index in 3:
		var u=sim.spawn("rifle",0,Vector2(10+index*8,60))
		for member in u.members:
			member.hp=0 if member.index>0 else member.hp
			member.pos=u.pos
			member.posture=["STANDING","CROUCHED","PRONE"][index]
			member.target=999 if index>0 else -1
		var visual=art.make_unit(stage,u)
		visual.position=Vector3((index-1)*3.1,0,0)
		for frame in 40:Motion.pose(visual.get_node("Model"),u,sim,1.0/30)
	var camera:=Camera3D.new();stage.add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=10
	camera.position=Vector3(4,5,8);camera.look_at(Vector3(0,0.4,0));camera.current=true
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	print("STANCE REVIEW ",root.get_texture().get_image().save_png("res://artifacts/stances.png"))
	quit()
