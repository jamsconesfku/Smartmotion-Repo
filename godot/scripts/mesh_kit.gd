class_name MeshKit
extends RefCounted
## Small helpers to build the aircraft out of code (no outside art).
## Godot treats clockwise triangles as front faces; add_tri() orients each triangle to match the normal you give it.

var verts := PackedVector3Array()
var norms := PackedVector3Array()
var cols := PackedColorArray()


func add_tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = c
		c = t
	verts.append_array([a, b, c])
	norms.append_array([n, n, n])
	cols.append_array([col, col, col])


func add_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
	add_tri(a, b, c, n, col)
	add_tri(a, c, d, n, col)


func add_smooth_tri(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	var n := (na + nb + nc)
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = c
		c = t
		t = nb
		nb = nc
		nc = t
		var tc := cb
		cb = cc
		cc = tc
	verts.append_array([a, b, c])
	norms.append_array([na, nb, nc])
	cols.append_array([ca, cb, cc])


func build() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


## Fuselage of revolution along z. profile: [[z, radius], ...] from nose (negative z) to tail. colour_fn(normal, pos) -> Color
static func lathe(profile: Array, segs: int, colour_fn: Callable) -> ArrayMesh:
	var k := MeshKit.new()
	var rings: Array = []
	for pi in profile.size():
		var z: float = profile[pi][0]
		var r: float = profile[pi][1]
		var prev: Array = profile[maxi(pi - 1, 0)]
		var nxt: Array = profile[mini(pi + 1, profile.size() - 1)]
		var slope := 0.0
		if nxt[0] != prev[0]:
			slope = -(float(nxt[1]) - float(prev[1])) / (float(nxt[0]) - float(prev[0]))
		var ring: Array = []
		for s in segs:
			var a := TAU * s / segs
			var p := Vector3(r * cos(a), r * sin(a), z)
			var n := Vector3(cos(a), sin(a), slope).normalized()
			ring.append([p, n, colour_fn.call(n, p)])
		rings.append(ring)
	for pi in range(profile.size() - 1):
		for s in segs:
			var s2 := (s + 1) % segs
			var a: Array = rings[pi][s]
			var b: Array = rings[pi][s2]
			var c: Array = rings[pi + 1][s2]
			var d: Array = rings[pi + 1][s]
			if profile[pi][1] > 0.001 or true:
				k.add_smooth_tri(a[0], b[0], c[0], a[1], b[1], c[1], a[2], b[2], c[2])
				k.add_smooth_tri(a[0], c[0], d[0], a[1], c[1], d[1], a[2], c[2], d[2])
	return k.build()


## Extruded flat shape (wing, tailplane). pts are (x, forward) pairs; thickness is y. Forward is -z.
static func slab_xf(pts: Array, thick: float, top_col: Color, bot_col: Color, side_col: Color) -> ArrayMesh:
	var k := MeshKit.new()
	var p3: Array = []
	for p in pts:
		p3.append(Vector3(p[0], 0.0, -float(p[1])))
	var h := thick / 2.0
	for i in range(1, p3.size() - 1):
		k.add_tri(p3[0] + Vector3(0, h, 0), p3[i] + Vector3(0, h, 0), p3[i + 1] + Vector3(0, h, 0), Vector3.UP, top_col)
		k.add_tri(p3[0] - Vector3(0, h, 0), p3[i] - Vector3(0, h, 0), p3[i + 1] - Vector3(0, h, 0), Vector3.DOWN, bot_col)
	for i in p3.size():
		var a: Vector3 = p3[i]
		var b: Vector3 = p3[(i + 1) % p3.size()]
		var e := b - a
		var n := Vector3(e.z, 0.0, -e.x).normalized()
		k.add_quad(a + Vector3(0, h, 0), b + Vector3(0, h, 0), b - Vector3(0, h, 0), a - Vector3(0, h, 0), n, side_col)
	return k.build()


## Extruded vertical shape (fin). pts are (forward, height) pairs; thickness is x.
static func slab_fy(pts: Array, thick: float, col: Color) -> ArrayMesh:
	var k := MeshKit.new()
	var p3: Array = []
	for p in pts:
		p3.append(Vector3(0.0, float(p[1]), -float(p[0])))
	var h := thick / 2.0
	for i in range(1, p3.size() - 1):
		k.add_tri(p3[0] + Vector3(h, 0, 0), p3[i] + Vector3(h, 0, 0), p3[i + 1] + Vector3(h, 0, 0), Vector3.RIGHT, col)
		k.add_tri(p3[0] - Vector3(h, 0, 0), p3[i] - Vector3(h, 0, 0), p3[i + 1] - Vector3(h, 0, 0), Vector3.LEFT, col)
	for i in p3.size():
		var a: Vector3 = p3[i]
		var b: Vector3 = p3[(i + 1) % p3.size()]
		var e := b - a
		var n := Vector3(0.0, -e.z, e.y)
		n = n.normalized()
		k.add_quad(a + Vector3(h, 0, 0), b + Vector3(h, 0, 0), b - Vector3(h, 0, 0), a - Vector3(h, 0, 0), n, col)
	return k.build()
