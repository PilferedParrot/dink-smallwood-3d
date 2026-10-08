extends SceneTree
# The rail fences stand as solid posts and rails (docs/DIRECTION.md, "Solid fences", Dink M3 solid unit). Parts, run by
# tests/test_fps_fences.py (all through fp_world.gd and scripts/fence_solid.gd as the game builds a scene):
#
#   --sweep   (headless) the scenes in --screens=a,b,c (with --vision=N for the story layer) loaded as the game loads them:
#             "FENCE screen index file kind=solid|card|none hit=layer/shapes|none": every entity of a fence art (lands/Fence,
#             isle-07, isle-08), what stands for it. "POST world_x world_z w d h": every post box built in the scene
#             (world px of its centre, its extent in px), read from the Posts meshes' vertices (36 per box); "BAR ax az bx bz":
#             the end centres of every bar (world px), from the Rails meshes (36 vertices per box: the last two faces are its ends).
#   --render  (rendered, under xvfb) 407's north fence (the entity at 230, 142) seen from its own axis, 1.5 m before its left end:
#             its pixels (the picture with it hidden against the picture with it shown) and the same fence seen from 1.5 m to
#             the side (the control that the count counts). A fixed card is a sliver from its axis; posts and rails are not.
# Verdict: written 2026-10-07 (Sonnet 5.5, solid-fences unit).
const GAME = preload("res://scripts/fps_game.gd")
const SCALE := 0.025

var game
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _fail(message: String) -> void:
	failures.append(message)
	print("FAIL ", message)

func _run() -> void:
	var sweep := false
	var render := false
	var screens: Array = []
	var vision := 0
	for arg in OS.get_cmdline_user_args():
		if arg == "--sweep": sweep = true
		if arg == "--render": render = true
		if arg.begins_with("--screens="):
			for s in arg.trim_prefix("--screens=").split(","): screens.append(int(s))
		if arg.begins_with("--vision="): vision = int(arg.trim_prefix("--vision="))
	game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	await game._new_game()
	await create_timer(1.0).timeout
	if sweep:
		for n in screens: await _sweep(n, vision)
	if render: await _render()
	if failures.is_empty():
		print("FPS FENCES PASS")
		quit(0)
	else:
		print("FPS FENCES FAIL ", failures.size())
		quit(1)

func _is_fence_art(path: String) -> bool:
	var p := path.to_lower()
	if "/lands/fence/" in p: return true
	return "/struct/island/" in p and p.get_file() in ["isle-07.png", "isle-08.png"]

func _settle(number: int, vision: int) -> void:
	game.vm.cancel_all()
	game.vm.globals["vision"] = vision
	game.load_map(number, false)
	await create_timer(0.6).timeout
	game.vm.cancel_all()
	game.playing = false
	game.ui.close_menu()
	game.ui.toast.text = ""
	game.ui.visible = false
	for model in [game.fps_viewmodel, game.fps_hand]:
		if is_instance_valid(model): model.visible = false
	await physics_frame
	await physics_frame

# The boxes of a mesh of 36-vertex boxes, in world metres: [[centre, min, max, vertices], ...].
func _boxes(instance: MeshInstance3D) -> Array:
	var out: Array = []
	if instance.mesh == null or instance.mesh.get_surface_count() == 0: return out
	var v: PackedVector3Array = instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var t: Transform3D = instance.global_transform
	for b in v.size() / 36:
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		var sum := Vector3.ZERO
		var pts: Array = []
		for i in 36:
			var p: Vector3 = t * v[b * 36 + i]
			lo = lo.min(p)
			hi = hi.max(p)
			sum += p
			pts.append(p)
		out.append([sum / 36.0, lo, hi, pts])
	return out

func _px(p: Vector3) -> Vector2:
	var o: Vector2 = game.fp_world.screen_origin(game.current_screen)
	return Vector2(p.x / SCALE + 320.0, p.z / SCALE + 200.0) + o

func _sweep(number: int, vision: int) -> void:
	await _settle(number, vision)
	var fw = game.fp_world
	for id in game.entities.keys():
		if int(id) == 1: continue
		var e: Dictionary = game.entities[id]
		var path: String = fw.frame_path(e)
		if not _is_fence_art(path): continue
		var node: Node3D = game.visuals.get(id)
		if node == null: continue
		var kind := "none"
		if node.get_node_or_null("Fence") != null: kind = "solid"
		if node.get_node_or_null("Model") is Sprite3D: kind = "card"
		var body := node.get_node_or_null("HitBody")
		var hit := "none"
		if body is StaticBody3D:
			var box: BoxShape3D = ((body as StaticBody3D).get_child(0) as CollisionShape3D).shape as BoxShape3D
			hit = "%d/%.3f,%.3f" % [(body as StaticBody3D).collision_layer, box.size.x, box.size.z]
		var rect: Rect2 = fw.hard_rect(e)
		var why := "-"
		if node.has_meta("seam_hidden"): why = "seam"
		if node.has_meta("ground_painted"): why = "ground"
		print("FENCE %d %d %s kind=%s hit=%s hard=%d type=%d box=%.3f,%.3f why=%s" % [number, int(e.get("index", -1)), path.get_file(), kind, hit, int(e.get("hard", 0)), int(e.get("type", 1)), maxf(0.2, rect.size.x * SCALE), maxf(0.2, rect.size.y * SCALE), why])
	# Every post and bar of the scene (the node's own meshes, whoever's they are).
	for holder in game.scene_root.find_children("Fence", "Node3D", true, false):
		for c in holder.get_children():
			if not (c is MeshInstance3D): continue
			var boxes := _boxes(c as MeshInstance3D)
			for b in boxes:
				var lo: Vector3 = b[1]
				var hi: Vector3 = b[2]
				if c.name == "Posts":
					var centre := _px(b[0])
					print("POST %d %.2f %.2f %.2f %.2f %.2f" % [number, centre.x, centre.y, (hi.x - lo.x) / SCALE, (hi.z - lo.z) / SCALE, (hi.y - lo.y) / SCALE])
				elif c.name == "Rails":
					var pts: Array = b[3]
					var e0 := Vector3.ZERO
					var e1 := Vector3.ZERO
					for i in 4:
						e0 += pts[24 + [0, 1, 2, 5][i]] / 4.0 # a quad's corners are vertices 0, 1, 2 and 5 of its 6
						e1 += pts[30 + [0, 1, 2, 5][i]] / 4.0
					var a := _px(e0)
					var z := _px(e1)
					print("BAR %d %.2f %.2f %.2f %.2f" % [number, a.x, a.y, z.x, z.y])

func _shoot(x: float, y: float, yaw: float, pitch: float) -> Image:
	game.entities[1].x = x
	game.entities[1].y = y
	game.fps_yaw = yaw
	game.fps_pitch = pitch
	game._sync_fps_camera()
	for id in game.entities.keys(): game._update_visual(id)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	return img

# A fence's axis: the line along its posts (a card: along its x axis), two points in world metres.
func _axis(node: Node3D) -> Array:
	var fence := node.get_node_or_null("Fence")
	if fence != null:
		for c in fence.get_children():
			if c is MeshInstance3D and c.name == "Posts":
				var boxes := _boxes(c as MeshInstance3D)
				if boxes.size() >= 2: return [boxes[0][0], boxes[boxes.size() - 1][0]]
	var model := node.get_node_or_null("Model")
	if model is Sprite3D:
		var t: Transform3D = (model as Sprite3D).global_transform
		return [t.origin - t.basis.x * 1.0, t.origin + t.basis.x * 1.0]
	return []

func _render() -> void:
	var fw = game.fp_world
	await _settle(407, 0)
	if fw.light != null: fw.light.shadow_enabled = false
	for id in game.entities.keys():
		if int(id) == 1: continue
		var e: Dictionary = game.entities[id]
		if not _is_fence_art(fw.frame_path(e)) or int(e.get("x", 0)) != 230 or int(e.get("y", 0)) != 142: continue
		var node: Node3D = game.visuals[id]
		var axis := _axis(node)
		if axis.is_empty():
			print("AXIS no geometry")
			continue
		var a: Vector3 = axis[0]
		var b: Vector3 = axis[1]
		# The card's axis is its own x axis through the hotspot; the posts' is their line. Along it, 1.5 m before the left end.
		var dir := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
		var yaw := atan2(-dir.x, -dir.z)
		var counts: Array = []
		for side in [0.0, 1.5]:
			var cam: Vector3 = a - dir * 1.5 + Vector3(-dir.z, 0, dir.x) * side
			var x: float = cam.x / SCALE + 320.0
			var y: float = cam.z / SCALE + 200.0
			var saved: Variant = e.get("nodraw", 0)
			e["nodraw"] = 0
			var shown: Image = await _shoot(x, y, yaw, -0.02)
			e["nodraw"] = 1
			var hidden: Image = await _shoot(x, y, yaw, -0.02)
			e["nodraw"] = saved
			game._update_visual(id)
			var differ := 0
			for yy in shown.get_height():
				for xx in shown.get_width():
					var p := shown.get_pixel(xx, yy)
					var q := hidden.get_pixel(xx, yy)
					if absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b) > 0.06: differ += 1
			counts.append(differ)
		print("AXIS %d %s on_axis=%d side=%d" % [int(id), fw.frame_path(e).get_file(), counts[0], counts[1]])
