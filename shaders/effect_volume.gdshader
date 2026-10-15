// Camera-facing smoke, dust, debris, water spray and fireballs for BattleEffects.
// INSTANCE_CUSTOM: x=kind (0 smoke/dust, 1 debris, 2 spray, 3 fireball), y=rotation turns, z=age 0..1, w=seed.
// BattleEffects writes each card's camera-facing, rotated world basis on the CPU, so the standard vertex
// transform is used and the shader behaves identically in the Compatibility and Forward+ renderers.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
// World direction toward the battle sun (rotation -48,-32,0) for painted cotton-ball shading.
uniform vec3 sun_dir = vec3(-0.355, 0.743, 0.567);

varying vec4 data;

void vertex() {
	data = INSTANCE_CUSTOM;
}

void fragment() {
	float kind = data.x;
	float age = data.z;
	vec2 offset = vec2(data.w * 7.31, data.w * 3.17);
	// Card-local disc coordinates (-1..1, y up), independent of the card's spin.
	vec2 sphere = vec2(UV.x - 0.5, 0.5 - UV.y) * 2.0;
	float r = length(sphere);
	float coarse = texture(noise_tex, UV * 0.45 + offset).r;
	float fine = texture(noise_tex, UV * 1.35 + offset.yx).r;
	float noise = coarse * 0.68 + fine * 0.32;
	// Undo the card spin so shading stays lit from the sun side.
	float turn = data.y * 6.2831853;
	vec2 view_xy = vec2(sphere.x * cos(turn) - sphere.y * sin(turn), sphere.x * sin(turn) + sphere.y * cos(turn));
	vec3 view_normal = vec3(view_xy, sqrt(max(0.0, 1.0 - r * r)));
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(view_normal, 0.0)).xyz);
	float light = clamp(dot(world_normal, normalize(sun_dir)) * 0.5 + 0.5, 0.0, 1.0);
	vec3 color = COLOR.rgb;
	float alpha = 0.0;
	if (kind < 0.5) {
		// Billowing smoke and dust: radial density eroded by noise as the puff thins.
		float density = (1.0 - r) + (noise - 0.5) * 0.95;
		float erosion = mix(0.04, 0.42, age * age);
		alpha = smoothstep(erosion, erosion + 0.32, density);
		alpha *= smoothstep(0.0, 0.06, age) * (1.0 - smoothstep(0.5, 1.0, age));
		color *= mix(0.6, 1.14, light) * (0.9 + 0.2 * fine);
	} else if (kind < 1.5) {
		// Hard-edged clods, shards and fragments.
		float edge = (1.0 - r) - (coarse - 0.5) * 0.75;
		alpha = smoothstep(0.3, 0.36, edge) * (1.0 - smoothstep(0.85, 1.0, age));
		color *= mix(0.55, 1.2, light);
	} else if (kind < 2.5) {
		// Broken water spray: granular, bright crowns and quick dissolve.
		float density = (1.0 - r) + (fine - 0.5) * 1.3;
		float erosion = mix(0.12, 0.6, age);
		alpha = smoothstep(erosion, erosion + 0.18, density) * (1.0 - smoothstep(0.65, 1.0, age));
		color *= mix(0.72, 1.12, light);
	} else {
		// Fireball: white-hot core to orange, then dark red into soot.
		float density = (1.0 - r) + (noise - 0.5) * 0.8;
		float erosion = mix(0.02, 0.5, age);
		alpha = smoothstep(erosion, erosion + 0.22, density) * (1.0 - smoothstep(0.7, 1.0, age));
		vec3 hot = mix(vec3(1.0, 0.94, 0.7), vec3(1.0, 0.56, 0.16), smoothstep(0.0, 0.35, age));
		vec3 cool = mix(vec3(0.62, 0.2, 0.06), vec3(0.13, 0.11, 0.1), smoothstep(0.5, 0.95, age));
		vec3 fire = mix(hot, cool, smoothstep(0.25, 0.7, age));
		float core = smoothstep(0.7, 0.0, r) * (1.0 - age);
		color = fire * color * (0.82 + 0.3 * core + 0.12 * coarse);
	}
	// Card corners are always fully transparent, whatever the noise.
	alpha *= 1.0 - smoothstep(0.92, 1.0, r);
	ALBEDO = color;
	ALPHA = clamp(alpha * COLOR.a, 0.0, 1.0);
}
