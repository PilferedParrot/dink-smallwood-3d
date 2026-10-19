extends SceneTree
## SCENARIO, NOT EARNED: places Dink in131; unmodified screen main/noise
## execute normally, including the4s wait and random line. No direct say call.
## FreeDink109.6 dinkc_bindings.cpp:766-788; brain_keyboard.cpp:216-241.
const GAME = preload("res://scripts/fps_game.gd")
const NOISE_LINES := ["Can we leave now? <shiver>", "I'm scared.", "Why, that's a funny noise.", "This cave sucks, let's leave..."]
var failures: Array[String] = []
var game
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, text: String) -> void:
	if not ok: failures.append(text); push_error(text)
func key(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_W; event.physical_keycode = KEY_W; event.pressed = pressed
	Input.parse_input_event(event); Input.flush_buffered_events()
	await process_frame
func _run() -> void:
	seed(42)
	game = GAME.new(); game.test_mode = true
	root.add_child(game)
	await process_frame
	game.vm.cancel_all()
	game.test_mode = false; game.playing = true
	game.vm.globals.wizard_see = 2
	game.ui.close_menu()
	game.load_map(131, true)
	game.entities[1].x = 290; game.entities[1].y = 100
	game.entities[1].frozen = false; game.entities[1].nocontrol = 0
	game.fps_yaw = 0; game.fps_pitch = 0; game._sync_fps_camera()
	check(game.is_physics_processing(), "Cave gameplay physics callback is enabled")
	var source_line := ""
	var speech_id := 0
	var wait_frames := 0
	# noise() waits four seconds before its first line. Bound the wait by engine
	# physics frames and require that exact source line to be on the live card.
	for _i in 600:
		await physics_frame
		wait_frames += 1
		var active_id: int = game.ui.active_speech_id
		if game.ui.panel.visible and game.ui.page == "dialogue" and game.ui.column.get_child_count() > 0:
			var shown: String = str(game.ui.column.get_child(0).text)
			if shown in NOISE_LINES:
				source_line = shown
				speech_id = active_id
				break
	check(speech_id > 0, "Normal S1-CAVES.main/noise produced a visible source line within 600 physics frames")
	check(not game.entities[1].frozen and speech_id > 0, "Cave ambient text is visible without explicit freeze")
	var before: Vector2 = game._position2(1)
	check(not game._blocked(before + Vector2(0,-20), 1), "Cave scenario north lane is clear")
	await key(true)
	var visible_ticks := 0
	var moved_during_card := 0.0
	for _i in 10:
		var start: Vector2 = game._position2(1)
		var visible_before: bool = speech_id > 0 and game.ui.panel.visible and game.ui.active_speech_id == speech_id
		await physics_frame
		await process_frame
		if visible_before and game.ui.panel.visible and game.ui.active_speech_id == speech_id:
			visible_ticks += 1
			moved_during_card += start.y - game._position2(1).y
	await key(false)
	check(visible_ticks == 10 and moved_during_card > 10 and not game.ui.modal, "Normal cave speech allows real W movement while its source card is visible (north pixels=%s, visible ticks=%s)" % [moved_during_card, visible_ticks])
	print("CAVE SCENARIO ", JSON.stringify({"setup":"scenario, not earned; normal screen scripts","screen":game.current_screen,"wait_physics_frames":wait_frames,"visible_ticks":visible_ticks,"north_px_during_card":moved_during_card,"north_px_total":before.y - game._position2(1).y,"modal":game.ui.modal,"frozen":game.entities[1].frozen,"line":source_line}))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(arg.trim_prefix("--capture="))
	game.vm.cancel_all(); game.ui.cancel_speech(); game.queue_free()
	await process_frame
	print("SPEECH CAVE PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
