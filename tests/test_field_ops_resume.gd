extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Ops=preload("res://scripts/field_ops.gd")
var checks:=0
var failures:=0
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
	check(Ops.build(sim,"aid_post",Vector2(25,97),builder.id),"create paid site")
	var site:Dictionary=sim.units.back()
	for i in 150:sim.tick(1.0/30)
	check(site.build_left>0 and site.build_left<12,"actual work accumulates")
	check(sim.issue([builder.id],Vector2(10,90))==1,"replacement movement accepted")
	check(site.build_paused and site.engineer_id==-1 and not builder.has("building_id"),"new order releases assignment")
	var remaining:float=site.build_left
	site.hp-=5
	var hp:float=site.hp
	for i in 120:sim.tick(1.0/30)
	check(site.build_left==remaining and site.hp==hp,"paused work and damage preserved")
	sim.credits=0
	check(Ops.available_engineer(sim,site.id)==builder.id,"default selects available engineer without supply")
	check(Ops.resume(sim,site.id),"manual resume succeeds with zero supply")
	check(sim.credits==0 and site.build_left==remaining and site.hp==hp,"resume preserves cash work and HP")
	check(site.engineer_id==builder.id and builder.building_id==site.id and not site.build_paused,"resume restores assignment")
	check(Ops.occupied_clear(sim,site.work_point,"engineer",false,[site.id,builder.id]),"resume work point clear outside own reserved footprint")
	check(not sim.terrain.traversable(site.pos,"land",0.8),"resume retains structure blocker")
	Ops.tick(sim,0.1)
	check(site.build_left==remaining,"resume cannot work remotely")
	for i in 600:sim.tick(1.0/30)
	check(site.build_left==0,"actual travel and resumed work finish")
	check(site.hp<site.max_hp,"completion preserves prior combat damage")
	check(not Ops.resume(sim,site.id) and Ops.available_engineer(sim,site.id)==-1,"completed site cannot resume")
	check(sim.field_ops.last_build_error!="","failed resume gives UI error")

	var freed=fixture()
	Ops.build(freed,"tactical_cover",Vector2(24,97),freed.units[0].id)
	var old:Dictionary=freed.units.back()
	freed.stop([freed.units[0].id])
	freed.visible_cells[freed.terrain.cell(Vector2(9,87))]=true
	check(Ops.build(freed,"tactical_cover",Vector2(9,87),freed.units[0].id),"paused builder can start a different site")
	check(Ops.available_engineer(freed,old.id)==-1,"active builder unavailable for another site")
	var old_hp:float=old.hp
	check(not Ops.resume(freed,old.id,freed.units[0].id) and old.hp==old_hp and old.build_paused,"busy builder resume rejected atomically")
	var replacement:Dictionary=freed.spawn("engineer",0,Vector2(31,97))
	var distant:Dictionary=freed.spawn("engineer",0,Vector2(14,75))
	check(Ops.available_engineer(freed,old.id)==replacement.id,"nearest free engineer preferred over busy and farther")
	check(Ops.resume(freed,old.id) and old.engineer_id==replacement.id,"default assigns nearest available")
	replacement.hp=0
	check(Ops.available_engineer(freed,old.id)==distant.id,"dead builder replaceable")
	var left:float=old.build_left
	freed.credits=0
	check(Ops.resume(freed,old.id) and old.engineer_id==distant.id and old.build_left==left and freed.credits==0,"dead builder replacement free and progress-preserving")
	var enemy_site:Dictionary=freed.spawn("tactical_cover",1,Vector2(40,80))
	enemy_site.build_left=8
	check(not Ops.resume(freed,enemy_site.id) and Ops.available_engineer(freed,enemy_site.id)==-1,"enemy site never resumable")
	old.hp=0
	check(not Ops.resume(freed,old.id),"destroyed site never resumable")

	var blocked=fixture()
	Ops.build(blocked,"tactical_cover",Vector2(24,97),blocked.units[0].id)
	var isolated:Dictionary=blocked.units.back()
	blocked.stop([blocked.units[0].id])
	blocked.terrain.blocks.append(Rect2(17,0,2,108))
	blocked.terrain.navigation.clear()
	var balance:float=blocked.credits
	var orders:Array=blocked.units[0].orders.duplicate(true)
	check(not Ops.resume(blocked,isolated.id),"resume requires reachable workpoint")
	check(isolated.build_paused and isolated.engineer_id==-1 and blocked.units[0].orders==orders and blocked.credits==balance,"failed route changes neither site nor engineer nor cash")
	check(blocked.field_ops.last_build_error=="Unable to reach work point","route failure generic UI message")

	var returned=fixture()
	Ops.build(returned,"tactical_cover",Vector2(24,97),returned.units[0].id)
	var held:Dictionary=returned.units.back()
	var engineer:Dictionary=returned.units[0]
	returned.stop([engineer.id])
	# Isolate the presence gate: put the released section back at its old point.
	engineer.pos=held.work_point
	for member in engineer.members:member.pos=engineer.pos+member.offset
	Ops.tick(returned,1)
	check(held.build_left==8,"returning to work point alone never auto-resumes")
	returned.credits=0
	check(Ops.resume(returned,held.id,engineer.id),"resume works when already at own reserved site's work point")
	Ops.tick(returned,0.5)
	check(held.build_left==7.5,"present living builder advances after manual resume")
	var paid:float=returned.credits
	var preserved_hp:float=held.hp
	check(Ops.resume(returned,held.id,engineer.id) and held.build_left==7.5 and held.hp==preserved_hp and returned.credits==paid,"repeated resume never charges or resets work")
	var hostile:Dictionary=returned.spawn("engineer",1,Vector2(50,90))
	check(not Ops.resume(returned,held.id,hostile.id) and held.engineer_id==engineer.id,"enemy engineer cannot take assignment")
	check(not Ops.resume(returned,held.id,99999) and held.engineer_id==engineer.id,"invalid engineer leaves assignment intact")
	check(Ops.cancel(returned,held.id) and held.state=="CANCELLED" and not engineer.has("building_id"),"cancel releases active builder without changing cancelled state")
	var refund_balance:float=returned.credits
	check(not Ops.cancel(returned,held.id) and returned.credits==refund_balance and returned.field_ops.last_build_error!="","repeat cancellation has generic failure and no refund")

	fog_tests()
	geometry_tests()
	print("FIELD OPS RESUME TESTS: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

func fog_tests()->void:
	var sim=fixture()
	var builder:Dictionary=sim.units[0]
	var pos:=Vector2(24,97)
	var baseline:Dictionary=Ops.proposal(sim,"tactical_cover",pos,builder.id)
	check(baseline.reason=="","fog fixture baseline valid")
	var hidden:Dictionary=sim.spawn("rifle",1,Vector2(50,97))
	hidden.seen_by=[false,true];hidden.visible=false
	hidden.pos=pos
	for member in hidden.members:member.pos=pos
	var preview:Dictionary=Ops.proposal(sim,"tactical_cover",pos,builder.id)
	check(preview==baseline,"hidden site occupants do not change preview or chosen route")
	var credits:float=sim.credits
	var count:int=sim.units.size()
	check(not Ops.build(sim,"tactical_cover",pos,builder.id),"commit rejects hidden physical site occupant")
	check(sim.credits==credits and sim.units.size()==count and not builder.has("building_id"),"hidden-site failure creates nothing and spends nothing")
	check(sim.field_ops.last_build_error=="Site unavailable","hidden failure reveals no identity or position")
	check(Ops.build_reason(sim,"tactical_cover",pos,builder.id)=="","preview stays knowledge-limited after failed commit")
	hidden.seen_by[0]=true
	check(Ops.build_reason(sim,"tactical_cover",pos,builder.id)=="Site obstructed","seen enemy blocks preview")
	hidden.seen_by[0]=false;hidden.pos=Vector2(50,97)
	# A soldier displaced from its unseen section still physically blocks commit.
	for member in hidden.members:member.pos=Vector2(50,97)
	hidden.members[0].pos=pos
	check(Ops.proposal(sim,"tactical_cover",pos,builder.id)==baseline,"hidden displaced soldier invisible to preview")
	check(not Ops.build(sim,"tactical_cover",pos,builder.id) and sim.credits==credits and sim.units.size()==count,"hidden soldier footprint checked before spawn and charge")
	# Hidden bodies at the work point must not bias its selected side either.
	hidden.members[0].pos=baseline.work_point
	check(Ops.proposal(sim,"tactical_cover",pos,builder.id)==baseline,"hidden workpoint soldier cannot bias preview route")
	check(not Ops.build(sim,"tactical_cover",pos,builder.id) and sim.credits==credits,"workpoint physical occupancy checked at commit")
	hidden.seen_by[0]=true
	var seen:Dictionary=Ops.proposal(sim,"tactical_cover",pos,builder.id)
	check(seen.reason!="" or seen.work_point!=baseline.work_point,"visible workpoint soldier affects preview")
	hidden.team=0;hidden.seen_by=[false,false]
	seen=Ops.proposal(sim,"tactical_cover",pos,builder.id)
	check(seen.reason!="" or seen.work_point!=baseline.work_point,"friendly occupancy always known")
	hidden.hp=0
	check(Ops.build(sim,"tactical_cover",pos,builder.id) and sim.field_ops.last_build_error=="","successful retry clears stale error")

func geometry_tests()->void:
	var sim=fixture()
	var grid=sim.terrain.nav_grid("land",2.65,"infantry")
	Ops.build(sim,"observation_post",Vector2(24,97),sim.units[0].id)
	var post:Dictionary=sim.units.back()
	check(sim.terrain.nav_grid("land",2.65,"infantry")==grid,"geometry integration preserves cached navigation object")
	sim.visibility_cache["probe"]=true
	post.build_left=0
	Ops.sync_obstacles(sim)
	check(sim.visibility_cache.has("probe"),"observation completion does not invalidate unchanged geometry visibility")
	post.hp=0
	Ops.sync_obstacles(sim)
	check(not sim.visibility_cache.has("probe"),"geometry removal clears visibility cache")
