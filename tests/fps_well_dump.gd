extends SceneTree
# The well's built surfaces, dumped (docs/DIRECTION.md, "P4d fix round"): for every part of the compound (base, posts, roof) the mesh the
# solid builder makes (vertices in sprite px, UVs in texels, triangles) and the texture it hands the material, so tools/well_materials.py can
# measure what the faces SHOW (the colour of every face of a post, the texel density and stretch of every face of the roof) against the
# sprite, not what the texture holds. Arguments: --out=DIR [--fits=FILE: a landmarks.json to use instead of the checkout's].
# Writes <out>/surfaces.json and <out>/part<i>.png (the texture of part i; a part with a plain colour has none).
# Verdict: written 2026-10-20 (Sonnet 5.5, P4d fix round).
const GAME = preload("res://scripts/fps_game.gd")
var game

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := ""
	var fits := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
		if arg.begins_with("--fits="): fits = arg.trim_prefix("--fits=")
	DirAccess.make_dir_recursive_absolute(out)
	game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	await game._new_game()
	await create_timer(0.5).timeout
	game.vm.cancel_all()
	var world = game.fp_world
	if fits != "":
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(fits))
		for key in parsed.keys(): world.props.fits[key] = parsed[key]
		world.props.cache.clear()
	var path := "assets/graphics/struct/Landmark/landm-01.png"
	var S: float = world.props.S
	var parts: Array = []
	var surfaces: Array = world.props.surfaces(path)
	for i in surfaces.size():
		var mesh: ArrayMesh = surfaces[i][0]
		var arrays: Array = mesh.surface_get_arrays(0)
		var verts: Array = []
		for v in (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array): verts.append([v.x/S, v.y/S, v.z/S])
		var uvs: Array = []
		for u in (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array): uvs.append([u.x, u.y])
		var tex: Variant = surfaces[i][1]
		var rec := {"verts": verts, "uvs": uvs, "index": Array(arrays[Mesh.ARRAY_INDEX] as PackedInt32Array), "texture": ""}
		if tex is ImageTexture:
			rec.texture = "part%d.png" % i
			(tex as ImageTexture).get_image().save_png(out.path_join(rec.texture))
		elif tex is StandardMaterial3D:
			var c: Color = (tex as StandardMaterial3D).albedo_color
			rec["colour"] = [c.r, c.g, c.b]
		parts.append(rec)
	var fh := FileAccess.open(out.path_join("surfaces.json"), FileAccess.WRITE)
	fh.store_string(JSON.stringify({"S": S, "parts": parts}))
	fh.close()
	game.queue_free()
	await process_frame
	quit()
