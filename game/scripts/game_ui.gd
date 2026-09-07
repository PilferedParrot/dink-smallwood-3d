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
var dialogue_mode := false
var page := "title"
var text_scale := 1.0
var menu_theme: Theme
const CREAM := Color("eadfc2")
const GOLD := Color("d4ad62")
const GREEN := Color("182d27")

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_controller_navigation()
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Keep clicks and pointer events inside a menu from reaching the 3D world.
	root.mouse_filter = Control.MOUSE_FILTER_STOP
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
	panel.custom_minimum_size = Vector2(560, 420)
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
	panel.add_child(scroll)
	column = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	scroll.add_child(column)

func _ensure_controller_navigation() -> void:
	var buttons := {"ui_accept": JOY_BUTTON_A, "ui_cancel": JOY_BUTTON_B}
	for action in buttons:
		if not InputMap.has_action(action): InputMap.add_action(action)
		var event := InputEventJoypadButton.new()
		event.button_index = buttons[action]
		InputMap.action_add_event(action, event)
	var axes := {"ui_up": -1.0, "ui_down": 1.0}
	for action in axes:
		if not InputMap.has_action(action): InputMap.add_action(action)
		var event := InputEventJoypadMotion.new()
		event.axis = JOY_AXIS_LEFT_Y
		event.axis_value = axes[action]
		InputMap.action_add_event(action, event)

func _clear(title: String, next_page: String) -> void:
	for child in column.get_children():
		column.remove_child(child)
		child.queue_free()
	modal = true
	dialogue_mode = false
	page = next_page
	root.mouse_filter = Control.MOUSE_FILTER_STOP
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
	_label("A NEW DIMENSION", 20, GOLD)
	_label("A familiar world. A different perspective.\nA 3D adaptation by PilferedParrot.", 20)
	if has_save:
		_button("Continue adventure", "continue")
	_button("Begin adventure", "new_game")
	_button("Settings & controls", "settings")
	_button("Credits & support", "credits")
	_button("Quit", "quit")
	_label("Unofficial adaptation · Development release 0.1\nOriginal artwork and FreeDink sound", 16, Color("9dad95"))
	_focus()

func show_pause() -> void:
	_clear("A moment by the roadside", "pause")
	_button("Return to adventure", "resume")
	_button("Save adventure", "save")
	_button("Load saved adventure", "load")
	_button("Equipment", "inventory")
	_button("Adventure journal", "journal")
	_button("Settings & controls", "settings")
	_button("Credits & support", "credits")
	_button("Title screen", "title")
	_focus()

func show_hud(stats: Dictionary) -> void:
	hud.text = "DINK   •   Health %d / %d   •   Level %d   •   Gold %d\n%s" % [stats.get("life",10),stats.get("lifemax",10),stats.get("level",1),stats.get("gold",0),stats.get("location", "Stonebrook")]
	hint.text = "Move  WASD / Left stick     Talk  E / A     Attack  Space / X     Magic  Q / Y     Menu  Esc / Start"

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

func notify(text: String) -> void:
	toast.text = text
	var previous := text
	await get_tree().create_timer(4.0).timeout
	if toast.text == previous:
		toast.text = ""

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
	_label("Move: WASD / arrows / left stick\nTalk / confirm: E / A    Attack: Space / X\nMagic: Q / Y    Equipment: I / Back\nPause: Esc / Start    Camera: R / right stick\nMenus: arrows / D-pad, Enter / A, Esc / B", 18)
	for setting in [["master", "Master volume", 0.0, 1.0, 0.1], ["music", "Music volume", 0.0, 1.0, 0.1], ["sfx", "Sound effects", 0.0, 1.0, 0.1], ["text_scale", "Text size", 0.85, 1.3, 0.05], ["camera_angle", "Camera elevation", 35.0, 70.0, 5.0]]:
		var key: String = setting[0]
		_label(setting[1], 18, GOLD)
		var slider := HSlider.new()
		slider.min_value = setting[2]
		slider.max_value = setting[3]
		slider.step = setting[4]
		slider.value = float(settings.get(key, 1.0))
		slider.custom_minimum_size.y = roundi(30.0 * text_scale)
		slider.focus_mode = Control.FOCUS_ALL
		slider.value_changed.connect(_setting_changed.bind(key))
		column.add_child(slider)
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

func show_credits() -> void:
	_clear("A shared adventure", "credits")
	_label("3D adaptation · PilferedParrot\nOriginal Dink Smallwood · Seth A. Robinson\nArtwork · Justin Martin\nStory & world · Seth A. Robinson, Greg Smith, Justin Martin\nAdditional levels · Chris Bakker\nv1.08 fixes · Talmadge Bradley III\nFree audio · GNU FreeDink contributors\nEngine · Godot contributors", 20)
	_label("New code: Apache 2.0. Original art, story and audio retain their own licenses. Detailed attributions are bundled in licenses/. This is an unofficial, modified adaptation.", 18)
	_button("Support PilferedParrot on Patreon ↗", "patreon")
	_button("Source code & full credits ↗", "source")
	_button("Done", "back")
	_focus()
