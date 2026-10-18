extends SceneTree
# Infantry sections sent to one point (one at a time, by a script or the AI,
# or as a group; move or attack-move) take distinct, clear arrival spots round
# it instead of stacking their anchors on the same spot: every section
# arrives, anchors end at least about two section radii apart, nobody stalls
# for long, and re-sending a section that is already there leaves it in place.
# Uses the showcase map (the regroup mission's map).
const Sim=preload("res://scripts/simulation.gd")
# Open field west of the villa.
const FIELD:=Vector2(10,34)
# North of the villa: open ground about 4 u from its north wall (y 12.95).
const YARD:=Vector2(44.5,8.8)
const APART:=3.8 # ~2 section crowd radii (SECTION_CROWD_RADIUS 2.0)
const NEAR:=9.0 # an arrival spot stays close to the ordered point
const STALL:=10.0
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func showcase()->int:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		if configs[i].id=="showcase":return i
	return -1

func setup(point:Vector2,starts:Array)->Array:
	var sim=Sim.new(false,showcase())
	# A friendly unit far off keeps the mission running.
	sim.spawn("rifle",0,Vector2(12,90))
	var sections:Array=[]
	for i in starts.size():
		sections.append(sim.spawn("atgm" if i%2==0 else "rifle",0,point+Vector2(starts[i])))
	return [sim,sections]

func min_gap(sections:Array)->float:
	var gap:=INF
	for a in sections:
		for b in sections:
			if a.id<b.id:gap=minf(gap,a.pos.distance_to(b.pos))
	return gap

# Runs `seconds`, sending section k at `gaps[k]` s (one at a time) or all at
# once (group); returns the longest stall (orders pending, anchor within 1 u
# of where it stood) over all sections.
func run(sim,sections:Array,point:Vector2,mode:String,group:bool,seconds:float)->float:
	var marks:={}
	var worst:=0.0
	if group:check(sim.issue(sections.map(func(u):return u.id),point,mode)==sections.size(),"group %s accepted"%mode)
	for frame in int(seconds*30):
		var t:float=frame/30.0
		if not group:
			for k in sections.size():
				if frame==int(k*3.0*30):check(sim.issue([sections[k].id],point,mode)==1,"section %d %s accepted"%[k,mode])
		sim.tick(1.0/30);sim.events.clear()
		for u in sections:
			if u.orders.is_empty() or not marks.has(u.id) or u.pos.distance_to(marks[u.id].pos)>1.0:
				marks[u.id]={"pos":u.pos,"time":sim.time}
			worst=maxf(worst,sim.time-float(marks[u.id].time))
	return worst

func scenario(label:String,point:Vector2,starts:Array,mode:String,group:bool)->void:
	var made:=setup(point,starts)
	var sim=made[0]
	var sections:Array=made[1]
	var stall:=run(sim,sections,point,mode,group,50.0)
	var arrived:=sections.all(func(u):return u.orders.is_empty() and u.maneuver.is_empty())
	var far:=0.0
	for u in sections:far=maxf(far,u.pos.distance_to(point))
	var gap:=min_gap(sections)
	print("  %s: arrived=%s min anchor gap %.2f, farthest %.2f from the point, longest stall %.1f s"%[label,arrived,gap,far,stall])
	for u in sections:print("    #%d %s at %s (%.2f) orders %d state %s"%[u.id,u.kind,u.pos,u.pos.distance_to(point),u.orders.size(),u.state])
	check(arrived,"%s: every section arrives"%label)
	check(gap>=APART,"%s: anchors at least %.1f u apart (%.2f)"%[label,APART,gap])
	check(far<=NEAR,"%s: arrival spots stay near the point (%.2f)"%[label,far])
	check(stall<=STALL,"%s: nobody stalls over %.0f s (%.1f)"%[label,STALL,stall])
	check(sections.all(func(u):return sim.terrain.traversable(u.pos,"land",1.0)),"%s: anchors on open ground"%label)
	# Re-sent to the same point (a script re-issuing its goal), sections already
	# there hold their spots instead of shuffling round each other.
	var before:=sections.map(func(u):return u.pos)
	for u in sections:check(sim.issue([u.id],point,mode)==1,"%s: re-sent order accepted"%label)
	for frame in 10*30:sim.tick(1.0/30);sim.events.clear()
	var moved:=0.0
	for k in sections.size():moved=maxf(moved,sections[k].pos.distance_to(before[k]))
	print("  %s re-sent: anchors moved at most %.2f u, min gap %.2f"%[label,moved,min_gap(sections)])
	check(moved<=1.5,"%s: re-sent sections hold their spots (%.2f)"%[label,moved])
	check(min_gap(sections)>=APART,"%s: still apart after re-sending"%label)

# Two idle sections that end up on one anchor anyway (orders ending together,
# give-way spots) do not stay stacked: within a few seconds one steps aside.
func stacked(label:String,point:Vector2)->void:
	var made:=setup(point,[Vector2(0,0),Vector2(0,8)])
	var sim=made[0]
	var sections:Array=made[1]
	var b:Dictionary=sections[1]
	var shift:Vector2=point+Vector2(0.6,0.3)-b.pos
	b.pos+=shift
	for m in b.members:m.pos+=shift
	sim.rebuild_spatial()
	var apart:=-1.0
	for frame in 15*30:
		sim.tick(1.0/30);sim.events.clear()
		if apart<0 and min_gap(sections)>=APART and sections.all(func(u):return u.orders.is_empty()):apart=sim.time
	var moved:float=sections[0].pos.distance_to(point)
	print("  %s: stacked 0.67 u apart -> %.2f u, apart and settled after %.1f s, first section moved %.2f u"%[label,min_gap(sections),apart,moved])
	check(apart>0 and apart<=STALL,"%s: stacked sections spread within %.0f s (%.1f)"%[label,STALL,apart])
	check(moved<=0.5,"%s: the section that was there first stays (%.2f)"%[label,moved])
	check(sections.all(func(u):return u.pos.distance_to(point)<=NEAR),"%s: the other steps aside, not away"%label)

func _init()->void:
	var west:=[Vector2(-18,4),Vector2(-20,-2),Vector2(-17,9),Vector2(-21,-7)]
	var south:=[Vector2(0,20),Vector2(4,22),Vector2(-4,21),Vector2(8,19)]
	scenario("open one at a time (move)",FIELD,south,"move",false)
	scenario("open one at a time (attack-move)",FIELD,west,"attack_move",false)
	scenario("open group (move)",FIELD,south,"move",true)
	scenario("open group (attack-move)",FIELD,west,"attack_move",true)
	var yard:=[Vector2(-20,-4),Vector2(-22,0),Vector2(-18,-7),Vector2(-24,-3)]
	scenario("near building one at a time (move)",YARD,yard,"move",false)
	scenario("near building one at a time (attack-move)",YARD,yard,"attack_move",false)
	scenario("near building group (move)",YARD,yard,"move",true)
	stacked("stacked in the open",FIELD)
	stacked("stacked near the building",YARD)
	print("SECTION SPREAD: %d checks, %d failures"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)
