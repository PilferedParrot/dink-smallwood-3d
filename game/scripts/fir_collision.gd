# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
# Original seq32/frame1 hardboxes rooted at source-fitted complete fir feet.
# Movement is blocked by each body's raw Rect2, as the original's hitmap would be. The source
# entity/hardbox and tile masks are not changed.
extends RefCounted

const DATA_PATH := "res://prototype/rc5_fir_collision.json"

var data: Dictionary = {}
var _rects: Dictionary = {} # screen -> Array[Rect2], built once from data
var _visible: Dictionary = {} # source rectangle id -> actual 5x5 scene centers

func _init() -> void:
	if not FileAccess.file_exists(DATA_PATH):
		push_error("Missing fir collision fit: %s" % DATA_PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not parsed is Dictionary or str(parsed.get("schema", "")) != "rc5-fir-collision-fit-1":
		push_error("Invalid fir collision fit: %s" % DATA_PATH)
		return
	data = parsed
	for item in data.get("rectangles",[]):
		_visible[str(item.id)] = (item.scene5x5_shown_centers as Array).map(func(value):return int(value))
	for key in data.get("by_screen", {}):
		var rects: Array[Rect2] = []
		for entry in data["by_screen"][key]:
			if not (int(key) in _visible.get(str(entry.id),[])): continue
			var xyxy: Array = entry["rect_local_xyxy"]
			rects.append(Rect2(Vector2(float(xyxy[0]), float(xyxy[1])),
				Vector2(float(xyxy[2]) - float(xyxy[0]), float(xyxy[3]) - float(xyxy[1]))))
		_rects[int(key)] = rects

# Local source-pixel rectangles with source IDs, useful to inspect the actual
# union and evaluate reachable pixels without rebuilding world coordinates.
func rectangles(screen: int) -> Array:
	return (data.get("by_screen", {}).get(str(screen), []) as Array).filter(func(entry):return screen in _visible.get(str(entry.id),[]))

func blocked(pos: Vector2, _from: Vector2, screen: int) -> bool:
	for rect: Rect2 in _rects.get(screen, []):
		if rect.has_point(pos): return true
	return false

# The distance field of `blocked`: the nearest fir rectangle within `limit` of `pos` (see game.gd _solid_nearest_here).
func offer_nearest(best: Array, pos: Vector2, limit: float, screen: int) -> void:
	for rect: Rect2 in _rects.get(screen, []):
		var at := pos.clamp(rect.position, rect.end)
		var d := pos.distance_to(at)
		if d <= limit and d < (best[0] as float):
			best[0] = d
			best[1] = at
