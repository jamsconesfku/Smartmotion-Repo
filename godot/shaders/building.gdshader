shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// Real buildings (v1.23.0, scripts/building_kit.gd). COLOR.rgb = tint, COLOR.a = (material + 0.5) / 16:
//   0 brick, 1 render, 2 metal cladding, 3 office (brick/render, wide windows), 4 roof tiles, 5 slate,
//   6 metal roof sheet, 7 flat roof, 8 trim (fascia, bargeboards, copings), 9 chimney stack, 10 chimney pot.
// Walls: UV = (metres along this wall, metres above the ground), UV2 = (wall length, layout code): the windows and
// doors are worked out here from the layout, so every window is whole, evenly spaced and centred on its wall, at
// the same height on every wall. They are recessed (the glass is drawn 12 cm behind the wall with the reveal at its
// edge, as you look), with frames, sills, and brick lintels; far away they fade to an even facade colour.
// Roofs: UV = (metres along the ridge, metres down the slope), so tile courses run parallel to the eaves.
// Textures: ambientCG (CC0).
uniform sampler2D ortho : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D brick_col : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D brick_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D plaster_col : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D plaster_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roof_col : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roof_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D metal_col : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D metal_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_col : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float half_size = 16384.0;

const vec3 DOORS[6] = vec3[6](vec3(0.06, 0.07, 0.08), vec3(0.08, 0.12, 0.22), vec3(0.07, 0.17, 0.11), vec3(0.4, 0.07, 0.06), vec3(0.86, 0.86, 0.84), vec3(0.36, 0.22, 0.12));

varying vec3 v_world;
varying vec3 v_nrm;
varying vec2 v_lay;   // wall length, layout code

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_nrm = NORMAL;
	v_lay = UV2;
	vec3 t = vec3(-NORMAL.z, 0.0, NORMAL.x);
	if (length(t) < 0.05) t = vec3(1.0, 0.0, 0.0);
	TANGENT = normalize(t);
	if (abs(NORMAL.y) < 0.5) {
		BINORMAL = vec3(0.0, -1.0, 0.0);              // walls: u along the wall, v up
	} else {
		BINORMAL = normalize(cross(NORMAL, TANGENT)); // roofs: u along the ridge, v down the slope
	}
}

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

// a box mask with soft (anti-aliased) edges: 1 inside [lo, hi]
float boxm(vec2 p, vec2 lo, vec2 hi, vec2 aa) {
	vec2 a = smoothstep(lo - aa, lo + aa, p) * (1.0 - smoothstep(hi - aa, hi + aa, p));
	return a.x * a.y;
}

void fragment() {
	int id = int(floor(COLOR.a * 16.0));
	vec3 tint = COLOR.rgb;
	float dist = length(v_world - CAMERA_POSITION_WORLD);
	float detail = 1.0 - smoothstep(400.0, 2500.0, dist);
	vec3 col;
	vec3 nm = vec3(0.5, 0.5, 1.0);
	float rough = 0.85;
	float metal = 0.0;
	float spec = 0.4;
	vec2 uv = UV;
	// a per-building random number (the same over the whole building: its footprint corner sits in one 25 m cell)
	float bid = h21(floor(v_world.xz / 25.0) + float(id));

	if (id <= 3 || id == 9) {
		// ---------------------------------------------------------------- walls
		if (id == 0 || id == 9) {
			col = texture(brick_col, uv / 2.4).rgb * tint * 1.25;
			nm = texture(brick_nrm, uv / 2.4).rgb;
		} else if (id == 1) {
			col = texture(plaster_col, uv / 3.0).rgb * tint * 1.08;
			nm = texture(plaster_nrm, uv / 3.0).rgb;
			nm = mix(vec3(0.5, 0.5, 1.0), nm, 0.6);
		} else if (id == 2) {
			// profiled metal cladding on a blockwork plinth
			col = texture(metal_col, uv / 4.0).rgb * tint * 1.4;
			nm = texture(metal_nrm, uv / 4.0).rgb;
			float rib = 0.5 + 0.5 * sin(uv.x * 6.2831 / 0.333);
			nm.x += (rib - 0.5) * 0.55;
			rough = 0.5;
			metal = 0.35;
			if (uv.y < 1.2) {
				vec2 bk = vec2(uv.x / 0.44, uv.y / 0.225);
				bk.x += 0.5 * mod(floor(bk.y), 2.0);
				vec2 f = fract(bk);
				float joint = max(1.0 - smoothstep(0.0, 0.06, f.x) * smoothstep(1.0, 0.94, f.x), 1.0 - smoothstep(0.0, 0.08, f.y) * smoothstep(1.0, 0.92, f.y));
				col = mix(vec3(0.55, 0.55, 0.52), vec3(0.36), joint * 0.6) * (0.92 + 0.08 * h21(floor(bk)));
				rough = 0.9;
				metal = 0.0;
				nm = vec3(0.5, 0.5, 1.0);
			}
		} else {
			col = texture(brick_col, uv / 2.4).rgb * tint * 1.25;
			nm = texture(brick_nrm, uv / 2.4).rgb;
		}
		if (id == 0 || id == 3) {
			// a course of darker engineering bricks at the bottom of the wall
			col *= mix(0.72, 1.0, smoothstep(0.28, 0.32, uv.y));
		}
		// ---------------------------------------------------------------- windows and doors
		float L = v_lay.x;
		float code = v_lay.y;
		int nwin = int(mod(code, 64.0));
		int floors = int(mod(floor(code / 64.0), 8.0));
		int dmode = int(mod(floor(code / 512.0), 4.0));
		int dbay = int(mod(floor(code / 2048.0), 32.0));
		int style = int(floor(code / 65536.0));
		// how big a metre is on screen: far away the openings fade into an even facade (no shimmering)
		float px = length(vec2(dFdx(uv.x), dFdy(uv.x))) + length(vec2(dFdx(uv.y), dFdy(uv.y)));
		float far_fade = 1.0 - smoothstep(0.08, 0.35, px);
		bool office = style == 4 || id == 3;
		float fh = office ? 3.3 : 2.65;
		vec3 frame_col = style == 3 || office ? vec3(0.17, 0.18, 0.19) : vec3(0.9, 0.9, 0.87);
		// view direction in the wall's own axes, for the recess
		float vn = max(dot(VIEW, NORMAL), 0.15);
		vec2 par = vec2(dot(VIEW, TANGENT), -dot(VIEW, BINORMAL)) / vn;
		float depth = 0.12;
		float open_mask = 0.0;
		vec3 open_col = col;
		if (nwin > 0 && floors > 0 && L > 0.5) {
			float cell = L / float(nwin);
			float bay = floor(uv.x / cell);
			float cx = uv.x - (bay + 0.5) * cell;
			float fi = floor(uv.y / fh);
			float fy = uv.y - fi * fh;
			float ww = office ? cell * 0.78 : min(1.2, cell * 0.6);
			float wh = office ? 1.7 : (fi < 0.5 ? 1.3 : 1.2);
			float wb = office ? 0.85 : 0.88;
			bool door = false;
			if (fi < 0.5) {
				if (dmode == 1 && int(bay) == dbay) door = true;
				if (dmode == 2 && int(mod(bay, 2.0)) == 0) door = true;
			}
			if (fi >= 0.0 && fi < float(floors)) {
				vec2 lo, hi;
				if (door) {
					lo = vec2(-0.47, 0.02);
					hi = vec2(0.47, 2.05);
				} else {
					lo = vec2(-ww * 0.5, wb);
					hi = vec2(ww * 0.5, wb + wh);
				}
				vec2 q = vec2(cx, fy);
				vec2 aa = vec2(px * 0.6 + 0.004);
				float outer = boxm(q, lo - 0.07, hi + 0.07, aa);           // frame
				float inner = boxm(q, lo, hi, aa);                           // the opening
				// the glass seen through the opening, 12 cm back: where the view falls outside, the reveal shows
				vec2 qg = q - par * depth * detail;
				float glass = boxm(qg, lo, hi, aa) * inner;
				float reveal = inner - glass;
				if (outer > 0.001) {
					vec3 c_open;
					if (door) {
						// the front door: a painted panel door with a small window
						vec3 dc = DOORS[int(bid * 5.99)];
						float pane = boxm(qg, vec2(-0.25, 1.45), vec2(0.25, 1.85), aa);
						c_open = mix(dc, vec3(0.04, 0.05, 0.06), pane);
						float panel = boxm(qg, vec2(-0.33, 0.15), vec2(0.33, 1.25), aa) - boxm(qg, vec2(-0.29, 0.19), vec2(0.29, 1.21), aa);
						c_open *= 1.0 - 0.25 * panel;
					} else {
						// glass: dark rooms behind, curtains at the sides of some, the sky in the reflection (specular)
						float wrand = h21(vec2(bay, fi) + bid * 31.0);
						vec3 room = mix(vec3(0.025, 0.027, 0.03), vec3(0.09, 0.08, 0.07), wrand * 0.6);
						float curtain = step(0.45, wrand) * (1.0 - smoothstep(0.0, 0.22, min(qg.x - lo.x, hi.x - qg.x) / max(hi.x - lo.x, 0.1)));
						room = mix(room, vec3(0.55, 0.5, 0.42) * (0.6 + 0.4 * wrand), curtain * 0.8 * float(!office));
						// glazing bars: a centre mullion and transom, or Georgian panes
						vec2 g = (qg - lo) / max(hi - lo, vec2(0.1));
						float bars = 0.0;
						float bw = 0.035 / max(hi.x - lo.x, 0.1);
						if (style == 0 || style == 3) bars = max(1.0 - smoothstep(bw * 0.5, bw, abs(g.x - 0.5)), 1.0 - smoothstep(0.012, 0.024, abs(g.y - 0.72)));
						if (style == 1) bars = 1.0 - smoothstep(0.012, 0.024, abs(g.y - 0.7));
						if (style == 2) bars = max(1.0 - smoothstep(bw * 0.4, bw * 0.8, abs(fract(g.x * 3.0) - 0.5) - 0.5 + bw), 1.0 - smoothstep(0.01, 0.02, abs(fract(g.y * 2.0) - 0.5) - 0.5 + 0.02));
						if (office) bars = 1.0 - smoothstep(bw * 0.5, bw, abs(fract(g.x * 2.0) - 0.5) - 0.5 + bw);
						c_open = mix(room, frame_col, clamp(bars, 0.0, 1.0));
					}
					vec3 rev = col * 0.55;                                    // the side of the opening, in shadow
					open_col = mix(mix(frame_col, rev, reveal), c_open, glass);
					open_mask = outer;
					if (!door) {
						// a stone sill under each window, a brick lintel over it
						float sill = boxm(q, vec2(lo.x - 0.1, lo.y - 0.16), vec2(hi.x + 0.1, lo.y - 0.07), aa) * (1.0 - outer);
						col = mix(col, vec3(0.78, 0.76, 0.7), sill);
						if (id == 0) {
							float lintel = boxm(q, vec2(lo.x - 0.16, hi.y + 0.07), vec2(hi.x + 0.16, hi.y + 0.25), aa) * (1.0 - outer);
							col *= 1.0 - 0.22 * lintel;
						}
					}
					// glass is smooth and shiny; the reflection comes from the sky
					float gl = glass * float(!door);
					// (0.12, not a perfect mirror: Godot's sky reflection is speckled when sampled almost perfectly sharp)
					rough = mix(rough, 0.12, gl * open_mask);
					spec = mix(spec, 0.75, gl * open_mask);
					metal = mix(metal, 0.0, open_mask);
					nm = mix(nm, vec3(0.5, 0.5, 1.0), open_mask);
				}
			}
		}
		if (dmode == 3 && L > 3.0) {
			// a roller door in the middle of the wall
			float rw = min(5.5, L * 0.55);
			vec2 q = vec2(uv.x - L * 0.5, uv.y);
			vec2 aa = vec2(px * 0.6 + 0.004);
			float door = boxm(q, vec2(-rw * 0.5, 0.0), vec2(rw * 0.5, 4.2), aa);
			if (door > 0.001) {
				float slat = 0.5 + 0.5 * sin(uv.y * 6.2831 / 0.1);
				open_col = vec3(0.5, 0.52, 0.53) * (0.88 + 0.12 * slat);
				open_mask = max(open_mask, door);
				nm = mix(nm, vec3(0.5, 0.5 + (slat - 0.5) * 0.4, 1.0), door);
				rough = mix(rough, 0.45, door);
				metal = mix(metal, 0.4, door);
			}
		}
		// far away the openings melt into the facade's average (dark windows read as a slightly darker wall)
		float avg_k = nwin > 0 ? 0.82 : 1.0;
		col = mix(col * avg_k, mix(col, open_col, open_mask), far_fade);
		// dirt at the foot of the wall, a little weathering
		col *= mix(0.78, 1.0, smoothstep(-0.6, 0.9, uv.y));
		col *= 0.95 + 0.08 * bid * detail;
	} else if (id == 8 || id == 10) {
		// fascia boards, bargeboards, copings, chimney pots: painted, smooth
		col = tint;
		rough = id == 10 ? 0.8 : 0.45;
		spec = 0.45;
		col *= 0.95 + 0.05 * bid;
	} else {
		// ---------------------------------------------------------------- roofs
		vec2 ouv = v_world.xz / (2.0 * half_size) + 0.5;
		vec3 sat = texture(ortho, ouv).rgb;
		if (id == 4 || id == 5) {
			// tiles or slates in courses parallel to the eaves (v runs down the slope)
			float course = id == 4 ? 0.24 : 0.21;
			float cw = id == 4 ? 0.3 : 0.25;
			vec2 t = vec2(uv.x / cw, uv.y / course);
			t.x += 0.5 * mod(floor(t.y), 2.0);
			vec2 f = fract(t);
			float lap = smoothstep(0.0, 0.85, f.y);                         // each course shades the one below
			float joint = 1.0 - smoothstep(0.0, 0.05, min(f.x, 1.0 - f.x));
			vec3 tex = texture(roof_col, uv / 2.5).rgb;
			float l = dot(tex, vec3(0.33)) / 0.42;
			float tv = 0.9 + 0.2 * h21(floor(t) + bid * 13.0);
			col = tint * l * tv * (0.78 + 0.22 * lap) * (1.0 - 0.25 * joint * detail);
			nm = texture(roof_nrm, uv / 2.5).rgb;
			nm.y += (lap - 0.5) * 0.35 * detail;
			rough = id == 4 ? 0.82 : 0.6;
			spec = id == 4 ? 0.35 : 0.5;
			// lichen and moss, more towards the eaves; a darker ridge
			float moss = smoothstep(0.55, 0.95, h21(floor(uv * 1.7) + bid) * 0.6 + h21(floor(uv * 0.6) + 2.0 * bid) * 0.4);
			col = mix(col, col * vec3(0.95, 1.0, 0.75), moss * 0.35 * detail);
			col *= mix(0.85, 1.0, smoothstep(0.0, 0.25, uv.y));
		} else if (id == 6) {
			// profiled metal roof sheets, ribs running down the slope
			vec3 tex = texture(metal_col, uv / 4.0).rgb;
			col = tint * (dot(tex, vec3(0.33)) / 0.4);
			float rib = 0.5 + 0.5 * sin(uv.x * 6.2831 / 0.333);
			nm = vec3(0.5 + (rib - 0.5) * 0.5, 0.5, 1.0);
			rough = 0.45;
			metal = 0.45;
			col *= 0.9 + 0.1 * h21(floor(vec2(uv.x / 1.0, 0.0)) + bid);
		} else {
			// flat roofs: felt and gravel, a little of the photo's colour
			col = texture(concrete_col, v_world.xz / 6.0).rgb * tint;
			nm = texture(concrete_nrm, v_world.xz / 6.0).rgb;
			rough = 0.9;
			col = mix(col, sat * 1.05, 0.3);
		}
	}
	ALBEDO = col;
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), nm, detail);
	NORMAL_MAP_DEPTH = 1.0;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
}
