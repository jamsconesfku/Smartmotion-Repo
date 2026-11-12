extends SceneTree
## Pictures of the spaceship (not a check; needs a screen, e.g. xvfb-run):
##   godot --path godot --rendering-driver vulkan --script res://tests/shot_ship.gd -- --out=/tmp/ship
## Draws only the space scenes (not Duxford), so it is quick even on a slow computer.
var out := "/tmp/ship"
var cam: Camera3D
var sm: SpaceMode


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	sm._place_space(cam.global_position)
	await _frames(3)
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s_%s.png" % [out, name])
	print("saved ", name)


func _cockpit(look_down := 0.0) -> void:
	var b := Basis(sm.q)
	cam.global_transform = Transform3D(b * Basis.from_euler(Vector3(-0.08 - look_down, 0, 0)), Transform3D(b, sm.pos) * SpaceShip.EYE)
	cam.fov = 80.0
	cam.near = 0.05


func _chase(back := 25.0, up := 6.0, side := 0.0) -> void:
	var b := Basis(sm.q)
	var cp := sm.pos + b * Vector3(side, up, back)
	cam.global_transform = Transform3D(Basis.looking_at((sm.pos + b * Vector3(0, 1, -20) - cp).normalized(), b.y), cp)
	cam.fov = 70.0
	cam.near = 0.3


func _run() -> void:
	root.get_viewport().size = Vector2i(1600, 900)
	cam = Camera3D.new()
	cam.far = 260000.0
	root.add_child(cam)
	cam.current = true
	sm = SpaceMode.new()
	root.add_child(sm)
	await sm.build(null, "low")
	cam.environment = sm.env
	sm.start()
	sm.running = true
	var inp := {"pitch": 0.0, "roll": 0.0, "yaw": 0.0, "throttle": 0.5, "fire": false, "boost": false, "press": []}
	# 1: above the Earth (just come up from Duxford), cockpit, looking a little down at the console
	sm.arrive({"q": Quaternion(Vector3.RIGHT, -0.25), "vel": Vector3(0, 0, -300), "wv": Vector3.ZERO, "thr": 0.5, "x10": false, "x10_k": 0.0,
		"assist": true, "lights": false, "dest": ShipMode.DESTS.find("mars"), "auto": "", "hints": {}})
	for i in 90:
		sm.step(1.0 / 60.0, inp)
	_cockpit(0.32)
	# a pointing hand pressing PLANET >
	var hand := VRHand.new(false)
	sm.ship.add_child(hand)
	var tip := sm.ship.button_pos("next")
	var cb := sm.ship.console.global_transform.basis
	hand.set_point(1.0)
	hand.set_curl(0.3)
	# grip frame: tube along Z with the index finger at -Z: point it down into the button, palm towards the pilot
	# grip frame: the pointing finger runs along -Y, the forearm along +Y (up and back towards the pilot),
	# the palm (-X) faces forward
	var cz := cb.z.normalized()
	var gy := (cb.y.normalized() + cz * 0.8).normalized()
	var gx := (cz - gy * cz.dot(gy)).normalized()
	var g := Transform3D(Basis(gx, gy, gx.cross(gy)).orthonormalized(), tip)
	hand.place(g)
	hand.global_position += tip - hand.fingertip() + cb.y.normalized() * 0.004
	await _shot("1_cockpit_earth")
	hand.queue_free()
	_chase(28.0, 7.0, 6.0)
	await _shot("2_above_earth")
	# coming back down into the Earth's air, fast
	var sv_pos := sm.pos
	var sv_q := sm.q
	sm.q = Quaternion(Vector3.RIGHT, -0.7)
	sm.pos = Vector3(0, 1600, 0)
	sm.vel = -Basis(sm.q).z * 2500.0
	sm.no_leave = 99.0
	for i in 60:
		sm.step(1.0 / 60.0, {"pitch": 0.0, "roll": 0.0, "yaw": 0.0, "throttle": 1.0, "fire": false, "boost": false, "press": ["x10"] if i == 0 else []})
	sm.pos = Vector3(0, 1600, 0)
	sm.ship.transform = Transform3D(Basis(sm.q), sm.pos)
	_chase(28.0, 7.0, 6.0)
	await _shot("2b_reentry")
	_cockpit()
	await _shot("2c_reentry_cockpit")
	sm.pos = sv_pos
	sm.q = sv_q
	sm.x10 = false
	sm.x10_k = 0.0
	sm.plasma = 0.0
	sm.vel = -Basis(sm.q).z * 300.0
	sm.no_leave = 0.0
	# 3: hyperspeed: the streaks building up, then the tunnel
	sm._start_hyper("jupiter", true)
	while sm.hyper != "spool" or sm.hyper_t < 1.3:
		sm.step(1.0 / 60.0, inp)
	_chase(25.0, 6.0)
	await _shot("3_hyper_spool")
	while sm.hyper != "tunnel" or sm.hyper_t < 1.5:
		sm.step(1.0 / 60.0, inp)
	_cockpit()
	await _shot("4_hyper_tunnel_cockpit")
	_chase(25.0, 6.0)
	await _shot("5_hyper_tunnel_chase")
	while sm.hyper != "":
		sm.step(1.0 / 60.0, inp)
	for i in 60:
		sm.step(1.0 / 60.0, inp)
	_chase(30.0, 8.0, -8.0)
	await _shot("6_jupiter")
	for k in ["saturn", "mars", "neptune", "moon"]:
		sm._arrive_at(k)
		sm._arrived()
		for i in 30:
			sm.step(1.0 / 60.0, inp)
		_chase(30.0, 8.0, -8.0)
		await _shot("7_" + k)
	quit()
