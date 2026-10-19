# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
# Local, short-lived gameplay evidence. The owner calls record_input only while
# the game is playing and its UI is not modal.
extends RefCounted

const WINDOW_USEC := 10_000_000
const MAX_EVENTS := 8192
const BINDINGS = preload("res://scripts/input_bindings.gd")
var bindings = BINDINGS.new()

# A test can supply a monotonic clock without waiting ten real seconds.
var clock_usec: Callable
var screenshot_provider: Callable
var _events: Array[Dictionary] = []
var _dropped_for_cap := 0
var _serial := 0

func _now_usec() -> int:
	return int(clock_usec.call()) if clock_usec.is_valid() else Time.get_ticks_usec()

func _is_gameplay_binding(event: InputEvent) -> bool:
	for action in bindings.gameplay_actions():
		if InputMap.has_action(action) and event.is_action(action):
			return true
	return false

func _encode(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		# Record only named gameplay actions; never Unicode or unrelated text.
		if event.is_action("bug_report") or not _is_gameplay_binding(event): return {}
		var physical := int(event.physical_keycode)
		var logical := int(event.keycode)
		return {"type":"key", "physical":physical, "logical":logical,
			"pressed":event.pressed, "echo":event.echo,
			"shift":event.shift_pressed, "ctrl":event.ctrl_pressed,
			"alt":event.alt_pressed, "meta":event.meta_pressed}
	if event is InputEventMouseMotion:
		return {"type":"mouse_motion", "dx":event.relative.x, "dy":event.relative.y}
	if event is InputEventMouseButton:
		if not _is_gameplay_binding(event): return {}
		return {"type":"mouse_button", "button":event.button_index, "pressed":event.pressed}
	if event is InputEventJoypadButton:
		if not _is_gameplay_binding(event): return {}
		return {"type":"joy_button", "button":event.button_index, "pressed":event.pressed}
	if event is InputEventJoypadMotion:
		if not _is_gameplay_binding(event): return {}
		return {"type":"joy_axis", "axis":event.axis, "value":event.axis_value}
	return {}

func record_input(event: InputEvent) -> void:
	var encoded := _encode(event)
	if encoded.is_empty(): return
	var now := _now_usec()
	encoded["at_usec"] = now
	_events.append(encoded)
	_prune(now)

func _prune(now: int) -> void:
	while not _events.is_empty() and int(_events[0].at_usec) < now - WINDOW_USEC:
		_events.pop_front()
	while _events.size() > MAX_EVENTS:
		_events.pop_front()
		_dropped_for_cap += 1

func _report_events(now: int) -> Array[Dictionary]:
	_prune(now)
	var result: Array[Dictionary] = []
	for original in _events:
		var event := original.duplicate()
		event["t_ms"] = (int(event.at_usec) - now) / 1000.0
		event.erase("at_usec")
		result.append(event)
	return result

# The replay harness can feed these events through Input.parse_input_event().
# The report omits device names and text; controller events target device 0.
static func to_input_event(record: Dictionary) -> InputEvent:
	var event: InputEvent
	match str(record.get("type", "")):
		"key":
			var key := InputEventKey.new()
			key.physical_keycode = int(record.get("physical", 0))
			key.keycode = int(record.get("logical", 0))
			key.pressed = bool(record.get("pressed", false))
			key.echo = bool(record.get("echo", false))
			key.shift_pressed = bool(record.get("shift", false))
			key.ctrl_pressed = bool(record.get("ctrl", false))
			key.alt_pressed = bool(record.get("alt", false))
			key.meta_pressed = bool(record.get("meta", false))
			event = key
		"mouse_motion":
			var motion := InputEventMouseMotion.new()
			motion.relative = Vector2(float(record.get("dx", 0)), float(record.get("dy", 0)))
			event = motion
		"mouse_button":
			var mouse := InputEventMouseButton.new()
			mouse.button_index = int(record.get("button", 0))
			mouse.pressed = bool(record.get("pressed", false))
			event = mouse
		"joy_button":
			var button := InputEventJoypadButton.new()
			button.device = 0
			button.button_index = int(record.get("button", 0))
			button.pressed = bool(record.get("pressed", false))
			event = button
		"joy_axis":
			var axis := InputEventJoypadMotion.new()
			axis.device = 0
			axis.axis = int(record.get("axis", 0))
			axis.axis_value = float(record.get("value", 0))
			event = axis
	return event

static func _script_hash(path: String) -> String:
	if FileAccess.file_exists(path): return FileAccess.get_sha256(path)
	# Release exports compile .gd to .gdc; fingerprint that shipped resource.
	var remap := ConfigFile.new()
	if remap.load(path+".remap") == OK:
		var packed := str(remap.get_value("remap","path",""))
		if FileAccess.file_exists(packed): return FileAccess.get_sha256(packed)
	return "unavailable"

func write_report(game: Node) -> String:
	if not game.entities.has(1) or game.vm == null: return ""
	var screenshot: Image
	if screenshot_provider.is_valid():
		screenshot = screenshot_provider.call()
	else:
		var viewport := game.get_viewport()
		if viewport == null or viewport.get_texture() == null: return ""
		screenshot = viewport.get_texture().get_image()
	if screenshot == null or screenshot.is_empty(): return ""
	var directory := "user://bug_reports"
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) != OK: return ""
	var stem := "report-%s-%d-%d" % [Time.get_datetime_string_from_system(true).replace(":", "-"), Time.get_ticks_usec(), _serial]
	_serial += 1
	var json_path := "%s/%s.json" % [directory, stem]
	var image_path := "%s/%s.png" % [directory, stem]
	while FileAccess.file_exists(json_path) or FileAccess.file_exists(image_path):
		stem += "-1"
		json_path = "%s/%s.json" % [directory, stem]
		image_path = "%s/%s.png" % [directory, stem]
	if screenshot.save_png(image_path) != OK: return ""
	var player: Dictionary = game.entities[1]
	var now := _now_usec()
	var data := {
		"schema":1,
		"captured_utc":Time.get_datetime_string_from_system(true),
		"screenshot":image_path.get_file(),
		"build":{"name":str(ProjectSettings.get_setting("application/config/name", "")),
			"version":str(ProjectSettings.get_setting("application/config/version", "")),
			"godot":Engine.get_version_info().get("string", ""), "platform":OS.get_name(),
			"fps_script_sha256":_script_hash("res://scripts/fps_game.gd"),
			"renderer_script_sha256":_script_hash("res://scripts/fp_world.gd")},
		"snapshot":{"screen":int(game.current_screen),
			"player":{"x":float(player.get("x", 0)), "y":float(player.get("y", 0)), "dir":int(player.get("dir", 0))},
			"camera":{"yaw":float(game.fps_yaw), "pitch":float(game.fps_pitch)},
			"globals":game.vm.globals.duplicate(true),
			"entities":game.entities.duplicate(true),
			"editor_state":game.editor_state.duplicate(true) if "editor_state" in game else {},
			"items":game.items.duplicate(true) if "items" in game else [],
			"magic_items":game.magic_items.duplicate(true) if "magic_items" in game else [],
			"ui_page":game.ui.page if "ui" in game and game.ui != null else "unknown",
			"settings":game.settings.duplicate(true) if "settings" in game else {},
			"next_entity":game.next_entity if "next_entity" in game else 2,
			"locked":game.locked if "locked" in game else false},
		"input":{"window_seconds":10, "events":_report_events(now), "dropped_for_cap":_dropped_for_cap},
		"limitations":"Current state and preceding input do not constitute an exact historical full-save or NPC-task replay. Events captured before this ten-second window and any in-progress script state are absent."
	}
	var file := FileAccess.open(json_path, FileAccess.WRITE)
	if file == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(image_path))
		return ""
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return json_path
