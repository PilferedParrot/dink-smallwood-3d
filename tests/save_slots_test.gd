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
	print("SAVE SLOTS FAILURES ", JSON.stringify(failures))
	print("SAVE SLOTS PASS" if failures.is_empty() else "SAVE SLOTS FAIL")
	clean_saves()
	game.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
