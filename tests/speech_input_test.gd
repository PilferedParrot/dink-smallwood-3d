extends SceneTree
## Fixture setup skips progression; physical key events use real input, physics,
## collision and UI. FreeDink109.6 brain_keyboard.cpp:216-241: speech is not a gate.
const FPS = preload("res://scripts/fps_game.gd")
const TOP = preload("res://scripts/game.gd")
var game
var failures: Array[String] = []
var completed := 0

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); push_error(message)
func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code; event.keycode = code; event.pressed = pressed
	Input.parse_input_event(event); Input.flush_buffered_events()
	await process_frame
func line() -> void:
	await game.dink_call("say_stop", ["An unfrozen speaker must never stop Dink walking.", 1], {})
	completed += 1
func walk() -> float:
	var before: Vector2 = game._position2(1)
	await key(KEY_D, true)
	for _i in 10:
		await physics_frame
		await process_frame
	await key(KEY_D, false)
	return before.distance_to(game._position2(1))
func clear_line() -> void:
	game.ui.cancel_speech()
	for _i in 4: await process_frame
func fixture(fps: bool) -> void:
	game = FPS.new() if fps else TOP.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	game.vm.cancel_all()
	game.load_map(439, false)
	game.ui.close_menu()
	game.playing = true; game.changing = false
	# Pick a source-collision-clear lane, not an assumption about map scenery.
	var lane := Vector2.INF
	for y in range(100, 300, 20):
		for x in range(100, 500, 20):
			var clear := true
			for dx in range(0, 50, 2):
				if game._blocked(Vector2(x + dx, y), 1): clear = false
			if clear: lane = Vector2(x,y); break
		if lane != Vector2.INF: break
	check(lane != Vector2.INF, "Harness has a clear movement lane")
	game.entities[1].x = lane.x; game.entities[1].y = lane.y
	game.entities[1].frozen = false; game.entities[1].nocontrol = 0
	if fps: game.fps_yaw = 0; game._sync_fps_camera()
	game.test_mode = false
	check(game.is_physics_processing(), "Gameplay physics callback is enabled")
	completed = 0
	line()
	for _i in 6: await process_frame
	check(game.ui.panel.visible and completed == 0, "Stop line is visible and caller waits")
	var distance := await walk()
	check(distance > 10, "G1 %s: unfrozen say_stop allows real-key walking (distance=%s)" % ["FPS" if fps else "2D", distance])
	check(not game.ui.modal, "Speech does not own global modality")
	await clear_line()
	await game.dink_call("freeze", [1], {})
	line()
	for _i in 6: await process_frame
	var frozen_distance := await walk()
	check(frozen_distance < 0.01, "Explicit freeze control blocks movement during speech")
	await clear_line()
	await game.dink_call("unfreeze", [1], {})
	game.ui.show_choices("A genuine modal choice", ["Stay", "Go"])
	for _i in 4: await process_frame
	var choice_modal: bool = game.ui.modal
	var choice_distance := await walk()
	check(choice_modal and choice_distance < 0.01, "Choice control still blocks movement")
	print("G1 ", JSON.stringify({"mode":"FPS" if fps else "2D","free_px":distance,"freeze_px":frozen_distance,"choice_px":choice_distance,"choice_modal":choice_modal,"physics":game.is_physics_processing()}))
	game.ui._choose_dialogue(1)
	game.vm.cancel_all(); game.queue_free()
	await process_frame
func _run() -> void:
	await fixture(true)
	await fixture(false)
	print("SPEECH INPUT PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
