extends SceneTree

const GAME = preload("res://scripts/fps_game.gd")
var game
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, text: String) -> void:
	if not ok: failures.append(text); push_error(text)

func click() -> void:
	var event := InputEventMouseButton.new(); event.button_index=MOUSE_BUTTON_LEFT; event.pressed=true
	Input.parse_input_event(event);Input.flush_buffered_events()
	for _i in 3: await physics_frame
	event=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=false
	Input.parse_input_event(event);Input.flush_buffered_events()
	await physics_frame

func place(p: Vector2, yaw: float = 0.0) -> void:
	game.entities[1].x=p.x;game.entities[1].y=p.y
	game.entities[1].frozen=false;game.entities[1].nocontrol=0
	game.fps_yaw=yaw;game.fps_pitch=-0.3;game._sync_fps_camera()
	game.attack_cooldown=0.0;game.fps_fire_held=false

func _run() -> void:
	game=GAME.new();game.test_mode=true;root.add_child(game)
	await process_frame
	await game._new_game();await create_timer(0.5).timeout
	game.vm.cancel_all();game.ui.close_menu();game._equip(0,false)
	# Static map setup skips progression; attacks execute the real mouse path
	# and original bar-e.hit procedure on the original screen439 barrel.
	game.load_map(439,false);await process_frame;await physics_frame
	game.playing=true;game.changing=false
	var barrel := 0
	for id in game.entities:
		if int(game.entities[id].get("editor_num",0)) == 22: barrel=int(id)
	check(barrel != 0 and int(game.entities[barrel].pseq) == 173,"Fixture is the actual intact barel-01 source barrel")
	place(Vector2(124,290),PI)
	await click()
	check(int(game.entities[barrel].get("last_hit",0)) == 0,"Fist cannot hit beyond the original expanded hardbox")
	place(Vector2(124,398))
	check(not game._blocked(game._position2(1),1),"Derived reach fixture starts outside barrel clearance")
	check(game._fps_ray_reaches(barrel),"Actual barrel ray body is visible from the attack point")
	await click()
	check(int(game.entities[barrel].get("last_hit",0)) == 1,"Mouse fist attack reaches barrel43px away via its source hardbox")
	check(int(game.entities[barrel].get("nohit",0)) == 1 and int(game.entities[barrel].get("brain",0)) == 5,"Original barrel hit script starts its break animation")
	var source_box := {"x":100.0,"y":100.0,"hardbox":[-17,-15,20,6],"size":100}
	for entry in [[8,Vector2(100,151)],[2,Vector2(100,45)],[6,Vector2(51,100)],[4,Vector2(152,100)]]:
		var rect: Rect2=game._fps_melee_hit_rect(source_box,entry[0],0)
		check(rect.has_point(entry[1]),"FreeDink target-hardbox extension holds in direction%s" % entry[0])
	# Ground truth intervals from FreeDink109.6 run_through_tag_list (inclusive).
	# Sword range40 extends by40 horizontally and46 vertically, using integer division.
	for entry in [[8,Rect2(68,80,67,82)],[2,Rect2(63,34,77,82)],[6,Rect2(38,65,87,66)],[4,Rect2(78,65,87,66)]]:
		check(game._fps_melee_hit_rect(source_box,entry[0],40)==entry[1],"Sword range parity direction%s" % entry[0])
	game.vm.cancel_all();game.queue_free();await process_frame
	print("FPS MELEE REACH PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
