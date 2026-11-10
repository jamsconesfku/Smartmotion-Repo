extends Control
## SmartMotion Motion: the operator screen. Replaces FlyPT Mover for SmartMotion Flight.
## Game (UDP JSON, port 4123) -> MotionEngine (cueing, 500 a second) -> Motion4Sim controller (USB or network).

const NAVY := Color("#02022f")
const ORANGE := Color("#ff4c00")
const RED := Color("#d92b2b")
const GREEN := Color("#2fbf71")
const AMBER := Color("#ffb347")
const INK := Color("#eceef8")
const MUTED := Color("#a9acd0")
const AXIS_NAMES := {"sway": "Sway (side)", "surge": "Surge (fwd/back)", "heave": "Heave (up/down)", "yaw": "Yaw (turn)", "roll": "Roll", "pitch": "Pitch (nose)"}

var cfg := Config.new()
var engine := MotionEngine.new()
var args := {}
var version := "dev"

var view: RigView
var bars := {}
var lbl_game: Label
var lbl_link: Label
var lbl_state: Label
var lbl_reason: Label
var lbl_rate: Label
var link_opt: OptionButton
var com_edit: LineEdit
var ip_edit: LineEdit
var row_com: HBoxContainer
var row_ip: HBoxContainer
var btn_connect: Button
var btn_motion: Button
var btn_estop: Button
var btn_start: Button
var btn_online: Button
var btn_park: Button
var strength: HSlider
var strength_lbl: Label
var page_settings: PanelContainer
var page_test: PanelContainer
var page_help: PanelContainer
var test_on: CheckBox
var test_sliders := {}
var wave_t := -1.0
var _shot_t := -1.0
var _port_msg_t := 0.0   # how long the "COM ports found" message stays up


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else true
	if FileAccess.file_exists("res://assets/version.txt"):
		version = FileAccess.get_file_as_string("res://assets/version.txt").strip_edges()
	# the USB helper has to be a real file for PowerShell to run it
	var ps := FileAccess.get_file_as_string("res://assets/serial_bridge.ps1")
	var f := FileAccess.open("user://serial_bridge.ps1", FileAccess.WRITE)
	if f != null:
		f.store_string(ps)
		f.close()
	_build_ui()
	engine.cue.cfg = cfg.cueing_values()
	engine.link.invert = cfg.inverts()
	engine.start(int(cfg.data["game_port"]), int(cfg.data["comp_port"]))
	if args.has("wave"):
		_on_test_toggled(true)
		test_on.button_pressed = true
		_start_wave()
	if args.has("motion"):
		_toggle_motion()
	if args.has("page"):
		_show_page({"settings": page_settings, "test": page_test, "help": page_help}.get(str(args["page"])))
	if args.has("shot"):
		_shot_t = float(args.get("shot_after", 3.0))
	get_window().close_requested.connect(_quit)
	get_tree().set_auto_accept_quit(false)


func _quit() -> void:
	engine.stop()
	cfg.save()
	get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit()


# ------------------------------------------------------------------ building the screen
func _sb(bg: Color, radius := 12, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(bw)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


func _lbl(text: String, size := 16, col := INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if text.length() > 40:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _wrap(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _btn(text: String, cb: Callable, col := Color(1, 1, 1, 0.1), font_col := INK, size := 17) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_stylebox_override("normal", _sb(col, 10))
	b.add_theme_stylebox_override("hover", _sb(col.lightened(0.15), 10))
	b.add_theme_stylebox_override("pressed", _sb(col.darkened(0.2), 10))
	b.add_theme_stylebox_override("disabled", _sb(Color(1, 1, 1, 0.04), 10))
	b.add_theme_color_override("font_color", font_col)
	b.add_theme_color_override("font_hover_color", font_col)
	b.add_theme_color_override("font_pressed_color", font_col)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _panel(parent: Control) -> VBoxContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _sb(Color(1, 1, 1, 0.05), 14, Color(1, 1, 1, 0.12), 1))
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	return v


func _build_ui() -> void:
	var th := Theme.new()
	th.default_font = load("res://assets/fonts/Barlow-Regular.ttf")
	th.set_font("font", "Button", load("res://assets/fonts/Barlow-SemiBold.ttf"))
	th.default_font_size = 16
	th.set_color("font_color", "Label", INK)
	th.set_stylebox("normal", "LineEdit", _sb(Color(1, 1, 1, 0.08), 8))
	th.set_stylebox("focus", "LineEdit", _sb(Color(1, 1, 1, 0.12), 8, ORANGE, 1))
	th.set_stylebox("normal", "OptionButton", _sb(Color(1, 1, 1, 0.1), 8))
	th.set_stylebox("hover", "OptionButton", _sb(Color(1, 1, 1, 0.16), 8))
	th.set_stylebox("pressed", "OptionButton", _sb(Color(1, 1, 1, 0.16), 8))
	th.set_stylebox("panel", "PopupMenu", _sb(Color("#0b0b4a"), 8))
	th.set_stylebox("slider", "HSlider", _sb(Color(1, 1, 1, 0.16), 4))
	th.set_stylebox("grabber_area", "HSlider", _sb(ORANGE, 4))
	th.set_stylebox("grabber_area_highlight", "HSlider", _sb(ORANGE, 4))
	theme = th
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = NAVY
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	margin.add_child(cols)

	# ---- left column: game, rig, controls
	var left_scroll := ScrollContainer.new()
	left_scroll.custom_minimum_size.x = 390
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cols.add_child(left_scroll)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	left_scroll.add_child(left)
	var head := HBoxContainer.new()
	left.add_child(head)
	var logo := TextureRect.new()
	logo.texture = load("res://assets/logo-dark.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	logo.custom_minimum_size = Vector2(150, 60)
	head.add_child(logo)
	var tv := VBoxContainer.new()
	head.add_child(tv)
	tv.add_child(_lbl("Motion", 26, ORANGE))
	tv.add_child(_lbl("v" + version, 13, MUTED))

	var g := _panel(left)
	g.add_child(_lbl("GAME", 13, MUTED))
	lbl_game = _wrap(_lbl("", 16))
	g.add_child(lbl_game)

	var r := _panel(left)
	r.add_child(_lbl("RIG CONNECTION", 13, MUTED))
	link_opt = OptionButton.new()
	link_opt.add_item("Dry run: no rig, screen only", 0)
	link_opt.add_item("USB cable (COM port)", 1)
	link_opt.add_item("Network cable (needs Pro licence)", 2)
	link_opt.select({"dry": 0, "usb": 1, "network": 2}.get(str(cfg.data["link"]), 0))
	link_opt.item_selected.connect(_on_link_selected)
	r.add_child(link_opt)
	row_com = HBoxContainer.new()
	r.add_child(row_com)
	row_com.add_child(_lbl("COM port", 15, MUTED))
	com_edit = LineEdit.new()
	com_edit.text = str(cfg.data["com_port"])
	com_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	com_edit.text_changed.connect(func(t: String): cfg.data["com_port"] = t.strip_edges().to_upper())
	row_com.add_child(com_edit)
	row_com.add_child(_btn("Find", _find_ports, Color(1, 1, 1, 0.1), INK, 15))
	row_ip = HBoxContainer.new()
	r.add_child(row_ip)
	row_ip.add_child(_lbl("Controller address", 15, MUTED))
	ip_edit = LineEdit.new()
	ip_edit.text = str(cfg.data["rig_ip"])
	ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ip_edit.text_changed.connect(func(t: String): cfg.data["rig_ip"] = t.strip_edges())
	row_ip.add_child(ip_edit)
	btn_connect = _btn("Connect", _toggle_connect, Color(1, 1, 1, 0.14))
	r.add_child(btn_connect)
	lbl_link = _wrap(_lbl("", 14, MUTED))
	r.add_child(lbl_link)
	lbl_state = _wrap(_lbl("", 15))
	r.add_child(lbl_state)
	var rb := HBoxContainer.new()
	rb.add_theme_constant_override("separation", 6)
	r.add_child(rb)
	btn_start = _btn("Start rig", func(): _cmd(RigLink.CMD_START, 0), Color(1, 1, 1, 0.1), INK, 15)
	btn_online = _btn("Online", func(): _cmd(RigLink.CMD_ONLINE, 0), Color(1, 1, 1, 0.1), INK, 15)
	btn_park = _btn("Park", func(): engine.request(engine.park), Color(1, 1, 1, 0.1), INK, 15)
	for b in [btn_start, btn_online, btn_park]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rb.add_child(b)
	r.add_child(_lbl("Start rig = homing (instead of pressing the controller's knob). Online = rig rises to the middle. Park = motion fades out, then the rig goes down.", 13, MUTED))

	var m := _panel(left)
	m.add_child(_lbl("MOTION", 13, MUTED))
	btn_motion = _btn("Motion OFF  (M)", _toggle_motion, Color(1, 1, 1, 0.12), INK, 22)
	btn_motion.custom_minimum_size.y = 54
	m.add_child(btn_motion)
	var sr := HBoxContainer.new()
	m.add_child(sr)
	sr.add_child(_lbl("Strength", 15, MUTED))
	strength = HSlider.new()
	strength.min_value = 0
	strength.max_value = 1
	strength.step = 0.05
	strength.value = float(cfg.data["intensity"])
	strength.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strength.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	strength.value_changed.connect(func(v: float): _set_cfg("intensity", v))
	sr.add_child(strength)
	strength_lbl = _lbl("", 15)
	strength_lbl.custom_minimum_size.x = 48
	sr.add_child(strength_lbl)
	btn_estop = _btn("EMERGENCY STOP  (Space)", _estop, RED, Color.WHITE, 22)
	btn_estop.custom_minimum_size.y = 64
	m.add_child(btn_estop)
	m.add_child(_btn("Clear emergency stop", func(): _cmd(RigLink.CMD_EMERGENCY, 0), Color(1, 1, 1, 0.08), MUTED, 14))
	m.add_child(_lbl("The red button wired to the controller is the real emergency stop: keep it within the operator's reach. This screen button sends the same command over the cable.", 13, AMBER))

	# ---- middle: rig picture and axis bars
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 10)
	cols.add_child(mid)
	var top_row := HBoxContainer.new()
	mid.add_child(top_row)
	lbl_reason = _wrap(_lbl("", 20, INK))
	lbl_reason.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(lbl_reason)
	top_row.add_child(_btn("Test movement", func(): _show_page(page_test), Color(1, 1, 1, 0.1), INK, 15))
	top_row.add_child(_btn("Settings", func(): _show_page(page_settings), Color(1, 1, 1, 0.1), INK, 15))
	top_row.add_child(_btn("Help", func(): _show_page(page_help), Color(1, 1, 1, 0.1), INK, 15))
	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.clip_contents = true
	mid.add_child(stack)
	view = RigView.new()
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(view)
	var hint := _lbl("Picture only (drag to turn). The real rig's measurements are stored in the Motion4Sim controller.", 13, MUTED)
	hint.position = Vector2(10, 8)
	hint.size = Vector2(600, 20)
	stack.add_child(hint)
	page_settings = _build_settings(stack)
	page_test = _build_test(stack)
	page_help = _build_help(stack)
	var bp := _panel(mid)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	bp.add_child(grid)
	for a in Cueing.AXES + ["belt"]:
		grid.add_child(_lbl(AXIS_NAMES.get(a, "Seat belt"), 15, MUTED))
		var bar := AxisBar.new()
		bar.custom_minimum_size = Vector2(200, 18)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.one_sided = a == "belt"
		grid.add_child(bar)
		var v := _lbl("", 15)
		v.custom_minimum_size.x = 80
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(v)
		bars[a] = [bar, v]
	lbl_rate = _wrap(_lbl("", 13, MUTED))
	bp.add_child(lbl_rate)
	_on_link_selected(link_opt.selected)


func _page(parent: Control, title: String) -> Array:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _sb(Color("#070745").lerp(NAVY, 0.3), 14, Color(1, 1, 1, 0.16), 1))
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.visible = false
	parent.add_child(p)
	var v := VBoxContainer.new()
	p.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	var t := _lbl(title, 22, ORANGE)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	h.add_child(_btn("Close", func(): p.visible = false, Color(1, 1, 1, 0.1), INK, 15))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	sc.add_child(body)
	return [p, body]


func _show_page(p) -> void:
	for q in [page_settings, page_test, page_help]:
		q.visible = q == p and not q.visible


func _slider_row(body: VBoxContainer, label: String, help: String, lo: float, hi: float, st: float, value: float, unit: String, cb: Callable) -> HSlider:
	var row := HBoxContainer.new()
	body.add_child(row)
	var l := _lbl(label, 16)
	l.custom_minimum_size.x = 280
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = st
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(s)
	var vl := _lbl("", 15)
	vl.custom_minimum_size.x = 130
	row.add_child(vl)
	var show := func(v: float):
		vl.text = ("%d %%" % roundi(v * 100.0)) if unit == "%" else ("%s %s" % [str(snappedf(v, st)), unit])
	show.call(value)
	s.value_changed.connect(func(v: float):
		show.call(v)
		cb.call(v))
	if help != "":
		body.add_child(_lbl(help, 13, MUTED))
	return s


func _build_settings(parent: Control) -> PanelContainer:
	var pb := _page(parent, "Settings")
	var body: VBoxContainer = pb[1]
	body.add_child(_lbl("Changes work straight away and are saved when you close the program. Try new values with Strength low.", 14, MUTED))
	for group in Config.FIELDS:
		body.add_child(_lbl(str(group[0]).to_upper(), 14, ORANGE))
		for fd in group[1]:
			var key: String = fd[0]
			if key == "belt_on":
				var cb := CheckBox.new()
				cb.text = fd[1]
				cb.button_pressed = bool(cfg.data[key])
				cb.toggled.connect(func(on: bool): _set_cfg("belt_on", on))
				body.add_child(cb)
				body.add_child(_lbl(fd[2], 13, MUTED))
				continue
			var s := _slider_row(body, fd[1], fd[2], fd[3], fd[4], fd[5], float(cfg.data[key]), fd[6], func(v: float): _set_cfg(key, v))
			if key == "intensity":
				s.value_changed.connect(func(v: float): strength.set_value_no_signal(v))
	body.add_child(_lbl("DIRECTIONS", 14, ORANGE))
	body.add_child(_lbl("If an axis moves the wrong way on the real rig (check with Test movement, Strength low), tick it here.", 13, MUTED))
	var inv := HFlowContainer.new()
	body.add_child(inv)
	for a in Cueing.AXES:
		var cb := CheckBox.new()
		cb.text = "Flip " + a
		cb.button_pressed = bool(cfg.data["inv_" + a])
		cb.toggled.connect(func(on: bool):
			cfg.data["inv_" + a] = on
			var d := cfg.inverts()
			engine.request(func(): engine.link.invert = d))
		inv.add_child(cb)
	body.add_child(_lbl("PORTS", 14, ORANGE))
	body.add_child(_lbl("Game data in on port %d (in the game: Settings > Motion rig > On, address 127.0.0.1 port %d). Seat position back to the game on port %d. Controller network port %d. USB speed %d." % [int(cfg.data["game_port"]), int(cfg.data["game_port"]), int(cfg.data["comp_port"]), int(cfg.data["rig_port"]), int(cfg.data["baud"])], 13, MUTED))
	body.add_child(_btn("Reset all settings above to the defaults", _reset_defaults, Color(1, 1, 1, 0.08), MUTED, 14))
	return pb[0]


func _build_test(parent: Control) -> PanelContainer:
	var pb := _page(parent, "Test movement")
	var body: VBoxContainer = pb[1]
	body.add_child(_lbl("Moves the seat by hand instead of from the game, to check each axis goes the right way. Use it first in Dry run, then on the rig with Strength low and nobody on board. Motion must be ON for the rig to move, and the movement is scaled by Strength.", 14, MUTED))
	test_on = CheckBox.new()
	test_on.text = "Test movement (ignore the game)"
	test_on.toggled.connect(_on_test_toggled)
	body.add_child(test_on)
	for a in Cueing.AXES:
		var rot: bool = a in ["yaw", "roll", "pitch"]
		var lim := float(cfg.data["limit_deg"] if rot else cfg.data["limit_mm"])
		test_sliders[a] = _slider_row(body, AXIS_NAMES[a], "", -lim, lim, 0.5, 0.0, "°" if rot else "mm", func(_v: float): _push_test())
	test_sliders["belt"] = _slider_row(body, "Seat belt", "", 0.0, 1.0, 0.05, 0.0, "%", func(_v: float): _push_test())
	var h := HBoxContainer.new()
	body.add_child(h)
	h.add_child(_btn("Wave each axis in turn", _start_wave, Color(1, 1, 1, 0.12), INK, 15))
	h.add_child(_btn("Back to the middle", _centre_test, Color(1, 1, 1, 0.12), INK, 15))
	body.add_child(_lbl("What you should see: sway + = seat to the right, surge + = forward, heave + = up, yaw + = nose to the right, roll + = right side down, pitch + = nose up. The wave goes through them in that order, each one to + first.", 13, MUTED))
	return pb[0]


func _build_help(parent: Control) -> PanelContainer:
	var pb := _page(parent, "How to use SmartMotion Motion")
	var body: VBoxContainer = pb[1]
	var steps := [
		"ONE-OFF SET-UP",
		"1. In the Motion4Sim Dashboard (the controller's own set-up program), enter the rig's measurements on the Rig tab. They use the same layout as FlyPT Mover, so copy them from the MotionXP-PRIME_FLY rig in Mover. Check them in the Dashboard's 3D view and on its Test tab in Position mode. Then close the Dashboard: only one program can use the USB port.",
		"2. Set the travel limits here (Settings > Safety limits) to fit inside the rig's real travel.",
		"3. With nobody on the rig and Strength at 20 %, use Test movement to check every axis goes the right way. Flip any that don't (Settings > Directions).",
		"EVERY SESSION",
		"1. Start SmartMotion Flight. In its Settings, turn Motion rig On (address 127.0.0.1, port 4123). The GAME box here should say it is receiving.",
		"2. Here: pick USB cable, check the COM port (press Find), press Connect.",
		"3. Press Start rig (the rig homes), then Online (it rises to the middle).",
		"4. Rider on board and belted, operator at the red stop button. Press Motion ON. The movement fades in over 2 seconds.",
		"5. Pausing or crashing in the game, or the game stopping, fades the motion out and the seat goes back to the middle by itself.",
		"6. After the ride: Park. The motion fades out and the rig goes down. Rider off only when it has stopped.",
		"VR",
		"SmartMotion Flight reads the seat position this program sends back (port 4124) and cancels the rig's movement out of the headset view, so the cockpit stays still around you while the seat moves. It only does this while the rig is really moving (not in Dry run).",
		"IF SOMETHING IS WRONG",
		"Space or the red button on screen: emergency stop. The hardware stop button on the controller always works, whatever this program does.",
		"'USB ... closed': the controller isn't plugged in, the COM port is wrong, or another program (Dashboard, FlyPT Mover) has the port open.",
		"Network cable: only works if the controller has the Pro licence, and the controller's address must be right (it is shown in the Dashboard).",
	]
	for s in steps:
		var head: bool = s == s.to_upper()
		body.add_child(_lbl(s, 14 if head else 15, ORANGE if head else INK))
	return pb[0]


# ------------------------------------------------------------------ actions
func _set_cfg(key: String, v) -> void:
	cfg.data[key] = v
	engine.request(func(): engine.cue.cfg[key] = v)


func _cmd(c: int, v: int) -> void:
	engine.request(func(): engine.link.send_command(c, v))


func _on_link_selected(i: int) -> void:
	cfg.data["link"] = ["dry", "usb", "network"][i]
	row_com.visible = i == 1
	row_ip.visible = i == 2
	btn_connect.visible = i != 0
	engine.request(func(): engine.link.close())


func _toggle_connect() -> void:
	var s := engine.snapshot()
	if bool(s.get("connected", false)):
		engine.request(func(): engine.link.close())
		return
	var link := str(cfg.data["link"])
	var com := str(cfg.data["com_port"])
	var baud := int(cfg.data["baud"])
	var ip := str(cfg.data["rig_ip"])
	var port := int(cfg.data["rig_port"])
	var helper := ProjectSettings.globalize_path("user://serial_bridge.ps1")
	if link == "usb":
		engine.request(func(): engine.link.open_usb(com, baud, helper))
	elif link == "network":
		engine.request(func(): engine.link.open_network(ip, port))
	cfg.save()


func _find_ports() -> void:
	var ports := RigLink.list_ports()
	if ports.is_empty():
		lbl_link.text = "No COM ports found. Is the controller plugged in by USB and switched on?"
		_port_msg_t = 8.0
		return
	com_edit.text = ports[ports.size() - 1]
	cfg.data["com_port"] = com_edit.text
	lbl_link.text = "COM ports found: " + ", ".join(ports) + ". If there are several, check Windows Device Manager."
	_port_msg_t = 8.0


func _toggle_motion() -> void:
	engine.request(func(): engine.cue.want_on = not engine.cue.want_on)


func _estop() -> void:
	engine.request(engine.emergency)


func _on_test_toggled(on: bool) -> void:
	if not on:
		wave_t = -1.0
		engine.set_test({})
	else:
		_push_test()


func _push_test() -> void:
	if test_on == null or not test_on.button_pressed:
		return
	var d := {}
	for a in test_sliders.keys():
		d[a] = (test_sliders[a] as HSlider).value
	engine.set_test(d)


func _centre_test() -> void:
	wave_t = -1.0
	for a in test_sliders.keys():
		(test_sliders[a] as HSlider).value = 0.0
	_push_test()


func _start_wave() -> void:
	if not test_on.button_pressed:
		test_on.button_pressed = true
	wave_t = 0.0


func _reset_defaults() -> void:
	for k in Cueing.DEFAULTS.keys():
		cfg.data[k] = Cueing.DEFAULTS[k]
	var d := cfg.cueing_values()
	engine.request(func(): engine.cue.cfg = d)
	cfg.save()
	# rebuild the page so the sliders show the defaults
	var parent := page_settings.get_parent()
	page_settings.queue_free()
	page_settings = _build_settings(parent)
	page_settings.visible = true
	strength.set_value_no_signal(float(cfg.data["intensity"]))


func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_SPACE:
			_estop()
		elif e.keycode == KEY_M:
			_toggle_motion()


# ------------------------------------------------------------------ every frame
func _process(delta: float) -> void:
	if wave_t >= 0.0:
		wave_t += delta
		var i := int(wave_t / 3.0)
		if i >= Cueing.AXES.size():
			_centre_test()
		else:
			var a: String = Cueing.AXES[i]
			var s: HSlider = test_sliders[a]
			for b in Cueing.AXES:
				if b != a:
					(test_sliders[b] as HSlider).value = 0.0
			s.value = sin(fmod(wave_t, 3.0) / 3.0 * TAU) * s.max_value * 0.6
	var s := engine.snapshot()
	if s.is_empty():
		return
	var pose: Dictionary = s["pose"]
	view.set_pose(pose)
	for a in Cueing.AXES:
		var rot: bool = a in ["yaw", "roll", "pitch"]
		var lim := float(cfg.data["limit_deg"] if rot else cfg.data["limit_mm"])
		var bar: AxisBar = bars[a][0]
		bar.value = float(pose[a]) / lim
		bar.queue_redraw()
		(bars[a][1] as Label).text = ("%+.1f°" if rot else "%+.0f mm") % float(pose[a])
	(bars["belt"][0] as AxisBar).value = float(s["belt"])
	(bars["belt"][0] as AxisBar).queue_redraw()
	(bars["belt"][1] as Label).text = "%d %%" % roundi(float(s["belt"]) * 100.0) if bool(cfg.data["belt_on"]) else "off"
	# game
	var gm: Dictionary = s["game"]
	if engine.listen_error != "":
		lbl_game.text = engine.listen_error
		lbl_game.add_theme_color_override("font_color", RED)
	elif float(s["age"]) < 0.5:
		var ac: String = {"bulldog": "Bulldog", "fighter": "WW2 fighter", "racing": "Racing car", "space": "Space fighter"}.get(str(gm["aircraft"]), str(gm["aircraft"]))
		lbl_game.text = "Receiving, %d a second.  %s, %d kt%s%s" % [roundi(float(s["frame_hz"])), ac, roundi(float(gm["ias_kt"])), ", on the ground" if gm["on_ground"] else "", "  PAUSED" if gm["paused"] else ("  CRASHED" if gm["crashed"] else "")]
		lbl_game.add_theme_color_override("font_color", GREEN)
	else:
		lbl_game.text = "No data yet. In SmartMotion Flight: Settings > Motion rig > On (127.0.0.1, port %d), then fly." % engine.game_port
		lbl_game.add_theme_color_override("font_color", AMBER)
	# rig
	var connected := bool(s["connected"])
	_port_msg_t -= delta
	if _port_msg_t <= 0.0:
		lbl_link.text = str(s["link"])
	btn_connect.text = "Disconnect" if connected else "Connect"
	var st := int(s["rig_state"])
	lbl_link.visible = int(s["mode"]) != RigLink.Mode.DRY_RUN or _port_msg_t > 0.0
	if int(s["mode"]) == RigLink.Mode.DRY_RUN:
		lbl_state.text = "Dry run: the picture moves, the rig doesn't."
		lbl_state.add_theme_color_override("font_color", MUTED)
	elif st >= 0:
		lbl_state.text = "Controller: " + RigLink.state_text(st)
		lbl_state.add_theme_color_override("font_color", RED if st >= 31 and st <= 34 else (GREEN if st >= 15 and st <= 20 else INK))
	elif connected:
		lbl_state.text = "Controller: sending (no status over the network cable; check the controller's screen)" if int(s["mode"]) == RigLink.Mode.NETWORK else "Controller: waiting for an answer..."
		lbl_state.add_theme_color_override("font_color", INK)
	else:
		lbl_state.text = "Not connected"
		lbl_state.add_theme_color_override("font_color", MUTED)
	for b in [btn_start, btn_online, btn_park]:
		b.disabled = not connected
	# motion
	var on := bool(s["want_on"])
	btn_motion.text = ("Motion ON  (M)" if on else "Motion OFF  (M)")
	var mc := ORANGE if on else Color(1, 1, 1, 0.12)
	btn_motion.add_theme_stylebox_override("normal", _sb(mc, 10))
	btn_motion.add_theme_stylebox_override("hover", _sb(mc.lightened(0.15), 10))
	strength_lbl.text = "%d %%" % roundi(strength.value * 100.0)
	var sc := float(s["scale"])
	var why := str(s["reason"])
	if bool(s["parking"]):
		lbl_reason.text = "Parking: fading out, then the rig goes down"
	elif not on:
		lbl_reason.text = "Motion off" + (": seat going back to the middle" if sc > 0.0 else "") + "   (game: %s)" % why
	elif sc < 1.0 and why in ["following the game", "test movement"]:
		lbl_reason.text = "Fading in... %d %%" % roundi(sc * 100.0)
	else:
		lbl_reason.text = why.substr(0, 1).to_upper() + why.substr(1)
	lbl_rate.text = "Positions sent: %d a second%s.  VR motion compensation: %s" % [roundi(float(s["loop_hz"])), "" if connected else " (dry run: not sent)", "active" if bool(s["live"]) else "off (rig not moving)"]
	if _shot_t >= 0.0:
		_shot_t -= delta
		if _shot_t < 0.0:
			get_viewport().get_texture().get_image().save_png(str(args["shot"]))
			_quit()


class AxisBar:
	extends Control
	var value := 0.0
	var one_sided := false

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(1, 1, 1, 0.1))
		var v := clampf(value, -1.0, 1.0)
		var col := Color("#ff4c00") if absf(v) < 0.9 else Color("#d92b2b")
		if one_sided:
			draw_rect(Rect2(0, 0, size.x * clampf(v, 0.0, 1.0), size.y), col)
		else:
			var mid := size.x * 0.5
			var w := mid * v
			draw_rect(Rect2(mid + minf(w, 0.0), 0, absf(w), size.y), col)
			draw_line(Vector2(mid, 0), Vector2(mid, size.y), Color(1, 1, 1, 0.6), 2.0)
