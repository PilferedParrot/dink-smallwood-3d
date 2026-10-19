extends SceneTree

const GAME := preload("res://scripts/fps_game.gd")

var game
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	await game._new_game()
	game.vm.cancel_all()
	game.playing = true
	game.ui.close_menu()
	game.set_physics_process(false)
	game.test_mode = false
	var mother: int = 0
	for id in game.entities:
		if str(game.entities[id].get("script", "")).to_lower() == "s1-h1-m": mother = int(id)
	check(mother != 0, "Story 2 fixture keeps Mother's real source actor")
	if mother != 0:
		game.vm.globals["story"] = 2
		game.entities[1]["x"] = 323.0
		game.entities[1]["y"] = 370.833333
		game.entities[mother]["x"] = 216.583511
		game.entities[mother]["y"] = 200.0
		game._update_visual(mother)
		for size in [Vector2i(1280,800), Vector2i(1920,1080)]:
			for scale in [1.0, 1.3]:
				root.size = size
				game.ui.set_text_scale(scale)
				await process_frame
				await _check_line(mother, "Mother speaks from the original room.", "Mother %s %.1f" % [size,scale])
	game.vm.globals["vision"] = 0
	game.load_map(439, false)
	game.entities[1]["x"] = 320.0
	game.entities[1]["y"] = 260.0
	game._sync_fps_camera()
	for fixture in [{"id":900101,"seq":411,"name":"Guard","x":350.0}, {"id":900102,"seq":221,"name":"Neighbor","x":440.0}]:
		var id: int = int(fixture.id)
		game.entities[id] = {"x":float(fixture.x),"y":130.0,"active":1,"type":1,"pseq":int(fixture.seq),"pframe":1,"seq":0,"frame":1,"size":100,"script":"s1-h1-o"}
		game._create_visual(id)
		check(game.visuals.has(id), "%s fixture has a real visual" % fixture.name)
		await _check_line(id, "%s speaks outside." % fixture.name, str(fixture.name))
	game.vm.globals["vision"] = 1
	game.vm.globals["story"] = 3
	game.load_map(1, false)
	var story_three_mother: int = 0
	for id in game.entities:
		if int(game.entities[id].get("editor_num", -1)) == 26: story_three_mother = int(id)
	check(story_three_mother != 0, "Story 3 fixture begins with Mother's editor sprite")
	if story_three_mother != 0:
		await game.vm.run("s1-h1-m", "main", story_three_mother)
		game._update_visual(story_three_mother)
	game.entities[1]["x"] = 323.0
	game.entities[1]["y"] = 370.833333
	game._sync_fps_camera()
	var inactive: bool = true
	var death_art: int = 0
	for id in game.entities:
		if str(game.entities[id].get("script", "")).to_lower() == "s1-h1-m" and int(game.entities[id].get("active", 1)) != 0: inactive = false
		if int(game.entities[id].get("editor_num", -1)) == 34: death_art = int(id)
	check(inactive, "Story 3 source script makes Mother inactive")
	check(death_art != 0 and game.visuals.has(death_art) and game.visuals[death_art].visible, "Authored vision-1 death art remains visible")
	var source_position: Vector2 = game._position2(1)
	var old_yaw: float = game.fps_yaw
	var old_pitch: float = game.fps_pitch
	var grief_view: Transform3D = game.camera.global_transform
	game._dialogue("Mother, you can't die.", 1, {"script":"s1-h1-s", "sprite_id":1})
	await _settled_line()
	check(not game.fps_dialogue_camera_active and game.camera.global_transform.is_equal_approx(grief_view), "Grief fallback preserves the player view")
	check(game.fps_dialogue_subject == 0, "Disabled grief experiment forces no scene or effect subject")
	check(game.fps_dialogue_subject == 0 or str(game.visuals[game.fps_dialogue_subject].get_meta("model_key", "")) not in ["flame", "fireplace"], "Grief never selects fire as its subject")
	check(game._position2(1).is_equal_approx(source_position), "Grief camera preserves Dink's source coordinates")
	_end_line()
	await process_frame
	await process_frame
	check(not game.fps_dialogue_camera_active, "Grief dialogue restores player camera")
	check(is_equal_approx(game.fps_yaw, old_yaw) and is_equal_approx(game.fps_pitch, old_pitch), "Grief restores the exact yaw and pitch")
	game._dialogue("Mother, you can't die.", 1, {"script":"s1-h1-s", "sprite_id":1})
	await _settled_line()
	game.load_map(439, false)
	check(not game.fps_dialogue_camera_active, "Map cancellation releases a candidate dialogue camera")
	_end_line()
	await process_frame
	if failures.is_empty(): print("FPS DIALOGUE FRAMING PASS")
	else: print("FPS DIALOGUE FRAMING FAILURES: ", failures)
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _check_line(id: int, line: String, label: String) -> void:
	var source_position: Vector2 = game._position2(1)
	var old_yaw: float = game.fps_yaw
	var old_pitch: float = game.fps_pitch
	# Camera framing is a presentation adaptation for explicitly frozen speech.
	game.entities[1].frozen = true
	game._dialogue(line, id, {"sprite_id":id})
	await _settled_line()
	var safe: Rect2 = game.ui.speech_safe_rect()
	var points: Array[Vector3] = game._fps_visible_points(game.visuals[id], game.camera.global_position)
	var bounds: Rect2 = game._fps_projected_bounds(points)
	check(points.size() >= 4, "%s measures the actor's rendered art" % label)
	check(bounds.has_area() and safe.encloses(bounds), "%s whole actor is above the measured opaque UI" % label)
	check(game._fps_subject_rays_clear(game.camera.global_position, game._fps_points_center(points), points, id, false), "%s has clear head and torso rays" % label)
	check(not game._fps_effect_in_front(points, game.camera.global_position, id), "%s is clear of nearer visible fire" % label)
	check(game._position2(1).is_equal_approx(source_position), "%s keeps player source position" % label)
	check(not game.ui.dialogue_continue.visible and not game.ui.modal, "%s speech retains nonmodal input while explicit freeze gates movement" % label)
	for pressed in [true,false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ENTER
		event.physical_keycode = KEY_ENTER
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
	check(not game.ui.panel.visible, "%s actual Talk fast-forwards frozen last_talk line (brain_keyboard.cpp:222-240)" % label)
	await process_frame
	await process_frame
	check(is_equal_approx(game.fps_yaw, old_yaw) and is_equal_approx(game.fps_pitch, old_pitch), "%s restores yaw and pitch" % label)

func _settled_line() -> void:
	for i in 5: await process_frame

func _end_line() -> void:
	game.ui.cancel_speech()
