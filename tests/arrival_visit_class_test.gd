extends SceneTree
## The class behind tests/arrival_visit_roll_test.gd: EVERY screen whose scripts draw
## random() before their first blocking command (the sandbox's random tape, the same
## startup the live load replays) rolls once per visit, not once per session. Census:
## all screens, seeds 0..5, story state "duck_search" (the only fixture in which the two
## findduck screens draw; the others draw in every fixture). A screen is visited with
## seed a, left, and visited with seed b, where the sandbox's tapes for a and b differ;
## the second arrival must carry b's tape. Red on 638cec6 for every screen.
const GAME := preload("res://scripts/fps_game.gd")
const SANDBOX := preload("res://scripts/neighbour_script_sandbox.gd")
var game
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); push_error(message)
func tape(screen: int, seed: int) -> Array:
	return SANDBOX.new(game, screen, seed).run_startup().random_tape
func _run() -> void:
	game = GAME.new(); game.test_mode = true
	root.add_child(game); await process_frame
	await game._new_game(); game.vm.cancel_all()
	game.vm.globals["story"] = 1; game.vm.globals["old_womans_duck"] = 1
	game.ui.close_menu(); game.playing = true
	var census: Array[int] = []
	for key in game.world.screens:
		for seed in 6:
			if not tape(int(key), seed).is_empty(): census.append(int(key)); break
	census.sort()
	check(census.size() >= 100 and census.has(440) and census.has(441), "census sees the known startup-draw screens (%d found; instrument check)" % census.size())
	var pairs := 0
	for screen in census:
		var a := -1
		var b := -1
		for s1 in 16:
			for s2 in range(s1 + 1, 16):
				if a < 0 and tape(screen, s1) != tape(screen, s2): a = s1; b = s2
		if a < 0:
			check(false, "screen %d: no two seeds in 0..15 give different startup draws (inconclusive)" % screen)
			continue
		var other: int = screen + 1 if game.world.screens.has(str(screen + 1)) else screen - 1
		game.neighbour_seed_override = a
		game.load_map(other, true)
		game.load_map(screen, true)
		game.neighbour_seed_override = b
		game.load_map(other, true)
		game.load_map(screen, true)
		var got: Array = game._incoming_arrival_basis.get("random_tape", [])
		var want := tape(screen, b)
		check(got == want, "screen %d: second visit (seed %d) carries its own roll, not the first visit's (seed %d)" % [screen, b, a])
		pairs += 1
	print("ARRIVAL CLASS screens=%d visited_twice=%d" % [census.size(), pairs])
	print("ARRIVAL CLASS CENSUS ", census)
	print("ARRIVAL CLASS FAILURES ", JSON.stringify(failures))
	print("ARRIVAL CLASS PASS" if failures.is_empty() else "ARRIVAL CLASS FAIL")
	game.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
