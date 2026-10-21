extends SceneTree
# Player FPV strike: purchase rules, launch geometry, target preference, cooldown,
# fog honesty, the enemy swarm path, and the HUD tile + targeting input path.
const Sim=preload("res://scripts/simulation.gd")
const FieldOps=preload("res://scripts/field_ops.gd")
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func harbor_index()->int:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		if configs[i].id=="black_sea_harbor":return i
	return -1

const AIM:=Vector2(420,560)

# Enemy tank and rifles at AIM, a player rifle section close enough to see them.
func staged(sim)->Dictionary:
	var tank:Dictionary=sim.spawn("tank",1,AIM+Vector2(6,3))
	var rifle:Dictionary=sim.spawn("rifle",1,AIM+Vector2(-3,-2))
	var spotter:Dictionary=sim.spawn("drone",0,AIM+Vector2(-6,4))
	# A rear section keeps the player force alive (no DEFEAT) if the spotter is shot down.
	sim.spawn("rifle",0,sim.field_ops.insertion)
	sim.update_visibility()
	return {"tank":tank,"rifle":rifle,"spotter":spotter}

func _init()->void:
	call_deferred("run")

func run()->void:
	var index:=harbor_index()
	check(index>=0,"harbor scenario exists")
	# Sim-level purchase and launch.
	var sim=Sim.new(false,index)
	var staged_units:=staged(sim)
	var tank:Dictionary=staged_units.tank
	check(tank.seen_by[0] and staged_units.rifle.seen_by[0],"staged enemies are seen (tank %s rifle %s)" % [tank.pos,staged_units.rifle.pos])
	sim.credits=400.0
	check(FieldOps.strike_reason(sim)=="","strike available with supply and no cooldown")
	var ids:Array=FieldOps.player_strike(sim,AIM)
	check(ids.size()==FieldOps.PLAYER_STRIKE_COUNT,"strike launches %d drones (got %d)" % [FieldOps.PLAYER_STRIKE_COUNT,ids.size()])
	check(is_equal_approx(sim.credits,400.0-FieldOps.PLAYER_STRIKE_COST),"strike charges its cost on launch")
	check(is_equal_approx(FieldOps.strike_ready_in(sim),FieldOps.PLAYER_STRIKE_COOLDOWN),"cooldown starts on launch")
	var drones:Array=ids.map(func(id):return sim.get_unit(id))
	check(drones.all(func(d):return d.team==0 and d.kind=="fpv_drone"),"drones are player strike drones")
	check(drones[0].strike_target==tank.id,"first drone takes the vehicle nearest the click")
	var home:Vector2=sim.field_ops.insertion
	var start:Vector2=drones[0].pos
	check(start.distance_to(AIM)<=FieldOps.PLAYER_STRIKE_STANDOFF+3.0,"launch within the strike standoff")
	check((start-AIM).normalized().dot((home-AIM).normalized())>0.98,"drones fly in from the player's base side")
	check(FieldOps.strike_reason(sim).begins_with("FPV strike ready in"),"cooldown blocks a second strike")
	var credits_before:float=sim.credits
	check(FieldOps.player_strike(sim,AIM).is_empty() and sim.credits==credits_before,"blocked strike launches nothing and charges nothing")
	var tank_hp:float=tank.hp
	var enemy_hp:=0.0
	for u in [tank,staged_units.rifle]:enemy_hp+=float(u.hp)
	var gone:=-1.0
	for i in 40*30:
		sim.tick(1.0/30)
		if drones.all(func(d):return not sim.alive(d)):gone=sim.time;break
	var enemy_after:=0.0
	for u in [tank,staged_units.rifle]:enemy_after+=maxf(0.0,float(u.hp))
	check(gone>0,"all drones expended within 40 s (%.1f s)" % gone)
	check(tank.hp<tank_hp,"strike damages the tank (%.0f -> %.0f)" % [tank_hp,tank.hp])
	check(enemy_after<enemy_hp,"strike damages the target group (%.0f -> %.0f)" % [enemy_hp,enemy_after])
	var shot_down:int=drones.filter(func(d):return float(d.get("last_hit",-100.0))>0).size()
	var on_tank:int=drones.filter(func(d):return d.strike_target==tank.id).size()
	print("STRIKE RUN: flight %.1f s, target HP %.0f -> %.0f, tank %.0f -> %.0f, %d/%d drones on tank at end, %d hit by fire" % [gone,enemy_hp,enemy_after,tank_hp,maxf(0,tank.hp),on_tank,drones.size(),shot_down])
	sim.time+=FieldOps.PLAYER_STRIKE_COOLDOWN
	check(FieldOps.strike_ready_in(sim)==0.0,"cooldown expires after %d s" % int(FieldOps.PLAYER_STRIKE_COOLDOWN))
	sim.credits=FieldOps.PLAYER_STRIKE_COST-1.0
	check(FieldOps.strike_reason(sim).begins_with("Need"),"insufficient supply blocks the strike")
	# Clicked unit is preferred over the ranked vehicle; unseen enemies are not targets.
	sim=Sim.new(false,index)
	staged_units=staged(sim)
	sim.credits=400.0
	ids=FieldOps.player_strike(sim,AIM,staged_units.rifle.id)
	check(not ids.is_empty() and sim.get_unit(ids[0]).strike_target==staged_units.rifle.id,"clicked enemy takes the first drone")
	sim=Sim.new(false,index)
	sim.spawn("tank",1,AIM)
	sim.update_visibility()
	sim.credits=400.0
	check(FieldOps.player_strike(sim,AIM).is_empty() and sim.credits==400.0,"no strike on enemies hidden by fog")
	check(sim.field_ops.last_purchase_error=="No visible enemy near the target","fog miss explains itself")
	check(FieldOps.strike_ready_in(sim)==0.0,"failed strike does not start the cooldown")
	# Enemy swarm uses the same observed-target rule as the player.
	sim=Sim.new(false,index)
	var victim:Dictionary=sim.spawn("tank",0,AIM)
	sim.spawn("drone",1,AIM+Vector2(0,4))
	sim.update_visibility()
	sim.events.clear()
	var enemy_ids:Array=FieldOps.launch_swarm(sim,AIM,4)
	check(victim.seen_by[1] and enemy_ids.size()==4 and sim.get_unit(enemy_ids[0]).team==1 and sim.get_unit(enemy_ids[0]).strike_target==victim.id,"enemy swarm launches at observed player units")
	check(sim.events.any(func(e):return e.type=="warning" and "FPV SWARM INBOUND" in str(e.text)),"enemy swarm still warns")
	await battle_input(index)
	print("PLAYER SWARM: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)

func hit_rect(battle,id:String)->Rect2:
	for hit in battle.hud.hits:
		if hit.id==id:return hit.rect
	return Rect2()

func click(p:Vector2,button:int=MOUSE_BUTTON_LEFT)->void:
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new()
		event.position=p;event.button_index=button;event.pressed=pressed
		root.push_input(event)

func key(code:Key)->void:
	for pressed in [true,false]:
		var event:=InputEventKey.new()
		event.keycode=code;event.pressed=pressed
		root.push_input(event)

func battle_input(index:int)->void:
	Sim.scenario_selection=index
	root.size=Vector2i(1440,900)
	var battle=load("res://scenes/main.tscn").instantiate()
	root.add_child(battle);current_scene=battle
	battle.set_physics_process(false)
	await process_frame
	battle.show_help=false;battle.paused=true
	var sim=battle.sim
	var staged_units:=staged(sim)
	sim.credits=400.0
	battle.camera_focus=Vector3(AIM.x,0,AIM.y);battle.update_camera()
	battle.hud.size=Vector2(1440,900)
	battle.hud.queue_redraw();await process_frame;await process_frame
	var tile:=hit_rect(battle,"strike:fpv")
	check(tile.size.x>0,"FPV STRIKE tile is drawn")
	for hit in battle.hud.hits:
		if hit.id!="strike:fpv":check(not hit.rect.intersects(tile),"strike tile clear of "+hit.id)
	check(Rect2(Vector2.ZERO,Vector2(1440,900)).encloses(tile),"strike tile fits the viewport")
	var header_end:float=1440-268+19+battle.hud.bold.get_string_size("REINFORCEMENTS",HORIZONTAL_ALIGNMENT_LEFT,-1,12).x
	check(header_end<tile.position.x-4,"strike tile clears the REINFORCEMENTS header (%.0f < %.0f)" % [header_end,tile.position.x])
	click(tile.get_center())
	check(battle.strike_mode,"clicking the tile arms targeting")
	key(KEY_ESCAPE)
	check(not battle.strike_mode and battle.paused,"Esc cancels targeting without unpausing")
	click(tile.get_center())
	click(battle.screen_pos(AIM),MOUSE_BUTTON_RIGHT)
	check(not battle.strike_mode and sim.credits==400.0,"right-click cancels targeting without charge")
	click(tile.get_center())
	click(battle.screen_pos(AIM+Vector2(0,-60)))
	check(battle.strike_mode and sim.credits==400.0,"click with no seen enemy keeps targeting armed, no charge")
	check(battle.toast=="No visible enemy near the target","miss explained in the toast: "+battle.toast)
	battle.hud.queue_redraw();await process_frame
	var target:Vector2=battle.screen_pos(staged_units.tank.pos,0.8)
	check(battle.hud.action_at(target)=="","target point is on the battlefield")
	click(target)
	var drones:Array=sim.units.filter(func(u):return sim.alive(u) and u.team==0 and u.kind=="fpv_drone")
	check(drones.size()==sim.FieldOps.PLAYER_STRIKE_COUNT,"map click launches the strike (%d drones)" % drones.size())
	check(not battle.strike_mode,"targeting clears after launch")
	check("FPV STRIKE LAUNCHED" in battle.toast,"launch toast shown: "+battle.toast)
	check(drones.any(func(d):return d.strike_target==staged_units.tank.id),"clicked tank is targeted")
	battle.hud.queue_redraw();await process_frame;await process_frame
	tile=hit_rect(battle,"strike:fpv")
	check(battle.hud.action_at(tile.get_center())=="blocked","tile disabled during cooldown")
	click(tile.get_center())
	check(not battle.strike_mode,"cooldown tile does not arm targeting")
	battle.queue_free()
	await process_frame
