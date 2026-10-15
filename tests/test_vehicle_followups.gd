extends SceneTree
# Vehicle and tree follow-ups: an abandoned vehicle's destroyed event carries
# "abandoned" (no blast in presentation) and it still becomes a wreck; a
# soldier behind a wreck is harder to hit; a repair point restores knocked-out
# components; a tank pushes over a collision tree (navigation opens locally);
# an HE burst fells a tree and the instanced tree topples.
const Sim=preload("res://scripts/simulation.gd")
const FieldOps=preload("res://scripts/field_ops.gd")
const VehicleDamage=preload("res://scripts/vehicle_damage.gd")
const StructureDamage=preload("res://scripts/structure_damage.gd")
const Visuals=preload("res://scripts/visuals.gd")
const Cover=preload("res://scripts/cover_behavior.gd")
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func scenario_index(id:String)->int:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		if configs[i].id==id:return i
	return -1

const BASE:=Vector2(300,640)

func _init()->void:
	abandoned_event()
	wreck_cover()
	field_repair()
	tree_crush()
	tree_blast()
	print("VEHICLE FOLLOWUPS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)

# --- 1. Crew bail-out: flagged destroyed event, wreck stays ----------------------
func abandoned_event()->void:
	var sim=Sim.new(false,scenario_index("black_sea_harbor"))
	var gunner:Dictionary=sim.spawn("tank",1,BASE+Vector2(14,0))
	var tank:Dictionary=sim.spawn("tank",0,BASE)
	tank.facing=Vector2.UP
	var flagged:Dictionary={}
	var blasted:Dictionary={}
	for i in 2000:
		VehicleDamage.ensure_state(sim,tank)
		tank.hp=tank.max_hp
		tank.crew=1
		tank.abandoned=false
		tank.erase("wrecked")
		VehicleDamage.wrecks(sim).clear()
		sim.events.clear()
		sim.resolve_shot(gunner,tank,1.0)
		if tank.hp>0.0:continue
		for event in sim.events:
			if event.type!="destroyed":continue
			if tank.abandoned:flagged=event
			else:blasted=event
		if not flagged.is_empty():break
	check(not flagged.is_empty() and flagged.get("abandoned",false),"bail-out destroyed event is flagged abandoned")
	check(tank.get("wrecked",false) and VehicleDamage.wrecks(sim).size()==1,"abandoned tank still becomes a wreck")
	check(blasted.is_empty() or not blasted.get("abandoned",false),"a knocked-out (not abandoned) tank's event is unflagged")
	print("ABANDONED event=",flagged.get("abandoned","none")," wrecks=",VehicleDamage.wrecks(sim).size())

# --- 2. Cover behind a wreck --------------------------------------------------------
func make_wreck(sim,pos:Vector2)->Dictionary:
	var hull:Dictionary=sim.spawn("tank",1,pos)
	hull.facing=Vector2.UP
	hull.hp-=VehicleDamage._finish(sim,hull,hull.hp+1.0)
	return VehicleDamage.wrecks(sim).back()

func place(section:Dictionary,pos:Vector2)->void:
	section.pos=pos
	for member in section.members:
		member.pos=pos
		member.posture="STANDING"
		member.in_trench=false

func wreck_cover()->void:
	# Classic map (no field ops): only the directional wreck_cover helper applies.
	var sim=Sim.new(false,scenario_index("classic"))
	var spot:=Vector2(-1,-1)
	for x in range(10,86,2):
		for y in range(10,62,2):
			var p:=Vector2(x,y)
			if spot.x<0 and not sim.terrain.cover(p) and not sim.terrain.cover(p+Vector2(4,0)) and not sim.terrain.cover(p+Vector2(-2.5,0)) and sim.terrain.traversable(p,"land",1.0) and sim.terrain.line_clear(p,p+Vector2(18,0)):spot=p
	check(spot.x>=0,"open ground for the wreck test")
	var shooter:Dictionary=sim.spawn("rifle",1,spot+Vector2(18,0))
	var squad:Dictionary=sim.spawn("rifle",0,spot)
	shooter.state="READY"
	place(squad,spot+Vector2(-2.5,0))
	var open_chance:float=sim.hit_chance(shooter,squad)
	var wreck:=make_wreck(sim,spot)
	check(VehicleDamage.wreck_cover(sim,squad.pos,shooter.pos),"wreck lies between soldier and shooter")
	var covered_chance:float=sim.hit_chance(shooter,squad)
	place(squad,spot+Vector2(4,0))
	var exposed_chance:float=sim.hit_chance(shooter,squad)
	check(covered_chance<open_chance*0.8,"soldier behind a wreck is harder to hit (%.3f vs %.3f)" % [covered_chance,open_chance])
	check(not VehicleDamage.wreck_cover(sim,squad.pos,shooter.pos) and exposed_chance>covered_chance,"soldier on the shooter's side of the wreck gets no cover")
	# Rolled hits over many rounds (dedicated RNG so the sim stream is untouched).
	var rng:=RandomNumberGenerator.new();rng.seed=4242
	var hits_open:=0;var hits_covered:=0
	for i in 2000:
		if rng.randf()<open_chance:hits_open+=1
		if rng.randf()<covered_chance:hits_covered+=1
	check(hits_covered<hits_open*0.8,"wreck cuts rolled hits (%d vs %d of 2000)" % [hits_covered,hits_open])
	print("WRECK COVER classic: open %.3f behind wreck %.3f shooter side %.3f | rolled %d vs %d" % [open_chance,covered_chance,exposed_chance,hits_open,hits_covered])
	# Harbor (field ops): wreck rects become terrain cover via sync_obstacles,
	# which Cover.find_slot also uses for cover seeking.
	var harbor=Sim.new(false,scenario_index("black_sea_harbor"))
	var hwreck:=make_wreck(harbor,BASE)
	FieldOps.sync_obstacles(harbor)
	check(harbor.terrain.cover(hwreck.pos+Vector2(hwreck.radius*0.7+0.8,0)),"harbor wreck gives terrain cover beside the hull")
	# Cover seeking: a section beside the wreck picks a slot screened by the hull.
	var squad_h:Dictionary=harbor.spawn("rifle",0,hwreck.pos+Vector2(5,0))
	place(squad_h,hwreck.pos+Vector2(5,0))
	var threat:={"pos":hwreck.pos+Vector2(-25,0)}
	var slot:Dictionary=Cover.find_slot(squad_h,squad_h.members[0],harbor,threat)
	var slot_pos:Vector2=slot.get("pos",Vector2.ZERO)
	check(not slot.is_empty() and slot_pos.distance_to(hwreck.pos)<float(hwreck.radius)+1.5 and not harbor.terrain.line_clear(threat.pos,slot_pos),"cover seeking picks the screened side of a wreck (%s)" % str(slot_pos-hwreck.pos))
	print("WRECK COVER harbor: terrain.cover beside hull=",harbor.terrain.cover(hwreck.pos+Vector2(hwreck.radius*0.7+0.8,0))," radius=%.2f" % wreck.radius)

# --- 3. Repair point restores components ------------------------------------------
func field_repair()->void:
	var sim=Sim.new(false,scenario_index("black_sea_harbor"))
	var repair:Dictionary=sim.spawn("repair_point",0,BASE)
	repair["build_left"]=0.0
	var tank:Dictionary=sim.spawn("tank",0,BASE+Vector2(6,0))
	VehicleDamage.ensure_state(sim,tank)
	tank.mobility_kill=true
	tank.firepower_kill=true
	tank.crew=int(tank.crew_full)-1
	tank.hp=tank.max_hp*0.5
	tank.last_hit=-100.0
	sim.time=100.0
	var fixed:Dictionary={}
	var toasts:Array=[]
	for second in 120:
		sim.events.clear()
		FieldOps.tick(sim,1.0)
		sim.time+=1.0
		for event in sim.events:
			if event.type=="warning" and "repair" in str(event.text) or event.type=="warning" and "replacement" in str(event.text):toasts.append(event.text)
		if not tank.mobility_kill and not fixed.has("mobility"):fixed["mobility"]=second+1
		if not tank.firepower_kill and not fixed.has("firepower"):fixed["firepower"]=second+1
		if int(tank.crew)==int(tank.crew_full) and not fixed.has("crew"):fixed["crew"]=second+1
		if fixed.size()==3:break
	print("REPAIR times (s): ",fixed," toasts=",toasts)
	check(fixed.get("mobility",999)>=18 and fixed.get("mobility",999)<=22,"tracks repaired in ~20 s")
	check(fixed.get("firepower",999)-fixed.get("mobility",0)>=23 and fixed.get("firepower",999)-fixed.get("mobility",0)<=27,"main gun repaired ~25 s later")
	check(fixed.get("crew",999)-fixed.get("firepower",0)>=38 and fixed.get("crew",999)-fixed.get("firepower",0)<=42,"crew casualty replaced ~40 s later")
	check(toasts.size()==3,"a warning toast for each repair (%d)" % toasts.size())
	check(VehicleDamage.weapon_ready(sim,tank),"repaired tank can fire")
	# Under fire: no progress.
	tank.firepower_kill=true
	tank.last_hit=sim.time
	for second in 5:FieldOps.tick(sim,1.0)
	check(tank.firepower_kill and float(tank.get("repair_done",0.0))==0.0,"no repair while under fire")

# --- 4. Tank pushes over a collision tree -------------------------------------------
func tree_lane(sim,radius:float)->Dictionary:
	var terrain=sim.terrain
	var clear:float=radius+terrain.TREE_CLEARANCE
	for index in terrain.trees.size():
		var tree:Vector2=terrain.trees[index]
		for direction in [Vector2.RIGHT,Vector2.LEFT,Vector2.DOWN,Vector2.UP]:
			var start:Vector2=tree-direction*(clear+3.0)
			var touch:Vector2=tree-direction*(clear+0.02)
			if not terrain.segment_clear(start,touch,"land",radius):continue
			# Nothing but this trunk on the lane (row neighbours stand 4 m to the
			# side, just outside the hull clearance); the far side is open too.
			var far:Vector2=tree+direction*(clear+3.0)
			var others:=false
			for other in terrain.trees:
				if other!=tree and Geometry2D.get_closest_point_to_segment(other,start,far).distance_to(other)<clear:others=true
			if others or not terrain.traversable(far,"land",radius):continue
			return {"index":index,"tree":tree,"direction":direction,"start":start}
	return {}

func tree_crush()->void:
	var sim=Sim.new(false,scenario_index("black_sea_harbor"))
	var radius:float=float(sim.definitions.tank.radius)
	var count:int=sim.terrain.trees.size()
	var lane:=tree_lane(sim,radius)
	check(count>=40 and not lane.is_empty(),"harbor has collision trees and a clear lane at one (%d trees)" % count)
	if lane.is_empty():return
	var tree:Vector2=lane.tree
	var grid:AStarGrid2D=sim.terrain.nav_grid("land",radius,"tracked")
	var cell:Vector2i=sim.terrain.nav_cell(tree)
	var solid_before:bool=grid.is_point_solid(cell)
	var blocked_before:bool=not sim.terrain.traversable(tree,"land",radius)
	var tank:Dictionary=sim.spawn("tank",0,lane.start)
	tank.facing=lane.direction
	var goal:Vector2=tree+lane.direction*8.0
	var crushed:Array=[]
	var started:=Time.get_ticks_usec()
	for i in 120:
		sim.events.clear()
		sim.hull_step(tank,goal,tank.pos.distance_to(goal),0.2,1.0/30,[])
		for event in sim.events:if event.type=="crushed" and event.get("id","")=="tree":crushed.append(event)
	var usec:=Time.get_ticks_usec()-started
	print("TREE CRUSH tree #%d at %s: events=%d solid %s->%s traversable %s->%s tank advanced %.1f m (%d us for 120 steps)" % [lane.index,str(tree),crushed.size(),solid_before,grid.is_point_solid(cell),not blocked_before,sim.terrain.traversable(tree,"land",radius),tank.pos.distance_to(lane.start),usec])
	check(blocked_before and solid_before,"standing tree blocks the tank and its nav cell")
	check(crushed.size()==1 and int(crushed[0].tree)==lane.index,"tank pushes over the tree (one crushed event)")
	check(sim.terrain.trees.size()==count and sim.terrain.trees[lane.index]==sim.terrain.FELLED_TREE,"tree leaves collision, array size stable")
	check(sim.terrain.traversable(tree,"land",radius) and not grid.is_point_solid(cell),"navigation opens at the felled tree (local refresh)")
	check(not sim.terrain._static_candidates("tree",tree,2.0).has(tree),"felled tree removed from the static index")
	check(tank.pos.distance_to(lane.start)>sim.terrain.TREE_CLEARANCE+radius+2.0,"tank drives on through the gap")
	# Wheeled/infantry movers only fell trees through blasts; infantry never crush.
	var second:=tree_lane(sim,radius)
	check(second.is_empty() or second.index!=lane.index,"felled tree no longer offered as an obstacle")

# --- 5. HE burst fells a tree; the instanced tree topples ---------------------------
func tree_blast()->void:
	var sim=Sim.new(false,scenario_index("black_sea_harbor"))
	var lane:=tree_lane(sim,float(sim.definitions.tank.radius))
	if lane.is_empty():check(false,"tree for the blast test");return
	var tree:Vector2=lane.tree
	var root:=Node3D.new()
	var art=Visuals.new()
	art.make_harbor_trees(root,sim.terrain.trees,sim.terrain)
	# The topple handler's lookup (bound to terrain.tree_felled) holds each
	# instance's transform; headless renderers cannot read MultiMesh data back.
	var entries:Array=[]
	for connection in sim.terrain.tree_felled.get_connections():
		var lookup:Array=connection.callable.get_bound_arguments()[0]
		if lookup[lane.index]!=null:entries=lookup[lane.index]
	var trunk:Array=[]
	for entry in entries:
		if entry[0].mesh is CylinderMesh:trunk=entry
	check(entries.size()==8 and not trunk.is_empty(),"instanced trunk and foliage found for the tree (%d instances)" % entries.size())
	var upright:float=Transform3D(trunk[3]).basis.y.normalized().y if not trunk.is_empty() else 0.0
	# A tank HE round lands 1.2 m from the trunk (structure_damage scans shot events).
	sim.events.append({"type":"shot","from":tree+Vector2(30,0),"to":tree+Vector2(1.2,0),"kind":"tank","target_kind":"rifle","hit":false,"from_y":1.0,"to_y":0.8,"visible":true})
	StructureDamage.tick(sim,1.0/30)
	check(sim.terrain.trees[lane.index]==sim.terrain.FELLED_TREE,"HE burst fells the tree")
	check(sim.terrain.traversable(tree,"land",float(sim.definitions.tank.radius)),"blast-felled tree no longer blocks")
	var lying:float=Transform3D(trunk[3]).basis.y.normalized().y if not trunk.is_empty() else 1.0
	check(upright>0.99 and lying<0.2,"instanced tree topples (up axis y %.2f -> %.2f)" % [upright,lying])
	# A burst far from any tree fells nothing.
	var before:int=sim.terrain.trees.count(sim.terrain.FELLED_TREE)
	check(sim.terrain.fell_trees(Vector2(-50,-50),2.2).is_empty() and sim.terrain.trees.count(sim.terrain.FELLED_TREE)==before,"distant burst fells nothing")
	print("TREE BLAST felled #%d trunk up-axis %.2f -> %.2f" % [lane.index,upright,lying])
	root.free()
