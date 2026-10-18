extends SceneTree
# Two friendly rifle sections attack-move along one black_sea_harbor street
# (different destinations) into a held enemy section. Once both have halted to
# engage they take separate fire positions: within a few seconds their anchors
# stay about two section radii apart and no soldier stands inside the other
# section's footprint; both keep firing; soldiers still use cover where the
# street offers it.
const Sim=preload("res://scripts/simulation.gd")
const FOOTPRINT:=2.0 # a section's formation (offsets ~1 u, prone 1.5 u) plus a body
const APART:=3.8 # ~2 section crowd radii (SECTION_CROWD_RADIUS 2.0)
const PASSING:=1.5 # longest a soldier may stand in the other footprint (walking through)
const SETTLE:=3.0 # seconds both have held to fight before spacing is judged
const WINDOW:=12.0
# [our spawn, held enemy]: the open street of probe_contact, then streets with
# cover 3-6 m away.
const FIGHTS:=[[Vector2(526,690),Vector2(551,690)],[Vector2(400,510),Vector2(375,510)],[Vector2(448,582),Vector2(448,607)],[Vector2(560,598),Vector2(585,595)]]
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func harbor_index()->int:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		if configs[i].id=="black_sea_harbor":return i
	return -1

# Seconds each living soldier of `u` has stood inside the formation footprint
# of section `other` without a break (a soldier passing through is brief).
func dwell(u:Dictionary,other:Dictionary,inside:Dictionary)->float:
	var longest:=0.0
	for m in u.members:
		var key:="%d:%d"%[u.id,m.index]
		inside[key]=float(inside.get(key,0.0))+1.0/30 if m.hp>0 and m.pos.distance_to(other.pos)<FOOTPRINT else 0.0
		longest=maxf(longest,inside[key])
	return longest

func sheltered(u:Dictionary)->int:
	return u.members.filter(func(m):return m.hp>0 and m.get("cover_phase","") in ["SETTLING","SHELTERED"]).size()

func fight(index:int,a:Vector2,b:Vector2)->void:
	var sim=Sim.new(false,index)
	var dir:=(b-a).normalized()
	var s1:Dictionary=sim.spawn("rifle",0,a)
	var s2:Dictionary=sim.spawn("rifle",0,a-dir*5)
	var enemy:Dictionary=sim.spawn("rifle",1,b)
	var second:Dictionary=sim.spawn("rifle",1,b+dir*4)
	enemy.hold_command=true;second.hold_command=true
	check(sim.issue([s1.id],b+dir*35,"attack_move")==1 and sim.issue([s2.id],b+dir*35+dir.orthogonal()*6,"attack_move")==1,"%s: orders accepted"%a)
	var both:=-1.0
	var halted:={}
	var judged:=0.0
	var gap:=INF
	var inside:={}
	var stay:=0.0
	var fired:={}
	var cover:=0
	var shelter_time:=0.0
	for frame in 40*30:
		sim.tick(1.0/30);sim.events.clear()
		for u in [s1,s2]:
			# Halted to fight: stopped with a target, until it moves on again.
			if u.state=="ENGAGING" or (halted.has(u.id) and u.state not in ["ADVANCING","MOVING","YIELDING","RETREATING"]):halted.get_or_add(u.id,sim.time)
			else:halted.erase(u.id)
			if sim.time-float(u.last_shot)<1.0/30+0.001:fired[u.id]=true
		if both<0 and halted.size()==2:both=sim.time
		cover=maxi(cover,sheltered(s1)+sheltered(s2))
		shelter_time+=float(sheltered(s1)+sheltered(s2))/30.0
		if not sim.alive(enemy) or judged>=WINDOW:break
		# Judged only while both have held their fight for a few seconds.
		if halted.size()<2 or sim.time-maxf(halted[s1.id],halted[s2.id])<SETTLE:continue
		judged+=1.0/30
		gap=minf(gap,s1.pos.distance_to(s2.pos))
		stay=maxf(stay,maxf(dwell(s1,s2,inside),dwell(s2,s1,inside)))
	print("  %s: both halted at %.1f s; judged %.1f s: min anchor gap %.2f, longest stay in the other footprint %.1f s, fired %s, most sheltered %d, soldier-seconds sheltered %.1f, anchors %s %s"%[a,both,judged,gap,stay,fired.keys(),cover,shelter_time,s1.pos,s2.pos])
	check(judged>=3.0,"%s: both sections hold a fight (%.1f s judged)"%[a,judged])
	check(gap>=APART,"%s: engaged anchors at least %.1f u apart (%.2f)"%[a,APART,gap])
	check(stay<=PASSING,"%s: no soldier stays inside the other section's footprint (%.1f s)"%[a,stay])
	check(fired.size()==2,"%s: both sections keep firing"%a)

func _init()->void:
	var index:=harbor_index()
	for f in FIGHTS:fight(index,f[0],f[1])
	print("ENGAGED SPACING: %d checks, %d failures"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)
