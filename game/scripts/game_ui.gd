# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
extends CanvasLayer
const INPUT_BINDINGS = preload("res://scripts/input_bindings.gd")
const CONTROLS_MENU = preload("res://scripts/controls_menu.gd")
const PLAIN_FONT = preload("res://assets/fonts/AtkinsonHyperlegible-Regular.ttf")
var controls_menu: VBoxContainer
var bindings
var control_primer_label: Label
var controls_label: Label
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
var dialogue_layout_key := Vector4.INF
var speech_request := 0
var active_speech_id := 0
var speech_born_msec := 0
# -1: readable natural expiry; 0: persistent; positive: explicit script deadline.
var speech_deadline_msec := -1
var pending_speech: Dictionary = {}
# Independent text sprites. The shared card presents the newest live line;
# expiry and script waiters belong to IDs, never to global menu modality.
var speech_lines: Dictionary = {}
var speech_pause_started_msec := -1
var speech_pause_offset_msec := 0
var speech_waits_for_me := false:
	set(value):
		speech_waits_for_me = value
		for line in speech_lines.values(): line.waits = value and bool(line.get("script_waits", false))
		if is_instance_valid(root): _update_hint()
var timed_reading_done := false
var speech_dismiss_hint: Label
var page := "title"
var text_scale := 1.0
var plain_font := false
var menu_theme: Theme
var controller_active := false
var title_art: TextureRect
var vines_left: TextureRect
var vines_right: TextureRect
var status_dock: Control
var equipment_stats: Dictionary = {}
var dialogue_continue: Button
var menu_scroll: ScrollContainer
var choice_prompt_scroll: ScrollContainer
var choice_prompt: Label
var choice_prompt_axis := 0.0
var timed_text := ""
var timed_layout_key := Vector4.INF
var timed_phase := 0
var timed_phase_elapsed := 0.0
var timed_hold := 0.0
var timed_last_hold := 0.0
var timed_scroll_speed := 0.0
var timed_scroll_offset := 0.0
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
var heading_row: VBoxContainer
var gameplay_hint_used := false
var gameplay_hint_deadline_msec := 0
const GAMEPLAY_HINT_SECONDS := 8.0
const SPEECH_VINE_SIZE := Vector2(80, 140)
# Display policy, not VM time: 170 words/minute, with a 17 character/second
# ceiling for long tokens. BBC R&D WHP306 reports a scrolling peak near171wpm.
const SPEECH_WORDS_PER_SECOND := 170.0 / 60.0
const SPEECH_CHARACTERS_PER_SECOND := 17.0
const CREAM := Color("f6ebcb")
const GOLD := Color("ffdc79")
const INK := Color("292019")
const CHOICE_BACKDROP = preload("res://assets/graphics/inter/Text-box/main-03.png")
const LOGO = preload("res://assets/graphics/Startme/options/dinkl-01.png")

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	if bindings == null:
		bindings = INPUT_BINDINGS.new()
		bindings.install()
	bindings.changed.connect(_bindings_changed)
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
	heading_row = VBoxContainer.new()
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
	modal_feedback_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	modal_feedback.add_child(modal_feedback_text)
	modal_feedback.hide()
	choice_prompt_scroll = ScrollContainer.new()
	choice_prompt_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	choice_prompt_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contents.add_child(choice_prompt_scroll)
	choice_prompt = Label.new()
	choice_prompt.name = "ChoicePrompt"
	choice_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	choice_prompt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice_prompt_scroll.add_child(choice_prompt)
	choice_prompt_scroll.hide()
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
	speech_dismiss_hint = Label.new()
	speech_dismiss_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	speech_dismiss_hint.add_theme_font_size_override("font_size", 18)
	speech_dismiss_hint.hide()
	contents.add_child(speech_dismiss_hint)
	menu_footer = Button.new()
	menu_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu_footer.custom_minimum_size.y = 48
	menu_footer.focus_mode = Control.FOCUS_ALL
	menu_footer.pressed.connect(_button_pressed.bind("back", null))
	contents.add_child(menu_footer)
	menu_footer.hide()
	# Instructions and notifications must render above the modal dimming layer.
	root.move_child(hint_backing, -1)
	root.move_child(toast_backing, -1)
	_set_playing_visuals(false)
	set_text_scale(text_scale)

func _vine(path: String) -> TextureRect:
	var vine := TextureRect.new()
	vine.texture = load(path)
	vine.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vine.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vine)
	return vine

func _process(_delta: float) -> void:
	var speech_now := _speech_now_msec()
	var speech_step := 0.0 if speech_pause_started_msec >= 0 else _delta
	for id in speech_lines.keys():
		var line: Dictionary = speech_lines[id]
		# FreeDink109.6 game_engine.cpp:188-207 uses a monotonic millisecond
		# clock. Godot clamps slow-frame delta: it must not extend short text.
		if not bool(line.get("layout_pending", false)):
			line.remaining = maxf(0, minf(float(line.remaining) - speech_step, float(int(line.expires) - speech_now) / 1000.0))
		var expired := int(line.deadline) > 0 and speech_now >= int(line.deadline)
		if int(line.deadline) == -1 and not bool(line.waits) and not bool(line.get("layout_pending", false)) and float(line.remaining) <= 0:
			# Keep P2's complete overflow reading/scroll coverage for the card
			# being read; hidden text still ages independently like FreeDink.
			expired = id != active_speech_id or page != "dialogue" or dialogue_mode or not bool(line.get("overflow", false)) or timed_reading_done
		if expired: cancel_speech_id(id)
	if page == "dialogue": _fit_dialogue_panel()
	if page == "dialogue" and not dialogue_mode: _advance_timed_speech(_delta)
	if page == "dialogue" and not modal:
		# Large speech can reach the aiming point. Keep the reticle from being
		# drawn through the speaker or text; ordinary gameplay restores it.
		crosshair.visible = not panel.get_global_rect().grow(3).intersects(crosshair.get_global_rect())
	if page == "dialogue" and choice_prompt_scroll.visible:
		choice_prompt_axis = Input.get_action_strength("ui_page_down") - Input.get_action_strength("ui_page_up")
		if not is_zero_approx(choice_prompt_axis):
			choice_prompt_scroll.scroll_vertical += roundi(choice_prompt_axis * _choice_prompt_step() * _delta)
		_update_hint()
	# A top-level Container grows to a wrapped Label's minimum but does not
	# shrink when that minimum falls. Startup can wrap before width settles;
	# keep the anchored width and own the content height on every layout pass.
	toast_backing.size.y = toast_backing.get_combined_minimum_size().y
	panel_underlay.visible = panel.visible and page != "title"
	if panel.visible:
		panel_underlay.position = panel.position
		panel_underlay.size = panel.size
		vines_left.position = panel.position + Vector2(-65, 0)
		vines_left.size = SPEECH_VINE_SIZE
		vines_right.position = panel.position + Vector2(panel.size.x - 15, 0)
		vines_right.size = vines_left.size
	if modal:
		hint_backing.modulate.a = 1.0
		hint_backing.visible = not hint.text.is_empty()
	else:
		# UI help expires in real time even when a heavy scene renders slowly.
		var remaining := maxf(0.0, float(gameplay_hint_deadline_msec - Time.get_ticks_msec()) / 1000.0)
		hint_backing.modulate.a = minf(1.0, remaining) if gameplay_hint_used else 1.0
		hint_backing.visible = hint_backing.modulate.a > 0.0 and not hint.text.is_empty()
		status_dock.set_context_hints_visible(hint_backing.visible)
	# A solid plaque keeps control instructions readable against every scene.
	var available := root.size.x - 40
	var font_size := hint.get_theme_font_size("font_size")
	var text_width := hint.get_theme_font("font").get_string_size(hint.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var width := minf(available, text_width + 24)
	hint_backing.offset_left = -width / 2; hint_backing.offset_right = width / 2
	var height := maxf(38, hint.get_minimum_size().y + 12)
	var dock_top: float = status_dock.global_position.y + status_dock.art_rect().position.y
	if status_dock.has_method("readout_top"): dock_top = status_dock.readout_top()
	hint_backing.offset_bottom = -6 if modal else dock_top - root.size.y - 8
	hint_backing.offset_top = hint_backing.offset_bottom - height
	if panel.visible and page != "dialogue":
		# Reserve the actual wrapped hint, including long remapped key names.
		panel.offset_bottom = 0
		var bottom := hint_backing.position.y - 8 if hint_backing.visible else root.size.y * 0.90
		panel.offset_bottom = minf(0, bottom - panel.anchor_bottom * root.size.y)

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
	panel.offset_top = 0
	panel.offset_bottom = 0
	if next_page == "title":
		panel.anchor_left = 0.38 if text_scale > 1.3 else 0.56
		panel.anchor_right = 0.96 if text_scale > 1.3 else 0.94
		panel.anchor_top = 0.10; panel.anchor_bottom = 0.92
		title_art.anchor_right = 0.34 if text_scale > 1.3 else 0.52
		overlay.color = Color.BLACK
	elif next_page == "dialogue":
		panel.anchor_left = 0.12; panel.anchor_right = 0.88
		panel.anchor_top = 0; panel.anchor_bottom = 0
		overlay.color = Color(0.025, 0.015, 0.008, 0.08)
	else:
		panel.anchor_left = 0.14; panel.anchor_right = 0.86
		panel.anchor_top = 0.07; panel.anchor_bottom = 0.90
		overlay.color = Color(0.025, 0.015, 0.008, 0.72)
	title_art.visible = next_page == "title"
	panel.add_theme_stylebox_override("panel", title_panel_style if next_page == "title" else panel_style)
	vines_left.visible = next_page != "title"; vines_right.visible = next_page != "title"

# Short speech uses only the height its heading, text and action need. The
# former fixed 35% menu card left most of a one-line conversation empty.
# The usual35% cap yields only to native full-line/focused-action minima at
# large text sizes. Never trade the requested font size for a smaller card.
func _fit_dialogue_panel() -> void:
	var chrome := panel.get_combined_minimum_size().y-menu_scroll.get_combined_minimum_size().y
	var body := column.get_combined_minimum_size().y
	var bottom: float = status_dock.readout_top() - column.get_theme_constant("separation")
	var available_height := maxf(1, bottom - column.get_theme_constant("separation"))
	var readable_body := 0.0
	if column.get_child_count() > 0 and column.get_child(0) is Label:
		var label: Label = column.get_child(0)
		readable_body = minf(body, label.get_line_height() * 2 + label.get_theme_constant("line_spacing"))
	var answer: Control
	var answer_height := 0.0
	if dialogue_mode and not dialogue_continue.visible and column.get_child_count() > 0:
		answer = get_viewport().gui_get_focus_owner()
		if answer == null or not column.is_ancestor_of(answer):
			answer = column.get_child(0) if column.get_child_count() > 0 else null
		answer_height = answer.get_combined_minimum_size().y if answer != null else 0.0
		readable_body = answer_height
	if choice_prompt_scroll.visible:
		chrome -= choice_prompt_scroll.get_combined_minimum_size().y
		body += choice_prompt.get_combined_minimum_size().y
		readable_body = answer_height + minf(choice_prompt.get_combined_minimum_size().y, choice_prompt.get_line_height())
	var height := minf(available_height, minf(chrome+body,maxf(chrome+readable_body,root.size.y*0.35)))
	if choice_prompt_scroll.visible:
		var available := maxf(0, height - chrome)
		# Give the focused answer its full height first. The prompt has its own
		# viewport and cannot push the selected action below the fold.
		var prompt_height := minf(choice_prompt.get_combined_minimum_size().y, maxf(0, available - answer_height))
		if choice_prompt_scroll.custom_minimum_size.y != prompt_height:
			choice_prompt_scroll.custom_minimum_size.y = prompt_height
			_keep_choice_visible.call_deferred(answer, page_serial)
	# All speech and choices share one footprint, even when blocking speech
	# hides the HUD. Include the vines, which can outgrow a short timed card.
	var top := bottom - maxf(height, SPEECH_VINE_SIZE.y)
	var key := Vector4(chrome,body,height,top)
	if key == dialogue_layout_key: return
	dialogue_layout_key = key
	panel.anchor_top = 0
	panel.anchor_bottom = 0
	panel.offset_top = top
	panel.offset_bottom = top + height

func _keep_choice_visible(answer: Control, serial: int) -> void:
	if serial == page_serial and is_instance_valid(answer) and answer.is_inside_tree():
		menu_scroll.ensure_control_visible(answer)

func _bindings_changed() -> void:
	_update_hint()
	# These are the only persistent labels whose text is built on page entry.
	if page == "title": show_title(FileAccess.file_exists("user://adventure.json"))
	elif page == "settings": show_settings(bindings.settings)

func _key(action: String) -> String:
	return bindings.short_label(action,controller_active)

func _navigation_hint() -> String:
	return "%s / %s  Choose     %s or click  Confirm" % [_key("ui_up"),_key("ui_down"),_key("ui_accept")]

func _gameplay_hint() -> String:
	var text := "%s  Move" % bindings.movement_label(controller_active)
	if bindings.context == "fps": text += "   %s  Look" % ("Mouse" if not controller_active else bindings.look_label())
	text += "   %s  Attack   %s  Talk   %s  Equipment   %s  Pause" % [_key("attack"),_key("talk"),_key("inventory"),_key("pause")]
	if not equipment_stats.get("spell_item",{}).is_empty(): text += "   %s  Magic" % _key("magic")
	return text

func _control_primer() -> String:
	var look := " · Mouse look" if bindings.context == "fps" else ""
	return "%s move%s\n%s talk · %s attack\n%s gear · %s pause · %s help" % [bindings.movement_label(),look,bindings.short_label("talk"),bindings.short_label("attack"),bindings.short_label("inventory"),bindings.short_label("pause"),bindings.short_label("help")]

func _controls_group(ids: Array) -> String:
	var parts: Array[String] = []
	for action in ids:
		if bindings.actions[action].contexts.has(bindings.context) or bindings.actions[action].contexts.has("global"):
			parts.append("%s: %s" % [bindings.actions[action].name,bindings.label(action,false,"",true)])
	return "    ".join(parts)

func _controls_text() -> String:
	var lines: Array[String] = ["Move: " + bindings.movement_label() + " / " + bindings.movement_label(true)]
	if bindings.context == "fps": lines[0] += "    Aim: mouse / " + bindings.look_label(true,true)
	lines.append(_controls_group(["attack","magic"]))
	lines.append(_controls_group(["talk","jump","sprint"]))
	var equipment := _controls_group(["inventory"])
	if bindings.context == "fps":
		var slots: Array[String] = []
		var consecutive := true
		for slot in range(1,10):
			var label: String = bindings.label("weapon_%d" % slot,false,"",true)
			slots.append(label)
			consecutive = consecutive and label == str(slot)
		equipment += "    Weapon slots: " + ("1–9" if consecutive else ", ".join(slots))
		equipment += " / " + bindings.label("weapon_previous",false,"",true) + " / " + bindings.label("weapon_next",false,"",true)
	lines.append(equipment)
	lines.append(_controls_group(["pause","map","help"]))
	lines.append(_controls_group(["camera","fullscreen","bug_report"]))
	lines.append("Guaranteed back / pause: " + bindings.label("escape"))
	lines.append("Controller labels use Xbox button positions.")
	return "\n".join(lines)

func _input(event: InputEvent) -> void:
	if modal and page != "dialogue" and not (page == "controls" and controls_menu.state == "capture"):
		# Reading must also reach labels after the final focusable action (the
		# title primer, journal, credits). Native ScrollContainer has wheel and
		# drag input; these are our already-configurable menu reading actions.
		var reading_scroll: ScrollContainer = controls_menu.scroll if page == "controls" else menu_scroll
		var direction := int(event.is_action_pressed("ui_page_down")) - int(event.is_action_pressed("ui_page_up"))
		if event.is_action_pressed("ui_home") or event.is_action_pressed("ui_end") or direction != 0:
			if event.is_action_pressed("ui_home"): reading_scroll.scroll_vertical = 0
			elif event.is_action_pressed("ui_end"):
				reading_scroll.scroll_vertical = ceili(reading_scroll.get_v_scroll_bar().max_value)
			else:
				var line := root.get_theme_font("font").get_height(menu_theme.default_font_size)
				reading_scroll.scroll_vertical += roundi(direction * maxf(1,reading_scroll.size.y-line))
			controller_active = event is InputEventJoypadButton or event is InputEventJoypadMotion
			_update_hint()
			get_viewport().set_input_as_handled()
			return
	if page == "dialogue" and not dialogue_mode and speech_lines.has(active_speech_id):
		if bool(speech_lines[active_speech_id].waits) and event.is_action_pressed("talk") and not event.is_echo():
			controller_active = event is InputEventJoypadButton or event is InputEventJoypadMotion
			cancel_speech_id(active_speech_id)
			get_viewport().set_input_as_handled()
			return
	if page == "dialogue" and choice_prompt_scroll.visible:
		var direction := int(event.is_action_pressed("ui_page_down")) - int(event.is_action_pressed("ui_page_up"))
		if direction != 0 and not event is InputEventJoypadMotion:
			controller_active = event is InputEventJoypadButton
			choice_prompt_scroll.scroll_vertical += roundi(direction * _choice_prompt_step())
			get_viewport().set_input_as_handled()
			_update_hint()
			return
	if not modal and event.is_action_pressed("help") and not event.is_echo():
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
	if event is InputEventMouseMotion: return event.relative.length() > 2.0
	for action in bindings.gameplay_actions():
		if event.is_action_pressed(action): return true
	return false

func _choice_prompt_step() -> float:
	# A single-line viewport must page to the next baseline, not through
	# fractional lines that never expose a complete row at large text sizes.
	var pitch := float(choice_prompt.get_line_height() + choice_prompt.get_theme_constant("line_spacing"))
	return pitch * maxf(1, floorf(choice_prompt_scroll.size.y / maxf(1,pitch)))

func _update_hint() -> void:
	if is_instance_valid(speech_dismiss_hint):
		speech_dismiss_hint.visible = page == "dialogue" and not dialogue_mode and speech_lines.has(active_speech_id) and bool(speech_lines[active_speech_id].waits)
		speech_dismiss_hint.text = "%s  Dismiss" % _key("talk")
	if is_instance_valid(control_primer_label): control_primer_label.text = _control_primer()
	if is_instance_valid(controls_label): controls_label.text = _controls_text()
	if not is_instance_valid(hint): return
	if page == "controls":
		hint.text = ""
		return
	if page == "dialogue" and not dialogue_mode:
		# Timed speech shares the card; gameplay help must not cover its name.
		hint.text = ""
		return
	if modal:
		if page == "loading":
			hint.text = "Loading Stonebrook…"
			return
		if dialogue_mode:
			if dialogue_continue.visible:
				# The focused action already gives its keyboard/controller cue.
				hint.text = ""
				dialogue_continue.text = "Continue   ·   " + _key("ui_accept")
			else:
				hint.text = _navigation_hint()
				if choice_prompt_scroll.visible and choice_prompt_scroll.get_v_scroll_bar().max_value > choice_prompt_scroll.size.y:
					hint.text += "     %s / %s  Read prompt" % [_key("ui_page_up"),_key("ui_page_down")]
		else:
			var back := "Resume" if return_page == "game" else "Back"
			hint.text = _navigation_hint()
			if page == "settings":
				hint.text += "     %s / %s  Adjust" % [_key("ui_left"),_key("ui_right")]
			if page != "title": hint.text += "     " + _key("ui_cancel") + "  " + back
		return
	hint.text = _gameplay_hint()

func _clear(title: String, next_page: String) -> void:
	# Our modal menus preserve reading time. Script choices remain on the
	# speech clock, as distinct from Escape/Settings/Equipment pages.
	_set_speech_clock_paused(next_page not in ["dialogue", "loading"])
	if is_instance_valid(controls_menu):
		controls_menu.get_parent().remove_child(controls_menu)
		controls_menu.queue_free()
		controls_menu = null
	menu_scroll.show()
	control_primer_label = null
	controls_label = null
	_clear_toast()
	if next_page == "pause": return_page = "game"
	elif next_page == "title": return_page = "title"
	elif next_page != page and next_page not in ["dialogue", "loading"]:
		return_page = page if page in ["pause", "title"] else "game"
	page_serial += 1
	dialogue_layout_key = Vector4.INF
	timed_text = ""
	timed_layout_key = Vector4.INF
	choice_prompt_axis = 0.0
	choice_prompt_scroll.hide()
	choice_prompt_scroll.custom_minimum_size.y = 0
	choice_prompt_scroll.scroll_vertical = 0
	menu_scroll.scroll_vertical = 0
	for child in column.get_children():
		column.remove_child(child)
		child.queue_free()
	dialogue_continue.hide()
	speech_dismiss_hint.hide()
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
	if action == "plain_font": return # Its toggle emits the persisted setting.
	if action == "controls":
		show_controls()
		return
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
	text_scale = clampf(value, 0.85, 2.0)
	if not is_instance_valid(root): return
	menu_theme.default_font_size = roundi(22.0 * text_scale)
	menu_theme.set_font_size("font_size", "TooltipLabel", roundi(18.0 * text_scale))
	compass_label.add_theme_font_size_override("font_size", roundi(18.0 * text_scale))
	compass_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", roundi(20.0 * text_scale))
	toast.add_theme_font_size_override("font_size", roundi(22.0 * text_scale))
	status_dock.set_text_scale(text_scale)
	speech_dismiss_hint.add_theme_font_size_override("font_size", roundi(18.0 * text_scale))
	heading.add_theme_font_size_override("font_size", roundi(32.0 * text_scale))
	equipment_name.add_theme_font_size_override("font_size", roundi(22.0 * text_scale))
	modal_feedback_text.add_theme_font_size_override("font_size", roundi(20.0 * text_scale))
	menu_footer.custom_minimum_size.y = roundi(48.0 * text_scale)
	dialogue_continue.custom_minimum_size.y = roundi(52.0 * text_scale)
	for node in column.get_children():
		if node.has_meta("base_font_size"):
			node.add_theme_font_size_override("font_size", roundi(float(node.get_meta("base_font_size")) * text_scale))
		if node.has_meta("base_minimum_height"):
			node.custom_minimum_size.y = roundi(float(node.get_meta("base_minimum_height")) * text_scale)
	dialogue_layout_key = Vector4.INF
	timed_layout_key = Vector4.INF
	_layout_for(page)

func set_plain_font(value: bool) -> void:
	plain_font = value
	if not is_instance_valid(root): return
	menu_theme.default_font = PLAIN_FONT if plain_font else null
	status_dock.queue_redraw()
	dialogue_layout_key = Vector4.INF
	timed_layout_key = Vector4.INF

func show_title(has_save: bool) -> void:
	cancel_speech()
	gameplay_hint_used = false
	gameplay_hint_deadline_msec = 0
	_clear("Your adventure awaits", "title")
	if has_save:
		_button("Continue adventure", "continue")
	_button("Begin adventure", "new_game")
	_button("Settings & controls", "settings")
	_button("Credits & support", "credits")
	_button("Quit", "quit")
	control_primer_label = _label(_control_primer(), 18)
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
	compass_label.text = str(stats.get("location", ""))
	_update_hint()

# Legacy modal presentation is retained for UI layout probes. DinkC speech
# always uses show_speech; only choices/menus may own player input.
func show_dialogue(text: String, speaker: String = "Dink", blocking: bool = true) -> int:
	if not blocking: return show_speech(text, speaker)
	speech_request += 1
	_clear(speaker, "dialogue")
	dialogue_mode = true
	_label(text)
	dialogue_continue.custom_minimum_size.y = roundi(52.0 * text_scale)
	dialogue_continue.show()
	_update_hint()
	_grab_current_focus.call_deferred(dialogue_continue, page_serial)
	return speech_request

func _speech_now_msec() -> int:
	var tick := Time.get_ticks_msec() if speech_pause_started_msec < 0 else speech_pause_started_msec
	return tick - speech_pause_offset_msec

func _set_speech_clock_paused(paused: bool) -> void:
	var tick := Time.get_ticks_msec()
	if paused and speech_pause_started_msec < 0:
		speech_pause_started_msec = tick
	elif not paused and speech_pause_started_msec >= 0:
		speech_pause_offset_msec += tick - speech_pause_started_msec
		speech_pause_started_msec = -1

static func source_speech_msec(expanded_text: String) -> int:
	# FreeDink109.6 text.cpp:40-65, strlen AFTER substitution, BEFORE colour removal.
	return maxi(2700, expanded_text.to_utf8_buffer().size() * 77)

static func speech_reading_seconds(text: String) -> float:
	var words := text.replace("\n", " ").replace("\t", " ").replace("\r", " ").split(" ", false).size()
	return maxf(float(words) / SPEECH_WORDS_PER_SECOND, float(text.length()) / SPEECH_CHARACTERS_PER_SECOND)

func show_speech(text: String, speaker: String = "Dink", owner: int = 0, ttl_msec: int = -1, script_waits: bool = false) -> int:
	if owner == 0: cancel_owner_speech(0)
	speech_request += 1
	var id := speech_request
	var ttl := source_speech_msec(text) if ttl_msec < 0 else ttl_msec
	# Preserve P2's reading floor for ALL natural speech, including short,
	# word-dense lines that fit without scrolling. Script deadlines override it.
	ttl = maxi(ttl, ceili(speech_reading_seconds(text) * 1000))
	var now := _speech_now_msec()
	speech_lines[id] = {"id":id,"text":text,"speaker":speaker,"owner":owner,"born":now,"expires":now+ttl,"deadline":-1,"remaining":float(ttl)/1000.0,"script_waits":script_waits,"waits":speech_waits_for_me and script_waits}
	if modal:
		pending_speech = speech_lines[id]
	else:
		_present_speech(id)
	return id

func _present_speech(id: int) -> void:
	if not speech_lines.has(id): return
	var line: Dictionary = speech_lines[id]
	_clear(str(line.speaker), "dialogue")
	active_speech_id = id
	speech_born_msec = int(line.born)
	speech_deadline_msec = int(line.deadline)
	dialogue_mode = false
	_label(str(line.text))
	modal = false
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.hide()
	_set_playing_visuals(true)
	timed_text = str(line.text)
	timed_reading_done = false
	timed_layout_key = Vector4.INF
	_update_hint()

func has_owner_speech(owner: int) -> bool:
	for line in speech_lines.values():
		if int(line.owner) == owner: return true
	return false

func cancel_owner_speech(owner: int) -> void:
	for id in speech_lines.keys():
		if int(speech_lines[id].owner) == owner: cancel_speech_id(id)

func _advance_timed_speech(delta: float) -> void:
	var bar := menu_scroll.get_v_scroll_bar()
	var extent := maxf(0, bar.max_value - bar.page)
	if speech_lines.has(active_speech_id): speech_lines[active_speech_id].overflow = extent > 0
	var label: Label = column.get_child(0) if column.get_child_count() > 0 else null
	if label == null: return
	var line_step := float(label.get_line_height() + label.get_theme_constant("line_spacing"))
	var key := Vector4(column.get_combined_minimum_size().y, menu_scroll.size.y, extent, line_step)
	if key != timed_layout_key:
		# Reflow starts reading again at the top; a resize never skips text.
		timed_layout_key = key
		var reading := speech_reading_seconds(timed_text)
		var visible_fraction := minf(1, menu_scroll.size.y / maxf(1, key.x))
		timed_hold = reading * visible_fraction if extent > 0 else reading
		timed_last_hold = reading * visible_fraction
		timed_scroll_speed = key.x / reading if reading > 0 else 0.0
		timed_scroll_offset = 0
		timed_phase_elapsed = 0
		timed_phase = 0
		menu_scroll.scroll_vertical = 0
		return
	if timed_phase == 0:
		timed_phase_elapsed += delta
		if timed_phase_elapsed >= timed_hold:
			if extent <= 0:
				timed_reading_done = true
			else: timed_phase = 1; timed_phase_elapsed = 0
	elif timed_phase == 1:
		# Even a stalled render may advance at most one overlapping text page.
		# Each line must be fully visible in some frame before normal expiry.
		var step := minf(timed_scroll_speed * delta, maxf(1, menu_scroll.size.y - line_step))
		timed_scroll_offset = minf(extent, timed_scroll_offset + step)
		menu_scroll.scroll_vertical = ceili(timed_scroll_offset)
		if timed_scroll_offset >= extent:
			timed_phase = 2
			timed_phase_elapsed = 0
	else:
		timed_phase_elapsed += delta
		if timed_phase_elapsed >= timed_last_hold: timed_reading_done = true

func _show_pending_speech() -> void:
	if modal or (page == "dialogue" and speech_lines.has(active_speech_id)): return
	pending_speech = {}
	if not speech_lines.is_empty():
		_present_speech(int(speech_lines.keys().back()))

func _finish_speech_layout(id: int) -> void:
	if speech_lines.has(id) and bool(speech_lines[id].get("layout_pending", false)):
		speech_lines[id].layout_pending = false
		speech_lines[id].expires = _speech_now_msec() + roundi(float(speech_lines[id].remaining) * 1000)

func prepare_dialogue_layout() -> bool:
	var id := active_speech_id
	if speech_lines.has(id): speech_lines[id].layout_pending = true
	var serial := page_serial
	panel.hide(); panel_underlay.hide(); vines_left.hide(); vines_right.hide()
	for _i in 3:
		await get_tree().process_frame
		if serial != page_serial or page != "dialogue":
			_finish_speech_layout(id)
			return false
		_fit_dialogue_panel()
	# These are the decorations' actual future positions, even while hidden.
	panel_underlay.position = panel.position
	panel_underlay.size = panel.size
	vines_left.position = panel.position + Vector2(-65, 0)
	vines_left.size = SPEECH_VINE_SIZE
	vines_right.position = panel.position + Vector2(panel.size.x-15, 0)
	vines_right.size = vines_left.size
	return true

func speech_safe_rect() -> Rect2:
	var viewport := get_viewport().get_visible_rect()
	var top := panel.get_global_rect().position.y
	for decoration in [panel_underlay, vines_left, vines_right]:
		top = minf(top, decoration.get_global_rect().position.y)
	var margin := float(column.get_theme_constant("separation"))
	return Rect2(viewport.position+Vector2(margin,margin), Vector2(maxf(0,viewport.size.x-2*margin),maxf(0,top-viewport.position.y-2*margin)))

func reveal_dialogue() -> void:
	if page != "dialogue": return
	_finish_speech_layout(active_speech_id)
	panel.show(); panel_underlay.show(); vines_left.show(); vines_right.show()
	# Initial deferred focus can run while prepare_dialogue_layout hides the
	# panel. Restore it only after the measured card becomes visible.
	if dialogue_mode: _grab_current_focus.call_deferred(dialogue_continue, page_serial)

func _continue_dialogue() -> void:
	hide_dialogue()
	dialogue_finished.emit(0)

func show_choices(title: String, options: Array) -> void:
	_clear("What will you do?", "dialogue")
	dialogue_mode = true
	# The prompt scrolls independently so the focused answer stays visible
	# while the entire card retains the speech height cap.
	if not title.is_empty():
		choice_prompt.text = title
		choice_prompt_scroll.show()
	_update_hint()
	for i in range(options.size()):
		var button := Button.new()
		button.text = str(options[i])
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size.y = roundi(48.0 * text_scale)
		button.focus_mode = Control.FOCUS_ALL
		# Keep the first option as the keyboard/pad confirmation owner while
		# reporting its prompt first to assistive apps. Page entry resets to top.
		if i == 0 and not title.is_empty(): button.accessibility_name = title + "\n" + button.text
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
	_set_speech_clock_paused(false)
	# An explicit close of a displayed text removes THAT text only. Opening
	# a menu uses _clear and preserves independent text lifetimes underneath.
	if page == "dialogue" and not dialogue_mode:
		speech_lines.erase(active_speech_id)
	active_speech_id = 0
	page_serial += 1
	speech_request += 1
	modal = false
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.hide()
	overlay.hide()
	title_art.hide(); vines_left.hide(); vines_right.hide()
	page = "game"
	timed_text = ""
	choice_prompt_axis = 0.0
	_set_playing_visuals(true)
	_update_hint()
	_sync_feedback()
	_show_pending_speech.call_deferred()

func is_speech_active(id: int) -> bool:
	return speech_lines.has(id)

func set_speech_ttl(id: int, milliseconds: int) -> void:
	if not speech_lines.has(id): return
	var line: Dictionary = speech_lines[id]
	line.deadline = 0 if milliseconds <= 0 else int(line.born) + milliseconds
	if active_speech_id == id: speech_deadline_msec = int(line.deadline)
	if int(line.deadline) > 0 and _speech_now_msec() >= int(line.deadline): cancel_speech_id(id)

func cancel_speech_id(id: int) -> void:
	if not speech_lines.has(id): return
	speech_lines.erase(id)
	if int(pending_speech.get("id", 0)) == id: pending_speech = {}
	if active_speech_id == id and page == "dialogue" and not dialogue_mode:
		close_menu()

func cancel_speech() -> void:
	var was_blocking := dialogue_mode
	speech_lines.clear()
	pending_speech = {}
	speech_request += 1
	if page == "dialogue":
		close_menu()
		dialogue_mode = false
	if was_blocking: dialogue_finished.emit(-1)

func request_back() -> void:
	if dialogue_mode or page in ["title", "loading"]: return
	if page == "controls":
		if controls_menu.back(): return
		var parent_page := return_page
		show_settings(bindings.settings)
		return_page = parent_page
		return
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
		modal_feedback.custom_minimum_size.x = 0

func show_inventory(items: Array, magic_items: Array) -> void:
	_clear("Your equipment", "inventory")
	var equipped_names: Array[String] = []
	for key in ["weapon_item", "spell_item"]:
		var item: Variant = equipment_stats.get(key, {})
		var name := "None"
		if item is Dictionary:
			name = str(item.get("name", "")).strip_edges()
			if name.is_empty():
				var script := str(item.get("script", "")).strip_edges()
				name = script.trim_prefix("item-").replace("-", " ").capitalize() if not script.is_empty() else "None"
		equipped_names.append(name)
	heading.text = "Equipped: %s (weapon)  ·  %s (spell)" % equipped_names
	_label("Choose a filled slot to equip it. E marks equipped items.", 18)
	equipment_name.text = "Selected: Choose a weapon, item or spell."
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
	label.text = "Selected: " + text

func show_journal(text: String) -> void:
	_clear("Adventure journal", "journal")
	_label(text, 22)
	_button("Back to paused adventure", "back")
	_focus()

func show_settings(settings: Dictionary) -> void:
	_clear("Settings & controls", "settings")
	_button("Controls", "controls")
	for setting in [["master", "Master volume", 0.0, 1.0, 0.1, 0.8], ["music", "Music volume", 0.0, 1.0, 0.05, 0.55], ["sfx", "Sound effects", 0.0, 1.0, 0.1, 0.8], ["text_scale", "Text size", 0.85, 2.0, 0.05, 1.0], ["mouse_sensitivity", "Mouse sensitivity", 0.0005, 0.006, 0.0005, 0.002], ["fov", "Field of view", 60.0, 105.0, 1.0, 80.0], ["controller_sensitivity", "Controller look sensitivity", 0.5, 4.0, 0.1, 2.0], ["controller_deadzone", "Controller stick dead zone", 0.05, 0.4, 0.05, 0.2]]:
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
		if key == "text_scale":
			var font_button := _button("", "plain_font")
			font_button.set_meta("setting_key", "plain_font")
			font_button.toggle_mode = true
			font_button.set_pressed_no_signal(bool(settings.get("plain_font", false)))
			font_button.toggled.connect(_plain_font_changed.bind(font_button))
			font_button.text = "Font: Plain (Atkinson Hyperlegible)" if font_button.button_pressed else "Font: Default"
	var invert := Button.new()
	invert.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	reduced.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reduced.toggle_mode = true
	reduced.set_meta("setting_key", "reduced_motion")
	reduced.text = "Reduce camera movement"
	reduced.focus_mode = Control.FOCUS_ALL
	reduced.button_pressed = settings.get("reduced_motion", false)
	reduced.toggled.connect(_reduced_motion_changed)
	reduced.toggled.connect(_toggle_readout.bind(reduced, "Reduce camera movement"))
	_toggle_readout(reduced.button_pressed, reduced, "Reduce camera movement")
	column.add_child(reduced)
	var speech_wait := Button.new()
	speech_wait.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	speech_wait.toggle_mode = true
	speech_wait.set_meta("setting_key", "speech_waits_for_me")
	speech_wait.focus_mode = Control.FOCUS_ALL
	speech_wait.button_pressed = bool(settings.get("speech_waits_for_me", false))
	speech_wait.toggled.connect(func(value: bool): action_requested.emit("setting", {"key":"speech_waits_for_me", "value":value}))
	speech_wait.toggled.connect(_toggle_readout.bind(speech_wait, "Speech waits for me"))
	_toggle_readout(speech_wait.button_pressed, speech_wait, "Speech waits for me")
	column.add_child(speech_wait)
	_button("Done", "back")
	_focus()

func show_controls() -> void:
	var parent_page := return_page
	_clear("Controls", "controls")
	return_page = parent_page
	menu_scroll.hide()
	controls_menu = CONTROLS_MENU.new()
	controls_menu.ui = self
	panel.get_child(0).add_child(controls_menu)

func _setting_changed(value: float, key: String) -> void:
	action_requested.emit("setting", {"key": key, "value": value})

func _plain_font_changed(value: bool, button: Button) -> void:
	button.text = "Font: Plain (Atkinson Hyperlegible)" if value else "Font: Default"
	action_requested.emit("setting", {"key":"plain_font", "value":value})

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
	_label("Development release %s" % str(ProjectSettings.get_setting("application/config/version", "")), 18)
	_label("3D adaptation · PilferedParrot\nOriginal Dink Smallwood · Seth A. Robinson\nArtwork · Justin Martin\nStory & world · Seth A. Robinson, Greg Smith, Justin Martin\nAdditional levels · Chris Bakker\nv1.08 fixes · Talmadge Bradley III\nFree audio · GNU FreeDink contributors\nEngine · Godot contributors\nOptional plain font · Atkinson Hyperlegible, Braille Institute (SIL OFL 1.1)", 20)
	_label("New code: Apache 2.0. Original art, story and audio retain their own licenses. Detailed attributions are bundled in licenses/. This is an unofficial, modified adaptation.", 18)
	_button("Support PilferedParrot on Patreon ↗", "patreon")
	_button("Source code & full credits ↗", "source")
	_button("Done", "back")
	_focus()
