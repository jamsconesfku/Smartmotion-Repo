extends Node
## SmartMotion Flight (native): game controller. Input, cameras, flight, gate run, VR (OpenXR) and the rig link.

const APP_VERSION := "1.3.5"
const KT := 1.94384
const FT := 3.28084
const FPM := 196.85

var world: World
var ui: GameUI
var cam: Camera3D
var plane: AircraftModel
var fm: FlightModel
var synth: Synth
var tel := Telemetry.new()
var state := "loading"
var paused := false
var cam_mode := "chase"
var inp := {"pitch": 0.0, "roll": 0.0, "yaw": 0.0, "throttle": 0.0, "brake": 0.0, "flaps": 0.0, "trim": 0.0}
var throttle := 0.0
var flaps_idx := 0
var trim := 0.0
var kb := {"pitch": 0.0, "roll": 0.0, "yaw": 0.0}
var gate := {"next": 0, "t": 0.0, "done": false, "active": false}
var look := Vector2.ZERO
var orbit_yaw := 0.6
var orbit_pitch := 0.25
var orbit_dist := 16.0
var cam_q := Quaternion.IDENTITY
var cam_init := false
var run_time := 0.0
var instr_t := 0.0
var rmb := false
var args := {}
var shot_timer := -1.0
var frame_count := 0
var quality := "high"

# VR
var vr_active := false
var xr_origin: XROrigin3D
var xr_cam: XRCamera3D
var xr_left: XRController3D
var xr_right: XRController3D
var vr_label: Label3D
var vr_frames := 0
var vr_edge := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	Diag.start(not args.has("xr"))
	Diag.write("SmartMotion Flight native v%s started" % APP_VERSION)
	for k in ["aircraft", "start", "mode", "tod", "wind"]:
		if args.has(k):
			Settings.data[k] = args[k]
	if args.has("assist"):
		Settings.data["assist"] = args["assist"] == "true" or args["assist"] == "1"
	if args.has("q"):
		Settings.data["quality"] = args["q"]
	quality = str(Settings.get_value("quality"))
	_apply_window()
	var vp := get_viewport()
	vp.msaa_3d = {"low": Viewport.MSAA_DISABLED, "medium": Viewport.MSAA_2X, "high": Viewport.MSAA_4X}.get(quality, Viewport.MSAA_2X)
	cam = Camera3D.new()
	cam.far = 40000.0
	cam.near = 0.4
	cam.fov = 68.0
	add_child(cam)
	cam.current = true
	world = World.new()
	add_child(world)
	synth = Synth.new()
	add_child(synth)
	ui = GameUI.new()
	add_child(ui)
	await get_tree().process_frame
	ui.fly_pressed.connect(_on_fly)
	ui.resume_pressed.connect(func(): _pause(false))
	ui.restart_pressed.connect(start_flight)
	ui.menu_pressed.connect(to_menu)
	ui.setting_changed.connect(_on_setting)
	ui.diag_pressed.connect(_copy_diag)
	var gpu := RenderingServer.get_video_adapter_name()
	ui.set_gpu_text("Graphics: %s  ·  %s  ·  F11 for full screen. If that isn't your NVIDIA/AMD card, set Windows Graphics Settings to High performance for this app." % [gpu, RenderingServer.get_current_rendering_method()])
	Diag.snapshot()
	await world.build(ui.set_progress, quality, str(Settings.get_value("tod")))
	if Settings.get_value("tel"):
		tel.start(str(Settings.get_value("tel_host")), int(Settings.get_value("tel_port")))
	ui.vr_btn.visible = XRServer.find_interface("OpenXR") != null
	to_menu()
	if args.has("auto") or args.has("vr"):
		await get_tree().create_timer(0.3).timeout
		await _on_fly(args.has("vr"))
	if args.has("telemetry"):
		var hp: PackedStringArray = str(args["telemetry"]).split(":")
		Settings.data["tel"] = true
		tel.start(hp[0], int(hp[1]))
	if args.has("sheet"):
		await get_tree().create_timer(0.5).timeout
		ui.open_sheet({"settings": ui.settings_sheet, "help": ui.help_sheet, "pause": ui.pause_sheet}[str(args["sheet"])])
	if args.has("cam"):
		cam_mode = args["cam"]
		_apply_view()
	if args.has("shot"):
		shot_timer = float(args.get("shot_after", "6"))


func _apply_window() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if Settings.get_value("fullscreen") else DisplayServer.WINDOW_MODE_WINDOWED)


# ------------------------------------------------------------ settings and menu
func _on_setting(key: String, value) -> void:
	Settings.set_value(key, value)
	match key:
		"aircraft":
			if state == "menu":
				showcase()
		"tod":
			world.set_time_of_day(str(value))
		"fullscreen":
			_apply_window()
		"tel", "tel_host", "tel_port":
			if Settings.get_value("tel"):
				tel.start(str(Settings.get_value("tel_host")), int(Settings.get_value("tel_port")))
			else:
				tel.stop()
		"quality":
			ui.toast("Graphics quality changes next time you start the game", 3.0)


func _on_fly(vr: bool) -> void:
	Diag.write("CLICK: %s" % ("Fly in VR" if vr else "Fly"))
	if vr and not await _start_vr():
		Diag.write("VR did not start")
		return
	start_flight()


func _copy_diag() -> void:
	Diag.write("CLICK: Copy diagnostics")
	Diag.snapshot()
	DisplayServer.clipboard_set(Diag.full_text())
	ui.set_vr_note("Diagnostics copied. Paste them into the chat (Ctrl+V). They are also saved in: " + Diag.log_path())


func _xr_mode_flag() -> bool:
	# true when this run was started in VR mode (by the VR .bat file or by the game's own restart);
	# the marker stops the game from restarting itself more than once
	return args.has("xr")


func showcase() -> void:
	state = "menu"
	paused = false
	world.wind = Vector3.ZERO
	fm = FlightModel.new(str(Settings.get_value("aircraft")), world.terrain)
	var xz := world.terrain.from_runway(-Terrain.RW_LEN / 2.0 + 70.0, 0.0)
	fm.reset({"x": xz.x, "z": xz.y, "heading": 62.0})
	_mount_plane()
	cam_mode = "chase"
	_apply_view()
	world.set_gates(false, 0)
	_place_plane(0.0)


func to_menu() -> void:
	_stop_vr()
	ui.hide_sheets()
	ui.show_menu()
	ui.show_pause(false)
	showcase()


func _mount_plane() -> void:
	if plane != null:
		plane.queue_free()
	plane = AircraftModel.new()
	var key := str(Settings.get_value("aircraft"))
	plane.build(key, world.logo if key == "trainer" else world.logo_dark)
	add_child(plane)
	if vr_active and xr_origin != null:
		xr_origin.get_parent().remove_child(xr_origin)
		plane.add_child(xr_origin)


func _apply_view() -> void:
	var cp := cam_mode == "cockpit" or vr_active
	if plane != null:
		plane.set_cockpit_view(cp)
	if ui != null and ui.adi != null:
		ui.adi.visible = not cp


func _place_plane(dt: float) -> void:
	plane.position = fm.pos
	plane.quaternion = fm.q
	plane.update_visuals(fm.surf, fm.engine, dt, fm.ias)


# ------------------------------------------------------------ flight set-up
func _start_pose() -> Dictionary:
	var spec: Dictionary = FlightModel.SPECS[str(Settings.get_value("aircraft"))]
	if Settings.get_value("mode") == "gates":
		var xz := world.terrain.from_runway(-500.0, 0.0)
		var g: Array = Terrain.GATES[0]
		var hd := fposmod(rad_to_deg(atan2(g[0] - xz.x, -(g[1] - xz.y))), 360.0)
		return {"x": xz.x, "z": xz.y, "heading": hd, "airborne": true, "agl": 140.0, "speed": spec["cruise"], "throttle": spec["cruiseThrottle"]}
	if Settings.get_value("start") == "air":
		var xz2 := world.terrain.from_runway(-1300.0, 0.0)
		return {"x": xz2.x, "z": xz2.y, "heading": 62.0, "airborne": true, "agl": 380.0, "speed": spec["cruise"], "throttle": spec["cruiseThrottle"]}
	var xz3 := world.terrain.from_runway(-Terrain.RW_LEN / 2.0 + 70.0, 0.0)
	return {"x": xz3.x, "z": xz3.y, "heading": 62.0}


func start_flight() -> void:
	world.wind = Vector3(-3.5, 0, 2) if Settings.get_value("wind") == "breezy" else Vector3.ZERO
	world.set_time_of_day(str(Settings.get_value("tod")))
	fm = FlightModel.new(str(Settings.get_value("aircraft")), world.terrain)
	fm.wind = world.wind
	fm.assist = bool(Settings.get_value("assist"))
	var pose := _start_pose()
	fm.reset(pose)
	_mount_plane()
	if cam_mode != "cockpit":
		cam_mode = "chase"
	_apply_view()
	cam_init = false
	throttle = float(pose.get("throttle", 0.0))
	flaps_idx = 0
	trim = 0.0
	kb = {"pitch": 0.0, "roll": 0.0, "yaw": 0.0}
	gate = {"next": 0, "t": 0.0, "done": false, "active": Settings.get_value("mode") == "gates"}
	world.set_gates(gate["active"], 0)
	ui.gate_box.visible = gate["active"]
	ui.tag_assist.text = "EASY" if fm.assist else "PRO"
	state = "fly"
	paused = false
	ui.show_hud()
	ui.show_pause(false)
	ui.adi.visible = cam_mode != "cockpit" and not vr_active
	ui.set_message("", false)
	if fm.i["on_ground"]:
		_toast("Full power, then pull back at about %d knots" % int(fm.spec["vr"] * 1.12 * KT), 4.5)
	elif gate["active"]:
		_toast("Fly through the orange gates as fast as you can", 4.0)


func end_flight(title: String, label: String, text: String, big: String) -> void:
	state = "ended"
	await get_tree().create_timer(0.9).timeout
	if state == "ended":
		ui.show_end(title, label, text, big)
		if vr_active:
			_vr_text("%s\nPress Y to fly again" % title)


# ------------------------------------------------------------ input
func _k(code: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(code) else 0.0


static func _dz(v: float) -> float:
	return 0.0 if absf(v) < 0.12 else (v - signf(v) * 0.12) / 0.88


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		match e.physical_keycode:
			KEY_F:
				flaps_idx = (flaps_idx + 1) % 3
				_toast("Flaps " + ["up", "half", "full"][flaps_idx])
			KEY_V, KEY_C:
				_cycle_camera()
			KEY_P, KEY_ESCAPE:
				if ui.help_sheet.visible:
					ui.close_sheet(ui.help_sheet)
				elif ui.settings_sheet.visible:
					ui.close_sheet(ui.settings_sheet)
				elif state == "fly":
					_pause(not paused)
			KEY_R:
				if state == "fly" or state == "ended":
					start_flight()
			KEY_T:
				ui.tel_panel.visible = not ui.tel_panel.visible
			KEY_M:
				Settings.set_value("sound", not Settings.get_value("sound"))
				ui.set_seg("sound", Settings.get_value("sound"))
				_toast("Sound on" if Settings.get_value("sound") else "Sound off")
			KEY_F11:
				Settings.set_value("fullscreen", not Settings.get_value("fullscreen"))
				ui.set_seg("fullscreen", Settings.get_value("fullscreen"))
				_apply_window()
			KEY_HOME:
				throttle = 1.0
			KEY_END:
				throttle = 0.0
			KEY_BRACKETLEFT:
				trim = clampf(trim - 0.03, -0.5, 0.5)
			KEY_BRACKETRIGHT:
				trim = clampf(trim + 0.03, -0.5, 0.5)
			_:
				if e.physical_keycode >= KEY_0 and e.physical_keycode <= KEY_9:
					var d: int = e.physical_keycode - KEY_0
					throttle = 1.0 if d == 0 else d / 10.0
	elif e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_RIGHT:
			rmb = e.pressed
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
			orbit_dist = clampf(orbit_dist * 0.92, 8.0, 60.0)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
			orbit_dist = clampf(orbit_dist * 1.08, 8.0, 60.0)
	elif e is InputEventMouseMotion and (rmb or state == "menu"):
		if cam_mode == "cockpit" and state != "menu":
			look.x = clampf(look.x - e.relative.x * 0.004, -2.2, 2.2)
			look.y = clampf(look.y - e.relative.y * 0.004, -1.0, 1.0)
		else:
			orbit_yaw -= e.relative.x * 0.005
			orbit_pitch = clampf(orbit_pitch + e.relative.y * 0.004, -0.2, 1.3)


func _cycle_camera() -> void:
	if state != "fly" and state != "ended":
		return
	if vr_active:
		_recentre_vr()   # V or C recentres the view in VR, so a keyboard alone is enough
		return
	cam_mode = {"chase": "cockpit", "cockpit": "orbit", "orbit": "chase"}[cam_mode]
	_apply_view()
	cam_init = false
	_toast({"chase": "Chase view", "cockpit": "Cockpit view", "orbit": "Orbit view (right mouse + drag)"}[cam_mode])


func _pause(on: bool) -> void:
	if state != "fly":
		return
	paused = on
	ui.show_pause(on)
	if vr_active:
		_vr_text("Paused\nX resume · Y restart" if on else "")


func _approach(cur: float, tgt: float, rate: float, dt: float) -> float:
	return cur + clampf(tgt - cur, -rate * dt, rate * dt)


func _read_input(dt: float) -> void:
	var tp := -(_k(KEY_UP) + _k(KEY_W)) + (_k(KEY_DOWN) + _k(KEY_S))
	tp = clampf(tp, -1.0, 1.0)
	var tr := clampf((_k(KEY_RIGHT) + _k(KEY_D)) - (_k(KEY_LEFT) + _k(KEY_A)), -1.0, 1.0)
	var ty := _k(KEY_E) - _k(KEY_Q)
	kb["pitch"] = _approach(kb["pitch"], tp, 2.6 if tp != 0.0 else 4.0, dt)
	kb["roll"] = _approach(kb["roll"], tr, 3.0 if tr != 0.0 else 4.5, dt)
	kb["yaw"] = _approach(kb["yaw"], ty, 4.0 if ty != 0.0 else 6.0, dt)
	var pitch := 0.0
	var roll := 0.0
	var yaw := 0.0
	var thr_axis := 0.0
	var brake := 0.0
	var pads := Input.get_connected_joypads()
	if pads.size() > 0:
		var id: int = pads[0]
		roll = _dz(Input.get_joy_axis(id, JOY_AXIS_RIGHT_X))
		pitch = _dz(Input.get_joy_axis(id, JOY_AXIS_RIGHT_Y))
		yaw = _dz(Input.get_joy_axis(id, JOY_AXIS_LEFT_X))
		thr_axis = -_dz(Input.get_joy_axis(id, JOY_AXIS_LEFT_Y))
		brake = Input.get_joy_axis(id, JOY_AXIS_TRIGGER_LEFT)
		if Input.is_joy_button_pressed(id, JOY_BUTTON_LEFT_SHOULDER):
			yaw = -1.0
		if Input.is_joy_button_pressed(id, JOY_BUTTON_RIGHT_SHOULDER):
			yaw = 1.0
		thr_axis += float(Input.is_joy_button_pressed(id, JOY_BUTTON_DPAD_UP)) - float(Input.is_joy_button_pressed(id, JOY_BUTTON_DPAD_DOWN))
		if _edge("pa", Input.is_joy_button_pressed(id, JOY_BUTTON_A)):
			flaps_idx = (flaps_idx + 1) % 3
			_toast("Flaps " + ["up", "half", "full"][flaps_idx])
		if _edge("pb", Input.is_joy_button_pressed(id, JOY_BUTTON_B)):
			_cycle_camera()
		if _edge("ps", Input.is_joy_button_pressed(id, JOY_BUTTON_START)):
			_pause(not paused)
	if vr_active:
		var v := _read_vr()
		roll += v["roll"]
		pitch += v["pitch"]
		yaw += v["yaw"]
		thr_axis += v["thr"]
		brake = maxf(brake, v["brake"])
	var inv := -1.0 if Settings.get_value("invert") else 1.0
	inp["pitch"] = clampf(kb["pitch"] + pitch * inv, -1.0, 1.0)
	inp["roll"] = clampf(kb["roll"] + roll, -1.0, 1.0)
	inp["yaw"] = clampf(kb["yaw"] + yaw, -1.0, 1.0)
	thr_axis += (_k(KEY_SHIFT) + _k(KEY_PAGEUP) + _k(KEY_X)) - (_k(KEY_CTRL) + _k(KEY_PAGEDOWN) + _k(KEY_Z))
	throttle = clampf(throttle + thr_axis * 0.35 * dt, 0.0, 1.0)
	inp["throttle"] = throttle
	inp["brake"] = maxf(maxf(_k(KEY_SPACE), _k(KEY_B)), brake)
	inp["flaps"] = flaps_idx / 2.0
	inp["trim"] = trim


func _edge(id: String, down: bool) -> bool:
	var was: bool = vr_edge.get(id, false)
	vr_edge[id] = down
	return down and not was


# ------------------------------------------------------------ VR (OpenXR: Meta Quest via Link / Air Link)
func _start_vr() -> bool:
	var xr := XRServer.find_interface("OpenXR")
	ui.set_vr_note("")
	Diag.write("_start_vr: interface found=%s initialized=%s started-in-xr-mode=%s" % [str(xr != null), str(xr != null and xr.is_initialized()), str(_xr_mode_flag())])
	if xr == null:
		ui.set_vr_note("This copy of the game has no VR support.")
		return false
	if not xr.is_initialized():
		if not _xr_mode_flag():
			# VR has to be switched on when the game starts, so restart the game in VR mode
			ui.set_vr_note("Restarting the game in VR mode…")
			var pid := OS.create_process(OS.get_executable_path(), ["--xr-mode", "on", "--", "--vr", "--xr"])
			Diag.write("Restarting in VR mode: new process id %d" % pid)
			await get_tree().create_timer(0.5).timeout
			get_tree().quit()
			return false
		var tried := xr.initialize()
		Diag.write("OpenXR manual initialize() returned: %s" % str(tried))
		Diag.snapshot()
		if not tried:
			Diag.write("OpenXR FAILED to start. Engine log tail follows.")
			Diag.write(Diag.engine_log_tail(60))
			ui.set_vr_note("The game restarted in VR mode but couldn't reach the headset. Press 'Copy diagnostics' below and paste the result to Claude. Also check: (1) Meta Quest Link app open on this laptop, (2) the headset shows the white Link room, (3) Link app > Settings > General > 'Set Meta Quest Link as active OpenXR runtime' is ON.")
			return false
		Diag.write("OpenXR started on the second try")
	get_viewport().use_xr = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	vr_active = true
	vr_frames = 0
	world.env.ssao_enabled = false
	xr_origin = XROrigin3D.new()
	xr_cam = XRCamera3D.new()
	xr_cam.near = 0.05
	xr_cam.far = 40000.0
	xr_origin.add_child(xr_cam)
	xr_left = XRController3D.new()
	xr_left.tracker = "left_hand"
	xr_right = XRController3D.new()
	xr_right.tracker = "right_hand"
	for c in [xr_left, xr_right]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.04, 0.04, 0.12)
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("#ff4c00")
		mi.material_override = m
		c.add_child(mi)
		xr_origin.add_child(c)
	vr_label = Label3D.new()
	vr_label.font = load("res://assets/fonts/Barlow-SemiBold.ttf")
	vr_label.font_size = 40
	vr_label.pixel_size = 0.0007
	vr_label.position = Vector3(0, -0.12, -0.7)
	vr_label.modulate = Color.WHITE
	vr_label.outline_size = 10
	vr_label.no_depth_test = true
	vr_label.render_priority = 10
	xr_cam.add_child(vr_label)
	if plane != null:
		plane.add_child(xr_origin)
	xr_cam.current = true
	_apply_view()
	ui.toast("VR started. Sit upright, then press B to recentre the view.", 5.0)
	return true


func _stop_vr() -> void:
	if not vr_active:
		return
	vr_active = false
	get_viewport().use_xr = false
	var xr := XRServer.find_interface("OpenXR")
	if xr != null and xr.is_initialized():
		xr.uninitialize()
	if xr_origin != null:
		xr_origin.queue_free()
		xr_origin = null
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	world.env.ssao_enabled = quality != "low"
	cam.current = true


func _read_vr() -> Dictionary:
	var out := {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "thr": 0.0, "brake": 0.0}
	if xr_right == null or not xr_right.get_is_active():
		return out
	var r := xr_right.get_vector2("primary")
	out["roll"] = _dz(r.x)
	out["pitch"] = -_dz(r.y)
	if _edge("vA", xr_right.is_button_pressed("ax_button")):
		flaps_idx = (flaps_idx + 1) % 3
		_toast("Flaps " + ["up", "half", "full"][flaps_idx])
	if _edge("vB", xr_right.is_button_pressed("by_button")):
		_recentre_vr()
	if xr_left != null and xr_left.get_is_active():
		var l := xr_left.get_vector2("primary")
		out["yaw"] = _dz(l.x)
		out["thr"] = _dz(l.y)
		out["brake"] = xr_left.get_float("trigger")
		if _edge("vX", xr_left.is_button_pressed("ax_button")):
			_pause(not paused)
		if _edge("vY", xr_left.is_button_pressed("by_button")):
			start_flight()
	return out


func _recentre_vr() -> void:
	if xr_origin == null or plane == null:
		return
	xr_origin.position = plane.eye - xr_cam.position
	_toast("View recentred")


func _vr_text(t: String) -> void:
	if vr_label != null:
		vr_label.text = t


# ------------------------------------------------------------ frame
func _toast(t: String, secs := 2.2) -> void:
	ui.toast(t, secs)
	if vr_active:
		_vr_text(t)
		get_tree().create_timer(secs).timeout.connect(func(): if not paused and state == "fly": _vr_text(""))


func _process(delta: float) -> void:
	if world == null or world.terrain == null or fm == null or plane == null:
		return
	frame_count += 1
	var dt := minf(delta, 0.05)
	run_time += dt
	if state == "fly" or state == "ended":
		if not paused:
			if state == "fly":
				_read_input(dt)
			else:
				inp["throttle"] = 0.0
				inp["brake"] = 1.0
			var prev := fm.pos
			fm.step(dt, inp)
			for ev in fm.consume_events():
				_handle_event(ev)
			if gate["active"] and not gate["done"] and state == "fly":
				gate["t"] += dt
				_check_gate(prev)
			tel.push(fm, inp, run_time, false)
	_place_plane(0.0 if paused else dt)
	_update_camera(dt)
	world.update_world(dt, cam.global_position if not vr_active else xr_cam.global_position)
	if state == "fly":
		_update_hud()
		instr_t += dt
		if instr_t > 0.05:
			instr_t = 0.0
			_update_instruments()
	if state == "menu":
		pass
	synth.set_state(fm.engine, fm.ias, fm.stall_warn and not bool(fm.i["on_ground"]), state == "fly" and not paused and bool(Settings.get_value("sound")))
	ui.tel_label.text = "Rig link: %s\npitch %.1f°  roll %.1f°  yaw rate %.1f°/s\nsurge %.2fg  sway %.2fg  heave %.2fg\nIAS %d kt  VS %d" % [tel.status, fm.i["pitch"], fm.i["roll"], -fm.w.y / FlightModel.D2R, -fm.spec_force.z / FlightModel.G, fm.spec_force.x / FlightModel.G, fm.spec_force.y / FlightModel.G, fm.i["ias"] * KT, fm.i["vs"] * FPM]
	ui.set_status.text = "Status: " + tel.status
	if shot_timer >= 0.0:
		shot_timer -= delta
		if shot_timer < 0.0:
			var img := get_viewport().get_texture().get_image()
			img.save_png(str(args["shot"]))
			print("saved screenshot ", args["shot"])
			get_tree().quit()


func _handle_event(ev: Dictionary) -> void:
	if ev["type"] == "touchdown":
		var fpm := int(float(ev["sink"]) * FPM)
		var r := "Smooth" if fpm < 120 else ("Good" if fpm < 300 else ("Firm" if fpm < 500 else "Hard"))
		_toast("Touchdown: %d ft/min (%s)" % [fpm, r], 3.5)
	elif ev["type"] == "crash":
		end_flight("Crashed", "Flight over", "%s. Take another go: be gentle with the controls, and keep your speed up on approach." % ev["reason"], "")


func _check_gate(prev: Vector3) -> void:
	var g: Dictionary = world.gates[gate["next"]]
	var nx: float = g["nx"]
	var nz: float = g["nz"]
	var d0: float = (prev.x - g["x"]) * nx + (prev.z - g["z"]) * nz
	var d1: float = (fm.pos.x - g["x"]) * nx + (fm.pos.z - g["z"]) * nz
	if d0 < 0.0 and d1 >= 0.0:
		var t: float = d0 / (d0 - d1)
		var p := prev.lerp(fm.pos, t)
		if Vector3(p.x - g["x"], p.y - g["y"], p.z - g["z"]).length() < float(g["r"]) * 0.96:
			gate["next"] += 1
			if gate["next"] >= world.gates.size():
				gate["done"] = true
				var best := Settings.best_time(str(Settings.get_value("aircraft")))
				var nb: bool = best <= 0.0 or gate["t"] < best
				if nb:
					Settings.set_best_time(str(Settings.get_value("aircraft")), gate["t"])
				world.set_gates(true, gate["next"])
				end_flight("Course complete", "Gate run", "New best time for this aircraft!" if nb else "Best: " + _fmt_time(best), _fmt_time(gate["t"]))
			else:
				world.set_gates(true, gate["next"])
				_toast("Gate %d  %s" % [gate["next"], _fmt_time(gate["t"])], 1.5)
		else:
			_toast("Missed the gate: turn back and fly through the ring", 2.5)


func _fmt_time(s: float) -> String:
	return "%d:%04.1f" % [int(s / 60.0), fmod(s, 60.0)]


func _update_hud() -> void:
	var i := fm.i
	ui.l_speed.text = str(int(round(float(i["ias"]) * KT)))
	ui.l_hdg.text = "%03d°" % (int(round(float(i["heading"]))) % 360)
	ui.l_alt.text = str(int(round(float(i["alt_msl"]) * FT)))
	ui.l_vs.text = "%d FT/MIN" % (int(round(float(i["vs"]) * FPM / 10.0)) * 10)
	ui.thr_bar.value = throttle
	ui.tag_flaps.text = "FLAPS %d%%" % int(round(float(i["flaps"]) * 100.0))
	ui.tag_brake.add_theme_color_override("font_color", Color("#ff4c00") if inp["brake"] > 0.1 else GameUI.MUTED)
	ui.adi.set_data({"pitch": i["pitch"], "roll": i["roll"], "ias": 0.0, "vmax": 200.0, "alt": 0.0, "vs": 0.0, "heading": 0.0, "throttle": 0.0, "rpm": 0.0, "rpm_max": 1.0, "flaps": 0.0, "stall": false})
	if gate["active"]:
		var g: Dictionary = world.gates[mini(gate["next"], world.gates.size() - 1)]
		ui.l_gate.text = "Finished" if gate["done"] else "Gate %d/%d" % [gate["next"] + 1, world.gates.size()]
		var dist := Vector2(g["x"] - fm.pos.x, g["z"] - fm.pos.z).length()
		ui.l_gate_t.text = _fmt_time(gate["t"]) + ("" if gate["done"] else "  ·  %d m" % int(dist))
		ui.arrow_angle = rad_to_deg(atan2(g["x"] - fm.pos.x, -(g["z"] - fm.pos.z))) - float(i["heading"])
		ui.arrow.queue_redraw()
	var m := ""
	var warn := false
	if fm.crashed:
		m = ""
	elif i["stall_warn"] and not i["on_ground"]:
		m = "STALL"
		warn = true
	elif not i["on_ground"] and i["alt_agl"] < 70.0 and i["vs"] < -7.0:
		m = "PULL UP"
		warn = true
	elif i["on_ground"] and i["ias"] > fm.spec["vr"] * 1.08 and i["ias"] < fm.spec["vr"] * 1.5 and fm.engine > 0.8:
		m = "ROTATE"
	ui.set_message(m, warn)
	if vr_active and m != "" and not paused:
		_vr_text(m)


func _update_instruments() -> void:
	var i := fm.i
	plane.set_instruments({
		"ias": float(i["ias"]) * KT, "vmax": 400.0 if fm.spec["key"] == "fighter" else 200.0, "alt": float(i["alt_msl"]) * FT, "vs": float(i["vs"]) * FPM,
		"heading": i["heading"], "pitch": i["pitch"], "roll": i["roll"], "throttle": throttle, "rpm": i["rpm"], "rpm_max": fm.spec["rpmMax"], "flaps": i["flaps"], "stall": i["stall"],
	})
	if plane.yoke != null:
		plane.yoke.rotation.z = -float(inp["roll"]) * 0.5
		plane.yoke.rotation.x = float(inp["pitch"]) * 0.18


# ------------------------------------------------------------ camera
func _update_camera(dt: float) -> void:
	var P := plane.position
	var Q := plane.quaternion
	var spec: Dictionary = fm.spec
	if vr_active:
		vr_frames += 1
		if vr_frames == 12:
			_recentre_vr()
		return
	cam.current = true
	cam.near = 0.1 if cam_mode == "cockpit" else 0.6
	if state == "menu":
		orbit_yaw += dt * 0.12
		var d := 19.0 if spec["key"] == "fighter" else 16.0
		var pos := Vector3(P.x + sin(orbit_yaw) * d, P.y + 4.5, P.z + cos(orbit_yaw) * d)
		var right := Vector3(cos(orbit_yaw), 0, -sin(orbit_yaw))
		var tgt := P + Vector3(0, 1.2, 0) - right * 4.5
		cam.global_transform = Transform3D(Basis.looking_at((tgt - pos).normalized(), Vector3.UP), pos)
		return
	if cam_mode == "cockpit":
		var e: Vector3 = Q * spec["eye"]
		var look_b := Basis.from_euler(Vector3(look.y, look.x, 0))
		cam.global_transform = Transform3D(Basis(Q) * look_b, P + e)
	elif cam_mode == "orbit":
		var dd := orbit_dist * (1.2 if spec["key"] == "fighter" else 1.0)
		var pos2 := Vector3(P.x + sin(orbit_yaw) * cos(orbit_pitch) * dd, P.y + sin(orbit_pitch) * dd, P.z + cos(orbit_yaw) * cos(orbit_pitch) * dd)
		cam.global_transform = Transform3D(Basis.looking_at((P - pos2).normalized(), Vector3.UP), pos2)
	else:
		if not cam_init:
			cam_q = Q
			cam_init = true
		cam_q = cam_q.slerp(Q, 1.0 - exp(-dt * 3.5))
		var back := Vector3(0, 3.2 if spec["key"] == "fighter" else 2.7, 14.0 if spec["key"] == "fighter" else 11.5)
		var pos3 := P + cam_q * back
		var up := Vector3.UP.lerp(cam_q * Vector3.UP, 0.3).normalized()
		var tgt2 := P + Q * Vector3(0, 0.9, -7.0)
		cam.global_transform = Transform3D(Basis.looking_at((tgt2 - pos3).normalized(), up), pos3)
	var gy := world.terrain.height(cam.global_position.x, cam.global_position.z) + 0.6
	if cam.global_position.y < gy:
		cam.global_position.y = gy
