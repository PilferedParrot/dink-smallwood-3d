extends SceneTree

const TARGETS = preload("res://scripts/entity_hit_targets.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, name: String) -> void:
	if not ok: failures.append(name)

func body(parent: Node3D, id: int, shape: Shape3D, at: Vector3) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Entity_%d" % id
	holder.position = at
	holder.set_meta("height", 100.0) # deliberately stale visual metadata
	parent.add_child(holder)
	var physics := StaticBody3D.new()
	physics.name = "HitBody"
	physics.collision_layer = 2
	physics.set_meta("entity_id", id)
	holder.add_child(physics)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = shape
	physics.add_child(collision)
	return holder

func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> PackedVector3Array:
	return PackedVector3Array([a, b, c, a, c, d])

func ring() -> ConcavePolygonShape3D:
	var faces := PackedVector3Array()
	faces.append_array(quad(Vector3(-1,-1,0),Vector3(1,-1,0),Vector3(0.2,-0.2,0),Vector3(-0.2,-0.2,0)))
	faces.append_array(quad(Vector3(-1,-1,0),Vector3(-0.2,-0.2,0),Vector3(-0.2,0.2,0),Vector3(-1,1,0)))
	faces.append_array(quad(Vector3(1,-1,0),Vector3(1,1,0),Vector3(0.2,0.2,0),Vector3(0.2,-0.2,0)))
	faces.append_array(quad(Vector3(-1,1,0),Vector3(-0.2,0.2,0),Vector3(0.2,0.2,0),Vector3(1,1,0)))
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	return shape

func _run() -> void:
	var helper := TARGETS.new()
	var holder := Node3D.new()
	root.add_child(holder)
	var box := BoxShape3D.new()
	box.size = Vector3(2, 2, 2)
	var box_node := body(holder, 17, box, Vector3(0, 0, 0))
	var hollow := body(holder, 22, ring(), Vector3(10, 0, 0))
	var nested := hollow.get_node("HitBody") as Node3D
	nested.rotation.y = 0.25
	nested.scale = Vector3(1.5, 1.0, 0.8)
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.5
	capsule.height = 2.0
	var cap_node := body(holder, 33, capsule, Vector3(20, 0, 0))
	var convex := ConvexPolygonShape3D.new()
	convex.points = PackedVector3Array([Vector3(-1,-1,-1),Vector3(1,-1,-1),Vector3(0,1,-1),Vector3(0,0,1)])
	var convex_node := body(holder, 44, convex, Vector3(30, 0, 0))
	var nested_box := BoxShape3D.new()
	nested_box.size = Vector3(1, 1, 1)
	var nested_node := body(holder, 55, nested_box, Vector3(40, 0, 0))
	var nested_body := nested_node.get_node("HitBody") as StaticBody3D
	nested_node.remove_child(nested_body)
	var shape_parent := Node3D.new()
	shape_parent.position = Vector3(0, 1, 0)
	shape_parent.rotation.y = 0.35
	shape_parent.scale = Vector3(1.25, 1.0, 0.75)
	nested_node.add_child(shape_parent)
	shape_parent.add_child(nested_body)
	await physics_frame
	var space := root.world_3d.direct_space_state
	check(helper.reaches(box_node,17,Vector3(0,0,5),space), "box actual surface ray")
	check(not helper.reaches(box_node,99,Vector3(0,0,5),space), "foreign entity id never accepted")
	check(helper.bounds(box_node,17).size.y > 1.9 and helper.bounds(box_node,17).size.y < 2.1,
		"bounds follow collision not stale visual height")
	check(helper.reaches(hollow,22,Vector3(10,0,5),space), "hollow center finds actual ring surface")
	check(helper.bounds(hollow,22).size.x > 2.0, "nested scale contributes to bounds")
	check(helper.reaches(cap_node,33,Vector3(20,0,5),space), "capsule curved debug surface")
	check(helper.reaches(convex_node,44,Vector3(30,0,5),space), "convex polygon surface")
	check(helper.reaches(nested_node,55,Vector3(40,1,5),space), "deeply nested transformed collision shape")
	check(helper.bounds(nested_node,55).position.y > 0.4, "nested offset enters collision bounds")
	box.size = Vector3(2, 4, 2)
	check(helper.bounds(box_node,17).size.y > 3.9, "changed shape invalidates cached geometry")
	var blocker := StaticBody3D.new()
	blocker.name = "OtherBody"
	blocker.collision_layer = 1
	blocker.set_meta("entity_id", 17) # same numeric id cannot spoof the owned body
	blocker.position = Vector3(0,0,2)
	holder.add_child(blocker)
	var block_shape := CollisionShape3D.new()
	var block_box := BoxShape3D.new()
	block_box.size = Vector3(4,4,1)
	block_shape.shape = block_box
	blocker.add_child(block_shape)
	await physics_frame
	check(not helper.reaches(box_node,17,Vector3(0,0,5),space), "foreign body with same id occludes own shape")
	box_node.get_node("HitBody/CollisionShape3D").disabled = true
	check(helper.targets(box_node,17,Vector3(0,0,5)).is_empty(), "disabled shape omitted")
	holder.queue_free()
	await process_frame
	if failures.is_empty():
		print("ENTITY HIT TARGETS PASS box capsule convex hollow occlusion cache")
		quit(0)
	else:
		for failure in failures: print("ENTITY HIT TARGETS FAIL ", failure)
		quit(1)
