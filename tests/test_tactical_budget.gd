extends SceneTree

const Budget=preload("res://scripts/tactical_work_budget.gd")
const Sim=preload("res://scripts/simulation.gd")
const Terrain=preload("res://scripts/terrain.gd")
const Cover=preload("res://scripts/cover_behavior.gd")
const Director=preload("res://scripts/tactical_director.gd")

# Controlled path failures expose candidates beyond the first tick's quota.
class CandidateTerrain extends BattleTerrain:
	var tried:Array=[]
	var allow_after:=1
	func traversable(_p:Vector2,_domain:String,_radius:float=-1,_pressed:Array=[],_profile:String="")->bool:return true
	func cover(_p:Vector2,_crush:bool=false)->bool:return true
	func path(_from:Vector2,to:Vector2,_domain:String,_radius:float=-1,_avoid:Array=[],_profile:String="default")->Array[Vector2]:
		tried.append(to)
		var route:Array[Vector2]=[]
		if tried.size()>=allow_after:route.append(to)
		return route

var checks:=0
var failures:=0

func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func admission_and_service() -> void:
	var budget=Budget.new()
	budget.begin_tick(1,{"routes":1})
	check(budget.request("routes",1,"move"),"first route admitted")
	check(not budget.request("routes",2,"move"),"route quota defers another owner")
	budget.begin_tick(1,{"routes":1})
	check(not budget.request("routes",3,"move"),"same-tick reset cannot replenish quota")
	budget.begin_tick(2,{"routes":1})
	check(not budget.request("routes",1,"move"),"new low-id work yields to older owner")
	check(budget.request("routes",2,"move"),"old ordinary route gets next service")
	check(int(budget.snapshot().used.routes)==1,"route count never exceeds declared limit")
	budget.cancel_owner(3)
	check(int(budget.snapshot().cancelled)==1,"replacement cancels obsolete pending work")
	budget.cancel_request("routes",1,"unrelated")
	check(int(budget.snapshot().pending)==1,"per-task cancellation cannot remove a different request")
	budget.cancel_request("routes",1,"move")
	check(int(budget.snapshot().pending)==0 and int(budget.snapshot().cancelled)==2,"finished task releases only its own pending slot")
	budget.request("routes",5,"stale")
	budget.begin_tick(80,{"routes":1})
	check(int(budget.snapshot().expired)==1 and int(budget.snapshot().pending)==0,"unvisited old requests expire with diagnostics")
	budget.end_tick()
	check(budget.request("routes",4,"load") and int(budget.snapshot().pending)==0,"load/tool calls are synchronous outside a tick")

	var fair=Budget.new()
	var served:Dictionary={}
	for tick in range(1,8):
		fair.begin_tick(tick,{"cover":1})
		for owner in range(1,7):
			if fair.request("cover",owner,"member"):served[owner]=tick
		check(int(fair.snapshot().used.get("cover",0))<=1,"cover bundles bounded on tick %d"%tick)
	check(served.size()==6,"fixed visitation order does not starve later owners")
	var urgent=Budget.new()
	urgent.begin_tick(0,{"decisions":0})
	urgent.request("decisions",1000,"ordinary")
	var ordinary_at:=-1
	for tick in range(1,14):
		urgent.begin_tick(tick,{"decisions":1})
		urgent.request("decisions",tick,"fresh urgent",2)
		if urgent.request("decisions",1000,"ordinary"):
			ordinary_at=tick
			break
	check(ordinary_at>0 and ordinary_at<=10,"aged ordinary request survives continuous urgent arrivals")
	var abandoned=Budget.new()
	abandoned.begin_tick(0,{"regroup":0})
	abandoned.request("regroup",1,"no longer needed")
	abandoned.begin_tick(1,{"regroup":1})
	check(not abandoned.request("regroup",2,"active"),"previous-tick requester retains its fair service opportunity")
	abandoned.begin_tick(2,{"regroup":1})
	check(abandoned.request("regroup",2,"active"),"unvisited stale request cannot monopolize capacity until lease expiry")

func field():
	var sim=Sim.new(false,0)
	sim.scenario=sim.scenario.duplicate(true)
	sim.scenario.autonomy=true
	sim.terrain.style="showcase"
	sim.terrain.dynamic_blocks.append(Rect2(8,35,8,6))
	sim.terrain.rubble=Rect2()
	return sim

func pending_cover_and_pressure() -> void:
	var sim=field()
	var squad:Dictionary=sim.spawn("rifle",0,Vector2(18,44))
	var enemy:Dictionary=sim.spawn("rifle",1,Vector2(19,31))
	sim.update_visibility()
	var member:Dictionary=squad.members[0]
	member.cover_until=7.0
	var before:Dictionary=member.duplicate(true)
	var paths:int=sim.terrain.path_calls
	sim.terrain.planning.begin_tick(1,{"cover":0})
	var delayed:Dictionary=Cover.find_slot(squad,member,sim,enemy,[enemy])
	check(delayed.get("pending",false),"cover deferral explicitly reports pending")
	check(member==before and sim.terrain.path_calls==paths,"deferred search preserves shelter/readiness and performs no path query")
	sim.terrain.planning.begin_tick(2,{"cover":1})
	var result:Dictionary=Cover.find_slot(squad,member,sim,enemy,[enemy])
	check(not result.get("pending",false) and result.has("pos"),"same cover request can complete when admitted")
	check(sim.terrain.path_calls-paths<=6,"cover admission bounds the route shortlist")
	sim.terrain.planning.end_tick()

	var pressured=Sim.new(false,0)
	pressured.scenario=pressured.scenario.duplicate(true)
	pressured.scenario.autonomy=true
	var force:Dictionary=pressured.spawn("rifle",0,Vector2(18,55))
	var threat:Dictionary=pressured.spawn("rifle",1,Vector2(18,43))
	pressured.update_visibility()
	check(pressured.issue([force.id],Vector2(26,55),"attack_move")==1,"pressure fixture receives objective")
	check(Director.plan(pressured,force,Vector2(22,55),"FLANK","Fixture flank"),"pressure fixture starts temporary advance")
	var version:int=force.order_version
	var assignment:int=force.assignment.id
	force.suppression=0.95
	pressured.terrain.planning.begin_tick(3,{"routes":0,"formation":0})
	check(Director.pressure_response(pressured,force),"known severe pressure triggers immediate response")
	check(force.maneuver.get("phase","")=="PRESSURE_WAIT" and force.maneuver.arrived and force.path.is_empty(),"denied withdrawal planning stops stale flank immediately")
	check(force.order_version==version and force.assignment.id==assignment and not force.orders.is_empty(),"pending safety response preserves objective ownership")
	check(pressured.actions.active(force,"movement").is_empty(),"unsafe movement reservation is released while pending")
	pressured.terrain.planning.end_tick()
	force.suppression=0.0
	Director.pressure_response(pressured,force)
	check(force.maneuver.is_empty() and force.order_version==version and not force.path.is_empty(),"eased danger resumes the same objective")
	pressured.stop([force.id])
	force.suppression=0.95
	force.pressure_review=0.0
	Director.pressure_response(pressured,force)
	check(force.hold_command and force.maneuver.is_empty(),"hard Hold remains fixed under pressure")
	check(not threat.is_empty(),"pressure threat exists")
	# Exercise the live typed formation adapter after admission, as well as the
	# denied path above. A direct helper call alone misses dynamic-call errors.
	pressured.stop([force.id])
	force.hold_command=false
	force.pressure_review=0.0
	pressured.rebuild_spatial()
	pressured.ticking=true
	pressured.terrain.planning.begin_tick(4,{"routes":1,"formation":1})
	Director.pressure_response(pressured,force)
	check(force.maneuver.get("phase","")=="WITHDRAW" and not force.path.is_empty(),"admitted live withdrawal completes formation adapter and retains a physical route")
	pressured.terrain.planning.end_tick()
	pressured.ticking=false

func incremental_projection() -> void:
	var terrain=Terrain.new(0,{"size":[48,48],"port":false,"blocks":[[20,0,1,30]],"woods":[],"objectives":[],"rubble":[0,0,0,0],"mud":[0,0,0,0]})
	var from:=Vector2(7,10)
	var desired:=Vector2(21.2,10)
	terrain.path_probe=true
	var expected:Vector2=terrain.reachable_destination(from,desired,"land",2.65,"infantry")
	var state:Dictionary={}
	var previous_queries:=0
	var steps:=0
	while not state.get("done",false) and steps<400:
		terrain.reachable_destination_step(from,desired,"land",2.65,"infantry",state,1,8)
		check(int(state.queries)-previous_queries<=1,"projection performs at most one connectivity query per step")
		previous_queries=int(state.queries)
		steps+=1
	check(state.done and state.pos==expected and expected.x>=0,"incremental projection preserves synchronous candidate choice")
	check(steps>1,"tight destination is resolved across bounded steps")
	var changed:Dictionary={}
	terrain.reachable_destination_step(from,desired,"land",2.65,"infantry",changed,1,1)
	check(not changed.done and int(changed.index)==1,"partial projection exposes pending rather than failure")
	terrain.geometry_version+=1
	terrain.reachable_destination_step(from,desired,"land",2.65,"infantry",changed,1,1)
	check(int(changed.index)==1,"geometry change restarts projection from its first candidate")

func bounded_candidate_bundles() -> void:
	var sim=Sim.new(false,0)
	var u:Dictionary=sim.spawn("rifle",0,Vector2(20,50))
	sim.terrain=CandidateTerrain.new(0)
	var terrain:CandidateTerrain=sim.terrain
	terrain.allow_after=9
	sim.ticking=true
	terrain.planning.begin_tick(1,{"routes":0})
	check(Director.bound_destination(sim,u).is_empty() and terrain.tried.is_empty(),"denied bound bundle performs no candidate route search")
	check(u.bound_check==sim.time and u.contact_review==sim.time,"denied bound retries without a failed-search delay")
	terrain.planning.begin_tick(2,{"routes":1})
	var bound:Dictionary=Director.bound_destination(sim,u)
	check(not bound.is_empty() and terrain.tried.size()==9,"one admitted bound bundle reaches a legal ninth candidate")
	check(int(terrain.planning.snapshot().used.routes)==1,"bound search consumes one declared finite bundle")
	check(not bound.is_empty() and is_equal_approx(bound.pos.distance_to(u.pos),11.0),"bound preserves ring order before choosing the later reachable anchor")
	terrain.tried.clear();terrain.allow_after=99
	terrain.planning.begin_tick(3,{"routes":1})
	check(Director.bound_destination(sim,u).is_empty() and terrain.tried.size()==21,"unreachable bound exhausts at most twenty-one candidate routes")
	terrain.tried.clear();terrain.allow_after=2
	terrain.planning.begin_tick(4,{"routes":1})
	var flank:Dictionary=Director.flank_choice(sim,u,u.pos+Vector2(20,0),[])
	check(not flank.is_empty() and terrain.tried.size()==2 and flank.pos==terrain.tried[1],"one admitted flank bundle can choose the reachable second side")
	check(int(terrain.planning.snapshot().used.routes)==1,"flank comparison consumes one declared finite bundle")
	terrain.tried.clear()
	terrain.planning.begin_tick(5,{"routes":0})
	check(Director.flank_choice(sim,u,u.pos+Vector2(20,0),[]).is_empty() and terrain.tried.is_empty(),"denied flank bundle performs no candidate route search")
	check(u.next_decision==sim.time,"denied flank preserves an immediate retry")
	terrain.planning.end_tick()
	sim.ticking=false

func _init() -> void:
	admission_and_service()
	pending_cover_and_pressure()
	incremental_projection()
	bounded_candidate_bundles()
	print("TACTICAL BUDGET: %d checks, %d failures"%[checks,failures])
	quit(1 if failures>0 else 0)
