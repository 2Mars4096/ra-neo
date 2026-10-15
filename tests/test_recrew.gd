extends SceneTree
# Re-crewing abandoned vehicles: a crew bail-out keeps the hull's integrity; an
# infantry section ordered to the hull climbs in after ~4 s beside it, the
# vehicle drives and fires again (understrength crew keeps its penalties), the
# section loses the boarding soldiers (and disappears if none are left), heavy
# fire delays the work, burnt-out wrecks cannot be re-crewed, an enemy hull is
# captured, and the battle right-click order is accepted with a toast. Follow-ups:
# the bail-out's kill/loss is revoked when the hull returns to service, the enemy
# AI re-crews its own hulls and captures idle-reach player hulls, and the battle
# selection / control groups follow the hull to the new vehicle.
const Sim=preload("res://scripts/simulation.gd")
const VehicleDamage=preload("res://scripts/vehicle_damage.gd")
const DT:=1.0/30.0
const BASE:=Vector2(300,640)
var failures:=0
var checks:=0
var battle:Node=null
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func scenario_index(id:String)->int:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		if configs[i].id==id:return i
	return -1

func _init()->void:
	bailout_keeps_hull()
	recrew_restores()
	last_soldiers()
	heavy_fire_delays()
	not_for_wrecks()
	capture_enemy()
	counters_follow_hull()
	enemy_reclaims_own()
	enemy_resumes_attack()
	enemy_captures_player()
	enemy_holds_off()
	preload("res://scripts/simulation.gd").scenario_selection=0
	call_deferred("battle_order")

# A hull whose crew bailed out (hp 0, wreck flagged abandoned, integrity kept).
func make_abandoned(sim,team:int,pos:Vector2,integrity:float=300.0)->Dictionary:
	var hull:Dictionary=sim.spawn("tank",team,pos)
	hull.facing=Vector2.UP
	VehicleDamage.ensure_state(sim,hull)
	hull.crew=0
	hull.abandoned=true
	hull["abandoned_hp"]=integrity
	hull.hp-=VehicleDamage._finish(sim,hull,hull.hp+1.0)
	return hull

func able(section:Dictionary)->int:
	return section.members.filter(func(m):return m.hp>0).size()

func boarded(section:Dictionary)->int:
	return section.members.filter(func(m):return m.wound==VehicleDamage.BOARDED).size()

func run_until(sim,seconds:float,done:Callable)->float:
	var start:float=sim.time
	while sim.time-start<seconds:
		sim.tick(DT)
		if done.call():break
	return sim.time-start

# --- 1. A real bail-out keeps the hull's integrity --------------------------------
func bailout_keeps_hull()->void:
	var sim=Sim.new(false,scenario_index("black_sea_harbor"))
	var gunner:Dictionary=sim.spawn("tank",1,BASE+Vector2(14,0))
	var tank:Dictionary=sim.spawn("tank",0,BASE)
	tank.facing=Vector2.UP
	for i in 2000:
		VehicleDamage.ensure_state(sim,tank)
		tank.hp=tank.max_hp
		tank.crew=1
		tank.abandoned=false
		tank.erase("wrecked")
		tank.erase("abandoned_hp")
		VehicleDamage.wrecks(sim).clear()
		sim.resolve_shot(gunner,tank,1.0)
		if tank.hp<=0.0 and tank.abandoned:break
	check(tank.abandoned and tank.hp<=0.0 and tank.get("wrecked",false),"crew bail-out still leaves an abandoned wreck")
	check(float(tank.get("abandoned_hp",0.0))>0.0 and float(tank.abandoned_hp)<tank.max_hp,"bail-out records the hull's remaining integrity")
	check(VehicleDamage.recrewable(sim,tank),"abandoned hull is re-crewable")
	check(VehicleDamage.abandoned_at(sim,tank.pos+Vector2(1.5,0))==tank,"abandoned hull found under the click")
	check(VehicleDamage.abandoned_at(sim,tank.pos+Vector2(10,0)).is_empty(),"no hull found 10 m away")
	print("BAILOUT abandoned_hp=%.1f of %.0f" % [float(tank.get("abandoned_hp",0.0)),tank.max_hp])

# --- 2. Re-crew: crew restored, section shrinks, vehicle moves and fires ----------
func recrew_restores()->void:
	var sim=Sim.new(false,scenario_index("black_sea_harbor"))
	var hull:=make_abandoned(sim,0,BASE,300.0)
	var section:Dictionary=sim.spawn("rifle",0,BASE+Vector2(-14,6))
	var members_before:int=able(section)
	var hp_before:float=section.hp
	sim.losses=1
	check(VehicleDamage.order_recrew(sim,[section.id],hull.id)==1,"re-crew order accepted")
	check(not section.orders.is_empty() and section.orders[0].mode=="move","section walks to the hull")
	var reach:float=float(sim.definitions.tank.radius)+VehicleDamage.RECREW_REACH
	# Lambdas capture locals by value: keep the arrival time in a dictionary.
	var mark:={"arrived":-1.0}
	var t:=run_until(sim,40.0,func():
		if mark.arrived<0.0 and section.pos.distance_to(hull.pos)<=reach:mark.arrived=sim.time
		return hull.has("recrewed_as"))
	var fresh:Dictionary=sim.get_unit(int(hull.get("recrewed_as",-1)))
	var arrived:float=mark.arrived
	var work:float=sim.time-arrived
	print("RECREW walked+boarded in %.1fs, work %.2fs after arriving, crew %d/%d, section %d->%d" % [t,work,int(fresh.get("crew",-1)),int(fresh.get("crew_full",-1)),members_before,able(section)])
	check(not fresh.is_empty() and sim.alive(fresh),"a crewed vehicle replaces the abandoned hull")
	check(arrived>0.0 and work>=VehicleDamage.RECREW_SECONDS-0.05 and work<=VehicleDamage.RECREW_SECONDS+1.0,"boarding takes ~4 s beside the hull (%.2f)" % work)
	if fresh.is_empty():return
	check(fresh.team==0 and fresh.kind=="tank" and not fresh.abandoned,"same kind, friendly, not abandoned")
	check(int(fresh.crew)==mini(2,int(sim.definitions.tank.crew)) and int(fresh.crew_full)==int(sim.definitions.tank.crew),"crew restored to min(crew_full, 2)")
	check(is_equal_approx(fresh.hp,300.0),"hull keeps its integrity (%.1f)" % fresh.hp)
	check(fresh.pos==hull.pos and fresh.facing==hull.facing,"vehicle stays where the hull stood")
	check(not hull.get("wrecked",false) and VehicleDamage.wrecks(sim).filter(func(w):return int(w.id)==int(hull.id)).is_empty(),"wreck removed")
	check(not VehicleDamage.recrewable(sim,hull),"hull cannot be re-crewed twice")
	check(able(section)==members_before-int(fresh.crew) and boarded(section)==int(fresh.crew),"section loses the boarding soldiers")
	check(sim.alive(section) and section.hp<hp_before,"section survives with the rest")
	check(sim.Infantry.casualties(section)==0 and not sim.Infantry.has_remains(section),"boarders are not casualties or bodies")
	check(not sim.has_meta(VehicleDamage.RECREW),"job finished")
	check(sim.losses==0,"re-crew revokes the bail-out loss (%d)" % sim.losses)
	var event:Array=sim.events.filter(func(e):return e.type=="vehicle_damage" and e.effect=="recrewed")
	check(event.size()==1 and int(event[0].unit)==fresh.id and int(event[0].get("from",-1))==hull.id and int(event[0].get("section",-1))==section.id,"recrewed event names the new vehicle, old hull and section")
	check(sim.events.any(func(e):return e.type=="warning" and str(e.text).contains("re-crewed")),"player toast on re-crew")
	# It drives.
	var start:Vector2=fresh.pos
	var accepted:=0
	for direction in [Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT,Vector2.UP]:
		accepted=sim.issue([fresh.id],fresh.pos+direction*16.0,"move")
		if accepted>0:break
	check(accepted==1,"re-crewed vehicle accepts a move order")
	run_until(sim,10.0,func():return fresh.orders.is_empty())
	print("RECREW drove %.1f m" % fresh.pos.distance_to(start))
	check(fresh.pos.distance_to(start)>8.0,"re-crewed vehicle moves")
	# It fires.
	var enemy:Dictionary=sim.spawn("tank",1,fresh.pos+(fresh.pos-start).normalized()*16.0)
	enemy.visible=true
	var fired_before:float=float(fresh.last_shot)
	run_until(sim,10.0,func():return float(fresh.last_shot)>fired_before)
	check(float(fresh.last_shot)>fired_before,"re-crewed vehicle fires")
	check(VehicleDamage.weapon_ready(sim,fresh) or fresh.firepower_kill,"weapon gate open")

# --- 3. Last soldiers: understrength crew, section disappears ---------------------
func last_soldiers()->void:
	var sim=Sim.new(false,scenario_index("black_sea_harbor"))
	var hull:=make_abandoned(sim,0,BASE,250.0)
	var section:Dictionary=sim.spawn("rifle",0,BASE+Vector2(-6,0))
	# Two soldiers already killed: one man left.
	for k in range(1,section.members.size()):
		section.members[k].hp=0.0
		section.members[k].wound=sim.Infantry.KIA
	sim.Infantry.publish(section)
	check(able(section)==1,"one soldier left")
	check(VehicleDamage.order_recrew(sim,[section.id],hull.id)==1,"lone soldier may re-crew")
	run_until(sim,30.0,func():return hull.has("recrewed_as"))
	var fresh:Dictionary=sim.get_unit(int(hull.get("recrewed_as",-1)))
	check(not fresh.is_empty() and int(fresh.crew)==1,"understrength crew of one")
	check(not sim.alive(section),"section with only the boarders disappears")
	if fresh.is_empty():return
	# Understrength: slower firing cycle than a full crew.
	var missing:int=int(fresh.crew_full)-int(fresh.crew)
	check(missing>0,"crew-casualty penalties apply (%d missing)" % missing)
	fresh.last_shot=sim.time
	fresh.cooldown=0.0
	VehicleDamage.weapon_ready(sim,fresh)
	check(float(fresh.cooldown)>0.0,"understrength reload penalty applied")

# --- 4. Heavy fire delays boarding ---------------------------------------------------
func heavy_fire_delays()->void:
	var sim=Sim.new(false,scenario_index("black_sea_harbor"))
	var hull:=make_abandoned(sim,0,BASE)
	var section:Dictionary=sim.spawn("rifle",0,BASE+Vector2(-5,0))
	check(VehicleDamage.order_recrew(sim,[section.id],hull.id)==1,"order accepted next to the hull")
	var pinned:=6.0
	var start:float=sim.time
	var t:=run_until(sim,30.0,func():
		if sim.time-start<pinned:section.suppression=0.9
		return hull.has("recrewed_as"))
	print("HEAVY FIRE boarded after %.2fs (pinned %.1fs)" % [t,pinned])
	check(t>=pinned+VehicleDamage.RECREW_SECONDS-0.6,"heavy fire delays boarding (%.2f s)" % t)
	check(hull.has("recrewed_as"),"boards once the fire lifts")
	# A recent hit also pauses the work.
	var sim2=Sim.new(false,scenario_index("black_sea_harbor"))
	var hull2:=make_abandoned(sim2,0,BASE)
	var section2:Dictionary=sim2.spawn("rifle",0,BASE+Vector2(-5,0))
	VehicleDamage.order_recrew(sim2,[section2.id],hull2.id)
	run_until(sim2,8.0,func():
		section2.last_hit=sim2.time
		return hull2.has("recrewed_as"))
	check(not hull2.has("recrewed_as") and able(section2)==3,"no boarding while being hit")

# --- 5. Not for burnt-out wrecks, live vehicles or non-infantry -------------------
func not_for_wrecks()->void:
	var sim=Sim.new(false,scenario_index("black_sea_harbor"))
	var burnt:Dictionary=sim.spawn("tank",0,BASE)
	burnt.hp-=VehicleDamage._finish(sim,burnt,burnt.hp+1.0)
	var section:Dictionary=sim.spawn("rifle",0,BASE+Vector2(-10,0))
	check(burnt.get("wrecked",false) and not VehicleDamage.recrewable(sim,burnt),"burnt-out wreck is not re-crewable")
	check(VehicleDamage.abandoned_at(sim,burnt.pos).is_empty(),"no re-crew target on a burnt-out wreck")
	check(VehicleDamage.order_recrew(sim,[section.id],burnt.id)==0,"order refused for a wreck")
	# Shot to pieces as the crew bailed out: nothing left to crew.
	var gutted:=make_abandoned(sim,0,BASE+Vector2(0,20),0.0)
	check(VehicleDamage.order_recrew(sim,[section.id],gutted.id)==0,"order refused for a gutted hull")
	var live:Dictionary=sim.spawn("tank",0,BASE+Vector2(20,0))
	check(VehicleDamage.order_recrew(sim,[section.id],live.id)==0,"order refused for a crewed vehicle")
	var hull:=make_abandoned(sim,0,BASE+Vector2(0,-20))
	var crewman:Dictionary=sim.spawn("tank",0,BASE+Vector2(-20,-20))
	check(VehicleDamage.order_recrew(sim,[crewman.id],hull.id)==0,"only infantry sections re-crew")
	# A new order cancels the job.
	check(VehicleDamage.order_recrew(sim,[section.id],hull.id)==1,"order accepted")
	sim.issue([section.id],section.pos+Vector2(-15,0),"move")
	run_until(sim,12.0,func():return hull.has("recrewed_as"))
	check(not hull.has("recrewed_as") and not sim.has_meta(VehicleDamage.RECREW),"a new order cancels re-crewing")

# --- 6. Capture an enemy hull -------------------------------------------------------
func capture_enemy()->void:
	var sim=Sim.new(false,scenario_index("black_sea_harbor"))
	var hull:=make_abandoned(sim,1,BASE)
	var section:Dictionary=sim.spawn("atgm",0,BASE+Vector2(-8,4))
	sim.kills=1
	check(VehicleDamage.order_recrew(sim,[section.id],hull.id)==1,"capture order accepted")
	run_until(sim,30.0,func():return hull.has("recrewed_as"))
	var fresh:Dictionary=sim.get_unit(int(hull.get("recrewed_as",-1)))
	check(not fresh.is_empty() and fresh.team==0 and int(fresh.crew)==2,"enemy hull captured with two crew")
	check(not sim.alive(section),"two-man AT team fully boarded: section gone")
	check(sim.events.any(func(e):return e.type=="warning" and str(e.text).contains("captured")),"player toast on capture")
	check(sim.kills==0,"capture revokes the bail-out kill (%d)" % sim.kills)

# --- 7. Counters: a real bail-out, a capture, and the captured vehicle's loss ------
func counters_follow_hull()->void:
	var sim=Sim.new(false,scenario_index("black_sea_harbor"))
	var gunner:Dictionary=sim.spawn("tank",0,BASE+Vector2(14,0))
	var tank:Dictionary=sim.spawn("tank",1,BASE)
	tank.facing=Vector2.UP
	for i in 2000:
		VehicleDamage.ensure_state(sim,tank)
		tank.hp=tank.max_hp
		tank.crew=1
		tank.abandoned=false
		tank.erase("wrecked")
		tank.erase("abandoned_hp")
		VehicleDamage.wrecks(sim).clear()
		sim.kills=0
		sim.resolve_shot(gunner,tank,1.0)
		if tank.hp<=0.0 and tank.abandoned and float(tank.get("abandoned_hp",0.0))>0.0:break
	check(VehicleDamage.recrewable(sim,tank) and sim.kills==1,"enemy bail-out counts one kill (%d)" % sim.kills)
	sim.issue([gunner.id],BASE+Vector2(14,-30),"move")
	var section:Dictionary=sim.spawn("rifle",0,BASE+Vector2(-8,0))
	VehicleDamage.order_recrew(sim,[section.id],tank.id)
	run_until(sim,30.0,func():return tank.has("recrewed_as"))
	var fresh:Dictionary=sim.get_unit(int(tank.get("recrewed_as",-1)))
	check(not fresh.is_empty() and fresh.team==0,"player captured the bailed-out enemy tank")
	check(sim.kills==0 and sim.losses==0,"capture: kill revoked, no loss (%d/%d)" % [sim.kills,sim.losses])
	if fresh.is_empty():return
	var enemy:Dictionary=sim.spawn("tank",1,fresh.pos+Vector2(0,-14))
	fresh.hp=1.0
	fresh.crew=fresh.crew_full
	for i in 400:
		if not sim.alive(fresh):break
		sim.resolve_shot(enemy,fresh,1.0)
	check(not sim.alive(fresh) and sim.kills==0 and sim.losses==1,"captured vehicle lost later counts once, as a player loss (%d/%d)" % [sim.kills,sim.losses])
	print("COUNTERS kills=%d losses=%d" % [sim.kills,sim.losses])

# --- 8. Enemy AI: infantry near its own abandoned hull climbs back in ---------------
func enemy_reclaims_own()->void:
	var sim=Sim.new(false,scenario_index("black_sea_harbor"))
	sim.spawn("rifle",0,BASE+Vector2(0,-90))
	var hull:=make_abandoned(sim,1,BASE)
	var section:Dictionary=sim.spawn("rifle",1,BASE+Vector2(11,3))
	sim.kills=1
	var t:=run_until(sim,30.0,func():return hull.has("recrewed_as"))
	var fresh:Dictionary=sim.get_unit(int(hull.get("recrewed_as",-1)))
	print("ENEMY RECREW own hull in %.1fs" % t)
	check(not fresh.is_empty() and fresh.team==1 and int(fresh.crew)==2,"enemy section re-crews its own hull through the field_ops tick")
	check(able(section)==1,"enemy section loses the boarders")
	check(sim.kills==0,"enemy re-crew revokes the player's kill (%d)" % sim.kills)
	check(not sim.events.any(func(e):return e.type=="warning" and str(e.text).contains("re-crewed")),"no player toast for an enemy re-crew")

# --- 9. Enemy AI: an attacking section re-crews in passing and carries on -----------
func enemy_resumes_attack()->void:
	var sim=Sim.new(false,scenario_index("black_sea_harbor"))
	sim.spawn("rifle",0,BASE+Vector2(0,-90))
	var hull:=make_abandoned(sim,1,BASE)
	var section:Dictionary=sim.spawn("rifle",1,BASE+Vector2(12,0))
	var goal:=BASE+Vector2(-40,0)
	check(sim.issue([section.id],goal,"attack_move")==1,"enemy section attack-moving past its hull")
	run_until(sim,30.0,func():return hull.has("recrewed_as"))
	var fresh:Dictionary=sim.get_unit(int(hull.get("recrewed_as",-1)))
	check(not fresh.is_empty() and fresh.team==1,"attacking enemy section re-crews a hull within reach")
	if fresh.is_empty():return
	check(not fresh.orders.is_empty() and fresh.orders[-1].mode=="attack_move" and fresh.orders[-1].pos.distance_to(goal)<6.0,"re-crewed enemy vehicle takes up the attack")
	check(not section.orders.is_empty() and section.orders[-1].mode=="attack_move","rest of the section resumes the attack")

# --- 10. Enemy AI: an idle section captures a player hull within ~25 m ---------------
func enemy_captures_player()->void:
	var sim=Sim.new(false,scenario_index("black_sea_harbor"))
	sim.spawn("rifle",0,BASE+Vector2(0,-90))
	var hull:=make_abandoned(sim,0,BASE)
	var far:=make_abandoned(sim,0,BASE+Vector2(0,60))
	var section:Dictionary=sim.spawn("rifle",1,BASE+Vector2(22,6))
	sim.losses=2
	check(VehicleDamage.enemy_recrew(sim)==1,"idle enemy section sent to the near player hull")
	check(sim.has_meta(VehicleDamage.RECREW) and int(sim.get_meta(VehicleDamage.RECREW)[0].hull)==hull.id,"the near hull, not the one ~60 m away")
	check(VehicleDamage.enemy_recrew(sim)==0,"AI poll is throttled")
	run_until(sim,30.0,func():return hull.has("recrewed_as"))
	var fresh:Dictionary=sim.get_unit(int(hull.get("recrewed_as",-1)))
	check(not fresh.is_empty() and fresh.team==1,"enemy captures the abandoned player hull")
	check(sim.losses==1,"capture revokes the bail-out loss for that hull (%d)" % sim.losses)
	check(VehicleDamage.recrewable(sim,far) and not far.has("recrewed_as"),"hull beyond reach left alone")
	check(not sim.events.any(func(e):return e.type=="warning" and str(e.text).contains("captured")),"no 'captured' player toast for an enemy capture")

# --- 11. Enemy AI holds off: under fire, busy elsewhere, or already claimed --------
func enemy_holds_off()->void:
	var sim=Sim.new(false,scenario_index("black_sea_harbor"))
	var own:=make_abandoned(sim,1,BASE)
	var player:=make_abandoned(sim,0,BASE+Vector2(0,40))
	var pinned:Dictionary=sim.spawn("rifle",1,BASE+Vector2(8,0))
	var busy:Dictionary=sim.spawn("rifle",1,BASE+Vector2(12,40))
	pinned.suppression=0.8
	check(sim.issue([busy.id],BASE+Vector2(12,60),"move")==1,"enemy section busy with a move order")
	check(VehicleDamage.enemy_recrew(sim)==0,"no re-crew under fire; no capture by a section with orders")
	pinned.suppression=0.0
	pinned.last_hit=sim.time
	sim.set_meta(VehicleDamage.RECREW_AI_NEXT,-1.0)
	check(VehicleDamage.enemy_recrew(sim)==0,"no re-crew just after being hit")
	pinned.last_hit=sim.time-VehicleDamage.ENEMY_RECREW_QUIET-1.0
	sim.set_meta(VehicleDamage.RECREW_AI_NEXT,-1.0)
	var ally:Dictionary=sim.spawn("rifle",0,BASE+Vector2(-8,0))
	check(VehicleDamage.order_recrew(sim,[ally.id],own.id)==1,"player claims the enemy hull first")
	check(VehicleDamage.enemy_recrew(sim)==0,"enemy does not race for a hull already claimed")
	check(VehicleDamage.recrewable(sim,player),"player hull untouched")

# --- 7. Battle right-click: order accepted, toast, presentation -------------------
func battle_order()->void:
	root.size=Vector2i(1440,900)
	battle=load("res://scenes/main.tscn").instantiate()
	root.add_child(battle)
	current_scene=battle
	await process_frame
	await process_frame
	var sim=battle.sim
	var section:Dictionary=sim.get_unit(1)
	check(section.kind in VehicleDamage.RECREW_KINDS,"unit 1 is an infantry section (%s)" % section.kind)
	var hull:=make_abandoned(sim,0,section.pos+Vector2(10,0))
	battle.sync_units(0.016)
	battle.selected=[section.id]
	# The hull was grouped before its crew bailed out; the section has a group too.
	battle.groups[2]=[hull.id,2]
	battle.groups[3]=[section.id]
	battle.groups[4]=[2]
	battle.give_order(battle.screen_pos(hull.pos),false,false)
	check(sim.has_meta(VehicleDamage.RECREW) and int(sim.get_meta(VehicleDamage.RECREW)[0].hull)==hull.id,"right-click on the hull orders re-crewing")
	check(str(battle.toast).contains("re-crew"),"toast: %s" % battle.toast)
	var t:=0.0
	while t<30.0 and not hull.has("recrewed_as"):
		sim.tick(DT)
		battle.consume_events()
		t+=DT
	battle.sync_units(0.016)
	var fresh:Dictionary=sim.get_unit(int(hull.get("recrewed_as",-1)))
	check(not fresh.is_empty(),"re-crewed in the battle scene (%.1fs)" % t)
	check(str(battle.toast).contains("re-crewed"),"completion toast: %s" % battle.toast)
	check(not battle.nodes[hull.id].visible,"old wreck model hidden")
	check(not fresh.is_empty() and battle.nodes.has(fresh.id) and battle.nodes[fresh.id].visible,"crewed vehicle model shown")
	check(not fresh.is_empty() and battle.selected.has(fresh.id) and battle.selected.has(section.id),"selection keeps the vehicle (and the rest of the section): %s" % [battle.selected])
	check(not fresh.is_empty() and battle.groups[2]==[2,fresh.id],"hull's control group now holds the vehicle: %s" % [battle.groups[2]])
	check(not fresh.is_empty() and battle.groups[3]==[section.id,fresh.id],"section's control group gains the vehicle: %s" % [battle.groups[3]])
	check(battle.groups[4]==[2],"unrelated control group untouched")
	# Plain right-click on open ground still moves.
	battle.selected=[section.id]
	battle.give_order(battle.screen_pos(section.pos+Vector2(0,12)),false,false)
	check(not section.orders.is_empty() and not sim.has_meta(VehicleDamage.RECREW),"open ground right-click is a normal move")
	print("RECREW: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
