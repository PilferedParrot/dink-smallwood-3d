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
	# The first grief line begins at the doorway. Its held camera must still find
	# the interior hearth before the second line moves Dink to the bedside.
	game.entities[1]["x"] = 323.0
	game.entities[1]["y"] = 370.833333
	game._sync_fps_camera()
	var doorway_position: Vector2 = game._position2(1)
	game._dialogue("Mother noooooo!", 1, {"script":"s1-h1-s", "sprite_id":1})
	await process_frame
	check(game.fps_dialogue_camera_active, "Doorway grief line uses a clear interior camera")
	check(game._position2(1).is_equal_approx(doorway_position), "Doorway grief camera does not move Dink")
	game.ui.dialogue_finished.emit(0)
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
	await process_frame
	check(game.fps_dialogue_camera_active, "Story 3 grief line uses a temporary room camera")
	check(game.fps_dialogue_subject != 0, "Grief camera selects an interior fire subject")
	if game.fps_dialogue_subject != 0:
		var key := str(game.visuals[game.fps_dialogue_subject].get_meta("model_key", ""))
		check(key in ["fireplace", "flame"], "Grief subject is source-backed fireplace or flame")
		var subject_visual: Node3D = game.visuals[game.fps_dialogue_subject]
		var height := float(subject_visual.get_meta("height", 1.8))
		var target := subject_visual.global_position + Vector3.UP * minf(1.35, maxf(0.55, height * 0.55))
		var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(game.camera.global_position, target, 3))
		if key == "fireplace":
			var collider: Object = hit.get("collider")
			check(collider != null and int(collider.get_meta("entity_id", 0)) == game.fps_dialogue_subject, "Grief camera has a physical clear ray to the hearth")
		else:
			check(hit.is_empty(), "Grief camera has an unobstructed ray to the non-colliding source flame")
	check(not game.camera.position.is_equal_approx(ordinary_camera), "Grief camera changes the view without moving the player")
	check(game._position2(1).is_equal_approx(player_position), "Grief camera does not move Dink")
	game.ui.dialogue_finished.emit(0)
	await process_frame
	await process_frame
	check(not game.fps_dialogue_camera_active, "Grief dialogue completion restores the ordinary camera")
	check(game.camera.position.is_equal_approx(ordinary_camera), "Grief dialogue restoration preserves camera position")
	check(game._position2(1).is_equal_approx(player_position), "Grief dialogue restoration preserves Dink coordinates")
	check(is_equal_approx(game.fps_yaw, ordinary_yaw) and is_equal_approx(game.fps_pitch, ordinary_pitch), "Grief dialogue restoration preserves camera rotation")
	# Render the actual second grief line after its opening line has completed.
	game._dialogue("Mother, you can't die, nooo I  I ...", 1, {"script":"s1-h1-s", "sprite_id":1})
	await process_frame
	check(game.fps_dialogue_camera_active, "Second grief line keeps the clear hearth view")
	if not capture_path.is_empty() and DisplayServer.get_name() != "headless":
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png(capture_path)
	game.ui.dialogue_finished.emit(0)
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
	# Reduced motion retains the ordinary camera, as requested by settings.
	game.settings["reduced_motion"] = true
	game._dialogue("Mother noooooo!", 1, {"script":"s1-h1-s", "sprite_id":1})
	await process_frame
	check(not game.fps_dialogue_camera_active, "Reduced motion skips the grief camera")
	game.ui.dialogue_finished.emit(0)
	await process_frame
	game.settings["reduced_motion"] = false
	# Title/reset and map cancellation both restore an active temporary camera.
	game._dialogue("Mother noooooo!", 1, {"script":"s1-h1-s", "sprite_id":1})
	await process_frame
	check(game.fps_dialogue_camera_active, "Grief camera starts before title/reset cancellation")
	game.playing = false
	game._physics_process(0.016)
	check(not game.fps_dialogue_camera_active, "Title/reset cancels the grief camera")
	check(is_equal_approx(game.fps_yaw, ordinary_yaw) and is_equal_approx(game.fps_pitch, ordinary_pitch), "Title/reset preserves the saved camera rotation")
	game.ui.dialogue_finished.emit(0)
	await process_frame
	game.playing = true
	game._dialogue("Mother noooooo!", 1, {"script":"s1-h1-s", "sprite_id":1})
	await process_frame
	check(game.fps_dialogue_camera_active, "Grief camera starts before map cancellation")
	game.load_map(439, false)
	await process_frame
	check(not game.fps_dialogue_camera_active, "Map load cancels the grief camera")
	check(is_equal_approx(game.fps_yaw, ordinary_yaw) and is_equal_approx(game.fps_pitch, ordinary_pitch), "Map cancellation preserves the saved camera rotation")
	if failures.is_empty(): print("FPS GRIEF PRESENTATION PASS")
	else: print("FPS GRIEF PRESENTATION FAILURES: ", failures)
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
