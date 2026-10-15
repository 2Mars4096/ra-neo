extends SceneTree
# Repro: engineers start a sandbag wall, are ordered away (site PAUSED), then
# RESUME is pressed. The site must get a builder and make progress.
const Sim=preload("res://scripts/simulation.gd")
const FieldOps=preload("res://scripts/field_ops.gd")
func _init()->void:
	var sim=Sim.new(false,5)
	var engineer:Dictionary=sim.spawn("engineer",0,Vector2(14,97))
	sim.update_visibility()
	var pos:=Vector2(-1,-1)
	for y in range(85,102,2):
		for x in range(7,30,2):
			if pos.x<0 and FieldOps.can_build(sim,"tactical_cover",Vector2(x,y),engineer.id):pos=Vector2(x,y)
	print("site pos ",pos," build ",FieldOps.build(sim,"tactical_cover",pos,engineer.id))
	var work:Dictionary=sim.units.back()
	for i in 60:sim.tick(1.0/30)
	sim.issue([engineer.id],engineer.pos+Vector2(12,0),"move")
	for i in 150:sim.tick(1.0/30)
	print("after move: paused=",work.get("build_paused")," engineer_id=",work.get("engineer_id")," queued_for=",work.get("queued_for",-1)," build_left=%.2f" % work.build_left," eng orders=",engineer.orders.size()," building_id=",engineer.get("building_id",-1))
	var ok:bool=FieldOps.resume(sim,work.id)
	print("resume -> ",ok," error=",sim.field_ops.get("last_build_error",""))
	print("after resume: paused=",work.get("build_paused")," engineer_id=",work.get("engineer_id")," eng orders=",engineer.orders.size()," building_id=",engineer.get("building_id",-1))
	var left:float=work.build_left
	for i in 600:sim.tick(1.0/30)
	print("after 20s: paused=",work.get("build_paused")," build_left=%.2f (was %.2f)" % [work.build_left,left]," eng pos=",engineer.pos.round()," state=",engineer.state," orders=",engineer.orders)
	ok=ok and work.build_left<left
	print("RESUME: ","PASS" if ok else "FAIL")
	quit(0 if ok else 1)
