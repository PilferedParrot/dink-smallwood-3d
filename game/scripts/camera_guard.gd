# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
# The camera's distance from solids. A mover is a point (game.gd): it stands on a solid's raw edge, as the original's
# does. The first-person camera cannot: its near plane would cut into the wall. So the camera is held `guard` source
# pixels from the nearest solid, displaced from the feet by up to 2 x that (MAX_DISPLACEMENT), where there is room.
#
# guard = how far a near-plane corner reaches + how far a prop's mesh stands past its hardbox:
#   reach = near * sqrt(1 + tan_h^2 + tan_v^2) / metres_per_px   (the corner of the near rectangle, in source pixels)
# The feet stay where they are: they are the hitbox for Talk, push and melee, as in the original.
extends RefCounted

const PROP_OVERHANG_PX := 3.0 # a prop's depth cap is hardbox depth + 2 * this (fp_world.gd), each side
const ITERATIONS := 3
const SCREEN := Rect2(20, 0, 600, 400) # the camera stays on its own screen: past an edge is another room's space (or no space)
const MAX_DISPLACEMENT := 2.0 # x guard: the camera stands this far from the feet at most; an inner corner of angle t needs 1 / sin(t / 2): sqrt(2) at a right angle, 2 at 60 degrees

var _key := []
var _at := Vector2.ZERO

static func reach_px(near: float, fov_degrees: float, aspect: float, metres_per_px: float) -> float:
	var tan_v := tan(deg_to_rad(fov_degrees) * 0.5)
	var tan_h := tan_v * aspect
	return near * sqrt(1.0 + tan_v * tan_v + tan_h * tan_h) / metres_per_px

static func guard_px(near: float, fov_degrees: float, aspect: float, metres_per_px: float) -> float:
	return reach_px(near, fov_degrees, aspect, metres_per_px) + PROP_OVERHANG_PX

# Where the camera stands for feet at `foot`, in source pixels. `nearest` is Callable(point, limit) -> [distance, closest
# point on a solid] (the game's `_solid_nearest`: this screen, the neighbours across the seams, doors, the world's edge).
# `stamp` identifies the world state (screen, physics frame): the answer is reused while foot, guard and stamp agree.
func position_for(foot: Vector2, guard: float, stamp: Variant, nearest: Callable) -> Vector2:
	var key := [foot, guard, stamp]
	if key == _key: return _at
	_key = key
	_at = _solve(foot, guard, nearest)
	if (nearest.call(_at, guard) as Array)[0] < guard: _at = _search(foot, _at, guard, nearest)
	return _at

# Stand `guard` from the nearest solid, directly away from its closest point. A second wall pushes again; two walls closer
# than two guards (a slot) push in opposite directions, and the answer is the midline between them: the best there is.
static func _solve(foot: Vector2, guard: float, nearest: Callable) -> Vector2:
	var c := foot
	var previous := Vector2.ZERO
	for _i in ITERATIONS:
		var hit: Array = nearest.call(c, guard)
		var distance: float = hit[0]
		if distance >= guard: break # includes INF: nothing within the guard
		var at: Vector2 = hit[1]
		if distance <= 0.0: break # inside a solid: the feet's own business, not the camera's
		var out := (c - at) / distance
		if previous != Vector2.ZERO and out.dot((c - previous).normalized()) < -0.5:
			var middle := (at + previous) * 0.5
			return middle if (nearest.call(middle, 0.0001) as Array)[0] > 0.0 else c
		var moved := at + out * guard
		if moved.distance_to(foot) > guard * MAX_DISPLACEMENT: break
		if (nearest.call(moved, 0.0001) as Array)[0] <= 0.0: break
		previous = at
		c = moved
	return c

# Pinched in a notch or a slot, pushing away from the nearest wall runs into the next one. The camera may then slide out
# of the pinch: the nearest of 24 directions x 3 distances (1, 1.25, 1.5 guards) that has the full clearance and a free
# slide from the feet; none, and the local answer stands (the centre of the slot).
static func _search(foot: Vector2, local: Vector2, guard: float, nearest: Callable) -> Vector2:
	for radius in [guard, guard * 1.25, guard * 1.5]:
		for k in 24:
			var candidate: Vector2 = foot + Vector2.RIGHT.rotated(TAU * float(k) / 24.0) * float(radius)
			if not SCREEN.has_point(candidate) or (nearest.call(candidate, guard) as Array)[0] < guard: continue
			var free := true
			for step in range(1, int(ceil(float(radius))) + 1):
				if (nearest.call(foot.lerp(candidate, float(step) / ceil(float(radius))), 0.0001) as Array)[0] <= 0.0:
					free = false
					break
			if free: return candidate
	return local
