# This scenario deliberately skips campaign progression. It retains the real
# game input handlers and physics consumers, with endpoint counters for attacks,
# spells, talk/equip and movement (matching the existing controller fixture).
extends SceneTree
const GAME = preload("res://scripts/fps_game.gd")
const BINDINGS = preload("res://scripts/input_bindings.gd")
class ProbeGame extends GAME:
	var attacks := 0
	var casts := 0
	var talks := 0
	var equipped := -1
	var moved := Vector2.ZERO
	func _fps_attack() -> void: attacks += 1
	func _cast() -> void: casts += 1
	func _talk() -> void: talks += 1
	func _equip(index: int, magic: bool) -> void:
		if not magic: equipped = index; vm.globals.cur_weapon = index+1
	func _move_entity(_id: int, displacement: Vector2, _ignore := false) -> void: moved += displacement
	func _transitions(_scripted := false, _from: Vector2 = Vector2.INF) -> void: pass
	func _update_ai(_delta: float) -> void: pass
var failures: Array[String] = []
var game
func _init() -> void: _run.call_deferred()
func check(ok: bool, text: String) -> void:
	if not ok: failures.append(text);push_error(text)
func event(record: Dictionary, pressed: bool) -> void:
	var e: InputEvent = BINDINGS.to_event(record)
	e.pressed = pressed
	if e is InputEventKey: e.keycode = e.physical_keycode
	Input.parse_input_event(e)
	Input.flush_buffered_events()
	await process_frame
func tap(code: int) -> void:
	await event(BINDINGS.key(code),true)
	await event(BINDINGS.key(code),false)
func _run() -> void:
	if OS.get_cmdline_user_args()[0] == "write":
		var b := BINDINGS.new()
		b.load_settings()
		for pair in [["attack",KEY_K],["talk",KEY_J],["magic",KEY_L],["jump",KEY_H],["up",KEY_U],["sprint",KEY_G],["look_right",KEY_F13],["weapon_1",KEY_F14],["weapon_next",KEY_F15],["inventory",KEY_F16],["map",KEY_F17],["pause",KEY_F18],["help",KEY_F19]]:
			check(b.set_bindings(pair[0],[BINDINGS.key(pair[1])]).ok,"Persist FPS action "+pair[0])
		print("FPS REMAP WRITE")
		quit(0 if failures.is_empty() else 1)
		return
	game = ProbeGame.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.vm.cancel_all()
	game.playing = true
	game.changing = false
	game.entities[1].frozen = false
	game.ui.close_menu()
	game.items = [{"name":"Fists","script":"item-fst","seq":438,"frame":1},{"name":"Bow","script":"item-b1","seq":0,"frame":1}]
	game.vm.globals.cur_weapon = 1
	await event(BINDINGS.key(KEY_K),true)
	game._physics_process(1.0/60)
	await event(BINDINGS.key(KEY_K),false)
	game._physics_process(1.0/60)
	check(game.attacks == 1,"Restarted K reaches FPS attack polling")
	await event(BINDINGS.mouse(MOUSE_BUTTON_LEFT),true)
	game._physics_process(1.0/60)
	await event(BINDINGS.mouse(MOUSE_BUTTON_LEFT),false)
	game._physics_process(1.0/60)
	check(game.attacks == 1,"Former left click cannot attack")
	await event(BINDINGS.key(KEY_L),true)
	game._physics_process(1.0/60)
	await event(BINDINGS.key(KEY_L),false)
	game._physics_process(1.0/60)
	check(game.casts == 1,"Remapped magic reaches polling")
	await tap(KEY_J)
	await tap(KEY_E)
	check(game.talks == 1,"Remapped talk reaches handler; old E does not")
	game.moved = Vector2.ZERO
	await event(BINDINGS.key(KEY_W),true)
	game._fps_move_player(0.1)
	await event(BINDINGS.key(KEY_W),false)
	check(game.moved == Vector2.ZERO,"Old W cannot move")
	await event(BINDINGS.key(KEY_U),true)
	game._fps_move_player(0.1)
	var walking: float = game.moved.length()
	game.moved = Vector2.ZERO
	await event(BINDINGS.key(KEY_G),true)
	game._fps_move_player(0.1)
	check(walking > 0 and is_equal_approx(game.moved.length()/walking,1.55),"Remapped movement and sprint reach consumers")
	await event(BINDINGS.key(KEY_U),false)
	await event(BINDINGS.key(KEY_G),false)
	var yaw: float = game.fps_yaw
	await event(BINDINGS.key(KEY_F13),true)
	game._fps_update_controller_look(0.1)
	await event(BINDINGS.key(KEY_F13),false)
	check(game.fps_yaw < yaw,"Keyboard binding drives look consumer")
	check(game.bindings.look_label().contains("right F13"),"Look labels name remapped direction")
	await tap(KEY_SPACE)
	check(game.fps_vertical_velocity == 0,"Old Space cannot jump")
	await event(BINDINGS.key(KEY_H),true)
	game._fps_update_jump(0.1)
	await event(BINDINGS.key(KEY_H),false)
	check(game.fps_jump_height > 0,"Remapped jump reaches consumer")
	await tap(KEY_F14)
	check(game.equipped == 0,"Remapped quick slot reaches equip")
	await tap(KEY_F15)
	check(game.equipped == 1,"Remapped next weapon reaches cycle")
	await tap(KEY_F16)
	check(game.ui.page == "inventory","Remapped inventory opens equipment")
	await tap(KEY_ESCAPE)
	await tap(KEY_F18)
	check(game.ui.page == "pause","Remapped pause opens menu")
	await tap(KEY_ESCAPE)
	await tap(KEY_F19)
	check(game.ui.hint_backing.visible,"Remapped help recalls strip")
	await tap(KEY_F17)
	check(game.ui.page == "dialogue" and game.ui.timed_text.contains("map"),"Remapped map dispatches original BUTTON6")
	game.vm.cancel_all()
	game.queue_free()
	await process_frame
	print("FPS REMAP PASS" if failures.is_empty() else "FPS REMAP FAIL "+str(failures.size()))
	quit(0 if failures.is_empty() else 1)
