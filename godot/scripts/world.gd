class_name World
extends Node3D
## SmartMotion Flight: the world. Sky, lighting, terrain, the Duxford airfield with SmartMotion signs,
## villages, woods, clouds, a blimp and the gate course. Everything is built from code.

const TOD := {
	"day": {"el": 46.0, "az": 205.0, "sun": Color(1, 0.96, 0.88), "top": Color(0.14, 0.36, 0.78), "hor": Color(0.74, 0.84, 0.95), "amb": 0.9, "sun_e": 1.5, "fog": 0.000045},
	"golden": {"el": 9.0, "az": 252.0, "sun": Color(1, 0.62, 0.32), "top": Color(0.12, 0.2, 0.5), "hor": Color(0.97, 0.74, 0.56), "amb": 0.7, "sun_e": 1.6, "fog": 0.00007},
}

var terrain: Terrain
var quality := "high"
var logo: Texture2D
var logo_dark: Texture2D
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ShaderMaterial
var ground_mats: Array = []
var rings: Array = []
var gates: Array = []
var gate_nodes: Array = []
var gate_group := Node3D.new()
var blimp: Node3D
var blimp_t := 0.0
var windsock: Node3D
var wind := Vector3.ZERO
var sign_cache := {}
var _vp_counter := 0


func _yaw_of(d: Vector2) -> float:
	return atan2(-d.y, d.x)   # rotates local +X onto the world direction d (x, z)


func _lin(c: Color) -> Color:
	return c.srgb_to_linear()


func build(progress: Callable, quality_: String, tod: String) -> void:
	quality = quality_
	terrain = Terrain.new()
	logo = load("res://assets/logo.png")
	logo_dark = load("res://assets/logo-dark.png")
	progress.call(0.08, "Lighting the sky")
	_environment()
	progress.call(0.15, "Painting the countryside")
	await _ground()
	progress.call(0.55, "Building Duxford")
	await _airfield()
	progress.call(0.8, "Planting woods and villages")
	_scenery()
	progress.call(0.92, "Hanging the signs")
	await _signs()
	_clouds()
	_blimp()
	_gates()
	set_time_of_day(tod)
	progress.call(1.0, "Ready")


# ---------------------------------------------------------------- sky and light
func _environment() -> void:
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 8.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.04
	env.ssao_enabled = quality != "low"
	env.ssao_radius = 2.5
	env.ssao_intensity = 1.4
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = quality != "low"
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 3500.0
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.05
	sun.shadow_normal_bias = 1.5
	add_child(sun)


func set_time_of_day(name: String) -> void:
	var t: Dictionary = TOD.get(name, TOD["day"])
	var el: float = deg_to_rad(t["el"])
	var az: float = deg_to_rad(t["az"])
	var sd := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
	sun.basis = Basis.looking_at(-sd, Vector3.UP)
	sun.light_color = t["sun"]
	sun.light_energy = t["sun_e"]
	sky_mat.set_shader_parameter("top_col", Vector3(t["top"].r, t["top"].g, t["top"].b))
	sky_mat.set_shader_parameter("hor_col", Vector3(t["hor"].r, t["hor"].g, t["hor"].b))
	sky_mat.set_shader_parameter("sun_col", Vector3(t["sun"].r, t["sun"].g, t["sun"].b))
	env.fog_light_color = t["hor"]
	env.fog_density = t["fog"]
	env.ambient_light_energy = t["amb"]
	var tint: Color = Color(minf(1.0, t["hor"].r + 0.15), minf(1.0, t["hor"].g + 0.12), minf(1.0, t["hor"].b + 0.1))
	if cloud_mat != null:
		cloud_mat.albedo_color = tint


# ---------------------------------------------------------------- ground
func _paint(px: int, size_m: float, road_mul: float, detail: float) -> ImageTexture:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/ground_paint.gdshader")
	var roads := PackedVector4Array()
	var road_w := PackedFloat32Array()
	for r in Terrain.ROADS:
		var pts: Array = r["pts"]
		for i in range(pts.size() - 1):
			if roads.size() < 28:
				roads.append(Vector4(pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1]))
				road_w.append(r["w"])
	while roads.size() < 28:
		roads.append(Vector4(1e6, 1e6, 1e6, 1e6))
		road_w.append(0.0)
	var river := PackedVector4Array()
	var rp: Array = Terrain.RIVER["pts"]
	for i in range(rp.size() - 1):
		river.append(Vector4(rp[i][0], rp[i][1], rp[i + 1][0], rp[i + 1][1]))
	while river.size() < 12:
		river.append(Vector4(1e6, 1e6, 1e6, 1e6))
	var vill := PackedVector3Array()
	for v in Terrain.VILLAGES:
		vill.append(Vector3(v["x"], v["z"], v["r"]))
	while vill.size() < 10:
		vill.append(Vector3.ZERO)
	var wood := PackedVector3Array()
	for w in Terrain.WOODS:
		wood.append(Vector3(w[0], w[1], w[2]))
	while wood.size() < 18:
		wood.append(Vector3.ZERO)
	mat.set_shader_parameter("u_size", size_m)
	mat.set_shader_parameter("u_road_mul", road_mul)
	mat.set_shader_parameter("u_detail", detail)
	mat.set_shader_parameter("u_road", roads)
	mat.set_shader_parameter("u_road_w", road_w)
	mat.set_shader_parameter("u_river", river)
	mat.set_shader_parameter("u_vill", vill)
	mat.set_shader_parameter("u_wood", wood)
	mat.set_shader_parameter("u_rw", Vector4(terrain.dir.x, terrain.dir.y, Terrain.RW_LEN, Terrain.RW_WIDTH))
	var vp := SubViewport.new()
	vp.size = Vector2i(px, px)
	vp.disable_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.size = Vector2(px, px)
	rect.material = mat
	vp.add_child(rect)
	add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		img = Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.36, 0.52, 0.22, 0.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _ring_mesh(cell: float, n: int, hole: int) -> ArrayMesh:
	var n1 := n + 1
	var verts := PackedVector3Array()
	verts.resize(n1 * n1)
	var norms := PackedVector3Array()
	norms.resize(n1 * n1)
	for j in n1:
		for i in n1:
			verts[j * n1 + i] = Vector3((i - n / 2) * cell, 0.0, (j - n / 2) * cell)
			norms[j * n1 + i] = Vector3.UP
	var idx := PackedInt32Array()
	for j in n:
		for i in n:
			if hole > 0 and i >= n / 2 - hole and i < n / 2 + hole and j >= n / 2 - hole and j < n / 2 + hole:
				continue
			var a := j * n1 + i
			var b := a + 1
			var c := a + n1
			var d := c + 1
			idx.append_array([a, b, c, b, d, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	m.custom_aabb = AABB(Vector3(-n / 2.0 * cell, -300.0, -n / 2.0 * cell), Vector3(n * cell, 900.0, n * cell))
	return m


func _detail_texture() -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var img := Image.create_empty(128, 128, false, Image.FORMAT_L8)
	var grid: Array = []
	for i in 256:
		grid.append(rng.randf())
	for y in 128:
		for x in 128:
			var v := 0.0
			var a := 0.5
			var f := 1.0
			for o in 4:
				var gx := float(x) / 128.0 * 16.0 * f
				var gy := float(y) / 128.0 * 16.0 * f
				var x0 := int(floor(gx))
				var y0 := int(floor(gy))
				var fx := gx - x0
				var fy := gy - y0
				var g00: float = grid[(y0 % 16) * 16 + (x0 % 16)]
				var g10: float = grid[(y0 % 16) * 16 + ((x0 + 1) % 16)]
				var g01: float = grid[((y0 + 1) % 16) * 16 + (x0 % 16)]
				var g11: float = grid[((y0 + 1) % 16) * 16 + ((x0 + 1) % 16)]
				v += a * ((g00 * (1.0 - fx) + g10 * fx) * (1.0 - fy) + (g01 * (1.0 - fx) + g11 * fx) * fy)
				a *= 0.5
				f *= 2.0
			img.set_pixel(x, y, Color(clampf(v * 1.1, 0.0, 1.0), 0, 0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _ground() -> void:
	var near_px: int = {"low": 1024, "medium": 2048, "high": 4096}.get(quality, 2048)
	var far_px: int = {"low": 1024, "medium": 2048, "high": 2048}.get(quality, 2048)
	var near_size := near_px * 5.0
	var far_size := far_px * 80.0
	var hm_img := Image.create_from_data(Terrain.SIZE, Terrain.SIZE, false, Image.FORMAT_RF, terrain.data.to_byte_array())
	var hm_tex := ImageTexture.create_from_image(hm_img)
	var near_tex := await _paint(near_px, near_size, 1.0, 1.0)
	var far_tex := await _paint(far_px, far_size, 3.0, 0.0)
	var detail := _detail_texture()
	var shader: Shader = load("res://shaders/ground.gdshader")
	var cells := [16.0, 64.0, 256.0, 1024.0]
	var biases := [0.0, -1.2, -2.5, -5.0]
	var n := 120
	for k in cells.size():
		var cell: float = cells[k]
		var hole := 0
		if k > 0:
			hole = int(n / 2.0 * float(cells[k - 1]) / cell) - 1
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("heightmap", hm_tex)
		mat.set_shader_parameter("near_map", near_tex)
		mat.set_shader_parameter("far_map", far_tex)
		mat.set_shader_parameter("detail_tex", detail)
		mat.set_shader_parameter("cell", Terrain.CELL)
		mat.set_shader_parameter("size_cells", float(Terrain.SIZE))
		mat.set_shader_parameter("near_size", near_size)
		mat.set_shader_parameter("far_size", far_size)
		mat.set_shader_parameter("y_bias", biases[k])
		var mi := MeshInstance3D.new()
		mi.mesh = _ring_mesh(cell, n, hole)
		mi.material_override = mat
		mi.extra_cull_margin = 4000.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if k > 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mi)
		rings.append({"node": mi, "snap": cell * 4.0})


func follow(cam_pos: Vector3) -> void:
	for r in rings:
		var snap: float = r["snap"]
		var n: MeshInstance3D = r["node"]
		n.position = Vector3(round(cam_pos.x / snap) * snap, 0.0, round(cam_pos.z / snap) * snap)


# ---------------------------------------------------------------- signs
func _italic() -> Font:
	return load("res://assets/fonts/BarlowSemiCondensed-ExtraBoldItalic.ttf")


func _label(parent: Control, text: String, rect: Rect2, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var l := Label.new()
	l.text = text
	l.position = rect.position
	l.size = rect.size
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", _italic())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.clip_text = false
	parent.add_child(l)


func sign_texture(w: float, h: float, dark: bool, tag := true, band := "SMARTMOTION.TECH", frame := true, px := 1024) -> ImageTexture:
	var key := "%s_%s_%s_%s_%s_%s_%s" % [w, h, dark, tag, band, frame, px]
	if sign_cache.has(key):
		return sign_cache[key]
	var W := px
	var H := int(px * h / w)
	var vp := SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var root := Control.new()
	root.size = Vector2(W, H)
	vp.add_child(root)
	var navy := Color("#02022f")
	var orange := Color("#ff4c00")
	var bg := ColorRect.new()
	bg.color = navy if dark else Color.WHITE
	bg.size = root.size
	root.add_child(bg)
	var ink := Color.WHITE if dark else navy
	if frame:
		var fr := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.set_border_width_all(int(H * 0.035))
		sb.border_color = orange if dark else navy
		fr.add_theme_stylebox_override("panel", sb)
		fr.position = Vector2(H * 0.04, H * 0.04)
		fr.size = Vector2(W - H * 0.08, H - H * 0.08)
		root.add_child(fr)
	if band != "":
		var br := ColorRect.new()
		br.color = orange
		br.position = Vector2(H * 0.04, H * 0.82)
		br.size = Vector2(W - H * 0.08, H * 0.14)
		root.add_child(br)
		_label(root, band, Rect2(H * 0.04, H * 0.82, W - H * 0.08, H * 0.14), int(H * 0.09), Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	var lt := TextureRect.new()
	lt.texture = logo_dark if dark else logo
	lt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var lh := H * (0.6 if tag else 0.68)
	var lw := lh * 2.5
	lt.position = Vector2(W * 0.05 if tag else (W - lw) / 2.0, H * 0.1)
	lt.size = Vector2(lw, lh)
	root.add_child(lt)
	if tag:
		var lines := ["FLY IT.", "DRIVE IT.", "FEEL IT."]
		for i in 3:
			_label(root, lines[i], Rect2(W * 0.56, H * (0.1 + i * 0.235), W * 0.4, H * 0.22), int(H * 0.2), orange if i == 1 else ink)
	add_child(vp)
	_vp_counter += 1
	return await _grab(vp, key)


func _grab(vp: SubViewport, key: String) -> ImageTexture:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		img = Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	sign_cache[key] = t
	return t


func _unshaded_tex(tex: Texture2D, alpha := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if alpha:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	return m


func _sign_board(x: float, z: float, w: float, h: float, n: Vector2, post: float, tex: Texture2D) -> Node3D:
	var g := Node3D.new()
	var back := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w + 0.8, h + 0.8, 0.5)
	back.mesh = bm
	var navy := StandardMaterial3D.new()
	navy.albedo_color = Color("#02022f").srgb_to_linear()
	back.material_override = navy
	back.position = Vector3(0, post + h / 2.0, -0.32)
	g.add_child(back)
	var panel := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	panel.mesh = q
	panel.material_override = _unshaded_tex(tex)
	panel.position = Vector3(0, post + h / 2.0, 0.0)
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(panel)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.22, 0.24, 0.3)
	for s in [-1.0, 1.0]:
		var p := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.7, post + 1.0, 0.7)
		p.mesh = pm
		p.material_override = steel
		p.position = Vector3(s * w * 0.35, (post + 1.0) / 2.0, -0.3)
		g.add_child(p)
	g.position = Vector3(x, terrain.height(x, z), z)
	g.rotation.y = atan2(n.x, n.y)
	add_child(g)
	return g


func _signs() -> void:
	for s in Terrain.SIGNS:
		var xz := terrain.from_runway(s["u"], s["v"])
		var fa: float = deg_to_rad(s["face"])
		var n := terrain.dir * cos(fa) + terrain.perp * sin(fa)
		var tex := await sign_texture(s["w"], s["h"], false)
		_sign_board(xz.x, xz.y, s["w"], s["h"], n, s["post"], tex)
	# roadside billboard beside the M11, facing the airfield
	var bb := await sign_texture(34.0, 11.0, true)
	_sign_board(3000.0, -220.0, 34.0, 11.0, Vector2(-1.0, 0.1).normalized(), 8.0, bb)
	# runway distance boards
	var db := await sign_texture(4.4, 1.8, false, false, "", true, 512)
	for k in range(-3, 4):
		var xz2 := terrain.from_runway(k * 220.0, 38.0)
		_sign_board(xz2.x, xz2.y, 4.4, 1.8, -terrain.perp, 1.2, db)
	# windsock
	windsock = Node3D.new()
	var pole := MeshInstance3D.new()
	var pc := CylinderMesh.new()
	pc.top_radius = 0.12
	pc.bottom_radius = 0.16
	pc.height = 9.0
	pole.mesh = pc
	pole.position.y = 4.5
	windsock.add_child(pole)
	var sock := MeshInstance3D.new()
	var sc := CylinderMesh.new()
	sc.top_radius = 0.25
	sc.bottom_radius = 0.75
	sc.height = 3.6
	sock.mesh = sc
	var om := StandardMaterial3D.new()
	om.albedo_color = Color("#ff4c00").srgb_to_linear()
	om.cull_mode = BaseMaterial3D.CULL_DISABLED
	sock.material_override = om
	sock.rotation.z = -PI / 2.0
	sock.position = Vector3(1.9, 9.0, 0)
	windsock.add_child(sock)
	var xz3 := terrain.from_runway(250.0, 45.0)
	windsock.position = Vector3(xz3.x, terrain.height(xz3.x, xz3.y), xz3.y)
	add_child(windsock)


# ---------------------------------------------------------------- airfield
func _place(n: Node3D, u: float, v: float, dy := 0.0, extra_yaw := 0.0) -> void:
	var xz := terrain.from_runway(u, v)
	n.position = Vector3(xz.x, terrain.height(xz.x, xz.y) + dy, xz.y)
	n.rotation.y = _yaw_of(terrain.dir) + extra_yaw
	add_child(n)


func _mat(c: Color, rough := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c.srgb_to_linear()
	m.roughness = rough
	return m


func _hangar_front(du: float, wall_h: float) -> ImageTexture:
	var key := "front_%s_%s" % [du, wall_h]
	if sign_cache.has(key):
		return sign_cache[key]
	var w := 512
	var h := int(512.0 * wall_h / du)
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color("#8a4f3a"))
	var y := 0
	while y < h:
		img.fill_rect(Rect2i(0, y, w, 1), Color("#7a4432"))
		y += 6
	img.fill_rect(Rect2i(int(w * 0.06), int(h * 0.3), int(w * 0.88), int(h * 0.7)), Color("#3b3f4d"))
	for i in range(1, 6):
		img.fill_rect(Rect2i(int(w * (0.06 + 0.88 * i / 6.0)) - 1, int(h * 0.3), 2, int(h * 0.7)), Color("#2d3040"))
	img.fill_rect(Rect2i(int(w * 0.06), int(h * 0.24), int(w * 0.88), int(h * 0.05)), Color("#ff4c00"))
	var lg := logo_dark.get_image()
	if lg.is_compressed():
		lg.decompress()
	lg.convert(Image.FORMAT_RGBA8)
	var lh := int(h * 0.2)
	lg.resize(int(lh * 2.5), lh, Image.INTERPOLATE_LANCZOS)
	img.blend_rect(lg, Rect2i(0, 0, lg.get_width(), lg.get_height()), Vector2i(w / 2 - lg.get_width() / 2, int(h * 0.02)))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	sign_cache[key] = t
	return t


func _airfield() -> void:
	var wall := _mat(Color("#9a8a7a"))
	var roof_m := _mat(Color("#6d717c"), 0.6)
	var roof_tex := await sign_texture(60.0, 30.0, false, true, "SMARTMOTION · DUXFORD")
	for b in Terrain.BUILDINGS:
		var g := Node3D.new()
		var du: float = b["du"]
		var dv: float = b["dv"]
		if b["kind"] == "tower":
			var base := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(du, 9, dv)
			base.mesh = bm
			base.material_override = _mat(Color("#e9e6df"))
			base.position.y = 4.5
			g.add_child(base)
			var cab := MeshInstance3D.new()
			var cm := BoxMesh.new()
			cm.size = Vector3(du + 3, 3.4, dv + 3)
			cab.mesh = cm
			var gl := _mat(Color("#7fa8cc"), 0.1)
			gl.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			gl.albedo_color.a = 0.8
			cab.material_override = gl
			cab.position.y = 10.7
			g.add_child(cab)
			var rf := MeshInstance3D.new()
			var rm := BoxMesh.new()
			rm.size = Vector3(du + 4, 0.5, dv + 4)
			rf.mesh = rm
			rf.material_override = _mat(Color("#2a2d38"))
			rf.position.y = 12.6
			g.add_child(rf)
			_place(g, b["u"], b["v"])
			continue
		var wall_h: float = 13.0 if b["kind"] == "bighangar" else 10.5
		var ridge: float = float(b["h"]) - wall_h
		var body := MeshInstance3D.new()
		var bx := BoxMesh.new()
		bx.size = Vector3(du, wall_h, dv)
		body.mesh = bx
		body.material_override = wall
		body.position.y = wall_h / 2.0
		g.add_child(body)
		var roof := MeshInstance3D.new()
		var pr := PrismMesh.new()
		pr.size = Vector3(dv, ridge, du)
		roof.mesh = pr
		roof.material_override = roof_m
		roof.position.y = wall_h + ridge / 2.0
		roof.rotation.y = PI / 2.0
		g.add_child(roof)
		var s := atan2(ridge, dv / 2.0)
		var sl := sqrt(dv * dv / 4.0 + ridge * ridge)
		var lw := du * 0.92
		var lh := minf(sl * 0.86, lw / 2.0)
		var decal := MeshInstance3D.new()
		var dq := QuadMesh.new()
		dq.size = Vector2(lw, lh)
		decal.mesh = dq
		decal.material_override = _unshaded_tex(roof_tex)
		decal.position = Vector3(0, wall_h + ridge / 2.0 + 0.12, dv / 4.0)
		decal.rotation.x = s - PI / 2.0
		decal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.add_child(decal)
		var front := MeshInstance3D.new()
		var fq := QuadMesh.new()
		fq.size = Vector2(du, wall_h)
		front.mesh = fq
		front.material_override = _unshaded_tex(_hangar_front(du, wall_h))
		front.position = Vector3(0, wall_h / 2.0, dv / 2.0 + 0.06)
		front.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.add_child(front)
		_place(g, b["u"], b["v"])
	_runway_decal()
	# parked aircraft on the apron
	var rows := [["trainer", -330.0, -140.0, 40.0], ["fighter", -250.0, -125.0, -20.0], ["trainer", -170.0, -145.0, 70.0], ["fighter", -80.0, -130.0, 15.0], ["trainer", 20.0, -150.0, -50.0], ["fighter", 140.0, -140.0, 95.0]]
	for r in rows:
		var a := AircraftModel.new()
		a.build(r[0], logo if r[0] == "trainer" else logo_dark, false)
		a.set_cockpit_view(false)
		var piv := Node3D.new()
		piv.add_child(a)
		a.rotation.x = 0.085 if r[0] == "fighter" else 0.0
		_place(piv, r[1], r[2], 0.97 if r[0] == "trainer" else 1.38, deg_to_rad(r[3]))


func _runway_decal() -> void:
	var L := Terrain.RW_LEN
	var wm := 46.0
	var W := 128
	var H := 4096
	var ppm := H / L
	var img := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var white := Color("#ecebe6")
	var X := func(v: float) -> int: return int((v + wm / 2.0) * ppm)
	var Y := func(u: float) -> int: return int((L / 2.0 - u) * ppm)
	var px := W / wm
	var u := -L / 2.0 + 70.0
	while u < L / 2.0 - 70.0:
		img.fill_rect(Rect2i(int((-0.45 + wm / 2.0) * px), Y.call(u + 30.0), maxi(1, int(0.9 * px)), int(30.0 * ppm)), white)
		u += 50.0
	img.fill_rect(Rect2i(int((-21.8 + wm / 2.0) * px), 0, maxi(1, int(0.4 * px)), H), white)
	img.fill_rect(Rect2i(int((21.45 + wm / 2.0) * px), 0, maxi(1, int(0.4 * px)), H), white)
	for sgn in [-1.0, 1.0]:
		var base: float = sgn * (L / 2.0)
		for k in range(-8, 9):
			if k == 0:
				continue
			var y0: int = Y.call(base - sgn * 6.0) if sgn < 0 else Y.call(base - sgn * 6.0 + 0.0) - int(30.0 * ppm)
			img.fill_rect(Rect2i(int((k * 2.4 - 0.7 + wm / 2.0) * px), y0, maxi(1, int(1.4 * px)), int(30.0 * ppm)), white)
		for d in [300.0, 450.0]:
			for dv in [-9.0, 9.0]:
				var yy: int = Y.call(base - sgn * d)
				if sgn > 0:
					yy -= int(22.0 * ppm)
				img.fill_rect(Rect2i(int((dv - 1.5 + wm / 2.0) * px), yy, maxi(1, int(3.0 * px)), int(22.0 * ppm)), white)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.4
	m.roughness = 0.9
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var mi := MeshInstance3D.new()
	var pl := PlaneMesh.new()
	pl.size = Vector2(wm, L)   # x across, z along
	mi.mesh = pl
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var g := Node3D.new()
	g.add_child(mi)
	mi.rotation.y = PI / 2.0   # plane z axis -> along the runway (local x of the placed node)
	mi.scale = Vector3(1, 1, -1)
	_place(g, 0.0, 0.0, 0.1)
	for e in [[-1.0, "06"], [1.0, "24"]]:
		var lb := Label3D.new()
		lb.text = e[1]
		lb.font = load("res://assets/fonts/BarlowSemiCondensed-ExtraBoldItalic.ttf")
		lb.font_size = 200
		lb.pixel_size = 0.05
		lb.modulate = white
		lb.double_sided = false
		lb.rotation_degrees = Vector3(-90, 0, 0)
		lb.shaded = false
		var gg := Node3D.new()
		gg.add_child(lb)
		_place(gg, float(e[0]) * (L / 2.0 - 60.0), 0.0, 0.14)
		# text 'up' points along the direction a pilot lands (towards the far end)
		var up_dir: Vector2 = terrain.dir * (-float(e[0]))
		gg.rotation.y = atan2(-up_dir.x, -up_dir.y)


# ---------------------------------------------------------------- scenery
var cloud_mat: StandardMaterial3D


func _in_road(p: Vector2, pad: float) -> bool:
	for r in Terrain.ROADS:
		var pts: Array = r["pts"]
		for i in range(pts.size() - 1):
			if Terrain.dist_to_segment(p, Vector2(pts[i][0], pts[i][1]), Vector2(pts[i + 1][0], pts[i + 1][1])) < float(r["w"]) / 2.0 + pad:
				return true
	var rp: Array = Terrain.RIVER["pts"]
	for i in range(rp.size() - 1):
		if Terrain.dist_to_segment(p, Vector2(rp[i][0], rp[i][1]), Vector2(rp[i + 1][0], rp[i + 1][1])) < float(Terrain.RIVER["w"]) / 2.0 + 6.0:
			return true
	return false


func _house_mesh() -> ArrayMesh:
	var k := MeshKit.new()
	var wcol := Color(0.92, 0.88, 0.8).srgb_to_linear()
	var rcol := Color(0.55, 0.22, 0.16).srgb_to_linear()
	var p := [Vector3(-0.5, 0, 0.5), Vector3(0.5, 0, 0.5), Vector3(0.5, 1, 0.5), Vector3(-0.5, 1, 0.5), Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, 1, -0.5), Vector3(-0.5, 1, -0.5)]
	k.add_quad(p[0], p[1], p[2], p[3], Vector3(0, 0, 1), wcol)
	k.add_quad(p[5], p[4], p[7], p[6], Vector3(0, 0, -1), wcol)
	k.add_quad(p[1], p[5], p[6], p[2], Vector3(1, 0, 0), wcol)
	k.add_quad(p[4], p[0], p[3], p[7], Vector3(-1, 0, 0), wcol)
	var ra := Vector3(-0.5, 1.6, 0)
	var rb := Vector3(0.5, 1.6, 0)
	k.add_quad(p[3], p[2], rb, ra, Vector3(0, 0.6, 0.8).normalized(), rcol)
	k.add_quad(p[6], p[7], ra, rb, Vector3(0, 0.6, -0.8).normalized(), rcol)
	k.add_tri(p[2], p[6], rb, Vector3.RIGHT, wcol)
	k.add_tri(p[7], p[3], ra, Vector3.LEFT, wcol)
	return k.build()


func _scenery() -> void:
	var q: float = {"low": 0.4, "medium": 0.8, "high": 1.0}.get(quality, 0.8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var houses: Array = []
	var trees: Array = []
	for vi in range(8):
		var v: Dictionary = Terrain.VILLAGES[vi]
		var n := int(PI * float(v["r"]) * float(v["r"]) / 2300.0 * q)
		for k in n:
			var a := rng.randf() * TAU
			var rr := sqrt(rng.randf()) * float(v["r"]) * 0.85
			var p := Vector2(v["x"] + cos(a) * rr, v["z"] + sin(a) * rr)
			if _in_road(p, 5.0):
				continue
			houses.append([p.x, p.y, 7.0 + rng.randf() * 7.0, 4.0 + rng.randf() * 2.5, 6.0 + rng.randf() * 5.0, rng.randf() * PI])
	for w in Terrain.WOODS:
		var wx: float = w[0]
		var wz: float = w[1]
		var wr: float = w[2]
		var sp := 26.0 / sqrt(q)
		var gx := -wr
		while gx <= wr:
			var gz := -wr
			while gz <= wr:
				var p2 := Vector2(wx + gx + (rng.randf() - 0.5) * sp * 0.8, wz + gz + (rng.randf() - 0.5) * sp * 0.8)
				var d := p2.distance_to(Vector2(wx, wz))
				if d <= wr * 0.82 and not _in_road(p2, 8.0):
					trees.append([p2.x, p2.y, 3.0 + rng.randf() * 2.5, 8.0 + rng.randf() * 9.0])
				gz += sp
			gx += sp
	var hm := MultiMesh.new()
	hm.transform_format = MultiMesh.TRANSFORM_3D
	hm.use_colors = true
	hm.mesh = _house_mesh()
	hm.instance_count = houses.size()
	for i in houses.size():
		var h: Array = houses[i]
		var b := Basis.from_euler(Vector3(0, h[5], 0)).scaled(Vector3(h[2], h[3], h[4]))
		hm.set_instance_transform(i, Transform3D(b, Vector3(h[0], terrain.height(h[0], h[1]), h[1])))
		var s := 0.85 + rng.randf() * 0.3
		hm.set_instance_color(i, Color(s, s, s))
	var hmi := MultiMeshInstance3D.new()
	hmi.multimesh = hm
	var hmat := StandardMaterial3D.new()
	hmat.vertex_color_use_as_albedo = true
	hmat.roughness = 0.9
	hmi.material_override = hmat
	hmi.visibility_range_end = 9000.0
	add_child(hmi)
	var tm := MultiMesh.new()
	tm.transform_format = MultiMesh.TRANSFORM_3D
	tm.use_colors = true
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.5
	cone.height = 1.0
	cone.radial_segments = 7
	cone.rings = 1
	tm.mesh = cone
	tm.instance_count = trees.size()
	for i in trees.size():
		var t: Array = trees[i]
		var b2 := Basis.from_euler(Vector3(0, rng.randf() * 6.0, 0)).scaled(Vector3(t[2], t[3], t[2]))
		tm.set_instance_transform(i, Transform3D(b2, Vector3(t[0], terrain.height(t[0], t[1]) + t[3] * 0.5 - 0.5, t[1])))
		tm.set_instance_color(i, Color(0.1 + rng.randf() * 0.1, 0.28 + rng.randf() * 0.18, 0.1 + rng.randf() * 0.08).srgb_to_linear())
	var tmi := MultiMeshInstance3D.new()
	tmi.multimesh = tm
	var tmat := StandardMaterial3D.new()
	tmat.vertex_color_use_as_albedo = true
	tmat.roughness = 1.0
	tmi.material_override = tmat
	tmi.visibility_range_end = 7000.0
	add_child(tmi)


func _clouds() -> void:
	var img := Image.create_empty(128, 128, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var blobs: Array = []
	for i in 9:
		blobs.append([40.0 + rng.randf() * 48.0, 50.0 + rng.randf() * 28.0, 18.0 + rng.randf() * 20.0])
	for y in 128:
		for x in 128:
			var a := 0.0
			for b in blobs:
				var d := Vector2(x - float(b[0]), y - float(b[1])).length() / float(b[2])
				if d < 1.0:
					a += 0.55 * (1.0 - d) * (1.0 - d)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	var tex := ImageTexture.create_from_image(img)
	cloud_mat = StandardMaterial3D.new()
	cloud_mat.albedo_texture = tex
	cloud_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cloud_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cloud_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	cloud_mat.billboard_keep_scale = true
	cloud_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cloud_mat.disable_fog = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 0.55)
	var n: int = {"low": 40, "medium": 90, "high": 140}.get(quality, 90)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	var items: Array = []
	var r2 := RandomNumberGenerator.new()
	r2.seed = 21
	for i in n:
		var cx := (r2.randf() - 0.5) * 30000.0
		var cz := (r2.randf() - 0.5) * 30000.0
		var cy := 1100.0 + r2.randf() * 700.0
		var k := 3 + int(floor(r2.randf() * 4.0))
		for j in k:
			var w := 350.0 + r2.randf() * 550.0
			items.append([Vector3(cx + (r2.randf() - 0.5) * 700.0, cy + (r2.randf() - 0.5) * 80.0, cz + (r2.randf() - 0.5) * 700.0), w])
	mm.instance_count = items.size()
	for i in items.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3(items[i][1], items[i][1], 1.0)), items[i][0]))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = cloud_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 40000.0
	add_child(mmi)


func _blimp() -> void:
	var img := Image.create_empty(512, 512, false, Image.FORMAT_RGBA8)
	img.fill(Color("#02022f"))
	img.fill_rect(Rect2i(0, 0, 512, 30), Color("#ff4c00"))
	img.fill_rect(Rect2i(0, 482, 512, 30), Color("#ff4c00"))
	var lg := logo_dark.get_image()
	if lg.is_compressed():
		lg.decompress()
	lg.convert(Image.FORMAT_RGBA8)
	lg.resize(150, 60, Image.INTERPOLATE_LANCZOS)
	for ux in [60, 316]:
		img.blend_rect(lg, Rect2i(0, 0, 150, 60), Vector2i(ux, 226))
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.roughness = 0.5
	blimp = Node3D.new()
	var body := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 32
	sm.rings = 16
	body.mesh = sm
	body.material_override = m
	body.scale = Vector3(8, 8, 26)
	body.rotation.y = PI / 2.0
	blimp.add_child(body)
	var gon := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(2.4, 2, 6)
	gon.mesh = gm
	gon.position.y = -8.8
	blimp.add_child(gon)
	for k in 4:
		var f := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(0.4, 6, 7)
		f.mesh = fm
		var om := StandardMaterial3D.new()
		om.albedo_color = Color("#ff4c00").srgb_to_linear()
		f.material_override = om
		f.position = Vector3(cos(k * PI / 2.0) * 4.0, sin(k * PI / 2.0) * 4.0, 22.0)
		f.rotation.z = k * PI / 2.0
		blimp.add_child(f)
	add_child(blimp)


func _gates() -> void:
	gate_group.visible = false
	add_child(gate_group)
	for g in Terrain.GATES:
		gates.append({"x": float(g[0]), "z": float(g[1]), "y": terrain.height(g[0], g[1]) + g[2], "nx": 0.0, "nz": -1.0, "r": 48.0})
	for i in gates.size():
		var ref: Dictionary = gates[i + 1] if i < gates.size() - 1 else gates[i - 1]
		var dx: float = ref["x"] - gates[i]["x"]
		var dz: float = ref["z"] - gates[i]["z"]
		if i == gates.size() - 1:
			dx = -dx
			dz = -dz
		var l := sqrt(dx * dx + dz * dz)
		gates[i]["nx"] = dx / l
		gates[i]["nz"] = dz / l
	for g in gates:
		var grp := Node3D.new()
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = g["r"] - 2.6
		tm.outer_radius = g["r"] + 2.6
		tm.rings = 48
		tm.ring_segments = 8
		ring.mesh = tm
		ring.rotation.x = PI / 2.0
		var om := StandardMaterial3D.new()
		om.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		om.albedo_color = Color("#ff4c00")
		ring.material_override = om
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		grp.add_child(ring)
		var inner := MeshInstance3D.new()
		var tm2 := TorusMesh.new()
		tm2.inner_radius = g["r"] - 5.2
		tm2.outer_radius = g["r"] - 3.8
		tm2.rings = 48
		tm2.ring_segments = 6
		inner.mesh = tm2
		inner.rotation.x = PI / 2.0
		var im := StandardMaterial3D.new()
		im.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		inner.material_override = im
		inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		grp.add_child(inner)
		grp.position = Vector3(g["x"], g["y"], g["z"])
		grp.rotation.y = atan2(g["nx"], g["nz"])
		gate_group.add_child(grp)
		gate_nodes.append({"grp": grp, "ring": om, "inner": inner})


func set_gates(active: bool, next: int) -> void:
	gate_group.visible = active
	for i in gate_nodes.size():
		var m: Dictionary = gate_nodes[i]
		var done := i < next
		var cur := i == next
		(m["ring"] as StandardMaterial3D).albedo_color = Color("#4cc283") if done else (Color("#ff4c00") if cur else Color("#1b2a8a"))
		(m["grp"] as Node3D).scale = Vector3.ONE * (1.08 if cur else 1.0)
		(m["grp"] as Node3D).visible = (not done) or i >= next - 2
		(m["inner"] as Node3D).visible = cur


# ---------------------------------------------------------------- per frame
func update_world(dt: float, cam_pos: Vector3) -> void:
	follow(cam_pos)
	if blimp != null:
		blimp_t += dt
		var a := blimp_t * 0.0125
		var cx := -300.0
		var cz := -900.0
		var r := 700.0
		var x := cx + cos(a) * r
		var z := cz + sin(a) * r
		blimp.position = Vector3(x, terrain.height(x, z) + 380.0 + sin(blimp_t * 0.2) * 6.0, z)
		blimp.rotation.y = atan2(sin(a), -cos(a))
	if windsock != null and (wind.x != 0.0 or wind.z != 0.0):
		windsock.rotation.y = atan2(-wind.z, wind.x)
