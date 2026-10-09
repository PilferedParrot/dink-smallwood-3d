# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
extends CanvasLayer
signal action_requested(action: String, payload: Variant)
signal dialogue_finished(choice: int)
var modal := true
var root: Control
var overlay: ColorRect
var panel: PanelContainer
var column: VBoxContainer
var hud: Label
var hint: Label
var toast: Label
var crosshair: Label
var health_bar: ProgressBar
var mana_bar: ProgressBar
var compass_label: Label
var toast_timer: Timer
var dialogue_mode := false
var page := "title"
var text_scale := 1.0
var menu_theme: Theme
var controller_active := false
var title_art: TextureRect
var vines_left: TextureRect
var vines_right: TextureRect
var status_dock: Control
var equipment_stats: Dictionary = {}
var dialogue_continue: Button
var menu_scroll: ScrollContainer
var page_serial := 0
var return_page := "title"
var toast_backing: PanelContainer
var heading: Label
var equipment_name: Label
var menu_footer: Button
var modal_feedback: PanelContainer
var modal_feedback_text: Label
var panel_style: StyleBoxTexture
var title_panel_style: StyleBoxEmpty
var panel_underlay: ColorRect
var hint_backing: PanelContainer
var gameplay_hint_used := false
var gameplay_hint_deadline_msec := 0
const GAMEPLAY_HINT_SECONDS := 8.0
const CREAM := Color("f6ebcb")
const GOLD := Color("ffdc79")
const INK := Color("292019")
const CHOICE_BACKDROP = preload("res://assets/graphics/inter/Text-box/main-03.png")
const LOGO = preload("res://assets/graphics/Startme/options/dinkl-01.png")

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_controller_navigation()
	# A plugged-in pad does not mean it is the device the player is using.
	# Switch cues when actual keyboard/pointer/controller input arrives.
	controller_active = false
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Keep clicks and pointer events inside a menu from reaching the 3D world.
	# Let mouse input reach the first-person camera during gameplay.
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	menu_theme = Theme.new()
	menu_theme.default_font_size = 22
	menu_theme.set_color("font_color", "Label", CREAM)
	# Reuse an original chest recess; no new bitmap or invented ornament.
	var button_texture := AtlasTexture.new()
	button_texture.atlas = preload("res://assets/graphics/inter/Menu/menu-01.png")
	button_texture.region = Rect2(239, 82, 69, 61)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var box := StyleBoxTexture.new()
		box.texture = button_texture
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			box.set_texture_margin(side, 5)
		box.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
		box.modulate_color = Color.WHITE if state == "normal" else Color("ffe4af")
		box.content_margin_left = 20; box.content_margin_right = 20
		box.content_margin_top = 8; box.content_margin_bottom = 8
		menu_theme.set_stylebox(state, "Button", box)
	var focus_frame := StyleBoxFlat.new()
	focus_frame.bg_color = Color.TRANSPARENT
	focus_frame.border_color = GOLD
	focus_frame.set_border_width_all(4)
	menu_theme.set_stylebox("focus", "Button", focus_frame)
	menu_theme.set_color("font_color", "Button", CREAM)
	menu_theme.set_color("font_hover_color", "Button", Color.WHITE)
	menu_theme.set_color("font_focus_color", "Button", Color.WHITE)
	menu_theme.set_color("font_disabled_color", "Button", Color("c3b79e"))
	root.theme = menu_theme
	status_dock = load("res://scripts/dink_status_bar.gd").new()
	root.add_child(status_dock)
	hud = Label.new()
	hud.position = Vector2(28, 22)
	hud.add_theme_color_override("font_shadow_color", Color.BLACK)
	hud.add_theme_constant_override("shadow_offset_x", 2)
	hud.add_theme_constant_override("shadow_offset_y", 2)
	root.add_child(hud)
	health_bar = _make_bar(Color("a94f42"))
	health_bar.position = Vector2(28, 124)
	health_bar.size = Vector2(190, 14)
	root.add_child(health_bar)
	mana_bar = _make_bar(Color("4f7891"))
	mana_bar.position = Vector2(28, 144)
	mana_bar.size = Vector2(190, 10)
	root.add_child(mana_bar)
	compass_label = Label.new()
	compass_label.anchor_left = 0.5
	compass_label.anchor_right = 0.5
	compass_label.offset_left = -30
	compass_label.offset_top = 24
	compass_label.offset_left = -250; compass_label.offset_right = 250
	compass_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	compass_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	compass_label.add_theme_constant_override("shadow_offset_x", 2)
	compass_label.add_theme_constant_override("shadow_offset_y", 2)
	compass_label.add_theme_color_override("font_color", GOLD)
	compass_label.add_theme_font_size_override("font_size", 18)
	compass_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(compass_label)
	crosshair = Label.new()
	crosshair.text = "+"
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.offset_left = -8; crosshair.offset_right = 8
	crosshair.offset_top = -14; crosshair.offset_bottom = 14
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.add_theme_color_override("font_color", Color("fff0b8"))
	crosshair.add_theme_color_override("font_outline_color", Color.BLACK)
	crosshair.add_theme_constant_override("outline_size", 3)
	crosshair.add_theme_font_size_override("font_size", 24)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(crosshair)
	hint = Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_shadow_color", Color.BLACK)
	hint.add_theme_constant_override("shadow_offset_x", 2)
	hint.add_theme_constant_override("shadow_offset_y", 2)
	hint.add_theme_font_size_override("font_size", 20)
	hint_backing = PanelContainer.new()
	hint_backing.anchor_left = 0.5; hint_backing.anchor_right = 0.5
	hint_backing.anchor_top = 1.0; hint_backing.anchor_bottom = 1.0
	hint_backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hint_style := StyleBoxFlat.new()
	hint_style.bg_color = Color("17130f")
	hint_style.content_margin_left = 12; hint_style.content_margin_right = 12
	hint_style.content_margin_top = 6; hint_style.content_margin_bottom = 6
	hint_backing.add_theme_stylebox_override("panel", hint_style)
	root.add_child(hint_backing)
	hint_backing.add_child(hint)
	toast = Label.new()
	toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_color_override("font_color", GOLD)
	toast_backing = PanelContainer.new()
	toast_backing.anchor_left = 0.18; toast_backing.anchor_right = 0.82
	toast_backing.offset_top = 65; toast_backing.offset_bottom = 65
	toast_backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var toast_style := StyleBoxFlat.new()
	toast_style.bg_color = Color("21180f")
	toast_style.border_color = GOLD
	toast_style.set_border_width_all(1)
	toast_style.content_margin_left = 16; toast_style.content_margin_right = 16
	toast_style.content_margin_top = 10; toast_style.content_margin_bottom = 10
	toast_backing.add_theme_stylebox_override("panel", toast_style)
	root.add_child(toast_backing)
	toast_backing.add_child(toast)
	toast_backing.hide()
	toast_timer = Timer.new()
	toast_timer.one_shot = true
	toast_timer.wait_time = 4.0
	toast_timer.timeout.connect(_clear_toast)
	add_child(toast_timer)
	overlay = ColorRect.new()
	overlay.color = Color(0.035, 0.025, 0.02, 0.78)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(overlay)
	title_art = TextureRect.new()
	title_art.texture = LOGO
	title_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_art.anchor_left = 0.06; title_art.anchor_right = 0.52
	title_art.anchor_top = 0.10; title_art.anchor_bottom = 0.54
	root.add_child(title_art)
	panel_underlay = ColorRect.new()
	panel_underlay.color = Color("17130f")
	panel_underlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel_underlay)
	panel = PanelContainer.new()
	panel.anchor_left = 0.08
	panel.anchor_right = 0.92
	panel.anchor_top = 0.07
	panel.anchor_bottom = 0.93
	panel.offset_left = 0
	panel.offset_right = 0
	panel.offset_top = 0
	panel.offset_bottom = 0
	panel.custom_minimum_size = Vector2(360, 0)
	var style := StyleBoxTexture.new()
	# FreeDink's actual choice renderer uses main02/03/04, not the unused
	# pale main01 plate. Tile the original dark dither rather than stretching it.
	style.texture = CHOICE_BACKDROP
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	style.content_margin_left = 32
	style.content_margin_right = 32
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	panel_style = style
	title_panel_style = StyleBoxEmpty.new()
	title_panel_style.content_margin_left = 32; title_panel_style.content_margin_right = 32
	title_panel_style.content_margin_top = 24; title_panel_style.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(panel)
	vines_left = _vine("res://assets/graphics/inter/Text-box/main-02.png")
	vines_right = _vine("res://assets/graphics/inter/Text-box/main-04.png")
	var contents := VBoxContainer.new()
	contents.add_theme_constant_override("separation", 8)
	panel.add_child(contents)
	var heading_row := HBoxContainer.new()
	heading_row.add_theme_constant_override("separation", 12)
	contents.add_child(heading_row)
	heading = Label.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_theme_color_override("font_color", GOLD)
	heading_row.add_child(heading)
	modal_feedback = PanelContainer.new()
	modal_feedback.add_theme_stylebox_override("panel", toast_style)
	heading_row.add_child(modal_feedback)
	modal_feedback_text = Label.new()
	modal_feedback_text.add_theme_color_override("font_color", GOLD)
	modal_feedback_text.add_theme_font_size_override("font_size", 20)
	modal_feedback_text.clip_text = true
	modal_feedback.add_child(modal_feedback_text)
	modal_feedback.hide()
	equipment_name = Label.new()
	equipment_name.add_theme_color_override("font_color", CREAM)
	equipment_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	contents.add_child(equipment_name)
	equipment_name.hide()
	var scroll := ScrollContainer.new()
	menu_scroll = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	contents.add_child(scroll)
	column = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	scroll.add_child(column)
	dialogue_continue = Button.new()
	dialogue_continue.custom_minimum_size.y = 52
	dialogue_continue.focus_mode = Control.FOCUS_ALL
	dialogue_continue.pressed.connect(_continue_dialogue)
	dialogue_continue.hide()
	contents.add_child(dialogue_continue)
	menu_footer = Button.new()
	menu_footer.custom_minimum_size.y = 48
	menu_footer.focus_mode = Control.FOCUS_ALL
	menu_footer.pressed.connect(_button_pressed.bind("back", null))
	contents.add_child(menu_footer)
	menu_footer.hide()
	# Instructions and notifications must render above the modal dimming layer.
	root.move_child(hint_backing, -1)
	root.move_child(toast_backing, -1)
	_set_playing_visuals(false)

func _vine(path: String) -> TextureRect:
	var vine := TextureRect.new()
	vine.texture = load(path)
	vine.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vine.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vine)
	return vine

func _process(_delta: float) -> void:
	panel_underlay.visible = panel.visible and page != "title"
	if panel.visible:
		panel_underlay.position = panel.position
		panel_underlay.size = panel.size
		vines_left.position = panel.position + Vector2(-65, 0)
		vines_left.size = Vector2(80, 140)
		vines_right.position = panel.position + Vector2(panel.size.x - 15, 0)
		vines_right.size = vines_left.size
	if modal:
		hint_backing.modulate.a = 1.0
		hint_backing.show()
	else:
		# UI help expires in real time even when a heavy scene renders slowly.
		var remaining := maxf(0.0, float(gameplay_hint_deadline_msec - Time.get_ticks_msec()) / 1000.0)
		hint_backing.modulate.a = minf(1.0, remaining) if gameplay_hint_used else 1.0
		hint_backing.visible = hint_backing.modulate.a > 0.0
		status_dock.set_context_hints_visible(hint_backing.visible)
	# A solid plaque keeps control instructions readable against every scene.
	var available := root.size.x - 40
	var font_size := hint.get_theme_font_size("font_size")
	var text_width := hint.get_theme_font("font").get_string_size(hint.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var width := minf(available, text_width + 24)
	hint_backing.offset_left = -width / 2; hint_backing.offset_right = width / 2
	var height := maxf(38, hint.get_minimum_size().y + 12)
	hint_backing.offset_bottom = -6 if modal else -150
	hint_backing.offset_top = hint_backing.offset_bottom - height

func _make_bar(fill: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = 100
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("26342c"); bg.set_corner_radius_all(4)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill; fg.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	return bar

func _set_playing_visuals(playing: bool) -> void:
	if is_instance_valid(crosshair): crosshair.visible = playing
	if is_instance_valid(health_bar): health_bar.visible = false
	if is_instance_valid(mana_bar): mana_bar.visible = false
	if is_instance_valid(hud): hud.visible = false
	if is_instance_valid(status_dock): status_dock.visible = playing
	if is_instance_valid(compass_label): compass_label.visible = playing

func _layout_for(next_page: String) -> void:
	if next_page == "title":
		panel.anchor_left = 0.56; panel.anchor_right = 0.94
		panel.anchor_top = 0.10; panel.anchor_bottom = 0.92
		overlay.color = Color.BLACK
	elif next_page == "dialogue":
		panel.anchor_left = 0.12; panel.anchor_right = 0.88
		panel.anchor_top = 0.58; panel.anchor_bottom = 0.93
		overlay.color = Color(0.025, 0.015, 0.008, 0.08)
	else:
		panel.anchor_left = 0.14; panel.anchor_right = 0.86
		panel.anchor_top = 0.07; panel.anchor_bottom = 0.90
		overlay.color = Color(0.025, 0.015, 0.008, 0.72)
	title_art.visible = next_page == "title"
	panel.add_theme_stylebox_override("panel", title_panel_style if next_page == "title" else panel_style)
	vines_left.visible = next_page != "title"; vines_right.visible = next_page != "title"

func _ensure_controller_navigation() -> void:
	var buttons := {"ui_accept": JOY_BUTTON_A, "ui_cancel": JOY_BUTTON_B, "ui_up": JOY_BUTTON_DPAD_UP, "ui_down": JOY_BUTTON_DPAD_DOWN, "ui_left": JOY_BUTTON_DPAD_LEFT, "ui_right": JOY_BUTTON_DPAD_RIGHT}
	for action in buttons:
		if not InputMap.has_action(action): InputMap.add_action(action)
		var event := InputEventJoypadButton.new()
		event.device = -1
		event.button_index = buttons[action]
		if not InputMap.action_has_event(action, event): InputMap.action_add_event(action, event)
	var axes := {"ui_up": [JOY_AXIS_LEFT_Y, -1.0], "ui_down": [JOY_AXIS_LEFT_Y, 1.0], "ui_left": [JOY_AXIS_LEFT_X, -1.0], "ui_right": [JOY_AXIS_LEFT_X, 1.0]}
	for action in axes:
		if not InputMap.has_action(action): InputMap.add_action(action)
		var event := InputEventJoypadMotion.new()
		event.device = -1
		event.axis = axes[action][0]
		event.axis_value = axes[action][1]
		if not InputMap.action_has_event(action, event): InputMap.action_add_event(action, event)

func _input(event: InputEvent) -> void:
	if not modal and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F1:
		gameplay_hint_used = true
		gameplay_hint_deadline_msec = Time.get_ticks_msec() + roundi(GAMEPLAY_HINT_SECONDS * 1000)
		get_viewport().set_input_as_handled()
	elif not modal and not gameplay_hint_used and _uses_gameplay_control(event):
		gameplay_hint_used = true
		gameplay_hint_deadline_msec = Time.get_ticks_msec() + roundi(GAMEPLAY_HINT_SECONDS * 1000)
	if event is InputEventJoypadButton and event.pressed or event is InputEventJoypadMotion and absf(event.axis_value) > 0.25:
		controller_active = true
	elif event is InputEventKey and event.pressed or event is InputEventMouseButton and event.pressed or event is InputEventMouseMotion and event.relative.length() > 2.0:
		controller_active = false
	else:
		return
	_update_hint()

func _uses_gameplay_control(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and event.physical_keycode in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_E, KEY_I, KEY_SPACE]
	if event is InputEventMouseButton:
		return event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]
	if event is InputEventMouseMotion:
		return event.relative.length() > 2.0
	if event is InputEventJoypadMotion:
		return absf(event.axis_value) > 0.25
	return event is InputEventJoypadButton and event.pressed

func _update_hint() -> void:
	if not is_instance_valid(hint): return
	if modal:
		if page == "loading":
			hint.text = "Loading Stonebrook…"
			return
		if dialogue_mode:
			hint.text = "A  Continue / choose" if controller_active else "Enter or click  Continue / choose"
			if dialogue_continue.visible:
				dialogue_continue.text = "Continue   ·   A" if controller_active else "Continue   ·   Enter"
		else:
			var back := "Resume" if return_page == "game" else "Back"
			hint.text = "D-pad / LS  Choose     A  Confirm" if controller_active else "Arrows  Choose     Enter or click  Confirm"
			if page == "settings":
				hint.text += "     Left / right  Adjust" if not controller_active else "     Left / right  Adjust"
			if page != "title": hint.text += "     B  " + back if controller_active else "     Esc  " + back
		return
	if controller_active:
		hint.text = "LS  Move   RS  Look   RT / X  Attack   A  Talk   Back  Equipment   Start  Pause"
	else:
		hint.text = "WASD  Move     Mouse  Look     Left click  Attack     E  Talk     I  Equipment     Esc  Pause"
	if not equipment_stats.get("spell_item", {}).is_empty():
		hint.text += "     LT / Y  Magic" if controller_active else "     Right click  Magic"

func _clear(title: String, next_page: String) -> void:
	_clear_toast()
	if next_page == "pause": return_page = "game"
	elif next_page == "title": return_page = "title"
	elif next_page != page and next_page not in ["dialogue", "loading"]:
		return_page = page if page in ["pause", "title"] else "game"
	page_serial += 1
	menu_scroll.scroll_vertical = 0
	for child in column.get_children():
		column.remove_child(child)
		child.queue_free()
	dialogue_continue.hide()
	menu_footer.hide()
	equipment_name.hide()
	modal = true
	dialogue_mode = false
	page = next_page
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	_layout_for(next_page)
	_set_playing_visuals(false)
	overlay.show()
	panel.show()
	heading.text = title
	heading.add_theme_font_size_override("font_size", roundi(32.0 * text_scale))
	_update_hint()
	_reset_scroll_after_layout.call_deferred(page_serial)

func _reset_scroll_after_layout(serial: int) -> void:
	# Replacing content changes the old scroll range after the container lays out.
	# Reset after deferred focus as well, so each page opens with its heading.
	await get_tree().process_frame
	await get_tree().process_frame
	if serial == page_serial and panel.visible: menu_scroll.scroll_vertical = 0

func _label(text: String, size: int = 22, color: Color = CREAM) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", roundi(float(size) * text_scale))
	label.add_theme_color_override("font_color", color)
	column.add_child(label)
	label.set_meta("base_font_size", size)
	return label

func _button(text: String, action: String, value: Variant = null) -> Button:
	var button := Button.new()
	button.text = text
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.custom_minimum_size.y = roundi(48.0 * text_scale)
	button.set_meta("base_minimum_height", 48)
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(_button_pressed.bind(action, value))
	column.add_child(button)
	return button

func _button_pressed(action: String, value: Variant) -> void:
	if action == "new_game":
		_clear("Beginning your adventure…", "loading")
		_label("Loading Stonebrook. Your adventure will begin shortly.", 22)
	action_requested.emit(action, value)

func _focus() -> void:
	for child in _focusable_children(column):
		if child is Control and child.focus_mode != Control.FOCUS_NONE:
			if child is BaseButton and child.disabled: continue
			_grab_current_focus.call_deferred(child, page_serial)
			return
	if menu_footer.visible: _grab_current_focus.call_deferred(menu_footer, page_serial)

func _grab_current_focus(child: Control, serial: int) -> void:
	if serial == page_serial and is_instance_valid(child) and child.is_inside_tree() and child.is_visible_in_tree():
		child.grab_focus()

func _focusable_children(node: Node) -> Array[Control]:
	var found: Array[Control] = []
	for child in node.get_children():
		if child is Control and child.focus_mode != Control.FOCUS_NONE:
			found.append(child)
		found.append_array(_focusable_children(child))
	return found

func set_text_scale(value: float) -> void:
	text_scale = clampf(value, 0.85, 1.3)
	if not is_instance_valid(root): return
	menu_theme.default_font_size = roundi(22.0 * text_scale)
	hint.add_theme_font_size_override("font_size", roundi(20.0 * text_scale))
	toast.add_theme_font_size_override("font_size", roundi(22.0 * text_scale))
	status_dock.set_text_scale(text_scale)
	heading.add_theme_font_size_override("font_size", roundi(32.0 * text_scale))
	equipment_name.add_theme_font_size_override("font_size", roundi(22.0 * text_scale))
	modal_feedback_text.add_theme_font_size_override("font_size", roundi(20.0 * text_scale))
	menu_footer.custom_minimum_size.y = roundi(48.0 * text_scale)
	for node in column.get_children():
		if node.has_meta("base_font_size"):
			node.add_theme_font_size_override("font_size", roundi(float(node.get_meta("base_font_size")) * text_scale))
		if node.has_meta("base_minimum_height"):
			node.custom_minimum_size.y = roundi(float(node.get_meta("base_minimum_height")) * text_scale)

func show_title(has_save: bool) -> void:
	gameplay_hint_used = false
	gameplay_hint_deadline_msec = 0
	_clear("Your adventure awaits", "title")
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	_label("Dink Smallwood in first person", 20)
	if has_save:
		_button("Continue adventure", "continue")
	_button("Begin adventure", "new_game")
	_button("Settings & controls", "settings")
	_button("Credits & support", "credits")
	_button("Quit", "quit")
	_label("Move with WASD. Look with the mouse.\nE to talk. Left click to attack.\nI for equipment. Esc to pause.\nF1 to show controls again. Controller? See Settings & controls.", 18)
	_label("Unofficial 3D adaptation by PilferedParrot\nDevelopment release %s" % version, 18)
	_focus()

func show_pause() -> void:
	_clear("Adventure paused", "pause")
	_button("Return to adventure", "resume")
	_button("Save adventure", "save")
	_button("Load saved adventure", "load")
	_button("Equipment", "inventory")
	_button("Adventure journal", "journal")
	_button("World map", "map")
	_button("Settings & controls", "settings")
	_button("Credits & support", "credits")
	_button("Title screen", "title")
	_button("Quit game", "quit")
	_focus()

func show_hud(stats: Dictionary) -> void:
	equipment_stats = stats
	status_dock.update_stats(stats)
	var life := float(stats.get("life", 10)); var life_max := maxf(float(stats.get("lifemax", 10)), 1.0)
	var mana := float(stats.get("magic_level", 0)); var mana_max := maxf(float(stats.get("magic_cost", 100)), 1.0)
	health_bar.value = clampf(life / life_max * 100.0, 0.0, 100.0)
	mana_bar.value = clampf(mana / mana_max * 100.0, 0.0, 100.0)
	hud.text = "DINK   •   Health %d / %d   •   Level %d   •   Gold %d\n%s" % [life,life_max,stats.get("level",1),stats.get("gold",0),stats.get("location", "Stonebrook")]
	var weapon := str(stats.get("weapon", stats.get("weapon_name", "")))
	if not weapon.is_empty(): hud.text += "\nWeapon: " + weapon
	compass_label.text = str(stats.get("location", ""))
	_update_hint()

func show_dialogue(text: String, speaker: String = "Dink") -> void:
	_clear(speaker, "dialogue")
	dialogue_mode = true
	_update_hint()
	_label(text, 26)
	dialogue_continue.text = "Continue   ·   A" if controller_active else "Continue   ·   Enter"
	dialogue_continue.custom_minimum_size.y = roundi(52.0 * text_scale)
	dialogue_continue.show()
	_grab_current_focus.call_deferred(dialogue_continue, page_serial)

func _continue_dialogue() -> void:
	hide_dialogue()
	dialogue_finished.emit(0)

func show_choices(title: String, options: Array) -> void:
	_clear(title if not title.is_empty() else "What will you do?", "dialogue")
	dialogue_mode = true
	_update_hint()
	for i in range(options.size()):
		var button := Button.new()
		button.text = str(options[i])
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size.y = roundi(48.0 * text_scale)
		button.focus_mode = Control.FOCUS_ALL
		button.pressed.connect(_choose_dialogue.bind(i + 1))
		column.add_child(button)
	_focus()

func _choose_dialogue(choice: int) -> void:
	hide_dialogue()
	dialogue_finished.emit(choice)

func hide_dialogue() -> void:
	close_menu()
	dialogue_mode = false

func close_menu() -> void:
	modal = false
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.hide()
	overlay.hide()
	title_art.hide(); vines_left.hide(); vines_right.hide()
	page = "game"
	_set_playing_visuals(true)
	_update_hint()
	_sync_feedback()

func request_back() -> void:
	if dialogue_mode or page in ["title", "loading"]: return
	var action := "pause" if return_page == "pause" else ("title" if return_page == "title" else "resume")
	action_requested.emit(action, null)

func _clear_toast() -> void:
	toast.text = ""
	toast_backing.hide()
	if is_instance_valid(modal_feedback): modal_feedback.hide()
	if is_instance_valid(toast_timer): toast_timer.stop()

func notify(text: String) -> void:
	toast.text = text
	toast_timer.start()
	_sync_feedback()

func _sync_feedback() -> void:
	var active := not toast.text.is_empty() and toast_timer.time_left > 0
	toast_backing.visible = active and not modal
	modal_feedback.visible = active and modal
	if active and modal:
		modal_feedback_text.text = toast.text
		modal_feedback_text.tooltip_text = toast.text
		var font_size := roundi(20.0 * text_scale)
		var width := modal_feedback_text.get_theme_font("font").get_string_size(toast.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		modal_feedback.custom_minimum_size.x = minf(width + 32, 280)

func show_inventory(items: Array, magic_items: Array) -> void:
	_clear("Your equipment", "inventory")
	_label("Choose a filled slot to equip it. E marks equipped items.", 18)
	equipment_name.text = "Select a weapon, item or spell."
	equipment_name.add_theme_font_size_override("font_size", roundi(22.0 * text_scale))
	equipment_name.show()
	var chest = preload("res://scripts/dink_equipment_chest.gd").new()
	chest.name = "EquipmentChest"
	chest.configure(items, magic_items, equipment_stats, status_dock.item_texture, text_scale)
	chest.selected.connect(_button_pressed)
	chest.highlighted.connect(_describe_equipment.bind(equipment_name))
	column.add_child(chest)
	if magic_items.is_empty():
		_label("No magic yet. Seek a teacher on your travels.", 18)
	menu_footer.text = "Back to paused adventure" if return_page == "pause" else "Back to adventure"
	menu_footer.custom_minimum_size.y = roundi(48.0 * text_scale)
	menu_footer.show()
	_focus()

func _describe_equipment(text: String, label: Label) -> void:
	label.text = text

func show_journal(text: String) -> void:
	_clear("Adventure journal", "journal")
	_label(text, 22)
	_button("Back to paused adventure", "back")
	_focus()

func show_settings(settings: Dictionary) -> void:
	_clear("Settings & controls", "settings")
	_label("Move: WASD / left stick    Aim: mouse / right stick\nAttack: left click / RT / X    Magic: right click / LT / Y\nTalk: E / A    Jump: Space / right stick click    Sprint: Shift / left stick click\nEquipment: I / Back (Select)    Quick weapons: 1–9 / LB and RB    Pause: Esc / Start\nWorld map: M or Pause → World map (once received)\nControls help: F1 (shows for 8 seconds)\nMenus: arrows / D-pad / left stick, Enter / A, Esc / B\nController labels use the Xbox layout; other mapped gamepads use the same button positions.", 18)
	for setting in [["master", "Master volume", 0.0, 1.0, 0.1, 0.8], ["music", "Music volume", 0.0, 1.0, 0.05, 0.55], ["sfx", "Sound effects", 0.0, 1.0, 0.1, 0.8], ["text_scale", "Text size", 0.85, 1.3, 0.05, 1.0], ["mouse_sensitivity", "Mouse sensitivity", 0.0005, 0.006, 0.0005, 0.002], ["fov", "Field of view", 60.0, 105.0, 1.0, 80.0], ["controller_sensitivity", "Controller look sensitivity", 0.5, 4.0, 0.1, 2.0], ["controller_deadzone", "Controller stick dead zone", 0.05, 0.4, 0.05, 0.2]]:
		var key: String = setting[0]
		var value_label := _label(setting[1], 18)
		var slider := HSlider.new()
		slider.set_meta("setting_key", key)
		slider.min_value = setting[2]
		slider.max_value = setting[3]
		slider.step = setting[4]
		slider.value = float(settings.get(key, setting[5]))
		slider.custom_minimum_size.y = roundi(30.0 * text_scale)
		slider.focus_mode = Control.FOCUS_ALL
		slider.draw.connect(_draw_slider_focus.bind(slider))
		slider.focus_entered.connect(slider.queue_redraw)
		slider.focus_exited.connect(slider.queue_redraw)
		slider.value_changed.connect(_setting_changed.bind(key))
		slider.value_changed.connect(_setting_readout.bind(value_label, str(setting[1]), key))
		column.add_child(slider)
		_setting_readout(slider.value, value_label, str(setting[1]), key)
	var invert := Button.new()
	invert.toggle_mode = true
	invert.set_meta("setting_key", "controller_invert_y")
	invert.text = "Invert controller vertical look"
	invert.focus_mode = Control.FOCUS_ALL
	invert.button_pressed = settings.get("controller_invert_y", false)
	invert.toggled.connect(_controller_invert_changed)
	invert.toggled.connect(_toggle_readout.bind(invert, "Invert controller vertical look"))
	_toggle_readout(invert.button_pressed, invert, "Invert controller vertical look")
	column.add_child(invert)
	var reduced := Button.new()
	reduced.toggle_mode = true
	reduced.set_meta("setting_key", "reduced_motion")
	reduced.text = "Reduce camera movement"
	reduced.focus_mode = Control.FOCUS_ALL
	reduced.button_pressed = settings.get("reduced_motion", false)
	reduced.toggled.connect(_reduced_motion_changed)
	reduced.toggled.connect(_toggle_readout.bind(reduced, "Reduce camera movement"))
	_toggle_readout(reduced.button_pressed, reduced, "Reduce camera movement")
	column.add_child(reduced)
	_button("Done", "back")
	_focus()

func _setting_changed(value: float, key: String) -> void:
	action_requested.emit("setting", {"key": key, "value": value})

func _draw_slider_focus(slider: HSlider) -> void:
	if not slider.has_focus(): return
	# Corner brackets frame the control without crossing its track or thumb.
	var left := 1.0
	var right := slider.size.x - 1.0
	var top := 1.0
	var bottom := slider.size.y - 1.0
	var length := minf(8.0, slider.size.y * 0.25)
	for x in [left, right]:
		var inward := length if x == left else -length
		for y in [top, bottom]:
			var vertical := length if y == top else -length
			slider.draw_line(Vector2(x, y), Vector2(x + inward, y), GOLD, 2)
			slider.draw_line(Vector2(x, y), Vector2(x, y + vertical), GOLD, 2)

func _toggle_readout(value: bool, button: Button, title: String) -> void:
	button.text = "%s   %s" % [title, "On" if value else "Off"]

func _setting_readout(value: float, label: Label, title: String, key: String) -> void:
	var shown := "%.2f" % value
	if key in ["master", "music", "sfx", "controller_deadzone"]: shown = "%d%%" % roundi(value * 100)
	elif key == "fov": shown = "%d°" % roundi(value)
	elif key == "text_scale": shown = "%d%%" % roundi(value * 100)
	elif key == "mouse_sensitivity": shown = "%.2f×" % (value / 0.002)
	label.text = "%s   %s" % [title, shown]

func _reduced_motion_changed(value: bool) -> void:
	action_requested.emit("setting", {"key": "reduced_motion", "value": value})

func _controller_invert_changed(value: bool) -> void:
	action_requested.emit("setting", {"key": "controller_invert_y", "value": value})

func show_credits() -> void:
	_clear("Credits & support", "credits")
	_label("3D adaptation · PilferedParrot\nOriginal Dink Smallwood · Seth A. Robinson\nArtwork · Justin Martin\nStory & world · Seth A. Robinson, Greg Smith, Justin Martin\nAdditional levels · Chris Bakker\nv1.08 fixes · Talmadge Bradley III\nFree audio · GNU FreeDink contributors\nEngine · Godot contributors", 20)
	_label("New code: Apache 2.0. Original art, story and audio retain their own licenses. Detailed attributions are bundled in licenses/. This is an unofficial, modified adaptation.", 18)
	_button("Support PilferedParrot on Patreon ↗", "patreon")
	_button("Source code & full credits ↗", "source")
	_button("Done", "back")
	_focus()
