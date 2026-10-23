extends SceneTree

# Unit 3A fix round (blind review review-20261023T214403-3d986137, findings 1-3): the camera guard's contracts on synthetic
# worlds, no game: every answer is on the camera's screen, is reached by a free slide from the feet (a thin wall is not a way
# through), and float32 noise on an edge does not start the expensive search. Each fixture is red on b1f80bc.
# Usage: godot --headless --path game --script tests/camera_guard_unit_test.gd

const GUARD := preload("res://scripts/camera_guard.gd")
const G := 5.38
var failures: Array = []
var calls := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
		print("FAIL ", what)

# A world of half-open boxes: Callable(point, limit) -> [distance, closest point], exactly the game's contract.
func _world(boxes: Array) -> Callable:
	return func(pos: Vector2, limit: float) -> Array:
		calls += 1
		var best := [INF, pos]
		for box: Rect2 in boxes:
			var at: Vector2 = preload("res://scripts/game.gd").box_nearest(pos, box.position, box.end)
			var d := pos.distance_to(at)
			if d <= limit and d < (best[0] as float):
				best[0] = d
				best[1] = at
		return best

func _free_slide(a: Vector2, b: Vector2, boxes: Array) -> bool:
	for i in range(0, 201):
		var p := a.lerp(b, float(i) / 200.0)
		for box: Rect2 in boxes:
			if box.has_point(p): return false
	return true

func _run() -> void:
	# 1. Finding 2: a thin wall behind the nearest one. The push would land beyond it; the camera must not cross.
	var boxes := [Rect2(80, 80, 19.9, 40), Rect2(102, 80, 1, 40)]
	var foot := Vector2(100, 100)
	var at: Vector2 = GUARD.new().position_for(foot, G, 1, _world(boxes))
	check(_free_slide(foot, at, boxes), "the camera slides free of a thin wall (answer %s)" % at)
	check(not boxes.any(func(b: Rect2) -> bool: return b.has_point(at)), "the camera is not inside a solid (answer %s)" % at)

	# 2. Finding 1: feet 0.2 px inside the top edge with a wall below. The push goes up, off the screen.
	boxes = [Rect2(300, 5, 60, 30)]
	foot = Vector2(320, 0.2)
	var pushed: Vector2 = GUARD.new().position_for(foot, G, 2, _world(boxes))
	check(GUARD.SCREEN.has_point(pushed), "the camera stays on its screen at the top edge (answer %s)" % pushed)
	foot = Vector2(619.5, 200)
	boxes = [Rect2(600, 180, 19, 40)] # a wall to the west, the world's edge to the east
	pushed = GUARD.new().position_for(foot, G, 3, _world(boxes))
	check(GUARD.SCREEN.has_point(pushed), "the camera stays on its screen at the east edge (answer %s)" % pushed)

	# 3. Finding 3: the full clearance minus float32 noise is not a pinch. An open wall costs the 3 calls of a solve, not 50+.
	boxes = [Rect2(200, 100, 50, 50)]
	foot = Vector2(199.0, 120.0)
	var exact_guard := G
	var noisy: Vector2 = Vector2(199.0 - (exact_guard - 1.0) + 2e-7, 120.0) # 2e-7 px short of the full clearance
	calls = 0
	GUARD.new().position_for(noisy, exact_guard, 4, _world(boxes))
	check(calls <= 12, "a 2e-7 px deficit does not start the search (%d field calls)" % calls)

	# 4. Temporal coherence: in a real pinch the second foot position reuses the way out (a few calls), not the 24 x 3 search.
	boxes = [Rect2(80, 80, 19.0, 60), Rect2(101.0, 80, 40, 60)] # a 2 px wide channel open to the north
	var guard := GUARD.new()
	var world := _world(boxes)
	foot = Vector2(100, 130)
	guard.position_for(foot, G, [7, 5], world)
	calls = 0
	var next: Vector2 = guard.position_for(Vector2(100, 129), G, [7, 6], world)
	check(calls <= 12, "an unresolvable pinch is searched once per 4 px cell, not every frame (%d field calls, answer %s)" % [calls, next])
	check(_free_slide(Vector2(100, 129), next, boxes), "the warm answer slides free")

	print("CAMERA GUARD UNIT ", "PASS" if failures.is_empty() else "FAIL %d" % failures.size())
	quit(0 if failures.is_empty() else 1)
