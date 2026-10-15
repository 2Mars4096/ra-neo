extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Actors=preload("res://scripts/infantry.gd")
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		if failures<=12:printerr("FAIL: ",label)
func _init()->void:
	var sim=Sim.new(true,3)
	check(sim.issue([1,2,3,4],sim.objectives[0].pos,"attack_move")==4,"single initial land order accepted")
	check(sim.issue([5],Vector2(36,28))==1,"single initial scout order accepted")
	var snapshots:Array=[]
	var previous:Dictionary={}
	var first_completion:Dictionary={}
	var original_intents:Array=[]
	var original_groups:Array=[]
	for id in [1,2,3]:
		original_intents.append(sim.get_unit(id).intent.duplicate())
		original_groups.append(sim.get_unit(id).command_group)
	for frame in 1800:
		sim.tick(1.0/30.0)
		sim.events.clear()
		check_actors(sim,previous)
		record_completions(sim,first_completion)
		if frame in [1799]:
			for id in [1,2,3]:
				var u:Dictionary=sim.get_unit(id)
				snapshots.append({"id":id,"position":[u.pos.x,u.pos.y],"hp":u.hp,"orders_remaining":u.orders.size(),"regroup_count":u.get("regroup_count",0),"max_member_gap":u.members.reduce(func(g,m):return maxf(g,m.pos.distance_to(u.pos)) if m.hp>0 else g,0.0)})
				print("REGROUP SNAPSHOT t=",roundi(sim.time)," squad=",id," pos=",u.pos," hp=",u.hp," blocked=",u.blocked_time," target=",u.target," orders=",u.orders," maneuver=",u.maneuver," path=",u.path)
				for m in u.members:
					print(" actor=",m.index," pos=",m.pos," phase=",m.get("cover_phase","")," occupying=",m.get("occupying",false)," goal=",m.cover_goal," cover_path=",m.get("cover_path",[])," gap=",m.pos.distance_to(u.pos)," regroup=",m.get("regroup_path",[]))
	check(sim.get_unit(1).pos.distance_to(Vector2(21.7,11.2))>6,"squad one escapes the reproduced villa stall")
	check(sim.get_unit(2).pos.distance_to(Vector2(16.6,30))>6,"squad two escapes the reproduced cafe stall")
	for id in [1,2,3]:
		var u:Dictionary=sim.get_unit(id)
		check(u.hp>0,"mission section survives recovery: %s"%id)
		check(u.members.all(func(m):return reunited(sim,m,u)),"all live section members reunite after contact: %s"%id)
		check(u.get("regroup_count",0)>0,"section completed a bounded regroup: %s"%id)
	check(sim.get_unit(1).orders.is_empty(),"first section completes its village order without reissue")
	check(sim.get_unit(3).pos.x>30,"AT section escapes villa and advances toward village")
	for frame in 900:
		sim.tick(1.0/30.0);sim.events.clear()
		check_actors(sim,previous)
		record_completions(sim,first_completion)
	for id in [1,2,3]:
		check(completed_attack_move(sim,sim.get_unit(id)),"all sections complete single attack-move: %s"%id)
		check(sim.get_unit(id).blocked_time<1,"no residual group congestion: %s"%id)
	check([sim.get_unit(1).command_group,sim.get_unit(2).command_group,sim.get_unit(3).command_group]==original_groups,"no player command reissue during recovery")
	for id in [1,2,3]:check(sim.get_unit(id).intent==original_intents[id-1],"original objective retained: %s"%id)
	print("FIRST ORDER COMPLETIONS: ",first_completion)
	print("VILLAGE owner=",sim.objectives[0].owner," progress=",sim.objectives[0].progress)
	run_wall_recovery()
	run_standoff_cover()
	var evidence:=FileAccess.open("/private/tmp/ra-regroup-owner-evidence.json",FileAccess.WRITE)
	if evidence!=null:evidence.store_string(JSON.stringify({"checks":checks,"failures":failures,"seconds":90,"snapshots_at_60":snapshots,"first_order_completions":first_completion,"orders_at_90":[sim.get_unit(1).orders,sim.get_unit(2).orders,sim.get_unit(3).orders],"village_owner":sim.objectives[0].owner,"native_render_review":false},"  "))
	print("REGROUP RECOVERY: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)

func run_wall_recovery()->void:
	for command in ["attack_move","move","retreat","hold"]:
		var sim=Sim.new(false,3)
		var u=sim.spawn("rifle",0,Vector2(21.7,11.2))
		var actor:Dictionary=u.members.back()
		actor.pos=Vector2(14.0,17.2)
		var start:Vector2=actor.pos
		check(sim.terrain.traversable(start,"land",0.8) and start.distance_to(u.pos)<10,"wall fixture starts clear inside leash")
		check(not sim.terrain.segment_clear(start,u.pos+actor.offset,"land",0.8),"wall obstructs direct formation return")
		if command=="hold":sim.stop([u.id])
		elif command=="retreat":check(sim.retreat([u.id])==1,"retreat command accepted")
		else:check(sim.issue([u.id],Vector2(39,22),command)==1,"new "+command+" accepted")
		var goal:Vector2=u.orders[0].pos if not u.orders.is_empty() else u.pos
		var reunion:=false
		var routed:=false
		for frame in 600:
			var old:Vector2=actor.pos
			sim.tick(1.0/30.0);sim.events.clear()
			routed=routed or not actor.get("regroup_path",[]).is_empty()
			reunion=reunion or actor.pos.distance_to(u.pos)<2.8
			check(actor.pos.distance_to(old)<0.3,"return uses continuous movement")
			check(actor.pos.distance_to(u.pos)<=10.001,"return preserves leash")
			check(sim.terrain.segment_clear(old,actor.pos,"land",actor.body_radius),"return preserves swept terrain clearance")
			for peer in u.members:
				if peer.index!=actor.index:check(actor.pos.distance_to(peer.pos)>=1.54,"return preserves actor separation")
		if command=="hold":
			check(actor.pos==start and u.hold_command and u.maneuver.is_empty(),"hold prevents regroup departure")
		else:
			check(routed and reunion,"actor routes around villa and reunites under "+command)
			check(u.pos.distance_to(goal)<6,"section progresses after reunion under "+command)
			if command in ["move","retreat"]:check(u.maneuver.is_empty(),"explicit command is not replaced by autonomy")

func check_actors(sim,previous:Dictionary)->void:
	var bodies:Array=[]
	for u in sim.living(0):
		if sim.definitions[u.kind].domain!="land":continue
		if u.members.is_empty():
			bodies.append({"pos":u.pos,"radius":sim.definitions[u.kind].radius})
		else:
			for m in u.members:
				if m.hp<=0:continue
				var key:=str(u.id)+":"+str(m.index)
				if previous.has(key):
					check(m.pos.distance_to(previous[key])<0.3,"mission actor moves continuously")
					check(sim.terrain.segment_clear(previous[key],m.pos,"land",m.body_radius),"mission actor swept terrain clearance")
				previous[key]=m.pos
				bodies.append({"pos":m.pos,"radius":m.body_radius,"soldier":true})
	for i in bodies.size():
		for j in range(i+1,bodies.size()):
			# Soldiers may squeeze shoulder to shoulder past each other (never
			# through each other); vehicles keep their full clearance.
			var soldiers:bool=bodies[i].get("soldier",false) and bodies[j].get("soldier",false)
			var minimum:float=0.6 if soldiers else bodies[i].radius+bodies[j].radius-0.051
			check(bodies[i].pos.distance_to(bodies[j].pos)>=minimum,"mission real actors preserve separation")

func run_standoff_cover()->void:
	var sim=Sim.new(false,3)
	var squad=sim.spawn("atgm",0,Vector2(39.86221,7.755771))
	var threat=sim.spawn("rifle",1,Vector2(34.41422,24.41421))
	check(threat.members.size()==3,"regression retains three rifle soldiers")
	for i in 3:
		check(threat.members[i].offset==Actors.formation_offset(i,3),"regression retains triangle slot: %s"%i)
	sim.update_visibility()
	check(sim.contact_known(squad,threat),"standoff fixture uses an observed contact")
	check(sim.can_fire(squad,threat),"standoff fixture has a valid outgoing shot")
	check(not Actors.Cover.in_weapon_range(threat,squad,sim),"rifles cannot reach the standoff section")
	Actors.Cover.update(squad,sim)
	check(not Actors.Cover.seeking(squad),"safe outgoing fire does not trigger a shelter excursion")
	# Test the range predicate independently of geometry and enemy knowledge.
	threat.members[0].pos=squad.pos+Vector2(10,0)
	check(Actors.Cover.in_weapon_range(threat,squad,sim),"a living rifle inside weapon range remains a threat")
	threat.members[0].hp=0
	check(not Actors.Cover.in_weapon_range(threat,squad,sim),"a dead forward rifle cannot create a threat envelope")
	var mixed=sim.spawn("atgm",1,Vector2(55,7))
	for m in mixed.members:m.pos=squad.pos+Vector2(17,0)
	check(Actors.Cover.in_weapon_range(mixed,squad,sim),"living launcher contributes its longer weapon range")
	mixed.members[0].hp=0
	check(not Actors.Cover.in_weapon_range(mixed,squad,sim),"surviving rifle does not inherit dead launcher range")

# A soldier rejoins within 2.8 u of the section anchor. Cover legitimately posts
# soldiers further out, which counts only while that shelter is inside the
# section leash: halt-in-cover (`occupying` a wall/prop slot, up to 8 u away),
# or a combat shelter taken while the section is still in contact (the same
# alert rule Cover uses: suppressed, or a known enemy within 25 u that threatens
# it). Without contact Cover expires combat shelters and the soldier must rejoin.
func reunited(sim,m:Dictionary,u:Dictionary)->bool:
	if m.hp<=0 or m.pos.distance_to(u.pos)<2.8:return true
	if m.pos.distance_to(u.pos)>Actors.Cover.LEASH:return false
	if m.get("occupying",false):return true
	return m.get("cover_phase","") in ["SEEKING","SETTLING","SHELTERED"] and m.cover_goal.distance_to(u.pos)<=Actors.Cover.LEASH and in_contact(sim,u)

func in_contact(sim,u:Dictionary)->bool:
	if u.suppression>0.2:return true
	for other in sim.units:
		if not sim.alive(other) or other.team==u.team or not sim.contact_known(u,other) or not sim.effective_unit(other,u.kind):continue
		if sim.can_fire(u,other) and not Actors.Cover.in_weapon_range(other,u,sim):continue
		if u.pos.distance_squared_to(other.pos)<625:return true
	return false

# The single attack-move is complete when the sim consumes its order (the anchor
# reached the end of its path), or when the section stands on its objective
# (within its crowd radius, the spacing at which sections share an attack-move
# arrival) still holding that same order because it is fighting there: its
# current target is a live enemy, or it fired within the last 2 s.
func completed_attack_move(sim,u:Dictionary)->bool:
	if u.orders.is_empty():return true
	if u.orders.size()!=1 or u.orders[0].mode!="attack_move" or u.pos.distance_to(u.orders[0].pos)>sim.crowd_radius(u.kind):return false
	var target:Dictionary=sim.get_unit(u.target)
	return (sim.alive(target) and target.team!=u.team) or sim.time-float(u.last_shot)<2.0

func record_completions(sim,first_completion:Dictionary)->void:
	for id in [1,2,3]:
		if not first_completion.has(id) and sim.get_unit(id).orders.is_empty():
			first_completion[id]=sim.time
