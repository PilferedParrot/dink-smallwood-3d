# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
extends "res://../tests/fps_indoor_portal_input.gd"
# Reuse actual input/pose helpers. Startup and progression are skipped; these
# near-exit poses test warp priority, not reachability from each room's spawn.
func _run() -> void:
	game = GAME.new(); game.test_mode = true; root.add_child(game); await process_frame
	await game._new_game(); game.vm.cancel_all()
	var corpus: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../tests/fixtures/indoor-warp-edge-samples.json"))
	var trials: Array = []
	var failed := 0
	for sample in corpus.trials:
		var source := int(sample.source)
		game.vm.cancel_all(); game.load_map(source,false)
		var live: Dictionary = {}
		for id in game.entities:
			if int(game.entities[id].get("editor_num",0)) == int(sample.editor_index): live = game.entities[id]
		var yaw := PI
		match str(sample.direction):
			"north": yaw = 0.0
			"west": yaw = PI/2.0
			"east": yaw = -PI/2.0
		var start := Vector2(float(sample.source_point[0]),float(sample.source_point[1]))
		var trigger := Rect2()
		if not live.is_empty():
			trigger = game._warp_trigger_rect(live)
			if bool(live.get("fps_portal",false)):
				# Fitted openings move the old bottom trigger up to the drawn
				# door plane. Approach that plane from its room-facing side.
				start.y = trigger.position.y-2.0
		place(start.x,start.y); game.fps_yaw = yaw; game._sync_fps_camera()
		var free_start: bool = not game._blocked(start,1)
		var owner_valid: bool = not live.is_empty() and live.get("warp") != null and int(live.warp.get("map",0)) == int(sample.authored_destination)
		if free_start and owner_valid: await hold_keys([KEY_W],12,source)
		var arrival: int = game.current_screen
		var ok: bool = free_start and owner_valid and arrival == int(sample.authored_destination) and arrival != int(sample.adjacent)
		trials.append({"source":source,"adjacent":sample.adjacent,"sample_point":sample.source_point,"editor_index":sample.editor_index,"expected":sample.authored_destination,"start":[start.x,start.y],"start_free":free_start,"owner_valid":owner_valid,"arrival":arrival,"ok":ok})
		print("INDOOR WARP EDGE source%s point%s arrival%s expected%s free%s" % [source,str(sample.source_point),arrival,sample.authored_destination,free_start])
		if not ok:
			failed += 1; failures.append("warp edge%s→%s point%s failed" % [source,sample.adjacent,str(sample.source_point)])
		if failed >= 2: break
	if trials.size() != 48: failures.append("all48 samples on16 additional warp edges must run")
	var result := {"setup":corpus.setup,"trials":trials,"failures":failures}
	if not report_path.is_empty():
		var f := FileAccess.open(report_path,FileAccess.WRITE); f.store_string(JSON.stringify(result,"  "))
	print("INDOOR WARP EDGES PASS" if failures.is_empty() else str(failures))
	game.vm.cancel_all(); game.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
