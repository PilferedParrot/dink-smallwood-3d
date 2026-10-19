# Packed-render fixture: skips progression for repeatable UI coverage, then
# starts a new game through title input and stops story tasks at the bow toast.
# Navigation/confirmation/help/recovery use the real physical input pipeline.
extends SceneTree
const GAME = preload("res://scripts/fps_game.gd")
var game
var failures: Array[String] = []
var out := ""
var choice := 0

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); push_error(message)

func key(code: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func click(control: Control) -> void:
	await process_frame
	await process_frame
	var position := root.get_final_transform() * control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = position
	Input.parse_input_event(motion)
	await process_frame
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func button(text: String) -> Control:
	for child in game.ui.column.get_children():
		if child is Button and child.text == text: return child
	return null

func frame(name: String) -> void:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	var path := out.path_join(name+".png")
	root.get_texture().get_image().save_png(path)
	print("FRAME="+path)

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	check(game.bindings.set_bindings("attack",[game.bindings.key(KEY_K)]).ok,"Attack remap")
	check(game.bindings.set_bindings("talk",[game.bindings.key(KEY_J)]).ok,"Talk remap")
	check(game.ui._control_primer().contains("K attack") and game.ui._control_primer().contains("J talk"),"Title primer follows both overrides")
	await frame("title")
	game.playing = true
	game.vm.cancel_all()
	game.ui.close_menu()
	game.load_map(439,false)
	game.entities[1].frozen = false
	game.fps_yaw = 0.55
	game._sync_fps_camera()
	await key(KEY_F1)
	check(game.ui.hint.text.contains("K  Attack") and game.ui.hint.text.contains("J  Talk"),"Real F1 strip follows remapped gameplay")
	await frame("gameplay-help")
	# Put menu controls on unusual keys; Escape and the pointer must recover.
	var code := KEY_F13
	for action in game.bindings.actions:
		if game.bindings.actions[action].contexts == ["menu"]:
			var replacement := [game.bindings.key(code)]
			if action in game.bindings.ESSENTIAL_MENU:
				for record in game.bindings.defaults(action):
					if record.type in ["pad","axis"]: replacement.append(record)
			check(game.bindings.set_bindings(action,replacement).ok,"Menu remap "+action)
			code += 1
	await key(KEY_ESCAPE)
	check(game.ui.page == "pause","Guaranteed Escape opens pause with every menu action remapped")
	await click(button("Settings & controls"))
	check(game.ui.page == "settings","Mouse still reaches settings")
	check(game.ui._controls_text().contains("Attack: K") and game.ui._controls_text().contains("Talk / examine: J"),"Settings controls follow overrides")
	check(game.ui.hint.text.contains(game.bindings.short_label("ui_left")) and game.ui.hint.text.contains(game.bindings.short_label("ui_cancel")),"Adjustment/back footer follows menu remaps")
	await frame("settings")
	await key(KEY_ESCAPE)
	check(game.ui.page == "pause","Guaranteed Escape leaves settings")
	game.ui.dialogue_finished.connect(func(value: int): choice = value)
	game.ui.show_dialogue("Every control cue uses the current binding.","Input check")
	await process_frame
	check(game.ui.dialogue_continue.text.contains(game.bindings.short_label("ui_accept")),"Dialogue Continue follows confirm remap")
	await frame("continue")
	await key(KEY_ENTER)
	check(game.ui.modal,"Old Enter no longer confirms")
	await key(int(game.bindings.events("ui_accept")[0].physical))
	check(not game.ui.modal,"Remapped confirm continues through real GUI input")
	game.ui.show_choices("A long original prompt. ".repeat(100),["First answer","Second answer"])
	await process_frame
	check(game.ui.hint.text.contains(game.bindings.short_label("ui_accept")),"Choice confirm cue follows remap")
	check(game.ui.hint.text.contains(game.bindings.short_label("ui_page_down")),"Overflow prompt cue follows remap")
	await frame("choices")
	await key(int(game.bindings.events("ui_down")[0].physical))
	await key(int(game.bindings.events("ui_accept")[0].physical))
	check(choice == 2,"Remapped menu directions/accept drive actual choices")
	await key(KEY_ESCAPE)
	await click(button("Settings & controls"))
	check(game.ui.page == "settings","Recovery returns to Settings from gameplay")
	# P3b supplies the reset button; this unit proves the data API is reachable
	# once the guaranteed exit and pointer have recovered the settings owner.
	check(game.bindings.reset_all().ok,"Reset API succeeds after Escape/mouse recovery")
	check(game.bindings.events("ui_accept") == game.bindings.defaults("ui_accept"),"Reset restores menu controls")
	await key(KEY_ESCAPE)
	check(game.ui.page == "pause","Escape still works after reset")
	check(game.bindings.set_bindings("attack",[game.bindings.key(KEY_K)]).ok,"Restore remapped Attack for opening toast")
	check(game.bindings.set_bindings("talk",[game.bindings.key(KEY_J)]).ok,"Restore remapped Talk for opening toast")
	game.playing = false
	game.ui.show_title(false)
	for _i in 4: await process_frame
	await key(KEY_ENTER)
	for _i in 180:
		if game.ui.toast.text.begins_with("A travel bow is ready."): break
		await process_frame
	check(game.ui.toast.text == "A travel bow is ready. K to fire.","Actual title input reaches binding-derived opening toast")
	game.vm.cancel_all()
	await frame("bow-ready")
	game.vm.cancel_all()
	game.queue_free()
	await process_frame
	print("INPUT HINTS PASS" if failures.is_empty() else "INPUT HINTS FAIL "+str(failures.size()))
	quit(0 if failures.is_empty() else 1)
