shader_type spatial;
render_mode cull_disabled;
// Racing circuit surfaces, all painted in the shader (no image files):
// kind 0 = grass and farmland around the circuit (world position), 1 = verges beside the track (kerbs, gravel,
// mown grass), 2 = the track (asphalt, white lines, start line and grid boxes), 3 = barriers (advertising
// boards in SmartMotion colours, tyre walls in the corners).
// UV.x = metres from the centre line (verges: always positive), UV.y = distance along the track (m).
// COLOR.r = how much of a corner this is (0..1), COLOR.g = 1 on the outside of the corner.

uniform int kind = 0;
uniform float half_width = 7.0;
uniform float track_len = 4000.0;
uniform vec3 centre = vec3(60.0, 0.0, 380.0);
uniform int grid_slots = 8;
uniform sampler2D ad_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform bool has_ad = false;

varying vec3 wp;
varying vec4 vc;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * vn(p); p = p * 2.07 + 13.1; a *= 0.5; }
	return v;
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vc = COLOR;
}

vec3 grass(vec2 p, float stripe) {
	float n = fbm(p * 0.08) * 0.6 + fbm(p * 0.9) * 0.4;
	vec3 g = mix(vec3(0.16, 0.30, 0.07), vec3(0.27, 0.42, 0.11), n);
	g *= 0.92 + stripe * 0.14;
	g *= 0.9 + vn(p * 7.0) * 0.18;
	return g;
}

vec3 fields(vec2 p, out float rough) {
	// patchwork farmland and hedges beyond the circuit, like the countryside around Duxford
	mat2 r = mat2(vec2(0.94, 0.34), vec2(-0.34, 0.94));
	vec2 q = r * p / 210.0 + vec2(fbm(p * 0.004), fbm(p * 0.004 + 7.0)) * 0.5;
	vec2 c = floor(q);
	vec2 f = fract(q);
	float id = h21(c);
	vec3 col = vec3(0.2, 0.33, 0.1);
	if (id < 0.25) col = vec3(0.55, 0.47, 0.22);          // ripe wheat
	else if (id < 0.4) col = vec3(0.36, 0.40, 0.14);      // young crop
	else if (id < 0.5) col = vec3(0.40, 0.30, 0.18);      // ploughed
	else if (id < 0.8) col = vec3(0.19, 0.33, 0.09);      // pasture
	float rows = 0.5 + 0.5 * sin((id > 0.5 ? q.x : q.y) * 140.0);
	col *= 0.93 + rows * 0.08;
	col *= 0.85 + fbm(p * 0.05) * 0.3;
	float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	float hedge = 1.0 - smoothstep(0.006, 0.02, edge);
	col = mix(col, vec3(0.07, 0.15, 0.04), hedge);
	rough = 0.95;
	return col;
}

void fragment() {
	vec3 col;
	float rough = 0.92;
	float spec = 0.3;
	float lat = UV.x;
	float s = UV.y;
	float corner = vc.r;
	float outside = vc.g;
	if (kind == 0) {
		float d = length(wp.xz - centre.xz);
		float stripe = step(0.5, fract(wp.x / 18.0));
		vec3 g = grass(wp.xz, stripe);
		float fr;
		vec3 f = fields(wp.xz, fr);
		col = mix(g, f, smoothstep(1250.0, 1700.0, d));
	} else if (kind == 1) {
		float stripe = step(0.5, fract((lat - half_width) / 5.0));
		col = grass(wp.xz, stripe);
		float kerb_w = 1.35;
		float x = lat - half_width;
		// gravel traps on the outside of the corners
		float gw = outside * smoothstep(0.3, 0.6, corner) * (6.0 + 9.0 * corner);
		if (x > kerb_w + 0.6 && x < kerb_w + 0.6 + gw) {
			float gn = vn(wp.xz * 9.0) * 0.5 + vn(wp.xz * 31.0) * 0.5;
			col = mix(vec3(0.62, 0.55, 0.42), vec3(0.78, 0.71, 0.56), gn);
			rough = 1.0;
		} else if (x < kerb_w + 0.6 && x > 0.0) {
			// a strip of asphalt between kerb and grass
			col = vec3(0.13, 0.13, 0.14) * (0.85 + vn(wp.xz * 20.0) * 0.3);
		}
		if (corner > 0.45 && x < kerb_w) {
			float k = step(0.5, fract(s / 6.0));
			col = mix(vec3(0.75, 0.07, 0.05), vec3(0.92, 0.92, 0.9), k);
			col *= 0.88 + 0.12 * smoothstep(0.0, 0.3, x);
			rough = 0.55;
			spec = 0.5;
		}
	} else if (kind == 2) {
		float a = abs(lat);
		float grain = vn(wp.xz * 14.0) * 0.5 + vn(wp.xz * 53.0) * 0.5;
		col = vec3(0.105, 0.105, 0.115) * (0.82 + grain * 0.36);
		// darker rubber on the racing line, worn patches
		col *= 1.0 - 0.18 * exp(-pow(lat * 0.5 + sin(s * 0.004) * 1.5, 2.0)) - 0.06 * fbm(wp.xz * 0.05);
		// white edge lines
		float line = smoothstep(half_width - 0.42, half_width - 0.38, a) * (1.0 - smoothstep(half_width - 0.18, half_width - 0.14, a));
		col = mix(col, vec3(0.86), line);
		// start / finish line: a chequered band
		float sl = s < 1.6 ? 1.0 : 0.0;
		if (sl > 0.5) {
			float ch = mod(floor(lat / 0.8) + floor(s / 0.8), 2.0);
			col = mix(vec3(0.05), vec3(0.9), ch);
		}
		// grid boxes behind the line
		float back = track_len - s;
		for (int k = 0; k < grid_slots; k++) {
			float gs = 12.0 + float(k) * 8.0;
			float side = (k % 2 == 0) ? -3.0 : 3.0;
			float lx = abs(lat - side);
			float bx = back - gs + 1.6;
			if (bx > 0.0 && bx < 0.25 && lx < 1.3) col = vec3(0.86);
			if (bx > 0.0 && bx < 1.6 && lx > 1.15 && lx < 1.3) col = vec3(0.86);
		}
		// a SMARTMOTION orange stripe across the track every lap (sector lines)
		float sec = min(abs(s - track_len / 3.0), abs(s - track_len * 2.0 / 3.0));
		if (sec < 0.15) col = mix(col, vec3(1.0, 0.3, 0.0), 0.8);
		rough = 0.78 - grain * 0.12;
		spec = 0.45;
	} else {
		// barriers. UV.x = height up the wall (0..1.1 m), front faces the track
		float h = lat;
		float panel = floor(s / 16.0);
		bool tyres = corner > 0.4;
		if (tyres) {
			float row = floor(h / 0.27);
			float u = fract(s / 0.62);
			float ring = length(vec2(u - 0.5, fract(h / 0.27) - 0.5));
			col = vec3(0.04) * (0.8 + 0.4 * smoothstep(0.2, 0.45, ring));
			if (mod(row, 2.0) < 1.0 && fract(h / 0.27) > 0.35 && fract(h / 0.27) < 0.65) {
				col = mod(panel, 2.0) < 1.0 ? vec3(0.8, 0.05, 0.03) : vec3(0.9);
			}
			rough = 0.9;
		} else {
			if (has_ad) {
				float row = mod(panel, 2.0);
				float vv = clamp((h - 0.06) / 0.98, 0.0, 1.0);
				col = texture(ad_tex, vec2(fract(s / 16.0), (row + 1.0 - vv) * 0.5)).rgb;
				if (h > 1.04) col = vec3(0.75);
				if (h < 0.06) col = vec3(0.2);
				rough = 0.55;
				spec = 0.4;
			} else {
			float which = mod(panel, 3.0);
			vec3 navy = vec3(0.008, 0.008, 0.16);
			vec3 org = vec3(1.0, 0.3, 0.0);
			col = which < 1.0 ? navy : (which < 2.0 ? org : vec3(0.92));
			// the band of text-like blocks (reads as advertising from a distance)
			float u = fract(s / 16.0);
			float blocks = step(0.5, fract(u * 11.0)) * step(0.15, u) * step(u, 0.85);
			float band = step(0.38, h) * step(h, 0.72);
			vec3 ink = which < 1.0 ? vec3(1.0) : (which < 2.0 ? vec3(1.0) : navy);
			col = mix(col, ink, band * blocks * 0.9);
			if (h > 0.95) col = vec3(0.75);
			if (h < 0.08) col = vec3(0.2);
			rough = 0.6;
			}
		}
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = spec;
}
