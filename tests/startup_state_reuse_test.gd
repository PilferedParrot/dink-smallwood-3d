extends SceneTree
## What a neighbour preview and a sandboxed `external` may carry from one state or run to the next.
## R5 (mut.py): a preview is a startup roll made from the state it was drawn in; a load REPLACES that state, so a
##   preview built before it must be rolled again after it (FreeDink 109.6 loads a screen afresh on every entry). The
##   key (screen + story state) is the same on both sides here on purpose (the second load of one file), so only the
##   clear can end the roll. _new_game's own clear is not testable: the new game's first load_map drops every preview
##   outside the start screen's block anyway (MUTANT-RED.md R5b).
## R6 (mut.py): the sandbox's `external` runs the called script as a NEW instance whose locals die with it (game.gd
##   `external` is vm.run(..., true)). Spawn and run_script_by_number share the spawned sprite's instance, which is
##   FreeDink's too, and is pinned here so that "make everything a new instance" is not the fix.
## 441's FINDDUCK draws random(4,1) and shows a duck (vision 2) only on 1, so two seeds can be told apart by it.
const GAME := preload("res://scripts/fps_game.gd")
const SANDBOX := preload("res://scripts/neighbour_script_sandbox.gd")
const DUCK_SCREEN := 441
const NEIGHBOUR := 442 # east of 441, outdoors, no startup draw of its own
const SAVE := "user://startup-state-reuse.json"
var game
var failures: Array[String] = []
var finished := 0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); push_error(message)
func fresh_game() -> void:
	if game != null: game.queue_free(); await process_frame
	game = GAME.new(); game.test_mode = true
	root.add_child(game); await process_frame
	await game._new_game()
	set_state()
	game.ui.close_menu(); game.playing = true
func set_state() -> void:
	game.vm.cancel_all()
	game.vm.globals["story"] = 1
	game.vm.globals["old_womans_duck"] = 1
	game.neighbour_arrival_cache.clear()
func duck(seed: int) -> bool:
	return int(SANDBOX.new(game, DUCK_SCREEN, seed).run_startup().vision) == 2
func seeds() -> Array:
	var a := 0
	var b := 1
	while duck(b) == duck(a): b += 1
	return [a, b]
func preview_is_duck() -> bool:
	return int(game.neighbour_arrival_state(DUCK_SCREEN).get("vision", -1)) == 2
func approach(seed: int) -> void:
	game.neighbour_seed_override = seed
	game.load_map(NEIGHBOUR, true) # builds the preview of 441 from here
func r5_load() -> void:
	await fresh_game()
	var s := seeds()
	check(game._save_game(SAVE), "fixture: the state saves")
	# A load does not restore bit-identical state to the one that was saved (the key of a preview built before it differs), so
	# first load once and take the preview from the loaded state: loading the same file again then gives that state back exactly.
	check(await game._load_game(SAVE), "fixture: the save loads")
	await approach(s[0])
	check(preview_is_duck() == duck(s[0]), "fixture: the preview built beside 441 is the draw of its seed")
	game.neighbour_seed_override = s[1]
	check(await game._load_game(SAVE), "fixture: the same save loads again")
	check(preview_is_duck() == duck(s[1]) and preview_is_duck() != duck(s[0]),
		"R5: after a load the preview of 441 is rolled again (duck %s; the pre-load roll gave %s, the new seed gives %s)" % [preview_is_duck(), duck(s[0]), duck(s[1])])
	finished += 1
func ins(op: String, target: String, expr: Variant, declare: String = "") -> Dictionary:
	var d := {"op": op, "target": target, "expr": expr}
	if not declare.is_empty(): d["declare"] = declare
	return d
func lit(v: Variant) -> Dictionary: return {"kind": "literal", "value": v}
func rf(n: String) -> Dictionary: return {"kind": "ref", "name": n}
func host_call(name: String, args: Array) -> Dictionary: return {"op": "call", "name": name, "args": args}
func startup_with(scripts: Dictionary, parent: String) -> Dictionary:
	var story_scripts: Dictionary = game.vm.story.scripts
	var screen: Dictionary = game.world.screens[str(NEIGHBOUR)]
	var before_script = screen.get("script", "")
	for name in scripts: story_scripts[name] = scripts[name]
	screen["script"] = parent
	var result: Dictionary = SANDBOX.new(game, NEIGHBOUR, 0).run_startup()
	screen["script"] = before_script
	for name in scripts: story_scripts.erase(name)
	return result
func child_script() -> Dictionary:
	return {"procedures": {
		"main": {"code": [ins("set", "&n", lit(5), "int")]},        # a LOCAL n = 5 in whatever instance runs it
		"init": {"code": [ins("set", "&n", lit(5), "int")]},
		"bump": {"code": [{"op": "inc", "target": "&n", "value": lit(1)}, ins("set", "&out", rf("&n"))]}}}
func r6_external() -> void:
	await fresh_game()
	# External twice, as DinkC does: init declares a local, bump (a second external) must not see it.
	var got := startup_with({
		"r6-parent": {"procedures": {"main": {"code": [
			host_call("external", [lit("r6-child"), lit("init")]),
			host_call("external", [lit("r6-child"), lit("bump")])]}}},
		"r6-child": child_script()}, "r6-parent")
	check(int(got.globals.get("out", -1)) == 1,
		"R6: an external is a new instance, so bump does not see init's local n=5 (out %s, want 1)" % [got.globals.get("out", "unset")])
	check(not got.sprite_locals.keys().any(func(k): return str(k).begins_with("r6-child")),
		"R6: no locals of an external survive its run (%s)" % [got.sprite_locals.keys()])
	finished += 1
func r6_spawned_sprite_keeps_its_instance() -> void:
	await fresh_game()
	# The other way round: a spawned sprite's script is ONE instance; run_script_by_number reaches its local.
	var got := startup_with({
		"r6-parent": {"procedures": {"main": {"code": [
			ins("set", "&sp", {"kind": "call", "name": "spawn", "args": [lit("r6-child")]}, "int"),
			host_call("run_script_by_number", [rf("&sp"), lit("bump")])]}}},
		"r6-child": child_script()}, "r6-parent")
	check(int(got.globals.get("out", -1)) == 6,
		"a spawned sprite keeps one instance: bump sees main's local n=5 (out %s, want 6)" % [got.globals.get("out", "unset")])
	finished += 1
func _run() -> void:
	await r5_load()
	await r6_external()
	await r6_spawned_sprite_keeps_its_instance()
	check(finished == 3, "every section ran to its end (%d of 3)" % finished)
	print("STARTUP STATE REUSE FAILURES ", JSON.stringify(failures))
	print("STARTUP STATE REUSE PASS" if failures.is_empty() else "STARTUP STATE REUSE FAIL")
	if game != null: game.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
