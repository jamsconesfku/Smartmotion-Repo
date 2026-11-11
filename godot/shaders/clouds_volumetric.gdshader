shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, blend_mix, fog_disabled, shadows_disabled;
// 3D clouds you can fly through: a full-screen pass that marches each pixel's ray through a slab of cloud
// between cloud_base and cloud_top. Shape: a weather map (where clouds are) x 3D noise (puffy detail).
// Light: Beer-Lambert absorption towards the sun, a "powder" darkening of thick edges, and forward scattering
// (bright silver edges when looking towards the sun). The scene's depth stops clouds showing through hills and buildings.
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D weather : filter_linear_mipmap, repeat_enable;
uniform sampler3D shape_noise : filter_linear_mipmap, repeat_enable;
uniform sampler3D detail_noise : filter_linear_mipmap, repeat_enable;
uniform float cloud_base = 950.0;
uniform float cloud_top = 2300.0;
uniform float coverage = 0.5;
uniform float density = 0.045;
uniform float weather_scale = 24000.0;
uniform vec2 offset = vec2(0.0);
uniform vec3 sun_dir = vec3(0.3, 0.7, -0.6);
uniform vec3 sun_col = vec3(1.0, 0.96, 0.88);
uniform float sun_energy = 1.6;
uniform vec3 amb_top = vec3(0.55, 0.65, 0.85);
uniform vec3 amb_bottom = vec3(0.35, 0.38, 0.45);
uniform vec3 haze_col = vec3(0.74, 0.84, 0.95);
uniform float haze = 0.000034;
uniform int steps = 64;
uniform int light_steps = 5;
uniform float max_dist = 45000.0;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
}

float remap(float v, float a, float b, float c, float d) { return c + (v - a) / max(b - a, 1e-4) * (d - c); }

float cover_at(vec2 xz) {
	return texture(weather, (xz + offset) / weather_scale).r;
}

float dens(vec3 p, bool cheap) {
	float h = clamp((p.y - cloud_base) / (cloud_top - cloud_base), 0.0, 1.0);
	float w = cover_at(p.xz);
	float c = clamp(remap(w, 1.0 - coverage, 1.0, 0.0, 1.0), 0.0, 1.0);
	if (c <= 0.0) return 0.0;
	// cumulus profile: flat-ish base, rounded tops; denser clouds grow taller
	float prof = smoothstep(0.0, 0.07, h) * (1.0 - smoothstep(0.25 + 0.65 * c, 0.3 + 0.7 * c, h));
	vec3 q = p + vec3(offset.x, 0.0, offset.y);
	float base = texture(shape_noise, q / 2600.0).r;
	float d = clamp(remap(base * prof, 1.0 - c * 0.85, 1.0, 0.0, 1.0), 0.0, 1.0);
	if (d <= 0.0 || cheap) return d;
	float det = texture(detail_noise, q / 420.0).r;
	d = clamp(remap(d, det * 0.35 * (1.0 - h * 0.5), 1.0, 0.0, 1.0), 0.0, 1.0);
	return d;
}

float hg(float c, float g) { float g2 = g * g; return (1.0 - g2) / (12.566 * pow(1.0 + g2 - 2.0 * g * c, 1.5)); }

float ign(vec2 px) { return fract(52.9829189 * fract(dot(px, vec2(0.06711056, 0.00583715)))); }

void fragment() {
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, 0.0, 1.0);
	vec4 vfar = INV_PROJECTION_MATRIX * ndc;
	vfar.xyz /= vfar.w;
	vec3 ro = CAMERA_POSITION_WORLD;
	vec3 rd = normalize((INV_VIEW_MATRIX * vec4(vfar.xyz, 0.0)).xyz);
	float depth = texture(depth_tex, SCREEN_UV).r;
	float scene = max_dist;
	if (depth > 0.0) {
		vec4 vp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
		scene = length(vp.xyz / vp.w);
	}
	// where the ray is inside the cloud slab
	float t0; float t1;
	if (abs(rd.y) < 1e-4) {
		if (ro.y < cloud_base || ro.y > cloud_top) discard;
		t0 = 0.0; t1 = max_dist;
	} else {
		float ta = (cloud_base - ro.y) / rd.y;
		float tb = (cloud_top - ro.y) / rd.y;
		t0 = max(min(ta, tb), 0.0);
		t1 = max(ta, tb);
	}
	t1 = min(t1, min(scene, max_dist));
	if (t1 <= t0) discard;

	float span = t1 - t0;
	float stp = clamp(span / float(steps), 25.0, 400.0);
	float t = t0 + stp * ign(FRAGCOORD.xy + vec2(TIME * 61.0, TIME * 37.0));
	vec3 sd = normalize(sun_dir);
	float cs = dot(rd, sd);
	float ph0 = mix(hg(cs, 0.65), hg(cs, -0.2), 0.3) * 12.566 * 0.5 + 0.25;
	float ph1 = mix(hg(cs, 0.325), hg(cs, -0.1), 0.3) * 12.566 * 0.5 + 0.25;
	float ph2 = mix(hg(cs, 0.16), hg(cs, -0.05), 0.3) * 12.566 * 0.5 + 0.25;
	float T = 1.0;
	vec3 L = vec3(0.0);
	int n = 0;
	float lstep = (cloud_top - cloud_base) / float(light_steps) * 0.6;
	for (int i = 0; i < 256; i++) {
		if (t >= t1 || T < 0.015 || i >= steps * 2) break;
		vec3 p = ro + rd * t;
		float d = dens(p, false);
		if (d > 0.002) {
			float sig = d * density;
			// light reaching this point from the sun
			float od = 0.0;
			for (int k = 1; k <= light_steps; k++) {
				od += dens(p + sd * lstep * float(k), k > 2) * lstep;
			}
			// light scattered once and several times inside the cloud (three "octaves": each one weaker,
			// reaching further in and spread more evenly), which gives the soft bright cores of real cumulus
			float powder = 1.0 - exp(-sig * 140.0);
			float odd = od * density * 1.1;
			float sunl = exp(-odd) * ph0 + 0.5 * exp(-odd * 0.4) * ph1 + 0.25 * exp(-odd * 0.16) * ph2;
			float h = clamp((p.y - cloud_base) / (cloud_top - cloud_base), 0.0, 1.0);
			// sky light: from above at the tops, from the ground (darker) underneath; less deep inside
			float occl = exp(-d * 1.6);
			vec3 amb = mix(amb_bottom, amb_top, h) * (0.45 + 0.55 * h) * (0.6 + 0.4 * occl);
			vec3 Ls = sun_col * sun_energy * sunl * mix(1.0, powder, 0.55) + amb;
			float a = exp(-sig * stp);
			// energy-conserving integration (Hillaire)
			L += T * Ls * (1.0 - a);
			T *= a;
			t += stp;
		} else {
			t += stp * 1.8;   // empty sky: take bigger steps
		}
		n++;
	}
	float alpha = 1.0 - T;
	if (alpha < 0.003) discard;
	// distant clouds fade into the haze, like the ground does
	float hz = 1.0 - exp(-t0 * haze * 1.3);
	L = mix(L, haze_col * alpha, hz);
	ALBEDO = L / alpha;
	ALPHA = alpha * (1.0 - smoothstep(max_dist * 0.7, max_dist, t0));
}
