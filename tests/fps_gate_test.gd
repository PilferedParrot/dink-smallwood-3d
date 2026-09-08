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
	game.load_map(407, false)
	await process_frame
	game.vm.cancel_all()
	game.playing = true
	game.changing = false
	game.ui.close_menu()
	game.fps_yaw = 0.0
	game.fps_pitch = 0.0

	# Scenario setup: place the player at the campaign's west approach, then use
	# the real keyboard input path to walk north through the hard=1 fence gate.
	game.entities[1].x = 110.0
	game.entities[1].y = 390.0
	game._sync_fps_camera()
	await _hold(KEY_W, 100)
	check(game._position2(1).y < 350.0, "Keyboard approach crosses the non-solid west fence gate")

	var open_fence := _entity_at(126.0, 359.0)
	check(not open_fence.is_empty() and int(open_fence.get("hard", 0)) == 1, "West gate retains source hard=1")
	if not open_fence.is_empty():
		check(_find_entity_body(int(open_fence.get("_id", 0))) == null, "Hard=1 gate has no first-person HitBody")

	# Scenario setup: the hard-zero south fence remains an intentional barrier.
	game.entities[1].x = 320.0
	game.entities[1].y = 390.0
	game._sync_fps_camera()
	await _hold(KEY_W, 60)
	check(game._position2(1).y > 378.0, "Hard-zero south fence still blocks north movement")
	var solid_fence := _entity_at(275.0, 361.0)
	check(not solid_fence.is_empty() and int(solid_fence.get("hard", 0)) == 0, "South fence retains source hard=0")
	if not solid_fence.is_empty():
		check(_find_entity_body(int(solid_fence.get("_id", 0))) != null, "Hard-zero fence retains its HitBody")

	game.queue_free()
	if failures.is_empty(): print("FPS GATE PASS: hard=1 fence opening is walkable and hard=0 fence remains solid")
	else: print("FPS GATE FAILURES: ", failures)
	quit(0 if failures.is_empty() else 1)

func _hold(key: int, frames: int) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = key
	down.pressed = true
	Input.parse_input_event(down)
	for _i in frames: await physics_frame
	var up := InputEventKey.new()
	up.physical_keycode = key
	Input.parse_input_event(up)
	await physics_frame

func _entity_at(x: float, y: float) -> Dictionary:
	for id in game.entities:
		var e: Dictionary = game.entities[id]
		if is_equal_approx(float(e.get("x", -999)), x) and is_equal_approx(float(e.get("y", -999)), y):
			var result := e.duplicate()
			result["_id"] = int(id)
			return result
	return {}

func _find_entity_body(id: int) -> Node:
	return _find_entity_body_in(game.scene_root, id)

func _find_entity_body_in(node: Node, id: int) -> Node:
	for child in node.get_children():
		if child.name == "HitBody" and int(child.get_meta("entity_id", 0)) == id: return child
		var found := _find_entity_body_in(child, id)
		if found != null: return found
	return null

func check(condition: bool, message: String) -> void:
	if condition: return
	failures.append(message)
	push_error(message)
