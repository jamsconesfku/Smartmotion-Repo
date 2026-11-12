class_name Terrain
extends RefCounted
## SmartMotion Flight: terrain heights and the Duxford layout (port of dashboard/fly/terrain.js).
## The ground is the real area: heights from the Copernicus DEM (assets/world/height.bin, made by
## scripts/build_world_data.py), centred on the middle of Duxford's hard runway. The runway numbers below come
## from world.json. Villages, roads and woods below are only used for the painted countryside beyond the real square.
## World axes: x east, y up, z south (north is -z), metres, origin at the runway centre.

const SIZE := 1024
const CELL := 32.0
const LEN := SIZE * CELL  # 32,768 m of real ground; the map repeats beyond this
const RW_HEADING_DEG := 58.04
const RW_HEADING := RW_HEADING_DEG * PI / 180.0
const RW_LEN := 1448.0
const RW_WIDTH := 46.0
const RW_ELEV := 33.5
const HEIGHT_FILE := "res://assets/world/height.bin"
## v1.15.0: an 8,192 m square round the airfield has the Environment Agency's LIDAR ground at 2 m
## (assets/world/detail_h.png, made by scripts/build_uk_detail.py). It fades into the 32 m map over the last 400 m.
const DETAIL_FILE := "res://assets/world/detail_h.png"
const D_HALF := 4096.0
const D_PX := 4096
const D_CELL := 2.0
const D_FADE := 400.0

var dir := Vector2(sin(RW_HEADING), -cos(RW_HEADING))
var perp := Vector2(cos(RW_HEADING), sin(RW_HEADING))   # to the right of the runway direction (south-east)
var data := PackedFloat32Array()
var colliders: Array = []   ## buildings near the aircraft (refreshed by the world as it moves)
var real := false           ## true when the real height data loaded
var detail := PackedByteArray()   ## detail heights, 3 bytes a sample (high byte, low byte, unused)
var has_detail := false

## runway frame: u along 062, v to the right. kind: hangar | bighangar | tower
const BUILDINGS := []   ## the real hangars and buildings now come from assets/world/buildings.bin
const ROADS := [
	{"name": "M11", "w": 30.0, "pts": [[1000, -9000], [2000, -4800], [3100, 0], [4000, 4600], [5200, 9000]]},
	{"name": "A505", "w": 13.0, "pts": [[-8000, -900], [-3000, -1150], [1000, -1450], [3100, -1700], [6500, -2400]]},
	{"name": "B1383", "w": 9.0, "pts": [[-1200, 5000], [-300, 2500], [300, 900], [1400, 480], [3100, 450]]},
	{"name": "lane", "w": 7.0, "pts": [[1500, 2400], [1450, 1300], [1400, 500]]},
	{"name": "lane", "w": 7.0, "pts": [[1500, 2400], [2300, 2900], [3600, 4000]]},
	{"name": "lane", "w": 7.0, "pts": [[-700, 1900], [-300, 2500]]},
	{"name": "lane", "w": 7.0, "pts": [[-1200, 5000], [-2500, 6500], [-4000, 7200]]},
	{"name": "lane", "w": 7.0, "pts": [[1400, 480], [1000, -400], [900, -1480]]},
	{"name": "lane", "w": 7.0, "pts": [[-2200, -2600], [-1500, -1500], [-300, -1250]]},
	{"name": "lane", "w": 7.0, "pts": [[2300, 2900], [3100, 2200]]},
]
const RIVER := {"w": 16.0, "pts": [[-2500, -9500], [-1700, -6800], [-1100, -4900], [-400, -2700], [600, -900], [1100, 700], [900, 2200], [600, 3200], [1500, 6000], [3000, 9500]]}
const VILLAGES := [
	{"name": "Duxford", "x": 1400.0, "z": 520.0, "r": 430.0}, {"name": "Whittlesford", "x": 1550.0, "z": 2450.0, "r": 390.0},
	{"name": "Pampisford", "x": -700.0, "z": 1950.0, "r": 330.0}, {"name": "Sawston", "x": -2300.0, "z": -2600.0, "r": 620.0},
	{"name": "Hinxton", "x": 900.0, "z": -1500.0, "r": 280.0}, {"name": "Ickleton", "x": 2300.0, "z": 2950.0, "r": 300.0},
	{"name": "Great Chesterford", "x": 3600.0, "z": 4000.0, "r": 460.0}, {"name": "Shelford", "x": -1200.0, "z": 5000.0, "r": 520.0},
	{"name": "Town", "x": -2500.0, "z": -13500.0, "r": 3000.0}, {"name": "Market town", "x": 9500.0, "z": 9500.0, "r": 1500.0},
]
const WOODS := [
	[-1800, 600, 380], [900, -2300, 300], [2400, 1500, 260], [-300, 2800, 340], [3600, -3000, 420], [-3200, -400, 450],
	[4800, 1200, 300], [-4500, 2800, 380], [200, 5200, 420], [2000, -5200, 360], [-1100, -4200, 300], [5600, -600, 320],
	[-2200, 4300, 300], [3300, 3800, 280], [-4000, -4500, 500], [6000, 5000, 420], [-6200, 800, 520], [7400, -5000, 480],
]
## low-level gate course: x, z, height above ground
const GATES := [
	[1300, -1700, 130], [2800, -3500, 120], [4200, -2100, 110], [4700, 0, 100], [3700, 2300, 110], [2100, 3500, 120],
	[200, 3000, 120], [-1600, 1700, 110], [-2300, -500, 120], [-1000, -1900, 130], [200, -700, 90],
]
## SmartMotion signs (runway frame); face = degrees the sign faces, measured from the runway direction
const SIGNS := [
	{"u": -560.0, "v": 105.0, "w": 34.0, "h": 11.0, "face": -90.0, "post": 8.0},
	{"u": 420.0, "v": -120.0, "w": 34.0, "h": 11.0, "face": 90.0, "post": 8.0},
	{"u": 760.0, "v": 180.0, "w": 26.0, "h": 8.5, "face": 180.0, "post": 7.0},
]


func _init() -> void:
	if not _load_heightmap():
		_build_heightmap()
	elif ResourceLoader.exists(DETAIL_FILE):
		var tex: Texture2D = load(DETAIL_FILE)
		var img := tex.get_image() if tex != null else null
		if img != null and img.get_width() == D_PX:
			if img.get_format() != Image.FORMAT_RGB8:
				img.convert(Image.FORMAT_RGB8)
			detail = img.get_data()
			has_detail = true


## One detail sample (metres), clamped to the square.
func _dh(i: int, j: int) -> float:
	var o := (clampi(j, 0, D_PX - 1) * D_PX + clampi(i, 0, D_PX - 1)) * 3
	return (detail[o] * 256 + detail[o + 1]) / 100.0 - 100.0


## How much the detail heights count at (x, z): 1 inside, fading to 0 at the edge of the square.
static func detail_weight(x: float, z: float) -> float:
	var e := maxf(absf(x), absf(z))
	return 1.0 - _sstep(D_HALF - D_FADE, D_HALF - D_CELL, e)


func _detail_height(x: float, z: float) -> float:
	var gx := (x + D_HALF) / D_CELL
	var gz := (z + D_HALF) / D_CELL
	var i0 := int(floor(gx))
	var j0 := int(floor(gz))
	var fx := gx - i0
	var fz := gz - j0
	var h00 := _dh(i0, j0)
	var h10 := _dh(i0 + 1, j0)
	var h01 := _dh(i0, j0 + 1)
	var h11 := _dh(i0 + 1, j0 + 1)
	return h00 + (h10 - h00) * fx + (h01 - h00) * fz + (h00 - h10 - h01 + h11) * fx * fz


func to_runway(x: float, z: float) -> Vector2:
	return Vector2(x * dir.x + z * dir.y, x * perp.x + z * perp.y)


func from_runway(u: float, v: float) -> Vector2:
	return Vector2(dir.x * u + perp.x * v, dir.y * u + perp.y * v)


static func _sstep(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _load_heightmap() -> bool:
	var f := FileAccess.open(HEIGHT_FILE, FileAccess.READ)
	if f == null or f.get_length() != SIZE * SIZE * 2:
		return false
	var raw := f.get_buffer(SIZE * SIZE * 2)
	data.resize(SIZE * SIZE)
	for k in SIZE * SIZE:
		data[k] = raw.decode_u16(k * 2) / 100.0 - 100.0
	real = true
	return true


func _build_heightmap() -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = 11
	noise.frequency = 1.0 / 7000.0
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 5
	data.resize(SIZE * SIZE)
	for j in SIZE:
		for i in SIZE:
			var x := (i - SIZE / 2) * CELL
			var z := (j - SIZE / 2) * CELL
			var r := Vector2(x, z).length()
			var hills := 48.0 + noise.get_noise_2d(x, z) * 42.0
			hills = lerpf(hills, 48.0, _sstep(11000.0, 15500.0, r))   # fade so the repeating map has no seam
			var uv := to_runway(x, z)
			var du := maxf(absf(uv.x) - RW_LEN / 2.0, 0.0)
			var d := Vector2(du, uv.y).length()
			data[j * SIZE + i] = RW_ELEV + (hills - RW_ELEV) * _sstep(480.0, 1100.0, d)


func height(x: float, z: float) -> float:
	if has_detail:
		var w := detail_weight(x, z)
		if w >= 1.0:
			return _detail_height(x, z)
		if w > 0.0:
			return lerpf(coarse_height(x, z), _detail_height(x, z), w)
	return coarse_height(x, z)


func coarse_height(x: float, z: float) -> float:
	var h := _map_height(x, z)
	if real:
		# v1.17.1: beyond the real 32 km map the ground levels out at 45 m (as the ground shader draws it);
		# before, the map's hills repeated there
		var e := maxf(absf(x), absf(z))
		h = lerpf(h, FLAT_H, _sstep(LEN / 2.0 - 1500.0, LEN / 2.0 + 4000.0, e))
	return h


const FLAT_H := 45.0
func _map_height(x: float, z: float) -> float:
	var gx := x / CELL + SIZE / 2.0
	var gz := z / CELL + SIZE / 2.0
	var i0 := int(floor(gx))
	var j0 := int(floor(gz))
	var fx := gx - i0
	var fz := gz - j0
	var a := posmod(i0, SIZE)
	var b := (a + 1) % SIZE
	var c := posmod(j0, SIZE)
	var d := (c + 1) % SIZE
	var h00 := data[c * SIZE + a]
	var h10 := data[c * SIZE + b]
	var h01 := data[d * SIZE + a]
	var h11 := data[d * SIZE + b]
	return h00 + (h10 - h00) * fx + (h01 - h00) * fz + (h00 - h10 - h01 + h11) * fx * fz


func paved(x: float, z: float) -> bool:
	var uv := to_runway(x, z)
	var au := absf(uv.x)
	var av := absf(uv.y)
	if au < RW_LEN / 2.0 + 15.0 and av < 26.0:
		return true
	if au < 700.0 and absf(uv.y + 75.0) < 10.0:
		return true
	if uv.y < -23.0 and uv.y > -75.0:
		for u0 in [-600.0, -250.0, 100.0, 450.0]:
			if absf(uv.x - u0) < 10.0:
				return true
	if uv.x > -400.0 and uv.x < 220.0 and uv.y < -90.0 and uv.y > -215.0:
		return true
	return false


static func dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)
