extends SceneTree

const GAME := preload("res://scripts/fps_game.gd")

var game
var failures: Array[String] = []
var capture_path := ""

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="): capture_path = arg.trim_prefix("--capture=")
	_run.call_deferred()

func _run() -> void:
	game = GAME.new()
	# Let the opening run in test mode, then cancel it before constructing the
	# Story 3 room. This leaves no opening dialogue coroutine behind the fixture.
	game.test_mode = true
	root.add_child(game)
	await process_frame
	await game._new_game()
	game.vm.cancel_all()
	await process_frame
	game.vm.globals["vision"] = 1
	game.vm.globals["story"] = 3
	game.load_map(1, false)
	await process_frame
	await process_frame
	var mother: int = 0
	var death_art: int = 0
	for id in game.entities:
		if int(game.entities[id].get("editor_num", -1)) == 26: mother = int(id)
		if int(game.entities[id].get("editor_num", -1)) == 34: death_art = int(id)
	check(mother != 0 and death_art != 0, "Source room contains editor 26 and vision-1 editor 34")
	if mother != 0:
		await game.vm.run("s1-h1-m", "main", mother)
		game._update_visual(mother)
		check(int(game.entities[mother].get("active", 1)) == 0, "Original S1-H1-M story-3 branch deactivates Mother")
	if death_art != 0:
		check(game.visuals.has(death_art) and game.visuals[death_art].is_visible_in_tree(), "Authored vision-1 death art is visible")
	game.dialogue_busy = false
	game.test_mode = false
	game.playing = true
	game.ui.close_menu()
	game.set_physics_process(false)
	game.entities[1]["x"] = 203.0
	game.entities[1]["y"] = 151.0
	game.fps_yaw = 0.585729
	game.fps_pitch = 0.022599
	game._sync_fps_camera()
	await physics_frame
	# The first grief line begins at the doorway. The original player view stays
	# unchanged while editor 26 is inactive and vision-1 death art paints the floor.
	game.entities[1]["x"] = 323.0
	game.entities[1]["y"] = 370.833333
	game._sync_fps_camera()
	var doorway_position: Vector2 = game._position2(1)
	var doorway_view: Transform3D = game.camera.global_transform
	game._dialogue("Mother noooooo!", 1, {"script":"s1-h1-s", "sprite_id":1})
	await _wait_for_dialogue_layout()
	check(not game.fps_dialogue_camera_active and game.camera.global_transform.is_equal_approx(doorway_view), "Doorway grief preserves the player view")
	check(game.fps_dialogue_subject == 0, "Grief does not force an effect or corpse camera subject")
	_assert_floor_art(death_art)
	check(game._position2(1).is_equal_approx(doorway_position), "Doorway grief camera does not move Dink")
	_end_line()
	await process_frame
	await process_frame
	game.entities[1]["x"] = 203.0
	game.entities[1]["y"] = 151.0
	game._sync_fps_camera()
	await physics_frame
	var player_position: Vector2 = game._position2(1)
	var ordinary_camera: Vector3 = game.camera.position
	var ordinary_yaw: float = game.fps_yaw
	var ordinary_pitch: float = game.fps_pitch
	var source_flames := 0
	for id in game.visuals:
		var visual: Node3D = game.visuals[id]
		if is_instance_valid(visual) and str(visual.get_meta("model_key", "")) == "flame": source_flames += 1
	check(source_flames > 0, "Story 3 vision fixture includes the source fire sprites")
	game._dialogue("Mother noooooo!", 1, {"script":"s1-h1-s", "sprite_id":1})
	await _wait_for_dialogue_layout()
	check(not game.fps_dialogue_camera_active, "Story 3 grief does not take over the camera")
	check(game.fps_dialogue_subject == 0, "No point-blank effect is selected as grief subject")
	_assert_floor_art(death_art)
	check(game.camera.position.is_equal_approx(ordinary_camera) and is_equal_approx(game.fps_yaw,ordinary_yaw) and is_equal_approx(game.fps_pitch,ordinary_pitch), "Grief preserves exact player camera position and rotation")
	check(game._position2(1).is_equal_approx(player_position), "Grief camera does not move Dink")
	_end_line()
	await process_frame
	await process_frame
	check(not game.fps_dialogue_camera_active, "Grief dialogue completion restores the ordinary camera")
	check(game.camera.position.is_equal_approx(ordinary_camera), "Grief dialogue restoration preserves camera position")
	check(game._position2(1).is_equal_approx(player_position), "Grief dialogue restoration preserves Dink coordinates")
	check(is_equal_approx(game.fps_yaw, ordinary_yaw) and is_equal_approx(game.fps_pitch, ordinary_pitch), "Grief dialogue restoration preserves camera rotation")
	# Render the actual second grief line after its opening line has completed.
	game._dialogue("Mother, you can't die, nooo I  I ...", 1, {"script":"s1-h1-s", "sprite_id":1})
	await _wait_for_dialogue_layout()
	check(not game.fps_dialogue_camera_active and game.camera.position.is_equal_approx(ordinary_camera), "Second grief line retains the same player view")
	check(game.fps_dialogue_subject == 0, "Second grief line forces no camera subject")
	_assert_floor_art(death_art)
	if not capture_path.is_empty() and DisplayServer.get_name() != "headless":
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png(capture_path)
	_end_line()
	await process_frame
	await process_frame
	game.entities[900001] = {"pseq":232, "base_walk":230, "script":"", "active":1}
	check(game._fps_speaker_name(900001, {"script":"s1-h1-o"}) == "Ethel", "S1-H1-O old lady is labelled Ethel")
	game.entities[900002] = {"pseq":222, "base_walk":220, "script":"", "active":1}
	game.entities[900003] = {"pseq":412, "base_walk":410, "script":"", "active":1}
	game.entities[900004] = {"pseq":258, "base_walk":250, "script":"", "active":1}
	check(game._fps_speaker_name(900002, {"script":"s1-h1-o"}) == "Neighbor", "S1-H1-O girl is labelled neighbor")
	check(game._fps_speaker_name(900003, {"script":"s1-h1-o"}) == "Guard", "S1-H1-O knight is labelled guard")
	check(game._fps_speaker_name(900004, {"script":"s1-h1-o"}) == "Neighbor", "S1-H1-O girl2 is labelled neighbor")
	check(game._fps_speaker_name(900005, {"script":"s1-gg"}) == "Renton", "S1-GG receives source-backed Renton label")
	check(game._fps_speaker_name(900006, {"script":"s1-ltr"}) == "Aunt Maria's letter", "S1-LTR uses the source-backed letter label")
	# Reduced motion may turn at the current eye but may not search another
	# viewpoint. An impossible fit is reported by the framing state.
	game.settings["reduced_motion"] = true
	var reduced_eye: Vector3 = game.camera.position
	game._dialogue("Mother noooooo!", 1, {"script":"s1-h1-s", "sprite_id":1})
	await _wait_for_dialogue_layout()
	check(game.camera.position.is_equal_approx(reduced_eye), "Reduced motion keeps the player eye position")
	check(game.fps_dialogue_frame_valid or not game.fps_dialogue_frame_failure.is_empty(), "Reduced motion reports an impossible fit")
	_end_line()
	await process_frame
	game.settings["reduced_motion"] = false
	# Title/reset and map cancellation both restore an active temporary camera.
	game._dialogue("Mother noooooo!", 1, {"script":"s1-h1-s", "sprite_id":1})
	await _wait_for_dialogue_layout()
	check(not game.fps_dialogue_camera_active, "Grief fallback has no override before title/reset")
	game.playing = false
	game._physics_process(0.016)
	check(not game.fps_dialogue_camera_active, "Title/reset cancels the grief camera")
	check(is_equal_approx(game.fps_yaw, ordinary_yaw) and is_equal_approx(game.fps_pitch, ordinary_pitch), "Title/reset preserves the saved camera rotation")
	_end_line()
	await process_frame
	game.playing = true
	game._dialogue("Mother noooooo!", 1, {"script":"s1-h1-s", "sprite_id":1})
	await _wait_for_dialogue_layout()
	check(not game.fps_dialogue_camera_active, "Grief fallback has no override before map cancellation")
	game.load_map(439, false)
	await process_frame
	check(not game.fps_dialogue_camera_active, "Map load cancels the grief camera")
	check(is_equal_approx(game.fps_yaw, ordinary_yaw) and is_equal_approx(game.fps_pitch, ordinary_pitch), "Map cancellation preserves the saved camera rotation")
	if failures.is_empty(): print("FPS GRIEF PRESENTATION PASS")
	else: print("FPS GRIEF PRESENTATION FAILURES: ", failures)
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _wait_for_dialogue_layout() -> void:
	for i in 8:
		await process_frame
		if game.ui.page == "dialogue" and game.ui.panel.visible: return
	check(false, "Dialogue card becomes visible after its measured layout")

func _assert_floor_art(id: int) -> void:
	check(id != 0 and game.visuals.has(id), "Authored death art has a source owner")
	if id == 0 or not game.visuals.has(id): return
	var visual: Node3D = game.visuals[id]
	check(visual.get_meta("ground_painted",false) and visual.has_meta("floor_art_rect"), "Death art uses the original ground projection")
	check(visual.get_child_count() == 0, "Death art has no duplicated upright card or shadow")

func _end_line() -> void:
	game.ui.hide_dialogue()
	game.ui.dialogue_finished.emit(0)
