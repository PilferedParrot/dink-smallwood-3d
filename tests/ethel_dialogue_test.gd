extends SceneTree

const GAME := preload("res://scripts/fps_game.gd")

class EthelGame extends GAME:
	var choice_count := 0
	var agreement := 1
	func dink_call(command: String, args: Array, context: Dictionary) -> Variant:
		# Focused VM regression: deterministic menu selection and omitted delays.
		# Rendered campaign acceptance separately exercises real UI inputs.
		if command.to_lower() == "wait": return 0
		if command.to_lower() == "choice":
			choice_count += 1
			return 2 if choice_count == 1 else agreement
		return await super.dink_call(command, args, context)

var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	if not value: failures.append(message); push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game := EthelGame.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	game.vm.cancel_all()
	game.playing = false
	game.load_map(2, false)
	var ethel := 0
	for id in game.entities:
		if game.entities[id].get("script", "") == "s1-h2-o": ethel = int(id)
	check(ethel > 1, "Original Ethel actor exists")
	for agreement in [1, 2]:
		game.vm.globals["old_womans_duck"] = 0
		game.vm.globals["story"] = 1
		game.choice_count = 0
		game.agreement = agreement
		await game.vm.run("s1-h2-o", "talk", ethel)
		check(int(game.vm.globals.get("old_womans_duck", 0)) == 1, "Ethel agreement %d starts the original quest" % agreement)
		check(not game.entities[1].get("frozen", false), "Ethel agreement %d releases Dink after dialogue" % agreement)
		check(not game.entities[ethel].get("frozen", false), "Ethel agreement %d releases Ethel after dialogue" % agreement)
		check(game.choice_count == 2, "Request and agreement each use the original choice")
	game.vm.cancel_all()
	game.queue_free()
	await process_frame
	if failures.is_empty(): print("ETHEL DIALOGUE PASS")
	quit(0 if failures.is_empty() else 1)
