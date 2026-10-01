extends SceneTree
# The castle's walls and towers stand in 3D (docs/DIRECTION.md, tenth pass, castle). A castle sprite fitted by
# tools/facade_fit.py castle_fit (prototype/facades.json "_walls") is a prism of wall or a round tower built
# from the sprite's own pixels (scripts/sprite_buildings.gd castle); it was a fixed card facing south, a tall
# sliver seen from the side. Two parts, run by tests/test_fps_castle.py:
#
#   --classify    (headless) load every screen with castle sprites as the game loads it, and print one line per
#                 castle sprite of the screen: "CASTLE screen path fitted|card|dup x y". A piece placed twice at
#                 one spot is built once (the second is "dup").
#   --render      (rendered, under xvfb, Dummy audio) for one piece of each fitted frame, alone in its scene:
#                 "CASTLE err path <colour> <xor>": through the original camera the mean |RGB| difference over the
#                 sprite's own pixels, and the fraction of the sprite's pixels where the piece and the sprite do not
#                 agree on covered or empty (a projected picture is the sprite's whatever the depth of the face it is
#                 on, so only the silhouette can tell a wrong geometry); "CASTLE err-wrong ..." the same with the
#                 geometry spoiled (a wall's base line moved 8 px down, a tower's centre 10 px sideways: the
#                 control, which must read worse); and for the walls
#                 "CASTLE thickness path <px> <tv>": seen from above (the shadows off) the piece covers this many
#                 source px across its depth, where the fit says the walkway is tv deep (a card has none).
# Verdict: written 2026-10-01 (Sonnet 5.5 subagent).
const GAME = preload("res://scripts/fps_game.gd")
const SCALE := 0.025

# [screen, x, y, sprite path] of one placement of each fitted frame.
const TARGETS := [
	[368, 224, 305, "assets/graphics/struct/Castle/castl-06.png"],
	[402, 106, 101, "assets/graphics/struct/Castle/castl-07.png"],
	[369, 399, 181, "assets/graphics/struct/Castle/castl-08.png"],
	[400, 574, 334, "assets/graphics/struct/Castle/castl-09.png"],
	[401, 220, 426, "assets/graphics/struct/Castle/castl-04.png"],
	[402, 395, 51, "assets/graphics/struct/Castle/castl-03.png"],
	[367, 505, 456, "assets/graphics/struct/Castle/castl-01.png"],
	[369, 71, 95, "assets/graphics/struct/Castle/castl-02.png"],
]

var game
var failures: Array[String] = []
var dump_dir := "" # --dump-dir=DIR: save each piece's two original-camera renders (for looking at)

func _initialize() -> void:
	_run.call_deferred()

func _fail(message: String) -> void:
	failures.append(message)
	print("FAIL ", message)

func _run() -> void:
	var classify := false
	var render := false
	for arg in OS.get_cmdline_user_args():
		if arg == "--classify": classify = true
		if arg == "--render": render = true
		if arg.begins_with("--dump-dir="): dump_dir = arg.trim_prefix("--dump-dir=")
	game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	await game._new_game()
	await create_timer(1.0).timeout
	if classify: await _classify()
	if render: await _render()
	if failures.is_empty():
		print("FPS CASTLE PASS")
		quit(0)
	else:
		print("FPS CASTLE FAIL ", failures.size())
		quit(1)

func _load(screen: int) -> void:
	game.vm.cancel_all()
	game.vm.globals["vision"] = 0
	game.load_map(screen, false)
	await create_timer(0.6).timeout
	game.vm.cancel_all()
	game.playing = false
	game.ui.close_menu()
	game.ui.toast.text = ""

func _castle_entities() -> Array:
	var out: Array = []
	for id in game.entities.keys():
		if id == 1: continue
		var e: Dictionary = game.entities[id]
		if "/castle/" in game.fp_world.source_path(e): out.append(id)
	return out

func _classify() -> void:
	var screens: Array = []
	for number in game.world.screens:
		if game.fp_world.is_inside(int(number)): continue
		for source in game.world.screens[number].get("sprites", []):
			var seq := int(source.get("seq", 0))
			var frame := int(source.get("frame", 1))
			if "/castle/" in str(game._frame(seq, frame).get("path", "")).to_lower():
				screens.append(int(number))
				break
	screens.sort()
	for n in screens:
		await _load(n)
		for id in _castle_entities():
			var e: Dictionary = game.entities[id]
			var node: Node3D = game.visuals[id]
			var model := node.get_node_or_null("Model")
			var kind := "dup"
			if model is Sprite3D: kind = "card"
			elif model is Node3D: kind = "fitted"
			print("CASTLE %d %s %s %d %d" % [n, game.fp_world.frame_path(e), kind, int(e.get("x", 0)), int(e.get("y", 0))])

# --- pixels -----------------------------------------------------------------------------------------------
func _hide_all_but(keep: int) -> void:
	for id in game.visuals.keys():
		if id == keep: continue
		var node = game.visuals[id]
		if is_instance_valid(node): node.visible = false
	for child in game.scene_root.get_children():
		if str(child.name).begins_with("Neighbor_"): child.visible = false
	for model in [game.fps_viewmodel, game.fps_hand]:
		if is_instance_valid(model): model.visible = false

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

# From straight above, centred on scene point `at`, south at the bottom: px per source px = width / 600.
func _top_camera(at: Vector3) -> Image:
	var cam: Camera3D = game.camera
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.size = 600.0 * SCALE
	cam.near = 0.05
	cam.far = 200.0
	cam.look_at_from_position(at + Vector3(0, 40, 0), at, Vector3(0, 0, -1))
	if game.fp_world.environment: game.fp_world.environment.fog_enabled = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _entity_of(spec: Array) -> int:
	for id in _castle_entities():
		var e: Dictionary = game.entities[id]
		if int(e.get("x", 0)) == int(spec[1]) and int(e.get("y", 0)) == int(spec[2]) and game.fp_world.frame_path(e) == str(spec[3]):
			var model := (game.visuals[id] as Node3D).get_node_or_null("Model")
			if model != null: return id
	return -1

# Against the sprite's own opaque pixels (the shadow dither left out), the sprite placed as the original places it
# on the screen (the 600 px view starts 20 px in): [mean |RGB| difference over those pixels, the fraction of the
# sprite's pixel count by which the piece's coverage (`with` differs from `without`) and the sprite's disagree].
func _compare(with: Image, without: Image, spec: Array) -> Array:
	var fw = game.fp_world
	var id := _entity_of(spec)
	var e: Dictionary = game.entities[id]
	var sprite: Image = fw.buildings.image(str(spec[3]))
	var dither: PackedByteArray = fw.buildings.dither_mask(sprite)
	var d: Dictionary = game._frame(int(e.get("pseq", e.get("seq", 0))), int(e.get("pframe", e.get("frame", 1))))
	var ox := int(spec[1]) - int(d.dx) - 20
	var oy := int(spec[2]) - int(d.dy)
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
			var b := without.get_pixel(px, py)
			var covered := maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b)) * 255.0 > 1.5
			if opaque:
				var c := sprite.get_pixel(sx, sy)
				total += (absf(a.r - c.r) + absf(a.g - c.g) + absf(a.b - c.b)) / 3.0 * 255.0
				count += 1
			if opaque != covered: xor += 1
	return [total / maxf(count, 1), float(xor) / maxf(count, 1)]

func _shot(spec: Array, spoil: bool) -> Array:
	var fw = game.fp_world
	var entry: Dictionary = fw.buildings.castle_fit(str(spec[3]))
	var saved: Array = []
	if spoil:
		for q in entry.parts:
			saved.append(q.duplicate())
			if str(q.type) == "wall": q.c = float(q.c) + 8.0
			else: q.cx = float(q.cx) + 10.0
		fw.buildings.castle_cache.clear()
	await _load(int(spec[0]))
	game.set_physics_process(false)
	game.set_process(false)
	fw.light.shadow_enabled = false
	var id := _entity_of(spec)
	if id < 0:
		_fail("no fitted piece %s at %d,%d on %d" % [spec[3], spec[1], spec[2], spec[0]])
		return [-1.0, -1.0]
	_hide_all_but(id)
	var node: Node3D = game.visuals[id]
	node.visible = true
	var with := await _original_camera()
	node.visible = false
	var without := await _original_camera()
	var out := _compare(with, without, spec)
	if dump_dir != "":
		var tag := "%s%s" % [str(spec[3]).get_file().get_basename(), "-wrong" if spoil else ""]
		with.save_png(dump_dir.path_join(tag + "-with.png"))
		without.save_png(dump_dir.path_join(tag + "-without.png"))
	if spoil:
		for i in entry.parts.size(): entry.parts[i] = saved[i]
		fw.buildings.castle_cache.clear()
	return out

func _thickness(spec: Array) -> Array:
	var fw = game.fp_world
	var entry: Dictionary = fw.buildings.castle_fit(str(spec[3]))
	var q: Dictionary = entry.parts[0]
	if entry.parts.size() != 1 or str(q.type) != "wall": return []
	await _load(int(spec[0]))
	game.set_physics_process(false)
	game.set_process(false)
	fw.light.shadow_enabled = false
	var id := _entity_of(spec)
	_hide_all_but(id)
	var ent: Dictionary = game.entities[id]
	var d: Dictionary = game._frame(int(ent.get("pseq", ent.get("seq", 0))), int(ent.get("pframe", ent.get("frame", 1))))
	var xm := (float(q.x0) + float(q.x1)) / 2.0
	var mid := Vector2(int(spec[1]) - int(d.dx) + xm, int(spec[2]) - int(d.dy) + float(q.s) * xm + float(q.c) - float(q.tv) / 2.0)
	var at: Vector3 = fw.point(mid.x, mid.y)
	var node: Node3D = game.visuals[id]
	node.visible = true
	var with := await _top_camera(at)
	node.visible = false
	var without := await _top_camera(at)
	var column := with.get_width() / 2
	var scale := with.get_width() / 600.0
	var covered := 0
	for y in with.get_height():
		var a := with.get_pixel(column, y)
		var b := without.get_pixel(column, y)
		if maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b)) * 255.0 > 1.5: covered += 1
	return [float(covered) / scale, float(q.tv)]

func _render() -> void:
	for spec in TARGETS:
		var err := await _shot(spec, false)
		var wrong := await _shot(spec, true)
		print("CASTLE err %s %.3f %.4f" % [spec[3], err[0], err[1]])
		print("CASTLE err-wrong %s %.3f %.4f" % [spec[3], wrong[0], wrong[1]])
		var t := await _thickness(spec)
		if not t.is_empty(): print("CASTLE thickness %s %.2f %.2f" % [spec[3], t[0], t[1]])
