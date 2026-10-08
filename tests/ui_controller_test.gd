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
	await process_frame
	# Headless Window starts at64x64; expand aspect would otherwise give a
	# square logical canvas rather than the player's1280x800 menu layout.
	root.size = Vector2i(1280, 800)
	await process_frame
	var ui := UI.new()
	root.add_child(ui)
	ui.action_requested.connect(_on_action)
	await process_frame
	ui.show_title(false)
	await process_frame
	ui.show_hud({"life": 4, "lifemax": 10, "weapon_item": {"script": "item-b1", "name": "Bow", "seq": 0}})
	check(not ui.status_dock.visible, "HUD refresh cannot expose the dock over the title")
	check(ui.status_dock.item_texture({"script": "item-b1", "seq": 0}) != null, "Starter bow has an icon before inventory opens")
	check(ui.status_dock.item_texture({"script": "item-b1", "seq": 0}).resource_path.ends_with("item-w08.png"), "Starter bow uses the original campaign bow icon, not clothing")
	ui.show_title(true)
	await process_frame
	await process_frame
	check(not ui.menu_scroll.get_v_scroll_bar().is_visible_in_tree(), "Default title fits with a saved-adventure Continue button")
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
	var music_slider: HSlider
	var music_readout: Label
	for node in ui.column.get_children():
		if node is HSlider and node.get_meta("setting_key", "") == "music": music_slider = node
		if node is Label and node.text.begins_with("Music volume"): music_readout = node
	check(music_slider != null and is_equal_approx(music_slider.value, 0.55) and music_readout.text.contains("55%"), "Music readout preserves the actual 55% default instead of rounding to 60%")
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
	var invert: Button
	for node in ui.column.get_children():
		if node is HSlider and is_equal_approx(node.max_value, 4.0): controller_slider = node
		if node is Button and node.get_meta("setting_key", "") == "controller_invert_y": invert = node
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
		check(invert.text.ends_with("On"), "Enabled toggle gives an explicit On state")
		await _button(JOY_BUTTON_A)
		check(invert.text.ends_with("Off") and not invert.button_pressed, "Disabled toggle gives an explicit Off state")
	ui.dialogue_finished.connect(_on_choice)
	ui.show_choices("Choose", ["First", "Second"])
	await process_frame
	await _button(JOY_BUTTON_DPAD_DOWN)
	await _button(JOY_BUTTON_A)
	check(choice == 2 and not ui.modal, "D-pad and A select the correct dialogue choice")
	ui.show_dialogue("A long line. ".repeat(80), "Mother")
	await process_frame
	check(ui.dialogue_continue.visible and ui.dialogue_continue.get_parent() != ui.column, "Continue remains outside scrolling dialogue text")
	check(not ui.status_dock.visible, "Dialogue hides the dock")
	await _button(JOY_BUTTON_A)
	check(not ui.modal, "A continues long dialogue")
	ui.show_inventory([{"name":"Fists"}, {"name":"Bow"}], [])
	await process_frame
	await _button(JOY_BUTTON_DPAD_RIGHT)
	await _button(JOY_BUTTON_A)
	check(received == "equip" and payload == 1, "Controller equips the selected inventory item")
	check(ui.hint.text.contains("D-pad") and ui.hint.text.contains("A"), "Controller input shows contextual menu hints")
	ui.close_menu()
	check(ui.hint.text.contains("RT / X"), "Closing a menu restores controller gameplay hints")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	Input.parse_input_event(key)
	await process_frame
	key.pressed = false
	Input.parse_input_event(key)
	check(ui.hint.text.contains("WASD"), "Keyboard input restores keyboard hints")
	var spells: Array = []
	for i in range(16): spells.append({"name": "Fireball %d" % i, "script": "item-fb", "seq": 437, "frame": 1})
	ui.show_inventory([], spells)
	await process_frame
	var chest = ui.column.get_node("EquipmentChest")
	check(chest._slot_buttons.size() == 8, "Magic chest presents eight selectable slots per page")
	chest._page_next.grab_focus()
	await _button(JOY_BUTTON_A)
	check(chest._spell_page == 1, "Controller can reach the second magic page")
	await _button(JOY_BUTTON_A)
	check(received == "equip_magic" and payload == 8, "Second magic page preserves the inventory index")
	ui.show_inventory([{"name": "Pig feed", "script": "item-pig"}], [])
	await process_frame
	await process_frame
	ui.menu_footer.grab_focus()
	await process_frame
	check(ui.heading.get_global_rect().end.y <= ui.menu_scroll.get_global_rect().position.y, "Equipment heading remains pinned while Back is focused")
	check(ui.menu_footer.get_global_rect().end.y <= ui.panel.get_global_rect().end.y, "Equipment Back remains inside panel")
	check(ui.equipment_name.text.contains("Pig feed") and not ui.equipment_name.text.contains("…"), "Selected item name is complete outside the scrolling chest")
	ui.close_menu()
	ui.set_text_scale(1.0)
	ui.show_pause()
	await process_frame
	await process_frame
	await process_frame
	check(ui.menu_scroll.scroll_vertical == 0, "Pause resets scrolling after equipment")
	check(ui.heading.get_global_rect().end.y <= ui.menu_scroll.get_global_rect().position.y, "Pause heading remains outside scrolling content")
	check(ui.column.get_child(ui.column.get_child_count() - 1).get_global_rect().end.y <= ui.menu_scroll.get_global_rect().end.y, "Default1280x800 pause shows the complete final action")
	ui.show_settings({})
	await process_frame
	await process_frame
	await process_frame
	check(ui.menu_scroll.scroll_vertical == 0, "Settings starts at its heading and instructions")
	ui.request_back()
	check(received == "pause", "Back from settings opened in pause requests its parent menu")
	ui.show_pause()
	ui.show_journal("A journal entry")
	ui.request_back()
	check(received == "pause", "Back from journal requests pause rather than resuming")
	ui.show_title(false)
	ui.show_settings({})
	ui.request_back()
	check(received == "title", "Back from title settings returns to title")
	ui.close_menu()
	ui.show_inventory([], [])
	ui.request_back()
	check(received == "resume", "Standalone equipment Back resumes gameplay")
	ui.notify("Equipped Fists")
	check(ui.modal_feedback.visible and not ui.toast_backing.visible, "Menu notifications use their own header space")
	ui.show_settings({})
	check(not ui.modal_feedback.visible and ui.toast.text.is_empty(), "Changing page clears stale notification instead of covering the heading")
	ui.close_menu()
	ui.notify("Equipped Fists")
	check(ui.toast_backing.visible, "Gameplay notifications have solid contrast backing")
	ui._clear_toast()
	check(not ui.toast_backing.visible, "Expired notifications remove their backing")
	ui.close_menu()
	ui.gameplay_hint_used = false
	ui._process(0.0)
	check(ui.hint_backing.visible, "New player receives gameplay control hints")
	var movement := InputEventKey.new()
	movement.physical_keycode = KEY_W
	movement.pressed = true
	ui._input(movement)
	ui.gameplay_hint_deadline_msec = Time.get_ticks_msec() - 1
	ui._process(0.0)
	check(not ui.hint_backing.visible, "Gameplay hints fade after first use")
	var help := InputEventKey.new()
	help.physical_keycode = KEY_F1
	help.pressed = true
	Input.parse_input_event(help)
	await process_frame
	await process_frame
	check(ui.hint_backing.visible, "F1 recalls gameplay controls through the actual input path")
	help.pressed = false
	Input.parse_input_event(help)
	ui.show_pause()
	ui._process(0.0)
	check(ui.hint_backing.visible and is_equal_approx(ui.hint_backing.modulate.a, 1.0), "Menu instructions stay visible after gameplay help fades")
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
