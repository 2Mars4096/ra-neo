// Permanent ground-damage tiles for BattleEffects remains (scripts/effects_remains.gd).
// Marks are only a few texels across and always magnified, so plain bilinear filtering shows texel squares (a
// crater rim reads as a diamond ring on the isometric camera). Sampling is a cubic B-spline built from 4 bilinear
// taps (smooth_sample): C2-continuous, so magnified marks keep round, soft outlines at a constant 4 taps per pixel.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled, blend_mix;

uniform sampler2D remains : source_color, filter_linear, repeat_disable;

// Cubic B-spline reconstruction: each axis's 4 weights fold into 2 bilinear taps (weights g0/g1 at offsets h0/h1).
vec4 smooth_sample(sampler2D tex, vec2 uv) {
	vec2 size = vec2(textureSize(tex, 0));
	vec2 st = uv * size - 0.5;
	vec2 i = floor(st);
	vec2 f = st - i;
	vec2 f2 = f * f;
	vec2 f3 = f2 * f;
	vec2 w0 = (1.0 - 3.0 * f + 3.0 * f2 - f3) / 6.0;
	vec2 w1 = (4.0 - 6.0 * f2 + 3.0 * f3) / 6.0;
	vec2 w2 = (1.0 + 3.0 * f + 3.0 * f2 - 3.0 * f3) / 6.0;
	vec2 w3 = f3 / 6.0;
	vec2 g0 = w0 + w1;
	vec2 g1 = w2 + w3;
	vec2 h0 = (i - 0.5 + w1 / g0) / size;
	vec2 h1 = (i + 1.5 + w3 / g1) / size;
	return g0.y * (g0.x * texture(tex, h0) + g1.x * texture(tex, vec2(h1.x, h0.y)))
		+ g1.y * (g0.x * texture(tex, vec2(h0.x, h1.y)) + g1.x * texture(tex, h1));
}

void fragment() {
	// Relief tiles share land triangles; crop any cell crossing the tile edge.
	if (any(lessThan(UV, vec2(0.0))) || any(greaterThan(UV, vec2(1.0)))) discard;
	vec4 c = smooth_sample(remains, UV);
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
