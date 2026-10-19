# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
# Registry class check: physical axis events activate and release every binding.
extends SceneTree
const B = preload("res://scripts/input_bindings.gd")
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var rows := 0
	for mode in ["2d","fps"]:
		var bindings = B.new(mode)
		bindings.install()
		for action in bindings.actions:
			if bindings.scope_for(action) == "menu" and mode == "2d": continue
			for record in bindings.events(action):
				if record.type != "axis": continue
				var event = bindings.to_event(record)
				event.device = 3
				Input.parse_input_event(event); Input.flush_buffered_events()
				check(Input.is_action_pressed(action) and Input.get_action_strength(action) > 0.0, mode+"/"+action+" axis activates")
				var deadzone := InputMap.action_get_deadzone(action)
				event = event.duplicate(); event.axis_value = float(record.direction)*deadzone*0.5
				Input.parse_input_event(event); Input.flush_buffered_events()
				check(not Input.is_action_pressed(action) and is_zero_approx(Input.get_action_strength(action)), mode+"/"+action+" releases inside deadzone")
				event = event.duplicate(); event.axis_value = float(record.direction)
				Input.parse_input_event(event); Input.flush_buffered_events()
				event = event.duplicate(); event.axis_value = 0.0
				Input.parse_input_event(event); Input.flush_buffered_events()
				check(not Input.is_action_pressed(action) and is_zero_approx(Input.get_action_strength(action)), mode+"/"+action+" releases at neutral")
				rows += 1
	check(rows == 20,"All twenty default axis/action/context rows are exercised")
	print("AXIS_ROWS=",rows)
	print("AXIS NEUTRAL PASS" if failures.is_empty() else "AXIS NEUTRAL FAIL")
	quit(0 if failures.is_empty() else 1)
