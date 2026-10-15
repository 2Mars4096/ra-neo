shader_type spatial;
render_mode cull_disabled;
uniform vec4 base_color : source_color = vec4(0.5);
uniform int surface_kind = 0;
uniform sampler2D construction_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D material_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
varying vec3 p;
varying vec3 n;
float hash(vec2 q){return fract(sin(dot(q,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 q){vec2 i=floor(q);vec2 f=fract(q);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void vertex(){p=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;n=normalize(mat3(MODEL_MATRIX)*NORMAL);}
void fragment(){
 vec2 uv=abs(n.z)>abs(n.x)?p.xy:p.zy;
 if(abs(n.y)>0.65)uv=p.xz;
 vec2 tile=1.0-abs(mod(uv*0.20,2.0)-1.0);
 vec3 plaster=texture(material_atlas,vec2(0.001)+tile*0.498).rgb;
 float age=noise(uv*0.72);
 float fine=noise(uv*12.0);
 vec3 color=base_color.rgb*(0.78+age*0.30);
 float relief=0.0;
 if(surface_kind==0){
  // Missing plaster reveals bonded masonry, with broad irregular edges.
  float wear=noise(uv*1.3)*0.65+noise(uv*3.7)*0.35;
  float exposed=smoothstep(0.67,0.76,wear+(1.0-smoothstep(0.0,1.1,p.y))*0.13);
  vec2 brick=uv*vec2(2.8,5.5);brick.x+=mod(floor(brick.y),2.0)*0.5;
  vec2 f=fract(brick);vec2 aa=max(fwidth(brick),vec2(0.01));
  float mortar=max(1.0-smoothstep(0.045,0.045+aa.x,f.x),1.0-smoothstep(0.09,0.09+aa.y,f.y));
  vec3 masonry=mix(vec3(0.34,0.27,0.21),vec3(0.45,0.35,0.26),hash(floor(brick)));
  masonry=texture(construction_atlas,vec2(0.501,0.501)+(1.0-abs(mod(uv*0.5,2.0)-1.0))*0.498).rgb;
  color=mix(color,masonry,exposed);
  float streak=noise(vec2(uv.x*5.0,uv.y*0.32));
  color*=0.84+streak*0.19;
  color*=1.0-(1.0-smoothstep(0.0,1.0,p.y))*0.25;
  color*=clamp(plaster/vec3(0.685,0.632,0.566),vec3(0.55),vec3(1.4));
  relief=(fine-0.5)*0.012-exposed*mortar*0.018;
 }else if(surface_kind==1){
  vec2 roof_uv=1.0-abs(mod(uv*0.34,2.0)-1.0);
  vec3 clay=texture(construction_atlas,vec2(0.001)+roof_uv*0.498).rgb;
  float slate=step(base_color.r,base_color.b);
  color=mix(clay,vec3(dot(clay,vec3(0.3,0.59,0.11)))*vec3(0.78,0.88,0.92),slate*0.65)*1.12;
  relief=0.0;
 }else{
  float seam=1.0-smoothstep(0.025,0.025+fwidth(uv.x)*2.0,abs(fract(uv.x*1.8)-0.5));
  vec3 sheet=texture(construction_atlas,vec2(0.501,0.001)+tile*0.498).rgb;
  color=mix(color,sheet*0.7,0.65);
  color=mix(color,vec3(0.29,0.16,0.08),smoothstep(0.58,0.85,age)*0.48);
  relief=sin(uv.x*30.0)*0.006;
 }
 // Screen-space surface gradient adds restrained relief without extra meshes.
 vec3 dx=dFdx(VERTEX),dy=dFdy(VERTEX);
 vec3 rx=cross(dy,NORMAL),ry=cross(NORMAL,dx);
 float det=dot(dx,rx);
 vec3 gradient=sign(det)*(dFdx(relief)*rx+dFdy(relief)*ry);
 NORMAL=normalize(abs(det)*NORMAL-gradient);
 ALBEDO=color*0.72;
 ROUGHNESS=surface_kind==2?0.78:0.94;
 SPECULAR=0.18;
}
