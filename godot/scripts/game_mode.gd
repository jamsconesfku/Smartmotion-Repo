class_name GameMode
extends Node3D
## Base for the extra game modes (Racing, Space). Each mode builds its own world (lighting, scenery, vehicle)
## and runs its own rules; main.gd keeps the menus, input devices, cameras, VR and the motion rig link.
## While a mode is active the Duxford world is hidden and not updated.

signal finished(title: String, label: String, text: String, big: String)
signal toast(text: String, secs: float)

var built := false
var env: Environment          # put on the camera (overrides the Duxford sky and fog)
var vehicle: Node3D           # the VR origin is parented here (moves with the car / ship)
var eye := Vector3.ZERO       # driver's / pilot's eye, in the vehicle's frame
var world_ref: World
var quality := "high"
var vr := false
var running := false          # false in the menu showcase
var cockpit := false          # cockpit camera (always in VR)
var tel_frame := {}           # for the motion rig (same field names as the flight frame)
var thr_set := -1.0           # when 0..1, main.gd sets its throttle to this (then puts it back to -1)


func build(w: World, q: String) -> void:
	world_ref = w
	quality = q
	built = true


## Menu background: the vehicle parked, the camera circling it.
func showcase() -> void:
	running = false


func start() -> void:
	running = true


func step(_dt: float, _inp: Dictionary) -> void:
	pass


## Called every frame in the menu too (things that move on their own).
func idle(_dt: float) -> void:
	pass


## Called every frame with the camera (or headset) position.
func follow_camera(_p: Vector3) -> void:
	pass


func camera_far() -> float:
	return 600000.0   # v1.17.1: past the horizon (the world modes: racing, coaster)


## Desktop cameras. Return true if the camera was placed.
func place_camera(_cam: Camera3D, _cam_mode: String, _dt: float, _orbit: Dictionary) -> void:
	pass


func set_cockpit(on: bool) -> void:
	cockpit = on


func set_vr(on: bool) -> void:
	vr = on


## Where a VR hand holds the controls (global), or an identity transform with reach 0 if there is nothing to hold.
func grip(_side: String) -> Array:
	return [Transform3D(), 0.0]


func hud(_ui) -> void:
	pass


## Engine sound: [rpm 0..1, load 0..1, speed m/s]
func sound() -> Array:
	return [0.0, 0.0, 0.0]


func camera_modes() -> Array:
	return ["chase", "cockpit", "orbit"]


## True for games that take place in the Duxford world (it stays visible and keeps loading scenery).
func uses_world() -> bool:
	return false


func mode_name() -> String:
	return ""


## Which set of labels the HUD boxes use (ui.gd set_hud_kind).
func hud_kind() -> String:
	return mode_name()


## True for games that stay in the Duxford world when another game runs (the circuit, the coaster).
func parked_in_world() -> bool:
	return uses_world()


## Throttle at the start (keyboard, gamepad and VR stick throttle).
func start_throttle() -> float:
	return 0.5


## A VR fingertip (global): 0 = nothing near, 1 = near something to press (the hand points), 2 = just pressed.
func touch(_side: String, _tip: Vector3) -> int:
	return 0


## Fades the whole view (alpha 0 = clear), e.g. when going between Earth and space.
func fade_color() -> Color:
	return Color(0, 0, 0, 0)


## Builds a telemetry frame for the motion rig from the vehicle's motion.
## basis: vehicle orientation; vel: world velocity (m/s); w_body: angular velocity in the vehicle frame (rad/s);
## acc_body: felt acceleration in the vehicle frame (m/s², gravity included).
func make_tel(t: float, paused: bool, crashed: bool, b: Basis, pos: Vector3, vel: Vector3, w_body: Vector3, acc_body: Vector3, speed_kt: float, extra: Dictionary) -> void:
	var fwd := -b.z
	var pitch := rad_to_deg(asin(clampf(fwd.y, -1.0, 1.0)))
	var right := b.x
	var roll := rad_to_deg(atan2(-right.y, b.y.y))
	var hdg := fposmod(rad_to_deg(atan2(fwd.x, -fwd.z)), 360.0)
	var vb := b.inverse() * vel
	var g := 9.81
	tel_frame = {
		"v": 1, "t": snappedf(t, 0.001), "aircraft": mode_name(), "paused": paused, "crashed": crashed,
		"pos": {"x": snappedf(pos.x, 0.01), "y": snappedf(pos.y, 0.01), "z": snappedf(pos.z, 0.01)},
		"att": {"pitch_deg": snappedf(pitch, 0.01), "roll_deg": snappedf(roll, 0.01), "heading_deg": snappedf(hdg, 0.01)},
		"rate": {"roll_dps": snappedf(-rad_to_deg(w_body.z), 0.01), "pitch_dps": snappedf(rad_to_deg(w_body.x), 0.01), "yaw_dps": snappedf(-rad_to_deg(w_body.y), 0.01)},
		"vel_body": {"surge": snappedf(-vb.z, 0.01), "sway": snappedf(vb.x, 0.01), "heave": snappedf(vb.y, 0.01)},
		"g_felt": {"surge": snappedf(-acc_body.z / g, 0.001), "sway": snappedf(acc_body.x / g, 0.001), "heave": snappedf(acc_body.y / g, 0.001)},
		"ias_kt": snappedf(speed_kt, 0.1), "gs_kt": snappedf(speed_kt, 0.1),
	}
	tel_frame.merge(extra)


# ---------------------------------------------------------------- saved settings (looked up at run time, so the
# headless checks in tests/ can run these scripts without the Settings autoload)
static func _cfg() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Settings")


static func opt(k: String, def: Variant = null) -> Variant:
	var s := _cfg()
	return s.get_value(k) if s != null else def


static func best_of(k: String) -> float:
	var s := _cfg()
	return float(s.best_time(k)) if s != null else 0.0


static func save_best(k: String, v: float) -> void:
	var s := _cfg()
	if s != null:
		s.set_best_time(k, v)


# ---------------------------------------------------------------- small building helpers
static func mat(c: Color, rough := 0.7, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


static func glow_mat(c: Color, energy := 3.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


static func add_box(parent: Node3D, size: Vector3, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func add_cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, m: Material, rot := Vector3.ZERO, segs := 20) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = segs
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func add_sphere(parent: Node3D, r: float, pos: Vector3, m: Material, scale_v := Vector3.ONE, segs := 24) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = segs
	sm.rings = segs / 2
	mi.mesh = sm
	mi.material_override = m
	mi.position = pos
	mi.scale = scale_v
	parent.add_child(mi)
	return mi


## A rod between two points (local to parent).
static func add_rod(parent: Node3D, a: Vector3, b: Vector3, r: float, m: Material, segs := 8) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = a.distance_to(b)
	cm.radial_segments = segs
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = m
	var d := (b - a).normalized()
	var up := Vector3.UP if absf(d.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var x := up.cross(d).normalized()
	mi.transform = Transform3D(Basis(x, d, x.cross(d)), (a + b) * 0.5)
	parent.add_child(mi)
	return mi


## A tube along a path of points (local), e.g. the racing car's halo.
static func tube_mesh(pts: Array, r: float, col: Color, segs := 10) -> ArrayMesh:
	var k := MeshKit.new()
	var rings: Array = []
	for i in pts.size():
		var p: Vector3 = pts[i]
		var t: Vector3 = (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var up := Vector3.UP if absf(t.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
		var nx := up.cross(t).normalized()
		var ny := t.cross(nx)
		var ring: Array = []
		for s in segs:
			var a := TAU * s / segs
			var n := nx * cos(a) + ny * sin(a)
			ring.append([p + n * r, n])
		rings.append(ring)
	for i in pts.size() - 1:
		for s in segs:
			var s2 := (s + 1) % segs
			var A: Array = rings[i][s]
			var B: Array = rings[i][s2]
			var C: Array = rings[i + 1][s2]
			var D: Array = rings[i + 1][s]
			k.add_smooth_tri(A[0], B[0], C[0], A[1], B[1], C[1], col, col, col)
			k.add_smooth_tri(A[0], C[0], D[0], A[1], C[1], D[1], col, col, col)
	return k.build()


static func label3d(parent: Node3D, text: String, size: int, pos: Vector3, col := Color.WHITE, px := 0.001, italic := true) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = load("res://assets/fonts/BarlowSemiCondensed-ExtraBoldItalic.ttf" if italic else "res://assets/fonts/Barlow-SemiBold.ttf")
	l.font_size = size
	l.pixel_size = px
	l.modulate = col
	l.outline_size = 0
	l.position = pos
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.double_sided = false
	parent.add_child(l)
	return l
