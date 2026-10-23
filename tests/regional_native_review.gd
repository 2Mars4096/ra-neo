extends SceneTree
# Native captures of real regional battle scenes. Fog is deliberately revealed
# for geography review; these images do not establish rendered performance.
# DISPLAY=:91 Godot --path . --script tests/regional_native_review.gd
const Sim=preload("res://scripts/simulation.gd")
const Catalog=preload("res://scripts/scenario_catalog.gd")
const VIEWS:=[
	{"id":"bayhead_rail_valley","slug":"rail-valley","overview":Vector2(224,160),"medium":Vector2(222,160),"medium_zoom":210.0,"detail":Vector2(239,119)},
	{"id":"limestone_pass","slug":"limestone-pass","overview":Vector2(224,160),"medium":Vector2(192,179),"medium_zoom":186.0,"detail":Vector2(170,236)},
	{"id":"south_inlet","slug":"south-inlet","overview":Vector2(224,160),"medium":Vector2(320,171),"medium_zoom":146.0,"detail":Vector2(359,183)}
]
var failed:=false

func _init()->void:call_deferred("run")

func capture(battle,point:Vector2,zoom:float,path:String)->void:
	battle.camera_focus=Vector3(point.x,0,point.y)
	battle.camera_size=zoom;battle.camera_zoom_target=zoom;battle.update_camera()
	battle.sync_units(0);battle.hud.queue_redraw()
	for i in 6:await process_frame
	await RenderingServer.frame_post_draw
	var error:=root.get_texture().get_image().save_png(path)
	if error!=OK:failed=true
	print("REGIONAL CAPTURE ",path," (",error,")")

func run()->void:
	root.size=Vector2i(1440,900)
	var only:=""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--map="):only=argument.trim_prefix("--map=")
	for view in VIEWS:
		if only!="" and only!=view.id:continue
		Sim.scenario_selection=Catalog.index_for_id(view.id)
		var battle=load("res://scenes/main.tscn").instantiate()
		root.add_child(battle);current_scene=battle
		battle.ui_action("begin",Vector2.ZERO)
		battle.paused=true;battle.show_help=false;battle.effects.muted=true
		battle.notices.clear()
		battle.set_physics_process(false);battle.set_process(false)
		for x in battle.sim.terrain.fog_grid_size.x:
			for y in battle.sim.terrain.fog_grid_size.y:battle.sim.visible_cells[Vector2i(x,y)]=true
		battle.update_fog_pixels();battle.fog_texture.update(battle.fog_image)
		for unit in battle.sim.units:unit.visible=true;unit.seen_by[0]=true
		var caption:=Label.new()
		caption.text="COMPOSITION REVIEW  •  FOG REVEALED"
		caption.position=Vector2(20,858)
		caption.add_theme_color_override("font_color",Color("f1dfb6"))
		caption.add_theme_font_size_override("font_size",14)
		caption.mouse_filter=Control.MOUSE_FILTER_IGNORE
		battle.hud.add_child(caption)
		await capture(battle,view.overview,220.0,"res://artifacts/regional-"+view.slug+"-overview.png")
		await capture(battle,view.medium,float(view.medium_zoom),"res://docs/images/regional-"+view.slug+".png")
		await capture(battle,view.detail,64.0,"res://artifacts/regional-"+view.slug+"-detail.png")
		battle.queue_free()
		await process_frame;await process_frame
	print("REGIONAL NATIVE REVIEW: ","FAIL" if failed else "complete")
	quit(1 if failed else 0)
