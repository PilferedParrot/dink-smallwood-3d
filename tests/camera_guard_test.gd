extends SceneTree

# Unit 3, checks G6, G3 and G7.
#  G6  the guard formula against the near-plane corner built explicitly, and against literal pins;
#  G3  the camera's clearance from solids, with the player's feet standing on the raw edge of every class of solid
#      (sprite hardbox, fitted footprint, Hard.dat tile, stone wall, fir, the seam to a neighbour screen), measured by an
#      oracle that is denser than the guard's own search (64 directions every quarter pixel);
#  G7  what the guard costs.
# The camera under test is the production one: game._sync_fps_camera() with a real Camera3D (near and fov as the game sets
# them); the requirement is built here from the near-plane corner, independently of camera_guard.gd's formula.
# Usage: godot --headless --path game --script tests/camera_guard_test.gd [-- --report=PATH]

const GUARD := preload("res://scripts/camera_guard.gd")
const SCALE := 0.025
const NEAR := 0.03
const FOV := 80.0
const ASPECT := 16.0 / 9.0 # no window in this test: the game falls back to 16:9
const TOLERANCE := 0.75 # px: the guard's search is a ray fan; the oracle's resolution is 0.25 px
const MAX_PER_CLASS_PER_SCREEN := 6

var game
var failures: Array = []
var report_path := ""
var only_screens: Array[int] = []
var classes := {}
var deficits: Array = []
var open_us: Array = []
var near_us: Array = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report_path = arg.trim_prefix("--report=")
		if arg.begins_with("--screens="):
			for value in arg.trim_prefix("--screens=").split(",", false): only_screens.append(int(value))
	_run.call_deferred()

func check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
		print("FAIL ", what)

func _formula() -> void:
	# The near rectangle's corner, built as a vector, against the closed form the game uses.
	var pins := {[60.0, 16.0 / 9.0]: 1.85, [78.0, 16.0 / 9.0]: 2.32, [80.0, 16.0 / 9.0]: 2.38, [90.0, 16.0 / 9.0]: 2.73,
		[105.0, 16.0 / 9.0]: 3.41, [80.0, 21.0 / 9.0]: 2.82, [105.0, 21.0 / 9.0]: 4.15, [105.0, 32.0 / 9.0]: 5.90,
		[60.0, 1.6]: 1.77}
	for key in pins:
		var fov: float = key[0]
		var aspect: float = key[1]
		var half_h := NEAR * tan(deg_to_rad(fov) * 0.5)
		var corner := Vector3(half_h * aspect, half_h, NEAR).length() / SCALE
		check(absf(GUARD.reach_px(NEAR, fov, aspect, SCALE) - corner) < 0.0001, "reach_px equals the explicit near-plane corner at %s" % [key])
		check(absf(GUARD.reach_px(NEAR, fov, aspect, SCALE) - float(pins[key])) < 0.01, "reach_px pin %s = %.2f" % [key, float(pins[key])])
		check(absf(GUARD.guard_px(NEAR, fov, aspect, SCALE) - corner - GUARD.PROP_OVERHANG_PX) < 0.0001, "guard_px adds the prop overhang at %s" % [key])
	# A guard from `near` alone (a flat 1.2 px, no frustum corners) is the wrong formula: it must miss the ultrawide corner.
	check(GUARD.reach_px(NEAR, 105.0, 21.0 / 9.0, SCALE) > NEAR / SCALE + 2.5, "the corner reach exceeds the face distance on an ultrawide")

func _setup() -> void:
	game = load("res://../tests/collision_survey_host.gd").new()
	game.world = game._read_json("res://data/world.json")
	game.sequences = game._read_json("res://data/sequences.json").sequences
	game.footprints = game._read_json("res://data/footprints.json").screens
	game.vm = game.VM.new(game)
	game.vm.load_story()
	game.camera = Camera3D.new()
	game.settings["fov"] = FOV

# The game's own camera for feet at `foot`, back in source pixels.
func _camera_for(foot: Vector2) -> Vector2:
	game.entities[1]["x"] = foot.x
	game.entities[1]["y"] = foot.y
	game._sync_fps_camera()
	return Vector2(game.camera.position.x / SCALE + 320.0, game.camera.position.z / SCALE + 200.0)

func _solid_class(q: Vector2, n: int) -> String:
	if game._blocking_sprite(q, 1) != 0: return "sprite"
	if game._footprint_blocked(q): return "footprint"
	if game.stone_walls.blocked(q, Vector2.INF, n): return "stone"
	if game.fir_collision.blocked(q, Vector2.INF, n): return "fir"
	if game._tile_blocked(q): return "tile"
	return "other" if game._blocked(q, 1) else ""

# The oracle: the distance from c to the nearest blocked sample over 64 directions, every quarter pixel out to `limit`.
func _clearance(c: Vector2, limit: float) -> float:
	var best := limit
	for k in 64:
		var u := Vector2.RIGHT.rotated(TAU * float(k) / 64.0)
		var r := 0.25
		while r < best:
			if game._blocked(c + u * r, 1, c): best = r; break
			r += 0.25
	return best

func _feasible(foot: Vector2, guard: float) -> bool:
	# Is there any free camera position within 2 guards of the feet that has the full clearance?
	var reach := int(ceil(guard * 2.0))
	for dx in range(-reach, reach + 1):
		for dy in range(-reach, reach + 1):
			var c := foot + Vector2(dx, dy)
			if c.distance_to(foot) > guard * 2.0 or game._blocked(c, 1, foot): continue
			if _clearance(c, guard) >= guard - TOLERANCE: return true
	return false

func _boundary_feet(n: int) -> Dictionary:
	# Free points within 1 px of a solid, found on a 3 px grid and 0.5 px probes round each, by class of the solid.
	var found := {}
	for y in range(0, 400, 3):
		for x in range(14, 626, 3):
			var p := Vector2(x, y)
			if game._blocked(p, 1): continue
			for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				var cls := _solid_class(p + d, n)
				if cls == "": continue
				var key := "seam" if (p + d).x < 20.0 or (p + d).x >= 620.0 or (p + d).y < 0.0 or (p + d).y >= 400.0 else cls
				if not found.has(key): found[key] = []
				(found[key] as Array).append(p)
				break
	return found

func _screens() -> Array[int]:
	if not only_screens.is_empty(): return only_screens
	# Screens that carry each class: fitted stone walls, fir rectangles, and the village/cottage maps of the triage.
	var picked: Array[int] = [408, 409, 439, 2, 3]
	for key in game.fir_collision.data.get("by_screen", {}):
		if picked.size() >= 9: break
		var n := int(key)
		if not (n in picked) and not game.fir_collision.rectangles(n).is_empty(): picked.append(n)
	for key in game.world.screens:
		var n := int(key)
		if picked.size() >= 12: break
		if not (n in picked) and not game.stone_walls.get_fit(n).is_empty(): picked.append(n)
	return picked

func _run() -> void:
	_formula()
	_setup()
	# The required distance, from the near-plane corner built as a vector: what the camera must keep, whatever the code computes.
	var half_h := NEAR * tan(deg_to_rad(FOV) * 0.5)
	var guard: float = Vector3(half_h * ASPECT, half_h, NEAR).length() / SCALE + GUARD.PROP_OVERHANG_PX
	var worst := 0.0
	var narrow := 0
	for n in _screens():
		game.load_map(n, false)
		var feet := _boundary_feet(n)
		for cls in feet:
			var list: Array = feet[cls]
			var step := maxi(1, list.size() / MAX_PER_CLASS_PER_SCREEN)
			for i in range(0, list.size(), step):
				var foot: Vector2 = list[i]
				var t0 := Time.get_ticks_usec()
				var c: Vector2 = _camera_for(foot)
				near_us.append(Time.get_ticks_usec() - t0)
				classes[cls] = int(classes.get(cls, 0)) + 1
				check(not game._blocked(c, 1, foot), "screen %d %s foot %s: the camera %s stands inside a solid" % [n, cls, foot, c])
				check(c.distance_to(foot) <= guard * 2.0 + 0.001, "screen %d %s foot %s: the camera is %.2f px from the feet, more than 2 guards" % [n, cls, foot, c.distance_to(foot)])
				var clearance := _clearance(c, guard)
				var deficit := guard - clearance
				if deficit > TOLERANCE:
					if _feasible(foot, guard):
						check(false, "screen %d %s foot %s: clearance %.2f < guard %.2f although a camera position with the full clearance exists" % [n, cls, foot, clearance, guard])
					else:
						narrow += 1
				else:
					worst = maxf(worst, maxf(0.0, deficit))
		# Open ground: a free point with nothing within the guard costs one scan.
		for probe in [Vector2(320, 200), Vector2(200, 100), Vector2(450, 300)]:
			if game._blocked(probe, 1) or _clearance(probe, guard + 1.0) < guard + 1.0: continue
			var t0 := Time.get_ticks_usec()
			var c: Vector2 = _camera_for(probe)
			open_us.append(Time.get_ticks_usec() - t0)
			check(c == probe, "screen %d open ground %s: the camera moved to %s" % [n, probe, c])
	for needed in (["sprite", "footprint", "tile", "stone", "fir", "seam"] if only_screens.is_empty() else []):
		check(int(classes.get(needed, 0)) >= 3, "G3 covers at least three cases of the %s class (has %d)" % [needed, int(classes.get(needed, 0))])
	var mean_near := 0.0
	for u in near_us: mean_near += float(u)
	mean_near /= maxf(1.0, float(near_us.size()))
	var mean_open := 0.0
	for u in open_us: mean_open += float(u)
	mean_open /= maxf(1.0, float(open_us.size()))
	near_us.sort()
	var result := {"guard_px": guard, "cases_by_class": classes, "narrow_infeasible": narrow, "worst_deficit_px_in_tolerance": worst,
		"tolerance_px": TOLERANCE, "near_solid_us": {"n": near_us.size(), "mean": mean_near, "max": near_us.back() if near_us.size() else 0},
		"open_ground_us": {"n": open_us.size(), "mean": mean_open}, "failures": failures}
	print("CAMERA GUARD ", JSON.stringify(result))
	if not report_path.is_empty():
		var file := FileAccess.open(report_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(result, "\t"))
	game.vm.cancel_all()
	game.free()
	if failures.is_empty(): print("CAMERA GUARD PASS")
	quit(0 if failures.is_empty() else 1)
