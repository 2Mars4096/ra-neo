extends SceneTree
const Sim=preload("res://tests/reachable_attack_probe.gd")
const C=preload("res://scripts/classic.gd")
func _init()->void:
	var sim=Sim.new(true,4)
	var builds:=["refinery","power","barracks","factory"]
	var clock:=0.0
	for frame in (3500 if "--diagnose" in OS.get_cmdline_user_args() else 9000):
		if frame%500==0:print("PROGRESS ",sim.time," funds ",sim.credits," bases ",C.structures(sim,0,"",false).size(),"/",C.structures(sim,1,"",false).size()," units ",sim.units.size())
		sim.tick(0.1)
		clock-=0.1
		if clock<=0:
			clock=4
			for kind in builds:
				if C.structures(sim,0,kind,false).is_empty():
					var site:Vector2=C.find_site(sim,kind,0)
					if site.x>=0:C.build(sim,kind,0,site)
					break
			var established:bool=not C.structures(sim,0,"factory").is_empty()
			if C.committed_count(sim,"harvester",0)<1:C.enqueue(sim,"harvester")
			if C.committed_count(sim,"drone",0)==0:C.enqueue(sim,"drone")
			C.enqueue(sim,"tank")
			if established and sim.credits>220:C.enqueue(sim,"atgm")
			var ids:Array=sim.living(0).filter(func(u):return not sim.definitions[u.kind].get("structure",false) and u.kind not in ["harvester","drone"]).map(func(u):return u.id)
			for scout in sim.living(0).filter(func(u):return u.kind=="drone"):
				if scout.orders.is_empty():sim.issue([scout.id],Vector2(68,9))
			if sim.time>0:
				var targets:Array=C.structures(sim,1,"",false).filter(func(u):return u.visible)
				for id in ids:
					var unit:Dictionary=sim.get_unit(id)
					var goal:Vector2=Vector2(16+6*(int(id)%3),29) if sim.time<180 else Vector2(58,43)
					if not unit.orders.is_empty() and (unit.orders[0].mode=="attack" or unit.get("policy_goal",Vector2.ZERO)==goal):continue
					unit.policy_goal=goal
					if sim.time>=180 and not targets.is_empty() and sim.effective_unit(unit,targets[0].kind):sim.issue([id],targets[0].pos,"attack",false,targets[0].id)
					else:sim.issue([id],goal,"attack_move")
		if sim.result!="":break
	if "--diagnose" in OS.get_cmdline_user_args():
		for u in sim.units:
			if sim.alive(u):print("UNIT ",u.id," team",u.team," ",u.kind," ",u.pos," orders ",u.orders," path ",u.path," cargo ",u.get("cargo",0)," reason ",u.reason," blocked ",u.blocked_time," queue ",u.get("queue",[]))
	var report:={"result":sim.result,"time":sim.time,"credits":sim.credits,"enemy_credits":sim.classic.enemy_credits,"friendly_structures":C.structures(sim,0,"",false).size(),"enemy_structures":C.structures(sim,1,"",false).size(),"kills":sim.kills,"losses":sim.losses}
	FileAccess.open("res://artifacts/classic-reachable-probe.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("CLASSIC MISSION: ",JSON.stringify(report))
	quit(0 if sim.result=="VICTORY" else 1)
