extends SceneTree

# Regression cases for accepted backup ownership crossing queued/provisional
# player commands. The broker and ordinary order executors both run here.
const Sim=preload("res://scripts/simulation.gd")
const Support=preload("res://scripts/support_requests.gd")
const DT:=1.0/30.0
var checks:=0
var failures:=0

func _init()->void:call_deferred("run")

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func step_broker(sim,seconds:float=0.3,deny_placement:bool=false)->void:
	sim.time+=seconds
	sim.action_tick+=1
	sim.route_budget=sim.ROUTE_BUDGET
	sim.actions.begin_tick(sim.action_tick)
	if deny_placement:
		sim.terrain.planning.begin_tick(sim.action_tick,{"formation":0})
		sim.resolve_slots()
	Support.tick(sim,seconds)
	if deny_placement:sim.terrain.planning.end_tick()

func fixture()->Dictionary:
	var sim=Sim.new(false,0)
	sim.scenario=sim.scenario.duplicate(true)
	sim.scenario.autonomy=true
	sim.scenario.jam_radius=0.0
	sim.enemy_clock=100000.0
	sim.tactical_clock=100000.0
	sim.terrain.style="showcase"
	var sender:Dictionary=sim.spawn("rifle",0,Vector2(20,54))
	var reserve:Dictionary=sim.spawn("rifle",0,Vector2(12,66))
	sim.stop([sender.id,reserve.id])
	Support.set_reserve(sim,[reserve.id],true)
	Support.request_backup(sim,[sender.id])
	step_broker(sim)
	var request:Dictionary=Support.request_for(sim,sender)
	for attempt in 12:
		step_broker(sim)
		if request.phase=="en_route":break
	check(request.phase=="en_route" and not reserve.path.is_empty(),"fixture receives an actual support route")
	return {"sim":sim,"sender":sender,"reserve":reserve,"request":request}

func move_section(unit:Dictionary,point:Vector2)->void:
	var delta:Vector2=point-unit.pos
	unit.pos=point
	for member in unit.members:member.pos+=delta;member.travel=0.0

func queued_head_activates(deferred:bool)->void:
	var f:=fixture()
	var sim=f.sim
	var unit:Dictionary=f.reserve
	var request:Dictionary=f.request
	var old_assignment:int=unit.assignment.id
	var destination:=Vector2(24,66)
	if deferred:sim.click_slots=0
	check(sim.issue([unit.id],destination,"move",true)==1,"queued head is accepted for "+("deferred" if deferred else "immediate")+" placement")
	if deferred:
		check(unit.orders[0].has("slot") and unit.assignment.id==old_assignment and request.phase=="en_route","unresolved queued head preserves the live backup assignment")
		sim.resolve_slots()
	step_broker(sim)
	check(unit.assignment.id!=old_assignment and unit.assignment.mode=="move" and unit.assignment.pos==destination,"queued head activates its own accepted movement assignment")
	check(request.phase=="cancelled" and not Support.owns_maneuver(unit),"activating a queued head revokes the old backup lease")
	check(not unit.reserve_enabled,"activating a queued head revokes reserve delegation")
	check(unit.maneuver.is_empty() and sim.actions.active(unit,"support").is_empty(),"queued head leaves no old backup maneuver or support action")
	check(not unit.path.is_empty() and unit.path.back()==destination,"queued head retains its own validated route")
	# A stale BACKUP maneuver makes finish_order mark that maneuver arrived
	# forever instead of completing the newly accepted player command.
	for tick in 600:
		sim.tick(DT)
		if unit.orders.is_empty():break
	check(unit.pos.distance_to(destination)<=1.0 and unit.orders.is_empty(),"queued head physically arrives and completes through the ordinary executor")

func rejected_queued_head()->void:
	var f:=fixture()
	var sim=f.sim
	var unit:Dictionary=f.reserve
	var route:Array=unit.path.duplicate()
	var assignment:Dictionary=unit.assignment.duplicate(true)
	sim.click_slots=0
	check(sim.issue([unit.id],Vector2(98,66),"move",true)==1 and unit.orders[0].has("slot"),"queued invalid destination awaits placement")
	sim.resolve_slots()
	check(unit.orders.is_empty() and unit.assignment==assignment,"rejected queued head preserves the original assignment")
	check(f.request.phase=="en_route" and Support.owns_maneuver(unit) and unit.reserve_enabled,"rejected queued head preserves backup and reserve authority")
	check(unit.path==route and unit.maneuver.get("support_request",-1)==f.request.id,"rejected queued head preserves the active support route")
	step_broker(sim)
	check(f.request.phase=="en_route" and sim.actions.valid(unit,sim.actions.active(unit,"support"),sim.time),"rejected queued head keeps a valid support action")

func genuine_queued_tail()->void:
	var f:=fixture()
	var sim=f.sim
	var unit:Dictionary=f.reserve
	check(sim.issue([unit.id],Vector2(24,66))==1,"ordinary movement can replace support before future delegation")
	check(Support.set_reserve(sim,[unit.id],true)==1,"a busy section can be delegated for future reserve duty")
	var assignment:Dictionary=unit.assignment.duplicate(true)
	check(sim.issue([unit.id],Vector2(30,66),"move",true)==1 and unit.orders.size()==2,"a genuine queued tail stays behind the active order")
	check(unit.reserve_enabled and unit.assignment==assignment,"queuing a future order does not prematurely revoke delegation or its active assignment")
	move_section(unit,unit.orders[0].pos)
	sim.finish_order(unit)
	check(not unit.reserve_enabled and unit.assignment.id!=assignment.id and unit.assignment.pos==Vector2(30,66),"queued tail revokes delegation when it actually activates")

func pending_route_is_paused(queued:bool)->void:
	var f:=fixture()
	var sim=f.sim
	var unit:Dictionary=f.reserve
	var request:Dictionary=f.request
	var route:Array=unit.path.duplicate()
	var assignment:Dictionary=unit.assignment.duplicate(true)
	sim.click_slots=0
	sim.issue([unit.id],Vector2(98,66),"move",queued)
	for tick in 21:step_broker(sim,0.3,true)
	check(unit.orders[0].has("slot") and unit.assignment==assignment,"denied formation work leaves replacement provisional")
	check(request.phase=="en_route" and Support.owns_maneuver(unit),"placement delay does not misreport the parked support route as blocked")
	check(sim.actions.valid(unit,sim.actions.active(unit,"support"),sim.time),"parked support retains its live exclusive action")
	sim.resolve_slots()
	check(unit.orders.is_empty() and unit.path==route and unit.maneuver.get("support_request",-1)==request.id,"rejection resumes the still-owned support route")
	step_broker(sim)
	check(request.phase=="en_route","resumption excludes placement waiting from the no-progress timeout")

func pending_delivery_is_paused(queued:bool)->void:
	var f:=fixture()
	var sim=f.sim
	var unit:Dictionary=f.reserve
	var request:Dictionary=f.request
	move_section(unit,request.position)
	step_broker(sim)
	check(request.phase=="delivering" and Support.useful(sim,unit,request),"fixture reaches an actually useful supporting position")
	var delivered:float=request.service_time
	sim.click_slots=0
	sim.issue([unit.id],Vector2(98,66),"move",queued)
	for tick in 8:step_broker(sim,0.3,true)
	check(request.phase=="delivering" and is_equal_approx(request.service_time,delivered),"parked delivery does not accrue service while a replacement is unresolved")
	sim.resolve_slots()
	step_broker(sim)
	check(request.phase=="delivering" and request.service_time>delivered and request.service_time<=delivered+0.5,"rejected replacement resumes useful service without crediting the paused interval")

func parked_terminal_cleanup(expiry:bool)->void:
	var f:=fixture()
	var sim=f.sim
	var unit:Dictionary=f.reserve
	var request:Dictionary=f.request
	var home:Vector2=unit.pos
	var assignment:Dictionary=unit.assignment.duplicate(true)
	sim.click_slots=0
	sim.issue([unit.id],Vector2(98,66))
	if expiry:step_broker(sim,Support.LEASE_SECONDS+0.1,true)
	else:check(sim.stop([f.sender.id])==1,"requester can cancel while provider placement is unresolved")
	step_broker(sim,0.3,true)
	var expected:String="expired" if expiry else "cancelled"
	check(request.phase==expected and not Support.owns_maneuver(unit),"parked support honors "+expected+" without renewing its lease")
	check(sim.actions.active(unit,"support").is_empty() and sim.actions.active(unit,"movement").is_empty(),"terminal parked support releases both action channels")
	sim.resolve_slots()
	check(unit.orders.is_empty() and unit.assignment==assignment,"rejection after "+expected+" restores the accepted parent assignment")
	check(unit.maneuver.is_empty() and unit.path.is_empty() and unit.hold_command,"rejected rollback cannot resurrect a "+expected+" support maneuver")
	for tick in 10:sim.tick(DT)
	check(unit.pos.distance_to(home)<0.1 and unit.maneuver.is_empty(),"terminal support remains at its authorized home after rollback")

func run()->void:
	queued_head_activates(false)
	queued_head_activates(true)
	rejected_queued_head()
	genuine_queued_tail()
	for queued in [false,true]:
		pending_route_is_paused(queued)
		pending_delivery_is_paused(queued)
	parked_terminal_cleanup(false)
	parked_terminal_cleanup(true)
	print("SUPPORT LIFECYCLE: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
