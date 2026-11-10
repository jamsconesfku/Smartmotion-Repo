class_name MotionEngine
extends RefCounted
## The motion loop, on its own thread so the screen never slows it down:
## read the game's data -> cueing (500 steps a second) -> send the seat position to the controller about every 2 ms,
## and send the same position back to the game (VR motion compensation).
## The screen talks to it only through request() and snapshot().

var cue := Cueing.new()
var link := RigLink.new()
var mutex := Mutex.new()

var _thread: Thread
var _run := false
var _cmds: Array[Callable] = []
var _game := PacketPeerUDP.new()
var _comp := PacketPeerUDP.new()
var _frame := {}
var _frame_us := 0
var _test := {}
var _parking := false
var _snap := {}
var game_port := 4123
var listen_error := ""


func start(gport: int, cport: int) -> void:
	game_port = gport
	var err := _game.bind(gport, "*")
	listen_error = "" if err == OK else "Cannot listen on port %d (is another copy of SmartMotion Motion, or FlyPT Mover, already running?)" % gport
	_comp.set_dest_address("127.0.0.1", cport)
	_run = true
	_thread = Thread.new()
	_thread.start(_loop)


func stop() -> void:
	_run = false
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	link.close()
	_game.close()
	_comp.close()


## Runs f on the motion thread at its next step.
func request(f: Callable) -> void:
	mutex.lock()
	_cmds.append(f)
	mutex.unlock()


func set_test(values: Dictionary) -> void:
	mutex.lock()
	_test = values.duplicate()
	mutex.unlock()


func snapshot() -> Dictionary:
	mutex.lock()
	var s := _snap.duplicate(true)
	mutex.unlock()
	return s


# ---- actions (call through request) ----

func park() -> void:
	cue.want_on = false
	_parking = true


func emergency() -> void:
	cue.want_on = false
	_parking = false
	for i in 3:
		link.send_command(RigLink.CMD_EMERGENCY, 1)


## True when the rig is really following our positions (so VR should cancel its movement out).
func rig_live() -> bool:
	if not link.connected or cue.scale <= 0.0:
		return false
	return link.rig_state < 0 or (link.rig_state >= 15 and link.rig_state <= 20)


func _loop() -> void:
	var next := Time.get_ticks_usec()
	var last_q := 0
	var last_comp := 0
	var last_snap := 0
	var rate_t := next
	var n_loops := 0
	var n_frames := 0
	var loop_hz := 0.0
	var frame_hz := 0.0
	while _run:
		mutex.lock()
		var cmds := _cmds
		_cmds = []
		var test := _test
		mutex.unlock()
		for f in cmds:
			f.call()
		while _game.get_available_packet_count() > 0:
			var j = JSON.parse_string(_game.get_packet().get_string_from_utf8())
			if j is Dictionary:
				_frame = j
				_frame_us = Time.get_ticks_usec()
				n_frames += 1
		var now := Time.get_ticks_usec()
		var age := (now - _frame_us) / 1e6 if _frame_us > 0 else 999.0
		var steps := 0
		while next <= now and steps < 25:
			cue.step(_frame, age, test)
			next += 2000
			steps += 1
		if steps >= 25:
			next = now + 2000   # fell behind (the PC was busy): carry on from now
		if steps > 0:
			link.send_pose(cue.pose, cue.belt)
			n_loops += 1
		link.poll()
		if link.mode == RigLink.Mode.USB and link.connected and now - last_q > 250000:
			link.send_command(RigLink.CMD_STATUS, 0)
			if link.firmware == "":
				link.send_command(RigLink.CMD_FIRMWARE, 0)
			last_q = now
		if _parking and cue.scale <= 0.0 and cue.at_rest():
			link.send_command(RigLink.CMD_ONLINE, 1)
			_parking = false
		if now - last_comp > 10000:
			var p := {"v": 1, "live": rig_live()}
			for a in Cueing.AXES:
				p[a] = snappedf(float(cue.pose[a]), 0.01)
			_comp.put_packet(JSON.stringify(p).to_utf8_buffer())
			last_comp = now
		if now - rate_t > 1000000:
			loop_hz = n_loops * 1e6 / (now - rate_t)
			frame_hz = n_frames * 1e6 / (now - rate_t)
			n_loops = 0
			n_frames = 0
			rate_t = now
		if now - last_snap > 20000:
			last_snap = now
			mutex.lock()
			_snap = {
				"pose": cue.pose.duplicate(), "target": cue.target.duplicate(), "belt": cue.belt, "scale": cue.scale,
				"want_on": cue.want_on, "reason": cue.reason, "link": link.status, "connected": link.connected,
				"mode": link.mode, "rig_state": link.rig_state, "sent": link.sent, "loop_hz": loop_hz, "frame_hz": frame_hz,
				"age": age, "parking": _parking, "live": rig_live(),
				"game": {"aircraft": _frame.get("aircraft", ""), "ias_kt": _frame.get("ias_kt", 0), "on_ground": _frame.get("on_ground", false),
					"paused": _frame.get("paused", false), "crashed": _frame.get("crashed", false)},
			}
			mutex.unlock()
		# sleep until the next 2 ms slot (Windows sleeps in whole milliseconds, then Godot waits out the rest exactly)
		OS.delay_usec(2100 if OS.get_name() == "Windows" else maxi(100, next - Time.get_ticks_usec()))
