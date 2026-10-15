shader_type spatial;
render_mode cull_disabled;
uniform vec4 paint : source_color = vec4(1.0);
uniform bool vertex_paint = false;
uniform float finish=0.0;
uniform sampler2D construction_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D material_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
varying vec3 surface_normal;
varying vec3 surface_pos;
void vertex(){surface_pos=VERTEX;surface_normal=NORMAL;}
void fragment(){
 vec3 base=vertex_paint?COLOR.rgb:paint.rgb;
 float coating=vertex_paint?COLOR.a:finish;
 vec3 an=abs(surface_normal);
 vec2 uv=an.y>max(an.x,an.z)?surface_pos.xz:(an.x>an.z?surface_pos.zy:surface_pos.xy);
 vec2 tile=1.0-abs(mod(uv*0.34,2.0)-1.0);
 vec3 color=base;
 if(coating<0.5){
  vec3 sample_paint=texture(material_atlas,vec2(0.501,0.001)+tile*0.498).rgb;
  float variation=clamp(dot(sample_paint,vec3(0.2126,0.7152,0.0722))/0.35,0.55,1.45);
  color*=mix(1.0,variation,0.85);
  if(coating>0.08 && coating<0.2){
   vec3 fabric=texture(construction_atlas,vec2(0.001,0.501)+(1.0-abs(mod(uv*3.4,2.0)-1.0))*0.498).rgb;
   color=base*clamp(dot(fabric,vec3(0.333))/0.30,0.9,1.1);
  }
  float dust=(1.0-smoothstep(0.08,0.75,surface_pos.y))*0.22;
  if(coating>0.035 && coating<0.06){
   float waterline=1.0-smoothstep(0.09,0.30,surface_pos.y);
   float salt=exp(-abs(surface_pos.y-0.34)*12.0)*0.10;
   color=mix(color,vec3(0.035,0.06,0.045),waterline*0.40);
   color=mix(color,vec3(0.28,0.29,0.26),salt);
  }else{
   color=mix(color,vec3(0.12,0.10,0.07),dust);
   if(coating>0.015 && coating<0.035){
    vec2 engine=surface_pos.xz-vec2(0.0,1.2);
    float soot=exp(-dot(engine,engine)*12.0)*smoothstep(0.65,0.95,surface_pos.y);
    color*=1.0-soot*0.65;
   }
  }
 }
 ALBEDO=color;
 ROUGHNESS=coating>0.8?0.25:(coating>0.5?0.96:(coating>0.2?0.58:0.86));
 SPECULAR=coating>0.8?0.6:0.22;
}
