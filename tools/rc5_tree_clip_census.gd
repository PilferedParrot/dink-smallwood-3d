extends SceneTree
# Native, read-only source-tree dispatch/5x5 scene census. No game render.
const GAME = preload("res://scripts/fps_game.gd")
const VM = preload("res://scripts/dink_vm.gd")
const FP = preload("res://scripts/fp_world.gd")

var game
var world
var entries: Array = []
var by_source: Dictionary = {}
var outdoor: Array[int] = []
var max_centers := -1
var out_path := ""

func _initialize() -> void:
	_run.call_deferred()

func _block(center: int) -> Dictionary:
	var block: Dictionary = {center: true}
	var col: int = (center - 1) % 32
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			if col + dx < 0 or col + dx >= 32: continue
			var n := center + dx + 32 * dz
			if game.world.screens.has(str(n)) and not world.is_inside(n): block[n] = true
	return block

func _vec2(v: Vector2) -> Array:
	return [v.x, v.y]

func _vec3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

func _sprite_geometry(node: Node3D) -> Array:
	var out := []
	var pending: Array[Node] = [node]
	while not pending.is_empty():
		var child: Node = pending.pop_back()
		if child is Sprite3D and str(child.name) != "ShadowTwin":
			var sp := child as Sprite3D
			var aabb := sp.get_aabb()
			var bottom := aabb.position.y
			var q: Node = sp
			while q != null and q != node:
				if q is Node3D: bottom += (q as Node3D).position.y
				q = q.get_parent()
			bottom += node.position.y
			out.append({"path": str(sp.get_meta("path", "")),
				"size_px": [sp.texture.get_width(), sp.texture.get_height()] if sp.texture != null else [],
				"billboard": sp.billboard, "pixel_size_m": sp.pixel_size,
				"offset_px": _vec2(sp.offset), "position_m": _vec3(sp.position),
				"region_enabled": sp.region_enabled,
				"region_rect_px": [sp.region_rect.position.x, sp.region_rect.position.y,
					sp.region_rect.size.x, sp.region_rect.size.y],
				"on_surface": bool(sp.get_meta("on_surface", false)),
				"depth_px": sp.get_meta("depth_px") if sp.has_meta("depth_px") else null,
				"physical_bottom_m": bottom,
				"aabb_local": [_vec3(aabb.position), _vec3(aabb.end)]})
		for next in child.get_children(): pending.append(next)
	return out

func _gather_sources() -> void:
	for sn in game.world.screens:
		var n := int(sn)
		if bool(game.world.screens[sn].get("indoor", false)): continue
		outdoor.append(n)
		var sprites: Array = game.world.screens[sn].get("sprites", [])
		for list_index in sprites.size():
			var raw: Dictionary = sprites[list_index]
			var vision := int(raw.get("vision", 0))
			var e: Dictionary = game.editor_entity(n, raw, true, vision)
			if e.is_empty(): continue
			var key: String = world.model_key(e)
			if key not in ["oak_tree", "pine_tree", "dead_tree"]: continue
			var path: String = world.frame_path(e)
			var d: Dictionary = game._frame(int(e.get("pseq", 0)), int(e.get("pframe", 1)))
			var parts: Array = world.stack_rows(path)
			if parts.size() <= 1: parts = [[-1, 0, 0]]
			var whole := bool(world.source_firs.handles(e))
			var ground := bool(world.paints_ground(e, n))
			var center_lists := []
			for _part in parts: center_lists.append([])
			var entry := {"source_screen": n, "source_list_index": list_index,
				"editor_index": int(raw.get("index", -1)), "seq": int(e.get("pseq", 0)),
				"frame": int(e.get("pframe", 1)), "path": path,
				"model_key": key, "source_type": int(e.get("type", 1)),
				"vision": vision, "scripted": not str(e.get("script", "")).is_empty(),
				"size": float(e.get("size", 100)), "source_xy": [float(e.x), float(e.y)],
				"frame_hotspot_px": [float(d.get("dx", 0)), float(d.get("dy", 0))],
				"dispatch": "ground_paint" if ground else ("whole_source_fir" if whole else "generic_billboard"),
				"static_scenery": bool(world.static_scenery(e)),
				"source_part_rows": parts,
				"shown_centers_by_part": center_lists,
				"native_source_scene_flags": [], "native_geometry_sample": []}
			if not by_source.has(n): by_source[n] = []
			by_source[n].append(entries.size())
			entries.append(entry)
	outdoor.sort()

func _scene_visibility() -> Dictionary:
	var per_scene: Dictionary = {}
	var center_count := 0
	for center in outdoor:
		if max_centers >= 0 and center_count >= max_centers: break
		center_count += 1
		world.scene_block = _block(center)
		var row: Dictionary = {"standing_vision0": 0, "standing_vision1": 0,
			"whole_vision0": 0, "generic_vision0": 0, "frame8_generic_vision0": 0,
			"ground_paint_vision0": 0}
		for source in world.scene_block:
			for index in by_source.get(source, []):
				var entry: Dictionary = entries[index]
				game.vm.globals["vision"] = int(entry["vision"])
				var raw: Dictionary = game.world.screens[str(source)].sprites[int(entry["source_list_index"])]
				var e: Dictionary = game.editor_entity(int(source), raw, true, int(entry["vision"]))
				if e.is_empty(): continue
				var flags: Array = world.seam_parts(e, int(source))
				if center == int(source):
					entry["native_source_scene_flags"] = flags.duplicate(true)
				if str(entry["dispatch"]) == "ground_paint":
					if int(entry["vision"]) == 0: row["ground_paint_vision0"] += 1
					continue
				for k in mini(flags.size(), (entry["shown_centers_by_part"] as Array).size()):
					if not bool(flags[k][3]): continue
					(entry["shown_centers_by_part"][k] as Array).append(center)
					row["standing_vision%d" % int(entry["vision"])] += 1
					if int(entry["vision"]) == 0:
						if str(entry["dispatch"]) == "whole_source_fir": row["whole_vision0"] += 1
						else:
							row["generic_vision0"] += 1
							if int(entry["frame"]) == 8: row["frame8_generic_vision0"] += 1
		per_scene[str(center)] = row
	world.scene_block.clear()
	return per_scene

func _sample_geometry() -> void:
	var parent := Node3D.new()
	root.add_child(parent) # Sprite3D computes its actual quad AABB in the tree.
	game.scene_root = parent
	for index in entries.size():
		var entry: Dictionary = entries[index]
		if str(entry["dispatch"]) == "ground_paint": continue
		var shown: Array = entry["shown_centers_by_part"]
		var chosen := -1
		for centers in shown:
			if not (centers as Array).is_empty():
				chosen = int(centers[0])
				break
		if chosen < 0: continue
		world.scene_block = _block(chosen)
		game.current_screen = chosen
		game.vm.globals["vision"] = int(entry["vision"])
		var n := int(entry["source_screen"])
		var raw: Dictionary = game.world.screens[str(n)].sprites[int(entry["source_list_index"])]
		var e: Dictionary = game.editor_entity(n, raw, true, int(entry["vision"]))
		var node: Node3D = world.make_entity(e, 0, parent, false, n)
		entry["native_geometry_sample"] = _sprite_geometry(node)
		entry["native_geometry_scene_center"] = chosen
		entry["native_on_surface"] = bool(node.has_meta("surface_position"))
		entry["native_house_part"] = bool(node.get_meta("house_part", false))
		parent.remove_child(node)
		node.free()
	world.scene_block.clear()
	root.remove_child(parent)
	parent.free()
	game.scene_root = null

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out_path = arg.trim_prefix("--out=")
		if arg.begins_with("--limit-centers="): max_centers = int(arg.trim_prefix("--limit-centers="))
	if out_path.is_empty():
		push_error("Pass -- --out=<absolute json>")
		quit(2)
		return
	game = GAME.new()
	game.test_mode = true
	game.world = game._read_json("res://data/world.json")
	var seqdoc: Dictionary = game._read_json("res://data/sequences.json")
	game.sequences = seqdoc.get("sequences", seqdoc)
	game.original_sequences = game.sequences.duplicate(true)
	game.footprints = game._read_json("res://data/footprints.json").get("screens", {})
	game.vm = VM.new(game)
	game.vm.globals["vision"] = 0
	game.fp_world = FP.new()
	game.fp_world.setup(game)
	world = game.fp_world
	world.interior = false
	_gather_sources()
	var scenes := _scene_visibility()
	_sample_geometry()
	var counts := {"outdoor_screens": outdoor.size(), "source_tree_placements": entries.size(),
		"per_frame": {}, "shown_source_placements": 0, "shown_parts": 0,
		"ground_paint_placements": 0, "generic_standing_placements": 0,
		"whole_source_fir_placements": 0}
	for entry in entries:
		var key := str(entry["frame"])
		if not counts["per_frame"].has(key): counts["per_frame"][key] = {"source": 0, "shown": 0}
		counts["per_frame"][key]["source"] += 1
		var shown := false
		for centers in entry["shown_centers_by_part"]:
			if not (centers as Array).is_empty():
				shown = true
				counts["shown_parts"] += 1
		if shown:
			counts["shown_source_placements"] += 1
			counts["per_frame"][key]["shown"] += 1
		match str(entry["dispatch"]):
			"ground_paint": counts["ground_paint_placements"] += 1
			"whole_source_fir": counts["whole_source_fir_placements"] += 1
			"generic_billboard": counts["generic_standing_placements"] += 1
	var result := {"schema": "rc5-native-tree-clip-census-1",
		"scope": "all outdoor source tree model keys, all seq32 frames/visions, actual native 5x5 scene_block + seam_parts, static source state",
		"counts": counts, "per_scene": scenes, "placements": entries}
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(result))
	file.close()
	print("TREE CLIP NATIVE source=", entries.size(), " shown=", counts["shown_source_placements"],
		" scenes=", scenes.size())
	world.art_cache.clear()
	world.stack_cache.clear()
	world.clean_cache.clear()
	world.host = null
	game.textures.clear()
	game.fp_world = null
	await process_frame
	quit(0)
