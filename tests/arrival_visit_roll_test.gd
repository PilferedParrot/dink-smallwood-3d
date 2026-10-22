extends SceneTree
## Part 2 of the save-roll unit: a screen's startup draws (random() before its first
## blocking command) are rolled once per VISIT. FreeDink 109.6 loads a screen fresh on
## every entry and its startup scripts draw again; our neighbour preview shows that
## roll early and the arrival must reuse it (tests/fps_neighbor_crossing.gd), but not
## beyond the visit (docs/DIRECTION.md NEIGHBOUR_STARTUP_PLAN, commit e6cf088).
## Triage engine control (tools/triage_arrival_rng.gd): 20 same-state requests keep the
## first outcome, because neighbour_arrival_cache never forgets a visit.
##
## Statistics (pre-registered): 441's FINDDUCK draws random(4,1) and hides the duck
## unless it returns 1 (vision 2 = duck), p(duck) = 1/4. Seeds 0..N-1 are fed to the
## private preview RNG (neighbour_seed_override), so the run is deterministic. N = 120
## gives mean 30 ducks, sd 4.74; accept 11..49 (+-4 sd). The oracle is exact: visit i
## must equal what the sandbox draws for seed i. The unseeded control (N = 60) must see
## both outcomes; a single-outcome result has probability .75^60 + .25^60 = 3e-8.
const GAME := preload("res://scripts/fps_game.gd")
const SANDBOX := preload("res://scripts/neighbour_script_sandbox.gd")
const DUCK_SCREEN := 441
const NEIGHBOUR := 442 # east of 441, outdoors, no startup draw of its own
const FAR := 444 # three columns from 441: outside its 5x5 preview block
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
func sandbox_duck(seed: int) -> bool:
	return int(SANDBOX.new(game, DUCK_SCREEN, seed).run_startup().vision) == 2
# One visit as the player lives it: stand next to the screen (its preview is built
# with `seed`), step onto it, and read the arrival's duck, then walk off to the neighbour.
func visit(seed: int) -> Dictionary:
	game.neighbour_seed_override = seed
	game.load_map(NEIGHBOUR, true)
	var preview: Dictionary = game.fp_world.neighbour_states.get(DUCK_SCREEN, {})
	game.load_map(DUCK_SCREEN, true)
	var live_vision := int(game.vm.globals.get("vision", 0))
	var arrival: Dictionary = game._incoming_arrival_basis
	return {"preview": int(preview.get("vision", -1)), "arrival": int(arrival.get("vision", -1)), "live": live_vision}
func _run() -> void:
	await fresh_game()
	check(game.world.screens.has(str(DUCK_SCREEN)) and str(game.world.screens[str(DUCK_SCREEN)].script).to_lower() == "findduck", "441 runs FINDDUCK")
	# 1. 120 same-state re-entries with seeds 0..119 follow the sandbox draw of each seed.
	var ducks := 0
	var follows := 0
	var mismatched_preview := 0
	var n := 120
	for seed in n:
		var got := await visit(seed)
		var want := sandbox_duck(seed)
		if (got.arrival == 2) == want: follows += 1
		if got.preview != got.arrival: mismatched_preview += 1
		if got.arrival == 2: ducks += 1
		check((got.live == 2) == (got.arrival == 2), "visit %d: live startup agrees with the arrival roll (live %d, arrival %d)" % [seed, got.live, got.arrival])
	check(follows == n, "every re-entry rolls its own seed: %d of %d visits equal the sandbox draw for their seed" % [follows, n])
	check(ducks >= 11 and ducks <= 49, "duck outcome at about 1/4 over %d same-state re-entries: %d ducks (accept 11..49)" % [n, ducks])
	check(mismatched_preview == 0, "preview and arrival share one roll on every visit (%d mismatches)" % mismatched_preview)
	print("SEEDED RE-ENTRIES n=%d ducks=%d follows_seed=%d preview_mismatch=%d cache_keys=%d" % [n, ducks, follows, mismatched_preview, game.neighbour_arrival_cache.size()])
	# 2. unseeded: both outcomes occur.
	var seen := {}
	for i in 60:
		var got := await visit(-1)
		seen[got.arrival] = true
	check(seen.size() == 2, "unseeded re-entries show both outcomes, saw %s" % [seen.keys()])
	# 3. a fixed seed is deterministic where determinism is wanted.
	var first := await visit(3)
	for i in 5:
		var again := await visit(3)
		check(again.arrival == first.arrival, "a fixed seed gives the same arrival on every visit")
	# 4. a preview that goes stale ends: approach 441, wander three screens away, come back.
	game.neighbour_seed_override = 5
	game.load_map(NEIGHBOUR, true)
	var before: int = int(game.fp_world.neighbour_states.get(DUCK_SCREEN, {}).get("vision", -1))
	game.load_map(FAR, true)
	var other_seed := 6
	while sandbox_duck(other_seed) == sandbox_duck(5): other_seed += 1
	game.neighbour_seed_override = other_seed
	game.load_map(NEIGHBOUR, true)
	var after: int = int(game.fp_world.neighbour_states.get(DUCK_SCREEN, {}).get("vision", -1))
	check(before != after and (after == 2) == sandbox_duck(other_seed), "a preview that left the block is rolled again (before %d, after %d)" % [before, after])
	print("ARRIVAL ROLL FAILURES ", JSON.stringify(failures))
	print("ARRIVAL ROLL PASS" if failures.is_empty() else "ARRIVAL ROLL FAIL")
	game.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
