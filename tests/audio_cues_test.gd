extends SceneTree
# Headless audio cue check (docs/AUDIO_FREEDINK_SWAP.md). Run with
# --headless (Godot then uses the Dummy audio driver): nothing is heard.
# Every shipped sound must load; every numbered sound slot and every music cue
# in the imported campaign must either resolve through the game's own
# _play_sound/_play_music or be one of the listed gaps below.
# Screen music goes through the game's own load_map, so a screen's music id is
# tested as the game reads it, not as a string handed to _play_music.

const GAME := preload("res://scripts/fps_game.gd")

# Original v1.08 sound files that GNU FreeDink has no free replacement for.
# FreeDink leaves these slots silent; so does this game.
const FREEDINK_SFX_GAPS := [
	"attack1.wav", "caveent.wav", "drag1.wav", "drag2.wav", "escape.wav", "flyby.wav",
	"hurt1.wav", "hurt2.wav", "knock.wav", "level.wav", "picker.wav", "pig1.wav",
	"pig2.wav", "pig3.wav", "pig4.wav", "quack.wav", "sel2.wav", "sel3.wav",
	"select.wav", "snarl1.wav", "snarl2.wav", "snarl3.wav", "spell1.wav", "splash.wav",
	"squish.wav", "steps.wav", "sword1.wav",
]
# Music. The original engine has no CD, so a 1000+N id (a CD-track cue) plays
# N.mid: GNU FreeDink 109.6 game_engine.cpp:334-339 (a screen's music) and
# dinkc_bindings.cpp:1264-1278 (playmidi, which then also tries the name as
# written, so playmidi("1003.mid") still plays 1003). A cue whose file is absent
# is left silent and the current track keeps playing (bgm.cpp:137-142).
# Every screen music id in world.json -> the file it plays ("" = no file).
# 100-103 and 107 are original v1.08 MIDIs with no FreeDink replacement;
# 4, 6, 8, 9, 10, 11, 15 and 16 (the CD tracks 1004 to 1016) likewise.
const SCREEN_MUSIC := {
	"-1": "", "1": "1.ogg", "100": "", "101": "", "102": "", "103": "", "104": "104.ogg",
	"105": "105.ogg", "106": "106.ogg", "107": "", "1002": "2.ogg", "1005": "5.ogg",
	"1007": "7.ogg", "1008": "", "1010": "", "1012": "12.ogg", "1013": "13.ogg", "1016": "",
}
# Every playmidi() argument in the story, by name without extension.
const PLAYMIDI_MUSIC := {
	"1003": "1003.ogg", "1004": "", "1005": "5.ogg", "1006": "", "1009": "", "1011": "",
	"1015": "", "1018": "18.ogg", "battle": "", "bullythe": "", "caveexpl": "",
	"dance": "dance.ogg", "denube": "denube.ogg", "insper": "insper.ogg", "love": "love.ogg",
	"lovin": "lovin.ogg", "wanderer": "",
}
# music_candidates(track, screen): the names to try, in order.
const CANDIDATES := [
	["1007", true, ["7"]], ["1007.0", true, ["7"]], ["1007", false, ["1007", "7"]],
	["1005.mid", false, ["1005", "5"]], ["1003.mid", false, ["1003", "3"]],
	["1000", true, ["1000"]], ["1001", true, ["1"]], ["105.0", true, ["105"]],
	["104", false, ["104"]], ["-1", true, ["-1"]], ["0", true, []], ["", false, []],
	["battle.mid", false, ["battle"]], ["1a", false, ["1a"]],
]

const SENTINEL := "denube"
const SENTINEL_FILE := "denube.ogg"

var failures: Array[String] = []

func _start_sentinel(game: Node) -> void:
	game.music.stop()
	game.last_music = ""
	game._play_music(SENTINEL)
	check(_current_file(game) == SENTINEL_FILE, "sentinel track did not start")

func _current_file(game: Node) -> String:
	if game.last_music == "" or game.music.stream == null:
		return ""
	return game.music.stream.resource_path.get_file()

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _collect_playmidi(node: Variant, out: Dictionary) -> void:
	if node is Dictionary:
		if str(node.get("op", "")) == "call" and str(node.get("name", "")).to_lower() == "playmidi":
			var args: Array = node.get("args", [])
			if not args.is_empty() and args[0] is Dictionary:
				out[str(args[0].get("value", ""))] = true
		for value in node.values():
			_collect_playmidi(value, out)
	elif node is Array:
		for value in node:
			_collect_playmidi(value, out)

func _run() -> void:
	var game := GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	game.vm.cancel_all()
	check(AudioServer.get_driver_name() == "Dummy", "Audio driver must be Dummy, got " + AudioServer.get_driver_name())

	# 1. Every manifest entry loads as a non-empty stream.
	var loaded := 0
	for kind in ["music", "effects"]:
		var entries: Dictionary = game.sounds.get(kind, {})
		for cue in entries:
			var path := "res://" + str(entries[cue]["path"])
			var stream: AudioStream = load(path) if ResourceLoader.exists(path) else null
			check(stream != null, "%s %s does not load: %s" % [kind, cue, path])
			if stream == null:
				continue
			loaded += 1
			var seconds := stream.get_length()
			print("AUDIO LOAD %s %s %s %.3f s" % [kind, cue, stream.get_class(), seconds])
			check(seconds > 0.0 or path.ends_with("/intro.wav"), "%s %s has no audio" % [kind, cue])
			if kind == "music":
				check(seconds > 1.0, "music %s is %.4f s long; its render is empty" % [cue, seconds])
	check(loaded == 39, "expected 39 shipped sounds, loaded %d" % loaded)

	# 2. The numbered sound registry from START.c, through the game's _play_sound.
	var gaps: Array = []
	var played := 0
	for slot in game.sound_slots:
		var path := str(game.sound_slots[slot])
		if ResourceLoader.exists(path):
			var id: int = game._play_sound(int(slot))
			check(id != 0, "sound slot %s (%s) did not start" % [slot, path.get_file()])
			if id != 0:
				played += 1
				print("AUDIO SLOT %s %s played" % [slot, path.get_file()])
		elif not gaps.has(path.get_file()):
			gaps.append(path.get_file())
	gaps.sort()
	check(gaps == FREEDINK_SFX_GAPS, "sound slots without a file changed: %s" % [gaps])
	print("AUDIO SLOTS played=%d freedink_gaps=%d" % [played, gaps.size()])

	# 3. The rule itself.
	check(game.has_method("music_candidates"), "the game has no music_candidates rule")
	if game.has_method("music_candidates"):
		for row in CANDIDATES:
			var got: Array = game.call("music_candidates", row[0], row[1])
			check(got == row[2], "music_candidates(%s, screen=%s) = %s, want %s" % [row[0], row[1], got, row[2]])

	# 4. Every screen music id in the campaign data, through the game's own
	# load_map (which reads the screen's music and hands it to _play_music).
	var screens: Dictionary = game.world.get("screens", {})
	var first_screen := {}
	for key in screens:
		var id := str(int(screens[key].get("music", 0)))
		if id != "0" and (not first_screen.has(id) or int(key) < int(first_screen[id])):
			first_screen[id] = key
	var ids: Array = first_screen.keys()
	ids.sort()
	var want_ids: Array = SCREEN_MUSIC.keys()
	want_ids.sort()
	check(ids == want_ids, "screen music ids in the data changed: %s" % [ids])
	# fps_game plays the Stonebrook music when a screen leaves nothing playing, so
	# each screen starts with a sentinel track (no screen uses it) and "silent"
	# means the sentinel is still the current track afterwards.
	var screen_played := 0
	for id in ids:
		_start_sentinel(game)
		game.load_map(int(first_screen[id]), false)
		var got := _current_file(game)
		if got == SENTINEL_FILE: got = ""
		var want: String = SCREEN_MUSIC.get(id, "?")
		check(got == want, "screen %s music %s plays '%s', want '%s'" % [first_screen[id], id, got, want])
		if got != "": screen_played += 1
		print("AUDIO SCREEN music %s (screen %s) -> %s" % [id, first_screen[id], got if got != "" else "silent (track kept)"])
	# A screen with no file leaves the current track playing.
	_start_sentinel(game)
	game.load_map(int(first_screen["1007"]), false)
	game.load_map(int(first_screen["1008"]), false)
	check(_current_file(game) == "7.ogg" and game.music.playing, "silent screen 1008 must leave track 7 playing, got '%s'" % _current_file(game))
	# Screens that share a track do not restart it (1007 and 7 are one track).
	game.music.seek(5.0)
	game.load_map(int(first_screen["1007"]), false)
	check(game.music.get_playback_position() >= 5.0, "re-entering a screen with the same music restarted it")
	game._play_music("7")
	check(game.music.get_playback_position() >= 5.0, "playmidi 7 restarted the track that screen 1007 plays")
	print("AUDIO SCREEN MUSIC played=%d silent=%d" % [screen_played, ids.size() - screen_played])

	# 5. Every playmidi() argument in the story, through _play_music.
	var cues := {}
	_collect_playmidi(game.vm.story, cues)
	var seen := {}
	for cue in cues:
		var name := str(cue).get_file().get_basename().to_lower()
		if name == "0" or name.is_empty():
			continue
		game.music.stop()
		game.last_music = ""
		game._play_music(str(cue))
		var got := _current_file(game)
		if got != "":
			print("AUDIO MUSIC %s -> %s %.3f s" % [cue, got, game.music.stream.get_length()])
		seen[name] = got
		check(PLAYMIDI_MUSIC.has(name), "playmidi(%s) is not in the expected list" % cue)
		check(got == PLAYMIDI_MUSIC.get(name, "?"), "playmidi(%s) plays '%s', want '%s'" % [cue, got, PLAYMIDI_MUSIC.get(name, "?")])
	var seen_names: Array = seen.keys()
	seen_names.sort()
	var want_names: Array = PLAYMIDI_MUSIC.keys()
	want_names.sort()
	check(seen_names == want_names, "playmidi names in the story changed: %s" % [seen_names])
	print("AUDIO MUSIC playmidi resolved=%d silent=%d" % [seen.values().filter(func(f): return f != "").size(), seen.values().filter(func(f): return f == "").size()])
	game.music.stop()

	if failures.is_empty():
		print("AUDIO CUES PASS")
		quit(0)
	else:
		print("AUDIO CUES FAIL: " + "; ".join(failures))
		quit(1)
