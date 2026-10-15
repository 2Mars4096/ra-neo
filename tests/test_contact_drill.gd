extends SceneTree
# Infantry contact tactics: posture in shelter and under fire, fire from cover,
# shelter re-evaluation on a new threat bearing, crossfire, and the contact
# drill (drop, return fire, then one soldier rushes at a time).
const Sim=preload("res://scripts/simulation.gd")
const Cover=preload("res://scripts/cover_behavior.gd")
const Director=preload("res://scripts/tactical_director.gd")
const WALL:=Rect2(8,35,8,6)
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func field(wall:bool=false):
	var sim=Sim.new(false,0)
	sim.scenario=sim.scenario.duplicate(true)
	sim.scenario.autonomy=true
	if wall:
		sim.terrain.style="showcase"
		sim.terrain.dynamic_blocks.append(WALL)
		# Scenario 0's rubble field overlaps the wall's north side; isolate the wall.
		sim.terrain.rubble=Rect2()
	return sim

# An enemy that is observed, stays put and holds its fire.
func silent(sim,kind:String,pos:Vector2)->Dictionary:
	var enemy:Dictionary=sim.spawn(kind,1,pos)
	enemy.cooldown=100000.0
	for m in enemy.members:m.cooldown=100000.0
	sim.stop([enemy.id])
	return enemy

func step(sim,seconds:float)->void:
	for i in int(round(seconds*30)):
		sim.tick(1.0/30);sim.events.clear()

func sheltered_soldiers_crouch()->void:
	var sim=field()
	var squad:Dictionary=sim.spawn("rifle",0,Vector2(18,55))
	var m:Dictionary=squad.members[0]
	# A combat shelter (not manning works) and no target in sight.
	m.cover_goal=m.pos;m.cover_phase="SHELTERED";m.cover_path=[];m.cover_deadline=sim.time+100.0
	m.occupying=false
	for i in 3:sim.infantry_combat(squad,1.0/30)
	check(m.target<0 and m.posture=="CROUCHED","soldier in a combat shelter without a target crouches (%s)" % m.posture)
	check(squad.members[1].posture=="STANDING","soldier in the open with no contact stays standing")

func cover_keeps_line_of_fire()->void:
	var sim=field(true)
	var squad:Dictionary=sim.spawn("rifle",0,Vector2(18,44))
	var enemy:=silent(sim,"rifle",Vector2(19,31))
	sim.update_visibility()
	check(sim.contact_known(squad,enemy),"fire-from-cover fixture observes the enemy")
	var member:Dictionary=squad.members[0]
	var slot:Dictionary=Cover.find_slot(squad,member,sim,enemy,[enemy])
	var pos:Vector2=slot.get("pos",Vector2.ZERO)
	var reach:float=float(sim.definitions.rifle.range)
	print("  fire-from-cover slot=",pos," clear=",sim.terrain.line_clear(enemy.pos,pos)," dist=%.1f" % pos.distance_to(enemy.pos))
	check(not slot.is_empty() and sim.terrain.cover(pos),"a shelter is found beside the wall")
	check(sim.terrain.line_clear(pos,enemy.pos) and pos.distance_to(enemy.pos)<=reach,"chosen shelter keeps a line of fire to the enemy")
	check(Cover.corner(sim,pos,enemy),"the firing shelter is a wall corner (a side-step is screened)")
	# Live: the section takes the firing shelters, shoots from them and is not
	# pulled out of cover by the idle-engage rule.
	var engaged:=false
	var fired_from_cover:=false
	for i in 240:
		sim.tick(1.0/30);sim.events.clear()
		if squad.maneuver.get("phase","")=="ENGAGE":engaged=true
		for m in squad.members:
			if m.hp>0 and m.get("cover_phase","")=="SHELTERED" and sim.time-float(m.last_shot)<0.1:fired_from_cover=true
	for m in squad.members:print("  member ",m.index," phase=",m.get("cover_phase","")," pos=",m.pos," target=",m.target," posture=",m.posture," shot=%.1f" % m.last_shot)
	check(fired_from_cover,"a sheltered soldier fires from cover")
	check(not engaged,"a section firing from cover is not pulled out to engage")

# A wall-face shelter taken while only suppressed (no known shooter) is checked
# when the shooter becomes known: abandoned if he sees it and cannot be answered
# from it (tank), kept as a fire-from-cover position if he can (rifles in reach).
func recheck_fixture(kind:String)->Dictionary:
	var sim=field(true)
	var squad:Dictionary=sim.spawn("rifle",0,Vector2(17.5,37))
	var m:Dictionary=squad.members[0]
	var face:=Vector2.ZERO
	for x in range(15,8,-1):
		if sim.terrain.cover(Vector2(x,33.95)) and not Cover.soft_cover(sim,Vector2(x,33.95)):face=Vector2(x,33.95);break
	check(face!=Vector2.ZERO,"fixture finds a hard wall face")
	squad.suppression=0.5
	m.pos=face;m.cover_goal=m.pos;m.cover_phase="SHELTERED";m.cover_path=[]
	m.cover_until=0.0;m.cover_deadline=sim.time+100.0;m.cover_screened=false;m.cover_from=Vector2.ZERO
	sim.update_visibility()
	Cover.update(squad,sim)
	check(m.cover_goal==face,"shelter kept while no shooter is known")
	var enemy:=silent(sim,kind,Vector2(face.x,26))
	enemy.seen_by[0]=true
	check(sim.contact_known(squad,enemy) and sim.terrain.line_clear(enemy.pos,face),"shooter now observed and sees the shelter")
	Cover.update(squad,sim)
	print("  %s: wall face=%s re-evaluated goal=%s phase=%s" % [kind,str(face),str(m.cover_goal),m.get("cover_phase","")])
	return {"sim":sim,"member":m,"face":face,"enemy":enemy}

func shelter_rechecked_on_new_threat()->void:
	var f:=recheck_fixture("tank")
	check(f.member.cover_goal!=f.face,"shelter seen by a newly known tank it cannot answer is abandoned")
	if f.member.cover_goal!=Vector2.ZERO:
		check(not f.sim.terrain.line_clear(f.enemy.pos,f.member.cover_goal),"replacement shelter is screened from the tank")
	f=recheck_fixture("rifle")
	check(f.member.cover_goal==f.face,"shelter with a shot at newly known rifles is kept (fire from cover)")

func crossfire()->void:
	# Open ground: threats from two bearings and no shelter -> go prone.
	var sim=field()
	var squad:Dictionary=sim.spawn("rifle",0,Vector2(18,55))
	silent(sim,"rifle",Vector2(18,40))
	silent(sim,"rifle",Vector2(33,55))
	squad.suppression=0.4
	squad["fired_on"]=0.0
	sim.update_visibility()
	squad["drill_seen"]=0.0
	for i in 90:
		sim.time+=1.0/30
		sim.Infantry.move(squad,sim,1.0/30)
		sim.infantry_combat(squad,1.0/30)
	var open:int=0;var prone:int=0;var sheltered:int=0
	for m in squad.members:
		if m.get("cover_phase","") in ["SEEKING","SETTLING","SHELTERED"]:sheltered+=1
		elif sim.terrain.cover(m.pos)==false:
			open+=1
			if m.posture=="PRONE":prone+=1
	for m in squad.members:print("  crossfire member ",m.index," phase=",m.get("cover_phase","")," posture=",m.posture," pos=",m.pos)
	print("  crossfire open=",open," prone=",prone," sheltered=",sheltered," crossfire=",squad.get("crossfire",false))
	check(squad.get("crossfire",false),"two bearings register as crossfire")
	check(open>0 and prone==open,"in crossfire with no shelter soldiers go prone")
	# Beside a wall: the slot must screen the main (strongest) threat or have a
	# shot at it, and never lie open to a threat it cannot answer.
	var walled=field(true)
	var section:Dictionary=walled.spawn("rifle",0,Vector2(18,44))
	var tank:=silent(walled,"tank",Vector2(12,27))
	var rifles:=silent(walled,"rifle",Vector2(27,47))
	walled.update_visibility()
	tank.seen_by[0]=true;rifles.seen_by[0]=true
	var threats:Array=[rifles,tank]
	var main:Dictionary=rifles if Cover.power(rifles)/section.pos.distance_to(rifles.pos)>Cover.power(tank)/section.pos.distance_to(tank.pos) else tank
	section.suppression=0.4
	section["drill_seen"]=0.0
	for i in 150:
		walled.time+=1.0/30
		walled.Infantry.move(section,walled,1.0/30)
		walled.infantry_combat(section,1.0/30)
	check(section.get("crossfire",false),"wall fixture registers crossfire")
	for m in section.members:
		var phase:String=m.get("cover_phase","")
		print("  crossfire wall member ",m.index," phase=",phase," posture=",m.posture," goal=",m.cover_goal," pos=",m.pos)
		if phase in ["SEEKING","SETTLING","SHELTERED"]:
			var rating:=Cover.rate(walled,m.cover_goal,main,threats,"rifle")
			check(rating.ok and (rating.screened or Cover.answers(walled,"rifle",m.cover_goal,main)),"crossfire shelter screens or answers the main threat")
			check(Cover.soft_cover(walled,m.cover_goal) or not walled.terrain.line_clear(tank.pos,m.cover_goal),"a wall shelter in crossfire is screened from the tank it cannot answer")
		else:check(m.posture=="PRONE","no protective shelter in crossfire: soldier goes prone (%s)" % m.posture)

func first_fire_drill()->void:
	# An unseen tank beyond sight (inside its gun range): holding still in the
	# open, the section drops within 0.5 s of the first near miss.
	var sim=field()
	var squad:Dictionary=sim.spawn("rifle",0,Vector2(18,55))
	var tank:=silent(sim,"tank",Vector2(18,34.5))
	step(sim,1.0)
	check(not sim.contact_known(squad,tank),"drop fixture: the shooter is not observed")
	check(squad.members.all(func(m):return m.posture=="STANDING" or m.get("cover_phase","")=="SEEKING"),"before fire soldiers without a target stand")
	squad.suppression+=0.23 # one HE near miss (resolve_shot pin)
	var fired:float=sim.time
	step(sim,0.5)
	var low:bool=squad.members.all(func(m):return m.hp<=0 or m.get("cover_phase","")=="SEEKING" or m.posture in ["CROUCHED","PRONE"])
	for m in squad.members:print("  drop member ",m.index," posture=",m.posture," phase=",m.get("cover_phase",""))
	check(low,"first incoming fire: soldiers drop within 0.5 s")
	check(float(squad.get("fired_on",-100.0))>=fired,"incoming fire is noticed")
	# Ambush by rifles with a wall nearby: return fire, then rush one at a time.
	var amb=field(true)
	var section:Dictionary=amb.spawn("rifle",0,Vector2(21,44))
	step(amb,0.5)
	var enemy:Dictionary=amb.spawn("rifle",1,Vector2(21,32))
	amb.stop([enemy.id])
	var first_fire:=-1.0
	var max_seeking:=0
	var cover_fire:=false
	var rush_in_drill:=false
	var returned:=-1.0
	var dropped:=-1.0
	var seeking_before:Array=[]
	for i in 150:
		var before:Array=section.members.map(func(m):return m.get("cover_phase","")=="SEEKING")
		amb.tick(1.0/30);amb.events.clear()
		if first_fire<0 and float(section.get("fired_on",-100.0))>0:first_fire=amb.time
		var seeking:=0
		for m in section.members:
			if m.hp<=0:continue
			if m.get("cover_phase","")=="SEEKING":
				seeking+=1
				if not before[m.index] and first_fire>0 and amb.time-first_fire<Cover.DRILL-0.05:rush_in_drill=true
		max_seeking=maxi(max_seeking,seeking)
		if first_fire>0:
			if returned<0 and section.members.any(func(m):return float(m.last_shot)>=first_fire):returned=amb.time-first_fire
			if dropped<0 and section.members.all(func(m):return m.hp<=0 or m.get("cover_phase","")=="SEEKING" or m.posture in ["CROUCHED","PRONE"]):dropped=amb.time-first_fire
		if seeking>0 and section.members.any(func(m):return m.hp>0 and m.get("cover_phase","")!="SEEKING" and amb.time-float(m.last_shot)<0.05):cover_fire=true
	print("  ambush first_fire=%.2f dropped=%.2f returned=%.2f max_seeking=%d cover_fire=%s rush_in_drill=%s" % [first_fire,dropped,returned,max_seeking,cover_fire,rush_in_drill])
	for m in section.members:print("  ambush member ",m.index," phase=",m.get("cover_phase","")," posture=",m.posture," hp=%.0f" % m.hp)
	check(first_fire>0,"ambush fixture: section comes under fire")
	check(dropped>=0 and dropped<=0.5,"ambushed soldiers drop within 0.5 s")
	check(returned>=0 and returned<=2.0,"ambushed soldiers return fire")
	check(not rush_in_drill,"no rush starts during the drop-and-fire drill")
	check(max_seeking<=1,"bounding: one soldier rushes at a time")
	check(cover_fire,"bounding: squadmates fire while one rushes")

func _init()->void:
	sheltered_soldiers_crouch()
	cover_keeps_line_of_fire()
	shelter_rechecked_on_new_threat()
	crossfire()
	first_fire_drill()
	print("CONTACT DRILL: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
