// Additive muzzle flashes, sparks, tracers and motor flares for BattleEffects.
// INSTANCE_CUSTOM: x=kind (0 star flash, 1 axial streak, 2 soft ember), y=petal phase, z=age 0..1, w=seed.
// BattleEffects writes camera-facing cards and view-widened streak ribbons (basis X along the streak, tail to
// head) on the CPU, so the standard vertex transform is used in every renderer.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add;

// Global additive strength; lower it if flashes bloom too hard under the active tonemapper.
uniform float brightness = 1.0;

varying vec4 data;

void vertex() {
	data = INSTANCE_CUSTOM;
}

void fragment() {
	float kind = data.x;
	float age = data.z;
	vec2 local = vec2(UV.x - 0.5, 0.5 - UV.y) * 2.0;
	float intensity = 0.0;
	vec3 color = COLOR.rgb;
	if (kind < 0.5) {
		float r = length(local);
		float angle = atan(local.y, local.x);
		// Five uneven tongues; integer lobe count keeps the pattern seamless around the circle.
		float petals = 0.5 + 0.5 * pow(0.5 + 0.5 * cos(angle * 5.0 + data.y * 6.2831853), 3.0);
		float star = 1.0 - smoothstep(0.0, petals, r);
		float core = exp(-r * r * 9.0);
		intensity = star * 0.75 + core;
		color = mix(color, vec3(1.0, 0.97, 0.86), core * 0.7);
		intensity *= 1.0 - age * age;
	} else if (kind < 1.5) {
		// UV.x runs tail(0) to head(1).
		float head = smoothstep(0.0, 1.0, UV.x);
		float across = 1.0 - abs(local.y);
		intensity = head * head * across * across;
		color = mix(color, vec3(1.0, 0.95, 0.82), smoothstep(0.75, 1.0, UV.x) * across);
		intensity *= 1.0 - smoothstep(0.6, 1.0, age);
	} else {
		float r = length(local);
		intensity = exp(-r * r * 5.0) * (1.0 - smoothstep(0.55, 1.0, age));
		color = mix(color, vec3(1.0, 0.9, 0.62), exp(-r * r * 16.0));
	}
	ALBEDO = color;
	ALPHA = clamp(intensity * COLOR.a * brightness, 0.0, 1.0);
}
