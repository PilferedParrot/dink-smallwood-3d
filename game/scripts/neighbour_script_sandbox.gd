# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
# Predict only the immediate arrival state. This host never yields or reaches the
# live scene's command bridge: a blocking command ends its own private VM task.
extends RefCounted

const VM = preload("res://scripts/dink_vm.gd")
const MAX_HOST_CALLS := 20000
const MAX_NESTED_RUNS := 64

var vm
var entities: Dictionary = {}
var editor_state: Dictionary = {}
var items: Array = []
var magic_items: Array = []
var random_tape: Array = []
var uncertain: Array = []
var cuts: Array = [] # procedures stopped at their first blocking host command
var next_entity: int
var current_screen: int
var _game: Object
var _rng := RandomNumberGenerator.new()
var _created_count := 0
var _host_calls := 0
var _nested_runs := 0
var _ran := false
var _cut_tasks: Dictionary = {}
var _last_run_cut := false

func _init(game: Object, number: int, seed_value: int, base_state: Dictionary = {}) -> void:
	_game = game
	current_screen = number
	next_entity = int(base_state.get("next_entity", game.next_entity))
	_rng.seed = seed_value
	vm = VM.new(self)
	# Story is compiler data and VM execution does not write it.
	vm.story = game.vm.story
	vm.globals = (base_state.get("globals", game.vm.globals) as Dictionary).duplicate(true)
	vm._global_names = (base_state.get("global_names", game.vm._global_names) as Dictionary).duplicate(true)
	vm._sprite_locals = (base_state.get("sprite_locals", game.vm._sprite_locals) as Dictionary).duplicate(true)
	vm.globals["player_map"] = number
	vm.globals["vision"] = 0
	editor_state = (base_state.get("editor_state", game.editor_state) as Dictionary).duplicate(true)
	items = (base_state.get("items", game.items) as Array).duplicate(true)
	magic_items = (base_state.get("magic_items", game.magic_items) as Array).duplicate(true)
	entities[1] = (base_state.get("player", game.entities.get(1, {})) as Dictionary).duplicate(true)
	entities[1]["frozen"] = false
	# RefCounted host and VM must not retain each other between runs.
	vm.host = null

func run_startup() -> Dictionary:
	if not _ran:
		_ran = true
		var screen: Dictionary = _game.world.get("screens", {}).get(str(current_screen), {})
		if screen.is_empty():
			uncertain.append("Missing screen %d" % current_screen)
		else:
			_run(str(screen.get("script", "")), "main", 0)
			var editor_entities: Array[int] = []
			for source in screen.get("sprites", []):
				var e: Dictionary = _game.editor_entity(current_screen, source, true, int(vm.globals.get("vision", 0)), editor_state)
				if e.is_empty(): continue
				e["_arrival_id"] = "editor:%d" % int(e.get("editor_num", 0))
				entities[next_entity] = e
				editor_entities.append(next_entity)
				next_entity += 1
			# As in load_map, all editor entities exist before any editor main.
			for id in editor_entities:
				var e: Dictionary = entities[id]
				if int(e.get("type", 1)) == 1:
					_run(str(e.get("script", "")), "main", id)
	var sprites: Array = []
	for id in entities:
		if int(id) != 1:
			sprites.append(entities[id].duplicate(true))
	return {"vision": int(vm.globals.get("vision", 0)), "sprites": sprites, "random_tape": random_tape.duplicate(true), "uncertain": uncertain.duplicate(), "cuts": cuts.duplicate(), "globals": vm.globals.duplicate(true), "global_names": vm._global_names.duplicate(true), "sprite_locals": vm._sprite_locals.duplicate(true), "editor_state": editor_state.duplicate(true), "items": items.duplicate(true), "magic_items": magic_items.duplicate(true), "player": entities[1].duplicate(true), "next_entity": next_entity}

func _run(script: String, procedure: String, sprite_id: int) -> Variant:
	_last_run_cut = false
	var name: String = vm._script_name(script)
	if name.is_empty() or vm._procedure_code(name, procedure.to_lower()).is_empty(): return 0
	if _nested_runs >= MAX_NESTED_RUNS:
		uncertain.append("Nested startup limit at %s.%s" % [name, procedure])
		return 0
	_nested_runs += 1
	vm.host = self
	var task_id: int = vm._next_task_id
	# VM's awaits complete immediately because this host is synchronous. No
	# timer, scene signal or deferred callback can survive this call.
	var value: Variant = vm.run(name, procedure, sprite_id)
	_last_run_cut = _cut_tasks.has(task_id)
	_nested_runs -= 1
	if _nested_runs == 0: vm.host = null
	return value

func _stop(context: Dictionary) -> void:
	var task_id := int(context.get("task_id", 0))
	_cut_tasks[task_id] = true
	var procedure := "%s.%s" % [str(context.get("script", "")), str(context.get("procedure", ""))]
	if not cuts.has(procedure): cuts.append(procedure)
	vm._live_tasks.erase(task_id)

func _note(cmd: String, context: Dictionary) -> void:
	var diagnostic := "%s.%s: unpredicted %s" % [str(context.get("script", "")), str(context.get("procedure", "")), cmd]
	if not uncertain.has(diagnostic): uncertain.append(diagnostic)

func _refuse(cmd: String, context: Dictionary) -> int:
	_note(cmd, context)
	_stop(context)
	return 0

func _create(args: Array) -> int:
	var id := next_entity
	next_entity += 1
	_created_count += 1
	var brain := int(args[2]) if args.size() > 2 else 0
	var seq := int(args[3]) if args.size() > 3 else 0
	entities[id] = {"x": float(args[0]) if args.size() > 0 else 0.0, "y": float(args[1]) if args.size() > 1 else 0.0, "brain": brain, "pseq": seq, "pframe": int(args[4]) if args.size() > 4 else 1, "seq": seq if brain in [5, 6, 7] else 0, "frame": 1, "active": 1, "hard": 1, "size": 100, "speed": 1, "dir": 2, "anim_time": 0.0, "script": "", "editor_num": 0, "_arrival_id": "created:%d" % _created_count}
	return id

func dink_call(command: String, args: Array, context: Dictionary) -> Variant:
	_host_calls += 1
	if _host_calls > MAX_HOST_CALLS: return _refuse("startup host-call limit", context)
	var cmd := command.to_lower()
	var a: Variant = args[0] if args.size() > 0 else 0
	var b: Variant = args[1] if args.size() > 1 else 0
	var c: Variant = args[2] if args.size() > 2 else 0
	var d: Variant = args[3] if args.size() > 3 else 0
	var sid := int(context.get("sprite_id", 0))
	if cmd.begins_with("sp_") and cmd not in ["sp_kill", "sp_kill_wait", "sp_script", "sp_prop"]:
		var id := int(a)
		if not entities.has(id): return 0
		var key := cmd.substr(3)
		if key == "editor_num": return int(entities[id].get("editor_num", 0))
		if args.size() > 1 and (int(b) != -1 or cmd == "sp_touch_damage"):
			entities[id][key] = b
			if key == "seq":
				entities[id]["frame"] = 1
				entities[id]["anim_time"] = 0.0
		return entities[id].get(key, 0)
	match cmd:
		"make_global_int":
			vm.globals[str(a).trim_prefix("&")] = b
			return b
		"random":
			var result := _rng.randi_range(0, maxi(0, int(a) - 1)) + int(b)
			random_tape.append([int(a), int(b), result, str(context.get("script", "")), str(context.get("procedure", ""))])
			return result
		"freeze", "freeeze", "unfreeze", "unfreeeze":
			if entities.has(int(a)): entities[int(a)]["frozen"] = cmd in ["freeze", "freeeze"]
			if cmd in ["freeze", "freeeze"]: _stop(context)
		"wait", "say_stop", "say_stop_npc", "say_stop_xy", "choice", "fade_down", "fade_up", "load_screen", "show_bmp", "activate_bow", "stop_entire_game", "restart_game", "kill_game", "load_game":
			_stop(context)
		"force_vision":
			vm.globals["vision"] = int(a)
			_stop(context)
		"create_sprite": return _create(args)
		"sp_script":
			if args.size() < 2 or str(b) == "-1": return str(entities.get(int(a), {}).get("script", ""))
			if entities.has(int(a)):
				entities[int(a)]["script"] = str(b).to_lower()
				_run(str(b), "main", int(a))
		"sp":
			for id in entities:
				if int(entities[id].get("editor_num", 0)) == int(a): return id
			return 0
		"move", "move_stop":
			if entities.has(int(a)):
				var e: Dictionary = entities[int(a)]
				e["move_token"] = int(e.get("move_token", 0)) + 1
				e["moving"] = true
				e["dir"] = int(b)
				var axis := "y" if int(b) in [2, 8] else "x"
				if absf(float(c) - float(e.get(axis, 0))) < 1.0:
					e.erase("moving")
					e["seq"] = 0
			if cmd == "move_stop": _stop(context)
		"external":
			var result: Variant = _run(str(a), str(b), sid)
			if _last_run_cut: _stop(context)
			return result
		"spawn", "load":
			var id := next_entity
			next_entity += 1
			_created_count += 1
			entities[id] = {"x": 0, "y": 0, "active": 0, "script": str(a), "editor_num": 0, "_arrival_id": "created:%d" % _created_count}
			_run(str(a), "main", id)
			return id
		"run_script_by_number":
			if entities.has(int(a)):
				var result: Variant = _run(str(entities[int(a)].get("script", "")), str(b), int(a))
				if _last_run_cut: _stop(context)
				return result
		"editor_type", "editor_seq", "editor_frame":
			var key := "%d:%d" % [current_screen, int(a)]
			var property: String = {"editor_type": "editor_type", "editor_seq": "seq", "editor_frame": "frame"}[cmd]
			if not editor_state.has(key): editor_state[key] = {}
			if args.size() > 1 and int(b) != -1:
				editor_state[key][property] = b
				if cmd == "editor_type":
					editor_state[key]["removed"] = int(b) == 1
					if int(b) in [6, 7, 8]: editor_state[key]["return_at"] = Time.get_unix_time_from_system() + {6: 300, 7: 180, 8: 60}[int(b)]
			return editor_state[key].get(property, 0)
		"get_sprite_with_this_brain", "get_rand_sprite_with_this_brain":
			if cmd.begins_with("get_rand"): _note("random sprite choice is not replayed", context)
			var found: Array = []
			for id in entities:
				if int(id) != int(b) and int(entities[id].get("brain", 0)) == int(a) and int(entities[id].get("active", 1)) != 0: found.append(id)
			if found.is_empty(): return 0
			return found[_rng.randi_range(0, found.size() - 1)] if cmd.begins_with("get_rand") else found[0]
		"compare_sprite_script": return int(entities.has(int(a)) and str(entities[int(a)].get("script", "")).to_lower() == str(b).to_lower())
		"is_script_attached":
			if a is int or a is float: return int(a) if entities.has(int(a)) and not str(entities[int(a)].get("script", "")).is_empty() else 0
			for id in entities:
				if str(entities[id].get("script", "")).to_lower() == str(a).to_lower(): return id
			return 0
		"inside_box": return int(Rect2(float(c), float(d), float(args[4]) - float(c), float(args[5]) - float(d)).has_point(Vector2(float(a), float(b)))) if args.size() >= 6 else 0
		"add_item", "add_magic":
			var list: Array = items if cmd == "add_item" else magic_items
			if list.size() >= 16: return 0
			list.append({"script": str(a).to_lower(), "seq": int(b), "frame": int(c)})
			return 1
		"count_item", "count_magic":
			var count := 0
			for item in (items if cmd == "count_item" else magic_items):
				if str(item.get("script", "")).to_lower() == str(a).to_lower(): count += 1
			return count
		"free_items": return 16 - items.size()
		"free_magic": return 16 - magic_items.size()
		"compare_weapon":
			var index := int(vm.globals.get("cur_weapon", 0)) - 1
			return int(index >= 0 and index < items.size() and str(items[index].get("script", "")).to_lower() == str(a).to_lower())
		"kill_this_item", "kill_cur_item":
			var script := str(a) if cmd == "kill_this_item" else str(context.get("script", ""))
			for index in range(items.size() - 1, -1, -1):
				if str(items[index].get("script", "")).to_lower() == script.to_lower():
					items.remove_at(index)
					break
			vm.globals["cur_weapon"] = mini(int(vm.globals.get("cur_weapon", 1)), items.size())
		"set_dink_speed":
			if entities.has(1): entities[1]["speed"] = int(a)
		"sp_prop":
			if entities.has(int(a)): entities[int(a)]["active"] = int(b)
		"sp_kill_wait":
			if entities.has(int(a)): entities[int(a)]["anim_time"] = 0.0
		"sp_kill":
			# Its timer may expire by the first rendered frame, but cannot be
			# advanced by a synchronous immediate-state predictor.
			_note("delayed sp_kill(%s,%s)" % [str(a), str(b)], context)
		"get_version": return 108
		"get_last_bow_power": return 100
		"get_burn": return int(vm.globals.get("burn", 0))
		"scripts_used": return vm._live_tasks.size()
		# These have no immediate sprite effect. Scheduled work is past the
		# arrival cut; presentation and audio are never sent to the live host.
		"say", "say_xy", "script_attach", "screenlock", "dink_can_walk_off_screen", "load_sound", "playsound", "playmidi", "stopmidi", "stopcd", "set_callback_random", "fill_screen", "preload_seq", "draw_screen", "draw_status", "draw_hard_sprite", "draw_hard_map", "kill_shadow", "set_y", "set_title_color", "reset_timer", "set_button", "debug", "kill_this_task": pass
		_: return _refuse(cmd, context)
	return 0
