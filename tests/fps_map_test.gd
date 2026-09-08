extends SceneTree

const GAME := preload("res://scripts/fps_game.gd")
var game
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func key(code: Key, echo_press: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	event.echo = echo_press
	Input.parse_input_event(event)
	await process_frame
	event = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func _run() -> void:
	game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	await game._new_game()
	game.vm.cancel_all()
	game.load_map(439, false)
	game.set_physics_process(false)
	game.playing = true
	game.ui.close_menu()
	game.entities[1]["frozen"] = false
	game.test_mode = false
	# Explicit ownership fixture: input still runs the original BUTTON6 script.
	game.vm.globals["s2-map"] = 0
	await key(KEY_M)
	check(not game.ui.modal and game.ui.toast.text == "I don't own a map yet.", "M before the invitation uses the original missing-map response")
	game.vm.globals["s2-map"] = 1
	game.entities[1]["frozen"] = true
	await key(KEY_M)
	check(not game.ui.modal, "M cannot interrupt frozen story movement")
	game.entities[1]["frozen"] = false
	game.entities[1]["nocontrol"] = 1
	await key(KEY_M)
	check(not game.ui.modal, "M respects script control inhibition")
	game.entities[1]["nocontrol"] = 0
	await key(KEY_M)
	check(game.ui.page == "map" and game.ui.modal, "M after ownership opens the world map")
	var artwork := false
	for child in game.ui.column.get_children():
		if child is TextureRect and child.texture != null:
			artwork = child.texture.resource_path == "res://assets/tiles/map1.png"
	check(artwork, "World map contains the original enclosed map artwork")
	var position: Vector2 = game._position2(1)
	Input.action_press("up")
	game._physics_process(0.1)
	Input.action_release("up")
	check(game._position2(1).is_equal_approx(position), "Map blocks player movement")
	await key(KEY_M, true)
	check(game.ui.page == "map", "Key repeat does not immediately close the map")
	await key(KEY_M)
	check(not game.ui.modal, "A second M press closes the map")
	await key(KEY_ESCAPE)
	check(game.ui.page == "pause", "Pause remains available")
	var map_button: Button
	for child in game.ui.column.get_children():
		if child is Button and child.text == "World map": map_button = child
	check(map_button != null, "Pause offers controller-accessible World map")
	if map_button != null:
		map_button.grab_focus()
		await key(KEY_ENTER)
		check(game.ui.page == "map", "Focused pause map button opens the original map")
		await key(KEY_ESCAPE)
		check(not game.ui.modal, "Escape closes the map")
	game.ui.show_inventory(game.items, game.magic_items)
	await key(KEY_M)
	check(game.ui.page == "inventory", "M does not replace another modal menu")
	if failures.is_empty(): print("FPS MAP PASS")
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
