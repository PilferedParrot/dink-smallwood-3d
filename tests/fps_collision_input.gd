extends SceneTree

const GAME = preload("res://scripts/fps_game.gd")
var game
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func hold(key: int, frames: int) -> void:
	var event := InputEventKey.new(); event.physical_keycode=key; event.pressed=true
	Input.parse_input_event(event);Input.flush_buffered_events()
	for _i in frames: await physics_frame
	event = InputEventKey.new(); event.physical_keycode=key; event.pressed=false
	Input.parse_input_event(event);Input.flush_buffered_events()
	await physics_frame

func _run() -> void:
	game=GAME.new(); game.test_mode=true; root.add_child(game)
	await process_frame
	await game._new_game()
	game.vm.cancel_all(); game.ui.close_menu()
	# Scenario setup: a source-art barrel with a small hardbox stands on the landing
	# pixels just past each seam (a mover is a point: only a solid the arrival lands
	# in stops the crossing). The old fixed inset jumps into or through its solidity.
	# This verifies controls/collision, not the fidelity of the placed fixture.
	var cases := [
		[439,440,Vector2(618,180),Vector2(22,180),-PI/2.0],
		[440,439,Vector2(22,180),Vector2(618,180),PI/2.0],
		[439,407,Vector2(400,2),Vector2(400,397),0.0],
		[407,439,Vector2(400,398),Vector2(400,3),PI],
	]
	for fixture in cases:
		var target: int=fixture[1]
		var original: Array=game.world.screens[str(target)].sprites.duplicate(true)
		var at: Vector2=fixture[3]
		game.world.screens[str(target)].sprites.append({"index":1000,"x":at.x,"y":at.y,"seq":174,"frame":1,"hardbox":[-3,-3,3,3],"type":1,"size":100,"hard":0,"vision":0})
		game.neighbour_arrival_cache.clear()
		game.load_map(fixture[0],false)
		game.vm.cancel_all()
		game.entities[1].x=fixture[2].x; game.entities[1].y=fixture[2].y
		game.fps_yaw=fixture[4]; game.fps_pitch=0.0
		game.playing=true; game.changing=false; game.warp_cooldown=0.0
		game._sync_fps_camera()
		var tasks: int=game.vm._live_tasks.size()
		await hold(KEY_W,12)
		check(game.current_screen == fixture[0],"A visible solid beyond seam %s->%s prevents crossing/tunneling" % [fixture[0],target])
		check(game.vm._live_tasks.size() == tasks,"A rejected crossing does not run target scripts")
		var stopped: Vector2=game._position2(1)
		await hold(KEY_S,3)
		check(game._position2(1).distance_to(stopped)>0.1,"Reverse input remains playable after rejected crossing")
		game.world.screens[str(target)].sprites=original
		game.neighbour_arrival_cache.clear()
	# Actual source-map regression: the old fixed north landing trapped Dink at (50,390) on 377. A mover is a point, so
	# the real arrival (50,397.6) is free and the crossing lands; the tree above it is solid, and Dink is not trapped:
	# ordinary sideways input moves him along the edge.
	game.load_map(409,false);game.vm.cancel_all();game.ui.close_menu()
	game.entities[1].x=50.0;game.entities[1].y=2.0
	game.fps_yaw=0.0;game.fps_pitch=-.08;game._sync_fps_camera()
	game.playing=true;game.changing=false;game.warp_cooldown=0.0
	await hold(KEY_W,12)
	check(game.current_screen==377,"Real409 north crossing lands on the free 377 arrival")
	var landed: Vector2=game._position2(1)
	check(not game._blocked(landed,1),"The real-map landing is a free source point")
	check(game._blocked(landed+Vector2(0,-1),1),"The tree above the landing is solid (the original blocks it too)")
	await hold(KEY_A,3)
	check(game._position2(1).distance_to(landed)>0.5,"Sideways input moves after the north landing")
	game.vm.cancel_all(); game.queue_free(); await process_frame
	print("FPS COLLISION INPUT PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
