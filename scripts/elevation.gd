extends RefCounted

# Authored height in world units. Rectangles are level plateaus; their external
# ramps use smoothstep so both the summit and foot meet without a hard step.
# The highest patch wins where ramps overlap. Values are gameplay abstractions.
const LIMITS := {"infantry":0.9,"tracked":0.42,"wheeled":0.30,"default":0.9}
const FOOTPRINT_SAMPLES := [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]
var patches:Array[Dictionary]=[]
var maximum:=0.0

func _init(records:Array=[]) -> void:
	for record in records:
		if not record is Dictionary:continue
		var value=record.get("rect",[])
		if not value is Array or value.size()!=4:continue
		var rect:=Rect2(float(value[0]),float(value[1]),float(value[2]),float(value[3]))
		var height:float=float(record.get("height",0.0))
		var ramp:float=float(record.get("ramp",24.0))
		if not rect.position.is_finite() or not rect.size.is_finite() or rect.size.x<=0 or rect.size.y<=0:continue
		if not is_finite(height) or not is_finite(ramp) or height<=0 or ramp<4.0:continue
		patches.append({"rect":rect,"height":minf(height,40.0),"ramp":ramp,"bounds":rect.grow(ramp)})
		maximum=maxf(maximum,minf(height,40.0))

func height_at(p:Vector2) -> float:
	var highest:=0.0
	for patch in patches:
		if not patch.bounds.has_point(p):continue
		var rect:Rect2=patch.rect
		var distance:=p.distance_to(p.clamp(rect.position,rect.end))
		var t:=clampf(1.0-distance/float(patch.ramp),0.0,1.0)
		highest=maxf(highest,float(patch.height)*t*t*(3.0-2.0*t))
	return highest

func gradient_at(p:Vector2) -> Vector2:
	var highest:=0.0
	var gradient:=Vector2.ZERO
	for patch in patches:
		if not patch.bounds.has_point(p):continue
		var rect:Rect2=patch.rect
		var delta:=p-p.clamp(rect.position,rect.end)
		var distance:=delta.length()
		var ramp:float=patch.ramp
		var t:=clampf(1.0-distance/ramp,0.0,1.0)
		var height:float=float(patch.height)*t*t*(3.0-2.0*t)
		if height<=highest:continue
		highest=height
		gradient=Vector2.ZERO if distance<0.00001 else -delta/distance*(float(patch.height)*6.0*t*(1.0-t)/ramp)
	return gradient

func slope_at(p:Vector2) -> float:
	return gradient_at(p).length()

func traversable(p:Vector2,radius:float,profile:String) -> bool:
	if patches.is_empty():return true
	var limit:float=LIMITS.get(profile,LIMITS.default)
	if slope_at(p)>limit:return false
	# A hull cannot balance its centre on a crest with its sides over a cliff.
	for offset in FOOTPRINT_SAMPLES:
		if slope_at(p+offset*radius)>limit:return false
	return true

func speed_at(p:Vector2,profile:String) -> float:
	if patches.is_empty():return 1.0
	var grade:=slope_at(p)
	var penalty:float={"infantry":1.3,"tracked":2.4,"wheeled":3.2}.get(profile,1.3)
	return maxf(0.18,1.0/(1.0+grade*penalty))

# Absolute heights at the two endpoints, so air and ground use the same ridge
# occlusion. Keep the 0.8 m line sampling used by other terrain sight checks.
func line_clear(a:Vector2,b:Vector2,source_height:float,target_height:float) -> bool:
	if patches.is_empty():return true
	if minf(source_height,target_height)>maximum+0.05:return true
	var bounds:=Rect2(a,Vector2.ZERO).expand(b)
	var relevant:=false
	for patch in patches:
		if patch.bounds.intersects(bounds,true):relevant=true;break
	if not relevant:return true
	var steps:=maxi(1,ceili(a.distance_to(b)/0.8))
	for i in range(1,steps):
		var t:=float(i)/steps
		if height_at(a.lerp(b,t))>lerpf(source_height,target_height,t)+0.05:return false
	return true

func normal_at(p:Vector2) -> Vector3:
	var slope:=gradient_at(p)
	return Vector3(-slope.x,1.0,-slope.y).normalized()

# Interpolate the same two triangles used by the visible heightfield. Thin
# ground overlays must use this surface, otherwise the smooth physical curve
# can dip below its straight render triangles by more than a road's thickness.
func mesh_height_at(p:Vector2,cell_size:Vector2) -> float:
	var cell:Vector2=(p/cell_size).floor()
	var part:Vector2=p/cell_size-cell
	var origin:=cell*cell_size
	var a:=height_at(origin)
	var d:=height_at(origin+cell_size)
	if part.y>part.x:
		var c:=height_at(origin+Vector2(0,cell_size.y))
		return a+(d-c)*part.x+(c-a)*part.y
	var b:=height_at(origin+Vector2(cell_size.x,0))
	return a+(b-a)*part.x+(d-b)*part.y

# Orthographic view corners may have a negative ray parameter at wide zoom;
# retain their useful ground projection while picking the first raised surface.
func ground_intersection(origin:Vector3,direction:Vector3,far_limit:float=4000.0) -> Vector3:
	if absf(direction.y)<0.0001:return origin+direction*far_limit
	var end:=minf(-origin.y/direction.y,far_limit)
	if patches.is_empty():return origin+direction*end
	var start:=minf((maximum-origin.y)/direction.y,far_limit)
	if start>end:
		var swap:=start;start=end;end=swap
	var count:=maxi(1,ceili((end-start)*Vector2(direction.x,direction.z).length()))
	var before:=start
	for i in range(1,count+1):
		var after:=lerpf(start,end,float(i)/count)
		var point:=origin+direction*after
		if point.y<=height_at(Vector2(point.x,point.z)):
			for iteration in 18:
				var middle:=(before+after)*0.5
				var sample:=origin+direction*middle
				if sample.y>height_at(Vector2(sample.x,sample.z)):before=middle
				else:after=middle
			return origin+direction*((before+after)*0.5)
		before=after
	return origin+direction*end
