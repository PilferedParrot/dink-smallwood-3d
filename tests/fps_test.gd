extends SceneTree

const GAME := preload("res://scripts/fps_game.gd")
const EYE_HEIGHT := 1.65
const SCALE: float = preload("res://scripts/fp_world.gd").SCALE

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
	# Let deferred visual construction and the campaign's opening scripts settle.
	await create_timer(2.0).timeout
	for _i in 2: await process_frame

	check(game.fp_world != null, "FPS host creates the first-person world renderer")
	check(game.camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "FPS camera uses perspective projection")
	check(game.camera.keep_aspect == Camera3D.KEEP_HEIGHT, "Widescreen preserves vertical field of view")
	var previous_size := root.size
	root.size = Vector2i(1280, 800)
	await process_frame
	var normal_projection: Projection = game.camera.get_camera_projection()
	root.size = Vector2i(1920, 1080)
	await process_frame
	var wide_projection: Projection = game.camera.get_camera_projection()
	check(is_equal_approx(normal_projection.y.y, wide_projection.y.y), "Widening the window leaves vertical projection unchanged")
	check(wide_projection.x.x < normal_projection.x.x, "Widening the window reveals more horizontally")
	root.size = previous_size
	await process_frame
	check(is_equal_approx(game.camera.position.y, EYE_HEIGHT), "Camera eye height is 1.65m at rest")
	check(is_equal_approx(game.camera.position.x, (float(game.entities[1].x)-320.0)*SCALE), "Camera follows source x coordinate")
	check(is_equal_approx(game.camera.position.z, (float(game.entities[1].y)-200.0)*SCALE), "Camera follows source y coordinate")
	check(not _stray_sprite3d(game.scene_root), "Active FPS scene draws sprites only as fp_world's depth-tested billboards")
	check(_billboard_count(game.scene_root) > 0, "The opening screens draw their original sprites")
	var stand_ins := _stand_ins(game.scene_root)
	check(stand_ins.is_empty(), "Nothing that is not a building keeps a stand-in model: %s" % [stand_ins])
	check(_mesh_count(game.scene_root) > 0, "Active FPS scene contains rendered 3D geometry")
	check(_body_count(game.scene_root) > 0, "Active FPS scene contains solid 3D bodies")
	# Aim rays respect the actor's vertical hit band, so looking over or under
	# an enemy cannot register a hit.
	var target_id := 900
	game.entities[target_id] = {"x": float(game.entities[1].x) + 20.0, "y": float(game.entities[1].y), "active": 1, "fps_min_height": 0.25, "fps_max_height": 1.8}
	var target_visual := Node3D.new()
	target_visual.set_meta("height", 1.8)
	game.visuals[target_id] = target_visual
	check(game._fps_targetable(target_id, Vector2.INF, 1.2), "Aim ray can hit an enemy at eye height")
	check(not game._fps_targetable(target_id, Vector2.INF, 2.0), "Aim ray misses above an enemy")
	game.entities.erase(target_id)
	game.visuals.erase(target_id)
	check(int(game.vm.globals.get("story", 0)) == 1, "Original opening quest advances story")
	check(not game.dialogue_log.is_empty(), "Original opening mother conversation is retained")

	# Menus release the captured mouse and gameplay recaptures it on the next update.
	game.ui.close_menu()
	game._fps_update_mouse_mode()
	check(not game.ui.modal and game.ui.page == "game", "Gameplay leaves the UI nonmodal")
	game.ui.show_pause()
	game._fps_update_mouse_mode()
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Pause menu releases the mouse")
	game.ui.close_menu()
	game._fps_update_mouse_mode()

	# The original house exit is just outside the source map's bottom edge.
	game.vm.cancel_all()
	game.load_map(1, false)
	game.entities[1].x = 325.0
	game.entities[1].y = 398.0
	game.warp_cooldown = 0.0
	game._transitions()
	check(game.current_screen == 439, "Home door at the original y=398 exit reaches screen 439")

	# Outdoor screens retain neighboring terrain in the same 3D scene.
	game.vm.cancel_all()
	game.load_map(400, false)
	await process_frame
	var neighbors := 0
	for child in game.scene_root.get_children():
		if str(child.name).begins_with("Neighbor_"): neighbors += 1
	check(neighbors > 0, "Outdoor FPS screen builds adjacent screen scenery")
	# Interiors are the original map's indoor screens (dink.dat): Dink's house and the inn's rooms
	# are; the walled streets and kit-417's courtyard, built of outdoor stone walls, are not.
	var inside: Array = []
	for n in game.world.screens:
		if game.fp_world.is_inside(int(n)): inside.append(int(n))
	check(inside.size() == game.world.screens.values().filter(func(sc): return bool(sc.get("indoor", false))).size(), "Every indoor-flagged screen, and only those, is an interior")
	check(game.fp_world.is_inside(1) and game.fp_world.is_inside(2), "Dink's house is an interior")
	check(not game.fp_world.is_inside(386) and not game.fp_world.is_inside(417) and not game.fp_world.is_inside(450), "kit-417's courtyard and its street are outdoors")
	check(_mesh_count(game.scene_root) > 0, "Outdoor FPS screen builds 3D terrain and models")

	target_visual.free()
	# Exercise the projectile against controlled 3D bodies.  The actor visual's
	# height is deliberately shorter than eye level for the over-target case.
	game.ui.close_menu()
	game.playing = true
	game.entities[1].x = 320.0; game.entities[1].y = 200.0
	game.fps_yaw = 0.0; game.fps_pitch = 0.0
	game._sync_fps_camera()
	await _clear_arena()
	_spawn_target(901, Vector3(0, 0, -4), 1.8, 10)
	game._fps_launch_projectile(false)
	await _physics_frames(20)
	check(int(game.entities[901].get("hitpoints", 10)) < 10, "Projectile damages an actor hit by its 3D body")

	await _clear_arena()
	_spawn_target(902, Vector3(0, 0, -4), 0.8, 10)
	game.camera.rotation.x = 0.55
	game._fps_launch_projectile(false)
	await _physics_frames(20)
	check(int(game.entities[902].get("hitpoints", 10)) == 10, "Projectile aimed above a short actor misses")
	game.camera.rotation.x = -0.30
	game._fps_launch_projectile(false)
	await _physics_frames(20)
	check(int(game.entities[902].get("hitpoints",10)) < 10,"Aimed projectile damages low creatures below default 1.2m band")

	await _clear_arena()
	_spawn_wall(Vector3(0, 0, -2))
	_spawn_target(903, Vector3(0, 0, -4), 1.8, 10)
	game.camera.rotation.x = 0.0
	game._fps_launch_projectile(false)
	await _physics_frames(20)
	check(int(game.entities[903].get("hitpoints", 10)) == 10, "Static wall body occludes projectile damage")

	await _clear_arena()
	var paused_projectile = game.PROJECTILE.new()
	game.add_child(paused_projectile)
	paused_projectile.configure(game, 1, game.camera.global_position, Vector3.FORWARD, 1)
	game.ui.show_pause()
	var paused_position: Vector3 = paused_projectile.position
	await _physics_frames(4)
	check(paused_projectile.position.distance_to(paused_position) < 0.0001, "Paused game freezes projectile movement")
	game.ui.close_menu()
	game.load_map(400, false)
	await process_frame
	check(not is_instance_valid(paused_projectile), "Map change expires stale projectiles")

	# Save/load must restore both campaign position and FPS camera orientation.
	game.playing = true
	game.entities[1].x = 271.0
	game.entities[1].y = 219.0
	game.fps_yaw = 0.47
	game.fps_pitch = -0.31
	var save_path := "user://fps-integration-save.json"
	check(game._save_game(save_path), "FPS campaign save succeeds")
	game.entities[1].x = 400.0
	game.entities[1].y = 300.0
	game.fps_yaw = 0.0
	game.fps_pitch = 0.0
	check(game._load_game(save_path), "FPS campaign load succeeds")
	check(is_equal_approx(float(game.entities[1].x), 271.0) and is_equal_approx(float(game.entities[1].y), 219.0), "Load restores source position")
	check(is_equal_approx(game.fps_yaw, 0.47) and is_equal_approx(game.fps_pitch, -0.31), "Load restores FPS camera orientation")
	DirAccess.remove_absolute(save_path)

	game.vm.cancel_all()
	game.queue_free()
	await process_frame
	if failures.is_empty(): print("FPS PASS: camera, UI capture, campaign transition, neighbors, renderer, save/load")
	else: print("FPS FAILURES: ", failures)
	quit(0 if failures.is_empty() else 1)

# Sprites are drawn only as fp_world's billboards (docs/DIRECTION.md supersedes the old "no
# Sprite3D" rule): depth-tested, each the "Model" of an entity visual. A Sprite3D anywhere else, or
# without the depth test, is the 2D renderer's leaking into the 3D scene.
func _stray_sprite3d(node: Node) -> bool:
	for child in node.get_children():
		if child is Sprite3D:
			var parent := child.get_parent()
			# A card the depth rule shifts (fp_world.gd depth_shift) casts its shadow from a shadow-only twin
			# of itself, a child of its "Model".
			if child.name == "ShadowTwin" and parent is Sprite3D and parent.name == "Model" and (child as Sprite3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY: continue
			if (child as Sprite3D).no_depth_test or child.name != "Model" or not parent.get_meta("billboard", false): return true
		if _stray_sprite3d(child): return true
	return false

func _billboard_count(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		if child is Sprite3D: count += 1
		count += _billboard_count(child)
	return count

# Visuals of things that are not buildings whose model is not their sprite (a Blender stand-in). A prop built from its own
# sprite's pixels (fp_world add_prop: a solid, "prop_path") is its sprite, not a stand-in.
func _stand_ins(node: Node) -> Array:
	var out: Array = []
	for child in node.get_children():
		var key := str(child.get_meta("model_key", ""))
		var model: Node = child.get_node_or_null("Model")
		if model != null and game.fp_world.sprite_drawn(key) and not model is Sprite3D and not child.has_meta("prop_path"): out.append("%s:%s" % [child.name, key])
		out.append_array(_stand_ins(child))
	return out

func _mesh_count(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		if child is MeshInstance3D or child is MultiMeshInstance3D: count += 1
		count += _mesh_count(child)
	return count

func _body_count(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		if child is CollisionObject3D: count += 1
		count += _body_count(child)
	return count

func _clear_arena() -> void:
	for id in [901, 902, 903]:
		game.entities.erase(id)
		var old_visual: Node = game.visuals.get(id)
		if is_instance_valid(old_visual): old_visual.queue_free()
		game.visuals.erase(id)
	for child in game.scene_root.get_children():
		if str(child.name).begins_with("TestArena"):
			child.queue_free()
	await process_frame

func _spawn_target(id: int, position: Vector3, height: float, hitpoints: int) -> void:
	var visual := Node3D.new()
	visual.name = "TestArenaTarget_%d" % id
	visual.position = position
	visual.set_meta("height", height)
	game.scene_root.add_child(visual)
	var body := StaticBody3D.new()
	body.name = "HitBody"
	body.set_meta("entity_id", id)
	body.collision_layer = 2
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, height, 0.8)
	shape.shape = box
	shape.position.y = height * 0.5
	body.add_child(shape)
	visual.add_child(body)
	# The entity stands where its body is (update_visual places the visual from x, y).
	game.entities[id] = {"x":320.0+position.x/SCALE,"y":200.0+position.z/SCALE,"active":1,"type":1,"hitpoints":hitpoints,"nohit":0,"script":"","fps_min_height":0.0,"fps_max_height":height}
	game.visuals[id] = visual

func _spawn_wall(position: Vector3) -> void:
	var wall := StaticBody3D.new()
	wall.name = "TestArenaWall"
	wall.collision_layer = 1
	wall.collision_mask = 0
	wall.position = position
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 3.0, 0.25)
	shape.shape = box
	shape.position.y = 1.5
	wall.add_child(shape)
	game.scene_root.add_child(wall)

func _physics_frames(count: int) -> void:
	for _i in count: await physics_frame
