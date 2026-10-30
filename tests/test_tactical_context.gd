extends SceneTree

const Context=preload("res://scripts/tactical_context.gd")
const Sim=preload("res://scripts/simulation.gd")
var checks:=0
var failures:=0

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func records()->void:
	var context=Context.new()
	context.observe(0,7,"tank",Vector2(10,20),2.0,1)
	var fact:Dictionary=context.team_contact(0,7,5.0)
	check(fact.pos==Vector2(10,20) and fact.observed_at==2.0 and fact.age==3.0,"contact retains observation position and timestamp")
	check(fact.confidence<1.0 and fact.confidence>0.0,"stale observation loses confidence")
	fact.pos=Vector2(99,99)
	check(context.team_contact(0,7,5.0).pos==Vector2(10,20),"consumer cannot mutate authoritative memory")
	context.observe(0,7,"tank",Vector2(40,40),1.0,1)
	check(context.team_contact(0,7,5.0).pos==Vector2(10,20),"late older report cannot overwrite a newer sighting")
	context.observe(0,8,"rifle",Vector2(15,25),3.0,2,false)
	check(context.team_contact(0,8,5.0).is_empty(),"disconnected observation is not uploaded")
	check(not context.local_for(2,8,5.0,0).is_empty(),"disconnected observer retains its own sighting")
	check(context.local_for(1,8,5.0,0).is_empty() and context.team_contact(1,7,5.0).is_empty(),"unrelated observers and opposing teams get no contact")
	check(context.contact_for({"id":2,"team":0},7,5.0,false).is_empty(),"radio loss does not grant another observer's team memory")
	check(context.local_for(2,8,5.0,1).is_empty(),"captured/reassigned observer cannot read its old faction memory")
	check(context.team_contact(0,7,32.0).is_empty(),"observation expires at exact age limit")
	context.expire(33.0)
	check(context.teams.is_empty() and context.observers.is_empty(),"expired contact groups are pruned")
	for id in Context.TEAM_CONTACTS+25:context.observe(0,id,"tank",Vector2(id,20),100.0+id,1)
	check(context.teams[0].size()==Context.TEAM_CONTACTS,"shared contact storage stays bounded")
	check(context.observers[1].contacts.size()==Context.LOCAL_CONTACTS,"local contact storage stays bounded")
	check(not context.teams[0].has(0),"oldest observation is evicted first")

func honest_live_memory()->void:
	var sim=Sim.new(false,0)
	sim.scenario=sim.scenario.duplicate(true);sim.scenario.jam_radius=0
	var scout:Dictionary=sim.spawn("aa",0,Vector2(12,50))
	var enemy:Dictionary=sim.spawn("rifle",1,Vector2(12,40))
	sim.update_visibility()
	check(sim.contact_known(scout,enemy),"real sensor establishes contact")
	check(sim.can_fire(scout,enemy),"observer can actually fire before contact is lost")
	var observed:Vector2=sim.context.team_contact(0,enemy.id,sim.time).pos
	enemy.pos=Vector2(64,10);sim.time+=1.0
	sim.update_visibility()
	check(not sim.contact_known(scout,enemy),"enemy moving outside sight loses live contact")
	check(sim.context.team_contact(0,enemy.id,sim.time).pos==observed,"memory never follows hidden live motion")
	check(not sim.can_fire(scout,enemy),"remembered observation does not authorize a live shot")
	enemy.hp=0.0;sim.time+=1.0;sim.update_visibility()
	check(sim.context.team_contact(0,enemy.id,sim.time).pos==observed,"unseen death does not reveal hidden state")
	var view:Dictionary=sim.situation_view(scout)
	check(view.contacts.size()==1 and view.contacts[0].pos==observed,"situation view exposes copied legitimate facts")
	view.contacts[0].pos=Vector2.ZERO
	check(sim.context.team_contact(0,enemy.id,sim.time).pos==observed,"diagnostic snapshot cannot rewrite knowledge")

func event_wakes()->void:
	var sim=Sim.new(false,0)
	var unit:Dictionary=sim.spawn("rifle",0,Vector2(12,50))
	sim.refresh_tactical_events()
	unit.next_decision=100.0;unit.contact_review=100.0;unit.cover_next=100.0
	unit.members[1].hp=0.0
	sim.Infantry.publish(unit)
	sim.time=1.0;sim.action_tick=30
	sim.refresh_tactical_events()
	check(unit.next_decision<=sim.time and unit.contact_review<=sim.time and unit.cover_next<=sim.time,"casualty wakes delayed tactical reviews")
	check(unit.tactical_wake_reason=="casualty" and unit.tactical_wake_tick==30,"wake trace identifies event and authoritative tick")
	var count:int=sim.actions.event_log.size()
	sim.refresh_tactical_events()
	check(sim.actions.event_log.size()==count,"unchanged facts do not emit repeated wakes")
	unit.hp=0.0;sim.refresh_tactical_events()
	check(sim.actions.active(unit).is_empty(),"lost owner releases pending action ownership")

func run()->void:
	records();honest_live_memory();event_wakes()
	print("TACTICAL CONTEXT: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func _init()->void:call_deferred("run")
