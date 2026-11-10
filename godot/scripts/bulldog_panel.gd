class_name BulldogPanel
extends Control
## The Bulldog's instrument panel, drawn at high resolution into a SubViewport and shown on the 3D panel.
## The 3D builder (bulldog.gd) puts a bezel and a glass over each round gauge using LAYOUT, so the
## positions here are in metres on the panel (origin top-left, x right, y down).
## Layout follows a classic RAF light-trainer panel: the six flight instruments in front of the left seat,
## engine gauges and the g-meter in the middle, radios and fuel on the right, switches along the bottom.

const PW := 1.12          # panel width, metres
const PH := 0.42          # panel height, metres
const PXM := 1800.0       # pixels per metre (about 1.8 px a millimetre: sharp in a headset at arm's length)
## name, centre x, centre y, radius (metres)
const LAYOUT := [
	["asi", 0.115, 0.115, 0.046], ["ai", 0.225, 0.115, 0.046], ["alt", 0.335, 0.115, 0.046],
	["tc", 0.115, 0.225, 0.046], ["di", 0.225, 0.225, 0.046], ["vsi", 0.335, 0.225, 0.046],
	["g", 0.445, 0.090, 0.033], ["rpm", 0.445, 0.185, 0.040], ["map", 0.445, 0.280, 0.033],
	["clock", 0.470, 0.372, 0.022],
	["oil", 0.545, 0.090, 0.028], ["fuel", 0.545, 0.165, 0.028], ["cht", 0.545, 0.240, 0.028], ["amp", 0.545, 0.315, 0.024],
]

var d := {"ias": 0.0, "alt": 0.0, "vs": 0.0, "heading": 0.0, "pitch": 0.0, "roll": 0.0, "throttle": 0.0, "rpm": 700.0,
	"rpm_max": 2700.0, "flaps": 0.0, "stall": false, "g": 1.0, "slip": 0.0, "turn": 0.0, "time": 0.0, "mover": 0}
## "static" draws the parts that never move (faces, scales, numbers, radios, switches, placards) once;
## "live" draws only the moving parts on top, every frame. Two layers keep the per-frame work small,
## which matters in VR (the whole panel used to be redrawn every frame: 3 to 5 ms of a 11 ms frame).
var layer := "all"
var S := true       # draw the fixed parts
var L := true       # draw the moving parts
var font: Font
var bold: Font
var g_max := 1.0
var g_min := 1.0

const FACE := Color("#0b0c0e")
const INK := Color("#eceae2")
const PANEL := Color("#26282c")
const GREEN := Color("#2fb34a")
const YELLOW := Color("#f2c21b")
const RED := Color("#e0261b")
const WHITE_ARC := Color("#f4f4f0")


func set_layer(l: String) -> void:
	layer = l
	S = l != "live"
	L = l != "static"
	queue_redraw()


func _init() -> void:
	font = load("res://assets/fonts/Barlow-SemiBold.ttf")
	bold = load("res://assets/fonts/BarlowSemiCondensed-BoldItalic.ttf")


var _grain: ImageTexture


func _grain_tex() -> ImageTexture:
	if _grain == null:
		var img := Image.create_empty(256, 256, false, Image.FORMAT_RGBA8)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in 1400:
			var x := rng.randi() % 255
			var y := rng.randi() % 255
			var c := Color(0, 0, 0, 0.14) if i % 2 == 0 else Color(1, 1, 1, 0.03)
			img.fill_rect(Rect2i(x, y, 2, 2), c)
		_grain = ImageTexture.create_from_image(img)
	return _grain


func set_data(nd: Dictionary) -> void:
	for k in nd.keys():
		d[k] = nd[k]
	g_max = maxf(g_max, float(d["g"]))
	g_min = minf(g_min, float(d["g"]))
	if L:
		queue_redraw()


func px(m: float) -> float:
	return m * PXM


# ---------------------------------------------------------------- helpers
func _txt(p: Vector2, t: String, size: float, col: Color, f: Font = null) -> void:
	var ff := f if f != null else font
	var w := ff.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(size)).x
	draw_string(ff, p - Vector2(w / 2.0, -size * 0.35), t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(size), col)


func _arc(r: float, a0: float, a1: float, w: float, col: Color) -> void:
	draw_arc(Vector2.ZERO, r, deg_to_rad(a0), deg_to_rad(a1), 48, col, w, true)


func _needle(a_deg: float, ln: float, w: float, col: Color, tail := 0.18) -> void:
	var a := deg_to_rad(a_deg)
	var dir := Vector2(cos(a), sin(a))
	var nrm := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array([-dir * ln * tail + nrm * w * 0.7, dir * ln * 0.82 + nrm * w * 0.5, dir * ln, dir * ln * 0.82 - nrm * w * 0.5, -dir * ln * tail - nrm * w * 0.7])
	draw_colored_polygon(pts, col)


func _hub(r: float) -> void:
	draw_circle(Vector2.ZERO, r, Color("#1a1a1a"))
	draw_circle(Vector2.ZERO, r * 0.55, Color("#3a3a3a"))


func _ticks(r: float, a0: float, a1: float, n: int, major: int, ln: float, lw: float) -> void:
	for k in range(n + 1):
		var a := deg_to_rad(a0 + (a1 - a0) * k / n)
		var dir := Vector2(cos(a), sin(a))
		var big := k % major == 0
		draw_line(dir * r, dir * (r - (ln if big else ln * 0.55)), INK, lw if big else lw * 0.6, true)


func _num(r: float, a_deg: float, t: String, size: float) -> void:
	var a := deg_to_rad(a_deg)
	_txt(Vector2(cos(a), sin(a)) * r, t, size, INK)


func _map(v: float, v0: float, v1: float, a0: float, a1: float) -> float:
	return a0 + (a1 - a0) * (clampf(v, v0, v1) - v0) / (v1 - v0)


func _screws(r: float) -> void:
	for a in [45.0, 135.0, 225.0, 315.0]:
		var p := Vector2(cos(deg_to_rad(a)), sin(deg_to_rad(a))) * r * 1.22
		draw_circle(p, r * 0.06, Color("#5a5c60"))
		draw_line(p - Vector2(r * 0.04, r * 0.04), p + Vector2(r * 0.04, r * 0.04), Color("#222"), 2.0, true)


func _begin(name: String) -> float:
	for l in LAYOUT:
		if l[0] == name:
			draw_set_transform(Vector2(px(l[1]), px(l[2])), 0.0, Vector2.ONE)
			var r := px(l[3])
			if S:
				_screws(r)
				draw_circle(Vector2.ZERO, r * 1.06, Color("#111214"))
				draw_circle(Vector2.ZERO, r, FACE)
			return r
	return 0.0


# ---------------------------------------------------------------- the panel
static var draw_us := 0     ## time spent drawing the panel (for the diagnostics log)
static var draw_n := 0
func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	_draw_all()
	draw_us += Time.get_ticks_usec() - t0
	draw_n += 1


func _draw_all() -> void:
	var W := px(PW)
	var H := px(PH)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if S:
		draw_rect(Rect2(0, 0, W, H), PANEL)
		# subtle crackle-paint grain: one small tiled texture, made once
		draw_texture_rect(_grain_tex(), Rect2(0, 0, W, H), true)
		# sub-panels
		draw_rect(Rect2(px(0.012), px(0.012), px(0.39), px(0.29)), Color("#1f2124"), true)
		draw_rect(Rect2(px(0.012), px(0.012), px(0.39), px(0.29)), Color("#3a3c40"), false, 3.0)
	_asi()
	_ai()
	_alt()
	_tc()
	_di()
	_vsi()
	_gmeter()
	_rpm()
	_mapg()
	_clock()
	_small_dual("oil", "OIL", "°C", "PSI", 0.55, 0.62)
	_small_dual("fuel", "FUEL", "L", "R", 0.7, 0.68)
	_small_single("cht", "CHT", 0.58)
	_small_single("amp", "AMPS", 0.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_radios()
	_switches()
	_annunciators()
	_placards()


func _asi() -> void:
	var r := _begin("asi")
	# Bulldog speeds (knots): white flap arc 50-100, green 59-130, yellow 130-185, red line 185
	var a := func(v: float) -> float: return _map(v, 40.0, 200.0, 125.0, 415.0)
	if S:
		_arc(r * 0.93, a.call(50.0), a.call(100.0), r * 0.06, WHITE_ARC)
		_arc(r * 0.86, a.call(59.0), a.call(130.0), r * 0.07, GREEN)
		_arc(r * 0.86, a.call(130.0), a.call(185.0), r * 0.07, YELLOW)
		var rl := deg_to_rad(a.call(185.0))
		draw_line(Vector2(cos(rl), sin(rl)) * r * 0.97, Vector2(cos(rl), sin(rl)) * r * 0.78, RED, r * 0.05, true)
		_ticks(r * 0.97, 125.0, 415.0, 32, 2, r * 0.13, r * 0.03)
		for v in [40, 60, 80, 100, 120, 140, 160, 180, 200]:
			_num(r * 0.62, a.call(float(v)), str(v), r * 0.2)
		_txt(Vector2(0, -r * 0.3), "AIRSPEED", r * 0.11, INK)
		_txt(Vector2(0, r * 0.32), "KNOTS", r * 0.12, INK)
	if not L:
		return
	_needle(a.call(float(d["ias"])), r * 0.92, r * 0.07, Color.WHITE)
	_hub(r * 0.1)


func _ai() -> void:
	var r := _begin("ai")
	if not L:
		return
	var circle := PackedVector2Array()
	for i in 64:
		circle.append(Vector2(cos(TAU * i / 64.0), sin(TAU * i / 64.0)) * r * 0.98)
	var py := clampf(float(d["pitch"]), -30.0, 30.0) * (r / 32.0)
	draw_set_transform(Vector2(px(0.225), px(0.115)), -deg_to_rad(d["roll"]), Vector2.ONE)
	var sky := PackedVector2Array([Vector2(-2 * r, -2 * r + py), Vector2(2 * r, -2 * r + py), Vector2(2 * r, py), Vector2(-2 * r, py)])
	var gnd := PackedVector2Array([Vector2(-2 * r, py), Vector2(2 * r, py), Vector2(2 * r, 2 * r + py), Vector2(-2 * r, 2 * r + py)])
	for poly in Geometry2D.intersect_polygons(sky, circle):
		draw_colored_polygon(poly, Color("#2f78c2"))
	for poly in Geometry2D.intersect_polygons(gnd, circle):
		draw_colored_polygon(poly, Color("#6b4423"))
	draw_line(Vector2(-r, py), Vector2(r, py), Color.WHITE, r * 0.03, true)
	for p in [-20, -10, -5, 5, 10, 20]:
		var y: float = py - p * (r / 32.0)
		var ww: float = r * (0.14 if absi(p) == 5 else (0.3 if absi(p) == 10 else 0.42))
		draw_line(Vector2(-ww, y), Vector2(ww, y), Color.WHITE, r * 0.022, true)
		if absi(p) >= 10:
			_txt(Vector2(ww + r * 0.12, y), str(absi(p)), r * 0.1, Color.WHITE)
	# bank scale on the rotating card
	for b in [-60, -45, -30, -20, -10, 0, 10, 20, 30, 45, 60]:
		var ang := deg_to_rad(-90.0 + b)
		var dir := Vector2(cos(ang), sin(ang))
		draw_line(dir * r * 0.97, dir * r * (0.84 if b % 30 == 0 else 0.9), Color.WHITE, r * 0.025, true)
	draw_set_transform(Vector2(px(0.225), px(0.115)), 0.0, Vector2.ONE)
	# fixed aircraft symbol and bank pointer
	var amber := Color("#ff9d00")
	draw_polyline(PackedVector2Array([Vector2(-r * 0.62, 0), Vector2(-r * 0.2, 0), Vector2(-r * 0.1, r * 0.1)]), amber, r * 0.06, true)
	draw_polyline(PackedVector2Array([Vector2(r * 0.62, 0), Vector2(r * 0.2, 0), Vector2(r * 0.1, r * 0.1)]), amber, r * 0.06, true)
	draw_circle(Vector2.ZERO, r * 0.05, amber)
	draw_colored_polygon(PackedVector2Array([Vector2(0, -r * 0.82), Vector2(-r * 0.07, -r * 0.68), Vector2(r * 0.07, -r * 0.68)]), amber)


func _alt() -> void:
	var r := _begin("alt")
	if S:
		_ticks(r * 0.97, -90.0, 270.0, 50, 5, r * 0.13, r * 0.03)
		for k in 10:
			_num(r * 0.68, -90.0 + k * 36.0, str(k), r * 0.24)
		# Kollsman window
		draw_rect(Rect2(r * 0.3, -r * 0.09, r * 0.42, r * 0.18), Color("#000"))
		_txt(Vector2(r * 0.51, 0), "1013", r * 0.11, INK)
		_txt(Vector2(0, -r * 0.32), "ALT", r * 0.12, INK)
		_txt(Vector2(0, r * 0.35), "FEET", r * 0.1, INK)
	if not L:
		return
	var ft := float(d["alt"])
	_needle(-90.0 + fposmod(ft, 10000.0) / 10000.0 * 360.0, r * 0.55, r * 0.11, Color.WHITE, 0.1)
	_needle(-90.0 + fposmod(ft, 1000.0) / 1000.0 * 360.0, r * 0.9, r * 0.065, Color.WHITE)
	_hub(r * 0.1)


func _tc() -> void:
	var r := _begin("tc")
	if S:
		_txt(Vector2(0, -r * 0.55), "TURN COORDINATOR", r * 0.1, INK)
		for s in [-1.0, 1.0]:
			var a := deg_to_rad(s * 20.0)
			draw_line(Vector2(cos(a), sin(a)) * r * 0.9 * s, Vector2(cos(a), sin(a)) * r * 0.72 * s, INK, r * 0.04, true)
		draw_line(Vector2(-r * 0.9, 0), Vector2(-r * 0.72, 0), INK, r * 0.04, true)
		draw_line(Vector2(r * 0.9, 0), Vector2(r * 0.72, 0), INK, r * 0.04, true)
		_txt(Vector2(-r * 0.68, r * 0.36), "L", r * 0.16, INK)
		_txt(Vector2(r * 0.68, r * 0.36), "R", r * 0.16, INK)
		_txt(Vector2(0, r * 0.82), "2 MIN", r * 0.09, INK)
		# curved tube for the ball
		var tube := Rect2(-r * 0.45, r * 0.42, r * 0.9, r * 0.2)
		draw_rect(tube, Color("#d9d4c2"))
		draw_line(Vector2(-r * 0.08, r * 0.42), Vector2(-r * 0.08, r * 0.62), Color.BLACK, 2.0)
		draw_line(Vector2(r * 0.08, r * 0.42), Vector2(r * 0.08, r * 0.62), Color.BLACK, 2.0)
	if not L:
		return
	var bx := clampf(-float(d["slip"]) * 0.03, -0.36, 0.36) * r
	draw_circle(Vector2(bx, r * 0.52), r * 0.085, Color.BLACK)
	# little aircraft banks with the rate of turn (standard rate 3 deg/s = 20 degrees)
	var rot := deg_to_rad(clampf(float(d["turn"]) / 3.0 * 20.0, -35.0, 35.0))
	draw_set_transform(Vector2(px(0.115), px(0.225)), rot, Vector2.ONE)
	draw_line(Vector2(-r * 0.7, 0), Vector2(r * 0.7, 0), Color.WHITE, r * 0.07, true)
	draw_circle(Vector2.ZERO, r * 0.11, Color.WHITE)
	draw_line(Vector2(0, -r * 0.12), Vector2(0, -r * 0.24), Color.WHITE, r * 0.05, true)


func _di() -> void:
	var r := _begin("di")
	if not L:
		return
	var hd := float(d["heading"])
	draw_set_transform(Vector2(px(0.225), px(0.225)), -deg_to_rad(hd), Vector2.ONE)
	for k in 72:
		var a := deg_to_rad(k * 5.0) - PI / 2.0
		var dir := Vector2(cos(a), sin(a))
		var big := k % 2 == 0
		draw_line(dir * r * 0.95, dir * r * (0.8 if big else 0.87), INK, r * (0.03 if big else 0.018), true)
		if k % 6 == 0:
			var n := k / 2
			var t := "N" if n == 0 else ("E" if n == 9 else ("S" if n == 18 else ("W" if n == 27 else str(n))))
			draw_set_transform(Vector2(px(0.225), px(0.225)) + dir.rotated(-deg_to_rad(hd)) * r * 0.62, -deg_to_rad(hd) + a + PI / 2.0, Vector2.ONE)
			_txt(Vector2.ZERO, t, r * (0.24 if t.length() == 1 and not t.is_valid_int() else 0.19), INK)
			draw_set_transform(Vector2(px(0.225), px(0.225)), -deg_to_rad(hd), Vector2.ONE)
	draw_set_transform(Vector2(px(0.225), px(0.225)), 0.0, Vector2.ONE)
	var amber := Color("#ff9d00")
	draw_colored_polygon(PackedVector2Array([Vector2(0, -r * 0.97), Vector2(-r * 0.06, -r * 0.84), Vector2(r * 0.06, -r * 0.84)]), amber)
	draw_line(Vector2(0, -r * 0.3), Vector2(0, r * 0.3), amber, r * 0.05, true)
	draw_line(Vector2(-r * 0.25, -r * 0.05), Vector2(r * 0.25, -r * 0.05), amber, r * 0.05, true)
	draw_line(Vector2(-r * 0.1, r * 0.25), Vector2(r * 0.1, r * 0.25), amber, r * 0.04, true)


func _vsi() -> void:
	var r := _begin("vsi")
	# 0 at 9 o'clock, +/-2000 ft/min at +/-170 degrees
	if S:
		_ticks(r * 0.97, 10.0, 350.0, 40, 5, r * 0.13, r * 0.03)
		for v in [-20, -15, -10, -5, 0, 5, 10, 15, 20]:
			_num(r * 0.68, 180.0 + v * 8.5, str(absi(v)), r * 0.19)
		_txt(Vector2(-r * 0.2, -r * 0.3), "UP", r * 0.12, INK)
		_txt(Vector2(-r * 0.2, r * 0.3), "DOWN", r * 0.12, INK)
		_txt(Vector2(r * 0.35, 0), "100 FT/MIN", r * 0.08, INK)
	if not L:
		return
	_needle(180.0 + clampf(float(d["vs"]), -2000.0, 2000.0) / 100.0 * 8.5, r * 0.92, r * 0.07, Color.WHITE)
	_hub(r * 0.1)


func _gmeter() -> void:
	var r := _begin("g")
	# accelerometer: -3 to +7 g, red beyond the Bulldog's +6 / -3 limits
	var a := func(v: float) -> float: return _map(v, -3.0, 7.0, 135.0, 405.0)
	if S:
		_arc(r * 0.88, a.call(-3.0), a.call(6.0), r * 0.06, GREEN)
		_arc(r * 0.88, a.call(6.0), a.call(7.0), r * 0.08, RED)
		_ticks(r * 0.97, 135.0, 405.0, 10, 1, r * 0.15, r * 0.035)
		for v in [-2, 0, 2, 4, 6]:
			_num(r * 0.62, a.call(float(v)), str(v), r * 0.22)
		_txt(Vector2(0, r * 0.4), "G", r * 0.2, INK)
	if not L:
		return
	_needle(a.call(g_max), r * 0.8, r * 0.05, Color("#c0c0c0"))
	_needle(a.call(g_min), r * 0.8, r * 0.05, Color("#c0c0c0"))
	_needle(a.call(float(d["g"])), r * 0.92, r * 0.08, Color.WHITE)
	_hub(r * 0.12)


func _rpm() -> void:
	var r := _begin("rpm")
	var a := func(v: float) -> float: return _map(v, 0.0, 3500.0, 135.0, 405.0)
	if S:
		_arc(r * 0.88, a.call(2000.0), a.call(2650.0), r * 0.07, GREEN)
		var rl := deg_to_rad(a.call(2700.0))
		draw_line(Vector2(cos(rl), sin(rl)) * r * 0.97, Vector2(cos(rl), sin(rl)) * r * 0.75, RED, r * 0.05, true)
		_ticks(r * 0.97, 135.0, 405.0, 35, 5, r * 0.14, r * 0.03)
		for v in [0, 5, 10, 15, 20, 25, 30, 35]:
			_num(r * 0.64, a.call(v * 100.0), str(v), r * 0.19)
		_txt(Vector2(0, -r * 0.3), "RPM", r * 0.13, INK)
		_txt(Vector2(0, r * 0.3), "x100", r * 0.11, INK)
	if not L:
		return
	_needle(a.call(float(d["rpm"])), r * 0.92, r * 0.07, Color.WHITE)
	_hub(r * 0.1)


func _mapg() -> void:
	var r := _begin("map")
	var a := func(v: float) -> float: return _map(v, 10.0, 35.0, 135.0, 405.0)
	if S:
		_arc(r * 0.88, a.call(15.0), a.call(29.0), r * 0.07, GREEN)
		_ticks(r * 0.97, 135.0, 405.0, 25, 5, r * 0.15, r * 0.035)
		for v in [10, 15, 20, 25, 30, 35]:
			_num(r * 0.63, a.call(float(v)), str(v), r * 0.2)
		_txt(Vector2(0, r * 0.38), "MAN PRESS", r * 0.1, INK)
	if not L:
		return
	var mp := 12.0 + 17.0 * float(d["throttle"]) - float(d["alt"]) / 1000.0
	_needle(a.call(mp), r * 0.9, r * 0.08, Color.WHITE)
	_hub(r * 0.12)


func _clock() -> void:
	var r := _begin("clock")
	if S:
		_ticks(r * 0.95, -90.0, 270.0, 12, 3, r * 0.2, r * 0.06)
	if not L:
		return
	var t := Time.get_time_dict_from_system()
	var hh := float(t["hour"] % 12) + float(t["minute"]) / 60.0
	_needle(-90.0 + hh * 30.0, r * 0.55, r * 0.1, Color.WHITE, 0.1)
	_needle(-90.0 + float(t["minute"]) * 6.0, r * 0.85, r * 0.07, Color.WHITE, 0.1)
	_hub(r * 0.12)


func _small_dual(name: String, label: String, l1: String, l2: String, v1: float, v2: float) -> void:
	var r := _begin(name)
	for s in [-1.0, 1.0]:
		var a0 := 200.0 if s < 0.0 else -20.0
		var a1 := 160.0 if s < 0.0 else 20.0
		if S:
			_arc(r * 0.82, minf(a0, a1), maxf(a0, a1), r * 0.08, GREEN)
		if L:
			var v := v1 if s < 0.0 else v2
			_needle(lerpf(a0, a1, v), r * 0.85, r * 0.08, Color.WHITE, 0.0)
	if S:
		_txt(Vector2(-r * 0.45, r * 0.55), l1, r * 0.2, INK)
		_txt(Vector2(r * 0.45, r * 0.55), l2, r * 0.2, INK)
		_txt(Vector2(0, -r * 0.45), label, r * 0.2, INK)
	if L:
		_hub(r * 0.12)


func _small_single(name: String, label: String, v: float) -> void:
	var r := _begin(name)
	if S:
		_arc(r * 0.82, 160.0, 380.0, r * 0.06, Color("#555"))
		_arc(r * 0.82, 220.0, 330.0, r * 0.08, GREEN)
		_ticks(r * 0.95, 160.0, 380.0, 8, 2, r * 0.2, r * 0.05)
		_txt(Vector2(0, r * 0.5), label, r * 0.22, INK)
	if not L:
		return
	_needle(lerpf(160.0, 380.0, v), r * 0.85, r * 0.09, Color.WHITE)
	_hub(r * 0.12)


func _radios() -> void:
	var x0 := px(0.62)
	var y0 := px(0.03)
	var w := px(0.3)
	var fx := px(0.96)
	if L:
		# flap position pointer (moves)
		var fy := px(0.07) + float(d["flaps"]) * 2.0 * px(0.028)
		draw_colored_polygon(PackedVector2Array([Vector2(fx + px(0.07), fy), Vector2(fx + px(0.1), fy - px(0.008)), Vector2(fx + px(0.1), fy + px(0.008))]), Color("#ff9d00"))
	if not S:
		return
	var rows := [["COM 1", "118.505", "122.475"], ["NAV 1", "112.30", "110.50"], ["XPDR", "7000", "ALT"]]
	for i in rows.size():
		var y := y0 + i * px(0.075)
		draw_rect(Rect2(x0, y, w, px(0.062)), Color("#141518"))
		draw_rect(Rect2(x0, y, w, px(0.062)), Color("#45474c"), false, 3.0)
		draw_rect(Rect2(x0 + px(0.05), y + px(0.012), px(0.19), px(0.038)), Color("#050505"))
		var r: Array = rows[i]
		_txt(Vector2(x0 + px(0.025), y + px(0.031)), r[0], px(0.011), INK)
		var col := Color("#54ff7a") if i < 2 else Color("#ffb347")
		_txt(Vector2(x0 + px(0.1), y + px(0.031)), r[1], px(0.022), col, bold)
		_txt(Vector2(x0 + px(0.195), y + px(0.031)), r[2], px(0.016), col.darkened(0.35), bold)
		for k in 2:
			draw_circle(Vector2(x0 + px(0.268) + k * px(0.0), y + px(0.031)), px(0.012 - k * 0.005), Color("#2e3034") if k == 0 else Color("#55585e"))
	# flap indicator placard
	draw_rect(Rect2(fx, px(0.03), px(0.14), px(0.13)), Color("#1b1c1f"))
	_txt(Vector2(fx + px(0.07), px(0.045)), "FLAPS", px(0.012), INK)
	for k in 3:
		var yy := px(0.07) + k * px(0.028)
		_txt(Vector2(fx + px(0.035), yy), ["UP", "TO", "LAND"][k], px(0.011), INK)


func _switches() -> void:
	if not S:
		return
	var names := ["MASTER", "ALT", "FUEL PUMP", "BEACON", "NAV", "STROBE", "LAND", "PITOT HT", "AVIONICS"]
	var x0 := px(0.62)
	var y := px(0.29)
	draw_rect(Rect2(x0 - px(0.01), y - px(0.035), px(0.48), px(0.11)), Color("#1d1e21"))
	for i in names.size():
		var x := x0 + px(0.012) + i * px(0.052)
		_txt(Vector2(x, y - px(0.02)), names[i], px(0.0085), INK)
		draw_rect(Rect2(x - px(0.009), y - px(0.008), px(0.018), px(0.035)), Color("#0c0c0d"))
		var on := i != 7
		draw_rect(Rect2(x - px(0.004), y + (px(-0.004) if on else px(0.014)), px(0.008), px(0.016)), Color("#c9cbd0"))
		_txt(Vector2(x, y + px(0.045)), "ON" if on else "OFF", px(0.007), Color("#9a9ca3"))
	# magneto key switch
	var kx := px(0.06)
	var ky := px(0.38)
	draw_circle(Vector2(kx, ky), px(0.022), Color("#3b3d42"))
	draw_circle(Vector2(kx, ky), px(0.014), Color("#8f9197"))
	draw_set_transform(Vector2(kx, ky), deg_to_rad(40.0), Vector2.ONE)
	draw_rect(Rect2(-px(0.003), -px(0.012), px(0.006), px(0.024)), Color("#d9d9d9"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for k in 5:
		var a := deg_to_rad(-150.0 + k * 30.0)
		_txt(Vector2(kx, ky) + Vector2(cos(a), sin(a)) * px(0.032), ["OFF", "R", "L", "BOTH", "START"][k], px(0.007), INK)


func _annunciators() -> void:
	var names := ["LOW VOLTS", "OIL PRESS", "FUEL PRESS", "STALL"]
	var x0 := px(0.15)
	var y := px(0.33)
	for i in names.size():
		var lit := L and i == 3 and bool(d["stall"])
		if not lit and not S:
			continue
		var r := Rect2(x0 + i * px(0.06), y, px(0.052), px(0.026))
		draw_rect(r, Color("#ff3020") if lit else Color("#3a1210"))
		draw_rect(r, Color("#0c0c0c"), false, 3.0)
		_txt(r.get_center(), names[i], px(0.0075), Color("#ffffff") if lit else Color("#8a6a66"))
	# FlyPT Mover light: green = Mover is reading the game, amber = waiting for Mover, dark = off
	if L:
		var m := int(d.get("mover", 0))
		var r := Rect2(x0 + names.size() * px(0.06), y, px(0.052), px(0.026))
		draw_rect(r, [Color("#1c1c1c"), Color("#c98500"), Color("#16a334")][clampi(m, 0, 2)])
		draw_rect(r, Color("#0c0c0c"), false, 3.0)
		var tc := Color("#d0d0d0") if m == 0 else Color("#000000")
		_txt(r.get_center() - Vector2(0, px(0.0055)), "MOVER", px(0.0095), tc, bold)
		_txt(r.get_center() + Vector2(0, px(0.0062)), ["OFF", "WAITING", "LINKED"][clampi(m, 0, 2)], px(0.0088), tc, bold)


func _placards() -> void:
	if not S:
		return
	_txt(Vector2(px(0.21), px(0.395)), "THIS AEROPLANE IS CLASSIFIED AS A VERY LIGHT AEROBATIC TRAINER", px(0.0075), Color("#c9c7bf"))
	_txt(Vector2(px(0.86), px(0.395)), "G-SMAT  ·  BULLDOG T.1  ·  XX658", px(0.011), Color("#c9c7bf"), bold)
	_txt(Vector2(px(0.86), px(0.412)), "MAX +6G  -3G   VNE 185 KT", px(0.0085), Color("#c9c7bf"))
