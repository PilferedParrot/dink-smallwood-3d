extends SceneTree
# Isolated native FPS interactions. Campaign and screen startup scripts are
# skipped; only the neighboring barrel HIT handlers run where stated below.
const TARGETS = preload("res://scripts/entity_hit_targets.gd")

class ProbeGame extends "res://scripts/fps_game.gd":
	var caught_events: Array = []
	var run_barrel_hit_script := false
	func _run_event(id: int, event: String) -> void:
		caught_events.append([id,event])
		if run_barrel_hit_script and event == "hit" and current_screen == 229 \
				and entities.has(id) and str(entities[id].get("script","")) == "bar-e":
			super._run_event(id,event)

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)

func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame
	await physics_frame

func editor_id(game, editor_index: int) -> int:
	for id in game.entities:
		if int(id) != 1 and int(game.entities[id].get("editor_num",-1)) == editor_index:
			return int(id)
	return 0

func has_event(game, id: int, event: String) -> bool:
	return game.caught_events.any(func(item): return int(item[0]) == id and str(item[1]) == event)

func aim_at(game, from: Vector2, target: Vector2) -> void:
	game.entities[1].x = from.x
	game.entities[1].y = from.y
	game.fps_yaw = atan2(-(target.x-from.x),-(target.y-from.y))
	game.fps_pitch = -0.08
	game._sync_fps_camera()
	game._fps_set_facing_from_camera()

func _run() -> void:
	var game := ProbeGame.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	await game._new_game()
	game.vm.cancel_all()
	game.ui.close_menu()
	game.load_map(768,false)
	game.vm.cancel_all()
	game.ui.close_menu()
	var id := editor_id(game,4)
	check(id != 0 and str(game.entities.get(id,{}).get("script","")) == "savebot",
		"authored savebot editor4 exists")
	if id != 0:
		var actor := game._position2(id)
		var visual := game.visuals.get(id) as Node3D
		var helper := TARGETS.new()
		var bounds := helper.bounds(visual,id)
		check(bounds.end.y-visual.global_position.y <= 0.80,
			"savebot upper bound follows actual mesh")
		aim_at(game,Vector2(322,78),actor)
		check(game._fps_line_clear(Vector2(322,78),actor),"north planar line clear")
		check(not helper.first_hit(visual,id,game.camera.global_position,
			game.get_world_3d().direct_space_state,3).is_empty(),"north own surface ray")
		game.caught_events.clear()
		game._talk()
		check(has_event(game,id,"talk"),"north FPS talk dispatch")
		# Reproduce the packed-save south approach with real movement and E.
		game.entities[1].x = 322.0
		game.entities[1].y = 240.0
		game.entities[1].frozen = false
		game.entities[1].nocontrol = 0
		game.playing = true
		game.changing = false
		game.fps_yaw = 0.0
		game.fps_pitch = -0.45
		game._sync_fps_camera()
		for i in 3: await physics_frame
		check(not game._blocked(game._position2(1),1),"south packed start free")
		await key(KEY_W,true)
		var frames := 0
		while game._position2(1).y > 185.0 and frames < 120:
			await physics_frame
			frames += 1
		await key(KEY_W,false)
		var south: Vector2 = game._position2(1)
		check(south.distance_to(Vector2(322,184)) < 0.05 and frames < 120,
			"real W input reaches exact south pose")
		check(game.current_screen == 768 and not game._blocked(south,1),"south pose free on768")
		check(not game._fps_line_clear(south,actor) and game._tile_blocked(Vector2(322,174)),
			"legacy planar line crosses authored tile798")
		check(game._fps_ray_reaches(id),"south own physics surface reached")
		game.caught_events.clear()
		await key(KEY_E,true)
		await key(KEY_E,false)
		check(has_event(game,id,"talk"),"real south E dispatches savebot TALK")
		# A real foreign solid between eye and target defeats own-body rays.
		var blocker := StaticBody3D.new()
		blocker.name = "ForeignPhysicalOccluder"
		blocker.collision_layer = 1
		blocker.collision_mask = 0
		blocker.position = Vector3(0.05,1.5,-0.8)
		var block_shape := CollisionShape3D.new()
		var block_box := BoxShape3D.new()
		block_box.size = Vector3(20.0,5.0,0.2)
		block_shape.shape = block_box
		blocker.add_child(block_shape)
		var visible_face := MeshInstance3D.new()
		var visible_box := BoxMesh.new()
		visible_box.size = block_box.size
		visible_face.mesh = visible_box
		blocker.add_child(visible_face)
		game.scene_root.add_child(blocker)
		await physics_frame
		check(visible_face.visible and visible_face.mesh != null,
			"foreign blocker has visible solid geometry")
		check(not game._fps_ray_reaches(id),"foreign solid blocks own target ray")
		game.caught_events.clear()
		await key(KEY_E,true)
		await key(KEY_E,false)
		check(not has_event(game,id,"talk"),"occluded E cannot dispatch")
		blocker.queue_free()
		await physics_frame
		check(game._fps_ray_reaches(id),"removing foreign solid restores ray")
		# Fist still uses source frame hardbox and directional HIT range.
		var target: Dictionary = game.entities[id]
		check(not game.vm._procedure_code(str(target.get("script","")).to_lower(),"hit").is_empty(),
			"savebot source script defines original HIT handler")
		var source_hb: Rect2 = game._hard_rect(target)
		var fist: Rect2 = game._fps_melee_hit_rect(target,8,0)
		check(absf(fist.position.x-(source_hb.position.x-15.0)) < 0.01
			and absf(fist.end.y-(source_hb.end.y+46.0)) < 0.01,
			"north-facing fist extends original source hardbox")
		# The new-game fixture equips a bow; choose its real fist slot, or the
		# production unarmed fallback (cur_weapon=0) for melee dispatch.
		var fist_slot := 0
		for i in game.items.size():
			if str(game.items[i].get("script","")) == "item-fst": fist_slot = i+1
		game.vm.globals["cur_weapon"] = fist_slot
		game.attack_cooldown = 0.0
		game._fps_set_facing_from_camera()
		check(game._fps_melee_target() == id,"inside source HIT rectangle selects savebot")
		game.caught_events.clear()
		game._fps_attack()
		check(has_event(game,id,"hit"),"inside fist dispatches original HIT")
		aim_at(game,Vector2(322,205),actor)
		game.attack_cooldown = 0.0
		check(game._fps_ray_reaches(id),"outside HIT rectangle still has own ray")
		check(game._fps_melee_target() != id,"outside source HIT rectangle cannot select")
		game.caught_events.clear()
		game._fps_attack()
		check(not has_event(game,id,"hit"),"outside fist does not dispatch HIT")
	# Scripted barrel break control: original bar-e HIT persists editor_type3;
	# reload applies those broken, noninteractive frames before retargeting.
	game.vm.cancel_all()
	game.playing = false
	game.load_map(229,false)
	await process_frame
	await physics_frame
	game.vm.cancel_all()
	var barrel := editor_id(game,19)
	check(barrel != 0 and str(game.entities.get(barrel,{}).get("script","")) == "bar-e",
		"barrel editor19 exists")
	if barrel != 0:
		aim_at(game,Vector2(120,168),game._position2(barrel))
		check(game._fps_ray_reaches(barrel),"barrel own ray before neighbors break")
		check(game._fps_melee_target() != barrel,"nearer intact barrel wins first")
		game.run_barrel_hit_script = true
		for editor in [18,20,21,22,23]:
			var neighbor := editor_id(game,editor)
			check(neighbor != 0 and str(game.entities.get(neighbor,{}).get("script","")) == "bar-e",
				"neighbor barrel editor%d exists" % editor)
			if neighbor != 0: game._run_event(neighbor,"hit")
		for i in 3: await process_frame
		for editor in [18,20,21,22,23]:
			check(int(game.editor_state.get("229:%d" % editor,{}).get("editor_type",0)) == 3,
				"original bar-e HIT persists broken editor%d" % editor)
		game.run_barrel_hit_script = false
		game.vm.cancel_all()
		game.load_map(229,false)
		await process_frame
		await physics_frame
		game.vm.cancel_all()
		barrel = editor_id(game,19)
		check(barrel != 0 and str(game.entities.get(barrel,{}).get("script","")) == "bar-e",
			"unbroken barrel keeps original HIT after reload")
		if barrel != 0:
			aim_at(game,Vector2(120,168),game._position2(barrel))
			check(game._fps_melee_target() == barrel,"breaking nearer barrels exposes editor19")
	game.vm.cancel_all()
	game.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("ENTITY HIT TARGETS LIVE PASS south E, occlusion, HIT rectangle, broken barrels")
		quit(0)
	else:
		for failure in failures: print("ENTITY HIT TARGETS LIVE FAIL ",failure)
		quit(1)
