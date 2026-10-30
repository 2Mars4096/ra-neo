extends SceneTree

const Actions=preload("res://scripts/tactical_actions.gd")
var checks:=0
var failures:=0

func _init()->void:call_deferred("run")

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: ",label)

func unit(id:int=1)->Dictionary:
	var u:Dictionary={"id":id,"team":0,"hp":100.0,"pos":Vector2(10,20)}
	Actions.ensure_unit(u)
	return u

func reservations_and_release()->void:
	var registry=Actions.new()
	var u:=unit()
	var other:=unit(2)
	var target:Dictionary={"unit":8,"snapshot":{"pos":Vector2(15,20)}}
	var first:Dictionary=registry.begin(u,"reload",0.0,{"channel":"weapon","claims":["magazine:1","magazine:1"],"target":target})
	check(not first.is_empty() and first.claims.size()==1,"one action owns each claim once")
	target.snapshot.pos=Vector2(90,90)
	check(first.target.snapshot.pos==Vector2(15,20),"action keeps a copied target snapshot")
	var competing:Dictionary=registry.begin(other,"reload",0.0,{"claims":["unused:2","magazine:1"]})
	check(competing.is_empty() and not registry.claims.has("unused:2"),"failed multi-claim reservation leaves no partial claim")
	check(registry.begin(u,"aim",0.0,{"channel":"weapon"}).is_empty(),"one actor cannot use its weapon channel twice")
	check(not registry.complete(u,first,0.0),"reserved work cannot report success before execution")
	check(not registry.commit(u,first,"magazine:1",0.0),"resources cannot commit during reservation")
	check(registry.transition(u,first,"preparing",0.1),"reserved action enters preparation")
	check(not registry.complete(u,first,0.1),"preparation cannot count as completed work")
	check(registry.transition(u,first,"executing",0.2),"prepared action starts execution")
	check(not registry.transition(u,first,"preparing",0.2),"executing action cannot rewind to preparation")
	check(not registry.commit(other,first,"magazine:1",0.2),"another unit cannot consume this action's resource")
	check(not registry.commit(u,first.duplicate(true),"magazine:1",0.2),"copied stale handles cannot commit a live action")
	var inventory:=1
	if registry.commit(u,first,"magazine:1",0.3):inventory-=1
	check(inventory==0,"execution commits the reserved item")
	check(not registry.commit(u,first,"magazine:1",0.3),"a committed resource cannot be consumed twice")
	check(registry.cancel(u,first,0.4,"order_replaced"),"released work can relinquish its actor")
	check(inventory==0 and first.committed==["magazine:1"],"cancellation retains expenditure and cannot refund executor-owned inventory")
	check(registry.claims.is_empty() and registry.owners.is_empty() and registry.actions.is_empty(),"cancellation releases all actor and role reservations")
	check(not registry.complete(u,first,0.5),"a cancelled action cannot later finish or restore old work")
	check(u.last_action.phase=="cancelled" and u.last_action.reason=="order_replaced","terminal action records a concise outcome")
	var cancelled_preparation:Dictionary=registry.begin(u,"reload",0.5,{"claims":["magazine:2"]})
	registry.transition(u,cancelled_preparation,"preparing",0.6)
	registry.cancel(u,cancelled_preparation,0.7)
	check(cancelled_preparation.committed.is_empty() and not registry.claims.has("magazine:2"),"interrupted preparation releases its unspent reservation")

func intent_and_child_actions()->void:
	var registry=Actions.new()
	var u:=unit()
	var order:Dictionary={"mode":"attack_move","pos":Vector2(40,20),"target":-1}
	check(registry.accept_order(u,order,0.0)==1,"received replacement creates a new intent version")
	var assignment:int=u.assignment.id
	for i in 2:
		var child:Dictionary=registry.begin(u,"reposition",float(i),{"channel":"movement","target":{"pos":Vector2(15+i,20)}})
		registry.transition(u,child,"executing",float(i))
		check(registry.complete(u,child,float(i)+0.1),"executor-owned reposition %d completes"%i)
	check(u.order_version==1 and u.assignment.id==assignment and u.assignment.pos==order.pos,"multiple child moves preserve the parent objective and version")
	var old:Dictionary=registry.begin(u,"reload",2.0,{"channel":"weapon","claims":["magazine:1"]})
	registry.accept_order(u,{"mode":"hold","pos":u.pos},2.1)
	check(u.order_version==2 and u.assignment.id>assignment,"replacement changes intent and assignment identity")
	check(old.phase=="cancelled" and old.reason=="order_replaced" and registry.claims.is_empty(),"replacement cancels the old action and frees its claim")
	check(not registry.transition(u,old,"executing",2.2),"a late old executor cannot overwrite replacement orders")
	var queued:Dictionary=registry.begin(u,"aim",2.3,{"channel":"weapon"})
	var version:int=u.order_version
	registry.activate_order(u,{"mode":"move","pos":Vector2(60,20)},2.4)
	check(u.order_version==version and u.assignment.id>assignment,"advancing an accepted queue changes assignment but retains player-intent version")
	check(queued.phase=="cancelled" and queued.reason=="assignment_changed","next queued assignment cancels the previous executor")

func expiration_and_backoff()->void:
	var registry=Actions.new()
	var u:=unit()
	var action:Dictionary=registry.begin(u,"reposition",0.0,{"deadline":1.0,"claims":["position:1"]})
	registry.transition(u,action,"executing",0.0)
	registry.expire(u,1.0)
	check(action.phase=="failed" and action.reason=="deadline" and registry.claims.is_empty(),"timed-out work fails and releases its reservation")
	check(registry.begin(u,"reposition",1.1).is_empty(),"timeout backs off repeated attempts at the same action")
	check(not registry.begin(u,"aim",1.1,{"channel":"weapon"}).is_empty(),"failed movement does not prevent another useful action")
	check(not registry.begin(u,"reposition",2.0).is_empty(),"bounded failure backoff eventually admits another attempt")
	registry.accept_order(u,{"mode":"hold"},2.1)
	check(registry.retry_after.is_empty(),"new valid order clears obsolete failure backoff")
	var stale:Dictionary=registry.begin(u,"reposition",2.2,{"claims":["position:2"]})
	u.order_version+=1
	check(not registry.transition(u,stale,"executing",2.3),"stale result is rejected even before ordinary cleanup runs")
	check(stale.phase=="cancelled" and stale.reason=="stale_order" and registry.retry_after.is_empty(),"stale-order cancellation does not penalize the replacement assignment")
	var down:Dictionary=registry.begin(u,"aim",3.0,{"claims":["weapon:1"]})
	u.hp=0.01;u.combat_ineffective=true
	registry.expire(u,3.1)
	check(down.phase=="cancelled" and down.reason=="owner_lost","all-downed section loses its action despite its selectable HP sentinel")
	check(registry.begin(u,"reload",3.2).is_empty() and registry.claims.is_empty(),"incapacitated owners cannot reserve new work")
	u.combat_ineffective=false;u.hp=100.0
	var resumed:Dictionary=registry.begin(u,"reload",3.3)
	check(not resumed.is_empty(),"recovered capability can act without a stale cancellation penalty")
	u.hp=0.0
	registry.fail(u,resumed,3.4)
	check(resumed.phase=="cancelled" and resumed.reason=="owner_lost","late failure notification for a lost owner remains cancellation")

func observed_executors()->void:
	var registry=Actions.new()
	var u:=unit()
	var observed:Dictionary=registry.observe_existing(u,"member:1:weapon","reload",0.0,{"weapon":"rifle"},"reloading")
	check(not observed.is_empty() and observed.phase=="executing","legacy reload is adapted as executing work")
	var action_id:int=observed.id
	var event_count:int=registry.event_log.size()
	for i in 30:
		observed=registry.observe_existing(u,"member:1:weapon","reload",float(i+1)/10.0,{"weapon":"rifle"},"reloading")
	check(observed.id==action_id and observed.started==0.0,"ordinary executor heartbeats preserve action identity and start time")
	check(registry.event_log.size()==event_count,"unchanged heartbeats do not flood decision traces")
	check(registry.valid(u,observed,3.5),"active executor keeps its observation lease alive")
	var aim:Dictionary=registry.observe_existing(u,"member:1:weapon","aim",3.5,{"unit":4,"member":0},"aiming")
	check(observed.phase=="cancelled" and aim.id!=action_id and aim.kind=="aim","changed physical work replaces the observed action")
	check(registry.complete(u,aim,3.6),"adapted work can finish normally")
	var count:int=registry.actions.size()
	check(registry.observe_existing(u,"weapon","aim",4.0,{},"aiming","completed").is_empty() and registry.actions.size()==count,"invalid observed terminal phase cannot leave an orphan reservation")
	check(registry.begin(u,"reload",NAN).is_empty() and registry.actions.size()==count,"invalid time cannot poison action state")
	var orphan:Dictionary=registry.observe_existing(u,"weapon","aim",4.0,{"unit":7},"aiming")
	registry.expire(u,7.0)
	check(orphan.phase=="failed" and orphan.reason=="deadline","an executor that stops reporting does not retain a channel forever")

func fire_permissions()->void:
	var registry=Actions.new()
	var u:=unit()
	check(Actions.engagement_allowed(u,7),"free-fire policy permits ordinary engagement")
	u.fire_policy="hold"
	check(not Actions.engagement_allowed(u,7),"Hold fire blocks autonomous engagement")
	registry.accept_order(u,{"mode":"attack_move","pos":Vector2(20,20)},0.0)
	check(not Actions.engagement_allowed(u,7),"attack-move does not silently override Hold fire")
	registry.accept_order(u,{"mode":"attack","target":7},0.1)
	check(Actions.engagement_allowed(u,7) and not Actions.engagement_allowed(u,8),"explicit attack grants permission only for the requested target")
	check(not Actions.engagement_allowed(u,-1),"explicit attack never authorizes an unspecified target")
	Actions.revoke_permission(u)
	check(not Actions.engagement_allowed(u,7),"revoking the scoped permission immediately prevents release")
	registry.activate_order(u,{"mode":"attack","target":8,"permission_revoked":true},0.2)
	check(not Actions.engagement_allowed(u,8),"a queued attack with revoked permission stays revoked")
	registry.accept_order(u,{"mode":"attack","target":9},0.3)
	check(Actions.engagement_allowed(u,9),"a fresh explicit attack can grant fresh permission")
	u.order_version+=1
	check(not Actions.engagement_allowed(u,9),"expired-order permission cannot authorize a late shot")
	registry.accept_order(u,{"mode":"move","pos":Vector2(30,20)},0.4)
	check(not Actions.engagement_allowed(u,9),"replacement movement restores the standing Hold fire policy")

func budgets_and_diagnostics()->void:
	var registry=Actions.new()
	check(not registry.take_work("line_checks"),"planning needs an active simulation tick")
	check(registry.begin_tick(1,{"line_checks":2,"route_searches":1}),"new tick establishes deterministic work limits")
	check(registry.take_work("line_checks",2) and not registry.take_work("line_checks"),"line-query admission cannot exceed the tick allowance")
	check(not registry.take_work("line_checks",0) and not registry.take_work("unknown"),"invalid work cannot mint capacity")
	check(not registry.begin_tick(1) and not registry.begin_tick(0) and not registry.take_work("line_checks"),"duplicate or older ticks cannot reset spent work")
	check(registry.begin_tick(2) and registry.take_work("line_checks",2),"following tick receives a fresh allowance")
	var u:=unit()
	for i in Actions.MAX_EVENTS+5:registry.invalidate(u,float(i),"known_contact")
	check(registry.event_log.size()==Actions.MAX_EVENTS,"decision history remains bounded during a long encounter")
	check(registry.event_log.front().id==6 and registry.event_log.back().id==Actions.MAX_EVENTS+5,"bounded traces retain stable monotonic event identities")
	check(registry.event_log.back().tick==2 and registry.event_log.back().unit==u.id,"trace identifies simulation tick and affected unit")
	check(Actions.reason_text("reloading")=="Reloading" and Actions.reason_text("stale_order")=="Order replaced","diagnostic reasons have concise display text")
	var replay=Actions.new()
	var v:=unit()
	replay.begin_tick(2,{"line_checks":2,"route_searches":1})
	for i in Actions.MAX_EVENTS+5:replay.invalidate(v,float(i),"known_contact")
	check(replay.event_log==registry.event_log,"same authoritative inputs produce the same action traces")

func run()->void:
	reservations_and_release()
	intent_and_child_actions()
	expiration_and_backoff()
	observed_executors()
	fire_permissions()
	budgets_and_diagnostics()
	print("TACTICAL ACTIONS: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
