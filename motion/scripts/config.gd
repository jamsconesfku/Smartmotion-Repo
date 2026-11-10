class_name Config
extends RefCounted
## Saved settings (user://motion.cfg, on Windows %APPDATA%\Godot\app_userdata\SmartMotion Motion).

const PATH := "user://motion.cfg"

const CONNECTION := {
	"link": "dry",            # dry | usb | network
	"com_port": "COM3",
	"baud": 250000,
	"rig_ip": "192.168.1.50",
	"rig_port": 53241,
	"game_port": 4123,        # the game sends its flight data here (game: Settings > Motion rig > On)
	"comp_port": 4124,        # the seat position goes back to the game here, so VR can cancel out the rig's movement
	"inv_sway": false, "inv_surge": false, "inv_heave": false, "inv_yaw": false, "inv_roll": false, "inv_pitch": false,
}

## Settings shown on the Settings page: [key, label, help, min, max, step, unit]
const FIELDS := [
	["Strength", [
		["intensity", "Overall strength", "How much of the movement reaches the seat. Start low (30 %) with a new rider.", 0.0, 1.0, 0.05, "%"],
		["gain_surge", "Speeding up / slowing down", "Forward and back push when the aircraft speeds up or slows down.", 0.0, 20.0, 0.5, "mm per m/s²"],
		["gain_sway", "Sideways", "Sideways push in skids and on the ground.", 0.0, 20.0, 0.5, "mm per m/s²"],
		["gain_heave", "Up and down", "Bumps, touchdowns and pulling up.", 0.0, 20.0, 0.5, "mm per m/s²"],
		["gain_roll", "Rolling", "How much the seat twitches as you start a roll.", 0.0, 1.0, 0.01, "° per °/s"],
		["gain_pitch", "Nose up / down", "How much the seat twitches as the nose starts to move.", 0.0, 1.0, 0.01, "° per °/s"],
		["gain_yaw", "Turning", "How much the seat twitches as the nose swings left or right.", 0.0, 1.0, 0.01, "° per °/s"],
		["tilt_gain", "Lasting forces (tilt)", "Leans the seat slowly so gravity gives a push that lasts, e.g. into the seat back on take-off.", 0.0, 1.5, 0.05, "×"],
	]],
	["Feel", [
		["washout_s", "Return to the middle", "How long a movement takes to drift back to the middle. Longer feels smoother but uses more travel.", 1.0, 10.0, 0.5, "s"],
		["smooth_s", "Smoothness", "More is softer, less is sharper and more detailed.", 0.02, 0.6, 0.02, "s"],
		["tilt_max_deg", "Most tilt for lasting forces", "", 0.0, 15.0, 0.5, "°"],
		["tilt_rate_dps", "Tilt speed", "Keep at 3 or below: faster and the rider feels the seat rotating instead of a push.", 0.5, 6.0, 0.5, "°/s"],
		["rumble_mm", "Runway rumble", "Small shake while rolling on the ground. 0 = off.", 0.0, 2.0, 0.1, "mm"],
		["fade_s", "Fade in / out", "Time to bring the motion in when you switch it on, and out on pause, crash or lost data.", 0.5, 6.0, 0.5, "s"],
	]],
	["Safety limits (set these to fit inside the rig's real travel)", [
		["limit_mm", "Most movement (sway, surge, heave)", "Furthest the seat may move from the middle.", 5.0, 150.0, 5.0, "mm"],
		["limit_deg", "Most turn (yaw, roll, pitch)", "Furthest the seat may turn from the middle.", 1.0, 25.0, 0.5, "°"],
		["speed_mm_s", "Top speed (movement)", "", 50.0, 800.0, 25.0, "mm/s"],
		["speed_deg_s", "Top speed (turn)", "", 5.0, 120.0, 5.0, "°/s"],
		["accel_mm_s2", "Top acceleration (movement)", "", 200.0, 5000.0, 100.0, "mm/s²"],
		["accel_deg_s2", "Top acceleration (turn)", "", 20.0, 1000.0, 20.0, "°/s²"],
	]],
	["Seat belt (actuator 7)", [
		["belt_on", "Drive the belt tensioner", "Tightens the belts when you slow down or go light in the seat.", 0, 1, 1, ""],
		["belt_base", "Belt tension in level flight", "", 0.0, 0.6, 0.05, "%"],
		["belt_gain", "Extra tension per g", "", 0.0, 3.0, 0.1, "×"],
	]],
]

var data := {}


func _init() -> void:
	data = Cueing.DEFAULTS.duplicate()
	data.merge(CONNECTION.duplicate())
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		for k in data.keys():
			if cf.has_section_key("s", k):
				data[k] = cf.get_value("s", k)


func save() -> void:
	var cf := ConfigFile.new()
	for k in data.keys():
		cf.set_value("s", k, data[k])
	cf.save(PATH)


func cueing_values() -> Dictionary:
	var d := {}
	for k in Cueing.DEFAULTS.keys():
		d[k] = data[k]
	return d


func inverts() -> Dictionary:
	var d := {}
	for a in Cueing.AXES:
		d[a] = bool(data["inv_" + a])
	return d
