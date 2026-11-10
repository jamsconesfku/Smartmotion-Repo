class_name World
extends Node3D
## SmartMotion Flight: the world. Sky, lighting, terrain, the Duxford airfield with SmartMotion signs,
## villages, woods, clouds, a blimp and the gate course. Everything is built from code.

const TOD := {
	"day": {"el": 46.0, "az": 205.0, "sun": Color(1, 0.96, 0.88), "top": Color(0.14, 0.36, 0.78), "hor": Color(0.74, 0.84, 0.95), "amb": 0.9, "sun_e": 1.6, "fog": 0.000034, "shade": Color(0.6, 0.66, 0.77)},
	"golden": {"el": 9.0, "az": 252.0, "sun": Color(1, 0.62, 0.32), "top": Color(0.12, 0.2, 0.5), "hor": Color(0.97, 0.74, 0.56), "amb": 0.7, "sun_e": 1.7, "fog": 0.00006, "shade": Color(0.55, 0.45, 0.52)},
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
var scenery: RealScenery
var ortho_tex: Texture2D
var focus := Vector2.ZERO
var _coll_t := 0.0
var vol_mat: ShaderMaterial
var vol_mi: MeshInstance3D
var cloud_cards: MultiMeshInstance3D
var cloud_off := Vector2.ZERO
var vr_mode := false
const CLOUD_WIND := Vector2(7.0, 2.5)   # m/s the clouds drift


func _yaw_of(d: Vector2) -> float:
	return atan2(-d.y, d.x)   # rotates local +X onto the world direction d (x, z)


func _lin(c: Color) -> Color:
	return c.srgb_to_linear()


func build(progress: Callable, quality_: String, tod: String) -> void:
	quality = quality_
	var t0 := Time.get_ticks_msec()
	var lap := func(what: String) -> void: Diag.write("load: %s at %.1f s" % [what, (Time.get_ticks_msec() - t0) / 1000.0])
	terrain = Terrain.new()
	logo = load("res://assets/logo.png")
	logo_dark = load("res://assets/logo-dark.png")
	progress.call(0.08, "Lighting the sky")
	_environment()
	progress.call(0.15, "Laying out the real countryside")
	lap.call('Laying out the real countryside')
	await _ground()
	progress.call(0.45, "Building Duxford")
	lap.call('Building Duxford')
	await _airfield()
	progress.call(0.55, "Loading 129,000 real buildings")
	lap.call('Loading 129,000 real buildings')
	await get_tree().process_frame
	scenery = RealScenery.new()
	add_child(scenery)
	scenery.setup(terrain, quality, ortho_tex)
	progress.call(0.75, "Planting the woods")
	lap.call('Planting the woods')
	await get_tree().process_frame
	scenery.preload_around(Vector2.ZERO)
	progress.call(0.92, "Hanging the signs")
	lap.call('Hanging the signs')
	await _signs()
	await _clouds()
	await _volumetric_clouds()
	_blimp()
	_gates()
	set_time_of_day(tod)
	progress.call(1.0, "Ready")
	lap.call('Ready')


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
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 8.0
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.35   # distant land takes on the colour of the sky behind it
	env.fog_sun_scatter = 0.12
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.1
	env.ssao_enabled = quality != "low"
	env.ssao_radius = 2.5
	env.ssao_intensity = 1.6
	env.ssil_enabled = quality == "high"   # light bouncing between nearby surfaces
	env.ssil_radius = 6.0
	env.ssil_intensity = 0.8
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.16
	env.adjustment_contrast = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = quality != "low"
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 3500.0
	sun.directional_shadow_blend_splits = true
	sun.light_angular_distance = 0.5 if quality == "high" else 0.0   # soft shadow edges
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
	if cloud_mat != null:
		var tint: Color = Color(1, 1, 1).lerp(t["sun"], 0.35)
		var sh: Color = t["shade"]
		cloud_mat.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
		cloud_mat.set_shader_parameter("shade", Vector3(sh.r, sh.g, sh.b))
		cloud_mat.set_shader_parameter("sun_col", Vector3(t["sun"].r, t["sun"].g, t["sun"].b))
		cloud_mat.set_shader_parameter("sun_dir", sd)
	for m in ground_mats:
		(m as ShaderMaterial).set_shader_parameter("shadow_shift", Vector2(sd.x, sd.z) / maxf(sd.y, 0.1) * 1500.0)
	if vol_mat != null:
		vol_mat.set_shader_parameter("sun_dir", sd)
		vol_mat.set_shader_parameter("sun_col", Vector3(t["sun"].r, t["sun"].g, t["sun"].b))
		vol_mat.set_shader_parameter("sun_energy", float(t["sun_e"]) * 1.15)
		var top: Color = t["top"]
		var hor: Color = t["hor"]
		var shd: Color = t["shade"]
		vol_mat.set_shader_parameter("amb_top", Vector3(top.r, top.g, top.b).lerp(Vector3(hor.r, hor.g, hor.b), 0.5) * 0.9)
		vol_mat.set_shader_parameter("amb_bottom", Vector3(shd.r, shd.g, shd.b) * 0.62)
		vol_mat.set_shader_parameter("haze_col", Vector3(hor.r, hor.g, hor.b))
		vol_mat.set_shader_parameter("haze", float(t["fog"]))


## 3D clouds (Forward+ renderer, not in VR): a full-screen raymarch. The flat cloud cards are the fallback.
func _volumetric_clouds() -> void:
	if quality == "low" or RenderingServer.get_current_rendering_method() != "forward_plus":
		return
	var wn := FastNoiseLite.new()
	wn.noise_type = FastNoiseLite.TYPE_PERLIN
	wn.seed = 4
	wn.frequency = 0.011
	wn.fractal_octaves = 4
	var weather := NoiseTexture2D.new()
	weather.width = 512
	weather.height = 512
	weather.seamless = true
	weather.normalize = true
	weather.generate_mipmaps = true
	weather.noise = wn
	var sn := FastNoiseLite.new()
	sn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	sn.seed = 8
	sn.frequency = 0.07
	sn.fractal_octaves = 3
	var shape := NoiseTexture3D.new()
	shape.width = 64
	shape.height = 64
	shape.depth = 64
	shape.seamless = true
	shape.normalize = true
	shape.noise = sn
	var dn := FastNoiseLite.new()
	dn.noise_type = FastNoiseLite.TYPE_CELLULAR
	dn.seed = 15
	dn.frequency = 0.16
	dn.fractal_type = FastNoiseLite.FRACTAL_FBM
	dn.fractal_octaves = 2
	var detail := NoiseTexture3D.new()
	detail.width = 32
	detail.height = 32
	detail.depth = 32
	detail.seamless = true
	detail.normalize = true
	detail.invert = true
	detail.noise = dn
	# the noise is made on another thread: wait until each texture has its pixels (at most about 10 s)
	for k in 600:
		if weather.get_image() != null and shape.get_data().size() > 0 and detail.get_data().size() > 0:
			break
		await get_tree().process_frame
	vol_mat = ShaderMaterial.new()
	vol_mat.shader = load("res://shaders/clouds_volumetric.gdshader")
	vol_mat.set_shader_parameter("weather", weather)
	vol_mat.set_shader_parameter("shape_noise", shape)
	vol_mat.set_shader_parameter("detail_noise", detail)
	vol_mat.set_shader_parameter("steps", 72 if quality == "high" else 44)
	vol_mat.set_shader_parameter("light_steps", 5 if quality == "high" else 4)
	vol_mat.set_shader_parameter("coverage", 0.48)
	vol_mi = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1, 1)
	vol_mi.mesh = qm
	vol_mi.material_override = vol_mat
	vol_mi.extra_cull_margin = 16384.0
	vol_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(vol_mi)
	for m in ground_mats:
		(m as ShaderMaterial).set_shader_parameter("cloud_map", weather)
		(m as ShaderMaterial).set_shader_parameter("cloud_cover", 0.48)
		(m as ShaderMaterial).set_shader_parameter("cloud_shadow", 0.38)
	_apply_cloud_mode()


## VR draws two views, so it uses the light cloud cards instead of the 3D clouds.
func set_vr_mode(on: bool) -> void:
	vr_mode = on
	if scenery != null:
		scenery.set_vr(on)
	_apply_cloud_mode()


func _apply_cloud_mode() -> void:
	var vol := vol_mi != null and not vr_mode
	if vol_mi != null:
		vol_mi.visible = vol
	if cloud_cards != null:
		cloud_cards.visible = not vol
	for m in ground_mats:
		(m as ShaderMaterial).set_shader_parameter("cloud_shadow", 0.38 if vol else 0.0)


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
	var far_px: int = {"low": 1024, "medium": 2048, "high": 2048}.get(quality, 2048)
	var far_size := far_px * 80.0
	var hm_img := Image.create_from_data(Terrain.SIZE, Terrain.SIZE, false, Image.FORMAT_RF, terrain.data.to_byte_array())
	var hm_tex := ImageTexture.create_from_image(hm_img)
	var far_tex := await _paint(far_px, far_size, 3.0, 0.0)
	ortho_tex = load("res://assets/world/ortho.jpg")
	var lc_tex: Texture2D = load("res://assets/world/landcover.png")
	var shader: Shader = load("res://shaders/ground.gdshader")
	var cells := [8.0, 32.0, 128.0, 512.0, 2048.0]
	var biases := [0.0, -0.6, -2.0, -4.0, -8.0]
	var n := 128
	for k in cells.size():
		var cell: float = cells[k]
		var hole := 0
		if k > 0:
			hole = int(n / 2.0 * float(cells[k - 1]) / cell) - 2   # 2 cells of overlap so rings never part
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("heightmap", hm_tex)
		mat.set_shader_parameter("ortho", ortho_tex)
		mat.set_shader_parameter("landcover", lc_tex)
		mat.set_shader_parameter("far_map", far_tex)
		for t in ["grass", "soil", "asphalt", "concrete"]:
			mat.set_shader_parameter(t + "_col", load("res://assets/textures/%s_col.jpg" % t))
			mat.set_shader_parameter(t + "_nrm", load("res://assets/textures/%s_nrm.jpg" % t))
		mat.set_shader_parameter("cell", Terrain.CELL)
		mat.set_shader_parameter("size_cells", float(Terrain.SIZE))
		mat.set_shader_parameter("half_size", Terrain.LEN / 2.0)
		mat.set_shader_parameter("far_size", far_size)
		mat.set_shader_parameter("y_bias", biases[k])
		mat.set_shader_parameter("rw", Vector4(terrain.dir.x, terrain.dir.y, Terrain.RW_LEN, Terrain.RW_WIDTH))
		ground_mats.append(mat)
		var mi := MeshInstance3D.new()
		mi.mesh = _ring_mesh(cell, n, hole)
		mi.material_override = mat
		mi.extra_cull_margin = 4000.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if k > 1 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mi)
		rings.append({"node": mi, "snap": cell * 2.0})


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
	_runway_decal()
	# parked aircraft on the apron
	var rows := [["bulldog", -330.0, -140.0, 40.0], ["fighter", -250.0, -125.0, -20.0], ["bulldog", -170.0, -145.0, 70.0], ["fighter", -80.0, -130.0, 15.0], ["bulldog", 20.0, -150.0, -50.0], ["fighter", 140.0, -140.0, 95.0]]
	for r in rows:
		var a := AircraftModel.new()
		a.build(r[0], logo if r[0] == "trainer" else logo_dark, false)
		a.set_cockpit_view(false)
		var piv := Node3D.new()
		piv.add_child(a)
		a.rotation.x = 0.085 if r[0] == "fighter" else 0.0
		_place(piv, r[1], r[2], 1.03 if r[0] == "bulldog" else 1.38, deg_to_rad(r[3]))


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
		lb.outline_size = 0
		var gg := Node3D.new()
		gg.add_child(lb)
		_place(gg, float(e[0]) * (L / 2.0 - 60.0), 0.0, 0.14)
		# text 'up' points along the direction a pilot lands (towards the far end)
		var up_dir: Vector2 = terrain.dir * (-float(e[0]))
		gg.rotation.y = atan2(-up_dir.x, -up_dir.y)


# ---------------------------------------------------------------- scenery
var cloud_mat: ShaderMaterial


func _cloud_atlas() -> Texture2D:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/cloud_paint.gdshader")
	var vp := SubViewport.new()
	vp.size = Vector2i(1024, 1024)
	vp.disable_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.size = Vector2(1024, 1024)
	rect.material = mat
	vp.add_child(rect)
	add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		img = Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _clouds() -> void:
	cloud_mat = ShaderMaterial.new()
	cloud_mat.shader = load("res://shaders/cloud.gdshader")
	cloud_mat.set_shader_parameter("atlas", await _cloud_atlas())
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var n: int = {"low": 40, "medium": 90, "high": 150}.get(quality, 90)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	var items: Array = []
	var r2 := RandomNumberGenerator.new()
	r2.seed = 21
	for i in n:
		var cx := (r2.randf() - 0.5) * 30000.0
		var cz := (r2.randf() - 0.5) * 30000.0
		var cy := 1050.0 + r2.randf() * 650.0
		var size := 0.7 + r2.randf() * 0.8
		# each cloud is a few overlapping cards: a wide base and smaller tops
		var k := 4 + int(floor(r2.randf() * 4.0))
		for j in k:
			var up := float(j) / float(k)
			var w := (520.0 + r2.randf() * 420.0) * size * (1.0 - up * 0.45)
			var spread := 520.0 * size * (1.0 - up * 0.5)
			items.append([Vector3(cx + (r2.randf() - 0.5) * spread, cy + up * 160.0 * size + w * 0.22, cz + (r2.randf() - 0.5) * spread), w, float(r2.randi() % 4)])
	mm.instance_count = items.size()
	for i in items.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3(items[i][1], items[i][1], 1.0)), items[i][0]))
		mm.set_instance_custom_data(i, Color(items[i][2], 0, 0, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = cloud_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 40000.0
	add_child(mmi)
	cloud_cards = mmi


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
	cloud_off += CLOUD_WIND * dt
	if vol_mi != null:
		vol_mi.global_position = cam_pos
		vol_mat.set_shader_parameter("offset", cloud_off)
		for m in ground_mats:
			(m as ShaderMaterial).set_shader_parameter("cloud_offset", cloud_off)
	if scenery != null:
		scenery.update(Vector2(cam_pos.x, cam_pos.z), 1)
		_coll_t -= dt
		if _coll_t <= 0.0:
			_coll_t = 0.2
			terrain.colliders = scenery.colliders_near(focus)
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
