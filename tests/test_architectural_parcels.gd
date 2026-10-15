extends SceneTree
# Assert every decorative solid stays inside the existing navigation blocker,
# parcels batch into few draws, and each showcase parcel is a distinct design
# with a measurably different mass (not a recolored or reshuffled clone).
const Kit=preload("res://scripts/parcel_kit.gd")
var checks:=0
var failures:Array[String]=[]
func inspect(node:Node3D,r:Rect2,profile:Dictionary,transform:Transform3D=Transform3D.IDENTITY)->void:
	for child in node.get_children():
		if not child is Node3D:continue
		var t:Transform3D=transform*child.transform
		if child is MeshInstance3D:
			for surface in child.mesh.get_surface_count():
				for vertex in child.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
					var p:Vector3=t*vertex
					checks+=1
					if not r.grow(0.002).has_point(Vector2(p.x,p.z)):
						var message:="Parcel escape at %s in %s"%[p,r]
						if failures.size()<8:failures.append(message)
					# Height profile on a 1 m grid measures the actual massing.
					var cell:=Vector2i(int(p.x-r.position.x),int(p.z-r.position.y))
					profile[cell]=maxf(profile.get(cell,0.0),p.y)
		inspect(child,r,profile,t)
func _init()->void:
	var art=preload("res://scripts/visuals.gd").new()
	var scenarios=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	var all_designs:Array[String]=[]
	var draws:=0
	var vertices:=0
	for scenario_index in scenarios.size():
		var scenario:Dictionary=scenarios[scenario_index]
		if scenario.get("style","")!="showcase":continue
		# Mirrors visuals.make_world: the harbor (scenario 6) builds city-building
		# specs through make_harbor_world, not the parcel kit (test_harbor_visuals).
		if scenario_index==6:continue
		var profiles:Array=[]
		for i in scenario.blocks.size():
			var a:Array=scenario.blocks[i]
			var r:=Rect2(a[0],a[1],a[2],a[3])
			var specs:Array=scenario.get("architecture",[])
			var spec:Dictionary=specs[i] if i<specs.size() else {}
			var ruin:bool=spec.get("design","") in Kit.RUINS if not spec.is_empty() else i%3==1
			var plan:Array=Kit.design(r,i,ruin,spec)
			if spec.is_empty() and not Kit.DESIGNS.has("%d,%d"%[int(r.position.x),int(r.position.y)]):failures.append("Unassigned showcase parcel %s"%r)
			if (plan[0] in Kit.RUINS)!=ruin:failures.append("Design %s does not match ruin slot %d"%[plan[0],i])
			if spec.is_empty() and plan[0] in all_designs:failures.append("Repeated design %s"%plan[0])
			all_designs.append(plan[0])
			var root:=Node3D.new()
			if ruin:preload("res://scripts/ruined_building.gd").build(art,root,r,i,spec)
			else:preload("res://scripts/architectural_block.gd").build(art,root,r,i,spec)
			var profile:={}
			inspect(root,r,profile)
			# Batching is required: all trim, leaves and props consolidate statically.
			art.bake_model(root)
			var baked:={}
			inspect(root,r,baked)
			if root.get_child_count()>6:failures.append("Unbatched architecture %s: %s"%[plan[0],root.get_child_count()])
			draws+=root.get_child_count()
			for child in root.get_children():vertices+=child.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
			var peak:=0.0
			for cell in profile:peak=maxf(peak,profile[cell])
			print("PARCEL %s %-15s facing %-5s draws %d peak %.1f m"%[scenario.name,plan[0],plan[1],root.get_child_count(),peak])
			profiles.append([plan[0],profile])
			root.free()
		# Massing must differ: mean absolute 1 m height difference between any two parcels.
		if scenario.has("architecture"):continue # Expanded districts deliberately reuse the 11 established families.
		for x in profiles.size():
			for y in range(x+1,profiles.size()):
				var pa:Dictionary=profiles[x][1];var pb:Dictionary=profiles[y][1]
				var total:=0.0;var cells:=0
				for gx in 9:
					for gz in 8:
						var c:=Vector2i(gx,gz)
						if not pa.has(c) and not pb.has(c):continue
						total+=absf(pa.get(c,0.0)-pb.get(c,0.0));cells+=1
				var difference:=total/maxf(1,cells)
				if difference<0.9:failures.append("Similar massing %s/%s: %.2f m"%[profiles[x][0],profiles[y][0],difference])
	print("PARCEL TOTALS: %d designs, %d static draws, %d vertices"%[all_designs.size(),draws,vertices])
	for message in failures:printerr("FAIL: ",message)
	print("ARCHITECTURAL PARCELS: ","PASS" if failures.is_empty() and checks>0 else "FAIL"," ",checks," vertex checks")
	quit(0 if failures.is_empty() and checks>0 else 1)
