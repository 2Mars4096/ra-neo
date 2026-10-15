extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Classic=preload("res://scripts/classic.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)
func _init()->void:call_deferred("run")
func run()->void:
	for scenario in [4]:
		Sim.scenario_selection=scenario
		var battle=load("res://scenes/main.tscn").instantiate();root.add_child(battle)
		battle.set_process(false);battle.set_physics_process(false)
		battle.ui_action("begin",Vector2.ZERO)
		var headquarters:Dictionary=Classic.structures(battle.sim,0,"hq")[0]
		var pixel:Vector2=battle.camera.unproject_position(Vector3(headquarters.pos.x,0,headquarters.pos.y))
		var field:Rect2=battle.hud.battlefield_rect()
		check(field.grow_individual(-field.size.x*0.2,-field.size.y*0.2,-field.size.x*0.2,-field.size.y*0.2).has_point(pixel),"classic HQ visible centrally at start")
		var sim=battle.sim;sim.credits=5000
		for i in 5:check(Classic.enqueue(sim,"harvester"),"fill HQ queue")
		var balance:float=sim.credits
		check(Classic.production_reason(sim,"harvester").contains("queues full"),"full queue has exact reason")
		check(not Classic.enqueue(sim,"harvester") and sim.credits==balance,"full queue does not spend")
		battle.ui_action("buy:harvester",Vector2.ZERO)
		check(battle.toast.contains("queues full"),"rejected purchase reports full queue")
		var other=sim.spawn("hq",0,Vector2(32,sim.terrain.world_size.y-11));other.build_left=0;other.queue=[]
		check(Classic.production_reason(sim,"harvester")=="" and Classic.enqueue(sim,"harvester"),"second producer with room stays purchasable")
		Classic.cancel(sim,headquarters)
		check(Classic.production_reason(sim,"harvester")=="","freed slot restores availability")
		battle.free()
	print("REVIEW USABILITY: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
