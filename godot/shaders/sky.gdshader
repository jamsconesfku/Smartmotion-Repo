shader_type sky;
// Sky: deep blue overhead fading to a bright hazy horizon, a soft sun glow, and a thin layer of high
// wispy cloud drawn procedurally (the low puffy clouds are separate billboards in world.gd).
uniform vec3 top_col = vec3(0.14, 0.36, 0.78);
uniform vec3 hor_col = vec3(0.74, 0.84, 0.95);
uniform vec3 sun_col = vec3(1.0, 0.96, 0.88);
uniform float cirrus = 0.55;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p, int oct) {
	float v = 0.0; float a = 0.5;
	mat2 r = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < oct; i++) { v += a * vn(p); p = r * p * 2.03 + 17.0; a *= 0.5; }
	return v;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 sd = normalize(LIGHT0_DIRECTION);
	float t = clamp(d.y, 0.0, 1.0);
	// sky gradient: darker, richer blue overhead, a bright band of haze at the horizon
	vec3 col = mix(hor_col, top_col, pow(t, 0.38));
	col = mix(col, top_col * 0.82, smoothstep(0.35, 1.0, t) * 0.35);
	col += hor_col * exp(-t * 22.0) * 0.12;
	if (d.y < 0.0) {
		col = mix(hor_col, hor_col * vec3(0.72, 0.76, 0.78), clamp(-d.y * 4.0, 0.0, 1.0));
	}
	float s = max(dot(d, sd), 0.0);
	// the sky is brighter and warmer on the sun's side
	float side = 0.5 + 0.5 * dot(normalize(d.xz + 1e-4), normalize(sd.xz + 1e-4));
	col += sun_col * side * exp(-t * 6.0) * 0.08;
	// high cloud on a curved layer above the camera
	if (d.y > 0.0) {
		vec2 uv = d.xz / (d.y + 0.12) * 1.6;
		int oct = AT_CUBEMAP_PASS ? 3 : 6;
		vec2 w = vec2(fbm(uv * 0.7 + 3.0, 3), fbm(uv * 0.7 + 9.0, 3));
		float c = fbm(vec2(uv.x * 1.6, uv.y * 0.45) + w * 1.4, oct);
		float m = smoothstep(1.0 - cirrus, 1.08 - cirrus * 0.6, c) * smoothstep(0.0, 0.18, d.y);
		vec3 cc = mix(hor_col, vec3(1.0), 0.75) + sun_col * pow(s, 6.0) * 0.5;
		col = mix(col, cc, m * 0.75);
	}
	// sun: wide glow, tighter halo and a bright disc
	col += sun_col * (pow(s, 4.0) * 0.10 + pow(s, 32.0) * 0.28 + pow(s, 400.0) * 0.6);
	col += sun_col * smoothstep(0.99955, 0.99985, s) * 6.0;
	COLOR = col;
}
