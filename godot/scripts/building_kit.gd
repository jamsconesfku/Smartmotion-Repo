class_name BuildingKit
extends RefCounted
## v1.23.0: real-looking buildings from the map's footprints (Sam: "make sure the buildings actually look like real
## buildings ... the windows don't line up"). Simple, few types, built so that what makes a building read as real is
## right: walls that end at proper corners, roofs with an overhang, fascia boards and ridge, chimneys, and windows and
## doors laid out wall by wall (whole windows, evenly spaced, centred, the same height on every wall, one front door).
##
## Types (picked from the footprint's shape, size and height):
##   house     a near-rectangular home: two storeys or a bungalow, gable or hipped roof (35-42 degrees), chimney
##   terrace   a long, narrow row: a door and two windows per home along the front, chimneys on the party walls
##   wings     an L-, T- or U-shaped home split into rectangles, each with its own roof
##   shed      barns, hangars, warehouses: profiled metal walls on a block plinth, shallow metal roof, a roller door
##   block     shops, offices, flats, schools and odd shapes: the real outline, flat roof, a row of windows per floor
##
## Thread-safe (runs on the scenery's worker threads). Windows and doors are drawn by shaders/building.gdshader from
## each wall's own coordinates (UV: metres along this wall, metres above the ground; UV2: wall length, layout code),
## so they cost nothing in triangles. COLOR.rgb = tint, COLOR.a = material id / 16 (see M_*).

const M_BRICK := 0
const M_RENDER := 1
const M_CLAD := 2         # profiled metal sheet walls
const M_OFFICE := 3       # brick or render with wide office windows
const M_TILE := 4         # clay / concrete roof tiles
const M_SLATE := 5
const M_SHEET := 6        # profiled metal roof
const M_FLAT := 7         # flat roof (felt, gravel)
const M_TRIM := 8         # fascia boards, bargeboards, copings (painted timber / uPVC)
const M_STACK := 9        # chimney stacks (brick, no windows)
const M_POT := 10         # chimney pots (terracotta)

## door modes in the wall layout code
const D_NONE := 0
const D_ONE := 1          # one front door, at window position `d`
const D_EVERY := 2        # a door in every home of a terrace (each home is two window bays)
const D_ROLLER := 3       # a big roller door in the middle (sheds)

var v := PackedVector3Array()
var n := PackedVector3Array()
var c := PackedColorArray()
var uv := PackedVector2Array()
var uv2 := PackedVector2Array()


static func code(windows: int, floors: int, door_mode: int, door_at: int, style: int) -> float:
	# windows 0-63, floors 0-7, door mode 0-3, door bay 0-31, style 0-7 (window type)
	return float(windows + 64 * floors + 512 * door_mode + 2048 * door_at + 65536 * style)


func _tri(a: Vector3, b: Vector3, cc: Vector3, nn: Vector3, col: Color, ua: Vector2, ub: Vector2, uc: Vector2, w2: Vector2) -> void:
	# Godot front faces are clockwise as seen from outside: order the corners to match the normal
	if (b - a).cross(cc - a).dot(nn) > 0.0:
		v.append_array([a, cc, b])
		uv.append_array([ua, uc, ub])
	else:
		v.append_array([a, b, cc])
		uv.append_array([ua, ub, uc])
	n.append_array([nn, nn, nn])
	c.append_array([col, col, col])
	uv2.append_array([w2, w2, w2])


func _quad(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, nn: Vector3, col: Color, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, w2 := Vector2.ZERO) -> void:
	_tri(a, b, cc, nn, col, ua, ub, uc, w2)
	_tri(a, cc, d, nn, col, ua, uc, ud, w2)


static func _col(rgb: Color, id: int) -> Color:
	return Color(rgb.r, rgb.g, rgb.b, (float(id) + 0.5) / 16.0)


## A wall from a to b (on the ground at height g0, base below it) up to height `top`, facing `out`.
## The wall's own u runs along the shader's tangent (so windows line up with the wall and its corners).
func wall(a: Vector2, b: Vector2, base: float, g0: float, top: float, out: Vector3, col: Color, w_code: float) -> void:
	var t := Vector3(-out.z, 0.0, out.x)
	var A := Vector3(a.x, base, a.y)
	var B := Vector3(b.x, base, b.y)
	var len := a.distance_to(b)
	var ua := 0.0
	var ub := len
	if (B - A).dot(t) < 0.0:
		ua = len
		ub = 0.0
	var w2 := Vector2(len, w_code)
	_quad(A, B, Vector3(b.x, top, b.y), Vector3(a.x, top, a.y), out, col,
		Vector2(ub * 0.0 + ua, base - g0), Vector2(ub, base - g0), Vector2(ub, top - g0), Vector2(ua, top - g0), w2)


## A gable end: the triangle above the eaves (wall material, no windows), u along the wall as for the wall below.
func gable(a: Vector3, b: Vector3, apex: Vector3, g0: float, out: Vector3, col: Color) -> void:
	var t := Vector3(-out.z, 0.0, out.x)
	var len := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
	var ua := 0.0 if (b - a).dot(t) >= 0.0 else len
	var ub := len - ua
	_tri(a, b, apex, out, col, Vector2(ua, a.y - g0), Vector2(ub, b.y - g0), Vector2(len / 2.0, apex.y - g0), Vector2(len, 0.0))


## A box (chimney stack, pot, roof plant): centre on the ground of the box, size, along axis ax.
func box(cx: Vector3, ax: Vector2, size: Vector3, col: Color) -> void:
	var a := Vector3(ax.x, 0, ax.y) * size.x * 0.5
	var b := Vector3(-ax.y, 0, ax.x) * size.z * 0.5
	var y0 := cx.y
	var y1 := cx.y + size.y
	var p := [cx - a - b, cx + a - b, cx + a + b, cx - a + b]
	for i in 4:
		var p0: Vector3 = p[i]
		var p1: Vector3 = p[(i + 1) % 4]
		var mid := (p0 + p1) / 2.0 - cx
		var nn := Vector3(mid.x, 0, mid.z).normalized()
		var L := p0.distance_to(p1)
		_quad(Vector3(p0.x, y0, p0.z), Vector3(p1.x, y0, p1.z), Vector3(p1.x, y1, p1.z), Vector3(p0.x, y1, p0.z), nn, col,
			Vector2(0, 0), Vector2(L, 0), Vector2(L, size.y), Vector2(0, size.y), Vector2(L, 0.0))
	_quad(Vector3(p[0].x, y1, p[0].z), Vector3(p[1].x, y1, p[1].z), Vector3(p[2].x, y1, p[2].z), Vector3(p[3].x, y1, p[3].z), Vector3.UP, col,
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))


# ---------------------------------------------------------------- footprint analysis
## The smallest rectangle round the footprint, along one of its own edges: [axis, lo, hi] in that axis' frame.
static func obb(pts: PackedVector2Array) -> Array:
	var best_area := 1e18
	var best: Array = []
	var nv := pts.size()
	for i in nv:
		var d := pts[(i + 1) % nv] - pts[i]
		if d.length() < 0.5:
			continue
		var ax := d.normalized()
		var lo := Vector2(1e9, 1e9)
		var hi := Vector2(-1e9, -1e9)
		for p in pts:
			var q := Vector2(p.dot(ax), p.dot(Vector2(-ax.y, ax.x)))
			lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
			hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
		var ar := (hi.x - lo.x) * (hi.y - lo.y)
		if ar < best_area:
			best_area = ar
			best = [ax, lo, hi]
	return best


static func poly_area(pts: PackedVector2Array) -> float:
	var a := 0.0
	for i in pts.size():
		var p := pts[i]
		var q := pts[(i + 1) % pts.size()]
		a += p.x * q.y - q.x * p.y
	return a / 2.0


## True if every wall (longer than 0.8 m) runs within 12 degrees of the rectangle's sides.
static func square_cornered(pts: PackedVector2Array, ax: Vector2) -> bool:
	for i in pts.size():
		var d := pts[(i + 1) % pts.size()] - pts[i]
		if d.length() < 0.8:
			continue
		var ca := absf(d.normalized().dot(ax))
		if ca > 0.208 and ca < 0.978:
			return false
	return true


## An L-, T- or U-shaped footprint as up to four rectangles (in the axis frame: [lo, hi] each), or [] if it isn't one.
static func split_rects(pts: PackedVector2Array, ax: Vector2) -> Array:
	var bx := Vector2(-ax.y, ax.x)
	var loc := PackedVector2Array()
	var us: Array = []
	var vs: Array = []
	for p in pts:
		var q := Vector2(p.dot(ax), p.dot(bx))
		loc.append(q)
		us.append(q.x)
		vs.append(q.y)
	us = _merge_close(us)
	vs = _merge_close(vs)
	if us.size() > 6 or vs.size() > 6 or us.size() < 2 or vs.size() < 2:
		return []
	var cells := {}
	for i in range(us.size() - 1):
		for j in range(vs.size() - 1):
			var cc := Vector2((us[i] + us[i + 1]) / 2.0, (vs[j] + vs[j + 1]) / 2.0)
			if Geometry2D.is_point_in_polygon(cc, loc):
				cells[Vector2i(i, j)] = true
	# strips along u in each row, then strips with the same ends stacked into rectangles
	var strips: Array = []
	for j in range(vs.size() - 1):
		var i := 0
		while i < us.size() - 1:
			if cells.has(Vector2i(i, j)):
				var i1 := i
				while i1 + 1 < us.size() - 1 and cells.has(Vector2i(i1 + 1, j)):
					i1 += 1
				strips.append([i, i1, j, j])
				i = i1 + 1
			else:
				i += 1
	var merged := true
	while merged:
		merged = false
		for a in strips.size():
			for b in strips.size():
				if a == b:
					continue
				var s: Array = strips[a]
				var t: Array = strips[b]
				if s[0] == t[0] and s[1] == t[1] and int(t[2]) == int(s[3]) + 1:
					s[3] = t[3]
					strips.remove_at(b)
					merged = true
					break
			if merged:
				break
	if strips.is_empty() or strips.size() > 4:
		return []
	var out: Array = []
	for s in strips:
		var lo := Vector2(us[int(s[0])], vs[int(s[2])])
		var hi := Vector2(us[int(s[1]) + 1], vs[int(s[3]) + 1])
		if (hi - lo).x < 2.0 or (hi - lo).y < 2.0:
			return []
		out.append([lo, hi])
	return out


static func _merge_close(a: Array) -> Array:
	a.sort()
	var out: Array = []
	for x in a:
		if out.is_empty() or float(x) - float(out[out.size() - 1]) > 0.45:
			out.append(x)
	return out


# ---------------------------------------------------------------- building
## Adds one building. pts: footprint (x, z), h: height to the top, kind: 0 house, 1 big low, 2 other (from the map).
func add(pts: PackedVector2Array, h: float, kind: int, gmin: float, rng: RandomNumberGenerator) -> void:
	var area := absf(poly_area(pts))
	var bb := obb(pts)
	if bb.is_empty():
		return
	var ax: Vector2 = bb[0]
	var lo: Vector2 = bb[1]
	var hi: Vector2 = bb[2]
	var rect_area := (hi.x - lo.x) * (hi.y - lo.y)
	var fill := area / maxf(rect_area, 0.01)
	var pal := _palette(rng, kind)
	if kind == 1:
		if fill > 0.75:
			_shed(ax, lo, hi, h, gmin, rng)
		else:
			_block(pts, h, gmin, rng, pal, true)
		return
	if kind == 2 or area > 450.0 or h > 13.0:
		_block(pts, h, gmin, rng, pal, false)
		return
	if fill > 0.86:
		_house_rect(ax, lo, hi, h, gmin, rng, pal, true)
		return
	if square_cornered(pts, ax):
		var rects := split_rects(pts, ax)
		if not rects.is_empty():
			# the biggest part has the front door and the chimney; the others are wings
			var big := 0
			for i in rects.size():
				var r: Array = rects[i]
				var r0: Array = rects[big]
				if ((r[1] as Vector2) - (r[0] as Vector2)).x * ((r[1] as Vector2) - (r[0] as Vector2)).y > ((r0[1] as Vector2) - (r0[0] as Vector2)).x * ((r0[1] as Vector2) - (r0[0] as Vector2)).y:
					big = i
			for i in rects.size():
				var r2: Array = rects[i]
				_house_rect(ax, r2[0], r2[1], h if i == big else h * 0.92, gmin, rng, pal, i == big)
			return
	_block(pts, minf(h, 6.0), gmin, rng, pal, false)


## Colours for one building: wall (brick / render), roof (clay, concrete, slate), trim, door.
func _palette(rng: RandomNumberGenerator, kind: int) -> Dictionary:
	var bricks := [Color("#9a5a46"), Color("#a8634a"), Color("#8c4b3c"), Color("#b98d62"), Color("#a67b55"), Color("#7e4a3a")]
	var renders := [Color("#ece7dc"), Color("#f2efe7"), Color("#e4dbc8"), Color("#d9d4c8"), Color("#cfc6b4")]
	var roofs := [[Color("#8a4433"), M_TILE], [Color("#73402f"), M_TILE], [Color("#5a3b30"), M_TILE], [Color("#4a4744"), M_TILE], [Color("#3f444b"), M_SLATE], [Color("#4b4f55"), M_SLATE]]
	var r_wall := rng.randf()
	var brick := r_wall < 0.62
	var w: Color = (bricks[rng.randi() % bricks.size()] if brick else renders[rng.randi() % renders.size()]) as Color
	var rf: Array = roofs[rng.randi() % roofs.size()]
	return {"wall": w, "wall_id": M_BRICK if brick else M_RENDER, "roof": rf[0], "roof_id": rf[1],
		"trim": Color("#f1f1ec") if rng.randf() < 0.8 else Color("#2c2f30"), "style": rng.randi() % 4}


## A house on a rectangle (lo..hi in the axis frame).
func _house_rect(ax: Vector2, lo: Vector2, hi: Vector2, h: float, gmin: float, rng: RandomNumberGenerator, pal: Dictionary, main: bool) -> void:
	var bx := Vector2(-ax.y, ax.x)
	var size := hi - lo
	var along := ax                       # the ridge runs along the long side
	var across := bx
	var L := size.x
	var W := size.y
	var ctr := ax * (lo.x + hi.x) / 2.0 + bx * (lo.y + hi.y) / 2.0
	if size.y > size.x:
		along = bx
		across = ax
		L = size.y
		W = size.x
	var terrace := L > 13.0 and W < 10.5 and L / W > 1.7
	var hip := not terrace and rng.randf() < 0.38 and L > 5.0
	var pitch := deg_to_rad(rng.randf_range(35.0, 42.0))
	var ridge := W / 2.0 * tan(pitch)
	ridge = minf(ridge, maxf(h - 2.4, 1.2))
	var eaves := maxf(h - ridge, 2.4)
	var floors := clampi(int(round((eaves - 0.3) / 2.65)), 1, 3)
	var base := gmin - 0.6
	var wc := _col(pal["wall"], pal["wall_id"])
	# corners, anticlockwise from the far-left
	var hl := along * L / 2.0
	var hw := across * W / 2.0
	var cs := [ctr - hl - hw, ctr + hl - hw, ctr + hl + hw, ctr - hl + hw]
	var front := 0 if rng.randf() < 0.5 else 2   # one of the long walls has the front door
	var style: int = pal["style"]
	for i in 4:
		var a: Vector2 = cs[i]
		var b: Vector2 = cs[(i + 1) % 4]
		var mid := (a + b) / 2.0 - ctr
		var out := Vector3(mid.x, 0, mid.y).normalized()
		var len := a.distance_to(b)
		var nw := int(floor((len - 0.6) / 2.4)) if len >= 2.2 else 0
		var long_wall := i % 2 == 0
		var w_code: float
		if terrace and long_wall:
			var homes := maxi(2, int(round(len / 5.2)))
			w_code = code(homes * 2, floors, D_EVERY if i == front else D_NONE, 0, style)
		else:
			nw = clampi(nw, 0, 12)
			if not long_wall:
				nw = mini(nw, 2)   # gable ends have a window or two, if any
			var door_mode := D_ONE if (main and i == front and nw > 0) else D_NONE
			var door_at := nw / 2 if nw > 1 else 0
			if door_mode == D_ONE and nw == 1:
				nw = 2
				door_at = rng.randi() % 2
			w_code = code(nw, floors, door_mode, door_at, style)
		wall(a, b, base, gmin, gmin + eaves, out, wc, w_code)
	_roof(cs, along, across, L, W, ctr, gmin + eaves, ridge, hip, pal, gmin, rng, terrace, main)


## Roof over four corners (cs[0]-cs[1] is a long side): gable or hipped, 0.3 m eaves overhang, fascia, verges.
func _roof(cs: Array, along: Vector2, across: Vector2, L: float, W: float, ctr: Vector2, eaves_y: float, ridge: float,
		hip: bool, pal: Dictionary, gmin: float, rng: RandomNumberGenerator, terrace: bool, main: bool) -> void:
	var o := 0.3                                     # eaves overhang
	var vg := 0.18 if not hip else 0.3               # verge overhang
	var slope := ridge / (W / 2.0)
	var drop := o * slope                            # the eaves edge is lower than the wall top by this much
	var rc := _col(pal["roof"], pal["roof_id"])
	var tc := _col(pal["trim"], M_TRIM)
	var A3 := Vector3(along.x, 0, along.y)
	var C3 := Vector3(across.x, 0, across.y)
	var c3 := Vector3(ctr.x, eaves_y, ctr.y)
	var ridge_half := L / 2.0 + vg if not hip else maxf(L / 2.0 - W / 2.0, 0.0)
	var R0 := c3 - A3 * ridge_half + Vector3(0, ridge, 0)
	var R1 := c3 + A3 * ridge_half + Vector3(0, ridge, 0)
	var ex := L / 2.0 + (vg if not hip else o)       # how far the eaves run along the house
	var ew := W / 2.0 + o
	var e_y := eaves_y - drop
	var slope_len := sqrt(ew * ew + (ridge + drop) * (ridge + drop))
	for s: float in [-1.0, 1.0]:
		# the two long roof planes (trapezoids on a hipped roof)
		var E0 := c3 - A3 * ex + C3 * s * ew + Vector3(0, e_y - eaves_y, 0)
		var E1 := c3 + A3 * ex + C3 * s * ew + Vector3(0, e_y - eaves_y, 0)
		var nrm := (C3 * s * (ridge + drop) + Vector3(0, ew, 0)).normalized()
		_quad(E0, E1, R1, R0, nrm, rc, Vector2(0, slope_len), Vector2(2.0 * ex, slope_len), Vector2(ex + ridge_half, 0), Vector2(ex - ridge_half, 0))
		# fascia board along the eaves and the soffit under the overhang
		var F0 := E0 + Vector3(0, -0.2, 0)
		var F1 := E1 + Vector3(0, -0.2, 0)
		_quad(F0, F1, E1, E0, C3 * s, tc, Vector2(0, 0), Vector2(2.0 * ex, 0), Vector2(2.0 * ex, 0.2), Vector2(0, 0.2))
		var W0 := c3 - A3 * ex + C3 * s * (W / 2.0) + Vector3(0, -0.2 - drop, 0)
		var W1 := c3 + A3 * ex + C3 * s * (W / 2.0) + Vector3(0, -0.2 - drop, 0)
		_quad(W0, W1, F1, F0, Vector3.DOWN, _col(pal["trim"].darkened(0.35), M_TRIM), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
		if hip:
			# the hipped ends: triangles down to the short sides
			var H0 := c3 + A3 * s * ex - C3 * ew + Vector3(0, e_y - eaves_y, 0)
			var H1 := c3 + A3 * s * ex + C3 * ew + Vector3(0, e_y - eaves_y, 0)
			var Rr := R1 if s > 0.0 else R0
			var hn := (A3 * s * (ridge + drop) + Vector3(0, ex - ridge_half, 0)).normalized()
			var hs := sqrt(pow(ex - ridge_half, 2.0) + pow(ridge + drop, 2.0))
			_tri(H0, H1, Rr, hn, rc, Vector2(0, hs), Vector2(2.0 * ew, hs), Vector2(ew, 0), Vector2.ZERO)
			var G0 := H0 + Vector3(0, -0.2, 0)
			var G1 := H1 + Vector3(0, -0.2, 0)
			_quad(G0, G1, H1, H0, A3 * s, tc, Vector2(0, 0), Vector2(2.0 * ew, 0), Vector2(2.0 * ew, 0.2), Vector2(0, 0.2))
		else:
			# gable end walls up to the ridge, and the bargeboards along the verge
			var g_a := c3 + A3 * s * (L / 2.0) - C3 * (W / 2.0)
			var g_b := c3 + A3 * s * (L / 2.0) + C3 * (W / 2.0)
			var apex := c3 + A3 * s * (L / 2.0) + Vector3(0, ridge, 0)
			gable(g_a, g_b, apex, gmin, A3 * s, _col(pal["wall"], pal["wall_id"]))
			var Rv := R1 if s > 0.0 else R0
			for t: float in [-1.0, 1.0]:
				var Ev := c3 + A3 * s * ex + C3 * t * ew + Vector3(0, e_y - eaves_y, 0)
				_quad(Ev + Vector3(0, -0.22, 0), Rv + Vector3(0, -0.22, 0), Rv + Vector3(0, 0.03, 0), Ev + Vector3(0, 0.03, 0), A3 * s, tc,
					Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	# ridge tiles: a low ridge strip
	var rt := _col(pal["roof"].darkened(0.2), pal["roof_id"])
	if R0.distance_to(R1) > 0.2:
		for s2: float in [-1.0, 1.0]:
			_quad(R0 + Vector3(0, 0.05, 0), R1 + Vector3(0, 0.05, 0), R1 + C3 * s2 * 0.14 + Vector3(0, -0.03, 0), R0 + C3 * s2 * 0.14 + Vector3(0, -0.03, 0),
				(C3 * s2 * 0.4 + Vector3.UP).normalized(), rt, Vector2(0, 0), Vector2(R0.distance_to(R1), 0), Vector2(R0.distance_to(R1), 0.15), Vector2(0, 0.15))
	# chimneys: on most homes, on the ridge; terraces have a stack on every other party wall
	var stack := _col(pal["wall"] if pal["wall_id"] == M_BRICK else Color("#8f5a45"), M_STACK)
	var pot := _col(Color("#a65a3a"), M_POT)
	var spots: Array = []
	if terrace:
		var homes := maxi(2, int(round(L / 5.2)))
		for k in range(1, homes, 2):
			spots.append(-L / 2.0 + L * k / homes)
	elif main and rng.randf() < 0.7 and L > 5.0:
		spots.append((L / 2.0 - 0.9) * (1.0 if rng.randf() < 0.5 else -1.0) * (1.0 if not hip else 0.45))
	for sp in spots:
		var base3 := c3 + A3 * float(sp) + Vector3(0, ridge - 0.4, 0)
		var sw := 0.9 if terrace else 0.6
		box(base3, along, Vector3(sw, 1.45, 0.55), stack)
		for k2 in (2 if terrace else rng.randi_range(1, 2)):
			var off := (float(k2) - 0.5) * 0.28 if terrace or k2 > 0 else 0.0
			box(base3 + A3 * off + Vector3(0, 1.45, 0), along, Vector3(0.2, 0.3, 0.2), pot)


## Barns, hangars, sheds, warehouses: metal walls on a block plinth (drawn by the shader), a shallow metal roof
## with a small overhang, a big roller door in one end.
func _shed(ax: Vector2, lo: Vector2, hi: Vector2, h: float, gmin: float, rng: RandomNumberGenerator) -> void:
	var bx := Vector2(-ax.y, ax.x)
	var size := hi - lo
	var along := ax
	var across := bx
	var L := size.x
	var W := size.y
	if size.y > size.x:
		along = bx
		across = ax
		L = size.y
		W = size.x
	var ctr := ax * (lo.x + hi.x) / 2.0 + bx * (lo.y + hi.y) / 2.0
	var ridge := minf(W / 2.0 * tan(deg_to_rad(rng.randf_range(7.0, 12.0))), maxf(h * 0.35, 0.6))
	var eaves := maxf(h - ridge, 3.0)
	var base := gmin - 0.6
	var cols := [Color("#7c8a7e"), Color("#6f7d86"), Color("#8f9293"), Color("#5f6a5e"), Color("#9a9a92"), Color("#4f5c66")]
	var wc := _col(cols[rng.randi() % cols.size()], M_CLAD)
	var hl := along * L / 2.0
	var hw := across * W / 2.0
	var cs := [ctr - hl - hw, ctr + hl - hw, ctr + hl + hw, ctr - hl + hw]
	var door_end := 1 if rng.randf() < 0.5 else 3
	for i in 4:
		var a: Vector2 = cs[i]
		var b: Vector2 = cs[(i + 1) % 4]
		var mid := (a + b) / 2.0 - ctr
		var out := Vector3(mid.x, 0, mid.y).normalized()
		var wcd := code(0, 0, D_ROLLER if i == door_end else D_NONE, 0, 0)
		wall(a, b, base, gmin, gmin + eaves, out, wc, wcd)
	var roof_cols := [Color("#5d6466"), Color("#6d7270"), Color("#4c5a52"), Color("#7a7b78")]
	var pal := {"roof": roof_cols[rng.randi() % roof_cols.size()], "roof_id": M_SHEET, "trim": Color("#55595a"), "wall": wc, "wall_id": M_CLAD}
	_roof(cs, along, across, L, W, ctr, gmin + eaves, ridge, false, pal, gmin, rng, false, false)


## Anything else: the real outline, walls up to a flat roof with a coping, a row of windows per floor.
func _block(pts: PackedVector2Array, h: float, gmin: float, rng: RandomNumberGenerator, pal: Dictionary, industrial: bool) -> void:
	var nv := pts.size()
	var sgn := 1.0 if poly_area(pts) > 0.0 else -1.0
	var base := gmin - 0.6
	var top := gmin + maxf(h, 3.0)
	var office := not industrial and (h > 7.5 or absf(poly_area(pts)) > 300.0)
	var floor_h := 3.3 if office else 2.8
	var floors := clampi(int(floor((h - 0.4) / floor_h)), 1, 7)
	var wid: int = M_CLAD if industrial else (M_OFFICE if office else int(pal["wall_id"]))
	var wcol: Color = pal["wall"]
	if industrial:
		wcol = [Color("#7c8a7e"), Color("#8f9293"), Color("#6f7d86")][rng.randi() % 3]
	var wc := _col(wcol, wid)
	var style := 4 if office else int(pal["style"])
	var front := -1
	var longest := 0.0
	for i in nv:
		var ln := pts[i].distance_to(pts[(i + 1) % nv])
		if ln > longest:
			longest = ln
			front = i
	for i in nv:
		var a := pts[i]
		var b := pts[(i + 1) % nv]
		var d := b - a
		var len := d.length()
		if len < 0.05:
			continue
		var out := Vector3(d.y, 0, -d.x).normalized() * sgn
		var nw := 0
		if not industrial and len >= 2.4:
			nw = clampi(int(floor((len - 0.6) / (3.0 if office else 2.4))), 0, 63)
		var dm := D_ONE if (i == front and nw > 0) else (D_ROLLER if industrial and i == front else D_NONE)
		wall(a, b, base, gmin, top, out, wc, code(nw, floors, dm, nw / 2, style))
	# flat roof, and a coping strip round its edge
	var rc := _col(Color("#5b5c5a").lerp(Color("#77746c"), rng.randf()), M_FLAT)
	var tris := Geometry2D.triangulate_polygon(pts)
	for t in range(0, tris.size(), 3):
		var a2 := pts[tris[t]]
		var b2 := pts[tris[t + 1]]
		var c2 := pts[tris[t + 2]]
		_tri(Vector3(a2.x, top, a2.y), Vector3(b2.x, top, b2.y), Vector3(c2.x, top, c2.y), Vector3.UP, rc, a2, b2, c2, Vector2.ZERO)
	var cc := _col(Color("#b8b4aa") if not industrial else Color("#6b6f70"), M_TRIM)
	for i in nv:
		var a3 := pts[i]
		var b3 := pts[(i + 1) % nv]
		var d3 := b3 - a3
		if d3.length() < 0.05:
			continue
		var out3 := Vector3(d3.y, 0, -d3.x).normalized() * sgn
		var o3 := Vector2(out3.x, out3.z) * 0.06
		_quad(Vector3(a3.x + o3.x, top - 0.25, a3.y + o3.y), Vector3(b3.x + o3.x, top - 0.25, b3.y + o3.y), Vector3(b3.x + o3.x, top + 0.12, b3.y + o3.y), Vector3(a3.x + o3.x, top + 0.12, a3.y + o3.y),
			out3, cc, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	# plant and stair housings on big flat roofs
	if absf(poly_area(pts)) > 400.0 and tris.size() >= 3:
		var bb := obb(pts)
		var ax: Vector2 = bb[0]
		var cxy: Vector2 = (pts[tris[0]] + pts[tris[1]] + pts[tris[2]]) / 3.0
		box(Vector3(cxy.x, top, cxy.y), ax, Vector3(rng.randf_range(2.0, 4.0), rng.randf_range(1.0, 2.2), rng.randf_range(1.5, 3.0)), _col(Color("#8c8d8a"), M_CLAD))


func arrays() -> Array:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_COLOR] = c
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	return arr
