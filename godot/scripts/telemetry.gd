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
var xp := XPlaneLink.new()   # FlyPT Mover reads the game as if it were X-Plane 11


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


## v1.22.0, for FlyPT Mover (Sam: "the planes need to produce more movement"). Mover's AIR pose leans the seat
## with the turn rates, so in a steady turn or climb the seat soon drifts back to level and gentle flying hardly
## moves the rig. As the coaster does (coaster_mode.gd), the aircraft now adds to the rates Mover reads a pull
## towards its own bank and pitch (fading over CUE_FADE seconds, so the seat leans into a turn and settles back
## slowly), a tilt back with the g of a pull-up, and a lean with any sideways force. Off on the ground (Mover's
## GROUND pose does the runway). SmartMotion Motion still gets the real rates.
const CUE_GAIN := 1.8      # degrees a second of extra turn rate per degree of bank or pitch
const CUE_G := 7.0         # ... of pitch rate per g above 1 (pulling g tips the seat back)
const CUE_SIDE := 30.0     # ... of roll rate per g of sideways force
const CUE_FADE := 6.0      # seconds for the extra lean to fade in a steady turn or climb
var cue_lp := Vector2.ZERO
var cue_out := Vector2.ZERO
var _cue_t := -1.0


func _aircraft_cue(fm: FlightModel, t: float, paused: bool) -> Dictionary:
	var dt := clampf(t - _cue_t, 0.0, 0.1) if _cue_t >= 0.0 else 0.0
	_cue_t = t
	var i: Dictionary = fm.i
	var air := not bool(i["on_ground"]) and not fm.crashed and not paused
	if dt <= 0.0:
		return {"roll_dps": snappedf(cue_out.x, 0.01), "pitch_dps": snappedf(cue_out.y, 0.01)}
	if air:
		# like degrees for small angles and smooth all the way round a roll or a loop
		var bank := 57.3 * sin(deg_to_rad(float(i["roll"])))
		var nose := 57.3 * sin(deg_to_rad(float(i["pitch"])))
		cue_lp = cue_lp.lerp(Vector2(bank, nose), 1.0 - exp(-dt / CUE_FADE))
		var g_up := fm.spec_force.y / FlightModel.G
		var g_side := fm.spec_force.x / FlightModel.G
		var want := Vector2(CUE_GAIN * (bank - cue_lp.x) + CUE_SIDE * g_side, CUE_GAIN * (nose - cue_lp.y) + CUE_G * clampf(g_up - 1.0, -1.5, 4.0))
		want = Vector2(40.0 * tanh(want.x / 40.0), 40.0 * tanh(want.y / 40.0))   # eased towards 40 degrees a second
		cue_out = cue_out.lerp(want, 1.0 - exp(-dt / 0.25))                       # smoothed over a quarter second
	else:
		cue_lp = Vector2.ZERO
		cue_out = cue_out.lerp(Vector2.ZERO, 1.0 - exp(-dt / 0.25))
	return {"roll_dps": snappedf(cue_out.x, 0.01), "pitch_dps": snappedf(cue_out.y, 0.01)}


func push(fm: FlightModel, inp: Dictionary, t: float, paused: bool) -> void:
	frame = make(fm, inp, t, paused)
	frame["mover_cue"] = _aircraft_cue(fm, t, paused)
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


## Called every frame (also in menus and pauses): answers FlyPT Mover.
func service() -> void:
	xp.service(frame, Time.get_ticks_msec() / 1000.0)
