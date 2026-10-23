class_name ScenarioCatalog
extends RefCounted

# Legacy indices are part of the existing regression fixtures. Regional maps
# append lightweight descriptors; only the selected battlefield is loaded.
const LEGACY_PATH:="res://resources/scenarios.json"
const REGION_PATH:="res://resources/regions/black_sea_region.json"
const SUMMARY_KEYS:=["id","name","brief","mode","hidden","size","hold","map_renderer","available_domains"]
static var _entries:Array=[]
static var _configs:Dictionary={}
static var _loaded:=false

static func _load()->void:
	if _loaded:return
	_loaded=true
	var legacy=JSON.parse_string(FileAccess.get_file_as_string(LEGACY_PATH))
	if not legacy is Array:
		push_error("Invalid scenario catalog: "+LEGACY_PATH)
		return
	for value in legacy:
		if not value is Dictionary:continue
		var summary:Dictionary={}
		for key in SUMMARY_KEYS:
			if value.has(key):summary[key]=value[key]
		_configs[_entries.size()]=value
		_entries.append(summary)
	if not FileAccess.file_exists(REGION_PATH):return
	var region=JSON.parse_string(FileAccess.get_file_as_string(REGION_PATH))
	if not region is Dictionary:
		push_error("Invalid region catalog: "+REGION_PATH)
		return
	for field in region.get("battlefields",[]):
		if not field is Dictionary:continue
		var id:String=str(field.get("scenario_id",field.get("id","")))
		if id.is_empty() or _find_id(id)>=0:continue
		var path:String=str(field.get("map_path",""))
		if not path.begins_with("res://resources/maps/") or not path.ends_with(".json"):
			push_error("Regional battlefield has an invalid map path: "+id)
			continue
		var summary:Dictionary={"id":id,"name":str(field.get("name",id.to_upper().replace("_"," "))),
			"brief":str(field.get("brief",field.get("description",""))),"hidden":false,
			"mode":"field_ops","map_renderer":"harbor","map_path":path}
		for key in SUMMARY_KEYS:
			if field.has(key) and key!="id":summary[key]=field[key]
		_entries.append(summary)

static func _find_id(id:String)->int:
	for index in _entries.size():
		if str(_entries[index].get("id",""))==id:return index
	return -1

static func entries()->Array:
	_load()
	return _entries.duplicate(true)

static func index_for_id(id:String)->int:
	_load()
	return _find_id(id)

static func config(index:int,reload_external:bool=false)->Dictionary:
	_load()
	if index<0 or index>=_entries.size():
		push_error("Scenario index is outside the catalog: %d"%index)
		return {}
	# A fresh deployment after editor Save & build must see the rebuilt file.
	# Keep metadata and unrelated maps cached; read only the selected external map.
	if reload_external and _entries[index].has("map_path"):_configs.erase(index)
	if not _configs.has(index):
		var descriptor:Dictionary=_entries[index]
		var path:String=str(descriptor.get("map_path",""))
		if not FileAccess.file_exists(path):
			push_error("Regional battlefield is missing: "+path)
			return {}
		var data=JSON.parse_string(FileAccess.get_file_as_string(path))
		if not data is Dictionary or str(data.get("id",""))!=str(descriptor.id):
			push_error("Regional battlefield ID does not match its catalog: "+path)
			return {}
		_configs[index]=data
	# Simulation fixtures may change config values; never mutate another battle
	# or the catalog's cached source by sharing a returned dictionary.
	return _configs[index].duplicate(true)

static func config_by_id(id:String)->Dictionary:
	var index:=index_for_id(id)
	return config(index) if index>=0 else {}
