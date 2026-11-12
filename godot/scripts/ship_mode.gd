class_name ShipMode
extends GameMode
## The spaceship games (v1.16.0) share this: flying over Duxford (ShipEarthMode) and in space (SpaceMode).
## It is one ship and one cockpit: the buttons, screens and settings carry over when you fly up into space
## or come back down. Each world asks main.gd to carry on in the other one with `transfer`.
##
## Buttons (the console in the cockpit, the keyboard, a gamepad or the VR controllers):
##   hyper  HYPERSPEED: jump to the chosen planet (in space)       x10   ten times the speed
##   prev / next  choose the planet                               land  land here / lift off (on Earth)
##   auto   TO SPACE (on Earth) / TO EARTH (in space): autopilot   assist  EASY / PRO     lights  headlights

signal sfx(kind: String)
## Asks main.gd to carry on in the other world: to = "space" or "ship_earth"; carry = the ship's state.
signal transfer(to: String, carry: Dictionary)

## Where hyperspeed can take you, in the order the PLANET buttons go through them.
const DESTS := ["earth", "moon", "mercury", "venus", "mars", "jupiter", "saturn", "uranus", "neptune"]
const DEST_NAMES := {"earth": "Earth", "moon": "The Moon", "mercury": "Mercury", "venus": "Venus", "mars": "Mars",
	"jupiter": "Jupiter", "saturn": "Saturn", "uranus": "Uranus", "neptune": "Neptune"}
const X10_TIME := 1.6      # seconds to get up to (or back down from) ten times the speed
const FELT_MAX := 12.0     # m/s²: the most acceleration the seat is told about (x10 and hyperspeed would be hundreds of g)

var ship: SpaceShip
var q := Quaternion.IDENTITY
var pos := Vector3.ZERO
var vel := Vector3.ZERO
var wv := Vector3.ZERO          # turn rates in the ship's frame (x pitch up, y yaw left, z roll left)
var thr := 0.5
var assist := true
var x10 := false
var x10_k := 0.0
var lights := false
var dest := 4                   # index in DESTS (Mars to start with)
var auto := ""                  # autopilot: "" | "space" (fly up out of the air) | "earth" (fly home) | "land"
var fade := 0.0                 # 0..1: the whole view fades to fade_col (leaving the air, hyperspeed flashes)
var fade_col := Color.WHITE
var acc_body := Vector3(0, 9.81, 0)
var prev_vel := Vector3.ZERO
var cue := Vector3.ZERO         # extra push for the seat (hyperspeed), m/s² in the ship's frame
var msg := ""
var msg_t := 0.0
var t_total := 0.0
var cam_q := Quaternion.IDENTITY
var cam_init := false
var pressed: Array = []         # buttons pressed by a VR fingertip since the last step
var leaving := false            # fading out on the way to the other world
var hints := {}                 # hints already shown this flight


func build_ship() -> void:
	ship = SpaceShip.new()
	add_child(ship)
	vehicle = ship
	eye = SpaceShip.EYE


## 1 .. 10, eased in and out over X10_TIME.
func x10_factor() -> float:
	var k := x10_k * x10_k * (3.0 - 2.0 * x10_k)
	return lerpf(1.0, 10.0, k)


func _say(t: String, secs := 1.8) -> void:
	msg = t
	msg_t = secs


func _hint(key: String, t: String, secs := 6.0) -> void:
	if not hints.has(key):
		hints[key] = true
		toast.emit(t, secs)


func dest_key() -> String:
	return DESTS[dest]


func dest_name() -> String:
	return DEST_NAMES[dest_key()]


# ---------------------------------------------------------------- buttons
## A VR fingertip at the console. 0 = not near it, 1 = over it (the hand points), 2 = a button was just pressed.
func touch(side: String, tip: Vector3) -> int:
	if ship == null or not running:
		return 0
	var r: Array = ship.touch(tip, side)
	if str(r[0]) != "":
		pressed.append(str(r[0]))
		return 2
	return 1 if r[1] else 0


## Presses from this step's input (keyboard, gamepad, VR controller buttons) and from fingertips.
func _buttons(inp: Dictionary) -> void:
	var list: Array = pressed.duplicate()
	pressed.clear()
	for id in inp.get("press", []):
		list.append(str(id))
	for id in list:
		ship.press_anim(id)
		sfx.emit("click")
		_button(id)


func _button(id: String) -> void:
	match id:
		"x10":
			x10 = not x10
			_say("x10 SPEED ON: ten times faster" if x10 else "x10 SPEED OFF", 1.8)
		"next", "prev":
			dest = posmod(dest + (1 if id == "next" else -1), DESTS.size())
			_say("PLANET: %s" % dest_name().to_upper(), 2.0)
		"assist":
			assist = not assist
			_say("EASY: THE SHIP HELPS YOU" if assist else "PRO: NO HELP", 2.0)
			toast.emit("Easy: the ship levels itself when you let go, keeps you off the ground and turns to the planet for hyperspeed." if assist else "Pro: no help. You fly every bit of it yourself.", 4.0)
		"lights":
			lights = not lights
			ship.set_lights(lights)
			_say("LIGHTS ON" if lights else "LIGHTS OFF", 1.2)


func _show_buttons(auto_label: String, land_label: String) -> void:
	ship.set_button("x10", x10)
	ship.set_button("assist", assist, "EASY" if assist else "PRO")
	ship.set_button("lights", lights)
	ship.set_button("auto", auto == "space" or auto == "earth", auto_label)
	ship.set_button("land", auto == "land", land_label)


# ---------------------------------------------------------------- flying
## Turns the ship at the rates in wt (ship frame), smoothly.
func _rotate(dt: float, wt: Vector3) -> void:
	wv = wv.lerp(wt, 1.0 - exp(-dt * 6.0))
	var ang := wv.length() * dt
	if ang > 0.0:
		q = (q * Quaternion(wv.normalized(), ang)).normalized()


## The stick's turn rates, plus (in Easy) rolling back upright, and the nose coming back level, when you let go.
func _stick_rates(inp: Dictionary, up: Vector3, level_pitch: bool) -> Vector3:
	var wt := Vector3(float(inp["pitch"]) * 1.5, -float(inp["yaw"]) * 0.9, -float(inp["roll"]) * 2.4)
	if assist:
		var b := Basis(q)
		var fu := (-b.z).dot(up)
		if absf(float(inp["roll"])) < 0.1:
			wt.z -= b.x.dot(up) * 1.4 * (1.0 - absf(fu))
		if level_pitch and absf(float(inp["pitch"])) < 0.1:
			wt.x -= fu * 0.7
	return wt


## Autopilot: turns smoothly to fly along dir.
func _steer_to(dir: Vector3, up: Vector3, dt: float, rate := 1.1) -> void:
	var b := Basis(q)
	var u := up if absf(dir.normalized().dot(up)) < 0.97 else b.y
	var tq := Quaternion(Basis.looking_at(dir.normalized(), u).orthonormalized())
	var nq := q.slerp(tq, 1.0 - exp(-dt * rate)).normalized()
	var dq := q.inverse() * nq
	var ang := dq.get_angle()
	wv = dq.get_axis() * (ang / maxf(dt, 0.001)) if ang > 0.00001 else Vector3.ZERO
	q = nq


## Felt acceleration for the motion rig (in the ship's frame), from the change in velocity. gravity: in world
## axes (Earth), or null to feel 1 g straight down into the seat all the time (space).
func _feel(dt: float, gravity: Variant) -> void:
	var b := Basis(q)
	var acc := ((vel - prev_vel) / maxf(dt, 0.001)).limit_length(FELT_MAX)
	var f: Vector3
	if gravity == null:
		f = b.inverse() * acc + Vector3(0, 9.81, 0)
	else:
		f = b.inverse() * (acc + (gravity as Vector3))
	acc_body = acc_body.lerp(f + cue, 1.0 - exp(-dt * 10.0))
	prev_vel = vel


# ---------------------------------------------------------------- going between Earth and space
func carry() -> Dictionary:
	return {"q": q, "vel": vel, "wv": wv, "thr": thr, "x10": x10, "x10_k": x10_k, "assist": assist, "lights": lights,
		"dest": dest, "auto": auto, "hints": hints.duplicate()}


## Carry on from the other world (after `transfer`): the view starts faded and clears.
func arrive(c: Dictionary) -> void:
	running = true
	q = c["q"]
	vel = c["vel"]
	wv = c["wv"]
	thr = c["thr"]
	x10 = c["x10"]
	x10_k = c["x10_k"]
	assist = c["assist"]
	lights = c["lights"]
	dest = c["dest"]
	auto = c["auto"]
	hints = c["hints"]
	prev_vel = vel
	fade = 1.0
	leaving = false
	cam_init = false
	ship.visible = true
	ship.set_lights(lights)
	thr_set = thr


## Test options (after --, for screenshots): --press=hyper (press a button at the start), and per world
## --ship_alt=8000 (Earth: start in the air that high) or --at_planet=mars (space: start there).
func test_options(a: Dictionary) -> void:
	if a.has("press"):
		for id in str(a["press"]).split(","):
			pressed.append(id)


func fade_color() -> Color:
	return Color(fade_col.r, fade_col.g, fade_col.b, clampf(fade, 0.0, 1.0))


# ---------------------------------------------------------------- shared bits
func grip(side: String) -> Array:
	if ship == null:
		return [Transform3D(), 0.0]
	return [ship.stick_grip() if side == "r" else ship.throttle_grip(), 0.2 if side == "r" else 0.14]


func set_cockpit(on: bool) -> void:
	super.set_cockpit(on)
	if ship != null:
		ship.set_first_person(on)


func sound() -> Array:
	var k := clampf(vel.length() / 300.0, 0.0, 1.0)
	return [maxf(thr * 0.8, k * 0.5) + (x10_k * 0.3), thr, vel.length()]


func camera_modes() -> Array:
	return ["chase", "cockpit", "orbit"]


func _cam_fov_extra() -> float:
	return x10_k * 6.0


## Desktop cameras: the menu orbit, chase, cockpit and orbit views.
func place_camera(cam: Camera3D, cam_mode: String, dt: float, orbit: Dictionary) -> void:
	var b := Basis(q)
	if not running:
		var oy: float = orbit["yaw"]
		var cp := pos + Vector3(sin(oy) * 26.0, 6.0, cos(oy) * 26.0)
		cam.global_transform = Transform3D(Basis.looking_at((pos - cp).normalized(), Vector3.UP), cp)
		cam.fov = 60.0
		_after_camera(cam)
		return
	cam.fov = 72.0
	if cam_mode == "cockpit":
		var lk: Vector2 = orbit["look"]
		cam.near = 0.05
		cam.global_transform = Transform3D(b * Basis.from_euler(Vector3(lk.y - 0.08, lk.x, 0)), Transform3D(b, pos) * eye)
		cam.fov = 72.0 + _cam_fov_extra() * 0.5
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
		cam.fov = 72.0 + _cam_fov_extra()
	_after_camera(cam)


func _after_camera(_cam: Camera3D) -> void:
	pass


## Speed for the screens: "280 m/s", "1,008 km/h".
static func kmh(v: float) -> String:
	return _thousands(int(round(v * 3.6))) + " km/h"


static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


static func metres(v: float) -> String:
	if absf(v) >= 10000.0:
		return "%.1f km" % (v / 1000.0)
	return _thousands(int(round(v))) + " m"


static func heading_of(b: Basis) -> int:
	var f := -b.z
	return int(round(fposmod(rad_to_deg(atan2(f.x, -f.z)), 360.0))) % 360
