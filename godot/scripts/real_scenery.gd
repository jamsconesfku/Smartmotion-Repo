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
var road_mat: ShaderMaterial
var roads := {}                      ## v1.23.0: Vector2i chunk -> Array of road runs [class, dual, points, s, length]
var radius_road := 3400.0
var total_roads := 0
var tree_mat: ShaderMaterial
var tree_near: Mesh
var tree_far: Mesh
var radius_bld := 6500.0
var radius_tree := 4200.0
var near_tree_range := 1100.0
var tree_density := 1.0
var _last_focus := Vector2(1e9, 1e9)
var _pending: Array = []
var _jobs: Array = []
var _to_free: Array = []             ## far squares waiting to be dropped (one per frame)
var chunk_cells := {}                ## Vector2i square -> the crash-box cells it filled (so freeing it is quick)                ## squares being made on worker threads
var total_buildings := 0


func setup(terrain_: Terrain, quality_: String, ortho: Texture2D) -> void:
	terrain = terrain_
	quality = quality_
	radius_bld = {"low": 3000.0, "medium": 5000.0, "high": 7000.0}.get(quality, 5000.0)
	radius_tree = {"low": 1800.0, "medium": 3000.0, "high": 4000.0}.get(quality, 3200.0)
	near_tree_range = {"low": 600.0, "medium": 900.0, "high": 1300.0}.get(quality, 900.0)
	tree_density = {"low": 0.35, "medium": 0.6, "high": 1.0}.get(quality, 0.6)
	_load_buildings()
	_load_trees()
	_load_roads()
	radius_road = {"low": 1600.0, "medium": 2600.0, "high": 3400.0}.get(quality, 2600.0)
	road_mat = ShaderMaterial.new()
	road_mat.shader = load("res://shaders/road.gdshader")
	road_mat.set_shader_parameter("asphalt_col", load("res://assets/textures/asphalt_col.jpg"))
	road_mat.set_shader_parameter("asphalt_nrm", load("res://assets/textures/asphalt_nrm.jpg"))
	road_mat.set_shader_parameter("fade_start", radius_road * 0.75)
	road_mat.set_shader_parameter("fade_end", radius_road)
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
	tree_mat = ShaderMaterial.new()
	tree_mat.shader = load("res://shaders/tree.gdshader")   # leaf clumps, light through the leaves, wind
	tree_near = _leafy_mesh(true)
	tree_far = _leafy_mesh(false)


var ultra := false
var extra_trees := 0.0                ## Ultra: chance of a second tree in each wooded 8 m square


## The Ultra and view-distance settings: how far buildings and trees are drawn, and how many trees.
func set_extent(ultra_: bool, view: String) -> void:
	ultra = ultra_
	if ultra:
		radius_bld = 9000.0
		radius_tree = 5500.0
		near_tree_range = 1800.0
		extra_trees = 0.45
	var k: float = {"near": 0.7, "normal": 1.0, "far": 1.35}.get(view, 1.0)
	radius_bld *= k
	radius_tree *= k
	near_tree_range *= minf(k, 1.15)


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
## v1.23.0: the real roads (assets/world/roads.bin, scripts/build_roads.py), cut into runs per 1 km square with
## their distance along the road kept, so the lines carry on across the squares. Nothing on the racing circuit.
func _load_roads() -> void:
	var f := FileAccess.open("res://assets/world/roads.bin", FileAccess.READ)
	if f == null:
		return
	var buf := f.get_buffer(f.get_length())
	var nr := buf.decode_u32(0)
	var o := 4
	var circuit := PackedVector2Array()
	for p in RaceTrack.POINTS:
		circuit.append((p as Vector2) + RaceTrack.OFFSET)
	for r in nr:
		var cls := buf.decode_u8(o)
		var dual := buf.decode_u8(o + 1) & 1 == 1
		var np := buf.decode_u16(o + 2)
		o += 4
		var pts := PackedVector2Array()
		pts.resize(np)
		for k in np:
			pts[k] = Vector2(buf.decode_s32(o) / 4.0, buf.decode_s32(o + 4) / 4.0)
			o += 8
		var s := PackedFloat32Array()
		s.resize(np)
		for k in range(1, np):
			s[k] = s[k - 1] + pts[k].distance_to(pts[k - 1])
		var total := s[np - 1]
		# runs: consecutive pieces in the same square (each piece goes to the square of its middle)
		var run_c := Vector2i(1 << 30, 0)
		var rp := PackedVector2Array()
		var rs := PackedFloat32Array()
		for k in range(np - 1):
			var mid := (pts[k] + pts[k + 1]) / 2.0
			var skip := _near_circuit(mid, circuit)
			var ck := _chunk_of(mid)
			if skip or ck != run_c:
				if rp.size() >= 2:
					_add_road_run(run_c, cls, dual, rp, rs, total)
				rp = PackedVector2Array()
				rs = PackedFloat32Array()
				run_c = ck
				if skip:
					run_c = Vector2i(1 << 30, 0)
					continue
				rp.append(pts[k])
				rs.append(s[k])
			rp.append(pts[k + 1])
			rs.append(s[k + 1])
		if rp.size() >= 2:
			_add_road_run(run_c, cls, dual, rp, rs, total)
	total_roads = nr


func _add_road_run(c: Vector2i, cls: int, dual: bool, pts: PackedVector2Array, s: PackedFloat32Array, total: float) -> void:
	if not roads.has(c):
		roads[c] = []
	roads[c].append([cls, dual, pts, s, total])


## Within 60 m of the racing circuit's centre line (its own track and kerbs are there).
static func _near_circuit(p: Vector2, circuit: PackedVector2Array) -> bool:
	if p.distance_to(circuit[0]) > 1500.0:
		return false
	for i in circuit.size():
		var a := circuit[i]
		var b := circuit[(i + 1) % circuit.size()]
		if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) < 60.0:
			return true
	return false


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


## v1.15.0: the real trees in the 8 km detail square round the airfield, found in the Environment Agency's LIDAR
## vegetation heights (assets/world/trees.bin, scripts/build_uk_detail.py): every tree and hedgerow tree where
## it really stands, at its real height. The detail square is exactly the 1 km squares 12-19 on each side.
var real_trees := {}                  ## Vector2i square -> PackedFloat32Array [x, z, height, crown radius, ...]
var total_real_trees := 0

func _load_trees() -> void:
	var f := FileAccess.open("res://assets/world/trees.bin", FileAccess.READ)
	if f == null:
		return
	var buf := f.get_buffer(f.get_length())
	var n := buf.decode_u32(0)
	var o := 4
	for i in n:
		var x := buf.decode_s16(o) / 4.0
		var z := buf.decode_s16(o + 2) / 4.0
		var h := buf.decode_u8(o + 4) / 5.0
		var r := buf.decode_u8(o + 5) / 20.0
		o += 6
		var key := _chunk_of(Vector2(x, z))
		if not real_trees.has(key):
			real_trees[key] = PackedFloat32Array()
		var a: PackedFloat32Array = real_trees[key]
		a.append_array([x, z, h, r])
		real_trees[key] = a
	total_real_trees = n


## True for the 1 km squares that use the real LIDAR trees.
func in_detail(c: Vector2i) -> bool:
	var lo := int((HALF - Terrain.D_HALF) / CHUNK)
	var hi := int((HALF + Terrain.D_HALF) / CHUNK)
	return total_real_trees > 0 and c.x >= lo and c.x < hi and c.y >= lo and c.y < hi


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
			if not want.has(c) and _chunk_centre(c).distance_to(p) > r + CHUNK * 2.0 and not _to_free.has(c):
				_to_free.append(c)
		_pending = []
		for c in want.keys():
			if not chunks.has(c):
				_pending.append(c)
		_pending.sort_custom(func(a, b): return _chunk_centre(a).distance_squared_to(p) < _chunk_centre(b).distance_squared_to(p))
	if budget > 1:
		# loading screen: build everything now
		while _pending.size() > 0:
			_build_chunk(_pending.pop_front())
		return
	# drop far squares one per frame (spreads the work out)
	while _to_free.size() > 0:
		var fc: Vector2i = _to_free.pop_front()
		if chunks.has(fc) and _chunk_centre(fc).distance_to(_last_focus) > maxf(radius_bld, radius_tree) + CHUNK * 2.0:
			_free_chunk(fc)
			break
	_poll_jobs()
	while _jobs.size() < 3 and _pending.size() > 0:
		_start_job(_pending.pop_front())


func _free_chunk(c: Vector2i) -> void:
	var node: Node3D = chunks[c]
	node.queue_free()
	chunks.erase(c)
	for k in chunk_cells.get(c, {}).keys():
		var keep: Array = []
		for col in coll_grid.get(k, []):
			if col["chunk"] != c:
				keep.append(col)
		if keep.is_empty():
			coll_grid.erase(k)
		else:
			coll_grid[k] = keep
	chunk_cells.erase(c)


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


## Thread-safe: everything for one square except the scene nodes.
func _chunk_data(c: Vector2i, want_trees: bool) -> Dictionary:
	var d := {"bld": null, "trees": PackedFloat32Array(), "roads": null}
	if bld.has(c):
		d["bld"] = _building_data(bld[c], c)
	if roads.has(c):
		var rk := RoadKit.new()
		for r in roads[c]:
			rk.add_run(r[0], r[1], r[2], r[3], r[4], terrain)
		if rk.v.size() > 0:
			var rm := ArrayMesh.new()
			rm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, rk.arrays())
			d["roads"] = rm
	if want_trees and lc_data.size() > 0:
		d["trees"] = _tree_data(c)
	return d


func _chunk_finish(c: Vector2i, node: Node3D, d: Dictionary) -> void:
	_chunk_buildings(c, node, d)
	_add_trees(d["trees"], node)


## Adds a square's buildings and crash boxes (its trees go in separately, see _poll_jobs).
func _chunk_buildings(c: Vector2i, node: Node3D, d: Dictionary) -> void:
	if d.get("roads") != null:
		var ri := MeshInstance3D.new()
		ri.mesh = d["roads"]
		ri.material_override = road_mat
		ri.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ri.visibility_range_end = radius_road + 800.0
		node.add_child(ri)
	var bd = d["bld"]
	if bd != null:
		if bd["arrays"] != null:
			var m: ArrayMesh = bd["mesh"] if bd.has("mesh") else null
			if m == null:
				m = ArrayMesh.new()
				m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bd["arrays"])
			var mi := MeshInstance3D.new()
			mi.mesh = m
			mi.material_override = bld_mat
			mi.visibility_range_end = radius_bld
			mi.visibility_range_end_margin = 400.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			node.add_child(mi)
		var cells := {}
		chunk_cells[c] = cells
		for e in bd["colls"]:
			var ck: Vector2i = e[0]
			cells[ck] = true
			if not coll_grid.has(ck):
				coll_grid[ck] = []
			coll_grid[ck].append(e[1])


## Builds a square straight away on the main thread (loading screen).
func _build_chunk(c: Vector2i) -> void:
	var node := Node3D.new()
	add_child(node)
	chunks[c] = node
	_chunk_finish(c, node, _chunk_data(c, _chunk_centre(c).distance_to(_last_focus) < radius_tree + CHUNK))


## Starts a square on a worker thread; _poll_jobs() adds it to the scene when it's ready.
func _start_job(c: Vector2i) -> void:
	var node := Node3D.new()
	add_child(node)
	chunks[c] = node
	var job := {"c": c, "node": node, "result": {}}
	var trees := _chunk_centre(c).distance_to(_last_focus) < radius_tree + CHUNK
	job["id"] = WorkerThreadPool.add_task(func(): job["result"] = _chunk_data(c, trees))   # a Dictionary, so the lambda can fill it
	_jobs.append(job)


func _exit_tree() -> void:
	for job in _jobs:
		if job.get("stage", 0) == 0:
			WorkerThreadPool.wait_for_task_completion(job["id"])
	_jobs = []


func _poll_jobs() -> void:
	var still: Array = []
	var finished := 0
	# one piece per frame (a square's buildings one frame, its trees the next), so no single frame is slow:
	# in VR a frame that misses the headset's deadline is felt as a judder when you turn your head
	for job in _jobs:
		if finished < 1 and (job.get("stage", 0) == 1 or WorkerThreadPool.is_task_completed(job["id"])):
			var c: Vector2i = job["c"]
			var node: Node3D = job["node"]
			finished += 1
			# the square may have been dropped while it was being made
			var alive: bool = chunks.get(c) == node and is_instance_valid(node)
			if job.get("stage", 0) == 0:
				WorkerThreadPool.wait_for_task_completion(job["id"])
				if alive:
					_chunk_buildings(c, node, job["result"])
					job["stage"] = 1
					still.append(job)
			elif alive:
				_add_trees(job["result"]["trees"], node)
		else:
			still.append(job)
	_jobs = still


class Buf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()

	func tri(a: Vector3, b: Vector3, cc: Vector3, nn: Vector3, col: Color, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
		# Godot front faces are clockwise: flip the triangle if it faces the other way
		if (b - a).cross(cc - a).dot(nn) > 0.0:
			v.append_array([a, cc, b])
			uv.append_array([ua, uc, ub])
		else:
			v.append_array([a, b, cc])
			uv.append_array([ua, ub, uc])
		n.append_array([nn, nn, nn])
		c.append_array([col, col, col])

	func quad(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, nn: Vector3, col: Color, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
		tri(a, b, cc, nn, col, ua, ub, uc)
		tri(a, cc, d, nn, col, ua, uc, ud)


## Runs on a worker thread: builds the arrays for one square's buildings and their crash boxes.
func _building_data(list: Array, c: Vector2i) -> Dictionary:
	# v1.23.0: the buildings themselves come from BuildingKit (houses, terraces, wings, sheds, blocks)
	var kit := BuildingKit.new()
	var colls: Array = []
	var rng := RandomNumberGenerator.new()
	for rec in list:
		var pts: PackedVector2Array = rec[0]
		var h: float = rec[1]
		var kind: int = rec[2]
		rng.seed = hash(pts[0])
		var gmin := 1e9
		for p in pts:
			gmin = minf(gmin, terrain.height(p.x, p.y))
		kit.add(pts, h, kind, gmin, rng)
		# crash boxes for the flight model: an oriented box around the footprint
		var bb := BuildingKit.obb(pts)
		if bb.is_empty():
			continue
		var ax: Vector2 = bb[0]
		var lo: Vector2 = bb[1]
		var hi: Vector2 = bb[2]
		var qc := (lo + hi) / 2.0
		var cw := ax * qc.x + Vector2(-ax.y, ax.x) * qc.y
		var col := {"cx": cw.x, "cz": cw.y, "c": ax.x, "s": ax.y, "hu": (hi.x - lo.x) / 2.0, "hv": (hi.y - lo.y) / 2.0, "top": gmin + h, "chunk": c}
		var ck := Vector2i(int(floor(cw.x / COLL_CELL)), int(floor(cw.y / COLL_CELL)))
		colls.append([ck, col])
	if kit.v.size() == 0:
		return {"arrays": null, "colls": colls}
	# v1.23.0: the mesh is made here on the worker thread (the buildings have about four times the triangles they
	# had, and making the mesh on the main thread held up a frame by 12-17 ms when a square came in)
	var arr := kit.arrays()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return {"arrays": arr, "mesh": mesh, "colls": colls}


# ---------------------------------------------------------------- trees
## Runs on a worker thread: places the trees for one square and packs them into a MultiMesh buffer
## (12 floats of transform + 4 of colour per tree), so the main thread copies it in one go.
func _tree_data(c: Vector2i) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = c.x * 7919 + c.y * 104729
	if in_detail(c):
		var a: PackedFloat32Array = real_trees.get(c, PackedFloat32Array())
		for i in range(0, a.size(), 4):
			if tree_density < 1.0 and rng.randf() > tree_density * 1.2:
				continue
			_real_tree(buf, rng, a[i], a[i + 1], a[i + 2], a[i + 3])
		return buf
	var px0 := c.x * int(CHUNK / 8.0)
	var py0 := c.y * int(CHUNK / 8.0)
	var span := int(CHUNK / 8.0)
	for y in range(py0, py0 + span):
		for x in range(px0, px0 + span):
			var o := (y * LC_PX + x) * 4
			if lc_data[o] < 128 or lc_data[o + 1] > 128:
				continue
			if rng.randf() > tree_density:
				continue
			for extra in (2 if rng.randf() < extra_trees else 1):
				_one_tree(buf, rng, x, y)
	return buf


## One tree somewhere in the wooded 8 m land-cover square (x, y).
func _one_tree(buf: PackedFloat32Array, rng: RandomNumberGenerator, x: int, y: int) -> void:
	var wx := -HALF + (x + rng.randf()) * 8.0
	var wz := -HALF + (y + rng.randf()) * 8.0
	if terrain.paved(wx, wz):
		return
	var h := 7.0 + rng.randf() * 10.0
	var w := h * (0.55 + rng.randf() * 0.25)
	var bs := Basis.from_euler(Vector3((rng.randf() - 0.5) * 0.08, rng.randf() * TAU, (rng.randf() - 0.5) * 0.08)).scaled(Vector3(w, h, w))
	var org := Vector3(wx, terrain.height(wx, wz) - 0.4, wz)
	var g := rng.randf()
	var col := Color(0.16, 0.27, 0.10).lerp(Color(0.30, 0.40, 0.15), g).lerp(Color(0.36, 0.34, 0.16), rng.randf() * 0.25).srgb_to_linear()
	buf.append_array([bs.x.x, bs.y.x, bs.z.x, org.x, bs.x.y, bs.y.y, bs.z.y, org.y, bs.x.z, bs.y.z, bs.z.z, org.z, col.r, col.g, col.b, col.a])


## One real tree: its height from the LIDAR, its crown as wide as the LIDAR saw, a random lean and colour.
func _real_tree(buf: PackedFloat32Array, rng: RandomNumberGenerator, wx: float, wz: float, h: float, r: float) -> void:
	var w := clampf(r * 2.0, h * 0.45, h * 1.1)
	var bs := Basis.from_euler(Vector3((rng.randf() - 0.5) * 0.08, rng.randf() * TAU, (rng.randf() - 0.5) * 0.08)).scaled(Vector3(w, h, w))
	var org := Vector3(wx, terrain.height(wx, wz) - 0.3, wz)
	var g := rng.randf()
	var col := Color(0.16, 0.27, 0.10).lerp(Color(0.30, 0.40, 0.15), g).lerp(Color(0.36, 0.34, 0.16), rng.randf() * 0.25).srgb_to_linear()
	buf.append_array([bs.x.x, bs.y.x, bs.z.x, org.x, bs.x.y, bs.y.y, bs.z.y, org.y, bs.x.z, bs.y.z, bs.z.z, org.z, col.r, col.g, col.b, col.a])


func _add_trees(buf: PackedFloat32Array, node: Node3D) -> void:
	var count := buf.size() / 16
	if count == 0:
		return
	for lod in 2:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = tree_near if lod == 0 else tree_far
		mm.instance_count = count
		mm.buffer = buf
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
