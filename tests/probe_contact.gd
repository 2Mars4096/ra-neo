extends SceneTree
# Diagnostic: what does a rifle section do when it meets an enemy section on a harbor street?
const Sim=preload("res://scripts/simulation.gd")
func harbor_index()->int:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		if configs[i].id=="black_sea_harbor":return i
	return -1
func _init()->void:
	var sim=Sim.new(false,harbor_index())
	var ours:Dictionary=sim.spawn("rifle",0,Vector2(560,598))
	var theirs:Dictionary=sim.spawn("rifle",1,Vector2(585,595))
	sim.issue([ours.id],Vector2(620,592),"attack_move")
	for second in 12:
		for i in 30:sim.tick(1.0/30)
		var line:=["t=%d" % (second+1)]
		for u in [ours,theirs]:
			var parts:Array=[]
			for m in u.members:
				if m.hp<=0:parts.append("dead");continue
				parts.append("%s/%s/%s cov=%s supp=%.2f" % [m.posture,m.get("cover_phase","-"),m.state,sim.terrain.cover(m.pos),m.suppression])
			line.append(("OURS " if u.team==0 else "THEIRS ")+u.state+" hp=%d " % int(u.hp)+str(parts))
		print(" | ".join(line))
	quit()
