extends Node3D

# Bounded presentation pools follow authoritative objects; particles never
# determine optical obstruction, collision, damage or expiry.
const SMOKE_LIMIT:=32
const PUFFS:=7
const PROJECTILE_LIMIT:=64
var clouds:MultiMeshInstance3D
var grenades:MultiMeshInstance3D
var known_smoke:Dictionary={}

func _ready()->void:
	var sphere:=SphereMesh.new()
	sphere.radius=1.0;sphere.height=2.0;sphere.radial_segments=12;sphere.rings=6
	var smoke_material:=StandardMaterial3D.new()
	smoke_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_material.albedo_color=Color(0.67,0.70,0.65,0.46)
	smoke_material.roughness=1.0
	smoke_material.vertex_color_use_as_albedo=true
	clouds=_pool(sphere,smoke_material,SMOKE_LIMIT*PUFFS)
	var payload:=SphereMesh.new()
	payload.radius=0.12;payload.height=0.24;payload.radial_segments=8;payload.rings=4
	var payload_material:=StandardMaterial3D.new()
	payload_material.albedo_color=Color("b6ba8d")
	payload_material.vertex_color_use_as_albedo=true
	grenades=_pool(payload,payload_material,PROJECTILE_LIMIT)

func _pool(mesh:Mesh,material:Material,capacity:int)->MultiMeshInstance3D:
	var instance:=MultiMeshInstance3D.new()
	instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var multimesh:=MultiMesh.new()
	multimesh.transform_format=MultiMesh.TRANSFORM_3D
	multimesh.use_colors=true
	multimesh.mesh=mesh
	multimesh.instance_count=capacity
	multimesh.visible_instance_count=0
	instance.multimesh=multimesh
	instance.material_override=material
	add_child(instance)
	return instance

func sync(sim)->void:
	if clouds==null:return
	var cloud_count:=0
	var active:Dictionary={}
	for smoke in sim.throwables.get("smoke",[]):
		active[smoke.id]=true
		var pos:Vector3=smoke.pos
		var flat:=Vector2(pos.x,pos.z)
		if int(smoke.team)==0 or sim.visible_cells.has(sim.terrain.cell(flat)) or smoke.get("visible",false):known_smoke[smoke.id]=true
		# An opaque cloud hides its own center. Discover its visible edge as a
		# section approaches, even if the distant deployment was never observed.
		if not known_smoke.has(smoke.id):
			for edge in 8:
				var point:Vector2=flat+Vector2.from_angle(edge*TAU/8)*(float(smoke.radius)+0.2)
				if sim.visible_cells.has(sim.terrain.cell(point)):known_smoke[smoke.id]=true;break
		if not known_smoke.has(smoke.id):continue
		# The footprint and top agree with the actual cylindrical optical volume.
		var radius:float=smoke.radius
		var height:float=smoke.height
		for puff in PUFFS:
			if cloud_count>=SMOKE_LIMIT*PUFFS:break
			var angle:float=(puff-1)*TAU/6+float(smoke.id)*0.3
			var offset:=Vector3.ZERO if puff==0 else Vector3(cos(angle),0,sin(angle))*radius*0.47
			var size:=Vector3(radius*0.56,height*0.5,radius*0.56)
			clouds.multimesh.set_instance_transform(cloud_count,Transform3D(Basis.IDENTITY.scaled(size),pos+offset+Vector3.UP*height*0.5))
			clouds.multimesh.set_instance_color(cloud_count,Color(0.94+0.05*sin(angle+sim.time*0.18),0.96,0.94,1))
			cloud_count+=1
	clouds.multimesh.visible_instance_count=cloud_count
	for id in known_smoke.keys():
		if not active.has(id):known_smoke.erase(id)
	var projectile_count:=0
	for projectile in sim.throwables.get("projectiles",[]):
		if projectile_count>=PROJECTILE_LIMIT:break
		var pos:Vector3=projectile.pos
		if not projectile.visible and not sim.visible_cells.has(sim.terrain.cell(Vector2(pos.x,pos.z))):continue
		grenades.multimesh.set_instance_transform(projectile_count,Transform3D(Basis.IDENTITY,pos))
		grenades.multimesh.set_instance_color(projectile_count,Color("d9d9d1") if projectile.payload=="smoke" else Color("8b9c52"))
		projectile_count+=1
	grenades.multimesh.visible_instance_count=projectile_count
