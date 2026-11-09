class_name GameUI
extends CanvasLayer
## Menus and heads-up display in SmartMotion colours.

signal fly_pressed(vr: bool)
signal resume_pressed
signal restart_pressed
signal menu_pressed
signal setting_changed(key: String, value)

const NAVY := Color("#02022f")
const ORANGE := Color("#ff4c00")
const INK := Color("#eceef8")
const MUTED := Color("#a9acd0")

var theme_res := Theme.new()
var root := Control.new()
var loading: Control
var load_bar: ProgressBar
var load_msg: Label
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
var fit := {}   # sheet -> [scroll container, content]


func _ready() -> void:
	logo_dark = load("res://assets/logo-dark.png")
	ital = load("res://assets/fonts/BarlowSemiCondensed-ExtraBoldItalic.ttf")
	_build_theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = theme_res
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_hud()
	_build_menu()
	_build_sheets()
	_build_loading()
	show_loading()


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


func set_seg(key: String, value) -> void:
	for e in seg_buttons.get(key, []):
		(e[1] as Button).set_pressed_no_signal(str(e[0]) == str(value))


# ------------------------------------------------------------ loading
func _build_loading() -> void:
	loading = ColorRect.new()
	(loading as ColorRect).color = NAVY
	loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(loading)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	loading.add_child(c)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	c.add_child(v)
	var lg := TextureRect.new()
	lg.texture = logo_dark
	lg.custom_minimum_size = Vector2(300, 120)
	lg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	v.add_child(lg)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(_lbl("Smart", 60, Color.WHITE, true))
	h.add_child(_lbl("Flight", 60, ORANGE, true))
	v.add_child(h)
	load_bar = ProgressBar.new()
	load_bar.custom_minimum_size = Vector2(360, 10)
	load_bar.show_percentage = false
	load_bar.max_value = 1.0
	v.add_child(load_bar)
	load_msg = _lbl("Starting up…", 15, MUTED, false, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(load_msg)


func set_progress(p: float, msg: String) -> void:
	load_bar.value = p
	load_msg.text = msg + "…"


func show_loading() -> void:
	loading.visible = true
	if menu != null:
		menu.visible = false
	hud.visible = false


# ------------------------------------------------------------ menu
func _build_menu() -> void:
	menu = Control.new()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(menu)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	m.add_theme_constant_override("margin_left", 24)
	m.add_theme_constant_override("margin_top", 20)
	m.add_theme_constant_override("margin_bottom", 20)
	m.custom_minimum_size = Vector2(560, 0)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(m)
	var panel := PanelContainer.new()
	m.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 7)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	var lg := TextureRect.new()
	lg.texture = logo_dark
	lg.custom_minimum_size = Vector2(190, 64)
	lg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	v.add_child(lg)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 0)
	h.add_child(_lbl("Smart", 54, Color.WHITE, true))
	h.add_child(_lbl("Flight", 54, ORANGE, true))
	v.add_child(h)
	var sub := _lbl("Fly the skies around Duxford. On your gaming laptop, and in VR on a Meta Quest.", 15, MUTED)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(480, 0)
	v.add_child(sub)
	_section(v, "Aircraft")
	_seg(v, "aircraft", [["trainer", "Light Trainer (easy)"], ["fighter", "WW2 Fighter (fast)"]], Settings.get_value("aircraft"))
	_section(v, "Start")
	_seg(v, "start", [["runway", "On the runway"], ["air", "In the air"]], Settings.get_value("start"))
	_section(v, "Game")
	_seg(v, "mode", [["free", "Free flight"], ["gates", "Gate run"]], Settings.get_value("mode"))
	_section(v, "Flying style")
	_seg(v, "assist", [[true, "Easy (assisted)"], [false, "Pro (manual)"]], Settings.get_value("assist"))
	_section(v, "Time of day")
	_seg(v, "tod", [["day", "Day"], ["golden", "Golden hour"]], Settings.get_value("tod"))
	_section(v, "Wind")
	_seg(v, "wind", [["calm", "Calm"], ["breezy", "Breezy"]], Settings.get_value("wind"))
	var fly := _big_button("Fly", true)
	fly.pressed.connect(func(): fly_pressed.emit(false))
	v.add_child(fly)
	vr_btn = _big_button("Fly in VR (Meta Quest)", false)
	vr_btn.add_theme_font_size_override("font_size", 20)
	vr_btn.custom_minimum_size = Vector2(0, 46)
	vr_btn.pressed.connect(func(): fly_pressed.emit(true))
	v.add_child(vr_btn)
	vr_note = _lbl("", 14, Color("#ffb347"))
	vr_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vr_note.custom_minimum_size = Vector2(480, 0)
	vr_note.visible = false
	v.add_child(vr_note)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var hb := Button.new()
	hb.text = "Controls"
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.pressed.connect(func(): open_sheet(help_sheet))
	row.add_child(hb)
	var sb := Button.new()
	sb.text = "Settings"
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sb.pressed.connect(func(): open_sheet(settings_sheet))
	row.add_child(sb)
	var qb := Button.new()
	qb.text = "Quit"
	qb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qb.pressed.connect(func(): get_tree().quit())
	row.add_child(qb)
	v.add_child(row)
	gpu_label = _lbl("", 12, MUTED)
	gpu_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gpu_label.custom_minimum_size = Vector2(480, 0)
	v.add_child(gpu_label)


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
	hv.add_child(_lbl("HEADING", 11, MUTED, false, HORIZONTAL_ALIGNMENT_CENTER))
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
	sv.add_child(_lbl("KNOTS", 11, MUTED))
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
	av.add_child(_lbl("FEET", 11, MUTED, false, HORIZONTAL_ALIGNMENT_RIGHT))
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
func _sheet(title: String) -> Array:
	var s := ColorRect.new()
	s.color = Color(0.004, 0.004, 0.11, 0.62)
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	s.visible = false
	root.add_child(s)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	s.add_child(c)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(520, 0)
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
	fit[s] = [sc, v]
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
	again.pressed.connect(func(): restart_pressed.emit())
	v.add_child(again)
	var mb := Button.new()
	mb.text = "Back to menu"
	mb.custom_minimum_size = Vector2(0, 42)
	mb.pressed.connect(func(): menu_pressed.emit())
	v.add_child(mb)
	end_title = (v.get_child(0) as Label)
	r = _sheet("Controls")
	help_sheet = r[0]
	v = r[1]
	var txt := _lbl("KEYBOARD\nUp / Down (W / S): push the nose down / pull it up\nLeft / Right (A / D): roll\nQ / E: rudder (steers on the ground)\nShift / Ctrl: more / less power (or keys 1 to 0)\nSpace: brakes   F: flaps   V: change camera\nRight mouse + drag: look around   Mouse wheel: zoom (orbit camera)\nP or Esc: pause   R: restart   T: telemetry   M: sound   F11: full screen\n\nGAMEPAD\nRight stick: pitch and roll   Left stick: power and rudder\nLeft trigger: brakes   A: flaps   B: camera   Start: pause\n\nVR (Meta Quest)\nRight stick: pitch and roll   Left stick: power and rudder\nLeft trigger: brakes   A: flaps   B: recentre view   X: pause   Y: restart\nKeyboard works in VR too (click the game window before putting the headset on); V recentres the view\n\nEasy mode levels the aircraft for you. Pro mode is direct control, like the real thing.", 15, INK)
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.custom_minimum_size = Vector2(480, 0)
	v.add_child(txt)
	var cl := _big_button("Got it", true)
	cl.pressed.connect(func(): close_sheet(help_sheet))
	v.add_child(cl)
	r = _sheet("Settings")
	settings_sheet = r[0]
	v = r[1]
	_section(v, "Graphics quality (applies on the next start)")
	_seg(v, "quality", [["low", "Fast"], ["medium", "Balanced"], ["high", "Best"]], Settings.get_value("quality"))
	_section(v, "Sound")
	_seg(v, "sound", [[true, "On"], [false, "Off"]], Settings.get_value("sound"))
	_section(v, "Pitch control")
	_seg(v, "invert", [[false, "Pull back = nose up"], [true, "Inverted"]], Settings.get_value("invert"))
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
	sc.custom_minimum_size = Vector2(540, h)


func open_sheet(s: Control) -> void:
	for x in [pause_sheet, help_sheet, settings_sheet]:
		if x != s:
			(x as Control).visible = false
	_fit_sheet(s)
	s.visible = true


func close_sheet(s: Control) -> void:
	s.visible = false
	if paused_ui:
		pause_sheet.visible = true

var paused_ui := false

func any_sheet() -> bool:
	return help_sheet.visible or settings_sheet.visible or pause_sheet.visible or end_sheet.visible


func hide_sheets() -> void:
	for x in [pause_sheet, help_sheet, settings_sheet, end_sheet]:
		(x as Control).visible = false


# ------------------------------------------------------------ states
func show_menu() -> void:
	loading.visible = false
	hud.visible = false
	hide_sheets()
	menu.visible = true


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


func set_message(t: String, warn: bool) -> void:
	msg_label.text = t
	msg_label.add_theme_color_override("font_color", Color("#ff5a4f") if warn else Color.WHITE)
	msg_label.visible = t != ""
