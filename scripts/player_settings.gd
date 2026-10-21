extends RefCounted
# Local preferences only: never stores mission state or changes simulation rules.
const PATH := "user://settings.cfg"
const DEFAULTS := {
	"master_volume":1.0, "muted":false, "fullscreen":false,
	"edge_scroll":true, "camera_speed":1.0, "zoom_speed":1.0,
	"invert_zoom":false, "camera_shake":1.0, "ui_scale":1.0
}
const LIMITS := {"master_volume":Vector2(0,1), "camera_speed":Vector2(0.5,2.0), "zoom_speed":Vector2(0.5,2.0), "camera_shake":Vector2(0,1), "ui_scale":Vector2(0.8,1.5)}
var values:Dictionary=DEFAULTS.duplicate()

func reset() -> void:
	values=DEFAULTS.duplicate()

func set_value(key:String,value:Variant) -> void:
	if not DEFAULTS.has(key):return
	if typeof(DEFAULTS[key])==TYPE_BOOL:
		if typeof(value)==TYPE_BOOL:values[key]=value
	elif typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)):
		var bounds:Vector2=LIMITS[key]
		values[key]=clampf(float(value),bounds.x,bounds.y)

func load_preferences(path:String=PATH) -> Error:
	reset()
	var config:=ConfigFile.new()
	var error:=config.load(path)
	if error!=OK:return error
	for key in DEFAULTS:
		set_value(key,config.get_value("player",key,DEFAULTS[key]))
	return OK

func save_preferences(path:String=PATH) -> Error:
	var config:=ConfigFile.new()
	for key in DEFAULTS:config.set_value("player",key,values[key])
	return config.save(path)
