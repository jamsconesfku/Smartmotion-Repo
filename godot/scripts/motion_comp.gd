class_name MotionComp
extends RefCounted
## VR motion compensation. SmartMotion Motion sends the seat position it is giving the rig (UDP JSON, port 4124,
## 100 a second). The headset moves with the seat, so without this the cockpit would swing around the rider's head
## every time the rig moves. We move the VR origin the opposite way, so the cockpit stays still around you.
## Signs: sway + right, surge + forward, heave + up (mm); yaw + nose right, roll + right side down, pitch + nose up (degrees).

const PIVOT_BELOW_EYE := 0.6   # m: the rig's centre of rotation, roughly, below the rider's eyes (set on the Motion4Sim Dashboard)

var udp := PacketPeerUDP.new()
var pose := {}
var live := false
var _at := 0
var ok := false


func start(port := 4124) -> void:
	ok = udp.bind(port, "127.0.0.1") == OK


func poll() -> void:
	if not ok:
		return
	while udp.get_available_packet_count() > 0:
		var j = JSON.parse_string(udp.get_packet().get_string_from_utf8())
		if j is Dictionary:
			pose = j
			_at = Time.get_ticks_msec()
	live = not pose.is_empty() and bool(pose.get("live", false)) and Time.get_ticks_msec() - _at < 300


## The seat's movement in the headset's room space, turning about pivot (room coordinates, metres).
static func rig_transform(p: Dictionary, pivot: Vector3) -> Transform3D:
	var b := Basis(Vector3.UP, deg_to_rad(-float(p.get("yaw", 0.0))))
	b = b * Basis(Vector3.RIGHT, deg_to_rad(float(p.get("pitch", 0.0))))
	b = b * Basis(Vector3.BACK, deg_to_rad(-float(p.get("roll", 0.0))))
	var t := Vector3(float(p.get("sway", 0.0)), float(p.get("heave", 0.0)), -float(p.get("surge", 0.0))) / 1000.0
	return Transform3D(Basis(), pivot + t) * Transform3D(b, Vector3.ZERO) * Transform3D(Basis(), -pivot)


## What to multiply the VR origin by this frame (identity when the rig isn't moving).
func correction(pivot: Vector3) -> Transform3D:
	if not live:
		return Transform3D.IDENTITY
	return rig_transform(pose, pivot).affine_inverse()
