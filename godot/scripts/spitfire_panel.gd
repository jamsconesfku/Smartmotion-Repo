class_name SpitfirePanel
extends BulldogPanel
## The Spitfire Mk IX's instrument panel (v1.21.0), drawn like the Bulldog's (a high-resolution SubViewport, the
## fixed parts once and the needles every frame). Black panel; in the middle the standard RAF blind-flying panel
## on its rubber mounts: airspeed (mph), artificial horizon, rate of climb on top; altimeter, direction
## indicator (drum card in a window), turn and slip below. Engine gauges on the right: rpm and boost, oil
## pressure, oil and radiator temperature. Left: undercarriage lights, magneto switches, clock, fuel contents,
## brake pressure. Positions in metres on the panel (origin top-left, x right, y down).

const W := 0.62
const H := 0.30
const BFP := Rect2(0.15, 0.03, 0.32, 0.215)
## name, centre x, centre y, radius
const GAUGES := [
	["asi", 0.205, 0.087, 0.041], ["ah", 0.31, 0.087, 0.041], ["vsi", 0.415, 0.087, 0.041],
	["alt", 0.205, 0.19, 0.041], ["di", 0.31, 0.19, 0.041], ["ts", 0.415, 0.19, 0.041],
	["rpm", 0.545, 0.085, 0.042], ["boost", 0.545, 0.19, 0.036],
	["oilp", 0.485, 0.268, 0.021], ["oilt", 0.545, 0.268, 0.021], ["radt", 0.598, 0.255, 0.019],
	["clock", 0.06, 0.15, 0.024], ["fuel", 0.075, 0.245, 0.03], ["brake", 0.15, 0.27, 0.022],
]
const MPH := 1.15078


func _begin(name: String) -> float:
	for l in GAUGES:
		if l[0] == name:
			draw_set_transform(Vector2(px(l[1]), px(l[2])), 0.0, Vector2.ONE)
			var r := px(l[3])
			if S:
				_screws(r)
				draw_circle(Vector2.ZERO, r * 1.06, Color("#08080a"))
				draw_circle(Vector2.ZERO, r, FACE)
			return r
	return 0.0


func _at(name: String) -> Vector2:
	for l in GAUGES:
		if l[0] == name:
			return Vector2(px(l[1]), px(l[2]))
	return Vector2.ZERO


func _draw_all() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if S:
		draw_rect(Rect2(0, 0, px(W), px(H)), Color("#151617"))
		draw_texture_rect(_grain_tex(), Rect2(0, 0, px(W), px(H)), true)
		# the blind-flying panel, its four rubber mounts
		var b := Rect2(px(BFP.position.x), px(BFP.position.y), px(BFP.size.x), px(BFP.size.y))
		draw_rect(b, Color("#0c0c0d"))
		draw_rect(b, Color("#2a2b2d"), false, 3.0)
		for c in [b.position, b.position + Vector2(b.size.x, 0), b.position + b.size, b.position + Vector2(0, b.size.y)]:
			draw_circle(c, px(0.007), Color("#1d1d1c"))
			draw_circle(c, px(0.003), Color("#4a4a48"))
		_labels()
	_asi()
	_ah()
	_vsi_s()
	_alt()
	_di_s()
	_ts()
	_rpm_s()
	_boost()
	_small("oilp", "OIL", "LBS", 0.0, 150.0, 70.0, [0, 50, 100, 150])
	_small("oilt", "OIL °C", "", 0.0, 120.0, 72.0, [0, 40, 80, 120])
	_small("radt", "RAD °C", "", 40.0, 140.0, 95.0, [40, 80, 120])
	_clock()
	_small("fuel", "FUEL", "GALLS", 0.0, 85.0, 60.0, [0, 20, 40, 60, 80])
	_small("brake", "BRAKE", "", 0.0, 220.0, 120.0, [0, 100, 200])
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_lights()


func _labels() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var ink := Color("#d8d4c8")
	_txt(Vector2(px(0.06), px(0.035)), "UNDERCARRIAGE", px(0.008), ink)
	_txt(Vector2(px(0.06), px(0.1)), "MAGNETOS", px(0.007), ink)
	_txt(Vector2(px(0.045), px(0.125)), "1", px(0.008), ink)
	_txt(Vector2(px(0.075), px(0.125)), "2", px(0.008), ink)
	_txt(Vector2(px(0.13), px(0.035)), "FLAPS", px(0.008), ink)
	# small placard
	draw_rect(Rect2(px(0.255), px(0.265), px(0.11), px(0.02)), Color("#c9c2a8"))
	_txt(Vector2(px(0.31), px(0.275)), "DO NOT EXCEED 450 MPH IAS", px(0.0065), Color("#1b1b1b"))


func _lights() -> void:
	# undercarriage indicator: green DOWN lights (the wheels are always down)
	var c := Vector2(px(0.06), px(0.065))
	draw_rect(Rect2(c - Vector2(px(0.035), px(0.017)), Vector2(px(0.07), px(0.034))), Color("#0a0a0a"))
	for s in [-1.0, 1.0]:
		var p := c + Vector2(s * px(0.016), 0)
		draw_circle(p, px(0.009), Color("#1f4d22") if not L else Color("#3ae05a"))
	if S:
		_txt(c + Vector2(0, px(0.024)), "DOWN", px(0.007), Color("#d8d4c8"))
	# FlyPT Mover light (as on the Bulldog): green = Mover is reading the game, amber = waiting, dark = off
	if L:
		var m := int(d.get("mover", 0))
		var r := Rect2(px(0.093), px(0.18), px(0.052), px(0.026))
		draw_rect(r, [Color("#1c1c1c"), Color("#c98500"), Color("#16a334")][clampi(m, 0, 2)])
		draw_rect(r, Color("#0c0c0c"), false, 3.0)
		var tc := Color("#d0d0d0") if m == 0 else Color("#000000")
		_txt(r.get_center() - Vector2(0, px(0.0055)), "MOVER", px(0.0095), tc, bold)
		_txt(r.get_center() + Vector2(0, px(0.0062)), ["OFF", "WAITING", "LINKED"][clampi(m, 0, 2)], px(0.0088), tc, bold)


func _asi() -> void:
	var r := _begin("asi")
	var a := func(v: float) -> float: return _map(v, 50.0, 450.0, 120.0, 420.0)
	if S:
		_ticks(r * 0.97, 120.0, 420.0, 40, 4, r * 0.13, r * 0.03)
		for v in [60, 100, 150, 200, 250, 300, 350, 400, 450]:
			_num(r * 0.64, a.call(float(v)), str(v / 10) if v >= 100 else "6", r * 0.2)
		_txt(Vector2(0, -r * 0.32), "AIR SPEED", r * 0.1, INK)
		_txt(Vector2(0, r * 0.3), "MPH x10", r * 0.11, INK)
	if not L:
		return
	_needle(a.call(maxf(float(d["ias"]) * MPH, 50.0)), r * 0.9, r * 0.07, Color.WHITE)
	_hub(r * 0.1)


func _ah() -> void:
	# RAF Mk I artificial horizon: a white bar that moves with pitch and bank behind a fixed little aircraft
	var r := _begin("ah")
	if not L:
		return
	var c := _at("ah")
	var py := clampf(float(d["pitch"]), -25.0, 25.0) * (r / 30.0)
	draw_set_transform(c, -deg_to_rad(d["roll"]), Vector2.ONE)
	var circle := PackedVector2Array()
	for i in 48:
		circle.append(Vector2(cos(TAU * i / 48.0), sin(TAU * i / 48.0)) * r * 0.97)
	var gnd := PackedVector2Array([Vector2(-2 * r, py), Vector2(2 * r, py), Vector2(2 * r, 2 * r + py), Vector2(-2 * r, 2 * r + py)])
	for poly in Geometry2D.intersect_polygons(gnd, circle):
		draw_colored_polygon(poly, Color("#26221c"))
	draw_line(Vector2(-r * 0.92, py), Vector2(r * 0.92, py), Color("#f0eee6"), r * 0.07, true)
	draw_set_transform(c, 0.0, Vector2.ONE)
	for bk in [-60, -30, 0, 30, 60]:
		var ang := deg_to_rad(-90.0 + bk)
		draw_line(Vector2(cos(ang), sin(ang)) * r * 0.97, Vector2(cos(ang), sin(ang)) * r * 0.85, INK, r * 0.03, true)
	var amber := Color("#f2a33a")
	draw_line(Vector2(-r * 0.55, 0), Vector2(-r * 0.15, 0), amber, r * 0.06, true)
	draw_line(Vector2(r * 0.15, 0), Vector2(r * 0.55, 0), amber, r * 0.06, true)
	draw_circle(Vector2.ZERO, r * 0.06, amber)
	draw_line(Vector2(0, 0), Vector2(0, -r * 0.18), amber, r * 0.04, true)


func _vsi_s() -> void:
	var r := _begin("vsi")
	if S:
		_ticks(r * 0.97, 15.0, 345.0, 32, 4, r * 0.13, r * 0.03)
		for v in [-4, -2, 0, 2, 4]:
			_num(r * 0.66, 180.0 + v * 41.0, str(absi(v)), r * 0.2)
		_txt(Vector2(-r * 0.2, -r * 0.32), "UP", r * 0.11, INK)
		_txt(Vector2(-r * 0.2, r * 0.32), "DOWN", r * 0.11, INK)
		_txt(Vector2(r * 0.38, 0), "x1000", r * 0.09, INK)
	if not L:
		return
	_needle(180.0 + clampf(float(d["vs"]), -4000.0, 4000.0) / 1000.0 * 41.0, r * 0.9, r * 0.07, Color.WHITE)
	_hub(r * 0.1)


func _di_s() -> void:
	# the direction indicator's drum card in a window
	var r := _begin("di")
	var c := _at("di")
	var win := Rect2(c + Vector2(-r * 0.72, -r * 0.24), Vector2(r * 1.44, r * 0.48))
	if S:
		_txt(Vector2(0, -r * 0.5), "DIRECTION", r * 0.1, INK)
		_txt(Vector2(0, r * 0.62), "SET", r * 0.1, INK)
	if not L:
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_rect(win, Color("#141414"))
	var hd := fposmod(float(d["heading"]), 360.0)
	var ppd := win.size.x / 60.0      # 60 degrees across the window
	var start := int(floor((hd - 30.0) / 5.0)) * 5
	for k in range(start, start + 70, 5):
		var x := win.position.x + win.size.x / 2.0 + (k - hd) * ppd
		if x < win.position.x + 2 or x > win.end.x - 2:
			continue
		var big := k % 10 == 0
		draw_line(Vector2(x, win.position.y), Vector2(x, win.position.y + win.size.y * (0.35 if big else 0.2)), INK, 2.0, true)
		if k % 30 == 0:
			var n := int(fposmod(k, 360)) / 10
			var t := "N" if n == 0 else ("E" if n == 9 else ("S" if n == 18 else ("W" if n == 27 else str(n))))
			_txt(Vector2(x, win.position.y + win.size.y * 0.7), t, r * 0.2, INK)
	draw_line(Vector2(win.position.x + win.size.x / 2.0, win.position.y - 2), Vector2(win.position.x + win.size.x / 2.0, win.end.y + 2), Color("#f2a33a"), 3.0)


func _ts() -> void:
	# turn and slip: the turn needle above, the slip needle below
	var r := _begin("ts")
	if S:
		for s in [-1.0, 1.0]:
			var a := deg_to_rad(-90.0 + s * 22.0)
			draw_line(Vector2(cos(a), sin(a)) * r * 0.95, Vector2(cos(a), sin(a)) * r * 0.78, INK, r * 0.04, true)
		draw_line(Vector2(0, -r * 0.95), Vector2(0, -r * 0.78), INK, r * 0.04, true)
		_txt(Vector2(-r * 0.55, -r * 0.05), "L", r * 0.16, INK)
		_txt(Vector2(r * 0.55, -r * 0.05), "R", r * 0.16, INK)
		_txt(Vector2(0, r * 0.15), "TURN", r * 0.1, INK)
		_txt(Vector2(0, r * 0.8), "SLIP", r * 0.09, INK)
	if not L:
		return
	var turn := deg_to_rad(-90.0 + clampf(float(d["turn"]) / 3.0 * 22.0, -45.0, 45.0))
	draw_line(Vector2.ZERO, Vector2(cos(turn), sin(turn)) * r * 0.88, Color.WHITE, r * 0.06, true)
	var slip := deg_to_rad(90.0 - clampf(float(d["slip"]) * 2.0, -35.0, 35.0))
	draw_line(Vector2(0, r * 0.1), Vector2(cos(slip), sin(slip)) * r * 0.7 + Vector2(0, r * 0.1), Color.WHITE, r * 0.05, true)
	_hub(r * 0.09)


func _rpm_s() -> void:
	var r := _begin("rpm")
	var a := func(v: float) -> float: return _map(v, 0.0, 5000.0, 135.0, 405.0)
	if S:
		_arc(r * 0.88, a.call(2650.0), a.call(3000.0), r * 0.07, YELLOW)
		var rl := deg_to_rad(a.call(3000.0))
		draw_line(Vector2(cos(rl), sin(rl)) * r * 0.97, Vector2(cos(rl), sin(rl)) * r * 0.74, RED, r * 0.05, true)
		_ticks(r * 0.97, 135.0, 405.0, 50, 5, r * 0.13, r * 0.03)
		for v in [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50]:
			_num(r * 0.66, a.call(v * 100.0), str(v), r * 0.17)
		_txt(Vector2(0, -r * 0.32), "R.P.M.", r * 0.12, INK)
		_txt(Vector2(0, r * 0.32), "x100", r * 0.11, INK)
	if not L:
		return
	_needle(a.call(float(d["rpm"])), r * 0.9, r * 0.07, Color.WHITE)
	_hub(r * 0.1)


func _boost() -> void:
	# boost (supercharger) pressure, lb/sq in: -7 to +24, the Merlin 66's combat limit +18
	var r := _begin("boost")
	var a := func(v: float) -> float: return _map(v, -7.0, 24.0, 135.0, 405.0)
	if S:
		var rl := deg_to_rad(a.call(18.0))
		draw_line(Vector2(cos(rl), sin(rl)) * r * 0.97, Vector2(cos(rl), sin(rl)) * r * 0.74, RED, r * 0.05, true)
		_ticks(r * 0.97, 135.0, 405.0, 31, 2, r * 0.14, r * 0.03)
		for v in [-6, -2, 0, 4, 8, 12, 16, 20, 24]:
			_num(r * 0.64, a.call(float(v)), str(v), r * 0.17)
		_txt(Vector2(0, r * 0.36), "BOOST", r * 0.12, INK)
		_txt(Vector2(0, -r * 0.3), "LBS/SQ IN", r * 0.09, INK)
	if not L:
		return
	var alt := float(d["alt"])
	var boost := lerpf(-6.0, 18.0, float(d["throttle"])) - maxf(alt - 21000.0, 0.0) / 1500.0
	_needle(a.call(boost), r * 0.9, r * 0.08, Color.WHITE)
	_hub(r * 0.12)


func _small(name: String, title: String, unit: String, v0: float, v1: float, v: float, marks: Array) -> void:
	var r := _begin(name)
	var a := func(x: float) -> float: return _map(x, v0, v1, 150.0, 390.0)
	if S:
		_ticks(r * 0.96, 150.0, 390.0, 8, 2, r * 0.18, r * 0.05)
		for m in marks:
			_num(r * 0.58, a.call(float(m)), str(m), r * 0.26)
		_txt(Vector2(0, r * 0.45), title, r * 0.2, INK)
		if unit != "":
			_txt(Vector2(0, -r * 0.4), unit, r * 0.17, INK)
	if not L:
		return
	var val := v
	if name == "oilp":
		val = 20.0 + 60.0 * clampf(float(d["rpm"]) / 3000.0, 0.0, 1.0)
	elif name == "radt":
		val = 70.0 + 30.0 * float(d["throttle"])
	elif name == "oilt":
		val = 50.0 + 30.0 * float(d["throttle"])
	_needle(a.call(val), r * 0.86, r * 0.1, Color.WHITE)
	_hub(r * 0.14)
