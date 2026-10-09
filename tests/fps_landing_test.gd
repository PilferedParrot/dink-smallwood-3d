extends SceneTree

# Walking east from screen 376 into 377 near the bottom edge lands Dink at (32, 375.0037). The
# tree there (editor sprite 6, hardbox [-48,-13,46,23] about 81,374) starts at x=33 in the
# original, but the game's 4 px player clearance grows its box to x=29, so the landing sat
# inside the grown box and every step was rejected: the player was trapped. The clearance band
# must never trap a mover that stands in it: it may leave or slide, not step closer to the solid.

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

	game.load_map(376,false)
	await process_frame
	game.entities[1]["x"] = 619.0; game.entities[1]["y"] = 375.003753662109
	game.warp_cooldown = 0.0
	game.fps_yaw = 0.0; game.fps_pitch = 0.0
	game._sync_fps_camera()
	# Walk off the east edge exactly as the physics loop does: the next step crosses x=620.
	game._move_entity(1, Vector2(2.0, 0.0))
	game._transitions()
	await process_frame
	await process_frame
	check(game.current_screen == 377, "East exit from screen 376 enters 377")
	var landed: Vector2 = game._position2(1)
	check(landed.distance_to(Vector2(32.0, 375.003753662109)) < 0.01, "The crossing lands at the reported trap point, got %s" % landed)

	# The fixture's premise: the landing is in the tree's clearance band, not its own box.
	var tree: Dictionary = {}
	for id in game.entities:
		if int(game.entities[id].get("editor_num",0)) == 6 and id != 1: tree = game.entities[id]
	check(not tree.is_empty(), "Screen 377 has editor sprite 6")
	if not tree.is_empty():
		var rect: Rect2 = game._hard_rect(tree)
		check(rect.grow(4).has_point(landed) and not rect.has_point(landed), "Landing is inside the grown box but outside the tree's own box")
		check(game._blocked(landed,1), "A plain point query still treats the clearance band as solid")

	# Every way that does not enter the tree is open; the tree itself still holds.
	var open_dirs := 0
	for pair in [["north",KEY_W],["south",KEY_S],["west",KEY_A]]:
		game.entities[1]["x"] = landed.x; game.entities[1]["y"] = landed.y; game._sync_fps_camera()
		var before: Vector2 = game._position2(1)
		await _hold(int(pair[1]),6)
		var moved: bool = game._position2(1).distance_to(before) > 0.01
		if moved: open_dirs += 1
		# A west step may legitimately cross back to 376; either way Dink moved.
		check(moved, "Dink can move %s out of the landing" % pair[0])
		if game.current_screen != 377:
			game.load_map(377,false); await process_frame
	check(open_dirs == 3, "Three directions open")
	game.entities[1]["x"] = landed.x; game.entities[1]["y"] = landed.y; game._sync_fps_camera()
	game._move_entity(1, Vector2(3.0, 0.0))
	check(game._position2(1).x < 33.0, "The tree's own box still stops an eastward step (x=%s)" % game._position2(1).x)

	# Out the north side: slide along the band and clear the tree's grown box entirely.
	game.entities[1]["x"] = landed.x; game.entities[1]["y"] = landed.y
	for _i in 60: game._move_entity(1, Vector2(0.0, -1.0))
	check(game._position2(1).y < 357.0 and not game._blocked(game._position2(1),1), "Dink walks clear of the tree to the north")

	game.vm.cancel_all(); game.queue_free()
	if failures.is_empty(): print("FPS LANDING PASS: 376 -> 377 landing in the tree's clearance band is walkable and the tree still holds")
	quit(0 if failures.is_empty() else 1)

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
