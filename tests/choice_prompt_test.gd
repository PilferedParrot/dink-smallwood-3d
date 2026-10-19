extends SceneTree
const UI = preload("res://scripts/game_ui.gd")
var ui
var failures: Array[String] = []
var choices: Array[int] = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message); push_error(message)

func settle() -> void:
	for _i in 8: await process_frame

func title_at(node: Variant, line: int) -> String:
	if node is Dictionary:
		if node.get("op") == "choice_title" and node.get("line") == line: return str(node.text)
		for child in node.values():
			var found := title_at(child, line)
			if not found.is_empty(): return found
	elif node is Array:
		for child in node:
			var found := title_at(child, line)
			if not found.is_empty(): return found
	return ""

func press(event) -> void:
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await settle()

func _chosen(choice: int) -> void:
	choices.append(choice)

func _run() -> void:
	var story: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/story.json"))
	ui = UI.new()
	root.add_child(ui)
	ui.dialogue_finished.connect(_chosen)
	await process_frame
	ui.set_text_scale(1.3)
	for size in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		root.size = size
		for source in [["escape", 114], ["s1-boot", 16]]:
			var title := title_at(story.scripts[source[0]], source[1])
			check(not title.is_empty(), "Known long source prompt exists")
			for device in ["keyboard", "controller"]:
				ui.show_choices(title, ["First", "Second"])
				await settle()
				print("CHOICE PROMPT ", source, " ", size, " ", device, " height=", ui.panel.size.y)
				check(ui.panel.size.y <= ui.root.size.y * 0.35 + 1, "Long source prompt retains the 35% cap")
				check(ui.menu_scroll.scroll_vertical == 0, "Choice opens with its prompt at the top")
				var prompt: Label = ui.get("choice_prompt")
				var prompt_view: ScrollContainer = ui.get("choice_prompt_scroll")
				check(prompt != null and prompt.text == title, "Complete source prompt belongs to its independent viewport")
				if prompt != null and prompt_view != null:
					check(absf(prompt.get_global_rect().position.y - prompt_view.get_global_rect().position.y) <= 1, "Prompt is the first visible scroll content")
				var focus := root.gui_get_focus_owner() as Button
				check(focus != null and focus.text == "First", "First option retains keyboard/controller focus")
				if focus != null:
					var answer_rect := focus.get_global_rect()
					var viewport_rect: Rect2 = ui.menu_scroll.get_global_rect().grow(1)
					check(viewport_rect.encloses(answer_rect), "Focused answer is fully visible on entry")
					check(focus.accessibility_name == title + "\nFirst", "First focused option reports prompt before answer to assistive apps")
				check(not ui.dialogue_continue.visible, "Choice options alone own confirmation")
				if prompt_view != null and prompt_view.get_v_scroll_bar().max_value > prompt_view.size.y:
					var pagedown := InputEventKey.new()
					pagedown.keycode = KEY_PAGEDOWN; pagedown.physical_keycode = KEY_PAGEDOWN
					await press(pagedown)
					check(prompt_view.scroll_vertical > 0 and root.gui_get_focus_owner() == focus, "PageDown reads prompt without moving the answer owner")
					check(ui.menu_scroll.get_global_rect().grow(1).encloses(focus.get_global_rect()), "Prompt scrolling keeps focused answer fully visible")
				if prompt_view != null and device == "controller":
					var stick := InputEventJoypadMotion.new()
					stick.device = 3; stick.axis = JOY_AXIS_RIGHT_Y; stick.axis_value = -1
					Input.parse_input_event(stick); Input.flush_buffered_events()
					ui._process(1.0)
					check(prompt_view.scroll_vertical == 0 and root.gui_get_focus_owner() == focus, "Right stick reads prompt independently")
					stick = stick.duplicate(); stick.axis_value = 0
					Input.parse_input_event(stick); Input.flush_buffered_events()
					# Action strengths are consumed on the process tick. Observe the
					# scroll owner rather than its cache before that tick occurs.
					ui._process(1.0/60.0)
					var stopped := prompt_view.scroll_vertical
					for _i in 30:
						ui._process(1.0/60.0)
						await process_frame
						check(prompt_view.scroll_vertical == stopped and root.gui_get_focus_owner() == focus, "Neutral right stick stops prompt scrolling and preserves answer focus for thirty frames")
				var count := choices.size()
				if device == "keyboard":
					var enter := InputEventKey.new()
					enter.keycode = KEY_ENTER; enter.physical_keycode = KEY_ENTER
					await press(enter)
					check(choices.size() == count + 1 and choices.back() == 1, "Enter confirms the original first option")
				else:
					var down := InputEventJoypadButton.new()
					down.device = 3; down.button_index = JOY_BUTTON_DPAD_DOWN
					await press(down)
					var accept := InputEventJoypadButton.new()
					accept.device = 3; accept.button_index = JOY_BUTTON_A
					await press(accept)
					check(choices.size() == count + 1 and choices.back() == 2, "D-pad/A confirm the original second option")
				check(ui.page == "game", "Choice confirmation releases its card")
	ui.queue_free()
	for _i in 3: await process_frame
	print("CHOICE PROMPT PASS" if failures.is_empty() else "CHOICE PROMPT FAIL")
	quit(0 if failures.is_empty() else 1)
