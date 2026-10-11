extends SceneTree
# Read-only native source/ownership/collision inventory for the whole-fir
# collision compiler. The host deliberately restores RC4 source collision so
# current RC5 walls or fir hooks cannot change the unsupported-root selection.

const FP = preload("res://scripts/fp_world.gd")
const VM = preload("res://scripts/dink_vm.gd")
const FIT_PATH := "res://prototype/rc5_firs.json"

class BaselineHost extends "res://../tests/collision_survey_host.gd":
	func _sprite_hardbox_replaced(e: Dictionary) -> bool:
		return footprint_sprites.has(int(e.get("editor_num", 0)))
	func _tile_pixel_replaced(_pos: Vector2) -> bool:
		return false
	func _additional_structure_blocked(_pos: Vector2, _from: Vector2) -> bool:
		return false

var game: BaselineHost
var fp

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out_path = arg.trim_prefix("--out=")
	if out_path.is_empty():
		push_error("Pass -- --out=<absolute json path>")
		quit(2)
		return
	var fit: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIT_PATH))
	game = BaselineHost.new()
	game.test_mode = true
	game.world = game._read_json("res://data/world.json")
	var seq_doc: Dictionary = game._read_json("res://data/sequences.json")
	game.sequences = seq_doc.get("sequences", seq_doc)
	game.original_sequences = game.sequences.duplicate(true)
	game.footprints = game._read_json("res://data/footprints.json").get("screens", {})
	game.vm = VM.new(game)
	game.vm.globals["vision"] = 0
	fp = FP.new()
	fp.setup(game)
	fp.interior = false
	game.fp_world = fp
	var placements: Array = []
	var parts: Array = []
	for sn in game.world.screens:
		var n := int(sn)
		if bool(game.world.screens[sn].get("indoor", false)): continue
		var sprites: Array = game.world.screens[sn].get("sprites", [])
		for list_index in sprites.size():
			var source: Dictionary = sprites[list_index]
			if int(source.get("seq", 0)) != 32 or int(source.get("frame", 0)) not in [8, 9, 10]: continue
			if int(source.get("type", 1)) not in [0, 1] or int(source.get("vision", 0)) != 0: continue
			if int(source.get("brain", 0)) != 0 or not str(source.get("script", "")).is_empty(): continue
			if absf(float(source.get("size", 100)) - 100.0) >= 0.5: continue
			var e: Dictionary = game.editor_entity(n, source, true, 0)
			if e.is_empty(): continue
			var frame := int(e.get("pframe", e.get("frame", 0)))
			var d: Dictionary = game._frame(32, frame)
			var path := str(d.get("path", ""))
			var fitted: Array = fit.get("source_parts", {}).get(path, [])
			var shown: Array = fp.seam_parts(e, n)
			if fitted.is_empty() or shown.size() != fitted.size():
				push_error("Missing matching source-part fit/seam at %d:%d frame %d: %d versus %d" %
					[n, list_index, frame, fitted.size(), shown.size()])
				quit(2)
				return
			var item := {"screen": n, "list_index": list_index,
				"editor_index": int(source.get("index", -1)), "type": int(source.get("type", 1)),
				"seq": 32, "frame": frame, "path": path,
				"source_xy": [float(e.x), float(e.y)], "part_indices": []}
			placements.append(item)
			for k in fitted.size():
				var source_part: Dictionary = fitted[k]
				var rows: Array = source_part["rows"]
				if int(shown[k][0]) != int(rows[0]) or int(shown[k][1]) != int(rows[1]):
					push_error("Source-part order mismatch at %d:%d frame %d part %d" % [n, list_index, frame, k])
					quit(2)
					return
				var source_foot: Array = source_part["source_foot_in_full_art_px"]
				var local := Vector2(float(e.x) - float(d.get("dx", 0)) + float(source_foot[0]),
					float(e.y) - float(d.get("dy", 0)) + float(source_foot[1]))
				var global: Vector2 = fp.screen_origin(n) + local
				var normalized := _normalize(global)
				var part := {"source_screen": n, "source_list_index": list_index,
					"source_editor_index": int(source.get("index", -1)),
					"source_type": int(source.get("type", 1)), "source_frame": frame,
					"source_path": path, "part": k,
					"rows": source_part["rows"], "source_foot_in_full_art_px": source_foot,
					"uniform_scale": float(source_part["uniform_scale"]),
					"source_local_foot_xy": [local.x, local.y],
					"global_foot_xy": [global.x, global.y], "normalized_foot": normalized,
					"full_world_shown": bool(shown[k][3]), "scene5x5_shown_centers": [],
					"baseline_blocked": false}
				if source_part.has("source_window_x_px"):
					part["source_window_x_px"] = source_part["source_window_x_px"]
					part["source_apex_px"] = source_part["source_apex_px"]
				item.part_indices.append(parts.size())
				parts.append(part)
	for center_text in game.world.screens:
		var center := int(center_text)
		if bool(game.world.screens[center_text].get("indoor", false)): continue
		var col := (center - 1) % 32
		var block := {center: true}
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				if dx == 0 and dz == 0: continue
				if col + dx < 0 or col + dx >= 32: continue
				var other := center + dx + dz * 32
				if game.world.screens.has(str(other)) and not fp.is_inside(other): block[other] = true
		fp.scene_block = block
		for item in placements:
			if not block.has(int(item.screen)): continue
			var source: Dictionary = game.world.screens[str(item.screen)].sprites[int(item.list_index)]
			var e: Dictionary = game.editor_entity(int(item.screen), source, true, 0)
			var flags: Array = fp.seam_parts(e, int(item.screen))
			for k in flags.size():
				if bool(flags[k][3]): parts[int(item.part_indices[k])].scene5x5_shown_centers.append(center)
	fp.scene_block.clear()
	var selected := 0
	var invalid := 0
	var visible := 0
	var last_screen := -1
	for part in parts:
		if not bool(part.full_world_shown) and part.scene5x5_shown_centers.is_empty(): continue
		visible += 1
		var normalized: Dictionary = part.normalized_foot
		if not bool(normalized.valid_outdoor_neighbor):
			invalid += 1
			continue
		var n := int(normalized.screen)
		if n != last_screen:
			game.load_map(n, false)
			# Match the source-support fixture's static editor state exactly.
			game.entities = {1: {}}
			var id := 2
			for source in game.world.screens[str(n)].get("sprites", []):
				var e: Dictionary = game.editor_entity(n, source, true, 0)
				if e.is_empty(): continue
				game.entities[id] = e
				id += 1
			last_screen = n
		var local: Array = normalized.local_xy
		part.baseline_blocked = game._blocked(Vector2(float(local[0]), float(local[1])), 1)
		if not bool(part.baseline_blocked): selected += 1
	var output := {"schema": "rc5-fir-collision-native-inventory-1",
		"baseline": "collision_survey_host with only original footprint hardbox replacement; no RC5 tile/stone/fir hooks",
		"counts": {"placements": placements.size(), "source_parts": parts.size(),
			"shown_union": visible, "valid_unsupported": selected, "invalid_unsupported": invalid},
		"parts": parts}
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "\t"))
	print("FIR COLLISION INVENTORY placements=%d parts=%d shown=%d unsupported=%d invalid=%d" %
		[placements.size(), parts.size(), visible, selected, invalid])
	fp.art_cache.clear()
	fp.stack_cache.clear()
	fp.clean_cache.clear()
	fp.terrain_cache.clear()
	fp.host = null
	fp.source_firs = null
	game.textures.clear()
	game.fp_world = null
	game.vm = null
	fp = null
	game.free()
	game = null
	await process_frame
	quit(0)

func _normalize(global: Vector2) -> Dictionary:
	var col := int(floor(global.x / 600.0))
	var row := int(floor(global.y / 400.0))
	var n := row * 32 + col + 1
	var local := Vector2(global.x - float(col * 600) + 20.0,
		global.y - float(row * 400))
	var valid: bool = col >= 0 and col < 32 and row >= 0 \
		and game.world.screens.has(str(n)) and not fp.is_inside(n) \
		and local.x >= 20.0 and local.x < 620.0 and local.y >= 0.0 and local.y < 400.0
	return {"screen": n, "local_xy": [local.x, local.y],
		"global_xy": [global.x, global.y], "valid_outdoor_neighbor": valid}
