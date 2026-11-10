extends SceneTree
## Checks the streamed real-world scenery: squares load on worker threads as the camera moves,
## buildings get crash boxes, and far squares are freed. Run:
##   godot --headless --path godot --script res://tests/test_scenery.gd

var fails := 0


func check(name: String, ok: bool, info := "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("  " + info if info != "" else ""))
	if not ok:
		fails += 1


func _initialize() -> void:
	var terrain := Terrain.new()
	var sc := RealScenery.new()
	root.add_child(sc)
	sc.setup(terrain, "medium", load("res://assets/world/ortho.jpg"))
	check("buildings loaded", sc.total_buildings > 100000, "%d buildings" % sc.total_buildings)
	sc.preload_around(Vector2.ZERO)
	var n0 := sc.chunks.size()
	check("squares built around the airfield", n0 > 20, "%d squares" % n0)
	var near := sc.colliders_near(Vector2(0, -250))
	check("crash boxes near the hangars", near.size() > 0, "%d boxes" % near.size())
	# fly 9 km east: new squares stream in on worker threads, far ones are dropped
	var t0 := Time.get_ticks_msec()
	var worst := 0
	for f in 900:
		var p := Vector2(f * 10.0, 0.0)
		var a := Time.get_ticks_usec()
		sc.update(p, 1)
		worst = maxi(worst, Time.get_ticks_usec() - a)
		await process_frame
	for f in 300:
		sc.update(Vector2(9000, 0), 1)
		await process_frame
	var far_gone := not sc.chunks.has(sc._chunk_of(Vector2.ZERO))
	var here := sc.chunks.has(sc._chunk_of(Vector2(9000, 0)))
	check("new squares appear where we fly", here)
	check("squares far behind are freed", far_gone)
	check("no jobs left hanging", sc._jobs.size() == 0, "%d" % sc._jobs.size())
	check("streaming never blocks a frame for long", worst < 60000, "worst update %.1f ms" % (worst / 1000.0))
	var c9 := sc.colliders_near(Vector2(9000, 0))
	print("crash boxes near 9 km east: %d; took %.1f s" % [c9.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	print("All checks passed" if fails == 0 else "%d checks failed" % fails)
	quit(1 if fails > 0 else 0)
