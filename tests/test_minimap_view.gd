extends SceneTree
# The minimap view outline on black_sea_harbor is the ground quad under the
# battlefield corners: 4 corners inside the minimap, convex, around the camera
# focus, and each corner projects back onto its screen corner, at the zoom
# limits and default zoom. A view that overhangs the map is clipped, not folded.
const Sim=preload("res://scripts/simulation.gd")
var failures:=0
var checks:=0
var battle
var hud
var sim

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: ",label)

func harbor_index()->int:
	var configs:Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	for i in configs.size():
		if configs[i].id=="black_sea_harbor":return i
	return -1

func _init()->void:
	Sim.scenario_selection=harbor_index()
	call_deferred("run")

func convex(poly:PackedVector2Array)->bool:
	var sign:=0.0
	for i in poly.size():
		var a:=poly[i];var b:=poly[(i+1)%poly.size()];var c:=poly[(i+2)%poly.size()]
		var turn:=(b-a).cross(c-b)
		if absf(turn)<0.001:continue
		if sign==0.0:sign=signf(turn)
		elif signf(turn)!=sign:return false
	return sign!=0.0

func to_minimap(p:Vector2)->Vector2:
	return hud.minimap.position+p/sim.terrain.world_size*hud.minimap.size

# The pre-fix outline: Plane.intersects_ray per corner, each clamped to the map.
func legacy_outline()->PackedVector2Array:
	var out:=PackedVector2Array()
	var view:Rect2=hud.battlefield_rect()
	for corner in [view.position,Vector2(view.end.x,view.position.y),view.end,Vector2(view.position.x,view.end.y)]:
		out.append(to_minimap((battle.world_pos(corner)/sim.terrain.world_size).clamp(Vector2.ZERO,Vector2.ONE)*sim.terrain.world_size))
	return out

func area(poly:PackedVector2Array)->float:
	var total:=0.0
	for i in poly.size():total+=poly[i].cross(poly[(i+1)%poly.size()])
	return absf(total)*0.5

func look(focus:Vector2,zoom:float)->void:
	battle.camera_size=zoom;battle.camera_zoom_target=zoom
	battle.camera_focus=Vector3(focus.x,0,focus.y)
	battle.update_camera()

func check_view(label:String)->void:
	var outline:PackedVector2Array=hud.minimap_view_outline(sim)
	var focus:=to_minimap(Vector2(battle.camera_focus.x,battle.camera_focus.z))
	var view:Rect2=hud.battlefield_rect()
	var screen:=[view.position,Vector2(view.end.x,view.position.y),view.end,Vector2(view.position.x,view.end.y)]
	var ground:PackedVector2Array=battle.view_ground_polygon()
	var worst:=0.0
	for i in 4:worst=maxf(worst,battle.camera.unproject_position(Vector3(ground[i].x,0,ground[i].y)).distance_to(screen[i]))
	var inside:=true
	for p in outline:inside=inside and hud.minimap.grow(0.5).has_point(p)
	print("%s zoom=%.0f outline=%s area=%.0f legacy=%s legacy_area=%.0f corner_err=%.3fpx" % [label,battle.camera_size,outline,area(outline),legacy_outline(),area(legacy_outline()),worst])
	check(outline.size()==4,label+": 4 corners")
	check(inside,label+": corners inside the minimap")
	check(convex(outline),label+": convex")
	check(Geometry2D.is_point_in_polygon(focus,outline),label+": contains the camera focus")
	check(worst<1.0,label+": ground corners project onto the screen corners")

func run()->void:
	root.size=Vector2i(1440,900)
	battle=load("res://scenes/main.tscn").instantiate()
	root.add_child(battle)
	current_scene=battle
	battle.set_process(false)
	await process_frame
	await process_frame
	hud=battle.hud;sim=battle.sim
	check(sim.scenario.id=="black_sea_harbor","harbor loaded")
	check(hud.minimap.size.x>0,"minimap laid out")
	var centre:Vector2=sim.terrain.world_size*0.5
	for zoom in [battle.MIN_ZOOM,72.0,battle.MAX_ZOOM]:
		look(centre,zoom)
		check_view("centre")
	# Far zoom at the map corners: the focus clamp keeps the whole view on the map.
	for corner in [Vector2.ZERO,sim.terrain.world_size]:
		look(corner,battle.MAX_ZOOM)
		check_view("corner %s" % corner)
	# A view that overhangs the map edge (bypassing the clamp) is clipped to the
	# minimap: still convex, inside the frame and around the focus.
	battle.camera_size=battle.MAX_ZOOM;battle.camera.size=battle.MAX_ZOOM
	battle.camera_focus=Vector3(30,0,30)
	battle.camera.position=battle.camera_focus+Vector3(26,64,46)
	battle.camera.look_at(battle.camera_focus,Vector3.UP)
	var clipped:PackedVector2Array=hud.minimap_view_outline(sim)
	var inside:=true
	for p in clipped:inside=inside and hud.minimap.grow(0.5).has_point(p)
	print("overhang outline=%s legacy=%s" % [clipped,legacy_outline()])
	check(clipped.size()>=4 and inside,"overhang: clipped to the minimap")
	check(convex(clipped),"overhang: convex")
	check(Geometry2D.is_point_in_polygon(to_minimap(Vector2(30,30)),clipped),"overhang: contains the focus")
	var started:=Time.get_ticks_usec()
	for i in 1000:hud.minimap_view_outline(sim)
	print("overhang outline cost %.1f us" % ((Time.get_ticks_usec()-started)/1000.0))
	print("MINIMAP VIEW: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
