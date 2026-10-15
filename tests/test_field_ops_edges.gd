extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Ops=preload("res://scripts/field_ops.gd")
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)
func fixture():
	var sim=Sim.new(false,5)
	sim.terrain.blocks.clear();sim.terrain.roadside_blocks.clear();sim.terrain.trees.clear();sim.terrain.poles.clear()
	sim.terrain.navigation.clear()
	sim.spawn("engineer",0,Vector2(14,97))
	sim.update_visibility()
	return sim
func _init()->void:
	var sim=fixture()
	var builder:Dictionary=sim.units[0]
	var pos:=Vector2(24,97)
	check(Ops.build(sim,"observation_post",pos,builder.id),"observation construction")
	var post:Dictionary=sim.units.back()
	var enemy:Dictionary=sim.spawn("rifle",1,Vector2(45,97))
	sim.update_visibility()
	check(not enemy.visible,"unfinished post cannot reveal hidden enemy")
	check(not sim.terrain.cover(Vector2(26,97)),"unfinished post supplies no cover")
	for i in 600:sim.tick(1.0/30)
	check(post.build_left==0,"observation completes through actual ticks")
	sim.update_visibility()
	check(enemy.visible,"completed post observes nearby enemy")
	check(post.pos==pos and post.orders.is_empty(),"structure position unchanged")
	var cancelled=fixture()
	check(Ops.build(cancelled,"aid_post",Vector2(25,97),cancelled.units[0].id),"partial refund fixture")
	var site:Dictionary=cancelled.units.back()
	for i in 180:cancelled.tick(1.0/30)
	check(site.build_left>0 and site.build_left<12,"partial work before cancellation")
	var refund:float=110*site.build_left/12
	var credits:float=cancelled.credits
	check(Ops.cancel(cancelled,site.id) and is_equal_approx(cancelled.credits,credits+refund),"proportional unused-work refund")
	var ordered=fixture()
	Ops.build(ordered,"tactical_cover",Vector2(24,97),ordered.units[0].id)
	var paused:Dictionary=ordered.units.back()
	check(ordered.issue([ordered.units[0].id],Vector2(10,94))==1,"new engineer order accepted")
	check(paused.build_paused and not ordered.units[0].has("building_id"),"new order releases engineer and pauses site")
	for i in 300:ordered.tick(1.0/30)
	check(paused.build_left==8,"paused site never auto completes")
	var blocked=fixture()
	blocked.terrain.blocks.append(Rect2(18,0,2,108))
	blocked.terrain.navigation.clear()
	# Keep an already-observed location in the test so the route check itself
	# is exercised, independent of the visibility gate.
	blocked.visible_cells[blocked.terrain.cell(pos)]=true
	var funds:float=blocked.credits
	var count:int=blocked.units.size()
	check(Ops.build_reason(blocked,"tactical_cover",pos,blocked.units[0].id)=="No clear engineer work route","disconnected work route rejected")
	check(not Ops.build(blocked,"tactical_cover",pos,blocked.units[0].id) and blocked.credits==funds and blocked.units.size()==count,"no charge or spawn on route failure")
	check(blocked.terrain.dynamic_blocks.is_empty(),"failed route restores proposed reservation")
	var capture=fixture()
	var fort:Dictionary=capture.spawn("tactical_cover",0,Vector2(56,57))
	capture.objectives[0].pos=fort.pos
	capture.update_objectives(20)
	check(capture.objectives[0].owner==1,"structure cannot capture")
	var victim:Dictionary=capture.spawn("observation_post",1,Vector2(30,97))
	var rifle:Dictionary=capture.units[0]
	var initial:float=victim.hp
	for i in 100:capture.resolve_shot(rifle,victim,0.25)
	check(victim.hp<initial,"field structures take combat damage")
	var poor=fixture()
	poor.credits=59
	check(not Ops.build(poor,"tactical_cover",pos,poor.units[0].id) and poor.credits==59,"insufficient funds never charged")
	var healing=fixture()
	healing.spawn("aid_post",0,Vector2(23,97))
	var section:Dictionary=healing.units[0]
	section.members[0].hp=10;Sim.Infantry.publish(section)
	section.last_hit=8;healing.time=10
	var hp:float=section.hp
	Ops.tick(healing,1)
	check(section.hp==hp,"recent hit prevents aid")
	check(healing.definitions.engineer.damage<healing.definitions.rifle.damage,"engineer rifle weaker")
	print("FIELD OPS EDGE TESTS: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
