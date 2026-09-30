extends SceneTree
# Walk into the drawn walls of buildings through the real input path (docs/DIRECTION.md,
# seventh pass). The drawn wall is the fitted footprint (tools/collision_map.py); the player
# must stop at it (4 px, the player's radius, plus at most one step), not inside it where the
# old 3/4-view hardness let him, and not in the air in front of it. Doors must still take him
# in, and the ground behind a house, which the old hardness ring closed, is open.
# Scenario setup: each case loads its screen with scripts off (load_map(n, false)) and places
# Dink; this skips progression, and only movement and doors are under test.
# Reads the footprints from data/footprints.json itself, so the same file measures a build
# without them (the before numbers in DIRECTION.md).

const GAME := preload("res://scripts/fps_game.gd")
var game
var failures: Array[String] = []
var polys_by_screen: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/footprints.json"))
	polys_by_screen = data.screens
	game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	await game._new_game()
	await create_timer(0.5).timeout
	game.vm.cancel_all()
	game.playing = true
	game.changing = false
	game.ui.close_menu()
	# screen, footprint name: Dink's cottage, Ethel's, the village houses, the inn (kit-537)
	for case in [[439,"home-01"],[409,"home-06"],[440,"home-04"],[500,"home-05"],[537,"home-07"],[617,"home-01"],[505,"kit-537"],[538,"kit-537"]]:
		await _walk_into_wall(int(case[0]),str(case[1]))
	await _enter_door(439,1)
	await _enter_door(409,2)
	_behind_house(439,"home-01")
	game.vm.cancel_all(); game.queue_free()
	if failures.is_empty(): print("FPS WALL PASS: the player stops at the drawn walls; doors open; behind the houses is open")
	quit(0 if failures.is_empty() else 1)

func _polys(screen: int, name: String) -> Array:
	var out: Array = []
	for p in polys_by_screen.get(str(screen),{}).get("polys",[]):
		if str(p.name) != name: continue
		var poly := PackedVector2Array()
		for q in p.pts: poly.append(Vector2(float(q[0]),float(q[1])))
		out.append(poly)
	return out

# Distance to the nearest footprint wall; negative inside the footprint (how far in).
func _distance(pos: Vector2, polys: Array) -> float:
	var best := INF
	var inside := false
	for poly in polys:
		inside = inside or Geometry2D.is_point_in_polygon(pos,poly)
		for i in poly.size():
			best = minf(best,Geometry2D.get_closest_point_to_segment(pos,poly[i],poly[(i+1)%poly.size()]).distance_to(pos))
	return -best if inside else best

func _near_warp(p: Vector2) -> bool:
	for id in game.entities:
		var e: Dictionary = game.entities[id]
		if e.get("warp") != null and game._hard_rect(e).grow(24).has_point(p): return true
	return false

# A point on a south-facing wall of the footprint whose approach from 40 px outside is clear
# of everything but the building, away from doors: [wall point, inward direction].
func _approach(polys: Array) -> Array:
	for poly in polys:
		var mid := Vector2.ZERO
		for q in poly: mid += q/poly.size()
		for i in poly.size():
			var a: Vector2 = poly[i]
			var b: Vector2 = poly[(i+1)%poly.size()]
			var out := Vector2(-(b-a).y,(b-a).x).normalized()
			if out.dot((a+b)*0.5-mid) < 0: out = -out
			if out.y < 0.3 or a.distance_to(b) < 40: continue
			for t in [0.3,0.7,0.5,0.2,0.8,0.1,0.9,0.4,0.6]:
				var w: Vector2 = a.lerp(b,t)
				var start := w+out*40.0
				if start.x < 30 or start.x > 610 or start.y < 10 or start.y > 390 or _near_warp(w): continue
				var clear := true
				for k in range(0,33):
					var p := start-out*float(k)
					if _distance(p,polys) > 5.0 and game._blocked(p,1): clear = false
				if clear: return [w,-out]
	return []

func _walk_into_wall(screen: int, name: String) -> void:
	game.load_map(screen,false)
	await process_frame
	var polys := _polys(screen,name)
	if polys.is_empty():
		check(false,"%d %s: no footprint" % [screen,name]); return
	var approach := _approach(polys)
	if approach.is_empty():
		check(false,"%d %s: no clear approach to a south wall" % [screen,name]); return
	var wall: Vector2 = approach[0]
	var inward: Vector2 = approach[1]
	var start := wall-inward*40.0
	game.entities[1]["x"] = start.x; game.entities[1]["y"] = start.y
	game.warp_cooldown = 1.0
	game.fps_yaw = atan2(-inward.x,-inward.y); game.fps_pitch = 0.0
	game._sync_fps_camera()
	await _hold(KEY_W,60)
	var stop: Vector2 = game._position2(1)
	var d := _distance(stop,polys)
	var travelled := start.distance_to(stop)
	print("WALL %d %s: start %s toward %s, stopped at %s, %.1f px from the drawn wall after %.1f px" % [screen,name,start,wall,stop,d,travelled])
	check(game.current_screen == screen,"%d %s: stayed on the screen" % [screen,name])
	check(d >= 3.9 and d <= 7.5,"%d %s: stops at the drawn wall (%.1f px from it)" % [screen,name,d])

func _enter_door(screen: int, inside: int) -> void:
	game.load_map(screen,false)
	await process_frame
	var door := 0
	for id in game.entities:
		var e: Dictionary = game.entities[id]
		if e.get("warp") != null and int(e.warp.get("map",0)) == inside: door = id
	if door == 0:
		check(false,"%d: no door to %d" % [screen,inside]); return
	var rect: Rect2 = game._hard_rect(game.entities[door])
	var start := Vector2(rect.get_center().x,rect.end.y+30.0)
	game.entities[1]["x"] = start.x; game.entities[1]["y"] = start.y
	game.warp_cooldown = 0.0
	game.fps_yaw = 0.0; game.fps_pitch = 0.0
	game._sync_fps_camera()
	await _hold(KEY_W,60)
	print("DOOR %d -> %d: now on %d" % [screen,inside,game.current_screen])
	check(game.current_screen == inside,"Walking into the door on %d enters %d" % [screen,inside])

func _behind_house(screen: int, name: String) -> void:
	game.load_map(screen,false)
	var polys := _polys(screen,name)
	var top := Vector2(0,INF)
	for poly in polys:
		for q in poly:
			if q.y < top.y: top = q
	# The old ring ran round the drawn roof, 30-60 px north of the back corner.
	var open := 0
	for dy in [12,24,36,48]:
		if not game._blocked(top-Vector2(0,dy),1): open += 1
	print("BEHIND %d %s: %d of 4 points north of the back corner %s are open" % [screen,name,open,top])
	check(open == 4,"Behind %s on %d is open ground" % [name,screen])

func _hold(key: int, frames: int) -> void:
	var down := InputEventKey.new(); down.physical_keycode = key; down.pressed = true
	Input.parse_input_event(down)
	for _i in frames: await physics_frame
	var up := InputEventKey.new(); up.physical_keycode = key; up.pressed = false
	Input.parse_input_event(up)
	await physics_frame

func check(condition: bool, message: String) -> void:
	if condition: return
	failures.append(message)
	push_error(message)
