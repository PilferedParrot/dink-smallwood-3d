extends SceneTree

const GAME := preload("res://scripts/fps_game.gd")

var failures: Array[String] = []
var out_dir := "/tmp/dink-fps-fire-world"

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
	var game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	await game._new_game()
	game.vm.cancel_all()
	game.playing = false
	game.ui.close_menu()
	game.set_physics_process(false)
	check(game.fp_world.model_key({"pseq": 231, "pframe": 1}) == "wizard", "Oldman source maps to wizard")
	check(game.fp_world.model_key({"pseq": 221, "pframe": 1}) == "woman", "Red maiden source maps to woman")
	check(game.fp_world.model_key({"pseq": 411, "pframe": 1}) == "knight", "Peasant2 source maps to Silver knight")
	check(game.fp_world.model_key({"pseq": 257, "pframe": 1}) == "woman", "Blue maiden source maps to woman")

	# These are source-backed map 439 fixtures: vision 1 contains the fire
	# sprites, while vision 2 contains the holes and surviving ruin detail.
	game.vm.globals["vision"] = 1
	game.load_map(439, false)
	await process_frame
	var fire_keys := _keys(game)
	check(fire_keys.has("cottage"), "Fire fixture keeps the source cottage")
	check(fire_keys.has("flame"), "Vision 1 maps source fire sprites to flame geometry")
	check(fire_keys.has("burn_scar"), "Vision 1 maps source damag sprite to burn scar geometry")
	check(not fire_keys.has("rock"), "Fire fixture does not regress damage sprites to generic rocks")
	check(_damage_has_no_hit_bodies(game), "Fire markers do not change the cottage collision route")
	check(_story_house_state(game) == "burning", "Only Dink's source home receives the attached burning treatment")
	_position_for_house(game)
	_show_discovery_dialogue(game)
	await _capture("story3-fire.png")

	game.vm.globals["vision"] = 2
	game.load_map(439, false)
	await process_frame
	var ruin_keys := _keys(game)
	check(ruin_keys.has("ruin"), "Vision 2 retains source home rubble piece")
	check(ruin_keys.has("hole"), "Vision 2 maps source hole sprites to wall openings")
	check(ruin_keys.has("cottage"), "Vision 2 preserves the original cottage structural body")
	check(not ruin_keys.has("rock"), "Ruin fixture does not regress hole sprites to generic rocks")
	check(_damage_has_no_hit_bodies(game), "Ruin markers do not change the cottage collision route")
	check(_story_house_state(game) == "charred", "Only Dink's source home receives the attached charred treatment")
	_position_for_house(game)
	_show_discovery_dialogue(game)
	await _capture("story5-ruin.png")
	game.ui.hide_dialogue()
	_position_for_front_door(game)
	await _capture("story5-ruin-door.png")

	if failures.is_empty(): print("FPS FIRE WORLD PASS: source-backed fire and ruin fixtures")
	else: print("FPS FIRE WORLD FAILURES: ", failures)
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _keys(game) -> Dictionary:
	var result: Dictionary = {}
	for id in game.visuals:
		var visual: Node = game.visuals[id]
		if is_instance_valid(visual): result[str(visual.get_meta("model_key", ""))] = true
	return result

func _position_for_house(game) -> void:
	# Reproduce the actual story-3 discovery checkpoint from the accepted
	# campaign trace (map 439, x=570.9167, y=226.9865, yaw=1.61395).
	game.entities[1]["x"] = 570.9167
	game.entities[1]["y"] = 226.9865
	game.fps_yaw = 1.61395
	game.fps_pitch = 0.0076
	game._sync_fps_camera()

func _position_for_front_door(game) -> void:
	# Door sprite 13 is at (368,280), below the home-01 hard rectangle.  This
	# faces north toward the original entry facade without changing player state.
	game.entities[1]["x"] = 368.0
	game.entities[1]["y"] = 310.0
	game.fps_yaw = 0.0
	game.fps_pitch = 0.0
	game._sync_fps_camera()

func _story_house_state(game) -> String:
	var states: Array[String] = []
	for id in game.visuals:
		var visual: Node = game.visuals[id]
		if is_instance_valid(visual) and visual.has_meta("story_house_state"):
			states.append(str(visual.get_meta("story_house_state")))
	check(states.size() == 1, "Story treatment is attached to exactly one map 439 cottage")
	return states[0] if states.size() == 1 else ""

func _damage_has_no_hit_bodies(game) -> bool:
	for id in game.visuals:
		var visual: Node = game.visuals[id]
		if not is_instance_valid(visual): continue
		if str(visual.get_meta("model_key", "")) in ["flame","burn_scar","hole","ruin"] and visual.get_node_or_null("HitBody") != null:
			return false
	return true

func _show_discovery_dialogue(game) -> void:
	# Keep the actual story line visible without advancing the async script task.
	game.ui.show_dialogue("What, the house, mother nooooo!!!", "Dink")

func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await process_frame
	get_root().get_texture().get_image().save_png(out_dir.path_join(name))
