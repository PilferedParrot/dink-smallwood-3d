extends SceneTree

const GAME := preload("res://scripts/fps_game.gd")
var game
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	await game._new_game()
	await create_timer(0.5).timeout
	game.vm.cancel_all()
	game.playing = true
	game.changing = false
	game.ui.close_menu()

	# Entering the pig farm from 439 at x=400 once put the old 0.24 m capsule inside the
	# decorative rocks-09 model at (400,390), where every movement input was rejected, and a
	# landing-recovery search moved the player. Collision now comes from the original data
	# alone (docs/DIRECTION.md, seventh pass), so the landing is walkable where it lands.
	await _enter_pig_farm(400)
	var landed: Vector2 = game._position2(1)
	check(game.current_screen == 407, "North exit from screen 439 enters pig farm")
	check(not game._blocked(landed,1), "Pig-farm landing is walkable in the original data")
	var escaped := false
	for pair in [["north",KEY_W],["south",KEY_S],["west",KEY_A],["east",KEY_D]]:
		game.entities[1]["x"] = landed.x; game.entities[1]["y"] = landed.y; game._sync_fps_camera()
		var before: Vector2 = game._position2(1)
		await _hold(int(pair[1]),4)
		escaped = escaped or game._position2(1).distance_to(before) > 0.01
	check(escaped, "Pig-farm landing has an actual keyboard route onward")
	check(not game.has_method("_fps_recover_landing_overlap"), "No landing-recovery search remains")

	# A normal adjacent landing remains held by the intentional north fence while
	# retaining back and strafe movement.
	await _enter_pig_farm(320)
	var fence_pos: Vector2 = game._position2(1)
	var north_before: Vector2 = fence_pos
	await _hold(KEY_W,4)
	check(game._position2(1).distance_to(north_before) < 0.01, "Pigpen fence still blocks north movement")
	for key in [KEY_S,KEY_A,KEY_D]:
		game.entities[1]["x"] = fence_pos.x; game.entities[1]["y"] = fence_pos.y; game._sync_fps_camera()
		var before: Vector2 = game._position2(1)
		await _hold(key,4)
		check(game._position2(1).distance_to(before) > 0.01, "Pigpen fence retains back and strafe escape")

	# A saved position that the old capsule found embedded loads where it was saved.
	game.load_map(407,false)
	await process_frame
	game.entities[1]["x"] = 400.0; game.entities[1]["y"] = 390.0; game._sync_fps_camera()
	check(game._save_game("user://embedded-pigpen.json"), "Embedded test save writes")
	check(game._load_game("user://embedded-pigpen.json"), "Embedded test save loads")
	await physics_frame
	await physics_frame
	check(game._position2(1).distance_to(Vector2(400,390)) < 0.01 and not game._blocked(game._position2(1),1), "A saved pig-farm position loads unchanged and walkable")
	DirAccess.remove_absolute("user://embedded-pigpen.json")
	game.vm.cancel_all(); game.queue_free()
	if failures.is_empty(): print("FPS STUCK PASS: pig-farm transition and saved position walkable from source collision; fence holds")
	quit(0 if failures.is_empty() else 1)

func _enter_pig_farm(x: float) -> void:
	game.load_map(439,false)
	await process_frame
	game.entities[1]["x"] = x; game.entities[1]["y"] = 10.0
	game.warp_cooldown = 0.0
	game.fps_yaw = 0.0; game.fps_pitch = 0.0
	game._sync_fps_camera()
	await _hold(KEY_W,12)

func _hold(key: int, frames: int) -> void:
	var down := InputEventKey.new(); down.physical_keycode = key; down.pressed = true
	Input.parse_input_event(down)
	for _i in frames: await physics_frame
	var up := InputEventKey.new(); up.physical_keycode = key; up.pressed = false
	Input.parse_input_event(up)
	await physics_frame

func check(condition: bool, message: String) -> void:
	if condition: return
	failures.append(message)
	push_error(message)
