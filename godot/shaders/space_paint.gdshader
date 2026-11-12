shader_type canvas_item;
// Paints the space pictures once at start-up (then kept as textures):
// mode 0: the whole sky as a panorama (stars, the Milky Way, coloured nebulae)
// mode 1: the gas giant's bands; mode 2: the rocky moon; mode 3: the gas giant's rings (a 1D strip)
// mode 4: the Earth (oceans, land, ice caps and clouds; land is always put round 'home', where Duxford is)
// v1.16.0: modes 1 and 2 take colours, so the same code paints Jupiter, Saturn, Venus, Uranus and Neptune (1)
// and the Moon, Mercury and Mars (2). The defaults are Saturn and its grey moon, as before.
uniform int mode = 0;
uniform vec3 c1 = vec3(0.86, 0.70, 0.52);
uniform vec3 c2 = vec3(0.62, 0.40, 0.28);
uniform vec3 c3 = vec3(0.93, 0.88, 0.78);
uniform vec3 storm_col = vec3(0.75, 0.32, 0.18);
uniform float bands = 18.0;
uniform float storm = 1.0;
uniform vec3 rock_a = vec3(0.28, 0.27, 0.26);
uniform vec3 rock_b = vec3(0.62, 0.6, 0.57);
uniform float caps = 0.0;        // white polar caps (Mars)
uniform float maria = 0.0;       // big dark patches (the Moon's seas, Mars's dark ground)
uniform float craters = 1.0;     // how strongly the craters show
uniform float seed = 0.0;
uniform vec3 home = vec3(0.0, 0.79, -0.62);

float h31(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float vn3(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h31(i), h31(i + vec3(1, 0, 0)), f.x), mix(h31(i + vec3(0, 1, 0)), h31(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(h31(i + vec3(0, 0, 1)), h31(i + vec3(1, 0, 1)), f.x), mix(h31(i + vec3(0, 1, 1)), h31(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float fbm(vec3 p, int oct) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < oct; i++) { v += a * vn3(p); p = p * 2.03 + vec3(1.7, 9.2, 3.1); a *= 0.5; }
	return v;
}

vec3 dir_of(vec2 uv) {
	float lon = (uv.x - 0.5) * 6.2831853;
	float lat = (0.5 - uv.y) * 3.1415927;
	return vec3(cos(lat) * sin(lon), sin(lat), -cos(lat) * cos(lon));
}

float stars(vec3 d, float scale, float thresh) {
	vec3 p = d * scale;
	vec3 c = floor(p);
	float h = h31(c);
	if (h < thresh) return 0.0;
	vec3 sp = c + vec3(h31(c + 1.3), h31(c + 2.7), h31(c + 5.1));
	float dist = length(p - sp);
	return smoothstep(0.55, 0.0, dist) * pow((h - thresh) / (1.0 - thresh), 3.0);
}

void fragment() {
	vec2 uv = UV;
	if (mode == 0) {
		vec3 d = dir_of(uv);
		// the Milky Way: a bright band tilted across the sky
		vec3 gal = normalize(vec3(0.3, 0.85, 0.42));
		float band = exp(-pow(dot(d, gal) * 3.2, 2.0));
		float dust = fbm(d * 6.0, 6);
		vec3 col = vec3(0.004, 0.005, 0.012);
		col += vec3(0.32, 0.30, 0.36) * band * smoothstep(0.25, 0.8, fbm(d * 3.0 + 4.0, 5)) * 0.55;
		col *= 1.0 - smoothstep(0.45, 0.75, dust) * band * 0.8;   // dark dust lanes
		// nebulae: soft clouds in navy, violet and SmartMotion orange
		float n1 = fbm(d * 2.2 + vec3(3.0), 6);
		float n2 = fbm(d * 3.4 + vec3(8.0, 1.0, 5.0), 6);
		float mask1 = smoothstep(0.52, 0.85, n1) * smoothstep(-0.2, 0.6, dot(d, normalize(vec3(-0.6, 0.2, -0.7))));
		float mask2 = smoothstep(0.55, 0.88, n2) * smoothstep(0.0, 0.7, dot(d, normalize(vec3(0.7, -0.3, 0.4))));
		col += mix(vec3(0.10, 0.05, 0.28), vec3(0.42, 0.12, 0.30), n2) * mask1 * 1.4;
		col += mix(vec3(0.55, 0.16, 0.02), vec3(0.9, 0.45, 0.12), n1) * mask2 * 0.8;
		col += vec3(0.03, 0.06, 0.16) * smoothstep(0.4, 0.9, fbm(d * 1.3, 4)) * 0.6;
		// faint stars, many more in the Milky Way
		float st = stars(d, 300.0, 0.86 - band * 0.08) + stars(d, 640.0, 0.9 - band * 0.06) * 0.6;
		vec3 sc = mix(vec3(0.75, 0.82, 1.0), vec3(1.0, 0.85, 0.7), h31(floor(d * 300.0)));
		col += sc * st * 1.4;
		COLOR = vec4(col, 1.0);
	} else if (mode == 1) {
		// gas giant: soft bands with swirls and a big storm
		float lat = (0.5 - uv.y) * 3.1415927;
		vec3 d = dir_of(uv);
		float warp = fbm(d * 4.0 + seed, 5) * 0.35 + fbm(d * 12.0, 4) * 0.08;
		float b = sin((lat + warp * 0.5) * bands) * 0.5 + 0.5;
		float b2 = sin((lat + warp * 0.3) * bands * 2.6) * 0.5 + 0.5;
		vec3 col = mix(c2, c1, b);
		col = mix(col, c3, b2 * 0.35);
		col *= 0.85 + fbm(d * 30.0, 3) * 0.3;
		vec3 storm_c = normalize(vec3(0.5, -0.32, -0.8));
		float sd = length(d - storm_c);
		float storm_m = smoothstep(0.16, 0.05, sd + fbm(d * 18.0, 3) * 0.05);
		col = mix(col, storm_col, storm_m * 0.8 * storm);
		COLOR = vec4(col, 1.0);
	} else if (mode == 2) {
		vec3 d = dir_of(uv);
		float n = fbm(d * 5.0 + seed, 6);
		vec3 col = mix(rock_a, rock_b, n);
		col *= 1.0 - maria * 0.45 * smoothstep(0.5, 0.62, fbm(d * 1.7 + seed + 3.0, 5));
		for (int i = 0; i < 24; i++) {
			vec3 cc = normalize(vec3(h31(vec3(float(i) + seed, 1, 2)) - 0.5, h31(vec3(float(i) + seed, 3, 4)) - 0.5, h31(vec3(float(i) + seed, 5, 6)) - 0.5));
			float r = 0.05 + h31(vec3(float(i), 7, 8)) * 0.18;
			float dd = length(d - cc) / r;
			col *= 1.0 - craters * (0.35 * smoothstep(1.0, 0.75, dd) - 0.25 * smoothstep(0.85, 1.0, dd) * smoothstep(1.15, 1.0, dd));
		}
		float lat2 = abs(0.5 - uv.y) * 3.1415927;
		col = mix(col, vec3(0.93, 0.92, 0.9), caps * smoothstep(1.2, 1.32, lat2 + fbm(d * 6.0, 4) * 0.15));
		COLOR = vec4(col, 1.0);
	} else if (mode == 4) {
		// the Earth: continents from noise, always with land round 'home' (Duxford sits there)
		vec3 d = dir_of(uv);
		float lat = (0.5 - uv.y) * 3.1415927;
		float h = fbm(d * 2.1 + vec3(4.0, 1.0, 7.0), 7) + fbm(d * 7.0, 4) * 0.12;
		h += 0.2 * smoothstep(0.45, 0.0, length(d - normalize(home)));
		float land = smoothstep(0.55, 0.565, h);
		vec3 ocean = mix(vec3(0.008, 0.035, 0.12), vec3(0.03, 0.15, 0.3), smoothstep(0.38, 0.55, h));
		float dry = fbm(d * 3.0 + vec3(5.0), 5);
		float tropic = 1.0 - abs(lat) / 1.5708;
		vec3 green = mix(vec3(0.07, 0.17, 0.05), vec3(0.2, 0.27, 0.09), fbm(d * 9.0, 4));
		vec3 desert = vec3(0.63, 0.51, 0.33);
		vec3 landc = mix(green, desert, smoothstep(0.5, 0.66, dry) * smoothstep(0.25, 0.65, tropic));
		landc = mix(landc, vec3(0.36, 0.33, 0.29), smoothstep(0.66, 0.74, h));
		vec3 col = mix(ocean, landc, land);
		float ice = smoothstep(1.18, 1.3, abs(lat) + fbm(d * 5.0, 4) * 0.25);
		col = mix(col, vec3(0.92, 0.95, 1.0), ice);
		float cl = fbm(d * 3.6 + vec3(11.0, 2.0, 5.0), 6) + fbm(d * 11.0, 3) * 0.1;
		float clouds = smoothstep(0.52, 0.72, cl + 0.07 * sin(lat * 6.0));
		col = mix(col, vec3(0.96), clouds * 0.88);
		COLOR = vec4(col, 1.0);
	} else {
		// rings: u = radius from inner (0) to outer (1)
		float r = uv.x;
		float rings = fbm(vec3(r * 60.0, 0.0, 0.0), 5);
		float a = smoothstep(0.0, 0.04, r) * smoothstep(1.0, 0.94, r);
		a *= 0.35 + 0.65 * smoothstep(0.25, 0.75, rings);
		a *= 1.0 - smoothstep(0.585, 0.6, r) * smoothstep(0.64, 0.625, r) * 0.9;   // the dark gap
		vec3 col = mix(vec3(0.62, 0.55, 0.46), vec3(0.9, 0.84, 0.74), rings);
		COLOR = vec4(col, a);
	}
}
