extends SceneTree
## Racing checks (headless):  godot --headless --path godot --script res://tests/test_race.gd
## The car drives itself round the circuit (time trial, then a race against the seven computer cars) and we
## check it stays on the track, sets a sensible lap time and top speed, and the race finishes.
var fails := 0


func check(name: String, ok: bool, info := "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("  " + info if info != "" else ""))
	if not ok:
		fails += 1


func _initialize() -> void:
	var st: Node = load("res://scripts/settings.gd").new()
	st.name = "Settings"
	root.add_child(st)
	st.data["race"] = "trial"
	st.data["assist"] = true
	RaceTrack.terr = Terrain.new()   # the circuit on the real ground west of Duxford, as in the game
	var t0 := Time.get_ticks_msec()
	var track := RaceTrack.new()
	track.build_data()
	print("circuit: %.0f m, %d samples, built in %d ms" % [track.length, track.n, Time.get_ticks_msec() - t0])
	check("circuit is about 4 km", track.length > 3600.0 and track.length < 4400.0, "%.0f m" % track.length)
	var min_r := INF
	for i in track.n:
		min_r = minf(min_r, 1.0 / maxf(absf(track.curv[i]), 0.0001))
	check("tightest corner radius over 20 m", min_r > 20.0, "%.0f m" % min_r)
	# time trial with the autopilot
	var rm := RaceMode.new()
	rm.track = track
	rm.add_child(track)
	rm.car = RaceCar.new()
	rm.add_child(rm.car)
	rm.make_rivals()
	root.add_child(rm)
	rm.start()
	var dt := 1.0 / 60.0
	var t := 0.0
	var vmax := 0.0
	var off := 0.0
	var walls := 0
	var laps_at := []
	var last_lap := 0
	while t < 260.0 and rm.lap < 3:
		rm.step(dt, rm.autopilot())
		t += dt
		vmax = maxf(vmax, absf(rm.vx))
		if rm.surf != "track" and rm.surf != "kerb":
			if off == 0.0 or fmod(t, 2.0) < dt:
				print("  off track at %.0f m, %.1f m from the centre, %d km/h, %s" % [rm.s_now, rm.lat, int(rm.vx * 3.6), rm.surf])
			off += dt
		if rm.bump_t > 0.99:
			walls += 1
		if rm.lap != last_lap:
			laps_at.append(t)
			last_lap = rm.lap
	print("time trial: laps %d, best %s, top speed %d km/h, off track %.1f s, barrier hits %d" % [rm.lap - 1, rm._fmt(rm.best), int(vmax * 3.6), off, walls])
	check("two laps completed", rm.lap >= 3, "lap counter %d after %.0f s" % [rm.lap, t])
	check("lap time between 1:05 and 2:10", rm.best > 65.0 and rm.best < 130.0, rm._fmt(rm.best))
	check("top speed 270-360 km/h", vmax * 3.6 > 270.0 and vmax * 3.6 < 360.0, "%d km/h" % int(vmax * 3.6))
	check("stays on the track (under 3 s off)", off < 3.0, "%.1f s" % off)
	check("no barrier hits", walls == 0, str(walls))
	# braking: 300 km/h to standstill
	rm.vx = 83.0
	rm.vy = 0.0
	rm.r = 0.0
	var bt := 0.0
	var pos0 := rm.pos
	rm.yaw = atan2(track.tan2[0].x, -track.tan2[0].y)
	rm.pos = track.pos3(0)
	rm.si = 0
	while rm.vx > 1.0 and bt < 10.0:
		rm.step(dt, {"steer": 0.0, "throttle": 0.0, "brake": 1.0})
		bt += dt
	check("brakes from 300 km/h in 2-5 s", bt > 2.0 and bt < 5.0, "%.1f s" % bt)
	# the race: the AI must get round three laps without stopping
	st.data["race"] = "race"
	rm.start()
	t = 0.0
	var stuck := 0.0
	while t < 420.0 and rm.phase != "done":
		rm.step(dt, rm.autopilot())
		t += dt
		for a in rm.ais:
			if t > 12.0 and float(a["v"]) < 5.0:
				stuck += dt
	var ai_laps := []
	for a in rm.ais:
		ai_laps.append(int(a["lap"]))
	print("race: finished %s in %s, position %d, rivals' laps %s" % [str(rm.phase == "done"), rm._fmt(rm.race_t), rm.player_pos, str(ai_laps)])
	check("race finishes", rm.phase == "done", "after %.0f s" % t)
	check("rivals keep moving", stuck < 3.0, "%.1f car-seconds below 18 km/h" % stuck)
	check("rivals complete laps", ai_laps.min() >= 2, str(ai_laps))
	print("\nAll checks passed" if fails == 0 else "\n%d checks failed" % fails)
	quit(1 if fails > 0 else 0)
