extends SceneTree

const GAME := preload("res://scripts/fps_game.gd")

var game
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	game.vm.cancel_all()
	game.playing = true
	game.changing = false
	game.ui.close_menu()

	for number in [1, 439]:
		game.load_map(number, false)
		await process_frame
		game.vm.cancel_all()
		var before := _structural_counts()
		check(int(before.models) > 0, "Map %d renders structural models before save" % number)
		check(int(before.bodies) > 0, "Map %d renders structural collision bodies before save" % number)
		var save_path := "user://fps-reload-%d.json" % number
		check(game._save_game(save_path), "Map %d focused save succeeds (scenario setup)" % number)
		for attempt in 2:
			check(game._load_game(save_path), "Map %d focused reload %d succeeds (scenario setup)" % [number, attempt + 1])
			await process_frame
			var after := _structural_counts()
			check(int(after.models) == int(before.models), "Map %d reload %d preserves structural model count" % [number, attempt + 1])
			check(int(after.bodies) == int(before.bodies), "Map %d reload %d preserves structural body count" % [number, attempt + 1])
		DirAccess.remove_absolute(save_path)

	game.vm.cancel_all()
	game.queue_free()
	if failures.is_empty(): print("FPS RELOAD PASS: structural visuals survive repeated save/load")
	else: print("FPS RELOAD FAILURES: ", failures)
	quit(0 if failures.is_empty() else 1)

func _structural_counts() -> Dictionary:
	var result := {"models": 0, "bodies": 0}
	_count_structural(game.scene_root, result)
	return result

func _count_structural(node: Node, result: Dictionary) -> void:
	for child in node.get_children():
		var key := str(child.get_meta("model_key", ""))
		if key in ["cottage", "tower", "wall"] and child.get_node_or_null("Model") != null:
			result.models += 1
			if child.get_node_or_null("HitBody") != null: result.bodies += 1
		_count_structural(child, result)

func check(condition: bool, message: String) -> void:
	if condition: return
	failures.append(message)
	push_error(message)
