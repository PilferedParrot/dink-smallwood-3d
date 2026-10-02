extends SceneTree
# The island's round huts stand in 3D (docs/DIRECTION.md, M3, huts). A hut sprite (struct/Island isle-01..06) fitted
# by tools/hut_fit.py (prototype/facades.json "_huts") is a solid of revolution built from the sprite's own pixels
# (scripts/sprite_buildings.gd hut); it was a fixed card facing south, a sliver seen from the side. Two parts, run by
# tests/test_fps_huts.py:
#
#   --classify    (headless) load every screen with island sprites as the game loads it and print one line per island
#                 sprite: "HUT screen path fitted|card x y" (isle-01..06 must be fitted, the rail fences isle-07..12,
#                 the spears 13..18 and the rest of the folder stay as they were).
#   --render      (rendered, under xvfb, Dummy audio) for each of the six huts, placed alone by the game's own
#                 make_entity on a quiet screen: "HUT err path <colour> <xor>": through the original camera the mean
#                 |RGB| difference over the sprite's opaque pixels (shadow dither left out) and the fraction of the
#                 sprite's pixel count by which the piece's coverage and the sprite's disagree (a projected picture is the
#                 sprite's whatever the depth of the surface it is on, so only the silhouette can tell a wrong geometry);
#                 "HUT err-axis ...", "HUT err-wide ..." and "HUT err-round ..." the same with the axis moved 10 px
#                 sideways, with every radius 10% wide and with a circle on the ground where the art draws the ellipse of
#                 aspect 0.4878 (the controls, which must read worse); and "HUT side path <south px> <east px>": the
#                 piece's width as an orthographic eye-level camera sees it from the south and from the east (a card
#                 is a sliver from the east).
#   --card        (rendered) the same "HUT err" measurement with the fits switched off, so each hut is the fixed card it
#                 was: "HUT card path <colour> <xor>" (the before; not an instrument floor: the card is cut at its hotspot
#                 by the depth rule, and a bottom third of the sprite is missing through the original camera).
# Verdict: written 2026-10-02 (Sonnet 5.5 subagent).
const GAME = preload("res://scripts/fps_game.gd")
const SCALE := 0.025
const SCREEN := 764
const SPOT := Vector2(300, 260) # where each hut is placed (the entity's hotspot, screen px)
const FRAMES := [1, 2, 3, 4, 5, 6]
const ISLAND_SEQ := 424

var game
var failures: Array[String] = []
var dump_dir := ""

func _initialize() -> void:
	_run.call_deferred()

func _fail(message: String) -> void:
	failures.append(message)
	print("FAIL ", message)

func _run() -> void:
	var classify := false
	var render := false
	var card := false
	for arg in OS.get_cmdline_user_args():
		if arg == "--classify": classify = true
		if arg == "--render": render = true
		if arg == "--card": card = true
		if arg.begins_with("--dump-dir="): dump_dir = arg.trim_prefix("--dump-dir=")
	game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	await game._new_game()
	await create_timer(1.0).timeout
	if classify: await _classify()
	if render: await _render()
	if card: await _render_cards()
	if failures.is_empty():
		print("FPS HUTS PASS")
		quit(0)
	else:
		print("FPS HUTS FAIL ", failures.size())
		quit(1)

func _load(screen: int, vision: int = 0) -> void:
	game.vm.cancel_all()
	game.vm.globals["vision"] = vision
	game.load_map(screen, false)
	await create_timer(0.6).timeout
	game.vm.cancel_all()
	game.playing = false
	game.ui.close_menu()
	game.ui.toast.text = ""

func _island_entities() -> Array:
	var out: Array = []
	for id in game.entities.keys():
		if id == 1: continue
		if "/island/" in game.fp_world.source_path(game.entities[id]): out.append(id)
	return out

func _classify() -> void:
	var screens: Array = []
	var story_screens: Array = [] # screens whose island sprites belong to a story layer (vision 1: 489's hut)
	for number in game.world.screens:
		if game.fp_world.is_inside(int(number)): continue
		for source in game.world.screens[number].get("sprites", []):
			var seq := int(source.get("seq", 0))
			var frame := int(source.get("frame", 1))
			if "/island/" in str(game._frame(seq, frame).get("path", "")).to_lower():
				if int(source.get("vision", 0)) == 0 and not screens.has(int(number)): screens.append(int(number))
				elif int(source.get("vision", 0)) != 0 and not story_screens.has(int(number)): story_screens.append(int(number))
				break
	screens.sort()
	story_screens.sort()
	for n in screens:
		await _load(n)
		_print_island(n)
	for n in story_screens:
		await _load(n, 1)
		_print_island(n)

func _print_island(n: int) -> void:
	for id in _island_entities():
		var e: Dictionary = game.entities[id]
		var node: Node3D = game.visuals[id]
		var model := node.get_node_or_null("Model")
		var kind := "none"
		if model is Sprite3D: kind = "card"
		elif model is Node3D: kind = "fitted"
		print("HUT %d %s %s %d %d" % [n, game.fp_world.frame_path(e), kind, int(e.get("x", 0)), int(e.get("y", 0))])

# --- pixels -----------------------------------------------------------------------------------------------
# Everything but the terrain and `keep` is hidden: the neighbours' trees (the south neighbour's stand over the lower right
# and left of the spot, and hid the two-storey huts' feet, which the first run took for a fault of the fits) included.
func _hide_all_but(keep: Node3D) -> void:
	for id in game.visuals.keys():
		var node = game.visuals[id]
		if is_instance_valid(node) and node != keep: node.visible = false
	for child in game.scene_root.get_children():
		if child == keep or child is MeshInstance3D: continue
		if child is Node3D: child.visible = false
	for model in [game.fps_viewmodel, game.fps_hand]:
		if is_instance_valid(model): model.visible = false

func _entity(frame: int) -> Dictionary:
	return {"seq": ISLAND_SEQ, "frame": frame, "x": int(SPOT.x), "y": int(SPOT.y), "size": 100, "type": 1, "vision": 0}

func _original_camera() -> Image:
	var cam: Camera3D = game.camera
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.size = 600.0 * SCALE
	cam.near = 0.05
	cam.far = 200.0
	cam.position = Vector3(0, 1, 1).normalized() * 40.0
	cam.look_at(Vector3.ZERO, Vector3.UP)
	if game.fp_world.environment: game.fp_world.environment.fog_enabled = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var rows := int(round(img.get_width() * (400.0 / sqrt(2.0)) / 600.0))
	img = img.get_region(Rect2i(0, (img.get_height() - rows) / 2, img.get_width(), rows))
	img.resize(600, 400, Image.INTERPOLATE_LANCZOS)
	return img

# An orthographic eye-level camera, `from` the direction (unit, horizontal) it stands in, looking at scene point `at`.
func _side_camera(at: Vector3, from: Vector3) -> Image:
	var cam: Camera3D = game.camera
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.size = 12.0
	cam.near = 0.05
	cam.far = 200.0
	cam.look_at_from_position(at + from * 30.0 + Vector3(0, 1.5, 0), at + Vector3(0, 1.5, 0), Vector3.UP)
	if game.fp_world.environment: game.fp_world.environment.fog_enabled = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _differs(a: Color, b: Color) -> bool:
	return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b)) * 255.0 > 1.5

# Against the sprite's own opaque pixels (shadow dither left out), the sprite placed as the original places it on the
# screen (the 600 px view starts 20 px in): [mean |RGB| over those pixels, the fraction of their count by which the
# piece's coverage and the sprite's disagree].
func _compare(with: Image, without: Image, path: String, d: Dictionary) -> Array:
	var sprite: Image = game.fp_world.buildings.image(path)
	var dither: PackedByteArray = game.fp_world.buildings.dither_mask(sprite)
	var ox := int(SPOT.x) - int(d.dx) - 20
	var oy := int(SPOT.y) - int(d.dy)
	var total := 0.0
	var count := 0
	var xor := 0
	for py in 400:
		for px in 600:
			var sx := px - ox
			var sy := py - oy
			var opaque := false
			if sx >= 0 and sy >= 0 and sx < sprite.get_width() and sy < sprite.get_height():
				opaque = sprite.get_pixel(sx, sy).a >= 0.5 and dither[sy * sprite.get_width() + sx] == 0
			var a := with.get_pixel(px, py)
			var covered := _differs(a, without.get_pixel(px, py))
			if opaque:
				var c := sprite.get_pixel(sx, sy)
				total += (absf(a.r - c.r) + absf(a.g - c.g) + absf(a.b - c.b)) / 3.0 * 255.0
				count += 1
			if opaque != covered: xor += 1
	return [total / maxf(count, 1), float(xor) / maxf(count, 1)]

func _place(frame: int) -> Node3D:
	var node: Node3D = game.fp_world.make_entity(_entity(frame), 0, game.scene_root, false, SCREEN)
	node.position = game.fp_world.point(SPOT.x, SPOT.y)
	return node

func _spoil(path: String, how: String) -> Array:
	var fit: Dictionary = game.fp_world.buildings.hut_fit(path)
	var saved: Array = [float(fit.cx), [], float(fit.k)]
	for n in fit.nodes: (saved[1] as Array).append(float(n[1]))
	if how == "axis": fit.cx = float(fit.cx) + 10.0
	elif how == "round": fit.k = 1.0 # a circle on the ground where the art draws the ellipse of aspect 0.4878
	else:
		for n in fit.nodes: n[1] = float(n[1]) * 1.1
	game.fp_world.buildings.hut_cache.clear()
	return saved

func _restore(path: String, saved: Array) -> void:
	var fit: Dictionary = game.fp_world.buildings.hut_fit(path)
	fit.cx = saved[0]
	fit.k = saved[2]
	for i in fit.nodes.size(): fit.nodes[i][1] = (saved[1] as Array)[i]
	game.fp_world.buildings.hut_cache.clear()

func _shot(frame: int, how: String) -> Array:
	var fw = game.fp_world
	var path := "assets/graphics/struct/Island/isle-%02d.png" % frame
	var saved: Array = []
	if how != "":
		if fw.buildings.hut_fit(path).is_empty():
			_fail("no fit for %s" % path)
			return [-1.0, -1.0]
		saved = _spoil(path, how)
	await _load(SCREEN)
	game.set_physics_process(false)
	game.set_process(false)
	fw.light.shadow_enabled = false
	var node := _place(frame)
	var model := node.get_node_or_null("Model")
	if model == null or model is Sprite3D:
		_fail("%s is not a fitted 3D hut (model %s)" % [path, str(model)])
		return [-1.0, -1.0]
	_hide_all_but(node)
	node.visible = true
	var with := await _original_camera()
	node.visible = false
	var without := await _original_camera()
	var d: Dictionary = game._frame(ISLAND_SEQ, frame)
	var out := _compare(with, without, path, d)
	if dump_dir != "":
		var tag := "isle-%02d%s" % [frame, ("-" + how) if how != "" else ""]
		with.save_png(dump_dir.path_join(tag + "-with.png"))
		without.save_png(dump_dir.path_join(tag + "-without.png"))
	node.queue_free()
	if how != "": _restore(path, saved)
	return out

# The piece's width, px, in an orthographic side camera of 12 m across: from the south and from the east.
func _side(frame: int) -> Array:
	var fw = game.fp_world
	await _load(SCREEN)
	game.set_physics_process(false)
	game.set_process(false)
	fw.light.shadow_enabled = false
	var node := _place(frame)
	_hide_all_but(node)
	var at: Vector3 = node.position
	var widths: Array = []
	for from in [Vector3(0, 0, 1), Vector3(1, 0, 0)]:
		node.visible = true
		var with := await _side_camera(at, from)
		node.visible = false
		var without := await _side_camera(at, from)
		var lo := 1 << 30
		var hi := -1
		for y in range(0, with.get_height(), 2):
			for x in with.get_width():
				if _differs(with.get_pixel(x, y), without.get_pixel(x, y)):
					lo = mini(lo, x)
					hi = maxi(hi, x)
		widths.append(hi - lo + 1 if hi >= 0 else 0)
	node.queue_free()
	return widths

# The before: the fits switched off, each hut the fixed card it was.
func _render_cards() -> void:
	var fw = game.fp_world
	var saved: Variant = fw.buildings.facades.get("_huts", {})
	fw.buildings.facades["_huts"] = {}
	for frame in FRAMES:
		var path := "assets/graphics/struct/Island/isle-%02d.png" % frame
		await _load(SCREEN)
		game.set_physics_process(false)
		game.set_process(false)
		fw.light.shadow_enabled = false
		var node := _place(frame)
		if not node.get_node("Model") is Sprite3D: _fail("%s is not a card with the fits off" % path)
		_hide_all_but(node)
		node.visible = true
		var with := await _original_camera()
		node.visible = false
		var without := await _original_camera()
		var out := _compare(with, without, path, game._frame(ISLAND_SEQ, frame))
		print("HUT card %s %.3f %.4f" % [path, out[0], out[1]])
		if dump_dir != "":
			with.save_png(dump_dir.path_join("card-%02d-with.png" % frame))
			without.save_png(dump_dir.path_join("card-%02d-without.png" % frame))
		node.queue_free()
	fw.buildings.facades["_huts"] = saved

func _render() -> void:
	for frame in FRAMES:
		var path := "assets/graphics/struct/Island/isle-%02d.png" % frame
		var err := await _shot(frame, "")
		print("HUT err %s %.3f %.4f" % [path, err[0], err[1]])
		for how in ["axis", "wide", "round"]:
			var wrong := await _shot(frame, how)
			print("HUT err-%s %s %.3f %.4f" % [how, path, wrong[0], wrong[1]])
		var w := await _side(frame)
		print("HUT side %s %d %d" % [path, w[0], w[1]])
