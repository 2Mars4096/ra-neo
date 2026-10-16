extends SceneTree
# A section sheltered beside a building kills the enemy it was shooting; a
# second enemy section stays in view beyond rifle reach of every shelter. The
# section must hold and observe (no ENGAGE advance, shelters kept) for a few
# seconds, then still close on the remaining threat. A fresh section in the
# open with a visible enemy beyond reach advances promptly.
const Sim=preload("res://scripts/simulation.gd")
const Garrison=preload("res://scripts/garrison.gd")
const HOLD_CHECK:=3.0
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)
func harbor_index()->int:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		if configs[i].id=="black_sea_harbor":return i
	return -1
func sheltered(u:Dictionary)->int:
	return u.members.filter(func(m):return m.hp>0 and m.get("cover_phase","") in ["SETTLING","SHELTERED"]).size()
func engage_planned(sim,u:Dictionary)->bool:
	var planned:=false
	for e in sim.events:
		if e.get("type","")=="decision" and e.unit==u.id and e.phase=="ENGAGE":planned=true
	sim.events.clear()
	return planned
# Runs one site; returns {} when the setup did not reach the trigger.
func run_site(start:Vector2,e1:Vector2,e2:Vector2)->Dictionary:
	var sim=Sim.new(false,harbor_index())
	var a:Dictionary=sim.spawn("rifle",0,start)
	var near:Dictionary=sim.spawn("rifle",1,e1)
	var far:Dictionary=sim.spawn("rifle",1,e2)
	near.hold_command=true;far.hold_command=true
	for m in near.members:m.cooldown=1000
	var killed:=-1.0
	for i in 360:
		sim.tick(1.0/30)
		if engage_planned(sim,a):return {}
		if a.target==near.id and sheltered(a)==a.members.size():
			# The section's shot drops the visible enemy: its target goes to -1.
			for m in near.members:m.hp=0.0
			near.hp=0.0;killed=sim.time;break
	if killed<0:return {}
	var result:={"left_cover":-1.0,"engaged":-1.0,"threat_known":true,"min_sheltered":a.members.size()}
	for i in 450:
		sim.tick(1.0/30)
		var t:float=sim.time-killed
		if t<=HOLD_CHECK:
			result.threat_known=result.threat_known and sim.contact_known(a,far)
			result.min_sheltered=mini(result.min_sheltered,sheltered(a))
			if result.left_cover<0 and (a.maneuver.get("phase","")=="ENGAGE" or sheltered(a)==0):result.left_cover=t
		if engage_planned(sim,a) and result.engaged<0:result.engaged=t
		if result.engaged>=0 and t>HOLD_CHECK:break
	return result
func _init()->void:
	var sim=Sim.new(false,harbor_index())
	var data:Dictionary=Garrison.index(sim)
	var radius:float=sim.definitions.rifle.radius
	var reach:float=sim.definitions.rifle.range
	var result:={}
	var sites:=0
	for b in data.buildings:
		var door:=Garrison.entry_point(sim,b.id,b.bounds.get_center()+Vector2(0,30))
		if door.x<0:continue
		var start:=door+Vector2(0,3)
		var e1:=start+Vector2(-3,11)
		var e2:=start+Vector2(0,19)
		# The old director's ENGAGE point toward the far enemy must be open ground.
		var desired:=e2+(start-e2).normalized()*reach*0.8
		if [start,e1,e2,desired].any(func(p):return not sim.terrain.traversable(p,"land",2.65)):continue
		if not sim.terrain.line_clear(start,e1) or not sim.terrain.line_clear(start,e2):continue
		if sim.terrain.path(start,desired,"land",radius,[],sim.terrain.mobility_profile("rifle")).is_empty():continue
		sites+=1
		result=run_site(start,e1,e2)
		if not result.is_empty():
			print("site building ",b.id," start=",start," far enemy %.1f m" % start.distance_to(e2))
			break
		if sites>=12:break
	check(not result.is_empty(),"found a site where the section shelters and then loses its target (%d tried)" % sites)
	if not result.is_empty():
		print("after target loss: left_cover=%.2f engage_at=%.2f min_sheltered=%d threat_known=%s" % [result.left_cover,result.engaged,result.min_sheltered,result.threat_known])
		check(result.threat_known,"far enemy stays a known threat during the hold")
		check(result.left_cover<0,"sheltered section does not leave cover within %.1f s of losing its target" % HOLD_CHECK)
		check(result.min_sheltered>=2,"shelters are kept during the hold (min %d)" % result.min_sheltered)
		check(result.engaged>HOLD_CHECK and result.engaged<HOLD_CHECK+8.0,"the hold is bounded: section then closes on the remaining threat (%.2f s)" % result.engaged)
	# Proactive engagement: a fresh section with a visible enemy beyond reach closes promptly.
	var open=Sim.new(false,harbor_index())
	var ours:Dictionary=open.spawn("rifle",0,Vector2(290,640))
	var theirs:Dictionary=open.spawn("rifle",1,Vector2(307,640))
	theirs.hold_command=true
	var advanced:=-1.0
	for i in 90:
		open.tick(1.0/30)
		if engage_planned(open,ours):advanced=open.time;break
	print("fresh section advance at %.2f s" % advanced)
	check(advanced>=0 and advanced<2.0,"fresh section advances on a visible enemy beyond reach within 2 s")
	print("ENGAGE HOLD: ",checks," checks, ",failures," failures")
	quit(1 if failures>0 else 0)
