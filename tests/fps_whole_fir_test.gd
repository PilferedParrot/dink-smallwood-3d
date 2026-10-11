extends SceneTree
# Logic-only fixture. It runs fp_world's real seam_parts ownership for every
# mapped tree-09/10 source and inspects each constructed complete sprite.

const FP = preload("res://scripts/fp_world.gd")
const SOURCE_FIR = preload("res://scripts/source_fir.gd")
const GAME = preload("res://scripts/fps_game.gd")
const SCALE := 0.025

class FakeHost:
	extends RefCounted
	var world: Dictionary
	var sequences: Dictionary
	func _frame(seq: int, frame: int) -> Dictionary:
		var frames: Array = sequences.get(str(seq), {}).get("frames", [])
		return frames[frame - 1] if frame >= 1 and frame <= frames.size() else {}
	func _texture(path: String) -> Texture2D:
		return load(path) as Texture2D

class FakeProps:
	extends RefCounted
	func has(_path: String) -> bool:
		return false

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _run() -> void:
	if "--live" in OS.get_cmdline_user_args():
		await _live_scene()
		return
	var host := FakeHost.new()
	host.world = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	host.sequences = JSON.parse_string(FileAccess.get_file_as_string("res://data/sequences.json"))["sequences"]
	var world := FP.new()
	world.host = host
	world.props = FakeProps.new()
	var fir := SOURCE_FIR.new(world)
	check(not fir.fit.is_empty(), "fir fit loads")
	if fir.fit.is_empty():
		print("WHOLE FIR FAIL no fit")
		quit(1)
		return
	var tested := 0
	var shown := 0
	var block_changed := 0
	var types := {0: 0, 1: 0}
	for sn in host.world["screens"]:
		var screen := int(sn)
		if bool(host.world["screens"][sn].get("indoor", false)): continue
		for e in host.world["screens"][sn].get("sprites", []):
			if int(e.get("seq", 0)) != 32 or int(e.get("frame", 0)) not in [9, 10]: continue
			if int(e.get("vision", 0)) != 0 or int(e.get("brain", 0)) != 0 or not str(e.get("script", "")).is_empty(): continue
			if absf(float(e.get("size", 100)) - 100.0) >= 0.5: continue
			tested += 1
			var kind := int(e.get("type", 1))
			types[kind] = int(types.get(kind, 0)) + 1
			check(fir.handles(e), "handles type %d screen %d" % [kind, screen])
			var live: Dictionary = e.duplicate()
			live["pseq"] = live.seq
			live["pframe"] = live.frame
			live["seq"] = 0
			live["frame"] = 1
			check(fir.handles(live), "normalized display frame screen %d" % screen)
			# Type-0 ground ownership belongs to the caller. Exercise its explicit
			# constructor path with the same retained source flags.
			var parts: Array = world.seam_parts(e, screen)
			var parent := Node3D.new()
			root.add_child(parent)
			parent.position = world.point(float(e["x"]), float(e["y"]))
			fir.add(parent, live, parts, screen, int(e["index"]), kind == 1)
			var expected := 0
			for k in parts.size():
				if not bool(parts[k][3]): continue
				expected += 1
				var holder := parent.get_node_or_null("WholeFir_%d" % k) as Node3D
				check(holder != null, "missing whole fir screen %d editor %d part %d" % [screen, e["index"], k])
				if holder != null: _check_fir(holder, e, parts[k], k, screen, kind == 1, fir.fit)
			shown += expected
			check(float(parent.get_meta("height",0.0)) > 0.0 or expected == 0,
				"normalized parent height screen %d" % screen)
			check(parent.get_child_count() == expected,
				"unexpected part count screen %d editor %d: %d vs %d" % [screen, e["index"], parent.get_child_count(), expected])
			parent.free()
			if kind == 1:
				world.scene_block[screen] = true
				var local_parts: Array = world.seam_parts(e, screen)
				world.scene_block.clear()
				var local_parent := Node3D.new()
				root.add_child(local_parent)
				fir.add(local_parent, e, local_parts, screen, int(e["index"]), false)
				var local_count := 0
				for k in local_parts.size():
					if bool(local_parts[k][3]):
						local_count += 1
						var holder := local_parent.get_node_or_null("WholeFir_%d" % k) as Node3D
						check(holder != null, "single-screen block missing shown fir %d:%d:%d" % [screen, e["index"], k])
						if holder != null: _check_fir(holder, e, local_parts[k], k, screen, false, fir.fit)
					if bool(parts[k][3]) != bool(local_parts[k][3]): block_changed += 1
				check(local_parent.get_child_count() == local_count,
					"single-screen block unexpected part count %d:%d" % [screen, e["index"]])
				local_parent.free()
	check(tested == 123 and types[1] == 116 and types[0] == 7,
		"source census %d placements, type1 %d, type0 %d" % [tested, types[1], types[0]])
	check(block_changed > 0, "scene_block ownership did not alter any shown source parts")
	# The seam decision can change with scene_block. Never bake these flags
	# into the fit; all four pairs of flags must construct all or none per part.
	var sample: Dictionary = host.world["screens"]["375"]["sprites"][0]
	for mask in range(4):
		var synthetic := [[0, 178, 177, (mask & 1) != 0], [200, 378, 377, (mask & 2) != 0]]
		var parent := Node3D.new()
		root.add_child(parent)
		fir.add(parent, sample, synthetic, 375, 1, false)
		check(parent.get_child_count() == int((mask & 1) != 0) + int((mask & 2) != 0),
			"synthetic shown flags %d" % mask)
		parent.free()
	var direct_parent := Node3D.new()
	root.add_child(direct_parent)
	var direct := fir.at_foot(direct_parent, Vector3(3.0, 0.0, -4.0), 1.25,
		{"screen": 999, "index": 7, "part": 0, "path": "future_forest"})
	check(direct != null and direct.position == Vector3(3.0, 0.0, -4.0), "reusable arbitrary foot")
	if direct != null:
		check(absf((direct.get_node("Model") as Sprite3D).pixel_size - SCALE * 1.25) < 0.00001,
			"reusable uniform scale")
	direct_parent.free()
	if failures.is_empty():
		print("WHOLE FIR PASS placements=%d type1=%d type0=%d shown=%d block_changed=%d" % [tested, types[1], types[0], shown, block_changed])
		quit(0)
	else:
		for failure in failures: print("WHOLE FIR FAIL ", failure)
		quit(1)

func _check_fir(holder: Node3D, e: Dictionary, part: Array, k: int,
		screen: int, collides: bool, fit: Dictionary) -> void:
	var template: Dictionary = fit["template"]
	var actual_frame: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sequences.json"))["sequences"]["32"]["frames"][int(e["frame"]) - 1]
	var source_path := str(actual_frame["path"])
	var source: Dictionary = fit["source_parts"][source_path][k]
	var expected := Vector3((float(source["source_foot_in_full_art_px"][0]) - float(actual_frame["dx"])) * SCALE,
		0.0, (float(source["source_foot_in_full_art_px"][1]) - float(actual_frame["dy"])) * SCALE)
	check(holder.position.distance_to(expected) < 0.0001,
		"physical foot screen %d editor %d part %d" % [screen, e["index"], k])
	check(holder.get_meta("whole_fir", false) and holder.get_meta("template_path", "") == template["path"],
		"whole source path screen %d editor %d part %d" % [screen, e["index"], k])
	var provenance: Dictionary = holder.get_meta("source_provenance", {})
	check(int(provenance.get("screen", -1)) == screen and int(provenance.get("index", -1)) == int(e["index"])
		and int(provenance.get("part", -1)) == k and str(provenance.get("path", "")) == source_path,
		"source provenance screen %d editor %d part %d" % [screen, e["index"], k])
	var sp := holder.get_node_or_null("Model") as Sprite3D
	check(sp != null, "one complete sprite")
	if sp == null: return
	check(sp.texture.get_size() == Vector2(128, 188) and not sp.region_enabled and not sp.flip_h and not sp.flip_v,
		"full source image screen %d editor %d part %d" % [screen, e["index"], k])
	check(sp.billboard == BaseMaterial3D.BILLBOARD_FIXED_Y,
		"whole object faces camera screen %d editor %d part %d" % [screen, e["index"], k])
	check(absf(sp.pixel_size - SCALE * float(source["uniform_scale"])) < 0.00001,
		"uniform crown scale screen %d editor %d part %d" % [screen, e["index"], k])
	check(sp.offset == Vector2(128.0 / 2.0 - float(template["source_foot_px"][0]),
		float(template["source_foot_px"][1]) - 188.0 / 2.0),
		"template foot anchor screen %d editor %d part %d" % [screen, e["index"], k])
	var twin := sp.get_node_or_null("ShadowTwin") as Sprite3D
	check(twin != null and twin.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		and twin.texture == sp.texture and twin.pixel_size == sp.pixel_size,
		"shadow twin screen %d editor %d part %d" % [screen, e["index"], k])
	check((holder.get_node_or_null("HitBody") != null) == collides,
		"ray body screen %d editor %d part %d" % [screen, e["index"], k])

func _collect(node: Node, whole: Array, old_parts: Array) -> void:
	if node.get_meta("whole_fir", false): whole.append(node)
	if node is Sprite3D:
		var path := str(node.get_meta("path", ""))
		if ("tree-09.png#" in path or "tree-10.png#" in path): old_parts.append(node)
	for child in node.get_children(): _collect(child, whole, old_parts)

func _live_scene() -> void:
	# Setup bypasses story progression and loads the actual renderer's 5x5 block.
	var game := GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	await game._new_game()
	game.vm.cancel_all()
	game.vm.globals["vision"] = 0
	game.load_map(439, false)
	await create_timer(0.5).timeout
	var whole: Array = []
	var old_parts: Array = []
	_collect(game.scene_root, whole, old_parts)
	check(old_parts.is_empty(), "old cropped source sprites remain in the live scene: %d" % old_parts.size())
	var target := false
	for node in whole:
		var provenance: Dictionary = node.get_meta("source_provenance", {})
		if int(provenance.get("screen", -1)) == 375 and int(provenance.get("index", -1)) == 1 \
				and int(provenance.get("part", -1)) == 1:
			target = true
		var sp := node.get_node_or_null("Model") as Sprite3D
		check(sp != null and sp.texture.get_size() == Vector2(128, 188), "live source fir lacks whole image")
	check(target, "375 editor 1 lower source part missing as a whole fir from screen 439")
	game.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("WHOLE FIR LIVE PASS whole=%d old_parts=%d target=%s" % [whole.size(), old_parts.size(), target])
		quit(0)
	else:
		for failure in failures: print("WHOLE FIR LIVE FAIL ", failure)
		quit(1)
