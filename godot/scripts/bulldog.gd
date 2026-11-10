class_name Bulldog
extends RefCounted
## Scottish Aviation Bulldog 120 / T.1, as Skysmart's G-SMAT (ex-RAF XX658, code 07), built entirely in code.
## Real dimensions: span 10.06 m, length 7.09 m, height 2.28 m, wing area 12.02 m2, two-blade 1.88 m Hartzell
## propeller, fixed tricycle gear, side-by-side seats under a sliding bubble canopy, centre control sticks.
## Livery: RAF light-trainer scheme (white upper surfaces, light grey undersides, signal-red bands and tips,
## black anti-glare panel, type D roundels, fin flash). Body axes: x right, y up, z back (nose is -z), metres,
## origin at the centre of gravity; the wheels touch the ground at y = -1.05.

const SILL := 0.22                      # top of the cockpit sides (the canopy sits on this)
const CK0 := -0.62                      # cockpit opening, front (windscreen base)
const CK1 := 1.0                        # cockpit opening, rear
const SE_N := 2.6                       # cross-section "squareness" (2 = ellipse)
## fuselage stations: z, half width, top, bottom
const ST := [
	[-2.04, 0.20, 0.10, -0.25], [-1.88, 0.33, 0.19, -0.37], [-1.58, 0.44, 0.28, -0.46], [-1.12, 0.52, 0.35, -0.51],
	[-0.62, 0.57, 0.40, -0.53], [-0.2, 0.60, 0.39, -0.53], [0.4, 0.60, 0.38, -0.51], [1.0, 0.55, 0.40, -0.45],
	[1.6, 0.45, 0.42, -0.36], [2.4, 0.33, 0.37, -0.24], [3.3, 0.22, 0.30, -0.10], [4.1, 0.13, 0.26, 0.0], [4.74, 0.04, 0.24, 0.12],
]
## wing: root at x = 0.42, tip at 5.03; chord 1.45 -> 0.95; leading edge z -0.62 -> -0.42; 6 degrees dihedral
const W_X0 := 0.42
const W_X1 := 5.03
const W_Y0 := -0.40
const DIHED := 0.105

var am: AircraftModel
var V := PackedVector3Array()
var NN := PackedVector3Array()
var CC := PackedColorArray()

var WHITE := Color("#f1f2ef").srgb_to_linear()
var GREY := Color("#a9adb0").srgb_to_linear()
var RED := Color("#c8102e").srgb_to_linear()
var BLACK := Color("#18191b").srgb_to_linear()
var BLUE := Color("#1f2f6b").srgb_to_linear()
var YELLOW := Color("#f2c400").srgb_to_linear()
var INTERIOR := Color("#2d2f33").srgb_to_linear()

var paint: StandardMaterial3D
var matte: StandardMaterial3D
var glass: StandardMaterial3D
var steel: StandardMaterial3D
var rubber: StandardMaterial3D
var interior_m: StandardMaterial3D

var stick_r: Node3D
var pedals: Array = []          # [node, side(+1 right pedal / -1 left), base z]
var throttle_lever: Node3D
var flap_lever: Node3D
var trim_wheel: Node3D
var flaps: Array = []           # flap hinge nodes (rotate down with flaps)
var instructor_head: Node3D
var panel_ui: BulldogPanel


# ---------------------------------------------------------------- mesh helpers
func _begin() -> void:
	V = PackedVector3Array()
	NN = PackedVector3Array()
	CC = PackedColorArray()


func _t3(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	# Godot front faces are clockwise as seen from the front: order the corners to match the normals
	if (b - a).cross(c - a).dot(na + nb + nc) > 0.0:
		V.append_array([a, c, b]); NN.append_array([na, nc, nb]); CC.append_array([ca, cc, cb])
	else:
		V.append_array([a, b, c]); NN.append_array([na, nb, nc]); CC.append_array([ca, cb, cc])


func _q(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
	_t3(a, b, c, n, n, n, col, col, col)
	_t3(a, c, d, n, n, n, col, col, col)


func _end(mat: Material, parent: Node3D, shadow := true) -> MeshInstance3D:
	if V.size() == 0:
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = V
	arrays[Mesh.ARRAY_NORMAL] = NN
	arrays[Mesh.ARRAY_COLOR] = CC
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	_begin()
	return mi


## A grid of points (rows x cols) -> smooth-shaded surface. out_fn(p) gives a rough "outwards" direction
## to orient normals; col_fn(p, n) the colour; keep_fn(p0, p1, p2, p3) can drop quads (cut-outs).
func _grid(P: Array, wrap: bool, out_fn: Callable, col_fn: Callable, keep_fn := Callable()) -> void:
	var rows := P.size()
	var cols: int = P[0].size()
	var N: Array = []
	for j in rows:
		var row: Array = []
		for i in cols:
			var im := (i - 1 + cols) % cols if wrap else maxi(i - 1, 0)
			var ip := (i + 1) % cols if wrap else mini(i + 1, cols - 1)
			var jm := maxi(j - 1, 0)
			var jp := mini(j + 1, rows - 1)
			var du: Vector3 = P[j][ip] - P[j][im]
			var dv: Vector3 = P[jp][i] - P[jm][i]
			var n := du.cross(dv)
			if n.length() < 1e-9:
				n = out_fn.call(P[j][i])
			n = n.normalized()
			if n.dot(out_fn.call(P[j][i])) < 0.0:
				n = -n
			row.append(n)
		N.append(row)
	var ilast := cols if wrap else cols - 1
	for j in rows - 1:
		for i in ilast:
			var i2 := (i + 1) % cols
			var a: Vector3 = P[j][i]
			var b: Vector3 = P[j][i2]
			var c: Vector3 = P[j + 1][i2]
			var d: Vector3 = P[j + 1][i]
			if keep_fn.is_valid() and not keep_fn.call(a, b, c, d):
				continue
			var na: Vector3 = N[j][i]
			var nb: Vector3 = N[j][i2]
			var nc: Vector3 = N[j + 1][i2]
			var nd: Vector3 = N[j + 1][i]
			_t3(a, b, c, na, nb, nc, col_fn.call(a, na), col_fn.call(b, nb), col_fn.call(c, nc))
			_t3(a, c, d, na, nc, nd, col_fn.call(a, na), col_fn.call(c, nc), col_fn.call(d, nd))


func _cap(ring: Array, n: Vector3, col: Color) -> void:
	var c := Vector3.ZERO
	for p in ring:
		c += p
	c /= ring.size()
	for i in ring.size():
		_t3(c, ring[i], ring[(i + 1) % ring.size()], n, n, n, col, col, col)


func _limb(parent: Node3D, a: Vector3, b: Vector3, r: float, mat: Material, cap := true) -> MeshInstance3D:
	# a rounded rod from a to b
	var mi := MeshInstance3D.new()
	var len := a.distance_to(b)
	if cap:
		var cm := CapsuleMesh.new()
		cm.radius = r
		cm.height = len + 2.0 * r
		cm.radial_segments = 12
		cm.rings = 4
		mi.mesh = cm
	else:
		var cy := CylinderMesh.new()
		cy.top_radius = r
		cy.bottom_radius = r
		cy.height = len
		cy.radial_segments = 10
		cy.rings = 1
		mi.mesh = cy
	mi.material_override = mat
	var up := (b - a).normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	mi.transform = Transform3D(Basis(side, up, side.cross(up)).orthonormalized(), (a + b) / 2.0)
	parent.add_child(mi)
	return mi


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _sph(parent: Node3D, r: float, pos: Vector3, mat: Material, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 20
	sm.rings = 10
	mi.mesh = sm
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	parent.add_child(mi)
	return mi


func _mat(col: Color, rough := 0.6, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m


# ---------------------------------------------------------------- shape functions
func fus_at(z: float) -> Array:
	# half width, top, bottom at station z (linear between stations)
	if z <= ST[0][0]:
		return [ST[0][1], ST[0][2], ST[0][3]]
	for k in range(ST.size() - 1):
		var a: Array = ST[k]
		var b: Array = ST[k + 1]
		if z <= b[0]:
			var t := (z - float(a[0])) / (float(b[0]) - float(a[0]))
			return [lerpf(a[1], b[1], t), lerpf(a[2], b[2], t), lerpf(a[3], b[3], t)]
	var l: Array = ST[ST.size() - 1]
	return [l[1], l[2], l[3]]


func se(t: float, hw: float, top: float, bot: float) -> Vector2:
	var c := cos(t)
	var s := sin(t)
	var yc := (top + bot) / 2.0
	var hh := (top - bot) / 2.0
	return Vector2(hw * signf(c) * pow(absf(c), 2.0 / SE_N), yc + hh * signf(s) * pow(absf(s), 2.0 / SE_N))


func fus_x(z: float, y: float) -> float:
	# the fuselage side's x at height y (for decals that hug the skin)
	var f := fus_at(z)
	var yc := (float(f[1]) + float(f[2])) / 2.0
	var hh := (float(f[1]) - float(f[2])) / 2.0
	var r := clampf(absf(y - yc) / hh, 0.0, 1.0)
	return float(f[0]) * pow(1.0 - pow(r, SE_N), 1.0 / SE_N)


func airfoil(f: float, t: float) -> Vector2:
	# NACA-style section: (thickness half, camber line) as fractions of chord at chord fraction f
	f = clampf(f, 0.0, 1.0)
	var yt := 5.0 * t * (0.2969 * sqrt(f) - 0.126 * f - 0.3516 * f * f + 0.2843 * f * f * f - 0.1036 * f * f * f * f)
	var m := 0.02
	var p := 0.4
	var yc := m / (p * p) * (2.0 * p * f - f * f) if f < p else m / ((1.0 - p) * (1.0 - p)) * ((1.0 - 2.0 * p) + 2.0 * p * f - f * f)
	return Vector2(yt, yc)


func wing_geo(ax: float) -> Array:
	# at |x| = ax: chord, leading-edge z, chord-line y, thickness ratio
	var s := clampf((ax - W_X0) / (W_X1 - W_X0), 0.0, 1.0)
	return [lerpf(1.45, 0.95, s), lerpf(-0.62, -0.42, s), W_Y0 + (ax - W_X0) * DIHED, lerpf(0.15, 0.12, s)]


func wing_pt(x: float, f: float, upper: bool) -> Vector3:
	var g := wing_geo(absf(x))
	var a := airfoil(f, g[3])
	var y: float = g[2] + (a.y + (a.x if upper else -a.x)) * float(g[0])
	return Vector3(x, y, float(g[1]) + f * float(g[0]))


func _section(x: float, f0: float, f1: float, n: int) -> Array:
	# closed ring round the aerofoil between chord fractions f0..f1 (upper surface back to front, then lower)
	var ring: Array = []
	for k in n + 1:
		var u := float(k) / n
		var f := f0 + (f1 - f0) * (0.5 - 0.5 * cos(PI * (1.0 - u)))
		ring.append(wing_pt(x, f, true))
	for k in range(1, n):
		var u2 := float(k) / n
		var f2 := f0 + (f1 - f0) * (0.5 - 0.5 * cos(PI * u2))
		ring.append(wing_pt(x, f2, false))
	return ring


# ---------------------------------------------------------------- build
func build(model: AircraftModel, with_cockpit: bool) -> void:
	am = model
	paint = StandardMaterial3D.new()
	paint.vertex_color_use_as_albedo = true
	paint.roughness = 0.38
	paint.clearcoat_enabled = true
	paint.clearcoat = 0.7
	paint.clearcoat_roughness = 0.07
	matte = StandardMaterial3D.new()
	matte.vertex_color_use_as_albedo = true
	matte.roughness = 0.85
	glass = StandardMaterial3D.new()
	glass.albedo_color = Color(0.82, 0.9, 0.97, 0.1)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.02
	glass.metallic_specular = 0.9
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.shadow_to_opacity = false
	steel = _mat(Color("#8a8f96"), 0.35, 0.8)
	rubber = _mat(Color("#141414"), 0.9)
	interior_m = StandardMaterial3D.new()
	interior_m.vertex_color_use_as_albedo = true
	interior_m.roughness = 0.8
	interior_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_begin()
	_fuselage()
	_canopy()
	_wings()
	_tail()
	_gear()
	_prop()
	_markings()
	_details()
	am.eye = Vector3(-0.3, 0.68, 0.22)
	if with_cockpit:
		_people()
		_cockpit()


func _fuselage() -> void:
	var nseg := 40
	var P: Array = []
	# the stations, plus extra ones exactly at the paint edges so the red bands have crisp edges
	var stations: Array = ST.duplicate()
	for z in [-1.87, -1.85, 2.84, 2.86, 3.19, 3.21]:
		var f0 := fus_at(z)
		stations.append([z, f0[0], f0[1], f0[2]])
	stations.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	for st in stations:
		var ring: Array = []
		for i in nseg:
			var t := TAU * i / nseg
			var q := se(t, st[1], st[2], st[3])
			ring.append(Vector3(q.x, q.y, st[0]))
		P.append(ring)
	var out := func(p: Vector3) -> Vector3:
		var f := fus_at(p.z)
		return Vector3(p.x, p.y - (float(f[1]) + float(f[2])) / 2.0, 0.0).normalized()
	var col := func(p: Vector3, n: Vector3) -> Color:
		if p.z > -1.95 and p.z < CK0 + 0.05 and p.y > 0.12 and absf(p.x) < 0.34:
			return BLACK                                   # anti-glare panel
		if p.z > 2.85 and p.z < 3.2:
			return RED                                     # trainer band round the rear fuselage
		if p.z < -1.86:
			return RED                                     # cowling nose ring
		return GREY if p.y < -0.12 else WHITE
	var keep := func(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> bool:
		var in_ck := a.z >= CK0 - 0.01 and c.z <= CK1 + 0.01
		return not (in_ck and a.y > SILL and b.y > SILL and c.y > SILL and d.y > SILL)
	_grid(P, true, out, col, keep)
	# close the cut edge: a flat sill strip on each side
	for s: float in [-1.0, 1.0]:
		var z0 := CK0
		while z0 < CK1 - 0.01:
			var z1 := minf(z0 + 0.1, CK1)
			var x0 := fus_x(z0, SILL) * s
			var x1 := fus_x(z1, SILL) * s
			_q(Vector3(x0, SILL, z0), Vector3(x1, SILL, z1), Vector3(x1 * 0.9, SILL, z1), Vector3(x0 * 0.9, SILL, z0), Vector3.UP, BLACK)
			z0 = z1
	_end(paint, am.fus)
	# tail cone cap
	var f := fus_at(4.74)
	_sph(am.fus, 0.06, Vector3(0, (float(f[1]) + float(f[2])) / 2.0, 4.74), _mat(WHITE, 0.4))


func _canopy() -> void:
	# sliding bubble canopy: sill to a roof that peaks at about 1.03 m
	var prof := [[CK0, 0.42], [-0.45, 0.70], [-0.25, 0.90], [0.05, 1.01], [0.45, 1.03], [0.85, 0.92], [1.05, 0.70], [1.22, 0.44]]
	var P: Array = []
	var nseg := 24
	for k in range(prof.size()):
		var z: float = prof[k][0]
		var top: float = prof[k][1]
		var sw := fus_x(minf(z, CK1), SILL) + 0.005
		var ring: Array = []
		for i in nseg + 1:
			var t := PI * i / nseg
			var c := cos(t)
			var s := sin(t)
			ring.append(Vector3(sw * signf(c) * pow(absf(c), 2.0 / 2.2), SILL + (top - SILL) * pow(s, 2.0 / 2.2), z))
		P.append(ring)
	var out := func(p: Vector3) -> Vector3: return Vector3(p.x, p.y - SILL, 0.0).normalized()
	var col := func(_p: Vector3, _n: Vector3) -> Color: return Color.WHITE
	_grid(P, false, out, col)
	var g := _end(glass, am.outer, false)
	g.name = "canopy"
	# frames: windscreen arch, canopy front bow, rear bow, sill rails
	var frame := _mat(Color("#1c1d20"), 0.5)
	for zf in [-0.3, 1.08]:
		var top := 0.0
		for k in range(prof.size() - 1):
			if zf >= float(prof[k][0]) and zf <= float(prof[k + 1][0]):
				top = lerpf(prof[k][1], prof[k + 1][1], (zf - float(prof[k][0])) / (float(prof[k + 1][0]) - float(prof[k][0])))
		var sw2 := fus_x(minf(zf, CK1), SILL) + 0.012
		var prev := Vector3.ZERO
		for i in 17:
			var t2 := PI * i / 16.0
			var c2 := cos(t2)
			var p2 := Vector3(sw2 * signf(c2) * pow(absf(c2), 2.0 / 2.2), SILL + (top + 0.008 - SILL) * pow(sin(t2), 2.0 / 2.2), zf)
			if i > 0:
				_limb(am.outer, prev, p2, 0.011, frame, false)
			prev = p2
	for s: float in [-1.0, 1.0]:
		var a := Vector3(s * (fus_x(CK0, SILL) + 0.01), SILL + 0.01, CK0)
		var b := Vector3(s * (fus_x(CK1, SILL) + 0.01), SILL + 0.01, 1.2)
		_limb(am.outer, a, b, 0.018, frame, false)


func _wings() -> void:
	var out_w := func(p: Vector3) -> Vector3:
		var g := wing_geo(absf(p.x))
		return Vector3(0, p.y - float(g[2]) - 0.01, (p.z - float(g[1]) - float(g[0]) * 0.35) * 0.3).normalized()
	var col := func(p: Vector3, n: Vector3) -> Color:
		if absf(p.x) > 4.345:
			return RED
		return WHITE if n.y > -0.2 else GREY
	for s: float in [1.0, -1.0]:
		# spanwise pieces: root, flap bay, aileron bay, tip
		var pieces := [[W_X0, 0.62, 0.0, 1.0], [0.62, 2.85, 0.0, 0.74], [2.85, 4.34, 0.0, 0.74], [4.35, 4.85, 0.0, 0.74], [4.85, W_X1, 0.0, 1.0]]
		for pc in pieces:
			var P: Array = []
			var x0: float = pc[0]
			var x1: float = pc[1]
			var nsp := maxi(2, int((x1 - x0) / 0.35) + 1)
			for k in nsp + 1:
				var x := s * lerpf(x0, x1, float(k) / nsp)
				P.append(_section(x, pc[2], pc[3], 14))
			_grid(P, true, out_w, col)
			# close the inboard/outboard ends with flat caps
			for endk in [0, nsp]:
				var ring: Array = P[endk]
				var c := Vector3.ZERO
				for p in ring:
					c += p
				c /= ring.size()
				var nrm := Vector3(s if endk == nsp else -s, 0, 0)
				for i in ring.size():
					var cl: Color = col.call(ring[i], Vector3.UP)
					_t3(c, ring[i], ring[(i + 1) % ring.size()], nrm, nrm, nrm, cl, cl, cl)
		# rounded wing tip
		var tipr: Array = _section(s * W_X1, 0.0, 1.0, 14)
		var tc := Vector3.ZERO
		for p in tipr:
			tc += p
		tc /= tipr.size()
		tc.x += s * 0.07
		for i in tipr.size():
			var a: Vector3 = tipr[i]
			var b: Vector3 = tipr[(i + 1) % tipr.size()]
			var na := (a - tc + Vector3(s * 0.15, 0, 0)).normalized()
			var nb := (b - tc + Vector3(s * 0.15, 0, 0)).normalized()
			_t3(tc, a, b, Vector3(s, 0, 0), na, nb, RED, RED, RED)
	_end(paint, am.outer)
	# moving surfaces: ailerons (outer) and flaps (inner), hinged at 74% chord
	for s: float in [1.0, -1.0]:
		for kind in ["aileron", "flap"]:
			var xa: float = 2.85 if kind == "aileron" else 0.62
			var xb: float = 4.85 if kind == "aileron" else 2.85
			var h0 := wing_pt(s * xa, 0.74, true).lerp(wing_pt(s * xa, 0.74, false), 0.5)
			var h1 := wing_pt(s * xb, 0.74, true).lerp(wing_pt(s * xb, 0.74, false), 0.5)
			var hx := (h1 - h0).normalized() * s       # hinge axis pointing to +x (world right) on both wings
			var zb := hx.cross(Vector3.UP).normalized()     # points back along the chord
			var hb := Basis(hx, zb.cross(hx).normalized(), zb)
			var hinge := Node3D.new()
			hinge.transform = Transform3D(hb, h0)
			am.outer.add_child(hinge)
			var surf: Node3D
			if kind == "aileron":
				surf = am.ail_r if s > 0.0 else am.ail_l
			else:
				surf = Node3D.new()
				flaps.append(surf)
			hinge.add_child(surf)
			var inv := hinge.transform.affine_inverse()
			var P2: Array = []
			var xs: Array = [2.86, 3.4, 3.9, 4.34, 4.35, 4.84] if kind == "aileron" else [0.63, 1.2, 1.8, 2.4, 2.84]
			for xv in xs:
				var x := s * float(xv)
				var ring: Array = []
				for p in _section(x, 0.74, 1.0, 6):
					ring.append(inv * (p as Vector3))
				P2.append(ring)
			var outl := func(p: Vector3) -> Vector3: return Vector3(0, p.y, p.z * 0.2).normalized()
			var cl2 := func(p: Vector3, n: Vector3) -> Color:
				var wp := hinge.transform * p
				if absf(wp.x) > 4.345:
					return RED
				return WHITE if n.y > -0.2 else GREY
			_grid(P2, true, outl, cl2)
			_end(paint, surf)


func _tail() -> void:
	# tailplane: span 3.4 m, chord 0.78 -> 0.55, set at y 0.17; elevator from 60% chord
	var col := func(p: Vector3, n: Vector3) -> Color:
		if absf(p.x) > 1.38:
			return RED
		return WHITE if n.y > -0.2 else GREY
	var tp := func(x: float, f: float, upper: bool) -> Vector3:
		var s := clampf(absf(x) / 1.7, 0.0, 1.0)
		var c := lerpf(0.78, 0.55, s)
		var le := lerpf(3.95, 4.12, s)
		var a := airfoil(f, 0.1)
		return Vector3(x, 0.17 + (a.x if upper else -a.x) * c, le + f * c)
	var ring_of := func(x: float, f0: float, f1: float) -> Array:
		var ring: Array = []
		for k in 9:
			ring.append(tp.call(x, f0 + (f1 - f0) * (0.5 - 0.5 * cos(PI * (1.0 - k / 8.0))), true))
		for k in range(1, 8):
			ring.append(tp.call(x, f0 + (f1 - f0) * (0.5 - 0.5 * cos(PI * k / 8.0)), false))
		return ring
	var out := func(p: Vector3) -> Vector3: return Vector3(0, p.y - 0.17, (p.z - 4.2) * 0.3).normalized()
	for s: float in [1.0, -1.0]:
		var P: Array = []
		for xv in [0.05, 0.5, 0.95, 1.37, 1.39, 1.7]:
			P.append(ring_of.call(s * xv, 0.0, 0.6))
		_grid(P, true, out, col)
	_end(paint, am.outer)
	# elevator on its hinge
	var hz: float = tp.call(0.0, 0.6, true).z
	am.elevator.position = Vector3(0, 0.17, hz)
	am.outer.add_child(am.elevator)
	var P2: Array = []
	for xv in [-1.7, -1.39, -1.37, -0.7, 0.0, 0.7, 1.37, 1.39, 1.7]:
		var x: float = xv
		var ring2: Array = []
		for p in ring_of.call(x, 0.6, 1.0):
			ring2.append((p as Vector3) - am.elevator.position)
		P2.append(ring2)
	_grid(P2, true, func(p: Vector3) -> Vector3: return Vector3(0, p.y, p.z * 0.2).normalized(), col)
	_end(paint, am.elevator)
	# fin: swept leading edge, root 3.55..4.72, tip at y 1.23 from 4.25..4.72; rudder from 62% chord
	var fin := func(y: float, f: float, side: float) -> Vector3:
		var s := clampf((y - 0.25) / (1.23 - 0.25), 0.0, 1.0)
		var le := lerpf(3.55, 4.28, s)
		var te := 4.74
		var c := te - le
		var a := airfoil(f, 0.11)
		return Vector3(side * a.x * c, y, le + f * c)
	var fcol := func(p: Vector3, n: Vector3) -> Color: return RED if p.y > 1.02 else WHITE
	var fout := func(p: Vector3) -> Vector3: return Vector3(p.x, 0, (p.z - 4.3) * 0.2).normalized()
	var P3: Array = []
	for yv in [0.2, 0.5, 0.8, 1.01, 1.03, 1.23]:
		var y: float = yv
		var ring3: Array = []
		for i in 9:
			ring3.append(fin.call(y, 0.62 * (0.5 - 0.5 * cos(PI * (1.0 - i / 8.0))), 1.0))
		for i in range(1, 8):
			ring3.append(fin.call(y, 0.62 * (0.5 - 0.5 * cos(PI * i / 8.0)), -1.0))
		P3.append(ring3)
	_grid(P3, true, fout, fcol)
	_cap(P3[P3.size() - 1], Vector3.UP, RED)
	# dorsal fillet blending the fin into the turtle deck
	for s: float in [1.0, -1.0]:
		var a := Vector3(0, 0.36, 2.6)
		var b := Vector3(0, 0.62, 3.7)
		var c := Vector3(0, 0.27, 3.75)
		var n := Vector3(s, 0.15, 0).normalized()
		_t3(a + Vector3(s * 0.02, 0, 0), b + Vector3(s * 0.025, 0, 0), c + Vector3(s * 0.04, 0, 0), n, n, n, WHITE, WHITE, WHITE)
	_end(paint, am.outer)
	# rudder on its hinge (hinge leans back with the fin)
	var h0: Vector3 = fin.call(0.2, 0.62, 1.0)
	var h1: Vector3 = fin.call(1.23, 0.62, 1.0)
	h0.x = 0.0
	h1.x = 0.0
	var up := (h1 - h0).normalized()
	var hinge := Node3D.new()
	hinge.transform = Transform3D(Basis(Vector3.RIGHT, up, Vector3.RIGHT.cross(up)).orthonormalized(), h0)
	am.outer.add_child(hinge)
	hinge.add_child(am.rudder)
	var inv := hinge.transform.affine_inverse()
	var P4: Array = []
	for yv in [0.0, 0.4, 0.8, 1.01, 1.03, 1.23]:
		var y: float = yv
		var ring4: Array = []
		for i in 5:
			ring4.append(inv * fin.call(y, 0.62 + 0.38 * (1.0 - i / 4.0), 1.0))
		for i in range(1, 4):
			ring4.append(inv * fin.call(y, 0.62 + 0.38 * (i / 4.0), -1.0))
		P4.append(ring4)
	_grid(P4, true, func(p: Vector3) -> Vector3: return Vector3(p.x, 0, p.z * 0.2).normalized(), func(p: Vector3, n: Vector3) -> Color:
		var wp := hinge.transform * p
		return RED if wp.y > 1.02 else WHITE)
	_cap(P4[P4.size() - 1], up, RED)
	_end(paint, am.rudder)


func _wheel(pos: Vector3, r: float, width: float) -> void:
	var piv := Node3D.new()
	piv.position = pos
	am.outer.add_child(piv)
	var tyre := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r * 0.55
	tm.outer_radius = r
	tm.rings = 24
	tm.ring_segments = 12
	tyre.mesh = tm
	tyre.material_override = rubber
	tyre.rotation.z = PI / 2.0
	tyre.scale = Vector3(width / (r * 0.45), 1.0, 1.0)
	piv.add_child(tyre)
	var hub := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = r * 0.58
	hm.bottom_radius = r * 0.58
	hm.height = width * 0.9
	hm.radial_segments = 16
	hub.mesh = hm
	hub.material_override = _mat(Color("#cfd2d4"), 0.4, 0.5)
	hub.rotation.z = PI / 2.0
	piv.add_child(hub)
	# a dark mark so the wheel can be seen turning
	_box(piv, Vector3(width * 0.95, r * 0.12, r * 0.6), Vector3(0, r * 0.3, 0), _mat(Color("#555a60"), 0.4, 0.5))
	am.wheels.append(piv)


func _gear() -> void:
	var leg := _mat(GREY, 0.45, 0.2)
	for s: float in [-1.0, 1.0]:
		_wheel(Vector3(s * 1.03, -0.83, 0.4), 0.22, 0.13)
		_limb(am.outer, Vector3(s * 0.86, -0.42, 0.33), Vector3(s * 0.98, -0.83, 0.4), 0.035, leg)
		_limb(am.outer, Vector3(s * 0.98, -0.83, 0.4), Vector3(s * 0.93, -0.83, 0.4), 0.03, steel, false)
	_wheel(Vector3(0, -0.86, -1.55), 0.19, 0.12)
	_limb(am.outer, Vector3(0, -0.42, -1.42), Vector3(0, -0.72, -1.5), 0.04, leg)
	_limb(am.outer, Vector3(0, -0.72, -1.5), Vector3(0, -0.86, -1.55), 0.028, steel)
	for s2: float in [-1.0, 1.0]:
		_limb(am.outer, Vector3(s2 * 0.08, -0.7, -1.5), Vector3(s2 * 0.08, -0.86, -1.55), 0.015, steel)


func _prop() -> void:
	am.prop.position = Vector3(0, 0.0, -2.05)
	am.outer.add_child(am.prop)
	# spinner
	var sp: Array = []
	var prof := [[-0.33, 0.0], [-0.3, 0.06], [-0.24, 0.12], [-0.14, 0.17], [0.0, 0.19]]
	for pr in prof:
		var ring: Array = []
		for i in 24:
			var t := TAU * i / 24.0
			ring.append(Vector3(cos(t) * float(pr[1]), sin(t) * float(pr[1]), float(pr[0])))
		sp.append(ring)
	_grid(sp, true, func(p: Vector3) -> Vector3: return Vector3(p.x, p.y, -0.3).normalized(), func(_p, _n): return RED)
	_end(paint, am.prop)
	# two Hartzell blades: tapered and twisted, black with yellow tips
	for bi in 2:
		var piv := Node3D.new()
		piv.rotation.z = bi * PI
		am.prop.add_child(piv)
		var P: Array = []
		for k in 9:
			var r := lerpf(0.13, 0.94, k / 8.0)
			var ch := lerpf(0.15, 0.09, k / 8.0) * (1.0 - 0.6 * pow(k / 8.0, 6.0))
			var tw := deg_to_rad(lerpf(38.0, 12.0, k / 8.0))
			var th := lerpf(0.035, 0.012, k / 8.0)
			var ring: Array = []
			for i in 10:
				var a := TAU * i / 10.0
				var lx := cos(a) * ch * 0.5
				var lz := sin(a) * th * 0.5
				ring.append(Vector3(lx * cos(tw) - lz * sin(tw), r, lx * sin(tw) + lz * cos(tw)))
			P.append(ring)
		_grid(P, true, func(p: Vector3) -> Vector3: return Vector3(p.x, 0, p.z).normalized(), func(p: Vector3, _n): return YELLOW if p.y > 0.85 else BLACK)
		_end(matte, piv)
		am.blades.append(piv)
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.1, 0.1, 0.12, 0.0)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var dq := QuadMesh.new()
	dq.size = Vector2(1.9, 1.9)
	var disc := MeshInstance3D.new()
	disc.mesh = dq
	disc.material_override = dm
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	am.prop.add_child(disc)
	am.disc = disc


# ---------------------------------------------------------------- markings
func _roundel_fus(z: float, y: float, r: float, side: float) -> void:
	# type D roundel hugging the curved fuselage side: blue outer, white, red centre (radii 3:2:1)
	var rings := [[0.0, RED], [r / 3.0 - 0.002, RED], [r / 3.0, WHITE], [2.0 * r / 3.0 - 0.002, WHITE], [2.0 * r / 3.0, BLUE], [r, BLUE]]
	var seg := 40
	for k in range(rings.size() - 1):
		var r0: float = rings[k][0]
		var r1: float = rings[k + 1][0]
		var cl: Color = rings[k + 1][1]
		for i in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			var pts: Array = []
			for pr in [[r0, a0], [r0, a1], [r1, a1], [r1, a0]]:
				var zz := z + cos(pr[1]) * float(pr[0])
				var yy := y + sin(pr[1]) * float(pr[0])
				pts.append(Vector3(side * (fus_x(zz, yy) + 0.004), yy, zz))
			var n := Vector3(side, 0, 0)
			_q(pts[0], pts[1], pts[2], pts[3], n, cl)


func _roundel_wing(x: float, zc: float, r: float, upper: bool) -> void:
	var rings := [[0.0, RED], [r / 3.0 - 0.002, RED], [r / 3.0, WHITE], [2.0 * r / 3.0 - 0.002, WHITE], [2.0 * r / 3.0, BLUE], [r, BLUE]]
	var seg := 40
	var dy := 0.004 if upper else -0.004
	for k in range(rings.size() - 1):
		var r0: float = rings[k][0]
		var r1: float = rings[k + 1][0]
		var cl: Color = rings[k + 1][1]
		for i in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			var pts: Array = []
			for pr in [[r0, a0], [r0, a1], [r1, a1], [r1, a0]]:
				var xx := x + cos(pr[1]) * float(pr[0])
				var zz := zc + sin(pr[1]) * float(pr[0])
				var g := wing_geo(absf(xx))
				var f := (zz - float(g[1])) / float(g[0])
				var wp := wing_pt(xx, f, upper)
				pts.append(Vector3(xx, wp.y + dy, zz))
			_q(pts[0], pts[1], pts[2], pts[3], Vector3.UP if upper else Vector3.DOWN, cl)


func _markings() -> void:
	for s: float in [-1.0, 1.0]:
		_roundel_fus(2.05, 0.04, 0.24, s)
		for up in [true, false]:
			var g := wing_geo(3.6)
			_roundel_wing(s * 3.6, float(g[1]) + float(g[0]) * 0.42, 0.36, up)
		# fin flash: red (front), white, blue (rear)
		var cols := [RED, WHITE, BLUE]
		for k in 3:
			var z0 := 4.08 + k * 0.1
			var z1 := z0 + 0.1
			var y0 := 0.55
			var y1 := 0.9
			var xo := s * 0.05
			_q(Vector3(xo, y0, z0), Vector3(xo, y0, z1), Vector3(xo, y1, z1), Vector3(xo, y1, z0), Vector3(s, 0, 0), cols[k])
	_end(paint, am.outer)
	# serial and code (black lettering)
	var f: Font = load("res://assets/fonts/Barlow-SemiBold.ttf")
	for s: float in [-1.0, 1.0]:
		for t in [["XX658", Vector3(0, 0.1, 3.62), 0.16], ["07", Vector3(0, 0.0, -1.3), 0.22]]:
			var lb := Label3D.new()
			lb.text = t[0]
			lb.font = f
			lb.font_size = 128
			lb.pixel_size = float(t[2]) / 128.0 * 1.3
			lb.modulate = Color("#111111")
			lb.outline_size = 0
			lb.double_sided = false
			lb.shaded = true
			lb.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
			var p: Vector3 = t[1]
			# lettering is flat but the fuselage tapers: lean it with the taper and keep it just outside the skin
			var half_len := float(t[2]) * 1.6
			var xa := fus_x(p.z - half_len, p.y)
			var xb := fus_x(p.z + half_len, p.y)
			var lean := atan2(xa - xb, 2.0 * half_len)
			lb.position = Vector3(s * (maxf(xa, xb) - absf(xb - xa) / 2.0 + 0.012), p.y, p.z)
			lb.rotation.y = s * (PI / 2.0 - lean)
			am.fus.add_child(lb)


func _details() -> void:
	var dark := _mat(Color("#2a2b2e"), 0.5, 0.4)
	# exhaust stubs under the cowling, chin air intake, oil cooler outlet
	for s: float in [-1.0, 1.0]:
		_limb(am.outer, Vector3(s * 0.17, -0.47, -1.35), Vector3(s * 0.19, -0.5, -1.0), 0.03, dark, false)
	_box(am.outer, Vector3(0.24, 0.08, 0.12), Vector3(0, -0.25, -2.0), _mat(Color("#0d0d0e"), 0.9))
	# whip aerial behind the canopy, belly aerial, pitot under the left wing
	_limb(am.outer, Vector3(0, 0.42, 1.7), Vector3(0, 0.95, 1.95), 0.006, dark, false)
	_box(am.outer, Vector3(0.02, 0.18, 0.12), Vector3(0, -0.36, 1.9), dark, Vector3(0.3, 0, 0))
	var pit := wing_pt(-3.3, 0.2, false)
	_limb(am.outer, pit, pit + Vector3(0, -0.12, -0.05), 0.01, steel, false)
	_limb(am.outer, pit + Vector3(0, -0.12, -0.05), pit + Vector3(0, -0.12, -0.42), 0.008, steel, false)
	# navigation lights and the beacon
	var navr := _mat(Color(1, 0.1, 0.1))
	navr.emission_enabled = true
	navr.emission = Color(1, 0.1, 0.1)
	navr.emission_energy_multiplier = 3.0
	var navg := navr.duplicate() as StandardMaterial3D
	navg.albedo_color = Color(0.1, 1, 0.3)
	navg.emission = Color(0.1, 1, 0.3)
	var navw := navr.duplicate() as StandardMaterial3D
	navw.albedo_color = Color(1, 1, 1)
	navw.emission = Color(1, 1, 1)
	_sph(am.outer, 0.035, wing_pt(-W_X1, 0.12, true) + Vector3(-0.06, 0, 0), navr)
	_sph(am.outer, 0.035, wing_pt(W_X1, 0.12, true) + Vector3(0.06, 0, 0), navg)
	_sph(am.outer, 0.03, Vector3(0, 0.22, 4.79), navw)
	_sph(am.outer, 0.04, Vector3(0, 1.25, 4.6), navr, Vector3(1, 0.6, 1))
	# fuel filler caps on the wings
	for s: float in [-1.0, 1.0]:
		_sph(am.outer, 0.04, wing_pt(s * 2.3, 0.3, true), steel, Vector3(1, 0.25, 1))


func _figure(x: float, parent: Node3D, is_instructor: bool) -> Node3D:
	# a seated crew member in a flight suit and helmet
	var suit := _mat(Color("#4d5638") if is_instructor else Color("#2f3b52"), 0.85)
	var glove := _mat(Color("#151515"), 0.8)
	var helmet := _mat(Color("#e9e9e4"), 0.35)
	var visor := _mat(Color("#101418"), 0.05, 0.3)
	var root := Node3D.new()
	parent.add_child(root)
	_limb(root, Vector3(x, -0.05, 0.62), Vector3(x, 0.4, 0.6), 0.17, suit)                       # torso
	for s: float in [-1.0, 1.0]:
		var hip := Vector3(x + s * 0.1, -0.08, 0.45)
		var knee := Vector3(x + s * 0.12, 0.02, -0.02)
		var foot := Vector3(x + s * 0.12, -0.27, -0.5)
		_limb(root, hip, knee, 0.075, suit)
		_limb(root, knee, foot, 0.06, suit)
		_box(root, Vector3(0.1, 0.08, 0.26), foot + Vector3(0, -0.02, -0.08), glove)
		var sh := Vector3(x + s * 0.2, 0.36, 0.58)
		var el := Vector3(x + s * 0.22, 0.06, 0.4)
		var hand := Vector3(x + s * 0.12, 0.05, 0.12)
		_limb(root, sh, el, 0.055, suit)
		_limb(root, el, hand, 0.045, suit)
		_sph(root, 0.045, hand, glove)
	var head := Node3D.new()
	head.position = Vector3(x, 0.66, 0.52)
	root.add_child(head)
	_sph(head, 0.1, Vector3(0, -0.02, 0), _mat(Color("#d9a88a"), 0.6))
	_sph(head, 0.125, Vector3(0, 0.03, 0.02), helmet)
	_sph(head, 0.11, Vector3(0, 0.0, -0.06), visor, Vector3(1, 0.55, 0.7))
	_limb(head, Vector3(0, -0.11, 0.02), Vector3(0, -0.2, 0.05), 0.04, suit)                      # neck
	if is_instructor:
		instructor_head = head
	return root


func _people() -> void:
	am.pilot_nodes = [_figure(-0.3, am.fus, false)]
	_figure(0.3, am.outer, true)


# ---------------------------------------------------------------- cockpit
func _cockpit() -> void:
	var ck := am.cockpit_node
	var black := _mat(Color("#141517"), 0.75)
	var dgrey := _mat(Color("#2a2c30"), 0.7)
	# lining inside the fuselage sides and floor (a U-shape from sill to sill)
	var P: Array = []
	for z in [CK0, -0.3, 0.1, 0.5, 0.9, 1.1]:
		var f := fus_at(z)
		var hw: float = float(f[0]) - 0.03
		var top: float = float(f[1])
		var bot: float = float(f[2]) + 0.03
		var yc := (top + bot) / 2.0
		var hh := (top - bot) / 2.0
		var ts := asin(clampf(pow(clampf((SILL - yc) / hh, 0.0, 1.0), SE_N / 2.0), -1.0, 1.0))
		var ring: Array = []
		for i in 21:
			var t := ts - (i / 20.0) * (PI + 2.0 * ts)
			var q := se(t, hw, top, bot)
			ring.append(Vector3(q.x, q.y, z))
		P.append(ring)
	_grid(P, false, func(p: Vector3) -> Vector3: return Vector3(-p.x, 0.1 - p.y, 0).normalized(), func(p: Vector3, _n): return INTERIOR * (0.75 if p.y < -0.3 else 1.0))
	_end(interior_m, ck)
	_box(ck, Vector3(1.0, 0.02, 1.7), Vector3(0, -0.37, 0.15), _mat(Color("#1e1f22"), 0.9))       # floor
	_box(ck, Vector3(1.05, 0.62, 0.03), Vector3(0, -0.08, 1.02), dgrey)                              # rear bulkhead
	_box(ck, Vector3(1.0, 0.35, 0.03), Vector3(0, 0.25, 1.15), black, Vector3(-0.35, 0, 0))           # parcel shelf
	# instrument panel: textured with the live gauges, tilted 12 degrees, with bezels and glass
	var pw := BulldogPanel.PW
	var ph := BulldogPanel.PH
	var vp := SubViewport.new()
	vp.size = Vector2i(int(pw * BulldogPanel.PXM), int(ph * BulldogPanel.PXM))
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.disable_3d = true
	vp.msaa_2d = Viewport.MSAA_2X   # smooth needle edges; 2x is plenty at this resolution
	var panel_fixed := BulldogPanel.new()     # faces, scales and labels: drawn once
	panel_fixed.set_layer("static")
	panel_fixed.size = Vector2(vp.size)
	vp.add_child(panel_fixed)
	panel_ui = BulldogPanel.new()             # needles and other moving parts: redrawn every frame
	panel_ui.set_layer("live")
	panel_ui.size = Vector2(vp.size)
	vp.add_child(panel_ui)
	ck.add_child(vp)
	var pnode := Node3D.new()
	pnode.position = Vector3(0, 0.235, -0.44)
	pnode.rotation.x = deg_to_rad(-12.0)
	ck.add_child(pnode)
	var pm := StandardMaterial3D.new()
	pm.albedo_texture = vp.get_texture()
	pm.emission_enabled = true
	pm.emission_texture = vp.get_texture()
	pm.emission_energy_multiplier = 0.45      # readable in the shade, still lit by the sun
	pm.roughness = 0.75
	pm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	var q := QuadMesh.new()
	q.size = Vector2(pw, ph)
	var pmi := MeshInstance3D.new()
	pmi.mesh = q
	pmi.material_override = pm
	pnode.add_child(pmi)
	_box(pnode, Vector3(pw + 0.04, ph + 0.03, 0.2), Vector3(0, 0, -0.105), black)                  # panel body
	var bezel := _mat(Color("#0e0f10"), 0.45, 0.3)
	var gglass := StandardMaterial3D.new()
	gglass.albedo_color = Color(0.9, 0.95, 1.0, 0.07)
	gglass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gglass.roughness = 0.03
	gglass.metallic_specular = 1.0
	for l in BulldogPanel.LAYOUT:
		var c := Vector3(float(l[1]) - pw / 2.0, ph / 2.0 - float(l[2]), 0.0)
		var r: float = l[3]
		var tm := TorusMesh.new()
		tm.inner_radius = r * 0.99
		tm.outer_radius = r * 1.1
		tm.rings = 40
		tm.ring_segments = 8
		var bz := MeshInstance3D.new()
		bz.mesh = tm
		bz.material_override = bezel
		bz.position = c + Vector3(0, 0, 0.004)
		bz.rotation.x = PI / 2.0
		bz.scale = Vector3(1, 0.4, 1)
		pnode.add_child(bz)
		var gm := CylinderMesh.new()
		gm.top_radius = r
		gm.bottom_radius = r
		gm.height = 0.001
		gm.radial_segments = 32
		var gl := MeshInstance3D.new()
		gl.mesh = gm
		gl.material_override = gglass
		gl.position = c + Vector3(0, 0, 0.007)
		gl.rotation.x = PI / 2.0
		gl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pnode.add_child(gl)
	# switch toggles and knobs standing out of the panel (3D, so they catch the light in VR)
	for i in 9:
		var sx := 0.62 + 0.012 + i * 0.052 - pw / 2.0
		_limb(pnode, Vector3(sx, ph / 2.0 - 0.29, 0.0), Vector3(sx, ph / 2.0 - 0.285, 0.022), 0.003, steel, false)
	for i in 3:
		var kx := 0.62 + 0.268 - pw / 2.0
		var ky := ph / 2.0 - (0.03 + i * 0.075 + 0.031)
		_limb(pnode, Vector3(kx, ky, 0.0), Vector3(kx, ky, 0.018), 0.011, black, false)
	# glare shield over the panel, coaming lip and a compass on top
	_box(ck, Vector3(pw + 0.06, 0.04, 0.32), Vector3(0, 0.47, -0.58), black, Vector3(0.06, 0, 0))
	_limb(ck, Vector3(-pw / 2.0 - 0.02, 0.455, -0.43), Vector3(pw / 2.0 + 0.02, 0.455, -0.43), 0.018, _mat(Color("#101010"), 0.95), false)
	_sph(ck, 0.03, Vector3(0.0, 0.515, -0.53), black, Vector3(1, 0.8, 1))
	var cw := _sph(ck, 0.02, Vector3(0.0, 0.518, -0.505), _mat(Color("#d9d3b8"), 0.4), Vector3(1, 0.7, 0.35))
	cw.name = "compass_card"
	# centre console with throttle quadrant (throttle black, propeller blue, mixture red), trim wheel, flap lever
	_box(ck, Vector3(0.16, 0.3, 0.9), Vector3(0, -0.22, 0.02), dgrey)
	_box(ck, Vector3(0.16, 0.2, 0.3), Vector3(0, -0.04, -0.3), dgrey, Vector3(-0.5, 0, 0))
	var lever_mats := [_mat(Color("#101010"), 0.4), _mat(Color("#1d4fb8"), 0.4), _mat(Color("#c4161c"), 0.4)]
	for k in 3:
		var piv := Node3D.new()
		piv.position = Vector3(-0.045 + k * 0.045, 0.02, -0.26)
		ck.add_child(piv)
		_limb(piv, Vector3.ZERO, Vector3(0, 0.15, 0), 0.007, steel, false)
		_sph(piv, 0.022 if k == 0 else 0.017, Vector3(0, 0.165, 0), lever_mats[k], Vector3(1, 0.8, 1.2) if k == 0 else Vector3.ONE)
		piv.rotation.x = -0.45
		if k == 0:
			throttle_lever = piv
	trim_wheel = Node3D.new()
	trim_wheel.position = Vector3(-0.085, -0.12, 0.12)
	ck.add_child(trim_wheel)
	var tw := MeshInstance3D.new()
	var twm := CylinderMesh.new()
	twm.top_radius = 0.07
	twm.bottom_radius = 0.07
	twm.height = 0.02
	twm.radial_segments = 24
	tw.mesh = twm
	tw.material_override = black
	tw.rotation.z = PI / 2.0
	trim_wheel.add_child(tw)
	_box(trim_wheel, Vector3(0.022, 0.012, 0.13), Vector3.ZERO, _mat(Color("#e6e6e6"), 0.5))
	flap_lever = Node3D.new()
	flap_lever.position = Vector3(0.0, -0.06, 0.32)
	ck.add_child(flap_lever)
	_limb(flap_lever, Vector3.ZERO, Vector3(0, 0.12, 0), 0.008, steel, false)
	_box(flap_lever, Vector3(0.05, 0.025, 0.03), Vector3(0, 0.13, 0), _mat(Color("#e8e8e8"), 0.5))
	# fuel selector on the floor between the seats
	_sph(ck, 0.035, Vector3(0, -0.36, 0.55), black, Vector3(1, 0.3, 1))
	_box(ck, Vector3(0.015, 0.02, 0.07), Vector3(0, -0.345, 0.55), _mat(Color("#c4161c"), 0.5))
	# seats (parachute bucket seats with cushions); harness straps on the empty-looking left seat would float, so
	# only the instructor's seat shows them
	var seat := _mat(Color("#33363b"), 0.6)
	var cushion := _mat(Color("#3a4a63"), 0.9)
	for s: float in [-1.0, 1.0]:
		var x := s * 0.3
		_box(ck, Vector3(0.42, 0.1, 0.48), Vector3(x, -0.21, 0.42), seat)
		_box(ck, Vector3(0.38, 0.06, 0.42), Vector3(x, -0.14, 0.42), cushion)
		_box(ck, Vector3(0.42, 0.7, 0.08), Vector3(x, 0.15, 0.72), seat, Vector3(-0.22, 0, 0))
		_box(ck, Vector3(0.36, 0.5, 0.05), Vector3(x, 0.15, 0.67), cushion, Vector3(-0.22, 0, 0))
	var strap := _mat(Color("#2b3d6b"), 0.85)
	for s2: float in [-1.0, 1.0]:
		_limb(ck, Vector3(0.3 + s2 * 0.09, 0.45, 0.66), Vector3(0.3 + s2 * 0.05, 0.05, 0.38), 0.012, strap, false)
		_limb(ck, Vector3(0.3 + s2 * 0.18, -0.08, 0.45), Vector3(0.3, -0.04, 0.3), 0.012, strap, false)
	_sph(ck, 0.03, Vector3(0.3, -0.03, 0.3), steel, Vector3(1, 1, 0.4))
	# control sticks (one each seat) and rudder pedals
	for s: float in [-1.0, 1.0]:
		var piv := Node3D.new()
		piv.position = Vector3(s * 0.3, -0.34, -0.02)
		ck.add_child(piv)
		var gaiter := MeshInstance3D.new()
		var gm2 := CylinderMesh.new()
		gm2.top_radius = 0.02
		gm2.bottom_radius = 0.07
		gm2.height = 0.1
		gm2.radial_segments = 14
		gaiter.mesh = gm2
		gaiter.material_override = rubber
		gaiter.position = Vector3(0, 0.05, 0)
		ck.add_child(gaiter)
		gaiter.position = piv.position + Vector3(0, 0.05, 0)
		_limb(piv, Vector3.ZERO, Vector3(0, 0.42, 0.02), 0.012, steel, false)
		_limb(piv, Vector3(0, 0.42, 0.02), Vector3(0, 0.55, 0.0), 0.022, rubber)                    # grip
		_box(piv, Vector3(0.012, 0.025, 0.02), Vector3(0, 0.5, -0.03), _mat(Color("#b01818"), 0.4))   # trigger
		_sph(piv, 0.009, Vector3(0, 0.575, -0.005), _mat(Color("#b01818"), 0.4))                       # button
		if s < 0.0:
			am.yoke = piv                     # main.gd drives this one; stick_r copies it
		else:
			stick_r = piv
		for p: float in [-1.0, 1.0]:
			var pd := Node3D.new()
			pd.position = Vector3(s * 0.3 + p * 0.1, -0.28, -0.62)
			ck.add_child(pd)
			_box(pd, Vector3(0.07, 0.13, 0.02), Vector3.ZERO, steel, Vector3(-0.5, 0, 0))
			_limb(pd, Vector3(0, -0.04, 0.03), Vector3(0, -0.1, 0.12), 0.01, steel, false)
			pedals.append([pd, p, pd.position.z])


# ---------------------------------------------------------------- per frame
func animate(ctl: Dictionary, dt: float) -> void:
	var pitch: float = ctl.get("pitch", 0.0)
	var roll: float = ctl.get("roll", 0.0)
	var yaw: float = ctl.get("yaw", 0.0)
	if am.yoke != null:
		am.yoke.rotation = Vector3(pitch * 0.32, 0.0, -roll * 0.32)
	if stick_r != null:
		stick_r.rotation = am.yoke.rotation
	for p in pedals:
		var node: Node3D = p[0]
		node.position.z = float(p[2]) + float(p[1]) * yaw * 0.05
	if throttle_lever != null:
		throttle_lever.rotation.x = lerpf(0.55, -0.45, float(ctl.get("throttle", 0.0)))
	if flap_lever != null:
		flap_lever.rotation.x = lerpf(-0.35, 0.45, float(ctl.get("flaps", 0.0)))
	if trim_wheel != null:
		trim_wheel.rotation.x = float(ctl.get("trim", 0.0)) * 8.0
	for f in flaps:
		(f as Node3D).rotation.x = float(ctl.get("flaps_pos", 0.0)) * 0.65
	if instructor_head != null:
		var t := Time.get_ticks_msec() / 1000.0
		instructor_head.rotation.y = 0.35 * sin(t * 0.21) + 0.15 * sin(t * 0.53)
		instructor_head.rotation.x = 0.08 * sin(t * 0.37)
