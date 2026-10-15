shader_type spatial;
uniform sampler2D material_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
varying vec2 ground;
void vertex(){ground=(MODEL_MATRIX*vec4(VERTEX,1.0)).xz;}
void fragment(){
 vec2 tile=1.0-abs(mod(ground*0.22,2.0)-1.0);
 vec3 asphalt=texture(material_atlas,vec2(0.001,0.501)+tile*0.498).rgb;
 ALBEDO=mix(vec3(0.14,0.145,0.14),asphalt*0.46,0.65);
 ROUGHNESS=0.92;
 SPECULAR=0.18;
}
