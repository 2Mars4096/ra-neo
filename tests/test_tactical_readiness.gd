extends SceneTree
# M0 readiness through the real combat loop, with durable roster/equipment
# invariants checked separately from healing and transient action state.
const Sim=preload("res://scripts/simulation.gd")
const Infantry=preload("res://scripts/infantry.gd")
const Garrison=preload("res://scripts/garrison.gd")
const Campaign=preload("res://scripts/regional_campaign.gd")
var checks:=0
var failures:=0

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func field():
	var sim=Sim.new(false,0)
	sim.scenario=sim.scenario.duplicate(true)
	sim.scenario["autonomy"]=true
	sim.scenario["jam_radius"]=0.0
	sim.terrain.style="showcase"
	return sim

func section(sim,kind:String="rifle")->Dictionary:
	var u:Dictionary=sim.spawn(kind,0,Vector2(14,50))
	sim.stop([u.id])
	return u

func combat_for(sim,u:Dictionary,seconds:float)->void:
	for tick in int(ceil(seconds*30.0)):
		sim.time+=1.0/30.0
		Garrison.tick_members(u,1.0/30.0)
		sim.infantry_combat(u,1.0/30.0,[])

func quiet_readiness()->void:
	var sim=field()
	var u:=section(sim)
	var empty:Dictionary=u.members[0]
	empty.rounds=0
	sim.infantry_combat(u,1.0/30.0,[])
	check(empty.state=="RELOADING" and empty.reload_until>sim.time,"quiet empty weapon starts reloading without a target")
	check(empty.rounds==0 and empty.target<0,"preparation grants no rounds or invented target")
	check(Infantry.strength(u,sim.time).ready_members==2,"two loaded members remain available while their buddy reloads")
	combat_for(sim,u,1.5)
	check(empty.rounds==0,"reload takes its full preparation time")
	combat_for(sim,u,0.4)
	check(empty.rounds==6 and empty.reload_until==0.0,"quiet reload completes through the combat loop")
	check(empty.state!="RELOADING" and empty.reload_completed_weapon=="rifle","quiet completion clears stale reload presentation and records the weapon")
	check(sim.events.filter(func(e):return e.type=="shot").is_empty(),"readiness produces no shot without a target")
	# Every weapon may be empty after an engagement. None can cover initially;
	# requiring a ready supporter for this case would permanently deadlock them.
	for member in u.members:member.rounds=0
	combat_for(sim,u,2.1)
	check(u.members.all(func(m):return m.rounds==6 and m.reload_until==0.0),"all-empty section recovers instead of waiting for nonexistent coverage")

func coordinated_topoff()->void:
	var sim=field()
	var u:=section(sim)
	sim.time=10.0
	for member in u.members:member.rounds=2
	sim.infantry_combat(u,1.0/30.0,[])
	check(u.members.filter(func(m):return m.reload_until>sim.time).size()==2,"quiet partial reloads retain one loaded member")
	check(Infantry.strength(u,sim.time).ready_members==1,"the remaining member can actually watch with a ready weapon")
	var kept_ready:=true
	for tick in 120:
		sim.time+=1.0/30.0
		sim.infantry_combat(u,1.0/30.0,[])
		kept_ready=kept_ready and int(Infantry.strength(u,sim.time).ready_members)>=1
	check(kept_ready and u.members.all(func(m):return m.rounds==6),"staggered topoffs finish without leaving everyone unavailable")
	for member in u.members:member.rounds=2
	sim.infantry_combat(u,1.0/30.0,[])
	var watcher:Dictionary=u.members.filter(func(m):return m.reload_until==0.0)[0]
	watcher.aiding=0
	sim.time+=1.0/30.0
	sim.infantry_combat(u,1.0/30.0,[])
	check(Infantry.strength(u,sim.time).ready_members>=1,"loss of the covering member interrupts a partial reload to restore readiness")
	watcher.aiding=-1
	for member in u.members:Infantry.cancel_readiness(member)
	var lone:Dictionary=u.members[0]
	for index in [1,2]:u.members[index].hp=0.0;u.members[index].wound=Infantry.KIA
	Infantry.publish(u)
	lone.rounds=2
	sim.time+=10.0
	sim.infantry_combat(u,1.0/30.0,[])
	check(lone.reload_until==0.0 and lone.rounds==2,"a lone loaded survivor keeps useful rounds without covering support")
	lone.rounds=0
	sim.infantry_combat(u,1.0/30.0,[])
	check(lone.reload_until>sim.time,"a lone empty survivor can still reload")

func readiness_interruptions()->void:
	var sim=field()
	var u:=section(sim)
	var member:Dictionary=u.members[0]
	member.rounds=0
	check(Infantry.update_readiness(u,member,10.0,"rifle"),"interruption fixture begins empty reload")
	member.travel=0.05
	check(not Infantry.update_readiness(u,member,12.0,"rifle") and member.rounds==0 and member.reload_until==0.0,"movement cancels an expired reload before granting ammunition")
	member.travel=0.0
	Infantry.update_readiness(u,member,12.0,"rifle")
	u.orders=[{"mode":"retreat"}]
	check(not Infantry.update_readiness(u,member,14.0,"rifle") and member.rounds==0,"retreat cancels preparation without completing it")
	u.orders=[]
	Infantry.update_readiness(u,member,14.0,"rifle")
	member.aiding=1
	check(not Infantry.update_readiness(u,member,16.0,"rifle") and member.reload_until==0.0,"casualty assistance owns the soldier before readiness")
	member.aiding=-1
	Infantry.update_readiness(u,member,16.0,"rifle")
	member["cover_phase"]="SEEKING"
	check(not Infantry.update_readiness(u,member,18.0,"rifle") and member.rounds==0,"cover movement interrupts an unfinished reload")
	member.cover_phase=""
	member.rounds=2
	check(Infantry.update_readiness(u,member,20.0,"rifle"),"quiet partial reload starts when a loaded peer is available")
	member.target=987
	check(not Infantry.update_readiness(u,member,20.1,"rifle") and member.rounds==2,"new contact interrupts a voluntary topoff and retains useful rounds")
	member.target=-1
	member.rounds=0
	Infantry.update_readiness(u,member,21.0,"rifle")
	u["fired_on"]=21.1
	check(Infantry.update_readiness(u,member,21.2,"rifle"),"incoming fire does not stop an empty weapon from becoming usable")
	check(not Infantry.update_readiness(u,member,22.9,"rifle") and member.rounds==6,"empty reload still finishes under contact")
	# Wounds can arrive after the timer, before its next processing opportunity.
	member.rounds=0
	Infantry.update_readiness(u,member,25.0,"rifle")
	Infantry.wound(u,member,Infantry.SEVERE,25.5,sim.combat_rng)
	Infantry.publish(u)
	check(not Infantry.update_readiness(u,member,28.0,"rifle") and member.rounds==0 and member.reload_until==0.0,"incapacitation releases preparation without resurrecting rounds")
	check(not Infantry.ready_to_cover(u,member,28.0),"downed soldier cannot count as coverage")

func covering_eligibility()->void:
	var sim=field()
	var u:=section(sim)
	var shooter:Dictionary=u.members[0]
	var peer:Dictionary=u.members[1]
	u.members[2].hp=0.0;u.members[2].wound=Infantry.KIA
	Infantry.publish(u)
	shooter.rounds=2
	peer.aiding=2
	check(not Infantry.update_readiness(u,shooter,10.0,"rifle"),"medic cannot justify a voluntary topoff")
	peer.aiding=-1;peer.travel=0.1
	check(not Infantry.update_readiness(u,shooter,11.0,"rifle"),"moving teammate cannot justify a voluntary topoff")
	peer.travel=0.0;peer.suppression=0.9
	check(not Infantry.update_readiness(u,shooter,12.0,"rifle"),"pinned teammate cannot justify a voluntary topoff")
	peer.suppression=0.0;peer.rounds=0
	check(not Infantry.update_readiness(u,shooter,13.0,"rifle"),"empty teammate cannot justify a voluntary topoff")
	peer.rounds=6;peer.reload_until=15.0
	check(not Infantry.update_readiness(u,shooter,14.0,"rifle"),"teammate still reloading cannot justify a voluntary topoff")
	Infantry.cancel_readiness(peer)
	u.last_shot=14.5
	check(not Infantry.update_readiness(u,shooter,15.0,"rifle"),"the section waits for a quiet interval after firing")
	check(Infantry.update_readiness(u,shooter,18.0,"rifle"),"ready teammate and a genuine lull permit topoff")

func launcher_and_rifle()->void:
	var sim=field()
	var u:=section(sim,"atgm")
	var operator:Dictionary=Infantry.member_by_id(u,str(u.equipment.launcher.holder))
	u["missiles"]=2
	operator.rounds=0
	check(Infantry.update_readiness(u,operator,10.0,"atgm"),"empty launcher starts readiness with carried ammunition")
	check(operator.reload_weapon=="atgm" and operator.reload_until==13.0,"launcher uses its own preparation duration and trace identity")
	check(not Infantry.update_readiness(u,operator,10.5,"rifle") and operator.rounds==6,"switch to rifle keeps its independent loaded magazine")
	check(Infantry.magazine_rounds(operator,"atgm")==0,"rifle switch does not refill the spent launcher")
	check(Infantry.update_readiness(u,operator,11.0,"atgm"),"return to launcher restarts interrupted preparation")
	check(operator.reload_until==14.0,"weapon switch cannot reuse an obsolete reload deadline")
	check(not Infantry.update_readiness(u,operator,14.0,"atgm") and operator.rounds==1 and u.missiles==2,"launcher readiness loads once without creating or spending carried missiles")
	operator.rounds=0;u.missiles=0
	check(not Infantry.update_readiness(u,operator,20.0,"atgm") and operator.rounds==0,"launcher cannot reload after supply exhaustion")
	check(not Infantry.update_readiness(u,operator,20.0,"rifle") and operator.rounds==6,"empty AT team retains a rifle fallback")
	# Quiet combat prepares the launcher even without an armored target.
	u.missiles=1
	operator.magazines.atgm=0
	combat_for(sim,u,3.3)
	check(Infantry.magazine_rounds(operator,"atgm")==1 and u.missiles==1,"combat loop prepares an empty launcher during a target-free lull")

func strength_and_equipment()->void:
	var sim=field()
	var u:=section(sim)
	var assigned:float=Infantry.assigned_capacity(u)
	for index in [1,2]:
		Infantry.wound(u,u.members[index],Infantry.KIA,1.0,sim.combat_rng)
	Infantry.publish(u)
	var view:=Infantry.strength(u,2.0)
	check(view.assigned_members==3 and view.effective_members==1 and is_equal_approx(view.fraction,1.0/3.0),"one healthy survivor is one third of assigned strength")
	check(Infantry.capacity(u)==u.members[0].max_hp,"healing capacity continues to describe actual survivors")
	Infantry.recover(u,1000.0)
	check(Infantry.assigned_capacity(u)==assigned and Infantry.strength(u).effective_members==1,"medical recovery does not recreate losses or reset assigned strength")
	u.members.pop_back()
	check(Infantry.assigned_capacity(u)==assigned and Infantry.strength(u).assigned_members==3,"removing a dead record cannot make losses disappear")
	var anti:=section(sim,"atgm")
	var holder_id:String=anti.equipment.launcher.holder
	var holder:Dictionary=Infantry.member_by_id(anti,holder_id)
	var assistant:Dictionary=anti.members[1]
	anti.members.reverse()
	check(Infantry.has_equipment(anti,holder,"launcher") and not Infantry.has_equipment(anti,assistant,"launcher"),"launcher ownership survives member-array reordering")
	anti.members.reverse()
	Infantry.wound(anti,holder,Infantry.KIA,2.0,sim.combat_rng)
	Infantry.publish(anti)
	check(not Infantry.strength(anti).launcher_available and not Infantry.has_equipment(anti,assistant,"launcher"),"specialist loss does not silently transfer equipment")
	anti.equipment={}
	Infantry.ensure_roster(anti)
	check(anti.equipment.is_empty(),"explicit empty inventory is never regenerated from member index zero")

func explicit_handover_contract()->void:
	var sim=field()
	var u:=section(sim,"atgm")
	var giver:Dictionary=u.members[0]
	var receiver:Dictionary=u.members[1]
	# Interface only: no autonomous equipment recovery is enabled in M0.
	giver.pos=Vector2(10,50);receiver.pos=Vector2(11,50)
	giver.rounds=0
	var ticket:=Infantry.begin_handover(u,"launcher",receiver.member_id,10.0)
	check(not ticket.is_empty() and Infantry.begin_handover(u,"launcher",receiver.member_id,10.0).is_empty(),"one handover owns the equipment reservation")
	check(not Infantry.complete_handover(u,ticket,11.0) and Infantry.has_equipment(u,giver,"launcher"),"equipment cannot transfer before preparation completes")
	check(Infantry.complete_handover(u,ticket,12.0) and Infantry.has_equipment(u,receiver,"launcher"),"explicit handover moves ownership after preparation")
	check(Infantry.magazine_rounds(receiver,"atgm")==0 and Infantry.magazine_rounds(giver,"atgm")==0,"handover conserves spent launcher ammunition")
	check(not Infantry.complete_handover(u,ticket,12.1),"completed handover cannot apply a second time")
	var replacement:=Infantry.begin_handover(u,"launcher",giver.member_id,20.0)
	u.order_version+=1
	check(not Infantry.complete_handover(u,replacement,22.0) and u.equipment_handovers.is_empty(),"new order cancels a stale handover and releases its reservation")

func garrison_and_campaign()->void:
	var sim=field()
	var u:=section(sim)
	# Use the actual garrison entry and member/combat adapters with a controlled
	# building record; no renderer or window placement is involved in this test.
	sim.set_meta("garrison_index",{"buildings":[{"id":0,"bounds":Rect2(30,26,8,12),"state":0,"capacity":8,"height":8.0}],"owner":{}})
	Garrison.enter(sim,u,0)
	u.members[0].rounds=0
	combat_for(sim,u,2.1)
	check(Garrison.inside(u) and u.members[0].rounds==6,"garrisoned soldier reloads during quiet combat updates")
	var campaign=Campaign.new()
	u.members[1].hp=0.0;u.members[1].wound=Infantry.KIA
	Infantry.publish(u)
	u.members[0].rounds=0
	Infantry.update_readiness(u,u.members[0],sim.time,"rifle")
	var saved:Array=campaign.snapshot(sim)
	check(saved.size()==1 and saved[0].members[0].magazines.rifle==0,"campaign snapshot preserves spent rounds during preparation")
	var next_sim=field()
	var restored:=section(next_sim)
	campaign.restore_unit(next_sim,restored,saved[0])
	check(restored.members[0].rounds==0 and restored.members[0].reload_until==0.0,"campaign transfer preserves inventory and discards transient reload progress")
	check(restored.members[1].wound==Infantry.KIA and restored.members[1].hp==0.0,"campaign transfer does not replace lost personnel")
	check(Infantry.assigned_capacity(restored)==Infantry.assigned_capacity(u) and Infantry.strength(restored).assigned_members==3,"assigned strength survives campaign restoration")
	var next_saved:Array=campaign.snapshot(next_sim)
	check(next_saved==saved,"repeated snapshot and restore preserve durable readiness exactly")

func _init()->void:
	quiet_readiness()
	coordinated_topoff()
	readiness_interruptions()
	covering_eligibility()
	launcher_and_rifle()
	strength_and_equipment()
	explicit_handover_contract()
	garrison_and_campaign()
	print("TACTICAL READINESS: %d checks, %d failures"%[checks,failures])
	quit(1 if failures>0 else 0)
