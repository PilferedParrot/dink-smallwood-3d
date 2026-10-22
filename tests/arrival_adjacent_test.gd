extends SceneTree
## Save-roll fix round 1, F1. The duck you SEE in a neighbour's preview is the duck you
## meet on arrival, also when the screen you stand on shares its startup script with the
## one you step onto (440 -> 441, both findduck).
## Cause it pins: the sandbox ran a screen main as a persistent-locals instance
## (neighbour_script_sandbox.gd, default new_instance=false) and exported the locals, while
## the live load runs it as a NEW instance whose locals die with the task (game.gd
## load_map; FreeDink 109.6 game_engine.cpp:710-721 load_script(...) + run_script, dinkc.cpp
## locate/load_script give every screen load a fresh script instance). The arrival key hashes
## the target script's `<script>:0` locals, so the preview of 441 (basis carries findduck:0)
## and the arrival (live VM has none) keyed differently, and the arrival rerolled.
## Preview and arrival here use DIFFERENT RNG seeds (neighbour_seed_override), so a reroll
## cannot hide behind a shared seed.
## Class: every directed pair of adjacent screens (+-1, +-32) whose startup script is the
## same and has a main (census below), same assertion.
const GAME := preload("res://scripts/fps_game.gd")
const SANDBOX := preload("res://scripts/neighbour_script_sandbox.gd")
var game
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); push_error(message)
func fresh_game() -> void:
	if game != null: game.queue_free(); await process_frame
	game = GAME.new(); game.test_mode = true
	root.add_child(game); await process_frame
	await game._new_game()
	game.vm.cancel_all()
	game.vm.globals["story"] = 1
	game.vm.globals["old_womans_duck"] = 1
	game.neighbour_arrival_cache.clear()
	game.ui.close_menu(); game.playing = true
func script_of(n: int) -> String:
	var s: String = str(game.world.screens.get(str(n), {}).get("script", "")).to_lower().replace("_", "-")
	if s.is_empty() or game.vm._procedure_code(s, "main").is_empty(): return ""
	return s
func tape(screen: int, seed: int) -> Array:
	return SANDBOX.new(game, screen, seed).run_startup().random_tape
func shown(r: Dictionary) -> String:
	return JSON.stringify([r.get("vision", -1), r.get("random_tape", []), r.get("sprites", [])])
func settle() -> void:
	# let the deferred sprite mains of the live load finish
	for i in 3: await process_frame
func _run() -> void:
	await fresh_game()
	# 1. the report: a real walk 439 -> 440 -> 441, a different seed at every step.
	var seeds := [-1, -1]
	var fixture := 0
	for a in 24:
		for b in range(a + 1, 24):
			if seeds[0] < 0 and tape(441, a) != tape(441, b): seeds = [a, b]
	check(seeds[0] >= 0, "fixture: two seeds draw different 441 duck rolls")
	var walks := 0
	for order in 2:
		await fresh_game()
		var s439: int = seeds[0] if order == 0 else seeds[1]
		var s440: int = seeds[1] if order == 0 else seeds[0]
		var s441 := 97
		game.neighbour_seed_override = s439
		game.load_map(439, true)
		await settle()
		game.neighbour_seed_override = s440
		game.load_map(440, true)
		await settle()
		var seen: Dictionary = game.fp_world.neighbour_states.get(441, {})
		check(not seen.is_empty(), "fixture: 441 is previewed from 440")
		game.neighbour_seed_override = s441
		game.load_map(441, true)
		await settle()
		var met: Dictionary = game._incoming_arrival_basis
		check(shown(seen) == shown(met), "walk 439(seed %d) -> 440(seed %d) -> 441(seed %d): the preview of 441 shows vision %d, tape %s; arrival has vision %d, tape %s" % [s439, s440, s441, int(seen.get("vision", -1)), str(seen.get("random_tape", [])), int(met.get("vision", -1)), str(met.get("random_tape", []))])
		check(int(game.vm.globals.get("vision", 0)) == int(seen.get("vision", -1)), "live startup of 441 completed on the previewed vision (live %d, previewed %d)" % [int(game.vm.globals.get("vision", 0)), int(seen.get("vision", -1))])
		walks += 1
	# 2. the class: every adjacent pair sharing a startup script.
	var census: Array = []
	for key in game.world.screens:
		var n := int(key)
		var sc := script_of(n)
		if sc.is_empty(): continue
		for d in [1, -1, 32, -32]:
			var m: int = n + d
			if (d == 1 and (n - 1) % 32 == 31) or (d == -1 and (n - 1) % 32 == 0): continue
			if game.world.screens.has(str(m)) and script_of(m) == sc: census.append([n, m, sc])
	census.sort()
	check(census.size() >= 20 and census.has([440, 441, "findduck"]) and census.has([441, 440, "findduck"]), "census sees the known sharing pairs (%d directed pairs; instrument check)" % census.size())
	var compared := 0
	var no_preview: Array = []
	for pair in census:
		var x: int = pair[0]
		var y: int = pair[1]
		var a := 0
		var b := 1
		for s1 in 16:
			for s2 in range(s1 + 1, 16):
				if a == 0 and b == 1 and tape(y, s1) != tape(y, s2): a = s1; b = s2
		await fresh_game()
		game.neighbour_seed_override = a
		game.load_map(x, true)
		await settle()
		var seen: Dictionary = game.fp_world.neighbour_states.get(y, {})
		if seen.is_empty(): no_preview.append(pair); continue
		game.neighbour_seed_override = b
		game.load_map(y, true)
		await settle()
		check(shown(seen) == shown(game._incoming_arrival_basis), "pair %d -> %d (%s), preview seed %d, arrival seed %d: the screen previewed is not the screen met" % [x, y, pair[2], a, b])
		compared += 1
	print("ARRIVAL ADJACENT walks=%d directed_pairs=%d compared=%d no_preview=%s" % [walks, census.size(), compared, str(no_preview)])
	print("ARRIVAL ADJACENT CENSUS ", census)
	print("ARRIVAL ADJACENT FAILURES ", JSON.stringify(failures))
	print("ARRIVAL ADJACENT PASS" if failures.is_empty() else "ARRIVAL ADJACENT FAIL")
	game.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
