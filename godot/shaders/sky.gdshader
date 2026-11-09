shader_type sky;
uniform vec3 top_col = vec3(0.14, 0.36, 0.78);
uniform vec3 hor_col = vec3(0.74, 0.84, 0.95);
uniform vec3 sun_col = vec3(1.0, 0.96, 0.88);
void sky() {
	vec3 d = normalize(EYEDIR);
	float t = clamp(d.y, 0.0, 1.0);
	vec3 col = mix(hor_col, top_col, pow(t, 0.5));
	if (d.y < 0.0) col = mix(hor_col, hor_col * 0.82, clamp(-d.y * 5.0, 0.0, 1.0));
	vec3 sd = normalize(LIGHT0_DIRECTION);
	float s = max(dot(d, sd), 0.0);
	col += sun_col * (pow(s, 6.0) * 0.14 + pow(s, 48.0) * 0.3) + sun_col * smoothstep(0.9993, 0.9998, s) * 2.5;
	COLOR = col;
}
