extends SceneTree

const GAME := preload("res://scripts/fps_game.gd")

var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	check(game.fp_world != null, "FPS renderer initializes")

	var numbers: Array[int] = []
	for key in game.world.screens.keys(): numbers.append(int(key))
	numbers.sort()
	for number in numbers:
		game.vm.cancel_all()
		game.load_map(number, false)
		check(not game.scene_root.get_children().is_empty(), "Screen %d builds a nonempty floor scene" % number)
		check(not _contains_sprite3d(game.scene_root), "Screen %d contains no Sprite3D" % number)
		check(_mesh_count(game.scene_root) > 0, "Screen %d contains 3D geometry" % number)
		check(game.vm._live_tasks.is_empty(), "Screen %d leaves no script tasks" % number)
		await process_frame

	game.vm.cancel_all()
	check(game.vm._live_tasks.is_empty(), "Renderer traversal ends with scripts canceled")
	game.queue_free()
	await process_frame
	if failures.is_empty(): print("FPS WORLD PASS: traversed %d screens" % numbers.size())
	else: print("FPS WORLD FAILURES: ", failures)
	quit(0 if failures.is_empty() else 1)

func _contains_sprite3d(node: Node) -> bool:
	for child in node.get_children():
		if child is Sprite3D or _contains_sprite3d(child): return true
	return false

func _mesh_count(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		if child is MeshInstance3D or child is MultiMeshInstance3D: count += 1
		count += _mesh_count(child)
	return count
