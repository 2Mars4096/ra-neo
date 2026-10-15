extends SceneTree
# Rifle section meets an enemy section at ~25 m on black_sea_harbor streets
# (attack_move into contact). Where real cover lies within the cover leash, at
# least 2 of 3 attackers must reach it (SETTLING/SHELTERED) or go prone within
# REACT seconds. On an open stretch (nearest cover beyond the leash) the
# soldiers must instead report EXPOSED, not chase a shelter they cannot reach.
const Sim=preload("res://scripts/simulation.gd")
const Cover=preload("res://scripts/cover_behavior.gd")
const REACT:=6.0
# [our spawn, enemy spawn, open street]: the audited open street (nearest cover
# ~14.5 m from the spawn, ~18 m from where contact halts it), then streets with
# cover 3-6 m away.
const FIGHTS:=[[Vector2(560,598),Vector2(585,595),true],[Vector2(526,690),Vector2(551,690),false],[Vector2(400,510),Vector2(375,510),false],[Vector2(448,582),Vector2(448,607),false]]
var failures:=0
func harbor_index()->int:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		if configs[i].id=="black_sea_harbor":return i
	return -1
func check(ok:bool,label:String)->void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok:failures+=1
# Nearest standable cover point (what CoverBehavior can choose) on a 0.5 m grid.
func nearest_cover(terrain,center:Vector2)->float:
	var best:=INF
	for x in range(-48,49):
		for y in range(-48,49):
			var p:=center+Vector2(x,y)*0.5
			var d:=p.distance_to(center)
			if d<best and terrain.cover(p) and terrain.traversable(p,"land",0.8):best=d
	return best
func fight(index:int,a:Vector2,b:Vector2,open:bool)->void:
	var sim=Sim.new(false,index)
	var ours:Dictionary=sim.spawn("rifle",0,a)
	var theirs:Dictionary=sim.spawn("rifle",1,b)
	sim.issue([ours.id],b+(b-a).normalized()*35,"attack_move")
	var reach:float=nearest_cover(sim.terrain,a)
	var reacted:={}
	var exposed:={}
	for frame in int(12*30):
		sim.tick(1.0/30)
		for m in ours.members:
			if m.hp<=0:continue
			var phase:String=m.get("cover_phase","")
			if phase in ["SETTLING","SHELTERED"] or m.posture=="PRONE":reacted.get_or_add(m.index,sim.time)
			if phase=="EXPOSED":exposed.get_or_add(m.index,sim.time)
		if (frame+1)%30==0:
			var line:=["t=%d" % roundi(sim.time)]
			for u in [ours,theirs]:
				var parts:Array=[]
				for m in u.members:
					parts.append("dead" if m.hp<=0 else "%s/%s/%s%s" % [m.posture,m.get("cover_phase","-"),m.state," cov" if sim.terrain.cover(m.pos) else ""])
				line.append(("OURS " if u.team==0 else "THEIRS ")+"%s supp=%.2f %s" % [u.state,u.suppression,parts])
			print("  "+" | ".join(line))
	var on_time:int=reacted.values().filter(func(t):return t<=REACT).size()
	var flagged:int=exposed.values().filter(func(t):return t<=REACT).size()
	var dead:int=ours.members.filter(func(m):return m.hp<=0).size()
	var summary:="%s->%s nearest cover %.1f m, covered/prone by %.0fs: %d %s, exposed: %d, ours dead %d" % [a,b,reach,REACT,on_time,reacted,flagged,dead]
	if open:
		check(reach>Cover.LEASH,"open street has no cover within the %.0f m leash: %s" % [Cover.LEASH,summary])
		check(flagged>=2,"open street reported EXPOSED: "+summary)
	else:
		check(reach<=Cover.LEASH-2.0,"street has cover within the leash: "+summary)
		check(on_time>=2,"cover within leash used: "+summary)
func _init()->void:
	var index:=harbor_index()
	for pair in FIGHTS:fight(index,pair[0],pair[1],pair[2])
	print("probe_contact: %d fights, %d failures" % [FIGHTS.size(),failures])
	print("probe_contact: "+("PASS" if failures==0 else "FAIL"))
	quit(1 if failures>0 else 0)
