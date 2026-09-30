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
	var walk := 0 # frames to hold W (the real input path) before the capture
	var back := 0.0 # then mark where he stopped and step the camera back this many px
	var scripts := true # --scripts=0: the screen's editor layer without its scripts, as a walk loads it
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screen="): screen = int(arg.trim_prefix("--screen="))
		if arg.begins_with("--x="): x = float(arg.trim_prefix("--x="))
		if arg.begins_with("--y="): y = float(arg.trim_prefix("--y="))
		if arg.begins_with("--yaw="): yaw = float(arg.trim_prefix("--yaw="))
		if arg.begins_with("--pitch="): pitch = float(arg.trim_prefix("--pitch="))
		if arg.begins_with("--out="): path = arg.trim_prefix("--out=")
		if arg.begins_with("--walk="): walk = int(arg.trim_prefix("--walk="))
		if arg.begins_with("--back="): back = float(arg.trim_prefix("--back="))
		if arg.begins_with("--scripts="): scripts = arg.trim_prefix("--scripts=") != "0"
	game.vm.cancel_all()
	# A walk measures collision: load the screen's editor layer without its scripts
	# (scenario setup that skips progression, as tests/fps_wall_test.gd does).
	game.vm.globals["vision"] = 0
	game.load_map(screen, walk == 0 and scripts)
	await create_timer(0.6).timeout
	game.entities[1].x = x
	game.entities[1].y = y
	game.fps_yaw = yaw
	game.fps_pitch = pitch
	game._sync_fps_camera()
	game.vm.cancel_all()
	if walk > 0:
		game.playing = true
		game.changing = false
		game.warp_cooldown = 1.0
		game.ui.close_menu()
		var down := InputEventKey.new(); down.physical_keycode = KEY_W; down.pressed = true
		Input.parse_input_event(down)
		for _i in walk:
			# Hold the heading: a rendered window captures the mouse, and the warp to its
			# centre arrives as look input. Movement is still the real W key.
			game.fps_yaw = yaw; game.fps_pitch = pitch
			game._sync_fps_camera() # movement reads the camera's heading
			await physics_frame
		var up := InputEventKey.new(); up.physical_keycode = KEY_W; up.pressed = false
		Input.parse_input_event(up)
		await physics_frame
		var stop: Vector2 = game._position2(1)
		print("WALKED to ",stop," on ",game.current_screen)
		if back > 0.0:
			# Evidence view: a post where he stopped, seen from behind him at eye level.
			var post := MeshInstance3D.new()
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.1; cylinder.bottom_radius = 0.1; cylinder.height = 2.0
			post.mesh = cylinder
			var paint := StandardMaterial3D.new()
			paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			paint.albedo_color = Color(1.0,0.1,0.7)
			post.material_override = paint
			post.position = Vector3((stop.x-320.0)*GAME.SCALE,1.0,(stop.y-200.0)*GAME.SCALE)
			game.scene_root.add_child(post)
			var heading := Vector2(-sin(yaw),-cos(yaw))
			game.entities[1].x = stop.x-heading.x*back
			game.entities[1].y = stop.y-heading.y*back
			game.fps_yaw = yaw; game.fps_pitch = pitch
			game._sync_fps_camera()
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
