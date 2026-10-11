# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
# Build a complete original seq32/frame1 fir at the physical foot of each
# retained tree-09/10 source part. fp_world.seam_parts owns visibility.
extends RefCounted

const FIT_PATH := "res://prototype/rc5_firs.json"
const SCALE := 0.025

var world: Object
var fit: Dictionary = {}


func _init(fp_world: Object) -> void:
	world = fp_world
	if FileAccess.file_exists(FIT_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIT_PATH))
		if parsed is Dictionary and str(parsed.get("schema", "")) == "rc5-whole-fir-fit-1":
			fit = parsed


# Both editor layers use the same object ownership. A source edge trim is
# standing foliage even when the old importer painted its type-0 copy flat.
func handles(e: Dictionary) -> bool:
	return not fit.is_empty() and not bool(e.get("runtime_created", false)) \
		and int(e.get("type", 1)) in [0,1] and int(e.get("pseq",e.get("seq",0))) == 32 \
		and int(e.get("pframe",e.get("frame",0))) in [9, 10] and int(e.get("vision", 0)) == 0 \
		and int(e.get("brain", 0)) == 0 and str(e.get("script", "")).is_empty() \
		and absf(float(e.get("size", 100)) - 100.0) < 0.5


# `node` already stands at e.x/e.y on its source screen. A shown part
# becomes one complete, indivisible visual with its own shadow-only twin.
# The caller supplies seam_parts(e, screen) for THIS scene_block, never a
# full-world fit's baked visibility. Source hardness stays with e.
func add(node: Node3D, e: Dictionary, parts: Array, screen: int, id: int,
		collision: bool) -> void:
	if fit.is_empty() or node == null or world == null: return
	var frame: int = int(e.get("pframe", e.get("frame", 0)))
	var path := str(world.call("frame_path", e))
	var source_parts: Array = fit.get("source_parts", {}).get(path, [])
	if frame not in [9, 10] or source_parts.size() != parts.size(): return
	var d: Dictionary = world.host._frame(32, frame)
	for k in parts.size():
		var r: Array = parts[k]
		if not bool(r[3]):
			node.set_meta("seam_hidden", true)
			continue
		var source: Dictionary = source_parts[k]
		if int(r[0]) != int(source["rows"][0]) or int(r[1]) != int(source["rows"][1]):
			push_error("Whole fir fit does not match source rows: %s part %d" % [path, k])
			continue
		var foot: Array = source["source_foot_in_full_art_px"]
		var local_foot := Vector3((float(foot[0]) - float(d.get("dx", 0))) * SCALE,
			0.0, (float(foot[1]) - float(d.get("dy", 0))) * SCALE)
		var provenance := {"screen": screen, "index": int(e.get("index", -1)),
			"part": k, "path": path, "source_rows": source["rows"].duplicate(),
			"source_foot_in_full_art_px": source["source_foot_in_full_art_px"].duplicate()}
		at_foot(node, local_foot, float(source["uniform_scale"]), provenance,
			collision, id)
		var height := float(fit.template.crown_height_px)*SCALE*float(source.uniform_scale)
		node.set_meta("height",maxf(float(node.get_meta("height",0.0)),height))


# Shared constructor for later forest choices. `foot` is local to `parent`,
# in world units. `uniform_scale` multiplies both art axes equally.
func at_foot(parent: Node3D, foot: Vector3, uniform_scale: float,
		provenance: Dictionary = {}, collision: bool = false, id: int = 0) -> Node3D:
	if fit.is_empty() or parent == null or world == null or uniform_scale <= 0.0: return null
	var template: Dictionary = fit["template"]
	var path := str(template["path"])
	var texture := world.call("clean_texture", path) as Texture2D
	if texture == null: return null
	var anchor: Array = template["source_foot_px"]
	var holder := Node3D.new()
	holder.name = "WholeFir_%s" % str(provenance.get("part", parent.get_child_count()))
	holder.position = foot
	holder.set_meta("model_key", "pine_tree")
	holder.set_meta("whole_fir", true)
	holder.set_meta("source_provenance", provenance.duplicate(true))
	holder.set_meta("template_path", path)
	holder.set_meta("template_height_px", int(template["crown_height_px"]))
	holder.set_meta("uniform_scale", uniform_scale)
	holder.set_meta("entity_id", id)
	parent.add_child(holder)
	var sp := Sprite3D.new()
	sp.name = "Model"
	sp.texture = texture
	sp.shaded = false
	sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	sp.pixel_size = SCALE * uniform_scale
	sp.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sp.centered = true
	sp.offset = Vector2(texture.get_width() / 2.0 - float(anchor[0]),
		float(anchor[1]) - texture.get_height() / 2.0)
	sp.set_meta("path", path)
	sp.set_meta("screen", int(provenance.get("screen", -1)))
	holder.add_child(sp)
	world.call("shadow_twin", sp, false)
	var height := float(template["crown_height_px"]) * SCALE * uniform_scale
	holder.set_meta("height", height)
	holder.set_meta("billboard", true)
	if collision:
		var body := StaticBody3D.new()
		body.name = "HitBody"
		body.set_meta("entity_id", id)
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.8, height, 0.8)
		shape.position.y = height * 0.5
		shape.shape = box
		body.add_child(shape)
		holder.add_child(body)
	return holder
