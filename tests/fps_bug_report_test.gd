extends SceneTree
const GAME=preload("res://scripts/fps_game.gd")
var game
var failures: Array=[]
func _initialize() -> void: _run.call_deferred()
func check(ok: bool,message: String) -> void:
	if not ok: failures.append(message);push_error(message)
func key(code: int, pressed: bool) -> void:
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=pressed;Input.parse_input_event(event)
	# Godot accumulates synthetic input until a rendered frame; a physics
	# signal alone does not establish delivery of the release.
	Input.flush_buffered_events()
	await physics_frame
func save() -> String:
	var old: String=game.last_bug_report
	await key(KEY_F9,true);await key(KEY_F9,false)
	for _i in 180:
		if not game.bug_report_pending and game.last_bug_report!=old: return game.last_bug_report
		await process_frame
	return ""
func _run() -> void:
	game=GAME.new();game.test_mode=true;root.add_child(game);await process_frame
	await game._new_game();game.vm.cancel_all();game.ui.close_menu();game.load_map(439,false)
	game.entities[1].x=510.0;game.entities[1].y=300.0;game.entities[1].frozen=false
	game.fps_yaw=0.0;game.playing=true;game.changing=false;game._sync_fps_camera()
	await key(KEY_W,true)
	for _i in 8: await physics_frame
	await key(KEY_W,false)
	for _i in 2: await physics_frame
	check(not Input.is_action_pressed("up"),"Release is delivered before measuring the stopped player")
	var at: Vector2=game._position2(1)
	var path: String=await save()
	check(not path.is_empty(),"Actual F9 writes a rendered local report")
	if not path.is_empty():
		var report: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
		check(report.snapshot.screen==439 and absf(float(report.snapshot.player.y)-at.y)<.01,"Captured source state matches the stopped player: %s vs %s" % [report.snapshot.player,at])
		check(report.build.fps_script_sha256.length()==64 and report.build.renderer_script_sha256.length()==64,"Source or compiled shipped scripts are fingerprinted")
		var image:=Image.load_from_file(path.get_base_dir().path_join(report.screenshot))
		check(image!=null and image.get_width()>400 and image.get_height()>200,"Report PNG contains a rendered viewport")
		var pressed:=false;var released:=false;var unwanted:=false
		for event in report.input.events:
			if event.get("physical",0)==KEY_W:
				if event.pressed: pressed=true
				else: released=true
			if event.get("physical",0)==KEY_F9: unwanted=true
		check(pressed and released and not unwanted,"Actual gameplay press and release survive; F9 is excluded")
		game.ui.show_pause()
		var second: String=await save()
		check(not second.is_empty() and second!=path and FileAccess.file_exists(path),"F9 also records modal defects without overwriting the first report")
		print("REPORT_PATH="+ProjectSettings.globalize_path(path))
	game.vm.cancel_all();game.queue_free();await process_frame
	print("FPS BUG REPORT PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
