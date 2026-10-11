extends SceneTree

const GAME := preload("res://scripts/fps_game.gd")

var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	check(game.fp_world != null, "FPS renderer initializes")
	var unsupported := Node3D.new()
	var loose_card := Sprite3D.new()
	loose_card.name = "Model"
	loose_card.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	loose_card.position = Vector3(1000,1000,1000)
	unsupported.add_child(loose_card)
	game.scene_root.add_child(unsupported)
	check(_stray_sprite3d(game.scene_root), "An unowned fixed card is rejected")
	unsupported.free()

	var numbers: Array[int] = []
	for key in game.world.screens.keys(): numbers.append(int(key))
	numbers.sort()
	for number in numbers:
		game.vm.cancel_all()
		game.load_map(number, false)
		check(not game.scene_root.get_children().is_empty(), "Screen %d builds a nonempty floor scene" % number)
		check(not _stray_sprite3d(game.scene_root), "Screen %d uses owned depth-tested sprite surfaces" % number)
		for card in _mounted_cards(game.scene_root):
			var position: Vector3 = card.position
			card.global_position += card.global_basis.z.normalized()*0.1
			check(_stray_sprite3d(game.scene_root), "Screen %d rejects a card 10cm off its built wall" % number)
			card.position = position
			var rotation: Vector3 = card.rotation
			card.rotation.y += 0.2
			check(_stray_sprite3d(game.scene_root), "Screen %d rejects an unaligned wall-card normal" % number)
			card.rotation = rotation
			check(not _stray_sprite3d(game.scene_root), "Screen %d restores wall-mounted geometry" % number)
		check(_mesh_count(game.scene_root) > 0, "Screen %d contains 3D geometry" % number)
		check(game.vm._live_tasks.is_empty(), "Screen %d leaves no script tasks" % number)
		await process_frame

	game.vm.cancel_all()
	check(game.vm._live_tasks.is_empty(), "Renderer traversal ends with scripts canceled")
	game.queue_free()
	await process_frame
	if failures.is_empty(): print("FPS WORLD PASS: traversed %d screens" % numbers.size())
	else: print("FPS WORLD FAILURES: ", failures)
	quit(0 if failures.is_empty() else 1)

# Source billboards and actual wall-mounted faces are depth-tested entity models.
# Fixed faces pass by geometric support, never by a poster class label.
func _stray_sprite3d(node: Node) -> bool:
	for child in node.get_children():
		if child is Sprite3D:
			var parent := child.get_parent()
			# A card the depth rule shifts (fp_world.gd depth_shift) casts its shadow from a shadow-only twin
			# of itself, a child of its "Model".
			if child.name == "ShadowTwin" and parent is Sprite3D and parent.name == "Model" and (child as Sprite3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY: continue
			if (child as Sprite3D).no_depth_test or child.name != "Model": return true
			if not parent.get_meta("billboard", false) and not _wall_supported(child as Sprite3D): return true
		if _stray_sprite3d(child): return true
	return false

func _mounted_cards(node: Node) -> Array[Sprite3D]:
	var cards: Array[Sprite3D] = []
	for child in node.get_children():
		if child is Sprite3D and child.name == "Model" and not node.get_meta("billboard",false):
			cards.append(child)
		cards.append_array(_mounted_cards(child))
	return cards

func _wall_meshes(node: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	for child in node.get_children():
		if child is MeshInstance3D and child.mesh != null: meshes.append(child)
		meshes.append_array(_wall_meshes(child))
	return meshes

func _built_wall_meshes(node: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	var body := node.get_node_or_null("HitBody")
	var model := node.get_node_or_null("Model")
	if body != null and body.has_meta("wall_prism") and model != null:
		# Metadata locates constructed wall candidates; their actual mesh vertices
		# below establish the support plane, normal and face bounds.
		if model is MeshInstance3D and model.mesh != null: meshes.append(model)
		meshes.append_array(_wall_meshes(model))
	for child in node.get_children(): meshes.append_array(_built_wall_meshes(child))
	return meshes

func _wall_supported(card: Sprite3D) -> bool:
	const EPSILON_M := 0.002 # source paired shift is 0.00025m; 10cm must fail
	if card.billboard != BaseMaterial3D.BILLBOARD_DISABLED or card.texture == null: return false
	var normal := card.global_basis.z.normalized()
	var right := card.global_basis.x.normalized()
	var up := card.global_basis.y.normalized()
	var quad := card.get_aabb()
	var corners: Array[Vector3] = []
	for x in [quad.position.x,quad.end.x]:
		for y in [quad.position.y,quad.end.y]:
			corners.append(card.global_transform*Vector3(x,y,quad.position.z))
	for mesh in _built_wall_meshes(root):
		var faces := mesh.mesh.get_faces()
		var plane_points: Array[Vector3] = []
		for i in range(0,faces.size()-2,3):
			var a: Vector3 = mesh.global_transform*faces[i]
			var b: Vector3 = mesh.global_transform*faces[i+1]
			var c: Vector3 = mesh.global_transform*faces[i+2]
			var face_normal := (b-a).cross(c-a)
			if face_normal.length_squared() <= 0.000000001: continue
			if absf(face_normal.normalized().dot(normal)) < 0.999999: continue
			if not corners.all(func(point):return absf((point-a).dot(normal)) <= EPSILON_M): continue
			plane_points.append_array([a,b,c])
		if plane_points.is_empty(): continue
		var bounds := Rect2(Vector2(plane_points[0].dot(right),plane_points[0].dot(up)),Vector2.ZERO)
		for point in plane_points: bounds=bounds.expand(Vector2(point.dot(right),point.dot(up)))
		var inside := true
		for point in corners:
			var projected := Vector2(point.dot(right),point.dot(up))
			if projected.x < bounds.position.x-EPSILON_M or projected.x > bounds.end.x+EPSILON_M \
				or projected.y < bounds.position.y-EPSILON_M or projected.y > bounds.end.y+EPSILON_M:
				inside=false;break
		if inside: return true
	return false

func _mesh_count(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		if child is MeshInstance3D or child is MultiMeshInstance3D: count += 1
		count += _mesh_count(child)
	return count
