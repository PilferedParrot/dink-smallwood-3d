extends SceneTree
# The landmarks stand solid (docs/DIRECTION.md, "The landmarks are solid"): the well (struct/Landmark landm-01..03: a stone base, two
# posts and a roof) and the save machine (inter/Save: a grating floor and an arched wall) were camera-facing billboards, the same
# picture from every side. Fitted by tools/landmark_fit.py (prototype/landmarks.json), built by scripts/prop_solids.gd from their own
# pixels. Run by tests/test_fps_landmarks.py (headless): load screen 408, which holds both, and print one line per landmark:
#   "LANDMARK index path kind class width depth height sil_ns sil_ew layer"
# kind: solid (a mesh model standing on the entity) or billboard (a Sprite3D); width, depth, height: metres, the model's extent
# across, along the camera's depth and up; sil_ns / sil_ew: the area (m^2) the model covers seen from the south and from the east,
# its vertices taken in bands of 0.1 m of height above the floor; layer: the collision layer of its ray body (0 = none, 2 = it has a script).
# Verdict: written 2026-10-08 (Sonnet 5.5 subagent).
const GAME = preload("res://scripts/fps_game.gd")
var game

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	await game._new_game()
	await create_timer(1.0).timeout
	game.vm.cancel_all()
	game.vm.globals["vision"] = 0
	game.load_map(408, false)
	await create_timer(0.6).timeout
	game.vm.cancel_all()
	game.playing = false
	var world = game.fp_world
	for id in game.entities.keys():
		if id == 1: continue
		var e: Dictionary = game.entities[id]
		var path: String = world.frame_path(e)
		var node: Node3D = game.visuals.get(id)
		if node == null or not is_instance_valid(node): continue
		var low := path.to_lower()
		if not ("/landmark/landm-0" in low or "/inter/save/" in low): continue
		var model := node.get_node_or_null("Model")
		if model == null: continue
		var kind := "billboard" if model is Sprite3D else "solid"
		var cls: String = world.props.class_of(path)
		var xs: Array = []
		var zs: Array = []
		var ys: Array = []
		var pts := PackedVector3Array()
		for c in model.get_children():
			if not c is MeshInstance3D: continue
			var mesh: Mesh = (c as MeshInstance3D).mesh
			for s in mesh.get_surface_count():
				for v in mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]: pts.append(model.transform*(v as Vector3))
		var lo := Vector3(1e9, 1e9, 1e9)
		var hi := -lo
		for p in pts:
			lo = lo.min(p)
			hi = hi.max(p)
		var bands := {}
		for p in pts:
			var b := int((p.y - lo.y - 0.1)/0.1)
			if b < 0: continue
			var r: Array = bands.get(b, [1e9, -1e9, 1e9, -1e9])
			r[0] = minf(r[0], p.x)
			r[1] = maxf(r[1], p.x)
			r[2] = minf(r[2], p.z)
			r[3] = maxf(r[3], p.z)
			bands[b] = r
		var ns := 0.0
		var ew := 0.0
		for b in bands:
			ns += (bands[b][1] - bands[b][0])*0.1
			ew += (bands[b][3] - bands[b][2])*0.1
		var body: Node = node.get_node_or_null("HitBody")
		var layer := int((body as CollisionObject3D).collision_layer) if body is CollisionObject3D else 0
		var size := hi - lo if pts.size() > 0 else Vector3.ZERO
		print("LANDMARK ", int(e.get("index", -1)), " ", path, " ", kind, " ", cls, " ", snappedf(size.x, 0.001), " ", snappedf(size.z, 0.001), " ",
			snappedf(size.y, 0.001), " ", snappedf(ns, 0.001), " ", snappedf(ew, 0.001), " ", layer, " ", str(e.get("script", "")).length() > 0)
	# The well's fitted roof, whether or not the well stands as one in the game: the compound's third surface (base, posts, roof; then the shaft's floor) is the roof. A gable is
	# higher along its ridge than at its eaves; the flat slab it replaced was one thickness (0.14 m) from end to end.
	var wp := "assets/graphics/struct/Landmark/landm-01.png"
	if world.props.has(wp):
		var roof: Mesh = (world.props.surfaces(wp)[2])[0]
		var rv: PackedVector3Array = roof.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var ymin := 1e9
		var ymax := -1e9
		var all := Vector2.ZERO
		for v in rv:
			ymin = minf(ymin, v.y)
			ymax = maxf(ymax, v.y)
			all += Vector2(v.x, v.z)/rv.size()
		var ridge := Vector2.ZERO
		var eave := Vector2.ZERO
		var nr := 0
		var ne := 0
		for v in rv:
			if v.y > ymax - 0.05:
				ridge += Vector2(v.x, v.z)
				nr += 1
			elif v.y < ymin + 0.2:
				eave += Vector2(v.x, v.z)
				ne += 1
		print("WELLROOF ", snappedf(ymax - ymin, 0.001), " ", snappedf((ridge/maxf(nr, 1) - all).length(), 0.001), " ", snappedf((eave/maxf(ne, 1) - all).length(), 0.001),
			" ", rv.size())
	print("FPS LANDMARKS PASS")
	quit(0)
