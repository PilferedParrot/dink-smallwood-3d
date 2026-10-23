extends SceneTree

# Unit 3: the distance field the camera guard stands on (game.gd _solid_nearest) is the same set of solids as `_blocked`.
# On every screen, at seeded random points (inside the screen and across its seams), against `_blocked` itself:
#   (a) a point is blocked exactly when its distance is 0 (a point on a half-open box's far edge is outside it, a hair away);
#   (b) the distance is right: no blocked sample closer (64 directions, every half pixel), and a blocked sample next to
#       the reported closest point;
# and its cost (G7): reported, and held to four times the registered budget so a slow regression fails here.
# Usage: godot --headless --path game --script tests/clearance_field_test.gd [-- --report=PATH]

const LIMIT := 8.0
const POINTS_PER_SCREEN := 12
const CHECKED_POINTS := 900
var game
var failures: Array = []
var counts := {"points": 0, "blocked": 0, "free": 0, "near": 0, "clear": 0, "distance_checked": 0}
var near_us: Array = []
var open_us: Array = []
var report_path := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report_path = arg.trim_prefix("--report=")
	_run.call_deferred()

func check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
		if failures.size() <= 30: print("FAIL ", what)

func _setup() -> void:
	game = load("res://../tests/collision_survey_host.gd").new()
	game.world = game._read_json("res://data/world.json")
	game.sequences = game._read_json("res://data/sequences.json").sequences
	game.footprints = game._read_json("res://data/footprints.json").screens
	game.vm = game.VM.new(game)
	game.vm.load_story()

func _closer_blocked(p: Vector2, below: float) -> bool:
	for k in 64:
		var u := Vector2.RIGHT.rotated(TAU * float(k) / 64.0)
		var r := 0.5
		while r < below:
			if game._blocked(p + u * r, 1): return true
			r += 0.5
	return false

# Review finding 4: a neighbour footprint that hangs over its screen's edge is solid only inside that screen. Injected valid
# footprint on 440 spanning x 18..30 (its screen starts at 20): from 439's east edge the nearest solid is at x = 620.
func _neighbour_footprint() -> void:
	var saved = game.footprints.get("440")
	game.footprints["440"] = {"polys": [{"pts": [[18, 180], [30, 180], [30, 220], [18, 220]], "owner": 0}]}
	game.survey_states.erase(440)
	game.load_map(439, false)
	var p := Vector2(619.0, 200.0)
	check(not game._blocked(p, 1), "the injected overhang does not block 439's own cell (619,200)")
	var hit: Array = game._solid_nearest(p, LIMIT)
	check(absf(float(hit[0]) - 1.0) < 0.01 and absf((hit[1] as Vector2).x - 620.0) < 0.01, "the field sees 440's solid only from x = 620 (got %s)" % [hit])
	var far: Array = game._solid_nearest(Vector2(610.0, 200.0), 3.0)
	check(far[0] == INF, "nothing within 3 px of (610,200): the overhang is not 439's solid")
	if saved == null: game.footprints.erase("440")
	else: game.footprints["440"] = saved
	game.survey_states.erase(440)

func _run() -> void:
	_setup()
	_neighbour_footprint()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var checked := 0
	var keys: Array = game.world.screens.keys()
	for key in keys:
		var n := int(key)
		game.load_map(n, false)
		for _i in POINTS_PER_SCREEN:
			# Inside the screen (the camera's feet never stand outside it); half of the points hug an edge, where the
			# neighbours' solids and the edge of the world are within reach.
			var p := Vector2(rng.randf_range(20.0, 619.999), rng.randf_range(0.0, 399.999))
			if _i % 2 == 1:
				match _i % 8:
					1: p.x = rng.randf_range(20.0, 20.0 + LIMIT)
					3: p.x = rng.randf_range(620.0 - LIMIT, 619.999)
					5: p.y = rng.randf_range(0.0, LIMIT)
					_: p.y = rng.randf_range(400.0 - LIMIT, 399.999)
			counts.points += 1
			var t0 := Time.get_ticks_usec()
			var hit: Array = game._solid_nearest(p, LIMIT)
			var dt := Time.get_ticks_usec() - t0
			var d: float = hit[0]
			var blocked: bool = game._blocked(p, 1)
			if blocked: counts.blocked += 1
			else: counts.free += 1
			check(blocked == (d <= 0.0), "screen %d at %s: blocked=%s but the field says distance %s" % [n, p, blocked, d])
			if d == INF:
				counts.clear += 1
				open_us.append(dt)
				continue
			counts.near += 1
			near_us.append(dt)
			if blocked or checked >= CHECKED_POINTS: continue
			checked += 1
			counts.distance_checked += 1
			check(not _closer_blocked(p, maxf(0.0, d - 0.6)), "screen %d at %s: a blocked sample lies closer than the reported distance %.2f" % [n, p, d])
			var q: Vector2 = hit[1]
			var touching := false
			for k in 8:
				if game._blocked(q + Vector2.RIGHT.rotated(TAU * float(k) / 8.0) * 0.3, 1): touching = true
			check(touching or game._blocked(q, 1), "screen %d at %s: nothing blocked beside the reported closest point %s" % [n, p, q])
	check(counts.near >= 300 and counts.clear >= 300 and counts.blocked >= 20, "the sample has near, clear and blocked points %s" % [counts])
	var mean_near := 0.0
	for u in near_us: mean_near += float(u)
	mean_near /= maxf(1.0, float(near_us.size()))
	var mean_open := 0.0
	for u in open_us: mean_open += float(u)
	mean_open /= maxf(1.0, float(open_us.size()))
	near_us.sort()
	var worst: float = near_us.back() if near_us.size() else 0.0
	var p99: float = near_us[int(0.99 * float(near_us.size() - 1))] if near_us.size() else 0.0 # the max is the machine's, not the code's
	var result := {"counts": counts, "near_us_mean": mean_near, "near_us_p99": p99, "near_us_max": worst, "open_us_mean": mean_open, "failures": failures.size()}
	print("CLEARANCE FIELD ", JSON.stringify(result))
	if not report_path.is_empty():
		var file := FileAccess.open(report_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(result, "\t"))
	check(mean_open < 4000.0 and mean_near < 12000.0 and p99 < 40000.0, "cost within four times the registered budget (open %.0f us, near %.0f us, p99 %.0f us)" % [mean_open, mean_near, p99])
	game.vm.cancel_all()
	game.free()
	if failures.is_empty(): print("CLEARANCE FIELD PASS")
	quit(0 if failures.is_empty() else 1)
