extends SceneTree
const Terrain=preload("res://scripts/terrain.gd")
const Sim=preload("res://scripts/simulation.gd")
const Ops=preload("res://scripts/field_ops.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)
func grid_state(grid:AStarGrid2D)->String:
	var cells:Array=[]
	for x in grid.region.size.x:
		for y in grid.region.size.y:cells.append([grid.is_point_solid(Vector2i(x,y)),grid.get_point_weight_scale(Vector2i(x,y))])
	return var_to_str(cells).sha256_text()
func fixture():
	var sim=Sim.new(false,5)
	sim.terrain.blocks.clear();sim.terrain.roadside_blocks.clear();sim.terrain.trees.clear();sim.terrain.poles.clear()
	sim.terrain.navigation.clear();sim.terrain.navigation_weights.clear()
	sim.spawn("engineer",0,Vector2(14,97));sim.update_visibility()
	return sim
func _init()->void:
	var lazy=Terrain.new(5)
	var eager=Terrain.new(5)
	var profiles=["infantry","tracked","wheeled"]
	for t in [lazy,eager]:
		for profile in profiles:t.nav_grid("land",1.2,profile)
	var wheel:AStarGrid2D=lazy.nav_grid("land",1.2,"wheeled")
	var old_weight:=wheel.get_point_weight_scale(Vector2i(10,90))
	lazy.wetness=0.51;eager.wetness=0.51
	lazy.nav_grid("land",1.2,"infantry")
	for profile in profiles:eager.nav_grid("land",1.2,profile)
	check(wheel.get_point_weight_scale(Vector2i(10,90))==old_weight,"unrequested grid untouched at bucket transition")
	check(lazy.navigation_weights.size()==1,"only requested mobility layer generated")
	lazy.wetness=0.62;eager.wetness=0.62
	check(lazy.nav_grid("land",1.2,"wheeled")==wheel,"stale grid refreshed in place")
	check(grid_state(wheel)==grid_state(eager.nav_grid("land",1.2,"wheeled")),"delayed request retains eager band sample, all cells")
	for wet in [0.8,0.1,0.51,1.0,0.0]:
		lazy.wetness=wet;eager.wetness=wet
		for profile in profiles:eager.nav_grid("land",1.2,profile)
		for profile in ["wheeled","infantry","tracked"]:
			check(grid_state(lazy.nav_grid("land",1.2,profile))==grid_state(eager.nav_grid("land",1.2,profile)),"all grid weights/solids equal after lazy request")
			var start:=Vector2(14,97);var finish:=Vector2(40,80)
			check(lazy.path(start,finish,"land",1.2,[],profile)==eager.path(start,finish,"land",1.2,[],profile),"weighted routes equal eager refresh")
	lazy.wetness=0.51;eager.wetness=0.51
	lazy.nav_grid("sea",3.3)
	for profile in profiles:eager.nav_grid("land",1.2,profile)
	lazy.wetness=0.62;eager.wetness=0.62
	check(grid_state(lazy.nav_grid("land",1.2,"tracked"))==grid_state(eager.nav_grid("land",1.2,"tracked")),"sea-first transition preserves land band sample")
	check(lazy.wetness==0.62,"layer generation restores live wetness")
	var old_grid=lazy.nav_grid("land",1.2,"infantry")
	lazy.dynamic_blocks.append(Rect2(20,88,3,3));lazy.navigation.clear();lazy.navigation_weights.clear()
	var rebuilt=lazy.nav_grid("land",1.2,"infantry")
	check(rebuilt!=old_grid and rebuilt.is_point_solid(Vector2i(21,89)),"explicit geometry invalidation rebuilds obstacles")
	var sim=fixture()
	var engineer:Dictionary=sim.units[0]
	var radius:float=sim.definitions.engineer.radius
	var grid=sim.terrain.nav_grid("land",radius,"infantry")
	var before:=grid_state(grid)
	var state:=var_to_str([sim.units,sim.credits,sim.terrain.dynamic_blocks])
	for kind in Ops.KINDS:
		for offset in [0.0,0.2,0.5]:
			var pos:=Vector2(25,97-offset)
			var plan:Dictionary=Ops.proposal(sim,kind,pos,engineer.id)
			check(plan.reason=="","clear site has work route: "+kind)
			if plan.reason!="":continue
			var previous:Vector2=engineer.pos
			var rect:Rect2=Ops.footprint(sim,kind,pos)
			for point in plan.route:
				for i in 101:
					check(not sim.terrain.circle_rect(previous.lerp(point,i/100.0),radius+0.12,rect),"entire route clears proposed rectangle")
				previous=point
			check(not sim.terrain.circle_rect(plan.work_point,radius+0.12,rect),"work point clears entire rectangle")
			check(grid_state(grid)==before,"preview restores all grid solids and weights")
	check(sim.terrain.navigation.size()==1 and sim.terrain.nav_grid("land",radius,"infantry")==grid,"hover reuses grid without cache growth")
	check(var_to_str([sim.units,sim.credits,sim.terrain.dynamic_blocks])==state,"proposal leaves units/orders/funds/obstacles unchanged")
	# Displaced actual body blocks a site despite its distant group anchor.
	var other:Dictionary=sim.spawn("rifle",0,Vector2(45,97))
	other.members[0].pos=Vector2(25,97)
	check(Ops.proposal(sim,"tactical_cover",Vector2(25,97),engineer.id).reason=="Site obstructed","actual living body blocks site")
	other.members[0].hp=0
	var plan:Dictionary=Ops.proposal(sim,"tactical_cover",Vector2(25,97),engineer.id)
	check(plan.reason=="","dead body does not reserve site")
	if plan.reason=="":
		other.members[1].pos=plan.work_point
		var shifted:Dictionary=Ops.proposal(sim,"tactical_cover",Vector2(25,97),engineer.id)
		check(shifted.reason!="" or shifted.work_point.distance_to(other.members[1].pos)>=radius+0.9,"work point avoids displaced actual body")
	sim.visible_cells.clear()
	check(not Ops.can_build(sim,"tactical_cover",Vector2(25,97),engineer.id),"current visibility still required")
	var blocked=fixture()
	blocked.terrain.blocks.append(Rect2(18,0,2,108));blocked.terrain.navigation.clear()
	blocked.visible_cells[blocked.terrain.cell(Vector2(25,97))]=true
	var blocked_grid=blocked.terrain.nav_grid("land",radius,"infantry")
	var blocked_before:=grid_state(blocked_grid)
	check(not Ops.can_build(blocked,"tactical_cover",Vector2(25,97),blocked.units[0].id),"disconnected site rejected")
	check(grid_state(blocked_grid)==blocked_before,"failed search also restores temporary exclusions")
	print("PERFORMANCE REPAIR: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
