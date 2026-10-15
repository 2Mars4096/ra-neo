extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
var failures:Array[String]=[]
var checks:=0
func check(value:bool,message:String) -> void:
	checks+=1
	if not value:
		failures.append(message)
		printerr("FAIL: ",message)
func _init() -> void:
	var sim=Sim.new(false,0)
	var rifle=sim.spawn("rifle",0,Vector2(20,55))
	var enemy=sim.spawn("rifle",1,Vector2(25,55))
	sim.update_visibility()
	check(sim.can_fire(rifle,enemy),"contact can be engaged before withdrawal")
	check(sim.retreat([rifle.id])==1,"retreat accepted")
	check(not sim.can_fire(rifle,enemy),"retreat sacrifices firepower")
	sim.stop([rifle.id])
	check(sim.can_fire(rifle,enemy),"stop cancels retreat and restores fire")
	enemy.hp=0
	rifle.pos=Vector2(15,61)
	rifle.hp=80
	sim.time=20
	sim.credits=10
	sim.update_tactics(1)
	check(is_equal_approx(rifle.hp,86) and is_equal_approx(sim.credits,8.5),"safe recovery heals and charges supply")
	rifle.last_hit=sim.time
	sim.update_tactics(1)
	check(is_equal_approx(rifle.hp,86),"recent damage prevents repair")
	rifle.last_hit=-100
	sim.credits=0
	sim.update_tactics(1)
	check(is_equal_approx(rifle.hp,86),"no free repair without supply")
	var capture=Sim.new(false,0)
	var squad=capture.spawn("rifle",0,Vector2(46,25))
	squad.suppression=1
	capture.update_objectives(5)
	check(capture.objectives[0].progress==0,"pinned section cannot capture")
	squad.suppression=0
	capture.update_objectives(5)
	check(capture.objectives[0].progress==5,"recovered section captures")
	var ai=Sim.new(false,0)
	var defender=ai.spawn("tank",1,Vector2(10,45))
	var scout=ai.spawn("rifle",0,Vector2(10,15))
	ai.update_visibility()
	ai.update_tactics(4)
	check(defender.orders.is_empty(),"AI does not react to hidden contact")
	scout.pos=Vector2(10,21)
	# A visible contact beyond weapon range should trigger a response.
	ai.spawn("drone",1,Vector2(10,25))
	ai.update_visibility()
	ai.update_tactics(4)
	check(not defender.orders.is_empty(),"AI responds to team-observed contact")
	defender.hp=100
	ai.update_tactics(4)
	check(not defender.orders.is_empty() and defender.orders[0].mode=="retreat","damaged defender withdraws")
	var withdrawal=Sim.new(false,0)
	var first=withdrawal.spawn("rifle",0,Vector2(12,45))
	var second=withdrawal.spawn("rifle",0,Vector2(18,45))
	check(withdrawal.retreat([first.id,second.id])==2,"group retreat accepts both sections")
	check(first.orders[0].pos.distance_to(second.orders[0].pos)>3.6,"retreat reserves separate destinations")
	for i in 200:withdrawal.tick(0.1)
	check(first.orders.is_empty() and second.orders.is_empty(),"group withdrawal reaches staging area")
	print("TACTICS TESTS: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
