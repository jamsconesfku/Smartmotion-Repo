shader_type sky;
render_mode use_quarter_res_pass;
// Sky (v1.14.0): a physical model of the air, worked out per pixel. Sunlight is scattered by the air
// itself (Rayleigh: the blue of the sky) and by haze (Mie: the white glow round the sun and the pale
// horizon), and absorbed a little by ozone. The light is followed from the camera out to space and, at each
// step, back to the sun, so the colours come out right at any time of day: deep blue overhead at noon, a
// warm horizon and an orange sun at sunset. The heavy part runs at quarter resolution (it is smooth); the
// sun disc and the thin high cloud are added at full resolution. The same model on the CPU
// (scripts/atmosphere.gd) gives the sunlight colour and the haze colour, so the ground matches the sky.
// Weather: `haze` adds Mie haze, `overcast` covers the sky with a grey cloud deck.
uniform float sky_energy = 1.0;      // brightness of the whole sky (matched to the sunlight in world.gd)
uniform float haze = 5.0;            // haze multiplier (1 = very clean air; 5 = an English summer day)
uniform float cam_alt_km = 0.05;     // camera height (set in steps from world.gd, so the sky isn't redrawn every frame)
uniform float cirrus = 0.55;         // how much thin high cloud
uniform float overcast = 0.0;        // 0 = open sky, 1 = covered by a grey cloud deck
uniform vec3 overcast_col = vec3(0.55, 0.58, 0.62);

const float RE = 6360.0;   // km
const float RA = 6460.0;
const vec3 B_R = vec3(5.802, 13.558, 33.1) * 1e-3;   // Rayleigh scattering per km
const float B_MS = 3.996e-3;                          // Mie scattering per km
const float B_ME = 4.40e-3;                           // Mie extinction per km
const vec3 B_O = vec3(0.650, 1.881, 0.085) * 1e-3;   // ozone absorption per km
const float SUN_I = 20.0;

vec2 ray_sphere(vec3 ro, vec3 rd, float r) {
	float b = dot(ro, rd);
	float c = dot(ro, ro) - r * r;
	float h = b * b - c;
	if (h < 0.0) return vec2(-1.0);
	h = sqrt(h);
	return vec2(-b - h, -b + h);
}

vec3 dens(float h) {
	return vec3(exp(-h / 8.0), exp(-h / 1.2), max(0.0, 1.0 - abs(h - 25.0) / 15.0));
}

vec3 ext_of(vec3 d) {
	return B_R * d.x + vec3(B_ME * haze) * d.y + B_O * d.z;
}

// how much sunlight reaches point p (km, planet centre at the origin)
vec3 sun_trans(vec3 p, vec3 sd, int n) {
	vec2 t = ray_sphere(p, sd, RA);
	float L = max(t.y, 0.0);
	float ds = L / float(n);
	vec3 od = vec3(0.0);
	for (int i = 0; i < n; i++) {
		vec3 q = p + sd * (ds * (float(i) + 0.5));
		od += dens(max(length(q) - RE, 0.0)) * ds;
	}
	// the Earth's shadow, softened over a fraction of a degree
	float r = length(p);
	float mu = dot(p / r, sd);
	float mu_h = -sqrt(max(1.0 - (RE / r) * (RE / r), 0.0));
	float lit = smoothstep(mu_h - 0.004, mu_h + 0.004, mu);
	return exp(-ext_of(od)) * lit;
}

vec3 atmosphere(vec3 rd, vec3 sd, int n, int nl) {
	vec3 ro = vec3(0.0, RE + cam_alt_km, 0.0);
	vec2 ta = ray_sphere(ro, rd, RA);
	float tmax = max(ta.y, 0.0);
	vec2 tg = ray_sphere(ro, rd, RE);
	if (tg.x > 0.0) tmax = tg.x;
	float mu = dot(rd, sd);
	float pr = 3.0 / (16.0 * PI) * (1.0 + mu * mu);
	float g = 0.78;
	float pm = 3.0 / (8.0 * PI) * ((1.0 - g * g) * (1.0 + mu * mu)) / ((2.0 + g * g) * pow(1.0 + g * g - 2.0 * g * mu, 1.5));
	vec3 T = vec3(1.0);
	vec3 L = vec3(0.0);
	float prev = 0.0;
	for (int i = 0; i < n; i++) {
		// steps grow with distance: fine near the camera where the haze is
		float f = (float(i) + 1.0) / float(n);
		float t1 = tmax * f * f;
		float ds = t1 - prev;
		vec3 p = ro + rd * (prev + ds * 0.5);
		prev = t1;
		vec3 d = dens(max(length(p) - RE, 0.0));
		vec3 ex = ext_of(d);
		vec3 Ts = sun_trans(p, sd, nl);
		vec3 sr = B_R * d.x;
		vec3 sm = vec3(B_MS * haze * d.y);
		// single scattering, plus a simple stand-in for light scattered more than once
		vec3 S = (sr * pr + sm * pm) * Ts + (sr + sm) * (Ts * 0.55 + vec3(0.006, 0.01, 0.018)) * (0.5 / (4.0 * PI));
		vec3 Tstep = exp(-ex * ds);
		L += T * S * (1.0 - Tstep) / max(ex, vec3(1e-7));
		T *= Tstep;
	}
	return L * SUN_I;
}

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
	// below the horizon the ground (or the haze over it) is what you'd see: use the horizon's colour
	vec3 da = normalize(vec3(d.x, max(d.y, 0.0015), d.z));
	vec3 col;
	if (AT_QUARTER_RES_PASS) {
		COLOR = atmosphere(da, sd, 20, 6) * sky_energy;
	} else {
		if (AT_CUBEMAP_PASS) {
			col = atmosphere(da, sd, 12, 4) * sky_energy;
		} else {
			col = QUARTER_RES_COLOR.rgb;
		}
		if (d.y < 0.0) {
			col *= mix(1.0, 0.82, clamp(-d.y * 6.0, 0.0, 1.0));
		}
		vec3 ro = vec3(0.0, RE + cam_alt_km, 0.0);
		vec3 sun_t = sun_trans(ro, sd, 6);
		float s = max(dot(d, sd), 0.0);
		// thin high cloud on a curved layer, lit by the sun's colour at that time of day
		if (d.y > 0.0 && cirrus > 0.01) {
			vec2 uv = d.xz / (d.y + 0.12) * 1.6;
			int oct = AT_CUBEMAP_PASS ? 3 : 6;
			vec2 w = vec2(fbm(uv * 0.7 + 3.0, 3), fbm(uv * 0.7 + 9.0, 3));
			float c = fbm(vec2(uv.x * 1.6, uv.y * 0.45) + w * 1.4, oct);
			float m = smoothstep(1.0 - cirrus, 1.08 - cirrus * 0.6, c) * smoothstep(0.0, 0.18, d.y);
			vec3 cc = sun_t * sky_energy * (0.55 + 0.9 * pow(s, 5.0)) + col * 0.5;
			col = mix(col, cc, m * 0.7);
		}
		// grey cloud deck (overcast weather)
		if (overcast > 0.0) {
			float deck = smoothstep(-0.03, 0.12, d.y);
			vec3 oc = overcast_col * (0.82 + 0.25 * d.y) * (0.9 + 0.2 * fbm(d.xz / (d.y + 0.08) * 2.2, AT_CUBEMAP_PASS ? 2 : 4));
			col = mix(col, oc, overcast * deck);
		}
		// the sun: a limb-darkened disc (not in the reflections: the light itself makes the highlight)
		if (!AT_CUBEMAP_PASS) {
			float disc = smoothstep(0.999955, 0.999975, s);
			if (disc > 0.0) {
				float r = sqrt(max(1.0 - s, 0.0)) / sqrt(1.0 - 0.999955);
				float limb = 1.0 - 0.55 * (1.0 - sqrt(max(1.0 - r * r, 0.0)));
				col += sun_t * SUN_I * 4.0 * sky_energy * disc * limb * (1.0 - overcast);
			}
		}
		COLOR = col;
	}
}
