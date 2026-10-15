extends SceneTree
# Measures nav_grid lazy reweight cost after a wetness bucket change vs a warm path.
const Sim=preload("res://scripts/simulation.gd")
func _init()->void:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	var idx:=0
	for i in configs.size():
		if configs[i].id=="black_sea_harbor":idx=i
	var sim=Sim.new(true,idx)
	var t=sim.terrain
	print("nav_size ",t.nav_size)
	for key in t.navigation.keys():print("grid ",key)
	for w in [0.0,0.45,0.45,0.1]:
		t.wetness=w
		for profile in ["tracked","infantry"]:
			var r:=1.82 if profile=="tracked" else 0.8
			var s:=Time.get_ticks_usec()
			t.nav_grid("land",r,profile)
			var g:=(Time.get_ticks_usec()-s)/1000.0
			s=Time.get_ticks_usec()
			var p:Array=t.path(Vector2(922,206),Vector2(274,685),"land",r,[],profile)
			print("wet %.2f %s nav_grid=%.1fms path=%.1fms n=%d" % [w,profile,g,(Time.get_ticks_usec()-s)/1000.0,p.size()])
	quit()
