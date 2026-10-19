extends SceneTree
const GAME := preload("res://scripts/fps_game.gd")
var game
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func _run() -> void:
	game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	await game._new_game()
	game.vm.cancel_all()
	game.vm.globals["story"] = 1
	game.load_map(1,false)
	game.vm.cancel_all()
	game.ui.close_menu()
	game.set_physics_process(false)
	game.test_mode = false
	var mother := 0
	for id in game.entities:
		if str(game.entities[id].get("script","")) == "s1-h1-m": mother = int(id)
	check(mother != 0 and game.visuals.has(mother), "Fixture uses the original Mother actor")
	if mother != 0 and game.visuals.has(mother):
		for size in [Vector2i(1280,800),Vector2i(1920,1080)]:
			root.size = size
			await process_frame
			game.entities[1].x = 202.0
			game.entities[1].y = 250.0
			game.fps_yaw = 0.0
			game.fps_pitch = 0.0
			game._sync_fps_camera()
			# FreeDink109.6 brain_keyboard.cpp:216-241: text alone does not
			# freeze input. Free speech must preserve the player's own viewpoint.
			var free_view: Transform3D = game.camera.global_transform
			game._dialogue("An unfrozen Mother line",mother,{})
			for _i in 4: await process_frame
			check(game.camera.global_transform.is_equal_approx(free_view) and not game.ui.modal, "Unfrozen Mother speech preserves the player camera")
			game.ui.cancel_speech()
			for _i in 3: await process_frame
			# S1-H1-M.main:57 freezes Dink before the actual pig-feed request;
			# freeze is explicit (dinkc_bindings.cpp:552-559). Keep the independent
			# floor/top projection checks for that framed presentation.
			await game.dink_call("freeze",[1],{})
			game._dialogue("Dink, would you go feed the pigs?",mother,{})
			for _i in 8: await process_frame
			# Independent projection contract, deliberately not the fitter's
			# computed rectangle: the actor's source floor and drawn top must be
			# on screen above the actual card, even when the head alone fits.
			var visual: Node3D = game.visuals[mother]
			var foot: Vector3 = visual.global_position
			var head: Vector3 = foot+Vector3.UP*float(visual.get_meta("height",1.65))
			var projected_foot: Vector2 = game.camera.unproject_position(foot)
			var projected_head: Vector2 = game.camera.unproject_position(head)
			var top: float = game.ui.panel.get_global_rect().position.y
			check(not game.camera.is_position_behind(foot) and projected_foot.y < top,
				"Speaker's floor is above the actual dialogue card: %s foot=%s card_top=%s" % [size,projected_foot,top])
			check(not game.camera.is_position_behind(head) and projected_head.y >= 0,
				"Speaker's drawn top remains in the viewport")
			game.ui.cancel_speech()
			for _i in 4: await process_frame
			await game.dink_call("unfreeze",[1],{})
	game.vm.cancel_all()
	game.queue_free()
	await process_frame
	print("SPEAKER OCCLUSION CONTRACT PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
