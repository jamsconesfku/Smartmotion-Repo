class_name Instruments
extends Control
## The cockpit instrument panel, drawn into a SubViewport and shown on the dashboard of the aircraft.

var d := {"ias": 0.0, "vmax": 200.0, "alt": 0.0, "vs": 0.0, "heading": 0.0, "pitch": 0.0, "roll": 0.0, "throttle": 0.0, "rpm": 800.0, "rpm_max": 3000.0, "flaps": 0.0, "stall": false}
var font: Font
var adi_only := false


func _init() -> void:
	font = load("res://assets/fonts/Barlow-SemiBold.ttf")


func set_data(nd: Dictionary) -> void:
	d = nd
	queue_redraw()


func _ang(v: float, a0: float, a1: float, v0: float, v1: float) -> float:
	return deg_to_rad(a0 + (a1 - a0) * (clampf(v, v0, v1) - v0) / (v1 - v0))


func _txt(p: Vector2, t: String, size: int, col: Color, w: float = 0.0) -> void:
	draw_string(font, p, t, HORIZONTAL_ALIGNMENT_CENTER, w if w > 0.0 else -1.0, size, col)


func _needle(a: float, ln: float, w: float, col: Color) -> void:
	var dir := Vector2(cos(a), sin(a))
	draw_line(-dir * ln * 0.15, dir * ln, col, w, true)


func _ticks(r: float, n: int, a0: float, a1: float, ln: float, w: float, labels: Callable, every: int, fs: int) -> void:
	for k in range(n + 1):
		var a := deg_to_rad(a0 + (a1 - a0) * k / n)
		var dir := Vector2(cos(a), sin(a))
		draw_line(dir * (r - 8.0), dir * (r - 8.0 - ln), Color("#d5d8e6"), w, true)
		if labels.is_valid() and k % every == 0:
			var p := dir * (r - 38.0)
			_txt(p + Vector2(-30, fs * 0.35), str(labels.call(k)), fs, Color("#e9ebf5"), 60.0)


func _dial(cx: float, cy: float, r: float) -> void:
	draw_set_transform(Vector2(cx, cy), 0.0, Vector2.ONE)
	draw_circle(Vector2.ZERO, r, Color("#05060b"))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color("#4a4d5e"), 5.0, true)


func _draw() -> void:
	var w := size.x
	var h := size.y
	if adi_only:
		_draw_adi(w * 0.5, h * 0.5, minf(w, h) * 0.47)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	draw_rect(Rect2(0, 0, w, h), Color("#16171f"))
	draw_rect(Rect2(0, 0, w, 8), Color("#ff4c00"))
	var cw := w / 3.0
	var ch := h / 2.0
	var r := minf(cw, ch) * 0.47
	var lab_col := Color("#9ea2b8")
	# airspeed
	_dial(cw * 0.5, ch * 0.5, r)
	var vmax: float = d["vmax"]
	_ticks(r, int(vmax / 10.0), 135.0, 405.0, 12.0, 3.0, func(k): return k * 10, int(vmax / 50.0), 21)
	_txt(Vector2(-60, r * 0.62), "KNOTS", 20, lab_col, 120.0)
	_needle(_ang(d["ias"], 135.0, 405.0, 0.0, vmax), r - 14.0, 6.0, Color("#ff4c00"))
	_draw_adi(cw * 1.5, ch * 0.5, r)
	# altimeter
	_dial(cw * 2.5, ch * 0.5, r)
	_ticks(r, 10, -90.0, 270.0, 12.0, 3.0, func(k): return k % 10, 1, 21)
	var ft: float = d["alt"]
	_needle(_ang(fposmod(ft, 1000.0), -90.0, 270.0, 0.0, 1000.0), r - 14.0, 6.0, Color.WHITE)
	_needle(_ang(fposmod(ft, 10000.0), -90.0, 270.0, 0.0, 10000.0), r * 0.6, 8.0, Color("#ff4c00"))
	_txt(Vector2(-60, r * 0.62), "FEET", 20, lab_col, 120.0)
	# heading
	_dial(cw * 0.5, ch * 1.5, r)
	draw_set_transform(Vector2(cw * 0.5, ch * 1.5), -deg_to_rad(d["heading"]), Vector2.ONE)
	for k in 36:
		var a := deg_to_rad(k * 10.0) - PI / 2.0
		var dir := Vector2(cos(a), sin(a))
		var big := k % 3 == 0
		draw_line(dir * (r - 8.0), dir * (r - (28.0 if big else 18.0)), Color("#d5d8e6"), 4.0 if big else 2.0, true)
		if big:
			var t := "N" if k == 0 else ("E" if k == 9 else ("S" if k == 18 else ("W" if k == 27 else str(k))))
			draw_set_transform(Vector2(cw * 0.5, ch * 1.5) + dir * (r - 54.0), -deg_to_rad(d["heading"]) + a + PI / 2.0, Vector2.ONE)
			_txt(Vector2(-30, 10), t, 28, Color("#e9ebf5"), 60.0)
			draw_set_transform(Vector2(cw * 0.5, ch * 1.5), -deg_to_rad(d["heading"]), Vector2.ONE)
	draw_set_transform(Vector2(cw * 0.5, ch * 1.5), 0.0, Vector2.ONE)
	draw_colored_polygon(PackedVector2Array([Vector2(0, -r + 6), Vector2(-10, -r + 28), Vector2(10, -r + 28)]), Color("#ff4c00"))
	draw_line(Vector2(0, -18), Vector2(0, 18), Color.WHITE, 5.0, true)
	draw_line(Vector2(-16, 4), Vector2(16, 4), Color.WHITE, 5.0, true)
	# vertical speed
	_dial(cw * 1.5, ch * 1.5, r)
	_ticks(r, 12, 90.0, 450.0, 12.0, 3.0, Callable(), 1, 21)
	_txt(Vector2(-60, -r * 0.45 + 8), "UP", 22, Color("#e9ebf5"), 120.0)
	_txt(Vector2(-60, r * 0.55 + 8), "DN", 22, Color("#e9ebf5"), 120.0)
	_needle(deg_to_rad(180.0 + (clampf(d["vs"], -2000.0, 2000.0) / 2000.0) * 160.0), r - 14.0, 6.0, Color("#ff4c00"))
	_txt(Vector2(-60, r * 0.25), "V/S x100", 18, lab_col, 120.0)
	# engine
	_dial(cw * 2.5, ch * 1.5, r)
	_ticks(r, 8, 135.0, 405.0, 12.0, 3.0, func(k): return k, 1, 21)
	_needle(_ang(d["rpm"], 135.0, 405.0, 0.0, d["rpm_max"]), r - 14.0, 6.0, Color.WHITE)
	_txt(Vector2(-80, r * 0.35), "THR %d%%" % int(round(float(d["throttle"]) * 100.0)), 24, Color("#e9ebf5"), 160.0)
	_txt(Vector2(-80, r * 0.62), "FLAPS %d%%" % int(round(float(d["flaps"]) * 100.0)), 24, Color("#e9ebf5"), 160.0)
	if d["stall"]:
		_txt(Vector2(-80, -r * 0.3), "STALL", 34, Color("#ff3b30"), 160.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_adi(cx: float, cy: float, r: float) -> void:
	_dial(cx, cy, r)
	var circle := PackedVector2Array()
	for i in 48:
		circle.append(Vector2(cos(TAU * i / 48.0), sin(TAU * i / 48.0)) * (r - 4.0))
	var py: float = float(d["pitch"]) * (r / 28.0)
	draw_set_transform(Vector2(cx, cy), -deg_to_rad(d["roll"]), Vector2.ONE)
	var sky := PackedVector2Array([Vector2(-2 * r, -2 * r + py), Vector2(2 * r, -2 * r + py), Vector2(2 * r, py), Vector2(-2 * r, py)])
	var gnd := PackedVector2Array([Vector2(-2 * r, py), Vector2(2 * r, py), Vector2(2 * r, 2 * r + py), Vector2(-2 * r, 2 * r + py)])
	for poly in Geometry2D.intersect_polygons(sky, circle):
		draw_colored_polygon(poly, Color("#3d7fc4"))
	for poly in Geometry2D.intersect_polygons(gnd, circle):
		draw_colored_polygon(poly, Color("#7a5a32"))
	draw_line(Vector2(-r, py), Vector2(r, py), Color.WHITE, 4.0, true)
	for p in [-20, -10, 10, 20]:
		var y: float = py - p * (r / 28.0)
		var ww: float = r * 0.3 if absi(p) == 10 else r * 0.45
		draw_line(Vector2(-ww, y), Vector2(ww, y), Color.WHITE, 3.0, true)
	draw_set_transform(Vector2(cx, cy), 0.0, Vector2.ONE)
	draw_polyline(PackedVector2Array([Vector2(-r * 0.55, 0), Vector2(-r * 0.15, 0), Vector2(0, r * 0.12), Vector2(r * 0.15, 0), Vector2(r * 0.55, 0)]), Color("#ffb000"), 7.0, true)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color("#4a4d5e"), 5.0, true)
