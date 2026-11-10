extends SceneTree
## Flight model checks (headless):  godot --headless --path godot --script res://tests/test_flight.gd
const KT := 1.94384
const FT := 3.28084
var fails := 0
var terrain: Terrain

func check(name: String, ok: bool, info := "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("  " + info if info != "" else ""))
	if not ok:
		fails += 1

func run(fm: FlightModel, secs: float, inp_fn: Callable, tick := Callable()) -> void:
	var dt := 1.0 / 60.0
	var t := 0.0
	while t < secs and not fm.crashed:
		fm.step(dt, inp_fn.call(t, fm))
		if tick.is_valid():
			tick.call(t, fm)
		t += dt

func start(key: String, o: Dictionary) -> FlightModel:
	var fm := FlightModel.new(key, terrain)
	var xz := terrain.from_runway(o.get("u", -700.0), o.get("v", 0.0))
	var d := {"x": xz.x, "z": xz.y, "heading": Terrain.RW_HEADING_DEG}
	d.merge(o, true)
	fm.reset(d)
	return fm

func _initialize() -> void:
	terrain = Terrain.new()
	print("terrain: runway height %.1f m; 3 km away %.1f m" % [terrain.height(0, 0), terrain.height(3000, 1000)])
	var flat := true
	for u in [-700.0, -350.0, 0.0, 350.0, 700.0]:
		for v in [-20.0, 0.0, 20.0]:
			var xz := terrain.from_runway(u, v)
			flat = flat and absf(terrain.height(xz.x, xz.y) - Terrain.RW_ELEV) < 0.05
	check("runway is flat", flat, "real heights loaded: %s" % str(terrain.real))
	for key in ["bulldog", "trainer", "fighter"]:
		print("\n=== %s ===" % key)
		var fm := start(key, {})
		var sp: Dictionary = fm.spec
		run(fm, 5.0, func(_t, _m): return {"pitch": 0.0, "roll": 0.0, "yaw": 0.0, "throttle": 0.0, "brake": 1.0, "flaps": 0.0})
		check("rests on its wheels", not fm.crashed and fm.vel.length() < 0.2, "speed %.3f pitch %.1f" % [fm.vel.length(), fm.euler()["pitch"]])

		fm = start(key, {})
		var vr: float = sp["vr"] * 1.12
		var liftoff := {}
		var d0 := fm.pos
		run(fm, 70.0, func(_t, m):
			var pitch := 0.0
			if m.i["ias"] > vr:
				pitch = 0.35
			elif key == "fighter" and m.i["ias"] > 20.0:
				pitch = -0.1
			return {"pitch": pitch, "roll": 0.0, "yaw": 0.0, "throttle": 1.0, "brake": 0.0, "flaps": 0.0},
			func(t, m):
				if liftoff.is_empty() and not m.i["on_ground"] and m.i["ias"] > 15.0:
					liftoff["d"] = Vector2(m.pos.x - d0.x, m.pos.z - d0.z).length()
					liftoff["ias"] = m.i["ias"])
		check("takes off", not liftoff.is_empty() and not fm.crashed, "liftoff after %d m at %d kt" % [liftoff.get("d", 0), liftoff.get("ias", 0) * KT])
		check("climbs away", fm.i["alt_agl"] > 120.0 and not fm.crashed, "%d ft after 70 s, %d kt" % [fm.i["alt_agl"] * FT, fm.i["ias"] * KT])
		check("stays on runway heading", absf(fposmod(fm.i["heading"] - Terrain.RW_HEADING_DEG + 540.0, 360.0) - 180.0) < 8.0, "heading %.1f" % fm.i["heading"])

		fm = start(key, {"airborne": true, "agl": 600.0, "speed": sp["cruise"], "heading": Terrain.RW_HEADING_DEG})
		var h0 := fm.pos.y
		run(fm, 60.0, func(_t, _m): return {"pitch": 0.0, "roll": 0.0, "yaw": 0.0, "throttle": sp["cruiseThrottle"], "flaps": 0.0})
		check("holds altitude hands off (assist)", not fm.crashed and absf(fm.pos.y - h0) < 40.0, "change %.1f m, %d kt" % [fm.pos.y - h0, fm.i["ias"] * KT])

		fm = start(key, {"airborne": true, "agl": 800.0, "speed": sp["cruise"], "heading": 0.0})
		var tr := {"bank": 0.0, "h10": 0.0, "h20": 0.0}
		run(fm, 25.0, func(t, _m): return {"pitch": 0.0, "roll": 0.5 if t > 2.0 else 0.0, "yaw": 0.0, "throttle": sp["cruiseThrottle"]},
			func(t, m):
				if t > 10.0: tr["bank"] = m.i["roll"]
				if t <= 10.0: tr["h10"] = m.i["heading"]
				if t <= 20.0: tr["h20"] = m.i["heading"])
		var bank: float = tr["bank"]
		var turn: float = (fposmod(tr["h20"] - tr["h10"] + 540.0, 360.0) - 180.0) / 10.0
		var expect: float = (FlightModel.G * tan(32.5 * FlightModel.D2R) / fm.i["tas"]) / FlightModel.D2R
		check("half stick gives a steady banked turn", absf(bank - 32.5) < 6.0 and absf(turn - expect) < 1.8, "bank %.1f, turn %.1f deg/s (expected %.1f)" % [bank, turn, expect])

		fm = start(key, {"airborne": true, "agl": 1500.0, "speed": sp["cruise"] * 0.8, "heading": 0.0})
		fm.assist = false
		var stalled := {}
		run(fm, 40.0, func(t, _m): return {"pitch": 0.55 + (0.45 if t > 5.0 else 0.0), "roll": 0.0, "yaw": 0.0, "throttle": 0.0},
			func(t, m):
				if stalled.is_empty() and m.i["stall"]:
					stalled["t"] = t
					stalled["ias"] = m.i["ias"])
		check("stalls when pulled back with no power", not stalled.is_empty() and not fm.crashed, "stall at %d kt" % [stalled.get("ias", 0) * KT])
		run(fm, 22.0, func(t, _m): return {"pitch": -0.4 if t < 3.0 else 0.15, "roll": 0.0, "yaw": 0.0, "throttle": 1.0})
		check("recovers with stick forward and power", not fm.crashed and not fm.i["stall"], "%d kt, %d m AGL" % [fm.i["ias"] * KT, fm.i["alt_agl"]])

		var lxz := terrain.from_runway(-2900.0, 0.0)
		fm = start(key, {"x": lxz.x, "z": lxz.y, "airborne": true, "agl": 150.0, "speed": sp["vr"] * 1.5, "heading": Terrain.RW_HEADING_DEG})
		var td := {}
		var v_app: float = sp["vr"] * 1.4
		run(fm, 160.0, func(_t, m):
			var uv := terrain.to_runway(m.pos.x, m.pos.z)
			var agl: float = m.i["alt_agl"]
			var pitch := 0.0
			var thr := 0.0
			if m.i["on_ground"]:
				pitch = 0.05
			elif agl > 10.0:
				pitch = -0.25
				thr = clampf(0.3 + (v_app - m.i["ias"]) * 0.06, 0.0, 1.0)
			else:
				pitch = clampf(-0.05 + (-m.i["vs"] - 0.6) * 0.15, -0.2, 0.3)
			return {"pitch": pitch, "roll": clampf(-uv.y * 0.003 - sin((m.i["heading"] - Terrain.RW_HEADING_DEG) * FlightModel.D2R) * 1.2, -0.3, 0.3), "yaw": 0.0, "throttle": thr, "brake": 1.0 if (m.i["on_ground"] and m.i["ias"] < 40.0) else 0.0, "flaps": 0.5},
			func(t, m):
				if td.is_empty() and m.i["on_ground"]:
					td["sink"] = -m.i["vs"]
					td["ias"] = m.i["ias"]
					td["u"] = terrain.to_runway(m.pos.x, m.pos.z).x)
		check("lands without crashing", not fm.crashed and not td.is_empty(), "touchdown at u=%d m, %d kt, sink %d fpm" % [td.get("u", 0), td.get("ias", 0) * KT, td.get("sink", 0) * 196.85])
		check("comes to a stop", not fm.crashed and fm.i["gs"] < 3.0, "ground speed %.1f kt" % [fm.i["gs"] * KT])
	print("\n%s" % ("%d check(s) failed" % fails if fails > 0 else "All checks passed"))
	quit(1 if fails > 0 else 0)
