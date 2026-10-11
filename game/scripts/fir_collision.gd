# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
# Original seq32/frame1 hardboxes rooted at source-fitted complete fir feet.
# Movement uses each body's original Rect2 grow(4) escape rule. The source
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

func _rect_distance(rect: Rect2, p: Vector2) -> float:
	var d := Vector2(maxf(maxf(rect.position.x - p.x, 0.0), p.x - rect.end.x),
		maxf(maxf(rect.position.y - p.y, 0.0), p.y - rect.end.y))
	return d.length()

func blocked(pos: Vector2, from: Vector2, screen: int) -> bool:
	var band := float(data.get("band_px", 4.0))
	for rect: Rect2 in _rects.get(screen, []):
		var grown := rect.grow(band)
		if not grown.has_point(pos): continue
		if from != Vector2.INF and not rect.has_point(pos) and grown.has_point(from) \
				and not rect.has_point(from) \
				and _rect_distance(rect, pos) >= _rect_distance(rect, from) - 0.0001:
			continue
		return true
	return false
