extends Node
## SmartMotion Flight (native): game controller. Input, cameras, flight, gate run, VR (OpenXR) and the rig link.
## Three games share it: Flight (Duxford, this file), Racing (race_mode.gd) and Space (space_mode.gd).

const APP_VERSION := "1.13.0"
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
var mcomp := MotionComp.new()   # VR: cancels out the rig's movement (seat position from SmartMotion Motion)
var vr_base := Vector3.ZERO      # VR origin position set by recentring
var vr_pivot := Vector3(0, 0.6, 0)  # rig's centre of rotation in the headset's room space
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
var ultra := false

# VR
var vr_active := false
var xr_origin: XROrigin3D
var xr_cam: XRCamera3D
var xr_left: XRController3D
var xr_right: XRController3D
var vr_label: Label3D
var vr_frames := 0
var vr_edge := {}
var focus_hint_t := 0.0
var vr_menu: Node3D
var vr_menu_lines: Array = []
var vr_menu_title: Label3D
var vr_menu_idx := 0
var vr_warn := false
var hand_l: VRHand
var hand_r: VRHand
var hand_on := {"l": 0.0, "r": 0.0}     # 0 = following the controller, 1 = holding the throttle / stick
var vr_scale := 1.0                      # VR picture resolution (lowered automatically if the graphics card falls behind)
var gpu_acc := {"sum": 0.0, "n": 0, "t": 0.0, "calm": 0}

# games other than Flight (built the first time they're chosen)
var game := "flight"
var modes := {}
var mode: GameMode = null
var activating := false
var vr_panel: VRPanel
var space_thr := 0.5
var mkb := {"steer": 0.0}
var learning := ""
# what each simulator set-up's controls are, for "Set up controls": [action, name, what to do]
const RIG_ACTIONS := {
	"stick": [["roll", "Stick left / right", "Push the stick fully to the RIGHT"], ["pitch", "Stick forward / back", "Pull the stick fully BACK towards you"],
		["throttle", "Throttle lever", "Push the throttle fully FORWARD"], ["rudder", "Rudder pedals or stick twist (optional)", "Push the RIGHT pedal (or twist the stick RIGHT)"],
		["fire", "Fire button (Space game)", "Press the fire button"]],
	"wheel": [["steer", "Steering wheel", "Turn the wheel to the RIGHT (about a quarter turn)"], ["accel", "Accelerator pedal", "Press the accelerator all the way down"],
		["brake", "Brake pedal", "Press the brake all the way down"]],
}
const BIPOLAR := ["roll", "pitch", "rudder", "steer"]

# frame timing (diagnostics log): how smooth the game is running
var perf := {"n": 0, "sum": 0.0, "worst": 0.0, "late": 0, "last": 0, "t": 0.0, "fm": 0.0, "world": 0.0, "instr": 0.0, "fps": 0.0, "late_pc": 0.0, "gpu": 0.0}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	Diag.start(not args.has("xr"))
	Diag.write("SmartMotion Flight native v%s started" % APP_VERSION)
	for k in ["aircraft", "start", "mode", "tod", "wind", "game", "race"]:
		if args.has(k):
			Settings.data[k] = args[k]
	if args.has("assist"):
		Settings.data["assist"] = args["assist"] == "true" or args["assist"] == "1"
	if args.has("q"):
		Settings.data["quality"] = args["q"]
	if args.has("clouds"):
		Settings.data["clouds3d"] = args["clouds"] != "off" and args["clouds"] != "false"
	if args.has("view"):
		Settings.data["view"] = args["view"]
	# "ultra" is "high" plus extras (World.ultra, RealScenery.ultra): the rest of the code treats it as high
	ultra = str(Settings.get_value("quality")) == "ultra"
	quality = "high" if ultra else str(Settings.get_value("quality"))
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
	if args.has("test_panel"):
		await _test_panel()
		return
	ui.fly_pressed.connect(_on_fly)
	ui.resume_pressed.connect(func(): _pause(false))
	ui.restart_pressed.connect(start_game)
	ui.vr_action.connect(_on_vr_action)
	ui.learn_pressed.connect(_learn)
	_refresh_controls_sheet()
	ui.menu_pressed.connect(to_menu)
	ui.setting_changed.connect(_on_setting)
	ui.diag_pressed.connect(_copy_diag)
	var gpu := RenderingServer.get_video_adapter_name()
	ui.set_gpu_text("Graphics: %s  ·  %s  ·  F11 for full screen. If that isn't your NVIDIA/AMD card, set Windows Graphics Settings to High performance for this app." % [gpu, RenderingServer.get_current_rendering_method()])
	Diag.snapshot()
	_start_flypt()   # before the world loads, so Mover connects straight away
	world.ultra = ultra
	world.view = str(Settings.get_value("view"))
	world.clouds_on = bool(Settings.get_value("clouds3d"))
	await world.build(ui.set_progress, quality, str(Settings.get_value("tod")))
	for g in ["race", "coaster"]:
		await _build_mode(g)   # part of the same world: built now so you can fly over them
		(modes[g] as GameMode).showcase()
		(modes[g] as GameMode).visible = true
	if Settings.get_value("tel"):
		tel.start(str(Settings.get_value("tel_host")), int(Settings.get_value("tel_port")))
	mcomp.start()
	ui.vr_btn.visible = XRServer.find_interface("OpenXR") != null
	to_menu()
	if args.has("auto") or (args.has("vr") and args.has("go")):
		# straight into the game (test option, or the game restarted itself in VR from the menu)
		await get_tree().create_timer(0.3).timeout
		await _on_fly(args.has("vr"))
	else:
		# first screen: how is the simulator set up today?
		if args.has("vr"):
			await get_tree().create_timer(0.3).timeout
			await _start_vr()
		ui.show_lobby()
		Diag.write("set-up screen shown")
		if vr_active:
			_panel_show(true)
	if args.has("telemetry"):
		var hp: PackedStringArray = str(args["telemetry"]).split(":")
		Settings.data["tel"] = true
		tel.start(hp[0], int(hp[1]))
	if args.has("sheet"):
		await get_tree().create_timer(0.5).timeout
		ui.open_sheet({"settings": ui.settings_sheet, "help": ui.help_sheet, "pause": ui.pause_sheet}[str(args["sheet"])])
	if args.has("switch_test"):
		_switch_test()
	if args.has("orbit_dist"):
		orbit_dist = float(args["orbit_dist"])
	if args.has("orbit_yaw"):
		orbit_yaw = deg_to_rad(float(args["orbit_yaw"]))
	if args.has("orbit_pitch"):
		orbit_pitch = deg_to_rad(float(args["orbit_pitch"]))
	if args.has("cam"):
		cam_mode = args["cam"]
		_apply_view()
	if args.has("look"):   # test option: --look=yaw,pitch in degrees for the cockpit camera
		var lp: PackedStringArray = str(args["look"]).split(",")
		look = Vector2(deg_to_rad(float(lp[0])), deg_to_rad(float(lp[1])))
	if args.has("shot"):
		shot_timer = float(args.get("shot_after", "6"))
		Diag.write("screenshot in %.0f s" % shot_timer)


func _start_flypt() -> void:
	if Settings.get_value("flypt"):
		tel.xp.start(int(Settings.get_value("flypt_port")), "127.0.0.1", int(Settings.get_value("flypt_out")))
	else:
		tel.xp.stop()


func _apply_window() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if Settings.get_value("fullscreen") else DisplayServer.WINDOW_MODE_WINDOWED)


# ------------------------------------------------------------ settings and menu
func _on_setting(key: String, value) -> void:
	Settings.set_value(key, value)
	match key:
		"aircraft":
			if state == "menu" and game == "flight":
				showcase()
		"rig":
			ui.set_rig(str(value))
			_refresh_controls_sheet()
			var allowed: Array = GameUI.RIG_GAMES.get(str(value), GameUI.RIG_GAMES["all"])
			Diag.write("Simulator set up for: %s" % str(value))
			if not str(Settings.get_value("game")) in allowed:
				ui.set_seg("game", allowed[0])
				await _on_setting("game", allowed[0])
			if vr_active:
				_panel_show(true)
		"game":
			ui.set_game(str(value))
			if state == "menu":
				await showcase()
				if vr_active:
					_panel_show(true)
		"tod":
			world.set_time_of_day(str(value))
			if modes.has("race"):
				(modes["race"] as RaceMode).set_time_of_day(str(value))
		"fullscreen":
			_apply_window()
		"flypt", "flypt_port", "flypt_out":
			_start_flypt()
		"tel", "tel_host", "tel_port":
			if Settings.get_value("tel"):
				tel.start(str(Settings.get_value("tel_host")), int(Settings.get_value("tel_port")))
			else:
				tel.stop()
		"quality", "view":
			ui.toast("This changes next time you start the game", 3.0)
		"clouds3d":
			world.set_clouds(bool(value))


func _on_fly(vr: bool) -> void:
	Diag.write("CLICK: %s" % ("Fly in VR" if vr else "Fly"))
	if vr and not vr_active and not await _start_vr():
		Diag.write("VR did not start")
		return
	start_game()


func start_game() -> void:
	if str(Settings.get_value("game")) == "flight":
		start_flight()
	else:
		await start_mode()


func _on_vr_action(what: String) -> void:
	Diag.write("CLICK: VR %s" % what)
	match what:
		"recentre":
			_recentre_vr()
		"hz":
			var rates := _vr_rates()
			if rates.size() > 1:
				var cur := _vr_hz()
				var nxt: float = rates[0]
				for r in rates:
					if float(r) > cur + 1.0:
						nxt = float(r)
						break
				_on_setting("vr_hz", nxt)
				_apply_vr_hz()
			ui.set_vr(vr_active, _vr_hz_label())
		"exit":
			_stop_vr()
			to_menu()


func _copy_diag() -> void:
	Diag.write("CLICK: Copy diagnostics")
	Diag.snapshot()
	DisplayServer.clipboard_set(Diag.full_text())
	ui.set_vr_note("Diagnostics copied. Paste them into the chat (Ctrl+V). They are also saved in: " + Diag.log_path())


func _xr_mode_flag() -> bool:
	# true when this run was started in VR mode (by the VR .bat file or by the game's own restart);
	# the marker stops the game from restarting itself more than once
	return args.has("xr")


## Switches the scene to a game: "flight" shows the Duxford world; "race" and "space" build their own world
## the first time (a few seconds) and hide Duxford while they run.
func _activate(g: String) -> void:
	while activating:
		await get_tree().process_frame   # already being built (e.g. chosen and started at once)
	if g != "flight" and not modes.has(g):
		await _build_mode(g)
	game = g
	if mode != null:
		mode.visible = false
		if mode.running:
			mode.showcase()   # park it (cars on the grid, the train in the station)
		mode.running = false
	if g == "flight":
		mode = null
		world.visible = true
		cam.environment = null
		cam.far = 40000.0
		synth.set_profile("plane")
	else:
		mode = modes[g]
		mode.visible = true
		world.visible = mode.uses_world()
		cam.environment = null if mode.uses_world() else mode.env
		cam.far = mode.camera_far()
		synth.set_profile({"race": "race", "space": "space"}.get(g, "ride"))
		mode.set_vr(vr_active)
	# the circuit and the coaster are part of the Duxford world: they stay there (parked) in the other games
	for k in modes:
		var om: GameMode = modes[k]
		if om != mode:
			om.visible = om.uses_world() and world.visible
	if xr_cam != null:
		xr_cam.environment = cam.environment
		xr_cam.far = cam.far
	_attach_rig()


## Builds a game's world (once). Racing and the coaster are built while the game loads, so they are in the
## Duxford world from the start (you can fly over them).
func _build_mode(g: String) -> void:
	if modes.has(g) or activating:
		return
	activating = true
	Diag.write("Building the %s game" % g)
	var was_menu := ui.menu.visible
	ui.show_loading()
	ui.set_progress(0.4, {"race": "Building the racing circuit", "space": "Building the space station and asteroid field", "coaster": "Building the roller coaster"}.get(g, "Building"))
	await get_tree().process_frame
	await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	var m: GameMode
	match g:
		"race":
			m = RaceMode.new()
		"space":
			m = SpaceMode.new()
		_:
			m = CoasterMode.new()
	m.visible = false
	add_child(m)
	await m.build(world, quality)
	Diag.write("%s built in %.1f s" % [g, (Time.get_ticks_msec() - t0) / 1000.0])
	m.finished.connect(end_flight)
	m.toast.connect(func(t: String, secs: float): _toast(t, secs))
	if m is SpaceMode:
		(m as SpaceMode).sfx.connect(synth.blip)
	modes[g] = m
	activating = false
	ui.loading.visible = false
	if was_menu or state == "menu":
		ui.show_menu()


## In VR the headset's origin rides in the vehicle (aircraft, car or ship).
func _attach_rig() -> void:
	if not vr_active or xr_origin == null:
		return
	var p: Node3D = mode.vehicle if mode != null else plane
	if p == null:
		return
	if xr_origin.get_parent() != p:
		if xr_origin.get_parent() != null:
			xr_origin.get_parent().remove_child(xr_origin)
		p.add_child(xr_origin)
		vr_frames = 0   # recentres in the new seat a few frames later


func _eye() -> Vector3:
	if mode != null:
		return mode.eye
	return plane.eye if plane != null else Vector3.ZERO


func start_mode() -> void:
	var g := str(Settings.get_value("game"))
	if mode == null or game != g:
		await _activate(g)
	if mode == null:
		return
	cam_mode = mode.camera_modes()[0]   # chase view (racing, space); the rider's view on the coaster
	if args.has("cam") and str(args["cam"]) in mode.camera_modes():
		cam_mode = str(args["cam"])   # test option (screenshots from the seat)
	cam_init = false
	space_thr = 0.5
	mkb = {"steer": 0.0}
	mode.set_cockpit(cam_mode == "cockpit" or vr_active)
	mode.start()
	state = "fly"
	paused = false
	_vr_menu_show(false, "")
	_vr_text("")
	ui.show_hud()
	ui.show_pause(false)
	ui.adi.visible = false
	ui.set_corner_boxes(true)
	ui.set_hud_kind(g)
	ui.set_message("", false)
	Diag.write("started %s" % g)


func showcase() -> void:
	state = "menu"
	paused = false
	var g := str(Settings.get_value("game"))
	if g != "flight":
		await _activate(g)
		if mode != null:
			mode.showcase()
			mode.set_cockpit(vr_active)
		return
	_activate("flight")
	world.wind = Vector3.ZERO
	fm = FlightModel.new(str(Settings.get_value("aircraft")), world.terrain)
	var xz := world.terrain.from_runway(-Terrain.RW_LEN / 2.0 + 70.0, 0.0)
	fm.reset({"x": xz.x, "z": xz.y, "heading": Terrain.RW_HEADING_DEG})
	_mount_plane()
	cam_mode = "chase"
	_apply_view()
	world.set_gates(false, 0)
	_place_plane(0.0)


func to_menu() -> void:
	ui.hide_sheets()
	ui.show_menu()
	ui.show_pause(false)
	ui.set_game(str(Settings.get_value("game")))
	await showcase()
	if vr_active:
		_panel_show(true)   # in VR the menu floats in front of you; you stay in the headset


func _mount_plane() -> void:
	if plane != null:
		plane.queue_free()
	plane = AircraftModel.new()
	var key := str(Settings.get_value("aircraft"))
	plane.build(key, world.logo if key == "trainer" else world.logo_dark)
	add_child(plane)
	_attach_rig()


func _apply_view() -> void:
	var cp := cam_mode == "cockpit" or vr_active
	if mode != null:
		mode.set_cockpit(cp)
		return
	if plane != null:
		plane.set_cockpit_view(cp)
	if ui != null and ui.adi != null:
		ui.adi.visible = not cp
		ui.set_corner_boxes(not (cp and plane != null and plane.bulldog != null))


func _place_plane(dt: float) -> void:
	plane.ctl = {"pitch": inp["pitch"], "roll": inp["roll"], "yaw": inp["yaw"], "throttle": throttle, "flaps": flaps_idx / 2.0, "flaps_pos": fm.flaps, "trim": trim}
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
	if args.has("at"):
		# test option --at=x,z,heading,height: start in the air there (screenshots of the world)
		var a: PackedStringArray = str(args["at"]).split(",")
		return {"x": float(a[0]), "z": float(a[1]), "heading": float(a[2]), "airborne": true, "agl": float(a[3]), "speed": spec["cruise"], "throttle": spec["cruiseThrottle"]}
	if Settings.get_value("start") == "air":
		var xz2 := world.terrain.from_runway(-1300.0, 0.0)
		return {"x": xz2.x, "z": xz2.y, "heading": Terrain.RW_HEADING_DEG, "airborne": true, "agl": 380.0, "speed": spec["cruise"], "throttle": spec["cruiseThrottle"]}
	var xz3 := world.terrain.from_runway(-Terrain.RW_LEN / 2.0 + 70.0, 0.0)
	return {"x": xz3.x, "z": xz3.y, "heading": Terrain.RW_HEADING_DEG}


func start_flight() -> void:
	_activate("flight")
	ui.set_hud_kind("flight")
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
	if fm.assist and fm.i["on_ground"]:
		throttle = 1.0   # Easy mode: full power is set for you, so the aircraft speeds up straight away
	flaps_idx = 0
	trim = 0.0
	kb = {"pitch": 0.0, "roll": 0.0, "yaw": 0.0}
	gate = {"next": 0, "t": 0.0, "done": false, "active": Settings.get_value("mode") == "gates"}
	world.set_gates(gate["active"], 0)
	ui.gate_box.visible = gate["active"]
	ui.tag_assist.text = "EASY" if fm.assist else "PRO"
	state = "fly"
	paused = false
	_vr_menu_show(false, "")
	ui.show_hud()
	ui.show_pause(false)
	ui.adi.visible = cam_mode != "cockpit" and not vr_active
	ui.set_message("", false)
	if fm.i["on_ground"] and fm.assist:
		_toast("Full power is on. At %d knots hold S to lift off. W/S nose, A/D turn, Shift/Ctrl power" % int(fm.spec["vr"] * 1.12 * KT), 6.0)
	elif fm.i["on_ground"]:
		_toast("Hold Shift for full power, then hold S at about %d knots" % int(fm.spec["vr"] * 1.12 * KT), 5.0)
	elif gate["active"]:
		_toast("Fly through the orange gates as fast as you can", 4.0)


func end_flight(title: String, label: String, text: String, big: String) -> void:
	state = "ended"
	await get_tree().create_timer(0.9).timeout
	if state == "ended":
		ui.show_end(title, label, text, big)
		if vr_active:
			_vr_text("")
			_vr_menu_show(true, title)


# ------------------------------------------------------------ input
func _k(code: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(code) else 0.0


static func _dz(v: float) -> float:
	return 0.0 if absf(v) < 0.12 else (v - signf(v) * 0.12) / 0.88


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		match e.physical_keycode:
			KEY_F:
				if mode != null:
					return
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
					start_game()
			KEY_T:
				ui.tel_panel.visible = not ui.tel_panel.visible
				if ui.tel_panel.visible:
					_toast("Data panel ON (top right)\nFlyPT Mover: " + tel.xp.status, 4.0)
				else:
					_toast("Data panel OFF (press T to show it)", 2.0)
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
	cam_mode = {"chase": "cockpit", "cockpit": "orbit", "orbit": "chase"}.get(cam_mode, "chase")
	_apply_view()
	cam_init = false
	_toast({"chase": "Chase view", "cockpit": "Cockpit view", "orbit": "Orbit view (right mouse + drag)"}[cam_mode])


func _pause(on: bool) -> void:
	if state != "fly":
		return
	paused = on
	ui.show_pause(on)
	if vr_active:
		_vr_text("")
		_vr_menu_show(on, "Paused")


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
	if pads.size() > 0 and not _has_map():
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
	throttle = clampf(throttle + thr_axis * 0.9 * dt, 0.0, 1.0)   # 0 to full power in about a second
	# the simulator's own joystick, throttle and pedals (Set up controls)
	var mr := _mapped("roll")
	var mp := _mapped("pitch")
	var my := _mapped("rudder")
	var mt := _mapped("throttle")
	if not is_nan(mr):
		inp["roll"] = clampf(inp["roll"] + mr, -1.0, 1.0)
	if not is_nan(mp):
		inp["pitch"] = clampf(inp["pitch"] + mp * inv, -1.0, 1.0)
	if not is_nan(my):
		inp["yaw"] = clampf(inp["yaw"] + my, -1.0, 1.0)
	if not is_nan(mt) and thr_axis == 0.0:
		throttle = mt
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
			var pid := OS.create_process(OS.get_executable_path(), ["--xr-mode", "on", "--", "--vr", "--xr", "--go"])
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
	get_viewport().use_taa = false            # TAA smears when you turn your head; MSAA keeps VR sharp
	# 2x MSAA: 4x on two eyes at headset resolution cost too much time per frame (judder when looking around)
	get_viewport().msaa_3d = Viewport.MSAA_2X
	# v1.6.3 also turned on foveated rendering, depth submission and a 72 Hz request here: VR then stuck on
	# Quest Link's loading hourglass on Sam's PC, so those are out. The refresh rate is only changed from the VR menu.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)   # the headset sets the pace, not the laptop screen
	Diag.write("VR refresh rates offered: %s; current %.0f Hz" % [str(_vr_rates()), _vr_hz()])
	vr_active = true
	vr_frames = 0
	world.env.ssao_enabled = false
	world.env.ssil_enabled = false
	world.set_vr_mode(true)
	xr_origin = XROrigin3D.new()
	vr_base = Vector3.ZERO
	xr_cam = XRCamera3D.new()
	xr_cam.near = 0.05
	xr_cam.far = 40000.0
	xr_origin.add_child(xr_cam)
	xr_left = XRController3D.new()
	xr_left.tracker = "left_hand"
	xr_right = XRController3D.new()
	xr_right.tracker = "right_hand"
	for c in [xr_left, xr_right]:
		xr_origin.add_child(c)
	# gloved hands instead of the controllers (placed every frame in _update_hands)
	hand_l = VRHand.new(true)
	hand_r = VRHand.new(false)
	xr_origin.add_child(hand_l)
	xr_origin.add_child(hand_r)
	hand_on = {"l": 0.0, "r": 0.0}
	vr_scale = 1.0
	get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	get_viewport().scaling_3d_scale = 1.0
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
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
	vr_panel = VRPanel.new()
	xr_origin.add_child(vr_panel)
	vr_panel.setup(ui, self, xr_origin)
	ui.set_vr(true, _vr_hz_label())
	xr_cam.environment = cam.environment
	xr_cam.far = cam.far
	_attach_rig()
	if mode != null:
		mode.set_vr(true)
	xr_cam.current = true
	_apply_view()
	DisplayServer.window_move_to_foreground()
	Diag.write("VR started; window focused for the keyboard: %s" % str(DisplayServer.window_is_focused()))
	ui.toast("VR started. Sit upright, then press B (or V) to recentre the view.", 5.0)
	return true


func _stop_vr() -> void:
	if not vr_active:
		return
	vr_active = false
	get_viewport().use_xr = false
	get_viewport().use_taa = true
	get_viewport().msaa_3d = {"low": Viewport.MSAA_DISABLED, "medium": Viewport.MSAA_2X, "high": Viewport.MSAA_4X}.get(quality, Viewport.MSAA_2X)
	var xr := XRServer.find_interface("OpenXR")
	if xr != null and xr.is_initialized():
		xr.uninitialize()
	if vr_panel != null:
		vr_panel.teardown()
		vr_panel = null
	ui.set_vr(false)
	if mode != null:
		mode.set_vr(false)
		mode.set_cockpit(cam_mode == "cockpit")
	if xr_origin != null:
		xr_origin.queue_free()
		xr_origin = null
	hand_l = null
	hand_r = null
	get_viewport().scaling_3d_scale = 1.0
	vr_menu = null
	vr_menu_lines = []
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	world.env.ssao_enabled = quality != "low"
	world.env.ssil_enabled = quality == "high"
	world.set_vr_mode(false)
	cam.current = true


func _read_vr() -> Dictionary:
	var out := {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "thr": 0.0, "brake": 0.0}
	if xr_right == null or not xr_right.get_is_active():
		return out
	var r := xr_right.get_vector2("primary")
	out["roll"] = _dz(r.x)
	out["pitch"] = -_dz(r.y)
	out["thr"] = xr_right.get_float("trigger") - xr_right.get_float("grip")   # right trigger more power, right grip less
	if _edge("vA", xr_right.is_button_pressed("ax_button")):
		flaps_idx = (flaps_idx + 1) % 3
		_toast("Flaps " + ["up", "half", "full"][flaps_idx])
	if _edge("vB", xr_right.is_button_pressed("by_button")):
		_recentre_vr()
	if xr_left != null and xr_left.get_is_active():
		var l := xr_left.get_vector2("primary")
		out["yaw"] = _dz(l.x)
		out["thr"] += _dz(l.y)
		out["brake"] = xr_left.get_float("trigger")
		if _edge("vX", xr_left.is_button_pressed("ax_button")):
			_pause(not paused)
		if _edge("vY", xr_left.is_button_pressed("by_button")):
			start_flight()
	return out


func _recentre_vr() -> void:
	if xr_origin == null or (plane == null and mode == null):
		return
	# work in the seat's middle position, so recentring while the rig is tilted still lines up
	var head := mcomp.correction(vr_pivot) * xr_cam.position
	vr_pivot = head + Vector3(0, -MotionComp.PIVOT_BELOW_EYE, 0)
	vr_base = _eye() - head
	xr_origin.transform = Transform3D(Basis(), vr_base) * mcomp.correction(vr_pivot)
	_toast("View recentred")


# ------------------------------------------------------------ VR menu (the real menus on a panel in the headset)
func _vr_hz_label() -> String:
	var t := "Headset:  %d Hz" % roundi(_vr_hz())
	if _vr_rates().size() < 2:
		t = "Headset:  %d Hz (set in the Quest Link app)" % roundi(_vr_hz())
	if perf["fps"] > 1.0:
		var ok: bool = perf["fps"] > _vr_hz() * 0.95 and perf["late_pc"] < 2.0
		t += "  ·  %d fps %s" % [roundi(perf["fps"]), "smooth" if ok else "(too slow: try 72 Hz)"]
	return t


func _vr_menu_show(on: bool, _title: String) -> void:
	_panel_show(on)


func _panel_show(on: bool) -> void:
	if not vr_active or vr_panel == null or xr_cam == null:
		return
	if on:
		ui.set_vr(true, _vr_hz_label())
	vr_panel.show_panel(on, xr_cam.transform)
	for k in ["mx", "my"]:
		vr_edge[k] = true   # a button must be released and pressed again


## While the panel is up: point and click, plus X to carry on and Y to restart.
func _vr_panel_tick(dt: float) -> void:
	if not vr_active or vr_panel == null or not vr_panel.shown:
		return
	vr_panel.update({"l": xr_left, "r": xr_right}, dt)
	if xr_left != null and xr_left.get_is_active():
		if _edge("mx", xr_left.is_button_pressed("ax_button")):
			if state == "fly" and paused:
				_pause(false)
			elif state == "ended":
				start_game()
		if _edge("my", xr_left.is_button_pressed("by_button")) and state != "menu":
			start_game()


func _input(e: InputEvent) -> void:
	# while VR is on the menus live on the headset panel: the laptop's mouse and arrow keys still work them
	if vr_active and vr_panel != null and vr_panel.shown:
		if e is InputEventMouse and vr_panel.desktop_mouse(e, get_viewport().get_visible_rect().size):
			get_viewport().set_input_as_handled()
		elif e is InputEventKey and e.pressed and not e.echo:
			var act: String = {KEY_UP: "ui_up", KEY_DOWN: "ui_down", KEY_ENTER: "ui_accept", KEY_KP_ENTER: "ui_accept"}.get(e.physical_keycode, "")
			if act != "":
				vr_panel._push_action(act)
				get_viewport().set_input_as_handled()


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
	tel.service()
	if args.has("switch_test") and Engine.get_process_frames() % 10 == 0:
		Diag.write("frame %d, %.0f ms, state %s, game %s, mode %s | process %.0f ms, physics %.0f ms, draw calls %d, objects %d, nodes %d, prims %d" % [Engine.get_process_frames(), delta * 1000.0, state, game, str(mode),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.OBJECT_COUNT),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	if tel.xp.event != "":
		_toast(tel.xp.event, 5.0)
		tel.xp.event = ""
	if world == null or world.terrain == null:
		return
	if mode != null:
		frame_count += 1
		_perf_frame()
		_process_mode(minf(delta, 0.05), delta)
		_shot_tick(delta)
		return
	if fm == null or plane == null:
		return
	frame_count += 1
	_perf_frame()
	var dt := minf(delta, 0.05)
	run_time += dt
	_vr_panel_tick(dt)
	_controls_tick()
	if state == "fly" or state == "ended":
		if not paused:
			if state == "fly":
				_read_input(dt)
			else:
				inp["throttle"] = 0.0
				inp["brake"] = 1.0
			var prev := fm.pos
			var t0 := Time.get_ticks_usec()
			fm.step(dt, inp)
			perf["fm"] += Time.get_ticks_usec() - t0
			for ev in fm.consume_events():
				_handle_event(ev)
			if gate["active"] and not gate["done"] and state == "fly":
				gate["t"] += dt
				_check_gate(prev)
			tel.push(fm, inp, run_time, false)
	_place_plane(0.0 if paused else dt)
	world.focus = Vector2(fm.pos.x, fm.pos.z)
	world.focus_agl = float(fm.i["alt_agl"])
	_update_camera(dt)
	if vr_active and xr_origin != null:
		# The headset places your head from XRServer.world_origin. Godot copies it from the XROrigin3D *before*
		# this script moves the aircraft, so it was always one frame behind: at 55 m/s that is ~0.75 m, and the
		# cockpit wobbled around your head whenever speed or attitude changed. Set it now, after the move.
		mcomp.poll()
		xr_origin.transform = Transform3D(Basis(), vr_base) * mcomp.correction(vr_pivot)
		XRServer.world_origin = xr_origin.global_transform
		_update_hands(dt)
		_vr_auto_resolution(delta)
	elif args.has("hands") and plane.bulldog != null:
		# test option: show the VR hands on the stick and throttle in the screen view (for screenshots)
		if hand_r == null or not is_instance_valid(hand_r):
			hand_r = VRHand.new(false)
			hand_l = VRHand.new(true)
			plane.add_child(hand_r)
			plane.add_child(hand_l)
		hand_r.place(plane.bulldog.stick_grip())
		hand_l.place(plane.bulldog.throttle_grip())
		hand_r.set_curl(1.0)
		hand_l.set_curl(1.0)
	var t1 := Time.get_ticks_usec()
	world.update_world(dt, cam.global_position if not vr_active else xr_cam.global_position)
	perf["world"] += Time.get_ticks_usec() - t1
	if vr_active and state == "fly":
		focus_hint_t -= dt
		if focus_hint_t <= 0.0 and not DisplayServer.window_is_focused():
			focus_hint_t = 12.0
			_toast("Keyboard not connected: click the game window on the laptop once", 4.0)
	if state == "fly":
		_update_hud()
		instr_t += dt
		if instr_t > (0.015 if plane.bulldog != null else 0.05):   # the Bulldog's 3D panel updates every frame (smooth needles in VR)
			instr_t = 0.0
			var t2 := Time.get_ticks_usec()
			_update_instruments()
			perf["instr"] += Time.get_ticks_usec() - t2
	if state == "menu":
		pass
	synth.set_state(fm.engine, fm.ias, fm.stall_warn and not bool(fm.i["on_ground"]), state == "fly" and not paused and bool(Settings.get_value("sound")))
	ui.tel_label.text = "Rig link: %s\nFlyPT Mover: %s\npitch %.1f°  roll %.1f°  yaw rate %.1f°/s\nsurge %.2fg  sway %.2fg  heave %.2fg\nIAS %d kt  VS %d" % [tel.status, tel.xp.status, fm.i["pitch"], fm.i["roll"], -fm.w.y / FlightModel.D2R, -fm.spec_force.z / FlightModel.G, fm.spec_force.x / FlightModel.G, fm.spec_force.y / FlightModel.G, fm.i["ias"] * KT, fm.i["vs"] * FPM]
	ui.set_status.text = "Status: " + tel.status + "\nFlyPT Mover: " + tel.xp.status
	if frame_count % 120 == 30 and (args.has("stats") or shot_timer >= 0.0):
		Diag.write("frame stats: %d triangles, %d draw calls, %d objects, %.1f fps" % [
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME), Engine.get_frames_per_second()])
	_shot_tick(delta)


var shot_still := -1
func _shot_tick(delta: float) -> void:
	if shot_still > 0:
		shot_still -= 1   # time stopped: a few still frames so the smoothing (TAA) settles before the picture
		if shot_still == 0:
			_save_shot()
		return
	if shot_timer >= 0.0:
		shot_timer -= delta
		if shot_timer < 0.0:
			Engine.time_scale = 0.0
			shot_still = 30


func _save_shot() -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(str(args["shot"]))
	print("saved screenshot ", args["shot"])
	get_tree().quit()


## Frame timing for the diagnostics log: every 5 s (2 s with --stats) while flying, the average and slowest
## frame and how many frames missed the deadline (in VR the headset's refresh, e.g. 11.1 ms at 90 Hz).
func _perf_frame() -> void:
	var now := Time.get_ticks_usec()
	if perf["last"] > 0:
		var ms: float = (now - int(perf["last"])) / 1000.0
		perf["n"] += 1
		perf["sum"] += ms
		perf["worst"] = maxf(perf["worst"], ms)
		if ms > _frame_budget_ms() * 1.5:
			perf["late"] += 1
		perf["t"] += ms / 1000.0
	perf["last"] = now
	if perf["t"] >= (2.0 if args.has("stats") else 5.0):
		var n: float = maxf(perf["n"], 1.0)
		perf["fps"] = 1000.0 / (perf["sum"] / n)
		perf["late_pc"] = 100.0 * perf["late"] / n
		if state == "fly" and (vr_active or args.has("stats")):
			Diag.write("timing%s: %.0f fps, avg %.1f ms, slowest %.1f ms, %d of %d frames late (over %.1f ms) | graphics card %.1f ms, resolution %d%% | flight %.2f ms, world %.2f ms, panel %.2f ms, panel draw %.2f ms x%d" % [
				" (VR %d Hz)" % roundi(_vr_hz()) if vr_active else "", 1000.0 / (perf["sum"] / n), perf["sum"] / n, perf["worst"],
				perf["late"], perf["n"], _frame_budget_ms() * 1.5, perf["gpu"], roundi(vr_scale * 100.0), perf["fm"] / n / 1000.0, perf["world"] / n / 1000.0, perf["instr"] / n / 1000.0, BulldogPanel.draw_us / n / 1000.0, BulldogPanel.draw_n])
			BulldogPanel.draw_us = 0
			BulldogPanel.draw_n = 0
		if vr_panel != null and vr_panel.shown:
			ui.set_vr(true, _vr_hz_label())   # keep the smoothness readout up to date
		for k in ["n", "sum", "worst", "late", "t", "fm", "world", "instr"]:
			perf[k] = 0 if k in ["n", "late"] else 0.0


## Gloved hands: follow the controllers; near the stick (right) or throttle (left) they close around it and
## move with it, so you see your hand flying the aircraft.
func _update_hands(dt: float) -> void:
	var bd: Bulldog = plane.bulldog if plane != null and mode == null else null
	for side in ["l", "r"]:
		var h: VRHand = hand_l if side == "l" else hand_r
		var c: XRController3D = xr_left if side == "l" else xr_right
		if h == null:
			continue
		var tracked := c != null and c.get_is_active() and c.get_has_tracking_data()
		h.visible = tracked
		if not tracked:
			continue
		var free := c.global_transform
		var grip := Transform3D()
		var reach := 0.0
		if mode != null:
			var gr: Array = mode.grip(side)
			grip = gr[0]
			reach = gr[1]
		elif bd != null:
			grip = bd.stick_grip() if side == "r" else bd.throttle_grip()
			reach = 0.2 if side == "r" else 0.13
		var near := reach > 0.0 and free.origin.distance_to(grip.origin) < reach
		hand_on[side] = move_toward(float(hand_on[side]), 1.0 if near else 0.0, dt * 6.0)
		var k: float = hand_on[side]
		var t := free
		if k > 0.0:
			t = free.interpolate_with(grip, k * k * (3.0 - 2.0 * k))
		h.place(t)
		var press := maxf(c.get_float("grip"), c.get_float("trigger"))
		h.set_curl(lerpf(0.3 + 0.7 * press, 1.0, k))


## Keeps VR smooth on any graphics card: if a frame takes the graphics card more than 85% of the time the
## headset allows, the 3D picture is drawn at a slightly lower resolution (down to 70%); when there is
## plenty of time again it goes back up. Checked twice a second.
func _vr_auto_resolution(delta: float) -> void:
	var rid := get_viewport().get_viewport_rid()
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(rid)
	if gpu <= 0.0:
		return
	gpu_acc["sum"] += gpu
	gpu_acc["n"] += 1
	gpu_acc["t"] += delta
	if gpu_acc["t"] < 0.5:
		return
	var avg: float = gpu_acc["sum"] / maxf(gpu_acc["n"], 1.0)
	perf["gpu"] = avg
	var budget := 1000.0 / _vr_hz()
	var was := vr_scale
	if avg > budget * 0.85 and vr_scale > 0.7:
		vr_scale = maxf(0.7, vr_scale - 0.05)
		gpu_acc["calm"] = 0
	elif avg < budget * 0.65 and vr_scale < 1.0:
		gpu_acc["calm"] += 1
		if gpu_acc["calm"] >= 4:
			vr_scale = minf(1.0, vr_scale + 0.05)
			gpu_acc["calm"] = 0
	else:
		gpu_acc["calm"] = 0
	if vr_scale != was:
		get_viewport().scaling_3d_scale = vr_scale
		Diag.write("VR resolution %d%% (graphics card %.1f ms of %.1f ms)" % [roundi(vr_scale * 100.0), avg, budget])
	gpu_acc["sum"] = 0.0
	gpu_acc["n"] = 0
	gpu_acc["t"] = 0.0


func _vr_rates() -> Array:
	var xr := XRServer.find_interface("OpenXR")
	if xr == null or not xr.is_initialized() or not xr.has_method("get_available_display_refresh_rates"):
		return []
	var out: Array = []
	for r in xr.get_available_display_refresh_rates():
		out.append(float(r))
	out.sort()
	return out


## Asks the headset for the refresh rate picked in the VR menu (only when picked there; otherwise the rate
## set in the Quest Link app is used). The game must finish each frame within 1/rate of a second, or you feel a judder.
func _apply_vr_hz() -> void:
	var rates := _vr_rates()
	var want := float(Settings.get_value("vr_hz"))
	var xr := XRServer.find_interface("OpenXR")
	Diag.write("VR refresh rates offered: %s; current %.0f Hz; wanted %.0f Hz" % [str(rates), _vr_hz(), want])
	for r in rates:
		if absf(float(r) - want) < 1.0:
			xr.set("display_refresh_rate", float(r))
			Diag.write("VR refresh rate set to %.0f Hz" % float(r))
			return


func _vr_hz() -> float:
	var xr := XRServer.find_interface("OpenXR")
	if xr != null and xr.is_initialized() and xr.has_method("get_display_refresh_rate"):
		var hz: float = xr.get_display_refresh_rate()
		if hz > 1.0:
			return hz
	return 90.0


func _frame_budget_ms() -> float:
	return 1000.0 / (_vr_hz() if vr_active else 60.0)


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
	if vr_active and not paused:
		if m != "":
			_vr_text(m)
			vr_warn = true
		elif vr_warn:
			_vr_text("")   # clear STALL / PULL UP once it's over
			vr_warn = false


func _update_instruments() -> void:
	var i := fm.i
	plane.set_instruments({
		"ias": float(i["ias"]) * KT, "vmax": 400.0 if fm.spec["key"] == "fighter" else 200.0, "alt": float(i["alt_msl"]) * FT, "vs": float(i["vs"]) * FPM,
		"heading": i["heading"], "pitch": i["pitch"], "roll": i["roll"], "throttle": throttle, "rpm": i["rpm"], "rpm_max": fm.spec["rpmMax"], "flaps": i["flaps"], "stall": i["stall"],
		"g": i["g"], "slip": i["slip"], "turn": -fm.w.y / FlightModel.D2R, "mover": tel.xp.light(),
	})
	if plane.yoke != null and plane.bulldog == null:
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
		var base_pitch := -0.2 if plane.bulldog != null else 0.0   # Bulldog: look slightly down so the panel shows on a monitor
		var look_b := Basis.from_euler(Vector3(look.y + base_pitch, look.x, 0))
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


# ------------------------------------------------------------ Racing and Space
func _process_mode(dt: float, delta: float) -> void:
	run_time += dt
	_vr_panel_tick(dt)
	if state == "menu":
		mode.idle(dt)
		orbit_yaw += dt * 0.15
	_controls_tick()
	if (state == "fly" or state == "ended") and not paused:
		var mi := _read_mode_input(dt) if state == "fly" else {"steer": 0.0, "throttle": 0.0, "brake": 0.6, "pitch": 0.0, "roll": 0.0, "yaw": 0.0, "fire": false, "boost": false}
		var t0 := Time.get_ticks_usec()
		mode.step(dt, mi)
		perf["fm"] += Time.get_ticks_usec() - t0
		tel.push_frame(mode.tel_frame, run_time)
	if state == "fly":
		mode.hud(ui)
		if vr_active and not paused:
			var m: String = ui.msg_label.text if ui.msg_label.visible else ""
			if m != "":
				_vr_text(m)
				vr_warn = true
			elif vr_warn:
				_vr_text("")
				vr_warn = false
	if vr_active and xr_origin != null:
		vr_frames += 1
		if vr_frames == 12:
			_recentre_vr()
		mcomp.poll()
		xr_origin.transform = Transform3D(Basis(), vr_base) * mcomp.correction(vr_pivot)
		XRServer.world_origin = xr_origin.global_transform   # same frame as the vehicle moved (no lag)
		_update_hands(dt)
		_vr_auto_resolution(delta)
		mode.follow_camera(xr_cam.global_position)
	else:
		cam.current = true
		mode.place_camera(cam, cam_mode, dt, {"yaw": orbit_yaw, "pitch": orbit_pitch, "dist": orbit_dist, "look": look})
	if mode.uses_world():
		var cp := xr_cam.global_position if vr_active and xr_cam != null else cam.global_position
		world.focus = Vector2(cp.x, cp.z)
		world.focus_agl = 500.0   # no building crash checks
		world.update_world(dt, cp)
	var snd: Array = mode.sound()
	synth.set_state(float(snd[0]), float(snd[2]), false, state == "fly" and not paused and bool(Settings.get_value("sound")))
	var f: Dictionary = mode.tel_frame
	if not f.is_empty():
		ui.tel_label.text = "Rig link: %s\nFlyPT Mover: %s\npitch %.1f°  roll %.1f°  yaw rate %.1f°/s\nsurge %.2fg  sway %.2fg  heave %.2fg" % [tel.status, tel.xp.status, f["att"]["pitch_deg"], f["att"]["roll_deg"], f["rate"]["yaw_dps"], f["g_felt"]["surge"], f["g_felt"]["sway"], f["g_felt"]["heave"]]
	ui.set_status.text = "Status: " + tel.status + "\nFlyPT Mover: " + tel.xp.status


## Controls for Racing and Space, from the keyboard, a gamepad and the VR controllers.
func _read_mode_input(dt: float) -> Dictionary:
	var out := {"steer": 0.0, "throttle": 0.0, "brake": 0.0, "pitch": 0.0, "roll": 0.0, "yaw": 0.0, "fire": false, "boost": false}
	var pads := Input.get_connected_joypads()
	var pad := -1 if pads.is_empty() or _has_map() else int(pads[0])
	var vl := xr_left if vr_active and xr_left != null and xr_left.get_is_active() else null
	var vrr := xr_right if vr_active and xr_right != null and xr_right.get_is_active() else null
	if vrr != null:
		if _edge("vB", vrr.is_button_pressed("by_button")):
			_recentre_vr()
	if vl != null:
		if _edge("vX", vl.is_button_pressed("ax_button")):
			_pause(true)
		if _edge("vY", vl.is_button_pressed("by_button")):
			start_game()
	if pad >= 0 and _edge("ps", Input.is_joy_button_pressed(pad, JOY_BUTTON_START)):
		_pause(true)
	if pad >= 0 and _edge("pb", Input.is_joy_button_pressed(pad, JOY_BUTTON_B)):
		_cycle_camera()
	if args.has("autopilot") and mode is RaceMode:
		return (mode as RaceMode).autopilot()   # test option: the car drives itself
	if game == "race":
		var ks := clampf((_k(KEY_D) + _k(KEY_RIGHT)) - (_k(KEY_A) + _k(KEY_LEFT)), -1.0, 1.0)
		mkb["steer"] = _approach(mkb["steer"], ks, 3.2 if ks != 0.0 else 5.0, dt)
		var steer: float = mkb["steer"]
		var thr := maxf(_k(KEY_W), _k(KEY_UP))
		var brk := maxf(maxf(_k(KEY_S), _k(KEY_DOWN)), _k(KEY_SPACE))
		if pad >= 0:
			steer += _dz(Input.get_joy_axis(pad, JOY_AXIS_LEFT_X))
			thr = maxf(thr, Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_RIGHT))
			brk = maxf(brk, Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_LEFT))
		if vrr != null:
			thr = maxf(thr, vrr.get_float("trigger"))
			steer += _dz(vrr.get_vector2("primary").x)
		if vl != null:
			brk = maxf(brk, vl.get_float("trigger"))
			steer += _dz(vl.get_vector2("primary").x)
		var ms := _mapped("steer")
		var ma := _mapped("accel")
		var mb := _mapped("brake")
		if not is_nan(ms):
			steer += ms
		if not is_nan(ma):
			thr = maxf(thr, ma)
		if not is_nan(mb):
			brk = maxf(brk, mb)
		out["steer"] = clampf(steer, -1.0, 1.0)
		out["throttle"] = clampf(thr, 0.0, 1.0)
		out["brake"] = clampf(brk, 0.0, 1.0)
		return out
	# space: like the aircraft (W/S nose, A/D roll, Q/E yaw), plus guns and boost
	var tp := clampf(-(_k(KEY_UP) + _k(KEY_W)) + (_k(KEY_DOWN) + _k(KEY_S)), -1.0, 1.0)
	var tr := clampf((_k(KEY_RIGHT) + _k(KEY_D)) - (_k(KEY_LEFT) + _k(KEY_A)), -1.0, 1.0)
	var ty := _k(KEY_E) - _k(KEY_Q)
	kb["pitch"] = _approach(kb["pitch"], tp, 3.0 if tp != 0.0 else 5.0, dt)
	kb["roll"] = _approach(kb["roll"], tr, 3.5 if tr != 0.0 else 5.0, dt)
	kb["yaw"] = _approach(kb["yaw"], ty, 4.0 if ty != 0.0 else 6.0, dt)
	var pitch: float = 0.0
	var roll: float = 0.0
	var yaw: float = 0.0
	var thr_axis := (_k(KEY_SHIFT) + _k(KEY_PAGEUP) + _k(KEY_X)) - (_k(KEY_CTRL) + _k(KEY_PAGEDOWN) + _k(KEY_Z))
	var fire := _k(KEY_SPACE) > 0.0 or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var boost := _k(KEY_TAB) > 0.0 or _k(KEY_B) > 0.0
	if pad >= 0:
		roll += _dz(Input.get_joy_axis(pad, JOY_AXIS_RIGHT_X))
		pitch += _dz(Input.get_joy_axis(pad, JOY_AXIS_RIGHT_Y))
		yaw += _dz(Input.get_joy_axis(pad, JOY_AXIS_LEFT_X))
		thr_axis += -_dz(Input.get_joy_axis(pad, JOY_AXIS_LEFT_Y))
		fire = fire or Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_RIGHT) > 0.4
		boost = boost or Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_LEFT) > 0.4
	if vrr != null:
		var r2 := vrr.get_vector2("primary")
		roll += _dz(r2.x)
		pitch += -_dz(r2.y)
		fire = fire or vrr.get_float("trigger") > 0.5
	if vl != null:
		var l2 := vl.get_vector2("primary")
		yaw += _dz(l2.x)
		thr_axis += _dz(l2.y)
		boost = boost or vl.get_float("trigger") > 0.5
	var inv := -1.0 if Settings.get_value("invert") else 1.0
	space_thr = clampf(space_thr + thr_axis * 0.8 * dt, 0.0, 1.0)
	for e in [["roll", "r"], ["pitch", "p"], ["rudder", "y"]]:
		var mv := _mapped(e[0])
		if not is_nan(mv):
			if e[1] == "r":
				roll += mv
			elif e[1] == "p":
				pitch += mv
			else:
				yaw += mv
	var mth := _mapped("throttle")
	if not is_nan(mth) and thr_axis == 0.0:
		space_thr = mth
	var mf := _mapped("fire")
	if not is_nan(mf) and mf > 0.5:
		fire = true
	out["pitch"] = clampf(kb["pitch"] + pitch * inv, -1.0, 1.0)
	out["roll"] = clampf(kb["roll"] + roll, -1.0, 1.0)
	out["yaw"] = clampf(kb["yaw"] + yaw, -1.0, 1.0)
	out["throttle"] = space_thr
	out["fire"] = fire or args.has("autopilot")
	out["boost"] = boost
	return out


## Test option --switch_test: goes between the games and back several times (the way a person would, through
## the menu), so a crash when switching shows up in the log.
func _switch_test() -> void:
	var order := ["race", "flight", "race", "flight", "coaster", "flight", "space", "race", "flight"]
	if str(args["switch_test"]) != "" and str(args["switch_test"]) != "true":
		order = Array(str(args["switch_test"]).split(","))
	for g in order:
		await get_tree().create_timer(6.0).timeout
		Diag.write("switch test: to the menu, then %s" % g)
		to_menu()
		await get_tree().create_timer(1.0).timeout
		Settings.data["game"] = g
		await showcase()
		await get_tree().create_timer(1.0).timeout
		await start_game()
		Diag.write("switch test: %s running" % g)
	Diag.write("switch test: done")
	get_tree().quit()


## Test option --test_panel (runs headless, before anything else): the VR menu panel passes clicks and
## stick/A presses to the real menus. Prints PASS/FAIL lines and quits.
func _test_panel() -> void:
	var got := {}
	ui.setting_changed.connect(func(k: String, v): got[k] = v)
	ui.fly_pressed.connect(func(vr: bool): got["fly"] = vr)
	var origin := XROrigin3D.new()
	add_child(origin)
	var p := VRPanel.new()
	origin.add_child(p)
	p.setup(ui, self, origin)
	ui.loading.visible = false
	ui.show_menu()
	await get_tree().process_frame
	await get_tree().process_frame
	p.show_panel(true, Transform3D())
	var want := "space" if str(Settings.get_value("game")) != "space" else "race"
	var btn: Button = null
	for e in ui.seg_buttons["game"]:
		if e[0] == want:
			btn = e[1]
	var c := btn.get_global_rect().get_center()
	p._click(c, null)   # what a trigger pull does
	await get_tree().process_frame
	print(("PASS" if got.get("game") == want else "FAIL") + " pointer click on the %s button (got %s)" % [want, str(got.get("game"))])
	var cut := []
	for b in ui.menu.find_children("*", "Button", true, false):
		if (b as Button).is_visible_in_tree() and (b as Button).get_global_rect().end.y > VRPanel.PX.y:
			cut.append((b as Button).text)
	print(("PASS" if cut.is_empty() else "FAIL") + " every menu button fits on the VR panel " + str(cut))
	for name in ["Settings", "Controls"]:
		var mb: Button = null
		for b in ui.menu.find_children("*", "Button", true, false):
			if (b as Button).text == name:
				mb = b
		ui.hide_sheets()
		await get_tree().process_frame
		var mc := mb.get_global_rect().get_center()
		var hov := ""
		p._click(mc, null)
		await get_tree().process_frame
		var sheet: Control = ui.settings_sheet if name == "Settings" else ui.help_sheet
		print(("PASS" if sheet.visible else "FAIL") + " pointer click on %s at %s opens it" % [name, str(mc)])
	ui.hide_sheets()
	await get_tree().process_frame
	p._focus_first()
	await get_tree().process_frame
	p._push_action("ui_accept")
	await get_tree().process_frame
	print(("PASS" if got.has("fly") else "FAIL") + " A presses the highlighted button (%s)" % str(got))
	ui.show_lobby()
	await get_tree().process_frame
	await get_tree().process_frame
	var card: Button = ui.seg_buttons["rig"][2][1]
	var cc := card.get_global_rect().get_center()
	p._click(cc, null)   # what a trigger pull does
	await get_tree().process_frame
	print(("PASS" if got.get("rig") == "ride" and not ui.lobby.visible else "FAIL") + " set-up screen: pointing at 'Hands-free ride' picks it (got %s)" % str(got.get("rig")))
	ui.set_rig("wheel")
	var shown := []
	for e in ui.seg_buttons["game"]:
		if (e[1] as Button).visible:
			shown.append(e[0])
	print(("PASS" if shown == ["race"] else "FAIL") + " steering wheel set-up shows only Racing (%s)" % str(shown))
	p.teardown()
	await get_tree().process_frame
	print(("PASS" if ui.get_parent() == self else "FAIL") + " menus back on the laptop screen after VR")
	get_tree().quit()


# ------------------------------------------------------------ the simulator's own controls (joystick, wheel, pedals)
func _rig_map() -> Dictionary:
	var m = Settings.get_value("rig_map")
	return m if m is Dictionary else {}


func _has_map() -> bool:
	return not _rig_map().is_empty()


func _map_device(e: Dictionary) -> int:
	var pads := Input.get_connected_joypads()
	for id in pads:
		if Input.get_joy_name(id) == str(e.get("name", "")):
			return id
	return int(e.get("dev", -1)) if int(e.get("dev", -1)) in pads else -1


## A control learned in "Set up controls", 0..1 (pedals, throttle) or -1..1 (stick, wheel); NAN if not set up.
func _mapped(action: String) -> float:
	var map := _rig_map()
	if not map.has(action):
		return NAN
	var e: Dictionary = map[action]
	var dev := _map_device(e)
	if dev < 0:
		return NAN
	if e.has("button"):
		return 1.0 if Input.is_joy_button_pressed(dev, int(e["button"])) else 0.0
	var raw := Input.get_joy_axis(dev, int(e["axis"]))
	var span: float = float(e["full"]) - float(e["rest"])
	if absf(span) < 0.05:
		return NAN
	var x: float = (raw - float(e["rest"])) / span
	if action in BIPOLAR:
		return 0.0 if absf(x) < 0.04 else clampf(x, -1.0, 1.0)
	return clampf(x, 0.0, 1.0)


func _refresh_controls_sheet() -> void:
	ui.set_control_actions(RIG_ACTIONS.get(str(Settings.get_value("rig")), []))


func _controls_tick() -> void:
	if ui.controls_sheet == null or not ui.controls_sheet.visible:
		return
	var map := _rig_map()
	for a in RIG_ACTIONS.get(str(Settings.get_value("rig")), []):
		var act: String = a[0]
		var v := _mapped(act)
		var st := "not set (keyboard / gamepad)"
		if learning == act:
			st = "move it now…"
		elif map.has(act):
			var e: Dictionary = map[act]
			st = ("button %d" % int(e["button"])) if e.has("button") else ("axis %d" % int(e["axis"]))
			if is_nan(v):
				st += " (not plugged in)"
		ui.set_control_row(act, st, 0.0 if is_nan(v) else v)


## "Set" in Set up controls: watches every axis and button of every plugged-in controller and keeps the one
## that moves most (8 seconds to do it).
func _learn(action: String) -> void:
	if action == "clear":
		Settings.set_value("rig_map", {})
		ui.ctl_info.text = "All controls cleared: the keyboard and gamepads work as normal."
		return
	if learning != "":
		return
	var info: Array = []
	for a in RIG_ACTIONS.get(str(Settings.get_value("rig")), []):
		if a[0] == action:
			info = a
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		ui.ctl_info.text = "No joystick, wheel or gamepad found. Plug it in (USB), wait a few seconds, then press Set again."
		return
	learning = action
	ui.ctl_info.text = "%s: %s, then let go." % [info[1], info[2]]
	var base := {}
	var btn0 := {}
	for id in pads:
		for ax in JOY_AXIS_SDL_MAX:
			base[Vector2i(id, ax)] = Input.get_joy_axis(id, ax)
		for b in 32:
			btn0[Vector2i(id, b)] = Input.is_joy_button_pressed(id, b)
	var best_k := Vector2i(-1, -1)
	var best_d := 0.0
	var best_v := 0.0
	var t := 0.0
	var found := {}
	while t < 8.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		if action == "fire":
			for k in btn0.keys():
				if Input.is_joy_button_pressed(k.x, k.y) and not btn0[k]:
					found = {"name": Input.get_joy_name(k.x), "dev": k.x, "button": k.y}
			if not found.is_empty():
				break
			continue
		for k in base.keys():
			var val := Input.get_joy_axis(k.x, k.y)
			var d := absf(val - float(base[k]))
			if d > best_d:
				best_d = d
				best_k = k
				best_v = val
		if best_d > 0.5 and t > 1.0:
			# keep watching for a moment to catch the full movement
			var t2 := 0.0
			while t2 < 0.6:
				await get_tree().process_frame
				t2 += get_process_delta_time()
				var val2 := Input.get_joy_axis(best_k.x, best_k.y)
				if absf(val2 - float(base[best_k])) > absf(best_v - float(base[best_k])):
					best_v = val2
			found = {"name": Input.get_joy_name(best_k.x), "dev": best_k.x, "axis": best_k.y, "rest": base[best_k], "full": best_v}
			break
	learning = ""
	if found.is_empty():
		ui.ctl_info.text = "Nothing moved. Check it's plugged in and press Set again."
		return
	var map := _rig_map().duplicate()
	map[action] = found
	Settings.set_value("rig_map", map)
	Diag.write("Control set: %s = %s" % [action, str(found)])
	ui.ctl_info.text = "%s set (%s). Next control, or Done." % [info[1], str(found["name"])]
