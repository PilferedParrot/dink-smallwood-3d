extends SceneTree
# Frame-time probe: wall time between consecutive frame_post_draw for a fixed camera on one screen.
# llvmpipe (software GL under xvfb) numbers are RELATIVE only: compare checkouts, never read as real fps.
# Verdict (2026-09-30, Sonnet): works with both checkouts; prints one PERF line (see report in tmp/perf-baseline.txt).
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
	var frames := 300
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screen="): screen = int(arg.trim_prefix("--screen="))
		if arg.begins_with("--x="): x = float(arg.trim_prefix("--x="))
		if arg.begins_with("--y="): y = float(arg.trim_prefix("--y="))
		if arg.begins_with("--yaw="): yaw = float(arg.trim_prefix("--yaw="))
		if arg.begins_with("--pitch="): pitch = float(arg.trim_prefix("--pitch="))
		if arg.begins_with("--frames="): frames = int(arg.trim_prefix("--frames="))
	game.vm.cancel_all()
	# Scenario setup that skips progression (as fps_capture.gd's walk mode does): the screen's
	# editor layer is loaded WITHOUT its scripts, so the measured scene is the static layout.
	game.vm.globals["vision"] = 0
	var t0 := Time.get_ticks_usec()
	game.load_map(screen, false)
	var load_ms := (Time.get_ticks_usec() - t0) / 1000.0
	await create_timer(0.6).timeout
	game.entities[1].x = x
	game.entities[1].y = y
	game.fps_yaw = yaw
	game.fps_pitch = pitch
	game._sync_fps_camera()
	game.vm.cancel_all()
	game.playing = false
	game.ui.close_menu()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for _i in 30:
		await RenderingServer.frame_post_draw
	var dts: Array[float] = []
	await RenderingServer.frame_post_draw
	var last := Time.get_ticks_usec()
	for _i in frames:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		dts.append((now - last) / 1000.0)
		last = now
	var sorted := dts.duplicate()
	sorted.sort()
	var sum := 0.0
	for d in dts: sum += d
	var mean := sum / maxf(1.0, float(dts.size()))
	var p50: float = sorted[int(sorted.size() * 0.50)] if sorted.size() > 0 else 0.0
	var p95: float = sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))] if sorted.size() > 0 else 0.0
	print("PERF screen=%d load_ms=%.1f frames=%d mean_ms=%.2f p50_ms=%.2f p95_ms=%.2f nodes=%d" % [screen, load_ms, dts.size(), mean, p50, p95, get_node_count()])
	game.queue_free()
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	quit()
