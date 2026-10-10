extends SceneTree

const RECORDER = preload("res://scripts/bug_report_recorder.gd")
var failures: Array[String] = []

class FakeVm:
	extends RefCounted
	var globals := {"life":7, "story":42}

class FakeGame:
	extends Node
	var entities := {1:{"x":123.5, "y":87.25, "dir":6}}
	var current_screen := 401
	var fps_yaw := 1.25
	var fps_pitch := -0.25
	var vm := FakeVm.new()

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
	print(("ok   " if condition else "FAIL ") + message)

func key(code: int, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	return event

func _run() -> void:
	var action := "left"
	if not InputMap.has_action(action): InputMap.add_action(action)
	var binding := key(KEY_A, false)
	InputMap.action_add_event(action, binding)
	for pair in [["attack", MOUSE_BUTTON_LEFT], ["magic", MOUSE_BUTTON_RIGHT]]:
		var mouse_binding := InputEventMouseButton.new()
		mouse_binding.button_index = pair[1]
		if not InputMap.has_action(pair[0]): InputMap.add_action(pair[0])
		InputMap.action_add_event(pair[0], mouse_binding)
	var joy_binding := InputEventJoypadMotion.new()
	joy_binding.device = -1
	joy_binding.axis = JOY_AXIS_LEFT_X
	joy_binding.axis_value = 1.0
	if not InputMap.has_action("right"): InputMap.add_action("right")
	InputMap.action_add_event("right", joy_binding)
	var button_binding := InputEventJoypadButton.new()
	button_binding.device = -1
	button_binding.button_index = JOY_BUTTON_A
	if not InputMap.has_action("talk"): InputMap.add_action("talk")
	InputMap.action_add_event("talk", button_binding)

	var time := {"usec":20_000_000}
	var recorder = RECORDER.new()
	recorder.clock_usec = func() -> int: return time.usec
	recorder.screenshot_provider = func() -> Image:
		var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		image.fill(Color.RED)
		return image
	var stale := key(KEY_A, true)
	recorder.record_input(stale)
	time.usec = 29_999_999
	recorder.record_input(key(KEY_A, true))
	recorder.record_input(key(KEY_A, false))
	recorder.record_input(key(KEY_F9, true))
	recorder.record_input(key(KEY_B, true))
	recorder.record_input(key(KEY_2, true))
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(3.5, -2.0)
	recorder.record_input(motion)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	recorder.record_input(mouse)
	mouse.pressed = false
	recorder.record_input(mouse)
	var axis := InputEventJoypadMotion.new()
	axis.axis = JOY_AXIS_LEFT_X
	axis.axis_value = 0.8
	recorder.record_input(axis)
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_A
	button.pressed = true
	recorder.record_input(button)
	button.pressed = false
	recorder.record_input(button)
	time.usec = 30_000_001

	var game := FakeGame.new()
	root.add_child(game)
	await process_frame
	var path: String = recorder.write_report(game)
	check(not path.is_empty(), "Report and screenshot were saved")
	if not path.is_empty():
		check(FileAccess.file_exists(path), "JSON report exists")
		var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var image_path := path.get_base_dir().path_join(str(report.get("screenshot", "")))
		check(FileAccess.file_exists(image_path), "PNG screenshot exists")
		check(report.snapshot.screen == 401 and report.snapshot.player.x == 123.5 and report.snapshot.player.y == 87.25 and report.snapshot.player.dir == 6, "Source screen, position, and facing match")
		check(report.snapshot.camera.yaw == 1.25 and report.snapshot.camera.pitch == -0.25, "Camera orientation matches")
		check(report.snapshot.globals.story == 42, "Story globals were captured")
		var events: Array = report.input.events
		check(events.size() == 9, "Stale, unrelated, and F9 events are omitted")
		var types: Array[String] = []
		for event in events:
			types.append(str(event.type))
			check(float(event.t_ms) >= -10_000.0 and float(event.t_ms) <= 0.0, "Event timestamp is relative and inside the ten-second window")
			check(RECORDER.to_input_event(event) != null, "Recorded event reconstructs as InputEvent")
		check(types.count("key") == 3 and types.count("mouse_motion") == 1 and types.count("mouse_button") == 2 and types.count("joy_axis") == 1 and types.count("joy_button") == 2, "Each supported gameplay event type survives")
		check(events[0].pressed and not events[1].pressed and events[4].pressed and not events[5].pressed and events[7].pressed and not events[8].pressed, "Press and release pairs retain their state")
		check(RECORDER.to_input_event(events[3]).relative == Vector2(3.5, -2.0), "Mouse look delta survives reconstruction")
		check(str(report.limitations).contains("not constitute an exact historical"), "Historical replay limitation is explicit")
		var path2: String = recorder.write_report(game)
		check(path2 != path and FileAccess.file_exists(path2) and FileAccess.file_exists(path), "Repeated reports do not overwrite each other")
	time.usec = 40_000_002
	check(recorder._report_events(time.usec).is_empty(), "Pruning removes events older than ten seconds")
	var boundary = RECORDER.new()
	boundary.clock_usec = func() -> int: return time.usec
	time.usec = 50_000_000
	boundary.record_input(key(KEY_1, true))
	time.usec = 60_000_000
	check(boundary._report_events(time.usec).size() == 1, "The exact ten-second boundary is retained")
	time.usec += 1
	check(boundary._report_events(time.usec).is_empty(), "One microsecond beyond the boundary is pruned")
	var capped = RECORDER.new()
	capped.clock_usec = func() -> int: return time.usec
	for i in range(RECORDER.MAX_EVENTS + 8): capped.record_input(motion)
	check(capped._report_events(time.usec).size() == RECORDER.MAX_EVENTS and capped._dropped_for_cap == 8, "High-rate input remains memory bounded")
	game.queue_free()
	await process_frame
	if failures.is_empty(): print("BUG REPORT RECORDER PASS")
	quit(0 if failures.is_empty() else 1)
