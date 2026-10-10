# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
# Diagnostic restoration, not a historical script/save replay. Isolate user://.
extends SceneTree
const GAME = preload("res://scripts/fps_game.gd")
const RECORDER = preload("res://scripts/bug_report_recorder.gd")
var report_path := ""
var mode := "snapshot"
var game
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report_path=arg.trim_prefix("--report=")
		if arg.begins_with("--mode="): mode=arg.trim_prefix("--mode=")
	_run.call_deferred()
func _run() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(report_path))
	if not data is Dictionary or data.get("schema",0) != 1 or mode not in ["snapshot","inputs"]:
		push_error("Expected schema1 report and snapshot|inputs mode");quit(2);return
	var state: Dictionary = data.get("snapshot",{})
	game=GAME.new();game.test_mode=true;root.add_child(game);await process_frame
	if not game.world.screens.has(str(int(state.get("screen",0)))) or not state.get("entities",{}).has("1"):
		push_error("Report has no supported screen/player");quit(2);return
	game.vm.cancel_all();game.ui.close_menu()
	game.vm.globals=state.get("globals",{}).duplicate(true)
	game.editor_state=state.get("editor_state",{}).duplicate(true)
	game.items=state.get("items",[]).duplicate(true);game.magic_items=state.get("magic_items",[]).duplicate(true)
	game.load_map(int(state.screen),false)
	for visual in game.visuals.values(): visual.queue_free()
	game.visuals.clear();game.entities.clear()
	for key in state.entities:
		var id := int(key)
		game.entities[id]=state.entities[key].duplicate(true)
		game.entities[id].erase("moving")
		game._create_visual(id)
	game.next_entity=int(state.get("next_entity",2));game.locked=bool(state.get("locked",false))
	for key in state.get("settings",{}): game.settings[key]=state.settings[key]
	game._apply_settings()
	game.fps_yaw=float(state.camera.yaw);game.fps_pitch=float(state.camera.pitch)
	game.playing=true;game.changing=false;game.ui.close_menu();game._sync_fps_camera()
	var before: Vector2=game._position2(1)
	var events: Array=data.get("input",{}).get("events",[])
	if mode=="inputs" and not events.is_empty():
		if events.size()>RECORDER.MAX_EVENTS: push_error("Too many events");quit(2);return
		var first := float(events[0].get("t_ms",0))
		var start := Time.get_ticks_usec()
		for record in events:
			var target := float(record.get("t_ms",0))-first
			if target<0 or target>10000: push_error("Invalid input timeline");quit(2);return
			while float(Time.get_ticks_usec()-start)/1000.0<target: await physics_frame
			var event: InputEvent=RECORDER.to_input_event(record)
			if event!=null: Input.parse_input_event(event)
		await physics_frame
	var after: Vector2=game._position2(1)
	print("BUG REPORT REPLAY "+JSON.stringify({"mode":mode,"start_screen":state.screen,"end_screen":game.current_screen,"start":[before.x,before.y],"end":[after.x,after.y],"events":events.size(),"limitations":"Final captured state; inputs rerun FROM that state. No rewind, pending DinkC tasks, restored modal dialogue, or prior-window held keys."}))
	game.vm.cancel_all();game.queue_free();await process_frame;quit(0)
