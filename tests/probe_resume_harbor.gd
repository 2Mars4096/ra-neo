extends SceneTree
# Repro on the harbor map: a dragged sandbag line, engineers ordered away mid-
# line (sites PAUSED), then RESUME on each paused site. Each must progress.
const Sim=preload("res://scripts/simulation.gd")
const FieldOps=preload("res://scripts/field_ops.gd")
func harbor_index()->int:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		if configs[i].id=="black_sea_harbor":return i
	return -1
func _init()->void:
	var sim=Sim.new(false,harbor_index())
	var engineer:Dictionary={}
	for u in sim.units:
		if u.team==0 and u.kind=="engineer":engineer=u
	if engineer.is_empty():engineer=sim.spawn("engineer",0,Vector2(300,640))
	sim.update_visibility()
	var start:=Vector2(-1,-1)
	for r in range(6,30,2):
		for k in 16:
			var p:Vector2=engineer.pos+Vector2.from_angle(k*TAU/16)*r
			if start.x<0 and FieldOps.can_build(sim,"tactical_cover",p,engineer.id):start=p
	var plan:Array=FieldOps.drag_plan(sim,"tactical_cover",start,start+Vector2(8.4,0))
	print("engineer ",engineer.id," at ",engineer.pos.round()," line start ",start.round()," segments ",plan.size()," built ",FieldOps.build_many(sim,"tactical_cover",plan,engineer.id))
	var sites:Array=sim.units.filter(func(u):return u.kind=="tactical_cover" and sim.alive(u) and u.team==0 and u.build_left>0)
	for i in 120:sim.tick(1.0/30)
	sim.issue([engineer.id],engineer.pos+Vector2(0,14),"move")
	for i in 240:sim.tick(1.0/30)
	for s in sites:print("site ",s.id," paused=",s.get("build_paused")," queued_for=",s.get("queued_for",-1)," engineer_id=",s.engineer_id," left=%.2f" % s.build_left)
	var ok:=true
	for s in sites:
		if s.build_left<=0:continue
		var before:float=s.build_left
		var resumed:bool=FieldOps.resume(sim,s.id)
		print("RESUME site ",s.id," -> ",resumed," error='",sim.field_ops.get("last_build_error",""),"' engineer_id=",s.engineer_id," paused=",s.build_paused)
		for i in 450:sim.tick(1.0/30)
		print("   left %.2f -> %.2f  engineer state=%s pos=%s orders=%d building_id=%d" % [before,s.build_left,engineer.state,engineer.pos.round(),engineer.orders.size(),engineer.get("building_id",-1)])
		if not resumed or s.build_left>=before:ok=false
	print("RESUME HARBOR: ","PASS" if ok else "FAIL")
	quit(0 if ok else 1)
