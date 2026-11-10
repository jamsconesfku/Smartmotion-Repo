shader_type spatial;
render_mode cull_back, diffuse_lambert_wrap, specular_disabled;
// The real woods and hedgerow trees (MultiMesh, one colour per tree). The crown is a few lumpy blobs; this
// shader gives it leaf clumps (noise in world space, so every tree is different), darker hollows inside,
// a warmer sunlit outside, light coming through the leaves, and a gentle sway in the wind. The trunk is
// told apart by its position in the 1-unit-tall mesh (below 0.47, thinner than 0.07).
uniform float wind = 1.0;

varying vec3 v_wpos;
varying float v_trunk;

float h31(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float vn3(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(h31(i), h31(i + vec3(1, 0, 0)), f.x), mix(h31(i + vec3(0, 1, 0)), h31(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(h31(i + vec3(0, 0, 1)), h31(i + vec3(1, 0, 1)), f.x), mix(h31(i + vec3(0, 1, 1)), h31(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}

void vertex() {
	v_trunk = (VERTEX.y < 0.47 && length(VERTEX.xz) < 0.07) ? 1.0 : 0.0;
	vec3 org = MODEL_MATRIX[3].xyz;
	float sway = (sin(TIME * 1.3 + org.x * 0.07 + org.z * 0.05) + 0.4 * sin(TIME * 2.9 + org.z * 0.11)) * 0.012 * wind;
	float k = max(VERTEX.y - 0.35, 0.0);
	VERTEX.x += sway * k;
	VERTEX.z += sway * 0.6 * k;
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float dist = length(v_wpos - CAMERA_POSITION_WORLD);
	if (v_trunk > 0.5) {
		ALBEDO = vec3(0.16, 0.12, 0.085) * (0.8 + 0.4 * vn3(v_wpos * vec3(6.0, 0.8, 6.0)));
		ROUGHNESS = 0.95;
	} else {
		float near = 1.0 - smoothstep(120.0, 1100.0, dist);
		float n1 = vn3(v_wpos * 0.85);
		float n2 = near > 0.01 ? vn3(v_wpos * 3.2 + 7.0) : 0.5;
		float clump = n1 * 0.62 + n2 * 0.38;
		vec3 col = COLOR.rgb * mix(1.0, 0.6 + 0.8 * clump, 0.4 + 0.6 * near);
		col *= mix(vec3(1.0), vec3(1.1, 1.07, 0.82), smoothstep(0.6, 0.9, clump) * (0.25 + 0.5 * near));
		ALBEDO = col;
		// leafy surface: tip the normal with the clumps (in view space, like a bump map)
		vec3 b = vec3(n2 - 0.5, n1 - 0.5, 0.5 - n2) * 0.9 * (0.3 + 0.7 * near);
		NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(b, 0.0)).xyz);
		AO = 0.5 + 0.5 * smoothstep(0.25, 0.75, clump);
		AO_LIGHT_AFFECT = 0.35;
		ROUGHNESS = 0.92;
		BACKLIGHT = vec3(0.16, 0.22, 0.05) * (0.4 + 0.6 * near);
	}
}
