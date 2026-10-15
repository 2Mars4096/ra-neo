extends SceneTree
# Tier-1 engineer works: build, complete and verify each non-solid zone effect.
const Sim=preload("res://scripts/simulation.gd")
const FieldOps=preload("res://scripts/field_ops.gd")
const FieldModels=preload("res://scripts/field_models.gd")
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)

func fixture():
	var sim=Sim.new(false,5)
	sim.spawn("engineer",0,Vector2(14,97))
	sim.update_visibility()
	return sim

func site(sim,kind:String,rotated:bool=false)->Vector2:
	for y in range(85,102,2):
		for x in range(7,30,2):
			var pos:=Vector2(x,y)
			if FieldOps.can_build(sim,kind,pos,sim.units[0].id,rotated):return pos
	return Vector2(-1,-1)

# Build and run the simulation until the engineers finish; returns the site.
func harbor_index()->int:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		if configs[i].id=="black_sea_harbor":return i
	return -1

func complete(sim,kind:String,rotated:bool=false)->Dictionary:
	var pos:=site(sim,kind,rotated)
	check(pos.x>=0,"site exists "+kind)
	if pos.x<0:return {}
	check(FieldOps.build(sim,kind,pos,sim.units[0].id,rotated),"build "+kind)
	var work:Dictionary=sim.units.back()
	for i in 1500:
		sim.tick(1.0/30)
		if work.build_left<=0:break
	check(work.build_left<=0,"engineers complete "+kind)
	return work

func _init()->void:
	var definitions:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/field_units.json"))
	for kind in FieldOps.KINDS:
		check(definitions.has(kind),"definition "+kind)
		check(FieldModels.FOOTPRINTS.has(kind) and FieldModels.FOOTPRINTS[kind]==Vector2(definitions[kind].footprint[0],definitions[kind].footprint[1]),"model footprint matches "+kind)
		check(is_equal_approx(FieldModels.BUILD_SECONDS[kind],float(definitions[kind].build_seconds)),"model timer matches "+kind)

	var sim=fixture()
	var wire:=complete(sim,"concertina_wire")
	if not wire.is_empty():
		var rect:=FieldOps.footprint(sim,"concertina_wire",wire.pos)
		check(sim.terrain.ground_speed(wire.pos,"infantry")<=0.16*sim.terrain._base_ground_speed(wire.pos,"infantry")+0.001,"wire slows infantry")
		check(is_equal_approx(sim.terrain.ground_speed(wire.pos,"tracked"),sim.terrain._base_ground_speed(wire.pos,"tracked")),"wire leaves armour speed")
		check(sim.terrain.traversable(wire.pos,"land",0.8),"wire is not a solid blocker")
		check(sim.collision_layer(wire)=="field_zone","wire bodies do not collide")
		var wire_rect:=FieldOps.footprint(sim,"concertina_wire",wire.pos)
		var infantry_grid:AStarGrid2D=sim.terrain.nav_grid("land",0.95,"infantry")
		check(infantry_grid.is_point_solid(sim.terrain.nav_cell(wire.pos)),"wire is an infantry navigation barrier")
		check(infantry_grid!=null,"infantry grid available")
	# Open ground in the harbor: a soldier's route goes around a free-standing wire belt.
	var open=Sim.new(false,harbor_index())
	FieldOps.spawn_prepared_works(open,[{"kind":"concertina_wire","position":[300,700]}],1)
	var belt:=FieldOps.footprint(open,"concertina_wire",Vector2(300,700))
	var a:=Vector2(300,692);var b:=Vector2(300,708)
	var detour:Array=open.terrain.path(a,b,"land",0.95,[],"infantry")
	var crosses:=false
	var previous:=a
	for p in detour:
		for k in 8:
			if belt.has_point(previous.lerp(p,k/7.0)):crosses=true
		previous=p
	check(open.terrain.traversable(a,"land",0.95) and open.terrain.traversable(b,"land",0.95),"open-ground wire fixture")
	check(not detour.is_empty() and not crosses,"infantry route goes around the wire")
	if not wire.is_empty():
		var rect:=FieldOps.footprint(sim,"concertina_wire",wire.pos)
		var tank:Dictionary=sim.spawn("tank",1,rect.get_center()+Vector2(0,4))
		tank.pos=rect.get_center()
		FieldOps.tick(sim,0.1)
		check(not sim.alive(wire),"tracked vehicle crushes wire")
		FieldOps.tick(sim,0.1)
		check(sim.terrain.field_zones.is_empty(),"crushed wire releases its zone")

	# Drag-to-install: a dragged line becomes several paid segments built in turn.
	var line=fixture()
	var start:=site(line,"concertina_wire")
	if start.x>=0:
		var plan:Array=FieldOps.drag_plan(line,"concertina_wire",start,start+Vector2(21,1))
		check(plan.size()==4 and plan.all(func(s):return not s.rotated),"horizontal drag lays 4 wire segments")
		check(FieldOps.drag_plan(line,"concertina_wire",start,start+Vector2(1,-21)).all(func(s):return s.rotated),"vertical drag turns segments")
		check(FieldOps.drag_cost(line,"concertina_wire",plan)==4*int(line.definitions.concertina_wire.cost),"cost scales with length")
		check(FieldOps.drag_plan(line,"camouflage_net",start,start+Vector2(11,9)).size()==9,"net drag tiles an area (3 x 3 centres)")
		var funds:float=line.credits
		var count:int=FieldOps.build_many(line,"concertina_wire",plan,line.units[0].id)
		check(count>=2,"dragged line marks several sites (%d)" % count)
		check(is_equal_approx(line.credits,funds-count*float(line.definitions.concertina_wire.cost)),"each marked segment is paid once")
		var segments:Array=line.units.filter(func(u):return u.kind=="concertina_wire" and line.alive(u))
		var queued:Array=segments.filter(func(u):return u.has("queued_for"))
		if not queued.is_empty():
			check(FieldOps.resume(line,queued[0].id),"RESUME on a queued segment switches the busy engineers to it")
			check(segments.filter(func(u):return u.has("queued_for")).size()==queued.size(),"the interrupted segment goes back into the queue")
		# An explicit order interrupts the line; idle engineers pick it back up.
		line.issue([line.units[0].id],line.units[0].pos+Vector2(0,-3),"move")
		for i in 2400:
			line.tick(1.0/30)
			if segments.all(func(u):return u.build_left<=0):break
		check(segments.all(func(u):return u.build_left<=0),"one engineer section completes every segment in turn")
	var rotated=fixture()
	var turned:=complete(rotated,"concertina_wire",true)
	if not turned.is_empty():
		var r:=FieldOps.footprint(rotated,"concertina_wire",turned.pos,true)
		check(r.size==Vector2(1.4,7.0) and turned.rotated,"rotation swaps the wire footprint")
		check(rotated.terrain.field_zones[0].rect==r,"rotated zone matches footprint")
	check(FieldOps.footprint(rotated,"vehicle_berm",Vector2(20,20),true).size==Vector2(6,6) and not "vehicle_berm" in FieldOps.ROTATABLE,"square works ignore rotation")

	var obstacles=fixture()
	var hedgehogs:=complete(obstacles,"tank_obstacles")
	if not hedgehogs.is_empty():
		check(obstacles.terrain.ground_speed(hedgehogs.pos,"tracked")<0.05,"hedgehogs stop tracked vehicles")
		check(obstacles.terrain.ground_speed(hedgehogs.pos,"wheeled")<0.05,"hedgehogs stop wheeled vehicles")
		check(obstacles.terrain.ground_speed(hedgehogs.pos,"infantry")>0.5*obstacles.terrain._base_ground_speed(hedgehogs.pos,"infantry"),"infantry pass hedgehogs")
		check(obstacles.terrain.cover(hedgehogs.pos),"hedgehogs give infantry cover")
		var grid:AStarGrid2D=obstacles.terrain.nav_grid("land",2.6,"tracked")
		var cell:Vector2i=obstacles.terrain.nav_cell(hedgehogs.pos)
		check(grid.get_point_weight_scale(cell)>10,"armour route planning avoids hedgehogs")
		check(grid.is_point_solid(cell),"hedgehog cells are solid for armour navigation")
		check(not obstacles.terrain.nav_grid("land",0.8,"infantry").is_point_solid(cell),"hedgehog cells stay open for infantry")
		check(obstacles.terrain.vehicle_barrier(hedgehogs.pos) and not obstacles.terrain.vehicle_barrier(hedgehogs.pos+Vector2(0,12)),"barrier is local")
		# Drive a tank straight at the obstacle line: it must never enter it.
		var rect:Rect2=FieldOps.footprint(obstacles,"tank_obstacles",hedgehogs.pos,hedgehogs.get("rotated",false))
		var across:Vector2=Vector2(9,0) if rect.size.x<rect.size.y else Vector2(0,9)
		var tank:Dictionary=obstacles.spawn("tank",0,hedgehogs.pos-across*1.6)
		check(not tank.is_empty() and not rect.grow(1).has_point(tank.pos),"tank fixture placed beside the obstacle line")
		if not tank.is_empty():across=(hedgehogs.pos-tank.pos)*0.75
		if not tank.is_empty():
			var start_side:float=signf((tank.pos-hedgehogs.pos).dot(across))
			obstacles.issue([tank.id],hedgehogs.pos+across*1.4,"move")
			var entered:=false
			for i in 600:
				obstacles.tick(1.0/30)
				if rect.has_point(tank.pos):entered=true
			check(not entered,"tank never drives through hedgehogs")
			check(start_side!=0,"tank starts on one side")

	var trench_sim=fixture()
	var trench:=complete(trench_sim,"fighting_trench")
	if not trench.is_empty():
		check(trench_sim.terrain.cover(trench.pos),"trench gives infantry cover inside")
		check(trench_sim.terrain.surface_name(trench.pos)!="","trench surface named")
		check(trench_sim.terrain.dug_in(trench.pos),"trench is a dug position")
		check(Sim.Infantry.Cover.soft_cover(trench_sim,trench.pos),"trench interior counts as protective cover")
		# A rifle section halted beside the trench mans it without needing an enemy.
		var manned:Dictionary=trench_sim.spawn("rifle",0,trench.pos+Vector2(0,6))
		if not manned.is_empty():
			for i in 360:trench_sim.tick(1.0/30)
			var inside:int=manned.members.filter(func(m):return m.hp>0 and trench_sim.terrain.dug_in(m.pos)).size()
			check(inside>=2,"halted section occupies the trench (%d in)" % inside)
		var squad:Dictionary=trench_sim.units[0]
		for member in squad.members:member.pos=trench.pos+Vector2(member.index-1,0)*1.2
		trench_sim.infantry_combat(squad,1.0/30)
		check(squad.members.all(func(m):return m.hp<=0 or (m.in_trench and m.posture=="CROUCHED")),"soldiers in a trench crouch below the parapet")

	var berm_sim=fixture()
	var berm:=complete(berm_sim,"vehicle_berm")
	if not berm.is_empty():
		check(berm_sim.terrain.hull_down(berm.pos),"berm is hull-down")
		var shooter:Dictionary=berm_sim.spawn("atgm",1,berm.pos+Vector2(0,-14))
		var tank:Dictionary=berm_sim.spawn("tank",0,berm.pos+Vector2(0,30))
		var exposed:float=berm_sim.damage_amount(shooter,tank)
		tank.pos=berm.pos
		check(berm_sim.damage_amount(shooter,tank)<exposed*0.7,"hull-down tank takes less damage")
		check(not berm_sim.terrain.hull_down(berm.pos,berm.pos+Vector2(0,10)),"open rear of berm does not protect")
		check(berm_sim.terrain.hull_down(berm.pos,berm.pos+Vector2(10,0)),"berm side protects")
		var helo:Dictionary=berm_sim.spawn("helo",1,berm.pos+Vector2(0,-10))
		var under_net:float=berm_sim.damage_amount(helo,tank)
		berm.hp=0;FieldOps.sync_obstacles(berm_sim)
		check(is_equal_approx(under_net,berm_sim.damage_amount(helo,tank)),"earth berm grants no protection against air attack")

	var camo=fixture()
	var net:=complete(camo,"camouflage_net")
	if not net.is_empty():
		check(is_equal_approx(camo.terrain.concealment(net.pos),0.5),"net halves detection range")
		check(is_equal_approx(camo.terrain.concealment(net.pos+Vector2(20,0)),1.0),"concealment is local")

	var supply=fixture()
	check(FieldOps.insertion_for(supply,"rifle",0)==supply.field_ops.insertion,"default entry before forward point")
	var depot:=complete(supply,"forward_supply_point")
	if not depot.is_empty():
		var entry:=FieldOps.insertion_for(supply,"rifle",0)
		check(entry.distance_to(depot.pos)<10,"land reinforcements use forward supply point")
		check(FieldOps.insertion_for(supply,"helo",0)==supply.field_ops.insertion,"aircraft keep original insertion")
		check(FieldOps.insertion_for(supply,"boat",0)==supply.field_ops.sea_insertion,"ships keep the sea lane")
		check(not supply.terrain.traversable(depot.pos,"land",0.8),"supply point is solid")
		var enemy:Dictionary=supply.spawn("rifle",1,depot.pos+Vector2(10,0))
		enemy.seen_by[0]=true
		check(FieldOps.insertion_for(supply,"rifle",0)==supply.field_ops.insertion,"threatened forward point falls back")
		enemy.hp=0
		supply.credits=1000
		supply.recruit_clock=0
		var before:int=supply.units.size()
		check(supply.recruit("rifle") and supply.units.size()==before+1 and supply.units.back().pos.distance_to(depot.pos)<14,"purchase arrives forward")
		supply.recruit_clock=0
		supply.terrain.update_field_geometry(supply.terrain.dynamic_blocks+[Rect2(supply.field_ops.insertion-Vector2(6,6),Vector2(12,12))],supply.terrain.field_cover)
		var balance:float=supply.credits
		var bought:bool=supply.recruit("rifle")
		check(not supply.field_ops.get("last_entry_forward",false),"disconnected route never deploys forward")
		check(bought or is_equal_approx(balance,supply.credits),"failed deployment never charges supply")
		var guard:Dictionary=supply.spawn("rifle",1,Vector2(35,97))
		guard.seen_by[0]=true
		var safe:Vector2=FieldOps.entry_position(supply,"rifle",Vector2(30,97),true)
		check(safe.x<0 or safe.distance_to(guard.pos)>=FieldOps.FORWARD_SAFE_RADIUS,"forward spawn candidate respects threat exclusion")
	var art=preload("res://scripts/visuals.gd").new()
	var stage:=Node3D.new()
	var turned_visual:Node3D=art.make_unit(stage,{"kind":"concertina_wire","team":0,"structure":true,"build_left":0.0,"rotated":true})
	check(is_equal_approx(turned_visual.get_node("Model").rotation.y,PI/2),"rendered model matches rotated footprint")
	stage.free()
	# Firing breaks net concealment without changing physical line-of-sight.
	var detection=Sim.new(false,5)
	var observer:Dictionary=detection.spawn("rifle",0,Vector2(14,85))
	var hidden:Dictionary=detection.spawn("rifle",1,Vector2(14,98))
	detection.terrain.update_field_zones([{"rect":Rect2(hidden.pos-Vector2(3,3),Vector2(6,6)),"speed":{},"cover":[],"conceal":0.5}])
	detection.update_visibility()
	check(not hidden.seen_by[0],"quiet net conceals target beyond half sight")
	hidden.last_shot=detection.time
	detection.update_visibility()
	check(hidden.seen_by[0],"firing reveals net occupant")
	detection.time+=3.1;detection.update_visibility()
	check(not hidden.seen_by[0],"net concealment recovers after firing cooldown")
	# Weather epochs, lazy profiles, destruction and overlapping input zones.
	var terrain=preload("res://scripts/terrain.gd").new(5)
	var zone={"rect":Rect2(10,90,7,2),"speed":{"infantry":0.15},"cover":["infantry"],"conceal":0.5}
	var sample:=Vector2(12.5,90.5)
	var grid:AStarGrid2D=terrain.nav_grid("land",0.8,"infantry")
	terrain.update_field_zones([zone,zone])
	check(is_equal_approx(terrain.concealment(sample),0.5),"duplicate nets never multiply concealment")
	check(is_equal_approx(terrain.ground_speed(sample,"infantry"),0.15*terrain._base_ground_speed(sample,"infantry")),"overlapping speed zones use strongest effect")
	check(terrain.cover(sample) and not terrain.cover(sample,false),"zone cover only inside and when enabled")
	for wet in [0.3,0.8,0.0]:
		terrain.wetness=wet
		grid=terrain.nav_grid("land",0.8,"infantry")
		check(is_equal_approx(grid.get_point_weight_scale(terrain.nav_cell(sample)),1.0/terrain.ground_speed(sample,"infantry")),"wetness refresh retains zone %s" % wet)
		var lazy:AStarGrid2D=terrain.nav_grid("land",1.2,"infantry")
		check(is_equal_approx(lazy.get_point_weight_scale(terrain.nav_cell(sample)),grid.get_point_weight_scale(terrain.nav_cell(sample))),"new radius retains zone %s" % wet)
	terrain.update_field_zones([])
	check(is_equal_approx(grid.get_point_weight_scale(terrain.nav_cell(sample)),1.0/terrain._base_ground_speed(sample,"infantry")),"zone removal restores cached weight")
	check(not terrain.cover(sample) and terrain.concealment(sample)==1.0,"removed zones leave no cover or concealment")
	if not net.is_empty():
		check(not FieldOps.site_ground_clear(camo,"camouflage_net",net.pos,false),"nets cannot stack during placement")
		net.hp=0;FieldOps.sync_obstacles(camo)
		check(camo.terrain.concealment(net.pos)==1.0,"destroyed net removes concealment immediately at sync")
	var placement=fixture()
	var clean:=site(placement,"concertina_wire")
	if clean.x>=0:
		placement.terrain.blocks.append(Rect2(clean+Vector2(1.2,-0.15),Vector2(0.1,0.3)))
		check(not FieldOps.site_ground_clear(placement,"concertina_wire",clean,false),"thin interior blocker rejected between footprint samples")
	print("ENGINEER WORKS: ",checks," checks, ",failures," failures")
	quit(1 if failures>0 else 0)
