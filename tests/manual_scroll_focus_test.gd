# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
extends SceneTree
## UI fixture with real key events. After the player scrolls the page by hand, changing
## the still-focused Text size slider must not leave it out of sight.
const UI = preload("res://scripts/game_ui.gd")
var ui
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func settle() -> void:
	for _i in 12: await process_frame

func tap(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
	await settle()

func wheel_down() -> void:
	var at: Vector2 = root.get_final_transform() * ui.menu_scroll.get_global_rect().get_center()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_WHEEL_DOWN
		event.pressed = pressed
		event.position = at
		event.global_position = at
		root.push_input(event)
		await process_frame
	await settle()

func run() -> void:
	root.size = Vector2i(1280, 800)
	for mode in ["none", "pagekey", "wheel"]:
		for plain in [false, true]:
			ui = UI.new()
			root.add_child(ui)
			ui.action_requested.connect(func(action: String, payload: Dictionary) -> void:
				if action == "setting" and payload.key == "text_scale": ui.set_text_scale(payload.value))
			ui.set_plain_font(plain)
			ui.set_text_scale(1.0)
			ui.show_settings({"text_scale": 1.0, "plain_font": plain})
			await settle()
			var slider: HSlider
			for node in ui.column.get_children():
				if node.get_meta("setting_key", "") == "text_scale": slider = node
			slider.grab_focus()
			await settle()
			if mode == "pagekey": await tap(KEY_PAGEDOWN)
			if mode == "wheel": await wheel_down()
			var scrolled: bool = ui.menu_scroll.scroll_vertical > 0
			if mode != "none": check(scrolled, "%s plain=%s: the manual scroll moved the page" % [mode, plain])
			if mode != "none":
				var held: int = ui.menu_scroll.scroll_vertical
				await settle()
				check(ui.menu_scroll.scroll_vertical == held, "%s plain=%s: with no interaction the manual position still wins" % [mode, plain])
			var hidden := 0
			for _i in 20:
				await tap(KEY_RIGHT)
				if not ui.menu_scroll.get_global_rect().grow(1).encloses(slider.get_global_rect()): hidden += 1
			check(ui.get_viewport().gui_get_focus_owner() == slider, "%s plain=%s: the slider keeps focus" % [mode, plain])
			check(hidden == 0, "%s plain=%s: the focused slider was out of sight for %d of 20 steps" % [mode, plain, hidden])
			print("MANUAL FOCUS mode=", mode, " plain=", plain, " hidden_steps=", hidden, " scale=", ui.text_scale)
			ui.queue_free()
			await process_frame
	print("MANUAL SCROLL FOCUS PASS" if failures.is_empty() else "MANUAL SCROLL FOCUS FAIL " + str(failures.size()))
	quit(0 if failures.is_empty() else 1)
