extends SceneTree
# Renderer regression: force both recycled material-slot orders, including an
# unordered negative control. Geometry setup deliberately skips the campaign.
const BUILDINGS = preload("res://scripts/sprite_buildings.gd")
var failures: Array[String] = []
var buildings
func _initialize() -> void:
	_run.call_deferred()
func _hash(data: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(data)
	return context.finish().hex_encode()
func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message); push_error(message)
func _grab() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	return img
func _quad(reverse: bool, unordered: bool, red: Texture2D, blue: Texture2D) -> String:
	var meshes: Array = [QuadMesh.new(), QuadMesh.new()]
	for mesh in meshes: mesh.size = Vector2(2, 2)
	# Reserve real slots and free them in opposite orders. No timing or RNG is
	# needed to reproduce the allocator order that changed the cabin's pixels.
	var slots: Array = []
	for i in 4:
		var material := StandardMaterial3D.new()
		material.get_rid()
		slots.append(material)
	slots.sort_custom(func(a, b): return (a.get_rid().get_id() & 0xffffffff) < (b.get_rid().get_id() & 0xffffffff))
	if reverse: slots[3] = null; slots[0] = null
	else: slots[0] = null; slots[3] = null
	var node: Node3D = buildings.node_from([[meshes[0], red], [meshes[1], blue]])
	root.add_child(node)
	var ids: Array = []
	for mi in node.get_children():
		var material: Material = mi.get_active_material(0)
		ids.append(material.get_rid().get_id() & 0xffffffff)
		if unordered: material.render_priority = 0
	var img := await _grab()
	if not unordered:
		_check(img.get_pixel(img.get_width()/2,img.get_height()/2) == Color.BLUE,"Authored later surface (blue) must own the known centre depth tie")
	var digest := _hash(img.get_data())
	print("ORDER ", "unordered" if unordered else "ordered", " reverse=",reverse," slots=",ids," centre=",img.get_pixel(img.get_width()/2,img.get_height()/2))
	root.remove_child(node)
	node.free()
	slots.clear()
	await process_frame
	return digest
func _run() -> void:
	var seqs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sequences.json")).sequences
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json")).screens
	var fits: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://prototype/facades.json"))
	buildings = BUILDINGS.new(seqs, world, fits, 0.025)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3
	camera.position = Vector3(0, 0, 3)
	root.add_child(camera)
	camera.make_current()
	var red_img := Image.create(1,1,false,Image.FORMAT_RGBA8); red_img.fill(Color.RED)
	var blue_img := Image.create(1,1,false,Image.FORMAT_RGBA8); blue_img.fill(Color.BLUE)
	var red := ImageTexture.create_from_image(red_img)
	var blue := ImageTexture.create_from_image(blue_img)
	# Initialize default renderer resources before reserving the controlled
	# slots; first-use allocation must not consume one of those two slots.
	var warm: Node3D = buildings.node_from([[QuadMesh.new(),red]])
	root.add_child(warm); await _grab()
	root.remove_child(warm); warm.free(); await process_frame
	var ordered_a := await _quad(false,false,red,blue)
	var ordered_b := await _quad(true,false,red,blue)
	_check(ordered_a == ordered_b,"Authored surface order must survive opposite material slot orders")
	var unordered_a := await _quad(false,true,red,blue)
	var unordered_b := await _quad(true,true,red,blue)
	_check(unordered_a != unordered_b,"CONTROL INVALID: allocator setup did not expose opposite equal-depth winners; this is a harness failure")
	# Measure actual emitted meshes, UVs and texture pixels, independently of
	# the emitter's source-record identity key. Duplicate source panels must not
	# produce a second identical solid.
	for kit in fits.get("_kit_buildings", []):
		var model: Node3D = buildings.kit(kit)
		model.visible = false
		root.add_child(model)
		await process_frame
		var seen := {}
		for mi in model.get_children():
			var material: StandardMaterial3D = mi.get_active_material(0)
			var identity := _hash(var_to_bytes(mi.mesh.surface_get_arrays(0))) + _hash(material.albedo_texture.get_image().get_data())
			_check(not seen.has(identity),"Duplicate emitted mesh/UV/texture in " + str(kit.name))
			seen[identity] = true
		print("KIT_UNIQUE ",kit.name," ",seen.size()," of ",model.get_child_count())
		root.remove_child(model); model.free()
	# A supplied cached material remains untouched and ordered copies keep
	# sharing for the same surface role, preserving the original batching.
	var supplied := StandardMaterial3D.new(); supplied.render_priority = 47
	supplied.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	supplied.alpha_scissor_threshold = 0.37
	var mesh := QuadMesh.new()
	var first: Node3D = buildings.node_from([[mesh,supplied]])
	var second: Node3D = buildings.node_from([[mesh,supplied]])
	_check(supplied.render_priority == 47,"Surface ordering must not mutate a supplied material")
	_check(first.get_child(0).get_active_material(0) == second.get_child(0).get_active_material(0),"Ordered copies must retain sharing between instances")
	var ordered: StandardMaterial3D = first.get_child(0).get_active_material(0)
	_check(ordered.transparency == supplied.transparency and is_equal_approx(ordered.alpha_scissor_threshold,0.37),"Surface ordering must retain alpha-scissor pass and coverage")
	first.free(); second.free()
	for i in 16:
		var transient := StandardMaterial3D.new()
		var preview: Node3D = buildings.node_from([[mesh,transient]])
		preview.free()
	# A construction without a supplied material still prunes dead inputs.
	var cleanup: Node3D = buildings.node_from([[mesh,red]])
	cleanup.free()
	if "ordered_materials" in buildings:
		_check(buildings.ordered_materials.size() == 1,"Transient prototype inputs must not accumulate ordered material copies")
	else:
		_check(false,"Builder is missing the bounded ordered-material cache")
	var overflow: Array = []
	for i in Material.RENDER_PRIORITY_MAX + 2: overflow.append([mesh,red])
	var rejected: Node3D = buildings.node_from(overflow)
	_check(rejected == null,"Unrepresentable surface order must be rejected in release builds too")
	if rejected != null: rejected.free()
	print("FITTED SURFACE ORDER PASS" if failures.is_empty() else "FITTED SURFACE ORDER FAIL")
	quit(0 if failures.is_empty() else 1)
