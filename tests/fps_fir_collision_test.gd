extends SceneTree
# Headless movement semantics for all compiled source-root bodies. No render.

const FIR = preload("res://scripts/fir_collision.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)

func _run() -> void:
	var fir := FIR.new()
	check(not fir.data.is_empty(), "fit loads")
	if fir.data.is_empty():
		quit(1)
		return
	var counts: Dictionary = fir.data["counts"]
	check(int(counts["source_placements"]) == 123 and int(counts["source_parts"]) == 246,
		"source census")
	check(int(counts["shown_union"]) == 165 and int(counts["authorized_roots"]) == 92,
		"native selected roots")
	check(int(counts["skipped_invalid"]) == 1 and int(fir.data["skipped_invalid"][0]["normalized_foot"]["screen"]) == 798,
		"absent 798 skipped")
	check(fir.data["template"]["hardbox_relative_to_measured_foot_xyxy"] == [-50.5, -31.0, 43.5, 5.0],
		"original frame1 hardbox relative to actual foot")
	check(int(counts["multi_screen_roots"]) == 12, "cross-screen roots")
	var seen: Dictionary = {}
	for record in fir.data["rectangles"]:
		var id := str(record["id"])
		check(not seen.has(id), "source root ID unique %s" % id)
		seen[id] = true
		var source: Dictionary = record["source"]
		check(id == "%d:%d:%d" % [int(source["source_screen"]),
			int(source["source_list_index"]), int(source["part"])], "provenance %s" % id)
		check(str(source["source_path"]).ends_with("tree-09.png") or
			str(source["source_path"]).ends_with("tree-10.png"), "source art %s" % id)
		var xyxy: Array = record["rect_global_xyxy"]
		var foot: Array = record["global_foot_xy"]
		check(float(xyxy[0]) < float(foot[0]) and float(foot[0]) < float(xyxy[2]) and
			float(xyxy[1]) < float(foot[1]) and float(foot[1]) < float(xyxy[3]),
			"root inside original hardbox %s" % id)
		check(not bool(record["baseline_blocked"]) and
			(bool(record["full_world_shown"]) or not record["scene5x5_shown_centers"].is_empty()),
			"authorized selection %s" % id)
		var screen := int(record["destination_screen"])
		var local: Array = record["destination_local_foot_xy"]
		var shown_here: bool = (record["scene5x5_shown_centers"] as Array).any(func(value):return int(value)==screen)
		check(fir.rectangles(screen).any(func(entry):return str(entry.id)==id) == shown_here,
			"body matches actual scene visibility %s" % id)
		if shown_here:
			check(fir.blocked(Vector2(float(local[0]), float(local[1])), Vector2.INF, screen),
				"physical root blocked %s" % id)
	check(seen.size() == 92, "92 distinct source records")
	# This old test used a distant seam fallback and would have certified an
	# invisible permanent body. Keep its negative ownership control explicitly.
	check(fir.rectangles(237).any(func(entry):return entry.id=="237:0:1"),"edge fallback remains solid in the scene that shows it")
	check(fir.rectangles(269).any(func(entry):return entry.id=="237:0:1"),"shown fallback spans the adjacent screen")
	check(not fir.rectangles(299).any(func(entry):return entry.id=="237:0:1"),"no collider indexed beyond its footprint")
	# Synthetic corners verify Rect2.grow(4), not a rounded 4px mask.
	fir._rects[999] = [Rect2(0, 0, 10, 10)]
	check(fir.blocked(Vector2(-3.5, -3.5), Vector2.INF, 999), "square grown corner blocks")
	check(not fir.blocked(Vector2(-4.1, -3.5), Vector2.INF, 999), "outside grown corner clear")
	check(not fir.blocked(Vector2(-3.5, 6), Vector2(-3.5, 5), 999),
		"band parallel distance does not trap")
	fir._rects[999] = [Rect2(0, 0, 10, 10), Rect2(13, 0, 10, 10)]
	check(fir.blocked(Vector2(12.5, 5), Vector2(11.5, 5), 999),
		"retreat from one rectangle cannot enter another band")
	check(fir.blocked(Vector2(13.5, 5), Vector2(11.5, 5), 999),
		"retreat from one rectangle cannot enter another body")
	if failures.is_empty():
		print("FIR COLLISION PASS roots=%d touched_screens=%d cross_screen=%d" %
			[seen.size(), int(counts["screens_touched"]), int(counts["multi_screen_roots"])])
		quit(0)
	else:
		for failure in failures: print("FIR COLLISION FAIL ", failure)
		quit(1)
