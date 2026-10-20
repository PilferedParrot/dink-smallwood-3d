extends SceneTree
# The well through the sprite's own camera (docs/DIRECTION.md, "P4d: the well"): screen 408's well, alone, rendered by an orthographic
# camera whose picture is the sprite's, screen = (X, k Z - Y): looking north and down at elevation atan(k) (then v / cos = k Z - Y), the
# vertical stretched back by 1/cos in tools/well_g1.py. The repo's original-camera view (fps_capture.gd) is a k = 1 camera and cannot
# reproduce a sprite drawn at k = 0.5. Writes <out>/all.png (the whole well) and <out>/roof.png (its roof alone: the last mesh of the
# compound), magenta background, and <out>/g1.json (the registration: sprite px <-> render px). Arguments: --out=DIR [--fits=FILE: a
# landmarks.json to use instead of the checkout's, set before the screen loads: the flat-slab control].
# Verdict: written 2026-10-20 (Sonnet 5.5, P4d).
const GAME = preload("res://scripts/fps_game.gd")
const WIDTH_PX := 240.0 # the render's width in sprite px
var game

func _initialize() -> void:
	_run.call_deferred()

func _hide_except(node: Node, keep: Node) -> void:
	if node is VisualInstance3D and node != keep and not keep.is_ancestor_of(node) and not node.is_ancestor_of(keep): node.visible = false
	for c in node.get_children(): _hide_except(c, keep)

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
	await create_timer(1.0).timeout
	game.vm.cancel_all()
	game.vm.globals["vision"] = 0
	var world = game.fp_world
	if fits != "":
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(fits))
		for key in parsed.keys(): world.props.fits[key] = parsed[key]
		world.props.cache.clear()
	game.load_map(408, false)
	await create_timer(0.6).timeout
	game.vm.cancel_all()
	game.playing = false
	game.set_physics_process(false)
	game.set_process(false)
	var well_path := "assets/graphics/struct/Landmark/landm-01.png"
	var node: Node3D = null
	for id in game.entities.keys():
		if id == 1: continue
		if world.frame_path(game.entities[id]).to_lower().ends_with("landm-01.png") and game.visuals.get(id) != null: node = game.visuals[id]
	var model: Node3D = node.get_node("Model")
	print("MODEL ", model.get_class(), " basis ", model.global_transform.basis, " children ", model.get_child_count())
	var fit: Dictionary = world.props.fits[well_path]
	var k := float(fit.k)
	var S: float = world.props.S
	var base: Dictionary = fit.base
	var zc := float(base.cz) - (1.0 - float(base.k))*float(base.nodes[0][1])
	_hide_except(game, model)
	var env: Environment = world.environment
	if env:
		env.fog_enabled = false
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(1, 0, 1)
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	for m in [game.fps_viewmodel, game.fps_hand]:
		if is_instance_valid(m): m.visible = false
	var theta := atan(k)
	var f := Vector3(0, -sin(theta), -cos(theta))
	var up := Vector3(0, cos(theta), -sin(theta))
	var target := Vector3(float(fit.cx), 55.0, zc)*S # local to the model: the sprite's middle in x, 55 px up
	var cam: Camera3D = game.camera
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.size = WIDTH_PX*S
	cam.near = 0.05
	cam.far = 200.0
	var gb := model.global_transform.basis
	var gpos := model.global_transform*(target - f*30.0)
	cam.global_transform = Transform3D(Basis.looking_at(gb*f, gb*up), gpos)
	game.ui.visible = false
	var shots := {"all": -1}
	for i in 2:
		for j in 6: await process_frame
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.save_png(out.path_join(("all" if i == 0 else "roof") + ".png"))
		if i == 0:
			var kids := model.get_children()
			for n in kids.size() - 1: (kids[n] as Node3D).visible = false # the roof is the last mesh
	var rec := {"k": k, "S": S, "cx": float(fit.cx), "cz": float(fit.cz), "zc": zc, "target": [target.x/S, target.y/S, target.z/S], "width_px": WIDTH_PX,
		"window": [root.get_texture().get_width(), root.get_texture().get_height()], "theta": theta}
	var fh := FileAccess.open(out.path_join("g1.json"), FileAccess.WRITE)
	fh.store_string(JSON.stringify(rec))
	fh.close()
	game.queue_free()
	await process_frame
	quit()
