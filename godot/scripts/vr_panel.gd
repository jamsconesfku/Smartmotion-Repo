class_name VRPanel
extends Node3D
## The game's real menus inside the headset. While VR is on, the menu screens (GameUI) are drawn into a
## SubViewport and shown on a floating panel in front of you. Point with either controller (an orange beam)
## and pull the trigger to click; push the stick up/down to scroll. Stick up/down and A also move through
## the buttons without pointing. The same picture is shown on the laptop screen, where the mouse still works.

const PX := Vector2i(1600, 900)
const SIZE_M := Vector2(1.44, 0.81)

var sub: SubViewport
var quad: MeshInstance3D
var ui: GameUI
var ui_home: Node
var beam: MeshInstance3D
var dot: MeshInstance3D
var mirror: CanvasLayer
var mirror_rect: TextureRect
var aims := {}                  # side -> XRController3D using the aim pose
var hand := "r"
var down := false
var last_px := Vector2(-1, -1)
var scroll_t := 0.0
var edge := {}
var shown := false


func setup(ui_: GameUI, home: Node, origin: XROrigin3D) -> void:
	ui = ui_
	ui_home = home
	sub = SubViewport.new()
	sub.size = PX
	sub.transparent_bg = true
	sub.gui_embed_subwindows = true
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sub)
	ui.get_parent().remove_child(ui)
	sub.add_child(ui)
	quad = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = SIZE_M
	quad.mesh = qm
	var m := StandardMaterial3D.new()
	m.albedo_texture = sub.get_texture()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.no_depth_test = true
	m.render_priority = 20
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	quad.material_override = m
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(quad)
	beam = MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.002
	bm.bottom_radius = 0.004
	bm.height = 1.0
	bm.radial_segments = 6
	bm.rings = 1
	beam.mesh = bm
	var beam_m := GameMode.glow_mat(Color(1.0, 0.35, 0.05), 2.0)
	beam_m.no_depth_test = true
	beam_m.render_priority = 21
	beam.material_override = beam_m
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	dot = MeshInstance3D.new()
	var dm := SphereMesh.new()
	dm.radius = 0.008
	dm.height = 0.016
	dm.radial_segments = 8
	dm.rings = 4
	dot.mesh = dm
	dot.material_override = beam_m
	add_child(dot)
	for side in ["l", "r"]:
		var c := XRController3D.new()
		c.tracker = "left_hand" if side == "l" else "right_hand"
		c.pose = &"aim"
		origin.add_child(c)
		aims[side] = c
	# the same picture on the laptop screen (the headset view is behind it)
	mirror = CanvasLayer.new()
	mirror.layer = 50
	mirror_rect = TextureRect.new()
	mirror_rect.texture = sub.get_texture()
	mirror_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	mirror_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mirror_rect.stretch_mode = TextureRect.STRETCH_SCALE
	mirror_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mirror.add_child(mirror_rect)
	home.add_child(mirror)
	show_panel(false, Transform3D())


## Puts the menus back on the laptop screen (when VR ends).
func teardown() -> void:
	if ui != null and ui.get_parent() == sub:
		sub.remove_child(ui)
		ui_home.add_child(ui)
	if mirror != null:
		mirror.queue_free()
	for c in aims.values():
		(c as Node3D).queue_free()
	aims = {}


## Shows the panel 0.95 m in front of where the head is (in the vehicle's frame), turned to face it.
func show_panel(on: bool, head: Transform3D) -> void:
	shown = on
	visible = on   # the laptop screen keeps showing the menus and the HUD (mirror) either way
	if not on:
		return
	var fwd := -head.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.1:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	var centre := head.origin + fwd * 0.95 + Vector3(0, -0.08, 0)
	if ui.menu.visible and not ui.any_sheet():
		centre += right * 0.38   # the main menu card sits on the left of the screen: bring it in front of you
	transform = Transform3D(Basis(right, Vector3.UP, -fwd), centre)
	for k in ["a", "u", "d", "trig_l", "trig_r"]:
		edge[k] = true
	_focus_first()


func _edge(k: String, v: bool) -> bool:
	var was: bool = edge.get(k, false)
	edge[k] = v
	return v and not was


func _focus_first() -> void:
	var layer: Control = null
	for s in [ui.lobby, ui.end_sheet, ui.controls_sheet, ui.help_sheet, ui.settings_sheet, ui.pause_sheet]:
		if (s as Control).visible:
			layer = s
			break
	if layer == null and ui.menu.visible:
		layer = ui.menu
	if layer == null:
		return
	var b := ui.fly_btn if layer == ui.menu else _first_button(layer, layer == ui.lobby)
	if b != null:
		b.grab_focus.call_deferred()


func _first_button(n: Node, toggles := false) -> Button:
	for c in n.get_children():
		if c is Button and (c as Button).is_visible_in_tree() and (toggles or not (c as Button).toggle_mode):
			return c
		var r := _first_button(c, toggles)
		if r != null:
			return r
	return null


func _push_action(a: String) -> void:
	var ev := InputEventAction.new()
	ev.action = a
	ev.pressed = true
	sub.push_input(ev)
	var ev2 := InputEventAction.new()
	ev2.action = a
	ev2.pressed = false
	sub.push_input(ev2)


func _push_mouse(px: Vector2, button := 0, pressed := false) -> void:
	if button == 0:
		var mm := InputEventMouseMotion.new()
		mm.position = px
		mm.global_position = px
		mm.relative = px - last_px if last_px.x >= 0.0 else Vector2.ZERO
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		sub.push_input(mm)
	else:
		var mb := InputEventMouseButton.new()
		mb.position = px
		mb.global_position = px
		mb.button_index = button
		mb.pressed = pressed
		mb.button_mask = MOUSE_BUTTON_MASK_LEFT if (pressed and button == MOUSE_BUTTON_LEFT) else 0
		sub.push_input(mb)


## Per frame while shown: aim, click, scroll. ctl: {"l": XRController3D, "r": XRController3D} (for buttons).
func update(ctl: Dictionary, dt: float) -> void:
	if not shown:
		return
	# which hand points: the one whose trigger was pulled last
	for side in ["l", "r"]:
		var c: XRController3D = ctl.get(side)
		if c != null and c.get_is_active() and c.get_float("trigger") > 0.6:
			hand = side
	var c2: XRController3D = ctl.get(hand)
	var aim: XRController3D = aims.get(hand)
	var src: Transform3D
	if aim != null and aim.get_has_tracking_data():
		src = aim.global_transform
	elif c2 != null and c2.get_has_tracking_data():
		src = c2.global_transform.rotated_local(Vector3.RIGHT, -0.6)   # grip pose tilted to point forwards
	else:
		beam.visible = false
		dot.visible = false
		_buttons(ctl, dt)
		return
	var o := global_transform.affine_inverse() * src.origin
	var d := (global_transform.basis.inverse() * -src.basis.z).normalized()
	var hit := false
	var px := Vector2.ZERO
	var hp := Vector3.ZERO
	if absf(d.z) > 0.0001:
		var t := -o.z / d.z
		if t > 0.0:
			hp = o + d * t
			if absf(hp.x) <= SIZE_M.x / 2.0 and absf(hp.y) <= SIZE_M.y / 2.0:
				hit = true
				px = Vector2((hp.x / SIZE_M.x + 0.5) * PX.x, (0.5 - hp.y / SIZE_M.y) * PX.y)
	var end_g := src.origin + (-src.basis.z) * (0.6 if not hit else (global_transform * hp).distance_to(src.origin))
	var len := src.origin.distance_to(end_g)
	beam.visible = true
	var bd := (end_g - src.origin).normalized()
	var up := Vector3.UP if absf(bd.y) < 0.99 else Vector3.RIGHT
	var x := up.cross(bd).normalized()
	beam.global_transform = Transform3D(Basis(x, bd, x.cross(bd)).scaled(Vector3(1, len, 1)), (src.origin + end_g) * 0.5)
	dot.visible = hit
	if hit:
		dot.global_position = global_transform * hp
		if px.distance_to(last_px) > 0.5:
			_push_mouse(px)
		last_px = px
	var trig := c2 != null and c2.get_is_active() and c2.get_float("trigger") > 0.6
	if _edge("trig_" + hand, trig) and hit:
		down = true
		_push_mouse(px, MOUSE_BUTTON_LEFT, true)
	elif not trig and down:
		down = false
		_push_mouse(last_px, MOUSE_BUTTON_LEFT, false)
	_buttons(ctl, dt)
	if hit and c2 != null and c2.get_is_active():
		var sy := c2.get_vector2("primary").y
		scroll_t -= dt
		if absf(sy) > 0.6 and scroll_t <= 0.0:
			scroll_t = 0.12
			_push_mouse(px, MOUSE_BUTTON_WHEEL_UP if sy > 0.0 else MOUSE_BUTTON_WHEEL_DOWN, true)


func _buttons(ctl: Dictionary, _dt: float) -> void:
	# without pointing: stick up/down moves between buttons, A presses the highlighted one
	var y := 0.0
	var a := false
	for side in ["l", "r"]:
		var c: XRController3D = ctl.get(side)
		if c == null or not c.get_is_active():
			continue
		var v := c.get_vector2("primary").y
		if absf(v) > absf(y) and (side != hand or not dot.visible):
			y = v
		if side == "r":
			a = c.is_button_pressed("ax_button")
	if _edge("u", y > 0.7):
		_push_action("ui_up")
	if _edge("d", y < -0.7):
		_push_action("ui_down")
	if _edge("a", a):
		_push_action("ui_accept")


## Mouse on the laptop screen while VR is on: passed on to the menus on the panel.
func desktop_mouse(e: InputEvent, screen: Vector2) -> bool:
	if not shown or not (e is InputEventMouse):
		return false
	var ev := e.duplicate() as InputEventMouse
	var p := (e as InputEventMouse).position / screen * Vector2(PX)
	ev.position = p
	ev.global_position = p
	sub.push_input(ev)
	return true
