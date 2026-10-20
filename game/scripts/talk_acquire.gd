extends RefCounted
# FreeDink 109.6 Talk acquisition, the pure part. The original has no ray, no
# line of sight and no visibility test: Talk goes to the first live sprite, in
# slot order, whose script has a TALK procedure and whose hardbox, grown by
# GROW px and extended toward Dink by his facing, contains Dink's point.

const GROW := 10.0 # freedink.cpp:262 rect_inflate(&box, 10, 10)
const REACH_EW := 50.0 # freedink.cpp:264 amount; :268 dir 6 box.left -= amount; :273 dir 4 box.right += amount
const REACH_NS := 35.0 # freedink.cpp:265 amounty; :278 dir 2 box.top -= amounty; :283 dir 8 box.bottom += amounty

# Nearest axis of the camera's ground heading, as a resting Dink faces: the
# original freezes a diagonal dir to a cardinal one (brain_keyboard.cpp:554-557,
# 1 and 3 -> 2, 7 and 9 -> 8), so an exact 45 degrees resolves to north/south.
static func facing(forward: Vector2) -> int:
	if absf(forward.x) > absf(forward.y): return 6 if forward.x > 0.0 else 4
	return 2 if forward.y > 0.0 else 8

# The box Talk tests Dink's point against: [left, top, right, bottom]. `hardbox`
# is the sprite's CURRENT frame hardbox relative to its position, unscaled by
# the sprite's size (freedink.cpp:259-260 k[getpic(i)].hardbox + rect_offset).
# A diagonal dir (only while Dink walks diagonally) extends nothing.
static func reach_box(hardbox: Array, position: Vector2, dir: int) -> Array:
	var box := [position.x + float(hardbox[0]) - GROW, position.y + float(hardbox[1]) - GROW,
		position.x + float(hardbox[2]) + GROW, position.y + float(hardbox[3]) + GROW]
	match dir:
		6: box[0] -= REACH_EW
		4: box[2] += REACH_EW
		2: box[1] -= REACH_NS
		8: box[3] += REACH_NS
	return box

# rect.cpp:81-91 inside_box: every edge inclusive.
static func contains(box: Array, point: Vector2) -> bool:
	return point.x >= box[0] and point.x <= box[2] and point.y >= box[1] and point.y <= box[3]
