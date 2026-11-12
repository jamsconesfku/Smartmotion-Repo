shader_type spatial;
render_mode cull_disabled, world_vertex_coords, diffuse_lambert_wrap, specular_schlick_ggx;
// 3D grass (v1.14.0) round the camera when you are on or near the ground: a grid of small clumps of blades
// (one MultiMesh, every clump placed here from its number, so the CPU does nothing per frame). Each clump
// sits on the real ground, takes its colour from the satellite photo under it, and only grows where the
// ground is grass: not on the runway, tarmac, roads, water, fields of bare soil, or under the 3D buildings.
// The grid moves with the camera in whole steps, and each blade's place comes from its world position, so
// the grass doesn't swim. Blades shrink away at the edge of the circle, so there is no hard line.
uniform sampler2D heightmap : filter_linear, repeat_enable;
uniform sampler2D ortho : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D landcover : filter_linear_mipmap, repeat_disable;
uniform sampler2D roofmask : filter_linear_mipmap, repeat_disable;
uniform float cell = 32.0;
uniform float size_cells = 1024.0;
uniform float half_size = 16384.0;
uniform vec4 rw = vec4(0.848, -0.530, 1448.0, 46.0);
uniform float spacing = 0.5;
uniform int grid = 144;
uniform float radius = 36.0;
uniform float blade_h = 0.32;
uniform float wind = 1.0;
uniform float exposure = 1.12;

#include "res://shaders/detail.gdshaderinc"

varying vec3 v_col;
varying float v_t;

float hgt(vec2 xz) {
	vec2 uv = (xz / cell + size_cells * 0.5 + 0.5) / size_cells;
	float h = textureLod(heightmap, uv, 0.0).r;
	float w = d_weight(xz);
	return w > 0.0 ? mix(h, d_height(xz), w) : h;
}
float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	vec3 centre = MODEL_MATRIX[3].xyz;
	vec3 lv = VERTEX - centre;   // the clump mesh, before placing
	int id = INSTANCE_ID;
	vec2 g = vec2(float(id % grid), float(id / grid)) - float(grid) * 0.5;
	vec2 ci = floor(centre.xz / spacing + 0.5) + g;
	vec2 base = (ci + vec2(h21(ci), h21(ci + 7.31)) - 0.5) * spacing;
	float r = length(base - CAMERA_POSITION_WORLD.xz);
	vec2 ouv = base / (2.0 * half_size) + 0.5;
	vec3 photo = textureLod(ortho, ouv, 0.0).rgb;
	vec4 lc = textureLod(landcover, ouv, 0.0);
	float green = clamp((photo.g - max(photo.r, photo.b)) * 9.0 + 0.3, 0.0, 1.0);
	float built = clamp(lc.g, 0.0, 1.0) * (1.0 - 0.85 * green);
	vec2 rd = rw.xy; vec2 rp = vec2(-rd.y, rd.x);
	float ru = dot(base, rd); float rv = dot(base, rp);
	float runway = (1.0 - step(rw.z * 0.5 + 3.0, abs(ru))) * (1.0 - step(rw.w * 0.5 + 2.5, abs(rv)));
	float rm = textureLod(roofmask, ouv, 0.0).r;
	float dw = d_weight(base);
	if (dw > 0.0) {
		// in the detail square: no grass on the roads, in water, under buildings or under the trees
		vec4 dm = textureLod(detail_mask, d_uv(base), 0.0);
		rm = max(rm, dm.a * dw);
		lc.b = max(lc.b, dm.b * dw);
		built = max(built, dm.g * dw);
		photo = mix(photo, textureLod(detail_photo, d_uv(base), 0.0).rgb, dw);
	}
	float grow = max(green, lc.a) * (1.0 - built) * (1.0 - runway) * clamp(1.0 - rm * 2.5, 0.0, 1.0) * clamp(1.0 - lc.b * 2.0, 0.0, 1.0);
	grow = smoothstep(0.35, 0.8, grow) * (1.0 - smoothstep(radius * 0.55, radius, r));
	float s = grow * (0.55 + 0.75 * h21(ci + 3.17));
	if (s < 0.04) s = 0.0;
	float a = h21(ci + 1.73) * 6.2831;
	float ca = cos(a); float sa = sin(a);
	vec3 v = vec3(lv.x * ca - lv.z * sa, lv.y, lv.x * sa + lv.z * ca);
	v_t = clamp(lv.y, 0.0, 1.0);
	v.y *= blade_h * s;
	v.xz *= 0.35 + 0.65 * s;
	// wind: gusts roll across the field, the tips move most
	float gust = sin(TIME * 1.7 + base.x * 0.21 + base.y * 0.13) * 0.6 + sin(TIME * 3.1 + base.x * 0.7) * 0.25;
	v.x += gust * 0.07 * wind * v_t * v_t * s;
	v.z += gust * 0.04 * wind * v_t * v_t * s;
	VERTEX = vec3(base.x, hgt(base), base.y) + v;
	NORMAL = normalize(vec3(0.0, 1.0, 0.0) + vec3(ca, 0.0, sa) * 0.25);
	float l = dot(photo, vec3(0.3, 0.59, 0.11));
	vec3 pc = mix(vec3(l), photo, 0.92) * exposure;
	pc.g *= 1.03;
	v_col = pc * (0.82 + 0.36 * h21(ci + 9.1));
}

void fragment() {
	// darker at the root (shaded by the other blades), lighter and a little yellower at the tip
	vec3 c = v_col * mix(0.55, 1.12, v_t);
	c = mix(c, c * vec3(1.08, 1.04, 0.8), v_t * v_t * 0.5);
	ALBEDO = c;
	ROUGHNESS = 0.78;
	SPECULAR = 0.35;
	BACKLIGHT = vec3(0.25, 0.32, 0.08) * v_t;
	AO = mix(0.45, 1.0, v_t);
	AO_LIGHT_AFFECT = 0.3;
}
