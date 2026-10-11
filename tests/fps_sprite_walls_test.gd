extends SceneTree
# Bounded runtime contract for the source-fitted stone family. This fixture
# does not load campaign progression or certify rendered appearance.

const WALLS := preload("res://scripts/sprite_walls.gd")
const GAME := preload("res://scripts/fps_game.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var walls = WALLS.new()
	var fit: Dictionary = walls.get_fit(712)
	check(not fit.is_empty(), "712 fit loaded")
	check(walls.data["screens"].size() == 14, "14 structural screens")
	check(int(walls.data["shared_height_px"]) == 74, "one art-derived shared height")
	var owner: Dictionary = fit["owners"][0]
	var e := {"index": owner["index"], "seq": owner["seq"], "frame": owner["frame"],
		"path": owner["path"], "type": 1, "size": 100, "vision": 0, "active": 1,
		"hard": owner["hard"]}
	check(walls.owns(e, 712), "exact source owner matched")
	var changed := e.duplicate()
	changed["path"] = "assets/graphics/inside/stnwalls/stonw-27.png"
	check(not walls.owns(changed, 712), "path mismatch rejected")
	changed = e.duplicate()
	changed["index"] = 999
	check(not walls.owns(changed, 712), "index mismatch rejected")
	changed = e.duplicate()
	changed["active"] = 0
	check(not walls.owns(changed, 712), "inactive source rejected")
	changed = e.duplicate()
	changed["size"] = 90
	check(not walls.owns(changed, 712), "resized source rejected")
	check(not walls.get_fit(244).has("owners"), "ivy remains outside structural family")
	check(not walls.get_fit(536).has("owners"), "piers remain outside structural family")
	check(not walls.get_fit(625).has("owners"), "open arch remains outside structural family")
	for screen_key in walls.data["screens"]:
		var screen := int(screen_key)
		var item: Dictionary = walls.get_fit(screen)
		check(not item["floor_runs"].is_empty(), "%d has floor" % screen)
		for row in item["floor_runs"]:
			check(int(row[1]) >= 20 and int(row[2]) <= 620 and int(row[0]) >= 0 and int(row[0]) < 400,
				"%d floor clipped to playable rect" % screen)
		for o in item["owners"]:
			check(int(o["frame"]) in [1,2,3,4,5,6,7,8,9,10,15], "%d body frame only" % screen)
			check(not o["path"].ends_with("-16.png"), "%d arch deferred" % screen)
			check(not o["path"].ends_with("-27.png"), "%d pier deferred" % screen)
			check(not o["path"].ends_with("-28.png"), "%d pier deferred" % screen)
	# Locate a floor edge with a clean normal approach. Exact floor cells block;
	# band traversal from within the band permits escape and parallel motion.
	var mask := _mask(fit["floor_runs"])
	var found := false
	for y in range(15, 385):
		if found: break
		for x in range(30, 610):
			if mask[y * 640 + x] != 0 or mask[y * 640 + x + 1] == 0: continue
			if x < 8 or mask[y * 640 + x - 6] != 0: continue
			var solid := Vector2(x + 1.5, y + 0.5)
			var band := Vector2(x - 0.5, y + 0.5)
			var outside := Vector2(x - 4.5, y + 0.5)
			check(walls.blocked(solid, Vector2.INF, 712), "occupied pixel cell blocks")
			check(walls.blocked(band, Vector2.INF, 712), "4px clearance band blocks entry")
			check(not walls.blocked(outside, band, 712), "band allows retreat")
			check(walls.blocked(solid, band, 712), "band never permits deeper entry")
			found = true
			break
	check(found, "found independent edge approach")
	var root_node := Node3D.new()
	root.add_child(root_node)
	root_node.position = Vector3(1, 0, 2)
	walls.add(root_node, e, 712, 17, true)
	check(root_node.get_child_count() == 1, "one composed wall group created")
	if root_node.get_child_count() == 1:
		var group := root_node.get_child(0)
		check(group.position.is_equal_approx(Vector3(-8.5, 0, -7)), "group offset aligns screen basis")
		var shell := group.get_node_or_null("SourceWallShell") as MeshInstance3D
		check(shell != null and shell.mesh.get_surface_count() == 2, "seen and inferred source surfaces")
		check(group.get_node_or_null("StoneWallRayBody") != null, "ray collision body built")
	walls.add(root_node, e, 712, 18, true)
	check(root_node.get_child_count() == 1, "screen group built once")
	walls.reset()
	walls.add(root_node, e, 712, 19, false)
	check(root_node.get_child_count() == 2, "new scene registry permits rebuild")
	var short_fit: Dictionary = walls.get_fit(388)
	check((short_fit["owners"] as Array).any(func(o): return int(o["frame"]) == 6 and int(o["size"][1]) == 50),
		"short frame composes at shared wall height")
	var all_end_on: Dictionary = walls.get_fit(420)
	check(str(all_end_on["unseen_face_material"]["selection"]) == "same_family_flat_wall_other_screen",
		"all end-on screen names inferred donor")
	walls.reset()
	var end_owner: Dictionary = all_end_on["owners"][0]
	var end_e := {"index": end_owner["index"], "seq": end_owner["seq"], "frame": end_owner["frame"],
		"path": end_owner["path"], "type": 1, "size": 100, "vision": 0, "active": 1}
	var end_node := Node3D.new()
	root.add_child(end_node)
	walls.add(end_node, end_e, 420, 1, true)
	check(end_node.get_child_count() == 1, "end-on family uses composed mesh")
	end_node.queue_free()
	root_node.queue_free()
	var seam_walls = WALLS.new()
	seam_walls.data = {"screens":{"1":{"floor_runs":[[100,618,620]]}}}
	check(seam_walls.blocked(Vector2(22,100.5),Vector2.INF,2),"neighbor wall clearance crosses source seam")
	check(not seam_walls.blocked(Vector2(25,100.5),Vector2(22,100.5),2),"neighbor band allows retreat")
	check(not seam_walls.blocked(Vector2(619,100.5),Vector2.INF,32),"world row never wraps to screen1")
	# Exercise the integrated FPS construction for every structural screen with
	# the real source dictionaries and the host's normalized editor entities.
	# load_map(n,false) skips story progression but runs the production scene and
	# native collision setup; no synthetic path field supplies ownership.
	var game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	await game._new_game()
	await create_timer(0.2).timeout
	game.vm.cancel_all()
	var built := 0
	for screen_number in [385,386,387,388,417,420,449,450,451,452,680,681,712,713]:
		game.load_map(screen_number,false)
		await process_frame
		var real_fit: Dictionary = game.stone_walls.get_fit(screen_number)
		var source: Array = game.world.screens[str(screen_number)]["sprites"]
		var selected_indexes: Dictionary = {}
		for index in real_fit["owner_indexes"]: selected_indexes[int(index)] = true
		var matched := 0
		for raw in source:
			var is_owner := selected_indexes.has(int(raw["index"]))
			check(game.stone_walls.owns(raw,screen_number) == is_owner,
				"%d raw source owner %d" % [screen_number,int(raw["index"])])
			if not is_owner: continue
			var normalized: Dictionary = game.editor_entity(screen_number,raw)
			check(not normalized.is_empty() and game.stone_walls.owns(normalized,screen_number),
				"%d normalized host-path owner %d" % [screen_number,int(raw["index"])])
			matched += 1
		check(matched == real_fit["owners"].size(), "%d complete native owner set" % screen_number)
		var group: Node3D = game.stone_walls._built.get(screen_number)
		check(group != null and is_instance_valid(group), "%d built composed native group" % screen_number)
		if group != null and is_instance_valid(group):
			var native_shell := group.get_node_or_null("SourceWallShell") as MeshInstance3D
			check(native_shell != null and native_shell.mesh.get_surface_count() == 2,
				"%d native seen/inferred mesh" % screen_number)
			check(group.get_node_or_null("StoneWallRayBody") != null,
				"%d native ray collision" % screen_number)
			built += 1
		var row: Array = real_fit["floor_runs"][int(real_fit["floor_runs"].size()/2)]
		var floor_point := Vector2(float(row[1]) + 0.5, float(row[0]) + 0.5)
		check(game.stone_walls.blocked(floor_point,Vector2.INF,screen_number),
			"%d native fitted floor blocks" % screen_number)
		check(game._blocked(floor_point,1), "%d integrated player collision blocks" % screen_number)
	check(built == 14, "all 14 native structural groups built")
	check(game.stone_walls.blocked(Vector2(330.5,10.5),Vector2.INF,449),
		"417/449 world-art seam closes old wall-interior pocket")
	game.vm.cancel_all()
	game.queue_free()
	if failures.is_empty(): print("FPS SPRITE WALLS PASS")
	quit(0 if failures.is_empty() else 1)

func _mask(rows: Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(640 * 400)
	for row in rows:
		for x in range(int(row[1]), int(row[2])):
			out[int(row[0]) * 640 + x] = 1
	return out

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)
