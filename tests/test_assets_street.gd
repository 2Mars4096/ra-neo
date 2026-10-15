extends SceneTree
# Street/town-life/utility asset library: metadata schema, every-vertex bounds under
# rotation, grounded datum, support connectivity, variant distinctness and batching.
const Library=preload("res://scripts/assets_street.gd")
const Visuals=preload("res://scripts/visuals.gd")
const EXPECTED={
	"manhole":["circulation",["round_cast","open_works"]],
	"direction_sign":["circulation",["fingerpost","roadside_panel"]],
	"guardrail":["circulation",["w_beam","wire_rope"]],
	"bicycle_rack":["town_life",["sheffield_stands","wheel_slots"]],
	"pickup":["town_life",["single_cab","crew_cab_canopy"]],
	"bus_stop":["town_life",["glazed_shelter","timber_lean_to"]],
	"transformer":["utilities",["pad_mounted","fenced_compound"]],
	"utility_pole":["utilities",["timber_crossarm","concrete_service"]],
	"overhead_cable":["utilities",["three_phase_span","service_drop"]],
	"drain_outfall":["utilities",["pipe_headwall","box_culvert"]],
}
const KEYS=["kind","variant","category","label","footprint","height","placement","collision","cover","description"]
const VERTEX_BUDGET=24000
const SLACK=0.12 # declared footprint/height may exceed measured geometry by at most this
var checks:=0
var failures:Array[String]=[]
func _init()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok and not failures.has(label):failures.append(label);printerr("FAIL: ",label)

func run()->void:
	var art=Visuals.new()
	var stage:=Node3D.new();root.add_child(stage)
	var raw_json=JSON.parse_string(FileAccess.get_file_as_string("res://resources/assets_street.json"))
	check(raw_json is Array,"json is a list")
	var entries:Array=Library.specs()
	check(entries==raw_json,"specs() mirrors resource")
	check(entries.size()==20,"twenty models")
	var seen:={}
	for entry in entries:
		var id:String="%s/%s"%[entry.get("kind","?"),entry.get("variant","?")]
		for key in KEYS:check(entry.has(key),"schema key "+key+" "+id)
		for key in entry:check(key in KEYS or key=="entrance","no unknown key "+key+" "+id)
		check(not seen.has(id),"unique "+id);seen[id]=true
		check(EXPECTED.has(entry.kind) and entry.variant in EXPECTED[entry.kind][1],"expected pair "+id)
		check(EXPECTED.get(entry.kind,[""])[0]==entry.category,"category "+id)
		check(entry.label is String and entry.label.length()>3,"label "+id)
		check(entry.description is String and entry.description.length()>40,"description "+id)
		check(entry.footprint is Array and entry.footprint.size()==4 and entry.footprint[2]>0 and entry.footprint[3]>0,"footprint shape "+id)
		check((entry.height is float or entry.height is int) and entry.height>0,"height "+id)
		check(entry.placement is Array and not entry.placement.is_empty(),"placement list "+id)
		for tag in entry.get("placement",[]):check(tag is String and tag.length()>2,"placement tag "+id)
		check(entry.collision in ["solid","flat","overhead"],"collision enum "+id)
		check(entry.cover==false,"cover false "+id)
		if entry.has("entrance"):
			check(entry.entrance is Array and entry.entrance.size()==2,"entrance shape "+id)
			check(Library.local_footprint(entry.kind,entry.variant).has_point(Vector2(entry.entrance[0],entry.entrance[1])),"entrance inside footprint "+id)
	for kind in EXPECTED:
		for variant in EXPECTED[kind][1]:check(seen.has(kind+"/"+variant),"listed "+kind+"/"+variant)
	for kind in EXPECTED:
		var signatures:=[]
		for variant in EXPECTED[kind][1]:
			var id:String=kind+"/"+variant
			var entry:=Library.spec(kind,variant)
			var bounds:Rect2=Library.local_footprint(kind,variant)
			var height:float=entry.height
			var model:Node3D=Library.build(art,stage,kind,variant)
			check(model!=null,"valid build "+id)
			if model==null:continue
			var glazed:bool=kind=="bus_stop" and variant=="glazed_shelter"
			check(model.get_child_count()==(2 if glazed else 1),"exact static batch count "+id)
			for part in model.get_children():
				check(part is MeshInstance3D and part.mesh.get_surface_count()==1,"single surface per batch "+id)
			if glazed:_check_glass(model)
			check(model.get_meta("grants_cover")==false,"no implied cover "+id)
			check(model.get_meta("placement_policy")=="library_only","library only "+id)
			check(model.get_meta("local_footprint")==bounds,"footprint meta "+id)
			check(model.find_children("*","Light3D",true,false).is_empty(),"no lights "+id)
			var mesh:MeshInstance3D=model.get_child(0)
			check(mesh.material_override==art.merged_paint,"shared cached batch material "+id)
			var vertices:PackedVector3Array=_vertices(model)
			check(vertices.size()<VERTEX_BUDGET,"vertex budget "+id)
			var lo:=Vector3(INF,INF,INF);var hi:=-lo
			for v in vertices:
				check(bounds.grow(0.001).has_point(Vector2(v.x,v.z)),"local footprint "+id)
				check(v.y>=-0.001 and v.y<=height+0.001,"between datum and declared height "+id)
				lo=lo.min(v);hi=hi.max(v)
			check(absf(lo.y)<0.001,"assembly contacts datum "+id)
			# Honest metadata: declared bounds hug the geometry rather than padding it.
			check(lo.x-bounds.position.x<SLACK and bounds.end.x-hi.x<SLACK and lo.z-bounds.position.y<SLACK and bounds.end.y-hi.z<SLACK,"footprint tight "+id)
			check(height-hi.y<SLACK,"height tight "+id)
			print("STREET MEASURE %s verts=%d x=[%.2f,%.2f] z=[%.2f,%.2f] y=[%.3f,%.2f]"%[id,vertices.size(),lo.x,hi.x,lo.z,hi.z,lo.y,hi.y])
			# Coarse 0.2 m occupancy of the surface, for construction (not colour) comparison.
			var cells:={}
			for v in vertices:cells[Vector3i((v/0.2).floor())]=true
			signatures.append([hash(vertices),cells])
			for yaw in [0.0,PI/2,PI,0.37,-1.1]:
				var origin:=Vector2(20,30)
				var xf:=Transform3D(Basis(Vector3.UP,yaw),Vector3(origin.x,0,origin.y))
				var world:=Rect2(origin,Vector2.ZERO)
				for corner in [bounds.position,Vector2(bounds.end.x,bounds.position.y),bounds.end,Vector2(bounds.position.x,bounds.end.y)]:
					world=world.expand(origin+corner.rotated(-yaw))
				for v in vertices:
					var q:Vector3=xf*v
					check(world.grow(0.001).has_point(Vector2(q.x,q.z)),"rotated footprint "+id)
			var material_count:int=art.materials.size()+art.models.palette.size()
			var repeat:Node3D=Library.build(art,stage,kind,variant)
			check(art.materials.size()+art.models.palette.size()==material_count,"repeat reuses cached materials "+id)
			check(repeat.get_child(0).material_override==art.merged_paint,"repeat shares batch material "+id)
			check(hash(_vertices(repeat))==signatures[-1][0],"deterministic all batches "+id)
			if glazed:
				check(repeat.get_child(1).material_override==model.get_child(1).material_override,"repeat shares glass material")
			if kind=="pickup":check(model.get_child_count()==1,"vehicle glazing stays opaque "+id)
			repeat.free();model.free()
			_check_supports(art,stage,kind,variant)
		if signatures.size()==2:
			check(signatures[0][0]!=signatures[1][0],"variant geometry differs "+kind)
			var a:Dictionary=signatures[0][1];var b:Dictionary=signatures[1][1]
			var shared:=0
			for cell in a:if b.has(cell):shared+=1
			var overlap:=float(shared)/(a.size()+b.size()-shared)
			print("STREET VARIANT OVERLAP %s %.2f"%[kind,overlap])
			check(overlap<0.6,"variant construction distinct "+kind)
	check(Library.build(art,stage,"missing","missing")==null,"unknown kind rejected")
	check(Library.build(art,stage,"pickup","missing")==null,"unknown variant rejected")
	check(Library.local_footprint("pickup","missing").size==Vector2.ZERO,"unknown footprint empty")
	check(stage.get_child_count()==0,"invalid input creates no nodes")
	# Optional opaque silhouette sheet: -- --raster=<png>; excludes transparent panes.
	# Flat CPU shading cannot validate glazing and is not a native capture.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--raster="):_raster(art,stage,arg.trim_prefix("--raster="))
	stage.free()
	print("ASSETS STREET: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)


func _vertices(model:Node3D)->PackedVector3Array:
	var result:=PackedVector3Array()
	for part in model.get_children():
		for vertex in part.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			result.append(part.transform*vertex)
	return result

func _check_glass(model:Node3D)->void:
	var pane:MeshInstance3D=model.get_child(1)
	var mat:StandardMaterial3D=pane.material_override
	check(mat.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA,"glass alpha blending enabled")
	check(mat.albedo_color.a>0.0 and mat.albedo_color.a<=0.22,"broad panes transmit at least 78 percent base background")
	check(mat.cull_mode==BaseMaterial3D.CULL_DISABLED,"glass visible from either side")
	check(mat.albedo_texture==null and not mat.emission_enabled,"glass has no texture or emission")
	check(pane.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"glass adds no shadow batch")
	var vertices:PackedVector3Array=pane.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(vertices.size()==12,"two thin panes four triangles total")
	var area:=0.0
	for i in range(0,vertices.size(),3):
		var cross:Vector3=(vertices[i+1]-vertices[i]).cross(vertices[i+2]-vertices[i])
		check(cross.length()>0.001,"glass triangle nondegenerate")
		area+=cross.length()*0.5
	check(absf(area-(3.12+1.06)*1.8)<0.001,"glass covers full back and end openings")

func _raster(art,stage:Node3D,path:String)->void:
	# Two rows per kind pair: game camera direction, then a low three-quarter view.
	var tile:=Vector2i(320,260)
	var image:=Image.create(tile.x*10,tile.y*4,false,Image.FORMAT_RGB8)
	image.fill(Color("34372e"))
	var depth:=PackedFloat32Array();depth.resize(image.get_width()*image.get_height());depth.fill(1e9)
	var column:=0
	for kind in EXPECTED:
		for v in 2:
			var variant:String=EXPECTED[kind][1][v]
			var model:Node3D=Library.build(art,stage,kind,variant)
			var bounds:Rect2=Library.local_footprint(kind,variant)
			var height:float=Library.spec(kind,variant).height
			var extent:=maxf(maxf(bounds.size.x,bounds.size.y),height)
			for row in 2:
				var view:Vector3=Vector3(26,64,46) if row==0 else Vector3(40,22,60)
				var cell:=Vector2(tile.x*(column%10)+tile.x/2.0,tile.y*(row+2*(column/10))+tile.y/2.0)
				var center:=Vector3(bounds.get_center().x,height/2.0,bounds.get_center().y)
				_draw(model.get_child(0),image,depth,view,center,tile.x*0.8/extent,cell)
			print("STREET RASTER tile %d = %s/%s"%[column,kind,variant])
			column+=1
			model.free()
	print("STREET RASTER ",path," ",image.save_png(path))

func _draw(mesh:MeshInstance3D,image:Image,depth:PackedFloat32Array,view:Vector3,origin:Vector3,scale:float,offset:Vector2)->void:
	var forward:=-view.normalized()
	var right:=forward.cross(Vector3.UP).normalized()
	var up:=right.cross(forward).normalized()
	var sun:=Vector3(-0.45,-1.0,-0.25).normalized()
	var arrays:Array=mesh.mesh.surface_get_arrays(0)
	var verts:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var colors:PackedColorArray=arrays[Mesh.ARRAY_COLOR]
	var idx:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	var size:=image.get_size()
	for tri in range(0,idx.size(),3):
		var w:=[verts[idx[tri]],verts[idx[tri+1]],verts[idx[tri+2]]]
		var n:Vector3=(w[1]-w[0]).cross(w[2]-w[0])
		if n.length_squared()<1e-14:continue
		n=n.normalized()
		if n.dot(forward)>0:n=-n
		var light:=0.42+0.58*maxf(0.0,n.dot(-sun))
		var base:Color=colors[idx[tri]].linear_to_srgb()
		var shade:=Color(base.r*light,base.g*light,base.b*light)
		var p:=[]
		for q in w:
			var rel:Vector3=q-origin
			p.append(Vector3(offset.x+rel.dot(right)*scale,offset.y-rel.dot(up)*scale,rel.dot(forward)))
		var area:float=(p[1].x-p[0].x)*(p[2].y-p[0].y)-(p[2].x-p[0].x)*(p[1].y-p[0].y)
		if absf(area)<1e-6:continue
		for y in range(maxi(0,int(floor(minf(p[0].y,minf(p[1].y,p[2].y))))),mini(size.y-1,int(ceil(maxf(p[0].y,maxf(p[1].y,p[2].y)))))+1):
			for x in range(maxi(0,int(floor(minf(p[0].x,minf(p[1].x,p[2].x))))),mini(size.x-1,int(ceil(maxf(p[0].x,maxf(p[1].x,p[2].x)))))+1):
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

# Unbaked parts must form one support graph rooted at the datum: each part either
# reaches y≈0 or touches (2 cm tolerance, axis-aligned bounds) a supported part.
func _check_supports(art,stage:Node3D,kind:String,variant:String)->void:
	var id:=kind+"/"+variant
	var raw:=Node3D.new();stage.add_child(raw)
	Library._assemble(art,raw,kind,variant)
	if kind=="bus_stop" and variant=="glazed_shelter":Library._shelter_glass(raw)
	var boxes:Array[AABB]=[]
	var riprap_parts:=0
	for part in raw.get_children():
		check(part is MeshInstance3D,"flat part hierarchy "+id)
		var material:Material=part.material_override
		check(material is StandardMaterial3D or art.models.palette.values().has(material),"cached palette material "+id)
		if material is StandardMaterial3D:check(material.albedo_texture==null,"no new textures "+id)
		var bounds:AABB=part.transform*part.mesh.get_aabb()
		boxes.append(bounds)
		if kind=="drain_outfall" and variant=="pipe_headwall" and material is ShaderMaterial:
			var paint:Color=material.get_shader_parameter("paint")
			if paint==Library.STONE or paint==Library.STONE_DARK:
				riprap_parts+=1
				check(absf(bounds.position.y)<0.001,"each rip-rap stone bedded at datum")
				check(not bounds.intersects(AABB(Vector3(-0.55,0.01,1.22),Vector3(1.1,0.4,0.4))),"rip-rap preserves exposed central discharge ground")
	if kind=="drain_outfall" and variant=="pipe_headwall":check(riprap_parts>0,"headwall retains scour-protection rocks")
	var supported:=[]
	supported.resize(boxes.size());supported.fill(false)
	var frontier:Array[int]=[]
	for i in boxes.size():
		if boxes[i].position.y<0.02:supported[i]=true;frontier.append(i)
	while not frontier.is_empty():
		var i:int=frontier.pop_back()
		for j in boxes.size():
			if not supported[j] and boxes[i].grow(0.02).intersects(boxes[j]):
				supported[j]=true;frontier.append(j)
	var floating:=supported.count(false)
	for i in boxes.size():
		if not supported[i]:print("STREET FLOATING %s part %d of %d at %s"%[id,i,boxes.size(),boxes[i]])
	check(floating==0,"every part supported "+id)
	raw.free()
