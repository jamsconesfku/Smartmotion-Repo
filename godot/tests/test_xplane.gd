extends SceneTree
## FlyPT Mover link checks (headless):  godot --headless --path godot --script res://tests/test_xplane.gd
## Pretends to be FlyPT Mover's X-Plane source: asks the game for values the way Mover asks X-Plane, and checks the answers.
var fails := 0


func check(name: String, ok: bool, info := "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("  " + info if info != "" else ""))
	if not ok:
		fails += 1


func frame(t: float, pitch: float, roll: float, hdg: float) -> Dictionary:
	return {
		"t": t, "paused": false, "crashed": false, "pos": {"x": 100.0, "y": 300.0, "z": -200.0},
		"att": {"pitch_deg": pitch, "roll_deg": roll, "heading_deg": hdg},
		"rate": {"roll_dps": 5.0, "pitch_dps": 2.0, "yaw_dps": -3.0},
		"vel_body": {"surge": 50.0, "sway": 0.0, "heave": 0.0},
		"g_felt": {"surge": 0.2, "sway": 0.0, "heave": 1.0},
		"ias_kt": 97.0, "alt_ft": 984.0, "agl_ft": 900.0, "throttle": 0.8, "rpm": 2500.0, "on_ground": false,
	}


func rref_req(hz: int, idx: int, path: String) -> PackedByteArray:
	var p := PackedByteArray("RREF".to_ascii_buffer())
	p.append(0)
	p.resize(5 + 8 + 400)
	p.encode_s32(5, hz)
	p.encode_s32(9, idx)
	var b := path.to_ascii_buffer()
	for i in b.size():
		p[13 + i] = b[i]
	return p


func _initialize() -> void:
	# 1. the orientation rebuilt from the frame's angles matches the game's own (GameMode.make_tel formulas)
	var worst := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in 200:
		var b0 := Basis.from_euler(Vector3(rng.randf_range(-1.4, 1.4), rng.randf_range(-3.1, 3.1), rng.randf_range(-3.1, 3.1)))
		var fwd := -b0.z
		var pitch := rad_to_deg(asin(clampf(fwd.y, -1.0, 1.0)))
		var roll := rad_to_deg(atan2(-b0.x.y, b0.y.y))
		var hdg := fposmod(rad_to_deg(atan2(fwd.x, -fwd.z)), 360.0)
		var b1 := XPlaneLink.basis_from(pitch, roll, hdg)
		for vec in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
			worst = maxf(worst, (b0 * vec - b1 * vec).length())
	check("orientation rebuilt from pitch/roll/heading", worst < 1e-3, "worst %.5f" % worst)

	# 2. values for level flight heading east, accelerating at 0.2 g
	var xp := XPlaneLink.new()
	var v := xp.values(frame(1.0, 0.0, 0.0, 90.0), 1.0)
	check("level flight: no vertical acceleration", absf(v["sim/flightmodel/position/local_ay"]) < 0.01, "%.3f" % v["sim/flightmodel/position/local_ay"])
	check("heading east: speed along +x", absf(v["sim/flightmodel/position/local_vx"] - 50.0) < 0.01, "%.2f" % v["sim/flightmodel/position/local_vx"])
	check("forward acceleration along +x", absf(v["sim/flightmodel/position/local_ax"] - 0.2 * 9.81) < 0.01, "%.3f" % v["sim/flightmodel/position/local_ax"])
	check("1 g normal", absf(v["sim/flightmodel/forces/g_nrml"] - 1.0) < 0.001)
	check("rates in deg/s and rad/s", absf(v["sim/flightmodel/position/P"] - 5.0) < 1e-6 and absf(v["sim/flightmodel/position/Prad"] - deg_to_rad(5.0)) < 1e-6)
	var v2 := xp.values(frame(1.0, 0.0, 0.0, 90.0), 2.0)   # same frame a second later: game paused or in the menu
	check("held still when the game stops sending", v2["sim/flightmodel/position/P"] == 0.0 and v2["sim/time/paused"] == 1.0 and absf(v2["sim/flightmodel/position/local_ax"]) < 1e-4)

	# 3. over the network, like Mover: RREF, DSEL and the fixed DATA output
	var port := 49170
	var out_port := 49171
	xp.start(port, "127.0.0.1", out_port)
	check("listening", xp.listening, xp.status)
	var data_rx := PacketPeerUDP.new()
	data_rx.bind(out_port, "127.0.0.1")
	var mover := PacketPeerUDP.new()
	mover.bind(49172, "127.0.0.1")
	mover.set_dest_address("127.0.0.1", port)
	mover.put_packet(rref_req(30, 0, "sim/flightmodel/position/theta"))
	mover.put_packet(rref_req(30, 1, "sim/flightmodel/position/phi"))
	mover.put_packet(rref_req(30, 2, "sim/flightmodel/position/local_ax"))
	mover.put_packet(rref_req(30, 3, "sim/flightmodel2/gear/on_ground[0]"))
	mover.put_packet(rref_req(30, 4, "sim/made/up/value"))
	var ds := PackedByteArray("DSEL".to_ascii_buffer())
	ds.append(0)
	ds.resize(9)
	ds.encode_s32(5, 17)
	mover.put_packet(ds)
	var got := {}
	var rows := {}
	var out_rows := {}
	var t := 0.0
	for k in 60:
		t += 1.0 / 60.0
		OS.delay_msec(4)
		xp.service(frame(t, 10.0, -20.0, 90.0), t)
		while mover.get_available_packet_count() > 0:
			var p := mover.get_packet()
			var head := p.slice(0, 4).get_string_from_ascii()
			if head == "RREF":
				var o := 5
				while o + 8 <= p.size():
					got[p.decode_s32(o)] = p.decode_float(o + 4)
					o += 8
			elif head == "DATA":
				var o := 5
				while o + 36 <= p.size():
					rows[p.decode_s32(o)] = [p.decode_float(o + 4), p.decode_float(o + 8)]
					o += 36
		while data_rx.get_available_packet_count() > 0:
			var p := data_rx.get_packet()
			var o := 5
			while o + 36 <= p.size():
				out_rows[p.decode_s32(o)] = p.decode_float(o + 4)
				o += 36
	check("Mover connected", xp.status.begins_with("CONNECTED"), xp.status)
	check("RREF pitch answered", got.has(0) and absf(got[0] - 10.0) < 1e-3, str(got.get(0)))
	check("RREF roll answered", got.has(1) and absf(got[1] + 20.0) < 1e-3, str(got.get(1)))
	check("RREF acceleration answered", got.has(2), str(got.get(2)))
	check("array dataref answered", got.has(3) and got[3] == 0.0)
	check("unknown dataref answered with 0", got.has(4) and got[4] == 0.0 and xp.unknown.has("sim/made/up/value"))
	check("DSEL row 17 (pitch, roll) sent", rows.has(17) and absf(rows[17][0] - 10.0) < 1e-3 and absf(rows[17][1] + 20.0) < 1e-3, str(rows.get(17)))
	check("DATA rows sent to the fixed address", out_rows.has(17) and out_rows.has(3) and out_rows.has(16), str(out_rows.keys()))
	# a request sent to the PC's network address (not 127.0.0.1), as Mover does, is answered too
	var lan := ""
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127."):
			lan = ip
	if lan != "":
		var m2 := PacketPeerUDP.new()
		m2.bind(49173, "*")
		m2.set_dest_address(lan, port)
		m2.put_packet(rref_req(20, 7, "sim/flightmodel/position/psi"))
		var ans := false
		for k in 30:
			t += 1.0 / 60.0
			OS.delay_msec(4)
			xp.service(frame(t, 10.0, -20.0, 90.0), t)
			while m2.get_available_packet_count() > 0:
				var p2 := m2.get_packet()
				if p2.slice(0, 4).get_string_from_ascii() == "RREF" and p2.decode_s32(5) == 7:
					ans = absf(p2.decode_float(9) - 90.0) < 1e-3
		check("request to the network address %s answered" % lan, ans)
	var bp := XPlaneLink.beacon_packet(49000)
	check("beacon packet", bp.slice(0, 4).get_string_from_ascii() == "BECN" and bp[5] == 1 and bp[6] == 2 and bp.decode_s32(7) == 1 and bp.decode_u16(19) == 49000, str(bp.size()))
	# stop: RREF at 0 Hz
	mover.put_packet(rref_req(0, 0, "sim/flightmodel/position/theta"))
	OS.delay_msec(10)
	xp.service(frame(t, 10.0, -20.0, 90.0), t + 1.0)
	check("RREF at 0 Hz stops that value", not xp.clients.values()[0]["refs"].has(0))
	xp.stop()
	print("FAILS: %d" % fails)
	quit(1 if fails > 0 else 0)
