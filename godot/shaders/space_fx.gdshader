shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
// Glowing things in space: the sun, stars, engine flames, explosions and the planet's atmosphere.
// kind 0: soft round glow that always faces the camera (sun, stars, flashes)
// kind 1: engine flame (a cone along -Z of the mesh, brighter at the nozzle)
// kind 2: fireball (round, noisy, burns from white through orange to smoke) - 'life' 0..1
// kind 3: atmosphere rim (on a sphere a little larger than the planet, lit on the sun's side)
uniform int kind = 0;
uniform vec3 color : source_color = vec3(1.0, 0.6, 0.2);
uniform float energy = 4.0;
uniform float life = 0.0;
uniform vec3 sun_dir = vec3(0.0, 0.3, 1.0);
uniform float falloff = 2.0;
uniform float star_twinkle = 0.0;

varying vec3 wn;
varying vec3 wpos;
varying float inst;

float h31(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float vn3(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h31(i), h31(i + vec3(1, 0, 0)), f.x), mix(h31(i + vec3(0, 1, 0)), h31(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(h31(i + vec3(0, 0, 1)), h31(i + vec3(1, 0, 1)), f.x), mix(h31(i + vec3(0, 1, 1)), h31(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	inst = INSTANCE_CUSTOM.r;
	if (kind == 0 || kind == 2) {
		float sc = length(MODEL_MATRIX[0].xyz);
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * sc, INV_VIEW_MATRIX[1] * sc, INV_VIEW_MATRIX[2] * sc, MODEL_MATRIX[3]);
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 c = color;
	float a = 0.0;
	if (kind == 0) {
		float d = length(UV - 0.5) * 2.0;
		a = pow(clamp(1.0 - d, 0.0, 1.0), falloff);
		a += pow(clamp(1.0 - d, 0.0, 1.0), falloff * 8.0) * 2.0;
		c = mix(color, COLOR.rgb, star_twinkle);
	} else if (kind == 1) {
		// UV.y runs along the cone
		float along = UV.y;
		a = pow(1.0 - along, 1.5) * (0.6 + 0.4 * vn3(vec3(UV * 8.0, TIME * 30.0)));
		c = mix(color, vec3(1.0), pow(1.0 - along, 4.0));
		float rim = abs(dot(normalize(NORMAL), normalize(VIEW)));
		a *= rim;
	} else if (kind == 2) {
		float d = length(UV - 0.5) * 2.0;
		float n = vn3(vec3(UV * 6.0, life * 3.0 + inst * 10.0)) * 0.5 + vn3(vec3(UV * 14.0, life * 5.0)) * 0.5;
		float edge = 1.0 - smoothstep(0.35 + life * 0.5 - n * 0.3, 0.9, d);
		vec3 hot = mix(vec3(1.0, 0.95, 0.8), vec3(1.0, 0.45, 0.1), smoothstep(0.0, 0.35, life));
		c = mix(hot, vec3(0.25, 0.08, 0.03), smoothstep(0.35, 1.0, life));
		a = edge * (1.0 - life) * (0.6 + n);
	} else {
		float rim = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
		float lit = smoothstep(-0.35, 0.6, dot(wn, normalize(sun_dir)));
		a = pow(rim, falloff) * lit;
	}
	ALBEDO = c * energy * a;
}
