class_name Keys
extends RefCounted
## Key bindings (v1.19.0): every keyboard control and controller button can be changed in Settings > Change keys.
## Each action has up to two keyboard keys and one controller button. Only the changed ones are saved
## (Settings "binds"), so new defaults reach everyone who hasn't touched that action.
##
## Keys are stored as physical key codes (the key's place on the keyboard), so they work on any layout.
## A controller button is {"i": button number, "name": device name}. The default buttons have no name: they
## are for a standard gamepad and only work while no simulator joystick is set up (as before v1.19.0).

## Which games use each group of actions. Two actions clash only if one game uses both.
const GROUP_GAMES := {
	"all": ["flight", "race", "space", "coaster"], "fly": ["flight", "space"], "flight": ["flight"], "race": ["race"], "space": ["space"],
}
const GROUP_TITLES := {
	"fly": "Flying (Flight and the spaceship)", "flight": "Flight only", "race": "Racing", "space": "Spaceship only", "all": "Every game",
}
const GROUP_ORDER := ["fly", "flight", "race", "space", "all"]

## id, group, name, default keys, default gamepad button (-1 none), short tag for the keyboard picture
const ACTIONS := [
	["pitch_down", "fly", "Nose down (push)", [KEY_W, KEY_UP], -1, "NOSE DOWN"],
	["pitch_up", "fly", "Nose up (pull)", [KEY_S, KEY_DOWN], -1, "NOSE UP"],
	["roll_left", "fly", "Bank left", [KEY_A, KEY_LEFT], -1, "BANK LEFT"],
	["roll_right", "fly", "Bank right", [KEY_D, KEY_RIGHT], -1, "BANK RIGHT"],
	["yaw_left", "fly", "Rudder left", [KEY_Q], JOY_BUTTON_LEFT_SHOULDER, "RUDDER LEFT"],
	["yaw_right", "fly", "Rudder right", [KEY_E], JOY_BUTTON_RIGHT_SHOULDER, "RUDDER RIGHT"],
	["thr_up", "fly", "More power", [KEY_SHIFT, KEY_PAGEUP], -1, "POWER UP"],
	["thr_down", "fly", "Less power", [KEY_CTRL, KEY_PAGEDOWN], -1, "POWER DOWN"],
	["trim_up", "flight", "Trim nose up", [KEY_BRACKETRIGHT, KEY_KP_1], JOY_BUTTON_DPAD_DOWN, "TRIM UP"],
	["trim_down", "flight", "Trim nose down", [KEY_BRACKETLEFT, KEY_KP_7], JOY_BUTTON_DPAD_UP, "TRIM DOWN"],
	["trim_reset", "flight", "Trim back to the middle", [KEY_BACKSLASH, KEY_KP_5], -1, "TRIM MIDDLE"],
	["flaps", "flight", "Flaps (up, half, full)", [KEY_F], JOY_BUTTON_A, "FLAPS"],
	["brake", "flight", "Wheel brakes", [KEY_SPACE, KEY_B], -1, "BRAKES"],
	["thr_full", "flight", "Full power", [KEY_HOME], -1, "FULL POWER"],
	["thr_idle", "flight", "Power off (idle)", [KEY_END], -1, "POWER OFF"],
	["steer_left", "race", "Steer left", [KEY_A, KEY_LEFT], -1, "STEER LEFT"],
	["steer_right", "race", "Steer right", [KEY_D, KEY_RIGHT], -1, "STEER RIGHT"],
	["accel", "race", "Accelerate", [KEY_W, KEY_UP], -1, "GO"],
	["race_brake", "race", "Brake (hold when stopped: reverse)", [KEY_S, KEY_DOWN], -1, "BRAKE"],
	["fire", "space", "Fire", [KEY_SPACE], -1, "FIRE"],
	["boost", "space", "Boost", [KEY_TAB, KEY_B], -1, "BOOST"],
	["hyper", "space", "Hyperspeed", [KEY_H], JOY_BUTTON_Y, "HYPER"],
	["x10", "space", "x10 speed", [KEY_G], JOY_BUTTON_A, "x10 SPEED"],
	["next", "space", "Next planet", [KEY_N, KEY_PERIOD], JOY_BUTTON_X, "NEXT PLANET"],
	["prev", "space", "Previous planet", [KEY_COMMA], -1, "LAST PLANET"],
	["auto", "space", "To space / to Earth (autopilot)", [KEY_U], JOY_BUTTON_BACK, "AUTO"],
	["land", "space", "Land / lift off", [KEY_L], -1, "LAND"],
	["lights", "space", "Lights", [KEY_K], -1, "LIGHTS"],
	["sp_assist", "space", "Easy / Pro", [KEY_J], -1, "EASY / PRO"],
	["camera", "all", "Change camera (in VR: recentre)", [KEY_V, KEY_C], JOY_BUTTON_B, "VIEW"],
	["pause", "all", "Pause (Esc always works too)", [KEY_P], JOY_BUTTON_START, "PAUSE"],
	["restart", "all", "Restart", [KEY_R], -1, "RESTART"],
	["help", "all", "Show / hide the controls while playing", [KEY_F1], -1, "HELP"],
	["data", "all", "Data panel", [KEY_T], -1, "DATA"],
	["sound", "all", "Sound on / off", [KEY_M], -1, "SOUND"],
	["fullscreen", "all", "Full screen", [KEY_F11], -1, "FULL SCREEN"],
]

## Keys that can't be given to an action: they work the menus.
const RESERVED := [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_BACKSPACE, KEY_DELETE]

static var over := {}        ## action -> {"k": [codes], "b": {"i": n, "name": ""}}: only what the player changed
static var _index := {}


static func info(id: String) -> Array:
	if _index.is_empty():
		for a in ACTIONS:
			_index[a[0]] = a
	return _index.get(id, [])


static func group_of(id: String) -> String:
	var a := info(id)
	return "" if a.is_empty() else str(a[1])


static func title(id: String) -> String:
	var a := info(id)
	return id if a.is_empty() else str(a[2])


static func tag(id: String) -> String:
	var a := info(id)
	return "" if a.is_empty() else str(a[5])


static func ids_in(group: String) -> Array:
	var out: Array = []
	for a in ACTIONS:
		if a[1] == group:
			out.append(a[0])
	return out


## The action's two keyboard keys (0 = empty).
static func keys_of(id: String) -> Array:
	var o: Dictionary = over.get(id, {})
	var src: Array = o["k"] if o.has("k") else info(id)[3]
	var out: Array = [0, 0]
	for i in mini(src.size(), 2):
		out[i] = int(src[i])
	return out


## The action's controller button: {"i": n, "name": device} or {} for none.
static func button_of(id: String) -> Dictionary:
	var o: Dictionary = over.get(id, {})
	if o.has("b"):
		return o["b"]
	var d: int = info(id)[4]
	return {"i": d, "name": ""} if d >= 0 else {}


static func uses(id: String, game: String) -> bool:
	return game in GROUP_GAMES.get(group_of(id), [])


static func clash(a: String, b: String) -> bool:
	for g in GROUP_GAMES.get(group_of(a), []):
		if g in GROUP_GAMES.get(group_of(b), []):
			return true
	return false


# ---------------------------------------------------------------- reading
## True while one of the action's keys is held.
static func key_down(id: String) -> bool:
	for k in keys_of(id):
		if k != 0 and Input.is_physical_key_pressed(k):
			return true
	return false


## True while the action's controller button is held. A default (gamepad) button only counts while no
## simulator joystick is set up, because a joystick's button numbers mean other things.
static func button_down(id: String, rig_set_up: bool) -> bool:
	var b := button_of(id)
	if b.is_empty():
		return false
	var nm := str(b.get("name", ""))
	if nm == "" and rig_set_up:
		return false
	for dev in Input.get_connected_joypads():
		if (nm == "" or Input.get_joy_name(dev) == nm) and Input.is_joy_button_pressed(dev, int(b["i"])):
			return true
	return false


static func down(id: String, rig_set_up := false) -> bool:
	return key_down(id) or button_down(id, rig_set_up)


static func val(id: String, rig_set_up := false) -> float:
	return 1.0 if down(id, rig_set_up) else 0.0


## The actions a key works in this game (for the press-once controls: flaps, camera, pause...).
static func actions_for_key(code: int, game: String) -> Array:
	var out: Array = []
	for a in ACTIONS:
		if uses(a[0], game) and code in keys_of(a[0]):
			out.append(a[0])
	return out


static func key_used(code: int, game: String) -> bool:
	return not actions_for_key(code, game).is_empty()


# ---------------------------------------------------------------- changing
static func _put(id: String, what: String, value) -> void:
	var o: Dictionary = over.get(id, {}).duplicate(true)
	o[what] = value
	over[id] = o


## Gives a key to an action (slot 0 or 1; code 0 empties the slot). The key is taken away from any other action
## it would clash with; returns the names of those actions (for a message).
static func set_key(id: String, slot: int, code: int) -> Array:
	var taken: Array = []
	if code != 0:
		for a in ACTIONS:
			var other: String = a[0]
			var ks := keys_of(other)
			if code in ks and (other != id) and clash(id, other):
				ks[ks.find(code)] = 0
				_put(other, "k", ks)
				taken.append(title(other))
	var mine := keys_of(id)
	if code != 0 and code in mine:
		mine[mine.find(code)] = 0   # the same key in the other slot: move it
	mine[slot] = code
	_put(id, "k", mine)
	return taken


## Gives a controller button to an action (button -1 = none); taken away from any action it would clash with.
static func set_button(id: String, button: int, device_name: String) -> Array:
	var taken: Array = []
	if button >= 0:
		for a in ACTIONS:
			var other: String = a[0]
			var b := button_of(other)
			if other != id and not b.is_empty() and int(b["i"]) == button and clash(id, other) and (str(b.get("name", "")) in ["", device_name]):
				_put(other, "b", {})
				taken.append(title(other))
	_put(id, "b", {"i": button, "name": device_name} if button >= 0 else {})
	return taken


static func reset_all() -> void:
	over = {}


static func changed() -> bool:
	return not over.is_empty()


# ---------------------------------------------------------------- names
const NAMES := {
	KEY_UP: "Up", KEY_DOWN: "Down", KEY_LEFT: "Left", KEY_RIGHT: "Right", KEY_SHIFT: "Shift", KEY_CTRL: "Ctrl", KEY_ALT: "Alt",
	KEY_SPACE: "Space", KEY_PAGEUP: "Page Up", KEY_PAGEDOWN: "Page Down", KEY_HOME: "Home", KEY_END: "End", KEY_TAB: "Tab",
	KEY_BRACKETLEFT: "[", KEY_BRACKETRIGHT: "]", KEY_BACKSLASH: "\\", KEY_COMMA: ",", KEY_PERIOD: ".", KEY_SLASH: "/", KEY_SEMICOLON: ";",
	KEY_APOSTROPHE: "'", KEY_MINUS: "-", KEY_EQUAL: "=", KEY_QUOTELEFT: "`", KEY_INSERT: "Insert", KEY_CAPSLOCK: "Caps Lock",
	KEY_KP_0: "Num 0", KEY_KP_1: "Num 1", KEY_KP_2: "Num 2", KEY_KP_3: "Num 3", KEY_KP_4: "Num 4", KEY_KP_5: "Num 5", KEY_KP_6: "Num 6",
	KEY_KP_7: "Num 7", KEY_KP_8: "Num 8", KEY_KP_9: "Num 9", KEY_KP_ADD: "Num +", KEY_KP_SUBTRACT: "Num -", KEY_KP_MULTIPLY: "Num *",
	KEY_KP_DIVIDE: "Num /", KEY_KP_PERIOD: "Num .",
}
const PAD_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y", JOY_BUTTON_BACK: "Back", JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_LEFT_STICK: "L stick click", JOY_BUTTON_RIGHT_STICK: "R stick click",
	JOY_BUTTON_DPAD_UP: "D-pad up", JOY_BUTTON_DPAD_DOWN: "D-pad down", JOY_BUTTON_DPAD_LEFT: "D-pad left", JOY_BUTTON_DPAD_RIGHT: "D-pad right",
}


static func key_name(code: int) -> String:
	if code == 0:
		return ""
	if NAMES.has(code):
		return NAMES[code]
	var s := OS.get_keycode_string(code)
	return s if s != "" else "Key %d" % code


static func button_name(b: Dictionary) -> String:
	if b.is_empty():
		return ""
	var i := int(b["i"])
	if str(b.get("name", "")) == "":
		return str(PAD_NAMES.get(i, "Button %d" % (i + 1)))
	return "Button %d" % (i + 1)   # joysticks number their buttons from 1


## "W / Up" (the action's keys), or "none".
static func label(id: String) -> String:
	var parts: Array = []
	for k in keys_of(id):
		if k != 0:
			parts.append(key_name(k))
	return " / ".join(parts) if not parts.is_empty() else "none"


## The first key only ("W"), for short hints.
static func first(id: String) -> String:
	for k in keys_of(id):
		if k != 0:
			return key_name(k)
	return "none"
