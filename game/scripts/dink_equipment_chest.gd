# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
extends Control
## Focusable inventory laid out on the original 600x400 menu artwork.

signal selected(action: String, index: int)
signal highlighted(text: String)

const ART: Texture2D = preload("res://assets/graphics/inter/Menu/menu-01.png")
const ART_SIZE := Vector2(600, 400)
const SLOT_SIZE := Vector2(66, 59)
const MAGIC_X := [25.0, 108.0]
const ITEM_X := [240.0, 323.0, 406.0, 489.0]
const ROW_Y := [83.0, 158.0, 233.0, 308.0]
const GOLD := Color("ffdc79")
const CREAM := Color("f6ebcb")
const PAGE_HEIGHT := 440.0

var _items: Array = []
var _spells: Array = []
var _stats: Dictionary = {}
var _texture_lookup: Callable
var _text_scale := 1.0
var _spell_page := 0
var _slot_buttons: Array[Button] = []
var _page_prev: Button
var _page_next: Button

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_rebuild()

func configure(items: Array, spells: Array, stats: Dictionary, texture_lookup: Callable, text_scale: float) -> void:
	_items = items.duplicate(true)
	_spells = spells.duplicate(true)
	_stats = stats.duplicate(true)
	_texture_lookup = texture_lookup
	_text_scale = clampf(text_scale, 0.75, 1.8)
	_spell_page = mini(_spell_page, maxi(0, (_spells.size() - 1) / 8))
	if is_node_ready():
		_rebuild()

func focus_first() -> void:
	if not is_node_ready():
		call_deferred("focus_first")
		return
	for button in _slot_buttons:
		if is_instance_valid(button):
			button.grab_focus()
			return
	if is_instance_valid(_page_next) and not _page_next.disabled:
		_page_next.grab_focus()

func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_slot_buttons.clear()
	_page_prev = null
	_page_next = null
	var has_extra_spells := _spells.size() > 8
	custom_minimum_size = Vector2(ART_SIZE.x, PAGE_HEIGHT if has_extra_spells else ART_SIZE.y)
	for index in range(mini(_spells.size() - _spell_page * 8, 8)):
		var real_index := _spell_page * 8 + index
		var value: Variant = _spells[real_index]
		if _has_item(value):
			_add_slot(value, "equip_magic", real_index, index % 2, int(index / 2), true)
	for index in range(mini(_items.size(), 16)):
		var value: Variant = _items[index]
		if _has_item(value):
			_add_slot(value, "equip", index, index % 4 + 2, int(index / 4), false)
	if has_extra_spells:
		_page_prev = _make_page_button("◀ Prev", Vector2(25, 405), _spell_page > 0, -1)
		_page_next = _make_page_button("Next ▶", Vector2(108, 405), (_spell_page + 1) * 8 < _spells.size(), 1)
	_set_focus_neighbors()
	queue_redraw()

func _add_slot(item: Dictionary, action: String, index: int, col: int, row: int, spell: bool) -> void:
	var x: float = MAGIC_X[col] if spell else ITEM_X[col - 2]
	var rect := Rect2(Vector2(x, ROW_Y[row]), SLOT_SIZE)
	var equipped := int(_stats.get("cur_magic" if spell else "cur_weapon", 0)) == index + 1
	var name := _item_name(item)
	var description := _item_description(item, name, spell, equipped)
	var button := Button.new()
	button.name = ("Magic" if spell else "Item") + str(index)
	button.position = rect.position
	button.size = rect.size
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.tooltip_text = description
	button.set_meta("grid", Vector2i(col, row))
	button.set_meta("spell", spell)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button.pressed.connect(func() -> void: selected.emit(action, index))
	button.focus_entered.connect(func() -> void:
		button.queue_redraw()
		highlighted.emit(description)
	)
	button.focus_exited.connect(func() -> void: button.queue_redraw())
	button.mouse_entered.connect(func() -> void: highlighted.emit(description))
	button.draw.connect(_draw_slot_border.bind(button, equipped))
	add_child(button)
	_slot_buttons.append(button)

	var icon := TextureRect.new()
	icon.position = Vector2(5, 3)
	icon.size = Vector2(56, 34)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _texture_lookup.is_valid():
		var result: Variant = _texture_lookup.call(item)
		if result is Texture2D:
			icon.texture = result
	button.add_child(icon)

	var caption := Label.new()
	caption.position = Vector2(3, 37)
	caption.size = Vector2(60, 22)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.clip_text = true
	var caption_size := roundi(16.0 * _text_scale)
	caption.text = _slot_caption(name, caption_size)
	caption.add_theme_font_size_override("font_size", caption_size)
	caption.add_theme_color_override("font_color", CREAM)
	caption.add_theme_color_override("font_shadow_color", Color.BLACK)
	caption.add_theme_constant_override("shadow_offset_x", 1)
	caption.add_theme_constant_override("shadow_offset_y", 1)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(caption)
	if equipped:
		var marker := Label.new()
		marker.text = "E"
		marker.position = Vector2(51, 0)
		marker.size = Vector2(13, 15)
		marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		marker.add_theme_font_size_override("font_size", 16)
		marker.add_theme_color_override("font_color", GOLD)
		marker.add_theme_color_override("font_shadow_color", Color.BLACK)
		marker.add_theme_constant_override("shadow_offset_x", 1)
		marker.add_theme_constant_override("shadow_offset_y", 1)
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(marker)

func _draw_slot_border(button: Button, equipped: bool) -> void:
	var border := Rect2(Vector2(1, 1), button.size - Vector2(2, 2))
	if button.has_focus():
		button.draw_rect(border, GOLD, false, 4.0)
		button.draw_rect(border.grow(-5), Color("fff4bd"), false, 1.0)
	elif equipped:
		button.draw_rect(border.grow(-1), Color("b89244"), false, 2.0)

func _make_page_button(label: String, at: Vector2, enabled: bool, delta: int) -> Button:
	var button := Button.new()
	button.text = label
	button.position = at
	button.size = Vector2(68, 30)
	button.focus_mode = Control.FOCUS_ALL
	button.disabled = not enabled
	button.tooltip_text = "Show %s magic slots" % ("previous" if delta < 0 else "next")
	button.add_theme_font_size_override("font_size", roundi(12.0 * _text_scale))
	button.add_theme_color_override("font_color", CREAM)
	button.add_theme_color_override("font_focus_color", GOLD)
	button.add_theme_color_override("font_disabled_color", Color("8b806d"))
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("34261c")
		style.border_color = GOLD if state == "focus" else Color("806339")
		style.set_border_width_all(3 if state == "focus" else 1)
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(_turn_page.bind(delta))
	add_child(button)
	return button

func _turn_page(delta: int) -> void:
	_spell_page = clampi(_spell_page + delta, 0, maxi(0, (_spells.size() - 1) / 8))
	_rebuild()
	focus_first()

func _set_focus_neighbors() -> void:
	for button in _slot_buttons:
		var position: Vector2i = button.get_meta("grid")
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var best: Button
			var best_score := INF
			for candidate in _slot_buttons:
				if candidate == button:
					continue
				var offset: Vector2i = (candidate.get_meta("grid") as Vector2i) - position
				var forward: int = offset.x * direction.x + offset.y * direction.y
				if forward <= 0:
					continue
				var sideways := absi(offset.y) if direction.x != 0 else absi(offset.x)
				var score := float(sideways * 10 + forward)
				if score < best_score:
					best_score = score
					best = candidate
			if best != null:
				var path := button.get_path_to(best)
				if direction == Vector2i.LEFT: button.focus_neighbor_left = path
				elif direction == Vector2i.RIGHT: button.focus_neighbor_right = path
				elif direction == Vector2i.UP: button.focus_neighbor_top = path
				else: button.focus_neighbor_bottom = path
	if _spells.size() > 8:
		var pager := _page_prev if _spell_page > 0 else _page_next
		if is_instance_valid(pager) and not pager.disabled:
			for button in _slot_buttons:
				if not bool(button.get_meta("spell")):
					continue
				var grid: Vector2i = button.get_meta("grid")
				var has_spell_below := false
				for other in _slot_buttons:
					var other_grid: Vector2i = other.get_meta("grid")
					if bool(other.get_meta("spell")) and other_grid.x == grid.x and other_grid.y > grid.y:
						has_spell_below = true
				if not has_spell_below:
					button.focus_neighbor_bottom = button.get_path_to(pager)
			var last_spell: Button
			for button in _slot_buttons:
				if bool(button.get_meta("spell")):
					last_spell = button
			if last_spell != null:
				pager.focus_neighbor_top = pager.get_path_to(last_spell)

func _item_name(item: Dictionary) -> String:
	var name := str(item.get("name", "")).strip_edges()
	if not name.is_empty():
		return name
	return str(item.get("script", "Item")).trim_prefix("item-").replace("-", " ").capitalize()

func _slot_caption(name: String, font_size: int) -> String:
	var font := ThemeDB.fallback_font
	if font == null:
		return name
	var shown := name
	while shown.length() > 1 and font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > 58.0:
		shown = shown.left(shown.length() - 1)
	if shown != name:
		while shown.length() > 1 and font.get_string_size(shown + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > 58.0:
			shown = shown.left(shown.length() - 1)
		shown += "…"
	return shown

func _has_item(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var item: Dictionary = value
	return not str(item.get("script", "")).strip_edges().is_empty() or not str(item.get("name", "")).strip_edges().is_empty()

func _item_description(item: Dictionary, name: String, spell: bool, equipped: bool) -> String:
	var result := ("Magic: " if spell else "Item: ") + name
	if equipped:
		result += " · Equipped"
	var detail := str(item.get("description", item.get("desc", ""))).strip_edges()
	if not detail.is_empty():
		result += "\n" + detail
	return result

func _draw() -> void:
	draw_texture_rect(ART, Rect2(Vector2.ZERO, ART_SIZE), false)
	if _spells.size() > 8:
		draw_rect(Rect2(0, 400, 600, 40), Color("261b13"))
		var font := ThemeDB.fallback_font
		if font != null:
			draw_string(font, Vector2(191, 425), "Magic %d / %d" % [_spell_page + 1, ceili(float(_spells.size()) / 8.0)], HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(13.0 * _text_scale), CREAM)
