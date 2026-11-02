extends SceneTree

const Sim=preload("res://scripts/simulation.gd")
const Terrain=preload("res://scripts/terrain.gd")
const Campaign=preload("res://scripts/regional_campaign.gd")
const DT:=1.0/30.0
const SOURCE:=Vector2(24,36)
const TARGET:=Vector2(37,36)
var checks:=0
var failures:=0
var paths:Array[String]=[]

func _init()->void:call_deferred("run")

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func path_for(label:String)->String:
	var path:="/tmp/ra-neo-m1-persistence-%s-%s.json"%[OS.get_process_id(),label]
	paths.append(path)
	return path

func write_state(path:String,value:Dictionary)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	check(file!=null,"isolated save path is writable")
	if file!=null:file.store_string(JSON.stringify(value));file.close()

func field():
	var sim=Sim.new(false,5)
	sim.scenario.id="bayhead_rail_valley"
	sim.terrain=Terrain.new(0,{"id":"persistence_fixture","size":[96,72],"shore_x":90,"port":false,
		"mode":"field_ops","style":"showcase","blocks":[],"woods":[],"rubble":[0,0,0,0],
		"mud":[0,0,0,0],"objectives":[],"roads":{}})
	sim.terrain.roadside_blocks.clear();sim.terrain.prop_blocks.clear();sim.terrain.trees.clear()
	sim.terrain.rebuild_static_index()
	sim.scenario.autonomy=false;sim.scenario.jam_radius=0.0
	sim.objectives.clear();sim.enemy_clock=10000.0;sim.tactical_clock=10000.0
	sim.field_ops.started=false;sim.field_ops.income_rate=0.0;sim.field_ops.enemy_clock=10000.0
	sim.field_ops.insertion=Vector2(12,50);sim.credits=1000.0
	return sim

func step_throws(sim,seconds:float)->void:
	for frame in ceili(seconds/DT):
		sim.time+=DT
		sim.Throwables.tick(sim,DT)

# JSON numbers return as floats. Compare inventory values as integral counts,
# while retaining the distinction between absent keys, zero keys and {}.
func stock(record:Dictionary)->Dictionary:
	var result:Dictionary={}
	for member in record.members:
		var carried:Dictionary={}
		for payload in member.get("throwables",{}):carried[payload]=int(member.throwables[payload])
		result[str(member.member_id)]=carried
	return result

func record_of(state:Dictionary,kind:String)->Dictionary:
	for record in state.roster:
		if record.kind==kind:return record
	return {}

func unit_of(sim,kind:String)->Dictionary:
	for unit in sim.living(0):
		if unit.kind==kind:return unit
	return {}

func release_and_transfer()->void:
	var sim=field()
	var unit:Dictionary=sim.spawn("rifle",0,SOURCE)
	var campaign=Campaign.new();campaign.prepare(sim)
	var path:=path_for("release")
	check(campaign.active and campaign.begin(sim,path)==OK,"real deployment saves a v3 inventory checkpoint")
	check(int(campaign.data.version)==3 and Campaign.valid(campaign.data),"snapshot produces valid current schema")
	var initial:=stock(unit)
	check(sim.issue_throw([unit.id],"smoke",TARGET)==1,"manual smoke starts actual preparation")
	var during:Array=campaign.snapshot(sim)
	check(stock(during[0])==initial,"snapshot during preparation retains unspent stock")
	check(not during[0].has("assignment") and not during[0].members.any(func(member):return member.has("task_action") or member.has("task_kind")),"snapshot excludes temporary command and actor ownership")
	sim.stop([unit.id]);step_throws(sim,0.2)
	check(sim.throwables.preparations.is_empty() and stock(unit)==initial,"cancellation before release spends no inventory")
	check(sim.issue_throw([unit.id],"smoke",TARGET)==1,"replacement smoke uses the retained carried item")
	var thrower:String=sim.throwables.preparations[0].member
	step_throws(sim,1.2)
	check(sim.events.filter(func(event):return event.type=="throw_release").size()==1,"executor physically releases exactly one payload")
	check(sim.Throwables.total(unit,"smoke")==2 and int(stock(unit)[thrower].smoke)==0,"release consumes only the selected holder's smoke")
	var spent:=stock(unit)
	check(campaign.record_outcome(sim,"WITHDRAWN",path)==OK,"withdrawal writes released inventory to disk")
	check(stock(campaign.data.roster[0])==spent,"outcome snapshot contains the actual spent holder")
	unit.members[0].throwables={}
	check(stock(campaign.data.roster[0])==spent,"saved roster does not alias later live inventory changes")
	var loaded=Campaign.new()
	check(loaded.load_state(path)==OK,"v3 outcome reloads from disk")
	var next=field();loaded.prepare(next)
	var restored:=unit_of(next,"rifle")
	check(not restored.is_empty() and next.living(0).size()==1,"saved section replaces the new operation's starting force")
	if restored.is_empty():return
	check(stock(restored)==spent and next.Throwables.total(restored,"smoke")==2,"redeployment preserves per-member spent inventory without a refill")
	check(next.throwables.preparations.is_empty() and next.throwables.projectiles.is_empty() and next.throwables.smoke.is_empty(),"throw preparation, projectiles and smoke remain transient across operations")
	check(restored.members.all(func(member):return int(member.get("task_action",0))==0) and next.FieldPositions.jobs(next).is_empty(),"restored soldiers have no stale actor/work claims")
	check(loaded.begin(next,path)==OK,"next deployment checkpoints its reduced stock")
	restored.members[0].throwables={}
	restored.members[1].throwables={"frag":0}
	restored.members[2].hp=0.0;restored.members[2].wound="KIA"
	var casualty_kit:Dictionary=restored.members[2].throwables.duplicate(true)
	next.Infantry.publish(restored)
	check(loaded.record_outcome(next,"VICTORY",path)==OK,"victory saves empty stock and casualty slots")
	var empty=Campaign.new();check(empty.load_state(path)==OK,"empty-stock outcome remains a valid save")
	var destination=field();empty.prepare(destination)
	var veteran:=unit_of(destination,"rifle")
	check(not veteran.is_empty(),"surviving empty-stock section deploys")
	if veteran.is_empty():return
	check(veteran.members[0].throwables.is_empty() and stock(veteran)[str(veteran.members[1].member_id)]=={"frag":0},"explicit empty and partial zero dictionaries retain their exact key sets")
	check(veteran.members[2].wound=="KIA" and veteran.members[2].hp==0 and veteran.members[2].get("campaign_absent",false),"casualty is still absent after redeployment")
	check(int(veteran.members[2].throwables.get("frag",0))==int(casualty_kit.get("frag",0)),"explicit inaccessible casualty stock is not replaced or donated")
	check(destination.Throwables.total(veteran,"frag")==0 and destination.Throwables.total(veteran,"smoke")==0,"casualty equipment cannot refill surviving empty members")
	destination.Throwables.ensure_unit(veteran)
	check(destination.Throwables.total(veteran,"frag")==0 and veteran.members[0].throwables.is_empty(),"ordinary runtime initialization does not refill restored empty records")

func legacy(current:Dictionary,version:int)->Dictionary:
	var result:Dictionary=current.duplicate(true);result.version=version;result.retry={}
	for record in result.roster:
		if version==1:
			for key in ["assigned_hp","assigned_members","equipment"]:record.erase(key)
		for member in record.members:
			member.erase("throwables")
			if version==1:
				for key in ["member_id","magazines","readiness_weapon"]:member.erase(key)
	return result

func migration()->void:
	var sim=field();var campaign=Campaign.new()
	for i in 3:sim.spawn(["rifle","atgm","engineer"][i],0,SOURCE+Vector2(0,i*10))
	var current:Dictionary=Campaign.fresh();current.started=true;current.supply=321.0;current.roster=campaign.snapshot(sim)
	for version in [1,2]:
		var old:=legacy(current,version)
		var rifle:=record_of(old,"rifle");rifle.members[1]["throwables"]={};rifle.members[2]["throwables"]={"frag":0}
		var engineer:=record_of(old,"engineer")
		engineer.members[1].hp=0.0;engineer.members[1].wound="KIA"
		engineer.members[2].hp=0.0;engineer.members[2].wound="SEVERE";engineer.members[2].bleed_left=8.0
		var atgm:=record_of(old,"atgm");atgm.members[0].hp=0.0;atgm.members[0].wound="KIA"
		atgm.members[1]["throwables"]={"frag":0,"smoke":0}
		if version==2:atgm.equipment={}
		old.retry=legacy(current,2 if version==1 else 1);old.retry.erase("retry")
		record_of(old.retry,"rifle").members[0]["throwables"]={}
		var before:Dictionary=old.duplicate(true)
		check(Campaign.valid(old),"version %d fixture is a valid legacy save including retry"%version)
		var upgraded:Dictionary=Campaign.upgrade_state(old)
		check(old==before,"version %d migration does not mutate its input"%version)
		check(int(upgraded.version)==3 and int(upgraded.retry.version)==3 and Campaign.valid(upgraded),"version %d and mixed-version nested retry migrate into valid v3"%version)
		check(Campaign.upgrade_state(upgraded)==upgraded,"version %d migration is idempotent"%version)
		var migrated:=record_of(upgraded,"rifle")
		check(migrated.members[0].throwables=={"frag":1,"smoke":1},"missing legacy stock receives one initial carried item of each kind")
		check(migrated.members[1].throwables.is_empty() and migrated.members[2].throwables=={"frag":0},"present legacy empty/partial stock remains authoritative")
		var eng:=record_of(upgraded,"engineer")
		check(int(eng.assigned_members)==3 and float(eng.assigned_hp)==160 and eng.members[0].throwables=={"frag":1,"smoke":1},"legacy engineer migration uses field-unit definitions and compatible stock")
		check(eng.members[1].throwables=={"frag":0,"smoke":0} and eng.members[2].throwables=={"frag":0,"smoke":0},"missing casualty/downed stock cannot create new equipment")
		check(record_of(upgraded,"atgm").equipment.is_empty() and record_of(upgraded,"atgm").members[1].throwables=={"frag":0,"smoke":0},"lost launcher holder and explicitly spent grenades remain lost/spent")
		check(record_of(upgraded.retry,"rifle").members[0].throwables.is_empty(),"nested retry retains its own explicit empty stock")
		if version==2:
			check(migrated.members[0].member_id==rifle.members[0].member_id and migrated.members[0].magazines==rifle.members[0].magazines,"v2 migration retains stable identity and existing magazines")
		var path:=path_for("v%d"%version);write_state(path,old)
		var loaded=Campaign.new();check(loaded.load_state(path)==OK and int(loaded.data.version)==3,"legacy disk load performs migration")
		check(stock(record_of(loaded.data,"rifle"))==stock(migrated),"disk migration preserves exact inventory key sets and counts")
		check(loaded.save_state(path)==OK and int(loaded.read_file(path).version)==3,"next save writes migrated schema durably")
		var again=Campaign.new();check(again.load_state(path)==OK and stock(record_of(again.data,"rifle"))==stock(migrated),"repeated disk load cannot grant another default stock")
		var retry_stock:=stock(record_of(again.data.retry,"rifle"))
		check(again.retry(path)==OK and int(again.data.version)==3 and stock(record_of(again.data,"rifle"))==retry_stock,"retry restores the independently migrated checkpoint inventory")

func validation_and_recovery()->void:
	var sim=field();sim.spawn("rifle",0,SOURCE)
	var snapshot=Campaign.new();var state:Dictionary=Campaign.fresh();state.started=true;state.roster=snapshot.snapshot(sim)
	var invalid_stock:Array=[null,[],0,{"frag":true},{"frag":-1},{"frag":0.5},{"frag":2},{"frag":INF},{"frag":NAN},{"frag":"1"},{"unknown":0},{"frag":0,"smoke":0,"extra":0}]
	for version in [1,2,3]:
		for inventory in invalid_stock:
			var bad:Dictionary=legacy(state,version) if version<3 else state.duplicate(true)
			bad.roster[0].members[0]["throwables"]=inventory
			check(not Campaign.valid(bad),"v%d rejects malformed carried inventory %s"%[version,str(inventory)])
	var missing:Dictionary=state.duplicate(true);missing.roster[0].members[0].erase("throwables")
	check(not Campaign.valid(missing),"v3 missing inventory is corrupt rather than an implicit refill")
	var valid_empty:Dictionary=state.duplicate(true);valid_empty.roster[0].members[0].throwables={};valid_empty.roster[0].members[1].throwables={"smoke":0}
	var unchanged:Dictionary=valid_empty.duplicate(true)
	check(Campaign.valid(valid_empty) and valid_empty==unchanged,"v3 validation accepts explicit empty/partial stock without mutating it")
	var bad_retry:Dictionary=state.duplicate(true);bad_retry.retry=missing
	check(not Campaign.valid(bad_retry),"invalid current retry inventory invalidates the enclosing save")
	var zero_legacy:=legacy(state,2);zero_legacy.roster[0].members[0].hp=0.0
	check(Campaign.upgrade_state(zero_legacy).roster[0].members[0].throwables=={"frag":0,"smoke":0},"zero-health legacy member gets no stock even if an old wound label is healthy")
	var path:=path_for("semantic-corruption")
	var campaign=Campaign.new();campaign.data=valid_empty
	check(campaign.save_state(path)==OK,"valid depleted inventory saves")
	check(valid_empty==unchanged,"saving valid current stock does not rewrite the caller's data")
	campaign.data.supply=12.0;check(campaign.save_state(path)==OK,"second depleted save creates a valid backup")
	var corrupt:=legacy(state,2);corrupt.roster[0].members[0]["throwables"]={"frag":true};write_state(path,corrupt)
	var recovered=Campaign.new()
	check(recovered.load_state(path)==OK and recovered.recovered,"malformed legacy inventory recovers backup instead of manufacturing defaults")
	check(stock(recovered.data.roster[0])==stock(valid_empty.roster[0]),"backup recovery preserves depleted inventory")
	check(recovered.save_state(path)==OK and Campaign.valid(recovered.read_file(path+".bak")),"recovery save retains a valid stock backup")
	write_state(path,missing);write_state(path+".bak",corrupt)
	var bytes:=FileAccess.get_file_as_string(path)
	var blocked=Campaign.new()
	check(blocked.load_state(path)==ERR_FILE_CORRUPT and blocked.blocked,"invalid primary and backup stock block automatic loading")
	check(blocked.save_state(path)==ERR_FILE_CORRUPT and FileAccess.get_file_as_string(path)==bytes,"blocked save leaves damaged inventory bytes available for recovery")

func parked_and_failed_writes()->void:
	var sim=field();var unit:Dictionary=sim.spawn("rifle",0,SOURCE);unit.members[0].throwables={}
	var campaign=Campaign.new();campaign.prepare(sim)
	var path:=path_for("frozen-outcome")
	check(campaign.begin(sim,path)==OK,"partly depleted deployment creates a retry checkpoint")
	var checkpoint_stock:=stock(campaign.data.retry.roster[0])
	check(sim.issue_throw([unit.id],"frag",TARGET)==1,"a stocked remaining member prepares a real frag")
	step_throws(sim,1.2)
	check(sim.Throwables.total(unit,"frag")==1,"real frag release spends one of the two remaining carried items")
	var released:=stock(unit)
	var parent_file:=path_for("not-directory");var blocker:=FileAccess.open(parent_file,FileAccess.WRITE);blocker.store_string("file");blocker.close()
	var bad_path:=parent_file+"/campaign.json"
	check(campaign.record_outcome(sim,"DEFEAT",bad_path)!=OK,"actual outcome write failure is reported")
	for member in unit.members:member.throwables={}
	check(campaign.record_outcome(sim,"DEFEAT",path)==OK and stock(campaign.data.roster[0])==released,"retrying failed outcome writes the frozen stock snapshot without resnapshotting/refilling")
	var before:Dictionary=campaign.data.duplicate(true)
	check(campaign.retry(bad_path)!=OK and campaign.data==before and campaign.finished and campaign.begun,"failed retry preserves the completed outcome and stock")
	check(campaign.retry(path)==OK and stock(campaign.data.roster[0])==checkpoint_stock,"successful retry restores exact deployment stock including an originally empty holder")
	var parked=Campaign.new();check(parked.load_state(path)==OK,"retry checkpoint reloads")
	var unsupported=field();unsupported.scenario.available_domains=["sea"];parked.data.supply=0.0
	parked.prepare(unsupported)
	check(parked.parked.size()==1 and unsupported.living(0).is_empty(),"unsupported infantry stays parked without buying a new force")
	check(parked.begin(unsupported,path)==OK and parked.record_outcome(unsupported,"WITHDRAWN",path)==OK,"parked inventory passes through deployment and outcome")
	check(stock(parked.data.roster[0])==checkpoint_stock,"parked snapshot retains exactly the same carried inventory")
	var reloaded=Campaign.new();check(reloaded.load_state(path)==OK,"parked depleted inventory reloads")
	var available=field();available.scenario.available_domains=["land"];reloaded.prepare(available)
	var veteran:=unit_of(available,"rifle")
	check(not veteran.is_empty() and reloaded.parked.is_empty() and stock(veteran)==checkpoint_stock,"compatible redeployment restores parked stock without duplication or a refill")

func run()->void:
	release_and_transfer()
	migration()
	validation_and_recovery()
	parked_and_failed_writes()
	for path in paths:
		for suffix in ["",".bak",".tmp"]:
			if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("M1 PERSISTENCE: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
