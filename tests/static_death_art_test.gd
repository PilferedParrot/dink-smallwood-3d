extends SceneTree
const GAME := preload("res://scripts/fps_game.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	game.vm.cancel_all()
	game.vm.globals["story"] = 3
	var fixtures := [[1,34],[91,21],[92,1],[94,1],[157,4],[222,4],[222,5]]
	var type_one := 0
	for pair in fixtures:
		var screen: int = int(pair[0])
		var source: Dictionary = {}
		for candidate in game.world.screens[str(screen)].sprites:
			if int(candidate.index) == int(pair[1]): source = candidate.duplicate(true)
		check(not source.is_empty(), "Source static death placement exists: %s" % [pair])
		if source.is_empty(): continue
		if int(source.type) == 1: type_one += 1
		var before := JSON.stringify(source)
		check(game.fp_world.paints_ground(source,screen), "Prone source art belongs to ground, including former upright types: %s" % [pair])
		var owners := 0
		for candidate in game.fp_world.background_sprites(screen,int(source.vision)):
			if int(candidate.get("index",candidate.get("editor_num",0))) == int(pair[1]): owners += 1
		check(owners == 1, "Exactly one ground owner for %s (got %d)" % [pair,owners])
		var holder := Node3D.new()
		root.add_child(holder)
		var visual: Node3D = game.fp_world.make_entity(source,999001,holder,true,screen)
		check(visual.get_child_count() == 0, "No extra standing card, body or shadow twin for %s" % [pair])
		check(visual.has_meta("floor_art_rect"), "Painted art retains its actual floor rectangle for camera framing")
		if visual.has_meta("floor_art_rect"):
			var rect: Rect2 = visual.get_meta("floor_art_rect")
			var frame: Dictionary = game._frame(int(source.seq),int(source.frame))
			check(is_equal_approx(rect.position.y,-float(frame.dy)*game.SCALE), "Original hotspot is preserved, including outside-frame Maiden dy59")
		check(JSON.stringify(source) == before, "Rendering preserves raw source state and hardbox semantics")
		var scripted := source.duplicate(true)
		scripted.type = 1
		scripted.script = "fixture"
		check(not game.fp_world.paints_ground(scripted,screen), "A scripted variant is not promoted to this static death class")
		var runtime := source.duplicate(true)
		runtime.type = 1
		runtime.runtime_created = true
		check(not game.fp_world.paints_ground(runtime,screen), "A runtime variant is not promoted to this editor death class")
		holder.queue_free()
	check(type_one == 3, "Inventory contains three formerly upright placements and four existing background owners")
	game.queue_free()
	await process_frame
	print("STATIC DEATH ART PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
