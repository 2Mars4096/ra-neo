extends SceneTree

const Sim=preload("res://scripts/simulation.gd")
const Terrain=preload("res://scripts/terrain.gd")
const Director=preload("res://scripts/tactical_director.gd")
const Infantry=preload("res://scripts/infantry.gd")
var checks:=0
var failures:=0

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func field():
	var sim=Sim.new(false,0)
	sim.scenario=sim.scenario.duplicate(true)
	sim.scenario.autonomy=true
	sim.terrain=Terrain.new(0,{"size":[96,72],"port":false,"blocks":[],"woods":[],"objectives":[],"rubble":[0,0,0,0],"mud":[0,0,0,0]})
	return sim

func unsafe_rally()->void:
	var sim=field()
	var squad:Dictionary=sim.spawn("rifle",0,Vector2(15,35))
	var threat:Dictionary=sim.spawn("rifle",1,Vector2(15,45))
	check(sim.issue([squad.id],Vector2(22,35),"attack_move")==1,"unsafe-rally fixture accepts its objective")
	check(Director.plan(sim,squad,Vector2(21,35),"FLANK","Fixture flank"),"unsafe-rally fixture has an active advance")
	var previous:Dictionary=sim.actions.active(squad,"movement")
	var version:int=squad.order_version
	var assignment:int=squad.assignment.id
	var order:Dictionary=squad.orders[0].duplicate(true)
	squad.suppression=0.95
	threat.seen_by[0]=false
	var paths:int=sim.terrain.path_calls
	check(not Director.pressure_response(sim,squad) and squad.maneuver.phase=="FLANK","unobserved threat cannot trigger a withdrawal")
	check(sim.terrain.path_calls==paths,"unobserved threat consumes no withdrawal planning")
	threat.seen_by[0]=true
	squad.pressure_review=0.0
	var rally:Vector2=sim.rally_point(squad)
	check(rally.distance_to(threat.pos)>squad.pos.distance_to(threat.pos),"far rally endpoint alone appears safer")
	check(sim.terrain.segment_clear(squad.pos,rally,"land",float(sim.definitions.rifle.radius)),"unsafe-rally fixture has a straight physical route through the threat")
	sim.rebuild_spatial();sim.ticking=true
	sim.terrain.planning.begin_tick(1,{"routes":1,"formation":1})
	Director.pressure_response(sim,squad)
	check(squad.maneuver.get("phase","")=="PRESSURE_WAIT" and squad.path.is_empty(),"unsafe rally halts the old advance without moving toward the threat")
	check(not squad.pressure_pending,"a rejected route is distinct from planning denial")
	check(previous.phase=="cancelled" and previous.reason=="urgent_withdrawal","urgent response immediately cancels the stale advance")
	check(squad.order_version==version and squad.assignment.id==assignment and squad.orders[0]==order,"route rejection preserves the player's accepted assignment")
	check(sim.actions.active(squad,"movement").is_empty() and not sim.actions.actions.values().any(func(action):return action.kind=="withdraw"),"an invalid candidate creates no completed withdrawal action")
	sim.terrain.planning.end_tick();sim.ticking=false
	paths=sim.terrain.path_calls
	sim.time=0.4
	Director.pressure_response(sim,squad)
	check(sim.terrain.path_calls==paths,"an unsafe route backs off while local cover remains available")
	var retry:float=squad.pressure_route_after
	sim.time=0.5;squad.fired_on=sim.time;squad.pressure_review=0.0
	Director.pressure_response(sim,squad)
	check(sim.terrain.path_calls>paths and float(squad.pressure_route_after)>retry,"fresh incoming fire invalidates an old unsafe-route backoff")
	squad.suppression=0.0
	Director.pressure_response(sim,squad)
	check(squad.maneuver.is_empty() and squad.orders[0]==order and not squad.path.is_empty(),"eased pressure resumes the same accepted objective")

func safe_withdrawal_and_hold()->void:
	var sim=field()
	var squad:Dictionary=sim.spawn("rifle",0,Vector2(18,55))
	var threat:Dictionary=sim.spawn("rifle",1,Vector2(18,43))
	threat.seen_by[0]=true
	squad.suppression=0.95
	Director.pressure_response(sim,squad)
	check(squad.maneuver.get("phase","")=="WITHDRAW" and not squad.path.is_empty(),"known pressure can still select a safe rally route")
	check(sim.actions.active(squad,"movement").kind=="withdraw","a real withdrawal retains its executing action")
	sim.stop([squad.id])
	squad.pressure_review=0.0
	var anchor:Vector2=squad.pos
	Director.pressure_response(sim,squad)
	check(squad.hold_command and squad.maneuver.is_empty() and squad.pos==anchor,"hard Hold remains authoritative under the same pressure")
	check(squad.reason=="Hold position · under pressure","hard Hold reports its current pressure")

func casualty_shelter()->void:
	var sim=Sim.new(false,3)
	var squad:Dictionary=sim.spawn("rifle",0,Vector2(40.48081,11.77421))
	var threat:Dictionary=sim.spawn("rifle",1,Vector2(34.41422,24.41421))
	threat.seen_by[0]=true
	var medic:Dictionary=squad.members[0]
	var casualty:Dictionary=squad.members[1]
	medic.pos=Vector2(42.7,12.8)
	casualty.pos=Vector2(42.05,12.7)
	Infantry.wound(squad,casualty,Infantry.SEVERE,sim.time,sim.combat_rng)
	Infantry.wound(squad,squad.members[2],Infantry.KIA,sim.time,sim.combat_rng)
	Infantry.publish(squad)
	squad.last_hit=-100.0
	check(Director.critical_pressure(squad),"one surviving medic recognizes losses against original strength")
	check(sim.terrain.cover(casualty.pos) and sim.terrain.traversable(casualty.pos,"land",0.8),"casualty has real reachable shelter")
	var paths:int=sim.terrain.path_calls
	Director.pressure_response(sim,squad)
	check(squad.maneuver.get("phase","")!="WITHDRAW" and sim.terrain.path_calls==paths,"nearby casualty care is preserved without a new planning search")
	for frame in 270:
		sim.time+=1.0/30.0
		squad.fired_on=sim.time
		Infantry.tick_wounds(squad,sim.time,1.0/30.0,sim)
		Director.pressure_response(sim,squad)
		if casualty.stable:break
	check(casualty.stable and casualty.aid>=Infantry.AID_SECONDS,"the last medic can stabilize a sheltered casualty under known fire")

func depleted_fixture()->Dictionary:
	var sim=field()
	var squad:Dictionary=sim.spawn("rifle",0,Vector2(18,55))
	var threat:Dictionary=sim.spawn("rifle",1,Vector2(18,43))
	for index in [0,1]:Infantry.wound(squad,squad.members[index],Infantry.LIGHT,sim.time,sim.combat_rng)
	Infantry.wound(squad,squad.members[2],Infantry.KIA,sim.time,sim.combat_rng)
	Infantry.publish(squad)
	sim.issue([squad.id],Vector2(25,55),"attack_move")
	threat.seen_by[0]=true
	Director.pressure_response(sim,squad)
	check(Director.critical_pressure(squad) and squad.maneuver.get("phase","")=="WITHDRAW","depleted fixture acknowledges original-strength losses")
	return {"sim":sim,"squad":squad,"threat":threat,"action":sim.actions.active(squad,"movement")}

func resolve_pressure(f:Dictionary)->void:
	f.threat.seen_by[0]=false
	f.sim.time=f.squad.commit_until+1.0
	f.squad.pressure_review=0.0
	Director.pressure_response(f.sim,f.squad)
	check(f.squad.has("pressure_resolved") and f.squad.maneuver.is_empty(),"quiet disengagement records a handled pressure episode")

func episode_and_disengagement()->void:
	var f:=depleted_fixture()
	var sim=f.sim
	var squad:Dictionary=f.squad
	var version:int=squad.order_version
	var assignment:int=squad.assignment.id
	var order:Dictionary=squad.orders[0].duplicate(true)
	f.threat.seen_by[0]=false
	sim.time=squad.commit_until-0.01
	Director.pressure_response(sim,squad)
	check(squad.maneuver.get("phase","")=="WITHDRAW","contact loss does not skip the original withdrawal commitment")
	sim.time=squad.commit_until+0.1
	squad.fired_on=sim.time-1.0
	Director.pressure_response(sim,squad)
	check(squad.maneuver.get("phase","")=="WITHDRAW","recent rounds keep withdrawal active even when the attacker is unseen")
	sim.time+=Director.CONSOLIDATE_QUIET
	sim.terrain.planning.begin_tick(1,{"routes":0})
	check(Director.pressure_response(sim,squad),"quiet disengagement ends this director pass")
	check(f.action.phase=="cancelled" and f.action.reason=="disengaged","early withdrawal exit does not claim a reached rally")
	check(squad.maneuver.is_empty() and squad.has("route_pending") and squad.path.is_empty(),"denied return route remains pending after disengagement")
	check(squad.order_version==version and squad.assignment.id==assignment and squad.orders[0]==order,"disengagement preserves the exact accepted assignment")
	sim.terrain.planning.end_tick()
	var paths:int=sim.terrain.path_calls
	for cycle in 6:
		f.threat.seen_by[0]=cycle%2==0
		sim.time+=0.4
		Director.pressure_response(sim,squad)
	check(Director.critical_pressure(squad) and squad.has("pressure_resolved"),"handled pressure does not erase permanent depletion")
	check(squad.maneuver.is_empty() and sim.terrain.path_calls==paths,"repeated sightings alone cannot restart the same withdrawal")
	sim.stop([squad.id])
	check(squad.has("pressure_resolved"),"replacement commands preserve physical pressure history")

func renewed_pressure()->void:
	for trigger in ["fire","hit","casualty","suppression"]:
		var f:=depleted_fixture()
		resolve_pressure(f)
		var squad:Dictionary=f.squad
		f.threat.seen_by[0]=true
		f.sim.time+=0.4
		match trigger:
			"fire":squad.fired_on=f.sim.time
			"hit":squad.last_hit=f.sim.time
			"casualty":
				Infantry.wound(squad,squad.members[1],Infantry.KIA,f.sim.time,f.sim.combat_rng)
				Infantry.publish(squad)
			"suppression":squad.suppression=0.95
		squad.pressure_review=0.0
		Director.pressure_response(f.sim,squad)
		check(not squad.has("pressure_resolved") and squad.maneuver.get("phase","")=="WITHDRAW","fresh %s rearms emergency response"%trigger)
	for reason in ["Maneuver blocked · resuming objective","Maneuver timed out · resuming objective"]:
		var f:=depleted_fixture()
		Director.resume(f.sim,f.squad,reason)
		check(not f.squad.has("pressure_resolved") and f.action.phase=="failed","failed withdrawal does not acknowledge an unhandled pressure episode")
	var replaced:=depleted_fixture()
	replaced.sim.stop([replaced.squad.id])
	check(not replaced.squad.has("pressure_resolved") and replaced.action.phase=="cancelled","cancelled withdrawal does not acknowledge an unhandled pressure episode")

func idle_arrival()->void:
	for under_fire in [false,true]:
		var sim=field()
		var squad:Dictionary=sim.spawn("rifle",0,Vector2(18,55))
		var threat:Dictionary=sim.spawn("rifle",1,Vector2(18,43))
		for index in [1,2]:Infantry.wound(squad,squad.members[index],Infantry.KIA,sim.time,sim.combat_rng)
		Infantry.publish(squad)
		threat.seen_by[0]=true
		Director.pressure_response(sim,squad)
		var action:Dictionary=sim.actions.active(squad,"movement")
		check(squad.orders.is_empty() and squad.intent.is_empty() and action.get("kind","")=="withdraw","idle section can start an owned withdrawal without a parent order")
		# Stage an actual physical arrival before its minimum commitment ends.
		squad.pos=squad.maneuver.pos;squad.path=[];squad.maneuver.arrived=true
		for member in squad.members:member.pos=squad.pos+member.offset
		threat.seen_by[0]=false
		sim.time=squad.commit_until-0.01
		Director.update(sim)
		check(squad.maneuver.get("phase","")=="WITHDRAW","early idle arrival retains its minimum commitment")
		sim.time=squad.commit_until+1.0
		if under_fire:squad.fired_on=sim.time
		Director.update(sim)
		check(squad.maneuver.is_empty() and action.phase=="completed","idle arrival reaches normal maneuver completion")
		check(squad.has("pressure_resolved")==not under_fire,"only a quiet safe arrival acknowledges the pressure episode")
		check(squad.orders.is_empty() and squad.intent.is_empty(),"idle withdrawal completion invents no parent command")
	var sim=field()
	var squad:Dictionary=sim.spawn("rifle",0,Vector2(18,55))
	var threat:Dictionary=sim.spawn("rifle",1,Vector2(18,43))
	threat.seen_by[0]=true;squad.suppression=0.95
	Director.pressure_response(sim,squad)
	squad.suppression=0.0;threat.seen_by[0]=false
	sim.time=squad.commit_until+1.0
	Director.pressure_response(sim,squad)
	check(not Director.critical_pressure(squad) and squad.maneuver.is_empty() and squad.has("pressure_resolved"),"active withdrawal re-evaluates after pressure drops below its entry threshold")

func _init()->void:
	unsafe_rally()
	safe_withdrawal_and_hold()
	casualty_shelter()
	episode_and_disengagement()
	renewed_pressure()
	idle_arrival()
	print("TACTICAL PRESSURE: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
