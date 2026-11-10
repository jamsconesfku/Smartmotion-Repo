class_name Telemetry
extends RefCounted
## Sends the flight data to the motion rig as JSON over UDP (about 60 frames a second).
## The frame has the same fields as the browser version, so tools/telemetry-bridge.mjs and any rig adapter work with both.

var udp := PacketPeerUDP.new()
var enabled := false
var host := "127.0.0.1"
var port := 4123
var status := "off"
var frame := {}
var _next := 0.0
var _sent := 0


func start(h: String, p: int) -> void:
	stop()
	host = h
	port = p
	var err := udp.connect_to_host(host, port)
	if err == OK:
		enabled = true
		status = "sending to %s:%d" % [host, port]
	else:
		enabled = false
		status = "cannot use %s:%d (error %d)" % [host, port, err]


func stop() -> void:
	udp.close()
	enabled = false
	status = "off"


static func make(fm: FlightModel, inp: Dictionary, t: float, paused: bool) -> Dictionary:
	var i: Dictionary = fm.i
	var KT := 1.94384
	var FT := 3.28084
	var vb := fm.q.inverse() * fm.vel
	var lat0 := 52.0908
	var lon0 := 0.1317
	var lat := lat0 - fm.pos.z / 111320.0
	var lon := lon0 + fm.pos.x / (111320.0 * cos(deg_to_rad(lat0)))
	var D2R := FlightModel.D2R
	var g := FlightModel.G
	return {
		"v": 1, "t": snappedf(t, 0.001), "aircraft": fm.spec["key"], "paused": paused, "crashed": fm.crashed,
		"pos": {"x": snappedf(fm.pos.x, 0.01), "y": snappedf(fm.pos.y, 0.01), "z": snappedf(fm.pos.z, 0.01)},
		"geo": {"lat": snappedf(lat, 0.000001), "lon": snappedf(lon, 0.000001), "alt_m": snappedf(fm.pos.y, 0.1)},
		"att": {"pitch_deg": snappedf(i["pitch"], 0.01), "roll_deg": snappedf(i["roll"], 0.01), "heading_deg": snappedf(i["heading"], 0.01)},
		"rate": {"roll_dps": snappedf(-fm.w.z / D2R, 0.01), "pitch_dps": snappedf(fm.w.x / D2R, 0.01), "yaw_dps": snappedf(-fm.w.y / D2R, 0.01)},
		"vel_body": {"surge": snappedf(-vb.z, 0.01), "sway": snappedf(vb.x, 0.01), "heave": snappedf(vb.y, 0.01)},
		"g_felt": {"surge": snappedf(-fm.spec_force.z / g, 0.001), "sway": snappedf(fm.spec_force.x / g, 0.001), "heave": snappedf(fm.spec_force.y / g, 0.001)},
		"ias_kt": snappedf(float(i["ias"]) * KT, 0.1), "tas_kt": snappedf(float(i["tas"]) * KT, 0.1), "gs_kt": snappedf(float(i["gs"]) * KT, 0.1),
		"alt_ft": round(float(i["alt_msl"]) * FT), "agl_ft": round(float(i["alt_agl"]) * FT), "vs_fpm": round(float(i["vs"]) * 196.85),
		"aoa_deg": snappedf(i["aoa"], 0.01), "slip_deg": snappedf(i["slip"], 0.01), "throttle": snappedf(i["throttle"], 0.001),
		"rpm": round(float(i["rpm"])), "flaps": snappedf(i["flaps"], 0.01), "on_ground": i["on_ground"], "stall": i["stall"],
		"controls": {"pitch": snappedf(inp["pitch"], 0.001), "roll": snappedf(inp["roll"], 0.001), "yaw": snappedf(inp["yaw"], 0.001)},
	}


func push(fm: FlightModel, inp: Dictionary, t: float, paused: bool) -> void:
	frame = make(fm, inp, t, paused)
	if enabled and t >= _next:
		_next = t + 1.0 / 60.0 - 0.002
		udp.put_packet(JSON.stringify(frame).to_utf8_buffer())
		_sent += 1


## Racing and Space send their own frame (same field names for the motion: att, rate, g_felt, vel_body).
func push_frame(f: Dictionary, t: float) -> void:
	frame = f
	if enabled and not f.is_empty() and t >= _next:
		_next = t + 1.0 / 60.0 - 0.002
		udp.put_packet(JSON.stringify(f).to_utf8_buffer())
		_sent += 1
