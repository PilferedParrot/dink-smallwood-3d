extends SceneTree

const GAME := preload("res://scripts/fps_game.gd")

class AftermathGame extends GAME:
	var aftermath_tail: Array[String] = []
	func dink_call(command: String, args: Array, context: Dictionary) -> Variant:
		if context.get("script", "") == "s1-h1-o" and command in ["fade_down", "force_vision", "fade_up", "unfreeze", "kill_this_task"]:
			aftermath_tail.append(command)
		return await super.dink_call(command, args, context)

var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	# Explicit script fixture: the continuous campaign separately earns the nut.
	# Test-mode dialogue and accelerated time keep this host regression bounded.
	var game := AftermathGame.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	game.vm.cancel_all()
	game.load_map(1, false)
	game.entities[1]["x"] = 321.0
	game.entities[1]["y"] = 398.0
	game.entities[1]["frozen"] = true
	game.warp_cooldown = 0.0
	game._transitions()
	check(game.current_screen == 1, "Ordinary transition checks preserve cutscene freeze")
	# Normal-rate small steps reproduce the entrance overlap that accelerated
	# movement can skip. Moving away must not bounce back out after the cooldown.
	game.entities[1]["x"] = 323.0
	game.entities[1]["y"] = 390.0
	game.ui.close_menu()
	game.playing = true
	await game._script_move(1, 8, 380.0, 1)
	check(game.current_screen == 1, "Normal-rate scripted entrance moves away from the exit without warping")
	check(game.entities[1].get("frozen", false), "Moving into the room retains cutscene freeze")
	Engine.time_scale = 8.0
	game.vm.globals["story"] = 3
	game.vm.globals["nuttree"] = 1
	game.vm.globals["old_womans_duck"] = 4
	game.entities[1]["x"] = 323.0
	game.entities[1]["y"] = 390.0
	game.ui.close_menu()
	game.playing = true
	game.load_map(1)
	await create_timer(55.0).timeout
	check(game.current_screen == 439, "Original frozen evacuation reaches outdoor doorway")
	check(int(game.vm.globals.get("story", 0)) == 5, "Original neighbor aftermath reaches story 5")
	check(int(game.vm.globals.get("vision", 0)) == 2, "Aftermath selects ruined-home vision")
	check(not game.entities[1].get("frozen", false), "Aftermath releases player controls")
	var lines := ["Mother noooooo!", "Mother, you can't die, nooo I  I ...",
		"never knew how much I really cared about you", "until now.",
		"Ahh, too much smoke .... gotta get out ...", "Dink!!!",
		"I .. I couldn't save her", "I was too late.", "It's not your fault Dink.",
		"There was nothing you could do..", "Don't blame yourself kid."]
	check(game.dialogue_log == lines, "All original interior and neighbor lines execute in order")
	check(game.aftermath_tail == ["fade_down", "force_vision", "fade_up", "unfreeze", "kill_this_task"], "Original aftermath completes beyond its early story flag and vision reload")
	check(game.vm._live_tasks.is_empty(), "Aftermath script has finished")
	var before: Vector2 = game._position2(1)
	Input.action_press("down")
	await create_timer(0.3).timeout
	Input.action_release("down")
	check(game._position2(1).distance_to(before) > 1.0, "Actual movement input works after aftermath")
	game.vm.cancel_all()
	game.queue_free()
	await process_frame
	if failures.is_empty(): print("ALKTREE AFTERMATH PASS")
	quit(0 if failures.is_empty() else 1)
