extends SceneTree

# Controlled surface fixture: a firm route above a slow wet field. It deliberately
# has no buildings, so a geometry-only direct shortcut would cross the mud.
class SurfaceFixture extends BattleTerrain:
	func on_road(p:Vector2)->bool:return absf(p.y-13.0)<=1.7

var checks:=0
var failures:Array[String]=[]
func _init()->void:call_deferred("run")
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message);printerr("FAIL: ",message)

# Independent fine sampling measures travel time in units of base unit speed.
func measured_cost(terrain,origin:Vector2,route:Array)->float:
	var cost:=0.0
	for waypoint in route:
		var distance:float=origin.distance_to(waypoint)
		var n:=maxi(1,ceili(distance/0.2))
		for i in n:
			cost+=distance/n/terrain.ground_speed(origin.lerp(waypoint,(i+0.5)/n))
		origin=waypoint
	return cost

func route_clear(terrain,origin:Vector2,route:Array,radius:float)->bool:
	for waypoint in route:
		if not terrain.segment_clear(origin,waypoint,"land",radius):return false
		origin=waypoint
	return true

func run()->void:
	var terrain:=SurfaceFixture.new(0)
	terrain.blocks.clear();terrain.woods.clear();terrain.trees.clear();terrain.poles.clear()
	terrain.dynamic_blocks.clear();terrain.navigation.clear()
	terrain.port=false;terrain.shore_x=94
	terrain.rubble=Rect2(0,0,0,0)
	terrain.mud=Rect2(25,15,20,20);terrain.wetness=1.0
	var start:=Vector2(15,25)
	var finish:=Vector2(55,25)
	var route:=terrain.path(start,finish,"land",1.4)
	check(not route.is_empty(),"wet field route exists")
	check(route.size()>1,"clear direct line must not erase cheaper firm-surface detour")
	check(measured_cost(terrain,start,route)<measured_cost(terrain,start,[finish])*0.95,"chosen detour saves meaningful travel time")
	check(route_clear(terrain,start,route,1.4),"all smoothed vehicle segments clear full footprint")
	check(not route.is_empty() and route[-1].is_equal_approx(finish),"route retains requested destination")
	var air:=terrain.path(start,finish,"air",1.4)
	check(air.size()==1 and air[0]==finish,"air ignores ground travel cost")
	terrain.wetness=0
	terrain.mud=Rect2(0,0,0,0);terrain.navigation.clear()
	var direct:=terrain.path(start,finish,"land",1.4)
	check(direct.size()==1,"dry open terrain retains economical direct travel")
	terrain.dynamic_blocks.append(Rect2(31,22,8,6));terrain.navigation.clear()
	var around:=terrain.path(start,finish,"land",1.4)
	check(not around.is_empty() and route_clear(terrain,start,around,1.4),"construction blocker still forces footprint-safe detour")
	terrain.dynamic_blocks.clear();terrain.navigation.clear()
	terrain.wetness=1.0;terrain.mud=Rect2(25,15,20,20)
	var conservative:=terrain.nav_grid("land",1.4)
	conservative.fill_solid_region(conservative.region,true)
	var fallback:=terrain.path(start,finish,"land",1.4)
	check(fallback.size()==1 and fallback[0]==finish,"safe direct route survives conservative grid failure")
	print("ROAD ROUTING: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
