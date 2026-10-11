# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
# Mount a source poster on the fitted inn wall face that supports its complete
# original-camera picture. It leaves source movement hardness and scripts alone.
extends RefCounted

const S := 0.025
const EPSILON_SOURCE_PX := 0.01 # paired height/depth shift preserves (z-height)

var world

func _init(fp_world) -> void:
	world = fp_world

func _poster(e: Dictionary, path: String) -> bool:
	return path.begins_with("assets/graphics/inner/poster") and path.get_file().begins_with("poster") \
		and path.get_extension().to_lower() == "png" and int(e.get("type", 1)) == 1 \
		and int(e.get("vision", 0)) == 0 and int(e.get("brain", 0)) == 0 \
		and int(e.get("active", 1)) != 0 and int(e.get("nodraw", 0)) == 0 \
		and int(e.get("disabled", 0)) == 0 and absf(float(e.get("size", 100)) - 100.0) < 0.5 \
		and not str(e.get("script", "")).is_empty()

func _source_rect(e: Dictionary, path: String) -> Rect2i:
	var d: Dictionary = world.host._frame(int(e.get("pseq", e.get("seq", 0))),
		int(e.get("pframe", e.get("frame", 1))))
	var image: Image = world.sprite_image(path)
	if image == null: return Rect2i()
	return Rect2i(int(e.get("x", 0)) - int(d.get("dx", 0)),
		int(e.get("y", 0)) - int(d.get("dy", 0)), image.get_width(), image.get_height())

# An opaque or transparent poster texel alike needs a wall picture at that
# original-camera coordinate. A poster can cross adjacent wall spans, provided
# they share the very same fitted front plane. No owner index or room number is
# built into the selection.
func _supported(rect: Rect2i, walls: Array) -> bool:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var found := false
			for wall in walls:
				var prism: Dictionary = wall["prism"]
				var base: Rect2 = prism["rect"]
				if float(x) + 0.5 < base.position.x or float(x) + 0.5 >= base.end.x: continue
				if float(y) + 0.5 < float(prism["front"]) - float(prism["height"]) \
						or float(y) + 0.5 >= float(prism["front"]): continue
				var at: Vector2i = wall["art_at"]
				var image: Image = wall["image"]
				var px := x - at.x
				var py := y - at.y
				if px < 0 or py < 0 or px >= image.get_width() or py >= image.get_height(): continue
				if image.get_pixel(px, py).a > 0.5:
					found = true
					break
			if not found: return false
	return true

func mount(e: Dictionary, screen: int) -> Dictionary:
	if world == null or world.host == null or world.solids == null: return {}
	var path: String = world.frame_path(e)
	if not _poster(e, path) or not world.solids.walls_fitted(screen): return {}
	var rect := _source_rect(e, path)
	if rect.size.x <= 0 or rect.size.y <= 0: return {}
	var groups: Dictionary = {}
	for source in world.host.world.screens.get(str(screen), {}).get("sprites", []):
		if int(source.get("vision", 0)) != 0: continue
		var wall_path: String = world.frame_path(source)
		var fit: Dictionary = world.solids.fit_of(wall_path)
		if str(fit.get("kind", "")) != "wall" or int(fit.get("cap", 0)) <= 0: continue
		var prism: Dictionary = world.solids.wall_prism(source, fit, screen)
		var base: Rect2 = prism["rect"]
		if base.end.x <= float(rect.position.x) or base.position.x >= float(rect.end.x): continue
		if float(rect.position.y) < float(prism["front"]) - float(prism["height"]) \
				or float(rect.end.y) > float(prism["front"]): continue
		var d: Dictionary = world.host._frame(int(source.get("seq", 0)), int(source.get("frame", 1)))
		var image: Image = world.sprite_image(wall_path)
		if image == null: continue
		var face: float = prism["front"]
		if not groups.has(face): groups[face] = []
		groups[face].append({"index": int(source.get("index", 0)), "prism": prism,
			"art_at": Vector2i(int(source.get("x", 0)) - int(d.get("dx", 0)),
				int(source.get("y", 0)) - int(d.get("dy", 0))), "image": image})
	var matches := []
	for face in groups:
		if _supported(rect, groups[face]): matches.append(float(face))
	if matches.size() != 1: return {} # no support, or ambiguous competing planes
	var front: float = matches[0]
	var indexes := []
	for wall in groups[front]: indexes.append(int(wall["index"]))
	return {"front_source_y": front, "poster_projection_rect": rect,
		"support_wall_indexes": indexes, "source_path": path,
		"rule": "entire original poster rectangle backed by source wall art on one fitted south-front plane"}

# Called after the regular sprite constructor has set its original clean
# texture and source hotspot offset, before its generic billboard and body.
# Returning false leaves nonmatching sprites on their existing path.
func add(node: Node3D, sp: Sprite3D, e: Dictionary, id: int,
		screen: int, collision: bool) -> bool:
	if node == null or sp == null or node.has_meta("surface_position"): return false
	var support := mount(e, screen)
	if support.is_empty(): return false
	var front := float(support["front_source_y"])
	var shift := (front - float(e.get("y", 0)) + EPSILON_SOURCE_PX) * S
	sp.position += Vector3(0.0, shift, shift)
	sp.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sp.rotation = Vector3.ZERO # source front faces the original +Z camera
	sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	sp.set_meta("screen", screen)
	sp.set_meta("mounted_poster", true)
	node.add_child(sp)
	var quad: AABB = sp.get_aabb() # actual texture, hotspot offset and pixel size
	if collision:
		var body := StaticBody3D.new()
		body.name = "HitBody"
		body.set_meta("entity_id", id)
		body.set_meta("mounted_poster", true)
		body.collision_layer = 2 # scripted talk/use surface
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(quad.size.x, quad.size.y, sp.pixel_size)
		shape.shape = box
		shape.position = sp.position + quad.get_center()
		body.add_child(shape)
		node.add_child(body)
	node.set_meta("height", sp.position.y + quad.end.y)
	node.set_meta("base_model_position", sp.position)
	node.set_meta("actor", false)
	node.set_meta("billboard", false)
	node.set_meta("mounted_poster", support)
	return true
