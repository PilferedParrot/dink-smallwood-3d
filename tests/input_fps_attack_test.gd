# Isolated-profile FPS Attack contract. The write and read phases run in
# separate Godot processes. Read proves the real opening (_new_game), frees it,
# then creates an isolated outdoor combat instance with an equipped bow. That
# setup skips campaign progression. No _fps_attack override is used.
extends SceneTree

const GAME = preload("res://scripts/fps_game.gd")
const BINDINGS = preload("res://scripts/input_bindings.gd")
const PROJECTILE = preload("res://scripts/fps_projectile.gd")

var failures: Array[String] = []
var game
var arrows_created := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _on_child_entered(node: Node) -> void:
	if node.get_script() == PROJECTILE:
		print("PROJECTILE_ENTERED spell=", node.get("spell"))
	if node.get_script() == PROJECTILE and not bool(node.get("spell")):
		arrows_created += 1

func event(record: Dictionary, pressed: bool) -> void:
	var input: InputEvent = BINDINGS.to_event(record)
	input.pressed = pressed
	if input is InputEventKey:
		input.keycode = input.physical_keycode
	Input.parse_input_event(input)
	Input.flush_buffered_events()
	await process_frame

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	check(args.size() == 1 and args[0] in ["write", "read"], "Fixture needs write/read phase")
	if not failures.is_empty():
		quit(1)
		return
	if args[0] == "write":
		var registry = BINDINGS.new("fps")
		registry.load_settings()
		var result: Dictionary = registry.replace_binding("attack", 0, BINDINGS.key(KEY_K))
		check(result.ok, "Replace only the FPS mouse Attack slot with K")
		check(registry.events("attack") == [BINDINGS.key(KEY_K), BINDINGS.pad(JOY_BUTTON_X), BINDINGS.axis(JOY_AXIS_TRIGGER_RIGHT, 1)], "Other controller Attack slots survive replacement")
		print("FPS ATTACK WRITE PASS" if failures.is_empty() else "FPS ATTACK WRITE FAIL")
		quit(0 if failures.is_empty() else 1)
		return

	game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	check(game.bindings.events("attack") == [BINDINGS.key(KEY_K), BINDINGS.pad(JOY_BUTTON_X), BINDINGS.axis(JOY_AXIS_TRIGGER_RIGHT, 1)], "Restart loads K and preserves both controller Attack slots")
	await game._new_game()
	var expected_toast: String = "A travel bow is ready. %s to fire." % game.bindings.label("attack", false, "", true)
	check(game.ui.toast.text == expected_toast, "Opening bow toast uses the restarted Attack label")
	# P3b renamed trigger edges to readable words (InputBindings.event_label);
	# the P3a fixture's RT+ spelling already fails unchanged base9395488.
	check(game.ui.toast.text.contains("K") and game.ui.toast.text.contains("X") and game.ui.toast.text.contains("RT press") and not game.ui.toast.text.contains("Left click"), "Toast names all live Attack devices and omits replaced mouse slot")
	check(game.items.any(func(item: Dictionary): return str(item.get("script", "")) == "item-b1"), "Real opening equips starter bow")

	# The opening can keep a delayed dialogue freeze alive. Retire that instance
	# after proving its real toast, so it cannot alter the combat fixture later.
	game.vm.cancel_all()
	game.queue_free()
	await process_frame

	# Fresh test-mode outdoor instance: the setup supplies Fists/Bow and skips
	# campaign progression and arrival scripts. Combat, including _fps_attack,
	# InputMap dispatch and actual physics frames, remains the inherited game.
	game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	check(game.bindings.events("attack") == [BINDINGS.key(KEY_K), BINDINGS.pad(JOY_BUTTON_X), BINDINGS.axis(JOY_AXIS_TRIGGER_RIGHT, 1)], "Fresh combat instance loads the same persisted Attack slots")
	game.vm.cancel_all()
	game.load_map(439, false)
	await process_frame
	game.vm.cancel_all()
	game.items = [{"script":"item-fst", "name":"Fists", "seq":438, "frame":1}, {"script":"item-b1", "name":"Bow", "seq":0, "frame":1}]
	game.vm.globals["cur_weapon"] = 2
	game.playing = true
	game.changing = false
	game.entities[1]["frozen"] = false
	game.entities[1]["nocontrol"] = 0
	game.entities[1]["disabled"] = 0
	game.ui.close_menu()
	game.set_physics_process(false)
	game.attack_cooldown = 0.0
	game.fps_fire_held = false
	game.child_entered_tree.connect(_on_child_entered)
	check(str(game.items[int(game.vm.globals.get("cur_weapon", 1)) - 1].get("script", "")) == "item-b1", "Starter bow is active for real FPS attack")
	check(not game.entities[1].get("frozen", false), "Combat fixture begins unfrozen after opening transition")

	await event(BINDINGS.mouse(MOUSE_BUTTON_LEFT), true)
	game._physics_process(1.0 / 60.0)
	check(not Input.is_action_pressed("attack") and arrows_created == 0, "Replaced left mouse input cannot fire")
	await event(BINDINGS.mouse(MOUSE_BUTTON_LEFT), false)
	game._physics_process(1.0 / 60.0)

	await event(BINDINGS.key(KEY_K), true)
	check(Input.is_action_pressed("attack"), "Persisted physical K activates Attack")
	print("ATTACK_PRE held=", game.fps_fire_held, " modal=", game.ui.modal, " playing=", game.playing, " frozen=", game.entities[1].get("frozen"), " nocontrol=", game.entities[1].get("nocontrol"))
	check(not game.entities[1].get("frozen", false) and not game.ui.modal, "Opening scripts do not block the combat fixture at first K press")
	game._physics_process(1.0 / 60.0)
	print("ATTACK_POST arrows=", arrows_created, " cooldown=", game.attack_cooldown, " recoil=", game.fps_recoil, " held=", game.fps_fire_held)
	check(arrows_created == 1 and game.attack_cooldown > 0.0 and game.fps_recoil > 0.0, "Real FPS bow attack launches one arrow and starts recoil/cooldown")
	check(game.fps_fire_held, "Initial K press enters held-fire state")
	game.set_physics_process(true)
	for _i in 75:
		await physics_frame
	game.set_physics_process(false)
	check(arrows_created == 1 and is_zero_approx(game.attack_cooldown) and game.fps_fire_held, "Held K does not auto-repeat after cooldown")

	await event(BINDINGS.key(KEY_K), false)
	game._physics_process(1.0 / 60.0)
	check(not Input.is_action_pressed("attack") and not game.fps_fire_held, "Physical K release clears held-fire state")
	for _i in 10:
		game._physics_process(1.0 / 60.0)
	check(arrows_created == 1, "Release and idle ticks fire no extra arrows")
	await event(BINDINGS.key(KEY_K), true)
	check(not game.entities[1].get("frozen", false) and not game.ui.modal, "Combat remains enabled at second K press")
	game._physics_process(1.0 / 60.0)
	check(arrows_created == 2, "Fresh physical K press fires the second real arrow")
	await event(BINDINGS.key(KEY_K), false)
	game._physics_process(1.0 / 60.0)
	game.vm.cancel_all()
	game.queue_free()
	await process_frame
	print("FPS ATTACK READ PASS" if failures.is_empty() else "FPS ATTACK READ FAIL")
	quit(0 if failures.is_empty() else 1)
