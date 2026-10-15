extends SceneTree
const L=preload("res://scripts/asset_library.gd")
const Art=preload("res://scripts/visuals.gd")
var checks:=0
var failures:=0
func colors(model:Node)->Array:
	var result:Array=[]
	if model is MeshInstance3D:
		for surface in model.mesh.get_surface_count():
			var data=model.mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]
			result.append(data)
	for child in model.get_children():result.append_array(colors(child))
	return result
func _init()->void:call_deferred("run")
func run()->void:
	var stage:=Node3D.new();root.add_child(stage)
	for spec in L.entries():
		var fresh=Art.new();var after_enemy=Art.new()
		var unit:=Node3D.new();stage.add_child(unit);after_enemy.models.build(unit,"tank",1);unit.free()
		var a:=L.build(fresh,stage,spec.id);var b:=L.build(after_enemy,stage,spec.id)
		checks+=1
		if colors(a)!=colors(b):failures+=1;printerr("FAIL: neutral colors depend on faction ",spec.id)
		a.free();b.free()
	stage.free()
	print("ASSET PALETTE: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
