shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// The real roads (v1.23.0, scripts/road_kit.gd): tarmac and white lines, drawn on a strip laid on the ground.
// UV = (metres along the road, -1 .. 1 across), UV2 = (metres to the nearer end, road length),
// COLOR = (class / 16, dual carriageway, half width / 16). Classes: 0 motorway, 1 primary, 2 A, 3 B, 4 minor,
// 5 local, 6 local access, 7 restricted access, 8 shared use, 9 busway.
// Lines as on UK roads: dashed centre line on A, B and minor roads (4 m line, 5 m gap; 2 m and 7 m on minor roads),
// solid edge lines on A roads and motorways, a double line down the middle of a dual carriageway, none on lanes.
// No lines within 9 m of a road's ends (that's where it meets another at a junction).
uniform sampler2D asphalt_col : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float fade_start = 2600.0;
uniform float fade_end = 3400.0;

varying vec3 v_world;
varying float v_dist;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 q) {
	vec2 i = floor(q); vec2 f = fract(q); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// pull the road a little towards the camera so it always wins over the ground it lies on (far away the ground
	// is drawn with bigger triangles, which can sit a little above the road's true height)
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float d = length(vp.xyz);
	v_dist = d;
	float cls = floor(COLOR.r * 16.0);
	float pull = 0.06 + d * 0.0012 + (9.0 - cls) * 0.003;
	vp.xyz *= max(d - pull, 0.05) / max(d, 0.05);
	POSITION = PROJECTION_MATRIX * vp;
}

float line(float x, float w, float aa) { return 1.0 - smoothstep(w * 0.5 - aa, w * 0.5 + aa, abs(x)); }
float dash(float s, float on, float gap, float aa) {
	float m = mod(s, on + gap);
	return smoothstep(0.0, aa, m) * (1.0 - smoothstep(on - aa, on, m));
}

void fragment() {
	int cls = int(floor(COLOR.r * 16.0));
	bool dual = COLOR.g > 0.5;
	float hw = COLOR.b * 16.0;
	float s = UV.x;
	float x = UV.y * hw;                  // metres from the centre line
	float to_end = UV2.x;
	float aa = max(fwidth(x), 0.01) * 0.75;
	float saa = max(fwidth(s), 0.01) * 0.75;
	// tarmac: fresher and darker on main roads, greyer and patched on lanes; texture along the road
	vec2 tuv = vec2(s, x) / 3.5;
	vec3 tex = texture(asphalt_col, tuv).rgb;
	float main = cls <= 3 ? 1.0 : 0.0;
	vec3 base = mix(vec3(0.115, 0.115, 0.12), vec3(0.075, 0.076, 0.08), main);
	vec3 col = base * (tex / 0.38);
	float n1 = vnoise(vec2(s, x) / 7.0) * 0.6 + vnoise(vec2(s, x) / 1.7) * 0.4;
	col *= 0.86 + 0.28 * n1;
	// patches of newer tarmac, and the worn, crumbly edges of lanes
	float patch = step(0.72, vnoise(vec2(s / 23.0, x / 3.0 + 7.0)));
	col = mix(col, col * 0.72, patch * 0.6);
	float edge_k = smoothstep(hw - 0.6, hw, abs(x));
	col = mix(col, mix(col, vec3(0.16, 0.15, 0.12), 0.5), edge_k * (1.0 - main * 0.6));
	// tyre tracks: two slightly polished darker bands in each lane
	float lane = dual ? hw * 0.5 : hw;
	float tw = mod(abs(x), lane) - lane * 0.5;
	col *= 1.0 - 0.06 * (line(abs(tw) - 0.6, 0.6, 0.2)) * main;
	// white lines
	float paint = 0.0;
	float marks_ok = smoothstep(8.0, 10.0, to_end);
	if (cls <= 4) {
		if (dual) {
			paint = max(paint, line(x - 0.18, 0.12, aa) + line(x + 0.18, 0.12, aa));        // double line in the middle
			paint = max(paint, line(abs(x) - hw * 0.5, 0.12, aa) * dash(s, 2.0, 7.0, saa)); // lane lines
		} else if (cls <= 3) {
			paint = max(paint, line(x, 0.12, aa) * dash(s, 4.0, 5.0, saa));                 // centre line
		} else if (hw > 2.5) {
			paint = max(paint, line(x, 0.1, aa) * dash(s, 2.0, 7.0, saa));                  // minor roads
		}
		if (cls <= 2) {
			paint = max(paint, line(abs(x) - (hw - 0.3), 0.15, aa));                         // edge lines
		}
	}
	paint *= marks_ok * (0.82 + 0.18 * vnoise(vec2(s * 2.0, x * 9.0)));                  // a little worn
	col = mix(col, vec3(0.78, 0.78, 0.74), clamp(paint, 0.0, 1.0));
	// far away the road fades into the ground picture (which has it too)
	float fade = 1.0 - smoothstep(fade_start, fade_end, v_dist);
	if (fade < 0.999) {
		// dither the fade so it needs no transparency
		float dth = h21(FRAGCOORD.xy);
		if (dth > fade) discard;
	}
	ALBEDO = col;
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), texture(asphalt_nrm, tuv).rgb, 0.6 * (1.0 - paint));
	ROUGHNESS = mix(0.88, 0.6, paint);
	SPECULAR = 0.35;
}
