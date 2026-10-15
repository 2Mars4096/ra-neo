extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Director=preload("res://scripts/tactical_director.gd")
const Actors=preload("res://scripts/infantry.gd")
const Cover=preload("res://scripts/cover_behavior.gd")
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)
func field():
	var sim=Sim.new(false,0)
	sim.scenario=sim.scenario.duplicate(true)
	sim.scenario.autonomy=true
	return sim
func flank_fixture()->Dictionary:
	var sim=field()
	var unit=sim.spawn("tank",0,Vector2(18,55))
	var ally=sim.spawn("tank",0,Vector2(30,55))
	var enemy=sim.spawn("tank",1,Vector2(18,40))
	sim.issue([unit.id],Vector2(18,20),"attack_move")
	ally.command_group=unit.command_group
	sim.update_visibility()
	check(sim.can_fire(ally,enemy),"fixture has observed supporting fire")
	return {"sim":sim,"unit":unit,"ally":ally,"enemy":enemy,"goal":unit.orders[0].pos}
func _init()->void:
	var f=flank_fixture()
	var blocker=f.sim.spawn("tank",0,Vector2(10,48))
	Director.update(f.sim)
	check(f.unit.maneuver.get("phase","")=="FLANK","supported advance chooses a maneuver")
	check(f.unit.maneuver.get("pos",Vector2.ZERO).distance_to(blocker.pos)>5.0,"flank rejects an occupied destination and chooses the other side")
	print("FLANK EVIDENCE: goal=",f.unit.maneuver.get("pos")," blocker=",blocker.pos)
	var flank_start:Vector2=f.unit.pos
	f.unit.cooldown=1000;f.ally.cooldown=1000;f.enemy.cooldown=1000
	for frame in 20:f.sim.tick(0.1);f.sim.events.clear()
	check(f.unit.pos.x>flank_start.x+1.0,"chosen alternate flank produces movement around the parked friendly")
	f=flank_fixture()
	Director.update(f.sim)
	check(f.unit.maneuver.get("phase","")=="FLANK","support-loss fixture begins a flank")
	f.ally.hp=0
	f.sim.time=1.0
	Director.update(f.sim)
	check(f.unit.maneuver.is_empty(),"loss of supporting weapon ends dependent flank before deadline")
	check(f.unit.orders[0].pos==f.goal,"support loss preserves objective")
	check(f.unit.reason=="Support lost · resuming objective","support loss reports why the flank ended")
	f=flank_fixture()
	Director.update(f.sim)
	f.unit.hp=f.unit.max_hp*0.2
	f.sim.time=1.0
	Director.update(f.sim)
	check(f.unit.maneuver.get("phase","")=="WITHDRAW","critical damage interrupts committed flank")
	var jam=field()
	var lead=jam.spawn("tank",0,Vector2(18,55))
	var parked=jam.spawn("tank",0,Vector2(10,48))
	jam.stop([parked.id])
	jam.issue([lead.id],Vector2(18,20),"attack_move")
	var original_goal:Vector2=lead.orders[0].pos
	check(Director.plan(jam,lead,parked.pos,"FLANK","route becomes occupied",6),"blocked maneuver fixture starts")
	for frame in 110:jam.tick(0.1);jam.events.clear()
	print("BLOCKED EVIDENCE: pos=",lead.pos," phase=",lead.maneuver.get("phase", "NONE")," blocked=",lead.blocked_time)
	check(lead.maneuver.is_empty(),"stalled maneuver releases before its old eighteen-second deadline")
	check(not lead.orders.is_empty() and lead.orders[0].pos==original_goal,"blocked maneuver retains objective route")
	check(lead.reason=="Maneuver blocked · resuming objective","stalled maneuver reports its blocked route")
	for exit_case in ["completed","timeout","default"]:
		var recovery=field()
		var recovering=recovery.spawn("tank",0,Vector2(18,55))
		recovery.issue([recovering.id],Vector2(18,20),"attack_move")
		var orders_before:Array=recovering.orders.duplicate(true)
		var intent_before:Dictionary=recovering.intent.duplicate(true)
		check(Director.plan(recovery,recovering,recovering.pos,"SUPPORT","Brief support wait",1),"resume reason fixture starts: "+exit_case)
		var expected:="Regrouping toward objective"
		if exit_case=="default":
			Director.resume(recovery,recovering)
		else:
			recovery.time=1.0 if exit_case=="completed" else recovering.maneuver.deadline+0.1
			expected="Maneuver complete · resuming objective" if exit_case=="completed" else "Maneuver timed out · resuming objective"
			Director.update(recovery)
		check(recovering.maneuver.is_empty() and recovering.reason==expected,"resume explains "+exit_case)
		check(recovering.orders==orders_before and recovering.intent==intent_before and not recovering.path.is_empty(),"resume preserves intent and restores objective route: "+exit_case)
		check(recovering.next_decision==recovery.time+5.0 and recovering.commit_until==recovery.time+5.0,"resume retains decision grace period: "+exit_case)
	# Real shelter acquisition, with weapons disabled to isolate movement.
	var sim=Sim.new(false,3)
	var squad=sim.spawn("rifle",0,Vector2(17,33))
	var enemy=sim.spawn("tank",1,Vector2(17,21))
	enemy.cooldown=1000
	sim.issue([squad.id],Vector2(12,55),"attack_move")
	squad.next_decision=1000
	var start:Vector2=squad.pos
	var sheltered:=false
	for frame in 400:
		sim.tick(0.1)
		for member in squad.members:
			if member.get("cover_phase","")=="SHELTERED":sheltered=true
		sim.events.clear()
	print("ADVANCE EVIDENCE: start=",start," end=",squad.pos," order_count=",squad.orders.size()," sheltered=",sheltered)
	check(sheltered,"advance fixture really occupies shelter after contact")
	check(squad.pos.distance_to(Vector2(12,55))<4,"sheltered soldiers eventually release and complete advance")
	# A real wall screens the original contact, then the observed contact changes sides.
	var wall=field()
	wall.terrain.style="showcase"
	wall.terrain.dynamic_blocks.append(Rect2(8,35,8,6))
	var section=wall.spawn("rifle",0,Vector2(18,44))
	var threat=wall.spawn("tank",1,Vector2(12,30))
	var member:Dictionary=section.members[0]
	member.pos=Vector2(12,42.05)
	member.cover_goal=member.pos;member.cover_phase="SHELTERED";member.cover_path=[]
	member.cover_until=0.0;member.cover_deadline=100.0
	member.cover_screened=true
	check(wall.terrain.cover(member.pos) and not wall.terrain.line_clear(threat.pos,member.pos),"fixture wall actually screens shelter")
	threat.pos=Vector2(12,49)
	wall.update_visibility()
	check(wall.contact_known(section,threat) and wall.terrain.line_clear(threat.pos,member.pos),"new observed bearing exposes old wall shelter")
	var old_goal:Vector2=member.cover_goal
	Cover.update(section,wall)
	check(member.cover_goal!=old_goal,"soldier abandons shelter exposed by an observed flanking threat")
	for frame in 35:
		wall.time+=0.1
		Actors.move(section,wall,0.1)
	check(member.pos.distance_to(old_goal)>0.5,"exposed soldier actually moves away from stale shelter")
	# Hidden enemies alone must never initiate tactics or shelter.
	var hidden=field()
	var scout=hidden.spawn("rifle",0,Vector2(12,55))
	hidden.spawn("tank",1,Vector2(70,10))
	hidden.issue([scout.id],Vector2(12,30),"attack_move")
	hidden.update_visibility();Director.update(hidden);Cover.update(scout,hidden)
	check(scout.maneuver.is_empty() and not Cover.seeking(scout),"unobserved enemy does not inform decisions")
	for mode in ["move","retreat","hold"]:
		f=flank_fixture()
		if mode=="hold":f.sim.stop([f.unit.id])
		elif mode=="retreat":f.sim.retreat([f.unit.id])
		else:f.sim.issue([f.unit.id],Vector2(12,60),"move")
		f.unit.hp=f.unit.max_hp*0.2
		Director.update(f.sim)
		check(f.unit.maneuver.is_empty(),"explicit %s retains authority"%mode)
	# Dead soldiers cannot be healed; withdrawal completion uses living capacity.
	var survivors=field()
	var remnant=survivors.spawn("rifle",0,Vector2(12,55))
	for i in range(1,remnant.members.size()):remnant.members[i].hp=0
	Actors.publish(remnant)
	survivors.issue([remnant.id],Vector2(12,30),"attack_move")
	check(Director.plan(survivors,remnant,remnant.pos,"WITHDRAW","capacity fixture",1),"survivor withdrawal fixture starts")
	survivors.time=2.0
	Director.update(survivors)
	check(remnant.maneuver.is_empty(),"fully healed survivors resume without waiting for dead-member health")
	audit_regressions()
	print("TACTICAL FLEXIBILITY: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)

func audit_regressions()->void:
	var sim=field()
	var a=sim.spawn("tank",0,Vector2(18,55))
	var b=sim.spawn("tank",0,Vector2(26,55))
	sim.spawn("tank",1,Vector2(22,40))
	sim.issue([a.id,b.id],Vector2(18,20),"attack_move")
	a.hp=a.max_hp*0.2;b.hp=b.max_hp*0.2
	sim.update_visibility();Director.update(sim)
	check(a.maneuver.get("phase","")=="WITHDRAW" and b.maneuver.get("phase","")=="WITHDRAW","two endangered units both withdraw")
	check(a.maneuver.get("pos",Vector2.ZERO).distance_to(b.maneuver.get("pos",Vector2.ZERO))>5,"withdrawals reserve distinct rally slots")
	var original:Dictionary=a.orders[0].duplicate()
	sim.time=4.9
	Director.update(sim)
	check(a.maneuver.is_empty() and a.orders[0]==original,"stalled withdrawal releases in five seconds and retains objective")
	check(sim.can_fire(a,sim.living(1)[0]),"blocked autonomous withdrawal restores firing")
	var wall=field()
	wall.terrain.style="showcase"
	wall.terrain.dynamic_blocks.append(Rect2(8,35,8,6))
	var section=wall.spawn("rifle",0,Vector2(18,44))
	var near=wall.spawn("tank",1,Vector2(18,33))
	var far=wall.spawn("tank",1,Vector2(12,63))
	var member:Dictionary=section.members[0]
	member.pos=Vector2(12,42.05);member.cover_goal=member.pos
	member.cover_phase="SHELTERED";member.cover_screened=true
	member.cover_until=100;member.cover_deadline=100
	near.seen_by[0]=true;far.seen_by[0]=true
	check(not wall.terrain.line_clear(near.pos,member.pos) and wall.terrain.line_clear(far.pos,member.pos),"near contact screened while farther contact exposes shelter")
	Cover.update(section,wall)
	check(member.cover_goal==Vector2.ZERO,"farther observed threat invalidates screened shelter")
	far.seen_by[0]=false
	member.cover_goal=member.pos;member.cover_phase="SHELTERED"
	member.cover_screened=true
	check(Director.plan(wall,section,section.pos,"SUPPORT","Covering partner",3),"stationary support accepted")
	Cover.update(section,wall)
	check(member.cover_goal==member.pos and member.cover_phase=="SHELTERED","SUPPORT retains valid occupied cover")
	var slot=Cover.find_slot(section,member,wall,near)
	check(not slot.is_empty(),"reservation fixture has a cover slot")
	if not slot.is_empty():
		var hidden=wall.spawn("rifle",1,Vector2(70,60))
		hidden.seen_by[0]=false
		hidden.members[0].cover_goal=slot.pos
		var after=Cover.find_slot(section,member,wall,near)
		check(after==slot,"hidden enemy destination does not reserve friendly shelter")
