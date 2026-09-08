extends SceneTree

const GAME := preload("res://scripts/fps_game.gd")

class ProbeGame extends GAME:
	var attacks := 0
	var casts := 0
	var talks := 0
	var equips: Array[String] = []
	var moved := Vector2.ZERO

	func _fps_attack() -> void:
		attacks += 1

	func _cast() -> void:
		casts += 1

	func _talk() -> void:
		talks += 1

	func _equip(index: int, magic: bool) -> void:
		if not magic: equips.append("%d" % index)
		vm.globals["cur_weapon"] = index + 1

	func _move_entity(id: int, displacement: Vector2, ignore_hardness: bool = false) -> void:
		moved += displacement
		if entities.has(id):
			entities[id]["x"] = float(entities[id].get("x", 0.0)) + displacement.x
			entities[id]["y"] = float(entities[id].get("y", 0.0)) + displacement.y

	func _transitions(_scripted_move: bool = false, _from_position: Vector2 = Vector2.INF) -> void:
		pass

	func _update_ai(_delta: float) -> void:
		pass

var game: ProbeGame
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	game = ProbeGame.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	await game._new_game()
	await process_frame
	game.vm.cancel_all()
	for key in ["controller_deadzone", "controller_sensitivity", "controller_invert_y"]:
		game.settings.erase(key)
	game.playing = true
	game.ui.close_menu()
	game._fps_update_mouse_mode()
	game.set_physics_process(false)

	# A nonzero controller device must match the actions just like device 0.
	check(InputMap.has_action("look_left") and InputMap.has_action("look_right"), "Right-stick look actions are registered")
	check(InputMap.has_action("weapon_previous") and InputMap.has_action("weapon_next"), "Shoulder weapon actions are registered")
	check(is_equal_approx(game._fps_controller_deadzone(), 0.2), "Controller deadzone defaults to 0.2")
	check(is_equal_approx(float(game.settings.get("controller_sensitivity", 2.0)), 2.0), "Controller sensitivity defaults to 2.0")
	check(not bool(game.settings.get("controller_invert_y", false)), "Controller Y is not inverted by default")

	# Stick look applies a rescaled value outside the deadzone and honors the
	# configured sensitivity, deadzone limits, and Y inversion.
	_send_axis(JOY_AXIS_RIGHT_X, 0.10)
	var yaw_before := game.fps_yaw
	game._fps_update_controller_look(1.0)
	check(is_equal_approx(game.fps_yaw, yaw_before), "Right-stick values inside deadzone do not turn")
	_send_axis(JOY_AXIS_RIGHT_Y, 0.0)
	_send_axis(JOY_AXIS_RIGHT_X, 0.60)
	yaw_before = game.fps_yaw
	game._fps_update_controller_look(1.0)
	var normal_turn := yaw_before - game.fps_yaw
	check(is_equal_approx(normal_turn, 1.0), "Right-stick turn uses default sensitivity and deadzone")
	game.settings["controller_sensitivity"] = 99.0
	yaw_before = game.fps_yaw
	game._fps_update_controller_look(1.0)
	check(is_equal_approx(yaw_before - game.fps_yaw, 2.0), "Controller sensitivity clamps to 4.0")
	_send_axis(JOY_AXIS_RIGHT_X, 0.0)
	_send_axis(JOY_AXIS_RIGHT_Y, 0.60)
	game.settings["controller_invert_y"] = false
	var pitch_before := game.fps_pitch
	game._fps_update_controller_look(1.0)
	var normal_pitch := pitch_before - game.fps_pitch
	game.settings["controller_invert_y"] = true
	pitch_before = game.fps_pitch
	game._fps_update_controller_look(1.0)
	check(normal_pitch > 0.0 and game.fps_pitch - pitch_before > 0.0, "Controller Y inversion reverses pitch")
	game.settings["controller_deadzone"] = -1.0
	check(is_equal_approx(game._fps_controller_deadzone(), 0.05), "Controller deadzone clamps to its lower bound")
	game.settings["controller_deadzone"] = 99.0
	check(is_equal_approx(game._fps_controller_deadzone(), 0.4), "Controller deadzone clamps to its upper bound")
	game.settings["controller_deadzone"] = 0.2
	game.settings["controller_sensitivity"] = 2.0
	game.settings["controller_invert_y"] = false
	_send_axis(JOY_AXIS_RIGHT_Y, 0.0)
	_send_axis(JOY_AXIS_RIGHT_X, 1.0)
	yaw_before = game.fps_yaw
	game._fps_update_controller_look(0.25)
	check(is_equal_approx(yaw_before - game.fps_yaw, 0.5), "Controller look scales with elapsed time")
	_send_axis(JOY_AXIS_RIGHT_X, 0.0)

	# Movement preserves analog magnitude after its explicit deadzone.
	game.entities[1]["x"] = 320.0; game.entities[1]["y"] = 200.0
	game.entities[1]["frozen"] = false; game.entities[1]["disabled"] = 0; game.entities[1]["nocontrol"] = 0
	game.attack_cooldown = 0.0
	game.moved = Vector2.ZERO
	_clear_left_stick()
	_send_axis(JOY_AXIS_LEFT_Y, -0.60)
	game._fps_move_player(1.0)
	var partial_distance := game.moved.length()
	game.entities[1]["x"] = 320.0; game.entities[1]["y"] = 200.0
	game.moved = Vector2.ZERO
	_send_axis(JOY_AXIS_LEFT_Y, -1.0)
	game._fps_move_player(1.0)
	var full_distance := game.moved.length()
	check(partial_distance > 0.0 and partial_distance < full_distance and absf(partial_distance / full_distance - 0.5) < 0.08, "Analog movement preserves partial stick magnitude")
	_clear_left_stick()
	await _dispatch_button(JOY_BUTTON_A)
	check(game.talks == 1, "A on a nonzero controller talks during gameplay")
	await _dispatch_button(JOY_BUTTON_BACK)
	check(game.ui.modal and game.ui.page == "inventory", "Back opens equipment on a nonzero controller")
	await _dispatch_button(JOY_BUTTON_B)
	check(not game.ui.modal, "B closes equipment")

	# Shoulder cycling wraps through the actual equipment list and is guarded by menus.
	game.items = [{"script":"item-fst"}, {"script":"item-b1"}, {"script":"item-sw1"}]
	game.vm.globals["cur_weapon"] = 1
	await _dispatch_button(JOY_BUTTON_RIGHT_SHOULDER)
	check(game.equips == ["1"], "Right shoulder equips next weapon once")
	game.vm.globals["cur_weapon"] = 1
	await _dispatch_button(JOY_BUTTON_LEFT_SHOULDER)
	check(game.equips == ["1", "2"], "Left shoulder wraps to the previous weapon")
	game.vm.globals["cur_weapon"] = 3
	await _dispatch_button(JOY_BUTTON_RIGHT_SHOULDER)
	check(game.equips == ["1", "2", "0"], "Right shoulder wraps to the next weapon")
	game.ui.show_pause()
	var equip_count := game.equips.size()
	await _dispatch_button(JOY_BUTTON_RIGHT_SHOULDER)
	check(game.equips.size() == equip_count, "Shoulder buttons do not equip while a menu is open")
	game.ui.close_menu()

	# Start pauses/resumes; B closes menus and has no gameplay pause behavior.
	await _dispatch_button(JOY_BUTTON_B)
	check(not game.ui.modal, "B does not pause during gameplay")
	await _dispatch_button(JOY_BUTTON_START)
	check(game.ui.modal, "Start opens pause menu during gameplay")
	await _dispatch_button(JOY_BUTTON_B)
	check(not game.ui.modal, "B exits the pause menu")

	# Trigger actions are separated from attack/magic and modal input is contained.
	game.attacks = 0; game.casts = 0
	game.ui.show_pause()
	await _pulse_button(JOY_BUTTON_X)
	await _pulse_button(JOY_BUTTON_Y)
	await _pulse_axis(JOY_AXIS_TRIGGER_RIGHT)
	await _pulse_axis(JOY_AXIS_TRIGGER_LEFT)
	check(game.attacks == 0 and game.casts == 0, "Attack and magic buttons do not bleed through menus")
	game.ui.close_menu()
	await _pulse_button(JOY_BUTTON_X)
	await _pulse_button(JOY_BUTTON_Y)
	check(game.attacks == 1 and game.casts == 1, "Attack and magic buttons reach gameplay handlers")
	game.attacks = 0; game.casts = 0
	await _pulse_axis(JOY_AXIS_TRIGGER_RIGHT)
	await _pulse_axis(JOY_AXIS_TRIGGER_LEFT)
	check(game.attacks == 1 and game.casts == 1, "Triggers reach the same gameplay handlers as face buttons")
	game.ui.show_pause()
	await process_frame
	_send_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	game._physics_process(0.016)
	var attack_count := game.attacks
	await _dispatch_button(JOY_BUTTON_START)
	game._physics_process(0.016)
	check(not game.ui.modal and game.attacks == attack_count, "Holding a trigger while resuming does not fire")
	_send_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	game._physics_process(0.016)
	await _pulse_axis(JOY_AXIS_TRIGGER_RIGHT)
	check(game.attacks == attack_count + 1, "Trigger fires again after release and a fresh press")

	game.queue_free()
	await process_frame
	if failures.is_empty(): print("FPS CONTROLLER PASS: look, movement, equipment, modal guards, actions")
	else: print("FPS CONTROLLER FAILURES: ", failures)
	quit(0 if failures.is_empty() else 1)

func _button(button: int) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = 3
	event.button_index = button
	event.pressed = true
	return event

func _send_button(button: int, pressed: bool) -> void:
	var event := _button(button)
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _dispatch_button(button: int) -> void:
	_send_button(button, true)
	await process_frame
	_send_button(button, false)
	await process_frame

func _pulse_button(button: int) -> void:
	_send_button(button, true)
	await process_frame
	game._physics_process(0.016)
	_send_button(button, false)
	await process_frame
	game._physics_process(0.016)

func _pulse_axis(axis: int) -> void:
	_send_axis(axis, 1.0)
	await process_frame
	game._physics_process(0.016)
	_send_axis(axis, 0.0)
	await process_frame
	game._physics_process(0.016)

func _send_axis(axis: int, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 3
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _clear_left_stick() -> void:
	_send_axis(JOY_AXIS_LEFT_X, 0.0)
	_send_axis(JOY_AXIS_LEFT_Y, 0.0)
