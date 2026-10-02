extends SceneTree
# Bridges are decks on the water and railings, not loose planks (docs/DIRECTION.md, tenth pass, unit E). The art
# draws two kinds of thing (fp_world.gd bridge_part): a DECK (struct/Bridge brdge-01, 02, 03, 05, 06, 08, 10, and the
# stone bridge landm-04..06) lies on the water, so it is painted into its screen's ground as a background sprite is;
# a RAILING (brdge-04, 07, 09, 11) stands as a fixed card in the plane it was drawn in. Two parts, run by
# tests/test_fps_bridges.py:
#
#   --sweep    (headless) every sprite of the map whose art is a bridge, in every story layer, built the way a scene
#              builds it: "BRIDGE screen index vision path painted=0|1 in_ground=0|1 card=none|fixed|billboard|model".
#              painted: the entity's node is flagged ground_painted; in_ground: the sprite is among the screen's
#              background_sprites (what ground_texture paints); card: what the node holds as its "Model".
#   --render   (rendered, under xvfb, Dummy audio) the pixel check: from 448's bridge, looking along it, the deck is
#              continuous down the middle of the picture; where the Blender planks floated, the water showed between.
# Verdict: written 2026-10-01 (Sonnet 5.5 subagent); the sweep 1 min headless, the render under 1 min under xvfb.
const GAME = preload("res://scripts/fps_game.gd")

# The pixel check: 448, the player's eye at (231, 390) looking north along the bridge (the planks at x 231, y 253-460).
const CAMERA := [448, 231.0, 390.0, 0.0, -0.1]
# The strip down the middle of the picture, as fractions of its width and height, where the deck must be unbroken.
const STRIP := [0.47, 0.53, 0.55, 0.98]

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
	for arg in OS.get_cmdline_user_args():
		if arg == "--sweep": sweep = true
		if arg == "--render": render = true
	game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	await game._new_game()
	await create_timer(1.0).timeout
	if sweep: _sweep()
	if render: await _render()
	if failures.is_empty():
		print("FPS BRIDGES PASS")
		quit(0)
	else:
		print("FPS BRIDGES FAIL ", failures.size())
		quit(1)

# Whether a sprite's art is a bridge (the folder struct/Bridge, or landm-04..06 of struct/Landmark): by the art's
# path, as the test reads it, not by the game's model keys.
func _is_bridge_art(path: String) -> bool:
	var p := path.to_lower()
	if "/struct/bridge/" in p: return true
	if "/struct/landmark/" in p:
		var file := p.get_file()
		return file.begins_with("landm-") and int(file.trim_prefix("landm-")) in [4, 5, 6]
	return false

func _sweep() -> void:
	var fw = game.fp_world
	var scratch := Node3D.new()
	root.add_child(scratch)
	var lines := 0
	for number in game.world.screens:
		var n := int(number)
		game.current_screen = n
		game.generation += 1
		fw.interior = fw.is_inside(n)
		for vision in [0, 1, 2]:
			var in_ground := {}
			for e in fw.background_sprites(n, vision): in_ground[int(e.get("index", -1))] = true
			for source in fw.drawn_sprites(n, vision):
				var e: Dictionary = source.duplicate()
				if not _is_bridge_art(fw.frame_path(e)): continue
				var node: Node3D = fw.make_entity(e, 0, scratch, false, n)
				var card := "none"
				var model := node.get_node_or_null("Model")
				if model is Sprite3D: card = "fixed" if (model as Sprite3D).billboard == BaseMaterial3D.BILLBOARD_DISABLED else "billboard"
				elif model != null: card = "model"
				# A near railing stands as a card in the plane it was drawn in with its posts as prisms (bridge_rails.gd: a "Rail"
				# child of meshes, no Sprite3D). A deck, painted into the ground, keeps no card of its own: its railing is its own node.
				elif not node.has_meta("ground_painted") and node.get_node_or_null("Rail") != null: card = "fixed"
				print("BRIDGE %d %d %d %s painted=%d in_ground=%d card=%s" % [n, int(e.get("index", -1)), vision, fw.frame_path(e),
					1 if node.has_meta("ground_painted") else 0, 1 if in_ground.has(int(e.get("index", -1))) else 0, card])
				lines += 1
				scratch.remove_child(node)
				node.free()
	scratch.free()
	print("BRIDGES ", lines)

# --- the pixel check ----------------------------------------------------------------------------------------
func _render() -> void:
	game.vm.cancel_all()
	game.vm.globals["vision"] = 0
	game.load_map(CAMERA[0], false)
	await create_timer(0.6).timeout
	game.vm.cancel_all()
	game.playing = false
	game.ui.close_menu()
	game.ui.toast.text = ""
	game.ui.visible = false
	game.entities[1].x = CAMERA[1]
	game.entities[1].y = CAMERA[2]
	game.fps_yaw = CAMERA[3]
	game.fps_pitch = CAMERA[4]
	game._sync_fps_camera()
	for model in [game.fps_viewmodel, game.fps_hand]:
		if is_instance_valid(model): model.visible = false
	for id in game.entities.keys(): game._update_visual(id)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var w := img.get_width()
	var h := img.get_height()
	var x0 := int(STRIP[0] * w)
	var x1 := int(STRIP[1] * w)
	var y0 := int(STRIP[2] * h)
	var y1 := int(STRIP[3] * h)
	var water := 0
	var deck := 0
	var total := 0
	var water_rows := 0 # rows of the strip that are mostly water: a gap in the deck
	for y in range(y0, y1):
		var row_water := 0
		for x in range(x0, x1):
			var c := img.get_pixel(x, y)
			var r := int(c.r * 255.0)
			var g := int(c.g * 255.0)
			var b := int(c.b * 255.0)
			total += 1
			if b > r + 40 and b > g + 20:
				water += 1
				row_water += 1
			elif r > b + 25 and r >= g:
				deck += 1
		if row_water * 2 > x1 - x0: water_rows += 1
	print("PIXELS size %dx%d strip %dx%d water %.4f deck %.4f water_rows %d of %d" % [w, h, x1 - x0, y1 - y0,
		float(water) / total, float(deck) / total, water_rows, y1 - y0])
