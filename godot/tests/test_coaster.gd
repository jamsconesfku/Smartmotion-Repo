extends SceneTree
## Roller coaster checks (headless):  godot --headless --path godot --script res://tests/test_coaster.gd
## Rides one lap and checks it gets round, stays within comfortable forces and ends stopped in the station.
var fails := 0


func check(name: String, ok: bool, info := "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("  " + info if info != "" else ""))
	if not ok:
		fails += 1


func _initialize() -> void:
	var cm := CoasterMode.new()
	root.add_child(cm)
	cm.build_track(null)
	print("track %.0f m, chain lift %.0f-%.0f m" % [cm.length, cm.lift_from, cm.lift_to])
	check("track is about 1 km", cm.length > 900.0 and cm.length < 1200.0, "%.0f m" % cm.length)
	check("chain lift found", cm.lift_to - cm.lift_from > 80.0, "%.0f m" % (cm.lift_to - cm.lift_from))
	cm.start()
	var dt := 1.0 / 60.0
	var t := 0.0
	var vmax := 0.0
	var gmin := 9.0
	var gmax := -9.0
	var lat := 0.0
	var vslow := 99.0
	while t < 240.0 and cm.phase != "done":
		cm.step(dt, {})
		t += dt
		vmax = maxf(vmax, cm.v)
		if cm.t_ride > 3.0:
			gmin = minf(gmin, cm.felt.y / 9.81)
			gmax = maxf(gmax, cm.felt.y / 9.81)
			lat = maxf(lat, absf(cm.felt.x) / 9.81)
			if cm._zone(fposmod(cm.s, cm.length)) == "":
				vslow = minf(vslow, cm.v)
	print("ride %.0f s, top speed %d km/h, force %.2f to %.2f g, sideways up to %.2f g, slowest %.1f m/s" % [t, int(vmax * 3.6), gmin, gmax, lat, vslow])
	check("ride finishes in the station", cm.phase == "done", "after %.0f s" % t)
	check("ride lasts 1:30 to 3:30", t > 90.0 and t < 210.0, "%.0f s" % t)
	check("top speed 90-115 km/h", vmax * 3.6 > 90.0 and vmax * 3.6 < 115.0, "%d km/h" % int(vmax * 3.6))
	check("never stalls on the track", vslow > 1.5, "%.1f m/s" % vslow)
	check("forces between -0.3 and 4 g", gmin > -0.3 and gmax < 4.0, "%.2f to %.2f g" % [gmin, gmax])
	check("little sideways force (track banks, under 0.8 g)", lat < 0.8, "%.2f g" % lat)
	print("\nAll checks passed" if fails == 0 else "\n%d checks failed" % fails)
	quit(1 if fails > 0 else 0)
