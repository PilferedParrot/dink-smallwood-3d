extends SceneTree

## Small, deterministic file-protocol host for external playtest agents.
## The game is paused while the command file is idle, so agent latency does not
## advance the campaign.  Run with --session-dir=/absolute/path.
const GAME := preload("res://scripts/fps_game.gd")
const MAX_HOLD := 120
const ACTION_KEYS := {"forward": KEY_W, "back": KEY_S, "left": KEY_A, "right": KEY_D,
        "sprint": KEY_SHIFT, "jump": KEY_SPACE, "attack": KEY_F, "magic": KEY_Q,
        "talk": KEY_E, "inventory": KEY_I, "map": KEY_M}
const MENU_KEYS := {"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT,
        "enter": KEY_ENTER, "space": KEY_SPACE, "escape": KEY_ESCAPE, "i": KEY_I,
        "ui_up": KEY_UP, "ui_down": KEY_DOWN, "ui_left": KEY_LEFT, "ui_right": KEY_RIGHT,
        "ui_accept": KEY_ENTER, "ui_cancel": KEY_ESCAPE}
class TickProbe extends Node:
	signal tick_done
	func _physics_process(_delta: float) -> void: tick_done.emit()
var session_dir := ""
var game
var command_number := 0
var simulation_frames := 0
var headless := false
var setup_screen := 407
var setup_x := 320.0
var setup_y := 390.0
var setup_yaw := 0.0
var setup_pitch := -0.08
var death_fixture := false
var tick_probe: TickProbe
var mode := "scenario"
var trace_path := ""

func _initialize() -> void:
	headless = DisplayServer.get_name().to_lower() == "headless"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--session-dir="): session_dir = arg.trim_prefix("--session-dir=")
		if arg.begins_with("--mode="): mode = arg.trim_prefix("--mode=")
		if arg.begins_with("--screen="): setup_screen = int(arg.trim_prefix("--screen="))
		if arg.begins_with("--x="): setup_x = float(arg.trim_prefix("--x="))
		if arg.begins_with("--y="): setup_y = float(arg.trim_prefix("--y="))
		if arg.begins_with("--yaw="): setup_yaw = float(arg.trim_prefix("--yaw="))
		if arg.begins_with("--pitch="): setup_pitch = float(arg.trim_prefix("--pitch="))
		if arg == "--death-fixture": death_fixture = true
	if session_dir.is_empty() or not session_dir.is_absolute_path():
		push_error("playtest session requires an absolute --session-dir")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(session_dir)
	trace_path = session_dir.path_join("trace.jsonl")
	_run.call_deferred()

func _run() -> void:
	game = GAME.new()
	root.add_child(game)
	tick_probe = TickProbe.new()
	tick_probe.process_physics_priority = 100
	root.add_child(tick_probe)
	await process_frame
	for _i in range(300):
		if game.entities.has(1): break
		await process_frame
	if not game.entities.has(1):
		_write_response({"ok": false, "error": "game did not initialize"}, "startup")
		quit(1)
		return
	if mode == "scenario":
		# Focused checks deliberately select a map and skip startup scripts. Keep
		# test_mode false so dialogue/input handling remains faithful.
		await game._new_game()
		game.vm.cancel_all()
		if not game.world.screens.has(str(setup_screen)):
			_write_response({"ok": false, "error": "setup screen does not exist: %d" % setup_screen}, "startup")
			quit(1)
			return
		game.load_map(setup_screen, false)
		await process_frame
		var p: Dictionary = game.entities.get(1, {})
		p["x"] = setup_x; p["y"] = setup_y
		game.entities[1] = p
		game.fps_yaw = setup_yaw; game.fps_pitch = setup_pitch
		game.playing = true
		game.changing = false
		game.ui.close_menu()
		game._sync_fps_camera()
	else:
		# Campaign starts at the real title screen produced by Game._ready(). No
		# map replacement, new-game call, inventory injection, or script skipping.
		await process_frame
		await process_frame
		await process_frame
	# Flush newly-created physics bodies before collecting the initial probes.
	await tick_probe.tick_done
	game._fps_update_mouse_mode()
	paused = true
	# Install the death fixture after physics is paused: the first requested
	# gameplay tick, rather than startup, must cause the actual damage.
	if death_fixture and mode == "scenario":
		# Bounded test setup: put the player at one synthetic touch attacker
		# with one health. The subsequent damage and restart are real input
		# and game paths; this fixture does not represent campaign progression.
		game.vm.globals["life"] = 1
		var attacker := {"x": setup_x, "y": setup_y, "active": 1, "hard": 1,
			"type": 1, "size": 100, "brain": 9, "touch_damage": 1,
			"hitpoints": 10, "script": "", "speed": 0, "dir": 2,
			"base_walk": 0, "base_idle": 0, "base_attack": -1,
			"base_hit": 0, "base_die": -1, "nohit": 0}
		game.entities[900001] = attacker
		game._create_visual(900001)
	var setup := {"mode": mode, "test_mode": false, "load_map_scripts": mode == "campaign",
		"death_fixture": death_fixture}
	if mode == "scenario":
		setup.merge({"screen": setup_screen, "x": setup_x, "y": setup_y, "yaw": setup_yaw})
	_write_response({"ok": true, "telemetry": _telemetry(), "setup": setup}, "startup")
	_poll.call_deferred()

func _poll() -> void:
	if not is_instance_valid(game): return
	var path := session_dir.path_join("command.json")
	if FileAccess.file_exists(path):
		var text := FileAccess.get_file_as_string(path)
		DirAccess.remove_absolute(path)
		var parsed = JSON.parse_string(text)
		if parsed is Dictionary:
			_trace({"kind": "command", "value": parsed})
			await _handle(parsed)
		else: _write_response({"ok": false, "error": "command.json must contain an object"}, "invalid")
	# Idle frames still run while the scene is paused. Avoid leaving a
	# SceneTreeTimer await alive when the player quits through the menu.
	await process_frame
	_poll.call_deferred()

func _handle(command: Dictionary) -> void:
	var id := str(command.get("id", str(command_number)))
	command_number += 1
	var kind := str(command.get("command", "observe"))
	var result := {"ok": true}
	if kind == "observe":
		result["telemetry"] = _telemetry()
	elif kind == "navigation_grid":
		result["navigation_grid"] = _navigation_grid()
	elif kind == "hold":
		result = await _hold(command)
	elif kind == "wait":
		result = await _wait(command)
	elif kind == "look":
		result = await _look(command)
	elif kind == "pause":
		result = await _raw_key(KEY_ESCAPE)
	elif kind == "menu_key":
		var key := int(command.get("key", -1))
		if command.get("key") is String:
			var name := str(command.get("key"))
			key = int(MENU_KEYS.get(name, -1))
		result = await _raw_key(key) if key in MENU_KEYS.values() else {"ok": false, "error": "key is not allowlisted"}
	elif kind == "screenshot":
		result = await _screenshot(command)
	elif kind == "quit":
		result["telemetry"] = _telemetry()
		_write_response(result, id)
		await process_frame
		quit(0)
		return
	else:
		result = {"ok": false, "error": "unknown command; use observe, navigation_grid, hold, wait, look, pause, menu_key, screenshot, quit"}
	if result.get("ok", false) and not result.has("telemetry"): result["telemetry"] = _telemetry()
	_write_response(result, id)

func _wait(command: Dictionary) -> Dictionary:
	var raw_frames: Variant = command.get("frames", 0)
	if not (raw_frames is float or raw_frames is int) or not is_finite(float(raw_frames)) or float(raw_frames) != floor(float(raw_frames)):
		return {"ok": false, "error": "frames must be an integer"}
	var frames := int(raw_frames)
	if frames < 0 or frames > MAX_HOLD: return {"ok": false, "error": "frames must be between 0 and 120"}
	await _advance(frames)
	paused = true
	return {"ok": true, "frames": frames}

func _navigation_grid() -> Dictionary:
	# Read-only planning evidence. The scene remains paused; scripts, position,
	# inventory, and simulated frame count are untouched by these collision probes.
	var rows: Array = []
	for y in range(0, 401, 5):
		var row := ""
		for x in range(0, 641, 5):
			row += "#" if game._blocked(Vector2(x, y), 1) else "."
		rows.append(row)
	return {"screen": game.current_screen, "step": 5, "origin": [0, 0], "rows": rows}

func _hold(command: Dictionary) -> Dictionary:
	var action := str(command.get("action", ""))
	var raw_frames: Variant = command.get("frames", 0)
	if not (raw_frames is float or raw_frames is int) or not is_finite(float(raw_frames)) or float(raw_frames) != floor(float(raw_frames)):
		return {"ok": false, "error": "frames must be an integer"}
	var frames := int(raw_frames)
	if not ACTION_KEYS.has(action): return {"ok": false, "error": "action is not allowlisted"}
	if frames < 0 or frames > MAX_HOLD: return {"ok": false, "error": "frames must be between 0 and 120"}
	var key := int(ACTION_KEYS[action])
	paused = false
	var down: InputEvent
	if action == "attack" or action == "magic":
		var mouse := InputEventMouseButton.new(); mouse.button_index = MOUSE_BUTTON_LEFT if action == "attack" else MOUSE_BUTTON_RIGHT; mouse.pressed = true; down = mouse
	else:
		var keyboard := InputEventKey.new(); keyboard.physical_keycode = key; keyboard.pressed = true; down = keyboard
	Input.parse_input_event(down)
	Input.flush_buffered_events()
	await _advance(frames)
	var up: InputEvent
	if action == "attack" or action == "magic":
		var mouse_up := InputEventMouseButton.new(); mouse_up.button_index = MOUSE_BUTTON_LEFT if action == "attack" else MOUSE_BUTTON_RIGHT; mouse_up.pressed = false; up = mouse_up
	else:
		var keyboard_up := InputEventKey.new(); keyboard_up.physical_keycode = key; keyboard_up.pressed = false; up = keyboard_up
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	paused = true
	return {"ok": true, "frames": frames}

func _look(command: Dictionary) -> Dictionary:
	if headless:
		return {"ok": false, "error": "mouse look requires a rendered session with captured input; rerun with --rendered"}
	var dx := float(command.get("dx", 0.0)); var dy := float(command.get("dy", 0.0))
	if is_nan(dx) or is_nan(dy) or is_inf(dx) or is_inf(dy): return {"ok": false, "error": "look delta must be finite"}
	if absf(dx) > 2000.0 or absf(dy) > 2000.0: return {"ok": false, "error": "look delta is bounded to +/-2000"}
	paused = false
	var event := InputEventMouseMotion.new(); event.relative = Vector2(dx, dy)
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _advance(1)
	paused = true
	return {"ok": true}

func _raw_key(key: int) -> Dictionary:
	if key < 0: return {"ok": false, "error": "invalid key"}
	paused = false
	var down := InputEventKey.new(); down.physical_keycode = key; down.keycode = key; down.pressed = true
	Input.parse_input_event(down)
	Input.flush_buffered_events()
	await _advance(1)
	var up := InputEventKey.new(); up.physical_keycode = key; up.keycode = key; up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	paused = true
	return {"ok": true}

func _advance(frames: int) -> void:
	paused = false
	for _i in range(frames):
		await tick_probe.tick_done
		simulation_frames += 1
	# The caller releases inputs before freezing the tree.

func _screenshot(command: Dictionary) -> Dictionary:
	if headless: return {"ok": false, "error": "screenshots require a rendered session; host is headless"}
	var requested := str(command.get("path", "screenshot.png"))
	var target := session_dir.path_join(requested) if not requested.is_absolute_path() else requested
	if not target.simplify_path().begins_with(session_dir.simplify_path() + "/"):
		return {"ok": false, "error": "screenshot path must remain inside session directory"}
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	await RenderingServer.frame_post_draw
	var image := get_root().get_texture().get_image()
	if image == null: return {"ok": false, "error": "viewport has no rendered image"}
	var err := image.save_png(target)
	return {"ok": err == OK, "path": target, "error": "could not save screenshot" if err != OK else ""}

func _telemetry() -> Dictionary:
	var p: Dictionary = game.entities.get(1, {})
	var pos := Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0)))
	var ui = game.ui
	var buttons: Array = []
	var focused := ""
	if is_instance_valid(game.ui.column):
		for child in game.ui.column.get_children():
			if child is Control and child.has_focus(): focused = str(child.name)
			if child is BaseButton: buttons.append({"text": child.text, "disabled": child.disabled, "focused": child.has_focus()})
	var entity_state: Array = []
	for id in game.entities:
		var entity: Dictionary = game.entities[id]
		entity_state.append({"id": int(id), "x": float(entity.get("x",0)), "y": float(entity.get("y",0)),
			"active": int(entity.get("active",1)), "script": str(entity.get("script","")),
			"brain": int(entity.get("brain",0)), "frozen": bool(entity.get("frozen",false)),
			"editor_num": int(entity.get("editor_num",0))})
	var script_entities: Array = []
	for entity in entity_state:
		if not str(entity.script).is_empty(): script_entities.append({"id": entity.id, "script": entity.script})
	return {"mode": mode, "screen": int(game.current_screen), "x": pos.x, "y": pos.y,
		"yaw": float(game.fps_yaw), "pitch": float(game.fps_pitch),
		"playing": bool(game.playing), "changing": bool(game.changing),
		"modal": bool(ui.modal), "page": str(ui.page), "dialogue": bool(ui.dialogue_mode),
		"frozen": bool(p.get("frozen", false)), "disabled": int(p.get("disabled", 0)),
		"nocontrol": int(p.get("nocontrol", 0)), "cooldown": float(game.attack_cooldown),
		"frame_count": simulation_frames, "cardinal_blocked": {"north": game._blocked(pos + Vector2(0, -8), 1),
		"south": game._blocked(pos + Vector2(0, 8), 1), "west": game._blocked(pos + Vector2(-8, 0), 1),
		"east": game._blocked(pos + Vector2(8, 0), 1)},
		"recent_dialogue": game.dialogue_log.slice(maxi(0, game.dialogue_log.size() - 5)),
		"ui": {"page": str(ui.page), "title": ui.page == "title", "dialogue": ui.dialogue_mode,
			"modal": ui.modal, "labels": _ui_labels(), "buttons": buttons, "focused": focused},
		"render_geometry": _render_geometry(),
		"globals": game.vm.globals.duplicate(true), "inventory": game.items.duplicate(true),
		"magic_inventory": game.magic_items.duplicate(true),
		"scripts": {"dialogue_busy": game.dialogue_busy, "vm_live_tasks": game.vm._live_tasks.size(),
			"generation": game.generation, "screen_script": str(game.world.screens.get(str(game.current_screen),{}).get("script","")),
			"entities": script_entities}, "entities": entity_state,
		"quest": {"visited": game.visited.duplicate(true), "locked": game.locked},
		"save": {"adventure": FileAccess.file_exists("user://adventure.json"), "session_path": session_dir}}

func _render_geometry() -> Dictionary:
	# Read-only geometry evidence catches a successful state load with missing
	# replacement meshes/colliders. Headless hosts still build these scene nodes.
	var models: Dictionary = {}
	var bodies: Dictionary = {}
	for visual in game.visuals.values():
		if not is_instance_valid(visual) or visual.is_queued_for_deletion(): continue
		var key := str(visual.get_meta("model_key", ""))
		if key not in ["wall", "cottage", "tower", "inn", "fence", "bridge"]: continue
		if visual.get_node_or_null("Model") != null: models[key] = int(models.get(key, 0)) + 1
		if visual.get_node_or_null("HitBody") != null: bodies[key] = int(bodies.get(key, 0)) + 1
	return {"structural_models": models, "structural_bodies": bodies}

func _ui_labels() -> Array:
	var labels: Array = []
	if is_instance_valid(game.ui.column):
		for child in game.ui.column.get_children():
			if child is Label: labels.append(str(child.text))
	return labels

func _write_response(value: Dictionary, id: String) -> void:
	value["id"] = id
	var tmp := session_dir.path_join("response.%s.tmp" % str(Time.get_ticks_usec()))
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify(value)); file.close()
	DirAccess.rename_absolute(tmp, session_dir.path_join("response.json"))
	_trace({"kind": "response", "value": value})

func _trace(value: Dictionary) -> void:
	if trace_path.is_empty(): return
	var file := FileAccess.open(trace_path, FileAccess.READ_WRITE)
	if file == null: file = FileAccess.open(trace_path, FileAccess.WRITE)
	if file == null: return
	file.seek_end(); file.store_string(JSON.stringify(value) + "\n"); file.close()
