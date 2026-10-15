extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Art=preload("res://scripts/visuals.gd")
const Motion=preload("res://scripts/unit_animation.gd")
func _init()->void:call_deferred("run")
func run()->void:
	var sim=Sim.new(false,0)
	var tank=sim.spawn("tank",0,Vector2(12,50))
	var first=sim.spawn("tank",1,Vector2(12,40))
	var second=sim.spawn("tank",1,Vector2(19,40))
	sim.update_visibility()
	sim.tick(0.1)
	var lock:int=tank.target
	second.pos=Vector2(12,44)
	sim.tick(0.1)
	assert(tank.target==lock,"valid targets must not flicker as ranges change")
	var stage:=Node3D.new()
	root.add_child(stage)
	var art=Art.new()
	var visual=art.make_unit(stage,tank)
	var model=visual.get_node("Model")
	for i in 90:
		tank.pos+=Vector2(0.02,0)
		sim.time+=1.0/60.0
		Motion.pose(model,tank,sim,1.0/60.0)
		assert(model.position.y==0,"flat-ground chassis must not vibrate")
	first.hp=0
	sim.tick(0.1)
	assert(tank.target==second.id,"destroyed target must release lock")
	stage.free()
	print("STABILITY TESTS: PASS")
	quit()
