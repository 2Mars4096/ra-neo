extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Terrain=preload("res://scripts/terrain.gd")
var checks:=0
var failures:=0
var evidence:Array=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)
func _init()->void:call_deferred("run")
func run()->void:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		var t=Terrain.new(i)
		var expected:Array=configs[i].get("size",[96,72])
		check(t.world_size==Vector2(expected[0],expected[1]),"authored/default dimensions %s"%i)
		check(t.land.region.size==t.fog_grid_size,"coarse grid covers scenario %s"%i)
		check(t.nav_grid("land",0.8).region.size==Vector2i((t.world_size/t.nav_cell_size).ceil()),"fine grid covers scenario %s"%i)
		evidence.append({"scenario":configs[i].name,"size":expected})
	# Constructor fixture exercises the same config API without editing authored maps.
	var config:Dictionary=configs[0].duplicate(true)
	config.size=[144,108];config.shore_x=128;config.port=false
	var terrain=Terrain.new(0,config)
	check(terrain.world_size==Vector2(144,108) and terrain.fog_grid_size==Vector2i(72,54),"large config dimensions")
	check(terrain.cell(Vector2(143,107))==Vector2i(71,53),"far fog cell")
	for domain in ["land","sea","air"]:
		var start:=Vector2(100,85) if domain!="sea" else Vector2(136,20)
		var goal:=Vector2(120,100) if domain!="sea" else Vector2(136,98)
		var path:Array=terrain.path(start,goal,domain,1.8)
		check(not path.is_empty(),"far-region route "+domain)
		for point in path:
			check(terrain.segment_clear(start,point,domain,1.8),"far route swept clearance "+domain)
			start=point
	check(not terrain.traversable(Vector2(143,106),"air",1.8),"outer body margin")
	var route:Array=terrain.path(Vector2(100,85),Vector2(120,100),"land",1.8,[{"pos":Vector2(110,92.5),"radius":4.0}],"tracked")
	check(not route.is_empty(),"far-region dynamic detour")
	var previous:=Vector2(100,85)
	for point in route:
		check(terrain.avoids_bodies(previous,point,[{"pos":Vector2(110,92.5),"radius":4.0}]),"far dynamic body clearance")
		previous=point
	terrain.wetness=0.8
	check(terrain.nav_grid("land",1.8,"tracked").region.size==Vector2i(144,108),"wet weight refresh covers expanded grid")
	var sim=Sim.new(false,0)
	sim.terrain=terrain
	var scout=sim.spawn("drone",0,Vector2(120,96))
	sim.update_visibility()
	check(sim.visible_cells.has(Vector2i(60,48)),"far observer reveals far fog")
	check(sim.rally_point(scout)==Vector2(15,97),"rally uses southern map edge")
	var battle=load("res://scripts/battle.gd").new()
	battle.sim=sim
	root.add_child(battle.camera)
	battle.setup_fog()
	check(battle.fog_image.get_size()==Vector2i(72,54),"fog image dimensions")
	battle.camera_focus=Vector3(130,0,95);battle.update_camera()
	check(battle.camera_focus==Vector3(130,0,95),"camera reaches expanded region")
	battle.camera_focus=Vector3(999,0,999);battle.update_camera()
	check(battle.camera_focus==Vector3(132,0,100),"camera respects expanded bounds")
	var hud=load("res://scripts/hud.gd").new()
	hud.minimap=Rect2(0,0,240,180);battle.hud=hud
	battle.ui_action("minimap",Vector2(200,160))
	check(battle.camera_focus.is_equal_approx(Vector3(120,0,96)),"minimap click maps to expanded world")
	hud.free();battle.effects.flashes.free();battle.effects.explosion_audio.free();battle.camera.free();battle.effects.free();battle.weather_fx.free();battle.sound.free();battle.free()
	var report={"checks":checks,"failures":failures,"scenarios":evidence,"synthetic_size":[144,108],"authored_sixth_present":configs.size()>5,"native_render_review":false}
	FileAccess.open("res://artifacts/scenario-dimensions.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("SCENARIO DIMENSIONS: ",checks," checks, ",failures," failures; authored sixth present: ",configs.size()>5)
	quit(0 if failures==0 else 1)
