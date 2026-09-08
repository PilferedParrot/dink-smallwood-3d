extends SceneTree

const UI = preload("res://scripts/game_ui.gd")
var received := ""
var payload: Variant
var failures: Array[String] = []
var choice := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _init() -> void:
	var ui := UI.new()
	root.add_child(ui)
	ui.action_requested.connect(_on_action)
	await process_frame
	ui.show_title(false)
	await process_frame
	ui.set_text_scale(1.3)
	check(ui.root.scale == Vector2.ONE, "Text scaling leaves root geometry unchanged")
	check(ui.root.get_viewport().gui_get_focus_owner() != null, "Title has controller focus")
	var down := InputEventJoypadMotion.new()
	down.device = 3
	down.axis = JOY_AXIS_LEFT_Y
	down.axis_value = 1.0
	Input.parse_input_event(down)
	await process_frame
	var neutral := InputEventJoypadMotion.new()
	neutral.device = 3
	neutral.axis = JOY_AXIS_LEFT_Y
	neutral.axis_value = 0.0
	Input.parse_input_event(neutral)
	await process_frame
	var accept := InputEventJoypadButton.new()
	accept.device = 3
	accept.button_index = JOY_BUTTON_A
	accept.pressed = true
	Input.parse_input_event(accept)
	await process_frame
	accept.pressed = false
	Input.parse_input_event(accept)
	await process_frame
	check(received == "settings", "Nonzero controller can navigate and activate title menu")
	ui.show_settings({})
	await process_frame
	await process_frame
	var first_slider: HSlider = root.gui_get_focus_owner() as HSlider
	check(first_slider != null, "Settings focuses its first slider")
	if first_slider != null:
		var before := first_slider.value
		await _axis(JOY_AXIS_LEFT_X, -1.0)
		check(first_slider.value < before, "Left stick adjusts a settings slider")
		check(received == "setting" and payload.key == "master", "Slider emits the correct setting key")
		await _button(JOY_BUTTON_DPAD_RIGHT)
		check(is_equal_approx(first_slider.value, before), "D-pad adjusts a settings slider")
	var controller_slider: HSlider
	var invert: CheckButton
	for node in ui.column.get_children():
		if node is HSlider and is_equal_approx(node.max_value, 4.0): controller_slider = node
		if node is CheckButton and node.text == "Invert controller vertical look": invert = node
	check(controller_slider != null and invert != null, "Controller settings are available")
	if controller_slider != null:
		controller_slider.grab_focus()
		await process_frame
		await process_frame
		var scroll: ScrollContainer = ui.column.get_parent()
		check(scroll.scroll_vertical > 0, "Menu scroll follows controller focus below the fold")
		await _button(JOY_BUTTON_DPAD_RIGHT)
		check(received == "setting" and payload.key == "controller_sensitivity" and is_equal_approx(payload.value, 2.1), "Controller sensitivity uses its default and emits adjustments")
	if invert != null:
		invert.grab_focus()
		await _button(JOY_BUTTON_A)
		check(received == "setting" and payload.key == "controller_invert_y" and payload.value == true, "A toggles controller look inversion")
	ui.dialogue_finished.connect(_on_choice)
	ui.show_choices("Choose", ["First", "Second"])
	await process_frame
	await _button(JOY_BUTTON_DPAD_DOWN)
	await _button(JOY_BUTTON_A)
	check(choice == 2 and not ui.modal, "D-pad and A select the correct dialogue choice")
	ui.show_inventory([{"name":"Fists"}, {"name":"Bow"}], [])
	await process_frame
	await _button(JOY_BUTTON_DPAD_DOWN)
	await _button(JOY_BUTTON_A)
	check(received == "equip" and payload == 1, "Controller equips the selected inventory item")
	check(ui.hint.text.contains("RT / X"), "Controller input shows controller hints")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	Input.parse_input_event(key)
	await process_frame
	key.pressed = false
	Input.parse_input_event(key)
	check(ui.hint.text.contains("WASD"), "Keyboard input restores keyboard hints")
	ui.queue_free()
	await process_frame
	if failures.is_empty(): print("UI CONTROLLER PASS: menus, sliders, scrolling, dialogue, inventory, hints")
	quit(0 if failures.is_empty() else 1)

func _on_action(action: String, value: Variant) -> void:
	received = action
	payload = value

func _on_choice(value: int) -> void:
	choice = value

func _button(button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 3
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func _axis(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 3
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)
	await process_frame
	event.axis_value = 0.0
	Input.parse_input_event(event)
	await process_frame
