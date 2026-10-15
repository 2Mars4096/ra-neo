class_name RoadNetwork
extends RefCounted

# Authored destination graph: transport intent is defined before parcels/detail.
# Shared by drawing, movement surfaces, and validation. Not a traffic simulation.
var nodes:Dictionary={}
var segments:Array[Dictionary]=[]
var use_spatial_index:=true
var _buckets:Dictionary={}
var _indexed_count:=-1
const BUCKET_SIZE:=32.0
func _init(config:Dictionary={})->void:
	for name in config.get("nodes",{}):
		var xy:Array=config.nodes[name]
		nodes[name]=Vector2(xy[0],xy[1])
	for edge in config.get("edges",[]):
		segments.append({"from":edge[0],"to":edge[1],"a":nodes[edge[0]],"b":nodes[edge[1]],"width":float(edge[2]),"purpose":edge[3]})
	rebuild_index()

# Call after in-place same-length edits; append/remove detected automatically.
func rebuild_index()->void:
	_buckets.clear()
	for index in segments.size():
		var s:Dictionary=segments[index]
		var bounds:=Rect2(s.a,s.b-s.a).abs().grow(float(s.width)*0.5)
		for x in range(floori(bounds.position.x/BUCKET_SIZE),floori(bounds.end.x/BUCKET_SIZE)+1):
			for y in range(floori(bounds.position.y/BUCKET_SIZE),floori(bounds.end.y/BUCKET_SIZE)+1):
				var key:=Vector2i(x,y)
				if not _buckets.has(key):_buckets[key]=[]
				_buckets[key].append(index)
	_indexed_count=segments.size()

func contains(p:Vector2)->bool:
	if use_spatial_index:
		if _indexed_count!=segments.size():rebuild_index()
		for index in _buckets.get(Vector2i((p/BUCKET_SIZE).floor()),[]):
			var s:Dictionary=segments[index]
			if Geometry2D.get_closest_point_to_segment(p,s.a,s.b).distance_to(p)<=s.width*0.5:return true
		return false
	for s in segments:
		if Geometry2D.get_closest_point_to_segment(p,s.a,s.b).distance_to(p)<=s.width*0.5:return true
	return false
