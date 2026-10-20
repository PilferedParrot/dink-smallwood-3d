extends "bed_capture.gd"
# Re-baseline instrument (INTEGRATE-2): per view, dump every entity's projected screen rect (native render rows
# mapped to the 600x400 fixture frame) from its visible mesh/sprite bounds, so two trees can be compared by geometry.
func _capture_setup(game, view: Dictionary) -> void:
	super._capture_setup(game, view)
	var size: Vector2i = root.size
	var rows := int(round(float(size.x)*(400.0/sqrt(2.0))/600.0))
	var crop: int = (size.y-rows)/2
	var out := {}
	for id in game.entities:
		var visual: Node3D = game.visuals.get(id)
		if visual == null or not visual.is_inside_tree(): continue
		var corners: Array = []
		_all_corners(visual, corners)
		if corners.is_empty(): continue
		var lo := Vector2.INF
		var hi := Vector2(-INF, -INF)
		for point in corners:
			if game.camera.is_position_behind(point): continue
			var p: Vector2 = game.camera.unproject_position(point) - Vector2(0, crop)
			lo = lo.min(p); hi = hi.max(p)
		if lo.x == INF: continue
		var e: Dictionary = game.entities[id]
		out[str(id)] = {"key": str(visual.get_meta("model_key", "")), "editor": int(e.get("editor_num", e.get("index", 0))),
			"rect600": [lo.x*600.0/size.x, lo.y*400.0/rows, hi.x*600.0/size.x, hi.y*400.0/rows]}
	var folder := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out-dir="): folder = arg.trim_prefix("--out-dir=")
	var f := FileAccess.open(folder.path_join(str(view.name)+"-footprints.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
func _all_corners(node: Node, out: Array) -> void:
	if (node is MeshInstance3D or node is SpriteBase3D):
		out.append_array(_corners(node.get_aabb(), node.global_transform))
	for child in node.get_children(): _all_corners(child, out)
