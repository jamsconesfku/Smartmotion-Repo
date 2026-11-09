class_name Synth
extends Node
## Engine, wind and stall-horn sound, generated live (no sound files).

var player := AudioStreamPlayer.new()
var playback: AudioStreamGeneratorPlayback
var rate := 22050.0
var ph1 := 0.0
var ph2 := 0.0
var ph3 := 0.0
var noise_lp := 0.0
var rng := RandomNumberGenerator.new()
var thr := 0.0
var ias := 0.0
var horn := false
var on := false
var vol := 0.0


func _ready() -> void:
	var g := AudioStreamGenerator.new()
	g.mix_rate = rate
	g.buffer_length = 0.12
	player.stream = g
	player.volume_db = -4.0
	add_child(player)
	player.play()
	playback = player.get_stream_playback()


func set_state(throttle: float, ias_ms: float, horn_on: bool, enabled: bool) -> void:
	thr = throttle
	ias = ias_ms
	horn = horn_on
	on = enabled


func _process(delta: float) -> void:
	if playback == null:
		return
	vol = move_toward(vol, 1.0 if on else 0.0, delta * 4.0)
	var n := playback.get_frames_available()
	if n <= 0:
		return
	var f := 22.0 + thr * 46.0
	var wind_gain := pow(clampf(ias / 90.0, 0.0, 1.3), 2.0) * 0.22
	var eng_gain := 0.16 * (0.35 + 0.65 * thr)
	var lp_k := 0.05 + clampf(ias / 200.0, 0.0, 0.4)
	for i in n:
		ph1 = fmod(ph1 + f / rate, 1.0)
		ph2 = fmod(ph2 + f * 2.02 / rate, 1.0)
		var saw := ph1 * 2.0 - 1.0
		var sq := 1.0 if ph2 < 0.5 else -1.0
		var e := (saw * 0.5 + sq * 0.18) * eng_gain
		noise_lp += (rng.randf_range(-1.0, 1.0) - noise_lp) * lp_k
		var w := noise_lp * wind_gain * 2.0
		var h := 0.0
		if horn:
			ph3 = fmod(ph3 + 1250.0 / rate, 1.0)
			h = (1.0 if ph3 < 0.5 else -1.0) * 0.04
		var s := (e + w + h) * vol
		playback.push_frame(Vector2(s, s))
