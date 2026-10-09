extends SceneTree
# Scenario setup: load screen 80 with vision 0, bypassing normal progression and screen scripts.
# Save the same frozen scene with its chains visible and hidden for a pixel subtraction.
const GAME = preload("res://scripts/fps_game.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out_dir := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out-dir="): out_dir = arg.trim_prefix("--out-dir=")
	if out_dir.is_empty(): quit(2); return
	DirAccess.make_dir_recursive_absolute(out_dir)
	var game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	await game._new_game()
	await create_timer(1.0).timeout
	game.vm.cancel_all()
	game.vm.globals["vision"] = 0
	game.load_map(80, false)
	await create_timer(0.6).timeout
	game.vm.cancel_all()
	game.set_physics_process(false)
	game.set_process(false)
	game.playing = false
	game.ui.close_menu()
	game.ui.visible = false
	for viewmodel in [game.fps_viewmodel,game.fps_hand]:
		if is_instance_valid(viewmodel): viewmodel.visible = false
	if game.fp_world.light != null: game.fp_world.light.shadow_enabled = false
	var chains: Array = []
	for id in game.entities.keys():
		if id == 1 or not game.fp_world.frame_path(game.entities[id]).ends_with("cdoor-06.png"): continue
		var model: Node3D = game.visuals[id].get_node_or_null("Model")
		for name in ["ChainLeft", "ChainRight"]:
			var chain: MeshInstance3D = model.get_node_or_null(name)
			if chain != null: chains.append(chain)
	# Fixed midpoint of the traced right-chain anchors in screen 80 world coordinates. A
	# mesh-derived target would move the before/after oblique cameras when link count changes.
	var target := Vector3(5.825,1.3342,2.2742)
	var joins := {
		"join_left_top": Vector3(3.675,2.2358,2.6008),
		"join_left_bottom": Vector3(5.575,0.01,3.3),
		"join_right_top": Vector3(4.875,2.6585,1.9985),
		"join_right_bottom": Vector3(6.775,0.01,2.55),
	}
	var cam: Camera3D = game.camera
	var environment: Environment = game.fp_world.environment
	for view in ["original", "oblique_left", "oblique_right", "join_left_top", "join_left_bottom", "join_right_top", "join_right_bottom"]:
		if view == "original":
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.keep_aspect = Camera3D.KEEP_WIDTH
			cam.size = 600.0 * GAME.SCALE
			cam.near = 0.05
			cam.far = 200.0
			cam.position = Vector3(0,1,1).normalized()*40.0
			cam.look_at(Vector3.ZERO,Vector3.UP)
			if environment: environment.fog_enabled = false
		else:
			cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			cam.keep_aspect = Camera3D.KEEP_HEIGHT
			cam.fov = 50.0
			cam.near = 0.05
			cam.far = 100.0
			var look_target: Vector3 = joins[view] if joins.has(view) else target
			var offset := Vector3(-2.0,1.0,2.5) if view == "oblique_left" else Vector3(2.0,1.0,2.5)
			if joins.has(view):
				offset = Vector3(-1.3,0.7,1.9) if view.begins_with("join_left") else Vector3(1.3,0.7,1.9)
				if view.ends_with("bottom"): offset.y = 1.0
			cam.global_position = look_target + offset
			cam.look_at(look_target,Vector3.UP)
			if environment: environment.fog_enabled = false
		for hidden in [false,true]:
			for chain in chains: chain.visible = not hidden
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var image := get_root().get_texture().get_image()
			if view == "original":
				var rows := int(round(image.get_width()*(400.0/sqrt(2.0))/600.0))
				image = image.get_region(Rect2i(0,(image.get_height()-rows)/2,image.get_width(),rows))
				image.resize(600,400,Image.INTERPOLATE_LANCZOS)
			var name: String = view + ("_hidden" if hidden else "")
			image.save_png(out_dir.path_join(name+".png"))
			print("CHAINSHOT ",name," ",out_dir)
	game.queue_free()
	await process_frame
	quit(0)
