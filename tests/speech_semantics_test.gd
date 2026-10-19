extends SceneTree
## Source contract, independent of presentation layout. Setup skips progression.
const GAME = preload("res://scripts/fps_game.gd")
# FreeDink109.6 dinkc_bindings.cpp:748-825; text.cpp:40-65;
# brain_keyboard.cpp:216-241; update_frame.cpp:295-300.
const ROWS := [
	["say", false, false, "dinkc_bindings.cpp:748-764"],
	["say_stop", true, false, "dinkc_bindings.cpp:766-788"],
	["say_stop_npc", true, false, "dinkc_bindings.cpp:790-807"],
	["say_xy", false, false, "dinkc_bindings.cpp:820-825"],
	["say_stop_xy", true, false, "dinkc_bindings.cpp:809-818"],
]
var game
var failures: Array[String] = []
var stopped := {}
var movement_lane := Vector2.INF
const CONTROL_ROWS := [
	["freeze", false, true, "dinkc_bindings.cpp:552-559; brain_keyboard.cpp:222-240"],
	["unfreeze", false, false, "dinkc_bindings.cpp:542-550"],
	["choice", true, true, "game_choice.cpp:38-54,166-177; brain_keyboard.cpp:219-220"],
]
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); push_error(message)
func literal(value: Variant) -> Dictionary: return {"kind":"literal", "value":value}
func settle() -> void:
	for _i in 8: await process_frame
func program(name: String, code: Array) -> void:
	game.vm.story.scripts[name] = {"procedures":{"main":{"code":code}}}
func physical_key(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_D; event.physical_keycode = KEY_D; event.pressed = pressed
	Input.parse_input_event(event); Input.flush_buffered_events()
	await process_frame
func measure_walk() -> float:
	game.entities[1].x = movement_lane.x; game.entities[1].y = movement_lane.y
	game.fps_yaw = 0; game._sync_fps_camera()
	var before: Vector2 = game._position2(1)
	game.set_physics_process(true)
	await physical_key(true)
	for _i in 12: await physics_frame
	await process_frame
	await physical_key(false)
	game.set_physics_process(false)
	return before.distance_to(game._position2(1))
func control_row(row: Array) -> void:
	game.ui.cancel_speech(); game.vm.cancel_all(); await settle()
	game.entities[1].frozen = row[0] == "unfreeze"
	game.entities[1].nocontrol = 0; game.entities[1].disabled = 0
	game.attack_cooldown = 0
	var args: Array = [literal(1)]
	if row[0] == "choice": args = [literal("A modal source choice"),literal([{"text":"First","value":1},{"text":"Second","value":2}])]
	program("speech_control", [{"op":"call","name":row[0],"args":args},{"op":"set","target":"&speech_marker","expr":literal(1)}])
	game.vm.globals.speech_marker = 0
	game.vm.run("speech_control","main",1)
	await settle()
	check((int(game.vm.globals.speech_marker) == 0) == row[1], "%s caller wait=%s (%s)" % [row[0],row[1],row[3]])
	var moved := await measure_walk()
	check((moved < 0.01) == row[2], "%s player blocked=%s via real physics (pixels=%s; %s)" % [row[0],row[2],moved,row[3]])
	if row[0] == "choice":
		for pressed in [true,false]:
			var event := InputEventKey.new()
			event.keycode = KEY_ENTER; event.physical_keycode = KEY_ENTER; event.pressed = pressed
			Input.parse_input_event(event); Input.flush_buffered_events()
			await process_frame
		await settle()
		check(int(game.vm.globals.speech_marker) == 1, "Choice input resumes its caller")
	print("SPEECH ROW ",JSON.stringify({"binding":row[0],"wait":row[1],"blocked":row[2],"pixels":moved,"lifetime":"not text","citation":row[3]}))
func run_row(row: Array) -> void:
	game.ui.cancel_speech()
	game.vm.cancel_all()
	await settle()
	game.entities[1].frozen = false
	game.entities[1].nocontrol = 0; game.entities[1].disabled = 0
	game.attack_cooldown = 0
	var text := "`2Text contains colour and UTF8: é."
	var cmd: String = row[0]
	var expected_wait: bool = row[1]
	if "--flip-row" in OS.get_cmdline_user_args() and cmd == "say": expected_wait = not expected_wait
	program("speech_row", [
		{"op":"call", "name":cmd, "args":[literal(text),literal(1),literal(40)]},
		{"op":"set", "target":"&speech_marker", "expr":literal(1)}])
	game.vm.globals.speech_marker = 0
	game.vm.run("speech_row", "main", 1)
	for _i in 8:
		game.ui._process(0)
		await process_frame
	check((int(game.vm.globals.speech_marker) == 0) == expected_wait, "%s caller wait=%s (%s)" % [cmd,expected_wait,row[3]])
	var expected_blocked: bool = row[2]
	if "--flip-movement-row" in OS.get_cmdline_user_args() and cmd == "say": expected_blocked = not expected_blocked
	var moved := await measure_walk()
	check((moved < 0.01) == expected_blocked, "%s player blocked=%s via real physics (pixels=%s; %s)" % [cmd,expected_blocked,moved,row[3]])
	check(game.ui.speech_lines.size() == 1, cmd + " creates exactly one independent text sprite")
	var id: int = int(game.ui.speech_lines.keys().back())
	var ttl := maxi(2700, text.to_utf8_buffer().size() * 77)
	check(int(game.ui.speech_lines[id].expires) - int(game.ui.speech_lines[id].born) == ttl, cmd + " source lifetime (text.cpp:40-65)")
	program("speech_other", [{"op":"set", "target":"&speech_other_marker", "expr":literal(42)}])
	await game.vm.run("speech_other", "main", 1000)
	check(int(game.vm.globals.speech_other_marker) == 42, cmd + " leaves other scripts running")
	check(not bool(game.ui.speech_lines[id].get("overflow", false)), cmd + " TTL fixture fits one viewport")
	game.ui._process(maxf(0, float(game.ui.speech_lines[id].remaining) - 0.01))
	check(game.ui.is_speech_active(id), cmd + " lives until source TTL")
	game.ui._process(0.02)
	await settle()
	check(not game.ui.is_speech_active(id), cmd + " text expires at source TTL")
	check(int(game.vm.globals.speech_marker) == 1, cmd + " caller completes after its own expiry")
	print("SPEECH ROW ", JSON.stringify({"binding":cmd,"wait":expected_wait,"blocked":expected_blocked,"pixels":moved,"ttl":ttl,"citation":row[3]}))
func stop_line(binding: String, text: String, owner: int, name: String) -> void:
	await game.dink_call(binding, [text, owner, 40], {})
	stopped[name] = true
func _run() -> void:
	game = GAME.new(); game.test_mode = true
	root.add_child(game)
	await process_frame
	game.set_physics_process(false); game.vm.cancel_all()
	game.load_map(439, false); game.ui.close_menu(); game.ui.set_process(false)
	game.test_mode = false; game.playing = true; game.changing = false
	for y in range(100,300,20):
		for x in range(100,500,20):
			var clear := true
			for dx in range(0,50,2):
				if game._blocked(Vector2(x+dx,y),1): clear = false
			if clear: movement_lane = Vector2(x,y); break
		if movement_lane != Vector2.INF: break
	check(movement_lane != Vector2.INF,"Real-physics table has a source-collision-clear lane")
	for row in ROWS: await run_row(row)
	for row in CONTROL_ROWS: await control_row(row)
	game.entities[1].frozen = false
	game.ui.cancel_speech(); game.vm.cancel_all(); await settle()
	check(game.ui.source_speech_msec("x") == 2700, "Source minimum is 2700ms")
	check(game.ui.source_speech_msec("é".repeat(40)) == 80 * 77, "strlen measures bytes, not codepoints")
	game.vm.globals.gold = 123456789
	var expanded_id: int = await game.dink_call("say", ["Gold: &gold", 1], {})
	check(is_equal_approx(float(game.ui.speech_lines[expanded_id-game.TEXT_SPRITE_BASE].remaining), 2.7), "Variable expansion precedes lifetime")
	game.ui.cancel_speech()
	# Two waiting scripts must coexist; one text expiry cannot release the other.
	stop_line("say_stop_npc", "First waiter", 1, "first")
	await settle()
	var first_waiter: int = int(game.ui.speech_lines.keys().back())
	stop_line("say_stop_xy", "Second waiter lives longer than the first one.", 0, "second")
	await settle()
	check(game.ui.speech_lines.size() == 2 and stopped.is_empty(), "Independent stop callers start concurrently without a global speech lock")
	game.ui.set_speech_ttl(first_waiter, 1)
	await create_timer(0.03).timeout
	game.ui._process(0)
	await settle()
	check(stopped.has("first") and not stopped.has("second") and game.ui.panel.visible, "First text expiry resumes only first waiter")
	game.ui.cancel_speech()
	await settle()
	# FreeDink109.6 dinkc_bindings.cpp:748-807: owner replacement/no-op.
	var older: int = await game.dink_call("say", ["First speaker", 1], {})
	var other: int = await game.dink_call("say", ["Other speaker", 1000], {})
	check(game.ui.speech_lines.size() == 2, "Unrelated speakers coexist")
	var npc: int = await game.dink_call("say_stop_npc", ["Must not replace", 1], {})
	check(npc == 0 and game.ui.speech_lines.size() == 2, "NPC no-op when owner is talking (dinkc_bindings.cpp:790-800)")
	await game.dink_call("sp_active", [older, 0], {})
	check(int(await game.dink_call("sp_active", [other], {})) == 1, "Removing one handle cannot cancel another owner")
	await game.dink_call("sp_kill", [other, 0], {})
	game.ui._process(10000)
	check(game.ui.panel.visible, "sp_kill(0) preserves persistent text (live_sprite.cpp:88-98)")
	await game.dink_call("sp_active", [other, 0], {})
	check(not game.ui.panel.visible, "sp_active(0) removes text immediately")
	var screen_text: int = await game.dink_call("say_xy", ["Old screen text", 0, 40], {})
	var player_text: int = await game.dink_call("say", ["Old player text", 1], {})
	stop_line("say_stop", "Screen-owner stop line", 1000, "screen-owner")
	await settle()
	check(int(await game.dink_call("sp_active", [screen_text], {})) == 0 and int(await game.dink_call("sp_active", [player_text], {})) == 0, "say_stop owner1000 replaces both its owner and player text (dinkc_bindings.cpp:776-778)")
	check(game.ui.speech_lines.size() == 1, "Owner1000 exception applies to say, not say_stop")
	game.ui.cancel_speech()
	await settle()
	var kill_id: int = await game.dink_call("say", ["Explicit deadline", 1], {})
	await create_timer(0.03).timeout
	await game.dink_call("sp_kill", [kill_id, 10], {})
	check(int(await game.dink_call("sp_active", [kill_id], {})) == 0, "Explicit kill is measured from creation (live_sprite.cpp:88-98)")
	await game.vm.run("s3-st2", "main", 1000)
	game.ui._process(10000)
	await settle() # source keeper may greet; expired foreground text reveals the persistent label
	check(game.ui.panel.visible and game.ui.column.get_child(0).text == "The best in bows", "Source S3-ST2 label survives zero TTL")
	game.ui.cancel_speech()
	var stalled: int = await game.dink_call("say", ["A short line", 1], {})
	OS.delay_msec(2750) # a stalled frame contributes no UI delta
	game.ui._process(0)
	check(int(await game.dink_call("sp_active", [stalled], {})) == 0, "Monotonic source clock expires short text even with zero frame delta")
	var prepared: int = game.ui.show_speech("Hidden line.", "Dink")
	await game.ui.prepare_dialogue_layout()
	OS.delay_msec(2800)
	game.ui._process(0)
	check(game.ui.is_speech_active(prepared) and not game.ui.panel.visible, "Hidden frozen-camera layout cannot consume natural reading time")
	game.ui.reveal_dialogue()
	game.ui._process(0)
	check(game.ui.is_speech_active(prepared) and game.ui.panel.visible, "Natural TTL begins when prepared card is revealed")
	game.ui.set_speech_ttl(prepared, 1)
	check(not game.ui.is_speech_active(prepared), "Explicit TTL still uses creation before hidden layout")
	game.ui.cancel_speech(); game.vm.cancel_all(); game.queue_free()
	await process_frame
	print("SPEECH FAILURES ", JSON.stringify(failures))
	print("SPEECH SEMANTICS PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
