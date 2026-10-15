extends SceneTree
const Terrain=preload("res://scripts/terrain.gd")
func _init()->void:
	var terrain=Terrain.new(5)
	var old_times:Array=[];var cached_times:Array=[]
	var base:=PackedColorArray();base.resize(terrain.fog_grid_size.x*terrain.fog_grid_size.y)
	for iteration in 25:
		var start:=Time.get_ticks_usec()
		var image:=Image.create(terrain.fog_grid_size.x,terrain.fog_grid_size.y,false,Image.FORMAT_RGB8)
		for x in terrain.fog_grid_size.x:
			for y in terrain.fog_grid_size.y:
				var p:Vector2=terrain.center(Vector2i(x,y))
				var c:=Color("3c695b") if terrain.cover(p) else Color("72765b")
				if terrain.is_water(p):c=Color("285867")
				elif terrain.blocked(p):c=Color("ada991")
				base[x+y*terrain.fog_grid_size.x]=c
				image.set_pixel(x,y,c.darkened(0.5))
		old_times.append((Time.get_ticks_usec()-start)/1000.0)
		start=Time.get_ticks_usec()
		var reused:=Image.create(terrain.fog_grid_size.x,terrain.fog_grid_size.y,false,Image.FORMAT_RGB8)
		for x in terrain.fog_grid_size.x:
			for y in terrain.fog_grid_size.y:reused.set_pixel(x,y,base[x+y*terrain.fog_grid_size.x].darkened(0.5))
		cached_times.append((Time.get_ticks_usec()-start)/1000.0)
		assert(image.get_data()==reused.get_data())
	old_times.sort();cached_times.sort()
	var report:={"cells":base.size(),"iterations":25,"reclassified_ms_median":old_times[12],"cached_ms_median":cached_times[12],"reclassified_p95":old_times[23],"cached_p95":cached_times[23],"image_bytes_identical":true,"scope":"CPU background classification only; excludes road rasterization, fog knowledge lookup and GPU; concurrent workers may affect absolute timings"}
	print(JSON.stringify(report));FileAccess.open("res://artifacts/minimap-profile.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));quit()
