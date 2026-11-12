class_name ShipEarthMode
extends ShipMode
## SmartMotion Space, on Earth (v1.16.0): the spaceship over the real Duxford. It sits on the runway on its
## landing legs, lifts straight up, hovers when you take the power off and flies like a fast jet when you put
## it on (x10 makes it ten times faster). Climb above 20 km and you are in space: main.gd carries on in
## SpaceMode. Come back down from space and you arrive high above Duxford, glowing from re-entry.
## Easy: the wings level themselves when you let go and it keeps you off the ground. Pro: no help, and you can crash.

const VMAX := 300.0          # m/s at full power (x10: 3,000 m/s)
const SPACE_ALT := 20000.0   # metres above sea level: higher than this and you are in space
const LEG_H := 1.6           # the ship's middle above the ground, standing on its legs
const BELLY := 1.1           # ... the lowest part of the hull with the legs folded away
const HOVER_H := 14.0        # how high it lifts off the ground before you fly away
const EDGE := 45000.0        # metres from Duxford: the map's edge (turn back)

var terrain: Terrain
var landed := true
var lifting := 0.0           # seconds left of rising off the ground
var need_idle := false       # after landing: the throttle must come back to zero before it lifts you off again
var crashed := false
var crash_t := 0.0
var plasma := 0.0            # re-entry glow (fades out after you come down from space)
var agl := 0.0
var gy := 0.0
var auto_v := -1.0           # autopilot's speed (m/s), or -1
var no_leave := 0.0          # seconds before you can leave for space again (just came down)


func mode_name() -> String:
	return "space"


func hud_kind() -> String:
	return "ship"


func uses_world() -> bool:
	return true


func parked_in_world() -> bool:
	return false   # only there while you play: the aircraft use the runway in Flight


func camera_far() -> float:
	return 60000.0


func start_throttle() -> float:
	return 0.0


func build(w: World, qual: String) -> void:
	super.build(w, qual)
	terrain = w.terrain if w != null else Terrain.new()
	build_ship()
	_park()


## On the runway, on its legs, pointing down the runway.
func _park() -> void:
	var xz := terrain.from_runway(-Terrain.RW_LEN / 2.0 + 160.0, 0.0)
	gy = terrain.height(xz.x, xz.y)
	pos = Vector3(xz.x, gy + LEG_H, xz.y)
	q = Quaternion(Vector3.UP, -Terrain.RW_HEADING)
	vel = Vector3.ZERO
	prev_vel = Vector3.ZERO
	wv = Vector3.ZERO
	landed = true
	lifting = 0.0
	crashed = false
	plasma = 0.0
	auto = ""
	auto_v = -1.0
	fade = 0.0
	leaving = false
	ship.leg_k = 1.0
	ship.visible = true
	ship.set_plasma(0.0)
	ship.transform = Transform3D(Basis(q), pos)


func showcase() -> void:
	super.showcase()
	_park()
	x10 = false
	x10_k = 0.0


func start() -> void:
	super.start()
	assist = bool(opt("assist", true))
	_park()
	x10 = false
	x10_k = 0.0
	thr = 0.0
	need_idle = true
	lights = str(opt("tod", "day")) == "sunset"
	ship.set_lights(lights)
	hints = {}
	no_leave = 0.0
	cam_init = false
	toast.emit("You're on the runway at Duxford. Push the throttle up (Shift) to lift off. Climb above 20 km to reach space, or press TO SPACE (U). x10 (G) goes ten times faster", 8.0)


func arrive(c: Dictionary) -> void:
	super.arrive(c)
	# you come down high over Duxford, some way back along the way you are flying, so you carry on towards it
	var f := -Basis(q).z
	var fh := Vector2(f.x, f.z)
	if fh.length() < 0.2:
		fh = terrain.dir
	fh = fh.normalized()
	pos = Vector3(-fh.x * 24000.0, SPACE_ALT - 2500.0, -fh.y * 24000.0)
	vel = vel.limit_length(VMAX * 10.0)
	prev_vel = vel
	landed = false
	lifting = 0.0
	crashed = false
	need_idle = false
	plasma = float(c.get("plasma", 1.0))
	fade_col = Color(1.0, 0.6, 0.3)
	ship.leg_k = 0.0
	no_leave = 4.0
	if auto == "earth":
		toast.emit("Back on Earth! The autopilot is flying you home to Duxford. Move the stick to take over.", 6.0)
	else:
		toast.emit("Back on Earth, 17 km above Duxford. Fly down and land (LAND or L), or press TO SPACE (U) to go back up.", 6.0)


func test_options(a: Dictionary) -> void:
	super.test_options(a)
	if a.has("ship_alt"):
		pos.y = terrain.height(pos.x, pos.z) + float(a["ship_alt"])
		landed = false
		need_idle = false
		ship.leg_k = 0.0
		vel = -Basis(q).z * 200.0
		thr_set = 0.66


func _button(id: String) -> void:
	match id:
		"hyper":
			_say("HYPERSPEED WORKS IN SPACE", 2.0)
			toast.emit("Hyperspeed only works in space: climb above 20 km, or press TO SPACE (U).", 4.0)
		"land":
			if landed:
				_lift_off()
			elif auto == "land":
				auto = ""
				_say("LANDING CANCELLED", 1.5)
			elif lifting <= 0.0:
				auto = "land"
				x10 = false
				_say("LANDING HERE", 2.0)
		"auto":
			if auto == "space":
				auto = ""
				auto_v = -1.0
				_say("AUTOPILOT OFF", 1.5)
			else:
				auto = "space"
				_say("AUTOPILOT: TO SPACE", 2.5)
				if landed:
					_lift_off()
		_:
			super._button(id)


func _lift_off() -> void:
	landed = false
	lifting = 2.6
	need_idle = false
	sfx.emit("click")
	_say("LIFT-OFF", 1.5)


func _touch_down() -> void:
	landed = true
	lifting = 0.0
	vel = Vector3.ZERO
	wv = Vector3.ZERO
	var f := -Basis(q).z
	q = Quaternion(Vector3.UP, atan2(-f.x, -f.z))   # level, same heading
	pos.y = gy + LEG_H
	auto = ""
	auto_v = -1.0
	x10 = false
	thr = 0.0
	thr_set = 0.0
	need_idle = true
	_say("LANDED", 2.0)
	toast.emit("Landed. Push the throttle up from zero (or press LAND) to lift off again.", 4.0)


func step(dt: float, inp: Dictionary) -> void:
	if not running:
		return
	t_total += dt
	msg_t -= dt
	no_leave -= dt
	_buttons(inp)
	if crashed:
		crash_t += dt
		fade_col = Color(0.02, 0.0, 0.0)
		fade = minf(crash_t / 1.4, 0.85)
		if crash_t > 1.6 and crash_t - dt <= 1.6:
			finished.emit("Crashed", "Spaceship lost", "You hit the ground at %s. In Pro there's no help near the ground: try Easy, or slow down before you get low." % kmh(vel.length()), "")
		vel = Vector3.ZERO
		_feel(dt, Vector3(0, 9.81, 0))
		_tel()
		return
	var b := Basis(q)
	gy = terrain.height(pos.x, pos.z)
	agl = pos.y - gy
	x10_k = move_toward(x10_k, 1.0 if x10 else 0.0, dt / X10_TIME)
	plasma = move_toward(plasma, 0.0, dt / 6.0)
	ship.set_plasma(plasma)
	if not leaving:
		fade = move_toward(fade, 0.0, dt * 1.1)
	# up into space
	if pos.y > SPACE_ALT and not leaving and no_leave <= 0.0:
		leaving = true
		fade_col = Color(0.0, 0.0, 0.02)
		sfx.emit("whoosh")
	if leaving:
		fade = move_toward(fade, 1.0, dt * 2.2)
		if fade >= 1.0:
			_tel()
			var c := carry()
			c["from"] = "earth"
			transfer.emit("space", c)
			return
	var inp2 := inp
	var manual := absf(float(inp["pitch"])) + absf(float(inp["roll"])) + absf(float(inp["yaw"]))
	if auto != "" and manual > 0.35 and auto != "land":
		auto = ""
		auto_v = -1.0
		_say("AUTOPILOT OFF: YOU HAVE CONTROL", 2.0)
	thr = float(inp["throttle"])
	if need_idle and thr < 0.05:
		need_idle = false
	# standing on the runway
	if landed:
		ship.leg_k = move_toward(ship.leg_k, 1.0, dt / 1.2)
		if (thr > 0.08 and not need_idle) or float(inp["pitch"]) > 0.4 or auto == "space":
			_lift_off()
		else:
			vel = Vector3.ZERO
			wv = Vector3.ZERO
			pos.y = gy + LEG_H
			_finish_step(dt, b, inp)
			return
	var up := Vector3.UP
	var spd := vel.length()
	# turning: autopilot, or the stick (with the Easy help) plus banked turns, like an aircraft
	auto_v = -1.0
	var vs_t := 0.0
	if lifting > 0.0:
		lifting -= dt
		_steer_to(-b.z * Vector3(1, 0, 1) + Vector3(0, 0.0001, 0), up, dt, 2.0)
		vs_t = clampf((gy + HOVER_H + LEG_H - pos.y) * 1.3, -3.0, 8.0)
		if lifting <= 0.0:
			_say("HOVERING: PUSH THE THROTTLE UP TO FLY", 2.5)
	elif auto == "space":
		var fh := (-b.z) * Vector3(1, 0, 1)
		if fh.length() < 0.1:
			fh = Vector3(terrain.dir.x, 0, terrain.dir.y)
		_steer_to(fh.normalized() * 0.42 + up * 0.9, up, dt, 0.8)
		auto_v = VMAX * (10.0 if agl > 250.0 else 1.0)
		x10 = agl > 250.0
	elif auto == "earth":
		var tgt := Vector3(0.0, terrain.height(0.0, 0.0) + 380.0, 0.0)
		var d := tgt - pos
		var dist := d.length()
		_steer_to(d, up, dt, 0.9)
		auto_v = clampf(dist * 0.2, 25.0, VMAX * 10.0)
		x10 = auto_v > VMAX * 1.2
		if dist < 240.0:
			auto = "land"
			x10 = false
			_say("OVER DUXFORD: LANDING", 2.5)
	elif auto == "land":
		var fh2 := (-b.z) * Vector3(1, 0, 1)
		_steer_to(fh2 if fh2.length() > 0.1 else Vector3(terrain.dir.x, 0, terrain.dir.y), up, dt, 1.5)
		vs_t = -clampf((agl - LEG_H) * 0.35, 1.2, 40.0)
		x10 = false
	else:
		var wt := _stick_rates(inp2, up, false)   # Easy levels the wings; the nose stays where you put it (to climb)
		var bank := Basis(q).x.dot(up)
		wt += Basis(q).inverse() * (up * bank * 0.65 * clampf(spd / 80.0, 0.0, 1.0))
		# the edge of the map: turn back towards Duxford
		var flat := Vector2(pos.x, pos.z)
		if flat.length() > EDGE:
			var home := -Vector3(flat.x, 0, flat.y).normalized()
			var side := (-Basis(q).z).cross(home).y
			wt.y += clampf(side, -1.0, 1.0) * 0.6 + (0.6 if (-Basis(q).z).dot(home) < -0.5 else 0.0)
			_say("EDGE OF THE MAP: TURN BACK", 0.5)
		_rotate(dt, wt)
	b = Basis(q)
	var fwd := -b.z
	# speed
	var want: Vector3
	if lifting > 0.0 or auto == "land":
		want = Vector3(0.0, vs_t, 0.0)
	else:
		var tv := VMAX * thr * x10_factor()
		if auto_v >= 0.0:
			tv = auto_v
		want = fwd * tv
	vel = vel.lerp(want, 1.0 - exp(-dt * (1.5 if lifting > 0.0 or auto == "land" else 1.1)))
	# Easy: stay clear of the ground (further when going fast)
	if assist and auto != "land" and lifting <= 0.0:
		var clear := lerpf(30.0, 280.0, x10_k) + spd * 0.06
		var ahead := pos + vel * 1.5
		var gh := maxf(gy, terrain.height(ahead.x, ahead.z))
		var h := pos.y - gh
		if h < clear and vel.y < 5.0 and not (ship.leg_k > 0.5 and spd < 40.0):
			vel.y += (clear - h) * 3.0 * dt + maxf(-vel.y, 0.0) * 4.0 * dt
			if fwd.dot(up) < 0.15:
				q = (q * Quaternion(Vector3.RIGHT, minf(0.9 * dt, 0.15 - fwd.dot(up)))).normalized()
			if h < clear * 0.6:
				_say("PULL UP", 0.6)
	pos += vel * dt
	gy = terrain.height(pos.x, pos.z)
	agl = pos.y - gy
	# landing legs come down by themselves when you are low and slow
	var legs_want := 1.0 if (auto == "land" or lifting > 0.0 or (agl < 45.0 and spd < 45.0)) else 0.0
	ship.leg_k = move_toward(ship.leg_k, legs_want, dt / 1.2)
	var floor_h := LEG_H if ship.leg_k > 0.5 else BELLY
	if pos.y < gy + floor_h:
		var level := Basis(q).y.dot(up) > 0.85
		if ship.leg_k > 0.8 and -vel.y < 7.0 and Vector2(vel.x, vel.z).length() < 25.0 and level:
			_touch_down()
		elif assist:
			pos.y = gy + floor_h
			vel.y = maxf(vel.y, 2.0)
			vel *= 0.92
			_say("TOO LOW!", 1.0)
		else:
			crashed = true
			crash_t = 0.0
			fade = 0.9
			fade_col = Color(1.0, 0.8, 0.5)
			ship.visible = cockpit
			sfx.emit("boom")
	_finish_step(dt, b, inp)


func _finish_step(dt: float, _b: Basis, inp: Dictionary) -> void:
	ship.transform = Transform3D(Basis(q), pos)
	ship.animate(thr if not landed else 0.0, x10_k > 0.5, float(inp["pitch"]), float(inp["roll"]), dt)
	_show_buttons("TO SPACE", "LIFT OFF" if landed else "LAND")
	_feel(dt, Vector3(0, 9.81, 0))
	_screens()
	_tel()


func _tel() -> void:
	make_tel(t_total, false, crashed, Basis(q), pos, vel, wv, acc_body, vel.length() * 1.94384,
		{"speed_ms": snappedf(vel.length(), 0.1), "agl": snappedf(agl, 0.1), "x10": x10, "where": "earth", "landed": landed})


# ---------------------------------------------------------------- the cockpit screens and the HUD
func _status() -> String:
	if crashed:
		return "CRASHED"
	if landed:
		return "LANDED"
	if lifting > 0.0:
		return "LIFT-OFF"
	match auto:
		"space":
			return "AUTOPILOT: TO SPACE"
		"earth":
			return "AUTOPILOT: HOME"
		"land":
			return "LANDING"
	return "HOVERING" if vel.length() < 3.0 else "FLYING"


func _screens() -> void:
	var v := vel.length()
	ship.holo["left"].text = "SPEED%s\n%d m/s\n%s" % ["  x10" if x10 else "", int(v), kmh(v)]
	ship.holo["mid"].text = "ALTITUDE\n%s\nCLIMB %+d m/s" % [metres(pos.y), int(vel.y)]
	var to_space := maxf(SPACE_ALT - pos.y, 0.0)
	ship.holo["right"].text = "SPACE IN %s\nPLANET\n%s" % [metres(to_space), dest_name().to_upper()]
	ship.holo["top"].text = "EARTH · DUXFORD   HDG %03d   %s   %s" % [heading_of(Basis(q)), _status(), "EASY" if assist else "PRO"]
	ship.holo["left"].modulate = Color("#ff7a3d") if x10 else Color(0.45, 0.9, 1.0)


func hud(ui) -> void:
	var v := vel.length()
	ui.l_speed.text = str(int(v))
	ui.l_alt.text = metres(pos.y)
	ui.l_vs.text = "CLIMB %+d M/S  ·  MACH %.1f" % [int(vel.y), v / 340.0]
	ui.l_hdg.text = "%03d°" % heading_of(Basis(q))
	ui.thr_bar.value = thr
	ui.tag_flaps.text = "x10 ON" if x10 else "x10 OFF"
	ui.tag_flaps.add_theme_color_override("font_color", Color("#ff4c00") if x10 else Color("#a9acd0"))
	ui.tag_brake.text = _status()
	ui.tag_brake.add_theme_color_override("font_color", Color("#a9acd0"))
	ui.tag_assist.text = "EASY" if assist else "PRO"
	ui.l_gate.text = "Space: %s up" % metres(maxf(SPACE_ALT - pos.y, 0.0))
	var flat := Vector2(pos.x, pos.z)
	ui.l_gate_t.text = "Duxford %s  ·  planet: %s" % [metres(flat.length()), dest_name()]
	var hd := float(heading_of(Basis(q)))
	ui.arrow_angle = rad_to_deg(atan2(-pos.x, pos.z)) - hd
	ui.arrow.queue_redraw()
	var m := msg if msg_t > 0.0 else ""
	ui.set_message(m, m == "PULL UP" or m == "TOO LOW!" or m.begins_with("EDGE"))


func _after_camera(cam: Camera3D) -> void:
	var g := terrain.height(cam.global_position.x, cam.global_position.z) + 0.8
	if cam.global_position.y < g:
		cam.global_position.y = g
