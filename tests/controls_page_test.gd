# Physical-input Controls acceptance fixture. Campaign progression is skipped.
extends SceneTree
const GAME = preload("res://scripts/fps_game.gd")
var game
var failures: Array[String] = []
var device := "keyboard"
var phase := "write"
var out := ""
var scale := 1.0
var capture_frames := false
var window_size := Vector2i(1280,800)
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); push_error(message)
func settle(n := 4) -> void:
	for i in n: await process_frame
func key(code: int) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	await settle(2)
	e.pressed = false
	Input.parse_input_event(e)
	await settle()
func pad(code: int) -> void:
	var e := InputEventJoypadButton.new()
	e.device = 3
	e.button_index = code
	e.pressed = true
	Input.parse_input_event(e)
	await settle(2)
	e.pressed = false
	Input.parse_input_event(e)
	await settle()
func axis(index: int, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = 3
	e.axis = index
	e.axis_value = value
	Input.parse_input_event(e)
	await settle()
func mouse(position: Vector2, code := MOUSE_BUTTON_LEFT) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = root.get_final_transform() * position
	Input.parse_input_event(motion)
	await settle(2)
	var e := InputEventMouseButton.new()
	e.position = motion.position
	e.button_index = code
	e.pressed = true
	Input.parse_input_event(e)
	await settle(2)
	e.pressed = false
	Input.parse_input_event(e)
	await settle()
func descendants(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in node.get_children():
		result.append(child)
		result.append_array(descendants(child))
	return result
func button(token: String) -> Button:
	for node in descendants(game.ui.root):
		if node is Button and node.is_visible_in_tree() and (node.get_meta("controls_token", "") == token or node.text == token): return node
	return null
func route_to(target: Control) -> Array:
	var current: Control = root.gui_get_focus_owner()
	if current == null: return []
	var queue: Array = [[current, []]]
	var seen := {current.get_instance_id():true}
	while not queue.is_empty():
		var step: Array = queue.pop_front()
		if step[0] == target: return step[1]
		for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
			var next: Control = step[0].find_valid_focus_neighbor(side)
			if next == null or seen.has(next.get_instance_id()): continue
			seen[next.get_instance_id()] = true
			queue.append([next,step[1]+[side]])
	return []
func reach(target: Button) -> bool:
	if target == null: return false
	if device == "mouse":
		var scroller: ScrollContainer = game.ui.controls_menu.scroll if is_instance_valid(game.ui.controls_menu) else game.ui.menu_scroll
		for i in 120:
			var r := target.get_global_rect()
			var s := scroller.get_global_rect()
			if not scroller.is_ancestor_of(target) or (r.position.y >= s.position.y and r.end.y <= s.end.y): return true
			await mouse(s.get_center(),MOUSE_BUTTON_WHEEL_DOWN if r.end.y > s.end.y else MOUSE_BUTTON_WHEEL_UP)
		check(false,"Pointer can scroll to "+str(target.text))
		return false
	for i in 512:
		if root.gui_get_focus_owner() == target: return true
		if device == "keyboard": await key(KEY_TAB)
		else:
			var route := route_to(target)
			if route.is_empty():
				check(false,"Pad focus graph reaches "+str(target.text))
				return false
			await pad({SIDE_LEFT:JOY_BUTTON_DPAD_LEFT,SIDE_TOP:JOY_BUTTON_DPAD_UP,SIDE_RIGHT:JOY_BUTTON_DPAD_RIGHT,SIDE_BOTTOM:JOY_BUTTON_DPAD_DOWN}[route[0]])
	check(false,"Input navigation reaches "+str(target.text))
	return false
func activate(token: String) -> bool:
	await settle()
	var target := button(token)
	if target == null:
		check(false,"Visible control exists: "+token)
		return false
	if not await reach(target): return false
	if device == "keyboard": await key(KEY_ENTER)
	elif device == "pad": await pad(JOY_BUTTON_A)
	else: await mouse(target.get_global_rect().get_center())
	await settle()
	return true
func new_input(clash := false) -> void:
	if device == "keyboard": await key(KEY_Q if clash else KEY_K)
	elif device == "pad": await pad(JOY_BUTTON_Y if clash else JOY_BUTTON_MISC1)
	else: await mouse(game.ui.controls_menu.scroll.get_global_rect().get_center(),MOUSE_BUTTON_RIGHT if clash else MOUSE_BUTTON_XBUTTON1)
func expected_record() -> Dictionary:
	if device == "keyboard": return {"type":"key","physical":KEY_K}
	if device == "pad": return {"type":"pad","button":JOY_BUTTON_MISC1}
	return {"type":"mouse","button":MOUSE_BUTTON_XBUTTON1}
func frame(name: String) -> void:
	if not capture_frames: return
	await settle(10)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name+".png"))
	print("FRAME="+out.path_join(name+".png"))
func open_controls() -> bool:
	if not await activate("Settings & controls"): return false
	check(game.ui.page == "settings","Real input reaches Settings")
	if not await activate("Controls"): return false
	check(game.ui.page == "controls","G1 real input reaches Controls")
	return game.ui.page == "controls"
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--device="): device = arg.trim_prefix("--device=")
		if arg.begins_with("--phase="): phase = arg.trim_prefix("--phase=")
		if arg.begins_with("--scale="): scale = float(arg.trim_prefix("--scale="))
		if arg.begins_with("--out="): out = arg.trim_prefix("--out="); capture_frames = true
		if arg == "--1080": window_size = Vector2i(1920,1080)
	if capture_frames: DirAccess.make_dir_recursive_absolute(out)
	root.size = window_size
	game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await settle()
	game.ui.set_text_scale(scale)
	await settle()
	if not await open_controls():
		await finish()
		return
	await frame("controls")
	if phase == "navigation":
		await navigation()
		await finish()
		return
	if phase == "read":
		check(game.bindings.events("attack").has(expected_record()),"Restart restores saved "+device+" attack binding")
		var text: String = game.bindings.event_label(expected_record())
		check(button("attack_0").text.contains(text),"Restart renders persisted binding")
		await finish()
		return
	if phase == "recovery":
		await recovery()
		await finish()
		return
	if phase == "edges":
		await edges()
		await finish()
		return
	if not await activate("attack_0"):
		await finish(); return
	check(game.ui.controls_menu.state == "capture","Slot opens capture")
	await frame("capture")
	await new_input()
	check(game.ui.controls_menu.state == "proposal","Physical input proposes a binding")
	var review_text := ""
	for node in descendants(game.ui.controls_menu):
		if node is Label: review_text += node.text+" "
	check(review_text.contains("will replace Left click"),"Review says which existing binding will be replaced")
	await activate("bind")
	check(game.bindings.events("attack").has(expected_record()),"G1 rebinds attack through "+device+" UI")
	var before: Array = game.bindings.events("attack")
	await activate("attack_0")
	await new_input(true)
	check(button("swap") != null,"Clash offers Swap")
	await frame("clash")
	await activate("swap")
	check(game.ui.controls_menu.state == "list","Swap returns to action list")
	check(game.bindings.events("attack") != before and game.bindings.events("magic").has(expected_record()),"G1 swaps the conflicting slots through "+device)
	before = game.bindings.events("attack")
	await activate("attack_0")
	if device == "keyboard": await key(KEY_ESCAPE)
	elif device == "mouse": await activate("cancel")
	else:
		# B is a valid candidate; the next B cancels its review without saving.
		await pad(JOY_BUTTON_B)
		check(game.ui.controls_menu.state == "proposal" and game.ui.controls_menu.record == {"type":"pad","button":JOY_BUTTON_B},"Pad B can be captured as a candidate")
		await pad(JOY_BUTTON_B)
	check(game.ui.controls_menu.state == "list" and game.bindings.events("attack") == before,"G1 cancel leaves bindings unchanged with "+device)
	await activate("reset_all")
	await activate("confirm")
	for area in game.bindings.SCOPES:
		for id in game.bindings.actions:
			if game.bindings.actions[id].contexts.has(area): check(game.bindings.events(id,area) == game.bindings.defaults(id,area),"Reset all restores "+area+"/"+id)
	await activate("attack_0")
	await new_input()
	await activate("bind")
	check(game.bindings.events("attack").has(expected_record()),"Final binding persisted after reset-all workflow")
	await frame("persisted")
	if capture_frames:
		# Presentation fixture: skip story progression and startup scripts.
		game.playing = true
		game.vm.cancel_all()
		game.ui.close_menu()
		game.load_map(439,false)
		game.entities[1].frozen = false
		game.fps_yaw = 0.55
		game._sync_fps_camera()
		await key(KEY_F1)
		check(game.ui.hint.text.contains(game.bindings.short_label("attack")+"  Attack"),"Rendered gameplay hint follows remapped input")
		await frame("gameplay-hint")
	await finish()
func navigation() -> void:
	# Independent of the pending mutation API; this is not the complete G1 gate.
	await activate("attack_0")
	check(game.ui.controls_menu.state == "capture","Device-only slot selection opens listening")
	await new_input()
	check(game.ui.controls_menu.state == "proposal","Device-only capture opens review")
	await activate("cancel")
	check(game.ui.controls_menu.state == "list","Device-only review cancellation returns focus")
	await activate("group_menu")
	await activate("ui_end_add")
	check(game.ui.controls_menu.state == "capture","Device-only navigation reaches final menu row")
	if device == "pad":
		await pad(JOY_BUTTON_B)
		check(game.ui.controls_menu.state == "proposal","B remains bindable")
		await pad(JOY_BUTTON_B)
	elif device == "keyboard": await key(KEY_ESCAPE)
	else: await activate("cancel")
	check(game.ui.controls_menu.state == "list","Device-only cancellation recovers from the bottom row")
	await activate("group_2d")
	await activate("group_global")
	check(button("escape_0") != null and button("escape_0").disabled,"Reserved Escape is visibly immutable")
	await activate("back")
	check(game.ui.page == "settings","Device-only Back returns to Settings")
func recovery() -> void:
	# Deliberately use every menu row; every mutation still uses real screen input.
	await activate("group_menu")
	var code := KEY_F13
	var actions: Array = []
	for id in game.bindings.actions:
		if game.bindings.actions[id].contexts == ["menu"]: actions.append(id)
	for id in actions:
		var records: Array = game.bindings.events(id,"menu")
		for index in records.size():
			if records[index].type != "key": continue
			# All keyboard aliases become unusual keys. Essential pad alternatives stay.
			await activate(id+"_"+str(index))
			await key(code)
			await activate("bind")
			check(game.bindings.events(id,"menu").has({"type":"key","physical":code}),"Menu row rebound through screen: "+id)
			code += 1
	await key(KEY_ESCAPE)
	check(game.ui.page == "settings","Escape leaves Controls despite menu remaps")
	await key(KEY_ESCAPE)
	check(game.ui.page == "title","Escape returns to title despite menu remaps")
	check(await open_controls(),"Pointer recovers Controls with every menu action remapped")
	await activate("reset_all")
	await activate("confirm")
	check(game.bindings.events("ui_accept") == game.bindings.defaults("ui_accept"),"G2 pointer Reset all recovers menu defaults")
func edges() -> void:
	# Reset-one confirmation and removal are user operations, not API edits.
	await activate("attack_add")
	await key(KEY_F24)
	await activate("bind")
	check(game.bindings.events("attack").has({"type":"key","physical":KEY_F24}),"Add preserves alternate bindings")
	var last: int = game.bindings.events("attack").size()-1
	await activate("attack_"+str(last))
	await activate("remove")
	await activate("confirm")
	check(not game.bindings.events("attack").has({"type":"key","physical":KEY_F24}),"Remove deletes only the selected alternate")
	await activate("attack_reset")
	await activate("confirm")
	check(game.bindings.events("attack") == game.bindings.defaults("attack"),"Reset one restores defaults")
	await activate("attack_0")
	await key(KEY_F9)
	check(game.ui.controls_menu.state == "proposal" and button("retry") != null,"Reserved F9 explains refusal without firing bug recorder")
	check(not game.bug_report_pending,"Capture suppresses F9 shortcut")
	await activate("cancel")
	await axis(JOY_AXIS_RIGHT_X,0.9)
	await activate("attack_0")
	await axis(JOY_AXIS_RIGHT_X,0.9)
	check(game.ui.controls_menu.state == "capture","Already-held axis cannot accidentally replace a binding")
	await axis(JOY_AXIS_RIGHT_X,0.0)
	await axis(JOY_AXIS_RIGHT_X,-0.9)
	check(game.ui.controls_menu.state == "proposal" and game.ui.controls_menu.record == {"type":"axis","axis":JOY_AXIS_RIGHT_X,"direction":-1},"Neutral then a fresh direction can be captured")
	await activate("cancel")
	await axis(JOY_AXIS_RIGHT_X,0.0)
	await activate("attack_add")
	var modifier := InputEventKey.new()
	modifier.physical_keycode = KEY_SHIFT
	modifier.keycode = KEY_SHIFT
	modifier.shift_pressed = true
	modifier.pressed = true
	Input.parse_input_event(modifier)
	await settle()
	check(game.ui.controls_menu.state == "capture","Modifier waits for a chord or its release")
	var modified := InputEventKey.new()
	modified.physical_keycode = KEY_K
	modified.keycode = KEY_K
	modified.shift_pressed = true
	modified.pressed = true
	Input.parse_input_event(modified)
	await settle()
	modified.pressed = false
	Input.parse_input_event(modified)
	modifier.pressed = false
	modifier.shift_pressed = false
	Input.parse_input_event(modifier)
	await settle()
	check(game.ui.controls_menu.record == {"type":"key","physical":KEY_K,"shift":true},"Capture retains physical key modifiers")
	await activate("bind")
	await activate("attack_reset")
	await activate("confirm")
	await activate("group_menu")
	await activate("ui_up_0")
	await activate("remove")
	await activate("confirm")
	check(game.ui.controls_menu.state == "error","Last keyboard navigation binding is refused")
	var words := ""
	for node in descendants(game.ui.controls_menu):
		if node is Label: words += node.text+" "
	check(words.contains("keyboard") and words.contains("pad"),"Last-device refusal explains recovery in plain words")
	await activate("cancel")
	await activate("group_fps")
	var before_timeout: Array = game.bindings.events("attack")
	await activate("attack_0")
	var until := Time.get_ticks_msec()+16000
	while game.ui.controls_menu.state == "capture" and Time.get_ticks_msec()<until: await process_frame
	check(game.ui.controls_menu.state == "list" and game.bindings.events("attack") == before_timeout,"Capture timeout cancels without a binding mutation")
func finish() -> void:
	print("CONTROLS "+("PASS " if failures.is_empty() else "FAIL ")+device+" "+phase+" failures="+str(failures.size()))
	game.vm.cancel_all()
	game.queue_free()
	await settle(3)
	quit(0 if failures.is_empty() else 1)
