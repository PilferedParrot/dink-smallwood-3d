extends SceneTree
## Fixture skips progression. Settings and Talk use physical events.
const GAME = preload("res://scripts/fps_game.gd")
const BINDINGS = preload("res://scripts/input_bindings.gd")
var game
var completed := 0
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); push_error(message)
func settle() -> void:
	for _i in 8: await process_frame
func settle_speech_layout() -> void:
	for _i in 8:
		game.ui._process(0); await process_frame
func event(record: Dictionary, pressed: bool) -> void:
	var e: InputEvent = BINDINGS.to_event(record)
	if e is InputEventJoypadMotion: e.axis_value = float(record.direction) if pressed else 0.0
	else: e.pressed = pressed
	if e is InputEventKey: e.keycode = e.physical_keycode
	Input.parse_input_event(e); Input.flush_buffered_events()
	await process_frame
func tap(record: Dictionary) -> void:
	await event(record, true); await event(record, false); await settle()
func line() -> void:
	await game.dink_call("say_stop", ["Take as long as you need.", 1], {})
	completed += 1
func _run() -> void:
	var phase: String = OS.get_cmdline_user_args()[0]
	game = GAME.new(); game.test_mode = true
	root.add_child(game)
	await process_frame
	game.set_physics_process(false); game.vm.cancel_all()
	game.load_map(439, false); game.ui.close_menu(); game.playing = true
	game.entities[1].frozen = false; game.entities[1].nocontrol = 0
	game.test_mode = false
	if phase == "write":
		check(not bool(game.settings.get("speech_waits_for_me", false)), "Accessibility defaults OFF")
		game.ui.show_settings(game.settings)
		await settle()
		var option: Button
		for child in game.ui.column.get_children():
			if child.get_meta("setting_key", "") == "speech_waits_for_me": option = child
		check(option != null, "Settings exposes Speech waits for me")
		option.grab_focus()
		await tap(BINDINGS.key(KEY_ENTER))
		check(bool(game.settings.get("speech_waits_for_me", false)), "Real menu confirmation turns setting on")
		check(game.bindings.set_bindings("magic", [BINDINGS.key(KEY_L)]).ok, "Free the left trigger for Talk")
		check(game.bindings.set_bindings("talk", [BINDINGS.key(KEY_J),BINDINGS.key(KEY_F13),BINDINGS.pad(JOY_BUTTON_A),BINDINGS.axis(JOY_AXIS_TRIGGER_LEFT,1)]).ok, "Talk remaps to keyboard, alternate, pad, axis")
		print("SPEECH ACCESSIBILITY WRITE")
	else:
		check(bool(game.settings.get("speech_waits_for_me", false)), "Speech waits setting persists across process restart")
		game.ui.close_menu(); game.ui.set_process(false)
		for record in game.bindings.events("talk"):
			completed = 0; line(); await settle()
			check(not game.ui.modal and not game.ui.dialogue_continue.visible, "Wait option keeps speech nonmodal without a focused Continue")
			# Use real movement polling with an independently accumulated delta;
			# game collision is proven separately by speech_input_test's real lane.
			game.entities[1].x = 505; game.entities[1].y = 340
			game.fps_yaw = 0; game._sync_fps_camera()
			var before: Vector2 = game._position2(1)
			await event(BINDINGS.key(KEY_D), true)
			for _i in 5: game._physics_process(1.0/60)
			await event(BINDINGS.key(KEY_D), false)
			check(before.distance_to(game._position2(1)) > 1, "Accessibility waiting leaves real movement free")
			game.ui._process(10000); await settle()
			check(completed == 0 and game.ui.panel.visible, "Enabled line outlives natural TTL and its caller waits")
			if record.type in ["pad", "axis"]:
				await tap(BINDINGS.pad(JOY_BUTTON_B))
				check(game.ui.speech_dismiss_hint.text.contains(game.bindings.short_label("talk",true)), "Dismiss hint follows controller input device")
			await tap(BINDINGS.key(KEY_ENTER))
			check(completed == 0, "Former Talk Enter cannot dismiss after remap")
			var hint: String = game.ui.speech_dismiss_hint.text
			check(game.ui.speech_dismiss_hint.visible and hint.contains(game.bindings.short_label("talk",false)), "Dismiss hint names current remapped Talk key")
			await tap(record)
			check(completed == 1 and not game.ui.panel.visible, "Each bound Talk input dismisses exactly its line")
		# Off returns to source lifetime, not a hidden opt-in or old setting.
		game._ui_action("setting", {"key":"speech_waits_for_me","value":false})
		line()
		await settle_speech_layout()
		var timed: Dictionary = game.ui.speech_lines[game.ui.active_speech_id]
		check(int(timed.expires) - int(timed.born) == 2700, "Off line uses source2700ms minimum")
		game.ui._process(maxf(0, float(timed.remaining) - 0.01))
		check(game.ui.panel.visible, "Off line stays until its source deadline")
		game.ui._process(0.02); await settle()
		check(completed == 2 and not game.ui.panel.visible, "Off line expires naturally and resumes its caller")
		# Default frozen Talk remains a separate original fast-forward contract.
		game.entities[1].frozen = true
		line(); await settle()
		await tap(BINDINGS.key(KEY_J))
		check(completed == 3 and game.entities[1].frozen, "Default Talk ends frozen last_talk speech without unfreezing Dink")
		game.entities[1].frozen = false
		for menu in ["pause", "inventory"]:
			var paused_text: int = await game.dink_call("say", ["Menus preserve reading time.", 1], {})
			await settle_speech_layout()
			await tap(BINDINGS.key(KEY_ESCAPE if menu == "pause" else KEY_I))
			check(game.ui.modal and game.ui.page == menu, "Real input opens " + menu)
			OS.delay_msec(2800)
			game.ui._process(10000)
			check(int(await game.dink_call("sp_active", [paused_text], {})) == 1, menu + " preserves natural TTL during a real-time stall")
			await tap(BINDINGS.key(KEY_ESCAPE))
			await settle_speech_layout()
			check(not game.ui.modal and game.ui.panel.visible, menu + " restores the readable line on resume")
			game.ui._process(3)
			check(int(await game.dink_call("sp_active", [paused_text], {})) == 0, menu + " resumes natural expiry after closing")
		print("SPEECH ACCESSIBILITY PASS" if failures.is_empty() else failures)
	game.ui.cancel_speech(); game.vm.cancel_all(); game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
