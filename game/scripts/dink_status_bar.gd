# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
extends Control
## A compact HUD dock built around the original 640x80 Dink status artwork.
## Dynamic copy uses Godot's fallback font because the original data ships no font.

const STATUS_ART := preload("res://assets/graphics/inter/status/stat-03.png")
const ITEM_ROOT := "res://assets/graphics/inter/Menu/"
const STATUS_HEIGHT := 80.0
const CONTROL_HEIGHT := 196.0
const MIN_DOCK_WIDTH := 900.0
const MAX_DOCK_WIDTH := 1120.0
const ART_HEALTH_RECT := Rect2(303, 29, 241, 12)
const ICON_WEAPON_RECT := Rect2(147, 10, 63, 55)
const ICON_SPELL_RECT := Rect2(550, 10, 63, 55)
const COLOR_TEXT := Color("f1d99a")
const COLOR_SHADOW := Color(0.025, 0.025, 0.025, 0.94)
const COLOR_HEALTH_BG := Color(0.08, 0.055, 0.045, 0.92)
const COLOR_HEALTH := Color("a94f42")
const COLOR_TAG_BG := Color(0.025, 0.035, 0.04, 0.9)

var _text_scale := 1.0
var _stats: Dictionary = {}
var _sequence_frames: Dictionary = {}
var _weapon_texture: Texture2D
var _spell_texture: Texture2D
var _dock_width := MIN_DOCK_WIDTH
var _dock_scale := 1.0
var _dock_y := 0.0
var _icon_cache: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	offset_left = 0.0
	offset_right = 0.0
	offset_top = -CONTROL_HEIGHT
	offset_bottom = 0.0
	_load_sequences()
	_layout_dock()
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_dock()
		queue_redraw()

func _load_sequences() -> void:
	var file := FileAccess.open("res://data/sequences.json", FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_sequence_frames = parsed.get("sequences", parsed)

func _layout_dock() -> void:
	var viewport_width := get_viewport_rect().size.x
	var desired_width := clampf(viewport_width * 0.583333, MIN_DOCK_WIDTH, MAX_DOCK_WIDTH)
	_dock_width = minf(viewport_width, maxf(240.0, desired_width))
	_dock_scale = _dock_width / 640.0
	var dock_height := STATUS_HEIGHT * _dock_scale
	_dock_y = CONTROL_HEIGHT - dock_height

func update_stats(stats: Dictionary) -> void:
	_stats = stats.duplicate(true)
	_weapon_texture = _texture_for_item(_stats.get("weapon_item", {}), false)
	_spell_texture = _texture_for_item(_stats.get("spell_item", {}), true)
	queue_redraw()

func set_text_scale(value: float) -> void:
	_text_scale = clampf(value, 0.75, 1.8)
	queue_redraw()

func item_texture(item: Dictionary) -> Texture2D:
	return _texture_for_item(item, str(item.get("script", "")) in ["item-fb", "item-acd", "item-ice", "item-hel"])

func _texture_for_item(value: Variant, is_spell: bool) -> Texture2D:
	if not value is Dictionary:
		return null
	var item: Dictionary = value
	var script_name := str(item.get("script", "")).to_lower()
	var path := ""
	var sequence := int(item.get("seq", -1))
	var frame_number := int(item.get("frame", 1))
	if sequence == 0 and not is_spell and script_name == "item-b1":
		# The opening bow is represented by seq 0 in the campaign data.
		# Original S2-OUT.c / S3-ST2P.c grant item-b1 with seq 438, frame 8.
		path = ITEM_ROOT + "item-w08.png"
	elif sequence >= 0:
		var sequence_data: Variant = _sequence_frames.get(str(sequence), {})
		if sequence_data is Dictionary:
			var frames: Array = sequence_data.get("frames", [])
			if not frames.is_empty():
				var frame_index := clampi(frame_number - 1, 0, frames.size() - 1)
				var frame_data: Variant = frames[frame_index]
				if frame_data is Dictionary:
					var source_path := str(frame_data.get("path", ""))
					if source_path.begins_with("assets/graphics/inter/Menu/"):
						path = "res://" + source_path
	# Some story items have world animation sequences rather than menu icons.
	# Resolve common script-named icons where the sequence does not point at one.
	if path.is_empty():
		path = _script_icon(script_name, is_spell)
	if path.is_empty():
		return null
	if not _icon_cache.has(path):
		_icon_cache[path] = load(path) as Texture2D
	return _icon_cache[path] as Texture2D

func _script_icon(script_name: String, is_spell: bool) -> String:
	if is_spell:
		var spell_icons := {
			"item-fb": "item-m01.png", "item-sfb": "item-m02.png",
			"item-ice": "item-m05.png",
		}
		return ITEM_ROOT + str(spell_icons.get(script_name, "")) if spell_icons.has(script_name) else ""
	var weapon_icons := {
		"item-fst": "item-w01.png", "item-sw1": "item-w07.png",
		"item-sw2": "item-w20.png", "item-sw3": "item-w21.png",
		"item-b1": "item-w08.png", "item-b2": "item-w12.png",
		"item-b3": "item-w13.png", "item-axe": "item-w06.png",
		"item-pig": "item-w02.png", "item-nut": "item-w19.png",
		"item-bom": "item-w03.png", "item-bt": "item-w22.png",
		"item-eli": "item-w09.png", "item-p1": "item-w14.png",
	}
	return ITEM_ROOT + str(weapon_icons.get(script_name, "")) if weapon_icons.has(script_name) else ""

func _draw() -> void:
	var x := (size.x - _dock_width) * 0.5
	var scale_factor := _dock_scale
	var art_rect := Rect2(x, _dock_y, _dock_width, STATUS_HEIGHT * scale_factor)
	draw_texture_rect(STATUS_ART, art_rect, false)
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var font_scale := scale_factor * _text_scale
	var fs := maxi(10, roundi(12.0 * font_scale))
	var number_fs := maxi(10, roundi(13.0 * font_scale))
	var shadow_offset := Vector2(1.0, 1.0) * maxf(1.0, font_scale)

	# The original labels are part of stat-03. Only the changing values are drawn.
	_draw_text(font, str(int(_stats.get("strength", 0))), x + 79 * scale_factor, _dock_y + 18 * scale_factor, number_fs, COLOR_TEXT, shadow_offset)
	_draw_text(font, str(int(_stats.get("defense", 0))), x + 79 * scale_factor, _dock_y + 40 * scale_factor, number_fs, COLOR_TEXT, shadow_offset)
	_draw_text(font, str(int(_stats.get("magic", 0))), x + 79 * scale_factor, _dock_y + 62 * scale_factor, number_fs, COLOR_TEXT, shadow_offset)

	var life_max := maxi(1, int(_stats.get("lifemax", 10)))
	var life := clampi(int(_stats.get("life", 10)), 0, life_max)
	var health_rect := Rect2(Vector2(x, _dock_y) + ART_HEALTH_RECT.position * scale_factor, ART_HEALTH_RECT.size * scale_factor)
	draw_rect(health_rect, COLOR_HEALTH_BG)
	var health_fill := Rect2(health_rect.position, Vector2(health_rect.size.x * float(life) / float(life_max), health_rect.size.y))
	if health_fill.size.x > 0:
		draw_rect(health_fill, COLOR_HEALTH)
	_draw_text(font, "%d / %d" % [life, life_max], x + 320 * scale_factor, _dock_y + 22 * scale_factor, fs, COLOR_TEXT, shadow_offset)
	_draw_text(font, str(int(_stats.get("gold", 0))), x + 320 * scale_factor, _dock_y + 67 * scale_factor, fs, COLOR_TEXT, shadow_offset)

	var level := maxi(1, int(_stats.get("level", 1)))
	var exp_value := maxi(0, int(_stats.get("exp", 0)))
	var exp_target := mini(99999, 100 * level * level)
	_draw_tag(font, "Level %d  ·  EXP %d / %d" % [level, exp_value, exp_target], x + 365 * scale_factor, _dock_y - 8 * scale_factor, fs, scale_factor)

	_draw_item_icon(_weapon_texture, x, ICON_WEAPON_RECT, scale_factor)
	_draw_item_icon(_spell_texture, x, ICON_SPELL_RECT, scale_factor)
	_draw_tag(font, _item_label(_stats.get("weapon_item", {}), "weapon"), x + 178.5 * scale_factor, _dock_y - 8 * scale_factor, fs, scale_factor)
	_draw_tag(font, _spell_label(), x + 581.5 * scale_factor, _dock_y - 8 * scale_factor, fs, scale_factor)

func _draw_item_icon(texture: Texture2D, origin_x: float, source_rect: Rect2, scale_factor: float) -> void:
	if texture == null:
		return
	var target := Rect2(Vector2(origin_x, _dock_y) + source_rect.position * scale_factor, source_rect.size * scale_factor)
	draw_texture_rect(texture, target, false)

func _item_label(value: Variant, default_kind: String) -> String:
	if value is Dictionary and not str(value.get("name", "")).strip_edges().is_empty():
		return str(value.get("name", ""))
	if value is Dictionary and not str(value.get("script", "")).is_empty():
		return str(value.get("script", "")).trim_prefix("item-").capitalize()
	return "No weapon" if default_kind == "weapon" else "No spell"

func _spell_label() -> String:
	var spell: Variant = _stats.get("spell_item", {})
	if not spell is Dictionary or str(spell.get("script", "")).is_empty():
		return "No spell"
	var cost := maxi(0, int(_stats.get("magic_cost", 0)))
	if cost <= 0:
		return _item_label(spell, "spell") + "  ·  Recharging"
	var magic_level := clampi(int(_stats.get("magic_level", 0)), 0, cost)
	if magic_level < cost:
		return _item_label(spell, "spell") + "  ·  Recharging %d%%" % roundi(100.0 * float(magic_level) / float(cost))
	return _item_label(spell, "spell") + "  ·  Ready"

func _draw_tag(font: Font, label: String, center_x: float, baseline_y: float, font_size: int, scale_factor: float) -> void:
	var text_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var pad := 7.0 * scale_factor
	var width := minf(text_width + pad * 2.0, 174.0 * scale_factor)
	var height := 20.0 * scale_factor
	var tag_rect := Rect2(center_x - width * 0.5, baseline_y - height, width, height)
	draw_rect(tag_rect, COLOR_TAG_BG)
	var shown := label
	while font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width - pad * 2.0 and shown.length() > 4:
		shown = shown.left(shown.length() - 2) + "…"
	var text_x := center_x - font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x * 0.5
	_draw_text(font, shown, text_x, baseline_y - 5.0 * scale_factor, font_size, COLOR_TEXT, Vector2.ONE * maxf(1.0, scale_factor))

func _draw_text(font: Font, text: String, x: float, baseline: float, font_size: int, color: Color, shadow_offset: Vector2) -> void:
	draw_string(font, Vector2(x + shadow_offset.x, baseline + shadow_offset.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, COLOR_SHADOW)
	draw_string(font, Vector2(x, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
