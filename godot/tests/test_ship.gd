extends SceneTree
## Spaceship checks (headless):  godot --headless --path godot --script res://tests/test_ship.gd
## Lifts off from the Duxford runway, flies, is kept off the ground in Easy, climbs into space, jumps at
## hyperspeed to Mars, presses a console button with a VR fingertip, flies home on the autopilot, comes back
## down over Duxford and lands; and in Pro, flying into the ground is a crash.
var fails := 0
var got := {}
var thr := 0.0
var gmax := 0.0


func check(name: String, ok: bool, info := "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("  " + info if info != "" else ""))
	if not ok:
		fails += 1


func _initialize() -> void:
	_run.call_deferred()


func inp(pitch := 0.0, press: Array = []) -> Dictionary:
	return {"pitch": pitch, "roll": 0.0, "yaw": 0.0, "throttle": thr, "fire": false, "boost": false, "press": press, "steer": 0.0, "brake": 0.0}


## Runs a mode for up to secs; stops early when done() is true. Returns the seconds it took.
func run(m: ShipMode, secs: float, stick: float, done: Callable, presses: Array = []) -> float:
	var dt := 1.0 / 60.0
	var t := 0.0
	var first := true
	while t < secs:
		if m.thr_set >= 0.0:
			thr = m.thr_set
			m.thr_set = -1.0
		m.step(dt, inp(stick, presses if first else []))
		first = false
		t += dt
		var gf: Dictionary = m.tel_frame.get("g_felt", {})
		if not gf.is_empty():
			gmax = maxf(gmax, Vector3(gf["surge"], gf["sway"], float(gf["heave"]) - 1.0).length())
		if not got.is_empty() or done.call():
			break
	return t


func _run() -> void:
	var em := ShipEarthMode.new()
	root.add_child(em)
	em.build(null, "low")
	var sm := SpaceMode.new()
	root.add_child(sm)
	await sm.build(null, "low")
	for m in [em, sm]:
		(m as ShipMode).transfer.connect(func(to: String, c: Dictionary): got["to"] = to; got["c"] = c)
		(m as GameMode).finished.connect(func(t: String, _l: String, _x: String, _b: String): got["end"] = t)
	# ---- on the runway
	em.start()
	var rw := em.terrain.to_runway(em.pos.x, em.pos.z)
	check("starts on the runway, standing on its legs", em.landed and absf(rw.y) < 5.0 and absf(em.pos.y - em.terrain.height(em.pos.x, em.pos.z) - ShipEarthMode.LEG_H) < 0.05, "runway %.0f, %.0f" % [rw.x, rw.y])
	thr = 0.0
	run(em, 1.0, 0.0, func(): return false)
	check("stays put with the throttle at zero", em.landed and em.vel.length() < 0.01)
	thr = 1.0
	run(em, 4.0, 0.0, func(): return false)
	check("lifts straight up when the throttle goes up", not em.landed and em.agl > 8.0, "%.1f m up" % em.agl)
	run(em, 20.0, 0.0, func(): return false)
	var v := em.vel.length()
	check("flies at full power (about 300 m/s)", v > 250.0 and v < 320.0 and not em.crashed, "%.0f m/s, %.0f m up" % [v, em.agl])
	# ---- Easy keeps it off the ground: dive at full power
	em.q = Quaternion(Basis.looking_at(Vector3(0.5, -0.7, -0.5).normalized(), Vector3.UP))
	var low := INF
	var t := 0.0
	while t < 15.0:
		em.step(1.0 / 60.0, inp(0.0))
		low = minf(low, em.pos.y - em.terrain.height(em.pos.x, em.pos.z))
		t += 1.0 / 60.0
	check("Easy: diving at the ground doesn't crash", not em.crashed and low > 1.0, "lowest %.1f m" % low)
	# ---- x10
	em.step(1.0 / 60.0, inp(0.0, ["x10"]))
	run(em, 6.0, 0.0, func(): return false)
	check("x10 makes it ten times faster", em.x10 and em.vel.length() > 2400.0 and not em.crashed, "%.0f m/s" % em.vel.length())
	em.step(1.0 / 60.0, inp(0.0, ["x10"]))
	# ---- TO SPACE autopilot
	got = {}
	gmax = 0.0
	var secs := run(em, 120.0, 0.0, func(): return false, ["auto"])
	check("TO SPACE climbs out of the air into space", got.get("to", "") == "space", "%.0f s" % secs)
	check("the seat is never told about more than 1.5 g extra", gmax < 1.5, "%.2f g" % gmax)
	if got.get("to", "") != "space":
		_end()
		return
	# ---- in space, above the Earth
	sm.arrive(got["c"])
	got = {}
	var alt := sm.pos.distance_to(sm.pc) - sm.pr
	check("arrives in space 2 km above the Earth", sm.loc == "earth" and absf(alt - SpaceMode.EARTH_ABOVE) < 1.0, "%.0f m" % alt)
	run(sm, 2.0, 0.0, func(): return false)
	check("the view clears after the fade", sm.fade < 0.5, "fade %.2f" % sm.fade)
	# ---- a VR fingertip on the console
	sm.dest = ShipMode.DESTS.find("venus")
	# the fingertip pushed 4 mm into the button (worked out again after each step: the ship is moving)
	var tip := func(lift: float) -> Vector3: return sm.ship.button_pos("next") + sm.ship.console.global_transform.basis.y.normalized() * lift
	var r1 := sm.touch("r", tip.call(-0.004))
	sm.step(1.0 / 60.0, inp(0.0))
	check("a fingertip on PLANET > presses it", r1 == 2 and sm.dest_key() == "mars", "touch %d, planet %s" % [r1, sm.dest_key()])
	var r2 := sm.touch("r", tip.call(-0.004))
	check("holding the finger there doesn't press it again", r2 == 1, "touch %d" % r2)
	var r0 := sm.touch("r", tip.call(0.06))
	check("a finger just above the console points (but doesn't press)", r0 == 1, "touch %d" % r0)
	var r3 := sm.touch("r", tip.call(-0.004))
	check("lifting the finger and pressing again does", r3 == 2, "touch %d" % r3)
	sm.step(1.0 / 60.0, inp(0.0))
	sm.dest = ShipMode.DESTS.find("mars")
	check("a finger away from the console does nothing", sm.touch("l", sm.ship.global_position + Vector3(0, 5, 0)) == 0)
	# ---- hyperspeed to Mars
	gmax = 0.0
	thr = 0.5
	secs = run(sm, 20.0, 0.0, func(): return sm.hyper == "" and sm.loc == "mars", ["hyper"])
	check("hyperspeed takes you to Mars", sm.loc == "mars" and sm.hyper == "", "%.1f s" % secs)
	check("hyperspeed jump stays within 1.5 g for the seat", gmax < 1.5, "%.2f g" % gmax)
	var to_mars := sm.pos.distance_to(sm.pc) / sm.pr
	check("Mars is in front of you when you arrive", to_mars > 2.0 and to_mars < 3.2 and (-Basis(sm.q).z).angle_to(sm.pc - sm.pos) < 0.6, "%.1f radii away" % to_mars)
	run(sm, 1.5, 0.0, func(): return false)
	check("after the jump the view is clear", sm.fade < 0.05 and sm.ship.tube.visible == false, "fade %.2f" % sm.fade)
	# ---- v1.18.0: look at a planet and press HYPERSPEED: it goes there, whatever planet was chosen
	sm.dest = SpaceMode.DESTS.find("neptune")
	sm.look_dir = sm._dest_dir("jupiter")
	check("looking at Jupiter, HYPERSPEED picks Jupiter", sm.looked_at() == "jupiter", "looked at %s" % sm.looked_at())
	sm._button("hyper")
	check("... and sets off for it (not the chosen Neptune)", sm.hyper != "" and sm.hyper_to == "jupiter", "hyper %s to %s" % [sm.hyper, sm.hyper_to])
	secs = run(sm, 25.0, 0.0, func(): return sm.hyper == "" and sm.loc == "jupiter", [])
	check("arrives at Jupiter", sm.loc == "jupiter", "%.1f s" % secs)
	sm.look_dir = Vector3.ZERO
	# ---- TO EARTH autopilot: hyperspeed home, down into the air
	secs = run(sm, 150.0, 0.0, func(): return false, ["auto"])
	check("TO EARTH flies home and down into the air", got.get("to", "") == "ship_earth", "%.0f s" % secs)
	if got.get("to", "") != "ship_earth":
		_end()
		return
	# ---- back over Duxford, the autopilot lands
	em.arrive(got["c"])
	got = {}
	check("comes back high above Duxford", em.pos.y > 15000.0 and not em.landed, "%.0f m" % em.pos.y)
	secs = run(em, 240.0, 0.0, func(): return em.landed)
	var home := Vector2(em.pos.x, em.pos.z).length()
	check("the autopilot lands at Duxford", em.landed and home < 800.0 and not em.crashed, "%.0f s, %.0f m from the runway" % [secs, home])
	thr = 0.0
	# ---- Pro: the ground is hard
	em.start()
	em.assist = false
	thr = 0.0
	run(em, 0.2, 0.0, func(): return false)
	thr = 1.0
	run(em, 6.0, 0.0, func(): return false)
	em.q = Quaternion(Basis.looking_at(Vector3(0.0, -0.8, -0.6).normalized(), Vector3.UP))
	run(em, 20.0, 0.0, func(): return got.has("end"))
	check("Pro: flying into the ground is a crash", em.crashed and got.get("end", "") == "Crashed")
	_end()


func _end() -> void:
	print("All checks passed" if fails == 0 else "%d check(s) failed" % fails)
	quit(1 if fails > 0 else 0)
