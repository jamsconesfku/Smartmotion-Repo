shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// Real buildings. COLOR.rgb = tint, COLOR.a = material: 0 brick wall, 0.25 rendered wall, 0.5 tiled roof,
// 0.75 metal-clad wall, 1 metal / flat roof. UV: walls = (metres along the wall, metres above the ground);
// roofs = world x, z (so the roof colour can be taken from the satellite photo). Textures: ambientCG (CC0).
uniform sampler2D ortho : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D brick_col : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D brick_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D plaster_col : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D plaster_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roof_col : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roof_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D metal_col : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D metal_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_col : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float half_size = 16384.0;

varying vec3 v_world;
varying vec3 v_nrm;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_nrm = NORMAL;
	// tangents for the normal maps: walls run along u and up; roofs use world x/z
	if (abs(NORMAL.y) < 0.5) {
		TANGENT = normalize(vec3(-NORMAL.z, 0.0, NORMAL.x));
		BINORMAL = vec3(0.0, -1.0, 0.0);
	} else {
		TANGENT = vec3(1.0, 0.0, 0.0);
		BINORMAL = vec3(0.0, 0.0, 1.0);
	}
}

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	float id = COLOR.a;
	vec3 tint = COLOR.rgb;
	float dist = length(v_world - CAMERA_POSITION_WORLD);
	float detail = 1.0 - smoothstep(400.0, 2500.0, dist);
	vec3 col;
	vec3 nm = vec3(0.5, 0.5, 1.0);
	float rough = 0.85;
	float metal = 0.0;
	bool wall = abs(v_nrm.y) < 0.5;
	if (wall) {
		vec2 uv = UV;
		if (id < 0.12) {
			col = texture(brick_col, uv / 2.4).rgb * tint;
			nm = texture(brick_nrm, uv / 2.4).rgb;
		} else if (id < 0.5) {
			col = texture(plaster_col, uv / 3.0).rgb * tint;
			nm = texture(plaster_nrm, uv / 3.0).rgb;
		} else {
			// profiled metal cladding (barns, hangars, sheds)
			col = texture(metal_col, uv / 4.0).rgb * tint * 1.4;
			nm = texture(metal_nrm, uv / 4.0).rgb;
			float rib = 0.5 + 0.5 * sin(uv.x * 6.2831 / 0.33);
			nm.x += (rib - 0.5) * 0.5;
			rough = 0.55;
			metal = 0.3;
		}
		// windows on houses and offices: a row per floor, 3.2 m apart along the wall
		if (id < 0.5) {
			vec2 cell = vec2(uv.x / 3.2, (uv.y - 0.9) / 2.8);
			vec2 f = fract(cell);
			float floor_ok = step(0.0, cell.y) * step(uv.y + 1.4, 99.0);
			float win = step(0.28, f.x) * step(f.x, 0.72) * step(0.22, f.y) * step(f.y, 0.7) * floor_ok;
			// gaps where the wall is too short for another floor, and a few blank bays
			win *= step(0.18, h21(floor(cell) + 3.0));
			if (win > 0.5) {
				float lit = h21(floor(cell) * 1.7);
				col = mix(vec3(0.05, 0.07, 0.09), vec3(0.18, 0.22, 0.27), lit * 0.5);
				rough = 0.08;
				nm = vec3(0.5, 0.5, 1.0);
			} else {
				float frame = step(0.24, f.x) * step(f.x, 0.76) * step(0.18, f.y) * step(f.y, 0.74) * floor_ok * step(0.18, h21(floor(cell) + 3.0));
				col = mix(col, vec3(0.92), frame * 0.85);
			}
		}
		// ground grime at the foot of the wall
		col *= mix(0.72, 1.0, smoothstep(-0.6, 1.2, uv.y));
	} else {
		// roofs: take the colour the satellite sees, mixed with the roof material so it isn't blurry
		vec2 ouv = v_world.xz / (2.0 * half_size) + 0.5;
		vec3 sat = texture(ortho, ouv).rgb;
		vec2 ruv = v_world.xz;
		if (id < 0.75) {
			col = texture(roof_col, ruv / 3.0).rgb;
			float l = dot(col, vec3(0.33));
			col = tint * (l / 0.42);
			nm = texture(roof_nrm, ruv / 3.0).rgb;
			rough = 0.8;
		} else {
			col = texture(concrete_col, ruv / 6.0).rgb * tint;
			nm = texture(concrete_nrm, ruv / 6.0).rgb;
			rough = 0.6;
		}
		col = mix(col, sat * 1.1, 0.35);
	}
	ALBEDO = col;
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), nm, detail);
	NORMAL_MAP_DEPTH = 1.0;
	ROUGHNESS = rough;
	METALLIC = metal;
}
