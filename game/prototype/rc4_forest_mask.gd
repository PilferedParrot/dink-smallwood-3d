# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
# Verdict: Disconnected negative contour experiment, never normal world geometry.
# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
# Screen-local forest experiment. The caller owns integration and keeps the source
# tile hardness and tree-09/10 sprites under fp_world's existing seam rules.
extends RefCounted

const SCALE := 0.025
const FIT_PATH := "res://prototype/rc4_forest.json"
const ATLAS_PATH := "res://assets/tiles/ts01.png"

static func load_fit() -> Dictionary:
	if not FileAccess.file_exists(FIT_PATH): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIT_PATH))
	return parsed if parsed is Dictionary else {}


# Replace only the bit set in ownership.mask_runs. The original source texture is
# retained for the upright shell, so the forest pixels are projected once rather
# than left flat beneath it. This image helper does not change the collision mask.
static func replacement_ground(source: Texture2D, fit: Dictionary) -> ImageTexture:
	if source == null or str(fit.get("schema", "")) != "rc4-forest-mask-prototype-1": return null
	var img := source.get_image().duplicate() as Image
	if img == null or img.get_width() != 600 or img.get_height() != 400: return null
	if img.is_compressed(): img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var atlas_texture := load(ATLAS_PATH) as Texture2D
	if atlas_texture == null: return null
	var atlas := atlas_texture.get_image()
	if atlas.is_compressed(): atlas.decompress()
	atlas.convert(Image.FORMAT_RGBA8)
	var ownership: Dictionary = fit.get("ownership", {})
	var donors: Dictionary = ownership.get("donor_tile_by_member_index", {})
	for run in ownership.get("mask_runs", []):
		var first := int(run[0])
		var length := int(run[1])
		for flat in range(first, first + length):
			var x := flat % 600
			var y := int(flat / 600)
			var member := int(y / 50) * 12 + int(x / 50)
			var key := str(member)
			if not donors.has(key): continue
			var cell := int(donors[key]) % 128
			var donor_x := (cell % 12) * 50 + x % 50
			var donor_y := int(cell / 12) * 50 + y % 50
			img.set_pixel(x, y, atlas.get_pixel(donor_x, donor_y))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# Returns a node owned by this prototype and a replacement texture. `offset` is
# fp_world.add_ground's screen offset. The mesh has no collision: the authored tile
# mask remains the only ground-boundary collision source.
static func build(parent: Node3D, offset: Vector3, source: Texture2D, fit: Dictionary) -> Dictionary:
	if parent == null or source == null or int(fit.get("screen", -1)) != 144: return {}
	var surface: Dictionary = fit.get("geometry", {}).get("surfaces", [])[0]
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for segment in surface.get("segments", []):
		var a: Array = segment["a"]
		var b: Array = segment["b"]
		var outward: Array = segment["outward"]
		var h := float(segment["height_px"])
		var normal := Vector3(float(outward[0]), 0.0, float(outward[1]))
		var start := vertices.size()
		for sample in [[a, 0.0], [b, 0.0], [b, h], [a, h]]:
			var q: Array = sample[0]
			var rise := float(sample[1])
			var x := float(q[0])
			var z := float(q[1])
			vertices.append(Vector3((x - 300.0) * SCALE, rise * SCALE, (z - 200.0) * SCALE))
			# Two source pixels into the owned foliage, away from the grass edge.
			uvs.append(Vector2((x - 2.0 * normal.x) / 600.0,
				(z - 2.0 * normal.z - rise) / 400.0))
			normals.append(normal)
		for tri in [0, 1, 2, 0, 2, 3]: indices.append(start + tri)
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.albedo_texture = source
	material.texture_repeat = true
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.96
	var shell := MeshInstance3D.new()
	shell.name = "ForestMaskShell_144"
	shell.mesh = mesh
	shell.material_override = material
	shell.position = offset
	shell.set_meta("prototype_owner", "forest_tile_ground")
	parent.add_child(shell)
	return {"node": shell, "ground": replacement_ground(source, fit),
		"tile_members": fit["ownership"]["tile_members"],
		"trim_members_unclaimed": fit["ownership"]["trim_members_unclaimed"]}
