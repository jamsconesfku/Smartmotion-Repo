class_name SpaceMode
extends GameMode
## SmartMotion Space: fly a space fighter round a space station in an asteroid field, with a ringed gas giant
## and a moon in the sky, and shoot down waves of enemy drones. Shields recharge, the hull doesn't.
## Easy mode: aim help on the guns and the ship rolls itself upright when you let go. Pro: neither.

signal sfx(kind: String)

const STATION := Vector3(0, 0, -900)
const RING_R := 160.0
const RING_TUBE := 16.0
const HUB_R := 34.0
const PLANET := Vector3(-38000, -9000, -52000)
const PLANET_R := 24000.0
const MOON := Vector3(9000, 2600, -16000)
const MOON_R := 2600.0
const BOLT_SPEED := 950.0
const CELL := 250.0

var ship: SpaceShip
var sun: DirectionalLight3D
var sun_dir := Vector3(0.55, 0.32, 0.77).normalized()
var station: Node3D
var station_spin := 0.0
var q := Quaternion.IDENTITY
var pos := Vector3.ZERO
var vel := Vector3.ZERO
var wv := Vector3.ZERO
var thr := 0.5
var boost_e := 1.0
var boosting := false
var hull := 100.0
var shield := 100.0
var shield_t := 0.0
var score := 0
var best := 0
var wave := 0
var wave_t := 0.0
var dead := false
var dead_t := 0.0
var assist := true
var fire_cd := 0.0
var gun_side := 0
var firing := false
var acc_body := Vector3(0, 9.81, 0)
var prev_vel := Vector3.ZERO
var enemies: Array = []
var bolts: Array = []
var rocks: Array = []           # [position, radius]
var rock_grid := {}
var booms: Array = []
var boom_i := 0
var stars: MultiMeshInstance3D
var dust: MultiMeshInstance3D
var dust_pos: Array = []
var bracket: MeshInstance3D
var bracket_lbl: Label3D
var target: Dictionary = {}
var drone_parts: Array = []     # [mesh, material, transform] to build a drone
var bolt_mesh_p: Mesh
var bolt_mesh_e: Mesh
var bolt_mat_p: Material
var bolt_mat_e: Material
var cam_q := Quaternion.IDENTITY
var cam_init := false
var msg := ""
var msg_t := 0.0
var fx_shader: Shader
var t_total := 0.0


func mode_name() -> String:
	return "space"


func build(w: World, qual: String) -> void:
	super.build(w, qual)
	fx_shader = load("res://shaders/space_fx.gdshader")
	var sky_tex := await _paint(0, Vector2i(4096, 2048) if qual != "low" else Vector2i(2048, 1024))
	var planet_tex := await _paint(1, Vector2i(2048, 1024))
	var moon_tex := await _paint(2, Vector2i(1024, 512))
	var ring_tex := await _paint(3, Vector2i(1024, 4))
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var pm := PanoramaSkyMaterial.new()
	pm.panorama = sky_tex
	pm.filter = true
	sky.sky_material = pm
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.16, 0.17, 0.26)
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.1
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.85
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.95
	env.ssao_enabled = qual != "low"
	env.ssao_radius = 2.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.06
	sun = DirectionalLight3D.new()
	sun.basis = Basis.looking_at(-sun_dir, Vector3.UP)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 2.3
	sun.shadow_enabled = qual != "low"
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 450.0
	sun.directional_shadow_split_1 = 0.1
	sun.shadow_bias = 0.05
	add_child(sun)
	_sun_glow()
	_planet(planet_tex, ring_tex)
	_moon(moon_tex)
	await _station()
	_asteroids(qual)
	_stars()
	_dust()
	_drone_template()
	_bolt_assets()
	_booms()
	_bracket()
	ship = SpaceShip.new()
	add_child(ship)
	vehicle = ship
	eye = SpaceShip.EYE


func _paint(mode: int, size: Vector2i) -> Texture2D:
	var vp := SubViewport.new()
	vp.size = size
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.transparent_bg = mode == 3
	var rect := ColorRect.new()
	rect.size = Vector2(size)
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/space_paint.gdshader")
	m.set_shader_parameter("mode", mode)
	rect.material = m
	vp.add_child(rect)
	add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		img = Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.02, 0.02, 0.05))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func fx_mat(kind: int, col: Color, energy: float, falloff := 2.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = fx_shader
	m.set_shader_parameter("kind", kind)
	m.set_shader_parameter("color", col)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("falloff", falloff)
	m.set_shader_parameter("sun_dir", sun_dir)
	return m


func _quad(size: float, m: Material, p: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(size, size)
	mi.mesh = qm
	mi.material_override = m
	mi.position = p
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0
	add_child(mi)
	return mi


func _sun_glow() -> void:
	_quad(16000.0, fx_mat(0, Color(1.0, 0.9, 0.7), 3.0, 1.6), sun_dir * 110000.0)
	_quad(70000.0, fx_mat(0, Color(1.0, 0.55, 0.25), 0.35, 3.0), sun_dir * 115000.0)


func _planet(tex: Texture2D, ring_tex: Texture2D) -> void:
	# tilted so the rings are seen open from the battle area
	var tilt := Basis(Quaternion(Vector3.UP, Vector3(0.35, 0.8, 0.5).normalized()))
	var root := Node3D.new()
	root.transform = Transform3D(tilt, PLANET)
	add_child(root)
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 96
	sm.rings = 48
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = Color(0.72, 0.72, 0.72)
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mi.material_override = m
	mi.scale = Vector3.ONE * PLANET_R
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var atm := MeshInstance3D.new()
	atm.mesh = sm
	atm.material_override = fx_mat(3, Color(0.95, 0.75, 0.55), 0.7, 4.0)
	atm.scale = Vector3.ONE * PLANET_R * 1.03
	atm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(atm)
	# rings: a flat band from 1.35 to 2.3 planet radii
	var segs := 160
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var nm := PackedVector3Array()
	var idx := PackedInt32Array()
	for k in segs + 1:
		var a := TAU * k / segs
		for j in 2:
			var rr := PLANET_R * (1.35 if j == 0 else 2.3)
			v.append(Vector3(cos(a) * rr, 0, sin(a) * rr))
			uv.append(Vector2(float(j), 0.5))
			nm.append(Vector3.UP)
	for k in segs:
		var a0 := k * 2
		idx.append_array([a0, a0 + 1, a0 + 3, a0, a0 + 3, a0 + 2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_NORMAL] = nm
	arr[Mesh.ARRAY_INDEX] = idx
	var rm := ArrayMesh.new()
	rm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var ring := MeshInstance3D.new()
	ring.mesh = rm
	var rmat := StandardMaterial3D.new()
	rmat.albedo_texture = ring_tex
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	rmat.roughness = 1.0
	rmat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	rmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	ring.material_override = rmat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.extra_cull_margin = 16384.0
	root.add_child(ring)


func _moon(tex: Texture2D) -> void:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 64
	sm.rings = 32
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.roughness = 1.0
	mi.material_override = m
	mi.scale = Vector3.ONE * MOON_R
	mi.position = MOON
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _station() -> void:
	station = Node3D.new()
	station.position = STATION
	add_child(station)
	var hull_m := GameMode.mat(Color(0.82, 0.83, 0.86), 0.45, 0.5)
	var dark := GameMode.mat(Color(0.15, 0.16, 0.19), 0.5, 0.6)
	var navy := GameMode.mat(Color("#02022f"), 0.4, 0.3)
	var org := GameMode.mat(Color("#ff4c00"), 0.4, 0.2)
	var pv := GameMode.mat(Color(0.05, 0.1, 0.3), 0.15, 0.8)
	# the ring (habitat) and its windows
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = RING_R - RING_TUBE
	tm.outer_radius = RING_R + RING_TUBE
	tm.rings = 96
	tm.ring_segments = 24
	ring.mesh = tm
	ring.material_override = hull_m
	station.add_child(ring)
	var wins := MultiMesh.new()
	wins.transform_format = MultiMesh.TRANSFORM_3D
	var wm := BoxMesh.new()
	wm.size = Vector3(5.0, 1.6, 0.3)
	wins.mesh = wm
	wins.instance_count = 288
	for k in 288:
		var a := TAU * (k % 96) / 96.0
		var row := k / 96
		var p := Vector3(cos(a) * (RING_R + RING_TUBE + 0.05), (row - 1) * 4.0, sin(a) * (RING_R + RING_TUBE + 0.05))
		wins.set_instance_transform(k, Transform3D(Basis(Vector3.UP, -a + PI / 2.0), p))
	var wmi := MultiMeshInstance3D.new()
	wmi.multimesh = wins
	wmi.material_override = GameMode.glow_mat(Color(1.0, 0.85, 0.55), 2.5)
	wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	station.add_child(wmi)
	# orange bands on the ring
	for k in 8:
		var a := TAU * k / 8.0
		var band := GameMode.add_cyl(station, RING_TUBE + 0.4, RING_TUBE + 0.4, 6.0, Vector3(cos(a) * RING_R, 0, sin(a) * RING_R), org if k % 2 == 0 else navy, Vector3(0, 0, 0), 24)
		band.basis = Basis(Vector3.UP, -a) * Basis(Vector3.RIGHT, PI / 2.0)
	# hub and spokes
	GameMode.add_cyl(station, HUB_R, HUB_R, 90.0, Vector3.ZERO, hull_m, Vector3.ZERO, 32)
	GameMode.add_cyl(station, HUB_R + 1.0, HUB_R + 1.0, 8.0, Vector3(0, 30, 0), navy, Vector3.ZERO, 32)
	GameMode.add_cyl(station, HUB_R + 1.0, HUB_R + 1.0, 8.0, Vector3(0, -30, 0), org, Vector3.ZERO, 32)
	GameMode.add_sphere(station, HUB_R * 0.98, Vector3(0, 45, 0), hull_m, Vector3(1, 0.5, 1), 32)
	GameMode.add_sphere(station, HUB_R * 0.98, Vector3(0, -45, 0), hull_m, Vector3(1, 0.5, 1), 32)
	for k in 4:
		var a := TAU * k / 4.0 + PI / 4.0
		var d := Vector3(cos(a), 0, sin(a))
		GameMode.add_rod(station, d * HUB_R, d * (RING_R - RING_TUBE), 5.0, dark, 12)
	# docking bay on the hub, lit
	GameMode.add_box(station, Vector3(26.0, 14.0, 4.0), Vector3(0, 0, HUB_R + 1.0), dark)
	var bay := GameMode.add_box(station, Vector3(22.0, 10.0, 0.5), Vector3(0, 0, HUB_R + 3.1), GameMode.glow_mat(Color(0.5, 0.75, 1.0), 1.6))
	bay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# solar panel masts above and below
	for sy: float in [-1.0, 1.0]:
		GameMode.add_cyl(station, 2.5, 2.5, 120.0, Vector3(0, sy * 110.0, 0), dark, Vector3.ZERO, 12)
		for k in 3:
			for sx: float in [-1.0, 1.0]:
				var panel := GameMode.add_box(station, Vector3(70.0, 0.6, 22.0), Vector3(sx * 40.0, sy * (80.0 + k * 26.0), 0), pv)
				panel.rotation.x = 0.3
				GameMode.add_box(station, Vector3(70.0, 0.8, 0.8), Vector3(sx * 40.0, sy * (80.0 + k * 26.0), 0), hull_m)
	# SmartMotion signs on the hub
	if world_ref != null:
		var tex: Texture2D = await world_ref.sign_texture(12.0, 4.0, true, true)
		var sm := StandardMaterial3D.new()
		sm.albedo_texture = tex
		sm.emission_enabled = true
		sm.emission_texture = tex
		sm.emission_energy_multiplier = 0.8
		for k in 4:
			var a := TAU * k / 4.0
			var s := MeshInstance3D.new()
			var qm := QuadMesh.new()
			qm.size = Vector2(42.0, 14.0)
			s.mesh = qm
			s.material_override = sm
			s.transform = Transform3D(Basis(Vector3.UP, a), Vector3(sin(a) * (HUB_R + 0.3), 18.0, cos(a) * (HUB_R + 0.3)))
			station.add_child(s)
	# blinking navigation lights
	for k in 12:
		var a := TAU * k / 12.0
		var col := Color(1, 0.1, 0.05) if k % 2 == 0 else Color(0.1, 1.0, 0.3)
		var l := GameMode.add_sphere(station, 1.2, Vector3(cos(a) * (RING_R + RING_TUBE + 1.0), 0, sin(a) * (RING_R + RING_TUBE + 1.0)), GameMode.glow_mat(col, 6.0), Vector3.ONE, 8)
		l.name = "nav%d" % k
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 0, HUB_R + 30.0)
	lamp.omni_range = 120.0
	lamp.light_energy = 3.0
	lamp.light_color = Color(0.6, 0.8, 1.0)
	station.add_child(lamp)


func _rock_mesh(seed_: int) -> ArrayMesh:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 24
	sm.rings = 12
	var arr := sm.get_mesh_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var noise := FastNoiseLite.new()
	noise.seed = seed_
	noise.frequency = 1.1
	noise.fractal_octaves = 4
	var squash := Vector3(1.0 + (seed_ % 3) * 0.25, 0.7 + (seed_ % 2) * 0.2, 0.85)
	for i in v.size():
		var p := v[i].normalized()
		var d := 1.0 + noise.get_noise_3dv(p * 1.6) * 0.45
		v[i] = p * d * squash
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	for i in idx:
		st.add_vertex(v[i])
	st.generate_normals()
	return st.commit()


func _asteroids(qual: String) -> void:
	var rm := StandardMaterial3D.new()
	var nt := NoiseTexture2D.new()
	var fn := FastNoiseLite.new()
	fn.frequency = 0.03
	fn.fractal_octaves = 5
	nt.noise = fn
	nt.seamless = true
	nt.width = 512
	nt.height = 512
	nt.color_ramp = Gradient.new()
	nt.color_ramp.set_color(0, Color(0.22, 0.2, 0.19))
	nt.color_ramp.set_color(1, Color(0.55, 0.5, 0.45))
	rm.albedo_texture = nt
	var nn := NoiseTexture2D.new()
	nn.noise = fn
	nn.seamless = true
	nn.as_normal_map = true
	nn.bump_strength = 6.0
	nn.width = 512
	nn.height = 512
	rm.normal_enabled = true
	rm.normal_texture = nn
	rm.uv1_triplanar = true
	rm.uv1_world_triplanar = false
	rm.uv1_scale = Vector3(0.6, 0.6, 0.6)
	rm.roughness = 0.95
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var count: int = {"low": 180, "medium": 280, "high": 380}.get(qual, 280)
	var meshes: Array = []
	for k in 5:
		meshes.append(_rock_mesh(k * 13 + 5))
	var per: Array = [[], [], [], [], []]
	while rocks.size() < count:
		var a := rng.randf() * TAU
		var rr := rng.randf_range(450.0, 3200.0)
		var p := Vector3(cos(a) * rr, rng.randf_range(-350.0, 350.0) * (0.5 + rr / 3200.0), sin(a) * rr - 400.0)
		if p.distance_to(STATION) < RING_R + 160.0 or p.distance_to(Vector3(0, 0, 300)) < 220.0:
			continue
		var r := 5.0 + 75.0 * pow(rng.randf(), 3.0)
		rocks.append([p, r])
		var b := Basis(Vector3(rng.randf() - 0.5, rng.randf() - 0.5, rng.randf() - 0.5).normalized(), rng.randf() * TAU).scaled(Vector3.ONE * r)
		per[rocks.size() % 5].append(Transform3D(b, p))
		# coarse lookup grid for collisions
		var c0 := Vector3i(floori((p.x - r) / CELL), floori((p.y - r) / CELL), floori((p.z - r) / CELL))
		var c1 := Vector3i(floori((p.x + r) / CELL), floori((p.y + r) / CELL), floori((p.z + r) / CELL))
		for x in range(c0.x, c1.x + 1):
			for y in range(c0.y, c1.y + 1):
				for z in range(c0.z, c1.z + 1):
					var key := Vector3i(x, y, z)
					if not rock_grid.has(key):
						rock_grid[key] = []
					rock_grid[key].append(rocks.size() - 1)
	for k in 5:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[k]
		mm.instance_count = per[k].size()
		for i in per[k].size():
			mm.set_instance_transform(i, per[k][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = rm
		add_child(mmi)


func _rocks_near(p: Vector3) -> Array:
	return rock_grid.get(Vector3i(floori(p.x / CELL), floori(p.y / CELL), floori(p.z / CELL)), [])


func _stars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var qm := QuadMesh.new()
	qm.size = Vector2(1, 1)
	mm.mesh = qm
	mm.instance_count = 2200
	for k in mm.instance_count:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var s := 120.0 + 260.0 * pow(rng.randf(), 6.0)
		mm.set_instance_transform(k, Transform3D(Basis().scaled(Vector3.ONE * s), d * 150000.0))
		var c := Color(0.7, 0.8, 1.0).lerp(Color(1.0, 0.8, 0.6), rng.randf())
		mm.set_instance_color(k, c * rng.randf_range(0.5, 1.0))
	stars = MultiMeshInstance3D.new()
	stars.multimesh = mm
	var m := fx_mat(0, Color.WHITE, 2.5, 3.0)
	m.set_shader_parameter("star_twinkle", 1.0)
	stars.material_override = m
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stars.extra_cull_margin = 16384.0
	add_child(stars)


func _dust() -> void:
	var rng := RandomNumberGenerator.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var qm := QuadMesh.new()
	qm.size = Vector2(0.35, 0.35)
	mm.mesh = qm
	mm.instance_count = 320
	for k in mm.instance_count:
		dust_pos.append(Vector3(rng.randf(), rng.randf(), rng.randf()) * 160.0)
	dust = MultiMeshInstance3D.new()
	dust.multimesh = mm
	dust.material_override = fx_mat(0, Color(0.7, 0.75, 0.9), 0.9, 2.0)
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dust.extra_cull_margin = 400.0
	add_child(dust)


func _drone_template() -> void:
	var body := GameMode.mat(Color(0.18, 0.18, 0.2), 0.35, 0.7)
	var red := GameMode.glow_mat(Color(1.0, 0.08, 0.05), 5.0)
	var edge := GameMode.mat(Color(0.5, 0.06, 0.05), 0.4, 0.5)
	var core := SphereMesh.new()
	core.radius = 2.2
	core.height = 4.4
	core.radial_segments = 16
	core.rings = 8
	drone_parts.append([core, body, Transform3D(Basis().scaled(Vector3(1, 0.8, 1.3)), Vector3.ZERO)])
	var eye_m := SphereMesh.new()
	eye_m.radius = 0.8
	eye_m.height = 1.6
	eye_m.radial_segments = 12
	eye_m.rings = 6
	drone_parts.append([eye_m, red, Transform3D(Basis(), Vector3(0, 0.3, -2.6))])
	for k in 3:
		var a := TAU * k / 3.0 + PI / 2.0
		var blade := BoxMesh.new()
		blade.size = Vector3(0.3, 6.5, 3.4)
		var b := Basis(Vector3.FORWARD, a) * Basis(Vector3.RIGHT, 0.15)
		drone_parts.append([blade, edge, Transform3D(b, b * Vector3(0, 3.6, 0.6))])
		var tipm := SphereMesh.new()
		tipm.radius = 0.35
		tipm.height = 0.7
		drone_parts.append([tipm, red, Transform3D(Basis(), b * Vector3(0, 6.8, 0.6))])
	var noz := CylinderMesh.new()
	noz.top_radius = 1.1
	noz.bottom_radius = 0.7
	noz.height = 1.0
	drone_parts.append([noz, red, Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, 0, 2.9))])


func _new_drone() -> Node3D:
	var n := Node3D.new()
	for p in drone_parts:
		var mi := MeshInstance3D.new()
		mi.mesh = p[0]
		mi.material_override = p[1]
		mi.transform = p[2]
		n.add_child(mi)
	add_child(n)
	return n


func _bolt_assets() -> void:
	var cm := CapsuleMesh.new()
	cm.radius = 0.22
	cm.height = 9.0
	cm.radial_segments = 8
	cm.rings = 2
	bolt_mesh_p = cm
	bolt_mesh_e = cm
	bolt_mat_p = GameMode.glow_mat(Color(1.0, 0.5, 0.12), 7.0)
	bolt_mat_e = GameMode.glow_mat(Color(1.0, 0.1, 0.2), 7.0)
	for k in 90:
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		bolts.append({"node": mi, "pos": Vector3.ZERO, "vel": Vector3.ZERO, "life": 0.0, "enemy": false})


func _booms() -> void:
	for k in 10:
		var n := Node3D.new()
		add_child(n)
		var mi := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(1, 1)
		mi.mesh = qm
		var m := fx_mat(2, Color.WHITE, 3.5, 2.0)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(mi)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.6, 0.3)
		l.omni_range = 90.0
		l.light_energy = 0.0
		n.add_child(l)
		var p := GPUParticles3D.new()
		p.one_shot = true
		p.emitting = false
		p.amount = 48
		p.lifetime = 1.4
		p.explosiveness = 1.0
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0, 0, 1)
		pm.spread = 180.0
		pm.initial_velocity_min = 25.0
		pm.initial_velocity_max = 110.0
		pm.gravity = Vector3.ZERO
		pm.damping_min = 15.0
		pm.damping_max = 35.0
		pm.scale_min = 0.4
		pm.scale_max = 1.4
		p.process_material = pm
		var sm := SphereMesh.new()
		sm.radius = 0.35
		sm.height = 0.7
		sm.radial_segments = 6
		sm.rings = 3
		sm.material = GameMode.glow_mat(Color(1.0, 0.55, 0.15), 6.0)
		p.draw_pass_1 = sm
		p.visibility_aabb = AABB(Vector3(-150, -150, -150), Vector3(300, 300, 300))
		n.add_child(p)
		n.visible = false
		booms.append({"node": n, "fire": mi, "mat": m, "light": l, "parts": p, "t": 2.0, "size": 20.0})


func _bracket() -> void:
	var img := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for k in 18:
		for t in 3:
			for c in [[k, t], [t, k], [63 - k, t], [63 - t, k], [k, 63 - t], [t, 63 - k], [63 - k, 63 - t], [63 - t, 63 - k]]:
				img.set_pixel(c[0], c[1], Color(1, 0.3, 0.1, 1))
	var tex := ImageTexture.create_from_image(img)
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.no_depth_test = true
	m.render_priority = 4
	m.albedo_color = Color(1.4, 1.4, 1.4)
	bracket = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1, 1)
	bracket.mesh = qm
	bracket.material_override = m
	bracket.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bracket.visible = false
	add_child(bracket)
	bracket_lbl = GameMode.label3d(self, "", 48, Vector3.ZERO, Color("#ff7a3d"), 0.001, false)
	bracket_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bracket_lbl.no_depth_test = true
	bracket_lbl.render_priority = 4
	bracket_lbl.visible = false


# ---------------------------------------------------------------- game
func showcase() -> void:
	super.showcase()
	_reset_ship()
	_clear()
	ship.transform = Transform3D(Basis(q), pos)


func _reset_ship() -> void:
	pos = Vector3(0, 10, 300)
	q = Quaternion.IDENTITY
	vel = Vector3(0, 0, -40)
	wv = Vector3.ZERO
	thr = 0.4
	boost_e = 1.0
	hull = 100.0
	shield = 100.0
	dead = false
	cam_init = false
	if ship != null:
		ship.visible = true


func _clear() -> void:
	for e in enemies:
		(e["node"] as Node3D).queue_free()
	enemies = []
	for b in bolts:
		b["life"] = 0.0
		(b["node"] as Node3D).visible = false
	bracket.visible = false
	bracket_lbl.visible = false


func start() -> void:
	super.start()
	assist = bool(opt("assist", true))
	_reset_ship()
	_clear()
	score = 0
	wave = 0
	wave_t = 3.0
	best = int(best_of("space_score"))
	toast.emit("Shoot the red drones before they get you. Space or right trigger: fire. W/S/A/D steer, Q/E yaw, Shift/Ctrl speed, Tab or left trigger: boost", 7.0)


func idle(dt: float) -> void:
	t_total += dt
	station_spin += dt * 0.025
	if station != null:
		station.rotation.y = station_spin
		var blink := fmod(t_total, 1.6) < 0.15
		for k in 12:
			var l := station.get_node_or_null("nav%d" % k)
			if l != null:
				(l as Node3D).visible = blink
	if not running:
		ship.animate(0.35, false, 0.0, 0.0, dt)
		pos += vel * dt * 0.1
		ship.transform = Transform3D(Basis(q), pos)


func _show(t: String, secs: float) -> void:
	msg = t
	msg_t = secs


func step(dt: float, inp: Dictionary) -> void:
	if not running:
		return
	idle(dt)
	msg_t -= dt
	if dead:
		dead_t += dt
		_update_bolts(dt)
		_update_booms(dt)
		if dead_t > 1.6 and dead_t - dt <= 1.6:
			var nb := score > best
			if nb:
				save_best("space_score", score)
			finished.emit("Ship destroyed", "Space battle over", "You reached wave %d. %s" % [wave, "New best score!" if nb else "Best score: %d" % best], str(score))
		return
	# steering: rates in the ship's frame (x pitch up, y yaw left, z roll left)
	var wt := Vector3(float(inp["pitch"]) * 1.7, -float(inp["yaw"]) * 1.0, -float(inp["roll"]) * 2.7)
	wv = wv.lerp(wt, 1.0 - exp(-dt * 6.0))
	var b := Basis(q)
	var fwd := -b.z
	if assist and absf(float(inp["roll"])) < 0.1:
		# roll gently back upright (relative to the station) when you let go of roll
		var rx := b.x.y
		wv.z -= rx * 1.4 * (1.0 - absf(fwd.y)) * dt * 6.0
	var ang := wv.length() * dt
	if ang > 0.0:
		q = (q * Quaternion(wv.normalized(), ang)).normalized()
	b = Basis(q)
	fwd = -b.z
	thr = float(inp["throttle"])
	boosting = bool(inp["boost"]) and boost_e > 0.05
	boost_e = clampf(boost_e + (-0.32 if boosting else 0.12) * dt, 0.0, 1.0)
	var target_v := lerpf(25.0, 150.0, thr)
	if boosting:
		target_v = 330.0
	prev_vel = vel
	vel = vel.lerp(fwd * target_v, 1.0 - exp(-dt * (1.3 if assist else 0.8)))
	pos += vel * dt
	var acc := (vel - prev_vel) / maxf(dt, 0.001)
	acc_body = acc_body.lerp(b.inverse() * acc + Vector3(0, 9.81, 0), 1.0 - exp(-dt * 10.0))
	_collide()
	# guns
	fire_cd -= dt
	firing = bool(inp["fire"])
	if firing and fire_cd <= 0.0:
		fire_cd = 0.1
		var gp: Vector3 = ship.guns[gun_side]
		gun_side = 1 - gun_side
		var from := Transform3D(b, pos) * gp
		var dir := fwd
		var tgt: Variant = _aim_target(pos, fwd, 0.07 if assist else 0.0)
		if tgt != null:
			var e: Dictionary = tgt
			var ep: Vector3 = e["pos"]
			var t_hit := ep.distance_to(from) / BOLT_SPEED
			dir = ((ep + (e["vel"] as Vector3) * t_hit) - from).normalized()
		else:
			# converge the two guns on a point 400 m ahead
			dir = ((pos + fwd * 400.0) - from).normalized()
		_spawn_bolt(from, dir * BOLT_SPEED + vel, false)
		sfx.emit("laser")
	# shields recharge 3 s after the last hit
	shield_t -= dt
	if shield_t <= 0.0:
		shield = minf(100.0, shield + 12.0 * dt)
	_update_enemies(dt)
	_update_bolts(dt)
	_update_booms(dt)
	# waves
	if enemies.is_empty():
		wave_t -= dt
		if wave_t <= 0.0:
			wave += 1
			_spawn_wave()
			_show("WAVE %d" % wave, 2.0)
			wave_t = 4.0
	ship.transform = Transform3D(b, pos)
	ship.animate(thr, boosting, float(inp["pitch"]), float(inp["roll"]), dt)
	_update_target()
	_holo()
	make_tel(t_total, false, dead, b, pos, vel, wv, acc_body, vel.length() * 1.94384, {"speed_ms": snappedf(vel.length(), 0.1), "score": score, "wave": wave, "hull": int(hull), "shield": int(shield), "boost": boosting})


func _aim_target(from: Vector3, fwd: Vector3, cone: float) -> Variant:
	var best_e: Variant = null
	var best_a := cone
	for e in enemies:
		var d: Vector3 = (e["pos"] as Vector3) - from
		var dist := d.length()
		if dist > 1500.0:
			continue
		var a := fwd.angle_to(d)
		if a < best_a:
			best_a = a
			best_e = e
	return best_e


func _collide() -> void:
	# rocks
	for ri in _rocks_near(pos):
		var rk: Array = rocks[ri]
		var rp: Vector3 = rk[0]
		var rr: float = rk[1] * 0.92 + 4.0
		var d := pos - rp
		var dist := d.length()
		if dist < rr and dist > 0.01:
			var nn := d / dist
			pos = rp + nn * rr
			var vn := vel.dot(nn)
			if vn < 0.0:
				vel -= nn * vn * 1.5
				_damage(clampf(-vn * 0.35, 3.0, 60.0), true)
	# the station: ring (torus), hub (cylinder)
	var lp := (pos - STATION).rotated(Vector3.UP, -station_spin)
	var rxz := Vector2(lp.x, lp.z)
	var ring_q := Vector2(rxz.length() - RING_R, lp.y)
	if ring_q.length() < RING_TUBE + 4.0:
		var dir2 := rxz.normalized()
		var nl := Vector3(dir2.x * ring_q.x, ring_q.y, dir2.y * ring_q.x).normalized()
		var nn := nl.rotated(Vector3.UP, station_spin)
		pos += nn * (RING_TUBE + 4.0 - ring_q.length())
		var vn := vel.dot(nn)
		if vn < 0.0:
			vel -= nn * vn * 1.5
			_damage(clampf(-vn * 0.35, 3.0, 60.0), true)
	if absf(lp.y) < 62.0 and rxz.length() < HUB_R + 4.0:
		var nn2 := Vector3(rxz.x, 0, rxz.y).normalized().rotated(Vector3.UP, station_spin)
		pos += nn2 * (HUB_R + 4.0 - rxz.length())
		var vn2 := vel.dot(nn2)
		if vn2 < 0.0:
			vel -= nn2 * vn2 * 1.5
			_damage(clampf(-vn2 * 0.35, 3.0, 60.0), true)
	# keep inside the battle area (about 5 km)
	if pos.length() > 5000.0:
		vel -= pos.normalized() * 40.0 * get_process_delta_time()
		if msg_t <= 0.0:
			_show("TURN BACK", 1.5)


func _damage(amount: float, bump: bool) -> void:
	shield_t = 3.0
	var s := minf(shield, amount)
	shield -= s
	hull -= (amount - s)
	sfx.emit("hit")
	if bump:
		_show("IMPACT!", 0.8)
	if hull <= 0.0 and not dead:
		hull = 0.0
		dead = true
		dead_t = 0.0
		_boom(pos, 40.0)
		ship.visible = cockpit
		sfx.emit("boom")


func _spawn_wave() -> void:
	var count := mini(2 + wave * 2, 12)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for k in count:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.4, 0.4), rng.randf_range(-1, 1)).normalized()
		var p := pos + d * rng.randf_range(1400.0, 2100.0)
		var node := _new_drone()
		node.position = p
		var f := (pos - p).normalized()
		enemies.append({"node": node, "pos": p, "vel": f * 100.0, "fwd": f, "hp": 2 + wave / 3, "cd": rng.randf_range(1.5, 3.5),
			"mode": "attack", "mode_t": 0.0, "side": Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized(), "speed": 105.0 + minf(wave * 6.0, 45.0)})


func _turn_towards(f: Vector3, d: Vector3, max_a: float) -> Vector3:
	var a := f.angle_to(d)
	if a < 0.0001:
		return f
	var axis := f.cross(d)
	if axis.length() < 0.0001:
		axis = Vector3.UP
	return f.rotated(axis.normalized(), minf(a, max_a)).normalized()


func _update_enemies(dt: float) -> void:
	for e in enemies:
		var p: Vector3 = e["pos"]
		var f: Vector3 = e["fwd"]
		var to := pos - p
		var dist := to.length()
		var desired := to / maxf(dist, 0.01)
		e["mode_t"] = float(e["mode_t"]) - dt
		if e["mode"] == "attack":
			var lead := pos + vel * (dist / 800.0)
			desired = (lead - p).normalized()
			if dist < 170.0:
				e["mode"] = "break"
				e["mode_t"] = randf_range(2.0, 3.5)
				e["side"] = (f.cross(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))).normalized() + f * 0.3).normalized()
		else:
			desired = e["side"]
			if float(e["mode_t"]) <= 0.0:
				e["mode"] = "attack"
		# avoid rocks and the station
		var ahead := p + f * 90.0
		for ri in _rocks_near(ahead):
			var rk: Array = rocks[ri]
			var rp: Vector3 = rk[0]
			var off := ahead - rp
			if off.length() < float(rk[1]) + 35.0:
				desired = (desired + off.normalized() * 2.0).normalized()
		if (ahead - STATION).length() < RING_R + 60.0:
			desired = (desired + (ahead - STATION).normalized() * 2.0).normalized()
		f = _turn_towards(f, desired, 1.4 * dt)
		var spd: float = float(e["speed"]) * (1.35 if e["mode"] == "break" else 1.0)
		p += f * spd * dt
		e["vel"] = f * spd
		e["pos"] = p
		e["fwd"] = f
		var node: Node3D = e["node"]
		var up := Vector3.UP if absf(f.y) < 0.95 else Vector3.FORWARD
		node.global_transform = Transform3D(Basis.looking_at(f, up).rotated(f, sin(t_total * 2.0 + p.x) * 0.4), p)
		# shoot when lined up
		e["cd"] = float(e["cd"]) - dt
		if e["mode"] == "attack" and float(e["cd"]) <= 0.0 and dist < 1100.0 and f.angle_to(to) < 0.16:
			e["cd"] = maxf(0.55, 1.4 - wave * 0.07) + randf() * 0.5
			var spread := maxf(0.006, 0.03 - wave * 0.002) * (1.4 if assist else 1.0)
			var aim := (pos + vel * (dist / 700.0) - p).normalized()
			aim = (aim + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spread).normalized()
			_spawn_bolt(p + f * 4.0, aim * 700.0, true)
			sfx.emit("enemy_laser")


func _spawn_bolt(p: Vector3, v: Vector3, enemy: bool) -> void:
	for b in bolts:
		if float(b["life"]) <= 0.0:
			b["pos"] = p
			b["vel"] = v
			b["life"] = 1.7
			b["enemy"] = enemy
			var n: MeshInstance3D = b["node"]
			n.material_override = bolt_mat_e if enemy else bolt_mat_p
			n.visible = true
			_orient_bolt(b)
			return


func _orient_bolt(b: Dictionary) -> void:
	var v: Vector3 = b["vel"]
	var d := v.normalized()
	var x := d.cross(Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT).normalized()
	(b["node"] as Node3D).global_transform = Transform3D(Basis(x, d, x.cross(d)), b["pos"])


func _seg_hit(a: Vector3, b: Vector3, c: Vector3, r: float) -> bool:
	var ab := b - a
	var t := clampf((c - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return (a + ab * t).distance_to(c) < r


func _update_bolts(dt: float) -> void:
	for b in bolts:
		if float(b["life"]) <= 0.0:
			continue
		var a: Vector3 = b["pos"]
		var v: Vector3 = b["vel"]
		var nb := a + v * dt
		b["life"] = float(b["life"]) - dt
		var gone := false
		if b["enemy"]:
			if not dead and _seg_hit(a, nb, pos, 5.0):
				_damage(9.0 if assist else 13.0, false)
				gone = true
		else:
			for e in enemies:
				if _seg_hit(a, nb, e["pos"], 7.5 if assist else 6.0):
					e["hp"] = int(e["hp"]) - 1
					gone = true
					if int(e["hp"]) <= 0:
						_kill(e)
					else:
						sfx.emit("hit")
					break
		if not gone:
			for ri in _rocks_near(nb):
				var rk: Array = rocks[ri]
				if nb.distance_to(rk[0]) < float(rk[1]) * 0.9:
					gone = true
					_boom(nb, 4.0)
					break
		if gone or float(b["life"]) <= 0.0:
			b["life"] = 0.0
			(b["node"] as Node3D).visible = false
		else:
			b["pos"] = nb
			_orient_bolt(b)


func _kill(e: Dictionary) -> void:
	_boom(e["pos"], 26.0)
	sfx.emit("boom")
	score += 100 + wave * 10
	(e["node"] as Node3D).queue_free()
	enemies.erase(e)
	if enemies.is_empty():
		score += 250 * wave
		_show("WAVE %d CLEARED  +%d" % [wave, 250 * wave], 2.5)
		toast.emit("Wave cleared! Shields recharging. Next wave in a few seconds", 3.0)


func _boom(p: Vector3, size: float) -> void:
	var bm: Dictionary = booms[boom_i]
	boom_i = (boom_i + 1) % booms.size()
	var n: Node3D = bm["node"]
	n.global_position = p
	n.visible = true
	bm["t"] = 0.0
	bm["size"] = size
	var parts: GPUParticles3D = bm["parts"]
	parts.scale = Vector3.ONE * size / 26.0
	parts.restart()
	parts.emitting = true


func _update_booms(dt: float) -> void:
	for bm in booms:
		var t: float = bm["t"]
		if t > 1.6:
			continue
		t += dt
		bm["t"] = t
		var life := clampf(t / 1.3, 0.0, 1.0)
		var s: float = float(bm["size"]) * (0.5 + life * 1.3)
		(bm["fire"] as Node3D).scale = Vector3.ONE * s
		(bm["mat"] as ShaderMaterial).set_shader_parameter("life", life)
		(bm["light"] as OmniLight3D).light_energy = maxf(0.0, 8.0 * (1.0 - life * 1.6))
		(bm["light"] as OmniLight3D).omni_range = float(bm["size"]) * 4.0
		if t > 1.6:
			(bm["node"] as Node3D).visible = false


func _update_target() -> void:
	var b := Basis(q)
	var fwd := -b.z
	target = {}
	var best_score := INF
	for e in enemies:
		var d: Vector3 = (e["pos"] as Vector3) - pos
		var sc := d.length() * (1.0 + fwd.angle_to(d) * 2.0)
		if sc < best_score:
			best_score = sc
			target = e
	if target.is_empty():
		bracket.visible = false
		bracket_lbl.visible = false
		ship.pointer.visible = false
		return
	var tp: Vector3 = target["pos"]
	var dist := tp.distance_to(pos)
	bracket.visible = true
	bracket.global_position = tp
	bracket.scale = Vector3.ONE * clampf(dist * 0.03, 12.0, 400.0)
	bracket_lbl.visible = true
	bracket_lbl.global_position = tp - b.y * clampf(dist * 0.03, 12.0, 400.0) * 0.7
	bracket_lbl.pixel_size = clampf(dist * 0.00012, 0.01, 0.4)
	bracket_lbl.text = "%d m" % int(dist)
	# the cockpit arrow points at it
	ship.pointer.visible = true
	var local := b.inverse() * (tp - pos).normalized()
	ship.pointer.basis = Basis.looking_at(local, Vector3.UP if absf(local.y) < 0.98 else Vector3.BACK)


func _holo() -> void:
	ship.holo["left"].text = "SHIELD %d%%\nHULL %d%%" % [int(shield), int(hull)]
	ship.holo["mid"].text = "WAVE %d\n%d" % [maxi(wave, 1), score]
	var td := ("%d m" % int((target["pos"] as Vector3).distance_to(pos))) if not target.is_empty() else "--"
	ship.holo["right"].text = "%d M/S\nTARGET %s" % [int(vel.length()), td]
	ship.holo["left"].modulate = Color(1.0, 0.3, 0.2) if hull < 35.0 else Color(0.45, 0.9, 1.0)


func hud(ui) -> void:
	ui.l_speed.text = str(int(vel.length()))
	ui.l_alt.text = str(score)
	ui.l_vs.text = "SHIELD %d%%  ·  HULL %d%%" % [int(shield), int(hull)]
	ui.l_hdg.text = str(maxi(wave, 1))
	ui.thr_bar.value = thr
	ui.tag_flaps.text = "BOOST %d%%" % int(boost_e * 100.0)
	ui.tag_brake.text = "FIRE"
	ui.tag_brake.add_theme_color_override("font_color", Color("#ff4c00") if firing else Color("#a9acd0"))
	ui.tag_assist.text = "EASY" if assist else "PRO"
	ui.l_gate.text = "%d drone%s" % [enemies.size(), "" if enemies.size() == 1 else "s"] if not enemies.is_empty() else "Next wave"
	if not target.is_empty():
		var d := Basis(q).inverse() * ((target["pos"] as Vector3) - pos)
		ui.arrow_angle = rad_to_deg(atan2(d.x, d.y))
		ui.l_gate_t.text = "nearest %d m  ·  best %d" % [int(d.length()), best]
	else:
		ui.l_gate_t.text = "%.0f s  ·  best %d" % [maxf(wave_t, 0.0), best]
	ui.arrow.queue_redraw()
	var m := msg if msg_t > 0.0 else ""
	if m == "" and hull < 35.0 and not dead:
		m = "HULL DAMAGED"
	ui.set_message(m, m.begins_with("HULL") or m == "IMPACT!" or m == "TURN BACK")


func sound() -> Array:
	return [thr * 0.8 + (0.3 if boosting else 0.0), thr, vel.length()]


func grip(side: String) -> Array:
	if ship == null:
		return [Transform3D(), 0.0]
	return [ship.stick_grip() if side == "r" else ship.throttle_grip(), 0.2 if side == "r" else 0.14]


func camera_far() -> float:
	return 260000.0


func set_cockpit(on: bool) -> void:
	super.set_cockpit(on)
	if ship != null:
		ship.set_first_person(on)


func set_vr(on: bool) -> void:
	super.set_vr(on)
	if env != null:
		env.ssao_enabled = not on and quality != "low"


# ---------------------------------------------------------------- cameras
func place_camera(cam: Camera3D, cam_mode: String, dt: float, orbit: Dictionary) -> void:
	var b := Basis(q)
	if not running:
		var oy: float = orbit["yaw"]
		var cp := pos + Vector3(sin(oy) * 28.0, 7.0, cos(oy) * 28.0)
		cam.global_transform = Transform3D(Basis.looking_at((pos - cp).normalized(), Vector3.UP), cp)
		cam.fov = 60.0
		_place_space(cam.global_position)
		return
	cam.fov = 72.0
	if cam_mode == "cockpit":
		var lk: Vector2 = orbit["look"]
		cam.near = 0.05
		cam.global_transform = Transform3D(b * Basis.from_euler(Vector3(lk.y - 0.08, lk.x, 0)), Transform3D(b, pos) * eye)
	elif cam_mode == "orbit":
		var oy2: float = orbit["yaw"]
		var op: float = orbit["pitch"]
		var od: float = orbit["dist"] * 2.2
		var cp2 := pos + Vector3(sin(oy2) * cos(op) * od, sin(op) * od, cos(oy2) * cos(op) * od)
		cam.global_transform = Transform3D(Basis.looking_at((pos - cp2).normalized(), Vector3.UP), cp2)
	else:
		cam.near = 0.3
		if not cam_init:
			cam_q = q
			cam_init = true
		cam_q = cam_q.slerp(q, 1.0 - exp(-dt * 4.0))
		var cb := Basis(cam_q)
		var cp3 := pos + cb * Vector3(0, 6.0, 25.0)
		var tgt := pos + b * Vector3(0, 2.0, -30.0)
		cam.global_transform = Transform3D(Basis.looking_at((tgt - cp3).normalized(), cb.y), cp3)
		cam.fov = 72.0 + (8.0 if boosting else 0.0)
	_place_space(cam.global_position)


func follow_camera(p: Vector3) -> void:
	_place_space(p)


## Stars and space dust stay round the camera (the dust wraps in a 160 m box so you see your speed).
func _place_space(cam_pos: Vector3) -> void:
	if stars != null:
		stars.global_position = cam_pos
	if dust != null:
		var mm := dust.multimesh
		var box := 160.0
		for k in dust_pos.size():
			var p: Vector3 = dust_pos[k]
			var rel := Vector3(fposmod(p.x - cam_pos.x, box), fposmod(p.y - cam_pos.y, box), fposmod(p.z - cam_pos.z, box)) - Vector3.ONE * box * 0.5
			mm.set_instance_transform(k, Transform3D(Basis(), cam_pos + rel))
		dust.global_position = Vector3.ZERO
