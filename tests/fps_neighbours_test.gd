extends SceneTree
# Neighbour screens draw their actors (docs/DIRECTION.md, tenth pass). The game builds the current screen
# and its 5x5 block of neighbours; a neighbour's people and animals were skipped, so the continuous world was
# empty of life beyond the screen you stand on. They now stand where the editor put them, in the frame the
# screen loads them with, redrawn for the camera every frame (fp_world.gd face_neighbours). Run by
# tests/test_fps_neighbours.py:
#
#   --dump=439,406   (headless is enough) load each screen with its scripts off, vision 0, and print
#                    "ACTOR loaded neighbour x y key path" for every actor the neighbours draw (x, y: the map's own
#                    coordinates on the neighbour screen), and "DIGEST loaded count hash" of every non-actor neighbour
#                    node (position, model key, frame): the rail, equal before and after the change.
#   --face           load 439 and, for the pig of 407 at (289, 302), put the camera due south, due north, due east
#                    and due west of it, call face_neighbours() when it exists, and print "FACE label path": the frame
#                    the pig shows.
#   --live           as --face, but the game runs (playing, scripts off) with the camera south-west, south and south-east
#                    of the pig, on 439: no face_neighbours() is called here; the game's own _physics_process must
#                    redraw the pig, and "LIVE label path" is what it shows.
#   --render         (rendered, under xvfb, Dummy audio) 439 from (300, 70) yaw 0: print "PIG x y changed" for each of
#                    407's pigs, the pixels that change when that one pig is hidden (0 when it is not in the picture),
#                    and "NOISE n", the pixels that change between two renders of the same scene.
# Verdict: written 2026-10-01 (Sonnet 5.5 subagent).
const GAME = preload("res://scripts/fps_game.gd")
const SCALE := 0.025

var game

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var dump: Array = []
	var face := false
	var render := false
	var live := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--dump="):
			for s in arg.trim_prefix("--dump=").split(",", false): dump.append(int(s))
		if arg == "--face": face = true
		if arg == "--render": render = true
		if arg == "--live": live = true
	game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	await game._new_game()
	await create_timer(1.0).timeout
	for n in dump:
		await _load(int(n))
		_dump(int(n))
	if face:
		await _load(439)
		_face()
	if live:
		await _load(439)
		await _live()
	if render:
		await _load(439)
		await _render()
	print("FPS NEIGHBOURS DONE")
	quit(0)

func _load(screen: int) -> void:
	game.vm.cancel_all()
	game.vm.globals["vision"] = 0
	game.load_map(screen, false)
	await create_timer(0.6).timeout
	game.vm.cancel_all()
	game.playing = false
	game.ui.close_menu()
	game.ui.toast.text = ""

# The neighbour screens' entity nodes: [screen, node].
func _entities() -> Array:
	var out: Array = []
	for child in game.scene_root.get_children():
		if not str(child.name).begins_with("Neighbor_"): continue
		var n := int(str(child.name).trim_prefix("Neighbor_"))
		for node in child.get_children():
			if node.has_meta("model_key"): out.append([n, node])
	return out

func _model(node: Node) -> Sprite3D:
	var model: Node = node.get_node_or_null("Model")
	return model as Sprite3D if model is Sprite3D else null

# The map's own coordinates on screen n of a node standing on it (the node holds the sprite's hotspot).
func _map_xy(n: int, node: Node3D) -> Vector2i:
	var offset: Vector2 = game.fp_world.screen_origin(game.current_screen) - game.fp_world.screen_origin(n)
	var local := Vector2(node.global_position.x / SCALE + 320.0, node.global_position.z / SCALE + 200.0)
	return Vector2i(roundi(local.x + offset.x), roundi(local.y + offset.y))

func _dump(loaded: int) -> void:
	var hash_context := HashingContext.new()
	hash_context.start(HashingContext.HASH_SHA256)
	var count := 0
	for pair in _entities():
		var node: Node3D = pair[1]
		var sp := _model(node)
		var path := str(sp.get_meta("path", "")) if sp != null else ""
		var key := str(node.get_meta("model_key", ""))
		var at := _map_xy(int(pair[0]), node)
		if node.get_meta("actor", false):
			print("ACTOR %d %d %d %d %s %s" % [loaded, int(pair[0]), at.x, at.y, key, path])
			continue
		count += 1
		var line := "%d %s %.4f %.4f %.4f %s %s\n" % [int(pair[0]), key, node.position.x, node.position.y, node.position.z, path, str(sp.position) if sp != null else ""]
		hash_context.update(line.to_utf8_buffer())
	print("DIGEST %d %d %s" % [loaded, count, hash_context.finish().hex_encode()])

func _set_camera(x: float, y: float, yaw: float, pitch: float) -> void:
	game.entities[1].x = x
	game.entities[1].y = y
	game.fps_yaw = yaw
	game.fps_pitch = pitch
	game._sync_fps_camera()
	for model in [game.fps_viewmodel, game.fps_hand]:
		if is_instance_valid(model): model.visible = false

# The pig of 407 at (289, 302) is the target; its position in 439's pixels is (289, -98).
func _target() -> Sprite3D:
	for pair in _entities():
		if int(pair[0]) == 407 and _map_xy(407, pair[1]) == Vector2i(289, 302): return _model(pair[1])
	return null

# The game runs: a camera outside 439 would walk the player onto the next screen, so the cameras are the south-west,
# south and south-east of the pig, on 439 itself.
func _live() -> void:
	var target := _target()
	if target == null:
		print("LIVE none none")
		return
	game.playing = true
	for view in [["sw", 30, 40], ["south", 289, 40], ["se", 550, 40]]:
		_set_camera(float(view[1]), float(view[2]), 0.0, -0.05)
		await create_timer(0.3).timeout
		print("LIVE %s %s" % [view[0], str(target.get_meta("path", ""))])
	game.playing = false

func _face() -> void:
	var target := _target()
	if target == null:
		print("FACE none none")
		return
	var spot := Vector2(289, -98)
	for view in [["south", 0, 150], ["north", 0, -150], ["east", 150, 0], ["west", -150, 0]]:
		_set_camera(spot.x + float(view[1]), spot.y + float(view[2]), 0.0, -0.05)
		if game.fp_world.has_method("face_neighbours"): game.fp_world.face_neighbours()
		print("FACE %s %s" % [view[0], str(target.get_meta("path", ""))])

func _grab() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return get_root().get_texture().get_image()

func _changed(a: Image, b: Image) -> int:
	var n := 0
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			if absf(p.r - q.r) > 0.012 or absf(p.g - q.g) > 0.012 or absf(p.b - q.b) > 0.012: n += 1
	return n

func _render() -> void:
	_set_camera(300.0, 70.0, 0.0, -0.05)
	if game.fp_world.has_method("face_neighbours"): game.fp_world.face_neighbours()
	var shown := await _grab()
	var again := await _grab()
	print("NOISE %d" % _changed(shown, again))
	for pair in _entities():
		if int(pair[0]) != 407 or not pair[1].get_meta("actor", false): continue
		var node: Node3D = pair[1]
		var at := _map_xy(407, node)
		node.visible = false
		var hidden := await _grab()
		node.visible = true
		print("PIG %d %d %d" % [at.x, at.y, _changed(shown, hidden)])
