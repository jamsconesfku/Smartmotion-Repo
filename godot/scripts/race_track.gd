class_name RaceTrack
extends Node3D
## SmartMotion Racing: the circuit. A made-up 4 km circuit in gentle English countryside (in the style of the
## Duxford world): long main straight, a tight first corner, fast esses, a hairpin, a back straight, a chicane
## and a sweeping last corner. Built from code: the track, kerbs, gravel, barriers, grandstands with a crowd,
## pit building, start gantry with lights, SmartMotion boards and trees.
## Queries for the car physics: nearest(), surface(), height().

const HALF_W := 7.0            # the track is 14 m wide
const KERB_W := 1.35
const DS := 2.0                # sample spacing along the centre line (m)
const CENTRE := Vector2(60.0, 380.0)
const POINTS := [Vector2(-400, 0), Vector2(0, 0), Vector2(450, 0), Vector2(560, 40), Vector2(580, 140), Vector2(520, 260),
	Vector2(560, 400), Vector2(680, 500), Vector2(720, 640), Vector2(650, 760), Vector2(520, 720), Vector2(380, 600),
	Vector2(100, 560), Vector2(-150, 600), Vector2(-380, 640), Vector2(-560, 560), Vector2(-620, 420), Vector2(-555, 305),
	Vector2(-640, 200), Vector2(-650, 80), Vector2(-560, 10)]
const START_XZ := Vector2(-60.0, 0.0)
const GRID_SLOTS := 8

var n := 0
var length := 0.0
var c2: PackedVector2Array          # centre line (x, z)
var tan2: PackedVector2Array        # direction of travel
var nrm2: PackedVector2Array        # to the right of the direction of travel
var curv: PackedFloat32Array        # curvature (1/m), + = turning right
var corner: PackedFloat32Array      # 0..1, how much of a corner (kerbs, gravel, tyre walls)
var wall_l: PackedFloat32Array      # barrier distance from the centre line, left and right
var wall_r: PackedFloat32Array
var vmax: PackedFloat32Array        # the AI's speed plan (m/s)
var grid := {}                      # coarse lookup: cell -> sample indices
var mat_ground: ShaderMaterial
var lights: Array = []              # the five pairs of start lights
var light_on_m: StandardMaterial3D
var light_off_m: StandardMaterial3D
var w: World
var wall_mats: Array = []


static func H(x: float, z: float) -> float:
	## Ground height: gentle rises round the circuit, hills on the horizon.
	var h := 3.2 * sin(x * 0.0058 + 0.7) * cos(z * 0.0047 - 0.3) + 2.2 * sin((x + z) * 0.0036) + 1.2 * cos((x - z) * 0.0081)
	var r := Vector2(x, z).distance_to(CENTRE)
	var far := smoothstep(1200.0, 2900.0, r)
	if far > 0.0:
		var a := atan2(z - CENTRE.y, x - CENTRE.x)
		h += far * (38.0 + 30.0 * sin(a * 3.0 + 1.0) + 18.0 * sin(a * 7.0 + 0.4) + 10.0 * sin(x * 0.0021) * cos(z * 0.0017)) + far * far * 60.0
	return h


func height(x: float, z: float) -> float:
	return H(x, z)


## The centre line, lookups and the AI's speed plan (no meshes): enough for the physics checks.
func build_data() -> void:
	_centre_line()
	_lookup()
	_speed_plan()


func build(world: World, quality: String) -> void:
	w = world
	build_data()
	mat_ground = ShaderMaterial.new()
	mat_ground.shader = load("res://shaders/race_ground.gdshader")
	mat_ground.set_shader_parameter("centre", Vector3(CENTRE.x, 0, CENTRE.y))
	_ground(quality)
	_road()
	_verges()
	_walls()
	await _buildings()
	_start_gantry()
	_trees(quality)
	_boards()


# ---------------------------------------------------------------- centre line
func _cr(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	# centripetal Catmull-Rom (no loops or cusps)
	var t0 := 0.0
	var t1 := t0 + sqrt(p0.distance_to(p1))
	var t2 := t1 + sqrt(p1.distance_to(p2))
	var t3 := t2 + sqrt(p2.distance_to(p3))
	var tt := t1 + (t2 - t1) * t
	var a1 := p0.lerp(p1, (tt - t0) / (t1 - t0))
	var a2 := p1.lerp(p2, (tt - t1) / (t2 - t1))
	var a3 := p2.lerp(p3, (tt - t2) / (t3 - t2))
	var b1 := a1.lerp(a2, (tt - t0) / (t2 - t0))
	var b2 := a2.lerp(a3, (tt - t1) / (t3 - t1))
	return b1.lerp(b2, (tt - t1) / (t2 - t1))


func _centre_line() -> void:
	var dense := PackedVector2Array()
	var m := POINTS.size()
	for i in m:
		for k in 120:
			dense.append(_cr(POINTS[(i - 1 + m) % m], POINTS[i], POINTS[(i + 1) % m], POINTS[(i + 2) % m], k / 120.0))
	var cum := PackedFloat32Array([0.0])
	var L := 0.0
	for i in range(1, dense.size() + 1):
		L += dense[i - 1].distance_to(dense[i % dense.size()])
		cum.append(L)
	n = int(L / DS)
	length = L
	var raw := PackedVector2Array()
	var j := 0
	for i in n:
		var s := i * L / n
		while cum[j + 1] < s:
			j += 1
		var f := (s - cum[j]) / (cum[j + 1] - cum[j])
		raw.append(dense[j].lerp(dense[(j + 1) % dense.size()], f))
	# start the lap at the start line
	var best := 0
	for i in n:
		if raw[i].distance_to(START_XZ) < raw[best].distance_to(START_XZ):
			best = i
	c2 = PackedVector2Array()
	for i in n:
		c2.append(raw[(i + best) % n])
	tan2 = PackedVector2Array()
	nrm2 = PackedVector2Array()
	curv = PackedFloat32Array()
	for i in n:
		var t := (c2[(i + 1) % n] - c2[(i - 1 + n) % n]).normalized()
		tan2.append(t)
		nrm2.append(Vector2(-t.y, t.x))
	for i in n:
		var h1 := tan2[(i - 3 + n) % n].angle()
		var h2 := tan2[(i + 3) % n].angle()
		curv.append(wrapf(h2 - h1, -PI, PI) / (6.0 * DS))
	# smoothed corner amount and barrier distances
	corner = PackedFloat32Array()
	wall_l = PackedFloat32Array()
	wall_r = PackedFloat32Array()
	corner.resize(n)
	wall_l.resize(n)
	wall_r.resize(n)
	for i in n:
		var mx := 0.0
		for k in range(-12, 13):
			mx = maxf(mx, absf(curv[(i + k + n) % n]))
		corner[i] = smoothstep(1.0 / 400.0, 1.0 / 90.0, mx)
	for i in n:
		var ks := 0.0
		var cs := 0.0
		for k in range(-15, 16):
			ks += curv[(i + k + n) % n]
			cs += corner[(i + k + n) % n]
		ks /= 31.0
		cs /= 31.0
		var outer := 20.0 + 16.0 * cs
		var inner := clampf(0.8 / maxf(absf(ks), 0.0001), 10.0, 20.0)
		# turning right: the left side is the outside
		wall_l[i] = outer if ks > 0.0 else inner
		wall_r[i] = inner if ks > 0.0 else outer


func _lookup() -> void:
	grid = {}
	for i in n:
		var c := Vector2i(floori(c2[i].x / 50.0), floori(c2[i].y / 50.0))
		if not grid.has(c):
			grid[c] = PackedInt32Array()
		grid[c].append(i)


## Distance from a point to the track centre line: [sample index, signed metres (+ right), distance along the lap].
func nearest(p: Vector2, hint := -1) -> Array:
	var bi := 0
	var bd := INF
	if hint >= 0:
		for k in range(-60, 61):
			var i := (hint + k + n) % n
			var d := p.distance_squared_to(c2[i])
			if d < bd:
				bd = d
				bi = i
	if hint < 0 or bd > 60.0 * 60.0:
		var c := Vector2i(floori(p.x / 50.0), floori(p.y / 50.0))
		bd = INF
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				for i in grid.get(c + Vector2i(dx, dz), PackedInt32Array()):
					var d := p.distance_squared_to(c2[i])
					if d < bd:
						bd = d
						bi = i
		if bd == INF:
			for i in range(0, n, 4):
				var d := p.distance_squared_to(c2[i])
				if d < bd:
					bd = d
					bi = i
	var rel := p - c2[bi]
	var along := rel.dot(tan2[bi])
	return [bi, rel.dot(nrm2[bi]), fposmod(bi * DS * length / (n * DS) + along, length)]


## Grip and drag for a spot beside the track: [grip multiplier, extra drag (1/s), name]
func surface(i: int, lat: float) -> Array:
	var a := absf(lat)
	if a <= HALF_W:
		return [1.0, 0.0, "track"]
	var x := a - HALF_W
	var outside := (lat < 0.0) == (curv[i] > 0.0)
	if corner[i] > 0.45 and x < KERB_W:
		return [0.92, 0.05, "kerb"]
	if x < KERB_W + 0.6:
		return [0.95, 0.02, "track"]
	var gw := (6.0 + 9.0 * corner[i]) * smoothstep(0.3, 0.6, corner[i]) if outside else 0.0
	if x < KERB_W + 0.6 + gw:
		return [0.45, 1.1, "gravel"]
	return [0.6, 0.35, "grass"]


func pos3(i: int, lat := 0.0) -> Vector3:
	var p := c2[i % n] + nrm2[i % n] * lat
	return Vector3(p.x, H(p.x, p.y), p.y)


## Start grid: [position, heading (radians, 0 = -Z)] for slot k (0 = pole).
func grid_slot(k: int) -> Array:
	var back := 12.0 + k * 8.0
	var i := (n - int(back / DS)) % n
	var lat := -3.0 if k % 2 == 0 else 3.0
	var t := tan2[i]
	return [pos3(i, lat), atan2(t.x, -t.y), i]


func _speed_plan() -> void:
	# fastest speed through each part of the lap for a car with downforce, then braking and acceleration limits
	vmax = PackedFloat32Array()
	vmax.resize(n)
	var mu := 1.75
	var m := 798.0
	var k := 0.5 * 1.225 * 3.2 * 0.75   # downforce per (m/s)^2 the AI counts on
	for i in n:
		var kap := 0.0
		for j in range(-4, 5):
			kap = maxf(kap, absf(curv[(i + j + n) % n]))
		var den := m * kap - mu * k
		vmax[i] = 92.0 if den <= 0.0 else minf(92.0, sqrt(mu * m * 9.81 / den))
	for pass_i in 2:
		for i in range(n - 1, -1, -1):
			var nx := vmax[(i + 1) % n]
			vmax[i] = minf(vmax[i], sqrt(nx * nx + 2.0 * 24.0 * DS))   # braking ~2.5 g
		for i in n:
			var pv := vmax[(i - 1 + n) % n]
			vmax[i] = minf(vmax[i], sqrt(pv * pv + 2.0 * 11.0 * DS))   # acceleration ~1.1 g


# ---------------------------------------------------------------- meshes
## Indexed strip mesh: rows of vertices along the track (each row the same number of points).
func _strip(rows: Array, uvs: Array, cols: Array, norms: Array, closed: bool) -> ArrayMesh:
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var cl := PackedColorArray()
	var nm := PackedVector3Array()
	var idx := PackedInt32Array()
	var w_ := (rows[0] as PackedVector3Array).size()
	if closed:
		# repeat the first row at the end, with the distance along the lap = the lap length (no seam in the paint)
		rows = rows.duplicate()
		uvs = uvs.duplicate()
		cols = cols.duplicate()
		norms = norms.duplicate()
		rows.append(rows[0])
		var u0 := (uvs[0] as PackedVector2Array).duplicate()
		for k in u0.size():
			u0[k] = Vector2(u0[k].x, length)
		uvs.append(u0)
		cols.append(cols[0])
		norms.append(norms[0])
		closed = false
	for r in rows.size():
		v.append_array(rows[r])
		uv.append_array(uvs[r])
		cl.append_array(cols[r])
		nm.append_array(norms[r])
	var nr := rows.size()
	var segs := nr if closed else nr - 1
	for r in segs:
		var r2 := (r + 1) % nr
		for c in w_ - 1:
			var a := r * w_ + c
			var b := r * w_ + c + 1
			var cc := r2 * w_ + c + 1
			var d := r2 * w_ + c
			idx.append_array([a, b, cc, a, cc, d])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_COLOR] = cl
	arr[Mesh.ARRAY_NORMAL] = nm
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func _hn(x: float, z: float) -> Vector3:
	var e := 1.5
	return Vector3(H(x - e, z) - H(x + e, z), 2.0 * e, H(x, z - e) - H(x, z + e)).normalized()


func _mi(mesh: Mesh, kind: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := mat_ground.duplicate() as ShaderMaterial
	m.set_shader_parameter("kind", kind)
	m.set_shader_parameter("half_width", HALF_W)
	m.set_shader_parameter("track_len", length)
	m.set_shader_parameter("grid_slots", GRID_SLOTS)
	mi.material_override = m
	add_child(mi)
	return mi


func _ground(quality: String) -> void:
	# fine grid over the circuit, coarse ring out to the horizon hills
	for part in 2:
		var cell := 14.0 if part == 0 else 120.0
		var cnt := 170 if part == 0 else 160
		var half := cell * cnt / 2.0
		var hole := 2.0 * 14.0 * 170 / 2.0 - 2.0 * 120.0
		var rows: Array = []
		var uvs: Array = []
		var cols: Array = []
		var nms: Array = []
		for zi in cnt + 1:
			var r := PackedVector3Array()
			var u := PackedVector2Array()
			var c := PackedColorArray()
			var nm := PackedVector3Array()
			for xi in cnt + 1:
				var x := CENTRE.x - half + xi * cell
				var z := CENTRE.y - half + zi * cell
				var y := H(x, z) - (0.03 if part == 0 else 0.4)
				r.append(Vector3(x, y, z))
				u.append(Vector2.ZERO)
				c.append(Color.BLACK)
				nm.append(_hn(x, z))
			rows.append(r)
			uvs.append(u)
			cols.append(c)
			nms.append(nm)
		var mesh := _strip(rows, uvs, cols, nms, false)
		if part == 1:
			# cut out the middle (the fine grid covers it): drop triangles inside the hole
			var arr := mesh.surface_get_arrays(0)
			var vtx: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var keep := PackedInt32Array()
			for t in range(0, idx.size(), 3):
				var cx := (vtx[idx[t]].x + vtx[idx[t + 1]].x + vtx[idx[t + 2]].x) / 3.0 - CENTRE.x
				var cz := (vtx[idx[t]].z + vtx[idx[t + 1]].z + vtx[idx[t + 2]].z) / 3.0 - CENTRE.y
				if absf(cx) > hole / 2.0 or absf(cz) > hole / 2.0:
					keep.append_array([idx[t], idx[t + 1], idx[t + 2]])
			arr[Mesh.ARRAY_INDEX] = keep
			mesh = ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mi := _mi(mesh, 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _road() -> void:
	var lats := [-HALF_W - 0.2, -HALF_W / 2.0, 0.0, HALF_W / 2.0, HALF_W + 0.2]
	var rows: Array = []
	var uvs: Array = []
	var cols: Array = []
	var nms: Array = []
	for i in n:
		var r := PackedVector3Array()
		var u := PackedVector2Array()
		var c := PackedColorArray()
		var nm := PackedVector3Array()
		for lat in lats:
			var p := c2[i] + nrm2[i] * float(lat)
			r.append(Vector3(p.x, H(p.x, p.y) + 0.06, p.y))
			u.append(Vector2(lat, i * length / n))
			c.append(Color(corner[i], 0, 0))
			nm.append(_hn(p.x, p.y))
		rows.append(r)
		uvs.append(u)
		cols.append(c)
		nms.append(nm)
	var mi := _mi(_strip(rows, uvs, cols, nms, true), 2)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _verges() -> void:
	for side: float in [-1.0, 1.0]:
		var rows: Array = []
		var uvs: Array = []
		var cols: Array = []
		var nms: Array = []
		for i in n:
			var wall: float = wall_l[i] if side < 0.0 else wall_r[i]
			var outside := 1.0 if (side < 0.0) == (curv[i] > 0.0) else 0.0
			var offs := [HALF_W + 0.1, HALF_W + KERB_W * 0.5, HALF_W + KERB_W, HALF_W + KERB_W + 0.6, HALF_W + 4.0, HALF_W + 9.0, lerpf(HALF_W + 9.0, wall, 0.5), wall + 0.5]
			var r := PackedVector3Array()
			var u := PackedVector2Array()
			var c := PackedColorArray()
			var nm := PackedVector3Array()
			for o in offs:
				var oo := minf(float(o), wall + 0.5)
				var p := c2[i] + nrm2[i] * oo * side
				var lift := 0.05
				if corner[i] > 0.45 and oo <= HALF_W + KERB_W:
					lift = 0.06 + 0.07 * sin(clampf((oo - HALF_W) / KERB_W, 0.0, 1.0) * PI * 0.5) * smoothstep(0.45, 0.6, corner[i])
				r.append(Vector3(p.x, H(p.x, p.y) + lift, p.y))
				u.append(Vector2(oo, i * length / n))
				c.append(Color(corner[i], outside, 0))
				nm.append(_hn(p.x, p.y))
			rows.append(r)
			uvs.append(u)
			cols.append(c)
			nms.append(nm)
		var mi := _mi(_strip(rows, uvs, cols, nms, true), 1)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _walls() -> void:
	var fence_m := StandardMaterial3D.new()
	fence_m.albedo_color = Color(0.75, 0.78, 0.8, 0.35)
	fence_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fence_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	fence_m.roughness = 0.5
	fence_m.metallic = 0.6
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.05
	post_mesh.bottom_radius = 0.05
	post_mesh.height = 3.2
	post_mesh.radial_segments = 6
	post_mesh.rings = 1
	var posts := []
	for side: float in [-1.0, 1.0]:
		var rows: Array = []
		var uvs: Array = []
		var cols: Array = []
		var nms: Array = []
		var frows: Array = []
		var fuv: Array = []
		var fcol: Array = []
		var fnm: Array = []
		for i in n:
			var wall: float = wall_l[i] if side < 0.0 else wall_r[i]
			var nn := Vector3(-nrm2[i].x * side, 0, -nrm2[i].y * side)   # faces the track
			var p := c2[i] + nrm2[i] * wall * side
			var p2 := c2[i] + nrm2[i] * (wall + 0.6) * side
			var y := H(p.x, p.y)
			var y2 := H(p2.x, p2.y)
			var r := PackedVector3Array([Vector3(p.x, y - 0.2, p.y), Vector3(p.x, y + 1.1, p.y), Vector3(p2.x, y2 + 1.1, p2.y), Vector3(p2.x, y2 - 0.2, p2.y)])
			var s := i * length / n
			rows.append(r)
			uvs.append(PackedVector2Array([Vector2(0, s), Vector2(1.1, s), Vector2(1.1, s), Vector2(0, s)]))
			var cc := Color(corner[i], 0, 0)
			cols.append(PackedColorArray([cc, cc, cc, cc]))
			nms.append(PackedVector3Array([nn, nn, Vector3.UP, -nn]))
			# debris fence on top of the barrier
			var pf := c2[i] + nrm2[i] * (wall + 0.3) * side
			var yf := H(pf.x, pf.y)
			frows.append(PackedVector3Array([Vector3(pf.x, yf + 1.1, pf.y), Vector3(pf.x, yf + 4.0, pf.y)]))
			fuv.append(PackedVector2Array([Vector2(0, s), Vector2(1, s)]))
			fcol.append(PackedColorArray([Color.WHITE, Color.WHITE]))
			fnm.append(PackedVector3Array([nn, nn]))
			if i % 4 == 0:
				posts.append(Transform3D(Basis(), Vector3(pf.x, yf + 2.5, pf.y)))
		var mi := _mi(_strip(rows, uvs, cols, nms, true), 3)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		wall_mats.append(mi.material_override)
		var fm := MeshInstance3D.new()
		fm.mesh = _strip(frows, fuv, fcol, fnm, true)
		fm.material_override = fence_m
		fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(fm)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = post_mesh
	mm.instance_count = posts.size()
	for k in posts.size():
		mm.set_instance_transform(k, posts[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = GameMode.mat(Color(0.55, 0.57, 0.6), 0.4, 0.8)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


# ---------------------------------------------------------------- buildings, crowd, gantry
func _frame_at(i: int, lat: float) -> Transform3D:
	## A frame on the track side: X along the track, Z away from the track (to the right if lat > 0).
	var t := Vector3(tan2[i].x, 0, tan2[i].y)
	var r := Vector3(nrm2[i].x, 0, nrm2[i].y) * signf(lat)
	return Transform3D(Basis(t, Vector3.UP, r) if lat > 0.0 else Basis(-t, Vector3.UP, r), pos3(i, lat))


func _buildings() -> void:
	var concrete := GameMode.mat(Color(0.78, 0.78, 0.76), 0.85)
	var navy := GameMode.mat(Color("#02022f"), 0.5)
	var orange := GameMode.mat(Color("#ff4c00"), 0.45)
	var glass := GameMode.mat(Color(0.25, 0.35, 0.45), 0.08, 0.6)
	var steel := GameMode.mat(Color(0.82, 0.84, 0.86), 0.3, 0.7)
	var dark := GameMode.mat(Color(0.06, 0.06, 0.07), 0.9)
	var white := GameMode.mat(Color(0.93, 0.93, 0.92), 0.6)
	var sign_tex: Texture2D = await w.sign_texture(12.0, 4.0, true, true)
	var ad := await _ad_texture()
	for m in wall_mats:
		(m as ShaderMaterial).set_shader_parameter("ad_tex", ad)
		(m as ShaderMaterial).set_shader_parameter("has_ad", true)
	var sign_m := StandardMaterial3D.new()
	sign_m.albedo_texture = sign_tex
	sign_m.emission_enabled = true
	sign_m.emission_texture = sign_tex
	sign_m.emission_energy_multiplier = 0.35
	# pit building and paddock on the left of the main straight
	var i0 := n - int(260.0 / DS)
	var pit := Node3D.new()
	pit.transform = _frame_at(i0, -(wall_l[i0] + 14.0))
	add_child(pit)
	var L := 330.0
	pit.position.y = H(pit.position.x, pit.position.z)
	for g in 14:
		var x := -L / 2.0 + 12.0 + g * 22.5
		GameMode.add_box(pit, Vector3(18.0, 5.0, 0.4), Vector3(x + 9.0, 2.5, -7.8), dark)
		GameMode.add_box(pit, Vector3(4.5, 5.6, 0.6), Vector3(x - 2.0, 2.8, -7.8), white)
		GameMode.add_box(pit, Vector3(18.4, 0.5, 0.7), Vector3(x + 9.0, 5.3, -7.8), orange if g % 2 == 0 else navy)
	GameMode.add_box(pit, Vector3(L, 6.0, 16.0), Vector3(0, 3.0, 0.4), concrete)
	GameMode.add_box(pit, Vector3(L, 3.6, 14.0), Vector3(0, 7.8, 0.0), glass)
	GameMode.add_box(pit, Vector3(L + 2.0, 0.5, 18.0), Vector3(0, 9.85, 0.0), steel)
	GameMode.add_box(pit, Vector3(L, 1.2, 0.3), Vector3(0, 6.6, -8.1), navy)
	# race control tower with a big SmartMotion sign
	GameMode.add_box(pit, Vector3(16.0, 20.0, 14.0), Vector3(-L / 2.0 + 20.0, 10.0, 1.0), white)
	GameMode.add_box(pit, Vector3(16.6, 4.0, 14.6), Vector3(-L / 2.0 + 20.0, 17.5, 1.0), glass)
	var sg := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(12.0, 4.0)
	sg.mesh = q
	sg.material_override = sign_m
	sg.position = Vector3(-L / 2.0 + 20.0, 12.0, -6.05)
	sg.rotation.y = PI
	pit.add_child(sg)
	# pit lane (paved) between the barrier and the garages
	GameMode.add_box(pit, Vector3(L + 40.0, 0.1, 12.0), Vector3(0, 0.02, -13.0), GameMode.mat(Color(0.2, 0.2, 0.21), 0.85))
	# grandstands opposite the pits and at the first corner and the hairpin
	for st in [[n - int(200.0 / DS), 1.0, 240.0], [n - int(40.0 / DS), 1.0, 90.0], [int(220.0 / DS), -1.0, 120.0], [int(length * 0.27 / DS), 1.0, 100.0]]:
		var si: int = st[0] % n
		var side: float = st[1]
		var lat := (wall_r[si] if side > 0.0 else wall_l[si]) + 9.0
		_grandstand(_frame_at(si, lat * side), float(st[2]), concrete, steel, navy, orange)
	# SmartMotion signs above the barriers on the main straight
	for k in 4:
		var si := (n - int((90.0 + k * 110.0) / DS)) % n
		var f := _frame_at(si, wall_r[si] + 1.5)
		var board := Node3D.new()
		board.transform = f
		add_child(board)
		var b := MeshInstance3D.new()
		var qq := QuadMesh.new()
		qq.size = Vector2(12.0, 4.0)
		b.mesh = qq
		b.material_override = sign_m
		b.position = Vector3(0, 7.0, 0)
		b.rotation.y = PI
		board.add_child(b)
		GameMode.add_box(board, Vector3(12.4, 4.4, 0.2), Vector3(0, 7.0, 0.15), navy)
		GameMode.add_cyl(board, 0.12, 0.12, 5.0, Vector3(-5.0, 2.5, 0.2), steel)
		GameMode.add_cyl(board, 0.12, 0.12, 5.0, Vector3(5.0, 2.5, 0.2), steel)


## Barrier advertising in SmartMotion colours: two 16 m boards (navy with the name, orange with the slogan).
func _ad_texture() -> Texture2D:
	var vp := SubViewport.new()
	vp.size = Vector2i(2048, 256)
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var font: Font = load("res://assets/fonts/BarlowSemiCondensed-ExtraBoldItalic.ttf")
	for row in 2:
		var bg := ColorRect.new()
		bg.color = Color("#02022f") if row == 0 else Color("#ff4c00")
		bg.position = Vector2(0, row * 128)
		bg.size = Vector2(2048, 128)
		vp.add_child(bg)
		var stripe := ColorRect.new()
		stripe.color = Color("#ff4c00") if row == 0 else Color("#02022f")
		stripe.position = Vector2(0, row * 128 + 112)
		stripe.size = Vector2(2048, 16)
		vp.add_child(stripe)
		for k in 2:
			var l := Label.new()
			l.text = "SMARTMOTION" if row == 0 else "FLY IT. DRIVE IT. FEEL IT."
			l.add_theme_font_override("font", font)
			l.add_theme_font_size_override("font_size", 92 if row == 0 else 74)
			l.add_theme_color_override("font_color", Color.WHITE)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			l.position = Vector2(k * 1024, row * 128 - 6)
			l.size = Vector2(1024, 124)
			vp.add_child(l)
	add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		img = Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color("#02022f"))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _grandstand(f: Transform3D, L: float, concrete: Material, steel: Material, navy: Material, orange: Material) -> void:
	var g := Node3D.new()
	g.transform = f
	add_child(g)
	var tiers := 12
	var rng := RandomNumberGenerator.new()
	rng.seed = int(f.origin.x * 7.0 + f.origin.z)
	var crowd: Array = []
	for t in tiers:
		var z := 2.0 + t * 1.1
		var y := 1.2 + t * 0.62
		GameMode.add_box(g, Vector3(L, 0.5, 1.1), Vector3(0, y, z), concrete)
		GameMode.add_box(g, Vector3(L, 0.45, 0.35), Vector3(0, y + 0.45, z + 0.3), navy if t % 2 == 0 else orange)
		var x := -L / 2.0 + 0.4
		while x < L / 2.0 - 0.4:
			if rng.randf() < 0.82:
				crowd.append(Vector3(x + rng.randf_range(-0.1, 0.1), y + 0.85, z - 0.1))
			x += 0.62
	GameMode.add_box(g, Vector3(L, tiers * 0.62 + 1.5, 0.6), Vector3(0, (tiers * 0.62 + 1.5) / 2.0, 2.0 + tiers * 1.1 + 0.3), concrete)
	# roof on posts
	var top := tiers * 0.62 + 6.5
	GameMode.add_box(g, Vector3(L + 2.0, 0.4, tiers * 1.1 + 5.0), Vector3(0, top, 1.5 + tiers * 0.55), steel, Vector3(-0.06, 0, 0))
	for k in int(L / 24.0) + 1:
		GameMode.add_cyl(g, 0.2, 0.2, top + 1.0, Vector3(-L / 2.0 + k * 24.0, (top + 1.0) / 2.0, 2.0 + tiers * 1.1), steel)
	GameMode.add_box(g, Vector3(L + 2.0, 1.4, 0.2), Vector3(0, top - 0.6, 0.2), navy)
	# the crowd: one small figure each, in shirts of every colour
	var body := CapsuleMesh.new()
	body.radius = 0.22
	body.height = 1.0
	body.radial_segments = 6
	body.rings = 1
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = body
	mm.instance_count = crowd.size()
	var shirts := [Color("#ff4c00"), Color("#02022f"), Color.WHITE, Color("#c8202a"), Color("#2a6fd6"), Color("#f2c230"), Color("#1d8a4a"), Color("#444444")]
	for k in crowd.size():
		mm.set_instance_transform(k, Transform3D(Basis().scaled(Vector3.ONE * rng.randf_range(0.9, 1.1)), crowd[k]))
		mm.set_instance_color(k, shirts[rng.randi() % shirts.size()])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var cm := StandardMaterial3D.new()
	cm.vertex_color_use_as_albedo = true
	cm.roughness = 0.9
	mmi.material_override = cm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(mmi)


func _start_gantry() -> void:
	var i := 3
	var steel := GameMode.mat(Color(0.12, 0.12, 0.14), 0.4, 0.6)
	var g := Node3D.new()
	var t := Vector3(tan2[i].x, 0, tan2[i].y)
	g.transform = Transform3D(Basis(Vector3(nrm2[i].x, 0, nrm2[i].y), Vector3.UP, -t), pos3(i))
	add_child(g)
	var span := wall_l[i] + wall_r[i]
	var mid := (wall_r[i] - wall_l[i]) / 2.0
	GameMode.add_box(g, Vector3(0.6, 9.0, 0.6), Vector3(-wall_l[i], 4.5, 0), steel)
	GameMode.add_box(g, Vector3(0.6, 9.0, 0.6), Vector3(wall_r[i], 4.5, 0), steel)
	GameMode.add_box(g, Vector3(span, 1.4, 0.8), Vector3(mid, 8.3, 0), GameMode.mat(Color("#02022f"), 0.5))
	GameMode.add_box(g, Vector3(span, 0.25, 0.82), Vector3(mid, 7.55, 0), GameMode.mat(Color("#ff4c00"), 0.5))
	var lbl := GameMode.label3d(g, "SMARTMOTION", 160, Vector3(mid, 8.3, 0.42), Color.WHITE, 0.02)
	lbl.rotation.y = 0.0
	var lbl2 := GameMode.label3d(g, "SMARTMOTION", 160, Vector3(mid, 8.3, -0.42), Color.WHITE, 0.02)
	lbl2.rotation.y = PI
	# five pairs of red start lights, facing the grid
	light_off_m = GameMode.mat(Color(0.08, 0.02, 0.02), 0.3)
	light_on_m = GameMode.glow_mat(Color(1.0, 0.05, 0.02), 6.0)
	var box := GameMode.add_box(g, Vector3(5.2, 1.6, 0.5), Vector3(0, 6.2, 0.2), steel)
	box.name = "lights"
	for k in 5:
		var pair: Array = []
		for r in 2:
			var s := GameMode.add_sphere(g, 0.26, Vector3(-2.0 + k * 1.0, 6.55 - r * 0.7, 0.48), light_off_m, Vector3(1, 1, 0.5), 12)
			pair.append(s)
		lights.append(pair)


func set_lights(count: int) -> void:
	for k in lights.size():
		for s in lights[k]:
			(s as MeshInstance3D).material_override = light_on_m if k < count else light_off_m


func _trees(quality: String) -> void:
	if w == null or w.scenery == null or w.scenery.tree_near == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var want: int = {"low": 1500, "medium": 3500, "high": 6000}.get(quality, 3500)
	var xs: Array = []
	var tries := 0
	while xs.size() < want and tries < want * 6:
		tries += 1
		# woods in clumps, plus single trees
		var cx := CENTRE.x + rng.randf_range(-1900.0, 1900.0)
		var cz := CENTRE.y + rng.randf_range(-1900.0, 1900.0)
		var clump := 1 if rng.randf() < 0.4 else rng.randi_range(6, 22)
		for c in clump:
			var p := Vector2(cx + rng.randf_range(-45.0, 45.0) * sqrt(clump), cz + rng.randf_range(-45.0, 45.0) * sqrt(clump))
			if not _clear_of_track(p, 14.0):
				continue
			if p.distance_to(CENTRE) > 1700.0 and rng.randf() < 0.6:
				continue
			xs.append(Vector3(p.x, H(p.x, p.y), p.y))
	# detailed trees near the track (where you see them up close), the simple ones further out
	var sets := [[], []]
	for p in xs:
		sets[0 if not _clear_of_track(Vector2(p.x, p.z), 80.0) else 1].append(p)
	for k2 in 2:
		var list: Array = sets[k2]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = w.scenery.tree_near if k2 == 0 else w.scenery.tree_far
		mm.instance_count = list.size()
		for k in list.size():
			# the Duxford tree is 1 m tall: scale it to 7-17 m, colours as in the Duxford woods
			var h := 7.0 + rng.randf() * 10.0
			var wd := h * (0.55 + rng.randf() * 0.25)
			var p3: Vector3 = list[k]
			mm.set_instance_transform(k, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(wd, h, wd)), p3 - Vector3(0, 0.4, 0)))
			mm.set_instance_color(k, Color(0.16, 0.27, 0.10).lerp(Color(0.30, 0.40, 0.15), rng.randf()).lerp(Color(0.36, 0.34, 0.16), rng.randf() * 0.25).srgb_to_linear())
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = w.scenery.tree_mat
		add_child(mmi)


func _clear_of_track(p: Vector2, margin: float) -> bool:
	var c := Vector2i(floori(p.x / 50.0), floori(p.y / 50.0))
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			for i in grid.get(c + Vector2i(dx, dz), PackedInt32Array()):
				if p.distance_to(c2[i]) < maxf(wall_l[i], wall_r[i]) + margin:
					return false
	return true


func _boards() -> void:
	# braking boards (300, 200, 100 m) before the slow corners
	var white := GameMode.mat(Color(0.95, 0.95, 0.95), 0.6)
	var done := {}
	for i in n:
		var a := vmax[i]
		var before := vmax[(i - 1 + n) % n]
		if a < 45.0 and before >= 45.0 and not done.has(i / 100):
			done[i / 100] = true
			for d in [100, 200, 300]:
				var bi := (i - int(d / DS) + n) % n
				var side := -1.0 if curv[i] > 0.0 else 1.0
				var lat := ((wall_l[bi] if side < 0.0 else wall_r[bi]) - 3.0) * side
				var f := _frame_at(bi, lat)
				var b := Node3D.new()
				b.transform = f
				add_child(b)
				GameMode.add_box(b, Vector3(1.6, 1.6, 0.08), Vector3(0, 1.5, 0), white).rotation.y = PI / 2.0
				GameMode.add_cyl(b, 0.05, 0.05, 1.0, Vector3(0, 0.4, 0), white)
				var tl := GameMode.label3d(b, str(d), 110, Vector3(0, 1.5, 0), Color("#02022f"), 0.01)
				tl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
