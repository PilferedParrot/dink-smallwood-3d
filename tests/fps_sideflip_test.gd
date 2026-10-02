extends SceneTree
# The side flip at a wall's plane (docs/DIRECTION.md, "The side flip, walked"; the eleventh-pass unit U5).
# A sprite near a fitted house is drawn over the house or under it by which side of the wall's plane the camera
# stands on (fp_world.gd depth_rule, DEPTH_SHADER). Modes walk and views are run by tests/test_fps_sideflip.py; list is for finding cases:
#
#   --mode=walk  --from=A --to=B --step=S   Walk the camera round 251's tree-08 (the cabin's; --screen=N --sprite=X,Y --radius=R
#       for another) at 230 px, angle A..B degrees
#       (the angle as the camera's offset from the tree, east = 0, north = 90: the crossing of the cabin's south wall's
#       plane is at 27.2 and 206.0), looking at the tree. At each angle two frames, with the tree and with it hidden
#       (the light's shadows off, the sprite's own pixels only); T = the pixels the tree changes. Prints
#           "TREE angle pixels popped"   popped = |T(angle) xor T(previous angle)|: the tree's picture's change in one
#       step, the motion of its edges and a flip alike. A flip is a step far over the walk's ordinary steps.
#       --out-dir=DIR also saves every frame with the tree (with the shadows on) as DIR/aNNN.NN.png.
#   --mode=views --views=FILE --out-dir=DIR   Render the views [{name, screen, x, y, yaw, pitch}] as fps_capture.gd
#       --batch does (frozen from the load, shadows on), as DIR/<name>.png.
#
#   --mode=list --views=A,B,C   (the screens, comma-separated) Print every flagged sprite of those screens:
#       "SPRITE screen x y reach_px normal_x normal_y".
#   --swap   (walk) add a last column to each TREE line: within 0.5 reach of the plane, the pixels of the whole frame that change
#       when the sprite is drawn on the other side at that camera (what the side is worth there: a hard flip pops by about this).
#   --probe  (views) after each SHOT line print every flagged sprite's reach, blend, side and e (for finding who is in the band).
#   --k=K   the width of the side's turn, in the sprite's reach (sets every flagged sprite's `blend`): K = 0 turns it at the plane
#       as before, 1 is a blend over the whole reach (the rejected one); no --k: as built (fp_world.gd SIDE_BLEND).
#   Each TREE line ends with e, the camera's distance from the sprite's wall plane in the sprite's reaches (+ on the original
#   camera's side): the side turns over |e| < K.
# Verdict: written 2026-10-02 (Sonnet 5.5 subagent, unit U5). Works: it measured the 251 pop (3,872 px at 206.0 -> 206.25 degrees,
# 2,504 at 27.0 -> 27.25), the failed depth ramp and the screen-door that replaced it. A walk of 129 angles takes under a minute.
const GAME = preload("res://scripts/fps_game.gd")
const EPS := 3 # max channel difference counted as a changed pixel
var screen_n := 251
var tree_at := Vector2(153, 374) # 251's tree-08, the cabin's
var radius := 230.0

var game

func _initialize() -> void:
	_run.call_deferred()

func _sprites(node: Node, out: Array) -> void:
	if node is Sprite3D and node.get_parent() != null and node.get_parent().has_meta("billboard"): out.append(node)
	for child in node.get_children(): _sprites(child, out)

func _flagged() -> Array:
	var all: Array = []
	_sprites(game.scene_root, all)
	var out: Array = []
	for sp in all:
		if sp.material_override is ShaderMaterial: out.append(sp)
	return out

func _set_k(k: float) -> void:
	if k < 0.0: return
	for sp in _flagged():
		var m := sp.material_override as ShaderMaterial
		m.set_shader_parameter("blend", k * float(m.get_shader_parameter("reach")))

func _load(screen: int) -> void:
	game.vm.cancel_all()
	game.vm.globals["vision"] = 0
	game.load_map(screen, false)
	game.set_physics_process(false)
	game.set_process(false)
	await create_timer(0.6).timeout
	game.vm.cancel_all()
	game.playing = false
	game.ui.close_menu()
	game.ui.visible = false
	for model in [game.fps_viewmodel, game.fps_hand]:
		if is_instance_valid(model): model.visible = false

func _camera(x: float, y: float, yaw: float, pitch: float) -> void:
	game.entities[1].x = x
	game.entities[1].y = y
	game.fps_yaw = yaw
	game.fps_pitch = pitch
	game._sync_fps_camera()
	for id in game.entities.keys(): game._update_visual(id)

func _grab() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	return img

func _changed(a: Image, b: Image) -> PackedByteArray:
	var da := a.get_data()
	var db := b.get_data()
	var out := PackedByteArray()
	out.resize(da.size() / 3)
	for i in out.size():
		var o := i * 3
		out[i] = 1 if (absi(da[o] - db[o]) > EPS or absi(da[o + 1] - db[o + 1]) > EPS or absi(da[o + 2] - db[o + 2]) > EPS) else 0
	return out

func _run() -> void:
	var mode := "walk"
	var from := 190.0
	var to := 222.0
	var step := 0.25
	var k := -1.0
	var out_dir := ""
	var views_file := ""
	var probe := false
	var swap := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="): mode = arg.trim_prefix("--mode=")
		if arg.begins_with("--from="): from = float(arg.trim_prefix("--from="))
		if arg.begins_with("--to="): to = float(arg.trim_prefix("--to="))
		if arg.begins_with("--step="): step = float(arg.trim_prefix("--step="))
		if arg == "--probe": probe = true
		if arg == "--swap": swap = true
		if arg.begins_with("--k="): k = float(arg.trim_prefix("--k="))
		if arg.begins_with("--out-dir="): out_dir = arg.trim_prefix("--out-dir=")
		if arg.begins_with("--views="): views_file = arg.trim_prefix("--views=")
		if arg.begins_with("--screen="): screen_n = int(arg.trim_prefix("--screen="))
		if arg.begins_with("--sprite="): tree_at = Vector2(float(arg.trim_prefix("--sprite=").split(",")[0]), float(arg.trim_prefix("--sprite=").split(",")[1]))
		if arg.begins_with("--radius="): radius = float(arg.trim_prefix("--radius="))
	game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	await game._new_game()
	await create_timer(1.0).timeout
	if mode == "list":
		# Every flagged sprite of the screens given as --screens=a,b,c: "SPRITE screen x y reach_px normal_x normal_y".
		for sc in views_file.split(",", false):
			await _load(int(sc))
			for sp in _flagged():
				var m := sp.material_override as ShaderMaterial
				var at: Vector3 = sp.get_meta("depth_sig")
				var nrm: Vector2 = m.get_shader_parameter("normal")
				print("SPRITE %s %d %d %.0f %.3f %.3f" % [sc, int(at.x), int(at.y), at.z, nrm.x, nrm.y])
	elif mode == "views":
		var views: Array = JSON.parse_string(FileAccess.get_file_as_string(views_file))
		var screens := []
		for v in views:
			if not (int(v.screen) in screens): screens.append(int(v.screen))
		for screen in screens:
			await _load(screen)
			_set_k(k)
			for v in views:
				if int(v.screen) != screen: continue
				_camera(float(v.x), float(v.y), float(v.yaw), float(v.get("pitch", -0.05)))
				var img := await _grab()
				img.save_png(out_dir.path_join(str(v.name) + ".png"))
				# How near the camera is to the nearest flagged sprite's wall plane, in that sprite's reaches.
				var near := INF
				var eye: Vector3 = game.camera.global_position
				for sp in _flagged():
					var m := sp.material_override as ShaderMaterial
					var nrm: Vector2 = m.get_shader_parameter("normal")
					if nrm.length_squared() < 0.5: continue
					var wall: Vector2 = m.get_shader_parameter("wall")
					near = minf(near, absf((Vector2(eye.x, eye.z) - wall).dot(nrm)) / float(m.get_shader_parameter("reach")))
				print("SHOT ", v.name, " ", "%.3f" % near)
				if probe:
					# Every flagged sprite: where, its reach in px, the shader's blend (m) and side0, e in reaches (+ the original camera's side).
					for sp in _flagged():
						var m := sp.material_override as ShaderMaterial
						var at: Vector3 = sp.get_meta("depth_sig")
						var nrm: Vector2 = m.get_shader_parameter("normal")
						var wall: Vector2 = m.get_shader_parameter("wall")
						var ee := (Vector2(eye.x, eye.z) - wall).dot(nrm) * signf(nrm.y) / float(m.get_shader_parameter("reach"))
						print("PROBE %s %d %d reach %.0f blend %.3f side0 %d e %.3f vis %s" % [v.name, int(at.x), int(at.y), at.z, m.get_shader_parameter("blend"), int(m.get_shader_parameter("side0")), ee, sp.is_visible_in_tree()])
	else:
		await _load(screen_n)
		_set_k(k)
		var tree: Sprite3D = null
		for sp in _flagged():
			var at: Vector3 = sp.get_meta("depth_sig")
			if absf(at.x - tree_at.x) < 1.0 and absf(at.y - tree_at.y) < 1.0: tree = sp
		if tree == null:
			print("FAIL the sprite is not flagged")
			quit(1)
			return
		print("TARGET blend ", (tree.material_override as ShaderMaterial).get_shader_parameter("blend"), " reach ", (tree.material_override as ShaderMaterial).get_shader_parameter("reach"), " side0 ", (tree.material_override as ShaderMaterial).get_shader_parameter("side0"))
		var previous := PackedByteArray()
		var a := from
		while a <= to + 1e-6:
			var r := deg_to_rad(a)
			var yaw := fposmod(PI / 2.0 + r + PI, 2.0 * PI) - PI # looking at the tree
			var x := tree_at.x + radius * cos(r)
			var y := tree_at.y - radius * sin(r)
			if out_dir != "":
				game.fp_world.light.shadow_enabled = true
				_camera(x, y, yaw, -0.06)
				(await _grab()).save_png(out_dir.path_join("a%06.2f.png" % a))
			game.fp_world.light.shadow_enabled = false
			_camera(x, y, yaw, -0.06)
			var with_tree := await _grab()
			tree.visible = false
			var without := await _grab()
			tree.visible = true
			var mask := _changed(with_tree, without)
			var n := 0
			for v in mask: n += v
			var popped := 0
			if previous.size() == mask.size():
				for i in mask.size():
					if mask[i] != previous[i]: popped += 1
			# e: the camera's distance from the sprite's wall plane in reaches (+ on the original camera's side), as the shader reads it.
			var m := tree.material_override as ShaderMaterial
			var nrm: Vector2 = m.get_shader_parameter("normal")
			var eye: Vector3 = game.camera.global_position
			var e := (Vector2(eye.x, eye.z) - (m.get_shader_parameter("wall") as Vector2)).dot(nrm) * signf(nrm.y) / float(m.get_shader_parameter("reach"))
			var swapped_px := -1
			if swap and absf(e) < 0.5:
				# What the side is worth at this camera: the pixels that change when the sprite is drawn on the other side
				# (the sprite's own `flip` uniform swapped; the other flagged sprites keep their sides).
				m.set_shader_parameter("flip", -1.0)
				var other := await _grab()
				m.set_shader_parameter("flip", 1.0)
				swapped_px = 0
				for v in _changed(with_tree, other): swapped_px += v
			print("TREE %.2f %d %d %.3f%s" % [a, n, popped if previous.size() == mask.size() else -1, e, (" %d" % swapped_px) if swap else ""])
			previous = mask
			a += step
	game.queue_free()
	await process_frame
	quit()
