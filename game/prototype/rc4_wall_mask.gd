# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
# Verdict: Disconnected bounded wall design candidate; no movement integration.
# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
# Isolated screen-712 geometry experiment. Movement hardness remains the authored map data.
# The source sprite defines the solid; the JSON lists mask cells separately for review.
extends RefCounted

const WALL_DATA := "res://prototype/rc4_walls.json"
const BUILDINGS := preload("res://scripts/sprite_buildings.gd")

var _scale := 0.025
var _atlas_size := Vector2(640, 600)
var _atlas_y0 := -200.0
var _height := 74.0
var _donor_width := 100.0
var _donor_height := 74.0
var _x_min := 0.0
var _x_max := 0.0
var _z_min := 0.0
var _z_max := 0.0

func read_fit() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(WALL_DATA))
	return parsed if parsed is Dictionary else {}

# The returned node is at the screen's local source-pixel origin: x=20 maps to
# x=0 m, z=0 maps to z=0 m. Only owner_indexes may be suppressed in the runner.
# No tile or sprite hardness is edited. ray_body is optional for aim rays.
# The first argument is retained for prototype-runner compatibility; mask disagreement
# no longer vetoes geometry, because collision will follow the source solid.
func build(allow_negative_fit := false, ray_body := false, scale := 0.025) -> Node3D:
	var fit := read_fit()
	if fit.is_empty() or int(fit.get("screen", 0)) != 712 or int(fit.get("schema", 0)) != 2:
		push_error("RC4 wall prototype: missing or wrong-screen fit")
		return Node3D.new()
	var _old_preview_flag: bool = allow_negative_fit
	_scale = scale
	_atlas_size = Vector2(float(fit.camera.atlas_size[0]), float(fit.camera.atlas_size[1]))
	_atlas_y0 = float(fit.camera.atlas_y0)
	_height = float(fit.shared_height_px)
	var donor: Dictionary = fit.unseen_face_material
	_donor_width = float(donor.face_size_px[0])
	_donor_height = float(donor.face_size_px[1])
	var extent_x := int(_atlas_size.x)
	var occupancy := PackedByteArray()
	occupancy.resize(extent_x * 400)
	var rows: Array = fit.surface.runs
	_x_min = INF
	_x_max = -INF
	_z_min = INF
	_z_max = -INF
	for item in rows:
		var z := int(item[0])
		var x0 := int(item[1])
		var x1 := int(item[2])
		_x_min = minf(_x_min, float(x0))
		_x_max = maxf(_x_max, float(x1))
		_z_min = minf(_z_min, float(z))
		_z_max = maxf(_z_max, float(z + 1))
		for x in range(x0, x1): occupancy[z * extent_x + x] = 1
	var seen := SurfaceTool.new()
	seen.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inferred := SurfaceTool.new()
	inferred.begin(Mesh.PRIMITIVE_TRIANGLES)
	for item in rows:
		var z := int(item[0])
		var x0 := int(item[1])
		var x1 := int(item[2])
		# The raised source camera saw the cap. Its projected UV preserves the
		# source cap pixels, including the bend and the end-on run.
		_quad_seen(seen, Vector3(x0, _height, z), Vector3(x1, _height, z),
			Vector3(x1, _height, z+1), Vector3(x0, _height, z+1))
		# X-constant walls collapse to one UV dimension under (x,z-y).
		# Give both end-on sides the own stone face at physical source-pixel scale.
		_quad_inferred(inferred, Vector3(x0, 0, z), Vector3(x0, 0, z+1),
			Vector3(x0, _height, z+1), Vector3(x0, _height, z), true, true)
		_quad_inferred(inferred, Vector3(x1, 0, z+1), Vector3(x1, 0, z),
			Vector3(x1, _height, z), Vector3(x1, _height, z+1), true, false)
		for x in range(x0, x1):
			if z == 0 or occupancy[(z-1) * extent_x + x] == 0:
				# North/back: unseen in the original, so transfer the stone face.
				_quad_inferred(inferred, Vector3(x+1, 0, z), Vector3(x, 0, z),
					Vector3(x, _height, z), Vector3(x+1, _height, z), false, true)
			if z == 399 or occupancy[(z+1) * extent_x + x] == 0:
				# South/front: retain the exact source-camera projection.
				_quad_seen(seen, Vector3(x, 0, z+1), Vector3(x+1, 0, z+1),
					Vector3(x+1, _height, z+1), Vector3(x, _height, z+1))
	var mesh := seen.commit()
	mesh = inferred.commit(mesh)
	var atlas := _source_atlas(fit.owners)
	var texture: ImageTexture = BUILDINGS.new({}, {}, {}, scale).fill_holes(atlas)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	material.albedo_texture = texture
	var face: ImageTexture = _donor_face_texture(donor)
	var transfer := StandardMaterial3D.new()
	transfer.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	transfer.cull_mode = BaseMaterial3D.CULL_DISABLED
	transfer.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	transfer.texture_repeat = true
	transfer.albedo_texture = face
	var root := Node3D.new()
	root.name = "RC4WallMaskPreview"
	root.set_meta("geometry_status", str(fit.geometry_status))
	root.set_meta("mask_comparison", fit.mask_comparison)
	root.set_meta("owner_indexes", fit.owner_indexes)
	root.set_meta("unseen_face_inference", donor.inference)
	var shell := MeshInstance3D.new()
	shell.name = "SourceWallShell"
	shell.mesh = mesh
	shell.set_surface_override_material(0, material)
	shell.set_surface_override_material(1, transfer)
	root.add_child(shell)
	if ray_body:
		var body := StaticBody3D.new()
		body.name = "WallRayBody"
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		shape.shape = mesh.create_trimesh_shape()
		body.add_child(shape)
		root.add_child(body)
	return root

# The proposed solid collision in screen pixels. The runner can inspect this
# alongside the authored tile mask; this prototype performs no subtraction.
func solid_footprint(fit: Dictionary = {}) -> PackedByteArray:
	if fit.is_empty(): fit = read_fit()
	var out := PackedByteArray()
	out.resize(640 * 400)
	for item in fit.get("surface", {}).get("runs", []):
		var z := int(item[0])
		for x in range(int(item[1]), int(item[2])): out[z * 640 + x] = 1
	return out

func _source_atlas(owners: Array) -> Image:
	var atlas := Image.create(int(_atlas_size.x), int(_atlas_size.y), false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	for owner in owners:
		var texture: Texture2D = load("res://" + str(owner.path))
		if texture == null:
			push_error("RC4 wall prototype: missing source image " + str(owner.path))
			continue
		var src := texture.get_image()
		if src.is_compressed(): src.decompress()
		src.convert(Image.FORMAT_RGBA8)
		atlas.blend_rect(src, Rect2i(Vector2i.ZERO, src.get_size()),
			Vector2i(int(owner.at[0]), int(owner.at[1] - _atlas_y0)))
	return atlas

func _uv(point: Vector3) -> Vector2:
	return Vector2(point.x / _atlas_size.x, (point.z - point.y - _atlas_y0) / _atlas_size.y)

func _donor_face_texture(donor: Dictionary) -> ImageTexture:
	var texture: Texture2D = load("res://" + str(donor.source_path))
	var image := texture.get_image()
	if image.is_compressed(): image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var cap := int(donor.face_crop_rows[0])
	var bottom := int(donor.face_crop_rows[1])
	var crop := image.get_region(Rect2i(0, cap, int(_donor_width), bottom - cap))
	crop.generate_mipmaps()
	return ImageTexture.create_from_image(crop)

# Like interior_solids._wall_face/_wall_end: one image texel per source pixel
# along the actual horizontal run, and the measured face rows over the one
# shared height. The opposite surface mirrors the physical run, not the UV
# height. Half-texel inset keeps top and bottom samples inside the face crop
# when horizontal texture repeat is enabled.
func _donor_uv(point: Vector3, along_z: bool, reverse: bool) -> Vector2:
	var run := point.z - _z_min if along_z else point.x - _x_min
	if reverse: run = _z_max - point.z if along_z else _x_max - point.x
	var v := (_donor_height - 0.5 - (_donor_height - 1.0) * point.y / _height) / _donor_height
	return Vector2(run / _donor_width, v)

func _quad_seen(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for p in [a, b, c, a, c, d]:
		st.set_uv(_uv(p))
		st.add_vertex(Vector3((p.x - 20.0) * _scale, p.y * _scale, p.z * _scale))

func _quad_inferred(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		along_z: bool, reverse: bool) -> void:
	for p in [a, b, c, a, c, d]:
		st.set_uv(_donor_uv(p, along_z, reverse))
		st.add_vertex(Vector3((p.x - 20.0) * _scale, p.y * _scale, p.z * _scale))
