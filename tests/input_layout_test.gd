extends SceneTree
const BINDINGS = preload("res://scripts/input_bindings.gd")
const UI = preload("res://scripts/game_ui.gd")
func _init() -> void: _run.call_deferred()
func _run() -> void:
	var b := BINDINGS.new()
	var output: Array = []
	var error := OS.execute("setxkbmap",["-layout","us,de"],output,true)
	if error != 0:
		push_error("Xvfb layout setup failed: "+str(output));quit(1);return
	for i in 4: await process_frame
	var count := DisplayServer.keyboard_get_layout_count()
	print("LAYOUT_COUNT="+str(count))
	if count < 2:
		push_error("Xvfb did not expose both layouts");quit(1);return
	b.load_settings()
	if not b.set_bindings("talk",[b.key(KEY_Y)]).ok:
		push_error("Layout test cannot bind Y");quit(1);return
	var ui := UI.new()
	ui.bindings = b
	root.add_child(ui)
	ui.show_title(false)
	var labels: Array[String] = []
	for index in [0,1]:
		DisplayServer.keyboard_set_current_layout(index)
		for i in 4: await process_frame
		labels.append(b.event_label(b.key(KEY_Y)))
		var input := InputEventKey.new()
		input.physical_keycode = KEY_Y
		input.keycode = KEY_Y if index == 0 else KEY_Z
		input.pressed = true
		Input.parse_input_event(input)
		await process_frame
		input.pressed = false
		Input.parse_input_event(input)
		await process_frame
		if not ui.control_primer_label.text.contains(labels[-1]+" talk"):
			push_error("Existing title primer did not refresh its keyboard layout");quit(1);return
	print("LAYOUT_LABELS="+str(labels))
	if labels[0] != "Y" or labels[1] != "Z":
		push_error("Physical key Y does not follow the active US/German layout");quit(1);return
	ui.show_settings({})
	if not ui.controls_label.text.contains("Talk / examine: Z"):
		push_error("Settings controls do not use German label");quit(1);return
	print("INPUT LAYOUT PASS")
	quit()
