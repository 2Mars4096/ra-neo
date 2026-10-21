extends RefCounted
# Ordinary player policy shared in intent with harbor_playthrough.gd's combined
# opening. Public objective positions/ownership, friendly units and supply only;
# this policy never reads hidden enemies or writes authoritative unit/map state.
const MIX:={"combined":["tank","rifle","atgm","tank","rifle","aa"]}
var policy:="combined"
var assigned:Dictionary={}
var purchase_index:=0
var last_goal:=-1
var stats:Dictionary={"orders":0,"sections_ordered":0,"sections_rejected":0,"purchases":{},"spent":0,"purchase_rejections":{}}
var actions:Array=[]
var api_costs:Array=[]

func effective(sim,unit:Dictionary)->bool:
	return sim.alive(unit) and not unit.get("structure",false) and not unit.get("combat_ineffective",false) and not unit.get("mobility_kill",false)

func order(sim,units:Array,goal:Vector2,mode:String="attack_move",force:bool=false)->void:
	var ids:Array=[]
	for unit in units:
		if not effective(sim,unit):continue
		var previous:Dictionary=assigned.get(unit.id,{})
		var changed:bool=previous.is_empty() or Vector2(previous.goal).distance_to(goal)>3.0 or previous.mode!=mode
		var idle:bool=unit.orders.is_empty() and unit.pos.distance_to(goal)>6.0
		var stalled:bool=float(unit.get("blocked_time",0.0))>12.0 and sim.time-float(previous.get("time",-100))>=18
		if force or changed or idle or stalled:
			ids.append(unit.id)
			assigned[unit.id]={"goal":goal,"mode":mode,"time":sim.time}
	if ids.is_empty():return
	var started:=Time.get_ticks_usec()
	var accepted:int=sim.issue(ids,goal,mode)
	api_costs.append({"type":"order","ms":(Time.get_ticks_usec()-started)/1000.0,"sections":ids.size(),"seconds":sim.time})
	stats.orders+=1
	stats.sections_ordered+=accepted
	stats.sections_rejected+=ids.size()-accepted
	actions.append({"seconds":sim.time,"type":"order","mode":mode,"ids":ids,"goal":[goal.x,goal.y],"accepted":accepted})

func play(sim)->void:
	var own:Array=sim.living(0)
	var combat:Array=own.filter(func(unit):return effective(sim,unit) and unit.kind!="engineer" and sim.definitions[unit.kind].domain=="land")
	var goal_index:=1 # Old Town is the nearest public sector to the insertion.
	for candidate in [1,0,2]:
		if sim.objectives[candidate].owner!=0:
			goal_index=candidate
			break
		goal_index=2
	var goal:Vector2=sim.objectives[goal_index].pos
	if goal_index!=last_goal:
		last_goal=goal_index
	# The two sensible policies share navigation and purchase cadence; only
	# reinforcement mix differs. Neither reads hidden enemy positions.
	if policy!="reckless":
		var mix:Array=MIX[policy]
		var committed:int=combat.size()+sim.FieldOps.queue(sim).size()
		while committed<22 and sim.FieldOps.queue(sim).size()<6:
			var kind:String=mix[purchase_index%mix.size()]
			if sim.credits<float(sim.definitions[kind].cost):break
			var started:=Time.get_ticks_usec()
			var bought:bool=sim.recruit(kind)
			api_costs.append({"type":"purchase","ms":(Time.get_ticks_usec()-started)/1000.0,"seconds":sim.time})
			if not bought:
				var reason:String=sim.field_ops.last_purchase_error
				stats.purchase_rejections[reason]=int(stats.purchase_rejections.get(reason,0))+1
				break
			purchase_index+=1
			committed+=1
			stats.purchases[kind]=int(stats.purchases.get(kind,0))+1
			stats.spent+=int(sim.definitions[kind].cost)
			actions.append({"seconds":sim.time,"type":"purchase","kind":kind,"cost":sim.definitions[kind].cost})
	order(sim,combat,goal)
	# Scouts observe from the approach side; gunships accompany the attack.
	var approach:Vector2=(sim.field_ops.insertion-goal).normalized()
	order(sim,own.filter(func(unit):return unit.kind=="drone"),goal+approach*26,"move")
	order(sim,own.filter(func(unit):return unit.kind=="helo"),goal+approach*12)
	# The public map shows the open western sea and inner-harbor channel.
	# Water waypoints are ordinary orders, not path/position mutations.
	var boats:Array=own.filter(func(unit):return unit.kind=="boat")
	for boat in boats:
		var sea_goal:=Vector2(160,295)
		if boat.pos.y<330:sea_goal=Vector2(330,290)
		if boat.pos.x>300:sea_goal=Vector2(650,285)
		order(sim,[boat],sea_goal)
	if policy=="reckless":
		order(sim,own.filter(func(unit):return unit.kind=="engineer"),goal,"move")
