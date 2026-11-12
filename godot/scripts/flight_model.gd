class_name FlightModel
extends RefCounted
## SmartMotion Flight: flight model (a line-by-line port of dashboard/fly/flightmodel.js).
## World axes: x east, y up, z south (north is -z), metres. Body axes: x right, y up, z back (nose is -z).
## Body rates: +x nose up, +y yaw left, +z roll left (right wing up). Basis/Quaternion map body to world.

const D2R := PI / 180.0
const G := 9.80665

const SPECS := {
	"trainer": {
		"key": "trainer", "name": "Light Trainer", "blurb": "Forgiving four-seat tourer. Slow, stable and easy to land.",
		"mass": 1100.0, "S": 16.2, "b": 11.0, "c": 1.5, "I": Vector3(1825.0, 2666.0, 1285.0),
		"clA": 4.6, "cl0": 0.31, "aStall": 16.0 * D2R, "aStallN": -14.0 * D2R, "clFlap": 0.42,
		"cd0": 0.031, "cdFlap": 0.04, "k": 0.057,
		"cm0": 0.04, "cmA": -0.89, "cmQ": -14.0, "cmDe": 1.3, "deMax": 0.44,
		"rollP": -0.47, "rollB": 0.09, "rollDa": 0.18, "daMax": 0.35,
		"yawB": -0.07, "yawR": -0.11, "yawDr": 0.07, "drMax": 0.38, "yawDa": 0.02, "cyB": -0.31,
		"power": 119e3, "eta": 0.8, "tStatic": 2600.0, "propSlip": 220.0,
		"gear": [{"p": Vector3(-1.15, -1.05, 0.25), "brake": true}, {"p": Vector3(1.15, -1.05, 0.25), "brake": true}, {"p": Vector3(0, -1.05, -1.5), "steer": true}],
		"gearK": 50000.0, "gearC": 3500.0, "brakeMu": 0.5, "tailDragger": false,
		"hit": [Vector3(0, -0.2, -2.5), Vector3(0, 0.6, 5.6), Vector3(-5.5, 0.9, -0.3), Vector3(5.5, 0.9, -0.3), Vector3(0, -0.7, 0.3), Vector3(0, 1.0, 0.5)],
		"eye": Vector3(-0.32, 0.5, -0.15), "cruise": 55.0, "cruiseThrottle": 0.62, "vr": 26.0, "rpmIdle": 700.0, "rpmMax": 2700.0,
	},
	# Scottish Aviation Bulldog 120 (Skysmart's G-SMAT, ex-RAF XX658): 10.06 m span, 12.02 m2 wing, 200 hp
	# Lycoming IO-360, about 1,000 kg with two crew. Clean stall about 55 kt, top speed about 130 kt, aerobatic.
	"bulldog": {
		"key": "bulldog", "name": "Bulldog", "blurb": "Skysmart's ex-RAF Scottish Aviation Bulldog trainer. Crisp, aerobatic and honest.",
		"mass": 1000.0, "S": 12.02, "b": 10.06, "c": 1.2, "I": Vector3(1450.0, 2150.0, 1050.0),
		"clA": 4.8, "cl0": 0.25, "aStall": 16.0 * D2R, "aStallN": -14.0 * D2R, "clFlap": 0.45,
		"cd0": 0.04, "cdFlap": 0.045, "k": 0.06,
		"cm0": 0.035, "cmA": -0.85, "cmQ": -13.0, "cmDe": 1.25, "deMax": 0.44,
		"rollP": -0.45, "rollB": 0.08, "rollDa": 0.21, "daMax": 0.38,
		"yawB": -0.07, "yawR": -0.11, "yawDr": 0.075, "drMax": 0.38, "yawDa": 0.02, "cyB": -0.3,
		"power": 149e3, "eta": 0.7, "tStatic": 3300.0, "propSlip": 240.0,
		"gear": [{"p": Vector3(-1.03, -1.05, 0.4), "brake": true}, {"p": Vector3(1.03, -1.05, 0.4), "brake": true}, {"p": Vector3(0, -1.05, -1.55), "steer": true}],
		"gearK": 46000.0, "gearC": 3200.0, "brakeMu": 0.5, "tailDragger": false,
		"hit": [Vector3(0, -0.15, -2.4), Vector3(0, 0.3, 4.75), Vector3(-5.0, 0.08, 0.1), Vector3(5.0, 0.08, 0.1), Vector3(0, -0.62, 0.3), Vector3(0, 0.98, 0.25)],
		"eye": Vector3(-0.3, 0.68, 0.22), "cruise": 55.0, "cruiseThrottle": 0.65, "vr": 27.0, "rpmIdle": 700.0, "rpmMax": 2700.0,
	},
	"fighter": {
		"key": "fighter", "name": "WW2 Fighter", "blurb": "Fast single-seat fighter. Powerful and lively: needs a firm hand.",
		"mass": 3000.0, "S": 22.5, "b": 11.2, "c": 2.1, "I": Vector3(8000.0, 11000.0, 4500.0),
		"clA": 4.4, "cl0": 0.18, "aStall": 15.0 * D2R, "aStallN": -13.0 * D2R, "clFlap": 0.35,
		"cd0": 0.0215, "cdFlap": 0.04, "k": 0.07,
		"cm0": 0.03, "cmA": -0.8, "cmQ": -14.0, "cmDe": 1.1, "deMax": 0.44,
		"rollP": -0.5, "rollB": 0.08, "rollDa": 0.2, "daMax": 0.38,
		"yawB": -0.08, "yawR": -0.12, "yawDr": 0.07, "drMax": 0.36, "yawDa": 0.02, "cyB": -0.3,
		"power": 1100e3, "eta": 0.82, "tStatic": 11000.0, "propSlip": 330.0,
		"gear": [{"p": Vector3(-1.9, -1.45, -0.2), "brake": true}, {"p": Vector3(1.9, -1.45, -0.2), "brake": true}, {"p": Vector3(0, -1.0, 5.1), "steer": true}],
		"gearK": 136000.0, "gearC": 9500.0, "brakeMu": 0.4, "tailDragger": true,
		"hit": [Vector3(0, -0.1, -3.2), Vector3(0, 0.4, 5.9), Vector3(-5.6, -0.2, 0), Vector3(5.6, -0.2, 0), Vector3(0, -0.8, 0.2), Vector3(0, -0.95, -3.1)],
		"eye": Vector3(0, 0.6, -0.9), "cruise": 90.0, "cruiseThrottle": 0.5, "vr": 40.0, "rpmIdle": 800.0, "rpmMax": 3000.0,
	},
}

var spec: Dictionary
var terrain: Terrain
var wind := Vector3.ZERO
var events: Array = []
var assist := true

var pos := Vector3.ZERO
var vel := Vector3.ZERO
var w := Vector3.ZERO
var q := Quaternion.IDENTITY
var acc := 0.0
var t := 0.0
var crashed := false
var crash_reason := ""
var surf := {"e": 0.0, "a": 0.0, "r": 0.0}
var engine := 0.0
var steer := 0.0
var gamma_int := 0.0
var airborne_t := 0.0
var ground_t := 1.0
var contacts := 0
var touchdown_done := true
var spec_force := Vector3(0, G, 0)
var flaps := 0.0
var stall_warn := false
var stalled := false
var tail_down := false
var alpha := 0.0
var beta := 0.0
var ias := 0.0
var i := {}  ## instruments, refreshed after every step


func _init(spec_key: String, terrain_: Terrain) -> void:
	spec = SPECS.get(spec_key, SPECS["trainer"])
	terrain = terrain_
	reset({"x": 0.0, "z": 0.0, "heading": 0.0})


static func qfrom_hpr(h: float, p: float, r: float) -> Quaternion:
	# heading clockwise from north, pitch nose up, roll right wing down (radians)
	var qh := Quaternion(Vector3.UP, -h)
	var qp := Quaternion(Vector3.RIGHT, p)
	var qr := Quaternion(Vector3.BACK, -r)
	return (qh * qp * qr).normalized()


func reset(o: Dictionary) -> void:
	var h: float = float(o.get("heading", 0.0)) * D2R
	pos = Vector3(o.get("x", 0.0), 0.0, o.get("z", 0.0))
	vel = Vector3.ZERO
	w = Vector3.ZERO
	acc = 0.0
	t = 0.0
	crashed = false
	crash_reason = ""
	surf = {"e": 0.0, "a": 0.0, "r": 0.0}
	engine = o.get("throttle", 0.0)
	steer = 0.0
	gamma_int = 0.0
	airborne_t = 0.0
	ground_t = 1.0
	contacts = 0
	touchdown_done = true
	spec_force = Vector3(0, G, 0)
	flaps = 0.0
	stall_warn = false
	stalled = false
	tail_down = false
	events = []
	if o.has("airborne"):
		var gy := terrain.height(pos.x, pos.z)
		pos.y = gy + float(o.get("agl", 500.0))
		q = qfrom_hpr(h, 0.0, 0.0)
		vel = (q * Vector3(0, 0, -1)) * float(o.get("speed", spec["cruise"]))
		touchdown_done = false
		airborne_t = 5.0
		ground_t = 0.0
	else:
		var gy2 := terrain.height(pos.x, pos.z)
		var low := 0.0
		for g in spec["gear"]:
			low = minf(low, g["p"].y)
		var tail = null
		for g in spec["gear"]:
			if g["p"].z > 1.0:
				tail = g
		var pitch := 0.0
		if tail != null:
			pitch = asin(clampf((tail["p"].y - low) / (tail["p"].z + 0.3), 0.0, 0.3))
		q = qfrom_hpr(h, pitch, 0.0)
		pos.y = gy2 - low * cos(pitch) + 0.02
		touchdown_done = true
		for n in 240:
			_sub(1.0 / 120.0, {"pitch": 0.0, "roll": 0.0, "yaw": 0.0, "throttle": 0.0, "brake": 1.0, "flaps": 0.0, "trim": 0.0})
		vel = Vector3.ZERO
		w = Vector3.ZERO
		events = []
		touchdown_done = true
		airborne_t = 0.0
	_instruments()


func step(dt: float, inp: Dictionary) -> void:
	var H := 1.0 / 120.0
	acc += minf(dt, 0.1)
	var n := 0
	while acc >= H and n < 24:
		_sub(H, inp)
		acc -= H
		n += 1
	_instruments()


func consume_events() -> Array:
	var e := events
	events = []
	return e


func euler() -> Dictionary:
	var f := q * Vector3(0, 0, -1)
	var u := q * Vector3(0, 1, 0)
	var r := q * Vector3(1, 0, 0)
	var hd := atan2(f.x, -f.z) / D2R
	if hd < 0.0:
		hd += 360.0
	return {"heading": hd, "pitch": asin(clampf(f.y, -1.0, 1.0)) / D2R, "roll": atan2(-r.y, u.y) / D2R}


static func _sstep(a: float, b: float, x: float) -> float:
	var tt := clampf((x - a) / (b - a), 0.0, 1.0)
	return tt * tt * (3.0 - 2.0 * tt)


func _coef(a: float, flap: float) -> Vector2:
	var cl0: float = spec["cl0"] + spec["clFlap"] * flap
	var cl_max: float = cl0 + spec["clA"] * spec["aStall"]
	var cl_min: float = cl0 + spec["clA"] * spec["aStallN"]
	var cl: float = cl0 + spec["clA"] * a
	var flat := 1.1 * sin(2.0 * a)
	if a > spec["aStall"]:
		cl = lerpf(cl_max, flat, _sstep(spec["aStall"], spec["aStall"] + 0.14, a))
	elif a < spec["aStallN"]:
		cl = lerpf(cl_min, flat, _sstep(spec["aStallN"], spec["aStallN"] - 0.14, a))
	var post := maxf(_sstep(spec["aStall"], spec["aStall"] + 0.2, a), _sstep(spec["aStallN"], spec["aStallN"] - 0.2, a))
	var cd: float = spec["cd0"] + spec["cdFlap"] * flap * flap + spec["k"] * cl * cl + 1.3 * sin(a) * sin(a) * post
	return Vector2(cl, cd)


func _controls(h: float, inp: Dictionary, v: float, alpha_: float, beta_: float, gamma: float, phi: float, on_ground: bool) -> Dictionary:
	var e: float
	var a: float
	var r: float
	if on_ground or not assist or v < 18.0:
		e = inp["pitch"] + inp.get("trim", 0.0)
		a = inp["roll"]
		r = inp["yaw"]
		gamma_int = 0.0
	else:
		var g_t: float = inp["pitch"] * 17.0 * D2R if inp["pitch"] >= 0.0 else inp["pitch"] * 12.0 * D2R
		g_t += float(inp.get("trim", 0.0)) * 16.0 * D2R   # v1.19.0: in Easy mode the trim sets a hands-off climb or descent (full trim: 8 degrees)
		var a_lim: float = 0.88 * spec["aStall"]
		if alpha_ > a_lim:
			g_t = minf(g_t, gamma - 4.0 * (alpha_ - a_lim))
		var g_err := g_t - gamma
		gamma_int = clampf(gamma_int + 0.25 * g_err * h, -0.25, 0.25)
		var q_cmd := clampf(2.0 * g_err, -0.5, 0.5)
		var ff: float = -(spec["cm0"] + spec["cmA"] * alpha_) / (spec["cmDe"] * spec["deMax"])
		e = ff + 0.9 * (q_cmd - w.x) + gamma_int
		var phi_t: float = inp["roll"] * 65.0 * D2R
		var p_cmd := clampf(2.0 * (phi_t - phi), -1.5, 1.5)
		a = 0.7 * (p_cmd - (-w.z))
		r = 1.4 * beta_ - 0.5 * (-w.y) + inp["yaw"]
	return {"e": clampf(e, -1.0, 1.0), "a": clampf(a, -1.0, 1.0), "r": clampf(r, -1.0, 1.0)}


func _sub(h: float, inp: Dictionary) -> void:
	var sp := spec
	if crashed:
		vel *= 1.0 - 3.0 * h
		w *= 1.0 - 4.0 * h
		pos += vel * h
		return
	t += h
	var qi := q.inverse()
	var vel_rel := vel - wind
	var v := vel_rel.length()
	var va := qi * vel_rel
	var rho := 1.225 * exp(-maxf(pos.y, 0.0) / 8500.0)
	var qbar := 0.5 * rho * v * v
	alpha = atan2(-va.y, -va.z) if v > 1.0 else 0.0
	beta = asin(clampf(va.x / v, -1.0, 1.0)) if v > 1.0 else 0.0
	var spd := vel.length()
	var gamma := asin(clampf(vel.y / spd, -1.0, 1.0)) if spd > 3.0 else 0.0
	var f := q * Vector3(0, 0, -1)
	var u := q * Vector3(0, 1, 0)
	var rr := q * Vector3(1, 0, 0)
	var phi := atan2(-rr.y, u.y)
	var on_ground := contacts > 0

	var cmd := _controls(h, inp, v, alpha, beta, gamma, phi, on_ground)
	var rate := 4.5 * h
	surf["e"] += clampf(cmd["e"] - surf["e"], -rate, rate)
	surf["a"] += clampf(cmd["a"] - surf["a"], -rate, rate)
	surf["r"] += clampf(cmd["r"] - surf["r"], -rate, rate)
	flaps += clampf(inp.get("flaps", 0.0) - flaps, -0.5 * h, 0.5 * h)
	var thr := clampf(inp["throttle"], 0.0, 1.0)
	engine += (thr - engine) * (1.0 - exp(-h / 0.6))

	var vt := maxf(v, 14.0)
	var thrust := minf(sp["tStatic"], sp["eta"] * sp["power"] * engine / vt) * (1.0 if engine > 0.02 else 0.0)

	var cc := _coef(alpha, flaps)
	var cl := cc.x
	var cd := cc.y
	stall_warn = alpha > 0.85 * sp["aStall"] and v > 8.0
	stalled = alpha > sp["aStall"] and v > 8.0
	var fb := Vector3.ZERO
	if v > 0.5:
		var vh := va / v
		var l := Vector3(0, 1, 0) - vh * vh.y
		var ll := l.length()
		l = l / ll if ll > 0.05 else Vector3(0, 1, 0)
		fb = l * (qbar * sp["S"] * cl) + vh * (-qbar * sp["S"] * cd)
		fb.x += qbar * sp["S"] * sp["cyB"] * beta
	fb.z -= thrust
	var qctl: float = 0.5 * rho * (v * v + float(sp["propSlip"]) * engine)
	var vh2 := maxf(v, 12.0)
	var S: float = sp["S"]
	var c: float = sp["c"]
	var b: float = sp["b"]
	var mx: float = qbar * S * c * (sp["cm0"] + sp["cmA"] * alpha + sp["cmQ"] * (w.x * c / (2.0 * vh2))) + qctl * S * c * sp["cmDe"] * surf["e"] * sp["deMax"]
	var mz: float = qbar * S * b * (sp["rollP"] * (w.z * b / (2.0 * vh2)) + sp["rollB"] * beta) - qctl * S * b * sp["rollDa"] * surf["a"] * sp["daMax"]
	var my: float = qbar * S * b * (sp["yawB"] * beta + sp["yawR"] * (w.y * b / (2.0 * vh2))) - qctl * S * b * sp["yawDr"] * surf["r"] * sp["drMax"] + qctl * S * b * sp["yawDa"] * surf["a"] * sp["daMax"]
	var m := Vector3(mx, my, mz)

	var fw := (q * fb) + Vector3(0, -sp["mass"] * G, 0)

	# landing gear
	var ww := q * w
	var cnt := 0
	var tor_w := Vector3.ZERO
	var worst_sink := 0.0
	var tail_now := false
	var speed_ground := Vector2(vel.x, vel.z).length()
	steer = inp["yaw"] * 0.5 * (1.0 - _sstep(8.0, 40.0, speed_ground))
	for gr in sp["gear"]:
		var r_w: Vector3 = q * gr["p"]
		var wp := pos + r_w
		var gh := terrain.height(wp.x, wp.z)
		var d := gh - wp.y
		if d <= 0.0:
			continue
		var vw := vel + ww.cross(r_w)
		var nn: float = sp["gearK"] * d - sp["gearC"] * vw.y
		if nn < 0.0:
			nn = 0.0
		cnt += 1
		if -vw.y > worst_sink:
			worst_sink = -vw.y
		if gr.has("steer"):
			tail_now = true
		var fwd := Vector3(f.x, 0, f.z)
		var fl := Vector2(fwd.x, fwd.z).length()
		if fl < 0.0001:
			fl = 1.0
		fwd = Vector3(fwd.x / fl, 0, fwd.z / fl)
		if gr.has("steer"):
			var cs := cos(steer)
			var sn := sin(steer)
			fwd = Vector3(fwd.x * cs + fwd.z * sn, 0, -fwd.x * sn + fwd.z * cs)
		var lat := Vector3(-fwd.z, 0, fwd.x)
		var v_f := vw.dot(fwd)
		var v_l := vw.dot(lat)
		var paved := terrain.paved(wp.x, wp.z)
		var roll_res := 0.018 if paved else 0.06
		var mu := 0.85 if paved else 0.6
		var brake := 0.0
		if gr.has("brake"):
			brake = inp.get("brake", 0.0) * sp["brakeMu"] * (1.0 if (not sp["tailDragger"] or tail_down) else 0.12)
		var f_l := -mu * nn * tanh(v_l / 0.25)
		var f_f := -(roll_res + brake) * nn * tanh(v_f / 0.4)
		var fg := Vector3(fwd.x * f_f + lat.x * f_l, nn, fwd.z * f_f + lat.z * f_l)
		fw += fg
		tor_w += r_w.cross(fg)
	tail_down = tail_now
	if cnt > 0:
		ground_t = 0.0
		airborne_t = 0.0
		contacts = cnt
	else:
		contacts = 0
		airborne_t += h
		ground_t += h
	if cnt > 0 and not touchdown_done and airborne_t == 0.0:
		touchdown_done = true
		events.append({"type": "touchdown", "sink": worst_sink, "ias": ias})
		if worst_sink > 7.5:
			_crash("Landed too hard: the gear collapsed")
			return
	if cnt == 0:
		touchdown_done = false
	var non_g := qi * (fw - Vector3(0, -sp["mass"] * G, 0))
	spec_force = non_g / sp["mass"]

	# body strikes and buildings
	for hp in sp["hit"]:
		var wp2: Vector3 = pos + q * (hp as Vector3)
		if terrain.height(wp2.x, wp2.z) - wp2.y > 0.12:
			_crash("The aircraft hit the ground")
			return
		for bx in terrain.colliders:
			var dx: float = wp2.x - bx["cx"]
			var dz: float = wp2.z - bx["cz"]
			var uu: float = dx * bx["c"] + dz * bx["s"]
			var vv: float = -dx * bx["s"] + dz * bx["c"]
			if absf(uu) < bx["hu"] and absf(vv) < bx["hv"] and wp2.y < bx["top"]:
				_crash("The aircraft hit a building")
				return

	# integrate
	m += qi * tor_w
	var I: Vector3 = sp["I"]
	var iw := Vector3(I.x * w.x, I.y * w.y, I.z * w.z)
	var gyro := w.cross(iw)
	w = Vector3(w.x + (m.x - gyro.x) / I.x * h, w.y + (m.y - gyro.y) / I.y * h, w.z + (m.z - gyro.z) / I.z * h)
	vel += fw * (h / sp["mass"])
	pos += vel * h
	var wl := w.length()
	if wl > 1e-6:
		q = (q * Quaternion(w / wl, wl * h)).normalized()
	if not (is_finite(pos.x) and is_finite(pos.y) and is_finite(pos.z)):
		_crash("Simulation error")


func _crash(reason: String) -> void:
	crashed = true
	crash_reason = reason
	events.append({"type": "crash", "reason": reason})


func _instruments() -> void:
	var sp := spec
	var v := vel - wind
	var tas := v.length()
	var rho := 1.225 * exp(-maxf(pos.y, 0.0) / 8500.0)
	var e := euler()
	var gnd := terrain.height(pos.x, pos.z)
	var low := 0.0
	for g in sp["gear"]:
		low = minf(low, g["p"].y)
	var wheel_y := -low
	ias = tas * sqrt(rho / 1.225)
	i = {
		"ias": ias, "tas": tas, "gs": Vector2(vel.x, vel.z).length(), "alt_msl": pos.y, "alt_agl": maxf(0.0, pos.y - gnd - wheel_y),
		"vs": vel.y, "heading": e["heading"], "pitch": e["pitch"], "roll": e["roll"], "aoa": alpha / D2R, "slip": beta / D2R,
		"g": spec_force.y / G, "on_ground": contacts > 0, "stall_warn": stall_warn, "stall": stalled,
		"throttle": engine, "rpm": sp["rpmIdle"] + (sp["rpmMax"] - sp["rpmIdle"]) * engine, "flaps": flaps,
	}
