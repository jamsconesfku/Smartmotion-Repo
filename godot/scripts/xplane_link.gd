class_name XPlaneLink
extends RefCounted
## Lets FlyPT Mover read the game through its "X-Plane 11 (UDP)" source, with no plug-in or bridge program:
## the game answers on the network the way X-Plane 11 does.
##  1. Listens on UDP 49000 (X-Plane's port) for Mover's requests and answers them:
##     RREF (subscribe to named values, "datarefs"), DSEL/USEL (DATA rows), RPOS (position packets).
##  2. Also sends X-Plane "DATA" rows to a fixed address (default 127.0.0.1:49001), like X-Plane's Data Output screen.
## Works for every game (Flight, Racing, Space, Coaster): it reads the same telemetry frame as the motion rig link.
## X-Plane axes: x east, y up, z south (the same as the game world); P/Q/R are roll/pitch/yaw rates.

const G := 9.81
const MAX_CLIENTS := 4
const UNUSED := -999.0
const DATA_ROWS := [1, 3, 4, 13, 14, 16, 17, 18, 20, 21, 25, 37]

var enabled := false
var listen := PacketPeerUDP.new()
var out := PacketPeerUDP.new()
var becn := PacketPeerUDP.new()  # X-Plane's "I'm here" beacon, which Mover uses to find X-Plane
var _next_becn := 0.0
var listen_port := 49000
var out_host := "127.0.0.1"
var out_port := 49001
var listening := false
var status := "off"
var dump: FileAccess        # test option --tel_dump=file.csv (see service)
var clients := {}          # "ip:port" -> {ip, port, refs: {index: [path, hz]}, next: {hz: time}, rows: [], rpos_hz, rpos_next}
var unknown := {}          # dataref names we were asked for but don't know (sent as 0)
var requests := 0
var sent := 0
var _next_data := 0.0
var _next_retry := 0.0
var _last_frame_t := -1.0
var _frame_seen_at := -99.0
var _prev_rates := Vector3.ZERO
var _rate_dot := Vector3.ZERO
var _dist := 0.0
var _vals := {}
var event := ""            # a message for the screen (main.gd shows it and clears it)
## Mover asks for data only once, when its X-Plane source connects. The game saves what it asked for here and
## carries on sending it after a restart (including the restart into VR), so Mover doesn't need reconnecting.
var save_path := "user://flypt_mover.json"
var restored := false
var _dirty := false
var _save_at := 0.0


func start(lport: int, ohost: String, oport: int) -> void:
	stop()
	enabled = true
	listen_port = lport
	out_host = ohost
	out_port = oport
	if out_port > 0:
		out.connect_to_host(out_host, out_port)
	becn.set_dest_address("239.255.1.1", 49707)
	_try_listen()
	if out_port > 0:
		status += "; DATA rows to port %d" % out_port
	_load()


## Picks up Mover's requests from the last time the game ran.
func _load() -> void:
	restored = false
	if save_path == "" or not FileAccess.file_exists(save_path):
		return
	var j = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not (j is Array):
		return
	for e in j:
		if not (e is Dictionary) or not e.has("ip"):
			continue
		var refs := {}
		var src: Dictionary = e.get("refs", {})
		for k in src:
			var r: Array = src[k]
			refs[int(k)] = [str(r[0]), int(r[1])]
		var rows: Array = []
		for r in e.get("rows", []):
			rows.append(int(r))
		if refs.is_empty() and rows.is_empty() and int(e.get("rpos_hz", 0)) <= 0:
			continue
		var key := "%s:%d" % [str(e["ip"]), int(e["port"])]
		clients[key] = {"ip": str(e["ip"]), "port": int(e["port"]), "refs": refs, "next": {}, "rows": rows,
			"rpos_hz": int(e.get("rpos_hz", 0)), "rpos_next": 0.0, "data_next": 0.0}
		restored = true
	if restored:
		status = "CONNECTED (remembered from last time), sending %d values to Mover" % (_count_refs() + _count_rows())
		Diag.write("FlyPT Mover: carrying on with the requests saved last time (%s)" % ", ".join(clients.keys()))


func _save() -> void:
	_dirty = false
	var names := []
	for k in clients:
		for idx in clients[k]["refs"]:
			names.append(str(clients[k]["refs"][idx][0]))
	if not names.is_empty():
		Diag.write("FlyPT Mover is reading: " + ", ".join(names))
	if save_path == "":
		return
	var out_list := []
	for k in clients:
		var c: Dictionary = clients[k]
		var refs := {}
		for idx in c["refs"]:
			refs[str(idx)] = c["refs"][idx]
		out_list.append({"ip": c["ip"], "port": c["port"], "refs": refs, "rows": c["rows"], "rpos_hz": c["rpos_hz"]})
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out_list))
		f.close()


## For the cockpit light: 0 off, 1 waiting for Mover, 2 Mover is reading the game.
func light() -> int:
	if not enabled:
		return 0
	return 2 if _count_refs() + _count_rows() > 0 or _rpos_on() else 1


func _rpos_on() -> bool:
	for k in clients:
		if int(clients[k]["rpos_hz"]) > 0:
			return true
	return false


func stop() -> void:
	listen.close()
	out.close()
	becn.close()
	listening = false
	enabled = false
	clients.clear()
	status = "off"


func _try_listen() -> void:
	# every address, not just 127.0.0.1: Mover sends its requests to the PC's network address or as a broadcast
	# (Windows may ask once whether to allow the game on the network: allow it)
	listen.set_broadcast_enabled(true)
	var err := listen.bind(listen_port, "*")
	listening = err == OK
	if listening:
		status = "waiting: Mover hasn't asked for data yet (port %d)" % listen_port
	else:
		status = "port %d is busy (is X-Plane running?), sending DATA rows only" % listen_port


## Called every frame. frame: the latest telemetry frame; now: seconds since start (real time).
func service(frame: Dictionary, now: float) -> void:
	if not enabled:
		return
	if not listening and now >= _next_retry:
		_next_retry = now + 5.0
		_try_listen()
	if listening and now >= _next_becn:
		_next_becn = now + 1.0
		becn.put_packet(beacon_packet(listen_port))
	_vals = values(frame, now)
	if dump != null and not frame.is_empty():
		# test option --tel_dump: one line per frame of what Mover's X-Plane source reads (for tuning Mover profiles)
		var fp := "sim/flightmodel/position/"
		var ff := "sim/flightmodel/forces/"
		dump.store_line("%.4f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.4f,%.4f,%.4f,%.3f,%.3f,%.3f,%.2f,%d,%d" % [float(frame.get("t", 0.0)),
			_vals[fp + "theta"], _vals[fp + "phi"], _vals[fp + "psi"], _vals[fp + "P"], _vals[fp + "Q"], _vals[fp + "R"],
			_vals[ff + "g_nrml"], _vals[ff + "g_axil"], _vals[ff + "g_side"], _vals[fp + "local_ax"], _vals[fp + "local_ay"], _vals[fp + "local_az"],
			_vals[fp + "groundspeed"], int(_vals["sim/flightmodel/failures/onground_any"]), int(_vals["sim/time/paused"])])
	if listening:
		while listen.get_available_packet_count() > 0:
			var pkt := listen.get_packet()
			if listen.get_packet_error() == OK:
				_on_request(pkt, listen.get_packet_ip(), listen.get_packet_port(), now)
	for key in clients:
		_serve_client(clients[key], now)
	if _dirty and now >= _save_at:
		_save()
	if out_port > 0 and now >= _next_data:
		_next_data = now + 1.0 / 30.0
		out.put_packet(data_packet(DATA_ROWS))


func _on_request(pkt: PackedByteArray, ip: String, port: int, now: float) -> void:
	if pkt.size() < 5:
		return
	var head := pkt.slice(0, 4).get_string_from_ascii()
	var c := _client(ip, port)
	requests += 1
	match head:
		"RREF":
			if pkt.size() < 13:
				return
			var hz := pkt.decode_s32(5)
			var idx := pkt.decode_s32(9)
			var path := pkt.slice(13).get_string_from_ascii().strip_edges()
			if hz <= 0:
				c["refs"].erase(idx)
			else:
				c["refs"][idx] = [path, hz]
				if not _known(path) and not unknown.has(path):
					unknown[path] = true
					Diag.write("FlyPT Mover asked for %s (not in the game, sent as 0)" % path)
		"DSEL", "USEL":
			var i := 5
			while i + 4 <= pkt.size():
				var row := pkt.decode_s32(i)
				i += 4
				if head == "DSEL" and not c["rows"].has(row):
					c["rows"].append(row)
				elif head == "USEL":
					c["rows"].erase(row)
		"RPOS":
			c["rpos_hz"] = pkt.slice(5).get_string_from_ascii().to_int()
		_:
			Diag.write("FlyPT Mover sent a %s request (ignored)" % head)
	status = "CONNECTED, Mover is reading %d values" % (_count_refs() + _count_rows())
	if not _dirty:
		_dirty = true
		_save_at = now + 1.0    # save once the burst of requests is over


func _client(ip: String, port: int) -> Dictionary:
	var key := "%s:%d" % [ip, port]
	if not clients.has(key):
		# Mover reconnected from a new port: forget its old one (from this run or remembered from the last)
		for k in clients.keys():
			if clients[k]["ip"] == ip:
				clients.erase(k)
		if clients.size() >= MAX_CLIENTS:
			clients.erase(clients.keys()[0])
		event = "FlyPT Mover connected: it is reading the game"
		clients[key] = {"ip": ip, "port": port, "refs": {}, "next": {}, "rows": [], "rpos_hz": 0, "rpos_next": 0.0, "data_next": 0.0}
		Diag.write("FlyPT Mover connected from %s" % key)
	return clients[key]


func _count_refs() -> int:
	var n := 0
	for k in clients:
		n += clients[k]["refs"].size()
	return n


func _count_rows() -> int:
	var n := 0
	for k in clients:
		n += clients[k]["rows"].size()
	return n


func _serve_client(c: Dictionary, now: float) -> void:
	listen.set_dest_address(c["ip"], c["port"])
	# RREF answers, grouped by the rate each value was asked for
	var by_hz := {}
	for idx in c["refs"]:
		var r: Array = c["refs"][idx]
		var hz: int = mini(int(r[1]), 100)
		if not by_hz.has(hz):
			by_hz[hz] = []
		by_hz[hz].append(idx)
	for hz in by_hz:
		var nt: float = c["next"].get(hz, 0.0)
		if now < nt:
			continue
		c["next"][hz] = maxf(nt + 1.0 / hz, now - 0.05)
		var idxs: Array = by_hz[hz]
		var i := 0
		while i < idxs.size():
			var part := idxs.slice(i, i + 150)
			i += 150
			var p := PackedByteArray("RREF,".to_ascii_buffer())
			p.resize(5 + part.size() * 8)
			var o := 5
			for idx in part:
				p.encode_s32(o, int(idx))
				p.encode_float(o + 4, value(str(c["refs"][idx][0])))
				o += 8
			listen.put_packet(p)
			sent += 1
	if not c["rows"].is_empty() and now >= float(c["data_next"]):
		c["data_next"] = now + 1.0 / 30.0
		listen.put_packet(data_packet(c["rows"]))
	if int(c["rpos_hz"]) > 0 and now >= float(c["rpos_next"]):
		c["rpos_next"] = now + 1.0 / float(c["rpos_hz"])
		listen.put_packet(rpos_packet())


# ---------------------------------------------------------------- values

## The value of one dataref ("sim/flightmodel/position/theta", or with an array index like "...[0]").
func value(path: String) -> float:
	var p := path
	var b := p.find("[")
	if b >= 0:
		p = p.substr(0, b)
	return float(_vals.get(p, 0.0))


func _known(path: String) -> bool:
	var p := path
	var b := p.find("[")
	if b >= 0:
		p = p.substr(0, b)
	return _vals.has(p)


## Orientation of the vehicle from the frame's angles (inverse of GameMode.make_tel / FlightModel).
static func basis_from(pitch_deg: float, roll_deg: float, hdg_deg: float) -> Basis:
	return Basis(Vector3.UP, deg_to_rad(-hdg_deg)) * Basis(Vector3.RIGHT, deg_to_rad(pitch_deg)) * Basis(Vector3.BACK, deg_to_rad(-roll_deg))


static func _f(d: Dictionary, k: String, def := 0.0) -> float:
	var v = d.get(k)
	return def if v == null else float(v)


## Works out the X-Plane values from a telemetry frame.
func values(frame: Dictionary, now: float) -> Dictionary:
	var f := frame
	var att: Dictionary = f.get("att", {})
	var rate: Dictionary = f.get("rate", {})
	var gf: Dictionary = f.get("g_felt", {})
	var vbd: Dictionary = f.get("vel_body", {})
	var pos: Dictionary = f.get("pos", {})
	var t := _f(f, "t", -1.0)
	if t != _last_frame_t:
		var dtf := t - _last_frame_t
		_last_frame_t = t
		_frame_seen_at = now
		var rv := Vector3(_f(rate, "roll_dps"), _f(rate, "pitch_dps"), _f(rate, "yaw_dps"))
		if dtf > 0.0 and dtf < 0.2:
			_rate_dot = _rate_dot.lerp((rv - _prev_rates) / dtf, 0.3)
		_prev_rates = rv
	var live := now - _frame_seen_at < 0.3 and not bool(f.get("paused", false)) and not f.is_empty()
	var pitch := _f(att, "pitch_deg")
	var roll := _f(att, "roll_deg")
	var hdg := _f(att, "heading_deg")
	var b := basis_from(pitch, roll, hdg)
	var vb := Vector3(_f(vbd, "sway"), _f(vbd, "heave"), -_f(vbd, "surge"))
	var vw := b * vb
	var gb := Vector3(_f(gf, "sway"), _f(gf, "heave", 1.0), -_f(gf, "surge"))
	# a game may add to the rates Mover sees (the coaster does: see coaster_mode.gd _tel)
	var cue: Dictionary = f.get("mover_cue", {})
	var P := _f(rate, "roll_dps") + _f(cue, "roll_dps")
	var Q := _f(rate, "pitch_dps") + _f(cue, "pitch_dps")
	var R := _f(rate, "yaw_dps")
	var rd := _rate_dot
	if not live:
		# paused, crashed out or no game running: hold still so the rig settles
		gb = b.inverse() * Vector3.UP   # 1 g straight up, seen from the seat
		vw = Vector3.ZERO
		vb = Vector3.ZERO
		P = 0.0
		Q = 0.0
		R = 0.0
		rd = Vector3.ZERO
	# road feel for FlyPT Mover (racing): a shake in the vertical force on kerbs, gravel and grass, stronger with speed
	var amp: float = {"kerb": 0.12, "gravel": 0.08, "grass": 0.05}.get(str(f.get("surface", "")), 0.0)
	if live and amp > 0.0:
		gb.y += amp * clampf(vw.length() / 15.0, 0.0, 1.0) * randf_range(-1.0, 1.0)
	var aw := b * (gb * G) + Vector3(0, -G, 0)
	var px := _f(pos, "x")
	var py := _f(pos, "y")
	var pz := _f(pos, "z")
	var geo: Dictionary = f.get("geo", {})
	var lat := _f(geo, "lat", 52.0908 - pz / 111320.0)
	var lon := _f(geo, "lon", 0.1317 + px / (111320.0 * cos(deg_to_rad(52.0908))))
	var spd := vw.length()
	var ias_kt := _f(f, "ias_kt", spd * 1.94384)
	var tas_kt := _f(f, "tas_kt", ias_kt)
	var gs_kt := _f(f, "gs_kt", Vector2(vw.x, vw.z).length() * 1.94384)
	var alt_ft := _f(f, "alt_ft", py * 3.28084)
	var agl_ft := _f(f, "agl_ft", alt_ft)
	var vs_fpm := _f(f, "vs_fpm", vw.y * 196.85) if live else 0.0
	var aoa := _f(f, "aoa_deg")
	var slip := _f(f, "slip_deg")
	var thr := _f(f, "throttle")
	var rpm := _f(f, "rpm")
	var flaps := _f(f, "flaps")
	var on_ground := 1.0 if bool(f.get("on_ground", false)) else 0.0
	var hpath := fposmod(rad_to_deg(atan2(vw.x, -vw.z)), 360.0) if Vector2(vw.x, vw.z).length() > 0.5 else hdg
	var vpath := rad_to_deg(atan2(vw.y, Vector2(vw.x, vw.z).length())) if spd > 0.5 else 0.0
	if live:
		_dist += spd / 60.0
	var paused := 0.0 if live else 1.0
	var D2R := PI / 180.0
	var fp := "sim/flightmodel/position/"
	var v := {
		fp + "theta": pitch, fp + "phi": roll, fp + "psi": hdg, fp + "magpsi": hdg,
		fp + "true_theta": pitch, fp + "true_phi": roll, fp + "true_psi": hdg, fp + "mag_psi": hdg,
		fp + "P": P, fp + "Q": Q, fp + "R": R,
		fp + "Prad": P * D2R, fp + "Qrad": Q * D2R, fp + "Rrad": R * D2R,
		fp + "P_dot": rd.x, fp + "Q_dot": rd.y, fp + "R_dot": rd.z,
		fp + "local_x": px, fp + "local_y": py, fp + "local_z": pz,
		fp + "local_vx": vw.x, fp + "local_vy": vw.y, fp + "local_vz": vw.z,
		fp + "local_ax": aw.x, fp + "local_ay": aw.y, fp + "local_az": aw.z,
		fp + "latitude": lat, fp + "longitude": lon, fp + "elevation": alt_ft / 3.28084, fp + "y_agl": agl_ft / 3.28084,
		fp + "indicated_airspeed": ias_kt, fp + "indicated_airspeed2": ias_kt, fp + "equivalent_airspeed": ias_kt,
		fp + "true_airspeed": tas_kt / 1.94384, fp + "groundspeed": gs_kt / 1.94384,
		fp + "vh_ind": vs_fpm / 196.85, fp + "vh_ind_fpm": vs_fpm, fp + "vh_ind_fpm2": vs_fpm,
		fp + "alpha": aoa, fp + "beta": slip, fp + "vpath": vpath, fp + "hpath": hpath,
		fp + "M": 0.0, fp + "N": 0.0, fp + "L": 0.0,
		"sim/flightmodel/misc/h_ind": alt_ft, "sim/flightmodel/misc/h_ind2": alt_ft, "sim/flightmodel/misc/machno": tas_kt / 661.5,
		"sim/flightmodel/misc/slip": slip,
		"sim/flightmodel/forces/g_nrml": gb.y, "sim/flightmodel/forces/g_axil": gb.z, "sim/flightmodel/forces/g_side": gb.x,
		"sim/flightmodel/forces/vx_acf_axis": vb.x, "sim/flightmodel/forces/vy_acf_axis": vb.y, "sim/flightmodel/forces/vz_acf_axis": vb.z,
		"sim/flightmodel/forces/faxil_total": 0.0, "sim/flightmodel/forces/fside_total": 0.0, "sim/flightmodel/forces/fnrml_total": 0.0,
		"sim/flightmodel/failures/onground_any": on_ground, "sim/flightmodel/failures/onground_all": on_ground,
		"sim/flightmodel2/gear/on_ground": on_ground, "sim/flightmodel/forces/gear_on_ground": on_ground,
		"sim/flightmodel2/misc/has_crashed": 1.0 if bool(f.get("crashed", false)) else 0.0,
		"sim/flightmodel/engine/ENGN_thro": thr, "sim/flightmodel/engine/ENGN_thro_use": thr,
		"sim/cockpit2/engine/actuators/throttle_ratio": thr, "sim/cockpit2/engine/actuators/throttle_ratio_all": thr,
		"sim/flightmodel/engine/ENGN_tacrad": rpm * TAU / 60.0, "sim/flightmodel/engine/POINT_tacrad": rpm * TAU / 60.0,
		"sim/cockpit2/engine/indicators/engine_speed_rpm": rpm, "sim/cockpit2/engine/indicators/prop_speed_rpm": rpm,
		"sim/flightmodel/engine/ENGN_running": 1.0 if rpm > 100.0 else 0.0,
		"sim/flightmodel/controls/flaprat": flaps, "sim/flightmodel/controls/flap_handle_deploy_ratio": flaps,
		"sim/cockpit2/controls/flap_ratio": flaps, "sim/flightmodel2/controls/flap_handle_deploy_ratio": flaps,
		"sim/aircraft/parts/acf_gear_deploy": 1.0, "sim/flightmodel2/gear/deploy_ratio": 1.0, "sim/cockpit/switches/gear_handle_status": 1.0,
		"sim/time/paused": paused, "sim/time/sim_speed": 0.0 if paused > 0.0 else 1.0, "sim/time/sim_speed_actual": 0.0 if paused > 0.0 else 1.0,
		"sim/time/total_running_time_sec": now, "sim/time/total_flight_time_sec": maxf(t, 0.0),
		"sim/time/framerate_period": 1.0 / 60.0, "sim/operation/misc/frame_rate_period": 1.0 / 60.0,
		"sim/time/ground_speed": 0.0 if paused > 0.0 else 1.0,
		"sim/version/xplane_internal_version": 115000.0, "sim/version/xplane_major_version": 11.0,
		"sim/aircraft/weight/acf_m_empty": 800.0, "sim/flightmodel/weight/m_total": 1000.0,
		"sim/weather/wind_speed_kt": 0.0, "sim/weather/wind_direction_degt": 0.0,
	}
	# for DATA rows / RPOS
	v["_dist_ft"] = _dist * 3.28084
	return v


# ---------------------------------------------------------------- packets

func data_packet(rows: Array) -> PackedByteArray:
	var p := PackedByteArray("DATA*".to_ascii_buffer())
	p.resize(5 + rows.size() * 36)
	var o := 5
	for row in rows:
		var vals := _row(int(row))
		p.encode_s32(o, int(row))
		for i in 8:
			p.encode_float(o + 4 + i * 4, float(vals[i]) if i < vals.size() else UNUSED)
		o += 36
	return p


func _row(n: int) -> Array:
	var fp := "sim/flightmodel/position/"
	var X := UNUSED
	var ias := value(fp + "indicated_airspeed")
	var tas := value(fp + "true_airspeed") * 1.94384
	var gs := value(fp + "groundspeed") * 1.94384
	var thr := value("sim/cockpit2/engine/actuators/throttle_ratio_all")
	var rpm := value("sim/cockpit2/engine/indicators/engine_speed_rpm")
	match n:
		0:
			return [60.0, 60.0, 1.0 / 60.0, X, X, X, X, X]
		1:
			var tt := value("sim/time/total_running_time_sec")
			return [tt, tt, value("sim/time/total_flight_time_sec"), 0.0, X, 0.0, 0.0, 0.0]
		3:
			return [ias, ias, tas, gs, X, ias * 1.15078, tas * 1.15078, gs * 1.15078]
		4:
			return [value("sim/flightmodel/misc/machno"), X, value(fp + "vh_ind_fpm"), X,
				value("sim/flightmodel/forces/g_nrml"), value("sim/flightmodel/forces/g_axil"), value("sim/flightmodel/forces/g_side"), X]
		13:
			var fl := value("sim/flightmodel/controls/flaprat")
			return [0.0, 0.0, 0.0, fl, fl, 0.0, 0.0, 0.0]
		14:
			return [1.0, 0.0, 0.0, 0.0, X, X, X, X]
		16:
			return [value(fp + "Qrad"), value(fp + "Prad"), value(fp + "Rrad"), X, X, X, X, X]
		17:
			return [value(fp + "theta"), value(fp + "phi"), value(fp + "psi"), value(fp + "magpsi"), X, X, X, X]
		18:
			return [value(fp + "alpha"), value(fp + "beta"), value(fp + "hpath"), value(fp + "vpath"), X, X, X, value(fp + "beta")]
		20:
			var lat := value(fp + "latitude")
			var lon := value(fp + "longitude")
			return [lat, lon, value("sim/flightmodel/misc/h_ind"), value(fp + "y_agl") * 3.28084,
				value("sim/flightmodel/failures/onground_any"), value("sim/flightmodel/misc/h_ind"), lat, lon]
		21:
			var d := value("_dist_ft")
			return [value(fp + "local_x"), value(fp + "local_y"), value(fp + "local_z"),
				value(fp + "local_vx"), value(fp + "local_vy"), value(fp + "local_vz"), d, d / 6076.12]
		25, 26:
			return [thr, X, X, X, X, X, X, X]
		37:
			return [rpm, X, X, X, X, X, X, X]
	return []


## X-Plane 11's network beacon (BECN, sent to 239.255.1.1:49707 once a second): "X-Plane 11.55, master, on port 49000".
static func beacon_packet(port: int) -> PackedByteArray:
	var name := "SmartMotion".to_ascii_buffer()
	var p := PackedByteArray("BECN".to_ascii_buffer())
	p.append(0)
	p.append(1)                # beacon major version
	p.append(2)                # beacon minor version
	var o := p.size()
	p.resize(o + 4 + 4 + 4 + 2)
	p.encode_s32(o, 1)         # application: 1 = X-Plane
	p.encode_s32(o + 4, 115501)
	p.encode_u32(o + 8, 1)     # role: 1 = master
	p.encode_u16(o + 12, port)
	p.append_array(name)
	p.append(0)
	o = p.size()
	p.resize(o + 2)
	p.encode_u16(o, 49010)     # raknet port (not used)
	return p


## X-Plane's RPOS answer: position, attitude, world velocity and body rates.
func rpos_packet() -> PackedByteArray:
	var fp := "sim/flightmodel/position/"
	var p := PackedByteArray("RPOS4".to_ascii_buffer())
	p.resize(5 + 24 + 40)
	p.encode_double(5, value(fp + "longitude"))
	p.encode_double(13, value(fp + "latitude"))
	p.encode_double(21, value(fp + "elevation"))
	var fl := [value(fp + "y_agl"), value(fp + "theta"), value(fp + "psi"), value(fp + "phi"),
		value(fp + "local_vx"), value(fp + "local_vy"), value(fp + "local_vz"),
		value(fp + "Prad"), value(fp + "Qrad"), value(fp + "Rrad")]
	for i in fl.size():
		p.encode_float(29 + i * 4, float(fl[i]))
	return p
