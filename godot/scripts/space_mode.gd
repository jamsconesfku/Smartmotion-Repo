class_name SpaceMode
extends ShipMode
## SmartMotion Space: fly the spaceship between the planets. v1.16.0: nine places to visit (Earth, the Moon,
## Mercury, Venus, Mars, Jupiter, Saturn with its space station and asteroid field, Uranus and Neptune), a
## hyperspeed jump between them, and Earth joined up with Duxford: fly down into Earth's air and you carry on
## over the real Duxford (ShipEarthMode); climb out of it and you are back here, high above the Earth.
## Each place is its own scene round the ship (the solar system is far too big for one): hyperspeed moves you
## to the next one while the tunnel hides the view. The sun and the other planets are where they would be
## in the sky (from a simple map of the solar system), always lit from the same side when you arrive.
## Game "battle" (Settings space_game): waves of enemy drones round the Saturn station, as before v1.16.0.
## Easy: aim help, rolls itself upright, turns to the planet for hyperspeed. Pro: none of them.

const STATION := Vector3(0, 0, -900)
const RING_R := 160.0
const RING_TUBE := 16.0
const HUB_R := 34.0
const PLANET := Vector3(-38000, -9000, -52000)   # Saturn, from the station
const MOON := Vector3(9000, 2600, -16000)        # one of Saturn's moons
const MOON_R := 2600.0
const BOLT_SPEED := 950.0
const CELL := 250.0
const SUN_LOCAL := Vector3(0.55, 0.32, 0.77)     # the sun's direction when you arrive anywhere
const EARTH_ABOVE := 2000.0                      # leaving Duxford's air puts you this high above the Earth here
const REENTRY := 1500.0                          # ... and coming down below this takes you back to Duxford
const FAR_D := 100000.0                          # the other planets are drawn this far away (small discs)
const SPOOL := 1.6                               # hyperspeed: seconds of build-up, then the tunnel, then...
const EXIT := 0.9                                # ... seconds coming out of it

## The planets. r: radius in the game (not to scale: big enough to look good, small enough to reach);
## au, ang: where it is round the sun (AU from the sun, degrees round), for which way the sun and the other
## planets are in the sky; paint and p: how its picture is painted (space_paint.gdshader) and its colours.
const BODIES := {
	"earth": {"r": 30000.0, "au": 1.0, "ang": 250.0, "paint": 4, "p": {}, "atm": Color(0.35, 0.6, 1.0), "atm_e": 1.4},
	"moon": {"r": 8000.0, "au": 1.0, "ang": 250.0, "paint": 2, "p": {"maria": 1.0, "seed": 3.0}},
	"mercury": {"r": 11000.0, "au": 0.39, "ang": 40.0, "paint": 2, "p": {"rock_a": Color(0.3, 0.27, 0.24), "rock_b": Color(0.62, 0.56, 0.5), "seed": 7.0}},
	"venus": {"r": 26000.0, "au": 0.72, "ang": 150.0, "paint": 1, "p": {"c1": Color(0.93, 0.83, 0.58), "c2": Color(0.84, 0.7, 0.45), "c3": Color(0.97, 0.93, 0.78), "bands": 6.0, "storm": 0.0, "seed": 2.0}, "atm": Color(1.0, 0.9, 0.65), "atm_e": 0.9},
	"mars": {"r": 16000.0, "au": 1.52, "ang": 310.0, "paint": 2, "p": {"rock_a": Color(0.4, 0.16, 0.07), "rock_b": Color(0.8, 0.43, 0.22), "maria": 0.8, "caps": 1.0, "craters": 0.35, "seed": 5.0}, "atm": Color(1.0, 0.6, 0.4), "atm_e": 0.35},
	"jupiter": {"r": 34000.0, "au": 5.2, "ang": 20.0, "paint": 1, "p": {"c1": Color(0.88, 0.78, 0.64), "c2": Color(0.6, 0.4, 0.27), "c3": Color(0.96, 0.93, 0.87), "bands": 24.0, "storm": 1.0, "storm_col": Color(0.75, 0.3, 0.17), "seed": 1.0}, "atm": Color(0.95, 0.8, 0.6), "atm_e": 0.6},
	"saturn": {"r": 24000.0, "au": 9.5, "ang": 200.0, "paint": 1, "p": {}, "atm": Color(0.95, 0.75, 0.55), "atm_e": 0.7},
	"uranus": {"r": 18000.0, "au": 19.2, "ang": 100.0, "paint": 1, "p": {"c1": Color(0.62, 0.86, 0.88), "c2": Color(0.55, 0.8, 0.84), "c3": Color(0.75, 0.92, 0.93), "bands": 8.0, "storm": 0.0, "seed": 4.0}, "atm": Color(0.6, 0.9, 1.0), "atm_e": 0.8},
	"neptune": {"r": 17000.0, "au": 30.0, "ang": 290.0, "paint": 1, "p": {"c1": Color(0.25, 0.42, 0.88), "c2": Color(0.16, 0.28, 0.72), "c3": Color(0.5, 0.65, 0.96), "bands": 10.0, "storm": 1.0, "storm_col": Color(0.08, 0.12, 0.4), "seed": 6.0}, "atm": Color(0.4, 0.6, 1.0), "atm_e": 0.9},
}
const MOON_KM := 384400.0

var sun: DirectionalLight3D
var sun_dir := SUN_LOCAL.normalized()
var sun_glows: Array = []
var station: Node3D
var station_spin := 0.0
var saturn_nodes: Array = []    # the station and the asteroid field: only at Saturn
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
var battle := false
var fire_cd := 0.0
var gun_side := 0
var firing := false
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
var fx_shader: Shader
# the planets
var tex := {}                   # body -> painted picture
var loc := "saturn"             # where you are
var pc := PLANET                # the planet's middle here
var pr := 24000.0               # ... and its radius
var sec := ""                   # a second body close by (the Moon at Earth, Earth at the Moon)
var sec_pc := Vector3.ZERO
var sec_r := 0.0
var body_root: Node3D
var body_mi: MeshInstance3D
var body_atm: MeshInstance3D
var body_ring: MeshInstance3D
var sec_root: Node3D
var sec_mi: MeshInstance3D
var sec_atm: MeshInstance3D
var smoon: MeshInstance3D       # Saturn's moon
var far := {}                   # body -> small sphere in the sky
var far_dir := {}               # body -> direction from here
var far_r := {}
var earth_tilt := Basis()       # turns the Earth so the place Duxford is painted is on top
var sky_rot := Basis()
var dest_mark: MeshInstance3D
var dest_lbl: Label3D
# hyperspeed
var hyper := ""                 # "" | "align" | "spool" | "tunnel" | "exit"
var hyper_t := 0.0
var hyper_to := ""
var hyper_len := 3.0
var swapped := false
var streak := 0.0
var streak_v := 0.0
var tunnel := 0.0
var plasma := 0.0
var no_leave := 0.0


func mode_name() -> String:
	return "space"


func hud_kind() -> String:
	return "space" if _battle_on() else "ship"


func _battle_on() -> bool:
	return battle and loc == "saturn"


func build(w: World, qual: String) -> void:
	super.build(w, qual)
	fx_shader = load("res://shaders/space_fx.gdshader")
	var sky_tex := await _paint(0, Vector2i(4096, 2048) if qual != "low" else Vector2i(2048, 1024))
	for k in BODIES:
		var bd: Dictionary = BODIES[k]
		tex[k] = await _paint(int(bd["paint"]), Vector2i(2048, 1024) if qual != "low" else Vector2i(1024, 512), bd["p"])
	tex["smoon"] = await _paint(2, Vector2i(1024, 512))
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
	_bodies(ring_tex)
	await _station()
	saturn_nodes.append(station)
	_asteroids(qual)
	_stars()
	_dust()
	_drone_template()
	_bolt_assets()
	_booms()
	_bracket()
	_dest_marker()
	build_ship()
	_set_location("saturn")


func _paint(mode: int, size: Vector2i, params := {}) -> Texture2D:
	if DisplayServer.get_name() == "headless":
		# nothing is drawn without a screen (the headless checks): a plain picture instead
		var plain := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
		plain.fill(Color(0.4, 0.4, 0.45))
		return ImageTexture.create_from_image(plain)
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
	for k in params:
		var v: Variant = params[k]
		m.set_shader_parameter(k, Vector3(v.r, v.g, v.b) if v is Color else v)
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
	sun_glows.append(_quad(16000.0, fx_mat(0, Color(1.0, 0.9, 0.7), 3.0, 1.6), sun_dir * 110000.0))
	sun_glows.append(_quad(70000.0, fx_mat(0, Color(1.0, 0.55, 0.25), 0.35, 3.0), sun_dir * 115000.0))


# ---------------------------------------------------------------- the planets
func _sphere_mi(parent: Node3D, segs: int, m: Material) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = segs
	sm.rings = segs / 2
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0
	parent.add_child(mi)
	return mi


func _planet_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.72, 0.72, 0.72)
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return m


func _bodies(ring_tex: Texture2D) -> void:
	# the planet you are at (one set of meshes, given each planet's picture as you get there)
	body_root = Node3D.new()
	add_child(body_root)
	body_mi = _sphere_mi(body_root, 128, _planet_mat())
	body_atm = _sphere_mi(body_root, 96, fx_mat(3, Color.WHITE, 0.7, 4.0))
	# Saturn's rings: a flat band from 1.35 to 2.3 planet radii
	var segs := 160
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var nm := PackedVector3Array()
	var idx := PackedInt32Array()
	for k in segs + 1:
		var a := TAU * k / segs
		for j in 2:
			var rr := 1.35 if j == 0 else 2.3
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
	body_ring = MeshInstance3D.new()
	body_ring.mesh = rm
	var rmat := StandardMaterial3D.new()
	rmat.albedo_texture = ring_tex
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	rmat.roughness = 1.0
	rmat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	rmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	body_ring.material_override = rmat
	body_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body_ring.extra_cull_margin = 16384.0
	body_root.add_child(body_ring)
	# a second body nearby (the Moon seen from Earth, Earth from the Moon)
	sec_root = Node3D.new()
	add_child(sec_root)
	sec_mi = _sphere_mi(sec_root, 96, _planet_mat())
	sec_atm = _sphere_mi(sec_root, 64, fx_mat(3, Color.WHITE, 0.7, 4.0))
	# Saturn's moon (with the station)
	var mm := StandardMaterial3D.new()
	mm.albedo_texture = tex["smoon"]
	mm.roughness = 1.0
	smoon = _sphere_mi(self, 64, mm)
	smoon.scale = Vector3.ONE * MOON_R
	smoon.position = MOON
	# the other planets: small discs in the sky
	for k in BODIES:
		var fm := _planet_mat()
		fm.albedo_texture = tex[k]
		fm.albedo_color = Color(0.9, 0.9, 0.9)
		far[k] = _sphere_mi(self, 32, fm)
	# which way up the Earth goes: the place its picture puts land for Duxford (latitude 52) on top
	var arrs := (body_mi.mesh as SphereMesh).get_mesh_arrays()
	var verts: PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrs[Mesh.ARRAY_TEX_UV]
	var want := Vector2(0.5, 0.5 - 52.0 / 180.0)
	var best_i := 0
	var best_d := INF
	for i in uvs.size():
		var d := uvs[i].distance_squared_to(want)
		if d < best_d:
			best_d = d
			best_i = i
	earth_tilt = Basis(Quaternion(verts[best_i].normalized(), Vector3.UP))


## Where a planet is round the sun (AU), on a simple flat map of the solar system.
static func _layout(k: String) -> Vector3:
	var bd: Dictionary = BODIES[k]
	var a := deg_to_rad(float(bd["ang"]))
	return Vector3(cos(a), 0.04 * sin(a * 3.0), sin(a)) * float(bd["au"])


## How far it is from one place to another, for the screens.
static func distance_text(a: String, b: String) -> String:
	if (a == "earth" and b == "moon") or (a == "moon" and b == "earth"):
		return "384,400 km"
	var au := (_layout(a) - _layout(b)).length()
	if au < 0.1:
		return ShipMode._thousands(int(au * 149597870.0)) + " km"
	return "%.1f AU" % au


## Sets up the scene for one place: its planet, what else is in the sky, the station (Saturn only).
func _set_location(k: String) -> void:
	loc = k
	var bd: Dictionary = BODIES[k]
	pr = float(bd["r"])
	sec = ""
	match k:
		"saturn":
			pc = PLANET
		"earth":
			pc = Vector3(0, -(pr + EARTH_ABOVE), 0)
			sec = "moon"
			sec_pc = Vector3(70000, 30000, -110000)
		"moon":
			pc = Vector3(-0.45, -0.22, -1.0).normalized() * pr * 2.6
			sec = "earth"
			sec_pc = Vector3(90000, 55000, -150000)
		_:
			pc = Vector3(-0.45, -0.22, -1.0).normalized() * pr * 2.6
	# the planet
	var tilt := Basis(Vector3.RIGHT, 0.35)
	if k == "saturn":
		tilt = Basis(Quaternion(Vector3.UP, Vector3(0.35, 0.8, 0.5).normalized()))   # the rings seen open
	elif k == "earth":
		tilt = earth_tilt
	elif k == "uranus":
		tilt = Basis(Vector3.FORWARD, 1.5)   # Uranus lies on its side
	body_root.transform = Transform3D(tilt, pc)
	body_mi.scale = Vector3.ONE * pr
	(body_mi.material_override as StandardMaterial3D).albedo_texture = tex[k]
	(body_mi.material_override as StandardMaterial3D).albedo_color = Color(0.85, 0.85, 0.85) if k == "earth" else Color(0.72, 0.72, 0.72)
	body_atm.visible = bd.has("atm")
	if body_atm.visible:
		body_atm.scale = Vector3.ONE * pr * (1.025 if k == "earth" else 1.03)
		(body_atm.material_override as ShaderMaterial).set_shader_parameter("color", bd["atm"])
		(body_atm.material_override as ShaderMaterial).set_shader_parameter("energy", bd["atm_e"])
	body_ring.visible = k == "saturn"
	body_ring.scale = Vector3.ONE * pr
	# the second body
	sec_root.visible = sec != ""
	if sec != "":
		var sd: Dictionary = BODIES[sec]
		sec_r = float(sd["r"])
		sec_root.transform = Transform3D(earth_tilt if sec == "earth" else Basis(), sec_pc)
		sec_mi.scale = Vector3.ONE * sec_r
		(sec_mi.material_override as StandardMaterial3D).albedo_texture = tex[sec]
		sec_atm.visible = sd.has("atm")
		if sec_atm.visible:
			sec_atm.scale = Vector3.ONE * sec_r * 1.03
			(sec_atm.material_override as ShaderMaterial).set_shader_parameter("color", sd["atm"])
			(sec_atm.material_override as ShaderMaterial).set_shader_parameter("energy", sd["atm_e"])
	smoon.visible = k == "saturn"
	for n in saturn_nodes:
		(n as Node3D).visible = k == "saturn"
	# this place's view of the solar system: turned so the sun is always in the same place when you arrive
	var here := _layout(k)
	var rot := Quaternion((-here).normalized(), sun_dir)
	var rot_sat := Quaternion((-_layout("saturn")).normalized(), sun_dir)
	sky_rot = Basis(rot * rot_sat.inverse())
	env.sky_rotation = sky_rot.get_euler()
	if stars != null:
		stars.basis = sky_rot
	for o in BODIES:
		var mi: MeshInstance3D = far[o]
		var show: bool = o != k and o != sec and o != "moon"   # the Moon is only big enough to see from Earth
		mi.visible = show
		if show:
			var d := _layout(o) - here
			far_dir[o] = (rot * d.normalized()).normalized()
			far_r[o] = clampf(float(BODIES[o]["r"]) * 3.0 / maxf(d.length(), 0.05), 300.0, 2500.0)
	# the sun looks bigger close in (Mercury) and smaller far out (Neptune)
	var sk := clampf(pow(1.0 / maxf(float(bd["au"]), 0.3), 0.6), 0.25, 1.8)
	for g in sun_glows:
		(g as Node3D).scale = Vector3.ONE * sk
	sun.light_energy = 2.3 * clampf(pow(1.0 / float(bd["au"]), 0.25), 0.55, 1.4)
	if loc != "saturn":
		_clear()


## Which way to point for a place (from where you are).
func _dest_dir(k: String) -> Vector3:
	if k == loc:
		return (pc - pos).normalized()
	if k == sec:
		return (sec_pc - pos).normalized()
	if far_dir.has(k):
		return far_dir[k]
	var d := _layout(k) - _layout(loc)
	return (Quaternion((-_layout(loc)).normalized(), sun_dir) * d.normalized()).normalized()


func _dest_marker() -> void:
	var img := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for k in 64:
		var a := TAU * k / 64.0
		for r in [27.0, 28.0, 29.0]:
			img.set_pixel(clampi(int(32 + cos(a) * r), 0, 63), clampi(int(32 + sin(a) * r), 0, 63), Color(0.45, 0.85, 1.0, 1))
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.no_depth_test = true
	m.render_priority = 4
	m.albedo_color = Color(1.3, 1.3, 1.3)
	dest_mark = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1, 1)
	dest_mark.mesh = qm
	dest_mark.material_override = m
	dest_mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dest_mark.visible = false
	add_child(dest_mark)
	dest_lbl = GameMode.label3d(self, "", 48, Vector3.ZERO, Color(0.55, 0.9, 1.0), 0.001, false)
	dest_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	dest_lbl.no_depth_test = true
	dest_lbl.render_priority = 4
	dest_lbl.visible = false


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
		saturn_nodes.append(mmi)


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
	_set_location("saturn")
	_reset_ship()
	_clear()
	ship.transform = Transform3D(Basis(q), pos)


func _reset_ship() -> void:
	pos = Vector3(0, 10, 300)
	q = Quaternion.IDENTITY
	vel = Vector3(0, 0, -40)
	prev_vel = vel
	wv = Vector3.ZERO
	thr = 0.4
	boost_e = 1.0
	hull = 100.0
	shield = 100.0
	dead = false
	cam_init = false
	hyper = ""
	streak = 0.0
	tunnel = 0.0
	plasma = 0.0
	cue = Vector3.ZERO
	fade = 0.0
	leaving = false
	auto = ""
	if ship != null:
		ship.visible = true
		ship.hyper_fx(0.0, 0.0, 0.0, 0.0)
		ship.set_plasma(0.0)
		ship.leg_k = 0.0


func _clear() -> void:
	for e in enemies:
		(e["node"] as Node3D).queue_free()
	enemies = []
	for b in bolts:
		b["life"] = 0.0
		(b["node"] as Node3D).visible = false
	if bracket != null:
		bracket.visible = false
		bracket_lbl.visible = false
	target = {}


func start() -> void:
	super.start()
	assist = bool(opt("assist", true))
	battle = str(opt("space_game", "explore")) == "battle"
	_set_location("saturn")
	_reset_ship()
	_clear()
	score = 0
	wave = 0
	wave_t = 3.0
	best = int(best_of("space_score"))
	x10 = false
	x10_k = 0.0
	lights = false
	ship.set_lights(false)
	hints = {}
	dest = DESTS.find("earth")
	if battle:
		toast.emit("Shoot the red drones before they get you. Space or right trigger: fire. W/S/A/D steer, Q/E yaw, Shift/Ctrl speed, Tab or left trigger: boost", 7.0)
	else:
		toast.emit("You're at the space station by Saturn. Pick a planet (< PLANET >, or N), then press HYPERSPEED (H). TO EARTH (U) flies you home to Duxford", 8.0)


## Carrying on from Duxford: you have just flown up out of the air, 2 km above the Earth.
func arrive(c: Dictionary) -> void:
	super.arrive(c)
	battle = str(opt("space_game", "explore")) == "battle"
	_set_location("earth")
	pos = Vector3(0, 0, 0)
	vel = vel.limit_length(3000.0)
	prev_vel = vel
	hyper = ""
	streak = 0.0
	tunnel = 0.0
	plasma = 0.0
	cue = Vector3.ZERO
	dead = false
	fade_col = Color(0.0, 0.0, 0.02)
	no_leave = 4.0
	ship.leg_k = 0.0
	if auto == "space":
		auto = ""
		auto_off()
	_hint("space", "You're in space! The Earth is below you. Choose a planet (< PLANET >, or N) and press HYPERSPEED (H). Fly back down to land at Duxford", 8.0)


func auto_off() -> void:
	thr_set = thr


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


func test_options(a: Dictionary) -> void:
	if a.has("at_planet") and BODIES.has(str(a["at_planet"])):
		_arrive_at(str(a["at_planet"]))
	if a.has("dest") and DESTS.has(str(a["dest"])):
		dest = DESTS.find(str(a["dest"]))
	super.test_options(a)


func _button(id: String) -> void:
	match id:
		"hyper":
			if hyper != "":
				return
			_start_hyper(dest_key(), false)
		"auto":
			if auto == "earth":
				auto = ""
				auto_off()
				_say("AUTOPILOT OFF", 1.5)
			else:
				auto = "earth"
				dest = DESTS.find("earth")
				_say("AUTOPILOT: TO EARTH", 2.5)
				if loc != "earth" and hyper == "":
					_start_hyper("earth", true)
		"land":
			_say("FLY DOWN TO EARTH TO LAND", 2.0)
			toast.emit("You can land on Earth (at Duxford). Fly down into its air, or press TO EARTH (U).", 4.0)
		_:
			super._button(id)


func _start_hyper(k: String, by_auto: bool) -> void:
	if k == loc:
		_say("YOU'RE AT %s" % DEST_NAMES[k].to_upper(), 2.0)
		return
	if dead:
		return
	var d := _dest_dir(k)
	if not assist and not by_auto and (-Basis(q).z).angle_to(d) > 0.2:
		_say("POINT AT %s FIRST (THE BLUE RING)" % DEST_NAMES[k].to_upper(), 2.5)
		return
	hyper_to = k
	hyper = "align" if (assist or by_auto) else "spool"
	hyper_t = 0.0
	swapped = false
	var au := (_layout(k) - _layout(loc)).length()
	hyper_len = clampf(2.2 + au * 0.08, 2.2, 4.4)
	_say("HYPERSPEED: %s" % DEST_NAMES[k].to_upper(), 2.0)
	if hyper == "spool":
		sfx.emit("hyper")


func step(dt: float, inp: Dictionary) -> void:
	if not running:
		return
	idle(dt)
	msg_t -= dt
	no_leave -= dt
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
	_buttons(inp)
	x10_k = move_toward(x10_k, 1.0 if x10 else 0.0, dt / X10_TIME)
	if not leaving:
		fade = move_toward(fade, 0.0, dt * (2.5 if hyper != "" else 1.1))
	var b := Basis(q)
	var up := _up()
	var manual := absf(float(inp["pitch"])) + absf(float(inp["roll"])) + absf(float(inp["yaw"]))
	if auto != "" and manual > 0.35 and hyper == "":
		auto = ""
		auto_off()
		_say("AUTOPILOT OFF: YOU HAVE CONTROL", 2.0)
	thr = float(inp["throttle"])
	# turning: the autopilot, hyperspeed lining up, or the stick
	if hyper == "align" or (hyper == "spool" and assist):
		_steer_to(_dest_dir(hyper_to), up, dt, 2.4)
	elif hyper == "tunnel" or hyper == "exit":
		_rotate(dt, Vector3.ZERO)
	elif auto == "earth" and loc == "earth":
		_steer_to((pc + up_at_home() * (pr + 700.0)) - pos, (pos - pc).normalized(), dt, 0.9)
	else:
		_rotate(dt, _stick_rates(inp, up, false))
	b = Basis(q)
	var fwd := -b.z
	boosting = bool(inp["boost"]) and boost_e > 0.05 and hyper == ""
	boost_e = clampf(boost_e + (-0.32 if boosting else 0.12) * dt, 0.0, 1.0)
	var target_v := lerpf(25.0, 150.0, thr) * x10_factor()
	if boosting:
		target_v = maxf(target_v, 330.0)
	if auto == "earth" and loc == "earth" and hyper == "":
		var dist := pos.distance_to(pc + up_at_home() * (pr + 700.0))
		target_v = clampf(dist * 0.12, 300.0, 3000.0)
	vel = vel.lerp(fwd * target_v, 1.0 - exp(-dt * (1.3 if assist else 0.8)))
	pos += vel * dt
	_hyper_step(dt)
	_feel(dt, null)
	_collide()
	_planets(dt)
	if leaving:
		fade = move_toward(fade, 1.0, dt * 2.2)
		if fade >= 1.0:
			# carry on over Duxford: the ship's frame turned so "up" here is up there
			var n := (pos - pc).normalized()
			var rot := Quaternion(n, Vector3.UP)
			var c := carry()
			c["q"] = (rot * q).normalized()
			c["vel"] = rot * vel
			c["wv"] = wv
			c["plasma"] = maxf(plasma, 0.6)
			c["from"] = "space"
			_tel()
			transfer.emit("ship_earth", c)
			return
	# guns
	fire_cd -= dt
	firing = bool(inp["fire"]) and hyper == ""
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
	if _battle_on():
		_update_enemies(dt)
	_update_bolts(dt)
	_update_booms(dt)
	# waves (the drone battle, round the station)
	if _battle_on() and enemies.is_empty():
		wave_t -= dt
		if wave_t <= 0.0:
			wave += 1
			_spawn_wave()
			_say("WAVE %d" % wave, 2.0)
			wave_t = 4.0
	ship.transform = Transform3D(b, pos)
	ship.animate(thr, boosting or hyper != "" or x10_k > 0.5, float(inp["pitch"]), float(inp["roll"]), dt)
	ship.hyper_fx(streak, streak_v, tunnel, dt)
	ship.set_plasma(plasma)
	_show_buttons("TO EARTH", "LAND")
	ship.set_button("hyper", hyper != "")
	_update_target()
	_holo()
	_tel()


func _tel() -> void:
	make_tel(t_total, false, dead, Basis(q), pos, vel, wv, acc_body, vel.length() * 1.94384, {"speed_ms": snappedf(vel.length(), 0.1),
		"score": score, "wave": wave, "hull": int(hull), "shield": int(shield), "boost": boosting, "where": loc, "hyper": hyper != "", "x10": x10})


## "Up" for the Easy roll-upright help: away from the Earth when you are near it, else the scene's up.
func _up() -> Vector3:
	if loc == "earth" or loc == "moon":
		var d := pos - pc
		if d.length() < pr * 2.2:
			return d.normalized()
	return Vector3.UP


## The top of the Earth here is above Duxford (see earth_tilt).
func up_at_home() -> Vector3:
	return Vector3.UP


func _hyper_step(dt: float) -> void:
	cue = Vector3.ZERO
	match hyper:
		"":
			streak = move_toward(streak, 0.0, dt)
			tunnel = 0.0
		"align":
			hyper_t += dt
			streak = 0.0
			if (-Basis(q).z).angle_to(_dest_dir(hyper_to)) < 0.06 or hyper_t > 3.0:
				hyper = "spool"
				hyper_t = 0.0
				sfx.emit("hyper")
		"spool":
			hyper_t += dt
			var k := clampf(hyper_t / SPOOL, 0.0, 1.0)
			streak = k * k * 0.55
			streak_v = k * k * 2600.0
			cue = Vector3(0, sin(t_total * 47.0) * 0.6 * k, -1.5 * k)
			if hyper_t >= SPOOL:
				hyper = "tunnel"
				hyper_t = 0.0
				fade = 0.85
				fade_col = Color(0.85, 0.92, 1.0)
				sfx.emit("jump")
		"tunnel":
			hyper_t += dt
			tunnel = clampf(hyper_t / 0.35, 0.0, 1.0)
			streak = 1.0
			streak_v = 9000.0
			cue = Vector3(sin(t_total * 31.0) * 0.3, sin(t_total * 53.0) * 0.5, -7.0 * exp(-hyper_t * 1.4))
			if not swapped and hyper_t > 0.5:
				swapped = true
				_arrive_at(hyper_to)
			if hyper_t >= hyper_len:
				hyper = "exit"
				hyper_t = 0.0
				fade = 0.7
				fade_col = Color(0.85, 0.92, 1.0)
				sfx.emit("jump")
		"exit":
			hyper_t += dt
			var k2 := 1.0 - clampf(hyper_t / EXIT, 0.0, 1.0)
			tunnel = k2 * k2 * (3.0 - 2.0 * k2)
			streak = k2 * 0.8
			streak_v = 2600.0 * k2
			cue = Vector3(0, 0, 5.0 * k2)
			if hyper_t >= EXIT:
				hyper = ""
				tunnel = 0.0
				_arrived()


## In the tunnel: move the ship to the new place (nobody can see out).
func _arrive_at(k: String) -> void:
	_set_location(k)
	var look := Vector3(0, 0, -1)
	match k:
		"saturn":
			pos = Vector3(0, 10, 300)
		"earth":
			pos = Vector3(0, 9000, 70000)
			look = (pc + Vector3(0, pr * 0.75, 0)) - pos
		_:
			pos = Vector3.ZERO
	q = Quaternion(Basis.looking_at(look.normalized(), Vector3.UP).orthonormalized())
	var spd := maxf(vel.length(), 60.0)
	vel = -Basis(q).z * spd
	prev_vel = vel
	wv = Vector3.ZERO
	cam_init = false


func _arrived() -> void:
	var nm: String = DEST_NAMES[loc]
	_say(nm.to_upper(), 3.0)
	match loc:
		"earth":
			if auto == "earth":
				toast.emit("Earth! The autopilot is taking you down to Duxford. Move the stick to take over.", 5.0)
			else:
				toast.emit("Earth. Fly down into the air to come home to Duxford, or press TO EARTH (U) for the autopilot.", 6.0)
		"saturn":
			toast.emit("Saturn, its rings and the SmartMotion space station.%s" % (" Watch out: drones attack here!" if battle else ""), 5.0)
		"moon":
			toast.emit("The Moon, with the Earth in the sky.", 4.0)
		_:
			toast.emit("%s. Pick another planet and press HYPERSPEED, or TO EARTH (U) to go home." % nm, 5.0)


## Re-entry over Earth, and keeping you off the other planets.
func _planets(dt: float) -> void:
	var r := pos - pc
	var dist := r.length()
	var n := r / maxf(dist, 0.001)
	var alt := dist - pr
	var radial := vel.dot(n)
	if loc == "earth":
		var pk := clampf((7000.0 - alt) / 5000.0, 0.0, 1.0) * clampf((-radial - 250.0) / 500.0, 0.0, 1.0)   # only diving in fast
		plasma = move_toward(plasma, pk, dt * 1.5)
		if alt < REENTRY and radial < 0.0 and not leaving and no_leave <= 0.0 and hyper == "":
			leaving = true
			fade_col = Color(1.0, 0.6, 0.3)
			sfx.emit("whoosh")
		elif alt < 300.0:
			pos = pc + n * (pr + 300.0)
			vel -= n * minf(radial, 0.0)
	else:
		plasma = move_toward(plasma, 0.0, dt)
		if alt < 400.0:
			pos = pc + n * (pr + 400.0)
			vel -= n * minf(radial, 0.0) * 1.2
			if msg_t <= 0.0:
				_say("YOU CAN ONLY LAND ON EARTH", 2.0)
	if sec != "":
		var r2 := pos - sec_pc
		if r2.length() < sec_r + 400.0:
			var n2 := r2.normalized()
			pos = sec_pc + n2 * (sec_r + 400.0)
			vel -= n2 * minf(vel.dot(n2), 0.0) * 1.2
			if msg_t <= 0.0:
				_say("HYPERSPEED TO EARTH TO LAND THERE" if sec == "earth" else "YOU CAN ONLY LAND ON EARTH", 2.0)


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
	if loc != "saturn":
		if pos.length() > 200000.0:
			vel -= pos.normalized() * 400.0 * get_process_delta_time()
			if msg_t <= 0.0:
				_say("TURN BACK", 1.5)
		return
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
	if _battle_on() and pos.length() > 5000.0:
		vel -= pos.normalized() * 40.0 * get_process_delta_time()
		if msg_t <= 0.0:
			_say("TURN BACK", 1.5)


func _damage(amount: float, bump: bool) -> void:
	shield_t = 3.0
	var s := minf(shield, amount)
	shield -= s
	hull -= (amount - s)
	sfx.emit("hit")
	if bump:
		_say("IMPACT!", 0.8)
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
		_say("WAVE %d CLEARED  +%d" % [wave, 250 * wave], 2.5)
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
	if not _battle_on():
		bracket.visible = false
		bracket_lbl.visible = false
		ship.pointer.visible = hyper == "" and dest_key() != loc
		if ship.pointer.visible:
			var lp := b.inverse() * _dest_dir(dest_key())
			ship.pointer.basis = Basis.looking_at(lp, Vector3.UP if absf(lp.y) < 0.98 else Vector3.BACK)
		return
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
	var v := vel.length()
	var alt := pos.distance_to(pc) - pr
	var here: String = DEST_NAMES[loc]
	if _battle_on():
		ship.holo["left"].text = "SHIELD %d%%\nHULL %d%%\n%d m/s" % [int(shield), int(hull), int(v)]
		ship.holo["mid"].text = "WAVE %d\n%d\nBEST %d" % [maxi(wave, 1), score, best]
		var td := ("%d m" % int((target["pos"] as Vector3).distance_to(pos))) if not target.is_empty() else "--"
		ship.holo["right"].text = "TARGET %s\nPLANET\n%s" % [td, dest_name().to_upper()]
		ship.holo["left"].modulate = Color(1.0, 0.3, 0.2) if hull < 35.0 else Color(0.45, 0.9, 1.0)
	else:
		if hyper == "tunnel" or hyper == "exit":
			ship.holo["left"].text = "SPEED\nHYPERSPEED\n%s" % ("x1,000,000" if hyper == "tunnel" else "SLOWING")
		else:
			ship.holo["left"].text = "SPEED%s\n%d m/s\n%s" % ["  x10" if x10 else "", int(v), kmh(v)]
		ship.holo["mid"].text = "%s\nALT %s\nHDG %03d" % [here.to_upper(), metres(alt), heading_of(Basis(q))]
		var dk := dest_key()
		var line := "YOU'RE HERE" if dk == loc else distance_text(loc, dk)
		var ready := "JUMPING..." if hyper != "" else ("HYPER READY" if dk != loc else "")
		ship.holo["right"].text = "PLANET\n%s  %s\n%s" % [dest_name().to_upper(), line, ready]
		ship.holo["left"].modulate = Color("#ff7a3d") if x10 or hyper != "" else Color(0.45, 0.9, 1.0)
	var st := "HYPERSPEED TO %s" % DEST_NAMES[hyper_to].to_upper() if hyper != "" else ("AUTOPILOT: TO EARTH" if auto == "earth" else ("RE-ENTRY" if plasma > 0.2 else "FLYING"))
	ship.holo["top"].text = "%s   %s   %s" % [here.to_upper(), st, "EASY" if assist else "PRO"]


func hud(ui) -> void:
	ui.set_hud_kind(hud_kind())
	var v := vel.length()
	ui.l_speed.text = str(int(v))
	ui.thr_bar.value = thr
	ui.tag_assist.text = "EASY" if assist else "PRO"
	ui.tag_flaps.add_theme_color_override("font_color", Color("#a9acd0"))
	var d := Basis(q).inverse() * Vector3.FORWARD
	if _battle_on():
		ui.l_alt.text = str(score)
		ui.l_vs.text = "SHIELD %d%%  ·  HULL %d%%" % [int(shield), int(hull)]
		ui.l_hdg.text = str(maxi(wave, 1))
		ui.tag_flaps.text = "BOOST %d%%" % int(boost_e * 100.0)
		ui.tag_brake.text = "FIRE"
		ui.tag_brake.add_theme_color_override("font_color", Color("#ff4c00") if firing else Color("#a9acd0"))
		ui.l_gate.text = "%d drone%s" % [enemies.size(), "" if enemies.size() == 1 else "s"] if not enemies.is_empty() else "Next wave"
		if not target.is_empty():
			d = Basis(q).inverse() * ((target["pos"] as Vector3) - pos)
			ui.l_gate_t.text = "nearest %d m  ·  best %d" % [int(d.length()), best]
		else:
			ui.l_gate_t.text = "%.0f s  ·  best %d" % [maxf(wave_t, 0.0), best]
	else:
		ui.l_alt.text = metres(pos.distance_to(pc) - pr)
		ui.l_vs.text = "%s  ·  x%d" % [DEST_NAMES[loc].to_upper(), int(round(x10_factor()))]
		ui.l_hdg.text = "%03d°" % heading_of(Basis(q))
		ui.tag_flaps.text = "x10 ON" if x10 else "x10 OFF"
		if x10:
			ui.tag_flaps.add_theme_color_override("font_color", Color("#ff4c00"))
		ui.tag_brake.text = "HYPERSPEED" if hyper != "" else ("HYPER READY" if dest_key() != loc else "")
		ui.tag_brake.add_theme_color_override("font_color", Color("#ff4c00") if hyper != "" else Color("#a9acd0"))
		ui.l_gate.text = "Planet: %s" % dest_name()
		ui.l_gate_t.text = "you're here" if dest_key() == loc else distance_text(loc, dest_key())
		if dest_key() != loc:
			d = Basis(q).inverse() * _dest_dir(dest_key())
	ui.arrow_angle = rad_to_deg(atan2(d.x, d.y))
	ui.arrow.queue_redraw()
	var m := msg if msg_t > 0.0 else ""
	if m == "" and hull < 35.0 and not dead and _battle_on():
		m = "HULL DAMAGED"
	ui.set_message(m, m.begins_with("HULL") or m == "IMPACT!" or m == "TURN BACK")


func camera_far() -> float:
	return 260000.0


func set_vr(on: bool) -> void:
	super.set_vr(on)
	if env != null:
		env.ssao_enabled = not on and quality != "low"


func _cam_fov_extra() -> float:
	return (8.0 if boosting else 0.0) + x10_k * 6.0 + streak * 18.0


func _after_camera(cam: Camera3D) -> void:
	_place_space(cam.global_position)


func follow_camera(p: Vector3) -> void:
	_place_space(p)


## Stars, the other planets and the space dust stay round the camera (the dust wraps in a 160 m box so you
## see your speed; it is hidden at hyperspeed and x10, where it would only flicker).
func _place_space(cam_pos: Vector3) -> void:
	if stars != null:
		stars.global_position = cam_pos
	for k in far:
		var mi: MeshInstance3D = far[k]
		if mi.visible:
			mi.global_position = cam_pos + (far_dir[k] as Vector3) * FAR_D
			mi.scale = Vector3.ONE * float(far_r[k])
	if dust != null:
		dust.visible = hyper == "" and x10_k < 0.3
		var mm := dust.multimesh
		var box := 160.0
		for k in dust_pos.size():
			var p: Vector3 = dust_pos[k]
			var rel := Vector3(fposmod(p.x - cam_pos.x, box), fposmod(p.y - cam_pos.y, box), fposmod(p.z - cam_pos.z, box)) - Vector3.ONE * box * 0.5
			mm.set_instance_transform(k, Transform3D(Basis(), cam_pos + rel))
		dust.global_position = Vector3.ZERO
	# the blue ring round the planet you have chosen
	if dest_mark != null:
		var dk := dest_key()
		var show := running and dk != loc and hyper == "" and not _battle_on()
		dest_mark.visible = show
		dest_lbl.visible = show
		if show:
			var dd := _dest_dir(dk)
			var p := cam_pos + dd * 3000.0
			dest_mark.global_position = p
			dest_mark.scale = Vector3.ONE * 150.0
			dest_lbl.global_position = p - Basis(q).y * 120.0
			dest_lbl.pixel_size = 0.35
			dest_lbl.text = "%s  ·  %s" % [DEST_NAMES[dk], distance_text(loc, dk)]
