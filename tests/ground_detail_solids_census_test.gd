extends SceneTree
# Merge census (INTEGRATE-2): make_entity routes ground_detail before solids.handles. The order only matters if
# one source entity is claimed by both; assert that set is empty over every screen, indoors and outdoors.
const GAME := preload("res://scripts/fps_game.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	game.vm.cancel_all()
	var w = game.fp_world
	var total := 0
	var details := 0
	var both: Array[String] = []
	for sid in game.world.screens:
		var screen := int(sid)
		for e in game.world.screens[sid].get("sprites", []):
			total += 1
			if w.model_key(e) != "ground_detail": continue
			details += 1
			# handles() reads the current screen only for is_inside/walls_fitted; test the claim for this screen.
			# Stronger than per-screen: with no fit for the path, handles() is false indoors and outdoors alike.
			if not w.solids.fit_of(w.frame_path(e)).is_empty(): both.append("fit %s" % w.frame_path(e))
			if w.solids.handles(e, screen): both.append("%s %s" % [sid, JSON.stringify(e)])
	print("CENSUS entities=%d ground_detail=%d both=%d" % [total, details, both.size()])
	for b in both: print("BOTH ", b)
	print("GROUND DETAIL SOLIDS CENSUS ", "PASS" if both.is_empty() and details > 0 else "FAIL")
	quit(0 if both.is_empty() and details > 0 else 1)
