class_name RigLink
extends RefCounted
## Talks to the Motion4Sim controller (docs.motion4sim.com, firmware 5.4x).
##  * Motion: "Position mode" packets, 36 bytes: <252><252> sway surge heave (mm) yaw roll pitch (degrees) as 32-bit floats,
##    belt and wind as 32-bit whole numbers (0 = off, 0xFFFFFFFF = full), then <10><13>. Low byte first.
##    The controller works out each actuator's length itself from the rig measurements stored on it.
##  * Commands: 8 bytes, <249><249> command (2 bytes) value (2 bytes) <10><13>, low byte first.
##  * Two ways to connect: USB (a COM port, 250,000 baud, works on every controller) or the network cable
##    (UDP to the controller's address, port 53241; needs the controller's Pro licence).
## Windows has no serial port access in Godot, so USB goes through a small helper run by Windows PowerShell
## (assets/serial_bridge.ps1): it copies bytes from this program to the COM port and back.

enum Mode { DRY_RUN, USB, NETWORK }

# Command numbers. The manual writes them as they go down the cable, low byte first ("0600" = command 0x0006).
const CMD_STATUS := 0x0000      # "0000"
const CMD_FIRMWARE := 0x0002    # "0200"
const CMD_EMERGENCY := 0x0005   # "0500": value 1 = on, 0 = off
const CMD_ONLINE := 0x0006      # "0600": value 0 = go online, 1 = go offline (park)
const CMD_SHUTDOWN := 0x0007    # "0700"
const CMD_START := 0x0080       # "8000": start homing and go online, instead of pressing the controller's knob
const CMD_GAIN := 0x0031        # "3100"

const STATES := {
	0: "starting up", 1: "preparing", 2: "preparing", 3: "preparing to park", 4: "preparing to park",
	5: "moving to park", 6: "moving to park", 7: "parked (offline)", 8: "parked (offline)",
	9: "parked, homing the belt", 10: "parked, homing the belt", 11: "going online", 12: "going online",
	13: "moving to online", 14: "moving to online", 15: "online, waiting for data", 16: "online, waiting for data",
	17: "online, moving", 18: "online, moving", 19: "online, data paused", 20: "online, data paused",
	21: "going to park", 22: "going to park", 23: "moving to park", 24: "moving to park",
	25: "park, switching online", 26: "park, switching online", 27: "shutting down", 28: "shutting down",
	29: "service mode", 30: "service mode", 31: "EMERGENCY STOP", 32: "EMERGENCY STOP",
	33: "ACTUATOR ERROR", 34: "ACTUATOR ERROR", 255: "waiting to start (press Start rig)",
}

var mode: int = Mode.DRY_RUN
var connected := false
var status := "dry run: nothing is sent to the rig"
var rig_state := -1           # last state number the controller reported (USB only), -1 = unknown
var firmware := ""
var invert := {"sway": false, "surge": false, "heave": false, "yaw": false, "roll": false, "pitch": false}
var sent := 0
var errors := 0

var _udp := PacketPeerUDP.new()
var _pipe: FileAccess
var _pid := -1
var _reader: Thread
var _rx_mutex := Mutex.new()
var _rx := PackedByteArray()
var _alive := false
var _closed_msg := ""         # set by the reader thread, applied by poll()


static func pose_packet(pose: Dictionary, belt: float, wind := 0.0, inv := {}) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.big_endian = false
	b.put_u8(252)
	b.put_u8(252)
	for a in ["sway", "surge", "heave", "yaw", "roll", "pitch"]:
		var v := float(pose.get(a, 0.0))
		if bool(inv.get(a, false)):
			v = -v
		b.put_float(v)
	b.put_u32(int(clampf(belt, 0.0, 1.0) * 4294967295.0))
	b.put_u32(int(clampf(wind, 0.0, 1.0) * 4294967295.0))
	b.put_u8(10)
	b.put_u8(13)
	return b.data_array


static func command_frame(cmd: int, value: int) -> PackedByteArray:
	return PackedByteArray([249, 249, cmd & 0xFF, (cmd >> 8) & 0xFF, value & 0xFF, (value >> 8) & 0xFF, 10, 13])


## Finds 8-byte replies (<249><249> cmd value <10><13>) in bytes from the controller. Returns [[cmd, value], ...]
## and leaves any unfinished bytes in buf. Other frames (log text, display) are skipped.
static func parse_replies(buf: PackedByteArray) -> Array:
	var out := []
	var i := 0
	while i + 8 <= buf.size():
		if buf[i] == 249 and buf[i + 1] == 249 and buf[i + 6] == 10 and buf[i + 7] == 13:
			out.append([buf[i + 2] | (buf[i + 3] << 8), buf[i + 4] | (buf[i + 5] << 8)])
			i += 8
		else:
			i += 1
	var rest := buf.slice(i)
	buf.resize(rest.size())
	for j in rest.size():
		buf[j] = rest[j]
	return out


static func state_text(n: int) -> String:
	return str(STATES.get(n, "state %d" % n))


func open_network(ip: String, port: int) -> void:
	close()
	mode = Mode.NETWORK
	var err := _udp.connect_to_host(ip, port)
	connected = err == OK
	status = ("network: sending to %s port %d" % [ip, port]) if connected else ("network: cannot use %s:%d (error %d)" % [ip, port, err])


func open_usb(port_name: String, baud: int, helper_path: String) -> void:
	close()
	mode = Mode.USB
	if OS.get_name() != "Windows":
		status = "USB only works on Windows"
		return
	var r := OS.execute_with_pipe("powershell.exe", ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", helper_path, port_name, str(baud)])
	if r.is_empty():
		status = "USB: could not start Windows PowerShell"
		return
	_pipe = r["stdio"]
	_pid = int(r["pid"])
	_alive = true
	connected = true
	status = "USB: opening %s..." % port_name
	_reader = Thread.new()
	_reader.start(_read_loop.bind(r["stderr"] as FileAccess, port_name))


func _read_loop(err_pipe: FileAccess, port_name: String) -> void:
	while _alive and _pipe != null and _pipe.is_open():
		var chunk := _pipe.get_buffer(64)
		if chunk.is_empty():
			if not OS.is_process_running(_pid):
				break
			OS.delay_msec(5)
			continue
		_rx_mutex.lock()
		_rx.append_array(chunk)
		_rx_mutex.unlock()
	if _alive:
		var msg := ""
		if err_pipe != null and err_pipe.is_open():
			msg = err_pipe.get_buffer(2000).get_string_from_utf8().strip_edges()
		_rx_mutex.lock()
		_closed_msg = "USB: %s closed. %s" % [port_name, msg if msg != "" else "Is the controller plugged in, and is the Motion4Sim Dashboard closed?"]
		_rx_mutex.unlock()


## Call often (from the motion loop). Handles replies from the controller.
func poll() -> void:
	if mode != Mode.USB:
		return
	_rx_mutex.lock()
	var replies := parse_replies(_rx)
	var closed := _closed_msg
	_closed_msg = ""
	_rx_mutex.unlock()
	if closed != "":
		connected = false
		status = closed
	for r in replies:
		match int(r[0]):
			CMD_STATUS:
				rig_state = int(r[1])
			CMD_FIRMWARE:
				firmware = "%d.%02d" % [int(r[1]) >> 8, int(r[1]) & 0xFF]
	if connected and status.begins_with("USB: opening") and (rig_state >= 0 or sent > 500):
		status = "USB: connected" + ((" (firmware %s)" % firmware) if firmware != "" else "")


func _write(bytes: PackedByteArray) -> bool:
	if not connected:
		return false
	match mode:
		Mode.NETWORK:
			if _udp.put_packet(bytes) != OK:
				errors += 1
				return false
		Mode.USB:
			if _pipe == null or not _pipe.is_open():
				return false
			_pipe.store_buffer(bytes)
			_pipe.flush()
		_:
			return false
	return true


func send_pose(pose: Dictionary, belt: float) -> void:
	if _write(pose_packet(pose, belt, 0.0, invert)):
		sent += 1


func send_command(cmd: int, value := 0) -> void:
	_write(command_frame(cmd, value))


func close() -> void:
	_alive = false
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	_pid = -1
	if _pipe != null:
		_pipe.close()
	_pipe = null
	if _reader != null and _reader.is_started():
		_reader.wait_to_finish()
	_reader = null
	_udp.close()
	connected = false
	rig_state = -1
	mode = Mode.DRY_RUN
	status = "dry run: nothing is sent to the rig"


## COM ports Windows knows about (asks PowerShell; takes about a second).
static func list_ports() -> PackedStringArray:
	if OS.get_name() != "Windows":
		return PackedStringArray()
	var out := []
	OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", "[System.IO.Ports.SerialPort]::GetPortNames() -join ','"], out)
	var s := str(out[0]).strip_edges() if out.size() > 0 else ""
	return s.split(",", false)
