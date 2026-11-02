extends SceneTree

const Sim=preload("res://scripts/simulation.gd")
var checks:=0
var failures:=0

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func _init()->void:
	var sim=Sim.new(false,0)
	sim.scenario.autonomy=true
	var u:Dictionary=sim.spawn("rifle",0,Vector2(20,60))
	var enemy:Dictionary=sim.spawn("rifle",1,Vector2(30,60))
	sim.update_visibility()
	var mover:Dictionary=u.members[0]
	var first:Dictionary=u.members[1]
	var second:Dictionary=u.members[2]
	var slot:={"pos":Vector2(24,60),"screened":false}
	check(sim.Coordination.can_cover(u,first,sim,enemy),"loaded partner has a real firing lane to observed threat")
	first.rounds=0
	second.suppression=0.9
	check(not sim.Coordination.begin_bound(u,mover,sim,enemy,slot),"stationary empty or pinned partners cannot cover an ordinary bound")
	check(mover.get("coord_reason","")=="waiting_for_cover","unsupported choice explains why it waits")
	first.rounds=6;second.suppression=0
	check(sim.Coordination.begin_bound(u,mover,sim,enemy,slot),"available partner authorizes one covered movement")
	mover.cover_phase="SEEKING"
	check(first.get("cover_for","")==mover.member_id and mover.covered_by==first.member_id,"covering and moving roles identify each other")
	var covering_position:Vector2=first.pos
	u.cover_command=u.command_group;u.cover_next=sim.time+10
	mover.cover_goal=Vector2(24,60);mover.cover_path=[]
	sim.Infantry.move(u,sim,0.1)
	check(first.pos==covering_position and sim.Coordination.can_cover(u,first,sim,enemy),"coverer retains its useful firing position while the teammate moves")
	second.travel=0.0
	first.rounds=1
	check(not sim.Infantry.can_topoff(u,first,sim.time),"coverer retains loaded rounds while teammate depends on it")
	first.reload_until=sim.time+1.0
	sim.Coordination.review(u,sim)
	check(mover.covered_by==second.member_id and second.cover_for==mover.member_id,"reload invalidates the old supporter and another capable member takes over")
	second.hp=0
	sim.Coordination.review(u,sim)
	check(not mover.has("covered_by") and mover.coord_reason=="cover_lost","casualty removes false covering claim while mover can finish seeking shelter")
	check(sim.actions.active(u,"member:%s:support"%second.member_id).is_empty(),"lost covering action releases its channel")
	mover.cover_phase="SHELTERED"
	sim.Coordination.review(u,sim)
	check(not mover.has("support_threat") and not first.has("cover_for"),"arrival releases the team's covering commitment")
	first.reload_until=0;first.rounds=6;second.hp=second.max_hp
	sim.set_fire_policy([u.id],"hold")
	check(not sim.Coordination.can_cover(u,first,sim,enemy),"Hold fire cannot be counted as useful covering fire")
	sim.set_fire_policy([u.id],"free")
	first["task_action"]=999;first["task_kind"]="dig"
	check(not sim.Infantry.ready_to_cover(u,first,sim.time),"an occupied worker is not a covering rifle")
	var rounds:int=first.rounds
	var position:Vector2=first.pos
	sim.infantry_combat(u,0.1)
	sim.Infantry.move(u,sim,0.1)
	check(first.rounds==rounds and first.target<0,"task actor cannot simultaneously fire its ordinary weapon")
	check(first.pos==position,"normal infantry movement cannot also move a task-owned actor")
	sim.stop([u.id])
	check(not sim.Infantry.task_busy(first),"replacement Hold immediately releases the actor task marker")
	check(u.members.all(func(m):return not m.has("cover_for") and not m.has("covered_by")),"replacement command releases all cooperation roles")
	alternate_weapon_readiness()
	defensive_shelter()
	print("INFANTRY COORDINATION: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func alternate_weapon_readiness()->void:
	var sim=Sim.new(false,0)
	sim.scenario.autonomy=true
	var u:Dictionary=sim.spawn("atgm",0,Vector2(20,60))
	var enemy:Dictionary=sim.spawn("rifle",1,Vector2(30,60))
	sim.update_visibility()
	var operator:Dictionary=u.members[0]
	operator.readiness_weapon="atgm";operator.rounds=0
	operator.magazines.atgm=0;operator.magazines.rifle=6
	var magazines:Dictionary=operator.magazines.duplicate(true)
	check(sim.Coordination.can_cover(u,operator,sim,enemy),"an empty stowed launcher does not mask a loaded covering rifle")
	check(operator.readiness_weapon=="atgm" and operator.rounds==0 and operator.magazines==magazines,"cover eligibility does not switch weapons, refill or consume either magazine")
	operator.reload_until=sim.time+1.0;operator.reload_weapon="atgm"
	check(not sim.Coordination.can_cover(u,operator,sim,enemy),"a live launcher reload remains unavailable even with a loaded rifle")
	check(operator.reload_weapon=="atgm" and operator.reload_until==sim.time+1.0,"eligibility does not interrupt an active reload")
	sim.Infantry.cancel_readiness(operator)
	operator["task_action"]=999;operator["task_kind"]="dig"
	check(not sim.Coordination.can_cover(u,operator,sim,enemy),"alternate loaded weapon cannot borrow a task-owned actor")
	operator.erase("task_action");operator.erase("task_kind")
	operator.aiding=1
	check(not sim.Coordination.can_cover(u,operator,sim,enemy),"alternate loaded weapon cannot borrow a medic")
	operator.aiding=-1;operator.suppression=0.9
	check(not sim.Coordination.can_cover(u,operator,sim,enemy),"alternate loaded weapon does not bypass suppression")
	operator.suppression=0.0
	sim.set_fire_policy([u.id],"hold")
	check(not sim.Coordination.can_cover(u,operator,sim,enemy),"alternate loaded weapon preserves Hold fire")
	sim.set_fire_policy([u.id],"free")
	var armor:Dictionary=sim.spawn("tank",1,Vector2(30,60))
	sim.update_visibility()
	operator.readiness_weapon="rifle";operator.rounds=0
	operator.magazines.rifle=0;operator.magazines.atgm=1
	magazines=operator.magazines.duplicate(true)
	check(sim.Coordination.can_cover(u,operator,sim,armor),"an empty current rifle does not mask a loaded covering launcher against armor")
	check(operator.readiness_weapon=="rifle" and operator.rounds==0 and operator.magazines==magazines,"launcher eligibility leaves inventory and current weapon unchanged")
	operator.magazines.rifle=6
	check(not sim.Coordination.can_cover(u,operator,sim,enemy),"current rifle rounds remain authoritative over a stale stored magazine")
	u.missiles=0
	check(not sim.Coordination.can_cover(u,operator,sim,armor),"stored launcher round cannot bypass exhausted missile stock")

func defensive_shelter()->void:
	var sim=Sim.new(false,3)
	var u:Dictionary=sim.spawn("rifle",0,Vector2(17,33))
	var armor:Dictionary=sim.spawn("tank",1,Vector2(17,21))
	armor.cooldown=1000
	sim.update_visibility()
	var member:Dictionary=u.members[2]
	var slot:Dictionary=sim.Infantry.Cover.find_slot(u,member,sim,armor,[armor])
	check(not slot.is_empty() and slot.get("screened",false),"unanswered armor fixture has a real screened shelter and physical route")
	if slot.is_empty():return
	check(not sim.effective_unit(u,armor.kind) and not u.members.any(func(m):return sim.Coordination.can_cover(u,m,sim,armor)),"rifles cannot claim useful covering fire against armor")
	check(sim.Coordination.begin_bound(u,member,sim,armor,slot),"observed unanswered weapon permits defensive shelter before it fires")
	sim.Infantry.Cover.assign(u,member,sim,slot,(armor.pos-u.pos).normalized())
	sim.Coordination.review(u,sim)
	check(member.coord_reason=="defensive_shelter" and sim.Coordination.status(u)=="Seeking shelter · no effective covering weapon","defensive shelter remains visibly unsupported during movement")
	check(not member.has("covered_by") and u.members.all(func(m):return not m.has("cover_for")),"defensive movement never invents a covering partner")
	var exposed:Dictionary=slot.duplicate(true)
	exposed.screened=false;exposed.pos=Vector2(17,26);exposed.path=[exposed.pos]
	check(not sim.Coordination.begin_bound(u,member,sim,armor,exposed),"unanswered weapon cannot authorize an ordinary exposed flank")
	armor.seen_by[0]=false
	check(not sim.Coordination.begin_bound(u,member,sim,armor,slot),"hidden armor cannot initiate defensive shelter")
	armor.seen_by[0]=true
	for mode in ["hold","move","retreat"]:
		if mode=="hold":sim.stop([u.id])
		else:sim.issue([u.id],Vector2(12,55),mode)
		sim.Infantry.Cover.update(u,sim)
		check(not sim.Infantry.Cover.seeking(u) and u.members.all(func(m):return m.cover_goal==Vector2.ZERO),"explicit %s remains authoritative over defensive shelter"%mode)
