extends RefCounted

# Shared with tools/build_harbor_map.py. source_size remains the placement and
# decoration envelope; these profiles describe the ground body inside it.
# Insets are left/front/right/rear in the building's local x/z frame.
# Custom, compound and open structures deliberately retain parcel collision
# until they have an explicit ground-body profile.
static var _data:Dictionary={}

static func data()->Dictionary:
	if _data.is_empty():
		_data=JSON.parse_string(FileAccess.get_file_as_string("res://resources/city_building_geometry.json"))
	return _data

static func profile(design:String)->Dictionary:
	var source:=data()
	return source.profiles.get(source.families.get(design,""),{})

static func shell_rect(design:String,size:Vector2)->Rect2:
	var row:=profile(design)
	assert(not row.is_empty(),"No ground-body profile for "+design)
	var inset:Array=row.insets
	return Rect2(-size.x/2+float(inset[0]),-size.y/2+float(inset[1]),
		size.x-float(inset[0])-float(inset[2]),size.y-float(inset[1])-float(inset[3]))

static func porch_rect(design:String,size:Vector2)->Rect2:
	var row:Dictionary=profile(design).porch
	var shell:=shell_rect(design,size)
	var width:=minf(float(row.width),size.x-float(row.width_margin))
	return Rect2(-width/2,shell.position.y-float(row.front_offset)-float(row.depth)/2,width,float(row.depth))

static func dock_rects(design:String,size:Vector2)->Array[Rect2]:
	var row:Dictionary=profile(design).dock
	var shell:=shell_rect(design,size)
	var width:=size.x-float(row.width_margin)
	return [Rect2(-width/2,shell.position.y-float(row.front_offset)-float(row.depth)/2,width,float(row.depth)),
		Rect2(-width/2,shell.end.y+float(row.front_offset)-float(row.depth)/2,width,float(row.depth))]

static func ground_pieces(spec:Dictionary)->Array[Dictionary]:
	var row:=profile(str(spec.design))
	if row.is_empty():return []
	var size:=Vector2(float(spec.source_size[0]),float(spec.source_size[1]))
	var result:Array[Dictionary]=[{"rect":shell_rect(str(spec.design),size).grow(float(row.wall_outset)),"wall":true}]
	# Low porch steps contain their posts; roof canopies and decorative skirts
	# do not become ground blockers. Steps/docks block movement, not shots or
	# full-wall cover. Authored ruined houses omit the porch.
	if row.has("porch") and int(spec.get("damage",0))<2:result.append({"rect":porch_rect(str(spec.design),size),"wall":false})
	if row.has("dock"):
		for dock in dock_rects(str(spec.design),size):result.append({"rect":dock,"wall":false})
	return result

static func ground_rects(spec:Dictionary)->Array[Rect2]:
	var result:Array[Rect2]=[]
	for piece in ground_pieces(spec):result.append(piece.rect)
	return result
