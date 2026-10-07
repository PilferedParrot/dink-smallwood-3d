# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
extends CanvasLayer
signal action_requested(action: String, payload: Variant)
signal dialogue_finished(choice: int)
var modal := true
var root: Control
var overlay: ColorRect
var panel: PanelContainer
var column: VBoxContainer
var hud: Label
var hint: Label
var toast: Label
var crosshair: Label
var health_bar: ProgressBar
var mana_bar: ProgressBar
var compass_label: Label
var toast_timer: Timer
var dialogue_mode := false
var page := "title"
var text_scale := 1.0
var menu_theme: Theme
var controller_active := false
const CREAM := Color("eadfc2")
const GOLD := Color("d4ad62")
const GREEN := Color("182d27")

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_controller_navigation()
	controller_active = not Input.get_connected_joypads().is_empty()
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Keep clicks and pointer events inside a menu from reaching the 3D world.
	# Let mouse input reach the first-person camera during gameplay.
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	menu_theme = Theme.new()
	menu_theme.default_font_size = 22
	menu_theme.set_color("font_color", "Label", CREAM)
	for state in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color("30453a") if state == "normal" else Color("51644a")
		box.border_color = GOLD if state == "focus" else Color("637450")
		box.set_border_width_all(3 if state == "focus" else 1)
		box.set_corner_radius_all(5)
		box.content_margin_left = 20
		box.content_margin_right = 20
		box.content_margin_top = 12
		box.content_margin_bottom = 12
		menu_theme.set_stylebox(state, "Button", box)
	menu_theme.set_color("font_color", "Button", CREAM)
	menu_theme.set_color("font_hover_color", "Button", Color.WHITE)
	menu_theme.set_color("font_focus_color", "Button", Color.WHITE)
	root.theme = menu_theme
	hud = Label.new()
	hud.position = Vector2(28, 22)
	hud.add_theme_color_override("font_shadow_color", Color.BLACK)
	hud.add_theme_constant_override("shadow_offset_x", 2)
	hud.add_theme_constant_override("shadow_offset_y", 2)
	root.add_child(hud)
	health_bar = _make_bar(Color("a94f42"))
	health_bar.position = Vector2(28, 124)
	health_bar.size = Vector2(190, 14)
	root.add_child(health_bar)
	mana_bar = _make_bar(Color("4f7891"))
	mana_bar.position = Vector2(28, 144)
	mana_bar.size = Vector2(190, 10)
	root.add_child(mana_bar)
	compass_label = Label.new()
	compass_label.anchor_left = 0.5
	compass_label.anchor_right = 0.5
	compass_label.offset_left = -30
	compass_label.offset_top = 24
	compass_label.add_theme_color_override("font_color", GOLD)
	compass_label.add_theme_font_size_override("font_size", 18)
	compass_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(compass_label)
	crosshair = Label.new()
	crosshair.text = "+"
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.offset_left = -8; crosshair.offset_right = 8
	crosshair.offset_top = -14; crosshair.offset_bottom = 14
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.add_theme_color_override("font_color", Color(1, 0.94, 0.72, 0.82))
	crosshair.add_theme_font_size_override("font_size", 24)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(crosshair)
	hint = Label.new()
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -48
	hint.offset_left = 28
	hint.add_theme_font_size_override("font_size", 18)
	root.add_child(hint)
	toast = Label.new()
	toast.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	toast.offset_top = 65
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_color_override("font_color", GOLD)
	root.add_child(toast)
	toast_timer = Timer.new()
	toast_timer.one_shot = true
	toast_timer.wait_time = 4.0
	toast_timer.timeout.connect(_clear_toast)
	add_child(toast_timer)
	overlay = ColorRect.new()
	overlay.color = Color(0.01, 0.025, 0.018, 0.78)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(overlay)
	panel = PanelContainer.new()
	panel.anchor_left = 0.08
	panel.anchor_right = 0.92
	panel.anchor_top = 0.07
	panel.anchor_bottom = 0.93
	panel.offset_left = 0
	panel.offset_right = 0
	panel.offset_top = 0
	panel.offset_bottom = 0
	panel.custom_minimum_size = Vector2(420, 300)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("15241f")
	style.border_color = Color("8c7950")
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 32
	style.content_margin_right = 32
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	panel.add_child(scroll)
	column = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	scroll.add_child(column)
	_set_playing_visuals(false)

func _make_bar(fill: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = 100
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("26342c"); bg.set_corner_radius_all(4)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill; fg.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	return bar

func _set_playing_visuals(playing: bool) -> void:
	if is_instance_valid(crosshair): crosshair.visible = playing
	if is_instance_valid(health_bar): health_bar.visible = playing
	if is_instance_valid(mana_bar): mana_bar.visible = playing
	if is_instance_valid(compass_label): compass_label.visible = playing

func _layout_for(next_page: String) -> void:
	if next_page == "title":
		panel.anchor_left = 0.055; panel.anchor_right = 0.43
		panel.anchor_top = 0.10; panel.anchor_bottom = 0.90
		overlay.color = Color(0.01, 0.025, 0.018, 0.32)
	elif next_page == "dialogue":
		panel.anchor_left = 0.055; panel.anchor_right = 0.945
		panel.anchor_top = 0.60; panel.anchor_bottom = 0.97
		overlay.color = Color(0.01, 0.025, 0.018, 0.18)
	else:
		panel.anchor_left = 0.14; panel.anchor_right = 0.86
		panel.anchor_top = 0.07; panel.anchor_bottom = 0.93
		overlay.color = Color(0.01, 0.025, 0.018, 0.70)

func _ensure_controller_navigation() -> void:
	var buttons := {"ui_accept": JOY_BUTTON_A, "ui_cancel": JOY_BUTTON_B, "ui_up": JOY_BUTTON_DPAD_UP, "ui_down": JOY_BUTTON_DPAD_DOWN, "ui_left": JOY_BUTTON_DPAD_LEFT, "ui_right": JOY_BUTTON_DPAD_RIGHT}
	for action in buttons:
		if not InputMap.has_action(action): InputMap.add_action(action)
		var event := InputEventJoypadButton.new()
		event.device = -1
		event.button_index = buttons[action]
		if not InputMap.action_has_event(action, event): InputMap.action_add_event(action, event)
	var axes := {"ui_up": [JOY_AXIS_LEFT_Y, -1.0], "ui_down": [JOY_AXIS_LEFT_Y, 1.0], "ui_left": [JOY_AXIS_LEFT_X, -1.0], "ui_right": [JOY_AXIS_LEFT_X, 1.0]}
	for action in axes:
		if not InputMap.has_action(action): InputMap.add_action(action)
		var event := InputEventJoypadMotion.new()
		event.device = -1
		event.axis = axes[action][0]
		event.axis_value = axes[action][1]
		if not InputMap.action_has_event(action, event): InputMap.action_add_event(action, event)

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed or event is InputEventJoypadMotion and absf(event.axis_value) > 0.25:
		controller_active = true
	elif event is InputEventKey and event.pressed or event is InputEventMouseButton and event.pressed or event is InputEventMouseMotion and event.relative.length() > 2.0:
		controller_active = false
	else:
		return
	_update_hint()

func _update_hint() -> void:
	if not is_instance_valid(hint): return
	if controller_active:
		hint.text = "LS  Move   RS  Aim   RT / X  Attack   LT / Y  Magic   A  Talk   LB / RB  Weapon   Back  Equipment   Start  Pause"
	else:
		hint.text = "WASD  Move     Mouse  Aim     Left click  Attack     Right click  Magic     E  Talk     I  Equipment     Esc  Pause"

func _clear(title: String, next_page: String) -> void:
	for child in column.get_children():
		column.remove_child(child)
		child.queue_free()
	modal = true
	dialogue_mode = false
	page = next_page
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	_layout_for(next_page)
	_set_playing_visuals(false)
	overlay.show()
	panel.show()
	_label(title, 32, GOLD)

func _label(text: String, size: int = 22, color: Color = CREAM) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", roundi(float(size) * text_scale))
	label.add_theme_color_override("font_color", color)
	column.add_child(label)
	label.set_meta("base_font_size", size)
	return label

func _button(text: String, action: String, value: Variant = null) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = roundi(48.0 * text_scale)
	button.set_meta("base_minimum_height", 48)
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(_button_pressed.bind(action, value))
	column.add_child(button)
	return button

func _button_pressed(action: String, value: Variant) -> void:
	action_requested.emit(action, value)

func _focus() -> void:
	for child in column.get_children():
		if child is Control and child.focus_mode != Control.FOCUS_NONE:
			if child is BaseButton and child.disabled: continue
			child.call_deferred("grab_focus")
			break

func set_text_scale(value: float) -> void:
	text_scale = clampf(value, 0.85, 1.3)
	if not is_instance_valid(root): return
	menu_theme.default_font_size = roundi(22.0 * text_scale)
	hint.add_theme_font_size_override("font_size", roundi(18.0 * text_scale))
	toast.add_theme_font_size_override("font_size", roundi(22.0 * text_scale))
	for node in column.get_children():
		if node.has_meta("base_font_size"):
			node.add_theme_font_size_override("font_size", roundi(float(node.get_meta("base_font_size")) * text_scale))
		if node.has_meta("base_minimum_height"):
			node.custom_minimum_size.y = roundi(float(node.get_meta("base_minimum_height")) * text_scale)

func show_title(has_save: bool) -> void:
	_clear("DINK SMALLWOOD", "title")
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	_label("FIRST-PERSON ADVENTURE · VERSION %s" % version, 16, GOLD)
	_label("A familiar world. A different perspective.\nA 3D adaptation by PilferedParrot.", 20)
	if has_save:
		_button("Continue adventure", "continue")
	_button("Begin adventure", "new_game")
	_button("Settings & controls", "settings")
	_button("Credits & support", "credits")
	_button("Quit", "quit")
	_label("Unofficial adaptation · Development release %s\nBlender-built world and FreeDink sound" % version, 16, Color("9dad95"))
	_focus()

func show_pause() -> void:
	_clear("A moment by the roadside", "pause")
	_button("Return to adventure", "resume")
	_button("Save adventure", "save")
	_button("Load saved adventure", "load")
	_button("Equipment", "inventory")
	_button("Adventure journal", "journal")
	_button("World map", "map")
	_button("Settings & controls", "settings")
	_button("Credits & support", "credits")
	_button("Title screen", "title")
	_focus()

func show_hud(stats: Dictionary) -> void:
	var life := float(stats.get("life", 10)); var life_max := maxf(float(stats.get("lifemax", 10)), 1.0)
	var mana := float(stats.get("magic_level", 0)); var mana_max := maxf(float(stats.get("magic_cost", 100)), 1.0)
	health_bar.value = clampf(life / life_max * 100.0, 0.0, 100.0)
	mana_bar.value = clampf(mana / mana_max * 100.0, 0.0, 100.0)
	hud.text = "DINK   •   Health %d / %d   •   Level %d   •   Gold %d\n%s" % [life,life_max,stats.get("level",1),stats.get("gold",0),stats.get("location", "Stonebrook")]
	var weapon := str(stats.get("weapon", stats.get("weapon_name", "")))
	if not weapon.is_empty(): hud.text += "\nWeapon: " + weapon
	compass_label.text = str(stats.get("compass", ""))
	_update_hint()

func show_dialogue(text: String, speaker: String = "Dink") -> void:
	_clear(speaker, "dialogue")
	dialogue_mode = true
	_label(text, 26)
	var button := Button.new()
	button.text = "Continue   ›"
	button.custom_minimum_size.y = roundi(52.0 * text_scale)
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(_continue_dialogue)
	column.add_child(button)
	_focus()

func _continue_dialogue() -> void:
	hide_dialogue()
	dialogue_finished.emit(0)

func show_choices(title: String, options: Array) -> void:
	_clear(title if not title.is_empty() else "What will you do?", "dialogue")
	dialogue_mode = true
	for i in range(options.size()):
		var button := Button.new()
		button.text = str(options[i])
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size.y = roundi(48.0 * text_scale)
		button.focus_mode = Control.FOCUS_ALL
		button.pressed.connect(_choose_dialogue.bind(i + 1))
		column.add_child(button)
	_focus()

func _choose_dialogue(choice: int) -> void:
	hide_dialogue()
	dialogue_finished.emit(choice)

func hide_dialogue() -> void:
	close_menu()
	dialogue_mode = false

func close_menu() -> void:
	modal = false
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.hide()
	overlay.hide()
	page = "game"
	_set_playing_visuals(true)

func _clear_toast() -> void:
	toast.text = ""

func notify(text: String) -> void:
	toast.text = text
	toast_timer.start()

func show_inventory(items: Array, magic_items: Array) -> void:
	_clear("Your equipment", "inventory")
	_label("Choose an item to equip or use it.", 18)
	for i in range(items.size()):
		_button(str(items[i].get("name", items[i].get("script", "Item"))).capitalize(), "equip", i)
	if not magic_items.is_empty():
		_label("Magic", 24, GOLD)
		for i in range(magic_items.size()):
			_button(str(magic_items[i].get("name",magic_items[i].get("script","Spell"))).capitalize(), "equip_magic", i)
	_button("Back to adventure", "resume")
	_focus()

func show_journal(text: String) -> void:
	_clear("Adventure journal", "journal")
	_label(text, 22)
	_button("Back to adventure", "resume")
	_focus()

func show_settings(settings: Dictionary) -> void:
	_clear("Make yourself comfortable", "settings")
	_label("Move: WASD / left stick    Aim: mouse / right stick\nAttack: left click / RT / X    Magic: right click / LT / Y\nTalk: E / A    Jump: Space / right stick click    Sprint: Shift / left stick click    Equipment: I / Back (Select)\nQuick weapons: 1–9 / LB and RB    Pause: Esc / Start\nWorld map: M or Pause → World map (once received)\nMenus: arrows / D-pad / left stick, Enter / A, Esc / B\nController labels use the Xbox layout; other mapped gamepads use the same button positions.", 18)
	for setting in [["master", "Master volume", 0.0, 1.0, 0.1, 0.8], ["music", "Music volume", 0.0, 1.0, 0.1, 0.55], ["sfx", "Sound effects", 0.0, 1.0, 0.1, 0.8], ["text_scale", "Text size", 0.85, 1.3, 0.05, 1.0], ["mouse_sensitivity", "Mouse sensitivity", 0.0005, 0.006, 0.0005, 0.002], ["fov", "Field of view", 60.0, 105.0, 1.0, 80.0], ["controller_sensitivity", "Controller look sensitivity", 0.5, 4.0, 0.1, 2.0], ["controller_deadzone", "Controller stick dead zone", 0.05, 0.4, 0.05, 0.2]]:
		var key: String = setting[0]
		_label(setting[1], 18, GOLD)
		var slider := HSlider.new()
		slider.min_value = setting[2]
		slider.max_value = setting[3]
		slider.step = setting[4]
		slider.value = float(settings.get(key, setting[5]))
		slider.custom_minimum_size.y = roundi(30.0 * text_scale)
		slider.focus_mode = Control.FOCUS_ALL
		slider.value_changed.connect(_setting_changed.bind(key))
		column.add_child(slider)
	var invert := CheckButton.new()
	invert.text = "Invert controller vertical look"
	invert.focus_mode = Control.FOCUS_ALL
	invert.button_pressed = settings.get("controller_invert_y", false)
	invert.toggled.connect(_controller_invert_changed)
	column.add_child(invert)
	var reduced := CheckButton.new()
	reduced.text = "Reduce camera movement"
	reduced.focus_mode = Control.FOCUS_ALL
	reduced.button_pressed = settings.get("reduced_motion", false)
	reduced.toggled.connect(_reduced_motion_changed)
	column.add_child(reduced)
	_button("Done", "back")
	_focus()

func _setting_changed(value: float, key: String) -> void:
	action_requested.emit("setting", {"key": key, "value": value})

func _reduced_motion_changed(value: bool) -> void:
	action_requested.emit("setting", {"key": "reduced_motion", "value": value})

func _controller_invert_changed(value: bool) -> void:
	action_requested.emit("setting", {"key": "controller_invert_y", "value": value})

func show_credits() -> void:
	_clear("A shared adventure", "credits")
	_label("3D adaptation · PilferedParrot\nOriginal Dink Smallwood · Seth A. Robinson\nArtwork · Justin Martin\nStory & world · Seth A. Robinson, Greg Smith, Justin Martin\nAdditional levels · Chris Bakker\nv1.08 fixes · Talmadge Bradley III\nFree audio · GNU FreeDink contributors\nEngine · Godot contributors", 20)
	_label("New code: Apache 2.0. Original art, story and audio retain their own licenses. Detailed attributions are bundled in licenses/. This is an unofficial, modified adaptation.", 18)
	_button("Support PilferedParrot on Patreon ↗", "patreon")
	_button("Source code & full credits ↗", "source")
	_button("Done", "back")
	_focus()
