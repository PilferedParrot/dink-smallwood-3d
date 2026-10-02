extends SceneTree
# Original-camera renders of many screens in one Godot run: the camera and crop of tests/fps_capture.gd _shoot with
# "original": true, each screen loaded as fps_capture --scripts=0 --batch loads it (editor layer, vision 0, frozen).
# Run by tools/original_batch.py (which see). --shadows=0 turns the light's shadows off.
# Verdict (2026-10-02, Opus 5.5, Dink M3 lead): pixel-identical to fps_capture.gd's single-screen render (471) and
# independent of the screens' order (30, 376, 471); 222 screens in about 90 s on three runs, where one Godot run per
# screen took an hour and hung under concurrent `xvfb-run -a`.
const GAME = preload("res://scripts/fps_game.gd")
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var screens: Array = []
	var out_dir := ""
	var shadows := true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screens="):
			for s in arg.trim_prefix("--screens=").split(",", false): screens.append(int(s))
		if arg.begins_with("--out-dir="): out_dir = arg.trim_prefix("--out-dir=")
		if arg == "--shadows=0": shadows = false
	var game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	await game._new_game()
	await create_timer(2).timeout
	for n in screens:
		game.set_physics_process(true)
		game.set_process(true)
		game.vm.cancel_all()
		game.vm.globals["vision"] = 0
		game.load_map(int(n), false)
		game.set_physics_process(false)
		game.set_process(false)
		await create_timer(0.6).timeout
		game.vm.cancel_all()
		game.playing = false
		game.ui.close_menu()
		game.ui.visible = false
		var cam: Camera3D = game.camera
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.keep_aspect = Camera3D.KEEP_WIDTH
		cam.size = 600.0 * GAME.SCALE
		cam.near = 0.05
		cam.far = 200.0
		cam.position = Vector3(0, 1, 1).normalized() * 40.0
		cam.look_at(Vector3.ZERO, Vector3.UP)
		if not shadows and game.fp_world.light != null: game.fp_world.light.shadow_enabled = false
		var environment: Environment = game.fp_world.environment
		if environment: environment.fog_enabled = false
		for model in [game.fps_viewmodel, game.fps_hand]:
			if is_instance_valid(model): model.visible = false
		for id in game.entities.keys(): game._update_visual(id)
		if game.fp_world.has_method("face_neighbours"): game.fp_world.face_neighbours()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := get_root().get_texture().get_image()
		var rows := int(round(img.get_width() * (400.0 / sqrt(2.0)) / 600.0))
		img = img.get_region(Rect2i(0, (img.get_height() - rows) / 2, img.get_width(), rows))
		img.resize(600, 400, Image.INTERPOLATE_LANCZOS)
		img.save_png(out_dir.path_join("%d.png" % int(n)))
		print("SHOT ", n)
	game.queue_free()
	await process_frame
	quit()
