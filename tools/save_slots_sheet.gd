extends SceneTree
## Native frames of every menu that lists save slots or button actions, for the
## save-slots unit. Rendered (software GL under xvfb), real choice input, an isolated
## profile (run through godot-scratch). Usage:
##   godot --audio-driver Dummy --resolution 1920x1080 --path game --script tools/save_slots_sheet.gd -- --out=DIR
## Writes DIR/<menu>-<font>-<pct>.png for menu in savebot, escape-buttons, start2-load,
## pause-save, pause-load, title-continue.
const GAME = preload("res://scripts/fps_game.gd")
var game
var out_dir := ""
func _initialize() -> void: _run.call_deferred()
func settle() -> void:
	for _i in 10:
		game.ui._process(0)
		await process_frame
func tap(code: Key) -> void:
	for pressed in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code; event.physical_keycode = code; event.pressed = pressed
		Input.parse_input_event(event); Input.flush_buffered_events()
		await process_frame
	await settle()
func shot(name: String) -> void:
	await settle()
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("SHEET ", name, " ", img.get_width(), "x", img.get_height())
func machine_talk() -> void:
	for id in game.entities:
		if str(game.entities[id].get("script","")).to_lower() == "savebot":
			await game.vm.run("savebot", "talk", int(id)); return
func fixtures() -> void:
	for slot in range(1, 11):
		if FileAccess.file_exists(game.SAVE_SLOTS.path(slot)): DirAccess.remove_absolute(game.SAVE_SLOTS.path(slot))
	for row in [[1, 27, 2, 1700000000], [3, 83, 4, 1700000100], [7, 605, 9, 1700000200]]:
		game.play_minutes_base = row[1]; game.play_started_msec = Time.get_ticks_msec()
		game.vm.globals["level"] = row[2]
		game._save_game(game.SAVE_SLOTS.path(row[0]))
		var data: Dictionary = game._read_json(game.SAVE_SLOTS.path(row[0]))
		data["saved_at"] = row[3]
		game._write_json(game.SAVE_SLOTS.path(row[0]), data)
func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out_dir = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	game = GAME.new(); game.test_mode = true
	root.add_child(game); await process_frame
	game.vm.cancel_all(); game.set_physics_process(false)
	var screen := 0
	for key in game.world.screens:
		for sprite in game.world.screens[key].get("sprites",[]):
			if str(sprite.get("script","")).to_lower() == "savebot": screen = int(key); break
		if screen != 0: break
	game.load_map(screen, false); game.ui.close_menu(); game.ui.set_process(false)
	game.playing = true; game.test_mode = false
	fixtures()
	for plain in [false, true]:
		for scale in [1.0, 2.0]:
			game.settings.text_scale = scale; game.settings.plain_font = plain
			game._apply_settings()
			var tag := "%s-%d" % ["plain" if plain else "pixel", int(scale * 100)]
			game.vm.cancel_all(); game.ui.close_menu(); await settle()
			game.entities[1].frozen = false
			machine_talk(); await settle(); await tap(KEY_ENTER)
			await shot("savebot-" + tag)
			game.ui.close_menu(); game.vm.cancel_all(); await settle()
			game.entities[1].frozen = false
			game.vm.run("escape", "main", 1); await settle()
			for _i in 5: await tap(KEY_DOWN)
			await tap(KEY_ENTER)
			await shot("escape-buttons-" + tag)
			game.ui.close_menu(); game.vm.cancel_all(); await settle()
			game.entities[1].frozen = false
			game.vm.run("start-2", "load", 1); await settle()
			await shot("start2-load-" + tag)
			game.ui.close_menu(); game.vm.cancel_all(); await settle()
			game.ui.show_pause(); game._ui_action("save", null); await shot("pause-save-" + tag)
			game._ui_action("load", null); await shot("pause-load-" + tag)
			game.ui.show_title(true); game._ui_action("continue", null); await shot("title-continue-" + tag)
			game.ui.close_menu()
	for slot in range(1, 11):
		if FileAccess.file_exists(game.SAVE_SLOTS.path(slot)): DirAccess.remove_absolute(game.SAVE_SLOTS.path(slot))
	game.queue_free(); await process_frame
	quit(0)
