class_name CoasterMode
extends GameMode
## SmartMotion Coaster: a roller coaster ride in a field beside Duxford airfield (it uses the Duxford world).
## For the simulator set up "hands-free": you just ride. 1.07 km of steel track: a 52 m chain lift, a 50 m
## drop to 104 km/h, a 32 m camelback (you float out of your seat over the top), a high banked turnaround at
## 25 m that dives back to the ground, a second hill, a helix and an S-bend back into the station (v1.12.0).
## No support post stands where another part of the track passes (plan_posts / post_blocked). The track banks itself so the force always pushes you into the seat (no sideways g), 0 to 3 g.
##
## Track: a smooth curve through the points below (metres; x along the field, y above the ground, z across).
## Speed: the chain pulls the train up at 4 m/s, then gravity and a little friction and air drag; tyres hold
## 3 m/s in the station. Checked by tests/test_coaster.gd.

const POINTS := [Vector3(0, 3, 40), Vector3(0, 3, 0), Vector3(0, 3, -30), Vector3(6, 3.5, -50), Vector3(20, 6, -63), Vector3(38, 13, -68),
	Vector3(60, 24, -68), Vector3(85, 39, -68), Vector3(105, 50, -68), Vector3(116, 52.5, -68), Vector3(127, 52, -68),
	Vector3(138, 47, -68), Vector3(150, 36, -68), Vector3(162, 22, -68), Vector3(174, 11, -68), Vector3(188, 5.5, -67), Vector3(204, 5, -66),
	Vector3(220, 11, -64), Vector3(236, 22, -62), Vector3(252, 30, -60), Vector3(268, 32, -58), Vector3(284, 27.5, -56), Vector3(300, 17, -53), Vector3(316, 8, -49),
	Vector3(334, 7, -40), Vector3(350, 13, -20), Vector3(357, 21, 4), Vector3(347, 25, 26), Vector3(326, 22, 41), Vector3(304, 14, 47),
	Vector3(280, 6.5, 48), Vector3(256, 12, 48), Vector3(236, 14, 48), Vector3(216, 11, 48), Vector3(196, 9.5, 48), Vector3(172, 12.5, 48),
	Vector3(150, 13.5, 48), Vector3(128, 12.5, 54), Vector3(118, 11, 70), Vector3(126, 9.5, 86), Vector3(140, 8, 92), Vector3(156, 6.5, 86),
	Vector3(162, 5, 70), Vector3(154, 4, 55), Vector3(140, 3.5, 48),
	Vector3(118, 4, 50), Vector3(98, 4.5, 62), Vector3(80, 5, 80), Vector3(60, 5, 89), Vector3(36, 4.5, 90), Vector3(16, 4, 85), Vector3(4, 3.5, 72)]
const ORIGIN := Vector2(500, 0)     # world x, z of the station end (a field 265 m south-east of the runway)
const DS := 0.5
const G := 9.81
const CARS := 4
const CAR_GAP := 2.7
const RIDER := Vector3(-0.32, 1.42, -0.34)   # your eyes, sitting in the front car (left seat, front row), in front of the seat back

var n := 0
var length := 0.0
var P: PackedVector3Array          # track centre (world)
var Tn: PackedVector3Array         # direction of travel
var Up: PackedVector3Array         # banked "up" (rails plane)
var lift_from := 0.0
var lift_to := 0.0
const POST_CLEAR := 2.6           # m from a post to the centre of any other part of the track (train 1.6 m wide)
const S_PARK := 42.0               # where the front car stops in the station (platform from 10 to 45 m)
var base_y := 0.0
var cars: Array = []
var train: Node3D
var s := 0.0
var v := 0.0
var phase := "station"             # station, ride, done
var wait := 0.0
var t_ride := 0.0
var max_g := 0.0
var felt := Vector3(0, G, 0)
var prev_vel := Vector3.ZERO
var prev_b := Basis()
var w_body := Vector3.ZERO
var cam_init := false
var cam_q := Quaternion.IDENTITY
var lap_bars: Array = []
var on_lift := false


func mode_name() -> String:
	return "coaster"


func uses_world() -> bool:
	return true


func camera_modes() -> Array:
	return ["cockpit", "chase", "orbit"]


func build(w: World, q: String) -> void:
	super.build(w, q)
	build_track(w.terrain)
	_meshes(w)
	await _station(w)
	_train()
	VehicleLook.apply(train, "coaster")   # v1.17.0
	vehicle = cars[0]
	eye = RIDER


# ---------------------------------------------------------------- the track
func _cr(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
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


## Works out the track (no meshes): centre line, banking and the speed plan used for the banking.
func build_track(terrain: Terrain) -> void:
	base_y = terrain.height(ORIGIN.x, ORIGIN.y) if terrain != null else 0.0
	var dense := PackedVector3Array()
	var m := POINTS.size()
	for i in m:
		for k in 60:
			dense.append(_cr(POINTS[(i - 1 + m) % m], POINTS[i], POINTS[(i + 1) % m], POINTS[(i + 2) % m], k / 60.0))
	var cum := PackedFloat32Array([0.0])
	var L := 0.0
	for i in range(1, dense.size() + 1):
		L += dense[i - 1].distance_to(dense[i % dense.size()])
		cum.append(L)
	n = int(L / DS)
	length = L
	P = PackedVector3Array()
	var j := 0
	for i in n:
		var sv := i * L / n
		while cum[j + 1] < sv:
			j += 1
		var f := (sv - cum[j]) / (cum[j + 1] - cum[j])
		var lp := dense[j].lerp(dense[(j + 1) % dense.size()], f)
		P.append(Vector3(ORIGIN.x + lp.x, base_y + lp.y, ORIGIN.y + lp.z))
	Tn = PackedVector3Array()
	for i in n:
		Tn.append((P[(i + 1) % n] - P[(i - 1 + n) % n]).normalized())
	# where the chain lift and the station are
	lift_from = -1.0
	for i in n:
		var lp := P[i] - Vector3(ORIGIN.x, base_y, ORIGIN.y)
		var on := lp.x > 15.0 and lp.x < 116.0 and lp.z < -58.0
		if on and lift_from < 0.0:
			lift_from = i * DS * length / (n * DS)
		if on:
			lift_to = i * length / n
	# speed plan (for the banking): one lap from the station
	var vp := PackedFloat32Array()
	vp.resize(n)
	var vv := 3.0
	for i in n:
		var sv := i * length / n
		if _zone(sv) != "":
			vv = 4.0 if _zone(sv) == "lift" else 3.0
		else:
			var dy := P[i].y - P[(i - 1 + n) % n].y
			vv = sqrt(maxf(vv * vv - 2.0 * G * dy - 2.0 * (0.012 * G + 0.0012 * vv * vv) * DS, 1.0))
		vp[i] = vv
	# banking: the rails tilt so the force you feel (gravity + turning) points straight down into the seat
	var bank := PackedFloat32Array()
	bank.resize(n)
	var W := 24
	for i in n:
		var dT := (Tn[(i + W) % n] - Tn[(i - W + n) % n]) / (2.0 * W * DS)
		var F := dT * vp[i] * vp[i] + Vector3(0, G, 0)
		var u0 := (Vector3.UP - Tn[i] * Tn[i].y).normalized()
		var r0 := Tn[i].cross(u0)
		bank[i] = atan2(F.dot(r0), maxf(F.dot(u0), 0.2 * G))
	Up = PackedVector3Array()
	for i in n:
		var b := 0.0
		for k in range(-20, 21):
			b += bank[(i + k + n) % n]
		b /= 41.0
		var u0 := (Vector3.UP - Tn[i] * Tn[i].y).normalized()
		Up.append(u0.rotated(Tn[i], b))


func _zone(sv: float) -> String:
	if sv >= lift_from and sv <= lift_to:
		return "lift"
	if sv < lift_from or sv > length - 25.0:
		return "station"   # tyres in the station and up to the lift
	return ""


## Frame on the track at distance sv: origin on the centre line at rail height, -Z forward, +Y up.
func frame(sv: float) -> Transform3D:
	var f := fposmod(sv, length) / length * n
	var i0 := int(f) % n
	var i1 := (i0 + 1) % n
	var k := f - floorf(f)
	var p := P[i0].lerp(P[i1], k)
	var t := Tn[i0].lerp(Tn[i1], k).normalized()
	var u := Up[i0].lerp(Up[i1], k)
	u = (u - t * u.dot(t)).normalized()
	var x := t.cross(u).normalized()   # right
	return Transform3D(Basis(x, u, -t), p)


# ---------------------------------------------------------------- meshes
func _sweep(k: MeshKit, off: Vector2, r: float, col: Color, from_i: int, to_i: int, step: int) -> void:
	# a tube along the track, offset (right, up) from the centre line
	var segs := 8
	var prev: Array = []
	var i := from_i
	while true:
		var fr := frame(i * length / n)
		var c := fr.origin + fr.basis.x * off.x + fr.basis.y * off.y
		var ring: Array = []
		for sgi in segs:
			var a := TAU * sgi / segs
			var nn := fr.basis.x * cos(a) + fr.basis.y * sin(a)
			ring.append([c + nn * r, nn])
		if not prev.is_empty():
			for sgi in segs:
				var s2 := (sgi + 1) % segs
				var A_: Array = prev[sgi]
				var B_: Array = prev[s2]
				var C_: Array = ring[s2]
				var D_: Array = ring[sgi]
				k.add_smooth_tri(A_[0], B_[0], C_[0], A_[1], B_[1], C_[1], col, col, col)
				k.add_smooth_tri(A_[0], C_[0], D_[0], A_[1], C_[1], D_[1], col, col, col)
		prev = ring
		if i == to_i:
			break
		i = mini(i + step, to_i)


func _meshes(w: World) -> void:
	var org := Color("#ff4c00")
	var navy := Color("#0b0d3a")
	var steel := GameMode.mat(Color.WHITE, 0.35, 0.6)
	steel.vertex_color_use_as_albedo = true
	var k := MeshKit.new()
	_sweep(k, Vector2(-0.55, 0.0), 0.065, Color(0.75, 0.76, 0.78), 0, n, 2)
	_sweep(k, Vector2(0.55, 0.0), 0.065, Color(0.75, 0.76, 0.78), 0, n, 2)
	_sweep(k, Vector2(0.0, -0.55), 0.24, org, 0, n, 2)
	var mi := MeshInstance3D.new()
	mi.mesh = k.build()
	mi.material_override = steel
	add_child(mi)
	# cross ties, the chain on the lift and supports down to the ground
	var ties: Array = []
	var posts: Array = []
	var i := 0
	var step := int(1.2 / DS)
	while i < n:
		ties.append(frame(i * length / n))
		i += step
	posts = plan_posts(w.terrain if w != null else null)
	var tie_mesh := BoxMesh.new()
	tie_mesh.size = Vector3(1.3, 0.12, 0.14)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = tie_mesh
	mm.instance_count = ties.size()
	for t in ties.size():
		var fr: Transform3D = ties[t]
		mm.set_instance_transform(t, Transform3D(fr.basis, fr.origin - fr.basis.y * 0.25))
	var tmi := MultiMeshInstance3D.new()
	tmi.multimesh = mm
	tmi.material_override = GameMode.mat(Color(0.3, 0.3, 0.33), 0.5, 0.7)
	add_child(tmi)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.22
	cyl.bottom_radius = 0.3
	cyl.height = 1.0
	cyl.radial_segments = 10
	cyl.rings = 1
	var pm := MultiMesh.new()
	pm.transform_format = MultiMesh.TRANSFORM_3D
	pm.mesh = cyl
	pm.instance_count = posts.size() * 2
	for p in posts.size():
		var bottom: Vector3 = posts[p][0]
		var gy: float = posts[p][1]
		var h: float = posts[p][2]
		var wide := 0.25 + h * 0.025   # taller posts get thicker
		pm.set_instance_transform(p * 2, Transform3D(Basis().scaled(Vector3(wide / 0.25, h, wide / 0.25)), Vector3(bottom.x, gy + h / 2.0, bottom.z)))
		pm.set_instance_transform(p * 2 + 1, Transform3D(Basis().scaled(Vector3(2.4, 0.4, 2.4)), Vector3(bottom.x, gy + 0.15, bottom.z)))   # footing
	var pmi := MultiMeshInstance3D.new()
	pmi.multimesh = pm
	pmi.material_override = GameMode.mat(navy, 0.5, 0.4)
	add_child(pmi)
	# the lift chain
	var ck := MeshKit.new()
	var a0 := int(lift_from / length * n)
	var a1 := int(lift_to / length * n)
	_sweep(ck, Vector2(0.0, 0.02), 0.06, Color(0.08, 0.08, 0.08), a0, a1, 2)
	var cmi := MeshInstance3D.new()
	cmi.mesh = ck.build()
	cmi.material_override = steel
	add_child(cmi)


## Support posts down to the ground: [bottom of the track, ground height, post height]. A post is left out
## wherever another part of the track passes through the space it would stand in (the train must never hit one).
func plan_posts(terrain: Terrain) -> Array:
	var posts: Array = []
	var last_post := -100.0
	for pi in range(0, n, int(2.0 / DS)):
		var sv := pi * length / n
		var fr := frame(sv)
		var bottom := fr.origin - fr.basis.y * 0.75
		var gy := terrain.height(bottom.x, bottom.z) if terrain != null else base_y
		var h := bottom.y - gy
		if sv - last_post >= (7.0 if h > 3.0 else 12.0) and h > 0.4 and not post_blocked(bottom, gy, sv):
			last_post = sv
			posts.append([bottom, gy, h])
	return posts


## True if a post standing at bottom (from the ground at gy) would be in the way of the track elsewhere.
func post_blocked(bottom: Vector3, gy: float, sv: float) -> bool:
	for i in n:
		var d := absf(i * length / n - sv)
		if minf(d, length - d) < 8.0:
			continue   # this post's own bit of track
		var q := P[i]
		if q.y < gy - 1.0 or q.y > bottom.y + 2.5:
			continue
		if Vector2(q.x - bottom.x, q.z - bottom.z).length() < POST_CLEAR:
			return true
	return false


func _station(w: World) -> void:
	var st := Node3D.new()
	var f0 := frame(0.0)
	var mid := frame(27.0)
	st.transform = Transform3D(mid.basis, mid.origin)
	add_child(st)
	var navy := GameMode.mat(Color("#02022f"), 0.5)
	var org := GameMode.mat(Color("#ff4c00"), 0.45)
	var white := GameMode.mat(Color(0.93, 0.93, 0.92), 0.6)
	var conc := GameMode.mat(Color(0.7, 0.7, 0.68), 0.9)
	var gy := base_y - f0.origin.y + 0.0
	# platforms both sides, roof, back wall, steps
	GameMode.add_box(st, Vector3(3.0, 1.0, 34.0), Vector3(-2.4, -0.55, 0), conc)
	GameMode.add_box(st, Vector3(3.0, 1.0, 34.0), Vector3(2.4, -0.55, 0), conc)
	GameMode.add_box(st, Vector3(0.12, 0.08, 34.0), Vector3(-0.95, -0.03, 0), org)
	GameMode.add_box(st, Vector3(0.12, 0.08, 34.0), Vector3(0.95, -0.03, 0), org)
	for sx: float in [-1.0, 1.0]:
		for z in range(-15, 16, 6):
			GameMode.add_cyl(st, 0.15, 0.15, 5.0, Vector3(sx * 3.7, 2.0, z), white)
		GameMode.add_box(st, Vector3(0.2, 1.0, 34.0), Vector3(sx * 3.9, -0.1, 0), navy)
	GameMode.add_box(st, Vector3(9.0, 0.35, 36.0), Vector3(0, 4.6, 0), navy, Vector3(0, 0, 0))
	GameMode.add_box(st, Vector3(9.2, 0.5, 0.3), Vector3(0, 4.5, -18.0), org)
	GameMode.add_box(st, Vector3(9.2, 0.5, 0.3), Vector3(0, 4.5, 18.0), org)
	GameMode.add_box(st, Vector3(9.0, maxf(-gy - 1.0, 0.2), 34.0), Vector3(0, (gy - 1.0) / 2.0 - 0.5, 0), conc)
	if w != null:
		var tex: Texture2D = await w.sign_texture(9.0, 3.0, true, true, "SMARTMOTION COASTER")
		var sm := StandardMaterial3D.new()
		sm.albedo_texture = tex
		sm.emission_enabled = true
		sm.emission_texture = tex
		sm.emission_energy_multiplier = 0.5
		for sz: float in [-1.0, 1.0]:
			var sg := MeshInstance3D.new()
			var qm := QuadMesh.new()
			qm.size = Vector2(9.0, 3.0)
			sg.mesh = qm
			sg.material_override = sm
			sg.position = Vector3(0, 6.3, sz * 18.0)
			sg.rotation.y = 0.0 if sz > 0.0 else PI
			st.add_child(sg)
			GameMode.add_box(st, Vector3(9.3, 3.3, 0.2), Vector3(0, 6.3, sz * 17.88), navy)


func _figure(parent: Node3D, pos: Vector3, shirt: Color, arms_up: bool) -> void:
	var skin := GameMode.mat(Color(0.86, 0.68, 0.55), 0.8)
	var body := GameMode.mat(shirt, 0.8)
	GameMode.add_box(parent, Vector3(0.38, 0.5, 0.24), pos + Vector3(0, 0.3, 0), body)
	GameMode.add_sphere(parent, 0.11, pos + Vector3(0, 0.68, -0.02), skin, Vector3.ONE, 10)
	for sx: float in [-1.0, 1.0]:
		if arms_up:
			GameMode.add_rod(parent, pos + Vector3(sx * 0.2, 0.5, 0), pos + Vector3(sx * 0.32, 1.05, -0.08), 0.045, body)
		else:
			GameMode.add_rod(parent, pos + Vector3(sx * 0.2, 0.5, 0), pos + Vector3(sx * 0.16, 0.25, -0.3), 0.045, body)


func _train() -> void:
	train = Node3D.new()
	add_child(train)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color("#02022f")
	paint.metallic = 0.4
	paint.roughness = 0.25
	paint.clearcoat_enabled = true
	var org := GameMode.mat(Color("#ff4c00"), 0.3, 0.3)
	var seat := GameMode.mat(Color(0.1, 0.1, 0.12), 0.85)
	var steel := GameMode.mat(Color(0.7, 0.72, 0.75), 0.3, 0.8)
	var shirts := [Color("#ff4c00"), Color("#2a6fd6"), Color.WHITE, Color("#c8202a"), Color("#1d8a4a"), Color("#f2c230")]
	for c in CARS:
		var car := Node3D.new()
		train.add_child(car)
		cars.append(car)
		# body: a low tub with orange sides, nose on the front car
		GameMode.add_box(car, Vector3(1.6, 0.5, 2.3), Vector3(0, 0.4, 0), paint)
		GameMode.add_box(car, Vector3(1.64, 0.14, 2.32), Vector3(0, 0.5, 0), org)
		if c == 0:
			var nose := GameMode.add_sphere(car, 0.8, Vector3(0, 0.45, -1.15), paint, Vector3(1.0, 0.45, 0.7), 18)
			nose.name = "nose"
			var lbl := GameMode.label3d(car, "SMARTMOTION", 64, Vector3(0, 0.72, -1.38), Color.WHITE, 0.0035)
			lbl.rotation.x = -0.9
			lbl.rotation.y = PI
			lbl.rotation.y = 0.0
		for row in 2:
			var z := -0.45 + row * 1.0
			for sx: float in [-1.0, 1.0]:
				var x := sx * 0.32
				GameMode.add_box(car, Vector3(0.52, 0.12, 0.5), Vector3(x, 0.66, z + 0.05), seat)
				GameMode.add_box(car, Vector3(0.52, 0.75, 0.12), Vector3(x, 0.98, z + 0.32), seat, Vector3(-0.15, 0, 0))
				GameMode.add_box(car, Vector3(0.3, 0.22, 0.1), Vector3(x, 1.42, z + 0.38), seat, Vector3(-0.15, 0, 0))
				# lap bar
				var bar := Node3D.new()
				bar.position = Vector3(x, 0.72, z - 0.25)
				car.add_child(bar)
				GameMode.add_rod(bar, Vector3(0, 0, 0), Vector3(0, 0.35, 0.18), 0.03, steel)
				GameMode.add_rod(bar, Vector3(-0.18, 0.35, 0.18), Vector3(0.18, 0.35, 0.18), 0.035, org)
				lap_bars.append(bar)
				# other riders (not in your seat)
				if not (c == 0 and row == 0 and sx < 0.0):
					_figure(car, Vector3(x, 0.66, z + 0.1), shirts[(c * 4 + row * 2 + int(sx > 0.0)) % shirts.size()], (c + row) % 2 == 0)
		# wheel assemblies
		for sx: float in [-1.0, 1.0]:
			GameMode.add_box(car, Vector3(0.25, 0.5, 0.9), Vector3(sx * 0.62, -0.05, 0), steel)
		# coupling
		GameMode.add_rod(car, Vector3(0, 0.25, 1.15), Vector3(0, 0.25, 1.45), 0.06, steel)


# ---------------------------------------------------------------- the ride
func showcase() -> void:
	super.showcase()
	_reset()


func _reset() -> void:
	s = S_PARK
	v = 0.0
	phase = "station"
	wait = 0.0
	t_ride = 0.0
	max_g = 0.0
	cam_init = false
	prev_vel = Vector3.ZERO
	_place(0.0)


func start() -> void:
	super.start()
	_reset()
	toast.emit("Sit back and enjoy the ride. The train leaves in a few seconds", 4.0)


func idle(dt: float) -> void:
	if not running:
		_place(dt)


func step(dt: float, _inp: Dictionary) -> void:
	if not running:
		return
	if phase == "station" and wait < 3.5:
		wait += dt
		for b in lap_bars:
			(b as Node3D).rotation.x = lerpf(0.9, 0.0, clampf(wait / 2.0, 0.0, 1.0))
		_place(dt)
		_tel(dt)
		return
	if phase == "station":
		phase = "ride"
	t_ride += dt
	# a few small steps for smooth speed changes
	for k in 4:
		var h := dt / 4.0
		var z := _zone(fposmod(s, length))
		on_lift = z == "lift"
		if z == "lift":
			v = move_toward(v, 4.0, 6.0 * h)
		elif z == "station":
			v = move_toward(v, 3.0, 4.0 * h)
			if s > length:
				v = minf(v, sqrt(maxf(3.0 * (length + S_PARK - s), 0.0)))   # brake to a stop at the platform
		else:
			var fr := frame(s)
			var ty := -fr.basis.z.y
			v += (-G * ty - (0.012 * G + 0.0012 * v * v)) * h
			v = maxf(v, 0.5)
		s += v * h
	if s >= length + S_PARK - 0.3 and phase == "ride":
		phase = "done"
		v = 0.0
		finished.emit("Ride complete", "SmartMotion Coaster", "Top speed %d km/h, biggest force %.1f g. Ride time %d s." % [int(max_speed() * 3.6), max_g, int(t_ride)], "%.1f g" % max_g)
	_place(dt)
	_tel(dt)


func max_speed() -> float:
	return 29.0


func _place(dt: float) -> void:
	for c in cars.size():
		(cars[c] as Node3D).global_transform = frame(s - c * CAR_GAP)


func _tel(dt: float) -> void:
	var fr := frame(s)
	var vel := -fr.basis.z * v
	if dt > 0.0:
		var acc := (vel - prev_vel) / dt
		var f_world := acc + Vector3(0, G, 0)
		felt = felt.lerp(fr.basis.inverse() * f_world, 1.0 - exp(-dt * 12.0))
		var dq := (prev_b.inverse() * fr.basis).get_rotation_quaternion()
		w_body = w_body.lerp(dq.get_axis() * dq.get_angle() / dt if dq.get_angle() > 0.00001 else Vector3.ZERO, 1.0 - exp(-dt * 10.0))
		if phase == "ride":
			max_g = maxf(max_g, felt.y / G)
	prev_vel = vel
	prev_b = fr.basis
	make_tel(Time.get_ticks_msec() / 1000.0, false, false, fr.basis, fr.origin, vel, w_body, felt, v * 1.94384,
		{"speed_kmh": snappedf(v * 3.6, 0.1), "g": snappedf(felt.y / G, 0.01), "phase": phase, "on_ground": phase != "ride"})


func sound() -> Array:
	return [1.0 if on_lift and phase == "ride" else 0.0, 0.0, v]


func grip(_side: String) -> Array:
	if lap_bars.is_empty():
		return [Transform3D(), 0.0]
	# both hands on your lap bar
	var bar: Node3D = lap_bars[0]
	var sx := -1.0 if _side == "l" else 1.0
	var g := Transform3D(Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0)), Vector3(sx * 0.12, 0.35, 0.18))
	return [bar.global_transform * g, 0.25]


func hud(ui) -> void:
	var fr := frame(s)
	ui.l_speed.text = str(int(v * 3.6))
	ui.l_alt.text = str(int(fr.origin.y - base_y))
	ui.l_vs.text = "%.1f g" % (felt.y / G)
	ui.l_hdg.text = "%.1f g" % (felt.y / G)
	ui.thr_bar.value = clampf(v / 30.0, 0.0, 1.0)
	ui.tag_flaps.text = "CHAIN LIFT" if on_lift else ""
	ui.tag_brake.text = ""
	ui.tag_assist.text = ""
	ui.l_gate.text = "Ride time %d s" % int(t_ride)
	ui.l_gate_t.text = "biggest force %.1f g" % max_g
	var m := ""
	if phase == "station" and wait < 3.5:
		m = "Lap bars closing" if wait < 2.0 else "Here we go!"
	ui.set_message(m, false)


func place_camera(cam: Camera3D, cam_mode: String, dt: float, orbit: Dictionary) -> void:
	var fr := (cars[0] as Node3D).global_transform
	cam.fov = 75.0
	if not running:
		var oy: float = orbit["yaw"]
		var c := frame(s - 4.0).origin
		var cp := c + Vector3(sin(oy) * 16.0, 6.0, cos(oy) * 16.0)
		cam.global_transform = Transform3D(Basis.looking_at((c - cp).normalized(), Vector3.UP), cp)
		cam.fov = 60.0
		return
	if cam_mode == "cockpit":
		var lk: Vector2 = orbit["look"]
		cam.near = 0.05
		cam.global_transform = Transform3D(fr.basis * Basis.from_euler(Vector3(lk.y - 0.12, lk.x, 0)), fr * eye)
		return
	cam.near = 0.3
	if cam_mode == "orbit":
		var oy2: float = orbit["yaw"]
		var op: float = orbit["pitch"]
		var od: float = orbit["dist"]
		var c2 := frame(s - 4.0).origin
		var cp2 := c2 + Vector3(sin(oy2) * cos(op) * od, sin(op) * od + 2.0, cos(oy2) * cos(op) * od)
		cam.global_transform = Transform3D(Basis.looking_at((c2 - cp2).normalized(), Vector3.UP), cp2)
		return
	var q := fr.basis.get_rotation_quaternion()
	if not cam_init:
		cam_q = q
		cam_init = true
	cam_q = cam_q.slerp(q, 1.0 - exp(-dt * 3.0))
	var cb := Basis(cam_q)
	var back := frame(s - 16.0).origin
	var cp3 := back + cb.y * 4.0 + Vector3(0, 2.0, 0)
	cam.global_transform = Transform3D(Basis.looking_at((fr.origin - cp3).normalized(), Vector3.UP), cp3)
