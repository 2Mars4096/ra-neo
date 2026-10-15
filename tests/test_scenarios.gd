extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
func _init() -> void:
	var results:Array=[]
	for preset in 3:results.append(run_scenario(preset))
	FileAccess.open("res://artifacts/scenarios.json",FileAccess.WRITE).store_string(JSON.stringify(results,"  "))
	var passed:bool=results.all(func(r):return r.result=="VICTORY")
	print("SCENARIO TESTS: ","PASS" if passed else "FAIL:",results)
	quit(0 if passed else 1)

func run_scenario(preset:int) -> Dictionary:
	var sim=Sim.new(true,preset)
	var next_order:=0.0
	var stages: Array=[]
	while sim.time<480 and sim.result=="":
		if sim.time>=next_order:
			next_order=sim.time+6
			var objective:Vector2=sim.objectives[0].pos if sim.objectives[0].owner!=0 else sim.objectives[1].pos
			var ids:Array=[]
			for u in sim.living(0):
				if u.kind=="drone":
					sim.issue([u.id],objective+Vector2(-9,8))
				elif u.kind=="boat":
					sim.issue([u.id],Vector2(87,43),"attack_move")
				else:
					ids.append(u.id)
			sim.issue(ids,objective,"attack_move")
			if sim.credits>=220:
				sim.recruit("tank")
			elif sim.living(0).filter(func(u):return u.kind=="rifle").size()<2:
				sim.recruit("rifle")
			stages.append({"time":int(sim.time),"friendly":sim.living(0).size(),"enemy":sim.living(1).size(),"relay":sim.objectives[0].progress,"harbor":sim.objectives[1].progress,"supply":int(sim.credits)})
		sim.tick(0.1)
		sim.events.clear()
	var report={"result":sim.result,"seconds":sim.time,"kills":sim.kills,"losses":sim.losses,"stages":stages,"policy":"Every 6 seconds: attack-move land force to first unsecured objective; scout nearby; corvette at coast; buy tank when funded, replace rifle sections."}
	return {"scenario":sim.scenario.name,"result":sim.result,"seconds":sim.time,"kills":sim.kills,"losses":sim.losses}
