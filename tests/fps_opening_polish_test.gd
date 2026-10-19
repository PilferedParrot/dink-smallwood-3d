extends SceneTree

const GAME := preload("res://scripts/fps_game.gd")

var game
var failures: Array[String] = []
var out_dir := "/tmp/dink-fps-opening-polish"

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out-dir="): out_dir = arg.trim_prefix("--out-dir=")
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	await game._new_game()
	game.vm.cancel_all()
	game.playing = true
	game.entities[1]["frozen"] = false
	game.entities[1]["nocontrol"] = 0
	game.entities[1]["disabled"] = 0
	game.ui.close_menu()
	game._fps_update_mouse_mode()
	game.set_physics_process(false)

	# Fixture setup is deliberate: this is an opening-presentation regression,
	# not a claim that the campaign has reached the pig-feed quest naturally.
	game.items = [{"script":"item-pig", "name":"Pig feed", "seq":0, "frame":1}]
	game.vm.globals["cur_weapon"] = 1
	game.entities[1]["x"] = 320.0
	game.entities[1]["y"] = 200.0
	game._sync_fps_camera()
	game._fps_update_viewmodel(0.016)
	check(is_instance_valid(game.fps_viewmodel), "Pig feed creates a first-person viewmodel")
	check(game.fps_viewmodel.name == "FirstPersonPigFeed", "Pig feed viewmodel has a stable presentation node")
	var feed_label: Label3D
	for child in game.fps_viewmodel.get_children():
		if child is Label3D: feed_label = child
	check(feed_label != null and feed_label.text == "FEED", "Equipped feed is visibly labeled")
	await _capture("feed-equipped.png")

	# Use the actual mapped action path, then inspect the transient motion and
	# original script effect rather than calling a test-only helper.
	game.attack_cooldown = 0.0
	game.fps_fire_held = false
	game.entities[1]["frozen"] = false
	game.entities[1]["nocontrol"] = 0
	game.entities[1]["disabled"] = 0
	Input.action_press("attack")
	game._physics_process(0.016)
	Input.action_release("attack")
	check(game.fps_feed_use > 0.0, "Using pig feed starts the transient use motion")
	# ITEM-PIG waits before it creates its source-script grain sprite. Rendered
	# llvmpipe frames can take longer than the former fixed delay, so observe the
	# actual script-created visual through a bounded frame loop.
	var grains := await _wait_for_feed_grains(1.5)
	check(not grains.is_empty(), "Original item-pig use creates feed_grains visuals")
	for id in grains:
		var visual: Node = game.visuals[id]
		check(visual.get_node_or_null("HitBody") == null, "Feed grains have no collider")
	await _capture("feed-use.png")

	# Dialogue framing fixture: test_mode is disabled so the real UI/dialogue
	# path is exercised. S1-BUL is originally spawned by ITEM-PIG with sequence
	# 341; this isolated actor keeps those source pixels and a real FPS visual.
	game.test_mode = false
	game.vm.globals["vision"] = 0
	game.load_map(439, false)
	game.entities[1]["x"] = 320.0
	game.entities[1]["y"] = 260.0
	var milder: int = 900101
	game.entities[milder] = {"x":350.0,"y":130.0,"active":1,"script":"s1-bul","type":1,"pseq":341,"pframe":1,"seq":0,"frame":1,"base_walk":400,"brain":0,"size":100,"hard":1,"runtime_created":true}
	game._create_visual(milder)
	check(game.visuals.has(milder) and game.visuals[milder].is_visible_in_tree(), "Source-sequence Milder has visible FPS geometry")
	game.fps_yaw = 0.0
	game.fps_pitch = 1.0
	game._sync_fps_camera()
	# FreeDink109.6 brain_keyboard.cpp:216-241 and dinkc_bindings.cpp:766-788:
	# text does not freeze Dink. Unfrozen speech must leave the player's view.
	var free_view: Transform3D = game.camera.global_transform
	game._dialogue("An unfrozen Milder line", milder, {"sprite_id":milder})
	await _wait_for_dialogue_layout()
	check(is_equal_approx(game.fps_yaw, 0.0) and is_equal_approx(game.fps_pitch, 1.0) and game.camera.global_transform.is_equal_approx(free_view), "Unfrozen NPC speech preserves the player's exact camera")
	check(not game.ui.modal and not game.entities[1].get("frozen",false), "Unfrozen speech takes no modal input ownership")
	_end_line()
	for _i in 3: await process_frame
	# Real S1-BUL.main:14 freezes Dink before Milder's lines. Framing is our
	# frozen-dialogue presentation adaptation; retain the full visibility bar.
	await game.dink_call("freeze", [1], {})
	var before: float = game.fps_yaw
	game._dialogue("A Milder line stays visible while the measured camera settles and captures the complete actor.", milder, {"sprite_id":milder})
	await _wait_for_dialogue_layout()
	var milder_speech: int = game.ui.active_speech_id
	check(not is_equal_approx(before, game.fps_yaw), "Off-camera NPC dialogue frames the camera on the speaker")
	check(game.fps_pitch < 0.2, "NPC framing recovers from looking at the ceiling")
	_assert_actor_fit(milder, "Milder")
	check(game._fps_speaker_name(milder) == "Milder", "Milder receives a readable speaker label")
	check(game.ui.heading.text == "Milder" and game.ui.heading.is_visible_in_tree(), "Dialogue UI displays the NPC name in the fixed heading")
	await _capture("offcamera-milder.png")
	var framed_yaw: float = game.fps_yaw
	var ethel: int = 900102
	game.entities[ethel] = {"x":440.0,"y":130.0,"active":1,"script":"s1-h2-o","type":1,"pseq":231,"pframe":1,"seq":0,"frame":1,"base_walk":230,"brain":0,"size":100,"hard":1,"runtime_created":true}
	game._create_visual(ethel)
	# say_stop yields only its caller (dinkc_bindings.cpp:766-788): a different
	# speaker starts independently, rather than queuing on a global modal lock.
	game._dialogue("An Ethel line starts independently while the previous speaker still has its own text lifetime.", ethel, {"sprite_id":ethel})
	await _wait_for_dialogue_layout()
	var ethel_speech: int = game.ui.active_speech_id
	check(ethel_speech != milder_speech and game.ui.heading.text == "Ethel" and game.ui.is_speech_active(milder_speech), "Independent speaker starts while the previous caller still waits")
	check(not is_equal_approx(framed_yaw, game.fps_yaw), "Explicitly frozen next speaker receives its own framing")
	_assert_actor_fit(ethel, "Ethel")
	var ethel_view: Transform3D = game.camera.global_transform
	game.ui.cancel_speech_id(milder_speech)
	for _i in 3: await process_frame
	check(game.ui.active_speech_id == ethel_speech and game.camera.global_transform.is_equal_approx(ethel_view), "Older caller completion cannot restore over the current speaker's camera")
	_end_line()
	await process_frame
	await game.dink_call("unfreeze", [1], {})
	await process_frame
	framed_yaw = game.fps_yaw
	game._dialogue("A Dink line", 1, {"sprite_id": 1})
	await _wait_for_dialogue_layout()
	check(is_equal_approx(framed_yaw, game.fps_yaw), "Dink's own line keeps the current view")
	_end_line()
	await process_frame

	if failures.is_empty(): print("FPS OPENING POLISH PASS: feed viewmodel/use, grains, NPC framing")
	else: print("FPS OPENING POLISH FAILURES: ", failures)
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await process_frame
	get_root().get_texture().get_image().save_png(out_dir.path_join(name))

func _feed_grain_ids() -> Array[int]:
	var grains: Array[int] = []
	for id in game.visuals:
		var visual: Node = game.visuals[id]
		if is_instance_valid(visual) and visual.get_meta("model_key", "") == "feed_grains": grains.append(int(id))
	return grains

func _wait_for_feed_grains(timeout_seconds: float) -> Array[int]:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var grains := _feed_grain_ids()
		if not grains.is_empty(): return grains
		await process_frame
	return _feed_grain_ids()

func _wait_for_dialogue_layout() -> void:
	for i in 8:
		await process_frame
		if game.ui.page == "dialogue" and game.ui.panel.visible: return
	check(false, "Dialogue card becomes visible after its measured layout")

func _assert_actor_fit(id: int, label: String) -> void:
	if not game.visuals.has(id): return
	var source: Vector3 = game.camera.global_position
	var points: Array[Vector3] = game._fps_visible_points(game.visuals[id], source)
	check(points.size() >= 4, "%s uses visible source actor bounds" % label)
	if points.is_empty(): return
	var bounds: Rect2 = game._fps_projected_bounds(points)
	var safe: Rect2 = game.ui.speech_safe_rect()
	check(bounds.has_area() and safe.encloses(bounds), "%s whole actor fits above opaque UI" % label)
	check(game.fps_dialogue_frame_valid, "%s has a committed valid dialogue shot" % label)
	check(game._fps_subject_rays_clear(source, game._fps_points_center(points), points, id, false), "%s head and torso rays are clear" % label)

func _end_line() -> void:
	game.ui.cancel_speech()
