extends RefCounted
# Optional, data-driven infrastructure rules. Maps without an operation block
# keep their original field-operations economy and victory requirements.

static func config(sim)->Dictionary:
	return sim.scenario.get("operation",{})

static func secured(sim,index:int)->bool:
	if index<0 or index>=sim.objectives.size():return false
	var objective:Dictionary=sim.objectives[index]
	return objective.owner==0 and not objective.get("enemy_present",false)

static func all_secured(sim,indices:Array)->bool:
	return not indices.is_empty() and indices.all(func(index):return secured(sim,int(index)))

static func income_bonus(sim)->float:
	var bonus:=0.0
	for facility in config(sim).get("facilities",[]):
		if facility.get("requires_naval_control",false) and not naval_ready(sim):continue
		if secured(sim,int(facility.objective)):bonus+=float(facility.get("income",0.0))
	return bonus

# Captured infrastructure may receive the same off-map reinforcements as an
# engineer's forward supply point. FieldOps.deploy still requires a safe entry
# and an actual route from the original insertion for the purchased unit.
static func forward_point(sim)->Vector2:
	var facilities:Array=config(sim).get("facilities",[])
	for index in range(facilities.size()-1,-1,-1):
		var facility:Dictionary=facilities[index]
		if not facility.has("forward_position") or not secured(sim,int(facility.objective)):continue
		if facility.get("requires_naval_control",false) and not naval_ready(sim):continue
		var position:Array=facility.forward_position
		return Vector2(float(position[0]),float(position[1]))
	return Vector2(-1,-1)

# These are authored routes, not physical links between adjacent maps. Cutting
# them prevents dispatch; forces already present keep their orders and health.
static func enemy_routes_open(sim)->bool:
	var denied:Array=config(sim).get("deny_reserve_objectives",[])
	return not all_secured(sim,denied)

static func reserve_delay(sim)->float:
	return float(config(sim).get("reserve_delay",12.0))+maxf(0.0,float(sim.field_ops.get("reserve_delay_bonus",0.0)))

static func naval_ready(sim)->bool:
	var zone:Dictionary=config(sim).get("naval_zone",{})
	if zone.is_empty():return true
	var prerequisites:Array=zone.get("requires_objectives",[])
	if not prerequisites.is_empty() and not all_secured(sim,prerequisites):return false
	var position:Array=zone.position
	var center:=Vector2(float(position[0]),float(position[1]))
	var radius_squared:float=pow(float(zone.radius),2)
	var friendly:=false
	for unit in sim.units:
		if not sim.alive(unit) or unit.get("combat_ineffective",false) or sim.definitions[unit.kind].domain!="sea":continue
		if unit.pos.distance_squared_to(center)>radius_squared:continue
		# Actual zone control uses physical presence, like land capture. UI never
		# identifies an unseen opponent or leaks its position through this check.
		if unit.team==1:return false
		if unit.team==0 and unit.suppression<=0.6 and (unit.orders.is_empty() or unit.orders[0].mode!="retreat"):
			friendly=true
	return friendly

static func hold_ready(sim)->bool:
	return naval_ready(sim)

static func status(sim)->String:
	var details:PackedStringArray=[]
	var bonus:=income_bonus(sim)
	if bonus>0:details.append("Logistics +%g/s"%bonus)
	if not enemy_routes_open(sim):details.append("Enemy route cut")
	if config(sim).has("naval_zone"):
		details.append("Sea lane secured" if naval_ready(sim) else "Sea lane unsecured")
	return " · ".join(details)

static func brief(scenario:Dictionary)->String:
	return str(scenario.get("operation",{}).get("brief",""))
