extends SceneTree
## Part 1 of the save-roll unit: the source's save machine lists slots that say what
## they are (FreeDink109.6 dinkc.cpp:766-777 &savegameinfo, :744-764 &buttoninfo),
## save_game/load_game/game_exist take a slot (dinkc_bindings.cpp:1316-1348).
## Real choice input for the menus; DinkC calls for the slot contract.
const GAME = preload("res://scripts/fps_game.gd")
var game
var failures: Array[String] = []
var savebot_done := false
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); push_error(message)
func settle() -> void:
	for _i in 8:
		game.ui._process(0)
		await process_frame
func tap(code: Key) -> void:
	for pressed in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code; event.physical_keycode = code; event.pressed = pressed
		Input.parse_input_event(event); Input.flush_buffered_events()
		await process_frame
	await settle()
func choice_labels() -> Array[String]:
	var out: Array[String] = []
	for child in game.ui.column.get_children():
		if child is Button: out.append(child.text)
	return out
func machine_id() -> int:
	for id in game.entities:
		if str(game.entities[id].get("script","")).to_lower() == "savebot": return int(id)
	return 0
func open_savebot_slots() -> Array[String]:
	savebot_done = false
	_talk_machine(machine_id()); await settle()
	await tap(KEY_ENTER) # "Save your game"
	return choice_labels()
func _talk_machine(id: int) -> void:
	await game.vm.run("savebot", "talk", id)
	savebot_done = true
func slot_expect(slot: int, minutes: int, info: String) -> String:
	return "Slot %d - %d:%02d - %s" % [slot, minutes / 60, minutes % 60, info]
func clean_saves() -> void:
	for slot in range(1, 11):
		for path in ["user://adventure.json", "user://adventure-slot-%d.json" % slot]:
			if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
func rewrite(slot: int, edit: Callable) -> void:
	var data: Dictionary = game._read_json(game.SAVE_SLOTS.path(slot))
	edit.call(data)
	game._write_json(game.SAVE_SLOTS.path(slot), data)
func focused_text() -> String:
	var owner = game.ui.get_viewport().gui_get_focus_owner()
	return owner.text if owner is Button else "<none>"
func legacy_and_continue() -> void:
	clean_saves()
	# A 0.3.3 save is today's save without the three keys slots add (638cec6 game.gd:1658-1662).
	game.vm.globals["gold"] = 31
	check(game._save_game(game.SAVE_SLOTS.path(1)), "fixture save writes")
	rewrite(1, func(d): d.erase("minutes"); d.erase("info"); d.erase("saved_at"))
	var legacy: Dictionary = game._read_json("user://adventure.json")
	check(not legacy.has("minutes") and not legacy.has("info") and not legacy.has("saved_at") and int(legacy.version) == 1, "legacy control has the 0.3.3 shape")
	check(int(await game.dink_call("game_exist", [1], {})) == 1, "legacy adventure.json is slot 1")
	check(game.SAVE_SLOTS.label(1) == "Slot 1 - 0:00 - Level 3", "legacy save reads from its own level, got '%s'" % game.SAVE_SLOTS.label(1))
	game.vm.globals["gold"] = 0
	check(int(await game.dink_call("load_game", [1], {})) == 1 and int(game.vm.globals.gold) == 31, "legacy save loads through load_game(1)")
	check(game.SAVE_SLOTS.latest() == 1, "legacy slot is the only and latest slot")
	# Latest: slot 7 saved after slot 3 is preselected by Continue.
	await game.dink_call("save_game", [3], {})
	await game.dink_call("save_game", [7], {})
	rewrite(3, func(d): d["saved_at"] = 1000)
	rewrite(7, func(d): d["saved_at"] = 5000)
	rewrite(1, func(d): d["saved_at"] = 2000)
	check(game.SAVE_SLOTS.latest() == 7, "latest slot follows saved_at, got %d" % game.SAVE_SLOTS.latest())
	game.ui.show_title(true)
	game._ui_action("continue", null); await settle()
	check(game.ui.page == "slots" and game.ui.return_page == "title", "title Continue opens the slot list over the title (page %s)" % game.ui.page)
	var shown := choice_labels()
	check(shown.size() == 10 and shown[6].begins_with("Slot 7 - ") and shown[4] == "Slot 5 - Empty", "slot list shows the ten slots: %s" % [shown])
	check(focused_text() == shown[6], "Continue preselects the most recently saved slot (focus '%s')" % focused_text())
	var empty_button: Button = null
	for child in game.ui.column.get_children():
		if child is Button and child.text == "Slot 5 - Empty": empty_button = child
	check(empty_button != null and empty_button.disabled, "an empty slot cannot be loaded")
	game.vm.globals["gold"] = 1
	for child in game.ui.column.get_children():
		if child is Button and child.text.begins_with("Slot 3 - "): child.pressed.emit()
	await settle()
	check(int(game.vm.globals.gold) == 31 and game.playing, "choosing slot 3 in the list loads slot 3")
	game.ui.show_title(true); game.ui.request_back(); await settle()
func minutes_and_pause_menu() -> void:
	clean_saves()
	game.play_minutes_base = 83
	game.play_started_msec = Time.get_ticks_msec() - 125000 # two minutes of play since the base
	game.vm.globals["level"] = 4
	game.ui.show_pause()
	game._ui_action("save", null); await settle()
	check(game.ui.page == "slots" and game.ui.return_page == "pause", "pause Save opens the slot list over the pause menu")
	check(focused_text() == "Slot 1 - Empty", "pause Save preselects the first empty slot, focus '%s'" % focused_text())
	var texts := choice_labels()
	check(texts.size() == 10 and texts[3] == "Slot 4 - Empty", "pause Save lists all ten slots, empty ones saveable: %s" % [texts])
	for child in game.ui.column.get_children():
		if child is Button and child.text.begins_with("Slot 4 - "):
			check(not child.disabled, "an empty slot can be saved into"); child.pressed.emit()
	await settle()
	check(game.SAVE_SLOTS.label(4) == "Slot 4 - 1:25 - Level 4", "slot 4 reads play time and level, got '%s'" % game.SAVE_SLOTS.label(4))
	check(game.ui.page == "pause", "after saving the pause menu returns (page %s)" % game.ui.page)
	check(not game.SAVE_SLOTS.exists(1) and not game.SAVE_SLOTS.exists(2), "pause Save into slot 4 left slots 1 and 2 empty")
	game._ui_action("load", null); await settle()
	game.ui.request_back(); await settle()
	check(game.ui.page == "pause", "Back from the slot list returns to pause (page %s)" % game.ui.page)
	game.play_minutes_base = 0; game.play_started_msec = Time.get_ticks_msec()
	await game.dink_call("load_game", [4], {})
	check(game._play_minutes() == 85, "load restores the saved play time, got %d" % game._play_minutes())
	game.ui.close_menu()
func button_info() -> void:
	clean_saves()
	game.bindings.reset_all()
	var talk: String = game.bindings.short_label("talk")
	check(game._interpolate_choice("Button 2 - &buttoninfo", {}, 2) == "Button 2 - Talk/Examine (%s)" % talk, "button 2 names Talk/Examine and its key, got '%s'" % game._interpolate_choice("Button 2 - &buttoninfo", {}, 2))
	var result: Dictionary = game.bindings.set_bindings("talk", [game.INPUT_BINDINGS.key(KEY_F)])
	check(result.ok, "remap fixture: Talk to F")
	check(game._interpolate_choice("Button 2 - &buttoninfo", {}, 2) == "Button 2 - Talk/Examine (F)", "remapped Talk reads F, got '%s'" % game._interpolate_choice("Button 2 - &buttoninfo", {}, 2))
	check(game._interpolate_choice("&buttoninfo", {}, 5).begins_with("Main Menu (") and game._interpolate_choice("&buttoninfo", {}, 7) == "Unused" and game._interpolate_choice("&buttoninfo", {}, 11) == "Error: not mapped", "other buttons: Main Menu, Unused, out of range")
	# The source's own escape menu: "View/change gamepad buttons" lists Button 1..10 - &buttoninfo.
	game.entities[1].frozen = false
	var run := func(): await game.vm.run("escape", "main", 1)
	run.call(); await settle()
	for _i in 5: await tap(KEY_DOWN)
	await tap(KEY_ENTER)
	var rows := choice_labels()
	check(rows.size() == 11 and rows[1] == "Button 2 - Talk/Examine (F)" and rows[9] == "Button 10 - Unused", "escape's button list names actions and the remapped key: %s" % [rows])
	game.ui.close_menu(); game.vm.cancel_all(); game.bindings.reset_all(); await settle()
func _run() -> void:
	game = GAME.new(); game.test_mode = true
	root.add_child(game); await process_frame
	game.vm.cancel_all(); game.set_physics_process(false)
	var screen := 0
	for key in game.world.screens:
		for sprite in game.world.screens[key].get("sprites",[]):
			if str(sprite.get("script","")).to_lower() == "savebot": screen = int(key); break
		if screen != 0: break
	check(screen != 0, "the world contains a save machine")
	game.load_map(screen,false); game.ui.close_menu(); game.ui.set_process(false)
	game.playing = true; game.test_mode = false
	game.vm.globals["level"] = 3
	clean_saves()
	# 1. every slot of an empty profile says Slot N - Empty (dinkc.cpp:776)
	var labels := await open_savebot_slots()
	check(labels.size() == 11, "savebot lists ten slots and Nevermind, got %d: %s" % [labels.size(), labels])
	for slot in range(1, 11):
		check(labels.size() >= slot and labels[slot-1] == "Slot %d - Empty" % slot, "empty profile, slot %d reads 'Slot %d - Empty', got '%s'" % [slot, slot, labels[slot-1] if labels.size() >= slot else "<missing>"])
	# 2. choose slot 3 with real input: down, down, enter
	await tap(KEY_DOWN); await tap(KEY_DOWN); await tap(KEY_ENTER)
	check(savebot_done, "savebot finishes after a slot is chosen")
	check(int(await game.dink_call("game_exist", [3], {})) == 1, "game_exist(3) after saving into slot 3")
	for slot in [1, 2, 4, 5, 6, 7, 8, 9, 10]:
		check(int(await game.dink_call("game_exist", [slot], {})) == 0, "slot %d stays empty after saving into slot 3" % slot)
	game.ui.close_menu(); await settle()
	# 3. the filled slot now says what it is, others still Empty
	labels = await open_savebot_slots()
	check(labels.size() == 11 and labels[2] == slot_expect(3, 0, "Level 3"), "slot 3 reads '%s', got '%s'" % [slot_expect(3, 0, "Level 3"), labels[2] if labels.size() > 2 else "<missing>"])
	check(labels.size() == 11 and labels[4] == "Slot 5 - Empty", "slot 5 still reads Slot 5 - Empty")
	game.ui.close_menu(); game.vm.cancel_all(); await settle()
	# 4. load slot 3 restores that state; slot 5 holds nothing to load
	game.vm.globals["gold"] = 123
	await game.dink_call("save_game", [3], {})
	game.vm.globals["gold"] = 9
	var loaded := int(await game.dink_call("load_game", [3], {}))
	check(loaded == 1 and int(game.vm.globals.get("gold", -1)) == 123, "load_game(3) restores the state saved into slot 3 (gold %s)" % game.vm.globals.get("gold"))
	game.vm.globals["gold"] = 77
	var empty_load := int(await game.dink_call("load_game", [5], {}))
	check(empty_load == 0 and int(game.vm.globals.get("gold", -1)) == 77, "load_game(5) on an empty slot loads nothing and changes nothing")
	# 5. a slot-5 save does not overwrite slot 3
	await game.dink_call("save_game", [5], {})
	game.vm.globals["gold"] = 5
	await game.dink_call("load_game", [3], {})
	check(int(game.vm.globals.get("gold", -1)) == 123, "slot 3 survives a later slot-5 save")
	await legacy_and_continue()
	await minutes_and_pause_menu()
	await button_info()
	print("SAVE SLOTS FAILURES ", JSON.stringify(failures))
	print("SAVE SLOTS PASS" if failures.is_empty() else "SAVE SLOTS FAIL")
	clean_saves()
	game.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
