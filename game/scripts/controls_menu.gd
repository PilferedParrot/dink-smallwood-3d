# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
# Native Controls page. Input identity, validation and persistence belong to P3a.
extends VBoxContainer

const CAPTURE_SECONDS := 15.0
# The existing countdown advances in whole seconds. A cancel hold is one tick.
const COUNTDOWN_TICK_SECONDS := 1.0
const CANCEL_HOLD_SECONDS := COUNTDOWN_TICK_SECONDS
const DETAIL_FONT_SIZE := 18 # Existing Settings detail text size.
const GROUPS := {"2d":"Walking", "fps":"First person", "menu":"Menus", "global":"Always"}
var ui
var bindings
var scope := "fps"
var state := "list"
var action := ""
var slot := -1
var record: Dictionary = {}
var operation := "replace"
var tabs: HFlowContainer
var scroll: ScrollContainer
var body: VBoxContainer
var footer: HFlowContainer
var countdown: Label
var cancel_button: Button
var buttons: Dictionary = {}
var axis_levels: Dictionary = {}
var blocked_axes: Dictionary = {}
var capture_deadline := 0
var layout_serial := 0
var restore_token := ""
var pending_modifier: Dictionary = {}
var cancel_pressed_msec := -1
var pending_cancel: Dictionary = {}
var intro: Label
var rows: Array[Control] = []
var snapping_scroll := false
var previous_scroll := 0.0

func _ready() -> void:
	bindings = ui.bindings
	scope = bindings.context
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", ui.column.get_theme_constant("separation"))
	ui.heading.add_theme_font_size_override("font_size",ui.menu_theme.default_font_size)
	intro = _label("Pad buttons are named as on an Xbox controller",self)
	intro.add_theme_font_size_override("font_size",roundi(DETAIL_FONT_SIZE*ui.text_scale))
	tabs = HFlowContainer.new()
	add_child(tabs)
	for area in GROUPS:
		var tab := _button(GROUPS[area], "group_"+area, tabs)
		_compact_button(tab)
		tab.toggle_mode = true
		# Selection stays visible without relying on the gold text colour.
		var selected: StyleBoxFlat = ui.menu_theme.get_stylebox("focus","Button").duplicate()
		selected.set_border_width_all(0)
		selected.border_width_bottom = ui.menu_theme.get_stylebox("focus","Button").border_width_bottom
		for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
			selected.set_content_margin(side,ui.menu_theme.get_stylebox("normal","Button").get_content_margin(side))
		tab.add_theme_stylebox_override("pressed",selected)
		tab.pressed.connect(_select_group.bind(area))
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ui._focus_scroll_owner(scroll)
	add_child(scroll)
	scroll.get_v_scroll_bar().value_changed.connect(_snap_scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",ui.column.get_theme_constant("separation"))
	scroll.add_child(body)
	footer = HFlowContainer.new()
	add_child(footer)
	_build_list()

func _button(text: String, token: String, parent: Node) -> Button:
	var button := Button.new()
	button.text = text
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size.y = 0 # Native font/style minima respect text size.
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.set_meta("controls_token", token)
	parent.add_child(button)
	var text_width := button.get_theme_font("font").get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,button.get_theme_font_size("font_size")).x
	var insets := button.get_theme_stylebox("normal").get_minimum_size().x
	button.custom_minimum_size.x = minf(text_width+insets,ui.root.size.x*0.5)
	buttons[token] = button
	return button

func _compact_button(button: Button) -> void:
	button.add_theme_font_size_override("font_size",roundi(DETAIL_FONT_SIZE*ui.text_scale))
	var width := button.get_theme_font("font").get_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,-1,button.get_theme_font_size("font_size")).x
	button.custom_minimum_size.x = width+button.get_theme_stylebox("normal").get_minimum_size().x

func _label(text: String, parent: Node = null, gold := false) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if gold: label.add_theme_color_override("font_color", ui.GOLD)
	(body if parent == null else parent).add_child(label)
	return label

func _clear_body() -> void:
	layout_serial += 1
	for parent in [body, footer]:
		for child in parent.get_children():
			parent.remove_child(child)
			child.queue_free()
	for token in buttons.keys():
		if not token.begins_with("group_"): buttons.erase(token)
	countdown = null
	cancel_button = null
	cancel_pressed_msec = -1
	pending_cancel = {}
	rows.clear()
	tabs.visible = state == "list"
	intro.visible = state == "list"
	# The list owns every pixel between the tabs and the footer; prompts size to content.
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL if state == "list" else Control.SIZE_FILL
	scroll.custom_minimum_size.y = 0
	ui._focus_scroll_owner(scroll).request_reset(ui.page_serial, true)
	previous_scroll = 0
	if state == "list": ui._layout_for("controls")

func _select_group(area: String) -> void:
	scope = area
	restore_token = ""
	_build_list()

func _event_name(value: Dictionary) -> String:
	var text: String = bindings.event_label(value)
	return "Pad " + text if value.type in ["pad","axis"] and not text.begins_with("Pad ") else text

func _reserved_reason(id: String) -> String:
	var key_name: String = bindings.label(id,false,"global" if id == "escape" else "fps")
	return "%s always goes back and pauses the game." % key_name if id == "escape" else "%s is reserved for local bug reports." % key_name

func _build_list() -> void:
	state = "list"
	_clear_body()
	for area in GROUPS:
		buttons["group_"+area].set_pressed_no_signal(area == scope)
		buttons["group_"+area].add_theme_color_override("font_pressed_color", ui.GOLD)
	# Combat first; all registry actions remain visible in their own context.
	var ids: Array = ["attack", "magic", "talk"]
	for id in bindings.actions:
		if not ids.has(id): ids.append(id)
	var first := ""
	for id in ids:
		var entry: Dictionary = bindings.actions[id]
		if not entry.contexts.has(scope): continue
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		body.add_child(row)
		rows.append(row)
		var title := HBoxContainer.new()
		row.add_child(title)
		_label(entry.name, title, true)
		if not entry.reserved:
			var reset := _button("Reset…", id+"_reset", title)
			_compact_button(reset)
			reset.size_flags_horizontal = Control.SIZE_SHRINK_END
			reset.pressed.connect(_ask_reset.bind(id))
		var slots := HFlowContainer.new()
		slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(slots)
		var events: Array = bindings.events(id,scope)
		for index in events.size():
			var token: String = id+"_"+str(index)
			var text := _event_name(events[index])
			var button := _button(text, token, slots)
			button.disabled = entry.reserved
			if not entry.reserved:
				button.pressed.connect(_capture.bind(id,index))
				if first.is_empty(): first = token
		if not entry.reserved:
			var add := _button("Add", id+"_add", slots)
			add.pressed.connect(_capture.bind(id,-1))
			if first.is_empty(): first = id+"_add"
		else:
			_label("Always available for going back and pausing." if id == "escape" else _reserved_reason(id), row)
	_button("Back", "back", footer).pressed.connect(ui.request_back)
	_button("Reset all…", "reset_all", footer).pressed.connect(_ask_reset.bind(""))
	_focus_later(restore_token if buttons.has(restore_token) else first, layout_serial)

func _focus_later(token: String, serial: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if serial != layout_serial or not is_inside_tree(): return
	if buttons.has(token) and is_instance_valid(buttons[token]):
		buttons[token].grab_focus()
		# The UI focus signal owns post-sort visibility for every scroller.

func _capture(id: String, index: int) -> void:
	action = id
	slot = index
	operation = "add" if slot < 0 else "replace"
	restore_token = id+"_"+str(index) if index >= 0 else id+"_add"
	state = "capture"
	_clear_body()
	_label(GROUPS[scope] + " · " + bindings.actions[action].name, body, true)
	_label("Press a key, mouse button or pad input. Review it before saving.")
	countdown = _label("")
	capture_deadline = Time.get_ticks_msec() + roundi(CAPTURE_SECONDS * 1000)
	pending_modifier = {}
	blocked_axes = axis_levels.duplicate()
	for device in Input.get_connected_joypads():
		for axis in range(10):
			if absf(Input.get_joy_axis(device,axis)) > 0.5: blocked_axes[str(device)+":"+str(axis)] = 1.0
	cancel_button = _button("Cancel", "cancel", footer)
	cancel_button.focus_mode = Control.FOCUS_NONE
	cancel_button.pressed.connect(_build_list)
	if slot >= 0:
		var remove := _button("Remove binding", "remove", footer)
		remove.focus_mode = Control.FOCUS_NONE
		remove.pressed.connect(_ask_remove)
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null: focus.release_focus()

func _process(_delta: float) -> void:
	if state == "list": return
	_fit_prompt()
	if state != "capture": return
	if cancel_pressed_msec >= 0 and Time.get_ticks_msec()-cancel_pressed_msec >= roundi(CANCEL_HOLD_SECONDS*1000):
		_build_list()
		return
	var seconds := maxi(0, ceili(float(capture_deadline-Time.get_ticks_msec())/1000.0))
	countdown.text = "%s or hold %s to cancel · %d s remaining" % [bindings.label("escape",false,"global"),bindings.label("ui_cancel",true,"menu"),seconds]
	if seconds == 0: _build_list()

func _snap_scroll(value: float) -> void:
	if state != "list" or snapping_scroll or rows.is_empty() or ui._focus_scroll_owner(scroll).automatic_active(): return
	var index := 0
	for i in rows.size():
		if rows[i].position.y <= value: index = i
	var target: float = rows[index].position.y
	if rows[index].size.y > scroll.size.y:
		# A large user-created action keeps native within-row scrolling.
		target = value
	elif value > previous_scroll and value > target and index+1 < rows.size():
		target = rows[index+1].position.y
	snapping_scroll = true
	ui._focus_scroll_owner(scroll).set_position(target, true, false)
	previous_scroll = scroll.scroll_vertical
	snapping_scroll = false

func _fit_prompt() -> void:
	var chrome: float = ui.panel.get_combined_minimum_size().y-scroll.get_combined_minimum_size().y
	var maximum: float = ui.root.size.y*(0.90-0.07)
	scroll.custom_minimum_size.y = minf(body.get_combined_minimum_size().y,maxf(0,maximum-chrome))
	ui.panel.anchor_bottom = ui.panel.anchor_top
	ui.panel.offset_bottom = chrome+scroll.custom_minimum_size.y
	ui.panel.size.y = chrome+scroll.custom_minimum_size.y

func _input(event: InputEvent) -> void:
	var axis_token := ""
	if event is InputEventJoypadMotion:
		axis_token = str(event.device)+":"+str(event.axis)
		if absf(event.axis_value) <= 0.25:
			axis_levels.erase(axis_token)
			blocked_axes.erase(axis_token)
		else: axis_levels[axis_token] = event.axis_value
	if event.is_action_pressed("escape") and state != "list":
		_build_list()
		get_viewport().set_input_as_handled()
		return
	if state != "capture":
		if state != "list" and event.is_action_pressed("ui_cancel"):
			_build_list()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion: return
	if not axis_token.is_empty() and blocked_axes.has(axis_token):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if event.is_action_pressed("ui_cancel"):
			if cancel_pressed_msec < 0:
				cancel_pressed_msec = Time.get_ticks_msec()
				pending_cancel = bindings.from_event(event)
			get_viewport().set_input_as_handled()
			return
		if cancel_pressed_msec >= 0 and event.is_action_released("ui_cancel"):
			get_viewport().set_input_as_handled()
			record = pending_cancel
			cancel_pressed_msec = -1
			if not record.is_empty(): _propose()
			return
	if event is InputEventMouseButton:
		# Native pointer activation is still available on Cancel/Remove.
		for button in footer.get_children():
			var local: InputEventMouseButton = button.make_input_local(event)
			if Rect2(Vector2.ZERO,button.size).has_point(local.position): return
	get_viewport().set_input_as_handled()
	if event.is_echo(): return
	var captured: Dictionary = bindings.from_event(event)
	if captured.is_empty(): return
	if bindings.is_modifier(captured):
		if event.is_pressed():
			pending_modifier = captured
			return
		if pending_modifier.is_empty(): return
		captured = pending_modifier
	elif not event is InputEventJoypadMotion and not event.is_pressed(): return
	record = captured
	_propose()

func _propose() -> void:
	state = "proposal"
	_clear_body()
	var candidate: Array = bindings.events(action,scope)
	var old_name := _event_name(candidate[slot]) if slot >= 0 else ""
	if slot < 0: candidate.append(record)
	else: candidate[slot] = record
	var clashes: Array = bindings.conflicts(action,candidate,scope)
	var name := _event_name(record)
	_label(GROUPS[scope] + " · " + bindings.actions[action].name, body, true)
	_label("%s will replace %s." % [name,old_name] if slot >= 0 else "Add %s as another binding." % name)
	if clashes.has("escape") or clashes.has("bug_report"):
		_label(_reserved_reason("escape" if clashes.has("escape") else "bug_report"))
		_button("Try another input", "retry", footer).pressed.connect(_capture.bind(action,slot))
	elif not clashes.is_empty():
		var names: Array[String] = []
		for id in clashes: names.append(bindings.actions[id].name)
		var can_swap: bool = slot >= 0 and clashes.size() == 1 and bindings.actions[clashes[0]].contexts.has(scope)
		_label("Already used by " + ", ".join(names) + (". Swap will move %s to that action." % old_name if can_swap else ". Choose a different input, or change that action first."))
		if can_swap:
			_button("Swap", "swap", footer).pressed.connect(_save.bind("swap"))
		else:
			_button("Try another input", "retry", footer).pressed.connect(_capture.bind(action,slot))
	else:
		_label("Save this binding?")
		_button("Bind", "bind", footer).pressed.connect(_save.bind("refuse"))
	if slot >= 0 and clashes.is_empty():
		_button("Remove binding", "remove", footer).pressed.connect(_ask_remove)
	_button("Cancel", "cancel", footer).pressed.connect(_build_list)
	_focus_later("swap" if buttons.has("swap") else ("bind" if buttons.has("bind") else "retry"), layout_serial)

func _save(policy: String) -> void:
	var result: Dictionary
	if operation == "remove": result = bindings.remove_binding(action,slot,scope)
	elif slot < 0: result = bindings.add_binding(action,record,policy,scope)
	else: result = bindings.replace_binding(action,slot,record,policy,scope)
	_finish(result)

func _ask_remove() -> void:
	state = "confirm"
	operation = "remove"
	_clear_body()
	_label("Remove this binding from " + bindings.actions[action].name + "?", body, true)
	_button("Remove", "confirm", footer).pressed.connect(_save.bind("refuse"))
	_button("Cancel", "cancel", footer).pressed.connect(_build_list)
	_focus_later("cancel", layout_serial)

func _ask_reset(id: String) -> void:
	action = id
	restore_token = "reset_all" if id.is_empty() else id+"_reset"
	state = "confirm"
	_clear_body()
	_label("Restore every action in every group?" if id.is_empty() else "Restore defaults for " + bindings.actions[id].name + "?", body, true)
	_label("Your custom bindings will be replaced.")
	_button("Reset all" if id.is_empty() else "Reset", "confirm", footer).pressed.connect(_reset.bind("refuse"))
	_button("Cancel", "cancel", footer).pressed.connect(_build_list)
	_focus_later("cancel", layout_serial)

func _reset(policy: String) -> void:
	var result: Dictionary = bindings.reset_all() if action.is_empty() else bindings.reset_action(action,policy,scope)
	if result.get("error","") == "conflict" and policy == "refuse":
		state = "reset_conflict"
		_clear_body()
		var names: Array[String] = []
		for id in result.get("conflicts",[]): names.append(bindings.actions[id].name)
		_label("Defaults clash with " + ", ".join(names) + ". Swap their bindings?",body,true)
		_button("Swap", "swap", footer).pressed.connect(_reset.bind("swap"))
		_button("Cancel", "cancel", footer).pressed.connect(_build_list)
		_focus_later("cancel",layout_serial)
	else: _finish(result)

func _finish(result: Dictionary) -> void:
	if result.get("ok",false):
		_build_list()
		return
	state = "error"
	_clear_body()
	_label("Binding unchanged", body, true)
	var error: String = result.get("error","")
	match error:
		"reserved": _label(_reserved_reason("escape") + " " + _reserved_reason("bug_report"))
		"write_failed": _label("Could not save settings. Your previous bindings are still in use.")
		"conflict": _label("These bindings cannot be swapped safely. Try another input, or reset all.")
		"menu_device_required":
			var affected: String = bindings.actions.get(result.get("action",action),{}).get("name","This menu action")
			_label(affected + " needs a keyboard binding and a pad binding, so you can always reach settings. Keep its last " + result.get("device","device") + " binding.")
		"invalid_index": _label("This binding has changed. Choose its current slot and try again.")
		_: _label("This input cannot be assigned. Choose another input.")
	_button("Back", "cancel", footer).pressed.connect(_build_list)
	_focus_later("cancel",layout_serial)

func back() -> bool:
	if state == "list": return false
	_build_list()
	return true
