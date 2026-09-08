extends SceneTree

const GAME := preload("res://scripts/fps_game.gd")
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	# Focused fixture: create a nut using the same host calls as S1-NTREE.
	# The continuous route separately earns it by hitting the actual tree.
	var game := GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	game.vm.cancel_all()
	game.set_physics_process(false)
	game.vm.globals["story"] = 2
	game.vm.globals["nuttree"] = 0
	game.entities[1]["x"] = 508.0
	game.entities[1]["y"] = 180.0
	game.load_map(474, false)
	game.ui.close_menu()
	game.playing = true
	game.warp_cooldown = 0.0
	game.fps_yaw = 0.0
	game.fps_pitch = 0.0
	game._sync_fps_camera()
	var nut: int = await game.dink_call("create_sprite", [508, 170, 0, 421, 23], {})
	await game.dink_call("sp_script", [nut, "s1-nut"], {})
	await physics_frame
	# Let the ordinary visual update apply the newly attached pickup script's
	# collision layer before movement, as it does while the real nut falls.
	game._physics_process(0.016)
	await physics_frame
	await process_frame
	check(int(game.entities[nut].get("touch_damage", 0)) == -1, "Original S1-NUT main enables the negative touch trigger")
	check(int(game.vm.globals.nuttree) == 0, "Nut startup alone cannot complete the quest")
	Input.action_press("up")
	game._physics_process(0.04)
	Input.action_release("up")
	await process_frame
	check(game._position2(1).y < 180, "Actual movement input approaches the nut")
	check(int(game.vm.globals.nuttree) == 1 and int(game.vm.globals.story) == 3, "Touch executes the original nut progression")
	check(game.items.any(func(item): return item.script == "item-nut"), "Touch grants the original Nut item")
	check(int(game.entities[nut].active) == 0, "Picked-up runtime nut disappears")
	check("I picked up a nut!" in game.dialogue_log, "Original pickup notification executes")
	game.vm.cancel_all()
	game.queue_free()
	await process_frame
	if failures.is_empty(): print("NUT PICKUP PASS")
	quit(0 if failures.is_empty() else 1)
