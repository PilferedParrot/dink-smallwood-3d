extends SceneTree
# Physics rays through the fitted fence parts, including a real blocked barrel sightline.
const GAME := preload("res://scripts/fps_game.gd")
const TEST_LAYER := 1 << 20

var game
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if ok: return
	failures.append(message)
	push_error(message)

func _editor_id(index: int) -> int:
	for id in game.entities:
		if int(game.entities[id].get("editor_num", 0)) == index: return int(id)
	return 0

func _hit(from: Vector3, to: Vector3) -> Dictionary:
	return game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, TEST_LAYER))

func _mesh_boxes(instance: MeshInstance3D) -> Array:
	var out: Array = []
	var vertices: PackedVector3Array = instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for start in range(0, vertices.size(), 36):
		if start + 36 > vertices.size(): break
		var low := Vector3.INF
		var high := -Vector3.INF
		for i in 36:
			var point: Vector3 = instance.global_transform * vertices[start + i]
			low = low.min(point)
			high = high.max(point)
		var ends: Array = []
		for offset in [24, 30]:
			var centre := Vector3.ZERO
			for i in [0, 1, 2, 5]: centre += instance.global_transform * vertices[start + offset + i] * 0.25
			ends.append(centre)
		out.append({"low": low, "high": high, "a": ends[0], "b": ends[1]})
	return out

func _part(node: Node3D, name: String) -> MeshInstance3D:
	return node.get_node_or_null("Fence/" + name) as MeshInstance3D

func _exercise(id: int, label: String, rotate: bool = false) -> void:
	var node: Node3D = game.visuals.get(id)
	var body := node.get_node_or_null("HitBody") as StaticBody3D
	var posts := _part(node, "Posts")
	var rails := _part(node, "Rails")
	check(body != null and posts != null and rails != null, label + ": fitted parts have a ray body")
	if body == null or posts == null or rails == null: return
	var shape := body.get_child(0) as CollisionShape3D
	check(shape.shape is ConcavePolygonShape3D, label + ": ray body uses a triangle mesh")
	if not shape.shape is ConcavePolygonShape3D: return
	check((shape.shape as ConcavePolygonShape3D).backface_collision, label + ": triangles hit from either side")
	var drawn_faces := 0
	for child in node.get_node("Fence").get_children():
		if child is MeshInstance3D: drawn_faces += (child as MeshInstance3D).mesh.get_faces().size()
	check((shape.shape as ConcavePolygonShape3D).get_faces().size() == drawn_faces, label + ": ray shape has every drawn triangle")
	if rotate: node.rotate_y(0.63)
	var rail_boxes := _mesh_boxes(rails)
	var post_boxes := _mesh_boxes(posts)
	check(not rail_boxes.is_empty() and not post_boxes.is_empty(), label + ": fitted boxes present")
	if rail_boxes.is_empty() or post_boxes.is_empty(): return
	var longest: Dictionary = rail_boxes[0]
	for box in rail_boxes:
		if (box.a as Vector3).distance_to(box.b) > (longest.a as Vector3).distance_to(longest.b): longest = box
	var a: Vector3 = longest.a
	var b: Vector3 = longest.b
	var direction := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
	check(direction.length() > 0.9 and a.distance_to(b) > 0.5, label + ": bay long enough for an open ray")
	if direction.length() < 0.9 or a.distance_to(b) <= 0.5: return
	var across := Vector3(-direction.z, 0, direction.x)
	var centre := (a + b) * 0.5
	var lower_rail_y := INF
	for box in rail_boxes: lower_rail_y = minf(lower_rail_y, (box.low as Vector3).y)
	var gap := Vector3(centre.x, maxf(0.025, lower_rail_y * 0.5), centre.z)
	var rail := Vector3(centre.x, (longest.low.y + longest.high.y) * 0.5, centre.z)
	var post_box: Dictionary = post_boxes[0]
	var post: Vector3 = (post_box.low + post_box.high) * 0.5
	var old_layer := body.collision_layer
	body.collision_layer = TEST_LAYER
	await physics_frame
	for sign in [-1.0, 1.0]:
		check(_hit(gap + across * sign, gap - across * sign).is_empty(), label + ": ray crosses open bay")
		var rail_hit := _hit(rail + across * sign, rail - across * sign)
		check(rail_hit.get("collider") == body, label + ": ray stops on rail from both sides")
		var post_hit := _hit(post + across * sign, post - across * sign)
		check(post_hit.get("collider") == body, label + ": ray stops on post from both sides")
	body.collision_layer = old_layer
	if rotate: node.rotate_y(-0.63)
	await physics_frame

func _screen(number: int, vision: int = 0) -> void:
	game.vm.cancel_all()
	game.vm.globals["vision"] = vision
	game.load_map(number, false)
	await physics_frame
	await physics_frame
	game.vm.cancel_all()

func _first_fitted(filename: String) -> int:
	for id in game.entities:
		if int(id) == 1: continue
		var e: Dictionary = game.entities[id]
		if not game.fp_world.frame_path(e).ends_with(filename) or int(e.get("hard", 0)) != 0: continue
		var node: Node3D = game.visuals.get(id)
		if is_instance_valid(node) and _part(node, "Posts") != null and _part(node, "Rails") != null and node.get_node_or_null("HitBody") != null:
			return int(id)
	return 0

func _run() -> void:
	game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	game.vm.cancel_all()
	game.set_physics_process(false)
	await _screen(439)
	# Scenario setup skips startup scripts and puts Dink at the observed blocked sightline.
	var barrel_id := _editor_id(22)
	var fence_id := _editor_id(16)
	check(barrel_id != 0 and fence_id != 0, "439 has the observed barrel and fence")
	if barrel_id != 0 and fence_id != 0:
		game.entities[1].x = 124.0
		game.entities[1].y = 398.0
		game.fps_yaw = 0.0
		game.fps_pitch = 0.0
		game.fps_jump_height = 0.0
		game._sync_fps_camera()
		await physics_frame
		check(game._fps_ray_reaches(barrel_id), "439 barrel at editor 22 is reachable through fence editor 16's bay")
		await _exercise(fence_id, "439 fence-01")
	var horizontal := _first_fitted("fence-01.png")
	if horizontal != 0 and horizontal != fence_id: await _exercise(horizontal, "439 second horizontal")
	await _screen(407)
	var vertical := _first_fitted("fence-04.png")
	check(vertical != 0, "407 has a fitted depth-axis fence")
	if vertical != 0: await _exercise(vertical, "407 fence-04 rotated", true)
	await _screen(731, 1)
	var island := _first_fitted("isle-08.png")
	check(island != 0, "731 has a fitted island depth-axis fence")
	if island != 0: await _exercise(island, "731 isle-08")
	game.queue_free()
	if failures.is_empty(): print("FPS FENCE RAY PASS")
	else: print("FPS FENCE RAY FAILURES: ", failures)
	quit(0 if failures.is_empty() else 1)
