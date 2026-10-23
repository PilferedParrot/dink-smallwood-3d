extends SceneTree

# The original 2D map stores a player arrival behind its projected near-wall
# rows. These checks use a real outdoor keyboard return, then labelled direct
# fixtures for restored/scripted positions and collision state.
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
	game.vm.cancel_all()
	game.ui.close_menu()
	game.playing = true
	game.changing = false
	# Labelled quest fixture: story 1 has no opening freeze or burning-home
	# cutscene. The default story 0 intentionally freezes input for the mother
	# conversation and cannot test the first controllable step after a return.
	game.vm.globals["story"] = 1

	var source: Dictionary = {}
	for e in game.world.screens["439"].sprites:
		if int(e.get("index", 0)) == 13: source = e
	check(not source.is_empty() and int(source.warp.map) == 1 and int(source.warp.x) == 323 and int(source.warp.y) == 390,
		"Outdoor editor warp retains raw destination (1,323,390)")

	# Ordinary return: drive W through the exterior editor warp. The FPS map
	# entry maps only the live player from raw y=390 to inner plane 352 minus
	# the existing four-pixel player clearance.
	game.entities[1]["x"] = 365.0
	game.entities[1]["y"] = 305.0
	game.load_map(439, false)
	await process_frame
	game.warp_cooldown = 0.0
	game.fps_yaw = 0.0
	game.fps_pitch = 0.0
	game._sync_fps_camera()
	var returned: bool = await _hold_until_screen(KEY_W, 1, 20)
	check(returned and game.current_screen == 1, "Real W approach enters screen 1")
	if returned:
		var arrived: Vector2 = game._position2(1)
		check(absf(arrived.x - 323.0) < 0.1 and arrived.y <= 348.0 and arrived.y >= 345.0,
			"Live return occupies room-side clearance at y=348 (got %s)" % arrived)
		var first_y := arrived.y
		check(not game.entities[1].get("frozen", false) and not game.ui.modal, "Normal-return fixture is controllable before first W")
		await _hold(KEY_W, 3)
		print("MAPPING FIRST W: before=", first_y, " after=", game._position2(1), " cooldown=", game.warp_cooldown)
		check(game.current_screen == 1 and float(game.entities[1].y) < first_y - 0.5,
			"First inward W input moves immediately from adapted arrival")
		var getter_value: Variant = await game.dink_call("sp_y", [1, -1], {})
		check(float(getter_value) == float(game.entities[1].y),
			"sp_y getter reports the live coordinate")

	# Direct save-position fixture: raw 390 maps once; an already adapted 348
	# survives another load unchanged. The source record is still 390.
	game.entities[1]["x"] = 323.0
	game.entities[1]["y"] = 390.0
	game.load_map(1, false)
	check(absf(float(game.entities[1].y) - 348.0) < 0.001, "Raw saved band position maps to y=348")
	var leaf: MeshInstance3D = game.scene_root.get_node_or_null("ExitDoor") as MeshInstance3D
	var leaf_body: StaticBody3D = null
	if leaf != null: leaf_body = leaf.get_node_or_null("HitBody") as StaticBody3D
	check(leaf != null and leaf_body != null, "Closed visible leaf carries its matching ray body")
	if leaf != null and leaf_body != null:
		var shape := leaf_body.get_child(0) as CollisionShape3D
		check(shape != null and shape.shape is ConcavePolygonShape3D and
			(shape.shape as ConcavePolygonShape3D).get_faces().size() == leaf.mesh.get_faces().size(),
			"Ray body uses the same mesh faces as the closed leaf")
	game.load_map(1, false)
	check(absf(float(game.entities[1].y) - 348.0) < 0.001, "Adapted save position is idempotent")
	check(int(source.warp.y) == 390, "Live adaptation never changes the source warp")
	game.warp_cooldown = 0.65
	var setter_value: Variant = await game.dink_call("sp_y", [1, 390], {})
	var set_y: float = float(setter_value)
	check(absf(set_y - 348.0) < 0.001 and absf(float(game.entities[1].y) - 348.0) < 0.001,
		"sp_y setter maps an old interior-band value and returns the live value")
	check(absf(game._script_move_destination(1, 8, 370.0) - 348.0) < 0.001,
		"Original north-wait goal 370 maps to the same room-side clearance")
	check(absf(game._script_move_destination(1, 2, 398.0) - 348.0) < 0.001,
		"Original evacuation goal 398 maps to the same source-derived doorway")

	# A closed door remains solid while cooldown prevents a warp. The leaf is the plane itself (a mover is a point): the
	# player stands up to it and may reverse toward the room.
	var at := Vector2(323.0, 351.0)
	check(game._blocked(Vector2(323.0, 352.5), 1, at), "Inactive leaf stops movement toward the plane")
	check(not game._blocked(Vector2(323.0, 350.5), 1, at), "Inactive leaf allows reverse movement from the plane")
	game.fps_yaw = 0.0
	game._sync_fps_camera()
	await _hold(KEY_S, 5)
	print("MAPPING INACTIVE S: position=", game._position2(1), " cooldown=", game.warp_cooldown, " portal=", game._portal_can_warp(25))
	check(float(game.entities[1].y) >= 351.0 and float(game.entities[1].y) < 352.0, "Cooldown makes actual southward input stop at closed leaf")
	await _hold(KEY_W, 5)
	check(float(game.entities[1].y) < 350.0, "Actual northward input backs out without a zero-motion trap")
	game.warp_cooldown = 0.0
	check(game._portal_can_warp(25), "An available live portal is active after cooldown")
	game.locked = true
	check(not game._portal_can_warp(25) and game._blocked(Vector2(323.0, 352.5), 1, at),
		"Screen lock makes the closed leaf solid")
	game.locked = false
	game.entities[1]["frozen"] = true
	check(not game._portal_can_warp(25), "Freeze makes normal-input portal inactive")
	game.entities[1]["frozen"] = false
	game.entities[1]["nocontrol"] = 1
	check(not game._portal_can_warp(25), "No-control animation makes portal inactive")
	game.entities[1]["nocontrol"] = 0
	game.changing = true
	check(not game._portal_can_warp(25), "Changing screens makes portal inactive")
	game.changing = false

	# Other fitted exits apply the same source rule. A setter targeting an
	# outdoor map retains its numerically similar y=373, as s2-bar requires.
	var others := 0
	for pair in [[2, 409, 16], [34, 498, 10]]:
		var screen: int = int(pair[0])
		var ex: Dictionary = {}
		for candidate in game.fp_world.solids.exits(screen):
			if game.fp_world.solids.portal_rect(screen, int(candidate.editor_num)).has_area(): ex = candidate
		if ex.is_empty(): continue
		var incoming: Dictionary = {}
		for candidate in game.world.screens[str(pair[1])].sprites:
			if int(candidate.get("index", 0)) == int(pair[2]): incoming = candidate
		check(not incoming.is_empty() and int(incoming.warp.map) == screen, "Actual incoming editor warp for screen %d exists" % screen)
		if incoming.is_empty(): continue
		others += 1
		game.entities[1]["x"] = float(incoming.warp.x)
		game.entities[1]["y"] = float(incoming.warp.y)
		game.load_map(screen, false)
		check(absf(float(game.entities[1].y) - (float(ex.zinner) - float(game.ARRIVAL_INSET_PX))) < 0.001,
			"Screen %d maps its actual incoming warp into its fitted doorway" % screen)
	check(others == 2, "Two other fitted south exits exercise the same mapping")
	# Screen 65's real inbound y=343 is already on the room side; it stays 343.
	game.entities[1]["x"] = 317.0
	game.entities[1]["y"] = 343.0
	game.load_map(65, false)
	check(absf(float(game.entities[1].y) - 343.0) < 0.001, "An already room-side incoming warp is unchanged")
	game.entities[1]["x"] = 320.0
	game.entities[1]["y"] = 330.0
	game.load_map(34, false)
	game.vm.globals["player_map"] = 498
	await game.dink_call("sp_x", [1, 320], {})
	await game.dink_call("sp_y", [1, 373], {})
	check(absf(float(game.entities[1].y) - 373.0) < 0.001,
		"s2-bar's sp_y=373 is an outdoor destination setter, not an interior-band value")
	game.load_map(498, false)
	check(absf(float(game.entities[1].y) - 373.0) < 0.001, "Outdoor load retains scripted arrival y=373")

	# Active outbound movement still reaches the original screen 439 warp.
	game.entities[1]["x"] = 323.0
	game.entities[1]["y"] = 330.0
	game.load_map(1, false)
	game.warp_cooldown = 0.0
	game.fps_yaw = 0.0
	game._sync_fps_camera()
	var exited: bool = await _hold_until_screen(KEY_S, 439, 24)
	check(exited and game.current_screen == 439, "Active southward keyboard approach uses original outward warp")
	if exited:
		var destination: Vector2 = game._position2(1)
		check(destination.distance_to(Vector2(365, 307)) < 5.0, "Original outdoor arrival remains (365,307)")

	game.vm.cancel_all()
	game.queue_free()
	await process_frame
	if failures.is_empty(): print("FPS FOYER MAPPING PASS: live arrival, script goals and inactive leaf agree")
	quit(0 if failures.is_empty() else 1)

func _hold(key: Key, frames: int) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = key
	down.pressed = true
	Input.parse_input_event(down)
	Input.flush_buffered_events()
	for _i in frames: await physics_frame
	var up := InputEventKey.new()
	up.physical_keycode = key
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	await physics_frame
	check(not Input.is_action_pressed("up") and not Input.is_action_pressed("down"), "Delivered directional release before the next fixture")

func _hold_until_screen(key: Key, screen: int, frames: int) -> bool:
	var down := InputEventKey.new()
	down.physical_keycode = key
	down.pressed = true
	Input.parse_input_event(down)
	Input.flush_buffered_events()
	var reached := false
	for _i in frames:
		await physics_frame
		if game.current_screen == screen:
			reached = true
			break
	var up := InputEventKey.new()
	up.physical_keycode = key
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	await physics_frame
	check(not Input.is_action_pressed("up") and not Input.is_action_pressed("down"), "Delivered portal-approach release before another hold")
	return reached

func check(condition: bool, message: String) -> void:
	if condition: return
	failures.append(message)
	push_error(message)
