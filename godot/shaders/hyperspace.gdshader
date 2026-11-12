shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;
// The hyperspeed tunnel (v1.16.0): the inside of a long tube round the ship, along the mesh's Y axis.
// Streaks of light rush past along it, over a swirling blue glow. 'amount' 0..1 fades it in and out;
// at 1 it covers the stars and planets outside (the ship is moved to the new planet while it does).
uniform float amount = 0.0;
uniform float speed = 1.0;
uniform vec3 tint : source_color = vec3(0.3, 0.55, 1.0);
uniform float half_len = 1000.0;

varying vec3 lp;

float h11(float x) { return fract(sin(x * 127.1) * 43758.5453); }
float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn2(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	lp = VERTEX;
}

void fragment() {
	float ang = atan(lp.x, lp.z) / 6.2831853 + 0.5;   // 0..1 round the tube
	float along = lp.y;                                 // metres along the tube
	float t = TIME * speed;
	// swirling glow
	float sw = vn2(vec2(ang * 18.0 + along * 0.004 + t * 0.6, along * 0.006 - t * 2.0));
	sw = sw * 0.6 + vn2(vec2(ang * 47.0 - t * 0.3, along * 0.02 - t * 5.0)) * 0.4;
	vec3 col = mix(vec3(0.01, 0.02, 0.08), tint * 0.9, smoothstep(0.35, 0.95, sw));
	// streaks: 220 lanes round the tube, each with dashes rushing back past the ship
	float lane = floor(ang * 220.0);
	float r = h11(lane + 3.0);
	float lane_x = fract(ang * 220.0);
	float thin = smoothstep(0.5, 0.15, abs(lane_x - 0.5));
	float s = fract(along * (0.0015 + r * 0.002) - t * (2.5 + r * 3.0) + r * 17.0);
	float dash = pow(s, 10.0) * step(0.35, r);
	col += mix(tint, vec3(1.0), 0.7) * dash * thin * 3.0;
	// bright towards the far end in front (light at the end of the tunnel), dark behind
	float ahead = clamp(-along / half_len, 0.0, 1.0);
	col += vec3(0.7, 0.85, 1.0) * pow(ahead, 6.0) * 2.5;
	ALBEDO = col;
	ALPHA = clamp(amount, 0.0, 1.0);
}
