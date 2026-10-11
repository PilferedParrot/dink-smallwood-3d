extends SceneTree
# Candidate white pixels are tested natively. Positive records stop at their
# first _talk/_fps_melee_target dispatch witness; negative records can exhaust
# the mask. Campaign/startup scripts are skipped; _run_event is intercepted.
class ProbeGame extends "res://scripts/fps_game.gd":
	var caught_events: Array = []
	func _run_event(id: int, event: String) -> void:
		caught_events.append([id,event])

func _initialize() -> void:
	_run.call_deferred()

func _probe_one(game, id: int, record: Dictionary, at: Vector2) -> String:
	var target: Dictionary = game.entities[id]
	var actor := Vector2(float(target.x),float(target.y))
	var is_talk := str(record["mode"]) == "talk_nearest_any_facing_90px"
	game.entities[1].x = at.x
	game.entities[1].y = at.y
	game.fps_yaw = atan2(-(actor.x-at.x),-(actor.y-at.y))
	game.fps_pitch = -0.08
	game._sync_fps_camera()
	if is_talk:
		if game.vm._procedure_code(str(target.get("script","")).to_lower(),"talk").is_empty(): return "no_talk_procedure"
		if int(target.get("active",1)) == 0 or int(target.get("type",1)) != 1 or str(target.get("script","")).is_empty(): return "source_state"
		var offset := actor-at
		var f3: Vector3 = -game.camera.global_transform.basis.z
		var forward := Vector2(f3.x,f3.z).normalized()
		if offset.length() >= 90.0: return "range"
		if offset.length() >= 20.0 and offset.normalized().dot(forward) <= 0.55: return "facing"
		if not game._fps_ray_reaches(id): return "own_physics_ray"
		game.caught_events.clear()
		game._talk()
		return "DISPATCH_TARGET" if not game.caught_events.is_empty() and int(game.caught_events[0][0]) == id else "nearest_other_entity"
	game._fps_set_facing_from_camera()
	if not game._fps_targetable(id,at): return "targetable_including_line"
	var offset := actor-at
	var f3: Vector3 = -game.camera.global_transform.basis.z
	var forward := Vector2(f3.x,f3.z).normalized()
	if offset.length_squared() < 0.0001 or offset.normalized().dot(forward) < 0.60: return "facing"
	var direction: int = game._cardinal(int(game.entities[1].get("dir",2)))
	var hit_box: Rect2 = game._fps_melee_hit_rect(target,direction,maxi(0,int(game.entities[1].get("range",0))))
	if at.x < hit_box.position.x or at.x > hit_box.end.x or at.y < hit_box.position.y or at.y > hit_box.end.y: return "melee_rect"
	if not game._fps_ray_reaches(id): return "own_physics_ray"
	return "DISPATCH_TARGET" if game._fps_melee_target() == id else "nearest_other_entity"

func _query(game, id: int, record: Dictionary, when: String, limit: int) -> Dictionary:
	var info: Dictionary = record["images"][when]
	var rect: Array = info["rect_xyxy"]
	var image := Image.load_from_file(str(info["image"]))
	var expected := int(info["eligible_cells"])
	var result := {"eligible_cells":expected,"visited_cells":0,"target_gate_cells":0,
		"actual_dispatch_cells":0,"witness_xy":[],"fail_first":{},"milliseconds":0}
	if image == null or image.is_empty():
		result["error"] = "candidate mask missing"
		return result
	var started := Time.get_ticks_msec()
	var priorities: Array = record.get("priority_xy",{}).get(when,[])
	var tested: Dictionary = {}
	for priority in priorities:
		if priority.size() != 2: continue
		var priority_x := int(priority[0])-int(rect[0])
		var priority_y := int(priority[1])-int(rect[2])
		if priority_x >= 0 and priority_x < image.get_width() and priority_y >= 0 and priority_y < image.get_height() \
				and image.get_pixel(priority_x,priority_y).r >= 0.5:
			var at := Vector2(float(priority[0]),float(priority[1]))
			tested["%d:%d" % [int(at.x),int(at.y)]] = true
			var status := _probe_one(game,id,record,at)
			result["visited_cells"] = int(result["visited_cells"])+1
			if status == "DISPATCH_TARGET":
				result["target_gate_cells"] = int(result["target_gate_cells"])+1
				result["actual_dispatch_cells"] = int(result["actual_dispatch_cells"])+1
				result["witness_xy"] = [at.x,at.y]
				result["milliseconds"] = Time.get_ticks_msec()-started
				result["exhaustive_or_witness"] = "witness"
				return result
			if status == "nearest_other_entity": result["target_gate_cells"] = int(result["target_gate_cells"])+1
			result["fail_first"][status] = int(result["fail_first"].get(status,0))+1
			if limit > 0 and int(result["visited_cells"]) >= limit: break
	if limit > 0 and int(result["visited_cells"]) >= limit:
		result["milliseconds"] = Time.get_ticks_msec()-started
		result["exhaustive_or_witness"] = "limited"
		return result
	for py in image.get_height():
		for px in image.get_width():
			if image.get_pixel(px,py).r < 0.5: continue
			var at := Vector2(float(int(rect[0])+px),float(int(rect[2])+py))
			if tested.has("%d:%d" % [int(at.x),int(at.y)]): continue
			result["visited_cells"] = int(result["visited_cells"])+1
			var status := _probe_one(game,id,record,at)
			if status == "DISPATCH_TARGET":
				result["target_gate_cells"] = int(result["target_gate_cells"])+1
				result["actual_dispatch_cells"] = int(result["actual_dispatch_cells"])+1
				result["witness_xy"] = [at.x,at.y]
				result["exhaustive_or_witness"] = "witness"
				result["milliseconds"] = Time.get_ticks_msec()-started
				return result
			if status == "nearest_other_entity": result["target_gate_cells"] = int(result["target_gate_cells"])+1
			result["fail_first"][status] = int(result["fail_first"].get(status,0))+1
			if limit > 0 and int(result["visited_cells"]) >= limit: break
		if limit > 0 and int(result["visited_cells"]) >= limit: break
	result["milliseconds"] = Time.get_ticks_msec()-started
	result["exhaustive_or_witness"] = "exhaustive" if limit <= 0 or int(result["visited_cells"]) >= expected else "limited"
	return result

func _run() -> void:
	var index_path := ""
	var out_path := ""
	var limit := 0
	var before_only := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--index="): index_path = arg.trim_prefix("--index=")
		if arg.begins_with("--out="): out_path = arg.trim_prefix("--out=")
		if arg.begins_with("--limit="): limit = int(arg.trim_prefix("--limit="))
		if arg == "--before-only": before_only = true
	if index_path.is_empty() or out_path.is_empty():
		push_error("Pass --index and --out")
		quit(2)
		return
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(index_path))
	if str(source.get("schema","")) != "rc5-all-reachable-dispatch-candidates-1":
		push_error("Wrong candidate index")
		quit(2)
		return
	var grouped: Dictionary = {}
	for record in source["records"]:
		grouped.get_or_add(int(record["screen"]),[]).append(record)
	var screens: Array = grouped.keys()
	screens.sort()
	var game := ProbeGame.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	game.vm.cancel_all()
	game.vm.globals["vision"] = 0
	game.playing = false
	var results := []
	for screen in screens:
		game.vm.cancel_all()
		game.load_map(int(screen),false)
		await process_frame
		await physics_frame
		game.vm.cancel_all()
		for record in grouped[screen]:
			var id := 0
			for candidate in game.entities:
				if int(candidate) == 1: continue
				var e: Dictionary = game.entities[candidate]
				if int(e.get("editor_num",-1)) != int(record["editor_index"]): continue
				if absf(float(e.get("x",0))-float(record["source_xy"][0])) > 1.0: continue
				if absf(float(e.get("y",0))-float(record["source_xy"][1])) > 1.0: continue
				id = int(candidate)
				break
			var item := {"screen":int(screen),"list_index":int(record["list_index"]),
				"editor_index":int(record["editor_index"]),"script":str(record["script"]),
				"mode":str(record["mode"]),"source_xy":record["source_xy"],
				"entity_id":id,"talk_procedure":false,"before":{},"after":{}}
			if id != 0:
				item["talk_procedure"] = not game.vm._procedure_code(str(game.entities[id].get("script","")).to_lower(),"talk").is_empty()
				item["before"] = _query(game,id,record,"before",limit)
				if not before_only: item["after"] = _query(game,id,record,"after",limit)
			else: item["status"] = "ENTITY_MISSING"
			results.append(item)
		print("DISPATCH CENSUS screen ",screen," records ",results.size()," elapsed_ms ",Time.get_ticks_msec())
	var counts := {"records":results.size(),"before_eligible":0,"before_visited":0,"before_dispatch":0,
		"after_eligible":0,"after_visited":0,"after_dispatch":0,"total_query_ms":0}
	for item in results:
		for when in ["before","after"]:
			var q: Dictionary = item[when]
			if q.is_empty(): continue
			counts[when+"_eligible"] += int(q["eligible_cells"])
			counts[when+"_visited"] += int(q["visited_cells"])
			counts[when+"_dispatch"] += int(q["actual_dispatch_cells"])
			counts["total_query_ms"] += int(q["milliseconds"])
	var out := {"schema":"rc5-native-full-dispatch-census-1","mode":"baseline_before" if before_only else "current_before_after",
		"setup":"isolated scene load; vision0; scripts off; direct native talk/melee selection with intercepted _run_event; camera aims at each source target",
		"limit_per_record":limit,"source_candidate_counts":source["counts"],"counts":counts,"records":results,
		"limits":["Positive records stop at a real dispatch witness and do not census every eligible white pixel; a negative is exhaustive only when visited_cells equals eligible_cells.",
			"Aimed yaw is chosen for each source target; actual player gaze in free exploration can differ.",
			"No story/screen startup scripts, saves, or real input event are run; the exact FPS _talk and _fps_melee_target selection methods are called after all target clauses pass.",
			"Static integer reachable cells and authored range are prefiltered by the companion PNG masks; limit_per_record can additionally stop negative scans early."]}
	var file := FileAccess.open(out_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(out,"\t"))
	print("DISPATCH CENSUS DONE ",counts)
	game.queue_free()
	await process_frame
	await process_frame
	quit(0)
