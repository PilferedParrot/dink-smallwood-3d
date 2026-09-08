extends SceneTree
const GAME = preload("res://scripts/fps_game.gd")
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	await game._new_game()
	await create_timer(2).timeout
	var screen := 439
	var x := 505.0
	var y := 340.0
	var yaw := 0.55
	var pitch := -0.03
	var path := "/tmp/dink-fps.png"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screen="): screen = int(arg.trim_prefix("--screen="))
		if arg.begins_with("--x="): x = float(arg.trim_prefix("--x="))
		if arg.begins_with("--y="): y = float(arg.trim_prefix("--y="))
		if arg.begins_with("--yaw="): yaw = float(arg.trim_prefix("--yaw="))
		if arg.begins_with("--pitch="): pitch = float(arg.trim_prefix("--pitch="))
		if arg.begins_with("--out="): path = arg.trim_prefix("--out=")
	game.vm.cancel_all()
	game.load_map(screen)
	await create_timer(0.6).timeout
	game.entities[1].x = x
	game.entities[1].y = y
	game.fps_yaw = yaw
	game.fps_pitch = pitch
	game._sync_fps_camera()
	game.vm.cancel_all()
	game.playing = false
	game.ui.close_menu()
	game.ui.toast.text = ""
	game.ui.show_hud(game.vm.globals.merged({"location":game._location(), "weapon":"Bow"}))
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(path)
	print("CAPTURE ",path," nodes ",get_node_count())
	game.queue_free()
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	quit()
