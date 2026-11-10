class_name AircraftModel
extends Node3D
## The aircraft you fly: built from code (fuselage lathe, wings, tail, gear, prop) in SmartMotion livery, plus the cockpit.
## Body axes: x right, y up, z back (nose is -z), origin at the centre of gravity.

var key := "trainer"
var fus := Node3D.new()        # shown from outside, hidden in the cockpit view
var outer := Node3D.new()      # wings, tail, gear: always shown
var cockpit_node := Node3D.new()
var prop := Node3D.new()
var blades: Array = []
var disc: MeshInstance3D
var wheels: Array = []
var ail_l := Node3D.new()
var ail_r := Node3D.new()
var elevator := Node3D.new()
var rudder := Node3D.new()
var pilot_nodes: Array = []
var instruments: Instruments
var yoke := Node3D.new()
var eye := Vector3.ZERO
var logo: Texture2D

static func C(hex: String) -> Color:
	return Color(hex).srgb_to_linear()

func _paint_mat(rough := 0.35, metal := 0.15) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	m.metallic = metal
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.clearcoat_enabled = true   # glossy lacquer: sharp sun glints like real aircraft paint
	m.clearcoat = 0.6
	m.clearcoat_roughness = 0.08
	return m

func _solid(col: Color, rough := 0.6, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m

func _mi(mesh: Mesh, mat: Material, parent: Node3D, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = mat
	n.position = pos
	n.rotation = rot
	parent.add_child(n)
	return n

func _box(sz: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = sz
	return b

func _cyl(r_top: float, r_bot: float, h: float, segs := 16) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c

func _sphere(r: float, rs := 16) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = rs
	s.rings = rs / 2
	return s

func radius_at(profile: Array, z: float) -> float:
	for i in range(profile.size() - 1):
		var a: Array = profile[i]
		var b: Array = profile[i + 1]
		if z >= a[0] and z <= b[0]:
			return float(a[1]) + (float(b[1]) - float(a[1])) * (z - float(a[0])) / (float(b[0]) - float(a[0]))
	return 0.1

func _decal(w: float, h: float) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	var m := StandardMaterial3D.new()
	m.albedo_texture = logo
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.3
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.5
	var n := MeshInstance3D.new()
	n.mesh = q
	n.material_override = m
	return n

func build(aircraft_key: String, logo_tex: Texture2D, with_cockpit := true) -> void:
	key = aircraft_key
	logo = logo_tex
	add_child(fus)
	add_child(outer)
	add_child(cockpit_node)
	var white := C("#f2f4fa")
	var navy := C("#0a0b4a")
	var orange := C("#ff4c00")
	var grey := C("#bcc0d4")
	var paint := _paint_mat()
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.55, 0.75, 0.95, 0.35)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var dark := _solid(Color(0.05, 0.05, 0.06), 0.8)
	var navy_m := _solid(navy, 0.4)
	var orange_m := _solid(orange, 0.4)
	var steel := _solid(Color(0.4, 0.42, 0.5), 0.4, 0.6)

	if key == "trainer":
		var profile := [[-2.4, 0.0], [-2.35, 0.18], [-2.1, 0.36], [-1.6, 0.5], [-0.9, 0.62], [0.2, 0.66], [1.4, 0.55], [2.8, 0.4], [4.4, 0.26], [5.9, 0.12]]
		var fm := MeshKit.lathe(profile, 20, func(n: Vector3, _p: Vector3):
			if n.y > 0.3: return white
			if n.y < -0.5: return navy
			if absf(n.y) < 0.18: return orange
			return navy if n.y < 0.0 else white)
		_mi(fm, paint, fus)
		var canopy := _mi(_sphere(1.0), glass, fus, Vector3(0, 0.6, -0.25))
		canopy.scale = Vector3(0.52, 0.4, 1.3)
		_mi(_cyl(0.4, 0.46, 0.5), orange_m, fus, Vector3(0, 0, -2.2), Vector3(PI / 2, 0, 0))
		var wing := MeshKit.slab_xf([[0.0, 1.0], [5.5, 0.85], [5.5, -0.35], [0.0, -0.7]], 0.14, white, grey, white)
		for s in [1.0, -1.0]:
			var wn := _mi(wing, paint, outer, Vector3(0, 0.97, 0))
			if s < 0.0:
				wn.scale.x = -1.0
			var strut := _mi(_box(Vector3(0.07, 1.25, 0.07)), _solid(white, 0.5), outer, Vector3(s * 1.9, 0.35, 0.05), Vector3(0, 0, s * -0.62))
			strut.name = "strut"
			_mi(_box(Vector3(0.6, 0.16, 0.5)), orange_m, outer, Vector3(s * 5.55, 0.97, 0.45))
			var ail := ail_r if s > 0.0 else ail_l
			ail.position = Vector3(s * 4.1, 0.97, 0.05)
			outer.add_child(ail)
			_mi(_box(Vector3(2.1, 0.05, 0.36)), navy_m, ail, Vector3(0, 0, 0.18))
		var stab := MeshKit.slab_xf([[0.0, -4.7], [1.8, -4.95], [1.8, -5.5], [0.0, -5.45]], 0.07, white, white, white)
		for s2 in [1.0, -1.0]:
			var sn := _mi(stab, paint, outer, Vector3(0, 0.2, 0))
			if s2 < 0.0:
				sn.scale.x = -1.0
		elevator.position = Vector3(0, 0.2, 5.45)
		outer.add_child(elevator)
		_mi(_box(Vector3(3.5, 0.05, 0.5)), navy_m, elevator, Vector3(0, 0, 0.25))
		_mi(MeshKit.slab_fy([[-4.6, 0.0], [-5.0, 1.35], [-5.45, 1.35], [-5.45, 0.0]], 0.08, white), paint, outer, Vector3(0, 0.2, 0))
		_mi(_box(Vector3(0.1, 0.35, 0.5)), orange_m, outer, Vector3(0, 1.4, 5.1))
		rudder.position = Vector3(0, 0.2, 5.45)
		outer.add_child(rudder)
		_mi(_box(Vector3(0.05, 1.3, 0.45)), navy_m, rudder, Vector3(0, 0.65, 0.22))
		for g in [[-1.15, -1.05, 0.25, 0.28], [1.15, -1.05, 0.25, 0.28], [0.0, -1.05, -1.5, 0.24]]:
			var wr: float = g[3]
			var wh := _mi(_cyl(wr, wr, 0.16, 16), dark, outer, Vector3(g[0], g[1] + wr + 0.08, g[2]), Vector3(0, 0, PI / 2))
			wheels.append(wh)
			_mi(_box(Vector3(0.08, 0.7, 0.08)), steel, outer, Vector3(float(g[0]) * 0.85, g[1] + wr + 0.4, g[2]))
			if g[0] != 0.0:
				var pant := _mi(_sphere(1.0), _solid(white, 0.5), outer, Vector3(float(g[0]) + signf(g[0]) * 0.12, g[1] + wr + 0.08, g[2]))
				pant.scale = Vector3(0.12, 0.34, 0.55)
		prop.position = Vector3(0, 0, -2.5)
		outer.add_child(prop)
		_mi(_cyl(0.0, 0.2, 0.45, 12), orange_m, prop, Vector3(0, 0, -0.18), Vector3(-PI / 2, 0, 0))
		for bi in 2:
			var bl := _mi(_box(Vector3(0.13, 1.95, 0.03)), dark, prop)
			bl.rotation.z = bi * PI / 2.0 + PI / 2.0
			blades.append(bl)
		eye = Vector3(-0.32, 0.5, -0.15)
		if logo != null:
			for s3 in [1.0, -1.0]:
				var rr := radius_at(profile, 2.3)
				var d := _decal(1.7, 0.68)
				d.position = Vector3(s3 * (sqrt(maxf(rr * rr - 0.04, 0.01)) + 0.02), 0.2, 2.3)
				d.rotation = Vector3(0, s3 * PI / 2, 0)
				fus.add_child(d)
	else:
		var profile2 := [[-3.0, 0.0], [-2.95, 0.22], [-2.5, 0.42], [-1.6, 0.55], [-0.4, 0.62], [0.8, 0.55], [2.2, 0.42], [3.8, 0.28], [5.5, 0.14], [5.95, 0.08]]
		var fm2 := MeshKit.lathe(profile2, 20, func(n: Vector3, _p: Vector3):
			if n.y > 0.35: return navy
			if n.y < -0.3: return white
			if absf(n.y) < 0.12: return orange
			return navy if n.y > 0.0 else white)
		_mi(fm2, paint, fus)
		var canopy2 := _mi(_sphere(1.0), glass, fus, Vector3(0, 0.55, 0.1))
		canopy2.scale = Vector3(0.4, 0.34, 1.05)
		var wing2 := MeshKit.slab_xf([[0.0, 1.4], [5.6, 0.2], [5.6, -0.8], [0.0, -1.6]], 0.2, navy, white, white)
		for s in [1.0, -1.0]:
			var wn2 := _mi(wing2, paint, outer, Vector3(0, -0.4, 0))
			if s < 0.0:
				wn2.scale.x = -1.0
			_mi(_box(Vector3(0.5, 0.18, 0.9)), orange_m, outer, Vector3(s * 5.5, -0.4, 0.2))
			var ail2 := ail_r if s > 0.0 else ail_l
			ail2.position = Vector3(s * 4.2, -0.4, 0.5)
			outer.add_child(ail2)
			_mi(_box(Vector3(2.0, 0.05, 0.5)), orange_m, ail2, Vector3(0, 0, 0.25))
		var stab2 := MeshKit.slab_xf([[0.0, -4.6], [2.0, -5.0], [2.0, -5.55], [0.0, -5.4]], 0.07, navy, navy, navy)
		for s4 in [1.0, -1.0]:
			var sn2 := _mi(stab2, paint, outer, Vector3(0, 0.2, 0))
			if s4 < 0.0:
				sn2.scale.x = -1.0
		elevator.position = Vector3(0, 0.2, 5.4)
		outer.add_child(elevator)
		_mi(_box(Vector3(4.0, 0.05, 0.55)), orange_m, elevator, Vector3(0, 0, 0.28))
		_mi(MeshKit.slab_fy([[-4.4, 0.0], [-5.1, 1.6], [-5.4, 1.6], [-5.4, 0.0]], 0.08, white), paint, outer, Vector3(0, 0.2, 0))
		rudder.position = Vector3(0, 0.2, 5.4)
		outer.add_child(rudder)
		_mi(_box(Vector3(0.05, 1.5, 0.55)), navy_m, rudder, Vector3(0, 0.75, 0.28))
		for g2 in [[-1.9, -1.45, -0.2, 0.36], [1.9, -1.45, -0.2, 0.36], [0.0, -1.0, 5.1, 0.14]]:
			var wr2: float = g2[3]
			var wh2 := _mi(_cyl(wr2, wr2, wr2 * 0.55, 14), dark, outer, Vector3(g2[0], g2[1] + wr2 + 0.1, g2[2]), Vector3(0, 0, PI / 2))
			wheels.append(wh2)
			if g2[2] < 1.0:
				_mi(_box(Vector3(0.1, 0.85, 0.12)), steel, outer, Vector3(float(g2[0]) * 0.94, g2[1] + wr2 + 0.55, g2[2]))
		prop.position = Vector3(0, 0, -3.2)
		outer.add_child(prop)
		_mi(_cyl(0.0, 0.3, 0.75, 14), orange_m, prop, Vector3(0, 0, -0.3), Vector3(-PI / 2, 0, 0))
		for bi2 in 3:
			var piv := Node3D.new()
			piv.rotation.z = bi2 * TAU / 3.0
			prop.add_child(piv)
			_mi(_box(Vector3(0.2, 1.75, 0.035)), dark, piv, Vector3(0, 0.875, 0))
			blades.append(piv)
		eye = Vector3(0, 0.6, -0.9)
		if logo != null:
			for s5 in [1.0, -1.0]:
				var d2 := _decal(1.0, 0.4)
				d2.position = Vector3(s5 * 0.07, 0.95, 5.0)
				d2.rotation = Vector3(0, s5 * PI / 2, 0)
				outer.add_child(d2)

	# spinning prop disc
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.12, 0.13, 0.17, 0.0)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var dq := QuadMesh.new()
	dq.size = Vector2(1.9, 1.9) if key == "trainer" else Vector2(3.5, 3.5)
	disc = _mi(dq, dm, prop)
	# pilot
	var skin := _solid(Color(0.85, 0.65, 0.55), 0.6)
	var p1 := _mi(_sphere(0.13, 10), skin, fus, eye + Vector3(0, 0.12, 0.1))
	var p2 := _mi(_sphere(0.145, 10), orange_m, fus, eye + Vector3(0, 0.135, 0.1))
	pilot_nodes = [p1, p2]
	if with_cockpit:
		_build_cockpit()


func _build_cockpit() -> void:
	var fighter := key == "fighter"
	var dark := _solid(Color(0.08, 0.085, 0.1), 0.7)
	var pw := 0.7 if fighter else 1.1
	var ph := 0.44 if fighter else 0.42
	var vp := SubViewport.new()
	vp.size = Vector2i(1024, int(1024.0 * ph / pw))
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.disable_3d = true
	vp.transparent_bg = false
	instruments = Instruments.new()
	instruments.size = Vector2(vp.size)
	vp.add_child(instruments)
	cockpit_node.add_child(vp)
	var pm := StandardMaterial3D.new()
	pm.albedo_texture = vp.get_texture()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var q := QuadMesh.new()
	q.size = Vector2(pw, ph)
	var cx := eye.x + (0.0 if fighter else 0.32)
	var panel := _mi(q, pm, cockpit_node, Vector3(cx, eye.y - 0.36, eye.z - 0.74), Vector3(-0.4, 0, 0))
	panel.name = "panel"
	_mi(_box(Vector3(pw + 0.3, 0.06, 0.42)), dark, cockpit_node, Vector3(cx, eye.y - 0.1, eye.z - 0.8), Vector3(-0.1, 0, 0))
	_mi(_box(Vector3(pw + 0.5, 0.35, 0.8)), dark, cockpit_node, Vector3(cx, eye.y - 0.62, eye.z - 1.05))
	_mi(_box(Vector3(pw + 0.6, 0.5, 0.3)), dark, cockpit_node, Vector3(cx, eye.y - 0.75, eye.z - 0.35))
	yoke.position = Vector3(eye.x, eye.y - 0.46, eye.z - 0.42)
	cockpit_node.add_child(yoke)
	var steel := _solid(Color(0.17, 0.18, 0.22), 0.5)
	if fighter:
		_mi(_cyl(0.014, 0.018, 0.34, 8), steel, yoke, Vector3(0, 0.15, 0))
		_mi(_sphere(0.04, 8), _solid(C("#ff4c00"), 0.4), yoke, Vector3(0, 0.33, 0))
	else:
		_mi(_cyl(0.02, 0.02, 0.3, 8), steel, yoke, Vector3(0, 0, 0.12), Vector3(PI / 2, 0, 0))
		var rim := TorusMesh.new()
		rim.inner_radius = 0.135
		rim.outer_radius = 0.165
		rim.rings = 20
		rim.ring_segments = 6
		_mi(rim, dark, yoke, Vector3(0, 0.07, 0.3), Vector3(PI / 2, 0, 0))


func set_instruments(nd: Dictionary) -> void:
	if instruments != null:
		instruments.set_data(nd)


func update_visuals(surf: Dictionary, engine: float, dt: float, ias: float) -> void:
	var k := 0.5
	ail_r.rotation.x = -k * float(surf["a"])
	ail_l.rotation.x = k * float(surf["a"])
	elevator.rotation.x = -k * float(surf["e"])
	rudder.rotation.y = k * float(surf["r"])
	prop.rotation.z += (8.0 + engine * 95.0) * dt
	var blur := clampf((engine - 0.2) / 0.5, 0.0, 1.0)
	(disc.material_override as StandardMaterial3D).albedo_color.a = 0.17 * blur
	for b in blades:
		(b as Node3D).visible = blur < 0.8
	for w in wheels:
		(w as Node3D).rotation.x += ias * dt * 3.0


func set_cockpit_view(on: bool) -> void:
	fus.visible = not on
	cockpit_node.visible = on
	disc.visible = not on
