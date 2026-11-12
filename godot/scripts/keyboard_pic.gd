class_name KeyboardPic
extends Control
## The picture of a keyboard on the Controls screen (v1.19.0): every key that does something in the chosen game
## is lit in colour with what it does written on it. It is drawn from the real key bindings (Keys), so it
## always shows the player's own keys after they change them.

const U := 44.0            # one key's width in pixels
const GAP := 4.0
const COL_MOVE := Color("#ff4c00")     # steering the vehicle
const COL_GAME := Color("#1f8fff")     # this game's other controls
const COL_ALL := Color("#6f76b8")      # works in every game
const COL_OFF := Color(1, 1, 1, 0.07)

## rows of [physical key code, width in keys, label]; code 0 = a gap
const MAIN := [
	[[KEY_ESCAPE, 1.0, "Esc"], [0, 1.0, ""], [KEY_F1, 1.0, "F1"], [KEY_F2, 1.0, "F2"], [KEY_F3, 1.0, "F3"], [KEY_F4, 1.0, "F4"], [0, 0.5, ""], [KEY_F5, 1.0, "F5"], [KEY_F6, 1.0, "F6"],
		[KEY_F7, 1.0, "F7"], [KEY_F8, 1.0, "F8"], [0, 0.5, ""], [KEY_F9, 1.0, "F9"], [KEY_F10, 1.0, "F10"], [KEY_F11, 1.0, "F11"], [KEY_F12, 1.0, "F12"]],
	[[KEY_QUOTELEFT, 1.0, "`"], [KEY_1, 1.0, "1"], [KEY_2, 1.0, "2"], [KEY_3, 1.0, "3"], [KEY_4, 1.0, "4"], [KEY_5, 1.0, "5"], [KEY_6, 1.0, "6"], [KEY_7, 1.0, "7"], [KEY_8, 1.0, "8"],
		[KEY_9, 1.0, "9"], [KEY_0, 1.0, "0"], [KEY_MINUS, 1.0, "-"], [KEY_EQUAL, 1.0, "="], [KEY_BACKSPACE, 2.0, "Backspace"]],
	[[KEY_TAB, 1.5, "Tab"], [KEY_Q, 1.0, "Q"], [KEY_W, 1.0, "W"], [KEY_E, 1.0, "E"], [KEY_R, 1.0, "R"], [KEY_T, 1.0, "T"], [KEY_Y, 1.0, "Y"], [KEY_U, 1.0, "U"], [KEY_I, 1.0, "I"],
		[KEY_O, 1.0, "O"], [KEY_P, 1.0, "P"], [KEY_BRACKETLEFT, 1.0, "["], [KEY_BRACKETRIGHT, 1.0, "]"], [KEY_BACKSLASH, 1.5, "\\"]],
	[[KEY_CAPSLOCK, 1.75, "Caps"], [KEY_A, 1.0, "A"], [KEY_S, 1.0, "S"], [KEY_D, 1.0, "D"], [KEY_F, 1.0, "F"], [KEY_G, 1.0, "G"], [KEY_H, 1.0, "H"], [KEY_J, 1.0, "J"], [KEY_K, 1.0, "K"],
		[KEY_L, 1.0, "L"], [KEY_SEMICOLON, 1.0, ";"], [KEY_APOSTROPHE, 1.0, "'"], [KEY_ENTER, 2.25, "Enter"]],
	[[KEY_SHIFT, 2.25, "Shift"], [KEY_Z, 1.0, "Z"], [KEY_X, 1.0, "X"], [KEY_C, 1.0, "C"], [KEY_V, 1.0, "V"], [KEY_B, 1.0, "B"], [KEY_N, 1.0, "N"], [KEY_M, 1.0, "M"], [KEY_COMMA, 1.0, ","],
		[KEY_PERIOD, 1.0, "."], [KEY_SLASH, 1.0, "/"], [KEY_SHIFT, 2.75, "Shift"]],
	[[KEY_CTRL, 1.5, "Ctrl"], [0, 1.25, ""], [KEY_ALT, 1.25, "Alt"], [KEY_SPACE, 6.25, "Space"], [KEY_ALT, 1.25, "Alt"], [0, 2.0, ""], [KEY_CTRL, 1.5, "Ctrl"]],
]
## the block with Home / End / Page Up / Page Down and the arrows: [code, column, row, label]
const NAV := [
	[KEY_INSERT, 0, 1, "Ins"], [KEY_HOME, 1, 1, "Home"], [KEY_PAGEUP, 2, 1, "PgUp"], [KEY_DELETE, 0, 2, "Del"], [KEY_END, 1, 2, "End"], [KEY_PAGEDOWN, 2, 2, "PgDn"],
	[KEY_UP, 1, 4, "Up"], [KEY_LEFT, 0, 5, "Left"], [KEY_DOWN, 1, 5, "Down"], [KEY_RIGHT, 2, 5, "Right"],
]
## the number pad
const PAD := [
	[KEY_KP_DIVIDE, 1, 1, "/"], [KEY_KP_MULTIPLY, 2, 1, "*"], [KEY_KP_SUBTRACT, 3, 1, "-"], [KEY_KP_7, 0, 2, "7"], [KEY_KP_8, 1, 2, "8"], [KEY_KP_9, 2, 2, "9"], [KEY_KP_ADD, 3, 2, "+"],
	[KEY_KP_4, 0, 3, "4"], [KEY_KP_5, 1, 3, "5"], [KEY_KP_6, 2, 3, "6"], [KEY_KP_1, 0, 4, "1"], [KEY_KP_2, 1, 4, "2"], [KEY_KP_3, 2, 4, "3"], [KEY_KP_0, 0, 5, "0"], [KEY_KP_PERIOD, 2, 5, "."],
]

var game := "flight"
var font: Font
var font_bold: Font


func _init() -> void:
	custom_minimum_size = Vector2(23.0 * U, 6.0 * U + 4.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = load("res://assets/fonts/Barlow-Regular.ttf")
	font_bold = load("res://assets/fonts/Barlow-SemiBold.ttf")


func set_game(g: String) -> void:
	game = g
	queue_redraw()


static func colour_of(id: String) -> Color:
	var g := Keys.group_of(id)
	if g == "all":
		return COL_ALL
	return COL_MOVE if (g == "fly" or g == "race") else COL_GAME


func _draw() -> void:
	# what each key does in this game
	var what := {}
	for a in Keys.ACTIONS:
		if Keys.uses(a[0], game):
			for k in Keys.keys_of(a[0]):
				if k != 0 and not what.has(k):
					what[k] = a[0]
	for r in MAIN.size():
		var x := 0.0
		for k in MAIN[r]:
			var w: float = k[1]
			if int(k[0]) != 0:
				_key(Rect2(x * U, r * U, w * U - GAP, U - GAP), int(k[0]), str(k[2]), what)
			x += w
	for k in NAV:
		_key(Rect2((15.5 + int(k[1])) * U, int(k[2]) * U, U - GAP, U - GAP), int(k[0]), str(k[3]), what)
	for k in PAD:
		_key(Rect2((19.0 + int(k[1])) * U, int(k[2]) * U, U - GAP, U - GAP), int(k[0]), "Num " + str(k[3]), what)


func _key(rc: Rect2, code: int, label: String, what: Dictionary) -> void:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(7)
	var id: String = what.get(code, "")
	var words := PackedStringArray()
	if id != "":
		sb.bg_color = colour_of(id)
		sb.border_color = Color(1, 1, 1, 0.55)
		sb.set_border_width_all(1)
		sb.shadow_color = Color(sb.bg_color, 0.45)
		sb.shadow_size = 5
		words = Keys.tag(id).split(" ")
	elif game == "flight" and code >= KEY_0 and code <= KEY_9:
		sb.bg_color = Color(COL_GAME, 0.38)   # the number keys set the power (1 = 10% ... 0 = full)
		words = PackedStringArray(["POWER", "100%" if code == KEY_0 else "%d0%%" % (code - KEY_0)])
	elif code == KEY_ESCAPE:
		sb.bg_color = COL_ALL
		words = PackedStringArray(["PAUSE"])
	else:
		sb.bg_color = COL_OFF
	draw_style_box(sb, rc)
	var lit := not words.is_empty()
	draw_string(font, rc.position + Vector2(5, 12), label, HORIZONTAL_ALIGNMENT_LEFT, rc.size.x - 6, 10, Color(1, 1, 1, 0.9 if lit else 0.38))
	var y := rc.position.y + (27.0 if words.size() > 1 else 31.0)
	for wd in words:
		draw_string(font_bold, Vector2(rc.position.x + 1, y), wd, HORIZONTAL_ALIGNMENT_CENTER, rc.size.x - 2, 9, Color.WHITE)
		y += 10.0
