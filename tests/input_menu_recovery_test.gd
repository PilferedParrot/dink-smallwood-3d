# Essential menu bindings must keep keyboard and pad routes through edits and restarts.
# The two-button Reset surface below exists only in this test harness; P3a has no
# shipping reset UI. Navigation and activation still travel through Godot's GUI.
extends SceneTree

const ESSENTIAL := ["ui_up", "ui_down", "ui_left", "ui_right", "ui_accept", "ui_cancel"]
const PAD_REMAP := [JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_LEFT_SHOULDER,
	JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_LEFT_STICK, JOY_BUTTON_RIGHT_STICK]
class CancelObserver:
	extends Node
	var back_seen := false
	func _unhandled_input(event: InputEvent) -> void:
		if event.is_action_pressed("ui_cancel"): back_seen = true
var registry_script: GDScript = preload("res://scripts/input_bindings.gd")
var phase := "class"
var device := "keyboard"
var failures: Array[String] = []
var binding
var reset_pressed := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="): phase = arg.trim_prefix("--phase=")
		if arg.begins_with("--device="): device = arg.trim_prefix("--device=")
		if arg.begins_with("--registry="): registry_script = load(arg.trim_prefix("--registry="))
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
		push_error(description)

func family(record: Dictionary) -> String:
	return "keyboard" if record.type == "key" else ("pad" if record.type in ["pad", "axis"] else "other")

func invariant(action: String) -> bool:
	var keyboard := false
	var pad := false
	for record in binding.events(action):
		keyboard = keyboard or family(record) == "keyboard"
		pad = pad or family(record) == "pad"
	return keyboard and pad

func stable_refusal(action: String, result: Dictionary, expected_device: String, label: String) -> void:
	check(not result.get("ok", false) and result.get("error", "") == "menu_device_required"
		and result.get("action", "") == action and result.get("device", "") == expected_device, label+" error contract")

func attempt_whole_list(action: String, records: Array, missing: String, label: String) -> void:
	var before_events: Array = binding.events(action)
	var before_bytes := FileAccess.get_file_as_string(binding.settings_path)
	var before_live: Array = InputMap.action_get_events(action)
	var result: Dictionary = binding.set_bindings(action, records)
	stable_refusal(action, result, missing, label)
	check(binding.events(action) == before_events, label+" keeps registry")
	check(FileAccess.get_file_as_string(binding.settings_path) == before_bytes, label+" keeps file bytes")
	check(InputMap.action_get_events(action) == before_live, label+" keeps live InputMap")

func class_cases() -> void:
	binding = registry_script.new("fps", "user://menu-class.json")
	check(binding.reset_all().get("ok", false), "initial reset")
	for action in ESSENTIAL:
		var original: Array = binding.defaults(action)
		var keys: Array = original.filter(func(record: Dictionary): return family(record) == "keyboard")
		var pads: Array = original.filter(func(record: Dictionary): return family(record) == "pad")
		attempt_whole_list(action, keys, "pad", action+" keyboard-only whole list")
		attempt_whole_list(action, pads, "keyboard", action+" pad-only whole list")
		attempt_whole_list(action, [], "keyboard", action+" empty whole list")
		check(invariant(action), action+" retains both families")
		if not binding.has_method("add_binding") or not binding.has_method("replace_binding") or not binding.has_method("remove_binding"):
			check(false, "per-slot binding API exists")
			return
		# Start from one event of each family, then run a deterministic edit sequence.
		check(binding.set_bindings(action, [keys[0], pads[0]]).get("ok", false), action+" minimal mixed list")
		var extra: Dictionary = registry_script.key(KEY_F13 + ESSENTIAL.find(action))
		check(binding.add_binding(action, extra).get("ok", false), action+" add keyboard slot")
		check(binding.events(action).size() == 3 and invariant(action), action+" add preserves slots")
		var swapped: Dictionary = registry_script.key(KEY_F19 + ESSENTIAL.find(action))
		check(binding.replace_binding(action, 2, swapped).get("ok", false), action+" replace keyboard slot")
		check(binding.events(action)[2] == swapped and invariant(action), action+" replacement is localized")
		var before: Array = binding.events(action)
		var bytes := FileAccess.get_file_as_string(binding.settings_path)
		var live: Array = InputMap.action_get_events(action)
		stable_refusal(action, binding.remove_binding(action, 1), "pad", action+" remove last pad")
		check(binding.events(action) == before and FileAccess.get_file_as_string(binding.settings_path) == bytes
			and InputMap.action_get_events(action) == live, action+" failed pad removal transactional")
		stable_refusal(action, binding.replace_binding(action, 1, swapped), "pad", action+" replace last pad")
		check(binding.remove_binding(action, 2).get("ok", false), action+" remove redundant keyboard")
		before = binding.events(action)
		bytes = FileAccess.get_file_as_string(binding.settings_path)
		live = InputMap.action_get_events(action)
		stable_refusal(action, binding.remove_binding(action, 0), "keyboard", action+" remove last keyboard")
		check(binding.events(action) == before and FileAccess.get_file_as_string(binding.settings_path) == bytes
			and InputMap.action_get_events(action) == live, action+" failed keyboard removal transactional")
		stable_refusal(action, binding.replace_binding(action, 0, pads[0]), "keyboard", action+" replace last keyboard")
		check(binding.reset_action(action).get("ok", false), action+" action reset")
		check(binding.events(action) == original and invariant(action), action+" reset restores both devices")
	var reloaded = registry_script.new("fps", binding.settings_path)
	reloaded.load_settings()
	for action in ESSENTIAL:
		check(reloaded.events(action) == reloaded.defaults(action), action+" reset persisted")
	# Fixed seed covers mixed sequences of slot edits, failed last-family
	# removals, resets and reloading without relying on one hand-picked path.
	var random := RandomNumberGenerator.new()
	random.seed = 0x1F1A2026
	for step in range(48):
		var action: String = ESSENTIAL[random.randi_range(0, ESSENTIAL.size()-1)]
		var action_index := ESSENTIAL.find(action)
		var current: Array = binding.events(action)
		var extra_key: Dictionary = registry_script.key(KEY_F13 + action_index)
		var extra_pad: Dictionary = registry_script.pad(PAD_REMAP[action_index])
		var operation := random.randi_range(0, 5)
		var result: Dictionary
		match operation:
			0:
				result = binding.add_binding(action, extra_key) if not current.has(extra_key) else binding.reset_action(action)
			1:
				result = binding.add_binding(action, extra_pad) if not current.has(extra_pad) else binding.reset_action(action)
			2:
				var key_index := -1
				for i in range(current.size()):
					if family(current[i]) == "keyboard": key_index = i; break
				result = binding.replace_binding(action, key_index, extra_key)
			3:
				var pad_index := -1
				for i in range(current.size()):
					if family(current[i]) == "pad": pad_index = i; break
				result = binding.replace_binding(action, pad_index, extra_pad)
			4:
				var slot := random.randi_range(0, current.size()-1)
				var target_family := family(current[slot])
				var count := 0
				for record in current:
					if family(record) == target_family: count += 1
				result = binding.remove_binding(action, slot)
				if count == 1: stable_refusal(action, result, target_family, "seeded step %d" % step)
				else: check(result.get("ok", false), "seeded step %d removes redundant slot" % step)
			5: result = binding.reset_action(action)
		if operation != 4:
			check(result.get("ok", false), "seeded step %d edit succeeds" % step)
		for id in ESSENTIAL: check(invariant(id), "seeded step %d retains %s device families" % [step,id])
		reloaded.load_settings()
		for id in ESSENTIAL:
			check(reloaded.events(id) == binding.events(id), "seeded step %d reloads %s" % [step,id])
	# A malformed persisted action is healed independently of its healthy neighbors.
	var forged := {"version": 1, "contexts": {"menu": {"ui_down": [registry_script.key(KEY_F13)],
		"ui_accept": [registry_script.pad(JOY_BUTTON_A)], "ui_left": [],
		"ui_right": [registry_script.mouse(MOUSE_BUTTON_LEFT)]}}}
	var file := FileAccess.open(binding.settings_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"bindings_v1": forged}))
	file.close()
	reloaded.load_settings()
	for action in ["ui_down", "ui_accept", "ui_left", "ui_right"]:
		check(reloaded.events(action) == reloaded.defaults(action), action+" invalid loaded override heals to defaults")
	check(reloaded.warnings.size() >= 4, "each invalid persisted essential action warns")
	check(binding.reset_all().get("ok", false), "final reset all")
	for action in ESSENTIAL: check(invariant(action), action+" reset all preserves both families")

func prepare() -> void:
	binding = registry_script.new("fps", "user://menu-native.json")
	check(binding.reset_all().get("ok", false), "prepare reset")
	for action in ESSENTIAL:
		var index := ESSENTIAL.find(action)
		var altered: Array = [registry_script.key(KEY_F13 + index), registry_script.pad(PAD_REMAP[index])]
		check(binding.set_bindings(action, altered).get("ok", false), action+" remap keyboard while retaining pad")
		check(invariant(action), action+" prepared both families")

func event_for(action: String) -> Dictionary:
	for record in binding.events(action):
		if family(record) == device: return record
	return {}

func press(action: String) -> void:
	var record := event_for(action)
	check(not record.is_empty(), device+" has "+action)
	if record.is_empty(): return
	var event: InputEvent = registry_script.to_event(record)
	if event is InputEventKey: event.keycode = event.physical_keycode
	if event is InputEventJoypadButton or event is InputEventJoypadMotion: event.device = 3
	if event is InputEventJoypadMotion: event.axis_value = float(record.direction)
	else: event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	var released: InputEvent = event.duplicate()
	if released is InputEventJoypadMotion: released.axis_value = 0.0
	else: released.pressed = false
	Input.parse_input_event(released)
	await process_frame

func native_recover() -> void:
	binding = registry_script.new("fps", "user://menu-native.json")
	binding.load_settings()
	binding.install()
	for action in ESSENTIAL:
		check(invariant(action), action+" survives process restart")
		var actual := event_for(action)
		if device == "keyboard": check(actual == registry_script.key(KEY_F13 + ESSENTIAL.find(action)), action+" custom keyboard survives restart")
		else: check(actual == registry_script.pad(PAD_REMAP[ESSENTIAL.find(action)]), action+" custom pad survives restart")
	root.size = Vector2i(800, 600)
	var back := CancelObserver.new()
	root.add_child(back)
	var canvas := Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(canvas)
	var column := GridContainer.new()
	column.columns = 2
	column.position = Vector2(80, 80)
	column.custom_minimum_size = Vector2(480, 150)
	canvas.add_child(column)
	var first := Button.new()
	first.text = "Continue"
	first.focus_mode = Control.FOCUS_ALL
	column.add_child(first)
	var right := Button.new()
	right.text = "Details"
	right.focus_mode = Control.FOCUS_ALL
	column.add_child(right)
	var reset := Button.new()
	reset.text = "Reset bindings (harness only)"
	reset.focus_mode = Control.FOCUS_ALL
	column.add_child(reset)
	var other := Button.new()
	other.text = "Other"
	other.focus_mode = Control.FOCUS_ALL
	column.add_child(other)
	reset.pressed.connect(func(): reset_pressed = true; binding.reset_all())
	await process_frame
	first.grab_focus()
	await process_frame
	check(root.gui_get_focus_owner() == first, "native menu starts on Continue")
	await press("ui_right")
	check(root.gui_get_focus_owner() == right, device+" native focus travels right")
	await press("ui_left")
	check(root.gui_get_focus_owner() == first, device+" native focus travels left")
	await press("ui_down")
	check(root.gui_get_focus_owner() == reset, device+" native focus reaches Reset")
	await press("ui_up")
	check(root.gui_get_focus_owner() == first, device+" native focus travels back up")
	await press("ui_down")
	check(root.gui_get_focus_owner() == reset, device+" native focus returns to Reset")
	await press("ui_cancel")
	check(back.back_seen, device+" native cancel reaches harness back endpoint")
	await press("ui_accept")
	check(reset_pressed, device+" native confirmation activates Reset")
	for action in ESSENTIAL:
		check(binding.events(action) == binding.defaults(action), action+" reset from native UI")

func verify() -> void:
	binding = registry_script.new("fps", "user://menu-native.json")
	binding.load_settings()
	for action in ESSENTIAL:
		check(binding.events(action) == binding.defaults(action), action+" native reset persisted")
		check(invariant(action), action+" default has both devices")

func _run() -> void:
	match phase:
		"class": class_cases()
		"prepare": prepare()
		"recover": await native_recover()
		"verify": verify()
		_: check(false, "unknown phase "+phase)
	if failures.is_empty(): print("MENU RECOVERY PASS "+phase+" "+device)
	else: print("MENU RECOVERY FAIL "+phase+" "+device+" count="+str(failures.size()))
	quit(0 if failures.is_empty() else 1)
