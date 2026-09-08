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
	await create_timer(0.38).timeout
	var grains: Array[int] = []
	for id in game.visuals:
		var visual: Node = game.visuals[id]
		if is_instance_valid(visual) and visual.get_meta("model_key", "") == "feed_grains": grains.append(int(id))
	check(not grains.is_empty(), "Original item-pig use creates feed_grains visuals")
	for id in grains:
		var visual: Node = game.visuals[id]
		check(visual.get_node_or_null("HitBody") == null, "Feed grains have no collider")
	await _capture("feed-use.png")

	# Dialogue framing fixture: test_mode is disabled so the real UI/dialogue
	# path is exercised; the entity is deliberately off-camera before the line.
	game.test_mode = false
	game.entities[2] = {"x": 500.0, "y": 200.0, "active":1, "script":"s1-bul", "type":1}
	game.fps_yaw = 0.0
	game.fps_pitch = 1.0
	game._sync_fps_camera()
	var before: float = game.fps_yaw
	game._dialogue("A Milder line", 2, {"sprite_id":2})
	await process_frame
	check(not is_equal_approx(before, game.fps_yaw), "Off-camera NPC dialogue frames the camera on the speaker")
	check(game.fps_pitch < 0.2, "NPC framing recovers from looking at the ceiling")
	check(game._fps_speaker_name(2) == "Milder", "Milder receives a readable speaker label")
	check(game.ui.column.get_child_count() > 0 and game.ui.column.get_child(0).text == "Milder", "Dialogue UI displays the NPC name")
	await _capture("offcamera-milder.png")
	var framed_yaw: float = game.fps_yaw
	game.entities[900002] = {"x": 140.0, "y": 200.0, "active": 1, "script": "s1-h2-o", "type": 1}
	game._dialogue("An Ethel line", 900002, {"sprite_id": 900002})
	await process_frame
	check(is_equal_approx(framed_yaw, game.fps_yaw), "Queued dialogue cannot frame a later speaker before its line")
	game.ui.dialogue_finished.emit(0)
	await process_frame
	await process_frame
	check(not is_equal_approx(framed_yaw, game.fps_yaw), "Next speaker is framed when its queued line begins")
	game.ui.dialogue_finished.emit(0)
	await process_frame
	framed_yaw = game.fps_yaw
	game._dialogue("A Dink line", 1, {"sprite_id": 1})
	await process_frame
	check(is_equal_approx(framed_yaw, game.fps_yaw), "Dink's own line keeps the current view")
	game.ui.dialogue_finished.emit(0)
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
