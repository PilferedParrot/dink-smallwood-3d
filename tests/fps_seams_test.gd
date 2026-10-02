extends SceneTree
# One object per seam, and stacked art stands at its parts' feet (docs/DIRECTION.md, M3; fp_world.seam_parts).
# Two parts, run by tests/test_fps_seams.py, headless:
#
#   --classify    every billboard sprite of every outdoor screen (the map's editor layer), one line per part:
#                 "SEAM screen index part shown(0|1) path". The pytest compares each with tools/seam_objects.py.
#   --scene=n,..  scenes loaded as the game loads them; one line per drawn billboard of static scenery in the 5x5 block:
#                 "DRAWN screen x_world z_world foot_px path", foot_px the height of its lowest drawn pixel above the
#                 ground, in source px.
# Verdict: written 2026-10-02 (Opus 5.5, Dink lead), for U7 (the floating trees on 376, the tree over 251).
const GAME = preload("res://scripts/fps_game.gd")

var game

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var classify := false
	var scenes: Array = []
	for arg in OS.get_cmdline_user_args():
		if arg == "--classify": classify = true
		if arg.begins_with("--scene="):
			for s in arg.trim_prefix("--scene=").split(",", false): scenes.append(int(s))
	game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	await game._new_game()
	await create_timer(1.0).timeout
	if classify: _classify()
	for n in scenes:
		await _load(int(n))
		_drawn(int(n))
	print("FPS SEAMS DONE")
	quit(0)

func _load(screen: int) -> void:
	game.vm.cancel_all()
	game.vm.globals["vision"] = 0
	game.load_map(screen, false)
	await create_timer(0.6).timeout
	game.vm.cancel_all()
	game.playing = false

func _classify() -> void:
	var fw = game.fp_world
	fw.interior = false
	fw.scene_block.clear() # every screen built: the reading is of the map, not of one block
	for number in game.world.screens:
		var n := int(number)
		if fw.is_inside(n): continue
		for e in game.world.screens[number].get("sprites", []):
			if int(e.get("type", 1)) == 2: continue
			if not fw.sprite_drawn(fw.model_key(e)): continue
			var parts: Array = fw.seam_parts(e, n)
			for k in parts.size():
				print("SEAM %d %d %d %d %s" % [n, int(e.get("index", 0)), k, 1 if bool(parts[k][3]) else 0, fw.frame_path(e)])

func _drawn(screen: int) -> void:
	var fw = game.fp_world
	var origin: Vector2 = fw.screen_origin(screen)
	for sp in game.scene_root.find_children("Model", "Sprite3D", true, false):
		var s := sp as Sprite3D
		if s.billboard != BaseMaterial3D.BILLBOARD_FIXED_Y or s.texture == null or not _live(s): continue
		var path := str(s.get_meta("path", ""))
		if not "/trees/" in path.to_lower(): continue
		# The lowest drawn pixel of the sprite's picture, as placed: offset is (w/2 - dx, dy - h/2) from the node.
		var img := s.texture.get_image()
		var low := -1
		for y in range(img.get_height() - 1, -1, -1):
			if not img.get_region(Rect2i(0, y, img.get_width(), 1)).is_invisible():
				low = y
				break
		if low < 0: continue
		var pos := s.global_position
		# A sprite's local +y is up: the bottom edge of texel row r is offset.y + h/2 - r - 1 pixels above the node.
		var foot_px := pos.y / s.pixel_size + s.offset.y + img.get_height() / 2.0 - float(low) - 1.0
		print("DRAWN %d %.1f %.1f %.1f %s" % [screen, pos.x / fw.SCALE + origin.x + 320.0, pos.z / fw.SCALE + origin.y + 200.0, foot_px, path])

# Not part of a scene being freed (a scene built before this one, still in the tree until its queue_free runs).
func _live(node: Node) -> bool:
	while node != null:
		if node.is_queued_for_deletion(): return false
		node = node.get_parent()
	return true
