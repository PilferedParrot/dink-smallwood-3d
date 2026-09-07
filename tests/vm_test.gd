extends SceneTree

const DinkVM = preload("res://scripts/dink_vm.gd")

var failures: Array[String] = []
var cancelled_finished := false


class Host:
	extends RefCounted
	var tree: SceneTree
	var calls: Array = []

	func _init(p_tree: SceneTree) -> void:
		tree = p_tree

	func dink_call(command: String, args: Array, context: Dictionary) -> Variant:
		calls.append({"command": command, "args": args.duplicate(true), "sprite_id": context["sprite_id"]})
		if command == "choice":
			return args[1][0]["value"]
		if command == "block":
			await tree.process_frame
			await tree.process_frame
		return 0


func literal(value: Variant) -> Dictionary:
	return {"kind": "literal", "value": value}


func ref(name: String) -> Dictionary:
	return {"kind": "ref", "name": name}


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _initialize() -> void:
	call_deferred("run_regressions")


func run_cancel(vm: DinkVM) -> void:
	await vm.run("test", "cancel", 3)
	cancelled_finished = true


func run_persistent(vm: DinkVM, procedure: String, sprite_id: int) -> void:
	await vm.run("test", procedure, sprite_id)


func _has_record(calls: Array, expected_sprite: int) -> bool:
	for call in calls:
		if call["command"] == "record" and call["sprite_id"] == expected_sprite and call["args"][0] == expected_sprite:
			return true
	return false


func _has_context(calls: Array, command: String, expected_sprite: int) -> bool:
	for call in calls:
		if call["command"] == command and call["sprite_id"] == expected_sprite:
			return true
	return false


func run_regressions() -> void:
	var host := Host.new(self)
	var vm := DinkVM.new(host)
	var story := {"scripts": {"test": {"procedures": {
		"nested": {"code": [
			{"op": "set", "target": "&copied", "expr": ref("&current_sprite"), "declare": "int"},
			{"op": "if", "condition": literal(true), "then": [
				{"op": "label", "name": "inside"},
				{"op": "call", "name": "record", "args": [ref("&current_sprite")]},
				{"op": "goto", "label": "done"}
			], "else": [{"op": "call", "name": "record", "args": [literal(99)]}]},
			{"op": "call", "name": "record", "args": [literal(0)]},
			{"op": "label", "name": "done"},
			{"op": "set", "target": "&copied_result", "expr": ref("&copied")}
		]},
		"loop": {"code": [
			{"op": "label", "name": "loop"},
			{"op": "inc", "target": "&count", "value": literal(1)},
			{"op": "if", "condition": {"kind": "binary", "op": "<", "left": ref("&count"), "right": literal(3)}, "then": [{"op": "goto", "label": "loop"}], "else": []}
		]},
		"choice_test": {"code": [
			{"op": "choice_start"},
			{"op": "choice_option", "text": "hidden", "result": 1, "condition": literal(false)},
			{"op": "choice_option", "text": "shown", "result": 2, "condition": literal(true)},
			{"op": "choice_end"},
			{"op": "set", "target": "&choice_value", "expr": ref("&result")}
		]},
		"snapshot": {"code": [
			{"op": "set", "target": "&local_value", "expr": literal(9), "declare": "int"},
			{"op": "set", "target": "&save_value", "expr": literal(7)}
		]},
		"cancel": {"code": [
			{"op": "call", "name": "block", "args": []},
			{"op": "set", "target": "&after_cancel", "expr": literal(1)}
		]},
		"transient": {"code": [
			{"op": "call", "name": "block", "args": []},
			{"op": "call", "name": "record", "args": [ref("&current_sprite")]}
		]},
		"persistent": {"code": [
			{"op": "call", "name": "script_attach", "args": [literal(1000)]},
			{"op": "call", "name": "external", "args": [literal("child"), literal("main")]},
			{"op": "call", "name": "block", "args": []},
			{"op": "call", "name": "record", "args": [ref("&current_sprite")]}
		]},
		"kill": {"code": [
			{"op": "call", "name": "kill_this_task", "args": []},
			{"op": "set", "target": "&after_kill", "expr": literal(1)}
		]}
	}}}}
	check(vm.load_story(story), "story loads")
	await vm.run("test", "nested", 42)
	check(_has_record(host.calls, 42), "nested goto retains current_sprite")
	check(vm.globals.get("copied_result") == 42, "current_sprite copies into a local")
	await vm.run("test", "loop", 1)
	check(vm.globals.get("count") == 3, "nested goto loop reaches flattened labels")
	await vm.run("test", "choice_test", 2)
	check(vm.globals.get("choice_value") == 2, "choice retains source IDs after hidden options")
	await vm.run("test", "snapshot", 7)
	var saved := vm.snapshot_state()
	vm.globals["save_value"] = 0
	vm.clear_sprite_locals(7)
	vm.restore_state(saved)
	check(vm.globals.get("save_value") == 7 and saved["sprite_locals"].get("test:7", {}).get("local_value") == 9, "snapshot restores globals and sprite locals")
	run_cancel.call_deferred(vm)
	await process_frame
	vm.cancel_all()
	for _frame in 3: await process_frame
	check(cancelled_finished and not vm.globals.has("after_cancel"), "cancel_all stops awaited task continuation")
	run_persistent.call_deferred(vm, "transient", 6)
	run_persistent.call_deferred(vm, "persistent", 7)
	for _frame in 2: await process_frame
	vm.cancel_screen_tasks()
	for _frame in 3: await process_frame
	check(_has_record(host.calls, 1000) and _has_context(host.calls, "external", 1000) and not _has_record(host.calls, 6), "script_attach(1000) survives screen cancellation and passes attachment to external host calls")
	await vm.run("test", "kill", 3)
	check(not vm.globals.has("after_kill"), "kill_this_task stops remaining instructions")
	if failures.is_empty():
		print("DinkVM regression tests passed")
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)
