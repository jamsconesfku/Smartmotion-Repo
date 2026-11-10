class_name Cueing
extends RefCounted
## Motion cueing: turns the game's flight data into a seat position for the rig.
## Runs at a fixed 500 steps a second (the controller wants a position about every 2 ms).
## Follows the standard Motion4Sim / FlyPT layout: gain -> wash-out (high-pass) -> smoothing (low-pass) per axis,
## plus slow "tilt" for forces that last, then a guard that keeps every axis inside its travel, speed and acceleration.
##
## Our signs (the rig link can flip any axis to match the controller):
##   sway + right, surge + forward, heave + up (mm);  yaw + nose right, roll + right side down, pitch + nose up (degrees)

const HZ := 500.0
const DT := 1.0 / HZ
const G := 9.81
const AXES := ["sway", "surge", "heave", "yaw", "roll", "pitch"]

## Tuning values. Plain-English names and help for each are in Config.FIELDS.
const DEFAULTS := {
	"intensity": 0.5,          # master strength, 0..1
	"gain_sway": 8.0,          # mm of movement per m/s² of sideways acceleration
	"gain_surge": 8.0,         # mm per m/s² forward/back
	"gain_heave": 6.0,         # mm per m/s² up/down
	"gain_yaw": 0.15,          # degrees per degree-per-second of turning
	"gain_roll": 0.15,
	"gain_pitch": 0.15,
	"washout_s": 4.0,          # seconds a quick movement takes to drift back to the middle
	"smooth_s": 0.2,           # smoothing, seconds (more = softer, less = sharper)
	"tilt_gain": 1.0,          # 1 = tilt the seat exactly as much as needed to fake a lasting force
	"tilt_max_deg": 8.0,       # most the seat tilts for lasting forces
	"tilt_rate_dps": 3.0,      # tilt slower than this (degrees a second) so the rider feels force, not rotation
	"limit_mm": 60.0,          # most each sway/surge/heave may move from the middle
	"limit_deg": 10.0,         # most each yaw/roll/pitch may turn from the middle
	"speed_mm_s": 300.0,       # top speed of a sway/surge/heave movement
	"speed_deg_s": 40.0,       # top speed of a yaw/roll/pitch movement
	"accel_mm_s2": 2000.0,     # top acceleration, sway/surge/heave
	"accel_deg_s2": 300.0,     # top acceleration, yaw/roll/pitch
	"rumble_mm": 0.4,          # runway rumble at taxi/take-off speed (0 = off)
	"belt_on": false,          # drive the seat-belt tensioner (actuator 7)
	"belt_base": 0.15,         # belt tension while flying straight and level, 0..1
	"belt_gain": 1.2,          # extra tension per g of braking or of going light in the seat
	"fade_s": 2.0,             # seconds to fade motion in or out (start, pause, crash, lost data)
	"timeout_s": 0.3,          # no game data for this long = fade to the middle
}

var cfg := DEFAULTS.duplicate()

# filter state
var _hp := {}        # high-pass: {axis: [last_in, out]}
var _lp := {}        # low-pass chains: {key: [stage values]}
var _tilt := {"pitch": 0.0, "roll": 0.0}
var _guard := {}     # {axis: [pos, vel]}
var _belt := 0.0
var _rumble_t := 0.0
var _primed := false
var _last_raw := {}  # last movement while flying; faded out when the game stops
var scale := 0.0     # current fade, 0..1
var want_on := false # operator has motion switched on
var active := false  # game data is fresh and the game is flying
var reason := "waiting for the game"

## Final pose (after intensity, fade and the guard), our signs.
var pose := {"sway": 0.0, "surge": 0.0, "heave": 0.0, "yaw": 0.0, "roll": 0.0, "pitch": 0.0}
var belt := 0.0      # 0..1
## Raw targets before the guard (for the display).
var target := pose.duplicate()


func _init() -> void:
	for a in AXES:
		_guard[a] = [0.0, 0.0]


func reset_filters() -> void:
	_hp.clear()
	_lp.clear()
	_tilt = {"pitch": 0.0, "roll": 0.0}
	_primed = false


static func _a(tau: float) -> float:
	return DT / (maxf(tau, 0.0001) + DT)


func _lowpass(key: String, x: float, tau: float, stages: int) -> float:
	if not _lp.has(key):
		var init := []
		for i in stages:
			init.append(x)
		_lp[key] = init
	var st: Array = _lp[key]
	var a := _a(tau)
	var v := x
	for i in stages:
		st[i] = float(st[i]) + a * (v - float(st[i]))
		v = st[i]
	return v


func _highpass(key: String, x: float, tau: float) -> float:
	if not _hp.has(key):
		_hp[key] = [x, 0.0]
	var st: Array = _hp[key]
	var k := tau / (maxf(tau, 0.0001) + DT)
	var y := k * (float(st[1]) + x - float(st[0]))
	st[0] = x
	st[1] = y
	return y


## Soft limit: passes values up to 80 % of the limit unchanged, then eases towards the limit without reaching it.
static func softcrop(x: float, limit: float) -> float:
	var s := 0.8 * limit
	var ax := absf(x)
	if ax <= s:
		return x
	return signf(x) * (s + (limit - s) * tanh((ax - s) / (limit - s)))


## Moves pos towards want without going over the speed or acceleration limits, and slows down in time not to overshoot.
static func guard_step(st: Array, want: float, speed: float, accel: float) -> void:
	var p: float = st[0]
	var v: float = st[1]
	var err := want - p
	var vd := signf(err) * minf(minf(speed, sqrt(2.0 * accel * absf(err))), absf(err) / DT)
	var dv := clampf(vd - v, -accel * DT, accel * DT)
	v += dv
	p += v * DT
	st[0] = p
	st[1] = v


## One 2 ms step.  frame = the game's latest telemetry Dictionary (or {}), age = seconds since it arrived.
## test = {} normally; in test mode a Dictionary of axis -> value that replaces the game.
func step(frame: Dictionary, age: float, test := {}) -> void:
	var c := cfg
	var fresh := not frame.is_empty() and age < float(c["timeout_s"])
	var flying := fresh and not bool(frame.get("paused", false)) and not bool(frame.get("crashed", false))
	if not test.is_empty():
		flying = true
	if not test.is_empty():
		reason = "test movement"
	elif not fresh:
		reason = "no game data"
	elif bool(frame.get("crashed", false)) and test.is_empty():
		reason = "crashed: back to the middle"
	elif bool(frame.get("paused", false)) and test.is_empty():
		reason = "game paused"
	else:
		reason = "following the game"
	active = flying
	var on := want_on and flying
	var fade := DT / maxf(float(c["fade_s"]), 0.05)
	scale = clampf(scale + (fade if on else -fade), 0.0, 1.0)

	var raw := {"sway": 0.0, "surge": 0.0, "heave": 0.0, "yaw": 0.0, "roll": 0.0, "pitch": 0.0}
	var belt_want := 0.0
	if not test.is_empty():
		for a in AXES:
			raw[a] = float(test.get(a, 0.0))
		belt_want = float(test.get("belt", 0.0))
		reset_filters()
	elif flying:
		var gf: Dictionary = frame.get("g_felt", {})
		var rt: Dictionary = frame.get("rate", {})
		var surge_g := clampf(float(gf.get("surge", 0.0)), -3.0, 3.0)
		var sway_g := clampf(float(gf.get("sway", 0.0)), -3.0, 3.0)
		var heave_g := clampf(float(gf.get("heave", 1.0)), -3.0, 6.0)
		var roll_r := clampf(float(rt.get("roll_dps", 0.0)), -90.0, 90.0)
		var pitch_r := clampf(float(rt.get("pitch_dps", 0.0)), -90.0, 90.0)
		var yaw_r := clampf(float(rt.get("yaw_dps", 0.0)), -90.0, 90.0)
		var wo := float(c["washout_s"])
		var sm := float(c["smooth_s"])
		# onset: the start of every movement, then a slow drift back to the middle
		raw["sway"] = _lowpass("sway", _highpass("sway", sway_g * G * float(c["gain_sway"]), wo), sm, 2)
		raw["surge"] = _lowpass("surge", _highpass("surge", surge_g * G * float(c["gain_surge"]), wo), sm, 2)
		raw["heave"] = _lowpass("heave", _highpass("heave", (heave_g - 1.0) * G * float(c["gain_heave"]), wo), sm, 2)
		raw["yaw"] = _lowpass("yaw", _highpass("yaw", yaw_r * float(c["gain_yaw"]), wo), sm, 1)
		var roll_on := _lowpass("roll", _highpass("roll", roll_r * float(c["gain_roll"]), wo), sm, 1)
		var pitch_on := _lowpass("pitch", _highpass("pitch", pitch_r * float(c["gain_pitch"]), wo), sm, 1)
		# tilt: lean the seat slowly so gravity supplies a force that lasts (pushed into the seat back, or sideways)
		var tg := float(c["tilt_gain"])
		var tmax := float(c["tilt_max_deg"])
		var p_want := softcrop(rad_to_deg(asin(clampf(surge_g * tg, -0.9, 0.9))), tmax)
		var r_want := softcrop(rad_to_deg(asin(clampf(-sway_g * tg, -0.9, 0.9))), tmax)
		p_want = _lowpass("tilt_p", p_want, sm, 3)
		r_want = _lowpass("tilt_r", r_want, sm, 3)
		var rate := float(c["tilt_rate_dps"]) * DT
		if not _primed:
			_tilt["pitch"] = p_want
			_tilt["roll"] = r_want
		_tilt["pitch"] = float(_tilt["pitch"]) + clampf(p_want - float(_tilt["pitch"]), -rate, rate)
		_tilt["roll"] = float(_tilt["roll"]) + clampf(r_want - float(_tilt["roll"]), -rate, rate)
		raw["pitch"] = pitch_on + float(_tilt["pitch"])
		raw["roll"] = roll_on + float(_tilt["roll"])
		_primed = true
		# seat belt: tighter when braking / decelerating or going light in the seat
		belt_want = float(c["belt_base"]) + float(c["belt_gain"]) * (maxf(0.0, -surge_g) + maxf(0.0, 1.0 - heave_g))
		_last_raw = raw.duplicate()
	else:
		# paused, crashed or no data: hold the last movement and let the fade bring it to the middle smoothly
		if not _last_raw.is_empty():
			raw = _last_raw
		if scale <= 0.0:
			reset_filters()
			_last_raw = {}

	var k := float(c["intensity"]) * scale
	for a in AXES:
		var rot: bool = a in ["yaw", "roll", "pitch"]
		var lim := float(c["limit_deg"] if rot else c["limit_mm"])
		target[a] = softcrop(float(raw[a]) * k, lim)
		guard_step(_guard[a], float(target[a]), float(c["speed_deg_s"] if rot else c["speed_mm_s"]), float(c["accel_deg_s2"] if rot else c["accel_mm_s2"]))
		pose[a] = clampf(float(_guard[a][0]), -lim, lim)
	# runway rumble, small and added after the guard (it is too quick for the speed limits but only a fraction of a mm)
	if flying and test.is_empty() and bool(frame.get("on_ground", false)):
		var gs := float(frame.get("gs_kt", 0.0))
		var amp := float(c["rumble_mm"]) * clampf(gs / 60.0, 0.0, 1.0) * k
		_rumble_t += DT
		var n := sin(_rumble_t * TAU * 11.0) * 0.6 + sin(_rumble_t * TAU * 17.3 + 1.3) * 0.4
		pose["heave"] = clampf(float(pose["heave"]) + amp * n, -float(c["limit_mm"]), float(c["limit_mm"]))
	if bool(c["belt_on"]):
		_belt += _a(0.05) * (clampf(belt_want, 0.0, 1.0) * scale - _belt)
	else:
		_belt = 0.0
	belt = clampf(_belt, 0.0, 1.0)


## True when the seat is (nearly) in the middle and still.
func at_rest() -> bool:
	for a in AXES:
		if absf(float(pose[a])) > 0.2 or absf(float(_guard[a][1])) > 1.0:
			return false
	return true
