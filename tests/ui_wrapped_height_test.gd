extends SceneTree

const GAME = preload("res://scripts/fps_game.gd")
var game
var failures: Array[String] = []
var output_dir := ""

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func settle() -> void:
	for _i in 6: await process_frame

func key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
	await settle()

func frame(tag: String) -> void:
	if output_dir.is_empty(): return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output_dir.path_join(tag + ".png"))

func check_toast(label: String) -> void:
	var backing: PanelContainer = game.ui.toast_backing
	var text: Label = game.ui.toast
	var lines := text.get_line_count()
	var content_height := 0.0
	for line in lines: content_height += text.get_line_height(line)
	content_height += maxf(0, lines - 1) * text.get_theme_constant("line_spacing")
	var style := backing.get_theme_stylebox("panel")
	content_height += style.get_content_margin(SIDE_TOP) + style.get_content_margin(SIDE_BOTTOM)
	print("HEIGHT ", label, " actual=", backing.size.y, " text-and-margins=", content_height)
	check(absf(backing.size.y - content_height) <= 2.0, label + ": notification height follows measured text and margins")
	check(backing.size.y <= game.ui.root.size.y * 0.35, label + ": notification leaves the world visible")

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out-dir="): output_dir = arg.trim_prefix("--out-dir=")
	root.size = Vector2i(1280, 800)
	game = GAME.new()
	# Fixture bypasses source dialogue progression to exercise UI geometry and
	# notifications deterministically; menu actions use actual key events.
	game.test_mode = true
	root.add_child(game)
	await game._new_game()
	await settle()
	check_toast("early-new-game")
	await frame("00-startup-toast")
	var ui = game.ui
	ui.notify("A multi-line notification.\nSecond line.\nThird line.\nFourth line.")
	await settle()
	check_toast("multi-line")
	var long_height: float = ui.toast_backing.size.y
	ui.notify("Short notification.")
	await settle()
	check_toast("long-to-short")
	check(ui.toast_backing.size.y < long_height, "Replacing a long notification shrinks its plaque")
	await frame("01-short-toast")
	# Esc and keyboard activation follow the same path as the exported game.
	await key(KEY_ESCAPE)
	check(ui.page == "pause", "Actual Escape opens pause")
	ui.notify("Adventure saved.")
	await settle()
	check(ui.modal_feedback.visible and not ui.toast_backing.visible, "Pause owns notification feedback")
	check(ui.modal_feedback.size.y < ui.root.size.y * 0.35, "Pause notification fits its header")
	await frame("02-pause")
	for _i in 8: await key(KEY_DOWN)
	await key(KEY_ENTER)
	check(ui.page == "title" and not game.playing, "Keyboard selects return to title")
	check(not ui.toast_backing.visible, "Title clears gameplay notification")
	await frame("03-title")
	await key(KEY_ENTER)
	check(ui.page == "game" and game.playing, "Keyboard begins a new adventure")
	check_toast("input-new-game")
	await frame("04-input-new-game")
	# All wrapped text types have a layout owner: notifications, hints,
	# dialogue/choices and menu headings/body/actions/equipment descriptions.
	for window_size in [Vector2i(960, 540), Vector2i(1280, 800), Vector2i(1920, 1080)]:
		root.size = window_size
		for scale in [0.85, 1.0, 1.3]:
			ui.set_text_scale(scale)
			ui.close_menu()
			ui.notify("A notice that wraps when its available width is small. ".repeat(3))
			await settle()
			check_toast("resize-%s-scale-%.2f" % [window_size, scale])
			ui.notify("Short.")
			await settle()
			check_toast("resize-short")
			check(absf(ui.hint_backing.size.y - maxf(38, ui.hint.get_minimum_size().y + 12)) <= 1.0, "Hint plaque follows wrapped content")
			ui.show_dialogue("A long dialogue line. ".repeat(100), "Mother")
			await settle()
			check(ui.panel.size.y <= ui.root.size.y * 0.35 + 1, "Long dialogue stays within its height cap")
			check(ui.dialogue_continue.visible, "Long dialogue keeps Continue outside scrolling text")
			await key(KEY_ENTER)
			check(not ui.dialogue_mode and ui.page == "game", "Actual Continue closes dialogue")
			ui.show_dialogue("A short line.", "Mother")
			await settle()
			check(ui.panel.size.y < ui.root.size.y * 0.35, "Short dialogue shrinks after long dialogue")
			ui.cancel_speech()
			await settle()
			check(ui.page == "game" and not ui.panel.visible and not ui.panel_underlay.visible, "Cancelled speech closes card and underlay")
			ui.show_choices("What will you do?", ["A choice that wraps onto multiple lines. ".repeat(8), "A short choice."])
			await settle()
			check(ui.panel.size.y <= ui.root.size.y * 0.35 + 1, "Wrapped choices stay capped and scroll")
			ui.cancel_speech()
			ui.show_pause()
			await settle()
			var menu_height: float = ui.panel.size.y
			ui.show_journal("A long journal entry. ".repeat(200))
			await settle()
			check(absf(ui.panel.size.y - menu_height) <= 1.0, "Long menu body scrolls inside the designed menu area")
			ui.show_inventory(game.items, game.magic_items)
			await settle()
			check(absf(ui.panel.size.y - menu_height) <= 1.0, "Equipment descriptions preserve menu geometry")
			ui.show_pause()
			await settle()
			check(absf(ui.panel.size.y - menu_height) <= 1.0, "Short menu restores its designed height after wrapped content")
	ui.close_menu()
	game.vm.cancel_all()
	game.queue_free()
	await process_frame
	if failures.is_empty(): print("UI WRAPPED HEIGHT PASS")
	quit(0 if failures.is_empty() else 1)
