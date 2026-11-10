extends SceneTree
## Motion checks (headless):  godot --headless --path motion --script res://tests/test_cueing.gd
var fails := 0

func check(name: String, ok: bool, info := "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("  " + info if info != "" else ""))
	if not ok:
		fails += 1

func frame(surge := 0.0, sway := 0.0, heave := 1.0, rates := Vector3.ZERO, extra := {}) -> Dictionary:
	var f := {"g_felt": {"surge": surge, "sway": sway, "heave": heave},
		"rate": {"roll_dps": rates.x, "pitch_dps": rates.y, "yaw_dps": rates.z}, "paused": false, "crashed": false,
		"on_ground": false, "gs_kt": 0.0}
	f.merge(extra, true)
	return f

## Runs secs of cueing; returns the largest |value| and largest change per second seen for each axis.
func run(c: Cueing, secs: float, fn: Callable) -> Dictionary:
	var mx := {}
	var mv := {}
	var prev := c.pose.duplicate()
	for a in Cueing.AXES:
		mx[a] = 0.0
		mv[a] = 0.0
	var n := int(secs * Cueing.HZ)
	for i in n:
		var t := i * Cueing.DT
		var r: Array = fn.call(t)
		c.step(r[0], r[1])
		for a in Cueing.AXES:
			mx[a] = maxf(mx[a], absf(float(c.pose[a])))
			mv[a] = maxf(mv[a], absf(float(c.pose[a]) - float(prev[a])) * Cueing.HZ)
		prev = c.pose.duplicate()
	return {"max": mx, "speed": mv}

func fresh() -> Cueing:
	var c := Cueing.new()
	c.cfg["intensity"] = 1.0
	c.cfg["rumble_mm"] = 0.0
	c.want_on = true
	return c

func _initialize() -> void:
	# 1. straight and level: the seat stays in the middle
	var c := fresh()
	run(c, 8.0, func(_t): return [frame(), 0.0])
	var mid := true
	for a in Cueing.AXES:
		mid = mid and absf(float(c.pose[a])) < 0.05
	check("level flight keeps the seat in the middle", mid, str(c.pose))
	check("fades in fully", c.scale == 1.0)

	# 2. braking: seat moves back first, then the nose tilts down (gravity pushes you into the belts)
	c = fresh()
	run(c, 3.0, func(_t): return [frame(), 0.0])
	var early := 0.0
	var r := run(c, 0.5, func(_t): return [frame(-0.4), 0.0])
	early = float(c.pose["surge"])
	check("braking: seat moves back at once", early < -5.0, "surge %.1f mm" % early)
	run(c, 8.0, func(_t): return [frame(-0.4), 0.0])
	check("braking: nose tilts down and stays down", float(c.pose["pitch"]) < -5.0, "pitch %.2f°" % float(c.pose["pitch"]))
	check("braking: surge drifts back to the middle", absf(float(c.pose["surge"])) < 8.0, "surge %.1f mm" % float(c.pose["surge"]))

	# 3. speeding up (take-off run): pushed into the seat back = nose up
	c = fresh()
	run(c, 10.0, func(_t): return [frame(0.3), 0.0])
	check("speeding up: nose up", float(c.pose["pitch"]) > 5.0, "pitch %.2f°" % float(c.pose["pitch"]))
	check("tilt stays under its limit", float(c.pose["pitch"]) <= float(c.cfg["tilt_max_deg"]) + 0.01)

	# 4. sideways force to the left (left turn on the ground): seat leans right side down, slides left first
	c = fresh()
	run(c, 2.0, func(_t): return [frame(), 0.0])
	r = run(c, 0.4, func(_t): return [frame(0.0, -0.3), 0.0])
	check("left turn: seat slides left first", float(c.pose["sway"]) < -3.0, "sway %.1f mm" % float(c.pose["sway"]))
	run(c, 8.0, func(_t): return [frame(0.0, -0.3), 0.0])
	check("left turn: right side down", float(c.pose["roll"]) > 4.0, "roll %.2f°" % float(c.pose["roll"]))

	# 5. tilt is slow: never faster than the tilt speed (3°/s) when only lasting forces act
	c = fresh()
	run(c, 2.0, func(_t): return [frame(), 0.0])
	r = run(c, 6.0, func(_t): return [frame(0.5, 0.5), 0.0])
	check("tilt speed under 3°/s", float(r["speed"]["pitch"]) <= 3.05 and float(r["speed"]["roll"]) <= 3.05, "pitch %.2f, roll %.2f °/s" % [float(r["speed"]["pitch"]), float(r["speed"]["roll"])])

	# 6. roll rate: a quick roll to the right gives a short twitch right side down, which washes out
	c = fresh()
	run(c, 2.0, func(_t): return [frame(), 0.0])
	run(c, 0.5, func(_t): return [frame(0, 0, 1, Vector3(40, 0, 0)), 0.0])
	var tw := float(c.pose["roll"])
	run(c, 15.0, func(_t): return [frame(0, 0, 1, Vector3(40, 0, 0)), 0.0])
	check("roll rate: twitch right side down", tw > 1.0, "roll %.2f°" % tw)
	check("roll rate: washes out while the roll carries on", absf(float(c.pose["roll"])) < 0.5, "roll %.2f°" % float(c.pose["roll"]))

	# 7. a crash-like mess of huge values: never past the limits, the speed limits or the acceleration limits
	c = fresh()
	r = run(c, 10.0, func(t): return [frame(sin(t * 37.0) * 9.0, cos(t * 23.0) * 9.0, 1.0 + sin(t * 51.0) * 9.0, Vector3(sin(t * 7) * 300, cos(t * 5) * 300, sin(t * 3) * 300)), 0.0])
	var inside := true
	var slow := true
	for a in Cueing.AXES:
		var rot: bool = a in ["yaw", "roll", "pitch"]
		inside = inside and float(r["max"][a]) <= float(c.cfg["limit_deg" if rot else "limit_mm"]) + 0.001
		slow = slow and float(r["speed"][a]) <= float(c.cfg["speed_deg_s" if rot else "speed_mm_s"]) * 1.02
	check("wild input stays inside the travel limits", inside, str(r["max"]))
	check("wild input stays under the speed limits", slow, str(r["speed"]))

	# 8. lost data, pause and crash: fade back to the middle smoothly
	for what in ["no data", "paused", "crashed"]:
		c = fresh()
		run(c, 6.0, func(_t): return [frame(0.3, -0.3), 0.0])
		var before := absf(float(c.pose["pitch"])) + absf(float(c.pose["roll"]))
		r = run(c, 6.0, func(_t):
			if what == "no data":
				return [frame(0.3, -0.3), 5.0]
			return [frame(0.3, -0.3, 1.0, Vector3.ZERO, {what: true}), 0.0])
		var after := 0.0
		for a in Cueing.AXES:
			after += absf(float(c.pose[a]))
		check(what + ": back to the middle", before > 5.0 and after < 0.2 and c.scale == 0.0, "before %.1f, after %.2f" % [before, after])
		check(what + ": goes back gently", float(r["speed"]["pitch"]) < 10.0 and float(r["speed"]["roll"]) < 10.0, "%.1f / %.1f °/s" % [float(r["speed"]["pitch"]), float(r["speed"]["roll"])])

	# 9. motion off: fades out; motion on again: fades in without a jump
	c = fresh()
	run(c, 6.0, func(_t): return [frame(0.3), 0.0])
	c.want_on = false
	r = run(c, 4.0, func(_t): return [frame(0.3), 0.0])
	check("motion off: back to the middle", c.at_rest(), str(c.pose))
	c.want_on = true
	r = run(c, 4.0, func(_t): return [frame(0.3), 0.0])
	check("motion on again: no jump", float(r["speed"]["pitch"]) < 10.0 and float(r["speed"]["surge"]) < 100.0, "%.1f °/s, %.1f mm/s" % [float(r["speed"]["pitch"]), float(r["speed"]["surge"])])

	# 10. strength scales the movement
	c = fresh()
	c.cfg["intensity"] = 0.5
	run(c, 10.0, func(_t): return [frame(0.3), 0.0])
	var half := float(c.pose["pitch"])
	c = fresh()
	run(c, 10.0, func(_t): return [frame(0.3), 0.0])
	check("half strength = about half the tilt", absf(half / float(c.pose["pitch"]) - 0.5) < 0.08, "%.2f vs %.2f" % [half, float(c.pose["pitch"])])

	# 11. belt: tightens when braking, nothing when switched off
	c = fresh()
	c.cfg["belt_on"] = true
	run(c, 3.0, func(_t): return [frame(), 0.0])
	var level := c.belt
	run(c, 2.0, func(_t): return [frame(-0.5), 0.0])
	check("belt tightens when braking", c.belt > level + 0.3, "%.2f -> %.2f" % [level, c.belt])
	c.cfg["belt_on"] = false
	run(c, 1.0, func(_t): return [frame(-0.5), 0.0])
	check("belt off = no tension", c.belt == 0.0)

	# 12. runway rumble only on the ground and small
	c = fresh()
	c.cfg["rumble_mm"] = 0.4
	r = run(c, 3.0, func(_t): return [frame(0, 0, 1, Vector3.ZERO, {"on_ground": true, "gs_kt": 60.0}), 0.0])
	check("runway rumble is small", float(r["max"]["heave"]) > 0.1 and float(r["max"]["heave"]) < 1.0, "%.2f mm" % float(r["max"]["heave"]))

	# 13. test movement follows the sliders through the limits
	c = fresh()
	for i in 2000:
		c.step({}, 999.0, {"sway": 30.0, "pitch": -5.0})
	check("test movement reaches the slider values", absf(float(c.pose["sway"]) - 30.0) < 0.5 and absf(float(c.pose["pitch"]) + 5.0) < 0.1, str(c.pose))
	for i in 2000:
		c.step({}, 999.0, {"sway": 500.0})
	check("test movement can't pass the limit", float(c.pose["sway"]) <= float(c.cfg["limit_mm"]))

	# 14. the bytes sent to the controller (docs.motion4sim.com: Position Motion Mode, Serial Commands)
	var pk := RigLink.pose_packet({"sway": 12.5, "surge": -3.0, "heave": 1.0, "yaw": 0.5, "roll": -2.25, "pitch": 4.0}, 1.0, 0.0, {"roll": true})
	check("pose packet is 36 bytes", pk.size() == 36, str(pk.size()))
	check("pose packet starts 252 252 and ends 10 13", pk[0] == 252 and pk[1] == 252 and pk[34] == 10 and pk[35] == 13)
	var sb := StreamPeerBuffer.new()
	sb.data_array = pk.slice(2, 34)
	var vals := []
	for i in 6:
		vals.append(sb.get_float())
	var beltv := sb.get_u32()
	var windv := sb.get_u32()
	check("pose packet values, low byte first, roll flipped", vals == [12.5, -3.0, 1.0, 0.5, 2.25, 4.0], str(vals))
	check("belt full = 0xFFFFFFFF, wind 0", beltv == 4294967295 and windv == 0, "%d %d" % [beltv, windv])
	check("go online command", RigLink.command_frame(RigLink.CMD_ONLINE, 0) == PackedByteArray([249, 249, 6, 0, 0, 0, 10, 13]))
	check("go offline command", RigLink.command_frame(RigLink.CMD_ONLINE, 1) == PackedByteArray([249, 249, 6, 0, 1, 0, 10, 13]))
	check("start rig command", RigLink.command_frame(RigLink.CMD_START, 0) == PackedByteArray([249, 249, 128, 0, 0, 0, 10, 13]))
	var rx := PackedByteArray([1, 2, 249, 249, 0, 0, 18, 0, 10, 13, 254, 249, 249, 2, 0, 0x2a, 5, 10, 13, 249, 249])
	var rep := RigLink.parse_replies(rx)
	check("reads the controller's answers", rep == [[0, 18], [2, 0x052a]] and rx == PackedByteArray([249, 249]), "%s rest %s" % [str(rep), str(rx)])
	check("state 18 = online, moving", RigLink.state_text(18) == "online, moving")

	# 15. the picture's pose: nose up tips the front up, roll + puts the right side down
	var tr := RigView.pose_transform({"pitch": 10.0})
	check("picture: pitch + = nose up", (tr.basis * Vector3.FORWARD).y > 0.1)
	tr = RigView.pose_transform({"roll": 10.0})
	check("picture: roll + = right side down", (tr.basis * Vector3.RIGHT).y < -0.1)
	tr = RigView.pose_transform({"yaw": 10.0})
	check("picture: yaw + = nose right", (tr.basis * Vector3.FORWARD).x > 0.1)

	print("\nAll checks passed" if fails == 0 else "\n%d checks failed" % fails)
	quit(1 if fails > 0 else 0)
