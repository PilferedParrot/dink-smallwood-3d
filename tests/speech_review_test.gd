extends SceneTree
## Review class controls: scenario setup, original savebot talk procedure and
## real menu/Talk input. No campaign progression claim.
const GAME = preload("res://scripts/fps_game.gd")
class ProbeGame extends GAME:
	var talk_count := 0
	func _talk() -> void: talk_count += 1
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
func waiting_line() -> void:
	await game.dink_call("say_stop", ["A script waits while Dink is free.",1], {})
func machine_talk(id: int) -> void:
	await game.vm.run("savebot", "talk", id)
	savebot_done = true
func natural_reading_floor() -> void:
	# Natural source SAY, S1-H2-2.talk:8; no explicit sp_kill in that procedure.
	# P2 keeps a reading floor even when the whole sentence fits on the card.
	var text := "The old lady has a ton of liquor up here!"
	var handle: int = await game.dink_call("say", [text,1], {})
	await settle()
	var line: Dictionary = game.ui.speech_lines[handle-game.TEXT_SPRITE_BASE]
	var reading: float = game.ui.speech_reading_seconds(text)
	check(game.ui.source_speech_msec(text) == 3157 and reading > 3.529, "P2 fixture has a reading floor above source natural TTL")
	check(int(line.expires)-int(line.born) == ceili(reading*1000), "P2 natural lifetime keeps the whole reading budget")
	game.ui._process(3.2)
	check(int(await game.dink_call("sp_active", [handle], {})) == 1, "P2 natural line lives beyond its shorter source TTL")
	game.ui._process(0.4)
	check(int(await game.dink_call("sp_active", [handle], {})) == 0, "P2 natural line expires after reading floor")
	for waits in [false,true]:
		game.ui.speech_waits_for_me = waits
		var id: int = game.ui.show_speech(text,"Dink",1,3157,true)
		await settle()
		game.ui.set_speech_ttl(id,1)
		check(not game.ui.is_speech_active(id), "P2 explicit deadline overrides reading floor and waits option=" + str(waits))
	game.ui.speech_waits_for_me = false
func ambient_option() -> void:
	game.ui.speech_waits_for_me = true
	for cmd in ["say", "say_xy"]:
		game.ui.cancel_speech()
		var id: int = await game.dink_call(cmd, ["Ambient line.",1,40], {})
		await settle()
		check(not game.ui.speech_dismiss_hint.visible, "F1 " + cmd + " has no dismissal hint when option is on")
		game.ui._process(3)
		check(int(await game.dink_call("sp_active", [id], {})) == 0, "F1 " + cmd + " keeps natural lifetime with option on")
		game.ui.cancel_speech()
		await game.dink_call(cmd, ["Talk must still reach gameplay.",1,40], {})
		await settle()
		var before: int = game.talk_count
		await tap(KEY_E)
		check(game.talk_count == before + 1, "F1 " + cmd + " cannot swallow gameplay Talk")
	# Source owner1000 permits independent XY lines; a modal-menu burst must
	# drain naturally after resume rather than become a dismissal backlog.
	game.ui.cancel_speech(); game.ui.show_pause()
	var ids: Array[int] = []
	for _i in 20: ids.append(int(await game.dink_call("say_xy", ["Queued ambient.",1,40], {})))
	game.ui.close_menu(); await settle()
	game.ui._process(3); await settle()
	for id in ids:
		check(int(await game.dink_call("sp_active", [id], {})) == 0, "F1 queued ambient burst expires without Talk")
	check(game.ui.speech_lines.is_empty(), "F1 no ambient dismissal backlog remains")
	game.ui.cancel_speech(); game.ui.speech_waits_for_me = false
func saving() -> void:
	# FreeDink109.6 dinkc_bindings.cpp:1316-1319 and savegame.cpp:348-490
	# delegate/write without speech, freeze, choice or VM-task state gates.
	game.entities[1].frozen = false; game.entities[1].nocontrol = 0
	waiting_line(); await settle()
	check(game.dialogue_busy and not game.ui.modal, "F3 fixture has an unfrozen waiting script")
	check(game._save_game("user://speech-review-free.json"), "F3 freely walking speech cannot refuse save")
	game.entities[1].frozen = true; game.entities[1].nocontrol = 1
	var saved: bool = game._save_game("user://speech-review-frozen.json")
	check(saved, "F3 DinkC save contract permits explicit freeze")
	if saved:
		check(game._load_game("user://speech-review-frozen.json"), "F3 frozen save reloads")
		check(not game.entities[1].get("frozen",false) and int(game.entities[1].get("nocontrol",0)) == 0, "F3 reload cannot retain unsaved freeze/nocontrol continuations")
	game.ui.cancel_speech(); game.vm.cancel_all(); await settle()
	game.entities[1].frozen = false; game.entities[1].nocontrol = 0
	# The source save machine itself freezes, presents two choice groups,
	# unfreezes and calls save_game: SAVEBOT.c:18-48. Execute that source path.
	var screen := 0
	for key in game.world.screens:
		for sprite in game.world.screens[key].get("sprites",[]):
			if str(sprite.get("script","")).to_lower() == "savebot": screen = int(key); break
		if screen != 0: break
	check(screen != 0, "F3 source map contains a save machine")
	game.load_map(screen,false)
	var machine := 0
	for id in game.entities:
		if str(game.entities[id].get("script","")).to_lower() == "savebot": machine = int(id); break
	check(machine > 1, "F3 live source save machine found")
	DirAccess.remove_absolute("user://adventure.json")
	machine_talk(machine); await settle()
	check(game.entities[1].frozen and game.ui.dialogue_mode, "F3 source savebot freezes Dink and opens first choice")
	await tap(KEY_ENTER)
	check(game.ui.dialogue_mode and not game.entities[1].frozen, "F3 source savebot opens its slot choice")
	await tap(KEY_ENTER)
	check(savebot_done and FileAccess.file_exists("user://adventure.json"), "F3 source savebot writes save through real choice input")
	check(not game.entities[1].frozen, "F3 source savebot releases player")
func _run() -> void:
	game = ProbeGame.new(); game.test_mode = true
	root.add_child(game); await process_frame
	game.vm.cancel_all(); game.set_physics_process(false)
	game.load_map(439,false); game.ui.close_menu(); game.ui.set_process(false)
	game.playing = true; game.test_mode = false
	await natural_reading_floor()
	await ambient_option()
	await saving()
	game.ui.cancel_speech(); game.vm.cancel_all(); await settle()
	game.queue_free(); await process_frame
	print("SPEECH REVIEW FAILURES ",JSON.stringify(failures))
	print("SPEECH REVIEW PASS" if failures.is_empty() else "SPEECH REVIEW FAIL")
	quit(0 if failures.is_empty() else 1)
