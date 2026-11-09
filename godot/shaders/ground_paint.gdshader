shader_type canvas_item;
render_mode blend_disabled;
// Paints the countryside once into a texture (fields, hedges, woods, villages, river, roads, the airfield).
// Port of the GLSL bake shader in dashboard/fly/world.js. RGB = colour, A = "crop row" amount for the ground shader.
uniform vec2 u_center = vec2(0.0);
uniform float u_size = 1.0;
uniform float u_road_mul = 1.0;
uniform float u_detail = 1.0;
uniform vec4 u_road[28];
uniform float u_road_w[28];
uniform vec4 u_river[12];
uniform vec3 u_vill[10];
uniform vec3 u_wood[18];
uniform vec4 u_rw = vec4(0.0); // runway dir.x, dir.y, length, width

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
vec2 h22(vec2 p) { return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453); }
float vn(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y); }
float segd(vec2 p, vec4 s) { vec2 pa = p - s.xy; vec2 ba = s.zw - s.xy; float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.001), 0.0, 1.0); return length(pa - ba * h); }
float boxm(vec2 p, vec2 c, vec2 hs, float soft) { vec2 d = abs(p - c) - hs; return 1.0 - smoothstep(0.0, soft, max(d.x, d.y)); }

void fragment() {
	vec2 p = u_center + (UV - 0.5) * u_size;
	vec2 q = p / 380.0;
	vec2 ci = floor(q);
	vec2 cf = fract(q);
	float d1 = 9.0; float d2 = 9.0; vec2 id = vec2(0.0);
	for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) {
		vec2 g = vec2(float(i), float(j)); vec2 r = g + h22(ci + g) - cf; float d = dot(r, r);
		if (d < d1) { d2 = d1; d1 = d; id = ci + g; } else if (d < d2) { d2 = d; }
	}
	float edge = (sqrt(d2) - sqrt(d1)) * 380.0;
	float hc = h21(id * 1.37 + 3.1);
	vec3 col;
	if (hc < 0.28) col = vec3(0.36, 0.52, 0.22); else if (hc < 0.46) col = vec3(0.74, 0.66, 0.28); else if (hc < 0.58) col = vec3(0.62, 0.62, 0.30);
	else if (hc < 0.72) col = vec3(0.47, 0.37, 0.26); else if (hc < 0.86) col = vec3(0.22, 0.41, 0.18); else col = vec3(0.80, 0.74, 0.20);
	col *= (0.88 + 0.24 * h21(id + 7.7)) * (0.92 + 0.16 * vn(p * 0.004));
	float alpha = (hc >= 0.28 && hc < 0.86) ? max(h21(id + 19.0), 0.03) : 0.0;
	float hedge = (1.0 - smoothstep(1.5, 5.0 + u_road_mul, edge)) * 0.85;
	col = mix(col, vec3(0.12, 0.24, 0.10), hedge);
	for (int i = 0; i < 18; i++) { vec3 w = u_wood[i]; if (w.z > 1.0) { vec2 d = p - w.xy; float a = atan(d.y, d.x);
		float rr = w.z * (1.0 + 0.25 * sin(3.0 * a + w.x * 0.01) + 0.15 * sin(5.0 * a + w.y * 0.013)); float m = 1.0 - smoothstep(0.82, 1.0, length(d) / rr);
		vec3 wc = vec3(0.13, 0.27, 0.13) * (0.75 + 0.5 * vn(p * 0.06)); col = mix(col, wc, m); alpha *= 1.0 - m; } }
	for (int i = 0; i < 10; i++) { vec3 v = u_vill[i]; if (v.z > 1.0) { vec2 d = p - v.xy; float a = atan(d.y, d.x);
		float rr = v.z * (1.0 + 0.2 * sin(3.0 * a + v.x * 0.02) + 0.12 * sin(6.0 * a + v.y * 0.011)); float m = 1.0 - smoothstep(0.85, 1.0, length(d) / rr);
		vec3 vc = vec3(0.52, 0.46, 0.42);
		if (u_detail > 0.5) { vec2 hp = p / 30.0; vec2 hi = floor(hp); vec2 hf = fract(hp);
			float house = step(0.3, h21(hi)) * step(0.18, hf.x) * step(hf.x, 0.82) * step(0.2, hf.y) * step(hf.y, 0.8);
			vc = mix(vec3(0.36, 0.5, 0.28), vec3(0.58, 0.34, 0.27) * (0.8 + 0.4 * h21(hi + 3.0)), house); }
		if (v.z > 1500.0) vc = vec3(0.48, 0.47, 0.47);
		col = mix(col, vc, m); alpha *= 1.0 - m; } }
	float rd = 1e5; for (int i = 0; i < 12; i++) rd = min(rd, segd(p, u_river[i]));
	float rw = 16.0 * max(1.0, u_road_mul * 0.5);
	col = mix(col, vec3(0.20, 0.28, 0.14), (1.0 - smoothstep(rw * 0.5, rw * 0.5 + 14.0 * u_road_mul, rd)) * 0.6);
	float water = 1.0 - smoothstep(rw * 0.5 - 1.0, rw * 0.5 + 1.5, rd);
	col = mix(col, vec3(0.22, 0.38, 0.52), water); alpha *= 1.0 - water;
	float road = 0.0; float verge = 0.0;
	for (int i = 0; i < 28; i++) { float w = u_road_w[i] * u_road_mul; if (w > 0.5) { float d = segd(p, u_road[i]);
		road = max(road, 1.0 - smoothstep(w * 0.5, w * 0.5 + 1.2, d)); verge = max(verge, 1.0 - smoothstep(w * 0.5, w * 0.5 + 7.0, d)); } }
	col = mix(col, col * 0.8 + vec3(0.05), verge * 0.5);
	col = mix(col, vec3(0.31, 0.31, 0.33), road); alpha *= 1.0 - road;
	vec2 rdir = u_rw.xy; vec2 rperp = vec2(-rdir.y, rdir.x);
	float u = dot(p, rdir); float v = dot(p, rperp); float L = u_rw.z * 0.5;
	float ag = boxm(vec2(u, v), vec2(0.0, -60.0), vec2(L + 140.0, 330.0), 30.0);
	float stripe = step(mod(v, 44.0), 22.0);
	vec3 grass = vec3(0.42, 0.60, 0.28) * (0.96 + 0.06 * stripe) * (0.95 + 0.1 * vn(p * 0.02));
	col = mix(col, grass, ag); alpha *= 1.0 - ag;
	float gr = boxm(vec2(u, v), vec2(0.0, 125.0), vec2(650.0, 24.0), 1.5);
	col = mix(col, vec3(0.50, 0.68, 0.32) * (0.94 + 0.1 * step(mod(u, 60.0), 30.0)), gr);
	vec3 asph = vec3(0.19, 0.20, 0.22); vec3 conc = vec3(0.52, 0.52, 0.52);
	float taxi = boxm(vec2(u, v), vec2(0.0, -75.0), vec2(700.0, 9.0), 1.5);
	for (int k = 0; k < 4; k++) { float u0 = -600.0 + 350.0 * float(k); taxi = max(taxi, boxm(vec2(u, v), vec2(u0, -48.0), vec2(9.0, 28.0), 1.5)); }
	col = mix(col, asph, taxi);
	col = mix(col, conc, boxm(vec2(u, v), vec2(-90.0, -152.0), vec2(310.0, 63.0), 2.0));
	float rwm = boxm(vec2(u, v), vec2(0.0), vec2(L + 12.0, 23.0), 1.2);
	col = mix(col, asph * 1.05, rwm);
	COLOR = vec4(col, alpha);
}
