class_name Spitfire
extends Bulldog
## Supermarine Spitfire LF Mk IX, as MH434 flies today (v1.21.0), built entirely in code.
## Real dimensions: span 11.23 m, length 9.47 m, wing area 22.48 m2, elliptical wing (root chord 2.54 m,
## NACA 2213 at the root thinning to 2209.4 at the tip, 6 degrees dihedral, 2 degrees washout), Rolls-Royce
## Merlin 66 with a 3.27 m four-blade Rotol propeller, narrow-track main gear (1.68 m) retracting outwards,
## fixed tail wheel, split flaps, radiators under both wings, 20 mm cannon stubs in the "c" wing.
## Paint: shaders/spitfire_paint.gdshader (Day Fighter Scheme, codes ZD-B, serial MH434).
## Body axes as everywhere in the game: x right, y up, z back (nose is -z), metres, origin at the centre of
## gravity (30% of the mean chord). Thrust line at y = 0. Main wheels touch the ground at y = -1.75 (z = -0.85),
## the tail wheel at y = -0.386 (z = 5.30): 12.5 degrees nose up when sitting on the ground.
## It extends Bulldog for the mesh helpers and the interface main.gd uses (panel_ui, stick and throttle grips,
## animate); everything the Spitfire has is built here.

## fuselage stations: z, half width, top, bottom, top narrowing (the decking behind the cockpit is a narrow hump).
## Round the cockpit the "top" is above the sill (cut away there), so the sides are near their widest at the sill.
const FUS := [
	[-2.88, 0.330, 0.330, -0.330, 0.00], [-2.74, 0.352, 0.362, -0.372, 0.04], [-2.45, 0.380, 0.400, -0.412, 0.08],
	[-2.00, 0.402, 0.435, -0.447, 0.10], [-1.45, 0.414, 0.468, -0.490, 0.12], [-0.88, 0.424, 0.535, -0.590, 0.10],
	[-0.35, 0.434, 0.72, -0.675, 0.05], [0.30, 0.432, 0.78, -0.715, 0.05], [0.95, 0.410, 0.76, -0.700, 0.55],
	[1.60, 0.368, 0.675, -0.640, 0.55], [2.40, 0.306, 0.605, -0.520, 0.55], [3.30, 0.240, 0.525, -0.380, 0.55],
	[4.20, 0.170, 0.445, -0.230, 0.50], [4.90, 0.108, 0.375, -0.090, 0.45], [5.35, 0.060, 0.330, 0.010, 0.40],
	[5.45, 0.030, 0.315, 0.040, 0.35],
]
const N_SE := 2.25                  # cross-section squareness (2 = ellipse)
const SP_SILL := 0.50               # top of the cockpit sides
const SP_CK0 := -0.88               # windscreen base
const SP_CK1 := 0.95                # rear of the cockpit opening (the armour and headrest)
const WS_TOP := -0.56               # top of the windscreen (where the sliding hood starts)
## sliding hood (bulged "Malcolm" type): z, height of the top
const HOOD := [[-0.56, 0.835], [-0.42, 0.885], [-0.2, 0.935], [0.1, 0.958], [0.45, 0.952], [0.72, 0.915], [0.95, 0.865]]
## wing: elliptical, the 30% chord line straight across at z = 0
const SEMI := 5.615
const ROOT_C := 2.54
const WY0 := -0.55                  # chord line height at the centre line
const DIH := 0.1051                 # tan 6 degrees
const AIL0 := 3.30                  # aileron, inner end
const AIL1 := 5.10                  # aileron, outer end
const AIL_F := 0.75                 # aileron hinge (chord fraction)
const FLAP0 := 0.45                 # split flaps
const FLAP1 := 2.75
## tail
const TP_SEMI := 1.60
const TP_C := 1.03
const TP_Y := 0.15
const TP_LE := 4.40
const TP_HINGE := 0.62
const RUD_Z := 5.43                 # rudder hinge
const FIN_TOP := 1.30
## where the eye is (the pilot sits low, under the bulged hood)
const EYE := Vector3(0.0, 0.76, 0.25)

var U1 := PackedVector2Array()
var U2 := PackedVector2Array()
var enc := false                   ## encode aircraft-frame position and normal for the paint shader
var xf := Transform3D()             ## mesh space -> aircraft frame (for the moving surfaces)
var pmats := {}
var spade: Node3D                   # the spade grip (rolls left and right on top of the column)
var prop_lever: Node3D
var gun_ring: MeshInstance3D

var DK := Color("#2c3326").srgb_to_linear()          # dark green-grey: canopy frames (outside)
var GG := Color("#7a8670").srgb_to_linear()          # RAF interior grey-green
var BAKELITE := Color("#5b2f1e").srgb_to_linear()     # the seat
var BLK := Color("#131314").srgb_to_linear()
var YEL := Color("#e8b000").srgb_to_linear()


# ---------------------------------------------------------------- mesh helpers (with the paint's per-vertex data)
func _begin() -> void:
	super._begin()
	U1 = PackedVector2Array()
	U2 = PackedVector2Array()


func _put(v: Vector3, n: Vector3, c: Color) -> void:
	V.append(v)
	NN.append(n)
	if enc:
		var a := xf * v
		var an := (xf.basis * n).normalized()
		U1.append(Vector2(a.x, a.y))
		U2.append(Vector2(a.z, 0.0))
		CC.append(Color(an.x * 0.5 + 0.5, an.y * 0.5 + 0.5, an.z * 0.5 + 0.5, 1.0))
	else:
		CC.append(c)


func _t3(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	if (b - a).cross(c - a).dot(na + nb + nc) > 0.0:
		_put(a, na, ca); _put(c, nc, cc); _put(b, nb, cb)
	else:
		_put(a, na, ca); _put(b, nb, cb); _put(c, nc, cc)


func _end(mat: Material, parent: Node3D, shadow := true) -> MeshInstance3D:
	if V.size() == 0:
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = V
	arrays[Mesh.ARRAY_NORMAL] = NN
	arrays[Mesh.ARRAY_COLOR] = CC
	if U1.size() == V.size():
		arrays[Mesh.ARRAY_TEX_UV] = U1
		arrays[Mesh.ARRAY_TEX_UV2] = U2
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


## The paint for one part: 0 fuselage, 1 wing, 2 tailplane, 3 fin and rudder, 4 spinner, 5 all grey (radiators).
func _pm(part: int) -> ShaderMaterial:
	if not pmats.has(part):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/spitfire_paint.gdshader")
		m.set_shader_parameter("part", part)
		m.set_shader_parameter("letters", load("res://assets/aircraft/spitfire_letters.png"))
		m.set_shader_parameter("panels", VehicleLook.panel_normals())
		m.set_shader_parameter("grain", VehicleLook._t("chipped_rgh"))
		pmats[part] = m
	return pmats[part]


## Ends a painted mesh: encoded for the shader, in the given part's paint.
func _paint_end(part: int, parent: Node3D, frame := Transform3D()) -> MeshInstance3D:
	var mi := _end(_pm(part), parent)
	return mi


func _painted(on: bool, frame := Transform3D()) -> void:
	_begin()
	enc = on
	xf = frame


# ---------------------------------------------------------------- shape functions
func _cr(a: float, b: float, c: float, d: float, t: float) -> float:
	# Catmull-Rom between b and c
	var t2 := t * t
	return 0.5 * ((2.0 * b) + (-a + c) * t + (2.0 * a - 5.0 * b + 4.0 * c - d) * t2 + (-a + 3.0 * b - 3.0 * c + d) * t2 * t)


## half width, top, bottom, top narrowing at station z (smooth between the stations)
func fs(z: float) -> Array:
	var n := FUS.size()
	if z <= float(FUS[0][0]):
		return [FUS[0][1], FUS[0][2], FUS[0][3], FUS[0][4]]
	if z >= float(FUS[n - 1][0]):
		return [FUS[n - 1][1], FUS[n - 1][2], FUS[n - 1][3], FUS[n - 1][4]]
	var k := 0
	while k < n - 2 and z > float(FUS[k + 1][0]):
		k += 1
	var t := (z - float(FUS[k][0])) / (float(FUS[k + 1][0]) - float(FUS[k][0]))
	var out: Array = []
	for j in range(1, 5):
		var a: float = FUS[maxi(k - 1, 0)][j]
		var b: float = FUS[k][j]
		var c: float = FUS[k + 1][j]
		var d: float = FUS[mini(k + 2, n - 1)][j]
		out.append(_cr(a, b, c, d, t))
	return out


## a point on the cross-section at station z, angle t (0 = right side, PI/2 = top)
func fpt(z: float, t: float) -> Vector3:
	var f := fs(z)
	var c := cos(t)
	var s := sin(t)
	var yc := (float(f[1]) + float(f[2])) / 2.0
	var hh := (float(f[1]) - float(f[2])) / 2.0
	var narrow := 1.0 - float(f[3]) * pow(maxf(s, 0.0), 2.0) - 0.12 * pow(maxf(-s, 0.0), 2.0)
	return Vector3(float(f[0]) * signf(c) * pow(absf(c), 2.0 / N_SE) * narrow, yc + hh * signf(s) * pow(absf(s), 2.0 / N_SE), z)


## the fuselage side's x at height y, station z
func fx(z: float, y: float) -> float:
	var f := fs(z)
	var yc := (float(f[1]) + float(f[2])) / 2.0
	var hh := (float(f[1]) - float(f[2])) / 2.0
	var r := clampf((y - yc) / hh, -1.0, 1.0)
	var s := signf(r) * pow(absf(r), N_SE / 2.0)
	var c := sqrt(maxf(1.0 - s * s, 0.0))
	var narrow := 1.0 - float(f[3]) * pow(maxf(s, 0.0), 2.0) - 0.12 * pow(maxf(-s, 0.0), 2.0)
	return float(f[0]) * pow(c, 2.0 / N_SE) * narrow


func chord(ax: float) -> float:
	return ROOT_C * sqrt(maxf(1.0 - (ax * ax) / (SEMI * SEMI), 0.0))


## a point on the wing at span x (signed), chord fraction f, upper or lower surface
func wpt(x: float, f: float, upper: bool) -> Vector3:
	var ax := absf(x)
	var c := maxf(chord(ax), 0.02)
	var tk := lerpf(0.132, 0.094, clampf(ax / SEMI, 0.0, 1.0))
	var a := airfoil(f, tk)
	var eta := (a.y + (a.x if upper else -a.x)) * c
	var inc := deg_to_rad(lerpf(2.0, -0.5, clampf(ax / SEMI, 0.0, 1.0)))
	var dz := (f - 0.3) * c
	return Vector3(x, WY0 + ax * DIH + eta * cos(inc) - dz * sin(inc), dz * cos(inc))


func wring(x: float, f0: float, f1: float, n: int) -> Array:
	var ring: Array = []
	for k in n + 1:
		var u := float(k) / n
		ring.append(wpt(x, f0 + (f1 - f0) * (0.5 - 0.5 * cos(PI * (1.0 - u))), true))
	for k in range(1, n):
		var u2 := float(k) / n
		ring.append(wpt(x, f0 + (f1 - f0) * (0.5 - 0.5 * cos(PI * u2)), false))
	return ring


func tp_chord(ax: float) -> float:
	return TP_C * sqrt(maxf(1.0 - (ax * ax) / (TP_SEMI * TP_SEMI), 0.0))


func tpt(x: float, f: float, upper: bool) -> Vector3:
	var c := maxf(tp_chord(absf(x)), 0.02)
	var a := airfoil(f, 0.10)
	return Vector3(x, TP_Y + (a.x if upper else -a.x) * c, TP_LE + 0.3 * TP_C - 0.3 * c + f * c)


func tring(x: float, f0: float, f1: float) -> Array:
	var ring: Array = []
	for k in 11:
		ring.append(tpt(x, f0 + (f1 - f0) * (0.5 - 0.5 * cos(PI * (1.0 - k / 10.0))), true))
	for k in range(1, 10):
		ring.append(tpt(x, f0 + (f1 - f0) * (0.5 - 0.5 * cos(PI * k / 10.0)), false))
	return ring


## fin and rudder outline at height y: leading edge z, trailing edge z
func fin_le(y: float) -> float:
	var u := clampf((y - 0.30) / (FIN_TOP - 0.30), 0.0, 0.999)
	return RUD_Z - 1.08 * sqrt(1.0 - u * u)


func rud_te(y: float) -> float:
	var span := (FIN_TOP - 0.40) if y >= 0.40 else 0.48
	var u := clampf((y - 0.40) / span, -0.999, 0.999)
	return RUD_Z + 0.46 * sqrt(1.0 - u * u)


## a point on the fin / rudder at height y, chord fraction f of the whole surface (fin leading edge to rudder
## trailing edge), side +1 right / -1 left. Below the fin (y < 0.30) the rudder keeps the outline of y = 0.30.
func fin_pt(y: float, f: float, side: float) -> Vector3:
	var le := fin_le(maxf(y, 0.30))
	var te := rud_te(y)
	if y < 0.30:
		var fh0 := (RUD_Z - fin_le(0.30)) / (rud_te(0.30) - fin_le(0.30))
		le = RUD_Z - fh0 / (1.0 - fh0) * (te - RUD_Z)
	var c := maxf(te - le, 0.01)
	var a := airfoil(f, 0.105)
	return Vector3(side * a.x * c, y, le + f * c)


func fin_fh(y: float) -> float:
	var le := fin_le(maxf(y, 0.30))
	var te := rud_te(y)
	if y < 0.30:
		return (RUD_Z - fin_le(0.30)) / (rud_te(0.30) - fin_le(0.30))
	return clampf((RUD_Z - le) / maxf(te - le, 0.01), 0.0, 1.0)


func fin_ring(y: float, f0: float, f1: float) -> Array:
	var ring: Array = []
	for k in 9:
		ring.append(fin_pt(y, f0 + (f1 - f0) * (0.5 - 0.5 * cos(PI * (1.0 - k / 8.0))), 1.0))
	for k in range(1, 8):
		ring.append(fin_pt(y, f0 + (f1 - f0) * (0.5 - 0.5 * cos(PI * k / 8.0)), -1.0))
	return ring


# ---------------------------------------------------------------- build
func build(model: AircraftModel, with_cockpit: bool) -> void:
	am = model
	am.prop_dir = -1.0    # the Merlin turns the propeller clockwise, seen from the cockpit
	matte = StandardMaterial3D.new()
	matte.vertex_color_use_as_albedo = true
	matte.roughness = 0.7
	glass = StandardMaterial3D.new()
	glass.albedo_color = Color(0.82, 0.9, 0.95, 0.09)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.02
	glass.metallic_specular = 0.9
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	steel = _mat(Color("#8a8f96"), 0.35, 0.8)
	rubber = _mat(Color("#141414"), 0.9)
	interior_m = StandardMaterial3D.new()
	interior_m.vertex_color_use_as_albedo = true
	interior_m.roughness = 0.75
	interior_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_begin()
	_sp_fuselage()
	_sp_canopy()
	_sp_wings()
	_sp_tail()
	_sp_gear()
	_sp_prop()
	_sp_details()
	am.eye = EYE
	_sp_pilot()
	if with_cockpit:
		_sp_cockpit()


func _sp_fuselage() -> void:
	_painted(true)
	var nseg := 48
	var zs: Array = []
	var z := -2.88
	while z < 5.45:
		zs.append(z)
		z += 0.09 if z < -0.6 else 0.14
	zs.append(5.45)
	for ze in [SP_CK0, SP_CK1]:
		if not ze in zs:
			zs.append(ze)
	zs.sort()
	var P: Array = []
	for zz in zs:
		var ring: Array = []
		for i in nseg:
			ring.append(fpt(zz, TAU * i / nseg))
		P.append(ring)
	var out := func(p: Vector3) -> Vector3:
		var f := fs(p.z)
		return Vector3(p.x, p.y - (float(f[1]) + float(f[2])) / 2.0, 0.0).normalized()
	var keep := func(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> bool:
		var in_ck := a.z >= SP_CK0 - 0.001 and c.z <= SP_CK1 + 0.001
		return not (in_ck and a.y > SP_SILL - 0.005 and b.y > SP_SILL - 0.005 and c.y > SP_SILL - 0.005 and d.y > SP_SILL - 0.005)
	var none := func(_p: Vector3, _n: Vector3) -> Color: return Color.WHITE
	_grid(P, true, out, none, keep)
	# the cut edge of the cockpit: a flat sill strip each side
	for s: float in [-1.0, 1.0]:
		var z0 := SP_CK0
		while z0 < SP_CK1 - 0.01:
			var z1 := minf(z0 + 0.08, SP_CK1)
			var x0 := fx(z0, SP_SILL) * s
			var x1 := fx(z1, SP_SILL) * s
			_q(Vector3(x0, SP_SILL, z0), Vector3(x1, SP_SILL, z1), Vector3(x1 - s * 0.03, SP_SILL, z1), Vector3(x0 - s * 0.03, SP_SILL, z0), Vector3.UP, Color.WHITE)
			z0 = z1
	# the chin air intake under the cowling (the supercharger's carburettor intake)
	var C: Array = []
	for zv in [-2.30, -2.18, -1.95, -1.65, -1.40, -1.25]:
		var zc: float = zv
		var bot: float = float(fs(zc)[2])
		var depth := 0.15 * sin(clampf((zc + 2.30) / 1.05, 0.0, 1.0) * PI * 0.92 + 0.12)
		var hw := 0.115
		var ring2: Array = []
		for i in 12:
			var t := PI + PI * i / 11.0         # the lower half of an oval, hanging under the cowling
			ring2.append(Vector3(cos(t) * hw, bot + 0.04 + sin(t) * (depth + 0.04), zc))
		C.append(ring2)
	_grid(C, false, func(p: Vector3) -> Vector3: return Vector3(p.x, -1.0, 0.0).normalized(), none)
	_paint_end(0, am.fus)
	# the intake's mouth (dark) and the tail cone
	var mouth := _mat(Color("#050506"), 0.9)
	_box(am.fus, Vector3(0.2, 0.11, 0.01), Vector3(0, float(fs(-2.30)[2]) - 0.02, -2.29), mouth)


func _sp_canopy() -> void:
	# sliding hood: bulged sides, from the top of the windscreen to the armour behind the pilot, then the fixed
	# rear glazing sloping down into the decking
	var prof: Array = HOOD.duplicate()
	for rz in [[1.12, 0.82], [1.28, 0.765], [1.42, 0.715]]:
		prof.append(rz)
	var P: Array = []
	var nseg := 28
	for k in prof.size():
		var z: float = prof[k][0]
		var top: float = prof[k][1]
		var w := fx(minf(z, SP_CK1), SP_SILL) + 0.006
		if z > SP_CK1:
			w = fx(z, SP_SILL) + 0.006
		var bulge := 0.07 if z <= SP_CK1 else lerpf(0.07, 0.0, (z - SP_CK1) / 0.47)
		var ring: Array = []
		for i in nseg + 1:
			var t := PI * i / nseg
			var c := cos(t)
			var s := sin(t)
			ring.append(Vector3(w * signf(c) * pow(absf(c), 2.0 / 2.6) * (1.0 + bulge * s), SP_SILL + (top - SP_SILL) * pow(s, 2.0 / 2.6), z))
		P.append(ring)
	_begin()
	enc = false
	_grid(P, false, func(p: Vector3) -> Vector3: return Vector3(p.x, p.y - SP_SILL, 0.0).normalized(), func(_p, _n): return Color.WHITE)
	# windscreen: an armoured flat front panel and curved side panels back to the hood
	var bl := Vector3(-0.15, 0.522, SP_CK0)
	var br := Vector3(0.15, 0.522, SP_CK0)
	var tl := Vector3(-0.13, 0.832, WS_TOP)
	var tr := Vector3(0.13, 0.832, WS_TOP)
	_q(bl, br, tr, tl, Vector3(0, 0.71, -0.71), Color.WHITE)
	var hood0: Array = P[0]
	for s: float in [-1.0, 1.0]:
		var S: Array = []
		for k in 9:
			var u := k / 8.0
			var front := (bl if s < 0.0 else br).lerp(tl if s < 0.0 else tr, u)
			var idx := int(round((1.0 - u * 0.5) * nseg)) if s < 0.0 else int(round(u * 0.5 * nseg))
			var back: Vector3 = hood0[idx]
			var base := Vector3(s * (fx(SP_CK0, SP_SILL) + 0.004), SP_SILL + 0.002, SP_CK0 + 0.01)
			if k == 0:
				front = base.lerp(front, 0.0)
				back = Vector3(s * (fx(WS_TOP, SP_SILL) + 0.006), SP_SILL, WS_TOP)
			S.append([front, front.lerp(back, 0.5), back])
		_grid(S, false, func(p: Vector3) -> Vector3: return Vector3(p.x, 0.3, -0.5).normalized(), func(_p, _n): return Color.WHITE)
	var g := _end(glass, am.outer, false)
	g.name = "canopy"
	# the armoured glass block behind the front panel (1.5 inches thick: greenish at its edges)
	var bp := StandardMaterial3D.new()
	bp.albedo_color = Color(0.55, 0.75, 0.62, 0.12)
	bp.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bp.roughness = 0.02
	bp.cull_mode = BaseMaterial3D.CULL_DISABLED
	var nrm := (tr - br).cross(bl - br).normalized()
	_begin()
	enc = false
	var off := nrm * 0.035
	_q(bl + off, br + off, tr + off, tl + off, Vector3(0, 0.71, -0.71), Color.WHITE)
	_end(bp, am.outer, false)
	# frames: windscreen posts and top, hood bows, sill rails, rear glazing frame, all dark camouflage outside
	var frame := _mat(Color("#2c3326"), 0.7)
	for e in [[bl, tl], [br, tr], [tl, tr], [bl, br]]:
		_limb(am.outer, e[0], e[1], 0.014, frame, false)
	for zf in [WS_TOP, SP_CK1, 1.28]:
		var top := 0.0
		for k in range(prof.size() - 1):
			if zf >= float(prof[k][0]) and zf <= float(prof[k + 1][0]):
				top = lerpf(prof[k][1], prof[k + 1][1], (zf - float(prof[k][0])) / (float(prof[k + 1][0]) - float(prof[k][0])))
		var w2 := fx(minf(zf, SP_CK1), SP_SILL) + 0.012 if zf <= SP_CK1 else fx(zf, SP_SILL) + 0.012
		var bul := 0.07 if zf <= SP_CK1 else 0.03
		var prev := Vector3.ZERO
		for i in 21:
			var t2 := PI * i / 20.0
			var c2 := cos(t2)
			var s2 := sin(t2)
			var p2 := Vector3(w2 * signf(c2) * pow(absf(c2), 2.0 / 2.6) * (1.0 + bul * s2), SP_SILL + (top + 0.006 - SP_SILL) * pow(s2, 2.0 / 2.6), zf)
			if i > 0:
				_limb(am.outer, prev, p2, 0.011 if zf != SP_CK1 else 0.016, frame, false)
			prev = p2
	# the sill rails follow the curve of the cockpit's edge (narrow at the windscreen, widest at the pilot)
	for s: float in [-1.0, 1.0]:
		var prev := Vector3.ZERO
		var zr := SP_CK0
		while zr <= 1.42 + 0.001:
			var pr := Vector3(s * (fx(minf(zr, 1.42), SP_SILL) + 0.008), SP_SILL + 0.01, zr)
			if zr > SP_CK0:
				_limb(am.outer, prev, pr, 0.012, frame, false)
			prev = pr
			zr += 0.1
	# rear-view mirror on top of the windscreen
	var mirror := Node3D.new()
	mirror.position = Vector3(0, 0.875, WS_TOP + 0.02)
	am.outer.add_child(mirror)
	_limb(mirror, Vector3(0, -0.04, 0), Vector3(0, 0.0, 0), 0.008, frame, false)
	_box(mirror, Vector3(0.13, 0.05, 0.025), Vector3(0, 0.02, 0), frame, Vector3(-0.2, 0, 0))
	_box(mirror, Vector3(0.12, 0.042, 0.004), Vector3(0, 0.02, 0.014), _mat(Color("#9fb2c4"), 0.05, 0.9), Vector3(-0.2, 0, 0))


func _sp_wings() -> void:
	var out_w := func(p: Vector3) -> Vector3:
		var g := wpt(p.x, 0.3, true).lerp(wpt(p.x, 0.3, false), 0.5)
		return Vector3(0, p.y - g.y, (p.z - g.z) * 0.15).normalized()
	var none := func(_p, _n): return Color.WHITE
	for s: float in [1.0, -1.0]:
		_painted(true)
		# root to the aileron, the aileron bay (cut at the hinge), the tip
		var pieces := [[0.0, AIL0, 0.0, 1.0, 12], [AIL0, AIL1, 0.0, AIL_F, 8], [AIL1, 5.55, 0.0, 1.0, 4], [5.55, 5.605, 0.0, 1.0, 2]]
		for pc in pieces:
			var P: Array = []
			var x0: float = pc[0]
			var x1: float = pc[1]
			var nsp: int = pc[4]
			for k in nsp + 1:
				var u := float(k) / nsp
				var x := s * lerpf(x0, x1, u)
				P.append(wring(x, pc[2], pc[3], 16))
			_grid(P, true, out_w, none)
			if pc[3] < 1.0:
				for endk in [0, nsp]:
					var ring: Array = P[endk]
					_cap(ring, Vector3(s if endk == nsp else -s, 0, 0), Color.WHITE)
		# the very tip
		var tipr: Array = wring(s * 5.605, 0.0, 1.0, 16)
		var tc := wpt(s * SEMI, 0.3, true).lerp(wpt(s * SEMI, 0.3, false), 0.5)
		for i in tipr.size():
			var a: Vector3 = tipr[i]
			var b: Vector3 = tipr[(i + 1) % tipr.size()]
			_t3(tc, a, b, Vector3(s, 0, 0), (a - tc + Vector3(s * 0.05, 0, 0)).normalized(), (b - tc + Vector3(s * 0.05, 0, 0)).normalized(), Color.WHITE, Color.WHITE, Color.WHITE)
		_paint_end(1, am.outer)
		# aileron on its hinge
		var h0 := wpt(s * AIL0, AIL_F, true).lerp(wpt(s * AIL0, AIL_F, false), 0.5)
		var h1 := wpt(s * AIL1, AIL_F, true).lerp(wpt(s * AIL1, AIL_F, false), 0.5)
		var hx := (h1 - h0).normalized() * s
		var zb := hx.cross(Vector3.UP).normalized()
		var hinge := Node3D.new()
		hinge.transform = Transform3D(Basis(hx, zb.cross(hx).normalized(), zb), h0)
		am.outer.add_child(hinge)
		var ail: Node3D = am.ail_r if s > 0.0 else am.ail_l
		hinge.add_child(ail)
		var inv := hinge.transform.affine_inverse()
		_painted(true, hinge.transform)
		var P2: Array = []
		for k in 7:
			var x := s * lerpf(AIL0 + 0.005, AIL1 - 0.005, k / 6.0)
			var ring2: Array = []
			for p in wring(x, AIL_F, 1.0, 6):
				ring2.append(inv * (p as Vector3))
			P2.append(ring2)
		_grid(P2, true, func(p: Vector3) -> Vector3: return Vector3(0, p.y, p.z * 0.2).normalized(), none)
		_cap(P2[0], -hx * s, Color.WHITE)
		_cap(P2[P2.size() - 1], hx * s, Color.WHITE)
		_paint_end(1, ail)
		# split flap: a plate under the inner wing, hinged at its front edge
		var f0 := wpt(s * FLAP0, 0.72, false)
		var f1 := wpt(s * FLAP1, 0.72, false)
		var fxv := (f1 - f0).normalized() * s
		var fzb := fxv.cross(Vector3.UP).normalized()
		var fh := Node3D.new()
		fh.transform = Transform3D(Basis(fxv, fzb.cross(fxv).normalized(), fzb), f0 + Vector3(0, -0.004, 0))
		am.outer.add_child(fh)
		var flap := Node3D.new()
		fh.add_child(flap)
		flaps.append(flap)
		var finv := fh.transform.affine_inverse()
		_painted(true, fh.transform)
		for k in 6:
			var xa := s * lerpf(FLAP0, FLAP1, k / 6.0)
			var xb := s * lerpf(FLAP0, FLAP1, (k + 1) / 6.0)
			var a0: Vector3 = finv * (wpt(xa, 0.72, false) + Vector3(0, -0.004, 0))
			var a1: Vector3 = finv * (wpt(xb, 0.72, false) + Vector3(0, -0.004, 0))
			var b0: Vector3 = finv * (wpt(xa, 0.97, false) + Vector3(0, -0.004, 0))
			var b1: Vector3 = finv * (wpt(xb, 0.97, false) + Vector3(0, -0.004, 0))
			_q(a0, a1, b1, b0, Vector3.DOWN, Color.WHITE)
			_q(a0 + Vector3(0, 0.006, 0), b0 + Vector3(0, 0.006, 0), b1 + Vector3(0, 0.006, 0), a1 + Vector3(0, 0.006, 0), Vector3.UP, Color.WHITE)
		_paint_end(1, flap)
		# radiator under the wing
		_painted(true)
		var rx := s * 1.85
		var R: Array = []
		var rz := [[-0.30, 0.17], [-0.18, 0.25], [0.15, 0.30], [0.60, 0.30], [0.95, 0.26], [1.22, 0.20]]
		for r in rz:
			var zc: float = r[0]
			var dep: float = r[1]
			var ytop: float = _w_lower_y(rx, zc) + 0.02
			var ring3: Array = []
			for i in 13:
				var t := PI + PI * i / 12.0
				var c := cos(t)
				var sn := sin(t)
				ring3.append(Vector3(rx + 0.28 * signf(c) * pow(absf(c), 2.0 / 3.5), ytop + dep * signf(sn) * pow(absf(sn), 2.0 / 3.5), zc))
			R.append(ring3)
		_grid(R, false, func(p: Vector3) -> Vector3: return Vector3(p.x - rx, -1.0, 0.0).normalized(), none)
		_paint_end(5, am.outer)
		var dark := _mat(Color("#070708"), 0.9)
		var mz: float = rz[0][0]
		_box(am.outer, Vector3(0.5, 0.13, 0.01), Vector3(rx, _w_lower_y(rx, mz) - 0.07, mz + 0.01), dark)
		_box(am.outer, Vector3(0.5, 0.15, 0.01), Vector3(rx, _w_lower_y(rx, 1.22) - 0.08, 1.21), dark)
		# 20 mm cannon: fairing and barrel out of the leading edge, a blister on top
		var cx := s * 1.95
		var le := wpt(cx, 0.0, true)
		var gun := _mat(Color("#1c1d1f"), 0.45, 0.6)
		_limb(am.outer, le + Vector3(0, 0.0, 0.1), le + Vector3(0, 0.0, -0.22), 0.045, _mat(Color("#2f3a2a"), 0.65), false)
		_limb(am.outer, le + Vector3(0, 0.0, -0.2), le + Vector3(0, 0.0, -0.62), 0.022, gun, false)
		_limb(am.outer, le + Vector3(0, 0.0, -0.6), le + Vector3(0, 0.0, -0.66), 0.026, gun, false)
		var top := wpt(cx, 0.32, true)
		_sph(am.outer, 0.11, top + Vector3(0, 0.0, 0), _mat(Color("#3a4234"), 0.65), Vector3(0.9, 0.28, 2.2))


func _w_lower_y(x: float, z: float) -> float:
	var c := chord(absf(x))
	return wpt(x, clampf((z + 0.3 * c) / c, 0.0, 1.0), false).y


func _sp_tail() -> void:
	var none := func(_p, _n): return Color.WHITE
	var tout := func(p: Vector3) -> Vector3: return Vector3(0, p.y - TP_Y, 0.0).normalized()
	_painted(true)
	for s: float in [1.0, -1.0]:
		var P: Array = []
		for xv in [0.0, 0.3, 0.6, 0.9, 1.15, 1.35, 1.48, 1.56, 1.595]:
			P.append(tring(s * float(xv), 0.0, TP_HINGE))
		_grid(P, true, tout, none)
		var tip: Vector3 = tpt(s * TP_SEMI, 0.3, true)
		_cap(P[P.size() - 1], Vector3(s, 0, 0), Color.WHITE)
		var _u := tip
	_paint_end(2, am.outer)
	# elevator on its hinge
	am.elevator.position = Vector3(0, TP_Y, tpt(0.0, TP_HINGE, true).z)
	am.outer.add_child(am.elevator)
	_painted(true, Transform3D(Basis(), am.elevator.position))
	var P2: Array = []
	for xv in [-1.595, -1.5, -1.3, -1.0, -0.6, -0.2, 0.0, 0.2, 0.6, 1.0, 1.3, 1.5, 1.595]:
		var ring: Array = []
		for p in tring(float(xv), TP_HINGE, 1.0):
			ring.append((p as Vector3) - am.elevator.position)
		P2.append(ring)
	_grid(P2, true, func(p: Vector3) -> Vector3: return Vector3(0, p.y, p.z * 0.2).normalized(), none)
	_paint_end(2, am.elevator)
	# fin (to the rudder hinge)
	_painted(true)
	var fout := func(p: Vector3) -> Vector3: return Vector3(p.x, 0, 0).normalized() if absf(p.x) > 1e-4 else Vector3.RIGHT
	var P3: Array = []
	for yv in [0.30, 0.42, 0.55, 0.68, 0.81, 0.94, 1.05, 1.14, 1.21, 1.26, 1.29]:
		var y: float = yv
		P3.append(fin_ring(y, 0.0, fin_fh(y)))
	_grid(P3, true, fout, none)
	_cap(P3[P3.size() - 1], Vector3.UP, Color.WHITE)
	_paint_end(3, am.outer)
	# rudder on its hinge
	var hinge := Node3D.new()
	hinge.position = Vector3(0, 0, RUD_Z)
	am.outer.add_child(hinge)
	hinge.add_child(am.rudder)
	_painted(true, hinge.transform)
	var P4: Array = []
	for yv in [-0.07, -0.02, 0.06, 0.16, 0.30, 0.42, 0.55, 0.68, 0.81, 0.94, 1.05, 1.14, 1.21, 1.26, 1.29]:
		var y2: float = yv
		var ring4: Array = []
		for p in fin_ring(y2, fin_fh(y2), 1.0):
			ring4.append((p as Vector3) - hinge.position)
		P4.append(ring4)
	_grid(P4, true, func(p: Vector3) -> Vector3: return Vector3(p.x, 0, 0).normalized() if absf(p.x) > 1e-4 else Vector3.RIGHT, none)
	_cap(P4[0], Vector3.DOWN, Color.WHITE)
	_cap(P4[P4.size() - 1], Vector3.UP, Color.WHITE)
	_paint_end(3, am.rudder)


func _sp_wheel(pos: Vector3, r: float, width: float, spokes: int) -> Node3D:
	var piv := Node3D.new()
	piv.position = pos
	am.outer.add_child(piv)
	var tyre := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r * 0.6
	tm.outer_radius = r
	tm.rings = 28
	tm.ring_segments = 14
	tyre.mesh = tm
	tyre.material_override = rubber
	tyre.rotation.z = PI / 2.0
	tyre.scale = Vector3(width / (r * 0.4), 1.0, 1.0)
	piv.add_child(tyre)
	var hub_m := _mat(Color("#8e9294"), 0.55, 0.2)
	var hub := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = r * 0.62
	hm.bottom_radius = r * 0.62
	hm.height = width * 0.55
	hm.radial_segments = 20
	hub.mesh = hm
	hub.material_override = hub_m
	hub.rotation.z = PI / 2.0
	piv.add_child(hub)
	for k in spokes:
		var a := TAU * k / spokes
		_box(piv, Vector3(width * 0.75, r * 0.12, r * 0.95), Vector3(0, 0, 0), hub_m, Vector3(a, 0, 0))
	_sph(piv, r * 0.18, Vector3.ZERO, steel, Vector3(width * 2.2, 1, 1))
	am.wheels.append(piv)
	return piv


func _sp_gear() -> void:
	var oleo := _mat(Color("#c9cdd2"), 0.22, 0.9)
	var leg_m := _mat(Color("#8e9294"), 0.55, 0.3)
	var fair := _mat(Color("#8e9294"), 0.6)
	for s: float in [-1.0, 1.0]:
		var pivot := Vector3(s * 0.62, -0.60, -0.22)
		var axle := Vector3(s * 0.95, -1.435, -0.85)
		var mid := pivot.lerp(axle, 0.58)
		_limb(am.outer, pivot, mid, 0.05, leg_m)
		_limb(am.outer, mid, axle + (pivot - axle).normalized() * 0.08, 0.036, oleo)
		_limb(am.outer, axle, axle - Vector3(s * 0.11, 0, 0), 0.03, steel, false)
		# torque links
		var tl0 := mid + Vector3(0, 0, -0.07)
		_limb(am.outer, tl0, tl0.lerp(axle, 0.5) + Vector3(0, 0, -0.08), 0.012, steel)
		_limb(am.outer, tl0.lerp(axle, 0.5) + Vector3(0, 0, -0.08), axle + Vector3(0, 0.06, -0.05), 0.012, steel)
		_sp_wheel(axle - Vector3(s * 0.11, 0, 0), 0.315, 0.17, 4)
		# leg fairing (the door that closes the wheel well), a flat oval on the outer side of the leg
		var up := (pivot - axle).normalized()
		var fwd := Vector3(0, 0, -1)
		var side := up.cross(fwd).normalized() * s
		var fwd2 := side.cross(up).normalized() * s
		var c := pivot.lerp(axle, 0.48) + side * 0.06
		var b := Basis(side, up, -fwd2 * s * s)
		var door := Node3D.new()
		door.transform = Transform3D(b.orthonormalized(), c)
		am.outer.add_child(door)
		var dm := _sph(door, 1.0, Vector3.ZERO, fair, Vector3(0.012, 0.52, 0.2))
		dm.name = "gear_door"
	# tail wheel: castoring, on a short fork
	var tw := Vector3(0, -0.261, 5.30)
	var top := Vector3(0, float(fs(5.25)[2]) + 0.03, 5.22)
	_limb(am.outer, top, tw + Vector3(0, 0.1, 0.0), 0.03, leg_m)
	for s2: float in [-1.0, 1.0]:
		_limb(am.outer, tw + Vector3(s2 * 0.05, 0.12, -0.02), tw + Vector3(s2 * 0.05, 0, 0), 0.012, leg_m)
	_sp_wheel(tw, 0.125, 0.075, 3)


func _sp_prop() -> void:
	am.prop.position = Vector3(0, 0.0, -3.02)
	am.outer.add_child(am.prop)
	# spinner (Sky), long and pointed as on the Rotol propeller
	_painted(true, Transform3D(Basis(), am.prop.position))
	var sp: Array = []
	var prof := [[-0.58, 0.0], [-0.555, 0.055], [-0.49, 0.125], [-0.39, 0.195], [-0.26, 0.256], [-0.12, 0.303], [0.0, 0.328], [0.13, 0.334]]
	for pr in prof:
		var ring: Array = []
		for i in 32:
			var t := TAU * i / 32.0
			ring.append(Vector3(cos(t) * float(pr[1]), sin(t) * float(pr[1]), float(pr[0])))
		sp.append(ring)
	_grid(sp, true, func(p: Vector3) -> Vector3: return Vector3(p.x, p.y, -0.25).normalized(), func(_p, _n): return Color.WHITE)
	_paint_end(4, am.prop)
	# four broad Rotol blades: black, yellow tips, a twist from coarse at the root to fine at the tip
	enc = false
	for bi in 4:
		var piv := Node3D.new()
		piv.rotation.z = bi * PI / 2.0 + PI / 4.0
		am.prop.add_child(piv)
		var P: Array = []
		var n := 12
		for k in n + 1:
			var u := k / float(n)
			var r := lerpf(0.24, 1.635, u)
			var ch := (0.17 + 0.17 * sin(clampf(u * 1.25, 0.0, 1.0) * PI * 0.8)) * (1.0 - 0.75 * pow(u, 7.0))
			var tw := deg_to_rad(lerpf(58.0, 20.0, u))
			var th := lerpf(0.07, 0.014, u)
			var ring: Array = []
			for i in 12:
				var a := TAU * i / 12.0
				var lx := cos(a) * ch * 0.5
				var lz := sin(a) * th * 0.5
				# clockwise from behind: the top blade moves to the right (+x), its leading edge forward (-z)
				ring.append(Vector3(lx * cos(tw) + lz * sin(tw), r, -lx * sin(tw) + lz * cos(tw)))
			P.append(ring)
		var ycol := YEL
		var bcol := Color("#101010").srgb_to_linear()
		_grid(P, true, func(p: Vector3) -> Vector3: return Vector3(p.x, 0, p.z).normalized(), func(p: Vector3, _n): return ycol if p.y > 1.52 else bcol)
		_cap(P[P.size() - 1], Vector3.UP, ycol)
		_end(matte, piv)
		am.blades.append(piv)
	# the spinning propeller from the cockpit: a faint disc with the yellow tips as a ring
	var dsh := Shader.new()
	dsh.code = """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform float strength = 0.0;
void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float tip = step(0.93, r);
	ALBEDO = mix(vec3(0.04), vec3(0.85, 0.6, 0.0), tip);
	ALPHA = strength * smoothstep(1.0, 0.985, r) * smoothstep(0.18, 0.26, r) * mix(0.1, 0.3, tip);
}"""
	var dm := ShaderMaterial.new()
	dm.shader = dsh
	var dq := QuadMesh.new()
	dq.size = Vector2(3.27, 3.27)
	var disc := MeshInstance3D.new()
	disc.mesh = dq
	disc.material_override = dm
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	am.prop.add_child(disc)
	am.disc = disc


func _sp_details() -> void:
	# six exhaust stacks each side (Merlin 60 series), sooty metal
	var ex := _mat(Color("#3a2c25"), 0.8, 0.55)
	var inner := _mat(Color("#0a0807"), 0.95)
	for s: float in [-1.0, 1.0]:
		for k in 6:
			var z := -2.36 + k * 0.165
			var y := 0.11
			var x := fx(z, y) * s
			var stack := Node3D.new()
			stack.position = Vector3(x, y, z)
			stack.rotation = Vector3(0, s * 0.12, 0)
			am.outer.add_child(stack)
			_box(stack, Vector3(0.09, 0.095, 0.11), Vector3(s * 0.035, 0, 0.01), ex, Vector3(0, 0, 0))
			_box(stack, Vector3(0.02, 0.07, 0.085), Vector3(s * 0.081, 0, 0.012), inner)
		# exhaust glare shield? (Mk IX has none) - a small air intake behind the stacks for the cabin
	# antenna mast behind the canopy and the wire to the fin
	var dark := _mat(Color("#1b1d1a"), 0.6)
	var mast_base := Vector3(0, float(fs(1.62)[1]) - 0.01, 1.62)
	var mast_top := mast_base + Vector3(0, 0.36, 0.14)
	_limb(am.outer, mast_base, mast_base.lerp(mast_top, 0.5), 0.016, dark)
	_limb(am.outer, mast_base.lerp(mast_top, 0.5), mast_top, 0.009, dark)
	_limb(am.outer, mast_top, Vector3(0, FIN_TOP - 0.06, fin_le(FIN_TOP - 0.06) + 0.12), 0.0025, dark, false)
	# pitot head under the left wing
	var pit := wpt(-4.25, 0.25, false)
	_limb(am.outer, pit, pit + Vector3(0, -0.1, -0.04), 0.012, steel, false)
	_limb(am.outer, pit + Vector3(0, -0.1, -0.04), pit + Vector3(0, -0.1, -0.5), 0.009, steel, false)
	# navigation lights: wing tips (red left, green right) and the tail light on the rudder
	var navr := _mat(Color(1, 0.1, 0.1))
	navr.emission_enabled = true
	navr.emission = Color(1, 0.1, 0.1)
	navr.emission_energy_multiplier = 2.0
	var navg := navr.duplicate() as StandardMaterial3D
	navg.albedo_color = Color(0.1, 1, 0.3)
	navg.emission = Color(0.1, 1, 0.3)
	var navw := navr.duplicate() as StandardMaterial3D
	navw.albedo_color = Color(1, 1, 1)
	navw.emission = Color(1, 1, 1)
	_sph(am.outer, 0.028, wpt(-5.58, 0.25, true) + Vector3(0, -0.01, 0), navr, Vector3(1, 0.6, 2.0))
	_sph(am.outer, 0.028, wpt(5.58, 0.25, true) + Vector3(0, -0.01, 0), navg, Vector3(1, 0.6, 2.0))
	_sph(am.rudder, 0.022, Vector3(0, 0.45, rud_te(0.45) - RUD_Z + 0.005), navw)


func _sp_pilot() -> void:
	# the pilot as you see him through the canopy from outside: leather helmet, goggles, oxygen mask, jacket
	var root := Node3D.new()
	am.fus.add_child(root)
	var jacket := _mat(Color("#3b3324"), 0.85)
	var helmet := _mat(Color("#4a3322"), 0.6)
	var mask := _mat(Color("#2c3128"), 0.7)
	var goggle := _mat(Color("#0e1214"), 0.08, 0.4)
	var h := EYE + Vector3(0, 0.035, 0.07)
	_limb(root, Vector3(0, 0.12, 0.52), Vector3(0, 0.56, 0.47), 0.18, jacket)
	for s: float in [-1.0, 1.0]:
		_limb(root, Vector3(s * 0.17, 0.53, 0.46), Vector3(s * 0.2, 0.3, 0.3), 0.06, jacket)
		_limb(root, Vector3(s * 0.2, 0.3, 0.3), Vector3(s * 0.06, 0.32, 0.05), 0.05, jacket)
	_sph(root, 0.1, h, _mat(Color("#d2a387"), 0.6))
	_sph(root, 0.115, h + Vector3(0, 0.03, 0.02), helmet, Vector3(1, 1, 1.08))
	_sph(root, 0.06, h + Vector3(0, -0.04, -0.08), mask, Vector3(1.1, 1.1, 1))
	for s2: float in [-1.0, 1.0]:
		_sph(root, 0.03, h + Vector3(s2 * 0.045, 0.06, -0.085), goggle, Vector3(1, 0.8, 0.6))
	am.pilot_nodes = [root]


# ---------------------------------------------------------------- cockpit
func _sp_cockpit() -> void:
	var ck := am.cockpit_node
	enc = false
	var gg := _mat(Color("#7a8670"), 0.7)
	var black := _mat(Color("#121314"), 0.7)
	var blk_metal := _mat(Color("#1a1b1d"), 0.5, 0.4)
	# lining inside the fuselage sides, sill to the bottom, in interior grey-green
	var P: Array = []
	for z in [SP_CK0, -0.6, -0.3, 0.0, 0.3, 0.6, SP_CK1]:
		var f := fs(z)
		var yc := (float(f[1]) + float(f[2])) / 2.0
		var hh := (float(f[1]) - float(f[2])) / 2.0
		var ts := asin(clampf(pow(clampf((SP_SILL - yc) / hh, 0.0, 1.0), N_SE / 2.0), -1.0, 1.0))
		var ring: Array = []
		for i in 25:
			var t := ts - (i / 24.0) * (PI + 2.0 * ts)
			var p := fpt(z, t)
			ring.append(Vector3(p.x * 0.96, p.y * 0.97 + 0.01, z))
		P.append(ring)
	_grid(P, false, func(p: Vector3) -> Vector3: return Vector3(-p.x, 0.2 - p.y, 0).normalized(), func(p: Vector3, _n): return GG * (0.55 if p.y < -0.25 else 1.0))
	_end(interior_m, ck)
	# fuselage frames (ribs) round the cockpit and the longerons along the sill
	for z2 in [-0.6, -0.15, 0.3, 0.75]:
		for s: float in [-1.0, 1.0]:
			var a := Vector3(s * fx(z2, SP_SILL) * 0.93, SP_SILL - 0.01, z2)
			var b := Vector3(s * fx(z2, -0.2) * 0.93, -0.2, z2)
			_limb(ck, a, b, 0.012, gg, false)
	# the bulkhead in front of the pilot (the back of the fuel tank): a wall cut to the fuselage's shape, below the
	# panel, so you never see out through the bottom of the nose
	_begin()
	enc = false
	var wz := SP_CK0 + 0.03
	var wr: Array = []
	var wf := fs(wz)
	for i in 40:
		var p := fpt(wz, TAU * i / 40.0)
		wr.append(Vector3(p.x * 0.97, minf(p.y, SP_SILL - 0.01) * 0.98, wz))
	_cap(wr, Vector3(0, 0, 1), GG * 0.7)
	_end(interior_m, ck)
	var _wf := wf
	# the floor: the top of the wing's centre section, under the seat and the pilot's feet
	_box(ck, Vector3(0.6, 0.02, SP_CK1 - SP_CK0 - 0.04), Vector3(0, -0.29, (SP_CK0 + SP_CK1) / 2.0 + 0.02), _mat(Color("#3d4436"), 0.85))
	# the door on the left: a frame and the crowbar clipped to it
	_box(ck, Vector3(0.01, 0.3, 0.62), Vector3(-fx(0.2, 0.32) * 0.92, 0.33, 0.2), gg)
	_limb(ck, Vector3(-fx(0.2, 0.3) * 0.9, 0.3, -0.05), Vector3(-fx(0.2, 0.3) * 0.9, 0.34, 0.45), 0.009, _mat(Color("#b8b9b4"), 0.4, 0.7), false)
	# armour and headrest behind the pilot, the rear wall
	_box(ck, Vector3(0.48, 0.5, 0.025), Vector3(0, 0.55, 0.9), _mat(Color("#4e5648"), 0.6, 0.3), Vector3(0.12, 0, 0))
	_box(ck, Vector3(0.2, 0.14, 0.07), Vector3(0, 0.83, 0.86), _mat(Color("#2a2420"), 0.85), Vector3(0.12, 0, 0))
	# the seat (moulded resin, reddish brown) with the parachute pack, Sutton harness
	var seat := _mat(Color("#5b2f1e"), 0.45)
	_box(ck, Vector3(0.42, 0.035, 0.42), Vector3(0, -0.03, 0.48), seat)
	_box(ck, Vector3(0.42, 0.5, 0.035), Vector3(0, 0.2, 0.71), seat, Vector3(-0.18, 0, 0))
	for s3: float in [-1.0, 1.0]:
		_box(ck, Vector3(0.03, 0.4, 0.42), Vector3(s3 * 0.21, 0.12, 0.52), seat, Vector3(-0.1, 0, 0))
	_box(ck, Vector3(0.36, 0.12, 0.36), Vector3(0, 0.04, 0.48), _mat(Color("#3a3f2e"), 0.9))
	var strap := _mat(Color("#8a7f60"), 0.85)
	for s4: float in [-1.0, 1.0]:
		_limb(ck, Vector3(s4 * 0.1, 0.62, 0.74), Vector3(s4 * 0.08, 0.2, 0.42), 0.011, strap, false)
		_limb(ck, Vector3(s4 * 0.2, 0.06, 0.5), Vector3(s4 * 0.03, 0.12, 0.3), 0.011, strap, false)
	_sph(ck, 0.035, Vector3(0, 0.15, 0.32), steel, Vector3(1, 1, 0.4))
	# the instrument panel: black, tilted back a little, the live gauges drawn into a SubViewport
	var pw := SpitfirePanel.W
	var ph := SpitfirePanel.H
	var vp := SubViewport.new()
	vp.size = Vector2i(int(pw * BulldogPanel.PXM), int(ph * BulldogPanel.PXM))
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.disable_3d = true
	vp.msaa_2d = Viewport.MSAA_2X
	var panel_fixed := SpitfirePanel.new()
	panel_fixed.set_layer("static")
	panel_fixed.size = Vector2(vp.size)
	vp.add_child(panel_fixed)
	panel_ui = SpitfirePanel.new()
	panel_ui.set_layer("live")
	panel_ui.size = Vector2(vp.size)
	vp.add_child(panel_ui)
	ck.add_child(vp)
	var pnode := Node3D.new()
	pnode.position = Vector3(0, 0.455, -0.47)
	pnode.rotation.x = deg_to_rad(-8.0)
	ck.add_child(pnode)
	var pm := StandardMaterial3D.new()
	pm.albedo_texture = vp.get_texture()
	pm.emission_enabled = true
	pm.emission_texture = vp.get_texture()
	pm.emission_energy_multiplier = 0.35
	pm.roughness = 0.7
	var rows: Array = []
	for j in 21:
		var yl := lerpf(-ph / 2.0, ph / 2.0, j / 20.0)
		var wp: Vector3 = pnode.transform * Vector3(0, yl, 0)
		var half := minf(pw / 2.0, fx(wp.z, minf(wp.y, SP_SILL)) * 0.93)
		if wp.y > SP_SILL:
			half = minf(half, (fx(WS_TOP, SP_SILL) + 0.0) * (1.0 - (wp.y - SP_SILL) / 0.5) * 0.95)
		rows.append([yl, half])
	var pmi := MeshInstance3D.new()
	pmi.mesh = _plate(rows, 0.0, pw, ph)
	pmi.material_override = pm
	pnode.add_child(pmi)
	var back := MeshInstance3D.new()
	back.mesh = _plate(rows, -0.015, pw, ph)
	var back_m := _mat(Color("#141517"), 0.8)
	back_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	back.material_override = back_m
	pnode.add_child(back)
	var bezel := _mat(Color("#0b0b0c"), 0.4, 0.4)
	var gglass := StandardMaterial3D.new()
	gglass.albedo_color = Color(0.9, 0.95, 1.0, 0.07)
	gglass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gglass.roughness = 0.03
	gglass.metallic_specular = 1.0
	for l in SpitfirePanel.GAUGES:
		var c := Vector3(float(l[1]) - pw / 2.0, ph / 2.0 - float(l[2]), 0.0)
		var r: float = l[3]
		var tm := TorusMesh.new()
		tm.inner_radius = r * 0.99
		tm.outer_radius = r * 1.12
		tm.rings = 36
		tm.ring_segments = 8
		var bz := MeshInstance3D.new()
		bz.mesh = tm
		bz.material_override = bezel
		bz.position = c + Vector3(0, 0, 0.004)
		bz.rotation.x = PI / 2.0
		bz.scale = Vector3(1, 0.45, 1)
		pnode.add_child(bz)
		var gm := CylinderMesh.new()
		gm.top_radius = r
		gm.bottom_radius = r
		gm.height = 0.001
		gm.radial_segments = 28
		var gl := MeshInstance3D.new()
		gl.mesh = gm
		gl.material_override = gglass
		gl.position = c + Vector3(0, 0, 0.008)
		gl.rotation.x = PI / 2.0
		gl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pnode.add_child(gl)
	# the blind-flying panel stands proud of the main panel on its rubber mounts
	var bfp: Rect2 = SpitfirePanel.BFP
	_box(pnode, Vector3(bfp.size.x, bfp.size.y, 0.012), Vector3(bfp.position.x + bfp.size.x / 2.0 - pw / 2.0, ph / 2.0 - bfp.position.y - bfp.size.y / 2.0, -0.022), black)
	# switches, the undercarriage selector lights, the flap button, primer
	for k in 2:
		var sx := 0.045 + k * 0.03 - pw / 2.0
		_limb(pnode, Vector3(sx, ph / 2.0 - 0.15, 0.0), Vector3(sx, ph / 2.0 - 0.145, 0.025), 0.003, steel, false)
	_limb(pnode, Vector3(0.13 - pw / 2.0, ph / 2.0 - 0.06, 0.0), Vector3(0.13 - pw / 2.0, ph / 2.0 - 0.06, 0.02), 0.009, _mat(Color("#2a2a2a"), 0.5), false)
	# coaming (the top of the panel) out to the windscreen
	var shade := Color("#0d0e0d").srgb_to_linear()
	_begin()
	var topw: float = rows[rows.size() - 1][1]
	var steps := 12
	for i in steps:
		var x0 := lerpf(-topw, topw, i / float(steps))
		var x1 := lerpf(-topw, topw, (i + 1) / float(steps))
		var r0: Vector3 = pnode.transform * Vector3(x0, ph / 2.0, 0.03)
		var r1: Vector3 = pnode.transform * Vector3(x1, ph / 2.0, 0.03)
		var fw := fx(SP_CK0, SP_SILL) * 0.96
		var f0 := Vector3(clampf(x0 * 1.3, -fw, fw), SP_SILL + 0.012, SP_CK0 + 0.02)
		var f1 := Vector3(clampf(x1 * 1.3, -fw, fw), SP_SILL + 0.012, SP_CK0 + 0.02)
		_q(r0, r1, f1, f0, Vector3.UP, shade)
	var cm := _mat(Color("#0d0e0d"), 0.95)
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_end(cm, ck)
	# reflector gunsight on top of the panel, its glass and the orange ring
	var gs := Node3D.new()
	gs.position = Vector3(0, 0.62, -0.53)
	ck.add_child(gs)
	_box(gs, Vector3(0.085, 0.11, 0.17), Vector3(0, 0, 0), blk_metal)
	_limb(gs, Vector3(0, -0.01, 0.085), Vector3(0, -0.01, 0.11), 0.022, _mat(Color("#2a2420"), 0.85), false)   # rubber crash pad
	var rg := StandardMaterial3D.new()
	rg.albedo_color = Color(0.75, 0.85, 0.8, 0.1)
	rg.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rg.roughness = 0.02
	rg.cull_mode = BaseMaterial3D.CULL_DISABLED
	var plate := _box(gs, Vector3(0.09, 0.085, 0.003), Vector3(0, 0.1, -0.03), rg, Vector3(-0.55, 0, 0))
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ringsh := Shader.new()
	ringsh.code = """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float r = length(d);
	float ring = smoothstep(0.035, 0.0, abs(r - 0.78));
	float dot = smoothstep(0.07, 0.03, r);
	float cross = (smoothstep(0.02, 0.0, abs(d.x)) + smoothstep(0.02, 0.0, abs(d.y))) * step(0.82, r) * step(r, 0.97);
	ALBEDO = vec3(1.0, 0.45, 0.08);
	ALPHA = clamp(ring + dot + cross, 0.0, 1.0) * 0.85;
}"""
	var rm := ShaderMaterial.new()
	rm.shader = ringsh
	var rq := QuadMesh.new()
	rq.size = Vector2(0.075, 0.075)
	gun_ring = MeshInstance3D.new()
	gun_ring.mesh = rq
	gun_ring.material_override = rm
	gun_ring.position = Vector3(0, 0.1, -0.028)
	gun_ring.rotation.x = -0.55
	gun_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gs.add_child(gun_ring)
	# compass between the knees, under the panel
	_sph(ck, 0.055, Vector3(0, 0.2, -0.36), black, Vector3(1, 0.75, 1))
	var cw := _sph(ck, 0.04, Vector3(0, 0.235, -0.36), _mat(Color("#d8d2b8"), 0.4), Vector3(1, 0.3, 1))
	cw.name = "compass_card"
	# control column and the spade grip (ring) with its gun button and brake lever
	var piv := Node3D.new()
	piv.position = Vector3(0, -0.32, -0.12)
	ck.add_child(piv)
	_limb(piv, Vector3.ZERO, Vector3(0, 0.46, 0.04), 0.02, _mat(Color("#2b2d2b"), 0.5, 0.4), false)
	spade = Node3D.new()
	spade.position = Vector3(0, 0.46, 0.04)
	piv.add_child(spade)
	var tor := TorusMesh.new()
	tor.inner_radius = 0.072
	tor.outer_radius = 0.098
	tor.rings = 32
	tor.ring_segments = 10
	var ringm := MeshInstance3D.new()
	ringm.mesh = tor
	ringm.material_override = _mat(Color("#18181a"), 0.4)
	ringm.position = Vector3(0, 0.1, 0)
	ringm.rotation.x = PI / 2.0
	spade.add_child(ringm)
	_limb(spade, Vector3(0, 0.0, 0), Vector3(0, 0.02, 0), 0.02, _mat(Color("#2b2d2b"), 0.5, 0.4), false)
	_box(spade, Vector3(0.05, 0.03, 0.035), Vector3(0, 0.19, 0.0), _mat(Color("#b08d3c"), 0.35, 0.8))   # gun button (brass)
	var lever := _limb(spade, Vector3(-0.06, 0.13, 0.03), Vector3(0.06, 0.13, 0.03), 0.007, steel, false)
	lever.name = "brake_lever"
	am.yoke = piv
	# rudder pedals: two-step bars on short arms
	for p: float in [-1.0, 1.0]:
		var pd := Node3D.new()
		pd.position = Vector3(p * 0.17, -0.22, -0.78)
		ck.add_child(pd)
		_box(pd, Vector3(0.11, 0.035, 0.05), Vector3(0, 0, 0), _mat(Color("#2b2d2b"), 0.55, 0.4))
		_box(pd, Vector3(0.11, 0.035, 0.05), Vector3(0, 0.1, -0.02), _mat(Color("#2b2d2b"), 0.55, 0.4))
		_limb(pd, Vector3(-0.055, 0, 0), Vector3(-0.055, 0.1, -0.02), 0.006, steel, false)
		_limb(pd, Vector3(0.055, 0, 0), Vector3(0.055, 0.1, -0.02), 0.006, steel, false)
		pedals.append([pd, p, pd.position.z])
	# throttle quadrant on the left wall: the throttle and the propeller pitch lever
	var xq := -fx(-0.2, 0.25) * 0.86
	_box(ck, Vector3(0.05, 0.08, 0.34), Vector3(xq, 0.28, -0.22), gg)
	throttle_lever = Node3D.new()
	throttle_lever.position = Vector3(xq + 0.035, 0.31, -0.2)
	ck.add_child(throttle_lever)
	_limb(throttle_lever, Vector3.ZERO, Vector3(0.0, 0.17, 0), 0.008, steel, false)
	_sph(throttle_lever, 0.022, Vector3(0.0, 0.18, 0), _mat(Color("#181818"), 0.45), Vector3(1, 0.8, 1.3))
	prop_lever = Node3D.new()
	prop_lever.position = Vector3(xq + 0.035, 0.31, -0.12)
	ck.add_child(prop_lever)
	_limb(prop_lever, Vector3.ZERO, Vector3(0.0, 0.12, 0), 0.006, steel, false)
	_sph(prop_lever, 0.014, Vector3(0.0, 0.125, 0), _mat(Color("#6a1f17"), 0.45))
	prop_lever.rotation.x = -0.3
	# elevator trim wheel (left side, behind the throttle) and the rudder trim knob
	trim_wheel = Node3D.new()
	trim_wheel.position = Vector3(-fx(0.15, 0.1) * 0.84, 0.12, 0.12)
	ck.add_child(trim_wheel)
	var tw := MeshInstance3D.new()
	var twm := CylinderMesh.new()
	twm.top_radius = 0.1
	twm.bottom_radius = 0.1
	twm.height = 0.022
	twm.radial_segments = 28
	tw.mesh = twm
	tw.material_override = black
	tw.rotation.z = PI / 2.0
	trim_wheel.add_child(tw)
	_box(trim_wheel, Vector3(0.026, 0.014, 0.16), Vector3.ZERO, _mat(Color("#d9d9d4"), 0.5))
	# right side: the undercarriage selector lever and a radio control box
	var xr := fx(-0.1, 0.25) * 0.86
	_box(ck, Vector3(0.05, 0.09, 0.22), Vector3(xr, 0.25, -0.05), gg)
	_limb(ck, Vector3(xr - 0.03, 0.26, -0.1), Vector3(xr - 0.05, 0.4, -0.12), 0.008, steel, false)
	_sph(ck, 0.018, Vector3(xr - 0.05, 0.405, -0.12), _mat(Color("#181818"), 0.45))
	_box(ck, Vector3(0.07, 0.1, 0.16), Vector3(xr - 0.01, 0.3, 0.35), _mat(Color("#20221f"), 0.6))


## Where a VR hand holds the spade grip (its right side).
func stick_grip() -> Transform3D:
	if spade == null:
		return Transform3D()
	var g := Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)), Vector3(0.085, 0.1, 0.0))
	return spade.global_transform * g.rotated_local(Vector3(1, 0, 0), 0.35)


## Where a VR hand holds the throttle knob.
func throttle_grip() -> Transform3D:
	if throttle_lever == null:
		return Transform3D()
	var g := Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)), Vector3(0.0, 0.18, 0.0))
	return throttle_lever.global_transform * g.rotated_local(Vector3(1, 0, 0), 0.9)


func animate(ctl: Dictionary, dt: float) -> void:
	var pitch: float = ctl.get("pitch", 0.0)
	var roll: float = ctl.get("roll", 0.0)
	var yaw: float = ctl.get("yaw", 0.0)
	if am.yoke != null:
		am.yoke.rotation = Vector3(pitch * 0.22, 0.0, 0.0)     # the column moves fore and aft
	if spade != null:
		spade.rotation = Vector3(0.0, 0.0, -roll * 0.45)       # the spade grip rolls for the ailerons
	for p in pedals:
		var node: Node3D = p[0]
		node.position.z = float(p[2]) + float(p[1]) * yaw * 0.06
	if throttle_lever != null:
		throttle_lever.rotation.x = lerpf(0.55, -0.55, float(ctl.get("throttle", 0.0)))
	if trim_wheel != null:
		trim_wheel.rotation.x = float(ctl.get("trim", 0.0)) * 8.0
	for f in flaps:
		# split flaps go straight down to 85 degrees (the real ones are up or down; half shows half)
		(f as Node3D).rotation.x = float(ctl.get("flaps_pos", 0.0)) * deg_to_rad(85.0)
