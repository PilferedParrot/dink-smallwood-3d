extends SceneTree

const GAME := preload("res://scripts/fps_game.gd")

class ControlledGame extends GAME:
	var random_calls := 0
	func dink_call(command: String, args: Array, context: Dictionary) -> Variant:
		if command.to_lower() == "random":
			random_calls += 1
			return 1
		return await super.dink_call(command, args, context)

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var duck_editor := await _load_case(440, false, {"old_womans_duck": 1, "vision": 0})
	var duck_live := await _load_case(440, true, {"old_womans_duck": 1, "vision": 0})
	var live_duck := _has_script(duck_live.entities, "s1-oldd")
	check(int(duck_live.globals.get("vision", 0)) == 2, "440 real load with random(4,1)=1 selects duck vision 2")
	check(live_duck, "440 real load creates the duck entity")
	check(int(duck_editor.globals.get("vision", 0)) == 0 and not _has_script(duck_editor.entities, "s1-oldd"), "440 editor-only baseline omits duck vision and entity")
	check(duck_live.random_calls == 1 and duck_editor.random_calls == 0, "440 positive and negative control random call counts")

	var gate_editor := await _load_case(408, false, {"story": 1, "little_girl": 0, "vision": 0})
	var gate_live := await _load_case(408, true, {"story": 1, "little_girl": 0, "vision": 0})
	var live_girl := _has_script(gate_live.entities, "s1-lg")
	check(live_girl, "408 real load with random=1 creates the gate girl")
	check(not _has_script(gate_editor.entities, "s1-lg"), "408 editor-only baseline omits the gate girl")
	check(gate_live.random_calls >= 1 and gate_editor.random_calls == 0, "408 real load takes deterministic gate roll")

	var gold_editor := await _load_case(505, false, {})
	var gold_live := await _load_case(505, true, {})
	var gold_before := _entity_for_editor(gold_editor.entities, 15)
	var gold_after := _entity_for_editor(gold_live.entities, 15)
	check(not gold_before.is_empty() and not gold_after.is_empty(), "505 editor gold exists in both snapshots")
	if not gold_before.is_empty() and not gold_after.is_empty():
		check(int(gold_before.get("frame", 0)) == 1 and int(gold_after.get("frame", 0)) == 4, "505 1gold startup changes editor sprite frame property from 1 to 4")
		check(gold_before != gold_after, "505 1gold real-load state disagrees with editor-only baseline")

	var neighbour := await _new_game()
	neighbour.vm.cancel_all()
	neighbour.playing = false
	neighbour.load_map(439, false)
	await process_frame
	# Rebuild a complete 5x5 block into a disposable root so this assertion
	# exercises the sandbox and every rendering consumer, not only house_plan.
	neighbour.neighbour_arrival_cache.clear()
	var original_root: Node3D = neighbour.scene_root
	var rebuilt_root := Node3D.new()
	neighbour.scene_root = rebuilt_root
	neighbour.add_child(rebuilt_root)
	var before := _live_snapshot(neighbour)
	neighbour.fp_world.build_ground(neighbour.world.screens["439"])
	var after := _live_snapshot(neighbour)
	check(before == after, "building 439's 5x5 neighbour ground leaves live game state unchanged")
	neighbour.scene_root = original_root
	rebuilt_root.queue_free()
	print("NEIGHBOR STARTUP RESULTS duck=%s gate=%s property=%s snapshot=%s" % [
		str(duck_live.globals.get("vision", 0)) + "/" + str(live_duck),
		str(live_girl),
		str(gold_before.get("frame", -1)) + "->" + str(gold_after.get("frame", -1)),
		str(before == after)])
	for g in [neighbour]:
		g.vm.cancel_all()
		g.queue_free()
	await process_frame
	if failures.is_empty(): print("NEIGHBOR STARTUP PASS")
	else: print("NEIGHBOR STARTUP FAILURES: ", failures)
	quit(0 if failures.is_empty() else 1)

func _new_game() -> ControlledGame:
	var game := ControlledGame.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	game.vm.cancel_all()
	game.playing = false
	return game

func _load_case(screen: int, run_scripts: bool, seed: Dictionary) -> Dictionary:
	var game := await _new_game()
	for key in seed: game.vm.globals[key] = seed[key]
	game.vm.cancel_all()
	game.load_map(screen, run_scripts)
	# Screen main is synchronous up to host awaits; editor mains are deferred from load_map.
	for _i in 4: await process_frame
	var record := {
		"globals": game.vm.globals.duplicate(true),
		"entities": _normalized_entities(game),
		"random_calls": game.random_calls,
	}
	game.vm.cancel_all()
	game.queue_free()
	await process_frame
	return record

func _normalized_entities(game: ControlledGame) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in game.entities:
		if int(id) == 1: continue
		var e: Dictionary = game.entities[id]
		var visual: Node = game.visuals.get(id)
		var visible: bool = visual != null and is_instance_valid(visual) and visual.visible
		if not visible: continue
		out.append({
			"id": int(id), "editor_num": int(e.get("editor_num", 0)),
			"script": str(e.get("script", "")).to_lower(),
			"x": float(e.get("x", 0)), "y": float(e.get("y", 0)),
			"seq": int(e.get("seq", 0)), "frame": int(e.get("frame", 1)),
			"pseq": int(e.get("pseq", e.get("seq", 0))),
			"pframe": int(e.get("pframe", e.get("frame", 1))),
			"active": int(e.get("active", 1)), "visible": visible,
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.get("editor_num", 0)) < int(b.get("editor_num", 0)))
	return out

func _has_script(entities: Array, script: String) -> bool:
	return entities.any(func(e): return str(e.get("script", "")).to_lower() == script)

func _entity_for_editor(entities: Array, index: int) -> Dictionary:
	for e in entities:
		if int(e.get("editor_num", 0)) == index: return e
	return {}

func _live_snapshot(game: ControlledGame) -> Dictionary:
	return {
		"globals": game.vm.globals.duplicate(true),
		"vm_locals": game.vm._sprite_locals.duplicate(true),
		"vm_global_names": game.vm._global_names.duplicate(true),
		"editor_state": game.editor_state.duplicate(true),
		"items": game.items.duplicate(true), "magic": game.magic_items.duplicate(true),
		"entities": game.entities.duplicate(true), "music": game.last_music,
		"music_stream": game.music.stream.resource_path if game.music.stream != null else "",
		"music_playing": game.music.playing,
		"screen": game.current_screen, "next_entity": game.next_entity,
		"visited": game.visited.duplicate(true), "dialogue_log": game.dialogue_log.duplicate(true),
		"ui": {"modal": game.ui.modal, "toast": game.ui.toast.text,
			"page": game.ui.page, "dialogue_mode": game.ui.dialogue_mode},
	}
