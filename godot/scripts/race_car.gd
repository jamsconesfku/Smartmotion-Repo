class_name RaceCar
extends Node3D
## An open-wheel single-seater racing car, built in code: nose and front wing, survival cell with the halo,
## sidepods, engine cover and fin, rear wing, floor, suspension arms, wide slick tyres that spin and steer,
## mirrors, driver's helmet and a steering wheel with a display and rev lights (the cockpit view and VR).
## Frame: forward -Z, up +Y, origin on the ground midway between the axles. Wheelbase 3.6 m, 2 m wide.

const WB := 3.6
const R_TYRE := 0.36
const EYE := Vector3(0, 1.04, 0.1)   # sat up a little higher than a real driver: clear over the halo, and the road at a natural height in VR

var body_col := Color("#02022f")
var accent := Color("#ff4c00")
var number := 7
var wheels: Array = []          # [pivot (steers), spinner]
var wheel_node: Node3D          # steering wheel (turns)
var helmet: Node3D
var rev_lights: Array = []
var rev_mats: Array = []
var off_m: StandardMaterial3D
var disp_gear: Label3D
var disp_info: Label3D
var spin := 0.0
var rain_light: MeshInstance3D
var cockpit_hidden: Array = []  # parts hidden in the first-person view


func _init(col := Color("#02022f"), acc := Color("#ff4c00"), num := 7) -> void:
	body_col = col
	accent = acc
	number = num
	_build()
	VehicleLook.apply(self, "car")   # v1.17.0: carbon fibre, tyre rubber, lacquer, brushed metal


func _paint_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.22
	m.metallic = 0.35
	m.clearcoat_enabled = true
	m.clearcoat = 0.6
	m.clearcoat_roughness = 0.15
	return m


func _lathe(profile: Array, segs: int, fn: Callable, pos: Vector3, sc: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.lathe(profile, segs, fn)
	mi.material_override = m
	mi.position = pos
	mi.scale = sc
	add_child(mi)
	return mi


func _build() -> void:
	var paint := _paint_mat()
	var carbon := GameMode.mat(Color(0.035, 0.035, 0.04), 0.35, 0.3)
	var black := GameMode.mat(Color(0.02, 0.02, 0.02), 0.6)
	var dark := GameMode.mat(Color(0.01, 0.01, 0.012), 0.9)
	var steel := GameMode.mat(Color(0.6, 0.62, 0.65), 0.25, 0.9)
	var bc := body_col
	var ac := accent
	var wh := Color(0.95, 0.95, 0.95)
	# nose: low and long, accent stripe on top
	_lathe([[-3.0, 0.05], [-2.8, 0.1], [-2.4, 0.15], [-2.0, 0.19], [-1.6, 0.24], [-1.2, 0.28]], 18,
		func(nn: Vector3, _p: Vector3) -> Color: return ac if nn.y > 0.55 else bc, Vector3(0, 0.3, 0), Vector3(1.0, 0.72, 1.0), paint)
	# survival cell around the driver
	_lathe([[-1.3, 0.27], [-0.9, 0.31], [-0.4, 0.33], [0.1, 0.34], [0.35, 0.33]], 20,
		func(nn: Vector3, _p: Vector3) -> Color: return bc if nn.y < 0.8 else bc.lightened(0.05), Vector3(0, 0.33, 0), Vector3(1.0, 0.72, 1.0), paint)
	# engine cover tapering to the back, with the shark fin
	_lathe([[0.1, 0.36], [0.5, 0.36], [1.0, 0.31], [1.5, 0.24], [1.9, 0.15], [2.2, 0.06]], 18,
		func(nn: Vector3, p: Vector3) -> Color: return ac if (nn.y > 0.3 and absf(p.x) < 0.05) else bc, Vector3(0, 0.42, 0), Vector3(1.0, 0.95, 1.0), paint)
	var fin := MeshInstance3D.new()
	fin.mesh = MeshKit.slab_fy([[-0.2, 0.0], [-1.9, 0.0], [-1.9, 0.38], [-0.4, 0.22]], 0.02, ac)
	fin.material_override = paint
	fin.position = Vector3(0, 0.72, 0)
	add_child(fin)
	# airbox above the driver's head (roll hoop)
	_lathe([[-0.18, 0.11], [-0.05, 0.14], [0.2, 0.15], [0.45, 0.1]], 14, func(_n: Vector3, _p: Vector3) -> Color: return bc, Vector3(0, 0.92, 0.42), Vector3(1.25, 1.0, 1.0), paint)
	GameMode.add_sphere(self, 0.1, Vector3(0, 0.92, 0.25), dark, Vector3(1.1, 0.95, 0.2), 12)
	# sidepods, with their dark air intakes
	for sx: float in [-1.0, 1.0]:
		_lathe([[-0.85, 0.2], [-0.6, 0.27], [0.0, 0.29], [0.6, 0.25], [1.2, 0.14], [1.5, 0.06]], 16,
			func(nn: Vector3, _p: Vector3) -> Color: return ac if nn.y < -0.2 else bc, Vector3(sx * 0.52, 0.3, 0.05), Vector3(1.0, 0.9, 1.0), paint)
		GameMode.add_sphere(self, 0.19, Vector3(sx * 0.52, 0.31, -0.8), dark, Vector3(1.0, 0.85, 0.25), 12)
		var lbl := GameMode.label3d(self, "SMARTMOTION", 64, Vector3(sx * 0.815, 0.37, 0.05), Color.WHITE, 0.0042)
		lbl.rotation.y = PI / 2.0 * sx
		var lbl2 := GameMode.label3d(self, "SMARTMOTION", 50, Vector3(sx * 0.37, 0.62, 1.05), ac if bc != ac else Color.WHITE, 0.0032)
		lbl2.rotation = Vector3(0, PI / 2.0 * sx, 0)
		lbl2.rotation.z = 0.0
	# number on the nose and engine cover
	var nl := GameMode.label3d(self, str(number), 120, Vector3(0, 0.43, -2.05), Color.WHITE, 0.0018)
	nl.rotation.x = -PI / 2.0 + 0.2
	var nf := GameMode.label3d(self, str(number), 120, Vector3(0.012, 0.88, 1.1), Color.WHITE, 0.0022)
	nf.rotation.y = PI / 2.0
	var nf2 := GameMode.label3d(self, str(number), 120, Vector3(-0.012, 0.88, 1.1), Color.WHITE, 0.0022)
	nf2.rotation.y = -PI / 2.0
	# floor and bargeboards
	var floor_mi := MeshInstance3D.new()
	floor_mi.mesh = MeshKit.slab_xf([[-0.82, 1.3], [0.82, 1.3], [0.82, -1.6], [0.4, -1.95], [-0.4, -1.95], [-0.82, -1.6]], 0.03, Color(0.04, 0.04, 0.045), Color(0.03, 0.03, 0.03), Color(0.03, 0.03, 0.03))
	floor_mi.material_override = _paint_mat()
	floor_mi.position.y = 0.07
	add_child(floor_mi)
	# front wing: three elements and endplates
	for e in 3:
		var fw := MeshInstance3D.new()
		var ch := 0.32 - e * 0.07
		fw.mesh = MeshKit.slab_xf([[-1.0, 0.0], [1.0, 0.0], [1.0, -ch], [-1.0, -ch]], 0.022, ac if e == 2 else bc, Color(0.03, 0.03, 0.03), Color(0.03, 0.03, 0.03))
		fw.material_override = paint
		fw.position = Vector3(0, 0.09 + e * 0.055, -2.7 + e * 0.14)
		fw.rotation.x = 0.06 + e * 0.12
		add_child(fw)
	for sx: float in [-1.0, 1.0]:
		GameMode.add_box(self, Vector3(0.02, 0.24, 0.6), Vector3(sx * 1.0, 0.17, -2.6), carbon)
		GameMode.add_rod(self, Vector3(sx * 0.04, 0.22, -2.45), Vector3(sx * 0.04, 0.1, -2.6), 0.015, carbon)
	# rear wing: main plane and flap, endplates, swan-neck pillar, beam wing
	var rw := MeshInstance3D.new()
	rw.mesh = MeshKit.slab_xf([[-0.52, 0.0], [0.52, 0.0], [0.52, -0.3], [-0.52, -0.3]], 0.03, bc, Color(0.03, 0.03, 0.03), Color(0.03, 0.03, 0.03))
	rw.material_override = paint
	rw.position = Vector3(0, 0.84, 2.55)
	rw.rotation.x = 0.12
	add_child(rw)
	var rf := MeshInstance3D.new()
	rf.mesh = MeshKit.slab_xf([[-0.52, 0.0], [0.52, 0.0], [0.52, -0.2], [-0.52, -0.2]], 0.02, ac, Color(0.03, 0.03, 0.03), Color(0.03, 0.03, 0.03))
	rf.material_override = paint
	rf.position = Vector3(0, 0.97, 2.42)
	rf.rotation.x = 0.55
	add_child(rf)
	for sx: float in [-1.0, 1.0]:
		GameMode.add_box(self, Vector3(0.02, 0.5, 0.55), Vector3(sx * 0.53, 0.8, 2.45), carbon)
		var el := GameMode.label3d(self, "SMARTMOTION", 46, Vector3(sx * 0.542, 0.88, 2.45), Color.WHITE, 0.0022)
		el.rotation.y = PI / 2.0 * sx
	GameMode.add_rod(self, Vector3(0, 0.55, 2.0), Vector3(0, 0.98, 2.38), 0.02, carbon)
	GameMode.add_box(self, Vector3(0.9, 0.02, 0.18), Vector3(0, 0.42, 2.35), carbon, Vector3(0.2, 0, 0))
	rain_light = GameMode.add_box(self, Vector3(0.12, 0.05, 0.03), Vector3(0, 0.36, 2.48), GameMode.glow_mat(Color(1, 0.05, 0.02), 1.0))
	# halo
	var halo := MeshInstance3D.new()
	var pts: Array = []
	for k in 13:
		var a := PI * k / 12.0
		pts.append(Vector3(cos(a) * 0.29, 0.72 + sin(a) * 0.08, 0.05 - sin(a) * 0.62))
	halo.mesh = GameMode.tube_mesh(pts, 0.026, Color(0.05, 0.05, 0.06), 10)
	halo.material_override = _paint_mat()
	add_child(halo)
	GameMode.add_rod(self, Vector3(0, 0.8, -0.57), Vector3(0, 0.6, -0.78), 0.03, carbon)
	# cockpit rim and headrest
	for sx: float in [-1.0, 1.0]:
		GameMode.add_box(self, Vector3(0.08, 0.09, 0.8), Vector3(sx * 0.27, 0.6, -0.1), dark)
	GameMode.add_box(self, Vector3(0.6, 0.12, 0.2), Vector3(0, 0.62, 0.32), dark)
	# mirrors
	for sx: float in [-1.0, 1.0]:
		GameMode.add_rod(self, Vector3(sx * 0.3, 0.58, -0.62), Vector3(sx * 0.48, 0.7, -0.6), 0.012, carbon)
		GameMode.add_box(self, Vector3(0.17, 0.07, 0.05), Vector3(sx * 0.5, 0.71, -0.6), carbon)
		GameMode.add_box(self, Vector3(0.15, 0.055, 0.005), Vector3(sx * 0.5, 0.71, -0.574), steel)
	# driver's helmet (hidden in the first-person view)
	helmet = Node3D.new()
	helmet.position = Vector3(0, 0.79, 0.1)
	add_child(helmet)
	GameMode.add_sphere(helmet, 0.135, Vector3.ZERO, _helmet_mat(), Vector3(1.0, 1.05, 1.1), 18)
	GameMode.add_sphere(helmet, 0.1, Vector3(0, 0.0, -0.08), GameMode.mat(Color(0.02, 0.02, 0.03), 0.05, 0.6), Vector3(1.15, 0.45, 0.6), 14)
	cockpit_hidden.append(helmet)
	# steering wheel
	_steering_wheel(carbon, dark)
	# wheels and suspension
	for wi in 4:
		var front := wi < 2
		var sx := -1.0 if wi % 2 == 0 else 1.0
		var z := -WB / 2.0 if front else WB / 2.0
		var x := sx * (0.82 if front else 0.78)
		var wdt := 0.3 if front else 0.4
		var piv := Node3D.new()
		piv.position = Vector3(x, R_TYRE, z)
		add_child(piv)
		var sp := Node3D.new()
		piv.add_child(sp)
		var tyre := GameMode.add_cyl(sp, R_TYRE, R_TYRE, wdt, Vector3.ZERO, black, Vector3(0, 0, PI / 2.0), 28)
		tyre.name = "tyre"
		var rim_m := GameMode.mat(Color(0.08, 0.08, 0.09), 0.3, 0.8)
		for side: float in [-1.0, 1.0]:
			GameMode.add_cyl(sp, 0.235, 0.235, 0.01, Vector3(side * (wdt / 2.0 + 0.001), 0, 0), rim_m, Vector3(0, 0, PI / 2.0), 24)
			var ring := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.27
			tm.outer_radius = 0.29
			tm.rings = 28
			tm.ring_segments = 4
			ring.mesh = tm
			ring.material_override = GameMode.mat(Color(0.95, 0.8, 0.1) if front else Color(0.9, 0.1, 0.08), 0.5)
			ring.position = Vector3(side * (wdt / 2.0 + 0.002), 0, 0)
			ring.rotation.z = PI / 2.0
			ring.scale = Vector3(1, 0.1, 1)
			sp.add_child(ring)
			# spokes so the spinning shows
			for k in 5:
				var a := TAU * k / 5.0
				GameMode.add_box(sp, Vector3(0.012, 0.03, 0.2), Vector3(side * (wdt / 2.0 + 0.004), sin(a) * 0.1, cos(a) * 0.1), steel, Vector3(a, 0, 0))
		wheels.append([piv, sp, front])
		# wishbones from the chassis to the hub
		var hub := Vector3(x - sx * wdt * 0.5, R_TYRE, z)
		for dz in [-0.28, 0.28]:
			GameMode.add_rod(self, Vector3(sx * 0.24, 0.42, z + dz), hub + Vector3(0, 0.08, 0), 0.016, carbon)
			GameMode.add_rod(self, Vector3(sx * 0.22, 0.22, z + dz), hub + Vector3(0, -0.07, 0), 0.016, carbon)
	# shadows from the whole car
	for c in get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _helmet_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = accent
	m.roughness = 0.15
	m.metallic = 0.2
	m.clearcoat_enabled = true
	return m


func _steering_wheel(carbon: Material, dark: Material) -> void:
	wheel_node = Node3D.new()
	wheel_node.position = Vector3(0, 0.62, -0.42)
	wheel_node.rotation.x = 0.35    # tilted towards the driver
	add_child(wheel_node)
	GameMode.add_box(wheel_node, Vector3(0.26, 0.13, 0.05), Vector3(0, 0, 0), carbon)
	GameMode.add_box(wheel_node, Vector3(0.12, 0.06, 0.03), Vector3(0, -0.075, 0), carbon)
	for sx: float in [-1.0, 1.0]:
		var g := GameMode.add_cyl(wheel_node, 0.025, 0.025, 0.15, Vector3(sx * 0.15, -0.005, 0.0), GameMode.mat(Color(0.05, 0.05, 0.05), 0.9), Vector3(0, 0, sx * 0.12), 10)
		g.name = "grip"
		# buttons
		for b in 3:
			var col: Color = [Color(1, 0.3, 0), Color(0.1, 0.5, 1), Color(0.9, 0.9, 0.9)][b]
			GameMode.add_cyl(wheel_node, 0.009, 0.009, 0.01, Vector3(sx * (0.06 + b * 0.02), 0.04 - b * 0.03, 0.027), GameMode.glow_mat(col, 0.6), Vector3(PI / 2.0, 0, 0), 8)
	# display
	var scr := GameMode.add_box(wheel_node, Vector3(0.1, 0.055, 0.004), Vector3(0, 0.0, 0.026), GameMode.mat(Color(0.01, 0.02, 0.03), 0.1))
	scr.name = "screen"
	disp_gear = GameMode.label3d(wheel_node, "N", 64, Vector3(0, 0.003, 0.0285), Color("#ff4c00"), 0.0006)
	disp_info = GameMode.label3d(wheel_node, "", 22, Vector3(0, -0.02, 0.0285), Color.WHITE, 0.0006, false)
	# rev lights across the top
	off_m = GameMode.mat(Color(0.05, 0.05, 0.05), 0.4)
	for k in 15:
		var col := Color(0.1, 1.0, 0.2) if k < 5 else (Color(1.0, 0.1, 0.05) if k < 10 else Color(0.3, 0.4, 1.0))
		rev_mats.append(GameMode.glow_mat(col, 3.0))
		var l := GameMode.add_sphere(wheel_node, 0.0055, Vector3(-0.07 + k * 0.01, 0.05, 0.027), off_m, Vector3(1, 1, 0.5), 8)
		rev_lights.append(l)


## Where a VR hand holds the steering wheel (global): the left or right grip.
func wheel_grip(side: String) -> Transform3D:
	var sx := -1.0 if side == "l" else 1.0
	var g := Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)), Vector3(sx * 0.15, 0.0, 0.0))
	return wheel_node.global_transform * g.rotated_local(Vector3(0, 0, 1), sx * 0.25)


func set_first_person(on: bool) -> void:
	for c in cockpit_hidden:
		(c as Node3D).visible = not on


## Wheels spin with speed, front wheels and the steering wheel turn, the display shows gear and speed.
func animate(speed: float, steer: float, dt: float, rpm: float, gear: int, info: String, braking: bool) -> void:
	spin = fmod(spin + speed / R_TYRE * dt, TAU)
	for wd in wheels:
		(wd[1] as Node3D).rotation.x = -spin
		if wd[2]:
			(wd[0] as Node3D).rotation.y = -steer
	if wheel_node != null:
		wheel_node.rotation.z = -steer * 4.5
	if disp_gear != null:
		disp_gear.text = "N" if gear == 0 else str(gear)
		disp_info.text = info
		var lit := int(clampf((rpm - 0.55) / 0.42, 0.0, 1.0) * 15.0)
		for k in rev_lights.size():
			(rev_lights[k] as MeshInstance3D).material_override = rev_mats[k] if k < lit else off_m
	if rain_light != null:
		(rain_light.material_override as StandardMaterial3D).emission_energy_multiplier = 6.0 if braking else 1.0
