# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
extends SceneTree
# Static editor-layer fixture; no campaign progression or startup scripts.
# Queries real collision/movement and talk/melee dispatch before/A/B in one scene.
class ProbeGame extends "res://scripts/fps_game.gd":
	var events: Array = []
	func _run_event(id: int, event: String) -> void:
		events.append([id, event])

const PREVIEW := preload("res://prototype/rc5_forest_preview.gd")
var game
var failures: Array = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func bodies(node: Node) -> int:
	var count := int(node is CollisionObject3D)
	for child in node.get_children(): count += bodies(child)
	return count

func mask() -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(600 * 400)
	for y in 400:
		for x in 600: result[y * 600 + x] = int(game._blocked(Vector2(x + 20, y), 1))
	return result

func escapes(at: Vector2) -> bool:
	for step in [1.0, 1.75, 2.7125]:
		for d in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN,
				Vector2(-1,-1).normalized(), Vector2(1,-1).normalized(),
				Vector2(-1,1).normalized(), Vector2(1,1).normalized()]:
			game.entities[1].x = at.x
			game.entities[1].y = at.y
			game._move_entity(1, d * step)
			if game._position2(1).distance_to(at) > 0.001: return true
	return false

func survey() -> Dictionary:
	var grid := 0
	var edges := 0
	var traps := 0
	var dispatch_queries := 0
	var dispatched := 0
	var melee_targets := 0
	var target_ids: Array[int] = []
	for y in range(0, 400, 10):
		for x in range(20, 620, 10):
			var at := Vector2(x, y)
			if game._blocked(at, 1): continue
			grid += 1
			if not escapes(at): traps += 1
			game.entities[1].x = at.x
			game.entities[1].y = at.y
			for angle in 8:
				game.fps_yaw = angle * PI / 4.0
				game.fps_pitch = -0.08
				game._sync_fps_camera()
				game._fps_set_facing_from_camera()
				game.events.clear()
				game._talk()
				dispatched += game.events.size()
				var target: int = game._fps_melee_target()
				melee_targets += int(target != 0)
				target_ids.append(target)
				dispatch_queries += 1
	var points: Array[Vector2] = []
	for y in 400:
		points.append(Vector2(21,y))
		points.append(Vector2(619,y))
	for x in range(20,620):
		points.append(Vector2(x,1))
		points.append(Vector2(x,399))
	for at in points:
		if game._blocked(at,1): continue
		edges += 1
		if not escapes(at): traps += 1
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(JSON.stringify(target_ids).to_utf8_buffer())
	return {"grid_walkable":grid,"edge_walkable":edges,"zero_motion_traps":traps,
		"dispatch_query_poses":dispatch_queries,"talk_events":dispatched,"melee_targets":melee_targets,
		"ordered_melee_target_sha256":hash.finish().hex_encode()}

func input_moves(at: Vector2) -> Array:
	var results := []
	for code in [KEY_W, KEY_A, KEY_S, KEY_D]:
		game.entities[1].x = at.x
		game.entities[1].y = at.y
		game.fps_yaw = 0.0
		game.fps_pitch = 0.0
		game._sync_fps_camera()
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = true
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		game._fps_move_player(1.0/60.0)
		var stopped: Vector2 = game._position2(1)
		results.append([stopped.x,stopped.y])
		event = InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = false
		Input.parse_input_event(event)
		Input.flush_buffered_events()
	return results

func _run() -> void:
	var output := ""
	var views_dir := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
		if arg.begins_with("--views="): views_dir = arg.trim_prefix("--views=")
	game = ProbeGame.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.set_process(false)
	game.vm.cancel_all()
	game.vm.globals["vision"] = 0
	game.playing = false
	var records := []
	for screen in [144,375]:
		game.load_map(screen,false)
		await process_frame
		await physics_frame
		game.vm.cancel_all()
		game.ui.close_menu()
		var proposal := PREVIEW.new(game.fp_world)
		var initial_children: int = game.scene_root.get_child_count()
		check(proposal.build(game.scene_root,screen) == null,"default enabled")
		check(proposal.build(game.scene_root,439,true) == null,"out of scope screen built")
		check(game.scene_root.get_child_count() == initial_children,"disabled build changed scene")
		var physics_before := bodies(game.scene_root)
		for row in proposal.fit.screens[str(screen)].added_roots:
			var root_xy: Array = row.foot_source_screen_px
			check(game._blocked(Vector2(float(root_xy[0]),float(root_xy[1])),1),
				"added root is outside current native hardness: %d %s" % [screen,root_xy])
		var baseline := mask()
		var before := survey()
		var input_before := []
		var views: Array = JSON.parse_string(FileAccess.get_file_as_string(views_dir.path_join("%d.json" % screen)))
		for view in views:
			if view.get("original",false): continue
			var at := Vector2(float(view.x),float(view.y))
			check(not game._blocked(at,1),"camera is hard: %d %s" % [screen,view.name])
			var movement := input_moves(at)
			check(movement.any(func(p): return Vector2(float(p[0]),float(p[1])).distance_to(at) > 0.001),
				"input harness produced no movement: %d %s" % [screen,view.name])
			input_before.append(movement)
		var record := {"screen":screen,"before":before,"integer_mask_queries_per_variant":240000,
			"physics_body_count":physics_before,"camera_input_cases":input_before.size()*4,"variants":[]}
		for floor_variant in [false,true]:
			var group := proposal.build(game.scene_root,screen,true,floor_variant)
			check(group != null,"preview failed")
			if group == null: continue
			check(bodies(group) == 0,"preview added physics bodies")
			check(bodies(game.scene_root) == physics_before,"scene physics count changed")
			check(group.get_child_count() == proposal.fit.screens[str(screen)].added_roots.size(),"missing firs")
			for fir in group.get_children():
				check(fir.get_meta("whole_fir",false),"constructor not whole fir")
				check(fir.get_meta("template_path","") == "assets/graphics/lands/Trees/tree-01.png","template changed")
				check(fir.get_node_or_null("Model") != null,"missing crown")
				check(fir.get_node_or_null("Model/ShadowTwin") != null,"missing original shadow twin")
			var after := mask()
			check(after == baseline,"collision mask changed")
			var stats := survey()
			check(stats == before,"walker or dispatch changed")
			check(stats.zero_motion_traps == 0,"walker found zero-motion traps")
			check(stats.talk_events == 0,"unexpected scripted talk event")
			var i := 0
			for view in views:
				if view.get("original",false): continue
				check(input_moves(Vector2(float(view.x),float(view.y))) == input_before[i],"real input movement changed")
				i += 1
			record.variants.append({"forest_floor":floor_variant,"whole_firs":group.get_child_count(),
				"mask_identical":after == baseline,"survey":stats})
			group.free()
		records.append(record)
		print("FOREST GATE screen=",screen," ",record)
	var file := FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"records":records,"failures":failures,
		"setup":"vision0 editor layer, scripts off; full integer collision mask; 10px interior and 1px edge walker, eight dispatch headings per grid cell; parsed W/A/S/D input with deterministic movement tick",
		"limits":"No campaign, saves, dynamic script state, all-cell dispatch or rendering certification; no scripted interaction targets are authored on these screens."},"\t"))
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
