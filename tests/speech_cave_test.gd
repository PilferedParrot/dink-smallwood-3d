extends SceneTree
## SCENARIO, NOT EARNED: places Dink in131; unmodified screen main/noise
## execute normally, including the4s wait and random line. No direct say call.
## FreeDink109.6 dinkc_bindings.cpp:766-788; brain_keyboard.cpp:216-241.
const GAME = preload("res://scripts/fps_game.gd")
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
	game.vm.cancel_all(); game.set_physics_process(false)
	game.test_mode = false; game.playing = true
	game.vm.globals.wizard_see = 2
	game.ui.close_menu()
	game.load_map(131, true)
	game.entities[1].x = 290; game.entities[1].y = 100
	game.entities[1].frozen = false; game.entities[1].nocontrol = 0
	game.fps_yaw = 0; game.fps_pitch = 0; game._sync_fps_camera()
	var deadline := Time.get_ticks_msec() + 15000
	var found := false
	while Time.get_ticks_msec() < deadline:
		for text in game.dialogue_log:
			if text in ["Can we leave now? <shiver>","I'm scared.","Why, that's a funny noise.","This cave sucks, let's leave..."]: found = true
		if found and game.ui.panel.visible: break
		await process_frame
	check(found, "Normal S1-CAVES.main/noise produced an ambient line")
	check(not game.entities[1].frozen and game.ui.panel.visible, "Cave ambient text is visible without explicit freeze")
	var before: Vector2 = game._position2(1)
	check(not game._blocked(before + Vector2(0,-20), 1), "Cave scenario north lane is clear")
	await key(true)
	for _i in 10: game._physics_process(1.0/60)
	await key(false)
	var moved: float = before.y - game._position2(1).y
	check(moved > 10 and not game.ui.modal, "Normal cave speech allows real W movement without Enter (north pixels=%s)" % moved)
	print("CAVE SCENARIO ", JSON.stringify({"setup":"scenario, not earned; normal screen scripts","screen":game.current_screen,"north_pixels":moved,"modal":game.ui.modal,"frozen":game.entities[1].frozen,"line":game.dialogue_log.back()}))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(arg.trim_prefix("--capture="))
	game.vm.cancel_all(); game.ui.cancel_speech(); game.queue_free()
	await process_frame
	print("SPEECH CAVE PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
