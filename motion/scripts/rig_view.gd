class_name RigView
extends SubViewportContainer
## A 3D picture of a six-actuator rig that follows the seat position, so a run can be checked on screen first.
## The shape is only an illustration: the real measurements live in the Motion4Sim controller.

const NAVY := Color("#02022f")
const ORANGE := Color("#ff4c00")
const H0 := 0.62     # seat plate height at the middle position (m)

var vp := SubViewport.new()
var top := Node3D.new()
var legs: Array[MeshInstance3D] = []
var base_j: Array[Vector3] = []
var top_j: Array[Vector3] = []
var cam := Camera3D.new()
var _yaw := 0.7


func _ready() -> void:
	stretch = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.own_world_3d = true
	add_child(vp)
	var root := Node3D.new()
	vp.add_child(root)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#06063a")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.58, 0.8)
	env.environment.ambient_light_energy = 0.6
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.2
	root.add_child(sun)
	# floor grid
	var floor_m := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4, 4)
	floor_m.mesh = pm
	floor_m.material_override = _mat(Color("#0b0b4a"))
	root.add_child(floor_m)
	for i in range(-4, 5):
		root.add_child(_box(Vector3(4, 0.004, 0.006), Vector3(0, 0.002, i * 0.5), Color(1, 1, 1, 0.12)))
		root.add_child(_box(Vector3(0.006, 0.004, 4), Vector3(i * 0.5, 0.002, 0), Color(1, 1, 1, 0.12)))
	# base frame and joints (pairs of joints at 3 corners: the usual six-actuator layout)
	for k in 3:
		for s in [-1, 1]:
			var a := deg_to_rad(90.0 + k * 120.0 + s * 18.0)
			base_j.append(Vector3(cos(a) * 0.78, 0.06, sin(a) * 0.78))
	# each top joint sits towards the neighbouring corner, so the legs lean like a real six-actuator rig
	for i in 6:
		var a := deg_to_rad(90.0 + floor(i / 2.0) * 120.0 + (1 if i % 2 == 1 else -1) * 48.0)
		top_j.append(Vector3(cos(a) * 0.5, -0.04, sin(a) * 0.5))
	var base := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.86
	cyl.bottom_radius = 0.86
	cyl.height = 0.06
	cyl.radial_segments = 6
	base.mesh = cyl
	base.position.y = 0.03
	base.material_override = _mat(Color("#2a2c63"))
	root.add_child(base)
	# moving platform
	root.add_child(top)
	var plate := MeshInstance3D.new()
	var pc := CylinderMesh.new()
	pc.top_radius = 0.56
	pc.bottom_radius = 0.56
	pc.height = 0.05
	pc.radial_segments = 6
	plate.mesh = pc
	plate.material_override = _mat(Color("#c9cbe0"))
	top.add_child(plate)
	top.add_child(_box(Vector3(0.48, 0.12, 0.5), Vector3(0, 0.09, 0.02), Color("#1b1b1f")))      # seat
	top.add_child(_box(Vector3(0.48, 0.62, 0.1), Vector3(0, 0.42, 0.27), Color("#1b1b1f")))      # seat back
	top.add_child(_box(Vector3(0.6, 0.06, 0.06), Vector3(0, 0.3, -0.45), ORANGE))                # front bar = forward
	top.add_child(_box(Vector3(0.05, 0.3, 0.05), Vector3(0, 0.15, -0.45), Color("#c9cbe0")))
	for i in 6:
		var leg := MeshInstance3D.new()
		var lc := CylinderMesh.new()
		lc.top_radius = 0.028
		lc.bottom_radius = 0.04
		lc.height = 1.0
		leg.mesh = lc
		leg.material_override = _mat(Color("#8f93c4"))
		root.add_child(leg)
		legs.append(leg)
	cam.fov = 40
	root.add_child(cam)
	_place_cam()
	set_pose({})


func _box(size: Vector3, pos: Vector3, col: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.position = pos
	m.material_override = _mat(col)
	return m


func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.6
	if col.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _place_cam() -> void:
	cam.position = Vector3(sin(_yaw) * 3.0, 1.55, cos(_yaw) * 3.0)
	cam.look_at(Vector3(0, 0.55, 0))


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_yaw -= e.relative.x * 0.01
		_place_cam()


## Seat pose in our signs (mm, degrees). Godot: x right, y up, -z forward.
static func pose_transform(pose: Dictionary) -> Transform3D:
	var b := Basis(Vector3.UP, deg_to_rad(-float(pose.get("yaw", 0.0))))
	b = b * Basis(Vector3.RIGHT, deg_to_rad(float(pose.get("pitch", 0.0))))
	b = b * Basis(Vector3.BACK, deg_to_rad(-float(pose.get("roll", 0.0))))
	var t := Vector3(float(pose.get("sway", 0.0)), float(pose.get("heave", 0.0)), -float(pose.get("surge", 0.0))) / 1000.0
	return Transform3D(b, t)


func set_pose(pose: Dictionary) -> void:
	var tr := Transform3D(Basis(), Vector3(0, H0, 0)) * pose_transform(pose)
	top.transform = tr
	for i in 6:
		var a := base_j[i]
		var b := tr * top_j[i]
		var leg := legs[i]
		var d := b - a
		var up := d.normalized()
		var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		leg.global_transform = Transform3D(Basis(side, up * d.length(), side.cross(up)), (a + b) * 0.5)
