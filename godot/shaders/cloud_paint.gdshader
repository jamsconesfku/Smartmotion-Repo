shader_type canvas_item;
render_mode blend_disabled;
// Paints four cumulus cloud shapes once into a 2x2 atlas. R = how sunlit (top 1, base 0), A = density.
float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * vn(p); p = p * 2.07 + 13.0; a *= 0.5; }
	return v;
}

void fragment() {
	vec2 cell = floor(UV * 2.0);
	vec2 uv = fract(UV * 2.0);
	float seed = cell.x + cell.y * 2.0 + 1.0;
	// a cloud is a row of overlapping round puffs, tallest in the middle, sitting on a flat base
	float d = 0.0;
	for (int i = 0; i < 9; i++) {
		float fi = float(i);
		float x = 0.14 + 0.72 * (fi / 8.0) + (h21(vec2(fi, seed)) - 0.5) * 0.08;
		float mid = 1.0 - abs(x - 0.5) * 1.7;
		float r = (0.09 + 0.12 * mid) * (0.75 + 0.5 * h21(vec2(seed, fi * 3.1)));
		float y = 0.74 - r * (0.6 + 0.5 * h21(vec2(fi * 7.3, seed * 1.9))) - 0.12 * mid * h21(vec2(seed * 5.0, fi));
		float l = length((uv - vec2(x, y)) * vec2(1.0, 1.15)) / r;
		d += max(0.0, 1.0 - l * l) * 0.9;
	}
	float n = fbm(uv * 9.0 + seed * 11.0);
	d = d - (n - 0.5) * 0.7;
	d *= 1.0 - smoothstep(0.70, 0.78, uv.y);   // flat bottom
	float a = smoothstep(0.18, 0.62, d);
	a *= smoothstep(0.0, 0.06, uv.x) * smoothstep(0.0, 0.06, 1.0 - uv.x) * smoothstep(0.0, 0.05, uv.y);
	float lit = clamp(1.15 - smoothstep(0.30, 0.76, uv.y) - (n - 0.5) * 0.5 + (1.0 - smoothstep(0.1, 0.5, d)) * 0.25, 0.0, 1.0);
	COLOR = vec4(lit, lit, lit, a);
}
