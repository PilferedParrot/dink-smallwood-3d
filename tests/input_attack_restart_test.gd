# Fixture skips world loading and campaign/DinkC progression. The inherited
# game _input/_unhandled_input and native GUI still receive physical events.
extends SceneTree
const GAME = preload("res://scripts/game.gd")
class ProbeGame extends GAME:
	var attacks := 0
	func _ready() -> void:
		_input_map()
		ui = UI.new()
		if get("bindings") != null: ui.set("bindings",get("bindings"))
		add_child(ui)
		ui.close_menu()
		playing = true
		set_physics_process(false)
	func _attack() -> void:
		attacks += 1

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var game := ProbeGame.new()
	root.add_child(game)
	await process_frame
	var phase := OS.get_cmdline_user_args()[0]
	if phase == "write":
		var b = game.get("bindings")
		if b != null:
			assert(b.set_bindings("attack",[b.key(KEY_K)]).ok)
		else:
			# Closest base path: change its live map and write the same settings
			# envelope. The restart must actually honor it for the gate to pass.
			InputMap.action_erase_events("attack")
			var key := InputEventKey.new()
			key.physical_keycode = KEY_K
			InputMap.action_add_event("attack",key)
			game._write_json("user://settings.json",{"bindings_v1":{"version":1,"contexts":{"2d":{"attack":[{"type":"key","physical":KEY_K}]}}}})
		print("ATTACK RESTART WRITE")
		quit()
		return
	for code in [KEY_K,KEY_SPACE]:
		var key := InputEventKey.new()
		key.physical_keycode = code
		key.keycode = code
		key.pressed = true
		Input.parse_input_event(key)
		await process_frame
		key.pressed = false
		Input.parse_input_event(key)
		await process_frame
		if code == KEY_K and game.attacks != 1:
			push_error("K failed to attack after restart")
			quit(1)
			return
	if game.attacks != 1:
		push_error("Old Space still attacks after remap")
		quit(1)
		return
	print("ATTACK RESTART PASS")
	quit()
