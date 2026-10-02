extends SceneTree
# Upright sprites are billboards, structures are fixed cards (docs/DIRECTION.md, tenth pass). A card keeps the
# orientation it was drawn in only if it is a structure (fence, wall, castle wall, sign, hut); a tree, bush,
# rock, well, statue, prop or actor is a Y-axis billboard whatever its width (the art's width includes its
# shadow dither: every tree is over 100 px, and every tree was an edge-on sliver from the side). A billboard
# casts its silhouette from a shadow-only twin turned to the sun. Three parts, run by tests/test_fps_cards.py:
#
#   --classify         (headless) build every sprite of every outdoor screen (the map's whole editor layer, both
#                      story layers) the way a scene builds it, and print one line per card the game draws:
#                      "CARD screen x y key fixed|billboard path". The pytest compares each with an independent
#                      reading of the art's path.
#   --dump=n,n,...     (headless) the same lines for the cards of scenes loaded as the game loads them, with the
#                      shadow twin's state: "CARD ... twin=<none|yaw_error_deg>".
#   --render           (rendered, under xvfb, Dummy audio) the pixel checks: a tree-04 seen from the east or west is
#                      as wide as seen from the south; every tree still casts a shadow on the ground.
# Verdict: written 2026-10-01 (Sonnet 5.5 subagent); classify 1 min, render under 1 min under xvfb.
const GAME = preload("res://scripts/fps_game.gd")
const EPS := 3 # max channel difference counted as a changed pixel (0..255)

# The target of the pixel checks: tree-04 (249 px wide), alone on its screen (nothing within a house's reach).
# screen, x, y of the tree; the camera stands CAM px away (source px), eye height as the game's.
const TREE := [342, 419, 169]
const CAM := 330.0

var game
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _fail(message: String) -> void:
	failures.append(message)
	print("FAIL ", message)

func _run() -> void:
	var classify := false
	var render := false
	var dump: Array = []
	var out_dir := ""
	for arg in OS.get_cmdline_user_args():
		if arg == "--classify": classify = true
		if arg == "--render": render = true
		if arg.begins_with("--dump="):
			for s in arg.trim_prefix("--dump=").split(",", false): dump.append(int(s))
		if arg.begins_with("--out-dir="): out_dir = arg.trim_prefix("--out-dir=")
	game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	await game._new_game()
	await create_timer(1.0).timeout
	if classify: _classify()
	for n in dump:
		await _load(int(n))
		_dump_scene(int(n))
	if render: await _render(out_dir)
	if failures.is_empty():
		print("FPS CARDS PASS")
		quit(0)
	else:
		print("FPS CARDS FAIL ", failures.size())
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

# --- classification -------------------------------------------------------------------------------------
func _card_line(screen: int, e: Dictionary, node: Node, twin_note: bool) -> String:
	var sp := node.get_node_or_null("Model") as Sprite3D
	if sp == null: return ""
	var line := "CARD %d %d %d %s %s %s" % [screen, int(e.get("x", 0)), int(e.get("y", 0)), node.get_meta("model_key", ""),
		"fixed" if sp.billboard == BaseMaterial3D.BILLBOARD_DISABLED else "billboard", game.fp_world.frame_path(e)]
	if twin_note: line += " twin=" + _twin_state(sp)
	return line

# "none", or the angle in degrees between the twin's face and the sun, horizontally, with the twin's own settings
# ("ok" or what is wrong): the twin must be a plain card (billboard off), shadow-only, with the sprite itself out
# of the shadow pass, and the same picture as the sprite.
func _twin_state(sp: Sprite3D) -> String:
	var twin := sp.get_node_or_null("ShadowTwin") as Sprite3D
	if twin == null: return "none"
	var problems: Array[String] = []
	if twin.billboard != BaseMaterial3D.BILLBOARD_DISABLED: problems.append("billboard")
	if twin.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY: problems.append("not-shadows-only")
	if sp.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: problems.append("sprite-casts")
	if twin.texture != sp.texture or twin.offset != sp.offset or not is_equal_approx(twin.pixel_size, sp.pixel_size): problems.append("out-of-sync")
	var light: DirectionalLight3D = game.fp_world.light
	var toward: Vector3 = light.global_transform.basis.z
	var face: Vector3 = twin.global_transform.basis.z
	var a := Vector2(toward.x, toward.z).normalized()
	var b := Vector2(face.x, face.z).normalized()
	var angle := rad_to_deg(a.angle_to(b))
	return "%.3f,%s" % [angle, "ok" if problems.is_empty() else "+".join(problems)]

func _classify() -> void:
	var fw = game.fp_world
	var scratch := Node3D.new()
	root.add_child(scratch)
	var cards := 0
	for number in game.world.screens:
		var n := int(number)
		if fw.is_inside(n): continue
		game.current_screen = n
		game.generation += 1
		fw.interior = false
		for source in game.world.screens[number].get("sprites", []):
			var e: Dictionary = source.duplicate()
			if int(e.get("type", 1)) == 2: continue
			var key: String = fw.model_key(e)
			if key in fw.BUILT: continue
			var node: Node3D = fw.make_entity(e, 0, scratch, false, n)
			# Stacked art stands as one card per part (fp_world.seam_parts, M3): each part's holder carries its Model.
			var holders: Array = [node] if node.get_node_or_null("Model") != null else node.get_children().filter(func(c): return str(c.name).begins_with("Part_"))
			for holder in holders:
				var line := _card_line(n, e, holder, false)
				if line != "":
					print(line)
					cards += 1
			scratch.remove_child(node)
			node.free()
	scratch.free()
	print("CARDS ", cards)

func _cards(node: Node, out: Array) -> void:
	if node is Node3D and node.has_meta("billboard") and node.get_node_or_null("Model") is Sprite3D: out.append(node)
	for child in node.get_children(): _cards(child, out)

func _dump_scene(screen: int) -> void:
	var nodes: Array = []
	_cards(game.scene_root, nodes)
	for node in nodes:
		var sp := node.get_node("Model") as Sprite3D
		if int(sp.get_meta("screen", -1)) != screen: continue
		var e: Dictionary = game.entities.get(int(node.get_meta("entity_id", 0)), {})
		if e.is_empty(): continue
		print(_card_line(screen, e, node, true))

# --- the pixel checks ---------------------------------------------------------------------------------
func _set_camera(x: float, y: float, yaw: float, pitch := -0.05) -> void:
	game.entities[1].x = x
	game.entities[1].y = y
	game.fps_yaw = yaw
	game.fps_pitch = pitch
	game._sync_fps_camera()
	for model in [game.fps_viewmodel, game.fps_hand]:
		if is_instance_valid(model): model.visible = false
	game.ui.visible = false

func _grab() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	return img

func _changed(a: Image, b: Image) -> PackedByteArray:
	var da := a.get_data()
	var db := b.get_data()
	var out := PackedByteArray()
	out.resize(da.size() / 3)
	for i in out.size():
		var o := i * 3
		out[i] = 1 if (absi(da[o] - db[o]) > EPS or absi(da[o + 1] - db[o + 1]) > EPS or absi(da[o + 2] - db[o + 2]) > EPS) else 0
	return out

# The columns [first, last] and rows [first, last] spanned by the changed pixels, and their count.
func _extent(mask: PackedByteArray, w: int) -> Dictionary:
	var x0 := 1 << 30
	var x1 := -1
	var y0 := 1 << 30
	var y1 := -1
	var count := 0
	for i in mask.size():
		if mask[i] == 0: continue
		count += 1
		var x := i % w
		var y := i / w
		x0 = mini(x0, x)
		x1 = maxi(x1, x)
		y0 = mini(y0, y)
		y1 = maxi(y1, y)
	return {"x0": x0, "x1": x1, "y0": y0, "y1": y1, "n": count, "w": x1 - x0 + 1 if x1 >= 0 else 0}

func _tree_group() -> Array:
	var nodes: Array = []
	_cards(game.scene_root, nodes)
	var target: Sprite3D = null
	for node in nodes:
		var sp := node.get_node("Model") as Sprite3D
		if int(sp.get_meta("screen", -1)) != TREE[0]: continue
		var e: Dictionary = game.entities.get(int(node.get_meta("entity_id", 0)), {})
		if absf(float(e.get("x", -999)) - TREE[1]) < 1.0 and absf(float(e.get("y", -999)) - TREE[2]) < 1.0: target = sp
	var group: Array = []
	if target == null: return group
	# A tree is drawn by every scene that holds it (the neighbours' backdrops too): hiding it hides every copy.
	for node in nodes:
		var sp := node.get_node("Model") as Sprite3D
		if sp.global_position.distance_to(target.global_position) < 0.05 and sp.texture == target.texture: group.append(sp)
	return group

# The pixels the tree covers from camera (x, y, yaw), with the shadows off: the render with the tree against the
# render without it.
func _tree_pixels(group: Array, x: float, y: float, yaw: float, out_dir: String, tag: String) -> Dictionary:
	_set_camera(x, y, yaw)
	for e in game.entities.keys(): game._update_visual(e)
	var with_tree := await _grab()
	for sp in group: sp.visible = false
	var without := await _grab()
	for sp in group: sp.visible = true
	if out_dir != "": with_tree.save_png(out_dir.path_join("tree-%s.png" % tag))
	var extent := _extent(_changed(with_tree, without), with_tree.get_width())
	extent["image_w"] = with_tree.get_width()
	return extent

func _render(out_dir: String) -> void:
	print("CASE tree-04 seen from every side")
	await _load(TREE[0])
	var group := _tree_group()
	if group.is_empty():
		_fail("the tree-04 at screen %d (%d, %d) is not in the scene" % [TREE[0], TREE[1], TREE[2]])
		return
	var light: DirectionalLight3D = game.fp_world.light
	var tx := float(TREE[1])
	var ty := float(TREE[2])
	# Shadows off: the tree's own pixels only.
	light.shadow_enabled = false
	var south := await _tree_pixels(group, tx, ty + CAM, 0.0, out_dir, "south")
	var east := await _tree_pixels(group, tx + CAM, ty, PI / 2.0, out_dir, "east")
	var west := await _tree_pixels(group, tx - CAM, ty, -PI / 2.0, out_dir, "west")
	var north := await _tree_pixels(group, tx, ty - CAM, PI, out_dir, "north")
	print("  tree-04 width in px: from the south %d, from the east %d, from the west %d, from the north %d" % [south.w, east.w, west.w, north.w])
	if south.n < 2000: _fail("the tree is not in view from the south (%d px)" % south.n)
	for view in [["east", east], ["west", west], ["north", north]]:
		var seen: Dictionary = view[1]
		if seen.x0 <= 0 or seen.x1 >= int(seen.image_w) - 1: _fail("tree-04 from the %s runs off the picture" % view[0])
		if float(seen.w) < 0.8 * float(south.w): _fail("tree-04 from the %s is %d px wide, under 0.8 of %d px from the south: it is an edge-on card" % [view[0], seen.w, south.w])
	# Every tree still casts a shadow: with the light's shadows on, hiding the tree changes the ground beyond the
	# pixels of the tree itself (its own pixels are the same with the shadows off).
	_set_camera(tx + CAM, ty, PI / 2.0, -0.35) # from the east: the sun is in the south west, the shadow falls across the view
	light.shadow_enabled = true
	var on_with := await _grab()
	for sp in group: sp.visible = false
	var on_without := await _grab()
	light.shadow_enabled = false
	var off_without := await _grab()
	for sp in group: sp.visible = true
	var off_with := await _grab()
	var own := _changed(off_with, off_without)
	var both := _changed(on_with, on_without)
	var shadow := PackedByteArray()
	shadow.resize(own.size())
	for i in shadow.size(): shadow[i] = 1 if both[i] == 1 and own[i] == 0 else 0
	var shadow_px := _extent(shadow, on_with.get_width())
	print("  tree-04: %d px of its own, %d px of shadow on the ground" % [_extent(own, on_with.get_width()).n, shadow_px.n])
	if out_dir != "": on_with.save_png(out_dir.path_join("tree-shadow.png"))
	if shadow_px.n < 3000: _fail("tree-04 casts no shadow on the ground (%d px change with the tree hidden beyond its own)" % shadow_px.n)
	# And its twin is what casts it.
	for sp in group:
		var state := _twin_state(sp)
		print("  twin: ", state)
		if not state.ends_with(",ok"): _fail("tree-04's shadow twin: " + state)
		elif absf(float(state.split(",")[0])) > 0.01: _fail("tree-04's shadow twin is %s degrees off the sun" % state.split(",")[0])
	light.shadow_enabled = true
