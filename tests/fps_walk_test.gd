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
	var sack := 0
	for id in game.entities:
		if int(game.entities[id].get("editor_num",0)) == 52: sack = id
	if sack == 0: push_error("Feed sack missing"); quit(1); return
	var goal: Rect2 = game._hard_rect(game.entities[sack]).grow(8)
	var path := route(goal)
	if path.is_empty(): push_error("No walkable first-person route from spawn to feed sack"); quit(1); return
	for p in path:
		game._move_entity(1,p-game._position2(1))
		game.warp_cooldown = 0
		game._transitions()
		await physics_frame
	if not game.items.any(func(item): return item.script == "item-pig"):
		push_error("Walking to feed sack did not collect feed");quit(1);return
	path = route(Rect2(290,387,55,13))
	if path.is_empty(): push_error("No walkable route from sack to home exit"); quit(1); return
	for p in path:
		game._move_entity(1,p-game._position2(1))
		game.warp_cooldown = 0
		game._transitions()
		await physics_frame
		if game.current_screen == 439: break
	if game.current_screen != 439: push_error("Walking to exit did not enter Stonebrook"); quit(1); return
	print("FPS WALK PASS: physically walked from spawn to feed sack and through home exit")
	game.vm.cancel_all()
	game.queue_free()
	await process_frame
	quit()
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
