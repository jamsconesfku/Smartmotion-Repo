extends Node
## Saved settings (user://settings.cfg). Autoload name: Settings.

const PATH := "user://settings.cfg"
var data := {
	"aircraft": "bulldog", "start": "runway", "mode": "free", "assist": true, "tod": "day", "wind": "calm",
	"invert": false, "sound": true, "quality": "high", "tel": false, "tel_host": "127.0.0.1", "tel_port": 4123, "fullscreen": false,
	"vr_hz": 72.0, "game": "flight", "race": "race",
}

func _ready() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		for k in data.keys():
			if cf.has_section_key("s", k):
				data[k] = cf.get_value("s", k)
	if data["aircraft"] == "trainer":
		data["aircraft"] = "bulldog"   # the Bulldog replaced the light trainer in v1.6.0

func get_value(k: String):
	return data.get(k)

func set_value(k: String, v) -> void:
	data[k] = v
	save()

func save() -> void:
	var cf := ConfigFile.new()
	for k in data.keys():
		cf.set_value("s", k, data[k])
	cf.save(PATH)

func best_time(aircraft: String) -> float:
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		return float(cf.get_value("best", aircraft, 0.0))
	return 0.0

func set_best_time(aircraft: String, t: float) -> void:
	var cf := ConfigFile.new()
	cf.load(PATH)
	cf.set_value("best", aircraft, t)
	for k in data.keys():
		cf.set_value("s", k, data[k])
	cf.save(PATH)
