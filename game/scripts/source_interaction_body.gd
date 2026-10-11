# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
# A scripted decorative sprite keeps the original image-hardbox as an FPS ray
# target. This body never participates in the source movement/hardness test.
extends RefCounted

const SCALE := 0.025
const DECORATIVE := ["grass", "flowers", "mushroom", "effect", "feed_grains",
	"flame", "burn_scar", "hole", "arrow"]

var world: Object


func _init(fp_world: Object) -> void:
	world = fp_world


func handles(e: Dictionary, key: String) -> bool:
	return key in DECORATIVE and int(e.get("type", 1)) == 1 \
		and int(e.get("active", 1)) != 0 and int(e.get("nodraw", 0)) == 0 \
		and int(e.get("disabled", 0)) == 0 and not bool(e.get("dead", false)) \
		and e.get("warp") == null and not str(e.get("script", "")).is_empty()


# `node` and the source `e` can have different positions: fitted or scene
# placement may move the holder. Resolve the current source hardbox globally,
# then express its centre relative to the holder. A false `collision` denotes a
# seam/backdrop copy, which must not gain an independently targetable body.
func add(node: Node3D, e: Dictionary, id: int, key: String, collision: bool) -> bool:
	if node == null or world == null: return false
	var existing := node.get_node_or_null("HitBody") as StaticBody3D
	var owned := existing != null and bool(existing.get_meta("source_image_hardbox", false))
	if not collision or not handles(e, key):
		if owned: _disable(existing)
		return false
	if existing != null and not owned: return false
	var rect: Rect2 = world.host._hard_rect(e)
	var height := float(world.sprite_height(e))*SCALE*float(e.get("size", 100))/100.0
	if rect.size.x <= 0.0 or rect.size.y <= 0.0 or height <= 0.0:
		if owned: _disable(existing)
		return false
	var body := existing
	if body == null:
		body = StaticBody3D.new()
		body.name = "HitBody"
		body.set_meta("source_image_hardbox", true)
		body.collision_mask = 0
		var new_shape := CollisionShape3D.new()
		new_shape.name = "CollisionShape3D"
		new_shape.shape = BoxShape3D.new()
		body.add_child(new_shape)
		node.add_child(body)
	var shape := body.get_node("CollisionShape3D") as CollisionShape3D
	var box := shape.shape as BoxShape3D
	var desired_size := Vector3(rect.size.x*SCALE, height, rect.size.y*SCALE)
	if not box.size.is_equal_approx(desired_size): box.size = desired_size
	var center := rect.get_center()
	shape.position = world.point(center.x, center.y)-node.position+Vector3.UP*height*0.5
	shape.disabled = false
	body.collision_layer = 2
	body.set_meta("entity_id", id)
	return true


func _disable(body: StaticBody3D) -> void:
	body.collision_layer = 0
	var shape := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape != null: shape.disabled = true
