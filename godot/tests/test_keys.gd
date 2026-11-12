extends SceneTree
## Checks the key bindings (v1.19.0):  godot --headless --path godot --script res://tests/test_keys.gd

var fails := 0

func ok(cond: bool, what: String) -> void:
	print(("PASS " if cond else "FAIL ") + what)
	if not cond:
		fails += 1


func _init() -> void:
	Keys.over = {}
	# the standard keys: no key does two things in one game, every action has a name and a tag
	for g in ["flight", "race", "space"]:
		var seen := {}
		var dup := ""
		for a in Keys.ACTIONS:
			if Keys.uses(a[0], g):
				for k in Keys.keys_of(a[0]):
					if k != 0:
						if seen.has(k):
							dup += "%s (%s, %s) " % [Keys.key_name(k), seen[k], a[0]]
						seen[k] = a[0]
		ok(dup == "", "standard keys don't clash in %s %s" % [g, dup])
		var bseen := {}
		var bdup := ""
		for a in Keys.ACTIONS:
			var b := Keys.button_of(a[0])
			if Keys.uses(a[0], g) and not b.is_empty():
				if bseen.has(b["i"]):
					bdup += "%s " % a[0]
				bseen[b["i"]] = true
		ok(bdup == "", "standard gamepad buttons don't clash in %s %s" % [g, bdup])
	ok(Keys.keys_of("trim_up")[0] == KEY_BRACKETRIGHT and Keys.keys_of("trim_down")[0] == KEY_BRACKETLEFT, "trim is on [ and ]")
	ok(Keys.label("pitch_down") == "W / Up", "label: " + Keys.label("pitch_down"))
	ok(Keys.actions_for_key(KEY_F, "flight") == ["flaps"] and Keys.actions_for_key(KEY_F, "race").is_empty(), "F is flaps in Flight only")
	ok(Keys.actions_for_key(KEY_W, "race") == ["accel"], "W accelerates in Racing")
	# give trim up to T: T is taken from the data panel (every game), W stays as it is
	var taken: Array = Keys.set_key("trim_up", 0, KEY_T)
	ok(Keys.keys_of("trim_up")[0] == KEY_T and taken == ["Data panel"], "trim up moved to T, taken from: " + str(taken))
	ok(Keys.keys_of("data") == [0, 0], "the data panel has no key now")
	ok(Keys.keys_of("trim_up")[1] == KEY_KP_1, "the second trim key is still Num 1")
	# a key used in another game only is not taken away
	taken = Keys.set_key("flaps", 1, KEY_H)
	ok(taken.is_empty() and Keys.keys_of("hyper")[0] == KEY_H, "H for flaps (Flight) leaves hyperspeed (Space) alone")
	# the same key in the action's other box moves over
	Keys.set_key("flaps", 0, KEY_H)
	ok(Keys.keys_of("flaps") == [KEY_H, 0], "the same key twice moves it: " + str(Keys.keys_of("flaps")))
	# emptying a box
	Keys.set_key("brake", 0, 0)
	ok(Keys.keys_of("brake") == [0, KEY_B] and Keys.first("brake") == "B", "emptied the first brake key")
	# controller buttons: a joystick button takes the clashing default away
	taken = Keys.set_button("trim_up", JOY_BUTTON_A, "Test Stick")
	ok(Keys.button_of("trim_up") == {"i": JOY_BUTTON_A, "name": "Test Stick"} and taken.size() == 1 and Keys.button_of("flaps").is_empty(), "button A to trim up, taken from flaps: " + str(taken))
	ok(not Keys.button_of("x10").is_empty(), "x10 (Space) keeps button A")
	ok(Keys.button_name(Keys.button_of("trim_up")) == "Button 1" and Keys.button_name(Keys.button_of("camera")) == "B", "button names")
	# what is saved survives a save and load (as the settings file does it)
	var cf := ConfigFile.new()
	cf.set_value("s", "binds", Keys.over)
	cf.save("user://test_keys.cfg")
	var cf2 := ConfigFile.new()
	cf2.load("user://test_keys.cfg")
	var before := str(Keys.keys_of("trim_up")) + str(Keys.button_of("trim_up")) + str(Keys.keys_of("brake"))
	Keys.over = cf2.get_value("s", "binds")
	ok(str(Keys.keys_of("trim_up")) + str(Keys.button_of("trim_up")) + str(Keys.keys_of("brake")) == before, "bindings survive saving and loading")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_keys.cfg"))
	Keys.reset_all()
	ok(Keys.keys_of("trim_up")[0] == KEY_BRACKETRIGHT and Keys.keys_of("data")[0] == KEY_T and not Keys.changed(), "back to the standard keys")
	print("FAILED: %d" % fails if fails > 0 else "ALL PASSED")
	quit(1 if fails > 0 else 0)
