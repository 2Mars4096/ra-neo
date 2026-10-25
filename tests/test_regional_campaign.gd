extends SceneTree
# Exercises real saves and transitions, without touching the player's save file.
const Campaign=preload("res://scripts/regional_campaign.gd")
const Catalog=preload("res://scripts/scenario_catalog.gd")
const Sim=preload("res://scripts/simulation.gd")
var checks:=0
var failures:=0
var paths:PackedStringArray=[]

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func path_for(label:String)->String:
	var path:="/tmp/ra-neo-campaign-%s-%s.json"%[OS.get_process_id(),label]
	paths.append(path)
	return path

func mission(id:String,populate:bool=false):
	return Sim.new(populate,Catalog.index_for_id(id))

func unit_of(sim,kind:String)->Dictionary:
	for unit in sim.living(0):
		if unit.kind==kind:return unit
	return {}

func roster_equal(actual:Array,expected:Array)->bool:
	if actual.size()!=expected.size():return false
	for index in actual.size():
		var a:Dictionary=actual[index]
		var b:Dictionary=expected[index]
		if a.kind!=b.kind or not is_equal_approx(float(a.hp),float(b.hp)) or a.members.size()!=b.members.size():return false
		for member in a.members.size():
			if a.members[member].wound!=b.members[member].wound or not is_equal_approx(float(a.members[member].hp),float(b.members[member].hp)):return false
	return true

func write_text(path:String,content:String)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	check(file!=null,"test save path is writable")
	if file!=null:file.store_string(content);file.close()

func casualties_and_domain_transfer()->void:
	var path:=path_for("survivors")
	var campaign=Campaign.new()
	var coastal=mission("south_inlet")
	var rifle:Dictionary=coastal.spawn("rifle",0,coastal.field_ops.insertion)
	var tank:Dictionary=coastal.spawn("tank",0,coastal.field_ops.insertion+Vector2(10,0))
	var boat:Dictionary=coastal.spawn("boat",0,coastal.field_ops.sea_insertion)
	check(not rifle.is_empty() and not tank.is_empty() and not boat.is_empty(),"mixed expedition has legal spawned bodies")
	campaign.prepare(coastal)
	check(campaign.begin(coastal,path)==OK,"first deployment saves its checkpoint")
	coastal.time=50.0
	rifle.members[0].hp=0.0;rifle.members[0].wound="KIA"
	rifle.members[1].hp=float(rifle.members[1].max_hp)*0.5;rifle.members[1].wound="LIGHT"
	rifle.members[2].hp=0.0;rifle.members[2].wound="SEVERE"
	rifle.members[2].bleed_at=65.0;rifle.members[2].stable=false
	coastal.Infantry.publish(rifle)
	var surviving_hp:float=rifle.hp
	coastal.VehicleDamage.ensure_state(coastal,tank)
	tank.hp=float(tank.max_hp)*0.6;tank.mobility_kill=true;tank.crew=1
	tank["optics_kill"]=true;tank["accuracy"]=coastal.VehicleDamage.OPTICS_ACCURACY
	coastal.VehicleDamage.ensure_state(coastal,boat)
	boat.hp=float(boat.max_hp)*0.8;boat["flood"]=0.2;boat["flood_rate"]=0.04;boat["fire_until"]=62.0
	coastal.credits=740.25
	check(campaign.record_outcome(coastal,"WITHDRAWN",path)==OK,"withdrawal saves damaged survivors")
	check(campaign.data.roster.size()==3,"one record per surviving section or vehicle")
	var loaded=Campaign.new()
	check(loaded.load_state(path)==OK and not loaded.recovered,"real save reloads without recovery")
	check(is_equal_approx(float(loaded.data.supply),740.25),"fractional remaining supply survives JSON round trip")
	var inland=mission("limestone_pass",true)
	loaded.prepare(inland)
	check(inland.living(0).size()==2,"saved expedition replaces the entire authored starter force")
	check(loaded.parked.size()==1 and loaded.parked[0].kind=="boat","unsupported naval survivor remains in regional reserve")
	var veteran:Dictionary=unit_of(inland,"rifle")
	var armor:Dictionary=unit_of(inland,"tank")
	check(not veteran.is_empty() and not armor.is_empty(),"supported veterans deploy on the inland battlefield")
	if veteran.is_empty() or armor.is_empty():return
	check(is_equal_approx(float(veteran.hp),surviving_hp),"section HP does not heal during transfer")
	check(veteran.members[0].wound=="KIA" and veteran.members[0].hp==0.0,"lost soldier is not resurrected")
	check(veteran.members[0].get("campaign_absent",false),"lost soldier is marked absent from the new battlefield")
	check(veteran.members[1].wound=="LIGHT" and is_equal_approx(float(veteran.members[1].hp),float(veteran.members[1].max_hp)*0.5),"light wound survives transfer")
	check(veteran.members[2].wound=="SEVERE" and is_equal_approx(float(veteran.members[2].bleed_at),15.0),"severe wound retains its remaining treatment time")
	check(is_equal_approx(float(armor.hp),float(armor.max_hp)*0.6) and armor.mobility_kill and armor.crew==1,"vehicle integrity, mobility damage and crew casualties persist")
	check(armor.get("optics_kill",false) and armor.get("accuracy",1.0)==coastal.VehicleDamage.OPTICS_ACCURACY,"actual optics damage and accuracy penalty persist")
	check(inland.VehicleDamage.weapon_ready(inland,armor),"restored crew state supports the real weapon readiness path")
	check(loaded.begin(inland,path)==OK and loaded.record_outcome(inland,"WITHDRAWN",path)==OK,"inland withdrawal retains both deployed and parked survivors")
	check(loaded.data.roster.size()==3,"parking and withdrawal never duplicate or discard the ship")
	var next_coast=mission("south_inlet",true)
	loaded.prepare(next_coast)
	check(next_coast.living(0).size()==3 and loaded.parked.is_empty(),"return to coast deploys the saved ship without adding starter forces")
	var ship:Dictionary=unit_of(next_coast,"boat")
	check(not ship.is_empty(),"parked ship has a real naval body on return")
	if ship.is_empty():return
	check(next_coast.terrain.traversable(ship.pos,"sea",float(next_coast.definitions.boat.radius)),"returning ship fits the destination sea insertion")
	check(is_equal_approx(float(ship.get("fire_until",-1.0)),12.0),"remaining fire duration is restored relative to the new battle clock")
	check(next_coast.has_meta(next_coast.VehicleDamage.HAZARDS),"restored ship is registered for physical hazard updates")
	var previous_hp:float=ship.hp
	next_coast.VehicleDamage.tick_hazards(next_coast,0.1)
	check(float(ship.flood)>0.2,"restored flooding continues instead of freezing")
	check(float(ship.hp)<previous_hp,"restored fire continues damaging the vessel")

func refunds_ownership_and_retry()->void:
	var path:=path_for("outcome")
	var campaign=Campaign.new()
	var sim=mission("bayhead_rail_valley")
	sim.spawn("rifle",0,sim.field_ops.insertion)
	campaign.prepare(sim)
	check(campaign.begin(sim,path)==OK,"deployment writes a retry checkpoint")
	var checkpoint:Dictionary=campaign.data.retry.duplicate(true)
	sim.credits=217.25
	sim.field_ops["queue"]=["rifle","tank"]
	var expected:float=sim.credits+float(sim.definitions.rifle.cost)+float(sim.definitions.tank.cost)
	check(campaign.record_outcome(sim,"VICTORY",path)==OK,"victory persists the completed operation")
	check(campaign.secured("bayhead_rail_valley") and campaign.modifiers().income==2.0,"victory grants the rail supply consequence")
	check(is_equal_approx(float(campaign.data.supply),expected),"only unarrived paid reinforcements are refunded")
	campaign.record_outcome(sim,"VICTORY",path)
	check(is_equal_approx(float(campaign.data.supply),expected),"repeated outcome callback cannot refund the queue twice")
	var repeat=mission("bayhead_rail_valley")
	campaign.prepare(repeat)
	check(repeat.field_ops.income_rate==float(repeat.scenario.field_income)+2.0,"secured regional logistics affects the next actual economy")
	campaign.begin(repeat,path)
	campaign.record_outcome(repeat,"VICTORY",path)
	check(campaign.modifiers().income==2.0 and campaign.data.secured.size()==1,"replaying a victory does not stack the same facility benefit")
	# Rebuild the original deployment checkpoint explicitly to exercise a retry
	# after defeat; normal UI offers this choice rather than a free replacement army.
	campaign.data.retry=checkpoint
	campaign.data.supply=0.0;campaign.data.roster=[];campaign.data.secured={}
	check(campaign.retry(path)==OK,"explicit retry restores the deployment checkpoint")
	check(campaign.data.roster==checkpoint.roster and campaign.data.supply==checkpoint.supply,"retry restores the exact prior roster and budget")
	check(campaign.data.secured==checkpoint.secured and campaign.data.retry.is_empty(),"retry restores strategic state and clears the consumed checkpoint")
	var loaded=Campaign.new()
	check(loaded.load_state(path)==OK and roster_equal(loaded.data.roster,campaign.data.roster),"retried checkpoint is durable on disk")
	var withdrawn=mission("bayhead_rail_valley")
	loaded.prepare(withdrawn);loaded.begin(withdrawn,path)
	loaded.data.secured={"black_sea_harbor":true,"bayhead_rail_valley":true}
	loaded.record_outcome(withdrawn,"WITHDRAWN",path)
	check(not loaded.secured("bayhead_rail_valley") and loaded.secured("black_sea_harbor"),"withdrawal releases only the abandoned battlefield")
	check(loaded.data.history.bayhead_rail_valley=="WITHDRAWN","withdrawal result remains visible in regional history")

func recovery_and_invalid_data()->void:
	var path:=path_for("recovery")
	var saved=Campaign.new()
	check(saved.save_state(path)==OK,"initial save is written atomically")
	saved.data.supply=55.0
	check(saved.save_state(path)==OK,"second save keeps a previous backup")
	write_text(path,"{broken")
	var recovered=Campaign.new()
	check(recovered.load_state(path)==OK and recovered.recovered,"corrupt primary recovers the last complete backup")
	check(recovered.data.supply==0.0,"recovery uses backup data, not malformed primary content")
	recovered.data.supply=23.0
	check(recovered.save_state(path)==OK,"recovered campaign can continue saving")
	check(Campaign.valid(recovered.read_file(path+".bak")),"saving recovered data preserves a valid fallback backup")
	write_text(path,"{also broken")
	var second=Campaign.new()
	check(second.load_state(path)==OK,"backup remains recoverable after a recovery save")
	write_text(path+".bak","{broken backup")
	var blocked=Campaign.new()
	check(blocked.load_state(path)==ERR_FILE_CORRUPT and blocked.blocked,"two corrupt copies block automatic overwrite")
	check(blocked.save_state(path)==ERR_FILE_CORRUPT,"blocked save cannot silently erase damaged files")
	check(FileAccess.get_file_as_string(path)=="{also broken","blocked write leaves original bytes available for recovery")
	check(blocked.reset(path)==OK and not blocked.blocked,"explicit new-campaign reset can replace corrupt state")
	var blank=Campaign.new()
	check(blank.load_state(path)==OK and not blank.data.started,"reset persists a clean unstarted campaign")
	var invalid:Dictionary=Campaign.fresh()
	invalid.roster=[{"kind":"tank","hp":100.0,"members":[],"damage":{"crew":true}}]
	check(not Campaign.valid(invalid),"boolean crew counts are rejected rather than becoming a one-person crew")
	invalid.roster=[{"kind":"rifle","hp":50.0,"members":[],"damage":{}}]
	check(not Campaign.valid(invalid),"missing infantry records cannot recreate a full healed squad")
	invalid.roster=[{"kind":"boat","hp":100.0,"members":[],"damage":{"flood":-0.1}}]
	check(not Campaign.valid(invalid),"negative damage values are rejected")

func failed_writes()->void:
	var parent_file:=path_for("not-directory")
	write_text(parent_file,"a file cannot contain a child save")
	var bad_path:=parent_file+"/save.json"
	var good_path:=path_for("save-retry")
	var campaign=Campaign.new()
	var sim=mission("bayhead_rail_valley")
	sim.spawn("rifle",0,sim.field_ops.insertion)
	campaign.prepare(sim)
	check(campaign.begin(sim,bad_path)!=OK,"deployment reports a real save failure")
	check(campaign.begin(sim,good_path)==OK and FileAccess.file_exists(good_path),"deployment retries its failed checkpoint write")
	sim.credits=90.5;sim.field_ops["queue"]=["rifle"]
	var expected:float=sim.credits+float(sim.definitions.rifle.cost)
	check(campaign.record_outcome(sim,"WITHDRAWN",bad_path)!=OK,"outcome reports a real save failure")
	check(campaign.finished and is_equal_approx(float(campaign.data.supply),expected),"failed outcome retains one finalized refund in memory")
	# A repeated callback must retry the frozen result, not snapshot changed
	# battle data or refund a queue that has already been accounted for.
	sim.credits=99999.0;sim.field_ops.queue.append("tank")
	check(campaign.record_outcome(sim,"WITHDRAWN",good_path)==OK,"outcome callback retries the failed disk write")
	var saved=Campaign.new()
	check(saved.load_state(good_path)==OK and is_equal_approx(float(saved.data.supply),expected),"retry saves the original outcome without duplicate refunds")
	var previous:Dictionary=campaign.data.duplicate(true)
	campaign.blocked=true;campaign.begun=true
	check(campaign.reset(bad_path)!=OK,"new campaign reports a failed reset write")
	check(campaign.data==previous and campaign.blocked and campaign.begun and campaign.finished,"failed reset preserves the existing campaign and lifecycle flags")

func _init()->void:
	call_deferred("run")

func run()->void:
	casualties_and_domain_transfer()
	refunds_ownership_and_retry()
	recovery_and_invalid_data()
	failed_writes()
	for path in paths:
		for suffix in ["",".bak",".tmp"]:
			if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("REGIONAL CAMPAIGN: %d checks, %d failures"%[checks,failures])
	quit(1 if failures>0 else 0)
