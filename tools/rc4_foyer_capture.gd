extends SceneTree
const GAME=preload("res://scripts/fps_game.gd")
var game
var out := ""
var mode := "return"
var records: Array=[]
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out=arg.trim_prefix("--out=")
		if arg.begins_with("--mode="): mode=arg.trim_prefix("--mode=")
	_run.call_deferred()
func key(code: int,pressed: bool) -> void:
	var e:=InputEventKey.new();e.keycode=code;e.physical_keycode=code;e.pressed=pressed
	Input.parse_input_event(e);Input.flush_buffered_events()
	await physics_frame
func grab(name: String) -> void:
	var expected_line: String=game.dialogue_log.back() if not game.dialogue_log.is_empty() else ""
	var expected_generation: int=game.generation
	# Dialogue state/log appear before the measured panel is revealed. Wait for
	# its committed visibility, then draw; actual input remains below this grab.
	if name.begins_with("line-"):
		for i in 60:
			if game.ui.page=="dialogue" and game.ui.panel.visible: break
			await process_frame
		assert(game.ui.page=="dialogue" and game.ui.panel.visible,"Dialogue capture waits for revealed card")
		assert(game.generation==expected_generation and game.dialogue_log.back()==expected_line,"Capture still owns the matching line and map")
	await RenderingServer.frame_post_draw;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name+".png"))
	var p: Vector2=game._position2(1)
	var row: Dictionary={"name":name,"screen":game.current_screen,"player":[p.x,p.y],"yaw":game.fps_yaw,"pitch":game.fps_pitch,"camera":str(game.camera.global_position),"frozen":game.entities[1].get("frozen",false),"dialogue_camera":game.fps_dialogue_camera_active if "fps_dialogue_camera_active" in game else false,"line":game.dialogue_log.back() if not game.dialogue_log.is_empty() else "","panel_visible":game.ui.panel.visible,"heading":game.ui.heading.text,"page_serial":game.ui.page_serial,"generation":game.generation}
	records.append(row);print("FOYER CAPTURE ",row)
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	game=GAME.new();game.test_mode=true;root.add_child(game);await process_frame
	await game._new_game();game.vm.cancel_all();game.ui.close_menu();game.test_mode=false
	game.vm.globals["story"]=3 if mode=="cutscene" else 5
	game.vm.globals["nuttree"]=1;game.vm.globals["old_womans_duck"]=4
	game.entities[1].x=365.0;game.entities[1].y=305.0
	game.load_map(439,false);game.vm.cancel_all();game.entities[1].frozen=false
	game.playing=true;game.changing=false;game.warp_cooldown=0.0
	game.fps_yaw=0.0;game.fps_pitch=-.08;game._sync_fps_camera()
	await key(KEY_W,true)
	for _i in 20:
		if game.current_screen==1: break
		await physics_frame
	await key(KEY_W,false)
	await grab("inbound-first-frame")
	var last := ""
	var start := Time.get_ticks_msec()
	var complete := false
	Engine.time_scale=4.0
	while Time.get_ticks_msec()-start<90000:
		await create_timer(.08).timeout
		if game.ui.dialogue_mode:
			var line: String=game.dialogue_log.back() if not game.dialogue_log.is_empty() else ""
			if line!=last:
				last=line;await grab("line-%02d" % records.size())
			await key(KEY_ENTER,true);await key(KEY_ENTER,false)
		if mode=="cutscene":
			if game.current_screen==439 and int(game.vm.globals.get("story",0))==5 and game.vm._live_tasks.is_empty(): complete=true;break
		elif game.current_screen==1 and game.vm._live_tasks.is_empty() and not game.entities[1].get("frozen",false): complete=true;break
	Engine.time_scale=1.0
	await grab("script-finished" if complete else "inconclusive")
	var file:=FileAccess.open(out.path_join("run.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"mode":mode,"complete":complete,"setup":"Explicit story/nut/duck/outdoor approach fixture skips progression. Actual W input activates original439 editor13 warp; original inbound/cutscene scripts and actual Enter continue. First frame normal time; subsequent waits accelerated4x. Names do not imply exact source coordinates; records carry actual position and dialogue-camera state.","records":records,"dialogue_log":game.dialogue_log,"story":game.vm.globals.get("story",0)},"\t"))
	game.vm.cancel_all();game.queue_free();await process_frame;quit(0 if complete else 1)
