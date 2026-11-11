class_name Atmosphere
extends RefCounted
## The same physical air model as shaders/sky.gdshader, on the CPU, for the few colours the rest of the
## world needs: the colour and strength of the sunlight that reaches the ground, and the colour of the haze
## at the horizon (fog, distant land, cloud shading). Worked out once per time-of-day or weather change.

const RE := 6360.0
const RA := 6460.0
const B_R := Vector3(5.802e-3, 13.558e-3, 33.1e-3)
const B_MS := 3.996e-3
const B_ME := 4.40e-3
const B_O := Vector3(0.650e-3, 1.881e-3, 0.085e-3)
const SUN_I := 20.0


static func _ray_sphere(ro: Vector3, rd: Vector3, r: float) -> Vector2:
	var b := ro.dot(rd)
	var c := ro.dot(ro) - r * r
	var h := b * b - c
	if h < 0.0:
		return Vector2(-1.0, -1.0)
	h = sqrt(h)
	return Vector2(-b - h, -b + h)


static func _dens(h: float) -> Vector3:
	return Vector3(exp(-h / 8.0), exp(-h / 1.2), maxf(0.0, 1.0 - absf(h - 25.0) / 15.0))


static func _ext(d: Vector3, haze: float) -> Vector3:
	return B_R * d.x + Vector3.ONE * (B_ME * haze * d.y) + B_O * d.z


static func _exp3(v: Vector3) -> Vector3:
	return Vector3(exp(v.x), exp(v.y), exp(v.z))


static func sun_trans(p: Vector3, sd: Vector3, haze: float, n := 8) -> Vector3:
	var t := _ray_sphere(p, sd, RA)
	var ds := maxf(t.y, 0.0) / float(n)
	var od := Vector3.ZERO
	for i in n:
		var q := p + sd * (ds * (float(i) + 0.5))
		od += _dens(maxf(q.length() - RE, 0.0)) * ds
	var r := p.length()
	var mu := (p / r).dot(sd)
	var mu_h := -sqrt(maxf(1.0 - (RE / r) * (RE / r), 0.0))
	var lit := smoothstep(mu_h - 0.004, mu_h + 0.004, mu)
	return _exp3(-_ext(od, haze)) * lit


## Colour of the sky in direction rd (linear, before sky_energy), seen from alt_km.
static func sky(rd: Vector3, sd: Vector3, haze: float, alt_km := 0.05, n := 16) -> Vector3:
	var ro := Vector3(0.0, RE + alt_km, 0.0)
	var tmax := maxf(_ray_sphere(ro, rd, RA).y, 0.0)
	var tg := _ray_sphere(ro, rd, RE)
	if tg.x > 0.0:
		tmax = tg.x
	var mu := rd.dot(sd)
	var pr := 3.0 / (16.0 * PI) * (1.0 + mu * mu)
	var g := 0.78
	var pm := 3.0 / (8.0 * PI) * ((1.0 - g * g) * (1.0 + mu * mu)) / ((2.0 + g * g) * pow(1.0 + g * g - 2.0 * g * mu, 1.5))
	var T := Vector3.ONE
	var L := Vector3.ZERO
	var prev := 0.0
	for i in n:
		var f := (float(i) + 1.0) / float(n)
		var t1 := tmax * f * f
		var ds := t1 - prev
		var p := ro + rd * (prev + ds * 0.5)
		prev = t1
		var d := _dens(maxf(p.length() - RE, 0.0))
		var ex := _ext(d, haze)
		var ts := sun_trans(p, sd, haze, 4)
		var sr := B_R * d.x
		var sm := Vector3.ONE * (B_MS * haze * d.y)
		var s := (sr * pr + sm * pm) * ts + (sr + sm) * (ts * 0.55 + Vector3(0.006, 0.01, 0.018)) * (0.5 / (4.0 * PI))
		var tstep := _exp3(-ex * ds)
		var gain := Vector3.ONE - tstep
		L += T * s * Vector3(gain.x / maxf(ex.x, 1e-7), gain.y / maxf(ex.y, 1e-7), gain.z / maxf(ex.z, 1e-7))
		T *= tstep
	return L * SUN_I


## Colour of the horizon (just above it) away from the sun: the colour distant haze takes on. The bright
## glow on the sun's side is left out (the fog adds its own sun glow), or a low sun would turn all the haze orange.
static func horizon(sd: Vector3, haze: float, el_deg := 2.5) -> Vector3:
	var acc := Vector3.ZERO
	var e := deg_to_rad(el_deg)
	var a0 := atan2(sd.z, sd.x)
	for k in 5:
		var a := a0 + PI * (0.5 + 0.25 * float(k))   # 90 to 270 degrees round from the sun
		acc += sky(Vector3(cos(a) * cos(e), sin(e), sin(a) * cos(e)), sd, haze)
	return acc / 5.0


static func to_color(v: Vector3) -> Color:
	return Color(v.x, v.y, v.z)
