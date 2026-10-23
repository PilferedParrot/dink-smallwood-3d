# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
extends SceneTree
# Labelled input fixture: source34/script startup and progression are skipped.
# Original update_frame.cpp:347-353 runs special_block on warp hardness before
# freedink.cpp:132-242 considers edge crossing. Keep the bar exit redirect.
const GAME = preload("res://scripts/fps_game.gd")
var game
var failures: Array = []
var report_path := ""
var column_start := 307
var column_stop := 340
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--column-start="): column_start = int(arg.trim_prefix("--column-start="))
		if arg.begins_with("--column-stop="): column_stop = int(arg.trim_prefix("--column-stop="))
		if arg.begins_with("--report="): report_path = arg.trim_prefix("--report=")
	_run.call_deferred()
func hold_keys(keys: Array, frames: int, leave_screen: int = -1) -> void:
	for key in keys:
		var e := InputEventKey.new(); e.physical_keycode = key; e.pressed = true
		Input.parse_input_event(e)
	Input.flush_buffered_events()
	for _i in frames:
		await physics_frame
		if leave_screen >= 0 and game.current_screen != leave_screen: break
	for key in keys:
		var e := InputEventKey.new(); e.physical_keycode = key; e.pressed = false
		Input.parse_input_event(e)
	Input.flush_buffered_events(); await physics_frame
func hold(key: int, frames: int) -> void:
	await hold_keys([key],frames)
func place(x: float, y: float) -> void:
	game.vm.cancel_all(); game.ui.cancel_speech(); game.ui.close_menu()
	game.entities[1].x = x; game.entities[1].y = y
	game.entities[1].frozen = false; game.entities[1].nocontrol = 0; game.entities[1].disabled = 0
	game.fps_yaw = PI; game.fps_pitch = -0.08; game._sync_fps_camera()
	game.playing = true; game.changing = false; game.locked = false; game.warp_cooldown = 0.0
	game._reset_push()
func _run() -> void:
	game = GAME.new(); game.test_mode = true; root.add_child(game); await process_frame
	await game._new_game(); game.vm.cancel_all(); game.load_map(34,false)
	var wall_face := 0.0
	for id in game.entities:
		if int(game.entities[id].get("editor_num",0)) == 3:
			wall_face = game._hard_rect(game.entities[id]).position.y
	var limit: float = wall_face
	# Start 1 px outside the source wall's raw hardbox (a mover is a point); eight normal steps
	# would enter it if movement ignored this wall, without waiting to PUSH.
	# x50 intersects the left wall as well as the selected south wall. Use
	# x100, and prove the approach/retreat free before driving any input.
	var start := Vector2(100,limit-1.0)
	var approach_free: bool = not game._blocked(start,1)
	var retreat_free: bool = not game._blocked(start+Vector2(0,-2),1,start)
	var forward_blocked: bool = game._blocked(Vector2(start.x,limit+1.0),1,start)
	var wall_owners := []
	for probe in [start,start+Vector2(0,-2),Vector2(start.x,limit+1.0)]:
		var id: int = game._blocking_sprite(probe,1,start)
		wall_owners.append({"point":[probe.x,probe.y],"blocking_editor_index":int(game.entities[id].get("editor_num",0)) if id != 0 else 0,"tile_hardness":game._tile_hardness(probe)})
	print("INDOOR PORTAL WALL PROBES %s" % JSON.stringify(wall_owners))
	if not approach_free or not retreat_free or not forward_blocked:
		failures.append("wall fixture requires a free approach/retreat and a blocked forward point")
		print(failures)
		quit(1)
		return
	place(start.x,start.y)
	print("INDOOR PORTAL WALL SETUP face=%s limit=%s" % [wall_face,limit])
	await hold(KEY_W,8)
	var wall_stop: Vector2 = game._position2(1)
	var wall_screen: int = game.current_screen
	if wall_face <= 0 or wall_screen != 34 or wall_stop.y > limit+0.001 or wall_stop.y < start.y: failures.append("plain south wall must stop ordinary input on34")
	await hold(KEY_S,3)
	var reverse: bool = game._position2(1).y < wall_stop.y-0.1
	if not reverse: failures.append("reverse must escape the wall stop")
	print("INDOOR PORTAL WALL RESULT %s reverse=%s" % [str(wall_stop),reverse])
	game.vm.cancel_all(); game.load_map(34,false); place(320,330)
	var free_columns: Array = []
	for x in range(20,620):
		var p := Vector2(x,399)
		if not game._blocked(p,1) and not game._blocked(Vector2(x,400),1,p): free_columns.append(x)
	var expected_columns: Array = []
	for x in range(307,340): expected_columns.append(x)
	if free_columns != expected_columns: failures.append("bar exit must exercise exactly the 33 pinned FPS-free columns 307..339 (the whole aperture: a mover is a point; 311..335 under the retired 4 px band) (got %d: %s..%s)" % [free_columns.size(), str(free_columns.front()) if free_columns.size() else "-", str(free_columns.back()) if free_columns.size() else "-"])
	var variants := [
		{"name":"straight","side":0,"sprint":false},{"name":"straight-sprint","side":0,"sprint":true},
		{"name":"diagonal-left","side":1,"sprint":false},{"name":"diagonal-right","side":-1,"sprint":false},
		{"name":"diagonal-left-sprint","side":1,"sprint":true},{"name":"diagonal-right-sprint","side":-1,"sprint":true}]
	var trial_columns: Array = []
	for x in free_columns:
		if int(x) >= column_start and int(x) < column_stop: trial_columns.append(x)
	if column_start < 307 or column_stop > 340 or column_stop <= column_start: failures.append("invalid column batch")
	var trials: Array = []
	var failed_trials := 0
	for x in trial_columns:
		for variant in variants:
			# The columns 307..310 and 336..339 are the aperture's edge, free since a mover is a point (the retired 4 px
			# band had left 311..335): a straight approach crosses there, a diagonal one runs into the jamb, as in the original.
			var edge_column: bool = int(x) < 311 or int(x) >= 336
			if edge_column and int(variant.side) != 0: continue
			game.vm.cancel_all(); game.load_map(34,false)
			# Two pixels before the fitted portal's normal tolerance begins.
			# Diagonal approaches aim at the sampled column at that threshold.
			var start_door := Vector2(float(x)-2.0*float(variant.side),343)
			place(start_door.x,start_door.y)
			var free_start: bool = not game._blocked(start_door,1)
			var keys: Array = [KEY_W]
			if int(variant.side) > 0: keys.append(KEY_A)
			if int(variant.side) < 0: keys.append(KEY_D)
			if bool(variant.sprint): keys.append(KEY_SHIFT)
			if free_start: await hold_keys(keys,12,34)
			var arrival: int = game.current_screen
			var ok: bool = free_start and arrival == 498 and not game.visited.has(66)
			trials.append({"column":x,"variant":variant.name,"start":[start_door.x,start_door.y],"start_free":free_start,"arrival":arrival,"never66":not game.visited.has(66),"ok":ok})
			if not ok:
				failed_trials += 1
				failures.append("door column%s %s failed: arrival%s free%s" % [x,variant.name,arrival,free_start])
			if failed_trials >= 2: break
		if failed_trials >= 2: break
		if int(x)%5 == 0: print("INDOOR PORTAL CLASS column%s completed%s" % [x,trials.size()])
	var expected_trials := 0
	for x in range(column_start,column_stop): expected_trials += 2 if (x < 311 or x >= 336) else 6
	if trials.size() != expected_trials: failures.append("every requested column times its approach/speed variants must run (%d of %d)" % [trials.size(),expected_trials])
	print("INDOOR PORTAL DOOR CLASS RESULT trials=%s failed=%s" % [trials.size(),failed_trials])
	var result := {"setup":"Injected source34 poses with startup/progression skipped; actual W/S events and normal runtime warp transition. Not earned campaign progress.","wall_preconditions":{"approach_free":approach_free,"retreat_free":retreat_free,"forward_blocked":forward_blocked},"wall_owners":wall_owners,"wall_start":[start.x,start.y],"wall_screen":wall_screen,"wall_stop":[wall_stop.x,wall_stop.y],"reverse_works":reverse,"door_columns":free_columns,"tested_columns":trial_columns,"batch_range":[column_start,column_stop],"door_trials":trials,"visited_screens":game.visited.duplicate(),"failures":failures}
	if not report_path.is_empty():
		var f := FileAccess.open(report_path,FileAccess.WRITE); f.store_string(JSON.stringify(result,"  "))
	print("INDOOR PORTAL INPUT PASS" if failures.is_empty() else str(failures))
	game.vm.cancel_all(); game.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
