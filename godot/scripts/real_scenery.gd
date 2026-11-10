class_name RealScenery
extends Node3D
## The real buildings and trees around Duxford, loaded in 1 km squares around the camera as you fly.
## Buildings: footprints and heights from Overture Maps (assets/world/buildings.bin, made by
## scripts/build_world_data.py), extruded with pitched roofs on houses. Trees: wherever ESA WorldCover marks
## tree cover (assets/world/landcover.png, red channel), with a detailed tree nearby and a simple one further out.

const CHUNK := 1024.0
const HALF := 16384.0
const NC := 32                       # chunks per side
const LC_PX := 4096                  # land cover pixels per side (8 m each)
const COLL_CELL := 128.0

var terrain: Terrain
var quality := "high"
var bld := {}                        # Vector2i chunk -> Array of [PackedVector2Array, height, kind]
var lc_data := PackedByteArray()
var chunks := {}                     # Vector2i -> Node3D
var coll_grid := {}                  # Vector2i cell -> Array of collider dicts
var bld_mat: ShaderMaterial
var tree_mat: StandardMaterial3D
var tree_near: Mesh
var tree_far: Mesh
var radius_bld := 6500.0
var radius_tree := 4200.0
var near_tree_range := 1100.0
var tree_density := 1.0
var _last_focus := Vector2(1e9, 1e9)
var _pending: Array = []
var total_buildings := 0


func setup(terrain_: Terrain, quality_: String, ortho: Texture2D) -> void:
	terrain = terrain_
	quality = quality_
	radius_bld = {"low": 3000.0, "medium": 5000.0, "high": 7000.0}.get(quality, 5000.0)
	radius_tree = {"low": 1800.0, "medium": 3000.0, "high": 4000.0}.get(quality, 3200.0)
	near_tree_range = {"low": 600.0, "medium": 900.0, "high": 1300.0}.get(quality, 900.0)
	tree_density = {"low": 0.35, "medium": 0.6, "high": 1.0}.get(quality, 0.6)
	_load_buildings()
	var lc: Texture2D = load("res://assets/world/landcover.png")
	if lc != null:
		var img := lc.get_image()
		if img.is_compressed():
			img.decompress()
		if img.get_width() != LC_PX:
			img.resize(LC_PX, LC_PX, Image.INTERPOLATE_NEAREST)
		img.convert(Image.FORMAT_RGBA8)
		lc_data = img.get_data()
	bld_mat = ShaderMaterial.new()
	bld_mat.shader = load("res://shaders/building.gdshader")
	bld_mat.set_shader_parameter("ortho", ortho)
	for k in ["brick", "plaster", "roof", "metal", "concrete"]:
		bld_mat.set_shader_parameter(k + "_col", load("res://assets/textures/%s_col.jpg" % k))
		bld_mat.set_shader_parameter(k + "_nrm", load("res://assets/textures/%s_nrm.jpg" % k))
	tree_mat = StandardMaterial3D.new()
	tree_mat.vertex_color_use_as_albedo = true
	tree_mat.roughness = 0.95
	tree_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	tree_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	tree_mat.backlight_enabled = true
	tree_mat.backlight = Color(0.05, 0.08, 0.02)
	tree_near = _leafy_mesh(true)
	tree_far = _leafy_mesh(false)


## VR draws two views at 72-90 fps: draw trees and buildings less far while it is on.
var _vr := false
func set_vr(on: bool) -> void:
	if on == _vr:
		return
	_vr = on
	var k := 0.6 if on else 1.0 / 0.6
	radius_bld *= k
	radius_tree *= k
	near_tree_range *= (0.75 if on else 1.0 / 0.75)
	for node in chunks.values():
		for ch in (node as Node3D).get_children():
			var gi := ch as GeometryInstance3D
			if gi is MultiMeshInstance3D and gi.visibility_range_begin > 0.0:
				gi.visibility_range_begin = near_tree_range
				gi.visibility_range_end = radius_tree
			elif gi is MultiMeshInstance3D:
				gi.visibility_range_end = near_tree_range
			elif gi != null:
				gi.visibility_range_end = radius_bld


# ---------------------------------------------------------------- data
func _load_buildings() -> void:
	var f := FileAccess.open("res://assets/world/buildings.bin", FileAccess.READ)
	if f == null:
		return
	var buf := f.get_buffer(f.get_length())
	var n := buf.decode_u32(0)
	var o := 4
	for b in n:
		var nv := buf.decode_u8(o)
		var kind := buf.decode_u8(o + 1)
		var h := buf.decode_u16(o + 2) / 10.0
		o += 4
		var pts := PackedVector2Array()
		pts.resize(nv)
		var cx := 0.0
		var cz := 0.0
		for k in nv:
			var x := buf.decode_s32(o) / 4.0
			var z := buf.decode_s32(o + 4) / 4.0
			o += 8
			pts[k] = Vector2(x, z)
			cx += x
			cz += z
		var key := _chunk_of(Vector2(cx / nv, cz / nv))
		if not bld.has(key):
			bld[key] = []
		bld[key].append([pts, h, kind])
	total_buildings = n


func _chunk_of(p: Vector2) -> Vector2i:
	return Vector2i(int(floor((p.x + HALF) / CHUNK)), int(floor((p.y + HALF) / CHUNK)))


func _chunk_centre(c: Vector2i) -> Vector2:
	return Vector2(-HALF + (c.x + 0.5) * CHUNK, -HALF + (c.y + 0.5) * CHUNK)


# ---------------------------------------------------------------- streaming
## Load everything near p straight away (used while the loading screen is up).
func preload_around(p: Vector2) -> void:
	_last_focus = Vector2(1e9, 1e9)
	update(p, 999)


## Called every frame with the camera position: queues squares that came into range, frees far ones,
## and builds up to `budget` squares this frame.
func update(p: Vector2, budget := 1) -> void:
	if p.distance_to(_last_focus) > 200.0:
		_last_focus = p
		var r := maxf(radius_bld, radius_tree)
		var want := {}
		var c0 := _chunk_of(p)
		var span := int(ceil(r / CHUNK)) + 1
		for j in range(c0.y - span, c0.y + span + 1):
			for i in range(c0.x - span, c0.x + span + 1):
				if i < 0 or j < 0 or i >= NC or j >= NC:
					continue
				var c := Vector2i(i, j)
				if _chunk_centre(c).distance_to(p) < r + CHUNK * 0.71:
					want[c] = true
		for c in chunks.keys():
			if not want.has(c) and _chunk_centre(c).distance_to(p) > r + CHUNK * 2.0:
				_free_chunk(c)
		_pending = []
		for c in want.keys():
			if not chunks.has(c):
				_pending.append(c)
		_pending.sort_custom(func(a, b): return _chunk_centre(a).distance_squared_to(p) < _chunk_centre(b).distance_squared_to(p))
	var n := 0
	while n < budget and _pending.size() > 0:
		_build_chunk(_pending.pop_front())
		n += 1


func _free_chunk(c: Vector2i) -> void:
	var node: Node3D = chunks[c]
	node.queue_free()
	chunks.erase(c)
	for k in coll_grid.keys():
		var arr: Array = coll_grid[k]
		var keep: Array = []
		for col in arr:
			if col["chunk"] != c:
				keep.append(col)
		coll_grid[k] = keep


## Buildings the aircraft could hit near p (a short list for the flight model).
func colliders_near(p: Vector2) -> Array:
	var out: Array = []
	var c := Vector2i(int(floor(p.x / COLL_CELL)), int(floor(p.y / COLL_CELL)))
	for j in range(c.y - 2, c.y + 3):
		for i in range(c.x - 2, c.x + 3):
			var k := Vector2i(i, j)
			if coll_grid.has(k):
				out.append_array(coll_grid[k])
	return out


func _build_chunk(c: Vector2i) -> void:
	var node := Node3D.new()
	add_child(node)
	chunks[c] = node
	var centre := _chunk_centre(c)
	if bld.has(c):
		var mesh := _building_mesh(bld[c], c)
		if mesh != null:
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = bld_mat
			mi.visibility_range_end = radius_bld
			mi.visibility_range_end_margin = 400.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			node.add_child(mi)
	if lc_data.size() > 0 and centre.distance_to(_last_focus) < radius_tree + CHUNK:
		_trees(c, node)


# ---------------------------------------------------------------- buildings
var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _c := PackedColorArray()
var _uv := PackedVector2Array()


func _tri(a: Vector3, b: Vector3, cc: Vector3, n: Vector3, col: Color, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	# Godot front faces are clockwise: flip the triangle if it faces the other way
	if (b - a).cross(cc - a).dot(n) > 0.0:
		_v.append_array([a, cc, b])
		_uv.append_array([ua, uc, ub])
	else:
		_v.append_array([a, b, cc])
		_uv.append_array([ua, ub, uc])
	_n.append_array([n, n, n])
	_c.append_array([col, col, col])


func _quad(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, n: Vector3, col: Color, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	_tri(a, b, cc, n, col, ua, ub, uc)
	_tri(a, cc, d, n, col, ua, uc, ud)


func _building_mesh(list: Array, c: Vector2i) -> ArrayMesh:
	_v = PackedVector3Array()
	_n = PackedVector3Array()
	_c = PackedColorArray()
	_uv = PackedVector2Array()
	var rng := RandomNumberGenerator.new()
	for rec in list:
		var pts: PackedVector2Array = rec[0]
		var h: float = rec[1]
		var kind: int = rec[2]
		var nv := pts.size()
		rng.seed = hash(pts[0])
		var gmin := 1e9
		for p in pts:
			gmin = minf(gmin, terrain.height(p.x, p.y))
		var base := gmin - 0.6
		# footprint winding (shoelace) so walls face outwards
		var area := 0.0
		for i in nv:
			var a := pts[i]
			var b := pts[(i + 1) % nv]
			area += a.x * b.y - b.x * a.y
		var sgn := 1.0 if area > 0.0 else -1.0
		# gable roofs on simple four-corner houses and sheds
		var gable := nv == 4 and kind != 2
		var long_i := 0
		var e0 := (pts[1] - pts[0]).length()
		var e1 := (pts[2] - pts[1]).length()
		if e1 > e0:
			long_i = 1
		var short := minf(e0, e1)
		var ridge := 0.0
		if gable:
			ridge = clampf(short * (0.42 if kind == 0 else 0.14), 1.0, 6.0)
		var wall_h := maxf(h - ridge, 2.6)
		var top := gmin + wall_h
		# colours: walls (brick, render, metal cladding) and roofs (tiles, slate, metal); alpha = material id
		var wall_col: Color
		var wall_id: float
		if kind == 1:
			wall_col = [Color(0.55, 0.57, 0.55), Color(0.42, 0.47, 0.42), Color(0.6, 0.58, 0.52)][rng.randi() % 3]
			wall_id = 0.75
		elif rng.randf() < 0.62:
			wall_col = Color(1, 1, 1).lerp(Color(0.85, 0.75, 0.65), rng.randf())
			wall_id = 0.0
		else:
			wall_col = [Color(0.93, 0.9, 0.84), Color(0.95, 0.93, 0.88), Color(0.86, 0.82, 0.72)][rng.randi() % 3]
			wall_id = 0.25
		var roof_col: Color
		var roof_id: float
		if kind == 1 or not gable:
			roof_col = Color(0.62, 0.63, 0.64).lerp(Color(0.45, 0.48, 0.47), rng.randf())
			roof_id = 1.0
		else:
			roof_col = [Color(0.62, 0.36, 0.28), Color(0.45, 0.3, 0.26), Color(0.36, 0.38, 0.42), Color(0.55, 0.4, 0.32)][rng.randi() % 4]
			roof_id = 0.5
		wall_col.a = wall_id
		roof_col.a = roof_id
		# walls
		var ulen := 0.0
		for i in nv:
			var a := pts[i]
			var b := pts[(i + 1) % nv]
			var d := b - a
			var len := d.length()
			if len < 0.05:
				continue
			var nrm := Vector3(d.y, 0, -d.x).normalized() * sgn
			var A := Vector3(a.x, base, a.y)
			var B := Vector3(b.x, base, b.y)
			var wall_top := top - gmin
			_quad(A, B, Vector3(b.x, top, b.y), Vector3(a.x, top, a.y), nrm, wall_col,
				Vector2(ulen, -0.6), Vector2(ulen + len, -0.6), Vector2(ulen + len, wall_top), Vector2(ulen, wall_top))
			ulen += len
		# roof
		if gable:
			var i0 := long_i
			var p0 := pts[i0]
			var p1 := pts[(i0 + 1) % 4]
			var p2 := pts[(i0 + 2) % 4]
			var p3 := pts[(i0 + 3) % 4]
			var m0 := (p0 + p3) / 2.0   # ridge ends on the two short sides
			var m1 := (p1 + p2) / 2.0
			var R0 := Vector3(m0.x, top + ridge, m0.y)
			var R1 := Vector3(m1.x, top + ridge, m1.y)
			var T := [Vector3(p0.x, top, p0.y), Vector3(p1.x, top, p1.y), Vector3(p2.x, top, p2.y), Vector3(p3.x, top, p3.y)]
			var mid := Vector3((m0.x + m1.x) / 2.0, top, (m0.y + m1.y) / 2.0)
			for side in [[T[0], T[1]], [T[2], T[3]]]:
				var sa: Vector3 = side[0]
				var sb: Vector3 = side[1]
				var ra := R0 if sa.distance_to(R0) < sa.distance_to(R1) else R1
				var rb := R1 if ra == R0 else R0
				var nrm2 := (sb - sa).cross(rb - sa).normalized()
				var outw := Vector3((sa.x + sb.x) / 2.0 - mid.x, 0, (sa.z + sb.z) / 2.0 - mid.z)
				if nrm2.dot(outw) < 0.0 or nrm2.y < 0.0:
					nrm2 = -nrm2
				if nrm2.y < 0.0:
					nrm2.y = -nrm2.y
				_quad(sa, sb, rb, ra, nrm2.normalized(), roof_col, Vector2(sa.x, sa.z), Vector2(sb.x, sb.z), Vector2(rb.x, rb.z), Vector2(ra.x, ra.z))
			# gable ends (triangles, wall material)
			for g in [[T[0], T[3], R0], [T[1], T[2], R1]]:
				var ga: Vector3 = g[0]
				var gb: Vector3 = g[1]
				var gr: Vector3 = g[2]
				var gn := Vector3(gr.x - mid.x, 0, gr.z - mid.z).normalized()
				_tri(ga, gb, gr, gn, wall_col, Vector2(0, wall_h), Vector2(ga.distance_to(gb), wall_h), Vector2(ga.distance_to(gb) / 2.0, wall_h + ridge))
		else:
			var tris := Geometry2D.triangulate_polygon(pts)
			for t in range(0, tris.size(), 3):
				var a2 := pts[tris[t]]
				var b2 := pts[tris[t + 1]]
				var c2 := pts[tris[t + 2]]
				_tri(Vector3(a2.x, top, a2.y), Vector3(b2.x, top, b2.y), Vector3(c2.x, top, c2.y), Vector3.UP, roof_col, a2, b2, c2)
		# crash boxes for the flight model: an oriented box around the footprint
		var ax := (pts[1] - pts[0]).normalized() if long_i == 0 else (pts[2] - pts[1]).normalized()
		var lo := Vector2(1e9, 1e9)
		var hi := Vector2(-1e9, -1e9)
		for p in pts:
			var q := Vector2(p.dot(ax), p.dot(Vector2(-ax.y, ax.x)))
			lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
			hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
		var qc := (lo + hi) / 2.0
		var cw := ax * qc.x + Vector2(-ax.y, ax.x) * qc.y
		var col := {"cx": cw.x, "cz": cw.y, "c": ax.x, "s": ax.y, "hu": (hi.x - lo.x) / 2.0, "hv": (hi.y - lo.y) / 2.0, "top": gmin + h, "chunk": c}
		var ck := Vector2i(int(floor(cw.x / COLL_CELL)), int(floor(cw.y / COLL_CELL)))
		if not coll_grid.has(ck):
			coll_grid[ck] = []
		coll_grid[ck].append(col)
	if _v.size() == 0:
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _v
	arrays[Mesh.ARRAY_NORMAL] = _n
	arrays[Mesh.ARRAY_COLOR] = _c
	arrays[Mesh.ARRAY_TEX_UV] = _uv
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


# ---------------------------------------------------------------- trees
func _trees(c: Vector2i, node: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = c.x * 7919 + c.y * 104729
	var px0 := c.x * int(CHUNK / 8.0)
	var py0 := c.y * int(CHUNK / 8.0)
	var span := int(CHUNK / 8.0)
	var near_xf: Array = []
	var cols: Array = []
	for y in range(py0, py0 + span):
		for x in range(px0, px0 + span):
			var o := (y * LC_PX + x) * 4
			if lc_data[o] < 128 or lc_data[o + 1] > 128:
				continue
			if rng.randf() > tree_density:
				continue
			var wx := -HALF + (x + rng.randf()) * 8.0
			var wz := -HALF + (y + rng.randf()) * 8.0
			if terrain.paved(wx, wz):
				continue
			var h := 7.0 + rng.randf() * 10.0
			var w := h * (0.55 + rng.randf() * 0.25)
			var b := Basis.from_euler(Vector3((rng.randf() - 0.5) * 0.08, rng.randf() * TAU, (rng.randf() - 0.5) * 0.08)).scaled(Vector3(w, h, w))
			near_xf.append(Transform3D(b, Vector3(wx, terrain.height(wx, wz) - 0.4, wz)))
			var g := rng.randf()
			cols.append(Color(0.16, 0.27, 0.10).lerp(Color(0.30, 0.40, 0.15), g).lerp(Color(0.36, 0.34, 0.16), rng.randf() * 0.25).srgb_to_linear())
	if near_xf.is_empty():
		return
	for lod in 2:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = tree_near if lod == 0 else tree_far
		mm.instance_count = near_xf.size()
		for i in near_xf.size():
			mm.set_instance_transform(i, near_xf[i])
			mm.set_instance_color(i, cols[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = tree_mat
		if lod == 0:
			mmi.visibility_range_end = near_tree_range
			mmi.visibility_range_end_margin = 150.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DEPENDENCIES
		else:
			mmi.visibility_range_begin = near_tree_range
			mmi.visibility_range_begin_margin = 150.0
			mmi.visibility_range_end = radius_tree
			mmi.visibility_range_end_margin = 500.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mmi)


func _blob(k: MeshKit, c: Vector3, r: Vector3, seg: int, rings: int, rng: RandomNumberGenerator) -> void:
	var top := Color(1, 1, 1)
	var bot := Color(0.42, 0.47, 0.42)
	var pts: Array = []
	for j in rings + 1:
		var row: Array = []
		var th := PI * float(j) / float(rings)
		for i in seg:
			var ph := TAU * float(i) / float(seg) + j * 0.4
			var n := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
			var bump := 1.0 + (rng.randf() - 0.5) * 0.3 if j > 0 and j < rings else 1.0
			row.append([c + n * r * bump, n])
		pts.append(row)
	for j in rings:
		for i in seg:
			var i2 := (i + 1) % seg
			var q4 := [pts[j][i], pts[j][i2], pts[j + 1][i2], pts[j + 1][i]]
			var cl: Array = []
			for v in q4:
				cl.append(bot.lerp(top, clampf(v[1].y * 0.5 + 0.55, 0.0, 1.0)))
			k.add_smooth_tri(q4[0][0], q4[1][0], q4[2][0], q4[0][1], q4[1][1], q4[2][1], cl[0], cl[1], cl[2])
			k.add_smooth_tri(q4[0][0], q4[2][0], q4[3][0], q4[0][1], q4[2][1], q4[3][1], cl[0], cl[2], cl[3])


func _leafy_mesh(detailed: bool) -> ArrayMesh:
	# a broadleaf tree 1 unit tall: trunk and a lumpy crown; the far version is one simple blob
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var k := MeshKit.new()
	var col := Color(0.5, 0.4, 0.3)
	var segs := 5
	for i in (segs if detailed else 0):
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var p0 := Vector3(cos(a0), 0, sin(a0)) * 0.05
		var p1 := Vector3(cos(a1), 0, sin(a1)) * 0.05
		var n := Vector3(cos((a0 + a1) / 2.0), 0, sin((a0 + a1) / 2.0))
		k.add_quad(p0, p1, p1 * 0.6 + Vector3(0, 0.45, 0), p0 * 0.6 + Vector3(0, 0.45, 0), n, col)
	if detailed:
		_blob(k, Vector3(0, 0.6, 0), Vector3(0.5, 0.36, 0.5), 8, 5, rng)
		_blob(k, Vector3(0.2, 0.76, 0.08), Vector3(0.3, 0.24, 0.3), 6, 4, rng)
		_blob(k, Vector3(-0.17, 0.72, -0.15), Vector3(0.3, 0.25, 0.3), 6, 4, rng)
	else:
		_blob(k, Vector3(0, 0.6, 0), Vector3(0.5, 0.42, 0.5), 5, 2, rng)   # 20 triangles
	return k.build()
