extends SceneTree

const GAME := preload("res://scripts/fps_game.gd")
var game
var failures: Array[String] = []
var completed := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func _blocking_line() -> void:
	await game.dink_call("say_stop", ["A blocking Dink line.", 1], {})
	completed += 1

func _run() -> void:
	game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	await game._new_game()
	game.vm.cancel_all()
	game.load_map(439, false)
	game.ui.close_menu()
	game.test_mode = false
	game.ui.toast_timer.wait_time = 0.15
	var transcript_count: int = game.dialogue_log.size()
	var returned: Variant = await game.dink_call("say", ["A timed Dink line.", 1], {})
	check(int(returned) == 0 and game.ui.panel.visible and not game.ui.modal, "say returns immediately with a nonmodal speech card")
	check(game.ui.heading.text == "Dink" and game.ui.toast.text != "A timed Dink line.", "Dink speech uses the shared named card, not the feedback banner")
	check(not game.ui.dialogue_continue.visible, "Timed speech has no Continue action or focus request")
	check(game.ui.hint.text.is_empty(), "Gameplay hint cannot overlap the timed speech card")
	await game.dink_call("sp_y", [1, 290], {})
	check(float(game.entities[1].y) == 290.0, "A following VM command executes while the timed card remains visible")
	check(game.dialogue_log.size() == transcript_count+1, "Timed speech is recorded exactly once")
	if not game.ui.has_method("cancel_speech"):
		print("SPEECH SEMANTICS FAIL: old presentation has no cancellable shared speech ownership")
		quit(1)
		return
	_blocking_line()
	for _i in 6: await process_frame
	check(game.ui.modal and game.ui.dialogue_continue.visible and completed == 0, "say_stop owns its card and waits for Continue")
	var blocking_heading: String = game.ui.heading.text
	await game.dink_call("say", ["Queued ambient line.", 1], {})
	await create_timer(0.2).timeout
	check(game.ui.modal and game.ui.heading.text == blocking_heading and completed == 0, "Neither an older timer nor queued ambient expiry completes a blocking request")
	game.ui._continue_dialogue()
	for _i in 3: await process_frame
	check(completed == 1, "Only the blocking request's Continue completes it")
	_blocking_line()
	for _i in 6: await process_frame
	game.load_map(409, false)
	for _i in 4: await process_frame
	check(not game.ui.modal and not game.ui.panel.visible and game.ui.pending_speech.is_empty(), "Map cancellation leaves no stale speech card or queued line")
	game.vm.cancel_all()
	game.queue_free()
	await process_frame
	print("SPEECH SEMANTICS PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
