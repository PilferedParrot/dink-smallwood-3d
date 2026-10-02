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
#
# M3 (October 2, Sonnet 5.5 subagent): the gatehouse (castl-05 on 80) and the corner (castl-12 on 16 and 48) are blocks, a
# wall is one solid with a true far side and a parapet strip with thickness. The same two parts, and in --render:
#                 "CASTLE merlon path <depth> <pt> <offset> <wall depth>": seen from above with only the parapet's alpha-cut
#                 surfaces drawn, the mean depth in source px that the merlons cover across the wall, the fit's pt, where
#                 the strip's middle lies behind the wall's near face, and the wall's depth (a zero-thickness card of
#                 merlons covers nothing from above);
#                 "CASTLE far path <triangles> <opaque>": the far face (two triangles) is drawn from the sibling sprite's
#                 picture, its texture coordinates on drawn brick, not the point mirror of the front; "far-wrong" the
#                 same with the far side point-mirrored again (the control: 0 triangles carry the sibling's picture);
#                 "CASTLE merlon-wrong": the merlon coverage with the parapet's thickness taken away (the control);
#                 "CASTLE gate <south> <east> <west> <perspective east/south>": the gatehouse's silhouette width from
#                 three sides at eye level (orthographic, then the game's perspective): a card is a sliver from the side.
# Verdict: written 2026-10-01 (Sonnet 5.5 subagent); extended 2026-10-02.
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
	[80, 505, 241, "assets/graphics/struct/Castle/castl-05.png"],
	[16, 408, 453, "assets/graphics/struct/Castle/castl-12.png"],
	[48, 408, 53, "assets/graphics/struct/Castle/castl-12.png"],
]

func _tag(spec: Array) -> String:
	return "%s@%d" % [spec[3], spec[0]]

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
	if entry.is_empty():
		_fail("%s has no fit: it is a card" % _tag(spec))
		return [-1.0, -1.0]
	var saved: Array = []
	if spoil:
		for q in entry.parts:
			saved.append(q.duplicate(true))
			if str(q.type) == "wall": q.c = float(q.c) + 8.0
			elif str(q.type) == "block":
				# the plan moved 8 px down the screen (the walls' control: a base line 8 px off)
				for p in q.poly: p[1] = float(p[1]) + 8.0
				if q.get("poly_ov") != null:
					for p in q.poly_ov: p[1] = float(p[1]) + 8.0
				for cap in q.get("caps", []):
					for p in cap.poly: p[1] = float(p[1]) + 8.0
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
		var tag := "%s-%d%s" % [str(spec[3]).get_file().get_basename(), int(spec[0]), "-wrong" if spoil else ""]
		with.save_png(dump_dir.path_join(tag + "-with.png"))
		without.save_png(dump_dir.path_join(tag + "-without.png"))
	if spoil:
		for i in entry.parts.size(): entry.parts[i] = saved[i]
		fw.buildings.castle_cache.clear()
	return out

func _thickness(spec: Array) -> Array:
	var fw = game.fp_world
	var entry: Dictionary = fw.buildings.castle_fit(str(spec[3]))
	if entry.is_empty(): return []
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
		print("CASTLE err %s %.3f %.4f" % [_tag(spec), err[0], err[1]])
		print("CASTLE err-wrong %s %.3f %.4f" % [_tag(spec), wrong[0], wrong[1]])
		var t := await _thickness(spec)
		if not t.is_empty(): print("CASTLE thickness %s %.2f %.2f" % [_tag(spec), t[0], t[1]])
		var m := await _merlons(spec)
		if not m.is_empty():
			print("CASTLE merlon %s %.3f %.2f %.2f %.2f" % [_tag(spec), m[0], m[1], m[2], m[3]])
			var mw := await _merlons(spec, true)
			print("CASTLE merlon-wrong %s %.3f" % [_tag(spec), mw[0]])
		var far := await _far_side(spec)
		if not far.is_empty():
			print("CASTLE far %s %d %.3f" % [_tag(spec), far[0], far[1]])
			var fm := await _far_side(spec, true)
			print("CASTLE far-wrong %s %d %.3f" % [_tag(spec), fm[0], fm[1]])
	await _gate()


# The parapet seen from above: only the alpha-cut surfaces (the strips of merlons) drawn, over the wall's span. Returns
# [the mean depth the merlons cover across the wall (source px), the fit's pt, the strip's middle behind the wall's near
# face (source px), the wall's depth]. A strip with no thickness covers nothing seen from above.
func _is_cut(mi: MeshInstance3D) -> bool:
	var m := mi.get_surface_override_material(0)
	return m is StandardMaterial3D and (m as StandardMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR

func _merlons(spec: Array, spoil := false) -> Array:
	var fw = game.fp_world
	var entry: Dictionary = fw.buildings.castle_fit(str(spec[3]))
	if entry.is_empty(): return []
	var q: Dictionary = entry.parts[0]
	if entry.parts.size() != 1 or str(q.type) != "wall" or str(q.parapet) == "none": return []
	var saved := q.duplicate(true)
	if spoil:
		# The control: the parapet strip with no thickness, as the ninth pass built it.
		q.pt = 0.0
		q.depth = float(q.tv)
		fw.buildings.castle_cache.clear()
	await _load(int(spec[0]))
	game.set_physics_process(false)
	game.set_process(false)
	fw.light.shadow_enabled = false
	var id := _entity_of(spec)
	_hide_all_but(id)
	var ent: Dictionary = game.entities[id]
	var d: Dictionary = game._frame(int(ent.get("pseq", ent.get("seq", 0))), int(ent.get("pframe", ent.get("frame", 1))))
	var origin := Vector2(int(spec[1]) - int(d.dx), int(spec[2]) - int(d.dy))
	var clip: Dictionary = fw.castle_clips(ent, int(spec[0]))
	var lo := float(q.x0)
	var hi := float(q.x1)
	if clip.has(0):
		lo = float(clip[0][0])
		hi = float(clip[0][1])
	var xm := (lo + hi) / 2.0
	var depth := float(q.get("depth", q.tv))
	var mid := Vector2(origin.x + xm, origin.y + float(q.s) * xm + float(q.c) - depth / 2.0)
	var at: Vector3 = fw.point(mid.x, mid.y)
	var node: Node3D = game.visuals[id]
	node.visible = true
	var model := node.get_node("Model")
	var kept: Array = []
	for child in model.get_children():
		if child is MeshInstance3D and not _is_cut(child): kept.append(child)
	for child in kept: child.visible = false
	var with := await _top_camera(at)
	node.visible = false
	var without := await _top_camera(at)
	for child in kept: child.visible = true
	if spoil:
		for k in saved.keys(): q[k] = saved[k]
		fw.buildings.castle_cache.clear()
	var scale := with.get_width() / 600.0
	var area := 0
	var sum_off := 0.0
	for y in with.get_height():
		for x in with.get_width():
			var a := with.get_pixel(x, y)
			var b := without.get_pixel(x, y)
			if maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b)) * 255.0 <= 1.5: continue
			var sx := mid.x + (x + 0.5 - with.get_width() / 2.0) / scale
			var sz := mid.y + (y + 0.5 - with.get_height() / 2.0) / scale
			if sx < origin.x + lo or sx > origin.x + hi: continue
			area += 1
			sum_off += origin.y + float(q.s) * (sx - origin.x) + float(q.c) - sz
	if area == 0: return [0.0, float(q.get("pt", 0.0)), 0.0, depth]
	return [float(area) / (scale * scale) / (hi - lo), float(q.get("pt", 0.0)), sum_off / float(area), depth]

# The far face is drawn from the sibling sprite's picture (castl-06/08 draw a wall's inner face, 07/09 its outer one, so the
# face the sprite never shows is the sibling's), not the point mirror of the front. Looked up in the built mesh, not in the
# fit: among the surfaces that carry the sibling's brick picture, the triangles lying on the far face (the wall's far offset
# from its near face, on the ground and up to the walkway); returns [their number (2 for the quad), the fraction whose
# texture coordinate lands on an opaque pixel of the sibling's picture].
func _far_side(spec: Array, mirrored := false) -> Array:
	var fw = game.fp_world
	var entry: Dictionary = fw.buildings.castle_fit(str(spec[3]))
	if entry.is_empty(): return []
	var q: Dictionary = entry.parts[0]
	if entry.parts.size() != 1 or str(q.type) != "wall" or str(q.parapet) == "none": return []
	var saved := q.duplicate(true)
	if mirrored:
		q["mirror_far"] = true # the control: the far side point-mirrored again
		fw.buildings.castle_cache.clear()
	await _load(int(spec[0]))
	var id := _entity_of(spec)
	var model := (game.visuals[id] as Node3D).get_node("Model")
	var sibling := str(q.far.path) if q.has("far") else ""
	var depth := float(q.get("depth", q.tv))
	var s := float(q.s)
	var c := float(q.c)
	var tris := 0
	var opaque := 0
	if sibling != "":
		var pic = fw.buildings.castle_raw(sibling)
		var img: Image = fw.buildings.image(sibling)
		for child in model.get_children():
			if not child is MeshInstance3D: continue
			var m := (child as MeshInstance3D).get_surface_override_material(0)
			if not (m is StandardMaterial3D and (m as StandardMaterial3D).albedo_texture == pic): continue
			var arrays := (child as MeshInstance3D).mesh.surface_get_arrays(0)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			for t in range(0, verts.size(), 3):
				var on_far := true
				for k in 3:
					var v: Vector3 = verts[t + k] / float(fw.buildings.S)
					on_far = on_far and absf(s * v.x + c - v.z - depth) < 0.05
				if not on_far: continue
				tris += 1
				var uv := (uvs[t] + uvs[t + 1] + uvs[t + 2]) / 3.0
				var px := Vector2i(int(uv.x * img.get_width()), int(uv.y * img.get_height()))
				if px.x >= 0 and px.y >= 0 and px.x < img.get_width() and px.y < img.get_height() and img.get_pixelv(px).a >= 0.5: opaque += 1
	if mirrored:
		for k in saved.keys(): q[k] = saved[k]
		q.erase("mirror_far")
		fw.buildings.castle_cache.clear()
	return [tris, float(opaque) / maxf(tris, 1)]

# The gatehouse at eye level from the south, the east and the west: the width of its silhouette in px (orthographic: the
# plan's extent; then the game's own perspective from the same distance). A fixed card is a sliver from the side.
func _gate_view(at: Vector3, from: Vector3, ortho: bool) -> float:
	var cam: Camera3D = game.camera
	var eye := at + Vector3(0, 1.65, 0)
	if ortho:
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.keep_aspect = Camera3D.KEEP_WIDTH
		cam.size = 14.0
		cam.near = 0.05
		cam.far = 200.0
		cam.look_at_from_position(eye + from * 40.0, eye, Vector3.UP)
	else:
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
		cam.fov = 80.0
		cam.near = 0.05
		cam.far = 200.0
		cam.look_at_from_position(Vector3(eye.x, 1.65, eye.z) + from * 12.0, eye, Vector3.UP)
	if game.fp_world.environment: game.fp_world.environment.fog_enabled = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return 0.0

func _columns(a: Image, b: Image) -> int:
	var n := 0
	for x in a.get_width():
		for y in a.get_height():
			var p := a.get_pixel(x, y)
			var r := b.get_pixel(x, y)
			if maxf(maxf(absf(p.r - r.r), absf(p.g - r.g)), absf(p.b - r.b)) * 255.0 > 1.5:
				n += 1
				break
	return n

func _gate() -> void:
	var fw = game.fp_world
	var spec: Array = TARGETS[8]
	await _load(int(spec[0]))
	game.set_physics_process(false)
	game.set_process(false)
	fw.light.shadow_enabled = false
	var id := _entity_of(spec)
	if id < 0:
		_fail("no fitted gatehouse")
		return
	_hide_all_but(id)
	var node: Node3D = game.visuals[id]
	node.visible = true
	var model := node.get_node("Model")
	var box := AABB()
	var first := true
	for child in model.get_children():
		if not child is MeshInstance3D: continue
		var bb: AABB = (child as MeshInstance3D).global_transform * (child as MeshInstance3D).get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	if first: box = AABB(node.global_position, Vector3.ZERO) # a card: a sprite, no mesh to measure
	var centre := box.get_center()
	centre.y = 0.0
	var results := {}
	for ortho in [true, false]:
		for side in [["south", Vector3(0, 0, 1)], ["east", Vector3(1, 0, 0)], ["west", Vector3(-1, 0, 0)]]:
			node.visible = true
			await _gate_view(centre, side[1], ortho)
			var with := root.get_texture().get_image()
			node.visible = false
			await _gate_view(centre, side[1], ortho)
			var without := root.get_texture().get_image()
			results["%s%s" % ["o" if ortho else "p", side[0]]] = _columns(with, without)
	print("CASTLE gate %d %d %d %d %d %d" % [results.osouth, results.oeast, results.owest, results.psouth, results.peast, results.pwest])
