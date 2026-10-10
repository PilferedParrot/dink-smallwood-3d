extends SceneTree

const GAME := preload("res://scripts/fps_game.gd")

var game
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	await game._new_game()
	game.vm.cancel_all()
	game.playing = true
	game.ui.close_menu()
	game.set_physics_process(false)
	game.entities[1]["x"] = 320.0
	game.entities[1]["y"] = 200.0
	game.fps_yaw = 0.0
	game.fps_pitch = 0.0
	game._sync_fps_camera()
	var source: Vector3 = game.camera.global_position
	var target: Vector3 = source+Vector3(0.0,0.0,-3.0)
	var target_points: Array[Vector3] = [target]
	var opaque: Image = Image.create(5,5,false,Image.FORMAT_RGBA8)
	opaque.fill(Color(1.0,0.2,0.1,1.0))
	var hole: Image = opaque.duplicate() as Image
	hole.set_pixel(2,2,Color(1.0,0.2,0.1,0.0))
	var effect: Node3D = Node3D.new()
	effect.name = "TestEffect"
	effect.set_meta("model_key", "effect")
	game.scene_root.add_child(effect)
	var card: Sprite3D = Sprite3D.new()
	card.name = "Model"
	card.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	card.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	card.alpha_scissor_threshold = 0.5
	card.pixel_size = 0.2
	card.texture = ImageTexture.create_from_image(hole)
	effect.add_child(card)
	effect.global_position = source+Vector3(0.0,0.0,-1.5)
	var twin: Sprite3D = Sprite3D.new()
	twin.name = "ShadowTwin"
	twin.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	twin.pixel_size = 0.2
	twin.texture = ImageTexture.create_from_image(opaque)
	effect.add_child(twin)
	var original_visuals: Dictionary = game.visuals
	game.visuals = {900001:effect}
	check(not game._fps_effect_in_front(target_points,source,0), "Transparent center and shadow twin do not occlude subject ray")
	card.texture = ImageTexture.create_from_image(opaque)
	check(game._fps_effect_in_front(target_points,source,0), "Opaque texel between camera and subject blocks")
	effect.global_position = source+Vector3(0.0,0.0,-4.0)
	check(not game._fps_effect_in_front(target_points,source,0), "Opaque card behind subject does not block")
	effect.global_position = source+Vector3(0.0,0.0,-0.04)
	card.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	card.rotation.y = PI*0.25
	var corners: Array[Vector3] = game._fps_visible_points(effect, source)
	var near_front: bool = false
	var near_clipped: bool = false
	for point in corners:
		var depth: float = -game.camera.global_transform.basis.z.dot(point-source)
		if depth > game.camera.near: near_front = true
		else: near_clipped = true
	check(near_front and near_clipped, "Rotated card straddles the near plane")
	check(game._fps_effect_in_front(target_points,source,0), "Opaque ray intersection beyond near plane blocks despite clipped corners")
	effect.global_position = source+Vector3(0.0,0.0,-0.02)
	check(not game._fps_effect_in_front(target_points,source,0), "Plane intersection inside near clip is not visible obstruction")
	var region_image: Image = Image.create(7,5,false,Image.FORMAT_RGBA8)
	region_image.fill(Color.TRANSPARENT)
	region_image.set_pixel(3,2,Color(1.0,0.2,0.1,1.0))
	card.texture = ImageTexture.create_from_image(region_image)
	card.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	card.rotation.y = 0.0
	card.region_enabled = true
	card.region_rect = Rect2(1.0,0.0,5.0,5.0)
	card.flip_h = true
	effect.global_position = source+Vector3(0.0,0.0,-1.5)
	var left_target: Vector3 = source+Vector3(-0.4,0.0,-3.0)
	var left_points: Array[Vector3] = [left_target]
	check(game._fps_effect_in_front(left_points,source,0), "Flipped region maps ray to its opaque source texel")
	card.flip_h = false
	check(not game._fps_effect_in_front(left_points,source,0), "Unflipped region maps same ray to transparent source texel")
	game.visuals = original_visuals
	effect.queue_free()
	game.vm.globals["vision"] = 1
	game.vm.globals["story"] = 3
	game.load_map(1,false)
	await process_frame
	await process_frame
	var mother: int = 0
	var death_art: int = 0
	for id in game.entities:
		if int(game.entities[id].get("editor_num",-1)) == 26: mother = int(id)
		if int(game.entities[id].get("editor_num",-1)) == 34: death_art = int(id)
	check(mother != 0 and death_art != 0, "Original story-3 room contains both source editor identities")
	if mother != 0: await game.vm.run("s1-h1-m","main",mother)
	if death_art != 0:
		var visual: Node3D = game.visuals[death_art]
		check(visual.has_meta("floor_art_rect") and visual.has_meta("floor_art_path"), "Painted art retains source path and rectangle")
		var path: String = str(visual.get_meta("floor_art_path", ""))
		var image: Image = game.fp_world.sprite_image(path)
		var frame: Dictionary = game._frame(355,1)
		var source_x: float = float(game.entities[death_art].get("x",0))
		var source_y: float = float(game.entities[death_art].get("y",0))
		var expected_min: Vector2 = Vector2((source_x-float(frame.get("dx",0))-320.0)*GAME.SCALE,
			(source_y-float(frame.get("dy",0))-200.0)*GAME.SCALE)
		var expected_max: Vector2 = expected_min+Vector2(image.get_size())*GAME.SCALE
		var bounds: Array[Vector3] = game._fps_visible_points(visual, game.camera.global_position)
		var low: Vector3 = bounds[0]
		var high: Vector3 = bounds[0]
		for point in bounds:
			low = low.min(point)
			high = high.max(point)
		check(is_equal_approx(low.x,expected_min.x) and is_equal_approx(low.z,expected_min.y), "Floor-art low corner derives from source hotspot")
		check(is_equal_approx(high.x,expected_max.x) and is_equal_approx(high.z,expected_max.y), "Floor-art high corner derives from source image size")
		var samples: Array[Vector3] = game._fps_dialogue_subject_samples(bounds, game.camera.global_position, death_art)
		check(samples.size() == 1914, "Every visible source death-art pixel is sampled")
		for point in samples:
			if not is_zero_approx(point.y):
				check(false, "Floor-art samples remain on the room floor")
				break
	if failures.is_empty(): print("EFFECT ALPHA VISIBILITY PASS")
	else: print("EFFECT ALPHA VISIBILITY FAILURES: ", failures)
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
