extends RefCounted
# A small operational save, deliberately separate from tactical simulation.
# Deployment checkpoints, outcomes, survivors and supply persist. Positions,
# orders, structures and elapsed battle time are local to the current battle.
const PATH := "user://regional_campaign.json"
const VERSION := 1
const Catalog := preload("res://scripts/region_catalog.gd")
const MOBILE := ["rifle","atgm","engineer","tank","aa","drone","helo","boat"]
const DAMAGE_FLAGS := ["mobility_kill","firepower_kill","optics_kill"]
const DAMAGE_KEYS := ["mobility_kill","firepower_kill","optics_kill","crew","crew_full","missiles","flood","flood_rate","fire_left"]
const MEMBER_COUNTS := {"rifle":3,"atgm":2,"engineer":3}
const BENEFITS := {
	"black_sea_harbor":{"label":"Harbor freight","income":1.0},
	"bayhead_rail_valley":{"label":"Rail resupply","income":2.0},
	"limestone_pass":{"label":"Pass interdiction","reserve_delay":45.0},
	"south_inlet":{"label":"Coastal resupply","income":1.0},
	"windbreak_fields":{"label":"Agricultural supply road","income":1.0}
}
static var session_loaded := false
static var storage_path := PATH
# Scripted test/review scenes must not read or overwrite a player's campaign.
# Integration tests opt in with their own isolated storage_path.
static var enabled := not OS.get_cmdline_args().has("--script")
var data:Dictionary = fresh()
var parked:Array = []
var active := false
var begun := false
var finished := false
var blocked := false
var recovered := false
var deploy_clock := 0.0
var last_error:Error = OK

static func fresh() -> Dictionary:
	return {"version":VERSION,"started":false,"supply":0.0,"roster":[],"secured":{},"history":{},"last_battlefield":"","retry":{}}

static func number(value:Variant,low:float,high:float) -> bool:
	return typeof(value) in [TYPE_FLOAT,TYPE_INT] and is_finite(float(value)) and float(value)>=low and float(value)<=high

static func valid(value:Variant,checkpoint:bool=false) -> bool:
	if not value is Dictionary or value.get("version",-1)!=VERSION:return false
	if not value.get("started") is bool or not number(value.get("supply"),0,10000000):return false
	if not value.get("roster") is Array or value.roster.size()>256:return false
	if not value.get("secured") is Dictionary or not value.get("history") is Dictionary:return false
	if value.secured.size()>64 or value.history.size()>64:return false
	if not value.get("last_battlefield") is String:return false
	for key in value.secured:
		if not key is String or not value.secured[key] is bool:return false
	for key in value.history:
		if not key is String or value.history[key] not in ["VICTORY","DEFEAT","WITHDRAWN"]:return false
	for record in value.roster:
		if not record is Dictionary or record.get("kind","") not in MOBILE:return false
		if not number(record.get("hp"),0.00001,100000) or not record.get("members",[]) is Array:return false
		# Missing infantry records would otherwise respawn the omitted soldiers
		# healthy. A version-1 save always contains every member, including KIA.
		if record.get("members",[]).size()!=int(MEMBER_COUNTS.get(record.kind,0)) or not record.get("damage",{}) is Dictionary:return false
		for key in record.get("damage",{}):
			var item:Variant=record.damage[key]
			if key not in DAMAGE_KEYS:return false
			if key in DAMAGE_FLAGS:
				if not item is bool:return false
			elif not number(item,0,10000):return false
			if key in ["crew","crew_full","missiles"] and float(item)!=floorf(float(item)):return false
		if record.get("damage",{}).has("crew_full") and float(record.damage.crew_full)<1:return false
		if record.get("damage",{}).has("crew") and record.damage.has("crew_full") and float(record.damage.crew)>float(record.damage.crew_full):return false
		for member in record.get("members",[]):
			if not member is Dictionary or not number(member.get("hp"),0,100000):return false
			if member.get("wound","") not in ["HEALTHY","LIGHT","SEVERE","KIA"]:return false
			if not number(member.get("bleed_left",0),0,10000):return false
			if not member.get("stable",false) is bool:return false
	if not checkpoint and not value.get("retry",{}) is Dictionary:return false
	if not checkpoint and not value.get("retry",{}).is_empty() and not valid(value.retry,true):return false
	return true

func read_file(path:String) -> Variant:
	if not FileAccess.file_exists(path):return null
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>2000000:return null
	# Corrupt saves are a recoverable input condition, not an engine script
	# error. Instance parsing reports the failure without logging a hard error.
	var parser:=JSON.new()
	return parser.data if parser.parse(file.get_as_text())==OK else null

func load_state(path:String=PATH) -> Error:
	data=fresh();parked.clear();blocked=false;recovered=false
	if not FileAccess.file_exists(path) and not FileAccess.file_exists(path+".bak"):return ERR_FILE_NOT_FOUND
	var parsed:Variant=read_file(path)
	if not valid(parsed):
		parsed=read_file(path+".bak")
		if not valid(parsed):
			blocked=true
			last_error=ERR_FILE_CORRUPT
			return last_error
		recovered=true
	data=parsed
	last_error=OK
	return OK

func save_state(path:String=PATH) -> Error:
	if blocked:return save_result(ERR_FILE_CORRUPT)
	if not valid(data):return save_result(ERR_INVALID_DATA)
	var target:=ProjectSettings.globalize_path(path)
	var error:=DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	if error!=OK:return save_result(error)
	var temporary:=target+".tmp"
	var file:=FileAccess.open(temporary,FileAccess.WRITE)
	if file==null:return save_result(FileAccess.get_open_error())
	file.store_string(JSON.stringify(data,"\t"));file.flush()
	error=file.get_error();file.close()
	if error!=OK:return save_result(error)
	# Rotate only a valid previous save. Recovery must never replace its
	# known-good backup with the corrupt primary it just recovered from.
	var had_previous:=FileAccess.file_exists(target)
	var previous_valid:bool=had_previous and valid(read_file(target))
	if previous_valid:
		if FileAccess.file_exists(target+".bak"):
			error=DirAccess.remove_absolute(target+".bak")
			if error!=OK:return save_result(error)
		error=DirAccess.rename_absolute(target,target+".bak")
		if error!=OK:return save_result(error)
	elif had_previous:
		error=DirAccess.remove_absolute(target)
		if error!=OK:return save_result(error)
	error=DirAccess.rename_absolute(temporary,target)
	if error!=OK and previous_valid:DirAccess.rename_absolute(target+".bak",target)
	if error==OK:recovered=false
	return save_result(error)

func save_result(error:Error) -> Error:
	last_error=error
	return error

func reset(path:String=PATH) -> Error:
	var previous:Dictionary={"data":data,"parked":parked.duplicate(true),"blocked":blocked,"begun":begun,"finished":finished,"recovered":recovered}
	data=fresh();parked=[];blocked=false;begun=false;finished=false;recovered=false
	var error:=save_state(path)
	if error!=OK:
		data=previous.data;parked=previous.parked;blocked=previous.blocked;begun=previous.begun;finished=previous.finished;recovered=previous.recovered
	return error

func secured(id:String) -> bool:
	return bool(data.secured.get(id,false))

func modifiers() -> Dictionary:
	var result:Dictionary={"income":0.0,"reserve_delay":0.0}
	for id in BENEFITS:
		if not secured(id):continue
		for key in result:result[key]+=float(BENEFITS[id].get(key,0.0))
	return result

func benefit(id:String) -> String:
	var entry:Dictionary=BENEFITS.get(id,{})
	if entry.is_empty():return ""
	if entry.has("income"):return "%s · +%s supply/s regionwide" % [entry.label,String.num(float(entry.income))]
	return "%s · first enemy reserve delayed 45s" % entry.label

func summary() -> String:
	if blocked:return "Campaign save could not be read. Start a new campaign to reset it."
	if not data.started:return "New campaign · survivors and supply carry between operations"
	return "%d secured  ·  %d reserve sections  ·  %d supply" % [data.secured.size(),data.roster.size(),int(data.supply)]

func prepare(sim) -> void:
	active=not sim.field_ops.is_empty() and Catalog.for_scenario(Catalog.data(),str(sim.scenario.id))!=""
	parked.clear();begun=false;finished=false
	if not active or blocked:return
	var bonus:=modifiers()
	sim.field_ops.income_rate+=float(bonus.income)
	sim.field_ops["reserve_delay_bonus"]=float(bonus.reserve_delay)
	if not data.started:return
	# The expedition replaces the authored initial force, never adds a free army.
	for index in range(sim.units.size()-1,-1,-1):
		if sim.units[index].team==0:
			sim.units_by_id.erase(sim.units[index].id)
			sim.units.remove_at(index)
	sim.credits=float(data.supply)
	parked=data.roster.duplicate(true)
	deploy_waiting(sim)
	# An empty expedition may buy one ordinary rifle section at its normal cost.
	# Defeat also retains the previous deployment checkpoint for an explicit retry.
	if sim.living(0).is_empty() and sim.credits>=float(sim.definitions.rifle.cost):
		if sim.FieldOps.deploy(sim,"rifle"):sim.credits-=float(sim.definitions.rifle.cost)
	sim.rebuild_spatial();sim.update_visibility()

func deploy_waiting(sim) -> void:
	if not active or finished or blocked:return
	var domains:Array=sim.scenario.get("available_domains",["land","air","sea"])
	for index in range(parked.size()-1,-1,-1):
		var record:Dictionary=parked[index]
		if not sim.definitions.has(record.kind) or sim.definitions[record.kind].domain not in domains:continue
		var origin:Vector2=sim.field_ops.sea_insertion if sim.definitions[record.kind].domain=="sea" else sim.field_ops.insertion
		var pos:Vector2=sim.FieldOps.entry_position(sim,str(record.kind),origin)
		if pos.x<0:continue
		var unit:Dictionary=sim.spawn(str(record.kind),0,pos)
		if unit.is_empty():continue
		restore_unit(sim,unit,record)
		parked.remove_at(index)

func tick(sim,dt:float) -> void:
	if not begun or finished or parked.is_empty():return
	deploy_clock-=dt
	if deploy_clock<=0:
		deploy_clock=3.0
		deploy_waiting(sim)

func restore_unit(sim,unit:Dictionary,record:Dictionary) -> void:
	unit.hp=clampf(float(record.hp),0.00001,float(unit.max_hp))
	# crew marks initialized component state. Install its transient reload/aim
	# fields before restoring persistent damage, or weapon_ready would read
	# missing keys and recovered damage could be overwritten on the next hit.
	if sim.VehicleDamage.tracked(sim,unit):sim.VehicleDamage.ensure_state(sim,unit)
	for key in record.get("damage",{}):
		if key!="fire_left":unit[key]=record.damage[key]
	if unit.get("optics_kill",false):unit["accuracy"]=sim.VehicleDamage.OPTICS_ACCURACY
	var fire_left:float=float(record.get("damage",{}).get("fire_left",0.0))
	if fire_left>0:unit["fire_until"]=sim.time+fire_left
	if unit.has("flood") or fire_left>0:sim.VehicleDamage._hazard(sim,unit)
	var saved:Array=record.get("members",[])
	for index in mini(saved.size(),unit.members.size()):
		var member:Dictionary=unit.members[index]
		var source:Dictionary=saved[index]
		member.hp=clampf(float(source.hp),0,float(member.max_hp))
		member.wound=str(source.wound)
		member.stable=bool(source.get("stable",false))
		member.bleed_at=sim.time+float(source.get("bleed_left",0.0)) if member.wound=="SEVERE" and not member.stable else INF
		member["campaign_absent"]=member.wound=="KIA"
		if member.wound in ["SEVERE","KIA"]:
			member.hp=0.0
			member.state="KIA" if member.wound=="KIA" else "DOWN"
	if not unit.members.is_empty():sim.Infantry.publish(unit)

func snapshot(sim) -> Array:
	var roster:Array=parked.duplicate(true)
	for unit in sim.living(0):
		if unit.kind not in MOBILE or unit.get("abandoned",false) or unit.has("crash"):continue
		var record:Dictionary={"kind":str(unit.kind),"hp":float(unit.hp),"members":[],"damage":{}}
		for key in DAMAGE_KEYS:
			if unit.has(key):record.damage[key]=unit[key]
		if unit.has("fire_until"):
			var fire_left:float=maxf(0,float(unit.fire_until)-sim.time)
			if fire_left>0:record.damage["fire_left"]=fire_left
		for member in unit.members:
			var left:float=maxf(0,float(member.get("bleed_at",INF))-sim.time)
			record.members.append({"hp":float(member.hp),"wound":str(member.get("wound","HEALTHY")),"stable":bool(member.get("stable",false)),"bleed_left":left if is_finite(left) else 0.0})
		roster.append(record)
	return roster

func begin(sim,path:String=PATH) -> Error:
	if not active:return OK
	if begun:return save_state(path) if last_error!=OK else OK
	if blocked:return ERR_FILE_CORRUPT
	data.started=true
	data.supply=maxf(0,sim.credits)
	data.roster=snapshot(sim)
	data.last_battlefield=str(sim.scenario.id)
	var checkpoint:Dictionary=data.duplicate(true)
	checkpoint.erase("retry")
	data.retry=checkpoint
	begun=true
	return save_state(path)

func record_outcome(sim,outcome:String,path:String=PATH) -> Error:
	if not active or not begun:return OK
	if finished:return save_state(path) if last_error!=OK else OK
	if outcome not in ["VICTORY","DEFEAT","WITHDRAWN"]:return save_result(ERR_INVALID_PARAMETER)
	data.roster=snapshot(sim)
	data.supply=maxf(0,sim.credits)
	# Purchases waiting off-map have not arrived; refund them exactly once.
	for kind in sim.field_ops.get("queue",[]):data.supply+=float(sim.definitions[kind].cost)
	var id:String=str(sim.scenario.id)
	data.last_battlefield=id
	data.history[id]=outcome
	if outcome=="VICTORY":data.secured[id]=true
	elif outcome=="DEFEAT" or outcome=="WITHDRAWN":data.secured.erase(id)
	finished=true
	return save_state(path)

func retry(path:String=PATH) -> Error:
	var checkpoint:Dictionary=data.get("retry",{})
	if checkpoint.is_empty():return ERR_DOES_NOT_EXIST
	var previous:Dictionary={"data":data,"finished":finished,"begun":begun}
	data=checkpoint.duplicate(true);data.retry={}
	finished=false;begun=false
	var error:=save_state(path)
	if error!=OK:data=previous.data;finished=previous.finished;begun=previous.begun
	return error
