class_name VRHand
extends Node3D
## A gloved pilot's hand for VR, made in code: palm, jointed fingers and thumb, gauntlet and flight-suit sleeve.
## The fingers close as `curl` goes from 0 (open) to 1 (a fist around a stick).
##
## Hand frame (before placing): the fist closes around a tube along X, centred at the origin; the index finger
## is at -X, the back of the hand faces +Y (palm -Y) and the forearm runs along +Z.
## place() puts that tube on a "grip frame": OpenXR's grip pose (tube along Z, index at -Z, right palm facing -X)
## or the same kind of frame on the control stick or throttle lever.

const GLOVE := Color("#6e5236")     # tan leather flying glove
const CUFF := Color("#4a3624")
const SLEEVE := Color("#2f3b52")    # the pilot's flight suit
const TUBE_C := Vector3(0.0, -0.028, -0.026)   # centre of the closed fist, in the hand's building frame

var left := false
var curl := 0.4
var point := 0.0                    # 0..1: the index finger straightens to point (pressing buttons)
var _fingers: Array = []            # [[joint, joint, joint], fist angles (radians)]
var _geo: Node3D                    # mirrored for the left hand
var _glove_m: StandardMaterial3D


func _init(is_left := false) -> void:
	left = is_left
	_build()


func _m(c: Color, rough := 0.75) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _cap(parent: Node3D, r: float, h: float, pos: Vector3, rot: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = maxf(h, r * 2.0)
	cm.radial_segments = 12
	cm.rings = 3
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, r0: float, r1: float, z0: float, z1: float, mat: Material, y := 0.0) -> void:
	# along +Z from z0 (radius r0) to z1 (radius r1)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r0
	cm.bottom_radius = r1
	cm.height = z1 - z0
	cm.radial_segments = 16
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.rotation.x = PI / 2.0          # cylinder's +Y (top) becomes -Z: top is at z0
	mi.position = Vector3(0, y, (z0 + z1) / 2.0)
	parent.add_child(mi)


func _build() -> void:
	_geo = Node3D.new()
	add_child(_geo)
	var inner := Node3D.new()           # building frame -> tube centre at the origin
	inner.position = -TUBE_C
	_geo.add_child(inner)
	if left:
		_geo.scale = Vector3(1, -1, 1)  # mirror image across the palm: a left hand (see place())
	_glove_m = _m(GLOVE, 0.7)
	var cuff := _m(CUFF, 0.75)
	var sleeve := _m(SLEEVE, 0.9)
	# palm and back of the hand
	var palm := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.074, 0.022, 0.08)
	palm.mesh = bm
	palm.material_override = _glove_m
	palm.position = Vector3(0, 0, -0.004)
	inner.add_child(palm)
	_cap(inner, 0.013, 0.08, Vector3(0, 0.0, -0.041), Vector3(0, 0, PI / 2.0), _glove_m)      # knuckle ridge
	_cap(inner, 0.016, 0.07, Vector3(0, -0.002, 0.03), Vector3(0, 0, PI / 2.0), _glove_m)     # heel of the hand
	_cap(inner, 0.012, 0.075, Vector3(0.033, -0.001, -0.005), Vector3(PI / 2.0, 0, 0), _glove_m)  # outer edge
	# gauntlet and sleeve
	_cyl(inner, 0.032, 0.042, 0.035, 0.115, cuff)
	_cyl(inner, 0.043, 0.047, 0.105, 0.25, sleeve)
	# fingers: x across the knuckles, segment lengths, radius
	var specs := [
		[-0.027, [0.044, 0.026, 0.021], 0.0095, 0.0],
		[-0.009, [0.048, 0.029, 0.022], 0.0098, 0.0],
		[0.009, [0.045, 0.027, 0.021], 0.0093, 0.002],
		[0.026, [0.035, 0.021, 0.019], 0.0083, 0.008],
	]
	for sp in specs:
		var joints: Array = []
		var parent: Node3D = inner
		var pos := Vector3(float(sp[0]), -0.002, -0.044 + float(sp[3]))
		for ln in sp[1]:
			var j := Node3D.new()
			j.position = pos
			parent.add_child(j)
			_cap(j, float(sp[2]), float(ln) + float(sp[2]), Vector3(0, 0, -float(ln) / 2.0), Vector3(PI / 2.0, 0, 0), _glove_m)
			joints.append(j)
			parent = j
			pos = Vector3(0, 0, -float(ln))
		_fingers.append([joints, [deg_to_rad(68.0), deg_to_rad(88.0), deg_to_rad(58.0)], Vector3.ZERO])
	# thumb: from the side of the palm, angled forward and in, closing over the top of the fist
	var tb := Node3D.new()
	tb.position = Vector3(-0.036, -0.014, 0.004)
	# points across the front of the fist towards the little finger, bending down over the curled fingers
	tb.basis = Basis.looking_at(Vector3(0.5, -0.62, -0.6).normalized(), Vector3(-0.3, 0.2, -1.0).normalized())
	inner.add_child(tb)
	var tj: Array = []
	var tparent: Node3D = tb
	var tpos := Vector3.ZERO
	for ln in [0.034, 0.03, 0.026]:
		var j := Node3D.new()
		j.position = tpos
		tparent.add_child(j)
		_cap(j, 0.0112, ln + 0.011, Vector3(0, 0, -ln / 2.0), Vector3(PI / 2.0, 0, 0), _glove_m)
		tj.append(j)
		tparent = j
		tpos = Vector3(0, 0, -ln)
	_fingers.append([tj, [deg_to_rad(8.0), deg_to_rad(22.0), deg_to_rad(26.0)], Vector3.ZERO])
	set_curl(curl)


## 0 = open hand, 1 = fist.
func set_curl(c: float) -> void:
	curl = clampf(c, 0.0, 1.0)
	_pose()


## 0 = as set_curl says, 1 = pointing: index finger straight, the other fingers and the thumb curled in.
func set_point(k: float) -> void:
	k = clampf(k, 0.0, 1.0)
	if absf(k - point) > 0.001:
		point = k
		_pose()


func _pose() -> void:
	for n in _fingers.size():
		var f: Array = _fingers[n]
		var joints: Array = f[0]
		var ang: Array = f[1]
		var c := lerpf(curl, 0.02 if n == 0 else 0.95, point)
		for i in joints.size():
			(joints[i] as Node3D).rotation.x = -float(ang[i]) * (0.08 + 0.92 * c)


## The tip of the index finger (global).
func fingertip() -> Vector3:
	var j: Node3D = _fingers[0][0][2]
	return j.global_transform * Vector3(0, 0, -0.03)


## Building frame -> grip frame (tube along Z, index at -Z, right palm facing -X, forearm towards +Y).
static func grip_offset() -> Transform3D:
	return Transform3D(Basis(Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)), Vector3.ZERO)


## Puts the hand on a grip frame (global).
func place(grip: Transform3D) -> void:
	global_transform = grip * grip_offset()
