extends SceneTree
# Native (windowed) captures of each harbor district at play zoom for realism review.
# Run windowed only by the lead: Godot --path . --script tests/harbor_native_review.gd
const VIEWS:=[
	["overview",Vector2(600,420),84.0],
	["old-town-square",Vector2(340,455),46.0],
	["monument-closeup",Vector2(328,474),24.0],
	["enemy-defence-freight",Vector2(697,385),40.0],
	["enemy-defence-old-town",Vector2(338,474),36.0],
	["old-town-waterfront",Vector2(320,360),46.0],
	["hillside-private",Vector2(430,640),46.0],
	["freight-port",Vector2(680,400),56.0],
	["microdistrict",Vector2(940,450),56.0],
	["farm-village",Vector2(700,670),56.0],
	["north-headland",Vector2(780,110),56.0],
]
func _init()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1440,900)
	var battle=load("res://scenes/main.tscn").instantiate();root.add_child(battle);current_scene=battle
	# Forces and prepared works spawn on Deploy, exactly as in play.
	battle.ui_action("begin",Vector2.ZERO)
	for i in 3:await process_frame
	battle.paused=true;battle.show_help=false;battle.effects.muted=true
	# Review the town itself: lift fog of war for every cell.
	for x in battle.sim.terrain.fog_grid_size.x:
		for y in battle.sim.terrain.fog_grid_size.y:battle.sim.visible_cells[Vector2i(x,y)]=true
	battle.update_fog_pixels();battle.fog_texture.update(battle.fog_image)
	for u in battle.sim.units:u.visible=true;u.seen_by[0]=true
	for i in 30:await process_frame
	for view in VIEWS:
		battle.camera_focus=Vector3(view[1].x,0,view[1].y);battle.camera_size=view[2];battle.camera_zoom_target=view[2];battle.update_camera()
		battle.sync_units(0)
		for i in 6:await process_frame
		await RenderingServer.frame_post_draw
		print("HARBOR CAPTURE ",view[0]," ",root.get_texture().get_image().save_png("res://artifacts/harbor-native-"+view[0]+".png"))
	print("HARBOR NATIVE REVIEW: done ",battle.sim.scenario.get("id",""))
	quit()
