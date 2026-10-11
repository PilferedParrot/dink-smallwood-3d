# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
# Aim at the entity's own live physics surface. Sprite/visual height is not a
# collision measurement (a mesh may be shorter or hollow at its center).
extends RefCounted

var _local_geometry: Dictionary = {} # Shape instance id -> weak shape, surface samples, local AABB


func reset() -> void:
	_local_geometry.clear()


func _invalidate_shape(id: int) -> void:
	_local_geometry.erase(id)


func _geometry(shape: Shape3D) -> Dictionary:
	var id := shape.get_instance_id()
	if _local_geometry.has(id):
		var cached: Dictionary = _local_geometry[id]
		if (cached["shape"] as WeakRef).get_ref() == shape: return cached
		_local_geometry.erase(id)
	var mesh := shape.get_debug_mesh()
	if mesh == null: return {}
	var faces: PackedVector3Array = mesh.get_faces()
	var points := PackedVector3Array()
	for i in range(0, faces.size() - 2, 3):
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		if (b - a).cross(c - a).length_squared() <= 0.0000000001: continue
		points.append((a + b + c) / 3.0)
		# A thin or hollow triangle can expose only a corner from a given eye.
		# These barycentric points stay on its actual planar surface.
		if shape is ConcavePolygonShape3D or shape is ConvexPolygonShape3D:
			points.append((a * 4.0 + b + c) / 6.0)
			points.append((a + b * 4.0 + c) / 6.0)
			points.append((a + b + c * 4.0) / 6.0)
	var result := {"shape": weakref(shape), "points": points, "bounds": mesh.get_aabb()}
	_local_geometry[id] = result
	var callback := _invalidate_shape.bind(id)
	if not shape.changed.is_connected(callback): shape.changed.connect(callback)
	return result


# All live collision shapes under an entity's own HitBody. A separate wall,
# another entity and a hidden/disabled ray body cannot become its target.
func _shapes(visual: Node3D, id: int) -> Array[CollisionShape3D]:
	var found: Array[CollisionShape3D] = []
	if visual == null or not is_instance_valid(visual) or not visual.is_inside_tree(): return found
	var pending: Array[Node] = [visual]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is CollisionObject3D and str(node.name) == "HitBody":
			var body := node as CollisionObject3D
			if int(body.get_meta("entity_id", -1)) == id and body.collision_layer != 0:
				var children: Array[Node] = [body]
				while not children.is_empty():
					var item: Node = children.pop_back()
					if item is CollisionShape3D:
						var collision := item as CollisionShape3D
						if not collision.disabled and collision.shape != null:
							found.append(collision)
					for child in item.get_children(): children.append(child)
			continue
		for child in node.get_children(): pending.append(child)
	return found


func _corners(box: AABB) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for x in [box.position.x, box.end.x]:
		for y in [box.position.y, box.end.y]:
			for z in [box.position.z, box.end.z]:
				out.append(Vector3(x, y, z))
	return out


func _own_bodies(visual: Node3D, id: int) -> Dictionary:
	var bodies := {}
	for collision in _shapes(visual, id):
		var parent: Node = collision.get_parent()
		while parent != null and not (parent is CollisionObject3D):
			parent = parent.get_parent()
		if parent is CollisionObject3D:
			bodies[parent.get_instance_id()] = true
	return bodies


# World-space collision bounds, never a visual's stale height metadata.
func bounds(visual: Node3D, id: int) -> AABB:
	var result := AABB()
	var first := true
	for collision in _shapes(visual, id):
		var geometry := _geometry(collision.shape)
		if geometry.is_empty(): continue
		for corner in _corners(geometry["bounds"]):
			var point: Vector3 = collision.global_transform * corner
			if first:
				result = AABB(point, Vector3.ZERO)
				first = false
			else:
				result = result.expand(point)
	return result


# Surface points nearest the camera first. Every point comes from an actual
# CollisionShape3D's debug collision triangles, transformed with its full
# nested scale/rotation/translation. Ray verification below is authoritative.
func targets(visual: Node3D, id: int, camera_origin: Vector3) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for collision in _shapes(visual, id):
		var geometry := _geometry(collision.shape)
		if geometry.is_empty(): continue
		for local: Vector3 in geometry["points"]:
			result.append(collision.global_transform * local)
	result.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return camera_origin.distance_squared_to(a) < camera_origin.distance_squared_to(b))
	return result


# A candidate is accepted only when the actual physics ray first hits this
# entity's own body. The 1cm extension crosses a triangle on the surface;
# a hollow center or another collider never becomes a false success.
func first_hit(visual: Node3D, id: int, camera_origin: Vector3,
		space: PhysicsDirectSpaceState3D, collision_mask: int = 3) -> Dictionary:
	if space == null: return {}
	var owned := _own_bodies(visual, id)
	if owned.is_empty(): return {}
	for target in targets(visual, id, camera_origin):
		var travel := target - camera_origin
		if travel.length_squared() < 0.000001: continue
		var query := PhysicsRayQueryParameters3D.create(camera_origin,
			target + travel.normalized() * 0.01, collision_mask)
		var hit := space.intersect_ray(query)
		if hit.is_empty(): continue
		var collider: Object = hit.get("collider")
		if collider != null and owned.has(collider.get_instance_id()) \
				and int(collider.get_meta("entity_id", -1)) == id:
			return {"target": target, "hit": hit}
	return {}


func reaches(visual: Node3D, id: int, camera_origin: Vector3,
		space: PhysicsDirectSpaceState3D, collision_mask: int = 3) -> bool:
	return not first_hit(visual, id, camera_origin, space, collision_mask).is_empty()
