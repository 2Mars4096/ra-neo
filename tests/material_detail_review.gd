extends SceneTree
func _init()->void:call_deferred("run")
func run()->void:
 root.size=Vector2i(1200,900)
 var art=preload("res://scripts/visuals.gd").new()
 var stage:=Node3D.new();root.add_child(stage)
 var environment:=WorldEnvironment.new();environment.environment=Environment.new()
 environment.environment.background_mode=Environment.BG_COLOR
 environment.environment.background_color=Color("272d2c")
 environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
 environment.environment.ambient_light_color=Color("b8c3cc")
 environment.environment.ambient_light_energy=0.85
 environment.environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC
 stage.add_child(environment)
 var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-48,-32,0)
 sun.light_color=Color("fff8ee");sun.light_energy=0.9;sun.shadow_enabled=true;sun.shadow_opacity=0.78;stage.add_child(sun)
 art.box(stage,Vector3(0,-0.13,0),Vector3(18,0.2,18),Color("4d5249"))
 var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL
 camera.position=Vector3(6,8,9);stage.add_child(camera);camera.look_at(Vector3(0,0.5,0));camera.current=true
 for kind in ["tank","boat","rifle"]:
  var model=art.make_unit(stage,{"kind":kind,"team":0})
  camera.size=9 if kind=="boat" else (6 if kind=="tank" else 4)
  await process_frame
  await process_frame
  await RenderingServer.frame_post_draw
  var path="res://artifacts/material-close-"+kind+".png"
  print("MATERIAL DETAIL ",kind," ",root.get_texture().get_image().save_png(path))
  model.queue_free();await process_frame
 stage.queue_free();await process_frame
 quit()
