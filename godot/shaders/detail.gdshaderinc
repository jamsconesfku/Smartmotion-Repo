// The high-detail square round the airfield (v1.15.0, scripts/build_uk_detail.py): ground heights every 2 m
// from the Environment Agency's LIDAR, a 1 m ground picture and a mask (trees, roads, water, buildings).
// Shared by ground.gdshader and grass.gdshader so the grass stands exactly on the ground.
uniform sampler2D detail_h : filter_nearest, repeat_disable;   // R high byte, G low byte: metres = v / 100 - 100
uniform sampler2D detail_photo : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D detail_mask : filter_linear_mipmap, repeat_disable;   // r trees, g road, b water, a building
uniform bool has_detail = false;
uniform float d_half = 4096.0;

float d_fetch(ivec2 c) {
	vec3 t = texelFetch(detail_h, clamp(c, ivec2(0), ivec2(4095)), 0).rgb;
	return (round(t.r * 255.0) * 256.0 + round(t.g * 255.0)) * 0.01 - 100.0;
}
float d_height(vec2 xz) {
	vec2 g = (xz + d_half) * 0.5;
	vec2 i = floor(g);
	vec2 f = g - i;
	ivec2 c = ivec2(i);
	float a = d_fetch(c); float b = d_fetch(c + ivec2(1, 0));
	float cc = d_fetch(c + ivec2(0, 1)); float d = d_fetch(c + ivec2(1, 1));
	return mix(mix(a, b, f.x), mix(cc, d, f.x), f.y);
}
// 1 inside the square, 0 outside, fading over the last 400 m (same as Terrain.detail_weight)
float d_weight(vec2 xz) {
	if (!has_detail) return 0.0;
	float e = max(abs(xz.x), abs(xz.y));
	return 1.0 - smoothstep(d_half - 400.0, d_half - 2.0, e);
}
vec2 d_uv(vec2 xz) { return (xz + d_half) / (2.0 * d_half); }
