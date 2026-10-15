extends SceneTree
# Headless parcel review: CPU-rasterizes the baked parcel meshes from the game
# camera direction with flat lighting and base colors (no atlas textures,
# shadows or post effects). It shows silhouettes, massing and arrangement only;
# native captures remain the authority on final appearance.
const Kit=preload("res://scripts/parcel_kit.gd")
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

func sheet(art,scenario:Dictionary,scale:float,path:String)->void:
	var lo:=Vector2(1e9,1e9);var hi:=Vector2(-1e9,-1e9)
	for a in scenario.blocks:
		lo=lo.min(Vector2(a[0],a[1]));hi=hi.max(Vector2(a[0]+a[2],a[1]+a[3]))
	var center:=Vector3((lo.x+hi.x)/2,2.0,(lo.y+hi.y)/2)
	var extent:=(hi-lo).length()*scale*0.75+120
	var size:=Vector2i(int(extent*1.5),int(extent))
	var image:=Image.create(size.x,size.y,false,Image.FORMAT_RGB8)
	image.fill(Color("34372e"))
	var depth:=PackedFloat32Array();depth.resize(size.x*size.y);depth.fill(1e9)
	# Ground plane hint: parcel blocker outlines.
	for i in scenario.blocks.size():
		var a:Array=scenario.blocks[i]
		var r:=Rect2(a[0],a[1],a[2],a[3])
		var root:=Node3D.new()
		var ruin:bool=i%3==1
		if ruin:preload("res://scripts/ruined_building.gd").build(art,root,r,i)
		else:preload("res://scripts/architectural_block.gd").build(art,root,r,i)
		art.bake_model(root)
		render(root,image,depth,center,scale,Vector2(size)/2)
		print("REVIEW %s %d %s"%[scenario.name,i,Kit.design(r,i,ruin)])
		root.free()
	print("PARCEL REVIEW ",path," ",image.save_png(path))

# Close-up contact sheet: each parcel centred in its own tile.
func closeups(art,scenarios:Array,scale:float,path:String)->void:
	var tiles:=[]
	for scenario in scenarios:
		if scenario.get("style","")!="showcase":continue
		for i in scenario.blocks.size():tiles.append([scenario.blocks[i],i])
	var tile:=Vector2i(400,380)
	var columns:=4
	var size:=Vector2i(tile.x*columns,tile.y*int(ceil(tiles.size()/float(columns))))
	var image:=Image.create(size.x,size.y,false,Image.FORMAT_RGB8)
	image.fill(Color("34372e"))
	var depth:=PackedFloat32Array();depth.resize(size.x*size.y);depth.fill(1e9)
	for n in tiles.size():
		var a:Array=tiles[n][0];var i:int=tiles[n][1]
		var r:=Rect2(a[0],a[1],a[2],a[3])
		var root:=Node3D.new()
		if i%3==1:preload("res://scripts/ruined_building.gd").build(art,root,r,i)
		else:preload("res://scripts/architectural_block.gd").build(art,root,r,i)
		art.bake_model(root)
		var cell:=Vector2(tile.x*(n%columns)+tile.x/2.0,tile.y*(n/columns)+tile.y/2.0+20)
		render(root,image,depth,Vector3(r.get_center().x,2.5,r.get_center().y),scale,cell)
		root.free()
	print("PARCEL REVIEW ",path," ",image.save_png(path))

func _init()->void:
	var art=preload("res://scripts/visuals.gd").new()
	var scenarios=JSON.parse_string(FileAccess.get_file_as_string("res://resources/scenarios.json"))
	closeups(art,scenarios,30.0,"res://artifacts/parcel-review-closeups.png")
	for scenario in scenarios:
		if scenario.get("style","")!="showcase":continue
		sheet(art,scenario,13.0,"res://artifacts/parcel-review-%s.png"%str(scenario.id))
	quit()
