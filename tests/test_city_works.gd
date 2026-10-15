extends SceneTree
# CPU review uses the game camera direction and flat base-color lighting.
# It does not simulate native atlas shading, shadows, or frame-time cost.
const Works=preload("res://scripts/city_buildings_works.gd")
const City=preload("res://scripts/city_buildings.gd")
const VIEW:=Vector3(26,64,46)
var forward:=-VIEW.normalized()
var right:=forward.cross(Vector3.UP).normalized()
var up:=right.cross(forward).normalized()
var sun:=Vector3(-0.45,-1.0,-0.25).normalized()
var checks:=0
var failures:Array[String]=[]
var builds:=0
var failure_count:=0

func expect(ok:bool,message:String)->void:
	checks+=1
	if not ok:
		failure_count+=1
		if failures.size()<20:failures.append(message)

func inspect(node:Node3D,w:float,d:float,ceiling:float,label:String,t:Transform3D=Transform3D.IDENTITY)->int:
	var triangles:=0
	for child in node.get_children():
		if not child is Node3D:continue
		var transform:Transform3D=t*child.transform
		if child is MeshInstance3D:
			for surface in child.mesh.get_surface_count():
				var arrays:Array=child.mesh.surface_get_arrays(surface)
				var verts:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
				var idx=arrays[Mesh.ARRAY_INDEX]
				triangles+=int((idx.size() if idx!=null and idx.size()>0 else verts.size())/3)
				for vertex in verts:
					var p:Vector3=transform*vertex
					expect(p.is_finite() and absf(p.x)<=w/2+0.002 and absf(p.z)<=d/2+0.002 and p.y>=-0.002 and p.y<=ceiling+0.002,"%s escape %s ceiling %.2f"%[label,p,ceiling])
		triangles+=inspect(child,w,d,ceiling,label,transform)
	return triangles

func review(art,damage:int)->void:
	var image:=Image.create(1600,1400,false,Image.FORMAT_RGB8)
	image.fill(Color("34372e"))
	var depth:=PackedFloat32Array();depth.resize(1600*1400);depth.fill(1e9)
	var n:=0
	for design in City.DESIGNS:
		var row:Dictionary=City.DESIGNS[design]
		if row.builder!="works":continue
		var w:float=(row.w[0]+row.w[1])/2.0;var d:float=(row.d[0]+row.d[1])/2.0
		var root:=Node3D.new()
		Works.build(art,root,{"design":design,"source_size":[w,d],"floors":row.floors[1],"variant":n%4,"palette":n%4,"damage":damage,"seed":827+n})
		art.bake_model(root)
		var scale:float=minf(340.0/(w*0.88+d*0.5),240.0/(d*0.8+w*0.5+row.floors[1]*2.7))
		render(root,image,depth,Vector3(0,2,0),scale,Vector2((n%4)*400+200,int(n/4)*350+190))
		print("REVIEW tile %d: %s"%[n,design])
		root.free();n+=1
	var path:="res://artifacts/city-works-damage-%d.png"%damage
	expect(image.save_png(path)==OK,"Cannot save "+path)
	print("REVIEW ",path)

func _init()->void:
	var art=preload("res://scripts/visuals.gd").new()
	if "--review" in OS.get_cmdline_user_args():
		for damage in 3:review(art,damage)
	else:
		for design in City.DESIGNS:
			var row:Dictionary=City.DESIGNS[design]
			if row.builder!="works":continue
			var peak:=0
			for size in 3:
				var w:float=lerpf(row.w[0],row.w[1],size/2.0);var d:float=lerpf(row.d[0],row.d[1],size/2.0)
				for floors in range(row.floors[0],row.floors[1]+1):
					for variant in 4:
						for damage in 3:
							for palette in 4:
								var root:=Node3D.new()
								var spec:={"design":design,"source_size":[w,d],"floors":floors,"variant":variant,"palette":palette,"damage":damage,"seed":1009+variant*53+size}
								Works.build(art,root,spec)
								var ceiling:float=12.0 if design in ["transit_shed","workshop_hall"] else floors*2.7+4
								var label:="%s size%d f%d v%d p%d damage%d"%[design,size,floors,variant,palette,damage]
								var tris:=inspect(root,w,d,ceiling,label)
								expect(tris>0,label+" empty")
								var budget:=2000 if design in ["stone_house","outbuilding","dacha_hut","gatehouse","petrol_station"] else 6000
								expect(tris<=budget,"%s triangles %d > %d"%[label,tris,budget])
								peak=maxi(peak,tris)
								# Check batching at every size/variant/damage/floor combination.
								if palette==0:
									art.bake_model(root)
									expect(inspect(root,w,d,ceiling,label+" baked")==tris,label+" batching triangle mismatch")
								root.free();builds+=1
			print("TRIANGLES %-16s max %d"%[design,peak])
	print("BUILDS: ",builds)
	for message in failures:printerr("FAIL: ",message)
	print("CITY WORKS: %d checks, %d failures"%[checks,failure_count])
	quit(0 if failures.is_empty() else 1)

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

