class_name SpaceShip
extends Node3D
## The player's space fighter, built in code: a sleek fuselage in SmartMotion navy and orange, swept wings with
## guns at the tips, twin engines with glowing exhaust, a bubble canopy, and a cockpit made for VR (seat, panel
## with holographic read-outs, a flight stick and throttle the VR hands hold, and a target pointer).
## Frame: forward -Z, up +Y. About 15 m long.
## v1.16.0: a console of eight buttons below the screens that you press with a fingertip in VR (lean forward
## to reach it), landing legs, headlights, the hyperspeed tunnel and streaks, and the glow of re-entry.

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
	VehicleLook.apply(self, "ship")   # v1.17.0: panel seams, brushed metal, leather, clearer glass


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
	var panel := GameMode.add_box(self, Vector3(1.3, 0.42, 0.1), Vector3(0, 1.15, -3.9), dark, Vector3(-0.55, 0, 0))
	panel.name = "panel"
	GameMode.add_box(self, Vector3(1.4, 0.05, 0.5), Vector3(0, 1.33, -4.1), dark)
	# screens with live read-outs
	var cyan := Color(0.45, 0.9, 1.0)
	for k in 3:
		var x := -0.36 + k * 0.36
		var scr := GameMode.add_box(self, Vector3(0.3, 0.2, 0.01), Vector3(x, 1.16, -3.84), GameMode.glow_mat(Color(0.02, 0.06, 0.1), 1.0), Vector3(-0.55, 0, 0))
		scr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holo["left"] = _holo_text(Vector3(-0.36, 1.165, -3.83), cyan, 27)
	holo["mid"] = _holo_text(Vector3(0.0, 1.165, -3.83), Color("#ff4c00"), 27)
	holo["right"] = _holo_text(Vector3(0.36, 1.165, -3.83), cyan, 27)
	# status strip along the top of the panel (where you are, what the ship is doing)
	holo["top"] = GameMode.label3d(self, "", 30, Vector3(0, 1.395, -3.86), Color("#ff7a3d"), 0.0009, false)
	holo["top"].rotation.x = -0.25
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
	_console(dark, org_m)
	_legs(metal, dark)
	_lamps()
	_hyper_fx()
	_plasma()


func _holo_text(pos: Vector3, col: Color, size: int) -> Label3D:
	var l := GameMode.label3d(self, "", size, pos, col, 0.0011, false)
	l.rotation.x = -0.55
	l.no_depth_test = false
	l.outline_size = 0
	return l


var first_person := false


func set_first_person(on: bool) -> void:
	first_person = on
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
	_tick_buttons(dt)
	for l in legs:
		var n: Node3D = l
		n.rotation.x = -(1.0 - leg_k) * 1.45
		n.visible = leg_k > 0.03


# ---------------------------------------------------------------- v1.16.0: the button console
## [id, label, colour, column 0..3, row (0 = the far row, 1 = the near row)]
const BUTTONS := [
	["hyper", "HYPERSPEED", Color(0.3, 0.6, 1.0), 0, 0],
	["x10", "x10 SPEED", Color(1.0, 0.3, 0.0), 1, 0],
	["prev", "< PLANET", Color(0.45, 0.9, 1.0), 2, 0],
	["next", "PLANET >", Color(0.45, 0.9, 1.0), 3, 0],
	["land", "LAND", Color(0.3, 1.0, 0.45), 0, 1],
	["auto", "TO SPACE", Color(0.75, 0.45, 1.0), 1, 1],
	["assist", "EASY", Color(0.95, 0.95, 0.95), 2, 1],
	["lights", "LIGHTS", Color(1.0, 0.82, 0.3), 3, 1],
]
const CONSOLE_POS := Vector3(0, 0.97, -3.57)
const CONSOLE_TILT := 0.75          # tipped towards the pilot
const CAP := Vector3(0.082, 0.024, 0.062)
const CAP_Y := 0.016                # height of a cap's middle above the console top

var console: Node3D
var buttons := {}
var legs: Array = []
var leg_k := 1.0                    # landing legs: 1 down, 0 folded away
var lamps: Array = []
var hyper_root: Node3D
var tube: MeshInstance3D
var tunnel_mat: ShaderMaterial
var streaks: MultiMeshInstance3D
var streak_pos: Array = []          # [x, y, z, speed factor]
var plasma: MeshInstance3D
var plasma_mat: ShaderMaterial


func _console(dark: Material, org_m: Material) -> void:
	console = Node3D.new()
	console.position = CONSOLE_POS
	console.rotation.x = CONSOLE_TILT
	add_child(console)
	GameMode.add_box(console, Vector3(1.1, 0.05, 0.34), Vector3(0, -0.025, 0), dark)
	GameMode.add_box(console, Vector3(1.12, 0.014, 0.014), Vector3(0, 0.0, 0.17), org_m)
	GameMode.add_box(self, Vector3(0.46, 0.36, 0.1), Vector3(0, 0.72, -3.72), dark)   # its stand
	var bezel := GameMode.mat(Color(0.12, 0.12, 0.14), 0.4, 0.6)
	for b in BUTTONS:
		var col: Color = b[2]
		var base := Vector3(-0.405 + float(b[3]) * 0.27, 0.0, -0.075 if int(b[4]) == 0 else 0.065)
		GameMode.add_box(console, Vector3(CAP.x + 0.022, 0.008, CAP.z + 0.022), base + Vector3(0, 0.004, 0), bezel)
		var m := StandardMaterial3D.new()
		m.albedo_color = col * 0.35
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 0.45
		m.roughness = 0.3
		var cap := GameMode.add_box(console, CAP, base + Vector3(0, CAP_Y, 0), m)
		cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var lbl := GameMode.label3d(console, str(b[1]), 30, base + Vector3(0, 0.0045, CAP.z * 0.5 + 0.022), Color(0.9, 0.92, 1.0), 0.00055, false)
		lbl.rotation.x = -PI / 2.0
		buttons[b[0]] = {"cap": cap, "mat": m, "col": col, "lbl": lbl, "base": base, "on": false, "t": 0.0, "armed": {"l": true, "r": true}}


## A fingertip (global position) at the console. Returns [id of a button it has just pressed or "", near]:
## near is true while the hand is over the console (the hand then points its finger).
## A button presses once when the fingertip pushes into its cap, and again only after the finger has left it.
func touch(tip: Vector3, side: String) -> Array:
	var lp := console.global_transform.affine_inverse() * tip
	var near := absf(lp.x) < 0.62 and absf(lp.z) < 0.24 and lp.y > -0.04 and lp.y < 0.18
	var hit := ""
	for id in buttons:
		var b: Dictionary = buttons[id]
		var d: Vector3 = lp - (b["base"] as Vector3)
		var inside := absf(d.x) < CAP.x * 0.5 + 0.012 and absf(d.z) < CAP.z * 0.5 + 0.012
		var top := CAP_Y + CAP.y * 0.5 + VRHand.R   # v1.18.0: the hand is a ball; it presses when its surface touches
		if inside and d.y < top + 0.004 and d.y > -0.035:
			if b["armed"][side]:
				b["armed"][side] = false
				if hit == "":
					hit = id
		elif not inside or d.y > top + 0.025:
			b["armed"][side] = true
	return [hit, near]


## Where a button is (global), e.g. for the headless checks.
func button_pos(id: String) -> Vector3:
	var b: Dictionary = buttons[id]
	return console.global_transform * ((b["base"] as Vector3) + Vector3(0, CAP_Y + CAP.y * 0.5, 0))


func press_anim(id: String) -> void:
	if buttons.has(id):
		buttons[id]["t"] = 0.2


## Lights a button up (a setting that is on) and changes its label.
func set_button(id: String, on: bool, label := "") -> void:
	if not buttons.has(id):
		return
	var b: Dictionary = buttons[id]
	b["on"] = on
	if label != "" and (b["lbl"] as Label3D).text != label:
		(b["lbl"] as Label3D).text = label


func _tick_buttons(dt: float) -> void:
	for id in buttons:
		var b: Dictionary = buttons[id]
		var t: float = maxf(float(b["t"]) - dt, 0.0)
		b["t"] = t
		var cap: Node3D = b["cap"]
		cap.position.y = CAP_Y - (0.011 if t > 0.0 else 0.0)
		var m: StandardMaterial3D = b["mat"]
		m.emission_energy_multiplier = (2.6 if b["on"] else 0.45) + (3.0 if t > 0.0 else 0.0)


# ---------------------------------------------------------------- landing legs and headlights
func _legs(metal: Material, dark: Material) -> void:
	for spec in [[Vector3(0, -0.45, -5.4), 1.15], [Vector3(-1.55, -0.45, 3.1), 1.15], [Vector3(1.55, -0.45, 3.1), 1.15]]:
		var piv := Node3D.new()
		piv.position = spec[0]
		add_child(piv)
		var ln: float = spec[1]
		GameMode.add_cyl(piv, 0.07, 0.09, ln, Vector3(0, -ln * 0.5, 0), metal, Vector3.ZERO, 10)
		GameMode.add_cyl(piv, 0.3, 0.32, 0.07, Vector3(0, -ln + 0.035, 0), dark, Vector3.ZERO, 16)
		legs.append(piv)


func _lamps() -> void:
	for sx: float in [-1.0, 1.0]:
		var l := SpotLight3D.new()
		l.position = Vector3(sx * 0.55, 0.05, -6.6)
		l.spot_range = 900.0
		l.spot_angle = 24.0
		l.spot_attenuation = 0.6
		l.light_energy = 7.0
		l.light_color = Color(1.0, 0.95, 0.85)
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		lamps.append(l)
		var lens := GameMode.add_sphere(self, 0.13, Vector3(sx * 0.55, 0.05, -6.65), GameMode.glow_mat(Color(1.0, 0.95, 0.8), 0.6), Vector3(1, 1, 0.5), 10)
		lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lamps.append(lens)


func set_lights(on: bool) -> void:
	for l in lamps:
		if l is SpotLight3D:
			(l as SpotLight3D).visible = on
		else:
			((l as MeshInstance3D).material_override as StandardMaterial3D).emission_energy_multiplier = 6.0 if on else 0.6


# ---------------------------------------------------------------- hyperspeed and re-entry effects
func _hyper_fx() -> void:
	hyper_root = Node3D.new()
	add_child(hyper_root)
	tube = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 34.0
	cm.bottom_radius = 34.0
	cm.height = 2000.0
	cm.radial_segments = 48
	cm.rings = 8
	cm.cap_top = false
	cm.cap_bottom = true      # the far end in front: a bright light at the end of the tunnel
	tube.mesh = cm
	tunnel_mat = ShaderMaterial.new()
	tunnel_mat.shader = load("res://shaders/hyperspace.gdshader")
	tunnel_mat.render_priority = 2
	tube.material_override = tunnel_mat
	tube.rotation.x = PI / 2.0          # the tube's +Y runs to the ship's back (+Z)
	tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tube.extra_cull_margin = 4000.0
	tube.visible = false
	hyper_root.add_child(tube)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3(0.14, 0.14, 1.0)
	mm.mesh = bm
	mm.instance_count = 420
	for k in mm.instance_count:
		var a := rng.randf() * TAU
		var r := 9.0 + 170.0 * pow(rng.randf(), 1.6)
		streak_pos.append([cos(a) * r, sin(a) * r, rng.randf_range(-1700.0, 400.0), rng.randf_range(0.75, 1.3)])
	streaks = MultiMeshInstance3D.new()
	streaks.multimesh = mm
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sm.albedo_color = Color(1.1, 1.4, 2.2)
	sm.disable_receive_shadows = true
	streaks.material_override = sm
	streaks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	streaks.extra_cull_margin = 4000.0
	streaks.visible = false
	hyper_root.add_child(streaks)


## stretch 0..1: how long the star streaks are; spd: how fast they rush past (m/s); tunnel 0..1: the tunnel.
func hyper_fx(stretch: float, spd: float, tunnel: float, dt: float) -> void:
	streaks.visible = stretch > 0.01
	if streaks.visible:
		var mm := streaks.multimesh
		var ln := maxf(stretch * 520.0, 0.6)
		for k in streak_pos.size():
			var sp: Array = streak_pos[k]
			var z: float = float(sp[2]) + spd * float(sp[3]) * dt
			if z > 400.0:
				z -= 2100.0
			sp[2] = z
			mm.set_instance_transform(k, Transform3D(Basis().scaled(Vector3(1.0, 1.0, ln)), Vector3(float(sp[0]), float(sp[1]), z)))
	tube.visible = tunnel > 0.005
	if tube.visible:
		tunnel_mat.set_shader_parameter("amount", clampf(tunnel, 0.0, 1.0))


func _plasma() -> void:
	plasma = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.5       # the shader is brightest at the mesh's top: the narrow end, at the nose
	cm.bottom_radius = 9.0
	cm.height = 24.0
	cm.radial_segments = 24
	cm.rings = 6
	cm.cap_top = false
	cm.cap_bottom = false
	plasma.mesh = cm
	plasma_mat = fx_mat(1, Color(1.0, 0.42, 0.12), 0.0, 5.0)   # fades off behind the nose, to nothing at the back
	plasma_mat.set_shader_parameter("uv_len", 2.0)
	plasma.material_override = plasma_mat
	plasma.rotation.x = -PI / 2.0       # the narrow, bright end (mesh top) at the nose
	plasma.position = Vector3(0, 0.3, 3.3)
	plasma.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plasma.visible = false
	add_child(plasma)


## The glow of coming back into the air from space, 0..1.
func set_plasma(k: float) -> void:
	plasma.visible = k > 0.01
	if plasma.visible:
		plasma_mat.set_shader_parameter("energy", 1.6 * k * (0.3 if first_person else 1.0))   # gentler from the seat (VR)
