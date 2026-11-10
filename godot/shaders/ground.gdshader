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
uniform sampler2D roofmask : filter_linear_mipmap, repeat_disable;     // where the real buildings stand (8 m pixels)
uniform float roof_fade = 7000.0;   // the 3D buildings are drawn this far: beyond it the photo's roofs stay
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

float h21g(vec2 q) { return fract(sin(dot(q, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 q) {
	vec2 i = floor(q); vec2 f = fract(q); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21g(i), h21g(i + vec2(1.0, 0.0)), f.x), mix(h21g(i + vec2(0.0, 1.0)), h21g(i + vec2(1.0, 1.0)), f.x), f.y);
}

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

// smooth (cubic) sampling of the photo up close, so its 8 m squares don't show as blocks: 4 filtered taps
vec4 cubic_w(float v) {
	vec4 n = vec4(1.0, 2.0, 3.0, 4.0) - v;
	vec4 s = n * n * n;
	float x = s.x; float y = s.y - 4.0 * s.x; float z = s.z - 4.0 * s.y + 6.0 * s.x;
	return vec4(x, y, z, 6.0 - x - y - z) * (1.0 / 6.0);
}
vec3 bicubic(sampler2D t, vec2 uv, float size) {
	uv = uv * size - 0.5;
	vec2 fxy = fract(uv);
	uv -= fxy;
	vec4 xc = cubic_w(fxy.x); vec4 yc = cubic_w(fxy.y);
	vec4 c = uv.xxyy + vec2(-0.5, 1.5).xyxy;
	vec4 s = vec4(xc.xz + xc.yw, yc.xz + yc.yw);
	vec4 off = (c + vec4(xc.yw, yc.yw) / s) / size;
	vec3 s0 = textureLod(t, off.xz, 0.0).rgb; vec3 s1 = textureLod(t, off.yz, 0.0).rgb;
	vec3 s2 = textureLod(t, off.xw, 0.0).rgb; vec3 s3 = textureLod(t, off.yw, 0.0).rgb;
	float sx = s.x / (s.x + s.y); float sy = s.z / (s.z + s.w);
	return mix(mix(s3, s2, sx), mix(s1, s0, sx), sy);
}

// how much a colour looks like bare soil or ripe crop (yellow-brown rather than green)
float wsoil_hint(vec3 c) { return clamp((c.r - c.g) * 6.0 + 0.5, 0.0, 1.0); }

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
	if (dist < 1800.0 && inside > 0.99) {
		photo = mix(bicubic(ortho, ouv, 4096.0), photo, smoothstep(1200.0, 1800.0, dist));
	}
	// close up: sharpen the 10 m photo a little (hedges, tracks and field edges read crisper)
	float near = 1.0 - smoothstep(600.0, 2600.0, dist);
	vec3 soft = textureLod(ortho, ouv, 2.0).rgb;
	photo = max(photo + (photo - soft) * 0.45 * near, vec3(0.0));
	// the 3D buildings stand here: paint over the photo's blurry roofs with garden and street colours
	float rm = texture(roofmask, ouv).r * inside * (1.0 - smoothstep(roof_fade * 0.8, roof_fade, dist));
	if (rm > 0.01) {
		vec3 around = textureLod(ortho, ouv, 4.0).rgb;
		vec3 yard = mix(around * vec3(0.78, 0.9, 0.72), vec3(0.11, 0.15, 0.08), 0.45);
		yard *= 0.85 + 0.3 * vnoise(p / 6.0);
		photo = mix(photo, yard, clamp(rm * 1.15, 0.0, 1.0));
	}
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
	float built = clamp(lc.g, 0.0, 1.0) * (1.0 - runway) * (1.0 - 0.6 * rm);
	float wgrass = (1.0 - built) * (1.0 - runway) * max(green, lc.a);
	float wsoil = (1.0 - built) * (1.0 - runway) * (1.0 - max(green, lc.a));

	float fade = 1.0 - smoothstep(250.0, 2200.0, dist);
	// patches inside the fields (soil, crop and grass vary over tens of metres, not in 10 m squares)
	float mfade = 1.0 - smoothstep(1500.0, 6000.0, dist);
	if (mfade > 0.001) {
		float m = vnoise(p / 23.0) * 0.6 + vnoise(p / 71.0 + 5.0) * 0.4;
		col *= mix(1.0, 0.9 + 0.2 * m, mfade * (1.0 - runway) * (1.0 - built));
		// detail between the photo's 10 m and the textures' few metres: tufts, patches and worn ground,
		// drawn here (not from a texture) so it stays sharp when seen at a low angle from the air
		float dfade = (1.0 - smoothstep(200.0, 1600.0, dist)) * (1.0 - runway) * (1.0 - built);
		if (dfade > 0.001) {
			vec2 w = p + vec2(vnoise(p / 13.0), vnoise(p / 13.0 + 9.0)) * 6.0;
			float d = vnoise(w / 3.3) * 0.55 + vnoise(w / 8.5 + 3.0) * 0.45;
			col *= mix(1.0, 0.82 + 0.36 * d, dfade * 0.8);
			col = mix(col, col * vec3(1.06, 1.0, 0.86), smoothstep(0.62, 0.8, d) * dfade * 0.6 * wsoil_hint(col));
		}
	}
	// arable fields: the pairs of tractor tracks ("tramlines", 24 m apart) that show from the air
	float arable = clamp(1.0 - (lc.r + lc.g + lc.b + lc.a) * 1.5, 0.0, 1.0) * (1.0 - runway) * (1.0 - rm);
	if (arable > 0.01 && dist < 4000.0) {
		float ang = vnoise(p / 1100.0 + 2.0) * 6.2832;
		float u = dot(p, vec2(cos(ang), sin(ang)));
		float m = mod(u, 24.0);
		float d = min(min(m, 24.0 - m), abs(m - 1.9));
		float fw = fwidth(u);
		float line = (1.0 - smoothstep(0.18, 0.5 + fw, d)) * (1.0 - smoothstep(0.6, 2.5, fw));
		col *= 1.0 - 0.16 * line * arable * (1.0 - smoothstep(2500.0, 4000.0, dist));
	}
	if (fade > 0.001) {
		// a coarse layer of the ground textures too, breaking up the smooth patches between photo pixels
		col *= mix(vec3(1.0), grain(grass_col, p, 19.0) * wgrass + grain(soil_col, p, 23.0) * wsoil + vec3(built + runway), 0.35 * fade);
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
