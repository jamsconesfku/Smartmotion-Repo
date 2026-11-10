class_name SpaceShip
extends Node3D
## The player's space fighter, built in code: a sleek fuselage in SmartMotion navy and orange, swept wings with
## guns at the tips, twin engines with glowing exhaust, a bubble canopy, and a cockpit made for VR (seat, panel
## with holographic read-outs, a flight stick and throttle the VR hands hold, and a target pointer).
## Frame: forward -Z, up +Y. About 15 m long.

const EYE := Vector3(0, 1.55, -2.95)

var flames: Array = []
var flame_mats: Array = []
var stick: Node3D
var throttle_lever: Node3D
var holo: Dictionary = {}
var pointer: Node3D
var reticle: Node3D
var guns := [Vector3(-5.2, 0.15, -2.6), Vector3(5.2, 0.15, -2.6)]
var exterior: Array = []          # hidden in the cockpit view where they'd block it
var fx_shader: Shader


func _init() -> void:
	fx_shader = load("res://shaders/space_fx.gdshader")
	_build()


func _paint() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.3
	m.metallic = 0.55
	m.clearcoat_enabled = true
	return m


func paint_navy() -> StandardMaterial3D:
	return GameMode.mat(Color("#0b0d3a"), 0.3, 0.55)


func fx_mat(kind: int, col: Color, energy: float, falloff := 2.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = fx_shader
	m.set_shader_parameter("kind", kind)
	m.set_shader_parameter("color", col)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("falloff", falloff)
	return m


func _build() -> void:
	var navy := Color("#0b0d3a")
	var org := Color("#ff4c00")
	var grey := Color(0.55, 0.58, 0.63)
	var paint := _paint()
	var dark := GameMode.mat(Color(0.03, 0.03, 0.05), 0.5, 0.4)
	var metal := GameMode.mat(Color(0.35, 0.37, 0.4), 0.35, 0.85)
	# fuselage: pointed nose and tapering tail, with an open cockpit tub between them under the canopy
	var col_fn := func(n: Vector3, p: Vector3) -> Color:
		if absf(n.x) > 0.55 and n.y > -0.2 and p.z < 3.0 and p.z > -6.5: return org
		return navy if n.y > -0.3 else grey
	for prof in [[[-8.5, 0.02], [-7.6, 0.35], [-6.0, 0.8], [-4.6, 1.1], [-4.4, 1.12]], [[-1.7, 1.3], [1.5, 1.35], [4.0, 1.15], [5.6, 0.9], [6.2, 0.6]]]:
		var fus := MeshInstance3D.new()
		fus.mesh = MeshKit.lathe(prof, 20, col_fn)
		fus.material_override = paint
		fus.scale = Vector3(1.0, 0.75, 1.0)
		fus.position = Vector3(0, 0.4, 0)
		add_child(fus)
		var end_z: float = prof[-1][0] if prof[0][0] < -8.0 else prof[0][0]
		var end_r: float = prof[-1][1] if prof[0][0] < -8.0 else prof[0][1]
		GameMode.add_cyl(self, end_r, end_r, 0.04, Vector3(0, 0.4, end_z), dark, Vector3(PI / 2.0, 0, 0), 20).scale = Vector3(1.0, 1.0, 0.75)
	# cockpit tub
	for sx: float in [-1.0, 1.0]:
		GameMode.add_box(self, Vector3(0.12, 1.75, 2.8), Vector3(sx * 1.0, 0.375, -3.05), paint_navy())
		GameMode.add_box(self, Vector3(0.16, 0.06, 2.8), Vector3(sx * 1.0, 1.28, -3.05), GameMode.mat(org, 0.4, 0.3))
	GameMode.add_box(self, Vector3(2.0, 0.12, 2.8), Vector3(0, 0.55, -3.05), dark)
	GameMode.add_box(self, Vector3(2.0, 0.1, 2.8), Vector3(0, -0.5, -3.05), paint_navy())
	# wings: swept, with orange tips
	for sx: float in [-1.0, 1.0]:
		var wg := MeshInstance3D.new()
		wg.mesh = MeshKit.slab_xf([[sx * 0.9, 2.5], [sx * 0.9, -3.6], [sx * 5.4, -4.8], [sx * 5.6, -3.0], [sx * 1.4, 4.2]], 0.22, navy, grey, org)
		wg.material_override = paint
		wg.position = Vector3(0, 0.15, 0)
		add_child(wg)
		var tip := MeshInstance3D.new()
		tip.mesh = MeshKit.slab_xf([[sx * 4.6, -3.2], [sx * 4.6, -4.55], [sx * 5.5, -4.8], [sx * 5.6, -3.0]], 0.24, org, org, org)
		tip.material_override = paint
		tip.position = Vector3(0, 0.16, 0)
		add_child(tip)
		# gun barrels at the wing tips
		GameMode.add_cyl(self, 0.09, 0.12, 2.4, Vector3(sx * 5.2, 0.15, -1.6), metal, Vector3(PI / 2.0, 0, 0), 10)
		GameMode.add_cyl(self, 0.18, 0.18, 1.2, Vector3(sx * 5.2, 0.15, -0.3), dark, Vector3(PI / 2.0, 0, 0), 12)
		# tail fins
		var fin := MeshInstance3D.new()
		fin.mesh = MeshKit.slab_fy([[-3.6, 0.0], [-6.2, 0.0], [-6.8, 2.2], [-5.7, 2.3]], 0.15, navy)
		fin.material_override = paint
		fin.position = Vector3(sx * 1.6, 0.9, 0)
		fin.rotation.z = -sx * 0.35
		add_child(fin)
		# engines
		var eng := GameMode.add_cyl(self, 0.75, 0.62, 4.4, Vector3(sx * 1.55, 0.25, 4.0), metal, Vector3(PI / 2.0, 0, 0), 20)
		exterior.append(eng)
		GameMode.add_cyl(self, 0.66, 0.66, 0.3, Vector3(sx * 1.55, 0.25, 6.25), dark, Vector3(PI / 2.0, 0, 0), 20)
		var glow := GameMode.add_cyl(self, 0.56, 0.56, 0.05, Vector3(sx * 1.55, 0.25, 6.38), GameMode.glow_mat(Color(1.0, 0.55, 0.2), 3.0), Vector3(PI / 2.0, 0, 0), 20)
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var fl := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.55
		cm.bottom_radius = 0.05
		cm.height = 1.0
		cm.radial_segments = 16
		cm.rings = 4
		fl.mesh = cm
		var fm := fx_mat(1, Color(1.0, 0.45, 0.12), 3.0)
		fl.material_override = fm
		fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var fpiv := Node3D.new()
		fpiv.position = Vector3(sx * 1.55, 0.25, 6.4)
		add_child(fpiv)
		fl.rotation.x = PI / 2.0
		fl.position = Vector3(0, 0, 0.5)
		fpiv.add_child(fl)
		flames.append(fpiv)
		flame_mats.append(fm)
	# SmartMotion lettering on the sides
	for sx: float in [-1.0, 1.0]:
		var l := GameMode.label3d(self, "SMARTMOTION", 90, Vector3(sx * 1.37, 0.42, 1.6), Color.WHITE, 0.012)
		l.rotation.y = PI / 2.0 * sx
		exterior.append(l)
	# canopy
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.4, 0.6, 0.8, 0.18)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.02
	glass.metallic = 0.5
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var can := GameMode.add_sphere(self, 1.0, Vector3(0, 1.25, -3.05), glass, Vector3(1.0, 0.58, 1.55), 24)
	can.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# canopy frame
	var frame_pts: Array = []
	for k in 13:
		var a := PI * k / 12.0
		frame_pts.append(Vector3(cos(a) * 0.98, 1.25 + sin(a) * 0.56, -3.75))
	var fr := MeshInstance3D.new()
	fr.mesh = GameMode.tube_mesh(frame_pts, 0.035, Color(0.08, 0.08, 0.1), 8)
	fr.material_override = paint
	add_child(fr)
	_cockpit(dark, metal)


func _cockpit(dark: Material, metal: Material) -> void:
	var seat_m := GameMode.mat(Color(0.12, 0.12, 0.14), 0.8)
	var org_m := GameMode.mat(Color("#ff4c00"), 0.5)
	# seat
	GameMode.add_box(self, Vector3(0.62, 0.12, 0.6), Vector3(0, 0.88, -2.7), seat_m)
	GameMode.add_box(self, Vector3(0.62, 0.95, 0.14), Vector3(0, 1.36, -2.35), seat_m, Vector3(-0.2, 0, 0))
	GameMode.add_box(self, Vector3(0.66, 0.06, 0.16), Vector3(0, 1.8, -2.28), org_m, Vector3(-0.2, 0, 0))
	# cockpit tub sides
	# panel
	var panel := GameMode.add_box(self, Vector3(1.3, 0.42, 0.1), Vector3(0, 1.22, -3.9), dark, Vector3(-0.55, 0, 0))
	panel.name = "panel"
	GameMode.add_box(self, Vector3(1.4, 0.05, 0.5), Vector3(0, 1.4, -4.1), dark)
	# screens with live read-outs
	var cyan := Color(0.45, 0.9, 1.0)
	for k in 3:
		var x := -0.36 + k * 0.36
		var scr := GameMode.add_box(self, Vector3(0.3, 0.2, 0.01), Vector3(x, 1.23, -3.84), GameMode.glow_mat(Color(0.02, 0.06, 0.1), 1.0), Vector3(-0.55, 0, 0))
		scr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holo["left"] = _holo_text(Vector3(-0.36, 1.235, -3.83), cyan, 34)
	holo["mid"] = _holo_text(Vector3(0.0, 1.235, -3.83), Color("#ff4c00"), 34)
	holo["right"] = _holo_text(Vector3(0.36, 1.235, -3.83), cyan, 34)
	# flight stick (right hand) and throttle (left hand)
	stick = Node3D.new()
	stick.position = Vector3(0.0, 0.76, -3.3)
	add_child(stick)
	GameMode.add_cyl(stick, 0.02, 0.025, 0.42, Vector3(0, 0.21, 0), metal, Vector3.ZERO, 10)
	GameMode.add_cyl(stick, 0.032, 0.036, 0.14, Vector3(0, 0.46, 0.0), GameMode.mat(Color(0.06, 0.06, 0.07), 0.9), Vector3.ZERO, 12)
	GameMode.add_sphere(stick, 0.014, Vector3(0, 0.54, -0.02), GameMode.glow_mat(Color(1, 0.2, 0.05), 2.0), Vector3.ONE, 8)
	throttle_lever = Node3D.new()
	throttle_lever.position = Vector3(-0.55, 1.05, -3.15)
	add_child(throttle_lever)
	GameMode.add_box(self, Vector3(0.12, 0.05, 0.4), Vector3(-0.55, 1.03, -3.15), dark)
	GameMode.add_cyl(throttle_lever, 0.015, 0.015, 0.16, Vector3(0, 0.08, 0), metal, Vector3.ZERO, 8)
	GameMode.add_box(throttle_lever, Vector3(0.06, 0.05, 0.09), Vector3(0, 0.17, 0), org_m)
	# target pointer: a small arrow on top of the panel that points at the nearest enemy
	pointer = Node3D.new()
	pointer.position = Vector3(0, 1.5, -4.05)
	add_child(pointer)
	var cone := GameMode.add_cyl(pointer, 0.0, 0.035, 0.12, Vector3.ZERO, GameMode.glow_mat(Color(1, 0.2, 0.1), 2.5), Vector3(-PI / 2.0, 0, 0), 10)
	cone.position = Vector3(0, 0, -0.03)
	GameMode.add_sphere(self, 0.04, Vector3(0, 1.5, -4.05), GameMode.glow_mat(Color(0.3, 0.6, 1.0), 0.4), Vector3.ONE, 10)
	# gun sight: an orange ring well out in front (no depth test so it is always visible)
	reticle = Node3D.new()
	reticle.position = Vector3(0, EYE.y, -60.0)
	add_child(reticle)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.05
	tm.outer_radius = 1.2
	tm.rings = 40
	tm.ring_segments = 4
	ring.mesh = tm
	var rm := GameMode.glow_mat(Color(1.0, 0.45, 0.1), 2.0)
	rm.no_depth_test = true
	rm.render_priority = 5
	ring.material_override = rm
	ring.rotation.x = PI / 2.0
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	reticle.add_child(ring)
	var dotm := GameMode.add_sphere(reticle, 0.12, Vector3.ZERO, rm, Vector3.ONE, 8)
	dotm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _holo_text(pos: Vector3, col: Color, size: int) -> Label3D:
	var l := GameMode.label3d(self, "", size, pos, col, 0.0011, false)
	l.rotation.x = -0.55
	l.no_depth_test = false
	l.outline_size = 0
	return l


func set_first_person(on: bool) -> void:
	reticle.scale = Vector3.ONE * (1.0 if on else 2.2)   # bigger in the chase view (seen from further back)


func stick_grip() -> Transform3D:
	var g := Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)), Vector3(0, 0.47, 0.0))
	return stick.global_transform * g.rotated_local(Vector3(0, 0, 1), -0.45).rotated_local(Vector3(1, 0, 0), 0.3)


func throttle_grip() -> Transform3D:
	var g := Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)), Vector3(0, 0.17, 0.0))
	return throttle_lever.global_transform * g.rotated_local(Vector3(1, 0, 0), 0.9)


func animate(thr: float, boost: bool, pitch: float, roll: float, dt: float) -> void:
	var k := 0.25 + thr * 1.1 + (1.4 if boost else 0.0)
	for i in flames.size():
		var f: Node3D = flames[i]
		f.scale = Vector3(1.0, 1.0, lerpf(f.scale.z, k * 2.6, 1.0 - exp(-dt * 8.0)))
		(flame_mats[i] as ShaderMaterial).set_shader_parameter("energy", 2.0 + k * 2.5)
		(flame_mats[i] as ShaderMaterial).set_shader_parameter("color", Color(0.4, 0.6, 1.0) if boost else Color(1.0, 0.45, 0.12))
	stick.rotation = Vector3(-pitch * 0.3, 0, -roll * 0.3)
	throttle_lever.position.z = -3.15 - (thr - 0.5) * 0.22
