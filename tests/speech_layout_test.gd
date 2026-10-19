extends SceneTree
## Scenario fixture skips campaign progression/startup scripts. M runs the
## original BUTTON6 script; Continue/choices use normal viewport key events.
const GAME = preload("res://scripts/fps_game.gd")
var game
var failures: Array[String] = []
var records: Array = []
var output_dir := ""
var window_size := Vector2i(1280, 800)
var completed := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out-dir="): output_dir = arg.trim_prefix("--out-dir=")
		if arg == "--1080": window_size = Vector2i(1920, 1080)
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func settle() -> void:
	for _i in 8: await process_frame

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

func art_rect() -> Rect2:
	# Independent oracle for the rectangle passed to draw_texture_rect in the
	# existing status owner, rather than its larger transparent Control bounds.
	var dock = game.ui.status_dock
	return Rect2(dock.global_position + Vector2((dock.size.x - dock._dock_width) * 0.5, dock._dock_y),
		Vector2(dock._dock_width, dock.STATUS_HEIGHT * dock._dock_scale))

func rect_data(rect: Rect2) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]

func inspect_card(tag: String) -> void:
	var ui = game.ui
	var dock := art_rect()
	var bounds: Rect2 = ui.panel.get_global_rect()
	var intersections := {"panel": rect_data(bounds.intersection(dock))}
	for decoration in [ui.panel_underlay, ui.vines_left, ui.vines_right]:
		bounds = bounds.merge(decoration.get_global_rect())
		intersections[str(decoration.get_instance_id())] = rect_data(decoration.get_global_rect().intersection(dock))
	var overlap := bounds.intersection(dock)
	var row := {"tag": tag, "window": [root.size.x, root.size.y], "canvas": [ui.root.size.x, ui.root.size.y],
		"scale": ui.text_scale, "heading": ui.heading.text, "panel": rect_data(ui.panel.get_global_rect()),
		"card_with_decorations": rect_data(bounds), "status_art": rect_data(dock),
		"overlap": rect_data(overlap), "part_intersections": intersections, "status_visible": ui.status_dock.visible,
		"continue_visible": ui.dialogue_continue.visible, "modal": ui.modal}
	if ui.dialogue_mode and not ui.dialogue_continue.visible:
		var focus: Control = root.gui_get_focus_owner()
		row["answer_viewport"] = rect_data(ui.menu_scroll.get_global_rect())
		if focus != null:
			row["focused_answer"] = rect_data(focus.get_global_rect())
			row["answer_fully_visible"] = ui.menu_scroll.get_global_rect().grow(1).encloses(focus.get_global_rect())
			check(row.answer_fully_visible, tag + ": focused answer fully visible")
		if ui.get("choice_prompt_scroll") != null:
			row["prompt_viewport"] = rect_data(ui.get("choice_prompt_scroll").get_global_rect())
	records.append(row)
	print("SPEECH LAYOUT ", JSON.stringify(row))
	check(not bounds.intersects(dock), tag + ": complete card leaves status artwork clear")
	check(bounds.position.y >= 0 and bounds.end.y <= ui.root.size.y, tag + ": complete card stays inside viewport")
	check(ui.panel.size.y <= ui.root.size.y * 0.35 + 1, tag + ": card retains 35% height cap")
	check(ui.speech_safe_rect().size.y > 0, tag + ": world has a positive speech-safe area")

func frame(tag: String) -> void:
	if output_dir.is_empty(): return
	await RenderingServer.frame_post_draw
	var path := output_dir.path_join(tag + ".png")
	root.get_texture().get_image().save_png(path)

func _blocking(command: String, line: String) -> void:
	await game.dink_call(command, [line, 1, 1], {})
	completed += 1

func _choices() -> void:
	await game.dink_call("choice", ["Choose your next step.", [{"text": "First step", "value": 1}, {"text": "Second step", "value": 2}]], {})
	completed += 1

func title_at(node: Variant, line: int) -> String:
	if node is Dictionary:
		if node.get("op") == "choice_title" and node.get("line") == line: return str(node.text)
		for child in node.values():
			var found := title_at(child, line)
			if not found.is_empty(): return found
	elif node is Array:
		for child in node:
			var found := title_at(child, line)
			if not found.is_empty(): return found
	return ""

func _run() -> void:
	root.size = window_size
	game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	await game._new_game()
	game.vm.cancel_all()
	game.load_map(439, false)
	game.vm.cancel_all()
	game.set_physics_process(false)
	game.playing = true
	game.entities[1].frozen = false
	game.entities[1].x = 510.0
	game.entities[1].y = 300.0
	game.fps_yaw = 0.0
	game.fps_pitch = -0.08
	game._sync_fps_camera()
	game.test_mode = false
	game.vm.globals["s2-map"] = 0
	game.ui.close_menu()
	await settle()
	await frame("00-status-unobstructed")
	await key(KEY_M)
	check(game.ui.page == "dialogue" and not game.ui.modal, "Actual M opens timed source speech")
	check(game.ui.column.get_child(0).text == "I don't own a map yet.", "Actual M runs original BUTTON6 missing-map line")
	check(game.ui.status_dock.visible and not game.ui.dialogue_continue.visible, "Timed speech keeps HUD and has no Continue")
	inspect_card("real-M-missing-map")
	await frame("01-real-M-timed")
	game.ui.cancel_speech()
	for scale in [0.85, 1.0, 1.3]:
		game.ui.set_text_scale(scale)
		for command in ["say", "say_xy", "say_stop", "say_stop_npc", "say_stop_xy"]:
			for line in ["Short line.", "A long speech line that must scroll within the card. ".repeat(100)]:
				var blocking: bool = command.begins_with("say_stop")
				var previous := completed
				if blocking: _blocking(command, line)
				else: await game.dink_call(command, [line, 1, 1], {})
				await settle()
				var tag := "%s-%s-%.2f" % [command, "short" if line.length() < 50 else "long", scale]
				inspect_card(tag)
				check(game.ui.dialogue_continue.visible == blocking, tag + ": one Continue owner for blocking speech only")
				if line.length() > 50:
					check(game.ui.menu_scroll.get_v_scroll_bar().max_value > game.ui.menu_scroll.size.y, tag + ": long text scrolls")
					if command == "say" and scale == 1.0: await frame("03-timed-long")
				if blocking:
					check(completed == previous, tag + ": script waits for real Continue input")
					if command == "say_stop" and scale == 1.0: await frame("02-blocking-" + ("short" if line.length() < 50 else "long"))
					await key(KEY_ENTER)
					check(completed == previous + 1 and game.ui.page == "game", tag + ": Enter releases exactly one blocking call")
				else:
					game.ui.cancel_speech()
		var previous := completed
		_choices()
		await settle()
		inspect_card("choices-%.2f" % scale)
		check(not game.ui.dialogue_continue.visible, "Choice buttons alone own confirmation")
		await key(KEY_ENTER)
		check(completed == previous + 1 and game.ui.page == "game", "Enter chooses through normal focus path")
	if not output_dir.is_empty():
		var story: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/story.json"))
		game.ui.set_text_scale(1.3)
		for source in [["escape", 114], ["s1-boot", 16]]:
			var title := title_at(story.scripts[source[0]], source[1])
			game.ui.show_choices(title, ["First", "Second"])
			await settle()
			var tag := "04-choice-%s-%s-130pct" % [source[0], source[1]]
			inspect_card(tag)
			await frame(tag)
			await key(KEY_ENTER)
		# Rendering proof of start/middle/final viewports. Deliberately accelerated
		# UI time; normal reading speed/coverage is checked by timed_reading_test.
		game.ui.set_text_scale(1.3)
		var reading_text := "FIRST: the beginning stays readable.\n"
		for i in 24: reading_text += "Line %02d: every line gets a visible turn.\n" % (i + 1)
		reading_text += "FINAL: the last line gets reading time."
		game.ui.show_dialogue(reading_text, "Dink", false)
		await settle()
		inspect_card("reading-start")
		await frame("05-reading-start")
		var middle := false
		var final_view := false
		for _tick in 400:
			game.ui._process(0.5)
			await process_frame
			var bar: VScrollBar = game.ui.menu_scroll.get_v_scroll_bar()
			if not middle and game.ui.menu_scroll.scroll_vertical >= (bar.max_value - bar.page) * 0.5:
				middle = true
				inspect_card("reading-middle")
				await frame("05-reading-middle")
			if game.ui.get("timed_phase") == 2:
				final_view = true
				inspect_card("reading-final")
				await frame("05-reading-final")
				break
		check(middle and final_view, "Accelerated render fixture reaches middle and final text viewports")
		game.ui.cancel_speech()
	# Invalidate placement while the same card remains alive, not just on reopen.
	game.ui.show_dialogue("Resize a live timed card.", "Dink", false)
	await settle()
	root.size = Vector2i(1920, 1080) if window_size.x == 1280 else Vector2i(1280, 800)
	await settle()
	inspect_card("live-resize")
	# A wide aspect changes HUD scale without changing logical canvas height.
	root.size = Vector2i(2560, 1080)
	await settle()
	inspect_card("live-wide-resize")
	game.ui.cancel_speech()
	game.vm.cancel_all()
	if not output_dir.is_empty():
		var file := FileAccess.open(output_dir.path_join("geometry.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify({"records": records, "failures": failures,
			"executable": OS.get_executable_path(), "editor_feature": OS.has_feature("editor"),
			"project_source_present": FileAccess.file_exists("res://project.godot"),
			"ui_source_present": FileAccess.file_exists("res://scripts/game_ui.gd"),
			"resource_root": ProjectSettings.globalize_path("res://"),
			"reading_frames": "05-* accelerates UI time in explicit0.5s steps; not a real-time playback capture.",
			"setup": "Scenario skips progression/startup scripts. M runs original BUTTON6. All five DinkC speech calls and choice traverse game owners; Enter advances via viewport input. Physics frozen for stable screenshots."}, "\t"))
	game.queue_free()
	await process_frame
	print("SPEECH LAYOUT PASS" if failures.is_empty() else "SPEECH LAYOUT FAIL: %d" % failures.size())
	quit(0 if failures.is_empty() else 1)
