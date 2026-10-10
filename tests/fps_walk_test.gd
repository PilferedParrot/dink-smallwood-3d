extends SceneTree
const GAME = preload("res://scripts/fps_game.gd")
var game
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	await game._new_game()
	await create_timer(2.1).timeout
	game.fps_yaw = 0.0
	game.fps_pitch = 0.0
	game._sync_fps_camera()
	var sack := 0
	for id in game.entities:
		if int(game.entities[id].get("editor_num",0)) == 52: sack = id
	if sack == 0: push_error("Feed sack missing"); quit(1); return
	var goal: Rect2 = game._hard_rect(game.entities[sack]).grow(8)
	var path := route(goal)
	if path.is_empty(): push_error("No walkable first-person route from spawn to feed sack"); quit(1); return
	if not await follow(path): quit(1); return
	if not game.items.any(func(item): return item.script == "item-pig"):
		push_error("Walking to feed sack did not collect feed");quit(1);return
	var exit_goal := Rect2()
	for entity in game.entities.values():
		if bool(entity.get("fps_portal",false)):
			var portal: Rect2 = game._hard_rect(entity)
			exit_goal = Rect2(portal.position, Vector2(portal.size.x,8.0))
			break
	if not exit_goal.has_area(): push_error("Source-derived live home portal missing"); quit(1); return
	path = route(exit_goal)
	if path.is_empty(): push_error("No walkable route from sack to home exit"); quit(1); return
	if not await follow(path,439): quit(1); return
	if game.current_screen != 439: push_error("Walking to exit did not enter Stonebrook"); quit(1); return
	print("FPS WALK PASS: physically walked from spawn to feed sack and through home exit")
	game.vm.cancel_all()
	game.queue_free()
	await process_frame
	quit()
func follow(path: Array[Vector2], stop_screen: int = 0) -> bool:
	# The route is planning only. Actual keys drive movement and its normal
	# direction-aware portal/collection path; no direct position/movement calls.
	var input_quantum := 0.0
	for target in path:
		for step in 24:
			if stop_screen != 0 and game.current_screen == stop_screen: return true
			var offset: Vector2 = target-game._position2(1)
			# Measure the driver's resolution rather than demand an arbitrary
			# sub-tick position: nearest points on a square motion lattice are
			# at most sqrt(2)/2 of one measured tick from a waypoint.
			var precision := minf(4.0,input_quantum*sqrt(0.5)+0.01)
			if offset.length() <= precision: break
			var code: Key = KEY_D if offset.x > 0.0 else KEY_A
			if absf(offset.y) > absf(offset.x): code = KEY_S if offset.y > 0.0 else KEY_W
			var before: Vector2=game._position2(1)
			await pulse(code)
			if stop_screen != 0 and game.current_screen == stop_screen: return true
			var moved: float=game._position2(1).distance_to(before)
			input_quantum=maxf(input_quantum,moved)
			# An obstructed axis is not a stuck player. At a prop corner try
			# the other needed axis rather than hammer the same blocked key.
			if moved < 0.01:
				var other: Key=KEY_S if offset.y>0.0 else KEY_W
				if code in [KEY_W,KEY_S]: other=KEY_D if offset.x>0.0 else KEY_A
				await pulse(other)
				if stop_screen != 0 and game.current_screen == stop_screen: return true
				input_quantum=maxf(input_quantum,game._position2(1).distance_to(before))
		if stop_screen != 0 and game.current_screen == stop_screen: return true
		if game._position2(1).distance_to(target)>minf(4.0,input_quantum*sqrt(0.5)+0.01):
			push_error("Input route could not reach %s from %s on screen%d (measured quantum%.3f)" % [target,game._position2(1),game.current_screen,input_quantum])
			return false
	return true
func pulse(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode=code; event.physical_keycode=code; event.pressed=true
	Input.parse_input_event(event); Input.flush_buffered_events()
	for i in 2: await physics_frame
	event=InputEventKey.new(); event.keycode=code; event.physical_keycode=code; event.pressed=false
	Input.parse_input_event(event); Input.flush_buffered_events()
	await physics_frame
func route(goal: Rect2) -> Array[Vector2]:
	var start: Vector2 = game._position2(1)
	var start_cell := Vector2i(roundi(start.x/8),roundi(start.y/8))
	var queue: Array[Vector2i] = [start_cell]
	var parents := {start_cell:start_cell}
	var cursor := 0
	while cursor < queue.size():
		var cell: Vector2i = queue[cursor]
		cursor += 1
		var p := Vector2(cell)*8
		if goal.has_point(p):
			var result: Array[Vector2] = []
			while cell != start_cell:
				result.push_front(Vector2(cell)*8)
				cell = parents[cell]
			return result
		for dir in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var next: Vector2i = cell+dir
			var pos := Vector2(next)*8
			if pos.x < 24 or pos.x > 616 or pos.y < 8 or pos.y > 400: continue
			if parents.has(next) or game._blocked(pos,1): continue
			parents[next] = cell
			queue.append(next)
	return []
