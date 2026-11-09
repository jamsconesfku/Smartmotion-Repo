shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;
// Puffy clouds: camera-facing cards that pick one of four cloud shapes from a 2x2 atlas
// (INSTANCE_CUSTOM.r). The atlas holds the shading (bright tops, grey bases); the sun side gets a glow.
uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 tint = vec3(1.0);
uniform vec3 shade = vec3(0.62, 0.68, 0.78);
uniform vec3 sun_col = vec3(1.0, 0.96, 0.88);
uniform vec3 sun_dir = vec3(0.0, 0.7, -0.7);

varying vec2 v_cell;
varying float v_dist;
varying vec3 v_view;

void vertex() {
	mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * bb * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, 1.0, 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	float k = floor(INSTANCE_CUSTOM.r + 0.5);
	v_cell = vec2(mod(k, 2.0), floor(k / 2.0)) * 0.5;
	vec3 wp = MODEL_MATRIX[3].xyz;
	v_view = normalize(wp - CAMERA_POSITION_WORLD);
	v_dist = length(wp - CAMERA_POSITION_WORLD);
}

void fragment() {
	vec4 t = texture(atlas, v_cell + UV * 0.5);
	float lit = t.r;   // 1 at the sunny top, 0 in the shaded base
	vec3 c = mix(shade, vec3(1.0), lit) * tint;
	float fwd = max(dot(v_view, normalize(sun_dir)), 0.0);
	c += sun_col * pow(fwd, 6.0) * (1.0 - t.a) * 0.9;   // bright rims when looking towards the sun
	// fade out when very close (no flat cards in your face) and far away (no popping at the edge)
	float fade = smoothstep(120.0, 520.0, v_dist) * (1.0 - smoothstep(22000.0, 30000.0, v_dist));
	ALBEDO = c;
	ALPHA = t.a * fade;
}
