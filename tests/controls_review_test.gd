# Review correction gates. UI-only fixture starts at Settings; physical input
# performs page entry/capture/cancel. Baseline UI copy is an explicit red control.
extends SceneTree
var ui
var failures: Array[String] = []
var mode := "pad"
var large := false
var source := "res://scripts/game_ui.gd"
func _initialize() -> void: run.call_deferred()
func check(ok: bool, text: String) -> void:
	if not ok: failures.append(text); push_error(text)
func settle(n := 6) -> void:
	for i in n: await process_frame
func key(code: int) -> void:
	var e := InputEventKey.new(); e.keycode=code; e.physical_keycode=code; e.pressed=true
	Input.parse_input_event(e); await settle(2)
	e.pressed=false; Input.parse_input_event(e); await settle()
func pad_event(code: int, pressed: bool) -> void:
	var e := InputEventJoypadButton.new(); e.device=3; e.button_index=code; e.pressed=pressed
	Input.parse_input_event(e); await settle(2)
func axis(value: float) -> void:
	var e := InputEventJoypadMotion.new(); e.device=3; e.axis=JOY_AXIS_TRIGGER_LEFT; e.axis_value=value
	Input.parse_input_event(e); await settle()
func pad(code: int) -> void:
	await pad_event(code,true); await pad_event(code,false); await settle()
func nodes(parent: Node) -> Array[Node]:
	var result: Array[Node]=[]
	for child in parent.get_children(): result.append(child); result.append_array(nodes(child))
	return result
func text() -> String:
	var result := ""
	for child in nodes(ui.controls_menu):
		if child is Label: result+=child.text+" "
	return result
func row_nodes() -> Array[Control]:
	var result: Array[Control]=[]
	for child in ui.controls_menu.body.get_children():
		if child is VBoxContainer: result.append(child)
	return result
func contained(a: Rect2,b: Rect2) -> bool:
	return a.position.y>=b.position.y-1 and a.end.y<=b.end.y+1
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):mode=arg.trim_prefix("--mode=")
		if arg=="--1080":large=true
		if arg.begins_with("--ui="):source=arg.trim_prefix("--ui=")
	root.size=Vector2i(1920,1080) if large else Vector2i(1280,800)
	ui=load(source).new(); root.add_child(ui); ui.set_text_scale(1.3); ui.show_settings({})
	await settle()
	if mode=="pad": await pad(JOY_BUTTON_A)
	else: await key(KEY_ENTER)
	check(ui.page=="controls","Real input opens Controls")
	if mode in ["pad","keyboard"]:
		if mode=="pad":await pad(JOY_BUTTON_A)
		else:await key(KEY_ENTER)
		check(ui.controls_menu.state=="capture","Real input opens capture")
		check(root.gui_get_focus_owner()==null,"F2 listening has no falsely activatable focus ring")
		if mode=="pad":
			check(text().contains("hold "+ui.bindings.label("ui_cancel",true,"menu")),"F1 prompt teaches the pad's hold-cancel input")
			await pad_event(JOY_BUTTON_B,true)
			await create_timer(1.1).timeout
			await settle()
			check(ui.controls_menu.state=="list","F1 pad-only hold cancels capture directly")
			await pad_event(JOY_BUTTON_B,false)
			if ui.controls_menu.state=="list":
				await settle(); await pad(JOY_BUTTON_A); await pad(JOY_BUTTON_B)
				check(ui.controls_menu.state=="proposal" and ui.controls_menu.record=={"type":"pad","button":JOY_BUTTON_B},"F1 a tap still proposes B")
		else:
			await key(KEY_ESCAPE)
			check(ui.controls_menu.state=="list","F1 keyboard-only Escape cancels capture")
			await key(KEY_ENTER); await key(KEY_ENTER)
			check(ui.controls_menu.state=="proposal" and ui.controls_menu.record=={"type":"key","physical":KEY_ENTER},"F2 Enter is honestly a candidate during listening")
	elif mode=="axis_cancel":
		# Explicit registry fixture: remap menu-cancel while its future axis is held.
		# Capture entry, neutral and the subsequent hold still use physical events.
		await axis(0.9)
		var changed: Dictionary=ui.bindings.replace_binding("ui_cancel",1,{"type":"axis","axis":JOY_AXIS_TRIGGER_LEFT,"direction":1},"refuse","menu")
		check(changed.get("ok",false),"Axis-cancel fixture is valid")
		await key(KEY_ENTER); await axis(1.0)
		await create_timer(1.1).timeout
		check(ui.controls_menu.state=="capture","Already-held cancel axis does not cancel or propose")
		await axis(0.0); await axis(0.9); await create_timer(1.1).timeout; await settle()
		check(ui.controls_menu.state=="list","Fresh remapped cancel-axis hold cancels directly")
		await axis(0.0)
	elif mode=="layout":
		var viewport: Rect2=ui.controls_menu.scroll.get_global_rect()
		var count := 0
		for row in row_nodes():
			if contained(row.get_global_rect(),viewport):count+=1
		check(count>=3,"F3 largest text shows at least three whole actions")
		var intro_count := 0
		for node in nodes(ui.controls_menu):
			if node is Label and node.text=="Pad buttons are named as on an Xbox controller":intro_count+=1
		check(intro_count==1,"F3 a single plain intro line")
		var motion := InputEventMouseMotion.new();motion.position=root.get_final_transform()*viewport.get_center();Input.parse_input_event(motion)
		var wheel := InputEventMouseButton.new();wheel.position=motion.position;wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN;wheel.pressed=true;Input.parse_input_event(wheel)
		await settle(12)
		viewport=ui.controls_menu.scroll.get_global_rect()
		for row in row_nodes():
			var rect := row.get_global_rect()
			if rect.intersection(viewport).size.y>1:check(contained(rect,viewport),"F3 scrolling leaves no partial action row")
		check(ui.controls_menu.scroll.scroll_vertical>0,"F3 wheel moves to the next row")
	elif mode=="dialogs":
		check(ui.controls_menu.buttons.attack_2.text.begins_with("Pad RT"),"F4 right trigger has pad prefix")
		check(ui.controls_menu.buttons.magic_3.text.begins_with("Pad LT"),"F4 left trigger has pad prefix")
		await key(KEY_ENTER);await settle()
		check(ui.controls_menu.scroll.size.y<=ui.controls_menu.body.get_combined_minimum_size().y+1,"F4 capture dialog fits content")
		await key(KEY_Q);await settle()
		check(ui.controls_menu.buttons.has("swap") and not ui.controls_menu.buttons.has("remove"),"F4 clash offers Swap/Cancel without destructive removal")
		check(ui.controls_menu.scroll.size.y<=ui.controls_menu.body.get_combined_minimum_size().y+1,"F4 clash dialog fits content")
	print("CONTROLS REVIEW "+("PASS " if failures.is_empty() else "FAIL ")+mode)
	ui.queue_free();await settle(3);quit(0 if failures.is_empty() else 1)
