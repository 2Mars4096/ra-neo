extends SceneTree
const Library=preload("res://scripts/assets_battlefield.gd")
const Visuals=preload("res://scripts/visuals.gd")
const Palette=preload("res://scripts/environment_palette.gd")

class RawVisuals:
	extends "res://scripts/visuals.gd"
	func bake_model(_model:Node3D)->void:pass

var checks:=0
var failures:Array[String]=[]
func _init()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok and not failures.has(label):failures.append(label);printerr("FAIL: ",label)

func geometry(model:Node3D,label:String)->Dictionary:
	var points:=PackedVector3Array()
	var triangles:=0
	for child in model.get_children():
		check(child is MeshInstance3D,label+" mesh-only hierarchy")
		if not child is MeshInstance3D:continue
		check(child.mesh!=null,label+" mesh exists")
		for surface in child.mesh.get_surface_count():
			var arrays:Array=child.mesh.surface_get_arrays(surface)
			var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
			for v in vertices:
				var point:Vector3=child.transform*v
				check(point.is_finite(),label+" finite vertex")
				points.append(point)
			var count:int=indices.size() if not indices.is_empty() else vertices.size()
			check(count%3==0,label+" triangle topology")
			triangles+=count/3
			for index in indices:check(index>=0 and index<vertices.size(),label+" valid index")
	return {"points":points,"triangles":triangles}

func bounds(points:PackedVector3Array,spec:Dictionary,label:String)->void:
	var f:Array=spec.footprint
	var footprint:=Rect2(f[0],f[1],f[2],f[3])
	var volume:=AABB(Vector3(f[0],0,f[1]),Vector3(f[2],spec.height,f[3]))
	var minimum:=INF
	for v in points:
		check(footprint.grow(0.001).has_point(Vector2(v.x,v.z)),label+" local XZ bounds")
		check(v.y>=-0.001 and v.y<=float(spec.height)+0.001,label+" full vertical bounds")
		minimum=minf(minimum,v.y)
	check(absf(minimum)<0.001,label+" grounded datum")
	for yaw in [0.0,PI/2,PI,PI*1.5,0.37,-0.81]:
		var pose:=Transform3D(Basis(Vector3.UP,yaw),Vector3(13,0.7,-19))
		var world:AABB=pose*volume
		for v in points:
			check(world.grow(0.002).has_point(pose*v),label+" rotated full bounds")

func run()->void:
	var art=Visuals.new()
	var raw_art=RawVisuals.new()
	var stage:=Node3D.new();root.add_child(stage)
	var specs:Array=Library.specs()
	check(specs.size()==18,"exactly eighteen entries")
	var variants:Dictionary={}
	var ids:Dictionary={}
	for spec in specs:
		var label:String=spec.kind+"/"+spec.variant
		check(not ids.has(label),"unique metadata pair "+label);ids[label]=true
		check(spec.category in ["field_defences","damage"],label+" category")
		check(spec.collision in ["solid","flat","overhead"] and spec.cover==false,label+" declarative placement")
		check(spec.placement.has("flat_ground") and spec.placement.has("library_only"),label+" placement tags")
		check(spec.footprint.size()==4 and spec.footprint[2]>0 and spec.footprint[3]>0 and spec.height>0,label+" positive bounds")
		check(not spec.label.is_empty() and not spec.description.is_empty(),label+" catalogue text")
		var model:Node3D=Library.build(art,stage,spec.kind,spec.variant)
		check(model!=null,label+" builds")
		if model==null:continue
		check(model.transform==Transform3D.IDENTITY,label+" local origin")
		check(model.get_meta("grants_cover")==false and model.get_meta("placement_policy")=="library_only",label+" no gameplay claim")
		check(model.get_child_count()==1,label+" one static batch")
		var baked:Dictionary=geometry(model,label)
		check(baked.points.size()>0 and baked.points.size()<24000,label+" bounded geometry budget")
		bounds(baked.points,spec,label)
		var top:=0.0
		for v in baked.points:top=maxf(top,v.y)
		# Declared height stays a conservative envelope but must not drift far above the model.
		check(float(spec.height)-top<=0.3,label+" declared height within 0.3 of built geometry")
		print("BOUNDS ",label," declared=",spec.height," built=",snappedf(top,0.001)," vertices=",baked.points.size())
		for child in model.get_children():
			if child is MeshInstance3D:
				check(child.material_override==art.merged_paint,label+" shared cached batch material")
				check(child.mesh.get_surface_count()==1,label+" one surface")
				var colors:PackedColorArray=child.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
				check(colors.size()==child.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(),label+" baked vertex paint")
		if not variants.has(spec.kind):variants[spec.kind]=[]
		variants[spec.kind].append(hash(baked.points))
		var raw:Node3D=Library.build(raw_art,stage,spec.kind,spec.variant)
		var unmerged:Dictionary=geometry(raw,label+" raw")
		bounds(unmerged.points,spec,label+" raw")
		check(unmerged.triangles==baked.triangles,label+" batching preserves all triangles")
		var raw_box:=AABB(unmerged.points[0],Vector3.ZERO);var baked_box:=AABB(baked.points[0],Vector3.ZERO)
		for v in unmerged.points:raw_box=raw_box.expand(v)
		for v in baked.points:baked_box=baked_box.expand(v)
		check(raw_box.position.is_equal_approx(baked_box.position) and raw_box.end.is_equal_approx(baked_box.end),label+" batching keeps bounds stable")
		if spec.kind in ["camouflage_net","supply_tent","antenna"]:
			var contacts:=0
			for child in raw.get_children():
				var box:AABB=child.transform*child.mesh.get_aabb()
				if absf(box.position.y)<0.001:contacts+=1
			check(contacts>=4,label+" multiple grounded feet or stakes")
		var cached:int=art.materials.size()+art.models.palette.size()
		var repeat:Node3D=Library.build(art,stage,spec.kind,spec.variant)
		check(art.materials.size()+art.models.palette.size()==cached,label+" palette reused")
		var repeated:Dictionary=geometry(repeat,label+" repeat")
		check(repeated.points==baked.points,label+" deterministic repeat")
		check(repeat.get_child(0).material_override==model.get_child(0).material_override,label+" material identity reused")
		# Rebatching must not destroy vertex paint/finish or alter the triangle count.
		var original_colors:PackedColorArray=model.get_child(0).mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		art.bake_model(model)
		var rebaked:Dictionary=geometry(model,label+" rebaked")
		check(rebaked.triangles==baked.triangles,label+" rebatch topology")
		check(model.get_child(0).mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]==original_colors,label+" rebatch paint preserved")
		repeat.free();raw.free();model.free()
	check(variants.size()==9,"nine families")
	for kind in variants:
		check(variants[kind].size()==2,kind+" two variants")
		check(variants[kind][0]!=variants[kind][1],kind+" geometry differs")
		check(Library.build(art,stage,kind,"invalid")==null,kind+" invalid variant rejected")
	check(Library.build(art,stage,"invalid","invalid")==null,"invalid kind rejected")
	check(stage.get_child_count()==0,"invalid inputs create no nodes")
	# Fresh metadata copies: callers cannot mutate subsequent catalogue reads.
	specs[0].label="changed"
	check(Library.specs()[0].label!="changed","metadata is isolated")
	neutral_palette_checks(stage)
	tent_checks(stage)
	decal_checks(stage)
	wreck_checks(stage)
	stage.free()
	print("BATTLEFIELD ASSETS: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)

# --- Visual regressions: neutral palette, continuous cloth, organic decals, burnt hulks ---

# Mirrors visuals.gd bake_model vertex paint encoding (linear blend, finish in alpha).
func baked_paint(color:Color,finish:float)->Color:
	var paint:=color.srgb_to_linear().lerp(color,0.25)
	paint.a=finish
	return paint

func same_paint(a:Color,b:Color)->bool:
	return absf(a.r-b.r)<0.006 and absf(a.g-b.g)<0.006 and absf(a.b-b.b)<0.006 and absf(a.a-b.a)<0.006

func luminance(c:Color)->float:
	return 0.2126*c.r+0.7152*c.g+0.0722*c.b

func painted(model:Node3D)->Array:
	# [point, paint] for every baked vertex; tolerates unindexed raw meshes.
	var result:Array=[]
	for child in model.get_children():
		var arrays:Array=child.mesh.surface_get_arrays(0)
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var colors:PackedColorArray=arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR]!=null else PackedColorArray()
		for i in vertices.size():result.append([child.transform*vertices[i],colors[i] if i<colors.size() else Color(0,0,0,0)])
	return result

func triangles_with_paint(model:Node3D,paint:Color)->Array:
	var result:Array=[]
	for child in model.get_children():
		var arrays:Array=child.mesh.surface_get_arrays(0)
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var colors:PackedColorArray=arrays[Mesh.ARRAY_COLOR]
		var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		var count:int=indices.size() if not indices.is_empty() else vertices.size()
		for t in range(0,count,3):
			var ids:Array=[indices[t],indices[t+1],indices[t+2]] if not indices.is_empty() else [t,t+1,t+2]
			if not same_paint(colors[ids[0]],paint):continue
			result.append([child.transform*vertices[ids[0]],child.transform*vertices[ids[1]],child.transform*vertices[ids[2]]])
	return result

func bin_triangles(tris:Array)->Dictionary:
	var grid:Dictionary={}
	for index in tris.size():
		var t:Array=tris[index]
		var lo:=Vector2(minf(t[0].x,minf(t[1].x,t[2].x)),minf(t[0].z,minf(t[1].z,t[2].z)))
		var hi:=Vector2(maxf(t[0].x,maxf(t[1].x,t[2].x)),maxf(t[0].z,maxf(t[1].z,t[2].z)))
		for gx in range(floori(lo.x/0.25),floori(hi.x/0.25)+1):
			for gz in range(floori(lo.y/0.25),floori(hi.y/0.25)+1):
				var key:=Vector2i(gx,gz)
				if not grid.has(key):grid[key]=[]
				grid[key].append(index)
	return grid

# Highest surface of the given triangles under a vertical ray at (x,z); -INF if none.
func top_hit(tris:Array,grid:Dictionary,x:float,z:float)->float:
	var best:=-INF
	for index in grid.get(Vector2i(floori(x/0.25),floori(z/0.25)),[]):
		var t:Array=tris[index]
		var a:Vector3=t[0];var b:Vector3=t[1];var c:Vector3=t[2]
		var denominator:=(b.z-c.z)*(a.x-c.x)+(c.x-b.x)*(a.z-c.z)
		if absf(denominator)<1e-9:continue
		var u:=((b.z-c.z)*(x-c.x)+(c.x-b.x)*(z-c.z))/denominator
		var v:=((c.z-a.z)*(x-c.x)+(a.x-c.x)*(z-c.z))/denominator
		var w:=1.0-u-v
		if u<-1e-6 or v<-1e-6 or w<-1e-6:continue
		best=maxf(best,u*a.y+v*b.y+w*c.y)
	return best

func neutral_palette_checks(stage:Node3D)->void:
	var fresh=Visuals.new()
	var tinted=Visuals.new()
	var unit:=Node3D.new();stage.add_child(unit)
	tinted.models.build(unit,"tank",1)
	unit.free()
	check(tinted.models.marking!=Palette.MARKING and tinted.models.canvas!=Palette.CANVAS and tinted.models.olive!=Palette.OLIVE,"precondition: team-1 build mutates shared unit palette")
	var reused=Visuals.new()
	for spec in Library.specs():
		var label:String=spec.kind+"/"+spec.variant
		var reference:Node3D=Library.build(fresh,stage,spec.kind,spec.variant)
		var after_team:Node3D=Library.build(tinted,stage,spec.kind,spec.variant)
		var expected:PackedColorArray=reference.get_child(0).mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		check(after_team.get_child(0).mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]==expected,label+" neutral vertex paint after team-1 unit")
		# Cache order: environment first, then a team-1 unit on the same art, then rebuild.
		var first:Node3D=Library.build(reused,stage,spec.kind,spec.variant)
		var unit_again:=Node3D.new();stage.add_child(unit_again)
		reused.models.build(unit_again,"rifle",1)
		var second:Node3D=Library.build(reused,stage,spec.kind,spec.variant)
		check(second.get_child(0).mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]==expected,label+" neutral paint unaffected by interleaved unit build")
		for node in [reference,after_team,first,second,unit_again]:node.free()
	var boom:Node3D=Library.build(fresh,stage,"checkpoint_gate","boom")
	var red:=0;var red_front:=0;var red_back:=0;var white:=0
	for entry in painted(boom):
		if same_paint(entry[1],baked_paint(Palette.SAFETY_RED,0.0)):
			red+=1
			if entry[0].z>0.09:red_back+=1
			if entry[0].z<-0.09:red_front+=1
		if same_paint(entry[1],baked_paint(Palette.SAFETY_WHITE,0.0)):white+=1
	check(red>0 and white>0,"boom uses muted red/white safety bands")
	check(red_front>0 and red_back>0,"boom safety bands wrap both faces")
	boom.free()

func tent_checks(stage:Node3D)->void:
	var art=Visuals.new()
	var canvas:=baked_paint(Palette.CANVAS,0.12)
	for variant in ["ridge","lean_to"]:
		var label:String="supply_tent/"+variant
		var model:Node3D=Library.build(art,stage,"supply_tent",variant)
		var tris:=triangles_with_paint(model,canvas)
		check(tris.size()>0,label+" canvas paint identifiable")
		var grid:=bin_triangles(tris)
		var slits:=0;var reversals:=0
		# 0.04 z steps cross every rafter line and the former inset bay seams.
		for zi in 119:
			var z:=-2.36+zi*0.04
			var heights:Array=[]
			for xi in 41:
				var y:=top_hit(tris,grid,-2.0+xi*0.1,z)
				if y<1.7:slits+=1
				heights.append(y)
			for xi in range(1,41):
				var x:=-2.0+xi*0.1
				var falling:bool=heights[xi]<heights[xi-1]-0.001
				var rising:bool=heights[xi]>heights[xi-1]+0.001
				if variant=="lean_to" and not falling:reversals+=1
				if variant=="ridge" and ((x<=0.0 and not rising) or (x>0.05 and not falling)):reversals+=1
		check(slits==0,label+" continuous canvas roof without slits")
		check(reversals==0,label+(" single monotonic pitch" if variant=="lean_to" else " symmetric ridge pitch"))
		if variant=="lean_to":
			var centre:=-2.4+0.48
			check(top_hit(tris,grid,-2.0,centre)-top_hit(tris,grid,2.0,centre)>0.4,label+" clear rise across the canopy")
		model.free()

func turns(radii:Array)->int:
	var count:=0
	for i in radii.size():
		var d0:float=radii[i]-radii[i-1]
		var d1:float=radii[(i+1)%radii.size()]-radii[i]
		if signf(d0)!=signf(d1):count+=1
	return count

# Max normalized radius in 24 angular bins around an origin, optionally rescaled per axis.
func outline(points:Array,origin:Vector3,scale:Vector2)->Array:
	var radii:Array=[]
	radii.resize(24);radii.fill(0.0)
	for point in points:
		var d:=Vector2((point.x-origin.x)/scale.x,(point.z-origin.z)/scale.y)
		if d.length()<0.05:continue
		var bin:=posmod(roundi(atan2(d.y,d.x)/(TAU/24.0)),24)
		radii[bin]=maxf(radii[bin],d.length())
	return radii

func decal_checks(stage:Node3D)->void:
	var art=Visuals.new()
	var ash:=baked_paint(Color("3a403d"),0.0)
	for variant in ["radial","streak"]:
		var label:String="scorch_mark/"+variant
		var model:Node3D=Library.build(art,stage,"scorch_mark",variant)
		var entries:=painted(model)
		var core:=Vector3.ZERO;var core_count:=0;var paints:Array=[]
		for entry in entries:
			if same_paint(entry[1],ash):core+=entry[0];core_count+=1
			var known:=false
			for p in paints:if same_paint(p,entry[1]):known=true
			if not known:paints.append(entry[1])
		check(core_count>0,label+" dark core present")
		core/=maxi(1,core_count)
		check(paints.size()>=3,label+" graded opaque edge uses several values")
		var far:Array=entries[0]
		for entry in entries:
			if Vector2(entry[0].x-core.x,entry[0].z-core.z).length()>Vector2(far[0].x-core.x,far[0].z-core.z).length():far=entry
		check(luminance(far[1])>luminance(ash)+0.01,label+" edge lighter than core")
		var points:Array=entries.map(func(e):return e[0])
		var radii:=outline(points,core,Vector2.ONE)
		check(turns(radii)<=10,label+" low-frequency outline (no star or cog)")
		check(radii.max()/maxf(0.001,radii.min())>1.08,label+" irregular, not circular")
		if variant=="streak":
			var head:=0.0;var tail:=0.0;var head_width:=0.0;var tail_width:=0.0
			for p in points:
				head=maxf(head,core.z-p.z);tail=maxf(tail,p.z-core.z)
			for p in points:
				if absf(p.z-core.z)<0.3:head_width=maxf(head_width,absf(p.x-core.x))
				if p.z-core.z>0.75*tail:tail_width=maxf(tail_width,absf(p.x-core.x))
			check(tail>1.8*head,label+" asymmetric drag from origin")
			check(tail_width<0.5*head_width,label+" tapering tail")
		model.free()
	for variant in ["shallow","elongated"]:
		var label:String="crater/"+variant
		var spec:Dictionary={}
		for entry in Library.specs():if entry.kind=="crater" and entry.variant==variant:spec=entry
		var model:Node3D=Library.build(art,stage,"crater",variant)
		var rim:Array=[]
		for entry in painted(model):
			if entry[0].y<0.001:rim.append(entry[0])
		var radii:=outline(rim,Vector3.ZERO,Vector2(spec.footprint[2]/2.0,spec.footprint[3]/2.0))
		check(turns(radii)<=10,label+" low-frequency rim (no cog)")
		check(radii.max()/maxf(0.001,radii.min())>1.08,label+" irregular rim")
		model.free()

func wreck_checks(stage:Node3D)->void:
	var art=Visuals.new()
	for variant in ["utility_hulk","tracked_hulk"]:
		var model:Node3D=Library.build(art,stage,"wreck",variant)
		var rubber:=0
		for entry in painted(model):
			if same_paint(entry[1],baked_paint(Palette.RUBBER,0.6)):rubber+=1
		check(rubber==0,"wreck/"+variant+" burnt out: no intact rubber tyres or tracks")
		model.free()
