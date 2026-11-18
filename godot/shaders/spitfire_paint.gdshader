// The Spitfire's paint (v1.21.0): MH434 as she flies today, in the RAF Day Fighter Scheme of 1943.
// Upper surfaces Dark Green and Ocean Grey camouflage, undersides Medium Sea Grey, Sky spinner and rear
// fuselage band, yellow leading-edge strips on the outer wings, type B roundels on top of the wings, type C
// underneath, type C1 on the fuselage, fin flash, codes ZD-B in Sky and the serial MH434 in black.
// Everything is worked out from where the point is on the aircraft (passed per vertex in the aircraft's own
// axes, so the moving surfaces keep their paint), so the edges stay sharp however close you get.
// Matt-to-satin finish (wartime paint is not glossy), panel seams and rivets from the shared panel normal map,
// a little fading, soot behind the exhausts and wear on the wing walkways.
shader_type spatial;
render_mode cull_back;

uniform int part = 0;                 // 0 fuselage, 1 wing, 2 tailplane / elevator, 3 fin / rudder, 4 spinner
uniform sampler2D letters : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D panels : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D grain : hint_default_white, filter_linear_mipmap, repeat_enable;

// RAF colours (linear-light values of the standard paints, slightly weathered)
const vec3 DARK_GREEN = vec3(0.050, 0.074, 0.034);
const vec3 OCEAN_GREY = vec3(0.104, 0.108, 0.112);
const vec3 SEA_GREY   = vec3(0.235, 0.250, 0.262);
const vec3 SKY        = vec3(0.420, 0.470, 0.330);
const vec3 YELLOW     = vec3(0.780, 0.480, 0.020);
const vec3 RAF_RED    = vec3(0.330, 0.035, 0.030);
const vec3 RAF_BLUE   = vec3(0.022, 0.034, 0.110);
const vec3 RAF_WHITE  = vec3(0.640, 0.640, 0.610);
const vec3 BLACK      = vec3(0.012, 0.012, 0.013);

// the wing's elliptical planform (as built in spitfire.gd)
const float SEMI = 5.615;
const float ROOT = 2.54;

varying vec3 ap;      // position in the aircraft's axes (x right, y up, z back), metres
varying vec3 an;      // normal in the aircraft's axes

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.17, 0.13));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	ap = vec3(UV.x, UV.y, UV2.x);
	an = normalize(COLOR.rgb * 2.0 - 1.0);
}

// a ring marking: colours from the outside in, radii r[0] > r[1] > ...
vec4 disc(vec2 d, float r0, vec3 c0, float r1, vec3 c1, float r2, vec3 c2, float r3, vec3 c3) {
	float r = length(d);
	float aa = 0.004;
	if (r > r0 + aa) return vec4(0.0);
	vec3 c = c0;
	c = mix(c, c1, smoothstep(r1 + aa, r1 - aa, r));
	c = mix(c, c2, smoothstep(r2 + aa, r2 - aa, r));
	c = mix(c, c3, smoothstep(r3 + aa, r3 - aa, r));
	return vec4(c, smoothstep(r0 + aa, r0 - aa, r));
}

// one word of the letters picture: row 0 "ZD", 1 "B", 2 "MH434"; aspect = the word's width / height
float word(vec2 uv, float row, float aspect) {
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return 0.0;
	float gw = aspect * 232.0;
	vec2 px = vec2((1024.0 - gw) * 0.5 + uv.x * gw, row * 256.0 + 12.0 + uv.y * 232.0);
	return texture(letters, px / vec2(1024.0, 768.0)).a;
}

// a word on the fuselage side, reading the right way round on both sides: centre (z, y), letter height h
float side_word(float zc, float yc, float h, float row, float aspect) {
	float w = h * aspect;
	float u = (ap.x < 0.0) ? (ap.z - (zc - w * 0.5)) / w : ((zc + w * 0.5) - ap.z) / w;
	float v = (yc + h * 0.5 - ap.y) / h;
	return word(vec2(u, v), row, aspect);
}

void fragment() {
	vec3 p = ap;
	vec3 n = an;
	// camouflage: big, flowing patches of Dark Green over Ocean Grey (a soft spray edge about 2 cm wide)
	// (about 1 to 1.5 m across, with a gentle sideways flow like the RAF's painted pattern)
	vec3 q = vec3(p.x * 0.62 + p.z * 0.28, p.y * 0.7 + p.x * 0.1, p.z * 0.55 - p.x * 0.22) * 1.55;
	q += 0.45 * vec3(vnoise(q * 0.9 + 4.2), vnoise(q * 0.9 + 8.1), vnoise(q * 0.9 + 1.7));
	float cn = vnoise(q + vec3(3.1, 7.7, 1.3)) * 0.75 + vnoise(q * 2.3 + vec3(9.2, 2.4, 5.5)) * 0.25;
	float edge = fwidth(cn) * 1.5 + 0.012;
	vec3 col = mix(OCEAN_GREY, DARK_GREEN, smoothstep(0.5 - edge, 0.5 + edge, cn));
	float rough = 0.7;

	// underneath: Medium Sea Grey
	float under = 0.0;
	if (part == 0) {
		// the fuselage: grey below a gently wavy line along the lower sides (a little higher towards the tail)
		float yd = mix(-0.20, -0.30, smoothstep(-2.9, -0.6, p.z));
		yd = mix(yd, 0.02, smoothstep(1.6, 5.2, p.z)) + 0.025 * sin(p.z * 2.3 + 1.0);
		under = smoothstep(yd + 0.015, yd - 0.015, p.y);
	} else if (part == 1 || part == 2) {
		under = smoothstep(0.03, -0.03, n.y);
	}
	col = mix(col, SEA_GREY, under);
	rough = mix(rough, 0.55, under);

	if (part == 0) {
		// Sky band round the rear fuselage (18 in)
		float band = step(3.82, p.z) * step(p.z, 4.28);
		col = mix(col, SKY, band);
		// soot behind the exhaust stacks, fading back along the cowling sides
		float soot = smoothstep(-2.45, -2.2, p.z) * smoothstep(0.3, -1.4, p.z) * smoothstep(-0.18, 0.02, p.y) * smoothstep(0.36, 0.12, p.y) * step(0.1, abs(n.x));
		soot *= 0.55 + 0.45 * vnoise(vec3(p.z * 6.0, p.y * 30.0, p.x));
		col = mix(col, vec3(0.02, 0.02, 0.018), soot * 0.75);
		rough = mix(rough, 0.85, soot);
		// fuselage roundel C1 (yellow, blue, white, red), the codes ZD (in front) and B (behind) in Sky, the serial
		if (abs(n.x) > 0.2) {
			vec4 r = disc(vec2(p.z - 2.32, p.y - 0.06), 0.457, YELLOW, 0.406, RAF_BLUE, 0.203, RAF_WHITE, 0.152, RAF_RED);
			col = mix(col, r.rgb, r.a);
			float codes = max(side_word(1.18, 0.06, 0.56, 0.0, 1.828), side_word(3.30, 0.06, 0.56, 1.0, 0.836));
			col = mix(col, SKY, codes);
			col = mix(col, BLACK, side_word(4.70, -0.025, 0.165, 2.0, 4.31));
		}
	} else if (part == 1) {
		float ax = abs(p.x);
		float c = ROOT * sqrt(max(1.0 - (ax * ax) / (SEMI * SEMI), 0.0004));
		float f = (p.z + 0.3 * c) / c;     // 0 at the leading edge, 1 at the trailing edge
		// yellow identification strips along the outer leading edges (both surfaces)
		float strip = smoothstep(2.73, 2.75, ax) * smoothstep(4.92, 4.90, ax) * smoothstep(0.085, 0.075, f);
		col = mix(col, YELLOW, strip);
		// roundels: type B on top (blue, red), type C underneath (blue, white, red)
		vec2 rc = vec2(ax - 3.30, f * c - 0.45 * c);
		if (under < 0.5) {
			vec4 r = disc(vec2(rc.x, p.z - (-0.3 * ROOT * sqrt(1.0 - 3.30 * 3.30 / (SEMI * SEMI)) + 0.45 * ROOT * sqrt(1.0 - 3.30 * 3.30 / (SEMI * SEMI)))), 0.71, RAF_BLUE, 0.284, RAF_RED, 0.0, RAF_RED, 0.0, RAF_RED);
			col = mix(col, r.rgb, r.a);
			// worn walkway on the inner wing, next to the cockpit: chips of bare metal
			float walk = smoothstep(0.95, 0.75, ax) * smoothstep(0.15, 0.25, f) * smoothstep(0.75, 0.6, f);
			float chip = step(0.78, vnoise(p * 38.0)) * walk;
			col = mix(col, vec3(0.32, 0.33, 0.34), chip);
			rough = mix(rough, 0.35, chip);
		} else {
			vec4 r = disc(vec2(rc.x, p.z - (-0.3 * ROOT * sqrt(1.0 - 3.30 * 3.30 / (SEMI * SEMI)) + 0.45 * ROOT * sqrt(1.0 - 3.30 * 3.30 / (SEMI * SEMI)))), 0.406, RAF_BLUE, 0.203, RAF_WHITE, 0.152, RAF_RED, 0.0, RAF_RED);
			col = mix(col, r.rgb, r.a);
			// oil and exhaust grime under the wing roots
			float grime = smoothstep(1.2, 0.5, ax) * smoothstep(-0.2, 1.2, p.z) * (0.5 + 0.5 * vnoise(vec3(p.x * 3.0, 0.0, p.z * 14.0)));
			col = mix(col, col * 0.55, grime * 0.6);
		}
	} else if (part == 3) {
		// fin flash: red (front), white, blue
		if (abs(n.x) > 0.3 && p.y > 0.47 && p.y < 1.13) {
			vec3 ff = p.z < 4.93 ? RAF_RED : (p.z < 4.98 ? RAF_WHITE : RAF_BLUE);
			float on = step(4.65, p.z) * step(p.z, 5.26);
			col = mix(col, ff, on);
		}
	} else if (part == 4) {
		col = SKY;
		rough = 0.45;
	}
	// a little fading and unevenness in the paint
	float fade = vnoise(p * 1.7) * 0.1 + vnoise(p * 9.0) * 0.05;
	col *= 0.93 + fade;
	ALBEDO = col;
	ROUGHNESS = clamp(rough + (texture(grain, p.xz * 0.7 + p.y * 0.3).r - 0.5) * 0.15, 0.25, 0.95);
	SPECULAR = 0.3;
	METALLIC = 0.0;
	// panel seams and rivets: the shared panel normal map, laid on from the side, from above or from the front
	// (in the aircraft's axes) and bent into the normal here (these meshes have no tangents)
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec2 sx = texture(panels, p.zy / 2.4).rg * 2.0 - 1.0;
	vec2 sy = texture(panels, p.xz / 2.4).rg * 2.0 - 1.0;
	vec2 sz = texture(panels, p.xy / 2.4).rg * 2.0 - 1.0;
	vec3 bend = w.x * vec3(0.0, sx.y, sx.x) + w.y * vec3(sy.x, 0.0, sy.y) + w.z * vec3(sz.x, sz.y, 0.0);
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * MODEL_MATRIX * vec4(bend * 0.55, 0.0)).xyz);
}
