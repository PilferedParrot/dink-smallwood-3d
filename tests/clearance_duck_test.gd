extends SceneTree

# Unit 3, check G2: the 441 duck. Its authored start (489,213) lies inside the raw hardbox of fence 13; the original lets
# it walk out (FreeDink check_if_move_is_legal reads only the destination pixel, and (488,212) / (489,212) are outside
# the box). The retired 4 px growth made the whole neighbourhood solid and the escape rule (both points outside the RAW
# box) could not admit it: 3,600 blocked ticks.
# Plus the CLASS (every mover in every screen, not only this one): an actor's one-pixel steps are blocked by exactly the
# raw hardboxes of the other solid sprites, nothing wider.
# Usage: godot --headless --path game --script tests/clearance_duck_test.gd

const DUCK_SCRIPT := "s1-oldd"
var game
var failures: Array = []
var counts := {"actors": 0, "inside_raw": 0, "steps": 0}

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
		print("FAIL ", what)

func _setup() -> void:
	game = load("res://../tests/collision_survey_host.gd").new()
	game.world = game._read_json("res://data/world.json")
	game.sequences = game._read_json("res://data/sequences.json").sequences
	game.footprints = game._read_json("res://data/footprints.json").screens
	game.vm = game.VM.new(game)
	game.vm.load_story()

# The other solid sprites' raw rectangles, as _blocking_sprite reads them.
func _solid_rects(except_id: int) -> Array:
	var rects: Array = []
	for id in game.entities:
		if id == 1 or id == except_id: continue
		var e: Dictionary = game.entities[id]
		if int(e.get("active", 1)) == 0 or int(e.get("hard", 1)) != 0 or e.get("warp") != null: continue
		if game._sprite_hardbox_replaced(e): continue
		rects.append(game._hard_rect(e))
	return rects

func _add_actor(number: int, source: Dictionary) -> int:
	var e: Dictionary = game.editor_entity(number, source, true, int(source.get("vision", 0)))
	if e.is_empty(): return 0
	var id := 5000 + int(source.get("index", 0))
	game.entities[id] = e
	return id

func _duck() -> void:
	game.load_map(441, false)
	var source := {}
	for s in game.world.screens["441"].sprites:
		if str(s.get("script", "")) == DUCK_SCRIPT and int(s.get("vision", 0)) == 2: source = s
	check(not source.is_empty(), "screen 441 has the vision-2 duck")
	if source.is_empty(): return
	var id := _add_actor(441, source)
	check(id != 0, "the duck entity builds")
	var start: Vector2 = game._position2(id)
	check(start == Vector2(489, 213), "the duck starts at its authored point %s" % start)
	check(game._blocking_sprite(start, id) != 0, "the start lies inside a raw hardbox (fence 13): the occupied-start case")
	check(not game._blocked(Vector2(488, 212), id, start), "the first NW step of the original is legal")
	check(not game._blocked(Vector2(489, 212), id, start), "the first N step of the original is legal")
	check(game._blocked(Vector2(489, 214), id, start), "a step that stays inside the fence is blocked, as in the original")
	# The brain: 3,600 ticks of the production AI step, nothing else moving.
	seed(441)
	var e: Dictionary = game.entities[id]
	e["brain"] = 3
	e["frozen"] = false
	var left := false
	var travelled := 0.0
	var last := start
	for _tick in 3600:
		game._update_ai(1.0 / 60.0)
		var p: Vector2 = game._position2(id)
		travelled += p.distance_to(last)
		last = p
		if game._blocking_sprite(p, id) == 0: left = true
	check(left, "3,600 ticks of brain 3 take the duck out of the fence")
	check(travelled > 100.0, "the duck walks (%.0f px in 3,600 ticks)" % travelled)

func _class() -> void:
	# Every actor of every screen (any vision), for every one-pixel step from its start.
	var steps := [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1), Vector2(1, 1), Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1)]
	for key in game.world.screens:
		var number := int(key)
		var movers: Array = []
		for s in game.world.screens[key].sprites:
			if int(s.get("brain", 0)) in [3, 4, 9, 10, 16] and int(s.get("hard", 1)) != 0: movers.append(s)
		if movers.is_empty(): continue
		game.load_map(number, false)
		for source in movers:
			var id := _add_actor(number, source)
			if id == 0: continue
			counts.actors += 1
			var start: Vector2 = game._position2(id)
			var rects := _solid_rects(id)
			var inside := rects.any(func(r: Rect2) -> bool: return r.has_point(start))
			if inside: counts.inside_raw += 1
			for d in steps:
				var q: Vector2 = start + d
				var raw := rects.any(func(r: Rect2) -> bool: return r.has_point(q))
				var live: bool = game._blocking_sprite(q, id, start) != 0
				counts.steps += 1
				check(raw == live, "screen %d actor %d at %s step %s: raw hardbox says %s, the mover says %s" % [number, int(source.get("index", 0)), start, d, raw, live])
			game.entities.erase(id)

func _run() -> void:
	_setup()
	_duck()
	_class()
	check(counts.actors > 100, "the class covers the actors of the world (%d)" % counts.actors)
	check(counts.inside_raw >= 1, "the class includes actors that start inside a raw hardbox (%d)" % counts.inside_raw)
	print("CLEARANCE DUCK ", JSON.stringify(counts))
	game.vm.cancel_all()
	game.free()
	if failures.is_empty(): print("CLEARANCE DUCK PASS")
	quit(0 if failures.is_empty() else 1)
