class_name VRHand
extends Node3D
## v1.18.0: where your hand is in VR, shown as a small ball (it was a gloved hand until v1.17). The ball sits where
## the controller is held and always shows your real hand position (it no longer jumps onto the stick or the
## throttle). It shrinks a little when you squeeze the grip or trigger, and glows orange over a spaceship button;
## you press the buttons by touching them with the ball.
## The same calls as the old hand, so the games didn't need to change: place(), set_curl(), set_point(), fingertip().

const R := 0.022                     # ball radius (m): about the size of a fingertip pad, clear but not in the way

var left := false
var curl := 0.4
var point := 0.0
var _ball: MeshInstance3D
var _mat: StandardMaterial3D


func _init(is_left := false) -> void:
	left = is_left
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.92, 0.93, 0.96)
	_mat.roughness = 0.35
	_mat.emission_enabled = true
	_mat.emission = Color(1.0, 0.3, 0.0)
	_mat.emission_energy_multiplier = 0.0
	_ball = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = R
	s.height = R * 2.0
	s.radial_segments = 20
	s.rings = 10
	_ball.mesh = s
	_ball.material_override = _mat
	_ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ball)


## 0 = relaxed, 1 = squeezed: the ball shrinks a little so you can see the grip or trigger is held.
func set_curl(c: float) -> void:
	curl = clampf(c, 0.0, 1.0)
	_ball.scale = Vector3.ONE * (1.0 - 0.25 * curl)


## 1 = over a spaceship button: the ball glows orange.
func set_point(k: float) -> void:
	point = clampf(k, 0.0, 1.0)
	_mat.emission_energy_multiplier = 2.5 * point
	_mat.albedo_color = Color(0.92, 0.93, 0.96).lerp(Color(1.0, 0.45, 0.1), point)


## What presses the spaceship's buttons: the ball itself.
func fingertip() -> Vector3:
	return _ball.global_position


## Puts the ball on the controller's grip pose (global).
func place(grip: Transform3D) -> void:
	global_transform = Transform3D(Basis(), grip.origin)
