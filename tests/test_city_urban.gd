extends SceneTree
const Urban=preload("res://scripts/city_buildings_urban.gd")
const Registry=preload("res://scripts/city_buildings.gd")
var checks:=0
var failures:Array[String]=[]
var failure_count:=0
var peak_height:=0.0
const VIEW:=Vector3(26,64,46)
var forward:=-VIEW.normalized()
var right:=forward.cross(Vector3.UP).normalized()
var up:=right.cross(forward).normalized()
var sun:=Vector3(-0.45,-1.0,-0.25).normalized()

func color_of(material:Material,arrays:Array,index:int)->Color:
	if material is ShaderMaterial:
		if material.get_shader_parameter("vertex_paint")==true:
			var colors=arrays[Mesh.ARRAY_COLOR]
			return colors[index] if colors!=null and colors.size()>index else Color.GRAY
		var base=material.get_shader_parameter("base_color")
		if base!=null:return base
		var paint=material.get_shader_parameter("paint")
		if paint!=null:return paint
	elif material is StandardMaterial3D:return material.albedo_color
	return Color.GRAY

func render(root:Node3D,image:Image,depth:PackedFloat32Array,origin:Vector3,scale:float,offset:Vector2)->void:
	var size:=image.get_size()
	for child in root.get_children():
		if not child is MeshInstance3D:continue
		var t:Transform3D=child.transform
		var arrays:Array=child.mesh.surface_get_arrays(0)
		var verts:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var idx=arrays[Mesh.ARRAY_INDEX]
		var count:int=idx.size() if idx!=null and idx.size()>0 else verts.size()
		for tri in range(0,count,3):
			var ids:=[idx[tri],idx[tri+1],idx[tri+2]] if idx!=null and idx.size()>0 else [tri,tri+1,tri+2]
			var w:=[t*verts[ids[0]],t*verts[ids[1]],t*verts[ids[2]]]
			var n:Vector3=(w[1]-w[0]).cross(w[2]-w[0])
			if n.length_squared()<1e-12:continue
			n=n.normalized()
			if n.dot(forward)>0:n=-n
			var light:=0.42+0.58*maxf(0.0,n.dot(-sun))
			var base:Color=color_of(child.material_override,arrays,ids[0])
			var shade:=Color(base.r*light,base.g*light,base.b*light)
			var p:=[]
			for v in w:
				var rel:Vector3=v-origin
				p.append(Vector3(offset.x+rel.dot(right)*scale,offset.y-rel.dot(up)*scale,rel.dot(forward)))
			var minx:=maxi(0,int(floor(minf(p[0].x,minf(p[1].x,p[2].x)))))
			var maxx:=mini(size.x-1,int(ceil(maxf(p[0].x,maxf(p[1].x,p[2].x)))))
			var miny:=maxi(0,int(floor(minf(p[0].y,minf(p[1].y,p[2].y)))))
			var maxy:=mini(size.y-1,int(ceil(maxf(p[0].y,maxf(p[1].y,p[2].y)))))
			var area:float=(p[1].x-p[0].x)*(p[2].y-p[0].y)-(p[2].x-p[0].x)*(p[1].y-p[0].y)
			if absf(area)<1e-6:continue
			for y in range(miny,maxy+1):
				for x in range(minx,maxx+1):
					var px:=x+0.5;var py:=y+0.5
					var a:float=((p[1].x-px)*(p[2].y-py)-(p[2].x-px)*(p[1].y-py))/area
					var b:float=((p[2].x-px)*(p[0].y-py)-(p[0].x-px)*(p[2].y-py))/area
					var c:=1.0-a-b
					if a<0 or b<0 or c<0:continue
					var z:float=a*p[0].z+b*p[1].z+c*p[2].z
					var k:=y*size.x+x
					if z<depth[k]:
						depth[k]=z
						image.set_pixel(x,y,shade)


func verify(ok:bool,message:String)->void:
	checks+=1
	if not ok:
		failure_count+=1
		if failures.size()<30:failures.append(message)
func inspect(node:Node3D,s:Dictionary,t:Transform3D=Transform3D.IDENTITY)->int:
	var triangles:=0
	for child in node.get_children():
		if not child is Node3D:continue
		var transform:Transform3D=t*child.transform
		if child is MeshInstance3D:
			for surface in child.mesh.get_surface_count():
				var arrays:Array=child.mesh.surface_get_arrays(surface)
				var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
				var indices=arrays[Mesh.ARRAY_INDEX]
				triangles+=(indices.size() if indices!=null and indices.size()>0 else vertices.size())/3
				for vertex in vertices:
					var p:Vector3=transform*vertex
					peak_height=maxf(peak_height,p.y)
					verify(absf(p.x)<=float(s.source_size[0])/2+0.003 and absf(p.z)<=float(s.source_size[1])/2+0.003 and p.y>=-0.003 and p.y<=Registry.height_cap(s.design,s.floors)+0.003,"%s v%d damage%d escape %s size %s"%[s.design,s.variant,s.damage,p,s.source_size])
		triangles+=inspect(child,s,transform)
	return triangles
func review(art,s:Dictionary)->void:
	var image:=Image.create(1200,400,false,Image.FORMAT_RGB8)
	image.fill(Color("43483f"))
	var depth:=PackedFloat32Array();depth.resize(1200*400);depth.fill(1e9)
	for damage in 3:
		s.damage=damage
		var root:=Node3D.new()
		Urban.build(art,root,s);art.bake_model(root)
		var scale:=minf(340.0/(float(s.source_size[0])*0.87+float(s.source_size[1])*0.5),300.0/(Registry.height_cap(s.design,s.floors)*0.65+float(s.source_size[1])*0.85))
		if s.design=="cathedral":scale*=1.25
		render(root,image,depth,Vector3(0,Registry.height_cap(s.design,s.floors)*0.35,0),scale,Vector2(damage*400+200,210))
		root.free()
	verify(image.save_png("res://artifacts/city-urban-%s.png"%s.design)==OK,"PNG failed")
func _init()->void:
	var art=preload("res://scripts/visuals.gd").new()
	var builds:=0
	for design in Registry.DESIGNS:
		var row:Dictionary=Registry.DESIGNS[design]
		if row.builder!="urban":continue
		if not OS.get_cmdline_user_args().is_empty() and design not in OS.get_cmdline_user_args():continue
		var maximum:=0
		peak_height=0.0
		for size_index in 3:
			var t:=size_index/2.0
			for variant in 4:
				for palette in 4:
					for damage in 3:
						var s:Dictionary={"design":design,"source_size":[lerpf(row.w[0],row.w[1],t),lerpf(row.d[0],row.d[1],t)],"floors":int(round(lerpf(row.floors[0],row.floors[1],t))),"variant":variant,"palette":palette,"damage":damage,"seed":173+variant}
						var root:=Node3D.new()
						Urban.build(art,root,s)
						var before:=inspect(root,s)
						verify(before>0,"Empty "+design)
						art.bake_model(root)
						var after:=inspect(root,s)
						verify(before==after,"Bake topology changed "+design)
						verify(after<=(8000 if design in ["stalin_block","panel_5","panel_9","point_tower","school","civic_hall"] else 3000),"Triangle budget %s: %d"%[design,after])
						verify(root.get_child_count()<=6,"Too many batches "+design)
						maximum=maxi(maximum,after)
						root.free();builds+=1
		print("URBAN %s maximum %d triangles, peak %.2f / cap %.2f"%[design,maximum,peak_height,Registry.height_cap(design,row.floors[1])])
		var sample:=Registry.normalized(Registry.sample(design))
		sample.variant=1
		review(art,sample)
	print("URBAN builds: ",builds,"; review columns intact / damaged / ruined")
	for failure in failures:printerr("FAIL: ",failure)
	print("CITY URBAN: %d checks, %d failures"%[checks,failure_count])
	quit(0 if failures.is_empty() else 1)
