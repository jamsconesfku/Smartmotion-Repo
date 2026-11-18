extends SceneTree
## Pictures of an aircraft on its own (not a check; needs a screen, e.g. xvfb-run), quick even on a slow computer:
##   godot --path godot --rendering-driver vulkan --script res://tests/shot_aircraft.gd -- --out=/tmp/air --key=fighter
## Options: --only=side,cockpit (which pictures), --size=1600x900.
var out := "/tmp/air"
var key := "fighter"
var only: Array = []
var cam: Camera3D
var plane: AircraftModel
var size := Vector2i(1600, 900)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--key="):
			key = a.substr(6)
		elif a.begins_with("--only="):
			only = Array(a.substr(7).split(","))
		elif a.begins_with("--size="):
			var p := a.substr(7).split("x")
			size = Vector2i(int(p[0]), int(p[1]))
	_run.call_deferred()


func _shot(name: String) -> void:
	if not only.is_empty() and not name in only:
		return
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s_%s.png" % [out, name])
	print("saved ", name)


func _look(from: Vector3, at: Vector3, fov := 40.0, near := 0.2) -> void:
	cam.global_transform = Transform3D(Basis.looking_at((at - from).normalized(), Vector3.UP), from)
	cam.fov = fov
	cam.near = near


func _run() -> void:
	root.get_viewport().size = size
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
	env.tonemap_exposure = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-42.0), deg_to_rad(-35.0), 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = load("res://assets/textures/grass_col.jpg")
	gm.uv1_scale = Vector3(80, 80, 1)
	gm.roughness = 0.95
	ground.material_override = gm
	root.add_child(ground)
	cam = Camera3D.new()
	cam.far = 2000.0
	root.add_child(cam)
	cam.current = true
	plane = AircraftModel.new()
	plane.build(key, null, true)
	VehicleLook.apply(plane, "aircraft")
	root.add_child(plane)
	plane.set_active(true)
	plane.set_cockpit_view(false)
	# sitting on its wheels (three-point for the tail-draggers)
	var sp: Dictionary = FlightModel.SPECS[key]
	var tilt := 0.0
	var h := -float(sp["gear"][0]["p"].y)
	if sp["tailDragger"]:
		var m: Vector3 = sp["gear"][0]["p"]
		var t: Vector3 = sp["gear"][2]["p"]
		tilt = atan2(t.y - m.y, t.z - m.z)
		h = -(m.y * cos(tilt) - m.z * sin(tilt))
	plane.position = Vector3(0, h, 0)
	plane.rotation = Vector3(tilt, 0, 0)
	plane.ctl = {"pitch": 0.0, "roll": 0.0, "yaw": 0.0, "throttle": 0.0, "flaps": 0.0, "flaps_pos": 0.0, "trim": 0.0}
	plane.update_visuals({"a": 0.0, "e": 0.0, "r": 0.0}, 0.0, 0.0, 0.0)
	var c := Vector3(0, 1.2, 0.8)
	# 1: from the right, as in Sam's photo (but on the ground)
	_look(Vector3(13.5, 1.9, -1.5), c + Vector3(0, -0.1, 0), 42.0)
	await _shot("side")
	_look(Vector3(-8.5, 2.3, -9.0), c, 45.0)
	await _shot("front34")
	_look(Vector3(7.0, 6.0, 12.0), c, 42.0)
	await _shot("rear34")
	_look(Vector3(0.0, 2.0, -11.0), c + Vector3(0, 0, 0), 45.0)
	await _shot("front")
	# close up of the nose, exhausts and cockpit
	_look(Vector3(3.6, 2.4, -3.4), Vector3(0, 1.9, -0.6), 40.0)
	await _shot("nose")
	# in flight, from below and from above (level, wheels down, flaps up)
	plane.position = Vector3(0, 14.0, 0)
	plane.rotation = Vector3(0.03, deg_to_rad(20.0), deg_to_rad(-25.0))
	_look(Vector3(5.0, 7.5, -12.0), plane.position + Vector3(0, 0, 0.5), 45.0)
	await _shot("below")
	_look(Vector3(-6.0, 26.0, 9.0), plane.position, 45.0)
	await _shot("above")
	# the cockpit, from the pilot's eye
	plane.position = Vector3(0, h, 0)
	plane.rotation = Vector3(tilt, 0, 0)
	plane.set_cockpit_view(true)
	var eye := plane.global_transform * plane.eye
	var b := plane.global_basis
	cam.global_transform = Transform3D(b * Basis.from_euler(Vector3(deg_to_rad(-16.0), 0, 0)), eye)
	cam.fov = 75.0
	cam.near = 0.03
	await _shot("cockpit")
	cam.global_transform = Transform3D(b * Basis.from_euler(Vector3(deg_to_rad(-38.0), deg_to_rad(55.0), 0)), eye)
	await _shot("cockpit_left")
	cam.global_transform = Transform3D(b * Basis.from_euler(Vector3(deg_to_rad(-26.0), deg_to_rad(-55.0), 0)), eye)
	await _shot("cockpit_right")
	quit()
