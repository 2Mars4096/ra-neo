extends RefCounted

# Opaque pointed leaf clusters: same 128 triangles/layer as the previous 64 quads.
# Folded centers and tapered tips break up the square-card silhouette without alpha overdraw.
static func cluster(seed_value:int,small:bool=false)->ArrayMesh:
	var rng:=RandomNumberGenerator.new();rng.seed=seed_value
	var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var extent:=Vector3(0.49,0.55,0.49)*(0.8 if small else 1.0)
	for i in 32:
		var direction:=Vector3(rng.randf_range(-1,1),rng.randf_range(-1,1),rng.randf_range(-1,1)).normalized()
		var center:=direction*extent*pow(rng.randf(),0.3333)
		var normal:=Vector3(rng.randf_range(-0.7,0.7),rng.randf_range(0.3,1),rng.randf_range(-0.7,0.7)).normalized()
		var axis:=normal.cross(Vector3.FORWARD).normalized()*rng.randf_range(0.13,0.20)
		var side:=normal.cross(axis).normalized()*rng.randf_range(0.08,0.13)
		var corners:Array[Vector3]=[center-axis,center+side,center+axis,center-side]
		var ridge:=center+normal*0.035
		var color:=Color.WHITE.darkened(rng.randf_range(0.0,0.22))
		for j in 4:
			var a:Vector3=corners[j];var b:Vector3=corners[(j+1)%4]
			var face:Vector3=(a-ridge).cross(b-ridge).normalized()
			if face.dot(normal)<0:face=-face
			for point in [ridge,a,b]:
				surface.set_normal(face)
				surface.set_color(color.lightened(0.07) if point==ridge else color)
				surface.add_vertex(point)
	return surface.commit()
