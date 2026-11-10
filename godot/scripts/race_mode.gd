class_name RaceMode
extends GameMode
## SmartMotion Racing: drive an open-wheel racing car round the circuit. A 3-lap race against seven computer
## cars from a standing start with start lights, or a time trial on your own. Easy mode helps with traction,
## stability and braking; Pro is the raw car.
##
## Car physics: a "bicycle" model (one front and one rear tyre) with tyre grip that rises with load and
## downforce, a friction circle (grip shared between cornering and accelerating or braking), weight transfer,
## 700 kW, drag and downforce growing with speed, 8 gears. Top speed about 340 km/h, about 4 g in fast corners.

const M := 800.0
const IZ := 1150.0
const A := 1.95          # centre of mass to front axle (m)
const B := 1.65          # to rear axle
const CG_H := 0.3
const POWER := 700000.0
const CDA := 1.3
const CLA := 3.4
const RHO := 1.225
const MU := 1.7
const GEARS := [0.0, 24.0, 35.0, 46.0, 57.0, 67.0, 77.0, 86.0, 98.0]   # top of each gear (m/s)
const LAPS := 3
const RIVALS := [[Color("#b8161b"), Color.WHITE, 16], [Color("#00a19b"), Color("#111111"), 44], [Color("#1f3d8f"), Color("#f2c230"), 1],
	[Color("#f47c20"), Color("#1a73e8"), 4], [Color("#2b6b3a"), Color("#e8e2c8"), 14], [Color("#d9dde3"), Color("#111111"), 63], [Color("#e6c619"), Color("#111111"), 22]]

var track: RaceTrack
var car: RaceCar
var sun: DirectionalLight3D
var ais: Array = []          # {node, s, lat, v, skill, lat_t, lap, done, i}
# player car state
var yaw := 0.0
var vx := 0.0
var vy := 0.0
var r := 0.0
var pos := Vector3.ZERO
var steer := 0.0
var thr := 0.0
var brk := 0.0
var gear := 1
var rpm := 0.0
var si := 0                  # nearest centre-line sample
var lat := 0.0
var s_now := 0.0
var lap := 0
var lap_t := 0.0
var best := 0.0
var last_lap := 0.0
var race_t := 0.0
var phase := "grid"          # grid, race, done
var lights_t := 0.0
var go_at := 6.0
var assist := true
var trial := false
var player_pos := 1
var surf := "track"
var a_long := 0.0
var a_lat := 0.0
var pitch_v := 0.0
var roll_v := 0.0
var msg := ""
var msg_t := 0.0
var bump_t := 0.0
var cam_yaw := 0.0
var cam_init := false
var sector := 0
var slip_rear := 0.0


func mode_name() -> String:
	return "racing"


func build(w: World, q: String) -> void:
	super.build(w, q)
	track = RaceTrack.new()
	add_child(track)
	await track.build(w, q)
	env = w.env.duplicate() as Environment
	env.fog_density = 0.00011
	env.fog_aerial_perspective = 0.5
	env.ssil_enabled = false
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = q != "low"
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 900.0
	sun.directional_shadow_split_1 = 0.02
	sun.directional_shadow_split_2 = 0.08
	sun.directional_shadow_split_3 = 0.3
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.light_angular_distance = 0.4 if q == "high" else 0.0
	add_child(sun)
	set_time_of_day(str(opt("tod")))
	car = RaceCar.new(Color("#02022f"), Color("#ff4c00"), 7)
	add_child(car)
	vehicle = car
	eye = RaceCar.EYE
	make_rivals()


func make_rivals() -> void:
	for k in RIVALS.size():
		var rv: Array = RIVALS[k]
		var node := RaceCar.new(rv[0], rv[1], rv[2])
		add_child(node)
		ais.append({"node": node, "s": 0.0, "lat": 0.0, "v": 0.0, "skill": 0.9 + 0.012 * k, "lat_t": 0.0, "lap": 0, "i": 0, "spin": 0.0, "steer": 0.0})


func set_time_of_day(tod: String) -> void:
	var t: Dictionary = World.TOD.get(tod, World.TOD["day"])
	var el: float = deg_to_rad(t["el"])
	var az: float = deg_to_rad(float(t["az"]) - 40.0)
	var sd := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
	sun.basis = Basis.looking_at(-sd, Vector3.UP)
	sun.light_color = t["sun"]
	sun.light_energy = float(t["sun_e"]) * 0.95
	if env != null:
		env.fog_light_color = t["hor"]
		env.ambient_light_energy = t["amb"]


func set_vr(on: bool) -> void:
	super.set_vr(on)
	if sun != null:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if on else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.directional_shadow_max_distance = 400.0 if on else 900.0
		sun.directional_shadow_split_1 = 0.08 if on else 0.02
		sun.light_angular_distance = 0.0 if on or quality != "high" else 0.4
	if env != null:
		env.ssao_enabled = not on and quality != "low"


func set_cockpit(on: bool) -> void:
	super.set_cockpit(on)
	if car != null:
		car.set_first_person(on)


func _place_grid() -> void:
	trial = opt("race") == "trial"
	var player_slot := 0 if trial else 4
	player_pos = player_slot + 1
	var g: Array = track.grid_slot(player_slot)
	pos = g[0]
	yaw = g[1]
	si = g[2]
	s_now = si * track.length / track.n
	vx = 0.0
	vy = 0.0
	r = 0.0
	steer = 0.0
	gear = 1
	lap = 0
	sector = 0
	var k := 0
	for a in ais:
		var slot := k if k < player_slot else k + 1
		var ga: Array = track.grid_slot(slot)
		a["i"] = ga[2]
		a["s"] = ga[2] * track.length / track.n
		a["lat"] = -3.0 if slot % 2 == 0 else 3.0
		a["lat_t"] = a["lat"]
		a["v"] = 0.0
		a["lap"] = 0
		(a["node"] as Node3D).visible = not trial
		k += 1


func showcase() -> void:
	super.showcase()
	_place_grid()
	phase = "grid"
	track.set_lights(0)
	_pose_all(0.0)


func start() -> void:
	super.start()
	assist = bool(opt("assist", true))
	for k in ais.size():
		# Easy: the rivals drive at 78-86% of the limit (beatable for a first-timer); Pro: 90-98%
		ais[k]["skill"] = (0.78 + 0.012 * k) if assist else (0.9 + 0.012 * k)
	_place_grid()
	phase = "grid"
	lights_t = 0.0
	go_at = 5.6 + randf_range(0.3, 1.4)
	if trial:
		go_at = 3.2
	race_t = 0.0
	lap_t = 0.0
	best = best_of("race_lap")
	last_lap = 0.0
	msg = ""
	track.set_lights(0)
	cam_init = false
	_pose_all(0.0)
	if trial:
		toast.emit("Time trial: set your fastest lap. W or right trigger to accelerate, S or left trigger to brake, A/D to steer", 6.0)
	else:
		toast.emit("Watch the lights: when all five go out, GO! Hold W to accelerate, S to brake, A/D to steer", 6.0)


func step(dt: float, inp: Dictionary) -> void:
	if not running:
		return
	msg_t -= dt
	if phase == "grid":
		lights_t += dt
		var on := clampi(int(lights_t - 0.6), 0, 5) if not trial else 0
		if lights_t < go_at:
			track.set_lights(on)
			if trial:
				msg = str(ceili(go_at - lights_t))
		else:
			track.set_lights(0)
			phase = "race"
			_show("GO!", 1.2)
		rpm = lerpf(rpm, 0.25 + 0.7 * float(inp["throttle"]), 1.0 - exp(-dt * 8.0))
	else:
		race_t += dt
		lap_t += dt
		var sub := 4
		for k in sub:
			_physics(dt / sub, inp)
		_ai(dt)
		_laps()
	_pose_all(dt)
	_tel()


func _show(t: String, secs: float) -> void:
	msg = t
	msg_t = secs


func _tyre(alpha: float, fz: float, mu: float) -> float:
	return mu * fz * sin(1.45 * atan(14.0 * alpha))


func _physics(dt: float, inp: Dictionary) -> void:
	var nr := track.nearest(Vector2(pos.x, pos.z), si)
	si = nr[0]
	lat = nr[1]
	var sf := track.surface(si, lat)
	surf = sf[2]
	var grip: float = sf[0]
	var v := absf(vx)
	# controls: speed-sensitive steering (fine control at speed, full lock in the hairpin)
	var max_steer := 0.3 / (1.0 + v / 22.0)
	var st_t := clampf(float(inp["steer"]), -1.0, 1.0) * max_steer
	steer = move_toward(steer, st_t, dt * (1.6 if absf(st_t) > absf(steer) else 2.6) * max_steer / 0.3 * 2.0)
	thr = move_toward(thr, float(inp["throttle"]), dt * 6.0)
	brk = move_toward(brk, float(inp["brake"]), dt * 9.0)
	var fd := 0.5 * RHO * CLA * v * v
	var drag := 0.5 * RHO * CDA * v * v + 160.0
	var L := A + B
	var fzf := M * 9.81 * B / L + fd * 0.45 - a_long * M * CG_H / L
	var fzr := M * 9.81 * A / L + fd * 0.55 + a_long * M * CG_H / L
	fzf = maxf(fzf, 500.0)
	fzr = maxf(fzr, 500.0)
	var mu := MU * grip
	# drive and brakes
	var drive := 0.0
	if thr > 0.0:
		drive = thr * minf(POWER / maxf(v, 4.0), 11000.0)
	var fx_r := drive
	var fx_f := 0.0
	if brk > 0.0 and vx > 0.3:
		var bf := brk * 1.75 * (fzf + fzr) * grip
		fx_f -= bf * 0.6
		fx_r -= bf * 0.4
	if brk > 0.5 and vx < 0.5 and thr < 0.1:
		fx_r = -brk * 2500.0 if vx > -3.0 else 0.0   # held brake when stopped: reverse slowly (to get away from a barrier)
	if assist:
		fx_r = clampf(fx_r, -0.95 * mu * fzr, 0.85 * mu * fzr)   # traction control
		fx_f = maxf(fx_f, -0.97 * mu * fzf)                      # anti-lock brakes
	# tyre slip angles and side forces, with the friction circle
	var sv := maxf(v, 1.0)
	var af := atan2(vy + A * r, sv) - steer
	var ar := atan2(vy - B * r, sv)
	slip_rear = ar
	var cap_f := mu * fzf
	var cap_r := mu * fzr
	if assist and fx_r > 0.0:
		# traction control: only as much drive as the rear tyres can give while they hold the corner
		var fy_need := _tyre(ar, fzr, mu)
		fx_r = minf(fx_r, sqrt(maxf(cap_r * cap_r - fy_need * fy_need, 0.0)) * 0.9 + 0.08 * cap_r)
	fx_f = clampf(fx_f, -cap_f, cap_f)
	fx_r = clampf(fx_r, -cap_r, cap_r)
	var fy_f := -_tyre(af, fzf, mu) * sqrt(maxf(0.0, 1.0 - pow(fx_f / cap_f, 2.0)))
	var fy_r := -_tyre(ar, fzr, mu) * sqrt(maxf(0.0, 1.0 - pow(fx_r / cap_r, 2.0)))
	var off_drag := float(sf[1]) * M * v
	var fx := fx_r + fx_f * cos(steer) - fy_f * sin(steer) - (drag + off_drag) * signf(vx)
	var fy := fy_f * cos(steer) + fx_f * sin(steer) + fy_r
	var mz := A * (fy_f * cos(steer) + fx_f * sin(steer)) - B * fy_r
	if assist:
		# stability control: calms a sliding rear end
		var excess := absf(ar) - 0.12
		if excess > 0.0 and v > 8.0:
			mz -= signf(r) * excess * 90000.0
			fx -= drive * clampf(excess * 6.0, 0.0, 0.7)
	a_long = fx / M
	a_lat = fy / M
	vx += (a_long + vy * r) * dt
	vy += (a_lat - vx * r) * dt
	r += mz / IZ * dt
	# low speed: the kinematic model (no tyre slip), so the car parks and turns cleanly
	var k := clampf((v - 1.5) / 5.0, 0.0, 1.0)
	r = lerpf(vx * tan(steer) / L, r, k)
	vy *= k
	if vx < 0.0 and thr < 0.05:
		vx = minf(vx + 6.0 * dt, 0.0)
	yaw += r * dt
	var f := Vector2(sin(yaw), -cos(yaw))
	var rt := Vector2(cos(yaw), sin(yaw))
	var vel := f * vx + rt * vy
	var p2 := Vector2(pos.x, pos.z) + vel * dt
	# barriers
	var nr2 := track.nearest(p2, si)
	var wall: float = track.wall_r[nr2[0]] if nr2[1] > 0.0 else track.wall_l[nr2[0]]
	var over: float = absf(nr2[1]) - (wall - 1.05)
	if over > 0.0:
		var nn := track.nrm2[nr2[0]] * signf(nr2[1])
		p2 -= nn * over
		var vn := vel.dot(nn)
		if vn > 0.0:
			vel -= nn * vn * 1.35
			var hit := vn
			vel *= clampf(1.0 - hit * 0.012, 0.6, 1.0)
			if hit > 6.0 and bump_t <= 0.0:
				bump_t = 1.0
				_show("BARRIER!", 1.0)
			r *= 0.5
		vx = vel.dot(Vector2(sin(yaw), -cos(yaw)))
		vy = vel.dot(Vector2(cos(yaw), sin(yaw))) * 0.5
	bump_t -= dt
	# other cars: two circles each
	if not trial:
		for a in ais:
			var an: Node3D = a["node"]
			var af2 := Vector2(-an.transform.basis.z.x, -an.transform.basis.z.z)
			var ap := Vector2(an.position.x, an.position.z)
			for mine in [1.3, -1.3]:
				for theirs in [1.3, -1.3]:
					var c1: Vector2 = p2 + f * mine
					var c2v: Vector2 = ap + af2 * theirs
					var d := c1.distance_to(c2v)
					if d < 1.9 and d > 0.001:
						var push := (c1 - c2v) / d * (1.9 - d)
						p2 += push * 0.6
						a["lat"] = float(a["lat"]) - push.dot(track.nrm2[int(a["i"])]) * 0.4
						var rel: float = vx - float(a["v"])
						if rel > 0.0 and push.dot(f) < 0.0:
							vx -= rel * 0.35
							a["v"] = float(a["v"]) + rel * 0.3
	pos = Vector3(p2.x, RaceTrack.H(p2.x, p2.y) + 0.0, p2.y)
	var spd := v
	rpm = _rpm(spd)


func _rpm(spd: float) -> float:
	while gear < 8 and spd > GEARS[gear] * 0.97:
		gear += 1
	while gear > 1 and spd < GEARS[gear - 1] * 0.82:
		gear -= 1
	var lo: float = GEARS[gear - 1] * 0.75
	return clampf(0.45 + 0.55 * (spd - lo) / maxf(GEARS[gear] - lo, 1.0), 0.3, 1.0)


func _ai(dt: float) -> void:
	if trial:
		return
	var n := track.n
	var L := track.length
	var ps := s_now + lap * L
	for a in ais:
		var i := int(float(a["s"]) / L * n) % n
		a["i"] = i
		var skill: float = a["skill"]
		# speed plan with a little hesitation at the start
		var tgt: float = track.vmax[i] * skill
		var v: float = a["v"]
		var acc := 10.5 if v < 60.0 else 7.5
		v = move_toward(v, tgt, (acc if tgt > v else 28.0) * dt)
		# racing line: towards the inside of the coming corner
		var ka := 0.0
		for j in range(8, 40, 4):
			ka += track.curv[(i + j) % n]
		ka /= 8.0
		var line := clampf(ka * 1300.0, -4.6, 4.6)
		var lt: float = line
		# traffic: don't drive into the car ahead (other rivals or you)
		var aps: float = float(a["s"]) + int(a["lap"]) * L
		for o in ais:
			if o == a:
				continue
			var gap: float = float(o["s"]) + int(o["lap"]) * L - aps
			if gap > 0.0 and gap < 18.0 and absf(float(o["lat"]) - float(a["lat"])) < 2.4:
				lt = float(o["lat"]) + (3.6 if float(o["lat"]) < 0.0 else -3.6)
				if gap < 9.0:
					v = minf(v, float(o["v"]))
		var pg := ps - aps
		if running and pg > 0.0 and pg < 18.0 and absf(lat - float(a["lat"])) < 2.4:
			lt = lat + (3.6 if lat < 0.0 else -3.6)
			if pg < 8.0:
				v = minf(v, absf(vx))
		a["lat_t"] = clampf(lt, -5.2, 5.2)
		a["lat"] = move_toward(float(a["lat"]), float(a["lat_t"]), dt * (1.2 + v * 0.02))
		a["v"] = v
		var ns: float = float(a["s"]) + v * dt
		if ns >= L:
			ns -= L
			a["lap"] = int(a["lap"]) + 1
		a["s"] = ns


func _laps() -> void:
	var ns: float = track.nearest(Vector2(pos.x, pos.z), si)[2]
	var L := track.length
	# sectors in order, so cutting across doesn't count
	if sector == 0 and ns > L / 3.0 and ns < L / 2.0:
		sector = 1
	elif sector == 1 and ns > L * 2.0 / 3.0 and ns < L * 0.8:
		sector = 2
	if s_now > L * 0.85 and ns < L * 0.15:
		if lap == 0 or sector == 2:
			if lap > 0:
				last_lap = lap_t
				var nb := best <= 0.0 or lap_t < best
				if nb:
					best = lap_t
					save_best("race_lap", best)
				_show(("NEW BEST LAP  " if nb else "LAP  ") + _fmt(lap_t), 2.5)
			lap += 1
			lap_t = 0.0
			sector = 0
			if not trial and lap > LAPS and phase != "done":
				phase = "done"
				var ptxt := "P%d of %d" % [player_pos, ais.size() + 1]
				finished.emit("Chequered flag" if player_pos > 1 else "You won!", "Race finished", "Best lap %s. Race time %s. %s" % [_fmt(best), _fmt(race_t), "Brilliant drive!" if player_pos == 1 else "Have another go: brake before the corners and get on the power early."], ptxt)
	elif s_now < L * 0.15 and ns > L * 0.85:
		sector = 0   # reversed over the line
	s_now = ns
	# race positions
	var mine := lap * L + s_now
	var p := 1
	for a in ais:
		if int(a["lap"]) * L + float(a["s"]) > mine:
			p += 1
	player_pos = p


func _fmt(t: float) -> String:
	if t <= 0.0:
		return "--:--.-"
	return "%d:%04.1f" % [int(t / 60.0), fmod(t, 60.0)]


func _pose_all(dt: float) -> void:
	# player: lean with the ground and a touch of pitch and roll from braking and cornering
	var f3 := Vector3(sin(yaw), 0, -cos(yaw))
	var r3 := Vector3(cos(yaw), 0, sin(yaw))
	var hf := RaceTrack.H(pos.x + f3.x * 1.8, pos.z + f3.z * 1.8)
	var hb := RaceTrack.H(pos.x - f3.x * 1.8, pos.z - f3.z * 1.8)
	var hl := RaceTrack.H(pos.x - r3.x * 0.8, pos.z - r3.z * 0.8)
	var hr := RaceTrack.H(pos.x + r3.x * 0.8, pos.z + r3.z * 0.8)
	pitch_v = lerpf(pitch_v, clampf(a_long * 0.0016, -0.03, 0.03), 1.0 - exp(-dt * 6.0))     # nose dips under braking
	roll_v = lerpf(roll_v, clampf(-a_lat * 0.0012, -0.03, 0.03), 1.0 - exp(-dt * 6.0))      # leans out of the corner
	var b := Basis(Vector3.UP, -yaw)
	b = b * Basis(Vector3.RIGHT, atan2(hf - hb, 3.6) + pitch_v) * Basis(Vector3.FORWARD, atan2(hl - hr, 1.6) + roll_v)
	var rumble := 0.0
	if running and phase != "grid" and (surf == "kerb" or surf == "gravel" or surf == "grass"):
		rumble = sin(Time.get_ticks_msec() * 0.09) * (0.012 if surf == "kerb" else 0.02) * clampf(absf(vx) / 20.0, 0.0, 1.0)
	car.transform = Transform3D(b, pos + Vector3(0, 0.06 + rumble, 0))
	var info := "P%d  L%d/%d" % [player_pos, clampi(lap, 1, LAPS), LAPS] if not trial else "LAP %s" % _fmt(lap_t)
	car.animate(vx, steer, dt, rpm, gear if phase != "grid" or absf(vx) > 0.5 else 0, "%d km/h  %s" % [int(absf(vx) * 3.6), info], brk > 0.2)
	# rivals
	var n := track.n
	var L := track.length
	for a in ais:
		var node: RaceCar = a["node"]
		if not node.visible:
			continue
		var fs: float = float(a["s"]) / L * n
		var i0 := int(fs) % n
		var i1 := (i0 + 1) % n
		var fr := fs - floorf(fs)
		var c := track.c2[i0].lerp(track.c2[i1], fr)
		var t := track.tan2[i0].lerp(track.tan2[i1], fr).normalized()
		var nm := Vector2(-t.y, t.x)
		var p := c + nm * float(a["lat"])
		var lat_v: float = (float(a["lat_t"]) - float(a["lat"])) * 0.15
		var ay := atan2(t.x, -t.y) + clampf(lat_v * 0.2, -0.08, 0.08)
		var ab := Basis(Vector3.UP, -ay)
		node.transform = Transform3D(ab, Vector3(p.x, RaceTrack.H(p.x, p.y) + 0.06, p.y))
		var st := track.curv[(i0 + 2) % n] * 3.6 * 1.1
		node.animate(float(a["v"]), st, dt, 0.8, 5, "", false)


## Drives the car round the track by itself (test option --autopilot and the physics checks).
func autopilot() -> Dictionary:
	var n := track.n
	var v := absf(vx)
	var ld := 7.0 + v * 0.28
	var i2 := (si + int(ld / RaceTrack.DS)) % n
	var tp := track.c2[i2]
	var to := tp - Vector2(pos.x, pos.z)
	var err := wrapf(atan2(to.x, -to.y) - yaw, -PI, PI)
	var delta := atan(2.0 * (A + B) * sin(err) / maxf(to.length(), 1.0))
	var max_steer := 0.3 / (1.0 + v / 22.0)
	var target := 1000.0
	for k in range(2, int((10.0 + v * 0.6) / RaceTrack.DS)):
		target = minf(target, track.vmax[(si + k) % n] * 0.93)
	return {"steer": clampf(delta / max_steer, -1.0, 1.0), "throttle": 1.0 if v < target else 0.0, "brake": clampf((v - target) / 2.5, 0.0, 1.0)}


func _tel() -> void:
	var b := car.transform.basis
	var f := Vector3(sin(yaw), 0, -cos(yaw))
	var rt := Vector3(cos(yaw), 0, sin(yaw))
	make_tel(Time.get_ticks_msec() / 1000.0, false, false, b, pos, f * vx + rt * vy, Vector3(0, -r, 0), Vector3(a_lat, 9.81, -a_long), absf(vx) * 1.94384,
		{"speed_kmh": snappedf(absf(vx) * 3.6, 0.1), "gear": gear, "rpm_frac": snappedf(rpm, 0.01), "rpm": round(rpm * 12000.0), "throttle": snappedf(thr, 0.001), "surface": surf, "on_ground": true,
		"controls": {"steer": snappedf(steer, 0.001), "throttle": snappedf(thr, 0.001), "brake": snappedf(brk, 0.001)}})


func sound() -> Array:
	return [rpm, thr, absf(vx)]


func grip(side: String) -> Array:
	if car == null:
		return [Transform3D(), 0.0]
	return [car.wheel_grip(side), 0.22]


func hud(ui) -> void:
	ui.l_speed.text = str(int(absf(vx) * 3.6))
	ui.l_alt.text = "N" if gear == 0 or (phase == "grid" and absf(vx) < 0.5) else str(gear)
	ui.l_vs.text = "%d RPM" % int(4000 + rpm * 8500)
	ui.l_hdg.text = ("%d/%d" % [clampi(lap, 1, LAPS), LAPS]) if not trial else str(maxi(lap, 1))
	ui.thr_bar.value = thr
	ui.tag_flaps.text = surf.to_upper() if surf != "track" else "TC ON" if assist else "TC OFF"
	ui.tag_brake.add_theme_color_override("font_color", Color("#ff4c00") if brk > 0.1 else Color("#a9acd0"))
	ui.tag_assist.text = "EASY" if assist else "PRO"
	ui.l_gate.text = ("P%d / %d" % [player_pos, ais.size() + 1]) if not trial else "Time trial"
	ui.l_gate_t.text = "%s  ·  best %s" % [_fmt(lap_t), _fmt(best)]
	var m := msg if msg_t > 0.0 or (phase == "grid" and trial) else ""
	if phase == "grid" and not trial and lights_t > 0.6:
		m = ""
	ui.set_message(m, m == "BARRIER!")


# ---------------------------------------------------------------- cameras
func place_camera(cam: Camera3D, cam_mode: String, dt: float, orbit: Dictionary) -> void:
	var P := car.global_position
	var fb := car.global_transform.basis
	if not running:
		var oy: float = orbit["yaw"]
		var d := 7.5
		var cp := P + Vector3(sin(oy) * d, 1.9, cos(oy) * d)
		cam.global_transform = Transform3D(Basis.looking_at((P + Vector3(0, 0.5, 0) - cp).normalized(), Vector3.UP), cp)
		cam.fov = 55.0
		return
	cam.fov = 70.0
	if cam_mode == "cockpit":
		var lk: Vector2 = orbit["look"]
		cam.near = 0.05
		cam.global_transform = Transform3D(fb * Basis.from_euler(Vector3(lk.y - 0.06, lk.x, 0)), car.global_transform * eye)
		cam.fov = 78.0
		return
	cam.near = 0.3
	if cam_mode == "orbit":
		var oy2: float = orbit["yaw"]
		var op: float = orbit["pitch"]
		var od: float = orbit["dist"] * 0.6
		var cp2 := P + Vector3(sin(oy2) * cos(op) * od, sin(op) * od + 0.5, cos(oy2) * cos(op) * od)
		cam.global_transform = Transform3D(Basis.looking_at((P - cp2).normalized(), Vector3.UP), cp2)
		return
	var target_yaw := yaw
	if not cam_init:
		cam_yaw = target_yaw
		cam_init = true
	cam_yaw = lerp_angle(cam_yaw, target_yaw, 1.0 - exp(-dt * 6.0))
	var back := Vector3(-sin(cam_yaw), 0, cos(cam_yaw))
	var spd := clampf(absf(vx) / 90.0, 0.0, 1.0)
	var cp3 := P + back * (6.2 + spd * 1.2) + Vector3(0, 1.85, 0)
	var gy := RaceTrack.H(cp3.x, cp3.z) + 0.5
	cp3.y = maxf(cp3.y, gy)
	var tgt := P + Vector3(sin(cam_yaw), 0, -cos(cam_yaw)) * 4.0 + Vector3(0, 0.9, 0)
	cam.global_transform = Transform3D(Basis.looking_at((tgt - cp3).normalized(), Vector3.UP), cp3)
	cam.fov = 68.0 + spd * 10.0
