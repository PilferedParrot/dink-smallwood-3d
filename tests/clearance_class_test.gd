extends SceneTree

# Unit 3, check G4: the class, not the instance. No solid is grown for any mover. For every screen of the world and every
# solid source the mover reads (sprite hardboxes, fitted footprints, RC5 stone-wall floors, firs), a point half a pixel
# outside its raw shape is free of THAT solid and a point inside it is blocked, for the player and for an NPC mover.
# (Doors are covered by fps_foyer_mapping_test and fps_indoor_arrival_door.)
# Usage: godot --headless --path game --script tests/clearance_class_test.gd

const NPC := 99999
var game
var failures: Array = []
var counts := {"screens": 0, "sprites": 0, "footprints": 0, "stone": 0, "firs": 0, "outside_probes": 0, "inside_probes": 0, "skipped_overlap": 0}

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, what: String) -> void:
	if not ok and failures.size() < 40:
		failures.append(what)
		print("FAIL ", what)
	elif not ok:
		failures.append("")

func _setup() -> void:
	game = load("res://../tests/collision_survey_host.gd").new()
	game.world = game._read_json("res://data/world.json")
	game.sequences = game._read_json("res://data/sequences.json").sequences
	game.footprints = game._read_json("res://data/footprints.json").screens
	game.vm = game.VM.new(game)
	game.vm.load_story()

func _faces(rc: Rect2) -> Array:
	var c := rc.get_center()
	return [Vector2(rc.position.x - 0.5, c.y), Vector2(rc.end.x + 0.5, c.y), Vector2(c.x, rc.position.y - 0.5), Vector2(c.x, rc.end.y + 0.5),
		rc.position - Vector2(0.5, 0.5), rc.end + Vector2(0.5, 0.5), Vector2(rc.end.x + 0.5, rc.position.y - 0.5), Vector2(rc.position.x - 0.5, rc.end.y + 0.5)]

func _sprites() -> void:
	var rects: Array = []
	for id in game.entities:
		if id == 1: continue
		var e: Dictionary = game.entities[id]
		if int(e.get("active", 1)) == 0 or int(e.get("hard", 1)) != 0 or e.get("warp") != null or game._sprite_hardbox_replaced(e): continue
		rects.append(game._hard_rect(e))
	for rc: Rect2 in rects:
		if rc.size.x < 1.0 or rc.size.y < 1.0: continue
		counts.sprites += 1
		for p: Vector2 in _faces(rc):
			if rects.any(func(r: Rect2) -> bool: return r.has_point(p)):
				counts.skipped_overlap += 1
				continue
			counts.outside_probes += 1
			for mover in [1, NPC]:
				check(game._blocking_sprite(p, mover) == 0, "screen %d: sprite box %s grown at %s for mover %d" % [game.current_screen, rc, p, mover])
		counts.inside_probes += 1
		for mover in [1, NPC]:
			check(game._blocking_sprite(rc.get_center(), mover) != 0, "screen %d: sprite box %s centre is not solid for mover %d" % [game.current_screen, rc, mover])

func _footprints() -> void:
	var polys: Array = []
	polys.append_array(game.screen_footprints)
	for key in game.footprint_sprites: polys.append_array(game.footprint_sprites[key])
	for poly: PackedVector2Array in polys:
		for i in poly.size():
			var a: Vector2 = poly[i]
			var b: Vector2 = poly[(i + 1) % poly.size()]
			if a.distance_to(b) < 3.0: continue
			var normal := Vector2(-(b - a).y, (b - a).x).normalized()
			var mid := (a + b) * 0.5
			var p := mid + normal * 0.5
			if Geometry2D.is_point_in_polygon(p, poly): p = mid - normal * 0.5
			if Geometry2D.is_point_in_polygon(p, poly): continue
			if polys.any(func(q: PackedVector2Array) -> bool: return Geometry2D.is_point_in_polygon(p, q)):
				counts.skipped_overlap += 1
				continue
			counts.footprints += 1
			counts.outside_probes += 1
			check(not game._footprint_blocked(p), "screen %d: footprint edge %s-%s grown at %s" % [game.current_screen, a, b, p])

func _stone(n: int) -> void:
	var fit: Dictionary = game.stone_walls.get_fit(n)
	if fit.is_empty(): return
	var cells := {}
	for row in fit.get("floor_runs", []):
		for x in range(int(row[1]), int(row[2])): cells[Vector2i(x, int(row[0]))] = true
	var every := 0
	for row in fit.get("floor_runs", []):
		every += 1
		if every % 4 != 0: continue
		var z := int(row[0])
		for edge in [[int(row[2]), z], [int(row[1]) - 1, z]]:
			var cell := Vector2i(edge[0], edge[1])
			if cells.has(cell) or cell.x < 22 or cell.x > 617 or z < 2 or z > 397: continue
			counts.stone += 1
			counts.outside_probes += 1
			var p := Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5)
			check(not game.stone_walls.blocked(p, Vector2.INF, n), "screen %d: stone wall grown at %s" % [n, p])
		counts.inside_probes += 1
		var inside := Vector2(float(int(row[1])) + 0.5, float(z) + 0.5)
		check(game.stone_walls.blocked(inside, Vector2.INF, n), "screen %d: stone floor cell %s is not solid" % [n, inside])

func _firs(n: int) -> void:
	var entries: Array = game.fir_collision.rectangles(n)
	var rects: Array = []
	for entry in entries:
		var r: Array = entry["rect_local_xyxy"]
		rects.append(Rect2(Vector2(float(r[0]), float(r[1])), Vector2(float(r[2]) - float(r[0]), float(r[3]) - float(r[1]))))
	for rc: Rect2 in rects:
		counts.firs += 1
		for p: Vector2 in _faces(rc):
			if rects.any(func(r: Rect2) -> bool: return r.has_point(p)):
				counts.skipped_overlap += 1
				continue
			counts.outside_probes += 1
			check(not game.fir_collision.blocked(p, Vector2.INF, n), "screen %d: fir box %s grown at %s" % [n, rc, p])
		counts.inside_probes += 1
		check(game.fir_collision.blocked(rc.get_center(), Vector2.INF, n), "screen %d: fir box %s centre is not solid" % [n, rc])

func _run() -> void:
	_setup()
	for key in game.world.screens:
		var n := int(key)
		game.load_map(n, false)
		counts.screens += 1
		_sprites()
		_footprints()
		_stone(n)
		_firs(n)
	for needed in ["sprites", "footprints", "stone", "firs"]:
		check(int(counts[needed]) >= 50, "G4 covers at least 50 %s shapes (has %d)" % [needed, int(counts[needed])])
	print("CLEARANCE CLASS ", JSON.stringify(counts), " failures=", failures.size())
	game.vm.cancel_all()
	game.free()
	if failures.is_empty(): print("CLEARANCE CLASS PASS")
	quit(0 if failures.is_empty() else 1)
