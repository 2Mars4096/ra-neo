extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Navigation=preload("res://scripts/tactical_navigation.gd")
const Terrain=preload("res://scripts/terrain.gd")

# Controlled query failure makes every candidate observable, including the
# important distinction between pending budgeted work and an unreachable goal.
class QueryTerrain extends BattleTerrain:
	var calls:Array=[]
	var allow:=false
	func traversable(_p:Vector2,_domain:String,_radius:float=-1,_pressed:Array=[],_profile:String="")->bool:return true
	func segment_clear(_a:Vector2,_b:Vector2,_domain:String,_radius:float,_pressed:Array=[],_profile:String="")->bool:return false
	func line_clear(_a:Vector2,_b:Vector2)->bool:return true
	func reachable(from:Vector2,to:Vector2,domain:String,radius:float=-1,profile:String="default")->bool:
		calls.append([from,to,domain,radius,[],profile])
		return allow
	func path(from:Vector2,to:Vector2,domain:String,radius:float=-1,avoid:Array=[],profile:String="default")->Array[Vector2]:
		calls.append([from,to,domain,radius,avoid.duplicate(true),profile])
		var result:Array[Vector2]=[]
		if allow:result.append(to)
		return result

var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func field():return Sim.new(false,0)

func formation(sim,origin:Vector2,u:Dictionary,slots:Array[Dictionary],open:Dictionary={},held:Array[Dictionary]=[],state:Dictionary={},query_limit:int=2,point_limit:int=7)->Dictionary:
	for step in 1000:
		var before:int=sim.terrain.calls.size() if sim.terrain is QueryTerrain else sim.terrain.astar_calls
		var result:=Navigation.formation(sim,origin,u,slots,open,held,state,query_limit,point_limit)
		var after:int=sim.terrain.calls.size() if sim.terrain is QueryTerrain else sim.terrain.astar_calls
		check(int(result.last_queries)<=query_limit and after-before<=query_limit,"formation call stays within its path budget")
		check(int(result.last_points)<=point_limit,"formation call stays within its candidate budget")
		if result.done:return result
	check(false,"formation search terminates")
	return state

func attack(sim,u:Dictionary,enemy:Dictionary,taken:Array,state:Dictionary={},query_limit:int=2,point_limit:int=17)->Dictionary:
	for step in 2000:
		var before:int=sim.terrain.calls.size() if sim.terrain is QueryTerrain else sim.terrain.astar_calls
		var result:=Navigation.attack(sim,u,enemy,taken,state,query_limit,point_limit)
		var after:int=sim.terrain.calls.size() if sim.terrain is QueryTerrain else sim.terrain.astar_calls
		check(int(result.last_queries)<=query_limit and after-before<=query_limit,"attack call stays within its path budget")
		check(int(result.last_points)<=point_limit,"attack call stays within its candidate budget")
		if result.done:return result
	check(false,"attack search terminates")
	return state

func real_formation_equivalence()->void:
	for probe in [false,true]:
		var sim=field()
		sim.terrain.path_probe=probe
		var slots:Array[Dictionary]=[]
		var legacy_open:Dictionary={}
		var step_open:Dictionary={}
		for row in [["rifle",Vector2(14,50),Vector2(30,50)],["rifle",Vector2(18,56),Vector2(30,50)],["tank",Vector2(20,60),Vector2(34,30)],["drone",Vector2(17,47),Vector2(45,40)],["boat",Vector2(93,55),Vector2(93,35)]]:
			var u:Dictionary=sim.spawn(row[0],0,row[1])
			check(not u.is_empty(),"real formation fixture spawns "+row[0])
			if u.is_empty():continue
			var expected:Vector2=sim.formation_slot(row[2],u,slots,legacy_open)
			var result:=formation(sim,row[2],u,slots,step_open)
			check(result.done and result.pos==expected,"incremental formation matches synchronous "+row[0]+" probe="+str(probe))
			if expected.x>=0:slots.append({"pos":expected,"layer":sim.collision_layer(u),"radius":sim.crowd_radius(u.kind)})
	# Held allies use the infantry-specific angular order and stable stay rule.
	var sim=field()
	var u:Dictionary=sim.spawn("rifle",0,Vector2(20,50))
	var held:Array[Dictionary]=[{"pos":Vector2(27,50),"layer":"land","radius":sim.crowd_radius("rifle")}]
	var slots:Array[Dictionary]=[]
	var expected:Vector2=sim.formation_slot(Vector2(27,50),u,slots,{},held)
	check(formation(sim,Vector2(27,50),u,slots,{},held).pos==expected,"held-section angular and stay ordering is unchanged")
	# The wreck displacement phase also yields within a tiny point budget.
	var tank:Dictionary=sim.spawn("tank",0,Vector2(14,60))
	sim.set_meta(sim.VehicleDamage.WRECKS,[{"id":900,"kind":"tank","pos":Vector2(27,50),"radius":2.45}])
	expected=sim.formation_slot(Vector2(27,50),tank,slots)
	var result:=formation(sim,Vector2(27,50),tank,slots,{},[],{},1,1)
	check(result.pos==expected,"wreck-side formation adjustment preserves its exact destination")

func formation_continuation_and_invalidation()->void:
	var sim=field()
	var u:Dictionary=sim.spawn("rifle",0,Vector2(14,50))
	sim.terrain=QueryTerrain.new(0)
	var terrain:QueryTerrain=sim.terrain
	var slots:Array[Dictionary]=[]
	var expected:Vector2=sim.formation_slot(Vector2(30,50),u,slots)
	var reference:Array=terrain.calls.duplicate(true)
	terrain.calls.clear()
	var state:Dictionary={}
	var initial:=Navigation.formation(sim,Vector2(30,50),u,slots,{},[],state,2,7)
	check(not initial.done and terrain.calls.size()==2,"budget exhaustion leaves formation pending")
	var result:=formation(sim,Vector2(30,50),u,slots,{},[],state)
	check(result.pos==expected and terrain.calls==reference,"formation continuation visits the same candidates once and in the same order")
	check(reference.size()==273,"failed formation fixture exercises every legacy ring candidate")
	state={};terrain.calls.clear()
	Navigation.formation(sim,Vector2(30,50),u,slots,{},[],state,0,7)
	check(not state.done and terrain.calls.is_empty() and int(state.last_points)==0,"zero query budget preserves pending state")
	var open:Dictionary={}
	Navigation.formation(sim,Vector2(30,50),u,slots,open,[],state,1,1)
	var original_queries:int=state.queries
	u.pos+=Vector2(1,0)
	terrain.allow=true
	result=Navigation.formation(sim,Vector2(30,50),u,slots,open,[],state,1,1)
	check(result.done and terrain.calls.back()[0]==u.pos and result.queries==original_queries,"unit movement restarts from the current physical origin")
	slots.append({"pos":result.pos,"layer":sim.collision_layer(u),"radius":sim.crowd_radius(u.kind)})
	expected=sim.formation_slot(Vector2(30,50),u,slots)
	result=formation(sim,Vector2(30,50),u,slots,open,[],state)
	check(result.pos==expected and result.pos!=Vector2(30,50),"new reservation invalidates a previously completed destination")
	slots.clear()
	result=formation(sim,Vector2(30,50),u,slots,open,[],state)
	check(result.pos==Vector2(30,50),"released reservation clears its cached exclusion")
	terrain.geometry_version+=1
	terrain.allow=false
	result=Navigation.formation(sim,Vector2(30,50),u,slots,open,[],state,1,1)
	check(not result.done and result.queries==1,"changed geometry invalidates a completed result without reporting a failed search")
	# Reachability-probe mode follows the same continuation contract.
	terrain.path_probe=true
	result=formation(sim,Vector2(31,50),u,slots,{},[],{},3,8)
	check(result.done and result.pos==Vector2(-1,-1) and result.queries==273,"probe-mode searches obey query limits and complete normally")

func real_attack_equivalence()->void:
	var sim=field()
	var tank:Dictionary=sim.spawn("tank",0,Vector2(14,50))
	var enemy:Dictionary=sim.spawn("rifle",1,Vector2(45,30))
	enemy.seen_by[0]=true
	var taken:Array=[]
	var expected:Vector2=sim.attack_position(tank,enemy,taken)
	check(attack(sim,tank,enemy,taken).pos==expected,"real attack position matches the synchronous path and sight rules")
	taken.append({"pos":expected,"layer":sim.collision_layer(tank),"radius":sim.crowd_radius("tank")})
	expected=sim.attack_position(tank,enemy,taken)
	check(attack(sim,tank,enemy,taken).pos==expected,"attack spread pass retains its exact preferred position")
	var aircraft:Dictionary=sim.spawn("drone",1,Vector2(35,50))
	aircraft.seen_by[0]=true
	var aa:Dictionary=sim.spawn("aa",0,Vector2(18,55))
	expected=sim.attack_position(aa,aircraft)
	check(attack(sim,aa,aircraft,[]).pos==expected,"air-target positioning retains its domain and range rules")

func attack_continuation_and_wrecks()->void:
	var sim=field()
	var u:Dictionary=sim.spawn("tank",0,Vector2(14,50))
	var enemy:Dictionary=sim.spawn("rifle",1,Vector2(30,50))
	enemy.seen_by[0]=true
	sim.terrain=QueryTerrain.new(0)
	var terrain:QueryTerrain=sim.terrain
	sim.definitions.tank.range=5.0
	var expected:Vector2=sim.attack_position(u,enemy)
	var reference:Array=terrain.calls.duplicate(true)
	terrain.calls.clear()
	var state:Dictionary={}
	var first:=Navigation.attack(sim,u,enemy,[],state,1,3)
	check(not first.done and terrain.calls.is_empty() and first.last_points==3,"attack geometry scan yields before path selection")
	var result:=attack(sim,u,enemy,[],state,1,7)
	check(result.pos==expected and terrain.calls==reference,"continued attack search keeps distance sorting and every route attempt in order")
	state={};terrain.calls.clear()
	Navigation.attack(sim,u,enemy,[],state,1,3)
	enemy.pos+=Vector2(3,0)
	terrain.allow=true
	expected=sim.attack_position(u,enemy)
	result=attack(sim,u,enemy,[],state,1,7)
	check(result.pos.x>=0 and result.pos.distance_to(enemy.pos)<=float(state.reach) and terrain.calls.back()[0]==u.pos,"moved target can complete a pending search with currently valid range and route")
	var taken:Array=[{"pos":result.pos,"radius":100.0,"layer":sim.collision_layer(u)}]
	expected=sim.attack_position(u,enemy,taken)
	result=attack(sim,u,enemy,taken,{},1,7)
	check(result.pos==expected,"fully occupied first pass falls back in the same order")
	terrain.allow=false
	sim.set_meta(sim.VehicleDamage.WRECKS,[{"id":901,"kind":"tank","pos":Vector2(24,53),"radius":2.45}])
	terrain.calls.clear()
	expected=sim.attack_position(u,enemy)
	reference=terrain.calls.duplicate(true)
	terrain.calls.clear()
	result=attack(sim,u,enemy,[],{},1,7)
	check(result.pos==expected and terrain.calls==reference,"wreck-limited route failures preserve the synchronous approach order")
	check(reference.size()==sim.WRECK_SPOT_MISSES and int(result.misses)==sim.WRECK_SPOT_MISSES,"wreck failure limit applies across resumed calls")

func moving_observation_and_claims()->void:
	var sim=field()
	var u:Dictionary=sim.spawn("tank",0,Vector2(14,50))
	var enemy:Dictionary=sim.spawn("rifle",1,Vector2(30,50))
	enemy.seen_by[0]=true
	sim.terrain=QueryTerrain.new(0)
	var terrain:QueryTerrain=sim.terrain
	terrain.allow=true
	sim.definitions.tank.range=5.0
	var taken:Array=[{"pos":Vector2(80,70),"radius":2.0,"layer":sim.collision_layer(u)}]
	var state:Dictionary={}
	var result:Dictionary={}
	var admitted:=0
	for step in 300:
		# Every admitted slice sees changed source/target/ally coordinates.
		# A search keyed on exact live positions would never finish gathering.
		u.pos+=Vector2(0.005,0)
		enemy.pos+=Vector2(0.01,0.003)
		taken[0].pos+=Vector2(-0.01,0)
		result=Navigation.attack(sim,u,enemy,taken,state,1,7)
		admitted+=1
		check(int(result.last_queries)<=1 and int(result.last_points)<=7,"moving-contact slice remains budgeted")
		if result.done:break
	check(result.get("done",false) and result.pos.x>=0 and admitted>1 and admitted<100,"moving observed contact and ally claims converge to a firing position")
	check(result.pos.distance_to(enemy.pos)<=sim.horizontal_reach(sim.attack_weapon(u,enemy.kind),enemy,sim.unit_altitude(u))*0.9,"moving-contact result is within current target range")
	check(not terrain.calls.is_empty() and terrain.calls.back()[0]==u.pos,"moving-contact result routes from the current source position")
	check(int(result.refreshes)==0,"small motion does not restart the geometric scan")
	# A newly occupied nearest position must be excluded before publishing.
	state={};taken=[];enemy.pos=Vector2(30,50);u.pos=Vector2(14,50)
	for step in 1000:
		Navigation.attack(sim,u,enemy,taken,state,1,1)
		if state.phase=="gather" and state.cell.x>state.high.x:break
	var now_taken:Vector2=sim.attack_position(u,enemy)
	taken.append({"pos":now_taken,"radius":2.0,"layer":sim.collision_layer(u)})
	result=attack(sim,u,enemy,taken,state,1,7)
	check(result.done and result.pos.x>=0 and result.pos.distance_to(now_taken)>=sim.crowd_radius(u.kind)+2.0+0.7,"new live claim invalidates a candidate before its route is committed")
	# A consistently outrunning target yields a bounded, explicit stale result.
	state={};taken=[];enemy.pos=Vector2(30,50)
	for step in 600:
		if state.has("target"):enemy.pos=state.target+Vector2(12.0+step*0.001,0)
		result=Navigation.attack(sim,u,enemy,taken,state,1,7)
		check(int(result.last_queries)<=1 and int(result.last_points)<=7,"stale-contact refresh remains budgeted")
		if result.done:break
	check(result.get("done",false) and result.pos==Vector2(-1,-1) and result.reason=="stale_search","rapidly displaced observation has an explicit bounded failure")
	check(int(result.refreshes)==Navigation.ATTACK_REFRESHES,"stale observation refreshes stop at the declared limit")
	# Knowledge loss must be checked before inspecting hidden coordinates.
	state={};enemy.pos=Vector2(30,50);enemy.seen_by[0]=true
	Navigation.attack(sim,u,enemy,[],state,1,1)
	enemy.seen_by[0]=false
	enemy.pos=Vector2(1000,1000)
	var prior_calls:=terrain.calls.size()
	result=Navigation.attack(sim,u,enemy,[],state,1,7)
	check(result.done and result.pos==Vector2(-1,-1) and result.reason=="contact_lost","lost contact cannot publish a firing position")
	check(terrain.calls.size()==prior_calls and int(result.last_points)==0 and not state.has("target"),"hidden target movement is neither sampled nor used to restart planning")
	# A new order is a hard reset even when source and target remain stationary.
	enemy.pos=Vector2(30,50);enemy.seen_by[0]=true;state={}
	Navigation.attack(sim,u,enemy,[],state,1,1)
	u.order_version+=1
	result=Navigation.attack(sim,u,enemy,[],state,1,1)
	check(not result.done and result.points==1 and result.refreshes==0,"replacement order starts a new attack search instead of inheriting stale progress")

func queued_attack_tracks_observed_motion()->void:
	var sim=field()
	var ship:Dictionary=sim.spawn("boat",0,Vector2(93,55))
	var enemy:Dictionary=sim.spawn("tank",1,Vector2(70,50))
	check(not ship.is_empty() and not enemy.is_empty(),"moving-target command fixture has valid sea and land bodies")
	if ship.is_empty() or enemy.is_empty():return
	ship.cooldown=100000.0;enemy.cooldown=100000.0
	enemy.hold_command=true
	enemy.seen_by[0]=true
	sim.tactical_clock=INF
	sim.sensor_clock=INF
	# Commands issued during a live simulation tick use incremental placement.
	sim.ticking=true
	check(sim.issue([ship.id],enemy.pos,"attack",false,enemy.id)==1,"moving-target attack enters the real command queue")
	sim.ticking=false
	check(not ship.orders.is_empty() and ship.orders[0].has("slot"),"deferred attack retains its provisional command while planning")
	var resolved:=false
	var preserved:=true
	for step in 240:
		enemy.pos+=Vector2(0,0.005)
		enemy.seen_by[0]=true
		sim.tick(1.0/30.0)
		sim.events.clear()
		if ship.orders.is_empty():preserved=false;break
		preserved=preserved and ship.orders[0].mode=="attack" and int(ship.orders[0].target)==int(enemy.id)
		if not ship.orders[0].has("slot"):
			resolved=true
			break
	check(resolved and preserved,"real moving-target attack resolves without losing the player's queued order")
	if resolved:
		var goal:Vector2=ship.orders[0].pos
		check(sim.terrain.traversable(goal,"sea",float(sim.definitions.boat.radius)),"resolved firing position fits the attacking ship")
		check(goal.distance_to(enemy.pos)<=sim.horizontal_reach("boat",enemy,sim.unit_altitude(ship))*0.9,"resolved command can engage the current observed target position")

func _init()->void:
	real_formation_equivalence()
	formation_continuation_and_invalidation()
	real_attack_equivalence()
	attack_continuation_and_wrecks()
	moving_observation_and_claims()
	queued_attack_tracks_observed_motion()
	print("TACTICAL NAVIGATION: %d checks, %d failures"%[checks,failures])
	quit(1 if failures>0 else 0)
