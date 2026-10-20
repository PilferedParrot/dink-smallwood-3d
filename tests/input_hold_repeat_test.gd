# A2: sprint hold/toggle and attack repeat-while-held, through the real input
# path (InputMap events -> fps_game._input / _physics_process). Setup skips
# campaign progression: a fresh test-mode game on map 439 with Fists equipped.
# Original: FreeDink 109.6 attack is press-edge only (brain_keyboard.cpp:294,
# update_frame.cpp:126-133) and has no run key (brain_keyboard.cpp:484-531), so
# repeat is an option (default off) and sprint defaults to hold.
extends SceneTree
const GAME = preload("res://scripts/fps_game.gd")
const BINDINGS = preload("res://scripts/input_bindings.gd")
const DT := 1.0 / 60.0

class ProbeGame extends GAME:
	var fired := 0       # attacks that really started a swing (cooldown 0 -> >0)
	var moved := Vector2.ZERO
	var ticks := 0
	var swing_ticks: Array[int] = []
	func _physics_process(delta: float) -> void:
		ticks += 1
		super(delta)
	func _fps_attack() -> void:
		var before := attack_cooldown
		super()
		if before <= 0.0 and attack_cooldown > 0.0:
			fired += 1
			swing_ticks.append(ticks)
	func _move_entity(_id: int, displacement: Vector2, _ignore := false) -> void: moved += displacement
	func _transitions(_scripted := false, _from: Vector2 = Vector2.INF) -> void: pass
	func _update_ai(_delta: float) -> void: pass

var failures: Array[String] = []
var game: ProbeGame

func _init() -> void: _run.call_deferred()
func check(ok: bool, text: String) -> void:
	if not ok: failures.append(text); push_error(text)
func event(record: Dictionary, pressed: bool) -> void:
	var e: InputEvent = BINDINGS.to_event(record)
	e.pressed = pressed
	if e is InputEventKey: e.keycode = e.physical_keycode
	Input.parse_input_event(e)
	Input.flush_buffered_events()
	await process_frame
func step(n: int) -> void:
	for _i in n: game._physics_process(DT)
# Walk speed of one 0.1 s step with W held (no sprint), measured not assumed.
func step_move(seconds: float) -> float:
	game.moved = Vector2.ZERO
	var n := roundi(seconds / DT)
	for _i in n: game._physics_process(DT)
	return game.moved.length() / float(n)

func new_game(extra: Dictionary) -> void:
	if game != null:
		game.vm.cancel_all()
		game.queue_free()
		await process_frame
	game = ProbeGame.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.vm.cancel_all()
	game.playing = true
	game.changing = false
	game.entities[1].frozen = false
	game.entities[1].nocontrol = 0
	game.ui.close_menu()
	game.items = [{"name":"Fists","script":"item-fst","seq":438,"frame":1}]
	game.vm.globals.cur_weapon = 1
	for key in extra: game.settings[key] = extra[key]
	game._apply_settings()
	game.attack_cooldown = 0.0
	game.fps_fire_held = false

func find_buttons(node: Node, out: Dictionary) -> void:
	if node is Button and node.has_meta("setting_key"): out[str(node.get_meta("setting_key"))] = node
	for child in node.get_children(): find_buttons(child, out)

func min_gap() -> int:
	var gap := 1 << 30
	for i in range(1, game.swing_ticks.size()): gap = mini(gap, game.swing_ticks[i] - game.swing_ticks[i - 1])
	return gap

func hold_count(frames: int) -> int:
	game.fired = 0
	game.swing_ticks.clear()
	game.attack_cooldown = 0.0
	await event(BINDINGS.key(KEY_K), true)
	for i in frames:
		game._physics_process(DT)
		if i < 40 and OS.get_environment("HOLD_DEBUG") == "1": print("t", i, " cd=", snappedf(game.attack_cooldown, 0.001), " nc=", game.entities[1].get("nocontrol"), " fr=", game.entities[1].get("frozen"), " armed=", game.fps_repeat_armed, " held=", game.fps_fire_held, " modal=", game.ui.modal, " fired=", game.fired)
	await event(BINDINGS.key(KEY_K), false)
	step(2)
	return game.fired

# Press-spam over the same number of physics ticks as hold_count(frames).
func spam_count(frames: int) -> int:
	game.fired = 0
	game.swing_ticks.clear()
	game.attack_cooldown = 0.0
	for _i in frames / 2:
		await event(BINDINGS.key(KEY_K), true)
		game._physics_process(DT)
		await event(BINDINGS.key(KEY_K), false)
		game._physics_process(DT)
	return game.fired

func _run() -> void:
	var phase := OS.get_cmdline_user_args()[0]
	if phase == "write":
		await new_game({})
		var registry := BINDINGS.new("fps")
		registry.load_settings()
		check(registry.set_bindings("attack", [BINDINGS.key(KEY_K)]).ok, "bind attack to K")
		check(registry.set_bindings("sprint", [BINDINGS.key(KEY_G)]).ok, "bind sprint to G")
		await new_game({})
		game.ui.show_settings(game.settings)
		var buttons := {}
		find_buttons(game.ui.root, buttons)
		check(buttons.has("sprint_mode") and buttons.has("attack_repeat"), "Settings page lists sprint mode and attack repeat")
		check(not buttons.sprint_mode.button_pressed and not buttons.attack_repeat.button_pressed, "Defaults: sprint holds, attack does not repeat")
		check(buttons.sprint_mode.text.begins_with("Sprint: Hold") and buttons.attack_repeat.text.ends_with("Off"), "Controls name the default behaviour")
		buttons.sprint_mode.button_pressed = true
		buttons.attack_repeat.button_pressed = true
		check(buttons.sprint_mode.text.begins_with("Sprint: Toggle") and buttons.attack_repeat.text.ends_with("On"), "Controls name the changed behaviour")
		check(game.settings.sprint_mode == "toggle" and game.settings.attack_repeat == true, "Settings page reaches game.settings")
		print("HOLD REPEAT WRITE PASS" if failures.is_empty() else "HOLD REPEAT WRITE FAIL")
		quit(0 if failures.is_empty() else 1)
		return

	# ---- read phase: persisted across a restart ----
	await new_game({})
	check(game.settings.get("sprint_mode") == "toggle" and game.settings.get("attack_repeat") == true, "Sprint mode and attack repeat persist across restart")
	var hint: String = game.ui._gameplay_hint()
	check(hint.contains("G  Sprint (press to toggle)"), "Gameplay hint names the bound sprint key and toggle mode: " + hint)
	check(game.ui._controls_text().contains("Sprint: G (press to toggle)"), "Controls text names sprint mode: " + game.ui._controls_text())
	game.settings.sprint_mode = "hold"
	game._apply_settings()
	check(game.ui._gameplay_hint().contains("G  Hold to sprint"), "Hold mode hint says hold")

	# ---- attack: default is press-only (the original) ----
	await new_game({"attack_repeat": false})
	check(await hold_count(150) == 1, "Default: a held attack fires once (FreeDink press-edge)")
	var spam := await spam_count(150)
	check(spam > 1, "Press-spam fires repeatedly (control: the counter can count > 1): %d" % spam)

	# ---- attack repeat on ----
	await new_game({"attack_repeat": true})
	var held := await hold_count(150)
	spam = await spam_count(150)
	check(held > 1, "Option on: held attack repeats: %d" % held)
	var swing_ticks_hold := game.swing_ticks.duplicate()
	# The swing's own timing is the floor for both: 0.45 s = 27 ticks at 60 Hz.
	# The fastest possible press cycle needs a tick that sees the button up
	# (2 ticks), so spam can land 1 tick later than a hold at the boundary.
	var swing_ticks := ceili(0.45 / DT)
	game.swing_ticks = swing_ticks_hold
	check(min_gap() >= swing_ticks, "Held repeat never swings faster than the 0.45 s swing (min gap %d ticks)" % min_gap())
	check(held <= int(150.0 / swing_ticks) + 1, "Held repeat count within the swing-time bound: %d" % held)
	check(held == 6, "Held repeat swings once per 0.45 s cooldown: %d in 150 ticks" % held)
	check(spam >= 1 and held >= spam and held - spam <= 1, "Repeat stays within one tick-aligned swing of the fastest press-spam (held %d, spam %d)" % [held, spam])
	# stops on release
	await event(BINDINGS.key(KEY_K), true)
	step(5)
	await event(BINDINGS.key(KEY_K), false)
	game.fired = 0
	step(120)
	check(game.fired == 0, "No attack after release")

	# ---- look-alikes: nothing fires through a menu, choice or freeze ----
	game.attack_cooldown = 0.0
	game.fired = 0
	game.ui.show_pause()
	await event(BINDINGS.key(KEY_K), true)
	step(120)
	check(game.fired == 0, "Held attack during pause fires nothing")
	game.ui.close_menu()
	step(120)
	check(game.fired == 0, "Menu closed with attack still held: no repeat without a fresh press")
	await event(BINDINGS.key(KEY_K), false)
	step(2)
	await event(BINDINGS.key(KEY_K), true)
	step(1)
	check(game.fired == 1, "A fresh press after the menu fires")
	await event(BINDINGS.key(KEY_K), false)
	step(2)
	# a repeat already running when a menu opens must not resume after it closes
	step(60) # let the previous swing's animation end
	game.attack_cooldown = 0.0
	game.fired = 0
	await event(BINDINGS.key(KEY_K), true)
	step(1)
	check(game.fired == 1 and game.fps_repeat_armed, "Repeat armed by a real press")
	game.ui.show_pause()
	step(120)
	game.ui.close_menu()
	step(120)
	check(game.fired == 1, "Menu opened mid-repeat and closed with attack held: no resumed repeat")
	await event(BINDINGS.key(KEY_K), false)
	step(2)
	game.attack_cooldown = 0.0
	game.fired = 0
	game.ui.show_choices("Pick", ["One", "Two"])
	await event(BINDINGS.key(KEY_K), true)
	step(120)
	check(game.fired == 0, "Held attack during a choice fires nothing")
	game.ui.close_menu()
	await event(BINDINGS.key(KEY_K), false)
	step(2)
	game.attack_cooldown = 0.0
	game.fired = 0
	await event(BINDINGS.key(KEY_K), true)
	step(1)
	check(game.fired == 1, "Armed by a real press")
	game.entities[1].frozen = true
	step(120)
	check(game.fired == 1, "Frozen (dialogue/script): repeat fires nothing")
	game.entities[1].frozen = false
	step(120)
	check(game.fired == 1, "Unfrozen with attack still held: no repeat until a fresh press")
	await event(BINDINGS.key(KEY_K), false)
	step(2)
	game.entities[1].nocontrol = 1
	game.attack_cooldown = 0.0
	await event(BINDINGS.key(KEY_K), true)
	step(120)
	check(game.fired == 1, "nocontrol: press and repeat fire nothing")
	await event(BINDINGS.key(KEY_K), false)
	game.entities[1].nocontrol = 0
	step(2)

	# ---- sprint ----
	await new_game({"sprint_mode": "hold"})
	await event(BINDINGS.key(KEY_G), false)
	await event(BINDINGS.key(KEY_W), true)
	var walk := step_move(0.3)
	check(walk > 0.0, "Walking moves (control)")
	await event(BINDINGS.key(KEY_G), true)
	check(is_equal_approx(step_move(0.3) / walk, 1.55), "Hold: sprint while held")
	await event(BINDINGS.key(KEY_G), false)
	check(is_equal_approx(step_move(0.3) / walk, 1.0), "Hold: releasing ends sprint")
	await event(BINDINGS.key(KEY_W), false)

	await new_game({"sprint_mode": "toggle"})
	await event(BINDINGS.key(KEY_W), true)
	check(is_equal_approx(step_move(0.3) / walk, 1.0), "Toggle: not sprinting before the toggle")
	await event(BINDINGS.key(KEY_G), true)
	await event(BINDINGS.key(KEY_G), false)
	check(is_equal_approx(step_move(0.5) / walk, 1.55), "Toggle: one tap sprints with the key released")
	check(game.ui.sprint_active and game.ui._gameplay_hint().contains("Sprint ON"), "Toggle: hint shows the sprint is on")
	await event(BINDINGS.key(KEY_G), true)
	await event(BINDINGS.key(KEY_G), false)
	check(is_equal_approx(step_move(0.3) / walk, 1.0) and not game.ui.sprint_active, "Toggle: second tap ends sprint")
	# a toggle made while standing still waits for movement
	await event(BINDINGS.key(KEY_W), false)
	await event(BINDINGS.key(KEY_G), true)
	await event(BINDINGS.key(KEY_G), false)
	step(30)
	await event(BINDINGS.key(KEY_W), true)
	check(is_equal_approx(step_move(0.3) / walk, 1.55), "Toggle set while stationary survives until the player moves")
	# stop ends it; a one-frame direction-change gap does not
	await event(BINDINGS.key(KEY_W), false)
	step(3)
	await event(BINDINGS.key(KEY_W), true)
	check(is_equal_approx(step_move(0.3) / walk, 1.55), "Toggle: a 3-frame gap between directions keeps sprint")
	await event(BINDINGS.key(KEY_W), false)
	step(30)
	await event(BINDINGS.key(KEY_W), true)
	check(is_equal_approx(step_move(0.3) / walk, 1.0) and not game.ui.sprint_active, "Toggle: stopping ends sprint")
	# menu, pause, freeze, screen change each end it
	for cause in ["modal", "frozen", "nocontrol", "changing"]:
		await event(BINDINGS.key(KEY_G), true)
		await event(BINDINGS.key(KEY_G), false)
		check(is_equal_approx(step_move(0.3) / walk, 1.55), "Toggle on before " + cause)
		match cause:
			"modal": game.ui.show_pause()
			"frozen": game.entities[1].frozen = true
			"nocontrol": game.entities[1].nocontrol = 1
			"changing": game.changing = true
		step(2)
		match cause:
			"modal": game.ui.close_menu()
			"frozen": game.entities[1].frozen = false
			"nocontrol": game.entities[1].nocontrol = 0
			"changing": game.changing = false
		check(is_equal_approx(step_move(0.3) / walk, 1.0) and not game.ui.sprint_active, "Toggle ends on " + cause)
	# a tap while a menu is open does not latch
	game.ui.show_pause()
	await event(BINDINGS.key(KEY_G), true)
	await event(BINDINGS.key(KEY_G), false)
	game.ui.close_menu()
	check(is_equal_approx(step_move(0.3) / walk, 1.0), "Sprint key inside a menu does not toggle")
	# switching back to hold drops the latch
	await event(BINDINGS.key(KEY_G), true)
	await event(BINDINGS.key(KEY_G), false)
	game.settings.sprint_mode = "hold"
	game._apply_settings()
	check(is_equal_approx(step_move(0.3) / walk, 1.0), "Switching to hold clears a toggled sprint")
	await event(BINDINGS.key(KEY_W), false)

	game.vm.cancel_all()
	print("HOLD REPEAT READ PASS" if failures.is_empty() else "HOLD REPEAT READ FAIL")
	quit(0 if failures.is_empty() else 1)
