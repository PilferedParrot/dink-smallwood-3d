extends SceneTree

const GAME := preload("res://scripts/fps_game.gd")

class SearchGame extends GAME:
	var rolls := 0
	var hiding := 1
	var visual_builds: Dictionary = {}
	func _create_visual(id: int) -> void:
		visual_builds[id] = int(visual_builds.get(id, 0)) + 1
		super._create_visual(id)
	func dink_call(command: String, args: Array, context: Dictionary) -> Variant:
		if command.to_lower() == "random":
			rolls += 1
			return hiding
		return await super.dink_call(command, args, context)

var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	if not value: failures.append(message); push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	# Focused setup: select the original request state and control random rolls.
	# Full campaign acceptance separately earns this state through real inputs.
	var game := SearchGame.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	game.vm.cancel_all()
	game.playing = false
	game.vm.globals["old_womans_duck"] = 1
	game.vm.globals["vision"] = 0
	game.load_map(440)
	await process_frame
	check(game.world.screens["440"].script == "findduck", "Imported map retains FINDDUCK script")
	check(game.rolls == 1, "Screen main runs exactly once")
	check(int(game.vm.globals.get("vision", 0)) == 2, "Original search script selects duck vision")
	check(game.entities.values().any(func(e): return str(e.get("script", "")) == "s1-oldd"), "Duck exists on the same entry that selected vision")
	game.vm.cancel_all()
	game.rolls = 0
	game.hiding = 2
	game.load_map(441)
	await process_frame
	check(game.rolls == 2, "Unsuccessful search executes its two original random calls once")
	check(not game.entities.values().any(func(e): return str(e.get("script", "")) == "s1-oldd"), "Unsuccessful search keeps duck hidden")
	game.vm.cancel_all()
	game.rolls = 0
	game.load_map(440, false)
	await process_frame
	check(game.rolls == 0, "Save reconstruction and focused setup skip startup when requested")
	game.vm.cancel_all()
	game.rolls = 0
	game.hiding = 1
	game.visual_builds.clear()
	game.vm.globals["little_girl"] = 0
	game.vm.globals["story"] = 1
	game.load_map(408)
	await process_frame
	check(game.rolls == 2, "Gate roll and runtime girl's main each run once")
	check(game.entities.values().any(func(e): return str(e.get("script", "")) == "s1-lg"), "Original gate script creates its runtime actor")
	check(game.visual_builds.values().all(func(count): return count == 1), "Screen-created visuals are not duplicated during map construction")
	game.vm.cancel_all()
	game.queue_free()
	await process_frame
	if failures.is_empty(): print("SCREEN STARTUP PASS")
	quit(0 if failures.is_empty() else 1)
