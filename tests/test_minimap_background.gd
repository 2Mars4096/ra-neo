extends SceneTree
const Cache=preload("res://scripts/minimap_background.gd")
const Terrain=preload("res://scripts/terrain.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)
func compare(terrain,cache,roads)->void:
	var colors:PackedColorArray=cache.colors_for(terrain,roads)
	for x in terrain.fog_grid_size.x:
		for y in terrain.fog_grid_size.y:
			var id:=Vector2i(x,y);var p:Vector2=terrain.center(id)
			var expected:=Color("3c695b") if terrain.cover(p) else Color("72765b")
			if terrain.is_water(p):expected=Color("285867")
			elif terrain.blocked(p):expected=Color("ada991")
			elif roads.has(id):expected=Color("bbb39a")
			check(colors[x+y*terrain.fog_grid_size.x]==expected,"cached base matches source classification")
func _init()->void:
	var cache=Cache.new()
	for scenario in 6:
		var terrain=Terrain.new(scenario);var roads:={Vector2i(2,3):true}
		compare(terrain,cache,roads)
		var count:int=cache.rebuilds
		cache.colors_for(terrain,roads);check(cache.rebuilds==count,"unchanged map reuses background")
		terrain.dynamic_blocks.append(Rect2(16,16,4,4));compare(terrain,cache,roads)
		check(cache.rebuilds==count+1,"construction invalidates background")
		terrain.field_cover.append(Rect2(30,30,3,2));compare(terrain,cache,roads)
		check(cache.rebuilds==count+2,"completed tactical cover invalidates background")
	print("MINIMAP BACKGROUND: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
