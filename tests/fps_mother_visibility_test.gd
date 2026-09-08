extends SceneTree

const GAME := preload("res://scripts/fps_game.gd")

var game
var failures: Array[String] = []
var capture_path := ""

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="): capture_path = arg.trim_prefix("--capture=")
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
	var mother := 0
	for id in game.entities:
		if str(game.entities[id].get("script", "")).to_lower() == "s1-h1-m": mother = int(id)
	check(mother != 0, "Home fixture contains Mother's original entity")
	if mother != 0:
		# This is the earned-route doorway position seen in the old blocked capture.
		game.entities[1]["x"] = 323.0
		game.entities[1]["y"] = 370.833333
		# S1-H1-M moves Mother from her editor position to y=200 before the
		# original six-line request. Exercise that live-dialogue placement.
		# Her normal walk can move x before this script forces y, so this is the
		# observed production placement rather than her editor anchor.
		game.entities[mother]["x"] = 216.583511
		game.entities[mother]["y"] = 200.0
		game._update_visual(mother)
		await physics_frame
		game.fps_yaw = 0.585729
		game.fps_pitch = 0.022599
		game.vm.globals["story"] = 2
		game._sync_fps_camera()
		var player_position: Vector2 = game._position2(1)
		var player_camera: Vector3 = game.camera.position
		game.test_mode = false
		game._dialogue("some AlkTree nuts, I think they're in season.", mother, {"sprite_id":mother})
		await process_frame
		check(game.fps_dialogue_camera_active, "Blocked Story 2 Mother line uses a temporary clear room camera")
		check(not game.camera.position.is_equal_approx(player_camera), "Temporary Mother camera does not move Dink's player camera position")
		var dialogue_camera: Vector3 = game.camera.position
		check(game._fps_ray_reaches(mother), "Temporary Mother camera has a physical ray to Mother")
		if not capture_path.is_empty():
			await RenderingServer.frame_post_draw
			get_root().get_texture().get_image().save_png(capture_path)
		game.ui.dialogue_finished.emit(0)
		await process_frame
		await process_frame
		check(not game.fps_dialogue_camera_active, "Mother dialogue completion restores the ordinary player camera")
		check(game.camera.position.is_equal_approx(player_camera), "Mother dialogue restoration preserves player camera position")
		check(game._position2(1).is_equal_approx(player_position), "Mother dialogue camera never changes Dink's coordinates")
		check(is_equal_approx(game.fps_yaw, 0.585729) and is_equal_approx(game.fps_pitch, 0.022599), "Mother dialogue restoration preserves player camera rotation")
		check(not dialogue_camera.is_equal_approx(player_camera), "Fixture exercised a separate cinematic vantage")
		# Keep the original editor-side x placement covered as well as the normal
		# walk-drifted production position above.
		game.entities[mother]["x"] = 202.0
		game.entities[mother]["y"] = 200.0
		game._update_visual(mother)
		game._sync_fps_camera()
		game._dialogue("Mother checks the original room position.", mother, {"sprite_id":mother})
		await process_frame
		check(game.fps_dialogue_camera_active, "Original Mother x=202 placement uses a temporary clear camera")
		check(game._fps_ray_reaches(mother), "Original Mother x=202 temporary camera has a physical ray")
		if not capture_path.is_empty():
			await RenderingServer.frame_post_draw
			get_root().get_texture().get_image().save_png(capture_path.get_basename() + "-x202.png")
		game.ui.dialogue_finished.emit(0)
		await process_frame
		await process_frame
		game.entities[mother]["x"] = 216.583511
		game.entities[mother]["y"] = 200.0
		game._update_visual(mother)
		game._sync_fps_camera()
		await physics_frame
		# A transition to title/reset runs no world physics, so that early exit
		# must release a temporary viewpoint even if UI cancellation is silent.
		game._dialogue("Mother checks the map transition.", mother, {"sprite_id":mother})
		await process_frame
		check(game.fps_dialogue_camera_active, "Second Mother line starts a temporary camera before title/reset")
		game.playing = false
		game._physics_process(0.016)
		check(not game.fps_dialogue_camera_active, "Title/reset physics releases the temporary Mother camera")
		check(is_equal_approx(game.fps_yaw, 0.585729) and is_equal_approx(game.fps_pitch, 0.022599), "Title/reset preserves the saved player rotation")
		game.ui.dialogue_finished.emit(0)
		await process_frame
		game.playing = true
		# Map teardown must likewise never leave a detached cinematic camera active.
		game._dialogue("Mother checks the map transition.", mother, {"sprite_id":mother})
		await process_frame
		check(game.fps_dialogue_camera_active, "Third Mother line starts a temporary camera before map cancellation")
		game.load_map(439, false)
		await process_frame
		check(not game.fps_dialogue_camera_active, "Map load cancels and restores the temporary Mother camera")
		check(is_equal_approx(game.fps_yaw, 0.585729) and is_equal_approx(game.fps_pitch, 0.022599), "Map cancellation preserves the saved player rotation")
	if failures.is_empty(): print("FPS MOTHER VISIBILITY PASS")
	else: print("FPS MOTHER VISIBILITY FAILURES: ", failures)
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
