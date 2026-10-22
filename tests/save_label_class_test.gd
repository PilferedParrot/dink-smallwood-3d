extends SceneTree
## The class behind save_slots_test.gd: every input to a slot's label, to slot choice and to the
## DinkC save calls, enumerated in tmp/save-tests/INPUTS.md. Slot files here are fixtures this test
## writes itself; FreeDink109.6 dinkc.cpp:744-779, savegame.cpp:365-382, dinkc_bindings.cpp:1316-1348
## and :1824-1827 are the source of what each must read.
const GAME = preload("res://scripts/fps_game.gd")
var game
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); push_error(message)
func settle() -> void:
	for _i in 8:
		game.ui._process(0)
		await process_frame
func focused_text() -> String:
	var owner = game.ui.get_viewport().gui_get_focus_owner()
	return owner.text if owner is Button else "<none>"
func choice_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for child in game.ui.column.get_children():
		if child is Button: out.append(child)
	return out
func slot_path(slot: int) -> String: return game.SAVE_SLOTS.path(slot)
func fresh_clock() -> void:
	game.play_minutes_base = 0; game.play_started_msec = Time.get_ticks_msec()
func clean_saves() -> void:
	for path in ["user://adventure.json", "user://adventure-slot-0.json", "user://adventure-slot--1.json", "user://adventure-slot-11.json"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	for slot in range(2, 11):
		if FileAccess.file_exists(slot_path(slot)): DirAccess.remove_absolute(slot_path(slot))
func put(slot: int, data: Dictionary) -> void:
	check(game._write_json(slot_path(slot), data), "fixture writes slot %d" % slot)
func raw(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text); file.close()
func filled(minutes: int, info: String) -> Dictionary: return {"version": 1, "minutes": minutes, "info": info, "saved_at": 1700000000}
func call_dink(name: String, args: Array) -> int: return int(await game.dink_call(name, args, {}))
func stored(slot: int) -> Dictionary: return game._read_json(slot_path(slot))

# 1. What a slot file must be before it reads as a saved game (dinkc.cpp:771: load_game_small == 1).
func file_shapes() -> void:
	clean_saves()
	check(game.SAVE_SLOTS.label(4) == "Slot 4 - Empty", "no file: Empty, got '%s'" % game.SAVE_SLOTS.label(4))
	raw(slot_path(4), "")
	check(game.SAVE_SLOTS.label(4) == "Slot 4 - Empty", "zero-byte file: Empty, got '%s'" % game.SAVE_SLOTS.label(4))
	for junk in ["not json at all", "{\"version\":1,", "[1,2,3]", "7", "null", "\"version\""]:
		raw(slot_path(4), junk)
		check(game.SAVE_SLOTS.label(4) == "Slot 4 - Empty", "non-object content '%s': Empty, got '%s'" % [junk, game.SAVE_SLOTS.label(4)])
	for version in [0, 2, 3, -1]:
		put(4, {"version": version, "minutes": 5, "info": "Level 9"})
		check(game.SAVE_SLOTS.label(4) == "Slot 4 - Empty", "version %d is not a version-1 save: Empty, got '%s'" % [version, game.SAVE_SLOTS.label(4)])
	put(4, {"minutes": 5, "info": "Level 9"})
	check(game.SAVE_SLOTS.label(4) == "Slot 4 - Empty", "no version key: Empty, got '%s'" % game.SAVE_SLOTS.label(4))
	put(4, {})
	check(game.SAVE_SLOTS.label(4) == "Slot 4 - Empty", "empty object: Empty, got '%s'" % game.SAVE_SLOTS.label(4))
	put(4, filled(5, "Level 9"))
	check(game.SAVE_SLOTS.label(4) == "Slot 4 - 0:05 - Level 9", "control: a version-1 file reads filled, got '%s'" % game.SAVE_SLOTS.label(4))
	# the ten-slot list, and the label of slot 10 (two-digit number)
	put(10, filled(61, "Ten"))
	check(game.SAVE_SLOTS.label(10) == "Slot 10 - 1:01 - Ten", "slot 10 reads '%s'" % game.SAVE_SLOTS.label(10))
	var all: Array[String] = game.SAVE_SLOTS.labels()
	check(all.size() == 10 and all[3] == "Slot 4 - 0:05 - Level 9" and all[9] == "Slot 10 - 1:01 - Ten" and all[0] == "Slot 1 - Empty", "labels() lists ten slots in order: %s" % [all])
	clean_saves()

# 2. "%d:%02d" of play.minutes (dinkc.cpp:775), and the legacy save with neither minutes nor info.
func minute_formats() -> void:
	clean_saves()
	for row in [[0, "0:00"], [1, "0:01"], [9, "0:09"], [59, "0:59"], [60, "1:00"], [61, "1:01"], [125, "2:05"], [600, "10:00"], [6039, "100:39"]]:
		put(2, filled(row[0], "x"))
		check(game.SAVE_SLOTS.label(2) == "Slot 2 - %s - x" % row[1], "%d minutes reads %s, got '%s'" % [row[0], row[1], game.SAVE_SLOTS.label(2)])
	# a save written before slots carried minutes/info reads 0:00 and the level it stored; none stored reads Level 1
	put(2, {"version": 1, "vm": {"globals": {"level": 6}}})
	check(game.SAVE_SLOTS.label(2) == "Slot 2 - 0:00 - Level 6", "legacy shape reads its own level, got '%s'" % game.SAVE_SLOTS.label(2))
	put(2, {"version": 1})
	check(game.SAVE_SLOTS.label(2) == "Slot 2 - 0:00 - Level 1", "legacy shape with no level reads Level 1, got '%s'" % game.SAVE_SLOTS.label(2))
	put(2, filled(3, ""))
	check(game.SAVE_SLOTS.label(2) == "Slot 2 - 0:03 - Level 1", "an empty info falls back to the level, got '%s'" % game.SAVE_SLOTS.label(2))
	clean_saves()

# 3. play minutes of a live game: fresh, after a load, across the minute boundary (dinkc_bindings.cpp:580,1756).
func live_minutes() -> void:
	clean_saves()
	game.play_minutes_base = 0; game.play_started_msec = Time.get_ticks_msec()
	check(game._play_minutes() == 0, "a fresh game has played 0 minutes, got %d" % game._play_minutes())
	game.play_started_msec = Time.get_ticks_msec() - 59000
	check(game._play_minutes() == 0, "59 s is still 0 minutes, got %d" % game._play_minutes())
	game.play_started_msec = Time.get_ticks_msec() - 60500
	check(game._play_minutes() == 1, "60.5 s is 1 minute, got %d" % game._play_minutes())
	game.play_minutes_base = 59; game.play_started_msec = Time.get_ticks_msec() - 61000
	check(game.SAVE_SLOTS.label(1) == "Slot 1 - Empty", "control: slot 1 starts empty")
	check(game._save_game(slot_path(1)), "live-minutes fixture writes")
	check(game.SAVE_SLOTS.label(1).begins_with("Slot 1 - 1:00 - "), "59 + 1 minutes reads 1:00 across the hour, got '%s'" % game.SAVE_SLOTS.label(1))
	# a load replaces both the base and the clock: the minutes of the game being left do not carry over
	put(2, filled(5, "x"))
	var fixture: Dictionary = stored(1)
	fixture["minutes"] = 5
	put(2, fixture)
	game.play_minutes_base = 40; game.play_started_msec = Time.get_ticks_msec() - 600000
	check(await call_dink("load_game", [2]) == 1, "live-minutes fixture loads slot 2")
	check(game.play_minutes_base == 5 and game._play_minutes() == 5, "after a load the clock restarts at the saved 5 minutes, got base %d total %d" % [game.play_minutes_base, game._play_minutes()])
	check(game._save_game(slot_path(3)) and game.SAVE_SLOTS.label(3).begins_with("Slot 3 - 0:05 - "), "a save right after the load keeps 0:05, got '%s'" % game.SAVE_SLOTS.label(3))
	clean_saves()

# 4. save_game_info: default, script-set, interpolated (ints, loaded floats, unknown names), cut at 77 (savegame.cpp:375-378).
func info_text() -> void:
	clean_saves(); fresh_clock()
	game.vm.globals["level"] = 4; game.vm.globals["gold"] = 31
	game.save_game_info = "Level &level"
	check(game._save_game(slot_path(2)) and game.SAVE_SLOTS.label(2).ends_with(" - Level 4"), "default info reads Level 4, got '%s'" % game.SAVE_SLOTS.label(2))
	check(await call_dink("set_save_game_info", ["Chapter Two, &gold coins"]) == 0 and game.save_game_info == "Chapter Two, &gold coins", "set_save_game_info stores the script's text, got '%s'" % game.save_game_info)
	check(game._save_game(slot_path(3)) and game.SAVE_SLOTS.label(3) == "Slot 3 - 0:00 - Chapter Two, 31 coins", "a script-set info reaches the label, got '%s'" % game.SAVE_SLOTS.label(3))
	check(stored(3).info == "Chapter Two, 31 coins", "the file stores the deciphered text, got '%s'" % stored(3).info)
	check(game.SAVE_SLOTS.label(2).ends_with(" - Level 4"), "an earlier slot keeps its own info after the script changed it, got '%s'" % game.SAVE_SLOTS.label(2))
	# interpolation of values the VM holds: loaded floats print as integers, a real fraction does not, an unknown name is 0
	game.vm.globals["whole"] = 4.0; game.vm.globals["neg"] = -3.0; game.vm.globals["frac"] = 4.5
	game.save_game_info = "&whole/&neg/&frac/&nosuchvariable"
	check(game._save_game(slot_path(4)) and stored(4).info == "4/-3/4.5/0", "floats 4.0,-3.0,4.5 and an unknown name interpolate as 4/-3/4.5/0, got '%s'" % stored(4).info)
	game.save_game_info = "`4Red &level"
	check(game._save_game(slot_path(4)) and stored(4).info == "Red 4", "colour codes do not reach the label, got '%s'" % stored(4).info)
	game.save_game_info = "100% &level&"
	check(game._save_game(slot_path(4)) and game.SAVE_SLOTS.label(4) == "Slot 4 - 0:00 - 100% 4&", "a % or a lone & in the info prints as typed, got '%s'" % game.SAVE_SLOTS.label(4))
	# the cut: 77 are kept whole, a 78th is dropped, and it counts the text AFTER interpolation
	var a77 := "A".repeat(77)
	game.save_game_info = a77
	check(game._save_game(slot_path(5)) and stored(5).info == a77, "77 characters are kept whole, got %d" % str(stored(5).info).length())
	game.save_game_info = a77 + "B"
	check(game._save_game(slot_path(5)) and stored(5).info == a77, "78 characters are cut to the first 77, got %d" % str(stored(5).info).length())
	game.save_game_info = "A".repeat(500)
	check(game._save_game(slot_path(5)) and str(stored(5).info).length() == 77 and game.SAVE_SLOTS.label(5) == "Slot 5 - 0:00 - %s" % a77, "500 characters are cut to 77 in the label, got '%s'" % game.SAVE_SLOTS.label(5))
	game.vm.globals["big"] = 1234567
	game.save_game_info = "&big" + "x".repeat(71) # 76 typed, 78 once &big is a number
	check(game._save_game(slot_path(5)) and stored(5).info == "1234567" + "x".repeat(70), "the cut counts the interpolated text (7+70), got %d '%s'" % [str(stored(5).info).length(), stored(5).info])
	# multibyte text at the cut: whole characters only, nothing torn, the file still parses
	game.save_game_info = "A".repeat(76) + "ééé"
	check(game._save_game(slot_path(6)) and stored(6).info == "A".repeat(76) + "é", "an accented letter at the cut survives whole, got '%s'" % stored(6).info)
	game.save_game_info = "A".repeat(76) + "😀😀"
	check(game._save_game(slot_path(6)) and stored(6).info == "A".repeat(76) + "😀", "an emoji at the cut survives whole, got '%s'" % stored(6).info)
	game.save_game_info = "日本語".repeat(40)
	check(game._save_game(slot_path(6)) and str(stored(6).info).length() == 77 and not str(stored(6).info).contains("�"), "CJK text is cut to 77 characters without a replacement character")
	check(game.SAVE_SLOTS.label(6).begins_with("Slot 6 - 0:00 - 日本語"), "the multibyte label reads, got '%s'" % game.SAVE_SLOTS.label(6))
	game.save_game_info = "Level &level"
	clean_saves()

# 5. A loaded save returns every global as a JSON float; a label made after the load prints integers (S9).
func loaded_floats() -> void:
	clean_saves(); fresh_clock()
	game.vm.globals["level"] = 7; game.vm.globals["gold"] = 250
	game.save_game_info = "Level &level, &gold gold"
	check(game._save_game(slot_path(2)), "float fixture writes")
	game.vm.globals["level"] = 0; game.vm.globals["gold"] = 0
	check(await call_dink("load_game", [2]) == 1, "float fixture loads")
	check(game.vm.globals["level"] is float and game.vm.globals["gold"] is float, "instrument check: both loaded globals are floats")
	check(game._save_game(slot_path(3)) and game.SAVE_SLOTS.label(3) == "Slot 3 - 0:00 - Level 7, 250 gold", "load then save prints 7 and 250 as integers, got '%s'" % game.SAVE_SLOTS.label(3))
	game.vm.globals["frac"] = 2.5
	check(game._interpolate("&frac", {}) == "2.5", "a real fraction still prints as 2.5, got '%s'" % game._interpolate("&frac", {}))
	game.save_game_info = "Level &level"
	clean_saves()

# 6. DinkC slot arguments (dinkc_bindings.cpp:1316-1348): the range, and a stray file that must not count.
func slot_arguments() -> void:
	clean_saves()
	game.vm.globals["gold"] = 11
	for slot in [0, -1, -10]:
		check(await call_dink("save_game", [slot]) == 0, "save_game(%d) fails" % slot)
		check(not FileAccess.file_exists(slot_path(slot)), "save_game(%d) writes no stray file %s" % [slot, slot_path(slot)])
		check(await call_dink("load_game", [slot]) == 0, "load_game(%d) fails" % slot)
		check(await call_dink("game_exist", [slot]) == 0, "game_exist(%d) is 0" % slot)
	# a file already sitting at the slot-0 / slot-minus-1 name must still not count as a save
	raw(slot_path(0), JSON.stringify(filled(5, "stray")))
	raw(slot_path(-1), JSON.stringify(filled(5, "stray")))
	check(await call_dink("game_exist", [0]) == 0 and await call_dink("game_exist", [-1]) == 0, "game_exist(0) and (-1) stay 0 beside a stray file")
	check(await call_dink("load_game", [0]) == 0 and int(game.vm.globals.gold) == 11, "load_game(0) beside a stray file loads nothing")
	check(not game.SAVE_SLOTS.exists(0) and not game.SAVE_SLOTS.exists(-1), "SAVE_SLOTS.exists rejects slots below 1")
	for slot in [1, 2, 9, 10]:
		check(await call_dink("save_game", [slot]) == 1 and await call_dink("game_exist", [slot]) == 1, "save_game(%d) then game_exist(%d) is 1" % [slot, slot])
	check(FileAccess.file_exists("user://adventure.json") and not FileAccess.file_exists("user://adventure-slot-1.json"), "slot 1 is the legacy adventure.json, not adventure-slot-1.json")
	check(FileAccess.file_exists("user://adventure-slot-10.json"), "slot 10 is adventure-slot-10.json")
	game.vm.globals["gold"] = 0
	check(await call_dink("load_game", [10]) == 1 and int(game.vm.globals.gold) == 11, "slot 10 loads")
	# slot 11: the source has no cap (the calls take any number) but the menus list ten; it is a file the menus never see
	check(await call_dink("save_game", [11]) == 1 and await call_dink("game_exist", [11]) == 1, "save_game(11) is accepted by DinkC like the source")
	put(11, filled(9, "beyond"))
	for slot in range(2, 11):
		if FileAccess.file_exists(slot_path(slot)): DirAccess.remove_absolute(slot_path(slot))
	DirAccess.remove_absolute("user://adventure.json")
	put(11, {"version": 1, "minutes": 9, "info": "beyond", "saved_at": 2000000000})
	check(game.SAVE_SLOTS.latest() == 0 and not game.SAVE_SLOTS.any_exists() and game.SAVE_SLOTS.labels().size() == 10, "a slot-11 file is invisible to Continue, the title and the ten-slot list (latest %d)" % game.SAVE_SLOTS.latest())
	# a failed load leaves the game as it was
	game.vm.globals["gold"] = 77
	raw(slot_path(5), "garbage"); put(6, {"version": 2}); put(7, {"version": 1}); put(8, {"version": 1, "screen": 99999, "entities": {"1": {}}})
	for slot in [3, 5, 6, 7, 8]:
		check(await call_dink("load_game", [slot]) == 0 and int(game.vm.globals.gold) == 77 and game.playing, "load_game(%d) of a missing/garbage/wrong-version/incomplete file returns 0 and changes nothing" % slot)
	# a complete save whose only difference is the version is refused too (the version gate, not the missing screen)
	game.vm.globals["gold"] = 55
	check(game._save_game(slot_path(2)), "version fixture writes")
	var versioned: Dictionary = stored(2)
	versioned["version"] = 2
	put(2, versioned)
	game.vm.globals["gold"] = 77
	check(await call_dink("load_game", [2]) == 0 and int(game.vm.globals.gold) == 77, "a complete save marked version 2 is not loaded")
	check(await call_dink("game_exist", [5]) == 1, "game_exist is file presence, like fopen in dinkc_bindings.cpp:1350: a garbage file exists")
	clean_saves()

# 7. Which slot the menus preselect: Continue/Load take the latest, ties the lower number; Save takes the first empty.
func preselection() -> void:
	clean_saves()
	check(game.SAVE_SLOTS.latest() == 0 and not game.SAVE_SLOTS.any_exists(), "no saves: latest is 0 and the title hides Continue")
	# a profile holding only the legacy adventure.json (slot 1) still offers Continue
	put(1, filled(1, "legacy only"))
	check(game.SAVE_SLOTS.any_exists() and game.SAVE_SLOTS.latest() == 1, "a profile with only slot 1 offers Continue on slot 1 (latest %d)" % game.SAVE_SLOTS.latest())
	clean_saves()
	game.ui.show_pause(); game._ui_action("load", null); await settle()
	var buttons := choice_buttons()
	var disabled := 0
	for button in buttons: disabled += 1 if button.disabled else 0
	check(buttons.size() == 10 and disabled == 10, "Load with no saves lists ten disabled slots (%d buttons, %d disabled)" % [buttons.size(), disabled])
	game.ui.close_menu()
	# ties: the lowest slot, wherever the tied slots sit
	for pair in [[6, 2], [2, 6], [9, 4, 7], [10, 1, 5]]:
		clean_saves()
		for slot in pair: put(slot, filled(1, "t"))
		var lowest: int = pair.min()
		check(game.SAVE_SLOTS.latest() == lowest, "slots %s saved in the same second: latest is the lowest, %d (got %d)" % [pair, lowest, game.SAVE_SLOTS.latest()])
		game.ui.show_title(true); game._ui_action("continue", null); await settle()
		check(focused_text().begins_with("Slot %d - " % lowest), "Continue preselects the lowest tied slot %d, focus '%s'" % [lowest, focused_text()])
		game.ui.close_menu()
	# a strictly newer slot beats a lower tied pair, in any position
	clean_saves()
	put(2, filled(1, "a")); put(3, filled(1, "b")); put(8, {"version": 1, "minutes": 1, "info": "c", "saved_at": 1700000001})
	check(game.SAVE_SLOTS.latest() == 8, "a newer slot beats older ones, got %d" % game.SAVE_SLOTS.latest())
	# a save without saved_at (0.3.3) is dated by its file, so it beats an old stamped save and loses to a far-future one
	clean_saves()
	put(4, {"version": 1, "minutes": 1, "info": "no stamp"})
	put(6, {"version": 1, "minutes": 1, "info": "old", "saved_at": 100})
	check(game.SAVE_SLOTS.latest() == 4, "an unstamped save is dated by its file (recent), so it beats saved_at 100, got %d" % game.SAVE_SLOTS.latest())
	put(8, {"version": 1, "minutes": 1, "info": "future", "saved_at": 4000000000})
	check(game.SAVE_SLOTS.latest() == 8, "a stamp in the far future wins, got %d" % game.SAVE_SLOTS.latest())
	# the real writer stamps whole seconds
	check(game._save_game(slot_path(9)), "stamp fixture writes")
	var at := float(stored(9).saved_at)
	check(at == floorf(at) and absf(at - Time.get_unix_time_from_system()) < 120.0, "a real save is stamped with the current unix second, got %s" % stored(9).saved_at)
	# Save preselects the first empty slot, wherever it is; with none empty it falls back to the latest
	clean_saves()
	for slot in range(2, 11): put(slot, filled(1, "full"))
	game.ui.show_pause(); game._ui_action("save", null); await settle()
	check(focused_text() == "Slot 1 - Empty", "slot 1 empty, 2-10 full: Save focuses slot 1, focus '%s'" % focused_text())
	game.ui.close_menu()
	clean_saves()
	for slot in range(1, 11): put(slot, filled(slot, "full %d" % slot))
	put(7, {"version": 1, "minutes": 7, "info": "full 7", "saved_at": 1700000099})
	game.ui.show_pause(); game._ui_action("save", null); await settle()
	check(focused_text().begins_with("Slot 7 - "), "all ten full: Save falls back to the latest slot (7), focus '%s'" % focused_text())
	game.ui.close_menu()
	clean_saves()
	for slot in range(1, 11): if slot != 10: put(slot, filled(1, "full"))
	game.ui.show_pause(); game._ui_action("save", null); await settle()
	check(focused_text() == "Slot 10 - Empty", "only slot 10 empty: Save focuses slot 10, focus '%s'" % focused_text())
	game.ui.close_menu()
	clean_saves()

# 8. The choice line: only a line that is exactly "&savegameinfo" becomes a slot label (dinkc.cpp:766).
func choice_line() -> void:
	clean_saves()
	put(3, filled(75, "Mid game"))
	check(game._interpolate_choice("&savegameinfo", {}, 3) == "Slot 3 - 1:15 - Mid game", "ordinal 3 reads slot 3, got '%s'" % game._interpolate_choice("&savegameinfo", {}, 3))
	check(game._interpolate_choice("  &SaveGameInfo ", {}, 3) == "Slot 3 - 1:15 - Mid game", "the match ignores case and surrounding blanks")
	check(game._interpolate_choice("&savegameinfo", {}, 4) == "Slot 4 - Empty", "ordinal 4 reads Empty")
	check(game._interpolate_choice("Slot &savegameinfo", {}, 3) != "Slot 3 - 1:15 - Mid game", "a longer line is not a slot label (it is plain text, got '%s')" % game._interpolate_choice("Slot &savegameinfo", {}, 3))
	clean_saves()

# 9. A new game after a load starts from nothing: minutes, info text (game.gd _new_game).
func new_game_after_load() -> void:
	clean_saves()
	put(2, filled(83, "Old game"))
	game.vm.globals["level"] = 3
	check(game._save_game(slot_path(3)), "new-game fixture writes")
	var fixture: Dictionary = stored(3)
	fixture["minutes"] = 83
	put(3, fixture)
	check(await call_dink("load_game", [3]) == 1 and game.play_minutes_base == 83, "new-game fixture: the load carries 83 minutes")
	await call_dink("set_save_game_info", ["Custom text"])
	await game._new_game()
	check(game.play_minutes_base == 0 and game._play_minutes() == 0, "a new game after a load starts at 0 minutes, got base %d total %d" % [game.play_minutes_base, game._play_minutes()])
	check(game.save_game_info == "Level &level", "a new game restores the stock info text, got '%s'" % game.save_game_info)
	check(game._save_game(slot_path(5)), "post-new-game save writes")
	var level := int(game.vm.globals.get("level", 0))
	check(game.SAVE_SLOTS.label(5) == "Slot 5 - 0:00 - Level %d" % level, "the new game's first save reads 0:00 and the stock text, got '%s'" % game.SAVE_SLOTS.label(5))
	clean_saves()

# 10. A slot the label calls Empty must not be what Continue or the title offers.
func unreadable_slot_is_not_offered() -> void:
	clean_saves()
	raw(slot_path(1), "this is not a save")
	check(game.SAVE_SLOTS.label(1) == "Slot 1 - Empty", "unreadable slot 1 reads Empty")
	check(game.SAVE_SLOTS.latest() == 0, "Continue does not preselect a slot the list calls Empty (latest %d)" % game.SAVE_SLOTS.latest())
	check(not game.SAVE_SLOTS.any_exists(), "the title does not offer Continue for a profile whose only file is unreadable")
	clean_saves()
	put(3, filled(5, "good"))
	put(7, {"version": 2, "minutes": 1, "info": "from a newer game"})
	check(game.SAVE_SLOTS.latest() == 3, "a newer-version file in slot 7 does not outrank the readable slot 3 (latest %d)" % game.SAVE_SLOTS.latest())
	clean_saves()

# 11. Save's automatic pick is the first slot with NO FILE, never the first that merely reads Empty: a file a newer
# build wrote (version 2) reads Empty here but is someone's save, and a stray Enter must not overwrite it. The player
# can still choose that slot by hand.
func save_never_picks_an_unreadable_file() -> void:
	clean_saves()
	put(1, {"version": 2, "minutes": 1, "info": "newer build"})
	raw(slot_path(2), "unreadable")
	check(game.SAVE_SLOTS.label(1) == "Slot 1 - Empty" and game.SAVE_SLOTS.label(2) == "Slot 2 - Empty", "fixture: slots 1 and 2 hold files that read Empty")
	game.ui.show_pause(); game._ui_action("save", null); await settle()
	check(focused_text() == "Slot 3 - Empty", "Save skips slots 1 and 2 (files that read Empty) and focuses slot 3, focus '%s'" % focused_text())
	var by_hand := false
	for button in choice_buttons():
		if button.text.begins_with("Slot 1 - "): by_hand = not button.disabled
	check(by_hand, "the player can still choose slot 1 by hand in the Save list")
	game.ui.close_menu()
	# every slot holds an unreadable file: no automatic pick is safe, the list still opens with all ten slots choosable
	for slot in range(1, 11): raw(slot_path(slot), "unreadable")
	game.ui.show_pause(); game._ui_action("save", null); await settle()
	check(choice_buttons().size() == 10, "ten unreadable files: the Save list still opens with ten slots (%d)" % choice_buttons().size())
	game.ui.close_menu()
	clean_saves()

func _run() -> void:
	game = GAME.new(); game.test_mode = true
	root.add_child(game); await process_frame
	game.vm.cancel_all(); game.set_physics_process(false)
	game.load_map(1, false); game.ui.close_menu(); game.ui.set_process(false)
	game.playing = true; game.test_mode = false
	check(game.world.screens.has("1") and game.entities.has(1), "fixture: screen 1 and the player exist")
	clean_saves()
	file_shapes()
	minute_formats()
	await live_minutes()
	await info_text()
	await loaded_floats()
	await slot_arguments()
	await preselection()
	choice_line()
	await unreadable_slot_is_not_offered()
	await save_never_picks_an_unreadable_file()
	await new_game_after_load()
	print("SAVE LABEL CLASS FAILURES ", JSON.stringify(failures))
	print("SAVE LABEL CLASS PASS" if failures.is_empty() else "SAVE LABEL CLASS FAIL")
	clean_saves()
	game.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
