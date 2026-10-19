# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
extends SceneTree
# Labelled input fixture: source34/script startup and progression are skipped.
# Original update_frame.cpp:347-353 runs special_block on warp hardness before
# freedink.cpp:132-242 considers edge crossing. Keep the bar exit redirect.
const GAME = preload("res://scripts/fps_game.gd")
var game
var failures: Array = []
var report_path := ""
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report_path = arg.trim_prefix("--report=")
	_run.call_deferred()
func hold(key: int, frames: int) -> void:
	var e := InputEventKey.new(); e.physical_keycode = key; e.pressed = true
	Input.parse_input_event(e); Input.flush_buffered_events()
	for _i in frames: await physics_frame
	e = InputEventKey.new(); e.physical_keycode = key; e.pressed = false
	Input.parse_input_event(e); Input.flush_buffered_events(); await physics_frame
func place(x: float, y: float) -> void:
	game.vm.cancel_all(); game.ui.cancel_speech(); game.ui.close_menu()
	game.entities[1].x = x; game.entities[1].y = y
	game.entities[1].frozen = false; game.entities[1].nocontrol = 0; game.entities[1].disabled = 0
	game.fps_yaw = PI; game.fps_pitch = -0.08; game._sync_fps_camera()
	game.playing = true; game.changing = false; game.locked = false; game.warp_cooldown = 0.0
func _run() -> void:
	game = GAME.new(); game.test_mode = true; root.add_child(game); await process_frame
	await game._new_game(); game.vm.cancel_all(); game.load_map(34,false)
	var wall_face := 0.0
	for id in game.entities:
		if int(game.entities[id].get("editor_num",0)) == 3:
			wall_face = game._hard_rect(game.entities[id]).position.y
	var limit: float = wall_face-float(game.FOOTPRINT_GROW)
	# Start1px outside the source wall's4px clearance; eight normal steps
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
	print("INDOOR PORTAL DOOR SETUP")
	await hold(KEY_W,45)
	var arrival: int = game.current_screen
	print("INDOOR PORTAL DOOR RESULT %s" % arrival)
	if arrival != 498 or game.visited.has(66): failures.append("bar door must redirect to498, never adjacent66")
	var result := {"setup":"Injected source34 poses with startup/progression skipped; actual W/S events and normal runtime warp transition. Not earned campaign progress.","wall_preconditions":{"approach_free":approach_free,"retreat_free":retreat_free,"forward_blocked":forward_blocked},"wall_owners":wall_owners,"wall_start":[start.x,start.y],"wall_screen":wall_screen,"wall_stop":[wall_stop.x,wall_stop.y],"reverse_works":reverse,"door_arrival":arrival,"visited_screens":game.visited.duplicate(),"failures":failures}
	if not report_path.is_empty():
		var f := FileAccess.open(report_path,FileAccess.WRITE); f.store_string(JSON.stringify(result,"  "))
	print("INDOOR PORTAL INPUT PASS" if failures.is_empty() else str(failures))
	game.vm.cancel_all(); game.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
