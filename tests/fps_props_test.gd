extends SceneTree
# The small props stand solid (docs/DIRECTION.md, "The small props are solid"). A prop sprite fitted by tools/prop_fit.py
# (prototype/props.json) is built by scripts/prop_solids.gd from its own pixels; it was a camera-facing billboard (food,
# barrels, cups ...) or a fixed card seen edge-on from the side (the pig-feed sack: Items/Paper "is a sign"). Run by
# tests/test_fps_props.py:
#
#   --classify    (headless) load the listed screens as the game loads them and print one line per sprite the fits cover:
#                 "PROP screen index path solid|billboard|hidden|painted class width depth height back" (metres: the model's extent
#                 across, along the original camera's depth, and up, in the entity's frame; back = how far its back stands
#                 behind the source hardbox's back plus the distance the player keeps (game.gd: 4 px), in px: > 0 would put
#                 the camera inside the prop when it stands against the back), and "OTHER screen index path kind" for
#                 sprites of the same folders the fits do not cover (the tools, the hearts: still billboards).
# Verdict: written 2026-10-07 (Sonnet 5.5 subagent).
const GAME = preload("res://scripts/fps_game.gd")
const SCALE := 0.025
const SCREENS := [1, 439, 499, 274, 35, 442, 184, 3, 539]
var game
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	await game._new_game()
	await create_timer(1.0).timeout
	for s in SCREENS: await _classify(s)
	await _animate()
	print("FPS PROPS PASS")
	quit(0)

func _load(screen: int) -> void:
	game.vm.cancel_all()
	game.vm.globals["vision"] = 0
	game.load_map(screen, false)
	await create_timer(0.6).timeout
	game.vm.cancel_all()
	game.playing = false

# A barrel breaks frame by frame (barel-01 whole, 03-06 splinters on the ground): the solid follows the frame the sequence is at.
func _animate() -> void:
	await _load(439)
	for id in game.entities.keys():
		var e: Dictionary = game.entities[id]
		if id == 1 or not game.fp_world.frame_path(e).ends_with("barel-01.png"): continue
		var node: Node3D = game.visuals[id]
		if not node.has_meta("prop_path"): continue # a copy the seam rule hides, or painted into the ground
		var seen: Array = []
		for frame in [1, 3, 1]:
			if int(e.get("seq", 0)) == 0: e["pframe"] = frame # a still sprite shows its pseq/pframe
			else: e["frame"] = frame
			game._update_visual(id)
			seen.append(str(node.get_meta("prop_path", "")).get_file() + ":" + ("body" if node.get_node_or_null("HitBody") != null else "nobody"))
		print("ANIM ", id, " ", " ".join(seen))
		return
	print("ANIM none")

func _classify(screen: int) -> void:
	await _load(screen)
	var world = game.fp_world
	for id in game.entities.keys():
		if id == 1: continue
		var e: Dictionary = game.entities[id]
		var path: String = world.frame_path(e)
		var node: Node3D = game.visuals.get(id)
		if node == null or not is_instance_valid(node): continue
		var index := int(e.get("index", -1))
		if world.props.has(path):
			if node.has_meta("seam_hidden"):
				print("PROP ", screen, " ", index, " ", path, " hidden ", world.props.class_of(path), " 0 0 0 0")
				continue
			var model := node.get_node_or_null("Model")
			var kind := "painted" if node.has_meta("ground_painted") else "billboard" # type 0: painted into the ground, as the original draws it
			var w := 0.0
			var d := 0.0
			var h := 0.0
			var back := 0.0
			if model != null and not (model is Sprite3D) and node.has_meta("prop_path"):
				kind = "solid"
				var box := AABB()
				var first := true
				for c in model.get_children():
					if not c is MeshInstance3D: continue
					var b: AABB = model.transform * (c as MeshInstance3D).get_aabb()
					box = b if first else box.merge(b)
					first = false
				w = box.size.x
				d = box.size.z
				h = box.size.y
				if int(e.get("hard", 0)) == 0 and world.props.class_of(path) != "flat" and not node.has_meta("prop_pushed"):
					var rect: Rect2 = world.hard_rect(e)
					var behind := (box.position.z / SCALE) - (rect.position.y - float(e.get("y", 0))) # px the back stands behind the hardbox's back
					var ahead := ((box.position.z + box.size.z) / SCALE) - (rect.end.y - float(e.get("y", 0)))
					back = maxf(-behind, ahead) - 4.0
			print("PROP ", screen, " ", index, " ", path, " ", kind, " ", world.props.class_of(path), " ", snappedf(w, 0.001), " ", snappedf(d, 0.001), " ", snappedf(h, 0.001), " ", snappedf(back, 0.01))
		elif "/graphics/items/" in path.to_lower() or "/bonuses/" in path.to_lower():
			print("OTHER ", screen, " ", index, " ", path, " ", "billboard" if (node.get_node_or_null("Model") is Sprite3D) else "other")
