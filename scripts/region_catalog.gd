extends RefCounted
# Small regional metadata only. Opening the atlas never constructs a simulation
# or loads every battlefield's buildings, collision grid or artwork.
const PATH := "res://resources/regions/black_sea_region.json"
const Scenarios := preload("res://scripts/scenario_catalog.gd")

static func data() -> Dictionary:
	if not FileAccess.file_exists(PATH):return {}
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return parsed if parsed is Dictionary else {}

static func battlefield(region:Dictionary,id:String) -> Dictionary:
	for item in region.get("battlefields",[]):
		if str(item.get("id",""))==id:return item
	return {}

static func for_scenario(region:Dictionary,id:String) -> String:
	for item in region.get("battlefields",[]):
		if str(item.get("scenario_id",item.get("id","")))==id:return str(item.id)
	return ""

static func scenario_index(region:Dictionary,id:String) -> int:
	var item:=battlefield(region,id)
	if item.is_empty():return -1
	var path:=str(item.get("map_path",""))
	if path!="" and not FileAccess.file_exists(path):return -1
	return Scenarios.index_for_id(str(item.get("scenario_id",id)))

static func point(value:Array) -> Vector2:
	return Vector2(float(value[0]),float(value[1])) if value.size()>=2 else Vector2.ZERO

static func bounds(item:Dictionary) -> Rect2:
	var value:Array=item.get("bounds",[0,0,0,0])
	return Rect2(float(value[0]),float(value[1]),float(value[2]),float(value[3])) if value.size()>=4 else Rect2()
