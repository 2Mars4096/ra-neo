extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Classic=preload("res://scripts/classic.gd")
var failures:=0
func check(ok:bool,label:String)->void:
	if not ok:failures+=1;printerr("FAIL: ",label)
func _init()->void:
	var sim=Sim.new(true,4)
	check(sim.objectives.is_empty(),"skirmish has no capture victory")
	check(Classic.structures(sim,0,"hq").size()==1,"start with HQ")
	check(not sim.recruit("tank"),"production prerequisites enforced")
	check(Classic.build(sim,"refinery",0,Vector2(10,45)),"construct refinery within base reach")
	check(not Classic.build(sim,"power",0,Vector2(10,45)),"reject overlapping construction")
	for i in 140:sim.tick(0.1)
	check(Classic.structures(sim,0,"refinery").size()==1,"construction completes")
	var funds:float=sim.credits
	for i in 900:sim.tick(0.1)
	check(sim.credits>funds,"harvester delivers resources")
	check(Classic.enqueue(sim,"harvester",0),"HQ queues replacement harvester")
	var hq:Dictionary=Classic.structures(sim,0,"hq")[0]
	var paid:float=sim.credits
	check(Classic.cancel(sim,hq) and sim.credits>paid,"cancel refunds queued production")
	var electricity:Vector2=Classic.power(sim,0)
	check(electricity.x>=12,"HQ provides basic power")
	var defeated=Sim.new(true,4)
	for building in Classic.structures(defeated,0,"",false):building.hp=0
	Classic.tick(defeated,0.1)
	check(defeated.result=="DEFEAT","losing all own structures ends skirmish")
	for u in sim.units:
		if u.team==1 and sim.definitions[u.kind].get("structure",false):u.hp=0
	Classic.tick(sim,0.1)
	check(sim.result=="VICTORY","destroy enemy structures to win")
	var isolated=Sim.new(false,4)
	isolated.classic.ai_clock=100000
	isolated.classic.attack_clock=100000
	isolated.spawn("hq",0,Vector2(10,61))
	isolated.spawn("refinery",0,Vector2(10,45))
	var barracks=isolated.spawn("barracks",0,Vector2(24,59))
	barracks.queue=[];barracks.rally=Vector2(24,50)
	check(Classic.enqueue(isolated,"rifle"),"ready barracks accepts production")
	check(Classic.committed_count(isolated,"rifle",0)==1,"replacement accounting includes queued units")
	Classic.tick(isolated,2.0)
	check(is_equal_approx(barracks.queue[0].left,7.3),"low power advances production at 35 percent")
	isolated.spawn("power",0,Vector2(8,31))
	Classic.tick(isolated,2.0)
	check(is_equal_approx(barracks.queue[0].left,5.3),"restored power resumes full production")
	Classic.tick(isolated,6.0)
	check(barracks.queue.is_empty() and isolated.living(0).any(func(u):return u.kind=="rifle"),"completed queue spawns a real unit")
	# A blocked exit waits; production must not teleport a unit across the map.
	for i in 12:isolated.spawn("tank",0,barracks.pos+Vector2.from_angle(i*TAU/12)*7)
	check(Classic.production_exit(isolated,barracks,"tank").x<0,"occupied exits reject deployment")
	var before_blocks:int=isolated.terrain.dynamic_blocks.size()
	barracks.hp=0
	Classic.sync_obstacles(isolated)
	check(isolated.terrain.dynamic_blocks.size()==before_blocks-1,"destroyed facility releases navigation obstacle")
	var from:=Vector2(31.91885,37.24885)
	var bodies:Array=[{"pos":Vector2(28.10845,38.06059),"radius":3.88}]
	var route:Array=sim.terrain.path(from,Vector2(24,38),"land",1.9,bodies)
	check(not route.is_empty(),"harvester can route away from adjacent body at grid boundary")
	for point in route:
		check(sim.terrain.avoids_bodies(from,point,bodies),"detour segments preserve body clearance")
		from=point
	var Models=preload("res://scripts/unit_models.gd")
	var art=Models.new()
	for kind in ["hq","power","refinery","barracks","factory","harvester"]:
		var node:=Node3D.new()
		art.build(node,kind,0)
		check(mesh_radius(node)<=float(sim.definitions[kind].radius),"new model fits collision footprint: "+kind)
		node.free()
	print("CLASSIC TESTS: ",failures," failures")
	quit(0 if failures==0 else 1)

func mesh_radius(node:Node3D,transform:Transform3D=Transform3D.IDENTITY) -> float:
	var radius:=0.0
	for child in node.get_children():
		if not child is Node3D:continue
		var local:Transform3D=transform*child.transform
		if child is MeshInstance3D:
			for surface in child.mesh.get_surface_count():
				for vertex in child.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
					var p:Vector3=local*vertex
					radius=maxf(radius,Vector2(p.x,p.z).length())
		radius=maxf(radius,mesh_radius(child,local))
	return radius
