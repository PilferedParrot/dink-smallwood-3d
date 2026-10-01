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
	var vision := 0 # --vision=N: the story layer to load (scenario setup)
	var batch := "" # --batch=file.json --out-dir=DIR: many views of this screen in one run (see _shoot)
	var out_dir := ""
	var shadows := true # --shadows=0: the light's shadows off (the sprites' own pixels only: for before/after views)
	var move := PackedStringArray() # --move=x,y,toX,toY: scenario setup, the map's actor at (x, y) stands at (toX, toY)
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
		if arg.begins_with("--vision="): vision = int(arg.trim_prefix("--vision="))
		if arg.begins_with("--batch="): batch = arg.trim_prefix("--batch=")
		if arg.begins_with("--out-dir="): out_dir = arg.trim_prefix("--out-dir=")
		if arg.begins_with("--shadows="): shadows = arg.trim_prefix("--shadows=") != "0"
		if arg.begins_with("--move="): move = arg.trim_prefix("--move=").split(",")
	game.vm.cancel_all()
	# A walk measures collision: load the screen's editor layer without its scripts
	# (scenario setup that skips progression, as tests/fps_wall_test.gd does).
	game.vm.globals["vision"] = vision
	game.load_map(screen, walk == 0 and scripts)
	if batch != "":
		# Frozen from the load: the same scene before and after a change, whatever the timing of the run
		# (live pigs and villagers move a few px in the time a run takes).
		game.set_physics_process(false)
		game.set_process(false)
	await create_timer(0.6).timeout
	if not shadows and game.fp_world != null and game.fp_world.light != null: game.fp_world.light.shadow_enabled = false
	if move.size() == 4:
		for id in game.entities.keys():
			var e: Dictionary = game.entities[id]
			if id == 1 or absf(float(e.get("x", -999)) - float(move[0])) > 1.0 or absf(float(e.get("y", -999)) - float(move[1])) > 1.0: continue
			e.x = float(move[2])
			e.y = float(move[3])
			game._update_visual(id)
			print("MOVED the actor of entity ", id, " to ", move[2], ",", move[3], " (scenario setup)")
	game.entities[1].x = x
	game.entities[1].y = y
	game.fps_yaw = yaw
	game.fps_pitch = pitch
	game._sync_fps_camera()
	game.vm.cancel_all()
	if batch != "":
		game.playing = false
		game.ui.close_menu()
		game.ui.visible = false
		for view in JSON.parse_string(FileAccess.get_file_as_string(batch)): await _shoot(game, view, out_dir)
		game.queue_free()
		await process_frame
		quit()
		return
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

# One view of the loaded screen, without the HUD or the viewmodel, saved as <out_dir>/<name>.png. A view is
# {"name", "x", "y", "yaw", "pitch"} (the player's eye in the screen's source pixels, as the other options),
# or {"name", "original": true}: the original's camera (orthographic, 45 degrees down, as the prototype's
# _original_view), the screen's 600 x 400 picture with the fog off.
func _shoot(game, view: Dictionary, out_dir: String) -> void:
	var cam: Camera3D = game.camera
	var original := bool(view.get("original", false))
	var environment: Environment = game.fp_world.environment
	if original:
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.keep_aspect = Camera3D.KEEP_WIDTH
		cam.size = 600.0 * GAME.SCALE
		cam.near = 0.05
		cam.far = 200.0
		cam.position = Vector3(0, 1, 1).normalized() * 40.0
		cam.look_at(Vector3.ZERO, Vector3.UP)
		if environment: environment.fog_enabled = false
	else:
		if environment: environment.fog_enabled = true
		cam.keep_aspect = Camera3D.KEEP_HEIGHT # as the game keeps it (an original-camera view before this one set KEEP_WIDTH)
		game.entities[1].x = float(view.x)
		game.entities[1].y = float(view.y)
		game.fps_yaw = float(view.yaw)
		game.fps_pitch = float(view.get("pitch", -0.05))
		game._sync_fps_camera()
	for model in [game.fps_viewmodel, game.fps_hand]:
		if is_instance_valid(model): model.visible = false
	# The game redraws its sprites for the camera every frame (an actor's frame is the one drawn for its
	# facing as seen from the camera); the batch is frozen, so redraw them once for this view.
	for id in game.entities.keys(): game._update_visual(id)
	if game.fp_world != null and game.fp_world.has_method("face_neighbours"): game.fp_world.face_neighbours()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	if original:
		var rows := int(round(img.get_width() * (400.0 / sqrt(2.0)) / 600.0))
		img = img.get_region(Rect2i(0, (img.get_height() - rows) / 2, img.get_width(), rows))
		img.resize(600, 400, Image.INTERPOLATE_LANCZOS)
	img.save_png(out_dir.path_join(str(view.name) + ".png"))
	print("SHOT ", view.name)
