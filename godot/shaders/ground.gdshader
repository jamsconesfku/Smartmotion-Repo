shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// The ground: a ring mesh that follows the camera; heights come from the real elevation data.
// Colour is a real satellite photo (Copernicus Sentinel-2) inside the 32.8 km square, and the painted
// countryside beyond it. Up close, free CC0 photo textures (ambientCG) add grain and bumps, chosen by land cover.
uniform sampler2D heightmap : filter_linear, repeat_enable;
uniform sampler2D ortho : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D landcover : filter_linear_mipmap, repeat_disable;   // r trees, g built-up, b water, a grassland
uniform sampler2D far_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_col : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_col : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_col : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_col : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cloud_map : filter_linear, repeat_enable;           // cloud cover, for cloud shadows
uniform float cell = 32.0;
uniform float size_cells = 1024.0;
uniform float half_size = 16384.0;
uniform float far_size = 163840.0;
uniform float y_bias = 0.0;
uniform vec4 rw = vec4(0.848, -0.530, 1448.0, 46.0);   // runway dir.x, dir.z, length, width
uniform float exposure = 1.12;
uniform float saturation = 0.92;
uniform float cloud_shadow = 0.0;
uniform vec2 cloud_offset = vec2(0.0);
uniform float cloud_scale = 1.0;
uniform float cloud_cover = 0.5;
uniform vec2 shadow_shift = vec2(0.0);   // where the cloud above a point is, along the sun direction

varying vec3 v_world;

float hgt(vec2 xz) {
	vec2 uv = (xz / cell + size_cells * 0.5 + 0.5) / size_cells;
	return texture(heightmap, uv).r;
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = hgt(wp.xz);
	VERTEX.y = h + y_bias - MODEL_MATRIX[3].y;
	v_world = vec3(wp.x, h, wp.z);
	float e = cell * 0.5;
	float hl = hgt(wp.xz - vec2(e, 0.0)); float hr = hgt(wp.xz + vec2(e, 0.0));
	float hu = hgt(wp.xz - vec2(0.0, e)); float hd = hgt(wp.xz + vec2(0.0, e));
	NORMAL = normalize(vec3(hl - hr, 2.0 * e, hu - hd));
	TANGENT = normalize(vec3(1.0, 0.0, 0.0) - NORMAL * NORMAL.x);
	BINORMAL = normalize(vec3(0.0, 0.0, 1.0) - NORMAL * NORMAL.z);
}

// sample a tiling texture twice at different scales and angles so the repeat can't be seen
vec3 tile2(sampler2D t, vec2 p, float s) {
	vec2 q = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p;
	return mix(texture(t, p / s).rgb, texture(t, q / (s * 2.7) + 0.37).rgb, 0.4);
}
// detail as a brightness multiplier around 1, so the satellite colour is kept and only the grain is added
vec3 grain(sampler2D t, vec2 p, float s) {
	vec3 c = tile2(t, p, s);
	vec3 avg = textureLod(t, vec2(0.5), 12.0).rgb + 0.02;
	vec3 g = c / avg;
	return mix(vec3(dot(g, vec3(0.333))), g, 0.35);   // keep the grain, drop the texture's own colour cast
}

void fragment() {
	vec2 p = v_world.xz;
	float dist = length(v_world - CAMERA_POSITION_WORLD);
	vec2 ouv = p / (2.0 * half_size) + 0.5;
	float edge = max(abs(p.x), abs(p.y));
	float inside = 1.0 - smoothstep(half_size - 1800.0, half_size - 150.0, edge);

	vec3 photo = texture(ortho, ouv).rgb;
	float l = dot(photo, vec3(0.3, 0.59, 0.11));
	photo = mix(vec3(l), photo, saturation) * exposure;
	photo.g *= 1.03;
	vec3 farc = texture(far_map, p / far_size + 0.5).rgb;
	vec3 col = mix(farc, photo, inside);
	vec4 lc = texture(landcover, ouv) * inside;

	// runway: real tarmac colour, cleaner than the 10 m photo
	vec2 rd = rw.xy; vec2 rp = vec2(-rd.y, rd.x);
	float ru = dot(p, rd); float rv = dot(p, rp);
	float runway = (1.0 - smoothstep(rw.z * 0.5 - 2.0, rw.z * 0.5 + 2.0, abs(ru))) * (1.0 - smoothstep(rw.w * 0.5 - 0.5, rw.w * 0.5 + 1.5, abs(rv)));
	col = mix(col, vec3(0.20, 0.205, 0.21), runway * 0.85);

	// what kind of surface: green plants, bare/ripe fields, built-up, tarmac
	float green = clamp((col.g - max(col.r, col.b)) * 9.0 + 0.3, 0.0, 1.0);
	float built = clamp(lc.g, 0.0, 1.0) * (1.0 - runway);
	float wgrass = (1.0 - built) * (1.0 - runway) * max(green, lc.a);
	float wsoil = (1.0 - built) * (1.0 - runway) * (1.0 - max(green, lc.a));

	float fade = 1.0 - smoothstep(250.0, 2200.0, dist);
	if (fade > 0.001) {
		vec3 g = grain(grass_col, p, 3.0) * wgrass + grain(soil_col, p, 4.0) * wsoil
			+ grain(concrete_col, p, 5.0) * built + grain(asphalt_col, p, 5.0) * runway;
		col *= mix(vec3(1.0), g, 0.75 * fade);
		vec3 n = tile2(grass_nrm, p, 3.0) * wgrass + tile2(soil_nrm, p, 4.0) * wsoil
			+ tile2(concrete_nrm, p, 5.0) * built + tile2(asphalt_nrm, p, 5.0) * runway;
		NORMAL_MAP = n;
		NORMAL_MAP_DEPTH = 1.2 * fade;
	}
	// woods read darker from above; the 3D trees stand on top of them nearby
	col *= 1.0 - 0.12 * lc.r;

	// water: dark, glassy, rippling
	float water = smoothstep(0.35, 0.7, lc.b);
	if (water > 0.0) {
		col = mix(col, vec3(0.05, 0.09, 0.08), water * 0.8);
		vec2 wv = vec2(sin(p.x * 0.7 + TIME * 1.3) + sin(p.y * 0.9 - TIME * 1.1), cos(p.x * 0.5 - TIME * 0.9) + cos(p.y * 0.6 + TIME * 1.4));
		NORMAL_MAP = mix(NORMAL_MAP, normalize(vec3(wv * 0.04, 1.0)) * 0.5 + 0.5, water);
	}
	// shadows of the clouds drifting over the ground
	if (cloud_shadow > 0.0) {
		float c = texture(cloud_map, (p + shadow_shift + cloud_offset) / (cloud_scale * 24000.0)).r;
		float sh = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.18, c);
		col *= 1.0 - cloud_shadow * sh;
	}
	ALBEDO = col;
	ROUGHNESS = mix(mix(0.92, 0.75, runway + built * 0.5), 0.05, water);
	SPECULAR = mix(0.3, 0.6, water);
}
