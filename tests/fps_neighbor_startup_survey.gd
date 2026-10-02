extends SceneTree

const GAME := preload("res://scripts/game.gd")
const FIXTURES := ["fresh", "post_letter", "burning_house", "duck_search"]
const PROPERTIES := ["active", "nodraw", "disabled", "type", "x", "y", "seq", "frame", "pseq", "pframe", "visible"]

var failures: Array[String] = []
var report_path := ""
var smoke := false
var report: FileAccess
var game
var outdoor_screens: Array[int] = []
var fresh_state: Dictionary = {}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report_path = arg.trim_prefix("--report=")
		if arg == "--smoke": smoke = true
	_run.call_deferred()

func _run() -> void:
	game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	await game._new_game()
	game.vm.cancel_all()
	game.playing = false
	for key in game.world.get("screens", {}):
		if not bool(game.world.screens[key].get("indoor", false)): outdoor_screens.append(int(key))
	outdoor_screens.sort()
	if not smoke and outdoor_screens.size() != 570:
		failures.append("Expected 570 outdoor screens, found %d" % outdoor_screens.size())
		push_error(failures.back())
	if smoke: outdoor_screens = [408, 439, 440, 505, 536]
	fresh_state = _capture_input_state()
	if not report_path.is_empty():
		report = FileAccess.open(report_path, FileAccess.WRITE)
		if report == null:
			failures.append("Could not open report path: " + report_path)
			push_error(failures.back())
	for fixture in FIXTURES:
		await _survey_fixture(fixture)
	game.vm.cancel_all()
	game.queue_free()
	await process_frame
	await process_frame
	game = null
	if report != null:
		report.close()
		report = null
	if failures.is_empty(): print("NEIGHBOR STARTUP SURVEY PASS screens=%d fixtures=%d" % [outdoor_screens.size(), FIXTURES.size()])
	else: print("NEIGHBOR STARTUP SURVEY FAILURES: ", failures)
	quit(0 if failures.is_empty() else 1)

func _capture_input_state() -> Dictionary:
	return {
		"globals": game.vm.globals.duplicate(true),
		"locals": game.vm._sprite_locals.duplicate(true),
		"global_names": game.vm._global_names.duplicate(true),
		"editor_state": game.editor_state.duplicate(true),
		"items": game.items.duplicate(true),
		"magic_items": game.magic_items.duplicate(true),
		"player": game.entities.get(1, {}).duplicate(true),
		"next_entity": int(game.next_entity),
	}

func _restore_input_state(fixture: String) -> void:
	game.vm.cancel_all()
	game.vm.globals = fresh_state.globals.duplicate(true)
	game.vm._sprite_locals = fresh_state.locals.duplicate(true)
	game.vm._global_names = fresh_state.global_names.duplicate(true)
	game.editor_state = fresh_state.editor_state.duplicate(true)
	game.items = fresh_state.items.duplicate(true)
	game.magic_items = fresh_state.magic_items.duplicate(true)
	game.entities = {1: fresh_state.player.duplicate(true)}
	game.next_entity = int(fresh_state.next_entity)
	game.neighbour_arrival_cache.clear()
	game.neighbour_seed_override = 1701
	game.playing = false
	game.dialogue_busy = false
	game.dialogue_log.clear()
	match fixture:
		"post_letter":
			game.vm.globals["story"] = 5
			game.vm.globals["nuttree"] = 1
			game.vm.globals["old_womans_duck"] = 4
		"burning_house":
			game.vm.globals["story"] = 4
			game.vm.globals["old_womans_duck"] = 4
		"duck_search":
			game.vm.globals["story"] = 1
			game.vm.globals["old_womans_duck"] = 1

func _survey_fixture(fixture: String) -> void:
	var counts := {"agreement": 0, "mismatch": 0, "post_cut": 0, "uncertain": 0, "inconclusive": 0, "unclassified": 0}
	for screen in outdoor_screens:
		_restore_input_state(fixture)
		if fixture == "duck_search" and screen == 440:
			await _choose_duck_seed(screen)
		var prediction: Dictionary = game.neighbour_arrival_state(screen)
		if fixture == "duck_search" and screen == 440:
			var forced_draw: bool = prediction.get("random_tape", []).any(func(draw): return draw.size() >= 3 and int(draw[0]) == 4 and int(draw[1]) == 1 and int(draw[2]) == 1)
			var duck_in_prediction: bool = prediction.get("sprites", []).any(func(e): return str(e.get("script", "")).to_lower() == "s1-oldd")
			if not forced_draw or int(prediction.get("vision", 0)) != 2 or not duck_in_prediction:
				failures.append("Duck search fixture did not force the 440 random control and duck outcome")
				push_error(failures.back())
			_write_line({"kind": "control", "fixture": fixture, "screen": screen, "random_tape": prediction.get("random_tape", []), "vision": prediction.get("vision", 0), "duck_predicted": duck_in_prediction})
		var expected := _normalize_prediction(prediction, int(fresh_state.next_entity))
		# The live path reuses this prediction's random draws only during startup;
		# all other host effects still go through game.gd's ordinary command bridge.
		game.vm.cancel_all()
		game.load_map(screen, true)
		await process_frame
		await process_frame
		# With simulation paused for a stable oracle, perform the same visual sync
		# the running game's frame would perform after deferred sprite mains.
		for id in game.entities.keys(): game._update_visual(int(id))
		var actual := _normalize_live(game, int(fresh_state.next_entity))
		var expected_vision := int(prediction.get("vision", 0))
		var actual_vision := int(game.vm.globals.get("vision", 0))
		if fixture == "duck_search" and screen == 440:
			var live_duck: bool = game.entities.values().any(func(e): return str(e.get("script", "")).to_lower() == "s1-oldd")
			if actual_vision != 2 or not live_duck:
				failures.append("Real 440 startup did not replay forced duck-search outcome")
				push_error(failures.back())
			_write_line({"kind": "live_control", "fixture": fixture, "screen": screen, "vision": actual_vision, "duck_live": live_duck})
		var equal := expected == actual and expected_vision == actual_vision
		var uncertain: Array = prediction.get("uncertain", [])
		var cuts: Array = prediction.get("cuts", [])
		var live_tasks: int = game.vm._live_tasks.size()
		var cause := ""
		if not equal:
			cause = _classify_mismatch(uncertain, cuts, live_tasks, _has_moving_difference(expected, actual, game))
			counts.mismatch += 1
			if cause == "post-cut": counts.post_cut += 1
			elif cause == "post-cut-motion": counts.post_cut += 1
			elif cause == "inconclusive": counts.inconclusive += 1
			elif cause == "unclassified": counts.unclassified += 1
		elif not uncertain.is_empty() or not cuts.is_empty() or live_tasks > 0:
			cause = "inconclusive" if live_tasks > 0 and uncertain.is_empty() else "uncertain"
			counts.inconclusive += 1 if cause == "inconclusive" else 0
			counts.uncertain += 1 if cause == "uncertain" else 0
		else:
			counts.agreement += 1
		var entry := {
			"kind": "screen", "fixture": fixture, "screen": screen,
			"result": cause if not cause.is_empty() else "agreement",
			"vision_expected": expected_vision,
			"vision_actual": actual_vision,
			"expected_count": expected.size(), "actual_count": actual.size(),
			"differences": _difference_summary(expected, actual),
			"uncertain": uncertain, "cuts": cuts, "live_tasks": live_tasks,
		}
		if fixture == "duck_search" and screen == 440: entry["preview_seed"] = game.neighbour_seed_override
		_write_line(entry)
		game.vm.cancel_all()
	if counts.unclassified > 0:
		failures.append("%s has %d unclassified startup mismatches" % [fixture, counts.unclassified])
	var summary := {"kind": "summary", "fixture": fixture, "tested_screens": outdoor_screens.size()}
	for key in counts: summary[key] = counts[key]
	_write_line(summary)
	print(JSON.stringify(summary))

func _choose_duck_seed(screen: int) -> void:
	# Search deterministic private RNG seeds until the planned 440 control draw is 1.
	for seed in range(1, 4097):
		game.neighbour_seed_override = seed
		game.neighbour_arrival_cache.clear()
		var state: Dictionary = game.neighbour_arrival_state(screen)
		var found_control_draw := false
		for draw in state.get("random_tape", []):
			if draw.size() >= 3 and int(draw[0]) == 4 and int(draw[1]) == 1:
				found_control_draw = true
				if int(draw[2]) == 1: return
		if found_control_draw: continue
	failures.append("Could not find deterministic random(4,1)=1 seed for screen 440")
	push_error(failures.back())
	game.neighbour_seed_override = 1
	game.neighbour_arrival_cache.clear()

func _normalize_prediction(state: Dictionary, first_created_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in state.get("sprites", []):
		if _visible_by_state(e) and _visible_on_screen(e):
			out.append(_normalize_entity(e, str(e.get("_arrival_id", "")), true))
	out.sort_custom(func(a: Dictionary, b: Dictionary): return str(a.key) < str(b.key))
	return out

func _normalize_live(host, first_created_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ids: Array = host.entities.keys()
	ids.sort()
	var created_ordinal := 0
	for id in ids:
		if int(id) == 1: continue
		var e: Dictionary = host.entities[id]
		var identity: String
		if int(e.get("editor_num", 0)) > 0:
			identity = "editor:%d" % int(e.get("editor_num", 0))
		else:
			created_ordinal += 1
			identity = "created:%d" % created_ordinal
		var visible: bool = host.visuals.has(id) and is_instance_valid(host.visuals[id]) and bool(host.visuals[id].visible) and _visible_by_state(e) and _visible_on_screen(e)
		if visible:
			out.append(_normalize_entity(e, identity, visible))
	out.sort_custom(func(a: Dictionary, b: Dictionary): return str(a.key) < str(b.key))
	return out

func _visible_by_state(e: Dictionary) -> bool:
	return int(e.get("active", 1)) != 0 and int(e.get("nodraw", 0)) == 0 and int(e.get("disabled", 0)) == 0 and int(e.get("type", 1)) != 2

func _visible_on_screen(e: Dictionary) -> bool:
	if not _visible_by_state(e): return false
	var seq := int(e.get("seq", 0))
	var frame := int(e.get("frame", 1))
	if seq == 0:
		seq = int(e.get("pseq", 0))
		frame = int(e.get("pframe", 1))
	var data: Dictionary = game._frame(seq, frame)
	if data.is_empty(): return false
	var texture = game._texture(str(data.get("path", "")))
	if texture == null: return false
	var scale := maxf(0.01, float(e.get("size", 100)) / 100.0)
	var dx := float(data.get("dx", texture.get_width() / 2.0))
	var dy := float(data.get("dy", texture.get_height() - 10.0))
	var left := float(e.get("x", 320)) - dx * scale
	var top := float(e.get("y", 200)) - dy * scale
	var clip_left := clampf((20.0 - left) / scale, 0.0, texture.get_width())
	var clip_top := clampf(-top / scale, 0.0, texture.get_height())
	var clip_right := clampf((620.0 - left) / scale, 0.0, texture.get_width())
	var clip_bottom := clampf((400.0 - top) / scale, 0.0, texture.get_height())
	return clip_right > clip_left and clip_bottom > clip_top

func _normalize_entity(e: Dictionary, identity: String, visible: bool) -> Dictionary:
	var out := {"key": identity, "visible": visible, "moving": bool(e.get("moving", false)), "script": str(e.get("script", "")).to_lower()}
	for property in PROPERTIES:
		if property == "visible": continue
		out[property] = e.get(property, 1 if property == "active" or property == "type" else 0)
	return out

func _has_moving_difference(expected: Array, actual: Array, _host) -> bool:
	var expected_by_key := {}
	var actual_by_key := {}
	for entity in expected: expected_by_key[entity.key] = entity
	for entity in actual: actual_by_key[entity.key] = entity
	for key in actual_by_key:
		if expected_by_key.has(key) and bool(actual_by_key[key].get("moving", false)):
			if absf(float(expected_by_key[key].x) - float(actual_by_key[key].x)) > 0.01 or absf(float(expected_by_key[key].y) - float(actual_by_key[key].y)) > 0.01:
				return true
	return false

func _classify_mismatch(uncertain: Array, cuts: Array, live_tasks: int, moving_difference: bool) -> String:
	if moving_difference: return "post-cut-motion"
	if not cuts.is_empty(): return "post-cut"
	for diagnostic in uncertain:
		var item := str(diagnostic)
		for command in ["wait", "say_stop", "say_stop_npc", "say_stop_xy", "move_stop", "freeze", "choice", "fade_down", "fade_up", "load_screen", "force_vision"]:
			if item.ends_with(": " + command): return "post-cut"
	if not uncertain.is_empty(): return "uncertain"
	return "inconclusive" if live_tasks > 0 else "unclassified"

func _difference_summary(expected: Array, actual: Array) -> Array:
	var expected_by_key := {}
	var actual_by_key := {}
	for e in expected: expected_by_key[e.key] = e
	for e in actual: actual_by_key[e.key] = e
	var keys: Dictionary = {}
	for key in expected_by_key: keys[key] = true
	for key in actual_by_key: keys[key] = true
	var differences: Array = []
	for key in keys:
		if not expected_by_key.has(key): differences.append({"key": key, "missing": "prediction"})
		elif not actual_by_key.has(key): differences.append({"key": key, "missing": "live", "expected": expected_by_key[key]})
		elif expected_by_key[key] != actual_by_key[key]: differences.append({"key": key, "expected": expected_by_key[key], "actual": actual_by_key[key]})
	return differences

func _write_line(value: Dictionary) -> void:
	var line := JSON.stringify(value)
	if report != null: report.store_line(line)
