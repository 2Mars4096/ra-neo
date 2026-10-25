extends SceneTree
# Native composition/UI evidence, not a performance measurement or playthrough.
# Campaign persistence is disabled automatically for --script review scenes.
const Sim=preload("res://scripts/simulation.gd")
var failed:=false

func _init() -> void:call_deferred("run")

func capture(path:String) -> void:
	for i in 5:await process_frame
	await RenderingServer.frame_post_draw
	var error:=root.get_texture().get_image().save_png(path)
	if error!=OK:failed=true
	print("OPERATIONS CAPTURE ",path," (",error,")")

func scene(id:String):
	Sim.scenario_selection=Sim.Scenarios.index_for_id(id)
	var battle=load("res://scenes/main.tscn").instantiate()
	root.add_child(battle);current_scene=battle
	battle.set_process(false);battle.set_physics_process(false)
	battle.effects.muted=true
	return battle

func reveal(battle) -> void:
	battle.show_help=false;battle.paused=true
	for x in battle.sim.terrain.fog_grid_size.x:
		for y in battle.sim.terrain.fog_grid_size.y:battle.sim.visible_cells[Vector2i(x,y)]=true
	battle.update_fog_pixels();battle.fog_texture.update(battle.fog_image)
	for unit in battle.sim.units:unit.visible=true
	var label:=Label.new()
	label.text="COMPOSITION REVIEW · FOG REVEALED"
	label.position=Vector2(20,860)
	label.add_theme_color_override("font_color",Color("e9d7ad"))
	label.add_theme_font_size_override("font_size",13)
	battle.hud.add_child(label)

func run() -> void:
	root.size=Vector2i(1440,900)
	var battle=scene("windbreak_fields")
	await capture("res://docs/images/regional-operations-briefing.png")
	if OS.get_cmdline_user_args().has("--briefing-only"):
		battle.queue_free();await process_frame;await process_frame
		quit(1 if failed else 0)
		return
	reveal(battle)
	battle.camera_focus=Vector3(288,0,192)
	battle.camera_size=220.0;battle.camera_zoom_target=220.0;battle.update_camera()
	battle.sync_units(0);battle.hud.queue_redraw()
	await capture("res://docs/images/regional-windbreak-fields.png")
	battle.open_region()
	battle.regional_map.select_battlefield("windbreak_fields")
	await capture("res://docs/images/regional-operations-atlas.png")
	battle.close_region()
	battle.queue_free();await process_frame;await process_frame
	battle=scene("south_inlet")
	reveal(battle)
	battle.camera_focus=Vector3(288,0,158)
	battle.camera_size=164;battle.camera_zoom_target=164;battle.update_camera()
	battle.sync_units(0);battle.hud.queue_redraw()
	await capture("res://docs/images/regional-sea-control.png")
	battle.queue_free();await process_frame;await process_frame
	print("REGIONAL OPERATIONS REVIEW: ","FAIL" if failed else "complete")
	quit(1 if failed else 0)
