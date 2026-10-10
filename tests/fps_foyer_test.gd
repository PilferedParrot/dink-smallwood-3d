extends SceneTree

# Screen 1's south doorway is derived from the original jamb footprints. Drive the
# player through it with the same keyboard input path used during play.
const GAME := preload("res://scripts/fps_game.gd")
const SCALE := 0.025
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
	game.vm.globals["vision"] = 0
	game.load_map(1, false)
	await process_frame
	game.vm.cancel_all()
	game.playing = true
	game.changing = false
	game.ui.close_menu()
	game.warp_cooldown = 0.0

	var solids = game.fp_world.solids
	var source: Dictionary = {}
	for e in game.world.screens["1"].sprites:
		if int(e.get("index", 0)) == 25: source = e
	check(not source.is_empty(), "The original screen 1 warp sprite exists")
	var portal: Rect2 = solids.portal_rect(1, 25)
	check(portal == Rect2(308, 352, 31, 1), "Aperture and inner plane come from the two source jambs: %s" % portal)
	check(not solids.portal_rect(1, 9999).has_area(), "Unsupported source editor numbers have no portal")
	var ex: Dictionary = {}
	for candidate in solids.exits(1):
		if int(candidate.editor_num) == 25: ex = candidate
	check(not ex.is_empty() and int(ex.original_base) == 400, "Original illustrated base is retained as evidence")

	var door: Node3D = game.scene_root.get_node_or_null("ExitDoor")
	var lintel: Node3D = game.scene_root.get_node_or_null("ExitLintel")
	check(door != null and lintel != null, "A door and lintel close the south opening")
	if door != null and lintel != null:
		var door_box := _aabb(door)
		var lintel_box := _aabb(lintel)
		var plane := (portal.position.y - 200.0) * SCALE
		check(absf(door_box.position.z - plane) < 0.001, "Door is flush with the inner plane: %s vs %s" % [door_box.position.z, plane])
		check(absf(lintel_box.position.z - plane) < 0.001, "Lintel shares the door plane")

	var live: Dictionary = {}
	for id in game.entities:
		if id != 1 and int(game.entities[id].get("editor_num", 0)) == 25: live = game.entities[id]
	check(not live.is_empty(), "The source warp has a live entity")
	if not live.is_empty():
		var hard: Rect2 = game._hard_rect(live)
		check(hard == portal and bool(live.get("fps_portal", false)), "Live warp bounds match the drawn doorway: %s" % hard)
	check(int(source.warp.map) == 439 and int(source.warp.x) == 365 and int(source.warp.y) == 307,
		"Original destination remains screen 439 at (365,307)")

	# Approach immediately beside the opening by the real keyboard path. The jamb
	# can stop movement, but the portal must never catch this lateral position.
	_place(306.0, 330.0)
	await _hold(KEY_S, 18)
	check(game.current_screen == 1, "Southward keyboard approach outside x=308 does not warp")

	# The middle of the opening remains passable and leads to the original warp.
	_place(portal.get_center().x, 330.0)
	var arrived := await _hold_until_warp(KEY_S, 24)
	check(arrived and game.current_screen == 439, "Centered southward keyboard approach exits to screen 439 (screen %s, pos %s)" % [game.current_screen, game._position2(1)])
	if arrived:
		var dest: Vector2 = game._position2(1)
		check(dest.distance_to(Vector2(365, 307)) < 5.0, "Arrival stays at the original (365,307): %s" % dest)
	check(int(source.x) == 325 and int(source.y) == 437, "Raw source warp record remains at its original location")

	game.vm.cancel_all()
	game.queue_free()
	await process_frame
	if failures.is_empty(): print("FPS FOYER PASS: source-derived flush door, bounded portal, and original keyboard warp")
	quit(0 if failures.is_empty() else 1)

func _aabb(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var meshes := node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D: meshes.append(node)
	for mesh in meshes:
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out

func _place(x: float, y: float) -> void:
	game.entities[1]["x"] = x
	game.entities[1]["y"] = y
	game.warp_cooldown = 0.0
	game.fps_yaw = 0.0
	game.fps_pitch = 0.0
	game._sync_fps_camera()

func _key(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)

func _hold(key: Key, frames: int) -> void:
	_key(key, true)
	for _i in frames: await physics_frame
	_key(key, false)
	await physics_frame

func _hold_until_warp(key: Key, frames: int) -> bool:
	_key(key, true)
	for _i in frames:
		await physics_frame
		if game.current_screen == 439:
			_key(key, false)
			return true
	_key(key, false)
	return false

func check(condition: bool, message: String) -> void:
	if condition: return
	failures.append(message)
	push_error(message)
