class_name MinimapBackground
extends RefCounted

var source_id:=-1
var revision:=0
var colors:=PackedColorArray()
var rebuilds:=0

func invalidate()->void:source_id=-1

func colors_for(terrain,road_cells:Dictionary)->PackedColorArray:
	# Static map data is small; hash the source definitions instead of repeating
	# thousands of cover/obstruction queries. New tactical geometry invalidates it.
	var key:int=hash([terrain.world_size,terrain.shore_x,terrain.style,terrain.blocks,terrain.roadside_blocks,terrain.woods,terrain.rubble,terrain.dynamic_blocks,terrain.get("field_cover"),terrain.roads.segments,road_cells])
	if source_id==terrain.get_instance_id() and revision==key:return colors
	source_id=terrain.get_instance_id();revision=key;rebuilds+=1
	colors.resize(terrain.fog_grid_size.x*terrain.fog_grid_size.y)
	for x in terrain.fog_grid_size.x:
		for y in terrain.fog_grid_size.y:
			var id:=Vector2i(x,y)
			var p:Vector2=terrain.center(id)
			var color:=Color("3c695b") if terrain.cover(p) else Color("72765b")
			if terrain.is_water(p):color=Color("285867")
			elif terrain.blocked(p):color=Color("ada991")
			elif road_cells.has(id):color=Color("bbb39a")
			colors[x+y*terrain.fog_grid_size.x]=color
	return colors
