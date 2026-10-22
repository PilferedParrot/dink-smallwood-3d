extends "res://../tests/fps_capture.gd"
# Stepped and flat rock walls at matched views, for tests/test_terrain_end_faces.py. A view carries "rects" (source px Rect2i
# values, [x, y, w, h]) that replace the screen's terrain, and the camera pose; the script writes NAME-faces.json beside the
# picture: every vertical face the camera sees, as its run-axis role ("end" faces look along the box's run) and screen box.
func _capture_setup(game, view: Dictionary) -> void:
	if not view.has("rects"): return
	var old: MultiMeshInstance3D = game.scene_root.get_node_or_null("SolidTerrain")
	var mesh: BoxMesh = old.multimesh.mesh
	for n in ["SolidTerrain","SolidTerrainFill","TerrainCollision"]:
		var node = game.scene_root.get_node_or_null(n)
		if node != null:
			game.scene_root.remove_child(node)
			node.free()
	var rects: Array[Rect2i] = []
	for r in view.rects: rects.append(Rect2i(int(r[0]),int(r[1]),int(r[2]),int(r[3])))
	var instance := MultiMeshInstance3D.new()
	instance.name = "SolidTerrain"
	instance.multimesh = game.fp_world.terrain_multimesh(mesh,rects,game.fp_world.terrain_outline_offsets(rects))
	game.scene_root.add_child(instance)
	_hide_sprites(game.scene_root) # the screen's own actors and items must not stand in the measured faces
	var cam: Camera3D = game.camera
	var faces: Array = []
	for r: Rect2i in rects:
		var along_x: bool = r.size.x >= r.size.y
		for side in [-1, 1]:
			for axis in ["x", "z"]:
				var normal: Vector3 = Vector3(side if axis == "x" else 0, 0, side if axis == "z" else 0)
				# a face looks along the run axis when its normal is on that axis
				var end: bool = (axis == "x") == along_x
				var x0: float = float(r.position.x)
				var y0: float = float(r.position.y)
				var x1: float = float(r.end.x)
				var y1: float = float(r.end.y)
				var corners: Array = []
				if axis == "x":
					var fx: float = x1 if side > 0 else x0
					corners = [Vector2(fx, y0), Vector2(fx, y1)]
				else:
					var fy: float = y1 if side > 0 else y0
					corners = [Vector2(x0, fy), Vector2(x1, fy)]
				var centre: Vector3 = game.fp_world.point((corners[0].x + corners[1].x) * 0.5, (corners[0].y + corners[1].y) * 0.5)
				if normal.dot(cam.global_position - centre) <= 0.0: continue
				var lo := Vector2(1e9, 1e9)
				var hi := Vector2(-1e9, -1e9)
				var behind := false
				for c in corners:
					for h in [0.0, mesh.size.y]:
						var world: Vector3 = game.fp_world.point(c.x, c.y) + Vector3(0, h, 0)
						if cam.is_position_behind(world): behind = true
						var s: Vector2 = cam.unproject_position(world)
						lo = Vector2(minf(lo.x, s.x), minf(lo.y, s.y))
						hi = Vector2(maxf(hi.x, s.x), maxf(hi.y, s.y))
				if behind: continue
				faces.append({"rect": [r.position.x, r.position.y, r.size.x, r.size.y], "normal": [normal.x, normal.z], "end": end, "box": [lo.x, lo.y, hi.x, hi.y]})
	var dir := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out-dir="): dir = arg.trim_prefix("--out-dir=")
	var out := FileAccess.open(dir.path_join(str(view.name) + "-faces.json"), FileAccess.WRITE)
	out.store_string(JSON.stringify(faces))
	out.close()

func _hide_sprites(node: Node) -> void:
	if node is SpriteBase3D: node.visible = false
	for child in node.get_children(): _hide_sprites(child)
