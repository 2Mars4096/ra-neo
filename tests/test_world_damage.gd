extends SceneTree
# World damage beyond soldiers and hulls (scripts/structure_damage.gd):
# buildings (integrity, states, garrison casualties, collapse to rubble and
# navigation), field works (small-arms proof, sandbag wear, depot cook-off,
# wire cutting), corvette fire/flooding, gunship crashes, fragile drones,
# street furniture flattened by HE, and the collapse visuals.
const Sim=preload("res://scripts/simulation.gd")
const SD=preload("res://scripts/structure_damage.gd")
const VehicleDamage=preload("res://scripts/vehicle_damage.gd")
const Garrison=preload("res://scripts/garrison.gd")
const Ruin=preload("res://scripts/ruined_building.gd")
const Art=preload("res://scripts/visuals.gd")
const Body=preload("res://scripts/city_building_geometry.gd")
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func fixture(ok:bool,label:String)->bool:
	check(ok,label)
	if not ok:
		printerr("WORLD DAMAGE: fixture unavailable; stopping before dependent checks")
		print("WORLD DAMAGE: %d checks, %d failures" % [checks,failures])
		quit(1)
	return ok

func harbor_index()->int:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		if configs[i].id=="black_sea_harbor":return i
	return -1

const BASE:=Vector2(300,640)

# A firing position `distance` m off the building, on open land with a clear line.
func firing_spot(sim,building:Dictionary,distance:float)->Vector2:
	var center:Vector2=building.bounds.get_center()
	var half:float=maxf(building.bounds.size.x,building.bounds.size.y)*0.5
	for ring in [distance,distance*0.8,distance*1.2]:
		for i in 24:
			var p:Vector2=center+Vector2.from_angle(i*TAU/24.0)*(half+ring)
			if not sim.terrain.traversable(p,"land",2.9) or sim.terrain.is_water(p):continue
			var aim:Vector2=SD.wall_point(building,p)
			if p.distance_to(aim)>18.0:continue
			if sim.terrain.line_clear(p,aim+(p-aim).normalized()*0.3):return p
	return Vector2(-1,-1)

func pick_building(sim,design:String,min_integrity:float,max_integrity:float)->Dictionary:
	for building in Garrison.index(sim).buildings:
		if building.design!=design:continue
		# A rectangular, axis-aligned physical body can own several colliders:
		# porch/dock pieces and rotated-body strips are not separate buildings.
		var spec:Dictionary=building.spec
		if absf(fposmod(float(spec.rotation_degrees)+45.0,90.0)-45.0)>0.001 or int(spec.damage)!=0:continue
		var walls:Array=Body.ground_pieces(spec).filter(func(piece):return piece.wall)
		if walls.size()!=1:continue
		var value:=SD.integrity(building)
		if value<min_integrity or value>max_integrity:continue
		if firing_spot(sim,building,10.0).x<0:continue
		if Garrison.entry_point(sim,building.id,building.bounds.get_center()+Vector2(0,40)).x<0:continue
		return building
	return {}

func garrison(sim,building:Dictionary,team:int)->Dictionary:
	var door:Vector2=Garrison.entry_point(sim,building.id,building.bounds.get_center()+Vector2(0,40))
	var u:Dictionary=sim.spawn("rifle",team,door)
	u["garrison_door"]=door
	Garrison.enter(sim,u,building.id)
	return u

func open_ground(sim,near:Vector2,radius:float=4.0)->Vector2:
	for ring in range(0,30):
		for i in 16:
			var p:Vector2=near+Vector2.from_angle(i*TAU/16.0)*ring*2.0
			if sim.terrain.traversable(p,"land",radius) and not sim.terrain.is_water(p):return p
	return Vector2(-1,-1)

func count(events:Array,type:String,key:String="",value="")->int:
	var n:=0
	for e in events:
		if e.type==type and (key=="" or e.get(key)==value):n+=1
	return n

func _init()->void:
	# Deferred so the battle scene in section 12b enters a running tree (_ready).
	call_deferred("run")

func run()->void:
	var harbor:=harbor_index()
	if not fixture(harbor>=0,"Harbor scenario exists"):return
	# --- 0. Shots to collapse per building size ---------------------------------
	var sim=Sim.new(false,harbor)
	print("SHOTS TO COLLAPSE (integrity = (%.0f + area x floors x %.2f) x construction)" % [SD.BASE,SD.PER_AREA])
	print("  %-15s %7s %6s %9s | %5s %6s %5s %5s %5s" % ["design","area","floors","integrity","tank","at_gun","atgm","helo","boat"])
	var shown:Dictionary={}
	var samples:Array=Garrison.index(sim).buildings.duplicate()
	samples.sort_custom(func(a,b):return SD.integrity(a)<SD.integrity(b))
	for building in samples:
		var key:String="%s/%d" % [building.design,int(building.floors)]
		if shown.has(key):continue
		shown[key]=true
		var value:=SD.integrity(building)
		var row:="  %-15s %7.0f %6d %9.0f |" % [building.design,building.area,building.floors,value]
		for weapon in ["tank","at_gun","atgm","helo","boat"]:row+=" %5d" % ceili(value/float(SD.HE[weapon].structure))
		print(row)
	var timber:Dictionary=pick_building(sim,"dacha_hut",0,1000)
	var stone:Dictionary=pick_building(sim,"stone_house",0,1000)
	if not fixture(not timber.is_empty() and not stone.is_empty(),"found timber and stone comparison buildings"):return
	check(SD.integrity(timber)<SD.integrity(stone),"timber hut weaker than a stone house")

	# --- 1. Small arms never damage buildings or hard works ------------------------
	var house:Dictionary=pick_building(sim,"stone_house",30.0,80.0)
	if not fixture(not house.is_empty(),"found a small stone house with a firing position"):return
	var defenders:Dictionary=garrison(sim,house,1)
	var rifle_spot:Vector2=firing_spot(sim,house,8.0)
	var rifle:={"kind":"rifle","pos":rifle_spot,"team":0,"suppression":0.0,"state":"READY","members":[],"visible":true}
	var leaked:=0.0
	for i in 200:leaked+=SD.strike(sim,rifle,defenders,1.0)
	check(float(house.damage)==0.0 and int(house.state)==SD.INTACT,"200 rifle hits leave the building intact (damage %.1f)" % house.damage)
	check(is_equal_approx(leaked,200.0),"intact building keeps full protection against small arms")
	var bunker:Dictionary=sim.spawn("bunker",1,open_ground(sim,BASE,4.0))
	var shooter:Dictionary=sim.spawn("rifle",0,bunker.pos+Vector2(10,0))
	var proxy:Dictionary=shooter.duplicate();proxy.kind="rifle";proxy.pos=shooter.pos
	var bunker_hp:float=bunker.hp
	var rifle_hits:=0
	for i in 150:if sim.resolve_shot(proxy,bunker,0.25):rifle_hits+=1
	check(rifle_hits>50 and bunker.hp==bunker_hp,"%d rifle hits do nothing to a bunker" % rifle_hits)
	var cooldown_before:float=bunker.cooldown
	SD.strike(sim,proxy,bunker,1.0)
	check(bunker.cooldown>cooldown_before,"rifle fire into the embrasure slows the bunker's gunners")
	var tank_shooter:Dictionary=sim.spawn("tank",0,bunker.pos+Vector2(-14,0))
	for i in 3:sim.resolve_shot(tank_shooter,bunker,1.0)
	check(bunker.hp<bunker_hp,"tank HE damages the bunker (%.0f -> %.0f)" % [bunker_hp,bunker.hp])

	# --- 2. Tank HE collapses a small building: measured shots, states, garrison --------
	var s2=Sim.new(false,harbor)
	var target:Dictionary=pick_building(s2,"stone_house",30.0,80.0)
	if not fixture(not target.is_empty(),"found a small stone house for the HE collapse check"):return
	var spot:Vector2=firing_spot(s2,target,10.0)
	var holders:Dictionary=garrison(s2,target,1)
	var tank:Dictionary=s2.spawn("tank",0,spot)
	tank.pos=spot
	check(SD.bombard(s2,[tank.id],target.id)==1,"tank accepts a fire mission on the building")
	var shots:=0;var states:Array=[];var collapse_event:Dictionary={}
	var center:Vector2=target.bounds.get_center()
	var nav_radius:=1.0
	var grids:={}
	for profile in ["infantry","tracked","wheeled"]:grids[profile]=s2.terrain.nav_grid("land",nav_radius,profile)
	var centre_cell:Vector2i=s2.terrain.nav_cell(center)
	var solid_before:={}
	for profile in grids:solid_before[profile]=grids[profile].is_point_solid(centre_cell)
	var traversable_before:bool=s2.terrain.traversable(center,"land",nav_radius)
	# 1.5 m beyond the point of aim, inside the house (garden fences stay up).
	var inside_wall:Vector2=SD.wall_point(target,spot)+(SD.wall_point(target,spot)-spot).normalized()*1.5
	var los_before:bool=s2.terrain.line_clear(spot,inside_wall)
	var holder_hp:float=holders.hp
	var started:=Time.get_ticks_usec()
	for i in 30*120:
		s2.tick(1.0/30)
		for e in s2.events:
			if e.type=="shot" and e.from==tank.pos and e.kind=="tank":shots+=1
			if e.type=="building_damage" and e.building==target.id and (states.is_empty() or states.back()!=e.state):states.append(e.state)
			if e.type=="building_collapse" and e.building==target.id:collapse_event=e
		s2.events.clear()
		if not collapse_event.is_empty():break
	var expected:=ceili(SD.integrity(target)/float(SD.HE.tank.structure))
	print("TANK vs %s (%.0f m2, %d floor, integrity %.0f): %d shots to collapse (expected %d), states %s, %.1f s" % [target.design,target.area,target.floors,SD.integrity(target),shots,expected,str(states),s2.time])
	check(not collapse_event.is_empty(),"tank HE collapses the small building")
	check(shots==expected,"collapse after exactly integrity/10 = %d HE rounds (%d)" % [expected,shots])
	check(states==[SD.INTACT,SD.DAMAGED,SD.BREACHED,SD.COLLAPSED] or states==[SD.DAMAGED,SD.BREACHED,SD.COLLAPSED],"states progress damaged -> breached -> collapsed %s" % str(states))
	check(not holders.has("garrison") or int(holders.garrison)<0,"the garrison is out of the building")
	check(not s2.alive(holders) or holders.hp<holder_hp,"collapse kills or wounds the garrison (%.0f -> %.0f, killed %d, survivors %d)" % [holder_hp,holders.hp,collapse_event.get("killed",-1),collapse_event.get("survivors",-1)])
	check(Garrison.building_at(s2,center)==-1 and Garrison.order(s2,[],target.id)==0,"collapsed building can no longer be garrisoned")
	check(not tank.has("bombard"),"fire mission ends with the collapse")
	# --- 3. Rubble and navigation -----------------------------------------------------
	print("RUBBLE at %s: traversable before %s after %s; solid before %s after infantry %s tracked %s wheeled %s" % [str(center),str(traversable_before),str(s2.terrain.traversable(center,"land",nav_radius)),str(solid_before),str(grids.infantry.is_point_solid(centre_cell)),str(grids.tracked.is_point_solid(centre_cell)),str(grids.wheeled.is_point_solid(centre_cell))])
	check(not traversable_before and s2.terrain.traversable(center,"land",nav_radius),"collision footprint removed")
	check(solid_before.infantry and not grids.infantry.is_point_solid(centre_cell),"infantry navigation opens through the rubble (local refresh)")
	check(not grids.tracked.is_point_solid(centre_cell),"tracked vehicles may plan through rubble")
	check(grids.wheeled.is_point_solid(centre_cell),"wheeled vehicles are blocked by rubble")
	var open:Vector2=spot
	var inf_speed:float=s2.terrain.ground_speed(center,"infantry")/s2.terrain.ground_speed(open,"infantry")
	var trk_speed:float=s2.terrain.ground_speed(center,"tracked")/maxf(0.01,s2.terrain.ground_speed(open,"tracked"))
	print("RUBBLE speed vs open: infantry %.2f tracked %.2f wheeled %.2f; surface '%s'" % [inf_speed,trk_speed,s2.terrain.ground_speed(center,"wheeled"),s2.terrain.surface_name(center)])
	check(inf_speed<0.8 and trk_speed<0.5 and trk_speed>0.1,"rubble slows infantry a little and tracks a lot")
	check(s2.terrain.cover(center),"rubble gives infantry cover")
	# Approaches from all round the footprint (a garden fence may close one side).
	var approaches:=0
	for i in 12:
		var from:Vector2=center+Vector2.from_angle(i*TAU/12.0)*12.0
		if s2.terrain.traversable(from,"land",nav_radius) and not s2.terrain.path(from,center,"land",nav_radius,[],"infantry").is_empty():approaches+=1
	print("RUBBLE infantry approaches with a route to the centre: %d of 12" % approaches)
	check(approaches>=6,"infantry can path into the rubble (%d of 12 approaches)" % approaches)
	var los_after:bool=s2.terrain.line_clear(spot,inside_wall)
	print("RUBBLE line of sight firing spot -> 1.5 m inside the struck wall: before %s after %s" % [str(los_before),str(los_after)])
	check(not los_before and los_after,"line of sight passes over the low rubble (blocked by the walls before)")

	# --- 4. Breach fragments and collapse casualties in a big building -------------------
	var s4=Sim.new(false,harbor)
	var block:Dictionary={}
	for building in Garrison.index(s4).buildings:
		if SD.integrity(building)>=400.0 and Garrison.entry_point(s4,building.id,building.bounds.get_center()+Vector2(0,40)).x>=0:block=building;break
	if not fixture(not block.is_empty(),"found a large building"):return
	var occupants:Dictionary=garrison(s4,block,0)
	var integrity:=SD.integrity(block)
	SD.damage_building(s4,block.id,integrity*0.36,block.bounds.get_center()+Vector2(0,30))
	check(int(block.state)==SD.DAMAGED,"36% -> DAMAGED")
	var probe:={"kind":"rifle","pos":block.bounds.get_center()+Vector2(0,30),"team":1}
	var damaged_leak:float=SD.strike(s4,probe,occupants,1.0)
	SD.damage_building(s4,block.id,integrity*0.35,block.bounds.get_center()+Vector2(0,30))
	check(int(block.state)==SD.BREACHED,"71% -> BREACHED")
	var breached_leak:float=SD.strike(s4,probe,occupants,1.0)
	print("GARRISON protection leak vs small arms: intact 1.00, damaged %.2f, breached %.2f" % [damaged_leak,breached_leak])
	check(damaged_leak>1.0 and breached_leak>damaged_leak,"protection falls as the building is wrecked")
	var before_fragments:float=occupants.hp
	for i in 10:SD.damage_building(s4,block.id,10.0,block.bounds.get_center()+Vector2(0,30))
	print("BREACH fragments: garrison hp %.0f -> %.0f after 10 HE hits" % [before_fragments,occupants.hp])
	check(occupants.hp<before_fragments,"HE through a breached building wounds the garrison")
	check(int(occupants.garrison)==block.id,"still garrisoned before collapse")
	s4.events.clear()
	# Grids battle.gd prebuilds plus a vehicle grid: the collapse refreshes them locally.
	s4.terrain.nav_grid("land",0.8,"infantry")
	s4.terrain.nav_grid("land",float(s4.definitions.tank.radius),"tracked")
	s4.terrain.nav_grid("land",float(s4.definitions.aa.radius),"wheeled")
	var collapse_started:=Time.get_ticks_usec()
	SD.damage_building(s4,block.id,integrity,block.bounds.get_center()+Vector2(0,30))
	var collapse_sim_ms:=(Time.get_ticks_usec()-collapse_started)/1000.0
	var buried:Dictionary={}
	for e in s4.events:if e.type=="building_collapse":buried=e
	print("COLLAPSE of %s (%d floors, %.0f x %.0f m): killed %d survivors %d; sim cost %.1f ms (nav refresh, rubble zone)" % [block.design,block.floors,block.bounds.size.x,block.bounds.size.y,buried.get("killed",-1),buried.get("survivors",-1),collapse_sim_ms])
	check(collapse_sim_ms<40.0,"collapse of a large building is a local update (%.1f ms)" % collapse_sim_ms)
	check(int(occupants.get("garrison",-1))==-1 and occupants.state=="READY","survivors are thrown clear (not garrisoned)")
	check(int(buried.get("killed",0))+int(buried.get("survivors",0))>0,"every occupant is either killed or ejected")
	check(count(s4.events,"warning")>0,"player warned about the collapse")

	# --- 5. Sandbag cover degrades under HE -------------------------------------------------
	var s5=Sim.new(false,harbor)
	var bag_pos:Vector2=open_ground(s5,BASE+Vector2(40,0),4.0)
	var bags:Dictionary=s5.spawn("tactical_cover",0,bag_pos)
	bags.build_left=0.0
	s5.FieldOps.sync_obstacles(s5)
	var behind:Vector2=bag_pos+Vector2(0,1.4)
	check(s5.terrain.cover(behind),"sandbags give cover")
	var squad:Dictionary=s5.spawn("rifle",0,behind+Vector2(0,1.5))
	for m in squad.members:m.pos=behind+Vector2(m.index-1,0.2)
	var gunner:Dictionary=s5.spawn("tank",1,bag_pos+Vector2(0,-16))
	var rifle_enemy:={"kind":"rifle","pos":bag_pos+Vector2(0,-12),"team":1}
	var bag_hp:float=bags.hp
	for i in 50:SD.strike(s5,rifle_enemy,bags,5.0)
	check(bags.hp==bag_hp,"rifle fire does not wear sandbags down")
	var wear:Array=[snappedf(SD.sandbag_protection(bags),0.01)]
	var leak_series:Array=[snappedf(SD.sandbag_leak(s5,gunner,squad),0.01)]
	var hits:=0
	while s5.alive(bags) and hits<20:
		s5.resolve_shot(gunner,bags,1.0)
		hits+=1
		wear.append(snappedf(SD.sandbag_protection(bags) if s5.alive(bags) else 1.0,0.01))
		leak_series.append(snappedf(SD.sandbag_leak(s5,gunner,squad),0.01))
	s5.FieldOps.sync_obstacles(s5)
	print("SANDBAGS under tank HE: protection factor %s, leak to soldiers %s, gone after %d hits" % [str(wear),str(leak_series),hits])
	check(wear[1]>wear[0] and wear[wear.size()-2]>wear[1],"protection drops as the bags are hit")
	check(not s5.alive(bags) and not s5.terrain.cover(behind),"destroyed sandbags give no cover")

	# --- 6. Ammunition depot cook-off ----------------------------------------------------------
	var s6=Sim.new(false,harbor)
	var depot_pos:Vector2=open_ground(s6,BASE+Vector2(-60,0),6.0)
	var depot:Dictionary=s6.spawn("ammo_depot",1,depot_pos)
	var crew:Dictionary=s6.spawn("rifle",1,depot_pos+Vector2(0,6.5))
	# spawn() spreads sections out; stand the crew 4-6 m from the stacks.
	crew.pos=depot_pos+Vector2(0,5.0)
	for m in crew.members:m.pos=crew.pos+Vector2(m.index-1,0.0)
	var post:Dictionary=s6.spawn("command_post",1,depot_pos+Vector2(-8,0))
	var attacker:Dictionary=s6.spawn("tank",0,depot_pos+Vector2(18,0))
	var crew_hp:float=crew.hp;var post_hp:float=post.hp
	var shells:=0
	while not depot.get("cooking",false) and shells<30 and s6.alive(depot):
		s6.resolve_shot(attacker,depot,1.0);shells+=1
	var blasts:=0
	for i in 30*10:
		s6.tick(1.0/30)
		blasts+=count(s6.events,"world_blast","kind","cook_off")
		s6.events.clear()
	print("DEPOT cook-off after %d HE rounds: %d secondary blasts; crew %.0f -> %.0f, command post %.0f -> %.0f" % [shells,blasts,crew_hp,crew.hp,post_hp,post.hp])
	check(depot.get("cooking",false) and not s6.alive(depot),"HE sets the depot cooking off and destroys it")
	check(blasts>=3,"a string of secondary explosions (%d)" % blasts)
	check(crew.hp<crew_hp and post.hp<post_hp,"secondary explosions damage troops and works around the depot")
	check(attacker.hp==attacker.max_hp,"the tank 18 m away is untouched")

	# --- 7. Concertina wire cut by HE nearby ---------------------------------------------------
	var wire:Dictionary=s6.spawn("concertina_wire",1,open_ground(s6,BASE+Vector2(80,0),3.0))
	wire.build_left=0.0
	s6.events.append({"type":"shot","from":wire.pos+Vector2(20,0),"to":wire.pos+Vector2(0,1.6),"kind":"rifle","target_kind":"rifle","hit":false,"visible":true})
	SD.tick(s6,1.0/30)
	check(s6.alive(wire),"rifle rounds do not cut wire")
	s6.events.append({"type":"shot","from":wire.pos+Vector2(20,0),"to":wire.pos+Vector2(0,1.6),"kind":"tank","target_kind":"rifle","hit":false,"visible":true})
	SD.tick(s6,1.0/30)
	check(not s6.alive(wire),"an HE burst beside the wire cuts it")

	# --- 8. Corvette fire, flooding and sinking --------------------------------------------------
	var s8=Sim.new(false,harbor)
	var sea:Vector2=s8.field_ops.sea_insertion
	# A player unit ashore keeps the battle from ending in defeat.
	s8.spawn("rifle",0,open_ground(s8,BASE,2.0))
	var boat:Dictionary=s8.spawn("boat",1,sea)
	check(not boat.is_empty(),"corvette spawned at sea")
	var gun:={"kind":"tank","pos":boat.pos+Vector2(-15,0),"team":0}
	var tally:Dictionary={}
	for i in 3000:
		for key in ["crew","crew_full","mobility_kill","firepower_kill","abandoned","flood","flood_rate","fire_until","altitude"]:boat.erase(key)
		boat.hp=boat.max_hp
		s8.events.clear()
		VehicleDamage.strike(s8,gun,boat,s8.damage_amount(gun,boat))
		for e in s8.events:if e.type=="vehicle_damage" and e.effect not in ["destroyed","wreck"]:tally[e.effect]=tally.get(e.effect,0)+1
	s8.remove_meta(VehicleDamage.HAZARDS)
	print("OUTCOMES tank HE vs corvette (n=3000): %s" % str(tally))
	check(tally.get("fire",0)>200 and tally.get("flooding",0)>200,"hits start fires and holes below the waterline")
	for key in ["crew","crew_full","mobility_kill","firepower_kill","abandoned","flood","flood_rate","fire_until","altitude"]:boat.erase(key)
	boat.hp=boat.max_hp
	VehicleDamage.ensure_state(s8,boat)
	# One hole with a full crew on the pumps is held; two holes sink her.
	boat["flood"]=0.0;boat["flood_rate"]=0.035
	VehicleDamage._hazard(s8,boat)
	for i in 30*40:s8.tick(1.0/30)
	var held:float=float(boat.flood)
	print("FLOODING one hole (0.035/s), 3 crew pumping: flood level %.2f after 40 s, alive %s, draft %.2f m" % [held,str(s8.alive(boat)),-float(boat.get("altitude",0.0))])
	check(s8.alive(boat) and held<1.0 and float(boat.flood_rate)==0.0,"damage control holds a single hole")
	check(float(boat.get("altitude",0.0))<0.0,"a flooded hull settles lower")
	boat["flood_rate"]=0.09
	boat.crew=1
	VehicleDamage._hazard(s8,boat)
	var sunk_at:=-1.0
	var start:float=s8.time
	for i in 30*60:
		s8.tick(1.0/30)
		if not s8.alive(boat):sunk_at=s8.time-start;break
	var sunk_warning:=false
	for e in s8.events:if e.type=="warning" and "sank" in str(e.text):sunk_warning=true
	print("FLOODING two holes, crew of 1: sank after %.1f s" % sunk_at)
	check(sunk_at>3.0 and sunk_at<40.0,"a badly holed corvette sinks over time, not instantly")
	check(count(s8.events,"vehicle_damage","effect","sunk")==1,"sinking reported")
	var burner:Dictionary=s8.spawn("boat",1,sea+Vector2(0,30))
	VehicleDamage.ensure_state(s8,burner)
	burner["fire_until"]=s8.time+12.0
	VehicleDamage._hazard(s8,burner)
	var burn_hp:float=burner.hp
	for i in 30*14:s8.tick(1.0/30)
	print("FIRE 12 s: corvette %.0f -> %.0f hp, burning %s" % [burn_hp,burner.hp,str(burner.has("fire_until"))])
	check(burner.hp<burn_hp-30.0 and not burner.has("fire_until"),"a fire burns integrity until put out")

	# --- 9. Gunship tail rotor: crash with impact damage; hydraulics: forced landing ------------
	var s9=Sim.new(false,harbor)
	var land:Vector2=open_ground(s9,BASE,4.0)
	var helo:Dictionary=s9.spawn("helo",1,land)
	var below:Dictionary=s9.spawn("rifle",0,land+Vector2(1.5,0))
	var aa:={"kind":"aa","pos":land+Vector2(15,0),"team":0}
	var helo_tally:Dictionary={}
	for i in 3000:
		for key in ["crew","crew_full","mobility_kill","firepower_kill","abandoned","crash"]:helo.erase(key)
		helo.hp=helo.max_hp
		s9.events.clear()
		VehicleDamage.strike(s9,aa,helo,s9.damage_amount(aa,helo))
		for e in s9.events:if e.type=="vehicle_damage" and e.effect not in ["destroyed","wreck"]:helo_tally[e.effect]=helo_tally.get(e.effect,0)+1
	s9.remove_meta(VehicleDamage.HAZARDS)
	print("OUTCOMES autocannon vs gunship (n=3000): %s" % str(helo_tally))
	check(helo_tally.get("tail_rotor",0)>150 and helo_tally.get("hydraulics",0)>70,"tail rotor and hydraulics hits occur")
	for key in ["crew","crew_full","mobility_kill","firepower_kill","abandoned","crash"]:helo.erase(key)
	helo.hp=helo.max_hp
	s9.events.clear()
	VehicleDamage.ensure_state(s9,helo)
	helo["crash"]="spin"
	VehicleDamage._hazard(s9,helo)
	check(not VehicleDamage.weapon_ready(s9,helo),"a falling gunship cannot fire")
	var below_hp:float=below.hp
	var down_at:=-1.0
	var crash_blast:=0
	for i in 30*8:
		s9.tick(1.0/30)
		crash_blast+=count(s9.events,"world_blast","kind","crash")
		s9.events.clear()
		if not s9.alive(helo) and down_at<0:down_at=s9.time
	print("TAIL ROTOR: down after %.1f s, troops below %.0f -> %.0f, wreck %s" % [down_at,below_hp,below.hp,str(helo.get("wrecked",false))])
	check(down_at>1.0 and down_at<4.0,"spins down and crashes within seconds")
	check(crash_blast==1 and below.hp<below_hp,"crash blast hurts the troops underneath")
	check(helo.get("wrecked",false) and VehicleDamage.wrecks(s9).any(func(w):return w.id==helo.id),"crash site is a wreck on the ground")
	var lander:Dictionary=s9.spawn("helo",1,open_ground(s9,BASE+Vector2(60,0),4.0))
	var bystander:Dictionary=s9.spawn("rifle",0,lander.pos+Vector2(1.5,0))
	VehicleDamage.ensure_state(s9,lander)
	lander["crash"]="landing"
	VehicleDamage._hazard(s9,lander)
	var bystander_hp:float=bystander.hp
	var landing_blasts:=0
	for i in 30*8:
		s9.tick(1.0/30)
		landing_blasts+=count(s9.events,"world_blast")
		s9.events.clear()
	check(not s9.alive(lander) and landing_blasts==0 and bystander.hp==bystander_hp,"hydraulics: forced landing, out of action, no blast")

	# --- 10. Drones: any hit downs them ------------------------------------------------------
	var s10=Sim.new(false,harbor)
	for kind in ["drone","fpv_drone"]:
		var drone:Dictionary=s10.spawn(kind,1,open_ground(s10,BASE,2.0))
		var row:="DRONE %s downed per hit:" % kind
		for weapon in ["rifle","engineer","tank","aa"]:
			var source:={"kind":weapon,"pos":drone.pos+Vector2(6,0),"team":0,"members":[]}
			var downed:=0
			var scale:float=(0.25*(0.4 if weapon=="engineer" else 1.0)) if weapon in ["rifle","engineer"] else 1.0
			for i in 400:
				drone.hp=drone.max_hp
				if SD.strike(s10,source,drone,s10.damage_amount(source,drone)*scale)>=drone.hp:downed+=1
			row+=" %s %.2f" % [weapon,downed/400.0]
			check(downed/400.0>0.85,"%s hit downs a %s (%.2f)" % [weapon,kind,downed/400.0])
		print(row)

	# --- 11. Street furniture and trees flattened by HE -----------------------------------------
	var s11=Sim.new(false,harbor)
	var picks:Dictionary={}
	for rect in s11.terrain.crushables:
		var family:String=str(s11.terrain.crushables[rect].id).get_slice(".",0)
		if family in ["lamp","tree","car","bench"] and not picks.has(family):picks[family]=rect
	for family in picks:
		var rect:Rect2=picks[family]
		var impact:Vector2=rect.get_center()+Vector2(1.2,0)
		s11.events.append({"type":"shot","from":impact+Vector2(20,0),"to":impact,"kind":"rifle","target_kind":"rifle","hit":false,"visible":true})
		SD.tick(s11,1.0/30)
		var survived:bool=s11.terrain.crushables.has(rect)
		s11.events.append({"type":"shot","from":impact+Vector2(20,0),"to":impact,"kind":"tank","target_kind":"rifle","hit":false,"visible":true})
		SD.tick(s11,1.0/30)
		var crushed:=false
		for e in s11.events:if e.type=="crushed" and e.get("cause","")=="blast" and e.pos==rect.get_center():crushed=true
		check(survived and not s11.terrain.crushables.has(rect) and crushed,"%s: rifle round leaves it, HE 1.2 m away flattens it" % family)
	check(picks.has("tree") and picks.has("lamp"),"harbor has crushable lamps and trees")
	var air_shot:={"type":"shot","from":BASE,"to":BASE+Vector2(3,0),"kind":"aa","target_kind":"helo","hit":true,"visible":true}
	var crush_count:int=s11.terrain.crushables.size()
	s11.events.append(air_shot)
	SD.tick(s11,1.0/30)
	check(s11.terrain.crushables.size()==crush_count,"flak at aircraft does not flatten props below")

	# --- 12. Collapse visuals: parcel triangles hidden, marks batched, mound baked ---------------
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	var art=Art.new()
	var root:=Node3D.new()
	var built:=Time.get_ticks_msec()
	art.make_harbor_building_chunks(root,[],configs[harbor].architecture)
	built=Time.get_ticks_msec()-built
	var spec_index:int=-1
	var architecture:Array=configs[harbor].architecture
	for i in architecture.size():
		var spec:Dictionary=architecture[i]
		if spec.has("collision") and int(spec.collision[0])==int(target.blocks[0]):spec_index=i
	if not fixture(spec_index>=0,"collapsed building maps to its authored visual"):
		root.free()
		return
	var staging:=Node3D.new()
	var spec:Dictionary=architecture[spec_index]
	var size:=Vector2(spec.source_size[0],spec.source_size[1])
	var own:Node3D=art.make_authored_building(staging,Rect2(Vector2(spec.position[0],spec.position[1])-size/2,size),spec_index,spec)
	var own_triangles:=triangles(own)
	staging.free()
	var before_total:=triangles(root)
	var t0:=Time.get_ticks_usec()
	for e in [{"type":"building_damage","building":target.id,"state":SD.DAMAGED,"impact":SD.wall_point(target,spot),"source":spot},{"type":"building_damage","building":target.id,"state":SD.BREACHED,"impact":SD.wall_point(target,spot),"source":spot}]:
		Ruin.show_damage(art,root,s2,e)
	var marks:MultiMeshInstance3D=root.get_node("WorldDamageMarks")
	var mark_count:int=marks.multimesh.visible_instance_count
	var t1:=Time.get_ticks_usec()
	Ruin.show_damage(art,root,s2,collapse_event)
	var collapse_ms:=(Time.get_ticks_usec()-t1)/1000.0
	var removed:=before_total-triangles(root.get_node("HarborBuildings"))
	var mound:Node3D=root.get_node_or_null("Rubble_%d" % target.id)
	print("VISUALS: tiles built in %d ms; damage marks %d (one MultiMesh); collapse handled in %.1f ms; parcel triangles %d, hidden %d; rubble mound %d mesh nodes" % [built,mark_count,collapse_ms,own_triangles,removed,mound.get_child_count() if mound!=null else -1])
	check(mark_count>=2,"damage events add scorch/hole marks")
	check(removed>=own_triangles*0.85 and removed<=own_triangles*1.05,"collapse hides this parcel's triangles only (%d of %d)" % [removed,own_triangles])
	check(mound!=null and mound.get_child_count()>0 and mound.get_child_count()<=4,"low rubble mound is baked into a few meshes")
	check(collapse_ms<60.0,"collapse visual update is cheap (%.1f ms)" % collapse_ms)
	root.free()

	# --- 12b. Through battle.gd: consume_events drives the same visuals in the real scene ---
	var previous:int=Sim.scenario_selection
	Sim.scenario_selection=harbor
	var battle=load("res://scenes/main.tscn").instantiate()
	get_root().add_child(battle)
	Sim.scenario_selection=previous
	battle.set_process(false)
	battle.set_physics_process(false)
	battle.effects.set_process(false)
	battle.effects.muted=true
	var bsim=battle.sim
	var bt:Dictionary=pick_building(bsim,"stone_house",30.0,80.0)
	if not fixture(not bt.is_empty(),"found a small stone house in the battle scene"):
		get_root().remove_child(battle)
		battle.free()
		return
	var tile_root:Node=battle.find_child("HarborBuildings",true,false)
	var tiles_before:=triangles(tile_root) if tile_root!=null else -1
	bsim.events.clear()
	var b_spot:Vector2=firing_spot(bsim,bt,10.0)
	SD.damage_building(bsim,bt.id,SD.integrity(bt)*0.8,b_spot)
	SD.damage_building(bsim,bt.id,SD.integrity(bt),b_spot)
	var b_started:=Time.get_ticks_usec()
	battle.consume_events()
	var b_ms:=(Time.get_ticks_usec()-b_started)/1000.0
	var b_hidden:=tiles_before-triangles(tile_root) if tile_root!=null else -1
	var b_marks:MultiMeshInstance3D=battle.find_child("WorldDamageMarks",true,false)
	print("BATTLE consume_events: collapse of %s handled in %.1f ms; hidden %d triangles; rubble %s; marks %d" % [bt.design,b_ms,b_hidden,str(battle.find_child("Rubble_%d" % bt.id,true,false)!=null),b_marks.multimesh.visible_instance_count if b_marks!=null else -1])
	check(tile_root!=null and b_hidden>0,"battle hides the collapsed parcel in its city tile")
	check(battle.find_child("Rubble_%d" % bt.id,true,false)!=null and b_marks!=null,"battle adds the rubble mound and damage marks")
	get_root().remove_child(battle)
	battle.free()

	# --- 13. Cost of the per-tick hook ------------------------------------------------------
	var s13=Sim.new(false,harbor)
	for i in 300:s13.events.append({"type":"shot","from":BASE,"to":BASE+Vector2(i%30,i/30),"kind":"rifle" if i%3 else "tank","target_kind":"rifle","hit":true,"visible":true})
	var scan:=Time.get_ticks_usec()
	SD.tick(s13,1.0/30)
	var scan_ms:=(Time.get_ticks_usec()-scan)/1000.0
	var idle:=Time.get_ticks_usec()
	for i in 1000:SD.tick(s13,1.0/30)
	print("HOOK cost: 300 fresh shot events %.2f ms; idle tick %.4f ms" % [scan_ms,(Time.get_ticks_usec()-idle)/1000.0/1000.0])
	check((Time.get_ticks_usec()-idle)/1000.0/1000.0<0.05,"idle per-tick cost is negligible")
	print("WORLD DAMAGE: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)

func triangles(node:Node)->int:
	var total:=0
	if node is MeshInstance3D and node.mesh!=null:
		for surface in node.mesh.get_surface_count():
			var a:Array=node.mesh.surface_get_arrays(surface)
			var indices=a[Mesh.ARRAY_INDEX]
			if indices!=null and not indices.is_empty():
				for t in range(0,indices.size(),3):
					if not (indices[t]==indices[t+1] and indices[t+1]==indices[t+2]):total+=1
			else:total+=a[Mesh.ARRAY_VERTEX].size()/3
	for child in node.get_children():total+=triangles(child)
	return total
