# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
# Picture-decision fixture only. No production caller; explicit opt-in required.
extends RefCounted

const FIT_PATH := "res://prototype/rc5_forest_preview.json"
const GRASS := preload("res://prototype/rc4_fir_stand.gd")
const SCALE := 0.025
var world: Object
var fit: Dictionary = {}

func _init(fp_world: Object) -> void:
	world = fp_world
	if FileAccess.file_exists(FIT_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIT_PATH))
		if parsed is Dictionary and parsed.get("schema", "") == "rc5-disabled-forest-preview-1":
			fit = parsed

func build(parent: Node3D, center: int, enabled: bool = false,
		forest_floor: bool = false) -> Node3D:
	if not enabled or center not in [144, 375] or fit.is_empty() or world == null: return null
	if parent == null or world.source_firs == null: return null
	var holder := Node3D.new()
	holder.name = "DisabledForestPreview"
	holder.set_meta("prototype_owner", "rc5_forest_preview")
	parent.add_child(holder)
	for key in fit["screens"]:
		var number := int(key)
		if not world.scene_block.has(number): continue
		var data: Dictionary = fit["screens"][key]
		var offset: Vector2 = world.screen_origin(number) - world.screen_origin(center)
		for row in data["added_roots"]:
			var foot: Array = row["foot_local_px"]
			var point := Vector3((float(foot[0]) + offset.x - 300.0) * SCALE, 0.0,
				(float(foot[1]) + offset.y - 200.0) * SCALE)
			var provenance: Dictionary = row.duplicate(true)
			provenance["screen"] = number
			provenance["part"] = holder.get_child_count()
			world.source_firs.at_foot(holder, point, float(row["uniform_scale"]), provenance, false)
		if forest_floor:
			var ground := parent.get_node_or_null("Terrain_%d" % number) as MeshInstance3D
			if ground == null:
				push_error("Forest preview ground missing: %d" % number)
				return null
			var material := ground.material_override.duplicate() as StandardMaterial3D
			var replacement := GRASS.replacement_ground(material.albedo_texture, data)
			if replacement == null:
				push_error("Forest preview grass donor failed: %d" % number)
				return null
			material.albedo_texture = replacement
			ground.material_override = material
	return holder
