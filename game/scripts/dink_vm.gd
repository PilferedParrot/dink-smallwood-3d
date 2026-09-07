## Small, cooperative interpreter for the JSON emitted by tools/compile_story.py.
## The scene host owns all Dink engine behaviour; this class only owns script state
## and flow control.  Keeping that boundary here means the original DinkC source is
## data, not code linked from the GPL engine.
class_name DinkVM
extends RefCounted

## Public game variables.  Names do not include the DinkC leading '&'.
var globals: Dictionary = {}
## Object with `func dink_call(command: String, args: Array, context: Dictionary) -> Variant`.
var host: Object

var story: Dictionary = {}
var _sprite_locals: Dictionary = {}
var _generation: int = 0
var _next_task_id: int = 1
var _live_tasks: Dictionary = {}
var _global_names: Dictionary = {}


func _init(p_host: Object = null) -> void:
	host = p_host


## Loads a compiler JSON document.  Passing no value loads the exported game data.
func load_story(value: Variant = null) -> bool:
	var parsed: Variant = null
	if value == null:
		var file := FileAccess.open("res://data/story.json", FileAccess.READ)
		if file == null:
			push_error("DinkVM: res://data/story.json is missing")
			return false
		parsed = JSON.parse_string(file.get_as_text())
		if not (parsed is Dictionary):
			push_error("DinkVM: story.json is not a JSON object")
			return false
		story = parsed
	elif value is Dictionary:
		story = value
	elif value is String:
		parsed = JSON.parse_string(value)
		if not (parsed is Dictionary):
			return false
		story = parsed
	else:
		return false
	return story.has("scripts")


## Cancels every currently executing script. Hosts should call this before replacing
## a screen. The current host await is allowed to return, but its continuation exits.
func cancel_all() -> void:
	_generation += 1
	_live_tasks.clear()


## Cancels all other coroutines without cancelling the task currently handling a
## load_screen call. Pass `context.task_id` from the host's dink_call implementation.
func cancel_except(task_id: int) -> void:
	for key in _live_tasks.keys():
		if int(key) != task_id:
			_live_tasks.erase(key)


## Cancels tasks owned by the outgoing screen. DinkC's pseudo-sprite 1000 is
## retained across screen changes; cancel_all() remains the full reset operation.
func cancel_screen_tasks(except_task: int = 0) -> void:
	for key in _live_tasks.keys():
		var id := int(key)
		if id != except_task and _task_sprite(id) != 1000:
			_live_tasks.erase(key)


## Save only interpreter-owned state. The host saves world entities and inventory.
func snapshot_state() -> Dictionary:
	return {"globals": globals.duplicate(true), "sprite_locals": _sprite_locals.duplicate(true)}


func restore_state(data: Dictionary) -> void:
	globals = data.get("globals", {}).duplicate(true) if data.get("globals", {}) is Dictionary else {}
	_sprite_locals = data.get("sprite_locals", {}).duplicate(true) if data.get("sprite_locals", {}) is Dictionary else {}


## Use this if a host deliberately reuses a sprite id for a fresh entity.
func clear_sprite_locals(sprite_id: int) -> void:
	var suffix := ":%d" % sprite_id
	for key in _sprite_locals.keys():
		if str(key).ends_with(suffix):
			_sprite_locals.erase(key)


## Runs one procedure asynchronously. Each sprite gets persistent local storage for
## a script, so event procedures such as talk/hit can share its declared variables.
func run(script: String, procedure: String, sprite_id: int = 0) -> Variant:
	var canonical: String = _script_name(script)
	var task_id: int = _next_task_id
	_next_task_id += 1
	_live_tasks[task_id] = {"sprite_id": sprite_id}
	var output: Variant = await _execute(canonical, procedure.to_lower(), sprite_id, task_id, _generation, [])
	_live_tasks.erase(task_id)
	return output


func _script_name(name: String) -> String:
	return name.get_file().get_basename().to_lower().replace("_", "-")


func _procedure_code(script: String, procedure: String) -> Array:
	var scripts: Dictionary = story.get("scripts", {})
	var record: Dictionary = scripts.get(script, {})
	if record.is_empty():
		# Accept source names too, which helps hand-authored test stories.
		for key in scripts:
			if _script_name(str(key)) == script:
				record = scripts[key]
				break
	var procedures: Dictionary = record.get("procedures", {})
	var proc: Variant = procedures.get(procedure, procedures.get(procedure.to_lower(), []))
	if proc is Dictionary:
		return proc.get("code", proc.get("instructions", []))
	return proc if proc is Array else []


func _locals_for(script: String, sprite_id: int) -> Dictionary:
	var key := "%s:%d" % [script, sprite_id]
	if not _sprite_locals.has(key):
		_sprite_locals[key] = {}
	return _sprite_locals[key]


func _execute(script: String, procedure: String, sprite_id: int, task_id: int, generation: int, stack: Array) -> Variant:
	if generation != _generation or not _live_tasks.has(task_id):
		return null
	if stack.size() > 64:
		push_error("DinkVM: procedure recursion limit reached (%s.%s)" % [script, procedure])
		return null
	# Flatten condition blocks for this task.  Labels inside a conditional block are
	# valid DinkC jump targets, and labels must therefore be indexed in the same linear
	# instruction stream as the goto that reaches them.  This also leaves story.json
	# immutable across runs.
	var code := _flatten_code(_procedure_code(script, procedure))
	if code.is_empty():
		push_warning("DinkVM: missing procedure %s.%s" % [script, procedure])
		return null
	var locals := _locals_for(script, sprite_id)
	var labels := _labels(code)
	var ip := 0
	var choice_options: Array = []
	var choice_title := ""
	while ip < code.size() and generation == _generation and _live_tasks.has(task_id):
		var current_sprite := _task_sprite(task_id, sprite_id)
		var raw: Variant = code[ip]
		ip += 1
		if not (raw is Dictionary):
			continue
		var instruction: Dictionary = raw
		var op: String = str(instruction.get("op", instruction.get("type", ""))).to_lower()
		match op:
			"", "label", "nop", "declare":
				continue
			"expr":
				var ignored_expression: Variant = await _eval(instruction.get("expr", null), locals, script, current_sprite, task_id, generation)
			"set", "assign":
				var set_target: Variant = instruction.get("target", instruction.get("name", ""))
				var set_value: Variant = await _eval(instruction.get("expr", instruction.get("value", 0)), locals, script, current_sprite, task_id, generation)
				if instruction.has("declare"):
					# `int &name` is a DinkC script-local declaration; '&' is part of
					# DinkC's variable spelling, not a global-state marker by itself.
					locals[_ref_name(set_target)] = set_value
				else:
					_set_ref(set_target, set_value, locals, current_sprite)
			"inc", "dec":
				var target: Variant = instruction.get("target", instruction.get("name", ""))
				var amount: int = _number(await _eval(instruction.get("expr", instruction.get("value", 1)), locals, script, current_sprite, task_id, generation))
				if op == "dec": amount = -amount
				_set_ref(target, _number(_get_ref(target, locals, current_sprite)) + amount, locals, current_sprite)
			"if_goto":
				var condition: bool = _truthy(await _eval(instruction.get("condition", instruction.get("test", false)), locals, script, current_sprite, task_id, generation))
				var false_label := str(instruction.get("false_label", ""))
				if not condition and labels.has(false_label): ip = labels[false_label]
			"jump", "goto":
				var destination := str(instruction.get("label", instruction.get("target", "")))
				if labels.has(destination): ip = labels[destination]
			"return", "kill", "kill_this_task", "stop":
				return await _eval(instruction.get("value", instruction.get("expr", null)), locals, script, current_sprite, task_id, generation)
			"choice_start":
				choice_options.clear()
				choice_title = ""
			"choice_title":
				choice_title = str(await _eval(instruction.get("value", instruction.get("text", "")), locals, script, current_sprite, task_id, generation))
			"choice", "choice_option", "choice_add":
				var visible: bool = _truthy(await _eval(instruction.get("condition", true), locals, script, current_sprite, task_id, generation))
				if visible:
					choice_options.append({"text": await _eval(instruction.get("text", instruction.get("value", "")), locals, script, current_sprite, task_id, generation), "value": await _eval(instruction.get("result", instruction.get("id", choice_options.size() + 1)), locals, script, current_sprite, task_id, generation)})
			"choice_end":
				var chosen: Variant = await _host_call("choice", [choice_title, choice_options], script, procedure, current_sprite, task_id, generation, locals)
				globals["result"] = chosen
				choice_options.clear()
			"proc", "procedure", "call_proc":
				var proc_name := str(instruction.get("procedure", instruction.get("name", "main"))).to_lower()
				var proc_result: Variant = await _execute(script, proc_name, sprite_id, task_id, generation, stack + [script + "." + procedure])
				if instruction.has("target"): _set_ref(instruction["target"], proc_result, locals, current_sprite)
			"call", "command":
				var command := str(instruction.get("name", instruction.get("command", "")))
				var args: Array = []
				for expr in instruction.get("args", []): args.append(await _eval(expr, locals, script, current_sprite, task_id, generation))
				if command.to_lower() == "make_global_int" and not args.is_empty():
					_register_global(str(args[0]))
				# Calls to another procedure in this DinkC source do not go to the host.
				if _procedure_code(script, command.to_lower()).size() > 0 and not instruction.get("host", false):
					var nested: Variant = await _execute(script, command.to_lower(), sprite_id, task_id, generation, stack + [script + "." + procedure])
					if instruction.has("target"): _set_ref(instruction["target"], nested, locals, current_sprite)
				else:
					if command.to_lower() == "script_attach" and not args.is_empty():
						_set_task_sprite(task_id, _number(args[0]))
					var result: Variant = await _host_call(command, args, script, procedure, current_sprite, task_id, generation, locals)
					if instruction.has("target"): _set_ref(instruction["target"], result, locals, current_sprite)
					# In DinkC this ends the current script after the host has completed its
					# transition bookkeeping.  Continuing here would run stale map logic.
					if command.to_lower() == "kill_this_task": return result
			_:
				push_warning("DinkVM: unsupported instruction '%s'" % op)
	return null


func _labels(code: Array) -> Dictionary:
	var result := {}
	for index in code.size():
		if code[index] is Dictionary and str(code[index].get("op", "")).to_lower() == "label":
			result[str(code[index].get("name", code[index].get("label", "")))] = index + 1
	return result


func _flatten_code(source: Array) -> Array:
	var result: Array = []
	var state := {"next": 0}
	_flatten_into(source, result, state)
	return result


func _flatten_into(source: Array, output: Array, state: Dictionary) -> void:
	for raw in source:
		if not (raw is Dictionary):
			continue
		var instruction: Dictionary = raw
		if str(instruction.get("op", instruction.get("type", ""))).to_lower() != "if":
			output.append(instruction.duplicate(true))
			continue
		var id: int = int(state["next"])
		state["next"] = id + 1
		var else_label := "__dink_vm_if_%d_else" % id
		var end_label := "__dink_vm_if_%d_end" % id
		var raw_else: Variant = instruction.get("else", [])
		var else_code: Array = raw_else if raw_else is Array else []
		var false_target := else_label if not else_code.is_empty() else end_label
		output.append({"op":"if_goto", "condition":instruction.get("condition", instruction.get("test", false)), "false_label":false_target})
		var raw_then: Variant = instruction.get("then", [])
		var then_code: Array = raw_then if raw_then is Array else []
		_flatten_into(then_code, output, state)
		if not else_code.is_empty():
			output.append({"op":"goto", "label":end_label})
			output.append({"op":"label", "name":else_label})
			_flatten_into(else_code, output, state)
		output.append({"op":"label", "name":end_label})


func _task_sprite(task_id: int, fallback: int = 0) -> int:
	var task: Variant = _live_tasks.get(task_id, {})
	if task is Dictionary:
		return int(task.get("sprite_id", fallback))
	return fallback


func _set_task_sprite(task_id: int, sprite_id: int) -> void:
	if not _live_tasks.has(task_id):
		return
	var task: Dictionary = _live_tasks[task_id] if _live_tasks[task_id] is Dictionary else {}
	task["sprite_id"] = sprite_id
	_live_tasks[task_id] = task


func _host_call(command: String, args: Array, script: String, procedure: String, sprite_id: int, task_id: int, generation: int, locals: Dictionary) -> Variant:
	if generation != _generation or not _live_tasks.has(task_id) or host == null or not host.has_method("dink_call"):
		return null
	var context := {"script": script, "procedure": procedure, "sprite_id": sprite_id, "task_id": task_id, "cancelled": false, "globals": globals, "locals": locals}
	var value: Variant = await host.dink_call(command, args, context)
	return null if generation != _generation or not _live_tasks.has(task_id) else value


func _eval(expr: Variant, locals: Dictionary, script: String, sprite_id: int, task_id: int, generation: int) -> Variant:
	if not (expr is Dictionary): return expr
	var node: Dictionary = expr
	var kind := str(node.get("kind", node.get("type", "literal"))).to_lower()
	match kind:
		"literal", "value", "number", "string": return node.get("value", node.get("text", 0))
		"ref", "var", "variable": return _get_ref(node, locals, sprite_id)
		"unary":
			var unary: Variant = await _eval(node.get("value", node.get("expr")), locals, script, sprite_id, task_id, generation)
			return -_number(unary) if str(node.get("operator", node.get("op", ""))) == "-" else (not _truthy(unary))
		"binary":
			var left: Variant = await _eval(node.get("left"), locals, script, sprite_id, task_id, generation)
			var operator := str(node.get("operator", node.get("op", "")))
			if operator == "&&" and not _truthy(left): return false
			if operator == "||" and _truthy(left): return true
			var right: Variant = await _eval(node.get("right"), locals, script, sprite_id, task_id, generation)
			return _binary(operator, left, right)
		"call":
			# Compiler keeps calls in expressions only for host functions such as random().
			var values: Array = []
			for arg in node.get("args", []): values.append(await _eval(arg, locals, script, sprite_id, task_id, generation))
			return await _host_call(str(node.get("name", "")), values, script, "expression", sprite_id, task_id, generation, locals)
	return node.get("value", 0)


func _binary(op: String, a: Variant, b: Variant) -> Variant:
	match op:
		"+": return str(a) + str(b) if a is String or b is String else _number(a) + _number(b)
		"-": return _number(a) - _number(b)
		"*": return _number(a) * _number(b)
		"/": return 0 if _number(b) == 0 else int(_number(a) / _number(b))
		"%": return 0 if _number(b) == 0 else int(_number(a)) % int(_number(b))
		"==": return a == b
		"!=": return a != b
		"<": return _number(a) < _number(b)
		"<=": return _number(a) <= _number(b)
		">": return _number(a) > _number(b)
		">=": return _number(a) >= _number(b)
		"&&": return _truthy(a) and _truthy(b)
		"||": return _truthy(a) or _truthy(b)
	return 0


func _get_ref(ref: Variant, locals: Dictionary, sprite_id: int = 0) -> Variant:
	var name := ""
	var scope := ""
	if ref is Dictionary:
		name = str(ref.get("name", ref.get("value", "")))
		scope = str(ref.get("scope", ""))
	else: name = str(ref)
	var has_ampersand := name.begins_with("&")
	name = name.trim_prefix("&")
	# DinkC populates this built-in for each event invocation. It must not be
	# represented as shared global state: two sprites can run the same script at once.
	if name == "current_sprite": return sprite_id
	if scope == "local" or locals.has(name): return locals.get(name, 0)
	var global_ref := scope == "global" or has_ampersand or _global_names.has(name) or globals.has(name)
	return globals.get(name, 0) if global_ref else locals.get(name, 0)


func _set_ref(ref: Variant, value: Variant, locals: Dictionary, sprite_id: int = 0) -> void:
	var name := ""
	var scope := ""
	if ref is Dictionary:
		name = str(ref.get("name", ref.get("value", "")))
		scope = str(ref.get("scope", ""))
	else: name = str(ref)
	var has_ampersand := name.begins_with("&")
	name = name.trim_prefix("&")
	if name == "current_sprite":
		# The executing event owns this value. Assignments cannot retarget a live
		# coroutine; scripts copy it to a declared local when they need an alias.
		return
	if scope == "local" or locals.has(name):
		locals[name] = value
		return
	var global_ref := scope == "global" or has_ampersand or _global_names.has(name) or globals.has(name)
	if global_ref: globals[name] = value
	else: locals[name] = value


func _number(value: Variant) -> int:
	return int(value) if value != null else 0


func _truthy(value: Variant) -> bool:
	return value is bool and value or _number(value) != 0


func _register_global(raw_name: String) -> void:
	var name := raw_name.trim_prefix("&")
	_global_names[name] = true
	if not globals.has(name): globals[name] = 0


func _ref_name(ref: Variant) -> String:
	if ref is Dictionary: return str(ref.get("name", ref.get("value", ""))).trim_prefix("&")
	return str(ref).trim_prefix("&")
