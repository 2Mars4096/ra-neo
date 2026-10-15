extends SceneTree
func _init()->void:call_deferred("run")
func run()->void:
	var stage:=Node3D.new();root.add_child(stage);var art=preload("res://scripts/visuals.gd").new()
	for kind in ["warehouse","gutted_shed"]:
		var m=preload("res://scripts/assets_existing.gd").build(art,stage,kind,"parcel")
		var box:=AABB();var first:=true
		for child in m.get_children():
			if child is MeshInstance3D:
				var next:AABB=child.transform*child.mesh.get_aabb()
				box=next if first else box.merge(next);first=false
		print(kind," ",box)
	quit()
