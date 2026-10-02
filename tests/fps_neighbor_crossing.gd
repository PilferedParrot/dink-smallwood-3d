extends SceneTree

# Scenario setup skips the Ethel quest but crosses the 439 -> 440 edge with the
# real W-key input path. The screen must use the private neighbour preview's
# duck-search roll when its story state still matches on entry.
const GAME := preload("res://scripts/fps_game.gd")
const SANDBOX := preload("res://scripts/neighbour_script_sandbox.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	await game._new_game()
	game.vm.cancel_all()
	game.vm.globals["story"] = 1
	game.vm.globals["old_womans_duck"] = 1
	game.neighbour_seed_override = 3 # preregistered survey: 440 rolls random(4,1) = 1
	game.load_map(439, false)
	var preview: Dictionary = game.fp_world.neighbour_states.get(440, {})
	check(int(preview.get("vision", 0)) == 2, "439 previews 440's duck vision")
	check(preview.get("sprites", []).any(func(e): return str(e.get("script", "")) == "s1-oldd"), "the duck is in the neighbour preview")
	# If entry rerolls instead of reusing the preview, this other private seed
	# would put 440 on vision 0. Changing the seed does not change cache state.
	var nonduck_seed := -1
	for seed in range(4, 100):
		if int(SANDBOX.new(game, 440, seed).run_startup().vision) != 2:
			nonduck_seed = seed
			break
	check(nonduck_seed >= 0, "control seed for a different random outcome exists")
	if nonduck_seed >= 0: game.neighbour_seed_override = nonduck_seed
	var edge_y := -1.0
	for y in [103.0, 180.0, 250.0, 300.0, 350.0]:
		if not game._blocked(Vector2(618.0, y), 1):
			edge_y = y
			break
	check(edge_y >= 0.0, "an eastern crossing point is open")
	if edge_y >= 0.0:
		game.entities[1].x = 618.0
		game.entities[1].y = edge_y
		game.fps_yaw = -PI / 2.0
		game.fps_pitch = -0.05
		game._sync_fps_camera()
		game.ui.close_menu()
		game.playing = true
		game.warp_cooldown = 0.0
		var down := InputEventKey.new()
		down.physical_keycode = KEY_W
		down.pressed = true
		Input.parse_input_event(down)
		for _i in 90:
			await physics_frame
			if game.current_screen == 440: break
		var up := InputEventKey.new()
		up.physical_keycode = KEY_W
		up.pressed = false
		Input.parse_input_event(up)
		await process_frame
	check(game.current_screen == 440, "W-key walk crosses from 439 to 440")
	if game.current_screen == 440:
		check(int(game.vm.globals.get("vision", 0)) == 2, "entry reuses the preview's duck vision")
		check(game.entities.values().any(func(e): return str(e.get("script", "")) == "s1-oldd"), "entry contains the previewed duck")
	game.vm.cancel_all()
	game.queue_free()
	await process_frame
	if failures.is_empty(): print("NEIGHBOR CROSSING PASS")
	else: print("NEIGHBOR CROSSING FAILURES: ", failures)
	quit(0 if failures.is_empty() else 1)
