shader_type spatial;
render_mode cull_back, diffuse_burley, specular_disabled;
// The ground: a ring mesh that follows the aircraft; heights come from one texture, colour from the painted maps.
uniform sampler2D heightmap : filter_linear, repeat_enable;
uniform sampler2D near_map : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D far_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_tex : filter_linear_mipmap, repeat_enable;
uniform float cell = 64.0;
uniform float size_cells = 512.0;
uniform float near_size = 20480.0;
uniform float far_size = 163840.0;
uniform vec2 snap_origin = vec2(0.0);

varying vec3 v_world;

float hgt(vec2 xz) {
	vec2 uv = (xz / cell + size_cells * 0.5 + 0.5) / size_cells;
	return texture(heightmap, uv).r;
}

uniform float y_bias = 0.0;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = hgt(wp.xz);
	VERTEX.y = h + y_bias - MODEL_MATRIX[3].y;
	v_world = vec3(wp.x, h, wp.z);
	float e = 4.0;
	float hl = hgt(wp.xz - vec2(e, 0.0)); float hr = hgt(wp.xz + vec2(e, 0.0));
	float hu = hgt(wp.xz - vec2(0.0, e)); float hd = hgt(wp.xz + vec2(0.0, e));
	NORMAL = normalize(vec3(hl - hr, 2.0 * e, hu - hd));
}

void fragment() {
	vec2 nuv = v_world.xz / near_size + 0.5;
	vec2 fuv = v_world.xz / far_size + 0.5;
	vec4 nc = texture(near_map, nuv);
	vec4 fc = texture(far_map, fuv);
	float e = max(abs(nuv.x - 0.5), abs(nuv.y - 0.5)) * 2.0;
	float w = 1.0 - smoothstep(0.86, 0.98, e);
	vec3 col = mix(fc.rgb, nc.rgb, w);
	float dist = length(v_world - CAMERA_POSITION_WORLD);
	float fade = 1.0 - smoothstep(150.0, 1800.0, dist);
	float dn = texture(detail_tex, v_world.xz / 11.0).r;
	col *= 1.0 + (dn - 0.5) * 0.5 * fade;
	float a = nc.a * w;
	if (a > 0.01 && dist < 520.0) {
		float ang = a * 6.2831;
		float s = sin(dot(v_world.xz, vec2(cos(ang), sin(ang))) * 6.2831 / 3.2);
		col *= 1.0 + 0.08 * s * (1.0 - smoothstep(60.0, 520.0, dist));
	}
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
