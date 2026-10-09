extends SceneTree
# A speaker in dialogue shows a frame facing the camera (RC1 review: Mother showed her back through the opening dialogue).
# Also pinned: Mother and the pigs turn with the camera (the review's 'pigs side-on from every side' was the art: pigs have
# only the four diagonal walks, each a three-quarter profile). Scenario setup: each screen loaded with its scripts off.
const GAME = preload("res://scripts/fps_game.gd")
var failures: Array = []
func _initialize() -> void:
	_run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
	print(("ok   " if ok else "FAIL ") + message)
func _frame_seen(game, id: int, from: Vector2) -> String:
	var e: Dictionary = game.entities[id]
	game.entities[1].x = float(e.x) + from.x
	game.entities[1].y = float(e.y) + from.y
	game.fps_yaw = atan2(from.x, from.y)
	game._sync_fps_camera()
	game._update_visual(id)
	var sp = game.visuals[id].get_node_or_null("Model")
	return str(sp.get_meta("path", "")) if sp != null else ""
func _run() -> void:
	var game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	await game._new_game()
	await create_timer(0.5).timeout
	game.vm.cancel_all()
	game.playing = false
	game.ui.close_menu()
	game.load_map(1, false)
	await create_timer(0.3).timeout
	game.set_process(false)
	game.set_physics_process(false)
	var mom := -1
	for id in game.entities:
		if str(game.entities[id].get("script", "")).to_lower() == "s1-h1-m": mom = id
	check(mom > 0, "Mother is on screen 1")
	var ring := [Vector2(90, 0), Vector2(0, 90), Vector2(-90, 0), Vector2(0, -90)]
	var seen := {}
	for r in ring: seen[_frame_seen(game, mom, r)] = true
	print("MOTHER frames ", seen.keys())
	check(seen.size() >= 2, "Mother's frame turns with the camera (%d frames from 4 sides)" % seen.size())
	game.visuals[mom].set_meta("face_camera", true)
	for r in ring:
		var p := _frame_seen(game, mom, r)
		check("c08w1" in p or "c08w3" in p, "Speaking, Mother faces the camera from %s (frame %s)" % [r, p.get_file()])
	game.visuals[mom].remove_meta("face_camera")
	game.load_map(407, false)
	await create_timer(0.3).timeout
	var pigs: Array = []
	for id in game.entities:
		if "/pig/" in game.fp_world.source_path(game.entities[id]).to_lower(): pigs.append(id)
	check(pigs.size() >= 4, "The pen has its pigs")
	if not pigs.is_empty():
		var pseen := {}
		for r in ring: pseen[_frame_seen(game, pigs[0], r)] = true
		print("PIG frames ", pseen.keys())
		check(pseen.size() >= 2, "A pig's frame turns with the camera (%d frames from 4 sides)" % pseen.size())
	if failures.is_empty(): print("FPS FACING PASS")
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
