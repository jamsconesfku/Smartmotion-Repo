class_name GameUI
extends CanvasLayer
## Menus and heads-up display in SmartMotion colours.

signal fly_pressed(vr: bool)
signal resume_pressed
signal restart_pressed
signal menu_pressed
signal setting_changed(key: String, value)
signal diag_pressed
signal vr_action(what: String)
signal learn_pressed(action: String)
signal binds_changed

const NAVY := Color("#02022f")
const ORANGE := Color("#ff4c00")
const INK := Color("#eceef8")
const MUTED := Color("#a9acd0")

var theme_res := Theme.new()
var root := Control.new()
var loading: Control
var load_bar: ProgressBar
var load_msg: Label
var load_pct: Label
var load_tip: Label
var tip_t := 0
var menu: Control
var hud: Control
var pause_sheet: Control
var end_sheet: Control
var help_sheet: Control
var settings_sheet: Control
var vr_btn: Button
var gpu_label: Label
var vr_note: Label
var seg_buttons := {}
var ital: Font
var logo_dark: Texture2D

# hud nodes
var l_speed: Label
var l_alt: Label
var l_vs: Label
var l_hdg: Label
var thr_bar: ProgressBar
var tag_flaps: Label
var tag_brake: Label
var tag_assist: Label
var msg_label: Label
var toast_label: Label
var gate_box: Control
var l_gate: Label
var l_gate_t: Label
var arrow: Control
var adi: Instruments
var tel_panel: PanelContainer
var tel_label: Label
var end_title: Label
var end_text: Label
var end_big: Label
var end_lab: Label
var set_tel_btn: Button
var set_status: Label
var toast_t := 0.0
var fps_label: Label
var fps_t := 0.0
var fit := {}   # sheet -> [scroll container, content]
var title_b: Label
var subtitle: Label
var mode_boxes := {}       # game -> VBoxContainer of its own options
var style_cap: Label
var tod_box: Control
var fly_btn: Button
var again_btn: Button
var in_vr := false
var vr_box: VBoxContainer
var vr_hz_btn: Button
var cap_speed: Label
var cap_alt: Label
var cap_hdg: Label
var adi_slot: Control
var launch_title: Label
var launch_sum: Label
const GAMES := {
	"flight": ["Flight", "Fly the skies around Duxford in Skysmart's Bulldog or a WW2 fighter.", "Fly"],
	"race": ["Racing", "Drive an open-wheel racing car round a 4 km circuit: race seven rivals or set a fast lap.", "Race"],
	"space": ["Space", "Fly a spaceship: take off from Duxford and climb into space, jump at hyperspeed between the planets, then fly back down and land. Or fight drones round the Saturn station.", "Launch"],
	"coaster": ["Coaster", "Ride a roller coaster beside Duxford airfield: a 52 m lift hill, a drop to 104 km/h, airtime hills and a helix. Just sit back.", "Ride"],
}
## How the simulator is set up (chosen on the first screen): what's fitted and which games suit it.
const RIGS := {
	"stick": ["Flight stick", "Flight  ·  Space", "Joystick for pitch and roll, a throttle lever, rudder pedals if fitted"],
	"wheel": ["Steering wheel", "Racing", "Steering wheel with accelerator and brake pedals"],
	"ride": ["Hands-free ride", "Roller coaster", "No controls fitted: the rider sits back and holds on"],
	"all": ["Laptop or gamepad", "All games", "For trying things out: keyboard, mouse or a gamepad"],
}
const RIG_GAMES := {"stick": ["flight", "space"], "wheel": ["race"], "ride": ["coaster"], "all": ["flight", "race", "space", "coaster"]}
var lobby: Control
var rig_label: Label
var setup_ctl_btn: Button
var controls_sheet: Control
var ctl_rows: VBoxContainer
var ctl_info: Label
var ctl_widgets := {}       # action -> [status label, bar]
# v1.19.0: change keys, the Controls picture and the controls shown while playing
var keys_sheet: Control
var keys_info: Label
var bind_btns := {}         # action -> [key 1 button, key 2 button, controller button]
var cap := {}               # the control waiting for a key or button: {"id", "slot" (0, 1 or "b"), "btn0": buttons already held}
var help_game := "flight"
var help_pic: KeyboardPic
var help_tabs := {}
var help_cards: HBoxContainer
var help_tip: Label
var overlay: PanelContainer
var overlay_rows: VBoxContainer
var overlay_game := "flight"
var f1_hint: Label


func _ready() -> void:
	logo_dark = load("res://assets/logo-dark.png")
	ital = load("res://assets/fonts/BarlowSemiCondensed-ExtraBoldItalic.ttf")
	_build_theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = theme_res
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_hud()
	_build_overlay()
	_build_menu()
	_build_sheets()
	_build_lobby()
	_build_loading()
	show_loading()
	show_fps(bool(Settings.get_value("show_fps")))


func _sb(bg: Color, radius := 14, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(bw)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 9
	s.content_margin_bottom = 9
	return s


func _build_theme() -> void:
	var t := theme_res
	t.default_font = load("res://assets/fonts/Barlow-Regular.ttf")
	t.set_font("font", "Button", load("res://assets/fonts/Barlow-SemiBold.ttf"))
	t.default_font_size = 18
	t.set_color("font_color", "Label", INK)
	t.set_color("font_color", "Button", MUTED)
	t.set_color("font_hover_color", "Button", INK)
	t.set_color("font_pressed_color", "Button", NAVY)
	t.set_color("font_hover_pressed_color", "Button", NAVY)
	t.set_color("font_focus_color", "Button", INK)
	t.set_stylebox("normal", "Button", _sb(Color(1, 1, 1, 0.08), 11))
	t.set_stylebox("hover", "Button", _sb(Color(1, 1, 1, 0.16), 11))
	t.set_stylebox("pressed", "Button", _sb(Color.WHITE, 11))
	t.set_stylebox("hover_pressed", "Button", _sb(Color.WHITE, 11))
	t.set_stylebox("focus", "Button", _sb(Color(0, 0, 0, 0), 11, ORANGE, 2))
	t.set_stylebox("panel", "PanelContainer", _sb(Color(0.005, 0.005, 0.16, 0.78), 22, Color(1, 1, 1, 0.16), 1))
	t.set_stylebox("fill", "ProgressBar", _sb(ORANGE, 6))
	t.set_stylebox("background", "ProgressBar", _sb(Color(1, 1, 1, 0.16), 6))


func _glass(parent: Control) -> PanelContainer:
	var p := PanelContainer.new()
	var s := _sb(Color(0.005, 0.005, 0.18, 0.62), 16, Color(1, 1, 1, 0.16), 1)
	p.add_theme_stylebox_override("panel", s)
	parent.add_child(p)
	return p


func _lbl(text: String, size: int, col := INK, italic := false, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if italic:
		l.add_theme_font_override("font", ital)
	l.horizontal_alignment = align
	return l


func _section(parent: Control, title: String) -> void:
	var l := _lbl(title.to_upper(), 12, MUTED)
	l.add_theme_constant_override("line_spacing", 0)
	parent.add_child(l)


func _big_button(text: String, accent: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", ital)
	b.add_theme_font_size_override("font_size", 26)
	b.custom_minimum_size = Vector2(0, 56)
	if accent:
		b.add_theme_stylebox_override("normal", _sb(ORANGE, 16))
		b.add_theme_stylebox_override("hover", _sb(Color("#ff6a24"), 16))
		b.add_theme_stylebox_override("pressed", _sb(Color("#cc3d00"), 16))
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(c, Color.WHITE)
	return b


func _seg(parent: Control, key: String, options: Array, current) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	var group := ButtonGroup.new()
	seg_buttons[key] = []
	for o in options:
		var b := Button.new()
		b.text = o[1]
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.button_pressed = str(o[0]) == str(current)
		b.pressed.connect(func(): setting_changed.emit(key, o[0]))
		row.add_child(b)
		seg_buttons[key].append([o[0], b])


func _note(parent: Control, text: String) -> void:
	var l := _lbl(text, 12, MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(420, 0)
	parent.add_child(l)


func set_seg(key: String, value) -> void:
	for e in seg_buttons.get(key, []):
		(e[1] as Button).set_pressed_no_signal(str(e[0]) == str(value))


# ------------------------------------------------------------ loading
const TIPS := [
	"The ground is the real Duxford area: 1 m laser-scanned heights, real roads, woods and buildings.",
	"Every tree and hedge near the airfield stands where the real one does, at its real height.",
	"Pick the time of day and the weather in the menu: try Golden hour with Few clouds.",
	"In VR, press B to recentre your view once you're sitting comfortably.",
	"Easy mode sets full power for you. Pro mode is the real thing.",
	"Fly over the racing circuit 2.5 km west of the runway, and the roller coaster beside the airfield.",
]


## Full-screen loading screen (v1.15.0): the whole window, with the logo, a wide progress bar and tips.
func _build_loading() -> void:
	loading = TextureRect.new()
	var gt := GradientTexture2D.new()
	var gd := Gradient.new()
	gd.set_color(0, Color("#0a0a52"))
	gd.set_color(1, Color("#010118"))
	gt.gradient = gd
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.42)
	gt.fill_to = Vector2(1.15, 1.1)
	(loading as TextureRect).texture = gt
	(loading as TextureRect).expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	(loading as TextureRect).stretch_mode = TextureRect.STRETCH_SCALE
	loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(loading)
	# an orange band low across the screen, the brand accent
	var band := ColorRect.new()
	band.color = Color(1.0, 0.3, 0.0, 0.9)
	band.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	band.offset_top = -6
	loading.add_child(band)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_bottom = -170
	loading.add_child(c)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	c.add_child(v)
	var lg := TextureRect.new()
	lg.texture = logo_dark
	lg.custom_minimum_size = Vector2(640, 256)
	lg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	v.add_child(lg)
	v.add_child(_lbl("FLY IT.  DRIVE IT.  FEEL IT.", 22, MUTED, true, HORIZONTAL_ALIGNMENT_CENTER))
	# progress along the bottom, two-thirds of the width
	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.anchor_left = 0.16
	bottom.anchor_right = 0.84
	bottom.offset_top = -150
	bottom.offset_bottom = -50
	bottom.add_theme_constant_override("separation", 12)
	loading.add_child(bottom)
	var row := HBoxContainer.new()
	bottom.add_child(row)
	load_msg = _lbl("Starting up…", 20, INK)
	load_msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(load_msg)
	load_pct = _lbl("0%", 20, ORANGE, true)
	row.add_child(load_pct)
	load_bar = ProgressBar.new()
	load_bar.custom_minimum_size = Vector2(0, 12)
	load_bar.show_percentage = false
	load_bar.max_value = 1.0
	bottom.add_child(load_bar)
	load_tip = _lbl(TIPS[randi() % TIPS.size()], 16, MUTED, false, HORIZONTAL_ALIGNMENT_CENTER)
	load_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom.add_child(load_tip)


func set_progress(p: float, msg: String) -> void:
	load_bar.value = p
	load_msg.text = msg + "…"
	load_pct.text = "%d%%" % int(round(p * 100.0))
	if Time.get_ticks_msec() - tip_t > 6000:
		tip_t = Time.get_ticks_msec()
		load_tip.text = TIPS[randi() % TIPS.size()]


func show_loading() -> void:
	loading.visible = true
	if menu != null:
		menu.visible = false
	hud.visible = false


# ------------------------------------------------------------ menu
func _build_menu() -> void:
	# v1.15.0 layout: a top bar (logo, the games, Controls / Settings / Quit), the chosen game's options on the
	# left, and a launch panel at the bottom right (what you picked, Fly, VR). The 3D world shows in between.
	menu = Control.new()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(menu)
	# soft dark edges so the white text reads over any sky
	for side in [0, 1]:
		var shade := TextureRect.new()
		var gt := GradientTexture2D.new()
		var gd := Gradient.new()
		gd.set_color(0, Color(0.004, 0.004, 0.12, 0.72))
		gd.set_color(1, Color(0.004, 0.004, 0.12, 0.0))
		gt.gradient = gd
		gt.fill_to = Vector2(1, 0) if side == 0 else Vector2(0, 1)
		shade.texture = gt
		shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shade.stretch_mode = TextureRect.STRETCH_SCALE
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if side == 0:
			shade.set_anchors_preset(Control.PRESET_LEFT_WIDE)
			shade.offset_right = 760
		else:
			shade.set_anchors_preset(Control.PRESET_TOP_WIDE)
			shade.offset_bottom = 170
		menu.add_child(shade)
	# ---- top bar
	var top := MarginContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	for k in ["margin_left", "margin_right"]:
		top.add_theme_constant_override(k, 30)
	top.add_theme_constant_override("margin_top", 20)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(top)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 18)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(bar)
	var lg := TextureRect.new()
	lg.texture = logo_dark
	lg.custom_minimum_size = Vector2(170, 58)
	lg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bar.add_child(lg)
	var gr := HBoxContainer.new()
	gr.add_theme_constant_override("separation", 8)
	gr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gr.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_child(gr)
	var gg := ButtonGroup.new()
	seg_buttons["game"] = []
	for g in ["flight", "race", "space", "coaster"]:
		var b := Button.new()
		b.text = GAMES[g][0]
		b.toggle_mode = true
		b.button_group = gg
		b.custom_minimum_size = Vector2(170, 56)
		b.add_theme_font_override("font", ital)
		b.add_theme_font_size_override("font_size", 27)
		b.add_theme_stylebox_override("normal", _sb(Color(0.01, 0.01, 0.2, 0.55), 14, Color(1, 1, 1, 0.14), 1))
		b.add_theme_stylebox_override("hover", _sb(Color(0.05, 0.05, 0.3, 0.75), 14, Color(1, 1, 1, 0.4), 1))
		b.add_theme_stylebox_override("pressed", _sb(ORANGE, 14))
		b.add_theme_stylebox_override("hover_pressed", _sb(Color("#ff6a24"), 14))
		b.add_theme_color_override("font_color", INK)
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
		b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
		b.button_pressed = Settings.get_value("game") == g
		b.pressed.connect(func(): setting_changed.emit("game", g))
		gr.add_child(b)
		seg_buttons["game"].append([g, b])
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 6)
	bar.add_child(tools)
	for spec in [["Controls", func(): open_sheet(help_sheet)], ["Settings", func(): open_sheet(settings_sheet)], ["Quit", func(): get_tree().quit()]]:
		var tb := Button.new()
		tb.text = spec[0]
		tb.custom_minimum_size = Vector2(104, 46)
		tb.add_theme_stylebox_override("normal", _sb(Color(0.01, 0.01, 0.2, 0.55), 12, Color(1, 1, 1, 0.14), 1))
		tb.add_theme_color_override("font_color", INK)
		tb.pressed.connect(spec[1])
		tools.add_child(tb)
	# ---- left: the chosen game's options
	var lm := MarginContainer.new()
	lm.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	lm.add_theme_constant_override("margin_left", 30)
	lm.add_theme_constant_override("margin_top", 104)
	lm.add_theme_constant_override("margin_bottom", 92)
	lm.custom_minimum_size = Vector2(590, 0)
	lm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(lm)
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	lm.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 7)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(v)
	title_b = _lbl("Flight", 48, Color.WHITE, true)
	v.add_child(title_b)
	subtitle = _lbl("", 15, MUTED)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.custom_minimum_size = Vector2(500, 0)
	v.add_child(subtitle)
	v.add_child(_rule())
	var fb := VBoxContainer.new()
	fb.add_theme_constant_override("separation", 7)
	v.add_child(fb)
	mode_boxes["flight"] = fb
	_section(fb, "Aircraft")
	_seg(fb, "aircraft", [["bulldog", "Bulldog G-SMAT (trainer)"], ["fighter", "WW2 Fighter (fast)"]], Settings.get_value("aircraft"))
	var fr := HBoxContainer.new()
	fr.add_theme_constant_override("separation", 12)
	fb.add_child(fr)
	for spec in [["Start", "start", [["runway", "On the runway"], ["air", "In the air"]]], ["Game", "mode", [["free", "Free flight"], ["gates", "Gate run"]]]]:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 7)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fr.add_child(col)
		_section(col, spec[0])
		_seg(col, spec[1], spec[2], Settings.get_value(spec[1]))
	var rb := VBoxContainer.new()
	rb.add_theme_constant_override("separation", 7)
	v.add_child(rb)
	mode_boxes["race"] = rb
	_section(rb, "Race")
	_seg(rb, "race", [["race", "3 laps against 7 cars"], ["trial", "Time trial (fastest lap)"]], Settings.get_value("race"))
	var sb := VBoxContainer.new()
	sb.add_theme_constant_override("separation", 7)
	v.add_child(sb)
	mode_boxes["space"] = sb
	var sr := HBoxContainer.new()
	sr.add_theme_constant_override("separation", 12)
	sb.add_child(sr)
	for spec in [["Start", "space_start", [["earth", "On Earth (Duxford)"], ["space", "In space"]]], ["Game", "space_game", [["explore", "Explore the planets"], ["battle", "Drone battle"]]]]:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 7)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sr.add_child(col)
		_section(col, spec[0])
		_seg(col, spec[1], spec[2], Settings.get_value(spec[1]))
	style_cap = _lbl("FLYING STYLE", 12, MUTED)
	v.add_child(style_cap)
	_seg(v, "assist", [[true, "Easy (assisted)"], [false, "Pro (manual)"]], Settings.get_value("assist"))
	tod_box = VBoxContainer.new()
	tod_box.add_theme_constant_override("separation", 7)
	v.add_child(tod_box)
	tod_box.add_child(_rule())
	_section(tod_box, "Time of day")
	_seg(tod_box, "tod", [["morning", "Morning"], ["day", "Midday"], ["golden", "Golden hour"], ["sunset", "Sunset"]], Settings.get_value("tod"))
	_section(tod_box, "Weather")
	_seg(tod_box, "weather", [["clear", "Clear"], ["few", "Few clouds"], ["scattered", "Scattered"], ["broken", "Broken"], ["overcast", "Overcast"]], Settings.get_value("weather"))
	var wb := VBoxContainer.new()
	wb.add_theme_constant_override("separation", 7)
	fb.add_child(wb)
	_section(wb, "Wind")
	_seg(wb, "wind", [["calm", "Calm"], ["breezy", "Breezy"]], Settings.get_value("wind"))
	# ---- bottom right: launch panel
	var go := PanelContainer.new()
	go.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	go.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	go.grow_vertical = Control.GROW_DIRECTION_BEGIN
	go.offset_right = -30
	go.offset_bottom = -30
	go.custom_minimum_size = Vector2(470, 0)
	menu.add_child(go)
	var gv := VBoxContainer.new()
	gv.add_theme_constant_override("separation", 10)
	go.add_child(gv)
	launch_title = _lbl("", 30, Color.WHITE, true)
	gv.add_child(launch_title)
	launch_sum = _lbl("", 15, MUTED)
	launch_sum.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	launch_sum.custom_minimum_size = Vector2(430, 0)
	gv.add_child(launch_sum)
	var fly := _big_button("Fly", true)
	fly.custom_minimum_size = Vector2(0, 64)
	fly.add_theme_font_size_override("font_size", 32)
	fly.pressed.connect(func(): fly_pressed.emit(false))
	gv.add_child(fly)
	fly_btn = fly
	vr_btn = _big_button("Play in VR (Meta Quest)", false)
	vr_btn.add_theme_font_size_override("font_size", 20)
	vr_btn.custom_minimum_size = Vector2(0, 46)
	vr_btn.pressed.connect(func():
		if in_vr:
			vr_action.emit("exit")
		else:
			fly_pressed.emit(true))
	gv.add_child(vr_btn)
	vr_note = _lbl("", 14, Color("#ffb347"))
	vr_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vr_note.custom_minimum_size = Vector2(430, 0)
	vr_note.visible = false
	gv.add_child(vr_note)
	# ---- bottom left: how the simulator is set up, help, graphics card
	var foot := VBoxContainer.new()
	foot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	foot.offset_left = 30
	foot.offset_bottom = -22
	foot.add_theme_constant_override("separation", 6)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(foot)
	var rr := HBoxContainer.new()
	rr.add_theme_constant_override("separation", 8)
	foot.add_child(rr)
	rig_label = _lbl("", 14, INK)
	rr.add_child(rig_label)
	var chg := Button.new()
	chg.text = "Change setup"
	chg.add_theme_font_size_override("font_size", 14)
	chg.pressed.connect(func(): show_lobby())
	rr.add_child(chg)
	setup_ctl_btn = Button.new()
	setup_ctl_btn.text = "Set up controls"
	setup_ctl_btn.add_theme_font_size_override("font_size", 14)
	setup_ctl_btn.pressed.connect(func(): open_sheet(controls_sheet))
	rr.add_child(setup_ctl_btn)
	var diag_btn := Button.new()
	diag_btn.text = "Copy diagnostics"
	diag_btn.tooltip_text = "Copies a report to paste to Claude if something doesn't work"
	diag_btn.add_theme_font_size_override("font_size", 14)
	diag_btn.pressed.connect(func(): diag_pressed.emit())
	rr.add_child(diag_btn)
	for fbtn in [chg, setup_ctl_btn, diag_btn]:
		fbtn.add_theme_stylebox_override("normal", _sb(Color(0.01, 0.01, 0.2, 0.6), 10, Color(1, 1, 1, 0.14), 1))
		fbtn.add_theme_color_override("font_color", INK)
	gpu_label = _lbl("", 12, INK)
	gpu_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gpu_label.custom_minimum_size = Vector2(700, 0)
	gpu_label.add_theme_color_override("font_outline_color", Color(0, 0, 0.1, 0.8))
	gpu_label.add_theme_constant_override("outline_size", 4)
	rig_label.add_theme_color_override("font_outline_color", Color(0, 0, 0.1, 0.8))
	rig_label.add_theme_constant_override("outline_size", 4)
	foot.add_child(gpu_label)
	setting_changed.connect(func(_k, _v): _refresh_summary.call_deferred())
	set_game(str(Settings.get_value("game")))
	set_rig(str(Settings.get_value("rig")))


func _rule() -> Control:
	var r := ColorRect.new()
	r.color = Color(1, 1, 1, 0.12)
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## The launch panel's line: what you've picked, in words ("Bulldog G-SMAT · on the runway · Midday, scattered cloud").
func _refresh_summary() -> void:
	if launch_sum == null:
		return
	var g := str(Settings.get_value("game"))
	var pick := func(key: String) -> String:
		for e in seg_buttons.get(key, []):
			if str(e[0]) == str(Settings.get_value(key)):
				return (e[1] as Button).text
		return ""
	var parts: Array = []
	var more: Array = []
	match g:
		"flight":
			parts = [pick.call("aircraft"), pick.call("start"), pick.call("mode"), pick.call("wind") + " wind"]
		"race":
			parts = [pick.call("race")]
		"space":
			parts = [pick.call("space_start"), pick.call("space_game")]
		"coaster":
			parts = ["1 km of track, 104 km/h, up to 3 g"]
	if g != "coaster":
		more.append(pick.call("assist"))
	if g != "space" or str(Settings.get_value("space_start")) == "earth":
		more.append("%s, %s" % [pick.call("tod"), pick.call("weather").to_lower()])
	launch_title.text = {"flight": "Ready to fly", "race": "Ready to race", "space": "Ready for launch", "coaster": "Ready to ride"}.get(g, "Ready")
	launch_sum.text = "  ·  ".join(parts) + ("\n" + "  ·  ".join(more) if not more.is_empty() else "")


## Shows the options for the chosen game (Flight, Racing or Space).
func set_game(g: String) -> void:
	if not GAMES.has(g):
		g = "flight"
	title_b.text = GAMES[g][0]
	subtitle.text = GAMES[g][1]
	fly_btn.text = GAMES[g][2]
	for k in mode_boxes.keys():
		(mode_boxes[k] as Control).visible = k == g
	style_cap.text = {"flight": "FLYING STYLE", "race": "DRIVING STYLE", "space": "DIFFICULTY", "coaster": ""}[g]
	style_cap.visible = g != "coaster"
	for e in seg_buttons.get("assist", []):
		(e[1] as Button).get_parent().visible = g != "coaster"
	tod_box.visible = g != "space" or str(Settings.get_value("space_start")) == "earth"
	if again_btn != null:
		again_btn.text = {"flight": "Fly again", "race": "Race again", "space": "Play again", "coaster": "Ride again"}[g]
	if cap_speed != null:
		set_hud_kind(g)
	_refresh_summary()


## The speed, height and heading boxes show different things in each game.
func set_hud_kind(g: String) -> void:
	cap_speed.text = {"flight": "KNOTS", "race": "KM/H", "space": "M/S", "ship": "M/S", "coaster": "KM/H"}.get(g, "KNOTS")
	cap_alt.text = {"flight": "FEET", "race": "GEAR", "space": "SCORE", "ship": "ALTITUDE", "coaster": "METRES UP"}.get(g, "FEET")
	cap_hdg.text = {"flight": "HEADING", "race": "LAP", "space": "WAVE", "ship": "HEADING", "coaster": "FORCE"}.get(g, "HEADING")
	tag_brake.text = "FIRE" if g == "space" else ("" if g == "ship" else "BRAKE")
	arrow.visible = g == "flight" or g == "space" or g == "ship"
	gate_box.visible = g != "flight"


## Shows only the games that suit how the simulator is set up.
func set_rig(rig: String) -> void:
	if not RIGS.has(rig):
		rig = "all"
	var allowed: Array = RIG_GAMES[rig]
	for e in seg_buttons.get("game", []):
		(e[1] as Button).visible = e[0] in allowed
	rig_label.text = "Simulator set up for:  " + RIGS[rig][0]
	setup_ctl_btn.visible = rig == "stick" or rig == "wheel"
	for e in seg_buttons.get("rig", []):
		(e[1] as Button).set_pressed_no_signal(e[0] == rig)


func show_lobby() -> void:
	loading.visible = false
	lobby.visible = true
	var cur := str(Settings.get_value("rig"))
	for e in seg_buttons.get("rig", []):
		(e[1] as Button).set_pressed_no_signal(e[0] == cur)
		if e[0] == cur:
			(e[1] as Button).grab_focus.call_deferred()


func _build_lobby() -> void:
	lobby = ColorRect.new()
	(lobby as ColorRect).color = Color(0.004, 0.004, 0.13, 0.985)
	lobby.set_anchors_preset(Control.PRESET_FULL_RECT)
	lobby.visible = false
	root.add_child(lobby)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	lobby.add_child(c)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	c.add_child(v)
	var lg := TextureRect.new()
	lg.texture = logo_dark
	lg.custom_minimum_size = Vector2(240, 90)
	lg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	v.add_child(lg)
	v.add_child(_lbl("How is the simulator set up?", 46, Color.WHITE, true, HORIZONTAL_ALIGNMENT_CENTER))
	var sub := _lbl("Pick what's fitted to the SmartMotion simulator today. You'll then see the games that suit it.", 17, MUTED, false, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(sub)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	seg_buttons["rig"] = []
	for k in ["stick", "wheel", "ride", "all"]:
		var info: Array = RIGS[k]
		var b := Button.new()
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(300, 230)
		b.add_theme_stylebox_override("normal", _sb(Color(1, 1, 1, 0.07), 20, Color(1, 1, 1, 0.18), 1))
		b.add_theme_stylebox_override("hover", _sb(Color(1, 1, 1, 0.14), 20, ORANGE, 2))
		b.add_theme_stylebox_override("pressed", _sb(Color(1, 0.3, 0.0, 0.25), 20, ORANGE, 3))
		b.add_theme_stylebox_override("hover_pressed", _sb(Color(1, 0.3, 0.0, 0.32), 20, ORANGE, 3))
		b.add_theme_stylebox_override("focus", _sb(Color(0, 0, 0, 0), 20, Color.WHITE, 2))
		var bv := VBoxContainer.new()
		bv.set_anchors_preset(Control.PRESET_FULL_RECT)
		bv.offset_left = 20
		bv.offset_right = -20
		bv.offset_top = 22
		bv.offset_bottom = -18
		bv.add_theme_constant_override("separation", 10)
		bv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(bv)
		var t := _lbl(info[0], 32, Color.WHITE, true)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bv.add_child(t)
		var gl := _lbl(info[1], 21, ORANGE, true)
		gl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bv.add_child(gl)
		var d := _lbl(info[2], 15, MUTED)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(250, 0)
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bv.add_child(d)
		b.pressed.connect(func():
			lobby.visible = false
			setting_changed.emit("rig", k))
		row.add_child(b)
		seg_buttons["rig"].append([k, b])


## The "Set up controls" sheet: one row per control with a live bar and a Set button (learns the axis).
func set_control_actions(actions: Array) -> void:
	for ch in ctl_rows.get_children():
		ch.queue_free()
	ctl_widgets = {}
	for a in actions:
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 8)
		var nm := _lbl(a[1], 15, INK)
		nm.custom_minimum_size = Vector2(190, 0)
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		r.add_child(nm)
		var st := _lbl("", 13, MUTED)
		st.custom_minimum_size = Vector2(130, 0)
		r.add_child(st)
		var bar := ProgressBar.new()
		bar.min_value = -1.0
		bar.max_value = 1.0
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(110, 10)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(bar)
		var b := Button.new()
		b.text = "Set"
		var act: String = a[0]
		b.pressed.connect(func(): learn_pressed.emit(act))
		r.add_child(b)
		ctl_rows.add_child(r)
		ctl_widgets[act] = [st, bar]


func set_control_row(action: String, status: String, value: float) -> void:
	if not ctl_widgets.has(action):
		return
	(ctl_widgets[action][0] as Label).text = status
	(ctl_widgets[action][1] as ProgressBar).value = value


func set_vr(on: bool, hz_text := "") -> void:
	in_vr = on
	vr_btn.text = "Leave VR" if on else "Play in VR (Meta Quest)"
	vr_box.visible = on
	if hz_text != "":
		vr_hz_btn.text = hz_text


func set_vr_note(t: String) -> void:
	vr_note.text = t
	vr_note.visible = t != ""


func set_gpu_text(t: String) -> void:
	gpu_label.text = t


# ------------------------------------------------------------ hud
func _build_hud() -> void:
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud)
	var lg := TextureRect.new()
	lg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	lg.texture = logo_dark
	hud.add_child(lg)
	lg.position = Vector2(16, 12)
	lg.size = Vector2(130, 52)
	# heading, top centre
	var top := CenterContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 10
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(top)
	var hp := _glass(top)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", -4)
	hp.add_child(hv)
	l_hdg = _lbl("062°", 34, Color.WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
	hv.add_child(l_hdg)
	cap_hdg = _lbl("HEADING", 11, MUTED, false, HORIZONTAL_ALIGNMENT_CENTER)
	hv.add_child(cap_hdg)
	# speed, bottom left
	var sp := _glass(hud)
	sp.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	sp.offset_left = 16
	sp.offset_bottom = -16
	sp.offset_top = -150
	sp.offset_right = 240
	sp.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 0)
	sp.add_child(sv)
	l_speed = _lbl("0", 50, Color.WHITE, true)
	sv.add_child(l_speed)
	cap_speed = _lbl("KNOTS", 11, MUTED)
	sv.add_child(cap_speed)
	thr_bar = ProgressBar.new()
	thr_bar.custom_minimum_size = Vector2(0, 8)
	thr_bar.show_percentage = false
	thr_bar.max_value = 1.0
	sv.add_child(thr_bar)
	var tags := HBoxContainer.new()
	tags.add_theme_constant_override("separation", 6)
	tag_flaps = _lbl("FLAPS 0%", 11, MUTED)
	tag_brake = _lbl("BRAKE", 11, MUTED)
	tag_assist = _lbl("EASY", 11, ORANGE)
	tags.add_child(tag_flaps)
	tags.add_child(tag_brake)
	tags.add_child(tag_assist)
	sv.add_child(tags)
	# altitude, bottom right
	var ap := _glass(hud)
	ap.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ap.offset_right = -16
	ap.offset_bottom = -16
	ap.offset_left = -240
	ap.offset_top = -130
	ap.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ap.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var av := VBoxContainer.new()
	av.add_theme_constant_override("separation", 0)
	ap.add_child(av)
	l_alt = _lbl("0", 50, Color.WHITE, true, HORIZONTAL_ALIGNMENT_RIGHT)
	av.add_child(l_alt)
	cap_alt = _lbl("FEET", 11, MUTED, false, HORIZONTAL_ALIGNMENT_RIGHT)
	av.add_child(cap_alt)
	l_vs = _lbl("0 FT/MIN", 13, MUTED, false, HORIZONTAL_ALIGNMENT_RIGHT)
	av.add_child(l_vs)
	# artificial horizon, bottom centre
	adi = Instruments.new()
	adi.adi_only = true
	adi.custom_minimum_size = Vector2(120, 120)
	adi.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	adi.offset_left = -60
	adi.offset_right = 60
	adi.offset_top = -136
	adi.offset_bottom = -16
	adi.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(adi)
	# message and toast
	msg_label = _lbl("", 46, Color.WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
	msg_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	msg_label.offset_left = -300
	msg_label.offset_right = 300
	msg_label.offset_top = 150
	msg_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	msg_label.add_theme_constant_override("outline_size", 8)
	hud.add_child(msg_label)
	toast_label = _lbl("", 18, NAVY, false, HORIZONTAL_ALIGNMENT_CENTER)
	toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_label.offset_left = -330
	toast_label.offset_right = 330
	toast_label.offset_top = 76
	toast_label.add_theme_stylebox_override("normal", _sb(Color("#fff3ea"), 20))
	hud.add_child(toast_label)
	toast_label.visible = false
	# gate box
	gate_box = _glass(hud)
	gate_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	gate_box.offset_left = -110
	gate_box.offset_right = 110
	gate_box.offset_top = 90
	var gh := HBoxContainer.new()
	gh.add_theme_constant_override("separation", 12)
	gate_box.add_child(gh)
	arrow = Control.new()
	arrow.custom_minimum_size = Vector2(36, 36)
	arrow.draw.connect(_draw_arrow)
	gh.add_child(arrow)
	var gv := VBoxContainer.new()
	gv.add_theme_constant_override("separation", -2)
	gh.add_child(gv)
	l_gate = _lbl("Gate 1/11", 26, Color.WHITE, true)
	l_gate_t = _lbl("0:00.0", 14, MUTED)
	gv.add_child(l_gate)
	gv.add_child(l_gate_t)
	gate_box.visible = false
	# telemetry panel
	tel_panel = _glass(hud)
	tel_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tel_panel.offset_left = -270
	tel_panel.offset_right = -16
	tel_panel.offset_top = 16
	tel_label = _lbl("", 13, INK)
	tel_panel.add_child(tel_label)
	tel_panel.visible = false


var arrow_angle := 0.0

func _draw_arrow() -> void:
	var c := Vector2(18, 18)
	var a := deg_to_rad(arrow_angle)
	var pts := PackedVector2Array()
	for p in [Vector2(0, -16), Vector2(12, 14), Vector2(0, 7), Vector2(-12, 14)]:
		pts.append(c + p.rotated(a))
	arrow.draw_colored_polygon(pts, ORANGE)


# ------------------------------------------------------------ sheets
func _sheet(title: String, width := 520.0) -> Array:
	var s := ColorRect.new()
	s.color = Color(0.004, 0.004, 0.11, 0.62)
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	s.visible = false
	root.add_child(s)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	s.add_child(c)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(width, 0)
	if width > 600.0:
		# the wide screens (Controls, Change keys) cover most of the menu: nearly solid, so it doesn't show through
		p.add_theme_stylebox_override("panel", _sb(Color(0.012, 0.012, 0.15, 0.97), 22, Color(1, 1, 1, 0.16), 1))
	c.add_child(p)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 0)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(sc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	v.add_child(_lbl(title, 34, Color.WHITE, true))
	fit[s] = [sc, v, width]
	return [s, v]


func _build_sheets() -> void:
	var r := _sheet("Paused")
	pause_sheet = r[0]
	var v: VBoxContainer = r[1]
	var res := _big_button("Resume", true)
	res.pressed.connect(func(): resume_pressed.emit())
	v.add_child(res)
	for e in [["Restart", func(): restart_pressed.emit()], ["Controls", func(): open_sheet(help_sheet)], ["Settings", func(): open_sheet(settings_sheet)], ["Back to menu", func(): menu_pressed.emit()]]:
		var b := Button.new()
		b.text = e[0]
		b.custom_minimum_size = Vector2(0, 42)
		b.pressed.connect(e[1])
		v.add_child(b)
	# VR only: recentre, headset refresh rate, leave VR
	vr_box = VBoxContainer.new()
	vr_box.add_theme_constant_override("separation", 8)
	vr_box.visible = false
	v.add_child(vr_box)
	_section(vr_box, "VR")
	for e in [["Recentre my view", "recentre"], ["Headset", "hz"], ["Leave VR", "exit"]]:
		var b := Button.new()
		b.text = e[0]
		b.custom_minimum_size = Vector2(0, 42)
		var what: String = e[1]
		b.pressed.connect(func(): vr_action.emit(what))
		vr_box.add_child(b)
		if what == "hz":
			vr_hz_btn = b
	r = _sheet("Flight over")
	end_sheet = r[0]
	v = r[1]
	end_lab = _lbl("", 13, ORANGE)
	v.add_child(end_lab)
	end_big = _lbl("", 54, Color.WHITE, true)
	v.add_child(end_big)
	end_text = _lbl("", 16, MUTED)
	end_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	end_text.custom_minimum_size = Vector2(460, 0)
	v.add_child(end_text)
	var again := _big_button("Fly again", true)
	again_btn = again
	again.pressed.connect(func(): restart_pressed.emit())
	v.add_child(again)
	var mb := Button.new()
	mb.text = "Back to menu"
	mb.custom_minimum_size = Vector2(0, 42)
	mb.pressed.connect(func(): menu_pressed.emit())
	v.add_child(mb)
	end_title = (v.get_child(0) as Label)
	r = _sheet("Controls", 1030.0)
	help_sheet = r[0]
	v = r[1]
	_build_help(v)
	var cred := _lbl("MAP DATA: Contains modified Copernicus Sentinel data 2023. Produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved. ESA WorldCover 2021 © ESA (CC BY 4.0). Buildings © OpenStreetMap contributors, Overture Maps Foundation (ODbL). Contains Environment Agency information © Environment Agency and/or database right 2026 (LIDAR heights, trees). Contains OS data © Crown copyright and database right 2026 (roads, water, buildings, built-up areas). Both under the Open Government Licence v3.0. Textures (ground, buildings and vehicles): ambientCG (CC0).", 11, MUTED)
	cred.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cred.custom_minimum_size = Vector2(990, 0)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	v.add_child(hb)
	var ck := _big_button("Change keys", false)
	ck.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ck.pressed.connect(func(): open_sheet(keys_sheet))
	hb.add_child(ck)
	var cl := _big_button("Got it", true)
	cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cl.pressed.connect(func(): close_sheet(help_sheet))
	hb.add_child(cl)
	v.add_child(cred)
	r = _sheet("Change keys", 860.0)
	keys_sheet = r[0]
	_build_keys(r[1])
	r = _sheet("Set up controls")
	controls_sheet = r[0]
	v = r[1]
	ctl_info = _lbl("Plug in the joystick or wheel, then press Set beside each control and move it as asked. Leave a control unset to use the keyboard or a gamepad for it.", 15, MUTED)
	ctl_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ctl_info.custom_minimum_size = Vector2(480, 0)
	v.add_child(ctl_info)
	ctl_rows = VBoxContainer.new()
	ctl_rows.add_theme_constant_override("separation", 6)
	v.add_child(ctl_rows)
	var cr := HBoxContainer.new()
	cr.add_theme_constant_override("separation", 6)
	var clr := Button.new()
	clr.text = "Clear all"
	clr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clr.pressed.connect(func(): learn_pressed.emit("clear"))
	cr.add_child(clr)
	v.add_child(cr)
	var cd := _big_button("Done", true)
	cd.pressed.connect(func(): close_sheet(controls_sheet))
	v.add_child(cd)
	r = _sheet("Settings")
	settings_sheet = r[0]
	v = r[1]
	_section(v, "Graphics quality (applies on the next start)")
	_seg(v, "quality", [["low", "Fast"], ["medium", "Balanced"], ["high", "Best"], ["ultra", "Ultra"]], Settings.get_value("quality"))
	_note(v, "Ultra: sharper shadows further out, more trees, buildings further away, reflections in water and windows, finer 3D clouds and more grass. Use it if Best runs smoothly; on battery or in VR, Best is safer.")
	_section(v, "Smooth edges and resolution")
	_seg(v, "aa", [["taa", "TAA"], ["smaa", "SMAA"], ["fsr_native", "FSR 2 Native"], ["fsr_quality", "FSR 2 Quality"], ["fsr_perf", "FSR 2 Fast"]], Settings.get_value("aa"))
	_note(v, "TAA: the standard, smooth picture. SMAA: sharper, a little more shimmer. FSR 2 Native: the smoothest edges at full resolution. FSR 2 Quality / Fast draw the 3D picture smaller and sharpen it back up: more frames per second for nearly the same picture. Not used in VR.")
	_section(v, "View distance (applies on the next start)")
	_seg(v, "view", [["near", "Near (fastest)"], ["normal", "Normal"], ["far", "Far"]], Settings.get_value("view"))
	_section(v, "3D clouds (the biggest cost on the screen; not used in VR)")
	_seg(v, "clouds3d", [[true, "On"], [false, "Off"]], Settings.get_value("clouds3d"))
	_section(v, "3D grass near the ground (Flight)")
	_seg(v, "grass", [[true, "On"], [false, "Off"]], Settings.get_value("grass"))
	_section(v, "Brightness")
	_seg(v, "brightness", [["dark", "Darker"], ["normal", "Normal"], ["bright", "Brighter"]], Settings.get_value("brightness"))
	_section(v, "V-Sync (off: more frames, but the picture may tear)")
	_seg(v, "vsync", [[true, "On"], [false, "Off"]], Settings.get_value("vsync"))
	_section(v, "Show frames per second")
	_seg(v, "show_fps", [[false, "Off"], [true, "On"]], Settings.get_value("show_fps"))
	_section(v, "Controls")
	var kb := Button.new()
	kb.text = "Change keys and buttons…"
	kb.custom_minimum_size = Vector2(0, 42)
	kb.pressed.connect(func(): open_sheet(keys_sheet))
	v.add_child(kb)
	_section(v, "Show the controls on screen while playing")
	_seg(v, "help_overlay", [[false, "Off"], [true, "On"]], Settings.get_value("help_overlay"))
	_note(v, "A small list of what each key does, at the side of the screen (in VR: beside the instrument panel). You can also switch it with the Help key while playing.")
	_section(v, "Sound")
	_seg(v, "sound", [[true, "On"], [false, "Off"]], Settings.get_value("sound"))
	_section(v, "Pitch control")
	_seg(v, "invert", [[false, "Pull back = nose up"], [true, "Inverted"]], Settings.get_value("invert"))
	_section(v, "Joystick left / right (roll; steering in Racing)")
	_seg(v, "invert_roll", [[false, "Normal"], [true, "Inverted"]], Settings.get_value("invert_roll"))
	_section(v, "Rudder pedals / twist (yaw)")
	_seg(v, "invert_yaw", [[false, "Normal"], [true, "Inverted"]], Settings.get_value("invert_yaw"))
	_section(v, "Full screen")
	_seg(v, "fullscreen", [[false, "Window"], [true, "Full screen"]], Settings.get_value("fullscreen"))
	_section(v, "Motion rig: send flight data (UDP, 60 times a second)")
	_seg(v, "tel", [[false, "Off"], [true, "On"]], Settings.get_value("tel"))
	var ar := HBoxContainer.new()
	ar.add_theme_constant_override("separation", 6)
	var host := LineEdit.new()
	host.text = str(Settings.get_value("tel_host"))
	host.placeholder_text = "address"
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.text_submitted.connect(func(t): setting_changed.emit("tel_host", t))
	host.focus_exited.connect(func(): setting_changed.emit("tel_host", host.text))
	ar.add_child(host)
	var port := LineEdit.new()
	port.text = str(Settings.get_value("tel_port"))
	port.custom_minimum_size = Vector2(90, 0)
	port.text_submitted.connect(func(t): setting_changed.emit("tel_port", int(t)))
	port.focus_exited.connect(func(): setting_changed.emit("tel_port", int(port.text)))
	ar.add_child(port)
	v.add_child(ar)
	_section(v, "FlyPT Mover: the game acts as X-Plane 11, so Mover's \"X-Plane 11 (UDP)\" source reads it")
	_seg(v, "flypt", [[true, "On"], [false, "Off"]], Settings.get_value("flypt"))
	var fr := HBoxContainer.new()
	fr.add_theme_constant_override("separation", 6)
	fr.add_child(_lbl("Answer on port", 13, MUTED))
	var lp := LineEdit.new()
	lp.text = str(Settings.get_value("flypt_port"))
	lp.custom_minimum_size = Vector2(80, 0)
	lp.text_submitted.connect(func(t): setting_changed.emit("flypt_port", int(t)))
	lp.focus_exited.connect(func(): setting_changed.emit("flypt_port", int(lp.text)))
	fr.add_child(lp)
	fr.add_child(_lbl("DATA rows to port", 13, MUTED))
	var op := LineEdit.new()
	op.text = str(Settings.get_value("flypt_out"))
	op.custom_minimum_size = Vector2(80, 0)
	op.text_submitted.connect(func(t): setting_changed.emit("flypt_out", int(t)))
	op.focus_exited.connect(func(): setting_changed.emit("flypt_out", int(op.text)))
	fr.add_child(op)
	v.add_child(fr)
	set_status = _lbl("", 13, MUTED)
	v.add_child(set_status)
	var sd := _big_button("Done", true)
	sd.pressed.connect(func(): close_sheet(settings_sheet))
	v.add_child(sd)


func _fit_sheet(s: Control) -> void:
	# a scroll container has no height of its own, so give it the height of its content (capped to the window)
	var pair: Array = fit[s]
	var sc: ScrollContainer = pair[0]
	var v: VBoxContainer = pair[1]
	var h := minf(v.get_combined_minimum_size().y + 44.0, maxf(get_viewport().get_visible_rect().size.y * 0.9, 300.0))
	sc.custom_minimum_size = Vector2(float(pair[2]) + 20.0, h)


func open_sheet(s: Control) -> void:
	for x in [pause_sheet, help_sheet, settings_sheet, controls_sheet, keys_sheet]:
		if x != s:
			(x as Control).visible = false
	if s == help_sheet:
		set_help_game(help_game)
	elif s == keys_sheet:
		refresh_binds()
	_fit_sheet(s)
	s.visible = true


func close_sheet(s: Control) -> void:
	s.visible = false
	if s == keys_sheet:
		_cap_end()
	if paused_ui:
		pause_sheet.visible = true

var paused_ui := false

func any_sheet() -> bool:
	return help_sheet.visible or settings_sheet.visible or pause_sheet.visible or end_sheet.visible or controls_sheet.visible or lobby.visible or keys_sheet.visible


## Esc (or the Pause key): closes the Controls, Settings or Change keys screen if one is open. True if it did.
func close_top_sheet() -> bool:
	for x in [keys_sheet, help_sheet, settings_sheet]:
		if (x as Control).visible:
			close_sheet(x)
			return true
	return false


func hide_sheets() -> void:
	for x in [pause_sheet, help_sheet, settings_sheet, end_sheet, controls_sheet, keys_sheet]:
		(x as Control).visible = false
	_cap_end()


# ------------------------------------------------------------ states
func show_menu() -> void:
	loading.visible = false
	hud.visible = false
	hide_sheets()
	menu.visible = true


## The speed and height boxes in the bottom corners (hidden in the Bulldog's cockpit, where the real gauges show it).
func set_corner_boxes(on: bool) -> void:
	for l in [l_speed, l_alt]:
		if l != null and l.get_parent() != null and l.get_parent().get_parent() != null:
			(l.get_parent().get_parent() as Control).visible = on


func show_hud() -> void:
	loading.visible = false
	menu.visible = false
	hide_sheets()
	hud.visible = true


func show_pause(on: bool) -> void:
	paused_ui = on
	if on:
		_fit_sheet(pause_sheet)
	pause_sheet.visible = on
	if not on:
		help_sheet.visible = false
		settings_sheet.visible = false
		keys_sheet.visible = false
		_cap_end()


func show_end(title: String, label: String, text: String, big: String) -> void:
	end_title.text = title
	end_lab.text = label.to_upper()
	end_text.text = text
	end_big.text = big
	end_big.visible = big != ""
	_fit_sheet(end_sheet)
	end_sheet.visible = true


func toast(t: String, secs := 2.2) -> void:
	toast_label.text = t
	toast_label.visible = true
	toast_t = secs


func _process(delta: float) -> void:
	if toast_t > 0.0:
		toast_t -= delta
		if toast_t <= 0.0:
			toast_label.visible = false
	_cap_poll()
	if fps_label != null and fps_label.visible:
		fps_t -= delta
		if fps_t <= 0.0:
			fps_t = 0.5
			var f := Engine.get_frames_per_second()
			fps_label.text = "%d fps" % f
			fps_label.add_theme_color_override("font_color", Color("#7ee08a") if f >= 55 else (Color("#ffb347") if f >= 40 else Color("#ff5a4f")))


## Frames-per-second counter in the top-right corner (setting "Show frames per second").
func show_fps(on: bool) -> void:
	if fps_label == null:
		fps_label = _lbl("", 16, Color.WHITE, true)
		fps_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		fps_label.offset_left = -110
		fps_label.offset_right = -14
		fps_label.offset_top = 8
		fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fps_label.z_index = 50
		root.add_child(fps_label)
	fps_label.visible = on


func set_message(t: String, warn: bool) -> void:
	msg_label.text = t
	msg_label.add_theme_color_override("font_color", Color("#ff5a4f") if warn else Color.WHITE)
	msg_label.visible = t != ""


# ------------------------------------------------------------ controls: picture, change keys, on-screen list (v1.19.0)
const HELP_GAMES := [["flight", "Flight"], ["race", "Racing"], ["space", "Spaceship"]]

## What the gamepad and the VR controllers do in each game: [button or stick, what it does]. The gamepad's
## buttons that can be changed are filled in from Keys.
const PAD_FIXED := {
	"flight": [["Right stick", "Nose up / down and bank"], ["Left stick", "Power (up / down) and rudder"], ["Left trigger", "Wheel brakes"]],
	"race": [["Left stick", "Steer"], ["Right trigger", "Accelerate"], ["Left trigger", "Brake"]],
	"space": [["Right stick", "Nose up / down and roll"], ["Left stick", "Speed and yaw"], ["Right trigger", "Fire"], ["Left trigger", "Boost"]],
}
const VR_HELP := {
	"flight": [["Right stick", "Nose up / down and bank"], ["Right trigger / grip", "More / less power"], ["Left stick", "Power and rudder"],
		["Left grip + left stick", "Trim nose down / up"], ["Left trigger", "Wheel brakes"], ["A", "Flaps"], ["B", "Recentre the view"], ["X", "Menu (pause)"], ["Y", "Restart"]],
	"race": [["Either stick", "Steer"], ["Right trigger", "Accelerate"], ["Left trigger", "Brake"], ["B", "Recentre the view"], ["X", "Menu (pause)"], ["Y", "Restart"]],
	"space": [["Right grip + point", "Fly where you point"], ["Right stick", "Nose up / down and roll"], ["Left stick", "Speed and yaw"], ["Right trigger", "Fire"], ["Left trigger", "Boost"],
		["A", "x10 speed"], ["Right stick click", "Hyperspeed"], ["Left stick click", "Next planet"], ["B", "Recentre"], ["X", "Menu"], ["Y", "Restart"]],
}
const HELP_TIPS := {
	"flight": "Easy mode sets full power on the runway and keeps the wings level for you: just pull the nose up at the speed shown. Trim saves you holding the stick: in Easy it sets a steady climb or descent, in Pro it moves the elevator like the real trim wheel (watch the wheel on the centre console turn). Right mouse + drag looks round the cockpit; the mouse wheel zooms the outside view.",
	"race": "Easy has traction control, anti-lock brakes and stability control; Pro has none of them. Hold the brake when stopped to reverse.",
	"space": "Look at a planet and press Hyperspeed to go there. On the runway, push the speed up to lift off; climb above 20 km to reach space, and fly down to the Earth to come back. In VR your hands show as small balls: touch the console buttons with them. The left mouse button also fires.",
}
## The list shown while playing: pairs of actions on one line
const OVERLAY := {
	"flight": [[["pitch_down", "pitch_up"], "Nose down / up"], [["roll_left", "roll_right"], "Bank left / right"], [["yaw_left", "yaw_right"], "Rudder left / right"],
		[["thr_up", "thr_down"], "Power more / less"], [["trim_down", "trim_up"], "Trim nose down / up"], [["flaps"], "Flaps"], [["brake"], "Wheel brakes"],
		[["camera"], "Change camera"], [["pause"], "Pause"], [["restart"], "Restart"]],
	"race": [[["steer_left", "steer_right"], "Steer left / right"], [["accel"], "Accelerate"], [["race_brake"], "Brake / reverse"], [["camera"], "Change camera"], [["pause"], "Pause"], [["restart"], "Restart"]],
	"space": [[["pitch_down", "pitch_up"], "Nose down / up"], [["roll_left", "roll_right"], "Roll left / right"], [["yaw_left", "yaw_right"], "Yaw left / right"],
		[["thr_up", "thr_down"], "Speed more / less"], [["fire"], "Fire"], [["boost"], "Boost"], [["hyper"], "Hyperspeed"], [["x10"], "x10 speed"], [["prev", "next"], "Choose the planet"],
		[["auto"], "To space / to Earth"], [["land"], "Land / lift off"], [["camera"], "Change camera"], [["pause"], "Pause"]],
	"coaster": [[["camera"], "Change camera"], [["pause"], "Pause"], [["restart"], "Restart"]],
}


## A key cap: a small rounded box with the key's name on it.
func _chip(text: String, col := Color(1, 1, 1, 0.14), size := 13) -> Label:
	var l := _lbl(text, size, Color.WHITE)
	l.add_theme_font_override("font", theme_res.get_font("font", "Button"))
	var sb := _sb(col, 6, Color(1, 1, 1, 0.3), 1)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 1
	sb.content_margin_bottom = 2
	l.add_theme_stylebox_override("normal", sb)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


func _help_row(parent: Control, chips: Array, text: String, col := Color(1, 1, 1, 0.14), size := 13) -> void:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 4)
	for c in chips:
		r.add_child(_chip(str(c), col, size))
	var t := _lbl(text, size + 1, INK)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(_lbl(" ", size))
	r.add_child(t)
	parent.add_child(r)


func _build_help(v: VBoxContainer) -> void:
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	v.add_child(tabs)
	var group := ButtonGroup.new()
	for g in HELP_GAMES:
		var b := Button.new()
		b.text = g[1]
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(150, 40)
		var key: String = g[0]
		b.pressed.connect(func(): set_help_game(key))
		tabs.add_child(b)
		help_tabs[key] = b
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(sp)
	for e in [[KeyboardPic.COL_MOVE, "Steering"], [KeyboardPic.COL_GAME, "This game"], [KeyboardPic.COL_ALL, "Every game"]]:
		var sw := ColorRect.new()
		sw.color = e[0]
		sw.custom_minimum_size = Vector2(14, 14)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tabs.add_child(sw)
		tabs.add_child(_lbl(str(e[1]) + "   ", 13, MUTED))
	help_pic = KeyboardPic.new()
	v.add_child(help_pic)
	help_cards = HBoxContainer.new()
	help_cards.add_theme_constant_override("separation", 10)
	v.add_child(help_cards)
	help_tip = _lbl("", 14, MUTED)
	help_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_tip.custom_minimum_size = Vector2(990, 0)
	v.add_child(help_tip)


## The Controls screen for one game: the keyboard picture, then the gamepad and VR controllers.
func set_help_game(g: String) -> void:
	if not help_tabs.has(g):
		g = "flight"
	help_game = g
	for k in help_tabs.keys():
		(help_tabs[k] as Button).set_pressed_no_signal(k == g)
	help_pic.set_game(g)
	for ch in help_cards.get_children():
		help_cards.remove_child(ch)
		ch.queue_free()
	var pad: Array = PAD_FIXED[g].duplicate()
	for a in Keys.ACTIONS:
		var b := Keys.button_of(a[0])
		if Keys.uses(a[0], g) and not b.is_empty():
			pad.append([Keys.button_name(b), Keys.title(a[0]).split(" (")[0]])
	for card in [["GAMEPAD", pad, Color("#2f9e44")], ["VR CONTROLLERS (META QUEST)", VR_HELP[g], Color("#7a4dd8")]]:
		var p := _glass(help_cards)
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 4)
		p.add_child(cv)
		cv.add_child(_lbl(card[0], 12, MUTED))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 14)
		grid.add_theme_constant_override("v_separation", 4)
		cv.add_child(grid)
		for e in card[1]:
			var cell := VBoxContainer.new()
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(cell)
			_help_row(cell, [e[0]], str(e[1]), Color(card[2], 0.55))
	help_tip.text = HELP_TIPS[g] + "  A simulator joystick, wheel or pedals: see Set up controls on the first screen."
	if help_sheet.visible:
		_fit_sheet(help_sheet)


func _build_keys(v: VBoxContainer) -> void:
	keys_info = _lbl("", 15, MUTED)
	keys_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	keys_info.custom_minimum_size = Vector2(820, 0)
	v.add_child(keys_info)
	_keys_msg("")
	var hd := HBoxContainer.new()
	hd.add_theme_constant_override("separation", 6)
	var h0 := _lbl("", 12, MUTED)
	h0.custom_minimum_size = Vector2(330, 0)
	hd.add_child(h0)
	for t in ["KEY", "SECOND KEY", "GAMEPAD / JOYSTICK BUTTON"]:
		var hl := _lbl(t, 12, MUTED, false, HORIZONTAL_ALIGNMENT_CENTER)
		hl.custom_minimum_size = Vector2(150, 0)
		hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hd.add_child(hl)
	v.add_child(hd)
	for g in Keys.GROUP_ORDER:
		_section(v, Keys.GROUP_TITLES[g])
		for id in Keys.ids_in(g):
			var r := HBoxContainer.new()
			r.add_theme_constant_override("separation", 6)
			var nm := _lbl(Keys.title(id), 15, INK)
			nm.custom_minimum_size = Vector2(330, 0)
			r.add_child(nm)
			bind_btns[id] = []
			for slot in [0, 1, "b"]:
				var b := Button.new()
				b.custom_minimum_size = Vector2(150, 34)
				b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				b.clip_text = true
				var act: String = id
				var sl = slot
				b.pressed.connect(func(): _cap_start(act, sl))
				r.add_child(b)
				bind_btns[id].append(b)
			v.add_child(r)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	var rs := _big_button("Back to the standard keys", false)
	rs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rs.pressed.connect(func():
		_cap_end()
		Keys.reset_all()
		_keys_msg("All keys and buttons are back to the standard ones.")
		_binds_done())
	row.add_child(rs)
	var dn := _big_button("Done", true)
	dn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dn.pressed.connect(func(): close_sheet(keys_sheet))
	row.add_child(dn)
	refresh_binds()


func _keys_msg(t: String) -> void:
	keys_info.text = (t + "\n" if t != "" else "") + "Each control can have two keys and one controller button (gamepad or joystick). Click a box, then press the key or button you want. Esc leaves it as it was; Backspace empties the box. Sticks, wheels and pedals are set in Set up controls on the first screen."


func refresh_binds() -> void:
	for id in bind_btns.keys():
		var ks := Keys.keys_of(id)
		for i in 2:
			var b: Button = bind_btns[id][i]
			b.text = Keys.key_name(ks[i]) if ks[i] != 0 else "—"
		var bb: Button = bind_btns[id][2]
		var bt := Keys.button_of(id)
		bb.text = Keys.button_name(bt) if not bt.is_empty() else "—"
	if not cap.is_empty():
		var cb: Button = bind_btns[cap["id"]][2 if str(cap["slot"]) == "b" else int(cap["slot"])]
		cb.text = "Press a button…" if str(cap["slot"]) == "b" else "Press a key…"


func capturing() -> bool:
	return not cap.is_empty()


func _cap_start(id: String, slot) -> void:
	var held := {}
	for dev in Input.get_connected_joypads():
		for b in 64:
			if Input.is_joy_button_pressed(dev, b):
				held[Vector2i(dev, b)] = true
	cap = {"id": id, "slot": slot, "held": held}
	if str(slot) == "b":
		_keys_msg("%s: press the button you want on the gamepad or joystick (Esc: leave it, Backspace: no button)." % Keys.title(id))
		if Input.get_connected_joypads().is_empty():
			_keys_msg("No gamepad or joystick found. Plug it in (USB), wait a few seconds and click the box again.")
	else:
		_keys_msg("%s: press the key you want (Esc: leave it, Backspace: no key)." % Keys.title(id))
	refresh_binds()


func _cap_end() -> void:
	if cap.is_empty():
		return
	cap = {}
	refresh_binds()


func _binds_done() -> void:
	refresh_binds()
	if help_pic != null:
		help_pic.queue_redraw()
	set_overlay_game(overlay_game)
	binds_changed.emit()


## A key pressed while a box in Change keys is waiting (sent here by main.gd, which sees the keyboard in VR too).
func capture_key(code: int) -> void:
	if cap.is_empty():
		return
	var id: String = cap["id"]
	var slot = cap["slot"]
	if code == KEY_ESCAPE:
		_keys_msg("")
		_cap_end()
		return
	var taken: Array = []
	if code == KEY_BACKSPACE or code == KEY_DELETE:
		if str(slot) == "b":
			Keys.set_button(id, -1, "")
		else:
			Keys.set_key(id, int(slot), 0)
		_keys_msg("%s: box emptied." % Keys.title(id))
	elif str(slot) == "b":
		return   # waiting for a controller button, not a key
	elif code in Keys.RESERVED or code == 0:
		_keys_msg("%s works the menus, so it can't be used. Press another key." % Keys.key_name(code))
		return
	else:
		taken = Keys.set_key(id, int(slot), code)
		_keys_msg("%s is now %s." % [Keys.title(id), Keys.key_name(code)] + ((" (It was taken away from: %s.)" % ", ".join(taken)) if not taken.is_empty() else ""))
	cap = {}
	_binds_done()


## While a controller box is waiting: the first button newly pressed on any gamepad or joystick.
func _cap_poll() -> void:
	if cap.is_empty() or str(cap["slot"]) != "b":
		return
	var held: Dictionary = cap["held"]
	for dev in Input.get_connected_joypads():
		for b in 64:
			var k := Vector2i(dev, b)
			var dn := Input.is_joy_button_pressed(dev, b)
			if not dn:
				held.erase(k)
			elif not held.has(k):
				var id: String = cap["id"]
				var taken: Array = Keys.set_button(id, b, Input.get_joy_name(dev))
				_keys_msg("%s is now button %d on %s." % [Keys.title(id), b + 1, Input.get_joy_name(dev)] + ((" (It was taken away from: %s.)" % ", ".join(taken)) if not taken.is_empty() else ""))
				cap = {}
				_binds_done()
				return


## The lines of the on-screen list for a game: [[key names], what they do].
func overlay_lines(g: String) -> Array:
	var out: Array = []
	for e in OVERLAY.get(g, OVERLAY["flight"]):
		var chips: Array = []
		for id in e[0]:
			chips.append(Keys.first(id))
		out.append([chips, e[1]])
	return out


func _build_overlay() -> void:
	var side := VBoxContainer.new()   # keeps the list half way up the left edge whatever its size
	side.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	side.offset_left = 16
	side.offset_right = 380
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(side)
	overlay = _glass(side)
	overlay.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_rows = VBoxContainer.new()
	overlay_rows.add_theme_constant_override("separation", 3)
	overlay_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(overlay_rows)
	overlay.visible = false
	f1_hint = _lbl("", 12, Color(1, 1, 1, 0.7))
	f1_hint.position = Vector2(20, 66)
	f1_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	f1_hint.add_theme_constant_override("outline_size", 4)
	hud.add_child(f1_hint)
	set_overlay_game("flight")


## Which game's controls the on-screen list shows (rebuilt when the game or a key changes).
func set_overlay_game(g: String) -> void:
	overlay_game = g
	if overlay_rows == null:
		return
	for ch in overlay_rows.get_children():
		overlay_rows.remove_child(ch)
		ch.queue_free()
	overlay_rows.add_child(_lbl("CONTROLS", 12, MUTED))
	for e in overlay_lines(g):
		_help_row(overlay_rows, e[0], str(e[1]), Color(1, 1, 1, 0.14), 12)
	if g != "coaster":
		_help_row(overlay_rows, ["Right mouse"], "Hold and drag: look round", Color(1, 1, 1, 0.14), 12)
	overlay_rows.add_child(_lbl("%s hides this list" % Keys.first("help"), 11, MUTED))
	f1_hint.text = "%s: show the controls" % Keys.first("help")


func show_overlay(on: bool) -> void:
	if overlay != null:
		overlay.visible = on
		f1_hint.visible = not on
