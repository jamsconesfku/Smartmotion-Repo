class_name RoadKit
extends RefCounted
## v1.23.0: the real roads (assets/world/roads.bin, scripts/build_roads.py, OS OpenMap Local) laid on the ground as road
## surfaces near you: a strip as wide as the real road, following the ground's shape every few metres, so the edges
## stay crisp and straight at any height and the road runs on unbroken through bends and junctions (the 1 m and 8 m
## ground pictures had them as pixels). shaders/road.gdshader draws the tarmac and the white lines.
## Per vertex: UV = (metres along the road, -1 left edge .. 1 right edge), UV2 = (metres to the nearer end of this
## road, its length), COLOR = (class / 16, dual carriageway, half width / 16, 1).

## carriageway width (m) for each class in roads.bin: motorway, primary (trunk A road), A, B, minor, local,
## local access, restricted local access, shared use, guided busway
const WIDTH := [11.0, 9.5, 7.3, 6.5, 5.5, 5.0, 3.8, 3.2, 3.5, 4.0]
const DUAL_K := 2.0       # a dual carriageway drawn as one road is this much wider (both sides and the middle)

var v := PackedVector3Array()
var n := PackedVector3Array()
var c := PackedColorArray()
var uv := PackedVector2Array()
var uv2 := PackedVector2Array()


## Adds one run of a road: pts in order, s = metres along the road at each point, total = the road's length.
func add_run(cls: int, dual: bool, pts: PackedVector2Array, s: PackedFloat32Array, total: float, terrain: Terrain) -> void:
	var np := pts.size()
	if np < 2:
		return
	var w: float = float(WIDTH[clampi(cls, 0, WIDTH.size() - 1)]) * (DUAL_K if dual else 1.0) * 0.5
	var col := Color((float(cls) + 0.5) / 16.0, 1.0 if dual else 0.0, w / 16.0, 1.0)
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	left.resize(np)
	right.resize(np)
	for i in np:
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, np - 1)]
		var t := (b - a).normalized()
		var nn := Vector2(-t.y, t.x)
		# keep the width through a bend (mitre), but not past twice the width at a sharp corner
		if i > 0 and i < np - 1:
			var t0 := (pts[i] - pts[i - 1]).normalized()
			var m := Vector2(-t0.y, t0.x)
			var k := nn.dot(m)
			if k > 0.5:
				nn = nn / k
		var pl := pts[i] + nn * w
		var pr := pts[i] - nn * w
		# on the ground at the edges and the middle (the highest of them, so the road never dips under the ground)
		var hm := terrain.height(pts[i].x, pts[i].y)
		var hl := maxf(terrain.height(pl.x, pl.y), hm - 0.25)
		var hr := maxf(terrain.height(pr.x, pr.y), hm - 0.25)
		left[i] = Vector3(pl.x, hl + 0.05, pl.y)
		right[i] = Vector3(pr.x, hr + 0.05, pr.y)
	for i in np - 1:
		var a0 := left[i]
		var a1 := left[i + 1]
		var b0 := right[i]
		var b1 := right[i + 1]
		var nrm := (a1 - a0).cross(b0 - a0).normalized()
		if nrm.y < 0.0:
			nrm = -nrm
		var e0 := minf(s[i], total - s[i])
		var e1 := minf(s[i + 1], total - s[i + 1])
		_tri(a0, a1, b1, nrm, col, Vector2(s[i], -1.0), Vector2(s[i + 1], -1.0), Vector2(s[i + 1], 1.0), Vector2(e0, total), Vector2(e1, total), Vector2(e1, total))
		_tri(a0, b1, b0, nrm, col, Vector2(s[i], -1.0), Vector2(s[i + 1], 1.0), Vector2(s[i], 1.0), Vector2(e0, total), Vector2(e1, total), Vector2(e0, total))


func _tri(a: Vector3, b: Vector3, cc: Vector3, nn: Vector3, col: Color, ua: Vector2, ub: Vector2, uc: Vector2, wa: Vector2, wb: Vector2, wc: Vector2) -> void:
	# Godot front faces are clockwise seen from above
	if (b - a).cross(cc - a).dot(nn) > 0.0:
		v.append_array([a, cc, b])
		uv.append_array([ua, uc, ub])
		uv2.append_array([wa, wc, wb])
	else:
		v.append_array([a, b, cc])
		uv.append_array([ua, ub, uc])
		uv2.append_array([wa, wb, wc])
	n.append_array([nn, nn, nn])
	c.append_array([col, col, col])


func arrays() -> Array:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_COLOR] = c
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	return arr
