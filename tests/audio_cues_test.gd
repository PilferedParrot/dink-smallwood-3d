extends SceneTree
# Headless audio cue check (docs/AUDIO_FREEDINK_SWAP.md). Run with
# --headless (Godot then uses the Dummy audio driver): nothing is heard.
# Every shipped sound must load; every numbered sound slot and every music cue
# in the imported campaign must either resolve through the game's own
# _play_sound/_play_music or be one of the listed gaps below.

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
# Music cues with no shipped file. 100-103, 107, battle, bullythe, caveexpl and
# wanderer are original v1.08 MIDIs without a FreeDink replacement; the 1000+
# numbers are CD-track cues that the current lookup does not map to a file.
const UNRESOLVED_MUSIC := [
	"-1", "100", "1002", "1004", "1005", "1006", "1007", "1008", "1009", "101", "1010",
	"1011", "1012", "1013", "1015", "1016", "1018", "102", "103", "107", "battle",
	"bullythe", "caveexpl", "wanderer",
]

var failures: Array[String] = []

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

	# 3. Every music cue in the campaign data, through the game's _play_music.
	var cues := {}
	for screen in game.world.get("screens", {}).values():
		cues[str(screen.get("music", 0))] = true
	_collect_playmidi(game.vm.story, cues)
	var unresolved: Array = []
	var resolved := 0
	for cue in cues:
		var name := str(cue).get_file().get_basename().to_lower()
		if name == "0" or name.is_empty():
			continue
		game.music.stop()
		game.last_music = ""
		game._play_music(str(cue))
		if game.last_music == name and game.music.stream != null:
			resolved += 1
			print("AUDIO MUSIC %s -> %s %.3f s" % [cue, game.music.stream.resource_path.get_file(), game.music.stream.get_length()])
		elif not unresolved.has(name):
			unresolved.append(name)
	unresolved.sort()
	check(unresolved == UNRESOLVED_MUSIC, "music cues without a file changed: %s" % [unresolved])
	print("AUDIO MUSIC resolved=%d unresolved=%d" % [resolved, unresolved.size()])
	game.music.stop()

	if failures.is_empty():
		print("AUDIO CUES PASS")
		quit(0)
	else:
		print("AUDIO CUES FAIL: " + "; ".join(failures))
		quit(1)
