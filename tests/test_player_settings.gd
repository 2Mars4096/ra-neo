extends SceneTree
const Settings=preload("res://scripts/player_settings.gd")
var checks:=0
var failures:=0
const TEST_PATH:="user://test-player-preferences.cfg"

func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: ",label)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var preferences:=Settings.new()
	preferences.set_value("master_volume",0.35)
	preferences.set_value("camera_speed",1.4)
	preferences.set_value("zoom_speed",0.7)
	preferences.set_value("edge_scroll",false)
	preferences.set_value("fullscreen",true)
	preferences.set_value("muted",true)
	check(preferences.save_preferences(TEST_PATH)==OK,"preferences save to writable user data")
	var loaded:=Settings.new()
	check(loaded.load_preferences(TEST_PATH)==OK and loaded.values==preferences.values,"all preferences survive a new settings instance")
	# Corrupt/out-of-range fields cannot create camera runaway or silent type coercion.
	var corrupt:=ConfigFile.new()
	corrupt.set_value("player","master_volume",9.0)
	corrupt.set_value("player","camera_speed",-5.0)
	corrupt.set_value("player","zoom_speed","fast")
	corrupt.set_value("player","muted","false")
	corrupt.set_value("player","camera_shake",NAN)
	corrupt.save(TEST_PATH)
	loaded.load_preferences(TEST_PATH)
	check(loaded.values.master_volume==1.0 and loaded.values.camera_speed==0.5,"numeric settings clamp to supported bounds")
	check(loaded.values.zoom_speed==1.0 and not loaded.values.muted and loaded.values.camera_shake==1.0,"malformed values use defaults")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	loaded.load_preferences(TEST_PATH)
	check(loaded.values==Settings.DEFAULTS,"missing preferences give a playable default")
	root.size=Vector2i(1280,720)
	var battle=load("res://scenes/main.tscn").instantiate()
	battle.settings_path=TEST_PATH
	root.add_child(battle);current_scene=battle
	battle.set_process(false);battle.set_physics_process(false)
	await process_frame;await process_frame
	battle.show_help=false;battle.paused=false
	battle.open_settings()
	await process_frame;await process_frame
	check(battle.paused and battle.menu_open(),"settings pauses the live battle")
	check(Rect2(Vector2.ZERO,battle.menu.size).encloses(battle.menu.panel.get_global_rect()),"settings panel fits 1280x720")
	check(root.get_visible_rect().size==Vector2(1280,720),"720p windows get a real compact logical viewport")
	battle.change_setting("ui_scale",1.5)
	check(root.content_scale_size==Vector2i(1280,720),"interface scale is bounded to keep controls on screen")
	root.size=Vector2i(1920,1080)
	battle.update_interface_scale()
	check(root.content_scale_size==Vector2i(1280,720),"larger windows can increase interface readability")
	root.size=Vector2i(1280,720)
	battle.change_setting("ui_scale",1.0)
	battle.change_setting("master_volume",0.4)
	check(absf(db_to_linear(AudioServer.get_bus_volume_db(0))-0.4)<0.001,"master slider changes the actual audio bus")
	battle.change_setting("master_volume",0.0)
	check(AudioServer.is_bus_mute(0),"zero volume truly silences the master bus")
	battle.change_setting("master_volume",0.4)
	battle.change_setting("muted",true)
	check(AudioServer.is_bus_mute(0) and battle.effects.muted,"mute synchronizes audio bus and effects")
	battle.change_setting("muted",false)
	check(not AudioServer.is_bus_mute(0),"unmute restores the chosen volume")
	battle.camera_zoom_target=72.0
	battle.change_setting("invert_zoom",true)
	battle.user_zoom(0.9)
	check(battle.camera_zoom_target>72.0,"reverse zoom changes actual camera intent")
	battle.close_menu()
	check(not battle.menu_open() and not battle.paused,"closing settings resumes the previous running state")
	loaded.load_preferences(TEST_PATH)
	check(loaded.values.master_volume==0.4 and loaded.values.invert_zoom,"closing settings persists changes")
	battle.paused=true;battle.open_settings();battle.reset_settings();battle.close_menu()
	check(battle.paused and battle.settings.values==Settings.DEFAULTS,"restore defaults preserves tactical pause")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	print("PLAYER SETTINGS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
