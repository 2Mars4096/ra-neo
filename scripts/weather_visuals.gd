extends MultiMeshInstance3D

const COUNT:=256
var paint:=ShaderMaterial.new()
var world_size:=Vector2(96,72)

func _ready() -> void:
	var shader:=Shader.new()
	shader.code="""shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform float clock=0.0;
uniform float rain=0.0;
varying float phase;
void vertex(){
 float height=mod(INSTANCE_CUSTOM.x-clock*18.0,14.0);
 VERTEX.y+=height;
 VERTEX.x+=height*0.12;
 VERTEX.z+=height*0.04;
 phase=INSTANCE_CUSTOM.y;
}
void fragment(){ALBEDO=vec3(0.66,0.79,0.84);ALPHA=0.35*rain*step(phase,rain);}
"""
	paint.shader=shader
	material_override=paint
	cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	multimesh=MultiMesh.new()
	multimesh.transform_format=MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data=true
	var streak:=BoxMesh.new()
	streak.size=Vector3(0.025,0.7,0.025)
	multimesh.mesh=streak
	multimesh.instance_count=COUNT
	world_size=get_parent().sim.terrain.world_size if get_parent().get("sim")!=null else world_size
	custom_aabb=AABB(Vector3(-2,0,-2),Vector3(world_size.x+4,16,world_size.y+4))
	var rng:=RandomNumberGenerator.new()
	rng.seed=193
	for i in COUNT:
		multimesh.set_instance_transform(i,Transform3D(Basis.IDENTITY,Vector3(rng.randf_range(1,world_size.x-1),0,rng.randf_range(1,world_size.y-1))))
		multimesh.set_instance_custom_data(i,Color(rng.randf()*14,rng.randf(),0,1))

func sync(state:Dictionary,seconds:float) -> void:
	visible=state.rain>0.01
	paint.set_shader_parameter("clock",seconds)
	paint.set_shader_parameter("rain",state.rain)
