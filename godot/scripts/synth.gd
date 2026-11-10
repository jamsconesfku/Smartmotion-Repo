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
var profile := "plane"     # plane, race (high-revving engine), space (low hum)
var fx: Array = []         # short sound effects playing: [kind, time]
var fx_lp := 0.0


func set_profile(p: String) -> void:
	profile = p


## Short sound effects for the space game: laser, enemy_laser, hit, boom.
func blip(kind: String) -> void:
	if not bool(Settings.get_value("sound")):
		return
	if fx.size() < 12:
		fx.append([kind, 0.0, rng.randf()])


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
	if profile == "race":
		f = 70.0 + thr * 430.0          # thr carries the engine revs (0..1)
		eng_gain = 0.11 + 0.05 * thr
		wind_gain = pow(clampf(ias / 95.0, 0.0, 1.2), 2.0) * 0.12
	elif profile == "ride":
		f = 8.0                         # the chain lift's clack (thr = 1 on the lift)
		eng_gain = 0.0
		wind_gain = pow(clampf(ias / 28.0, 0.0, 1.3), 2.0) * 0.3
	elif profile == "space":
		f = 34.0 + thr * 42.0
		eng_gain = 0.12 + 0.06 * thr
		wind_gain = 0.0
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
		if profile == "ride" and thr > 0.5:
			e = (1.0 if ph1 < 0.03 else 0.0) * 0.25 * (1.0 - ph1 / 0.03)
		if profile == "space":
			e = (absf(ph1 * 2.0 - 1.0) * 2.0 - 1.0) * eng_gain + noise_lp * 0.05
		var s := (e + w + h) * vol + _fx_sample()
		playback.push_frame(Vector2(s, s))
	var k := 0
	while k < fx.size():
		var lim := 0.9 if fx[k][0] == "boom" else 0.2
		if float(fx[k][1]) > lim:
			fx.remove_at(k)
		else:
			k += 1


func _fx_sample() -> float:
	var out := 0.0
	for e in fx:
		var t: float = e[1]
		var kind: String = e[0]
		e[1] = t + 1.0 / rate
		match kind:
			"laser":
				if t < 0.13:
					var fr := lerpf(1900.0, 380.0, t / 0.13) * (0.9 + float(e[2]) * 0.2)
					out += (1.0 if fmod(t * fr, 1.0) < 0.5 else -1.0) * 0.045 * (1.0 - t / 0.13)
			"enemy_laser":
				if t < 0.16:
					var fr2 := lerpf(950.0, 220.0, t / 0.16)
					out += sin(TAU * t * fr2) * 0.05 * (1.0 - t / 0.16)
			"hit":
				if t < 0.1:
					out += rng.randf_range(-1.0, 1.0) * 0.12 * (1.0 - t / 0.1)
			"boom":
				if t < 0.9:
					fx_lp += (rng.randf_range(-1.0, 1.0) - fx_lp) * 0.06
					out += (fx_lp * 0.9 + sin(TAU * 48.0 * t) * 0.3) * 0.35 * pow(1.0 - t / 0.9, 2.0)
	return out
