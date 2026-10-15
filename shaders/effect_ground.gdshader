// Flat ground marks for BattleEffects: scorch, blast dust rings and water foam rings.
// INSTANCE_CUSTOM: x=kind (0 scorch, 1 dust ring, 2 foam ring), y=rotation turns, z=age 0..1, w=seed.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying vec4 data;

void vertex() {
	data = INSTANCE_CUSTOM;
}

void fragment() {
	float kind = data.x;
	float age = data.z;
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r = length(p);
	vec2 offset = vec2(data.w * 5.7, data.w * 2.3);
	float coarse = texture(noise_tex, UV * 0.6 + offset).r;
	float fine = texture(noise_tex, UV * 1.8 + offset.yx).r;
	float alpha = 0.0;
	if (kind < 0.5) {
		// Irregular blackened soil with a sooty rim; fades over its long life.
		float blot = (1.0 - r) + (coarse - 0.5) * 0.7;
		alpha = smoothstep(0.08, 0.45, blot) * (0.75 + 0.25 * fine);
		alpha *= smoothstep(0.0, 0.02, age) * (1.0 - smoothstep(0.55, 1.0, age));
	} else {
		// Expanding ring of kicked-up dust or broken foam.
		float rim = 1.0 - smoothstep(0.0, 0.22, abs(r - 0.72));
		float inner = (1.0 - smoothstep(0.0, 0.72, r)) * 0.35;
		float broken = smoothstep(0.32, 0.62, kind < 1.5 ? coarse : fine);
		alpha = (rim + inner) * broken * (1.0 - smoothstep(0.2, 1.0, age));
	}
	ALBEDO = COLOR.rgb * (0.9 + 0.2 * fine);
	ALPHA = clamp(alpha * COLOR.a, 0.0, 1.0);
}
