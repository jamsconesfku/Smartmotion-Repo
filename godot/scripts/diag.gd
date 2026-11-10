class_name Diag
extends RefCounted
## Diagnostics: every important step is written to SmartMotionFlight-log.txt next to the game (and to the user folder),
## so a problem such as VR not starting can be worked out from the log.

static var lines := PackedStringArray()
static var paths: Array = []


static func start(fresh: bool) -> void:
	paths = [OS.get_executable_path().get_base_dir().path_join("SmartMotionFlight-log.txt"), "user://smartmotion-log.txt"]
	if fresh:
		# keep the last run's log (if the game crashed, that's where it shows)
		for p in paths:
			if FileAccess.file_exists(p):
				DirAccess.copy_absolute(p, p.get_basename() + "-previous.txt")
		for p in paths:
			var f := FileAccess.open(p, FileAccess.WRITE)
			if f:
				f.close()


static func write(msg: String) -> void:
	var line := "[%s] %s" % [Time.get_time_string_from_system(), msg]
	lines.append(line)
	print(line)
	for p in paths:
		var f: FileAccess = FileAccess.open(p, FileAccess.READ_WRITE) if FileAccess.file_exists(p) else FileAccess.open(p, FileAccess.WRITE)
		if f:
			f.seek_end()
			f.store_line(line)
			f.close()


static func log_path() -> String:
	return str(paths[0]) if paths.size() > 0 else ""


static func snapshot() -> void:
	write("=== system ===")
	var vi := Engine.get_version_info()
	write("Godot %s | OS %s %s | %s" % [vi.get("string", "?"), OS.get_name(), OS.get_version(), DisplayServer.get_name()])
	write("GPU: %s | vendor: %s | renderer: %s | api: %s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor(), RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_api_version()])
	write("Engine args: %s" % [str(OS.get_cmdline_args())])
	write("Game args: %s" % [str(OS.get_cmdline_user_args())])
	write("Executable: %s" % OS.get_executable_path())
	write("XR_RUNTIME_JSON env: '%s'" % OS.get_environment("XR_RUNTIME_JSON"))
	if OS.get_name() == "Windows":
		for key in ["HKLM\\SOFTWARE\\Khronos\\OpenXR\\1", "HKLM\\SOFTWARE\\WOW6432Node\\Khronos\\OpenXR\\1", "HKCU\\SOFTWARE\\Khronos\\OpenXR\\1"]:
			var out: Array = []
			var code := OS.execute("reg", ["query", key, "/v", "ActiveRuntime"], out, true)
			write("OpenXR active runtime (%s): exit %d | %s" % [key, code, str(out).replace("\\r\\n", " ").replace("\n", " ").strip_edges()])
	var n := XRServer.get_interface_count()
	write("XR interfaces: %d" % n)
	for i in XRServer.get_interfaces():
		write("  - %s" % str(i))
	var xr := XRServer.find_interface("OpenXR")
	if xr == null:
		write("OpenXR interface: NOT PRESENT")
	else:
		write("OpenXR interface: present | initialized: %s" % str(xr.is_initialized()))
		if xr.is_initialized():
			write("OpenXR system info: %s" % str(xr.get_system_info()))
			write("OpenXR refresh rate: %s" % str(xr.get_display_refresh_rate()))


static func engine_log_tail(max_lines := 120) -> String:
	var p := "user://logs/godot.log"
	if not FileAccess.file_exists(p):
		return "(no engine log found)"
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return "(engine log could not be read: error %d)" % FileAccess.get_open_error()
	var all := f.get_as_text().split("\n")
	f.close()
	var start := maxi(0, all.size() - max_lines)
	return "\n".join(all.slice(start))


## The end of the last run's logs: the game's own and Godot's (a crash report is at the end of Godot's).
static func previous_text(max_lines := 60) -> String:
	var out := ""
	var p := "user://smartmotion-log-previous.txt"
	if FileAccess.file_exists(p):
		var all := FileAccess.get_file_as_string(p).split("\n")
		out += "\n".join(all.slice(maxi(0, all.size() - max_lines)))
	var logs: Array = []
	var dir := DirAccess.open("user://logs")
	if dir != null:
		for f in dir.get_files():
			if f.begins_with("godot") and f.ends_with(".log") and f != "godot.log":
				logs.append(f)
	logs.sort()
	if not logs.is_empty():
		var all2 := FileAccess.get_file_as_string("user://logs/" + str(logs[-1])).split("\n")
		out += "\n--- engine log of the last run (%s) ---\n" % str(logs[-1]) + "\n".join(all2.slice(maxi(0, all2.size() - max_lines)))
	return out if out != "" else "(no log from the last run)"


static func full_text() -> String:
	return "\n".join(lines) + "\n\n=== engine log (last lines) ===\n" + engine_log_tail() + "\n\n=== last run (look here after a crash) ===\n" + previous_text()
