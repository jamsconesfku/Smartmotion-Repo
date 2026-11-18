extends SceneTree
## Pictures of the buildings on their own (not a check; needs a screen, e.g. xvfb-run), quick on a slow computer:
##   godot --path godot --rendering-driver vulkan --script res://tests/shot_buildings.gd -- --out=/tmp/bld [--at=x,z] [--r=180]
## Takes the real footprints from assets/world/buildings.bin and the real roads (roads.bin) round a point (default:
## the houses 4 km north of the runway), builds them with BuildingKit and RoadKit on the real ground heights with the
## 1 m ground picture under them, and photographs them from the street and from the air.
var out := "/tmp/bld"
var at := Vector2(2500, -3750)
var r := 180.0
var cam: Camera3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--at="):
			var p := a.substr(5).split(",")
			at = Vector2(float(p[0]), float(p[1]))
		elif a.begins_with("--r="):
			r = float(a.substr(4))
	_run.call_deferred()


func _shot(name: String, from: Vector3, look: Vector3, fov := 55.0) -> void:
	cam.global_transform = Transform3D(Basis.looking_at((look - from).normalized(), Vector3.UP), from)
	cam.fov = fov
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s_%s.png" % [out, name])
	print("saved ", name)


func _run() -> void:
	root.get_viewport().size = Vector2i(1600, 900)
	root.get_viewport().msaa_3d = Viewport.MSAA_4X
	var env := Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.32, 0.5, 0.78)
	psm.sky_horizon_color = Color(0.72, 0.8, 0.88)
	psm.ground_bottom_color = Color(0.2, 0.22, 0.18)
	psm.ground_horizon_color = Color(0.55, 0.6, 0.55)
	sky.sky_material = psm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-38.0), deg_to_rad(-140.0), 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 400.0
	root.add_child(sun)
	var terrain := Terrain.new()
	# the ground: real heights, the 1 m ground picture (as in the game's detail square)
	var gk := SurfaceTool.new()
	gk.begin(Mesh.PRIMITIVE_TRIANGLES)
	var R := int(r * 2.2)
	var stp := 3
	var dh := 4096.0
	for zi in range(-R, R, stp):
		for xi in range(-R, R, stp):
			var q := [Vector2(xi, zi), Vector2(xi + stp, zi), Vector2(xi + stp, zi + stp), Vector2(xi, zi + stp)]
			var vs: Array = []
			for qq in q:
				var w: Vector2 = at + qq
				vs.append(Vector3(w.x, terrain.height(w.x, w.y), w.y))
			for tri in [[0, 2, 1], [0, 3, 2]]:
				for k in tri:
					var pv: Vector3 = vs[k]
					gk.set_uv(Vector2((pv.x + dh) / (2.0 * dh), (pv.z + dh) / (2.0 * dh)))
					gk.add_vertex(pv)
	gk.generate_normals()
	var ground := MeshInstance3D.new()
	ground.mesh = gk.commit()
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = load("res://assets/world/detail_photo.jpg")
	gm.roughness = 0.95
	gm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	ground.material_override = gm
	root.add_child(ground)
	cam = Camera3D.new()
	cam.far = 5000.0
	root.add_child(cam)
	cam.current = true
	# the real footprints round the point, moved to the origin, on flat ground
	var f := FileAccess.open("res://assets/world/buildings.bin", FileAccess.READ)
	var buf := f.get_buffer(f.get_length())
	var nb := buf.decode_u32(0)
	var o := 4
	var kit := BuildingKit.new()
	var rng := RandomNumberGenerator.new()
	var count := 0
	for b in nb:
		var nv := buf.decode_u8(o)
		var kind := buf.decode_u8(o + 1)
		var h := buf.decode_u16(o + 2) / 10.0
		o += 4
		var pts := PackedVector2Array()
		var cc := Vector2.ZERO
		for k in nv:
			var p := Vector2(buf.decode_s32(o) / 4.0, buf.decode_s32(o + 4) / 4.0)
			o += 8
			pts.append(p)
			cc += p
		cc /= nv
		if cc.distance_to(at) > r:
			continue
		rng.seed = hash(pts[0])
		var gmin := 1e9
		for pp in pts:
			gmin = minf(gmin, terrain.height(pp.x, pp.y))
		kit.add(pts, h, kind, gmin, rng)
		count += 1
	print("buildings: ", count, ", triangles: ", kit.v.size() / 3)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/building.gdshader")
	mat.set_shader_parameter("ortho", load("res://assets/world/ortho.jpg"))
	for k in ["brick", "plaster", "roof", "metal", "concrete"]:
		mat.set_shader_parameter(k + "_col", load("res://assets/textures/%s_col.jpg" % k))
		mat.set_shader_parameter(k + "_nrm", load("res://assets/textures/%s_nrm.jpg" % k))
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, kit.arrays())
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	root.add_child(mi)
	# the roads, through the game's own loader (so the test sees exactly what the game builds)
	var sc := RealScenery.new()
	sc.terrain = terrain
	sc._load_roads()
	var rk := RoadKit.new()
	for c in sc.roads.keys():
		for rr in sc.roads[c]:
			var pts2: PackedVector2Array = rr[2]
			if pts2[0].distance_to(at) < R * 1.4:
				rk.add_run(rr[0], rr[1], pts2, rr[3], rr[4], terrain)
	var rmat := ShaderMaterial.new()
	rmat.shader = load("res://shaders/road.gdshader")
	rmat.set_shader_parameter("asphalt_col", load("res://assets/textures/asphalt_col.jpg"))
	rmat.set_shader_parameter("asphalt_nrm", load("res://assets/textures/asphalt_nrm.jpg"))
	if rk.v.size() > 0:
		var rmesh := ArrayMesh.new()
		rmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, rk.arrays())
		var rmi := MeshInstance3D.new()
		rmi.mesh = rmesh
		rmi.material_override = rmat
		root.add_child(rmi)
	print("road triangles: ", rk.v.size() / 3)
	var g0 := terrain.height(at.x, at.y)
	var A := Vector3(at.x, g0, at.y)
	var views := [["street", Vector3(-6, 1.7, 0), Vector3(30, 3, -25), 60.0], ["street2", Vector3(20, 1.7, 40), Vector3(-20, 4, 0), 60.0],
		["low", Vector3(-90, 35, 90), Vector3(0, 0, 0), 50.0], ["aerial", Vector3(-250, 160, 250), Vector3(0, 0, 0), 45.0]]
	for vw in views:
		var fr: Vector3 = vw[1]
		var to: Vector3 = vw[2]
		var fw := A + fr
		fw.y = terrain.height(fw.x, fw.z) + fr.y
		await _shot(vw[0], fw, A + to, vw[3])
	quit()
