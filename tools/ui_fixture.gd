extends SceneTree
## Create an explicitly staged save for exported HUD/feed visibility checks.
## Verdict: this skips campaign progression and map startup scripts; it only
## supplies a save. Subsequent rendering and attack inputs use the actual export.
const GAME := preload("res://scripts/fps_game.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := ""
	var text_size := 1.0
	var pickup := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
		if arg.begins_with("--text-size="): text_size = float(arg.trim_prefix("--text-size="))
		if arg == "--pickup": pickup = true
	if not out.is_absolute_path():
		push_error("Pass --out=/absolute/path/adventure.json")
		quit(2)
		return
	var game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	await game._new_game()
	game.vm.cancel_all()
	game.vm.globals["story"] = 1
	# Already fed: the item still scatters grain, while the bully cutscene does
	# not interrupt this explicitly staged presentation/input check.
	game.vm.globals["pig_story"] = 1
	game.vm.globals["vision"] = 0
	game.items.append({"script": "item-pig", "name": "Pig feed", "seq": 438, "frame": 2})
	game.vm.globals["cur_weapon"] = game.items.size()
	game.load_map(407, false)
	for id in game.entities:
		if int(id) != 1: game.entities[id].frozen = true
	game.entities[1].x = 320.0
	game.entities[1].y = 310.0
	game.entities[1].frozen = false
	if pickup:
		game.entities[1].x = 230.0
		game.entities[1].y = 290.0
		game.vm.globals["life"] = 5
		var heart := int(await game.dink_call("create_sprite", [230, 255, 6, 52, 1], {}))
		game.entities[heart].script = "heart"
		await game.vm.run("heart", "main", heart)
	game.fps_yaw = 0
	game.fps_pitch = -0.85
	game._sync_fps_camera()
	game.ui.close_menu()
	game.dialogue_busy = false
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var ok: bool = game._save_game(out)
	game.settings["text_scale"] = text_size
	game._write_json(out.get_base_dir().path_join("settings.json"), game.settings)
	print("UI FIXTURE: map 407, injected pig feed, skipped progression/startup scripts; save ", out, " success ", ok)
	game.vm.cancel_all()
	game.queue_free()
	await process_frame
	await process_frame
	quit(0 if ok else 1)
