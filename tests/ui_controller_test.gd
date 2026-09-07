extends SceneTree

const UI = preload("res://scripts/game_ui.gd")
var received := ""

func _init() -> void:
	var ui := UI.new()
	root.add_child(ui)
	ui.action_requested.connect(_on_action)
	await process_frame
	ui.show_title(false)
	await process_frame
	ui.set_text_scale(1.3)
	assert(ui.root.scale == Vector2.ONE)
	assert(ui.root.get_viewport().gui_get_focus_owner() != null)
	var down := InputEventJoypadMotion.new()
	down.axis = JOY_AXIS_LEFT_Y
	down.axis_value = 1.0
	Input.parse_input_event(down)
	await process_frame
	var neutral := InputEventJoypadMotion.new()
	neutral.axis = JOY_AXIS_LEFT_Y
	neutral.axis_value = 0.0
	Input.parse_input_event(neutral)
	await process_frame
	var accept := InputEventJoypadButton.new()
	accept.button_index = JOY_BUTTON_A
	accept.pressed = true
	Input.parse_input_event(accept)
	await process_frame
	accept.pressed = false
	Input.parse_input_event(accept)
	await process_frame
	assert(received == "settings")
	quit()

func _on_action(action: String, _payload: Variant) -> void:
	received = action
