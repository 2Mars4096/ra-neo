extends SceneTree
class SurfaceFixture extends BattleTerrain:
	func on_road(p:Vector2)->bool:return absf(p.y-8.0)<1.7
var checks:=0
var failures:Array[String]=[]
func _init()->void:call_deferred("run")
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message);printerr("FAIL: ",message)
func clean(terrain)->void:
	terrain.blocks.clear();terrain.woods.clear();terrain.trees.clear();terrain.poles.clear()
	terrain.dynamic_blocks.clear();terrain.navigation.clear();terrain.port=false
	terrain.shore_x=80;terrain.rubble=Rect2();terrain.mud=Rect2()
func measure(terrain,origin:Vector2,route:Array,profile:String)->float:
	var total:=0.0
	for point in route:
		var length:float=origin.distance_to(point)
		var samples:=maxi(1,ceili(length/0.2))
		for i in samples:total+=length/samples/terrain.ground_speed(origin.lerp(point,(i+0.5)/samples),profile)
		origin=point
	return total
func run()->void:
	var terrain:=SurfaceFixture.new(0);clean(terrain)
	check(terrain.mobility_profile("rifle")=="infantry" and terrain.mobility_profile("atgm")=="infantry","foot teams use infantry mobility")
	check(terrain.mobility_profile("tank")=="tracked" and terrain.mobility_profile("aa")=="tracked","tracked combat vehicles use tracked mobility")
	check(terrain.mobility_profile("harvester")=="wheeled","harvester uses wheeled mobility")
	var open:=Vector2(20,25)
	check(terrain.ground_speed(open,"infantry")>terrain.ground_speed(open,"tracked") and terrain.ground_speed(open,"tracked")>terrain.ground_speed(open,"wheeled"),"open ground profiles differ")
	for profile in ["infantry","tracked","wheeled"]:
		check(is_equal_approx(terrain.ground_speed(Vector2(40,8),profile),1.0),"firm road preserves base speed: "+profile)
	terrain.mud=Rect2(25,10,20,30)
	var muddy:=Vector2(35,25)
	var dry_wheels:float=terrain.ground_speed(muddy,"wheeled")
	terrain.wetness=1.0
	check(terrain.ground_speed(muddy,"wheeled")<dry_wheels,"wet mud further slows wheels")
	check(terrain.ground_speed(muddy,"infantry")>terrain.ground_speed(muddy,"tracked") and terrain.ground_speed(muddy,"tracked")>terrain.ground_speed(muddy,"wheeled"),"mud vulnerability is profile dependent")
	var start:=Vector2(15,25);var finish:=Vector2(55,25)
	var wheel_route:=terrain.path(start,finish,"land",1.4,[],"wheeled")
	var foot_route:=terrain.path(start,finish,"land",0.8,[],"infantry")
	check(not wheel_route.is_empty() and not foot_route.is_empty(),"both mobility profiles find routes")
	check(measure(terrain,start,wheel_route,"wheeled")<measure(terrain,start,[finish],"wheeled")*0.85,"wheels take materially faster firm-ground detour")
	check(measure(terrain,start,foot_route,"infantry")<=measure(terrain,start,wheel_route,"infantry")*1.05,"infantry need not inherit costly vehicle detour")
	check(wheel_route!=foot_route,"routing distinguishes mobility profile")
	check(terrain.nav_grid("land",1.4,"wheeled")!=terrain.nav_grid("land",1.4,"infantry"),"profile-specific grids do not share wrong weights")
	for profile in ["infantry","tracked","wheeled"]:
		var air:=terrain.path(start,finish,"air",1.4,[],profile)
		check(air.size()==1 and air[0]==finish,"air path independent of surface profile: "+profile)
	clean(terrain)
	terrain.blocks=[Rect2(38,0,4,31),Rect2(38,34,4,38)]
	check(terrain.traversable(Vector2(40,32.5),"land",0.8),"individual soldier fits narrow passage")
	check(not terrain.traversable(Vector2(40,32.5),"land",2.45),"tank footprint cannot fit same passage")
	check(not terrain.path(Vector2(30,32.5),Vector2(50,32.5),"land",0.8,[],"infantry").is_empty(),"individual foot route crosses passage")
	check(terrain.path(Vector2(30,32.5),Vector2(50,32.5),"land",2.45,[],"tracked").is_empty(),"vehicle cannot cheat access through mobility costs")
	check(not terrain.traversable(Vector2(90,50),"land",0.8) and terrain.traversable(Vector2(90,50),"sea",3.3),"water remains domain-specific")
	print("MOBILITY: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
