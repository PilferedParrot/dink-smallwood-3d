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
# FreeDink status.cpp draws the 640x80 bar at screen y=400. These
# regions follow its digit/health origins; the lower-right inset is EXP.
const ART_STRENGTH_RECT := Rect2(81, 12, 53, 20)
const ART_DEFENSE_RECT := Rect2(81, 34, 53, 20)
const ART_MAGIC_RECT := Rect2(81, 56, 53, 20)
const ART_COINS_RECT := Rect2(298, 54, 99, 22)
const ART_EXP_RECT := Rect2(404, 54, 110, 22)
const ART_LEVEL_RECT := Rect2(517, 54, 30, 22)
const ART_HEALTH_RECT := Rect2(284, 12, 253, 17)
# Value line boxes include unused font ascent/descent; ink remains within the bar.
const ART_HEALTH_VALUE_RECT := Rect2(284, 9, 253, 23)
const ICON_WEAPON_RECT := Rect2(147, 10, 63, 55)
const ICON_SPELL_RECT := Rect2(550, 10, 63, 55)
# Live numbers on the original art. The text-size setting multiplies the size they
# are fitted to at 100%; when the art's rects cannot hold that, the optional
# readout above the art takes over. The floor is the smallest size ever drawn.
const MIN_VALUE_SIZE := 10
const COLOR_TEXT := Color("f1d99a")
const COLOR_HEALTH_BG := Color(0.08, 0.055, 0.045, 0.92)
const COLOR_HEALTH := Color("a94f42")

var _text_scale := 1.0
var _stats: Dictionary = {}
var _sequence_frames: Dictionary = {}
var _weapon_texture: Texture2D
var _spell_texture: Texture2D
var _dock_width := MIN_DOCK_WIDTH
var _dock_scale := 1.0
var _dock_y := 0.0
var _icon_cache: Dictionary = {}
var readout: PanelContainer
var readout_flow: HFlowContainer
var readout_labels: Dictionary = {}
var _drawn_sizes: Dictionary = {}
var _readout_cache := {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	offset_left = 0.0
	offset_right = 0.0
	offset_top = -CONTROL_HEIGHT
	offset_bottom = 0.0
	_load_sequences()
	readout = PanelContainer.new()
	readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var backing := StyleBoxFlat.new()
	backing.bg_color = Color("21180f")
	backing.border_color = Color("806339")
	backing.set_border_width_all(1)
	backing.content_margin_left = 6; backing.content_margin_right = 6
	backing.content_margin_top = 4; backing.content_margin_bottom = 4
	readout.add_theme_stylebox_override("panel", backing)
	add_child(readout)
	readout_flow = HFlowContainer.new()
	readout_flow.add_theme_constant_override("h_separation", 16)
	readout_flow.add_theme_constant_override("v_separation", 2)
	readout.add_child(readout_flow)
	for key in ["life", "strength", "defense", "magic", "gold", "exp", "level"]:
		var label := Label.new()
		label.add_theme_color_override("font_color", COLOR_TEXT)
		readout_flow.add_child(label)
		readout_labels[key] = label
	_layout_dock()
	_update_readout()
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_dock()
		queue_redraw()
	elif what == NOTIFICATION_THEME_CHANGED:
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

func art_rect() -> Rect2:
	# The Control reserves transparent space above the original 640x80 art.
	# Other UI owners must reserve the drawn artwork, not that padding.
	return Rect2((size.x - _dock_width) * 0.5, _dock_y, _dock_width, STATUS_HEIGHT * _dock_scale)

func readout_top() -> float:
	# All other UI reserves both the original artwork and this optional copy.
	return global_position.y + (readout.position.y if uses_readout() and is_instance_valid(readout) else _dock_y)

func _process(_delta: float) -> void:
	if not is_instance_valid(readout): return
	readout.visible = uses_readout()
	if not readout.visible: return
	var fs := roundi(15.0 * _dock_scale * _text_scale)
	for label in readout_labels.values(): label.add_theme_font_size_override("font_size", fs)
	readout.position.x = 12
	readout.size.x = maxf(1, size.x - 24)
	readout.size.y = readout.get_combined_minimum_size().y
	readout.position.y = _dock_y - readout.size.y - 6

func _display_stats() -> Dictionary:
	var values := _stats.duplicate()
	values.lifemax = maxi(1, int(_stats.get("lifemax", 10)))
	values.life = clampi(int(_stats.get("life", 10)), 0, values.lifemax)
	values.level = maxi(1, int(_stats.get("level", 1)))
	values.exp = maxi(0, int(_stats.get("exp", 0)))
	return values

func _update_readout() -> void:
	if not is_instance_valid(readout): return
	var values := _display_stats()
	readout_labels.life.text = "Life %d / %d" % [values.life, values.lifemax]
	for field in [["strength", "Attack"], ["defense", "Defense"], ["magic", "Magic"], ["gold", "Coins"], ["level", "Lv"]]:
		readout_labels[field[0]].text = "%s %d" % [field[1], int(values.get(field[0], 0))]
	readout_labels.exp.text = "EXP %d / %d" % [values.exp, mini(99999, 100 * values.level * values.level)]

func update_stats(stats: Dictionary) -> void:
	_stats = stats.duplicate(true)
	_weapon_texture = _texture_for_item(_stats.get("weapon_item", {}), false)
	_spell_texture = _texture_for_item(_stats.get("spell_item", {}), true)
	_update_readout()
	queue_redraw()

func set_text_scale(value: float) -> void:
	_text_scale = clampf(value, 0.85, 2.0)
	queue_redraw()

func set_context_hints_visible(_value: bool) -> void:
	# The game UI still calls this for control hints. Equipment appears in the
	# original icon slots, independent of whether those hints are visible.
	pass

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
	draw_texture_rect(STATUS_ART, art_rect(), false)
	var font := get_theme_font("font")
	if font == null:
		return
	var fs := 14.0
	var number_fs := 15.0
	var in_art := not uses_readout()
	_drawn_sizes.clear()

	# Keep the artwork's engraved labels visible. Fit the live digits to their
	# original regions at 100% and scale that fit with the text-size setting.
	if in_art:
		_draw_value("strength", font, str(int(_stats.get("strength", 0))), ART_STRENGTH_RECT, number_fs)
		_draw_value("defense", font, str(int(_stats.get("defense", 0))), ART_DEFENSE_RECT, number_fs)
		_draw_value("magic", font, str(int(_stats.get("magic", 0))), ART_MAGIC_RECT, number_fs)

	var values := _display_stats()
	var life_max: int = values.lifemax
	var life: int = values.life
	var health_rect := Rect2(Vector2(x, _dock_y) + ART_HEALTH_RECT.position * scale_factor, ART_HEALTH_RECT.size * scale_factor)
	draw_rect(health_rect, COLOR_HEALTH_BG)
	var health_fill := Rect2(health_rect.position, Vector2(health_rect.size.x * float(life) / float(life_max), health_rect.size.y))
	if health_fill.size.x > 0:
		draw_rect(health_fill, COLOR_HEALTH)
	if in_art:
		_draw_value("health", font, "%d / %d" % [life, life_max], ART_HEALTH_VALUE_RECT, fs, HORIZONTAL_ALIGNMENT_CENTER)
		_draw_value("gold", font, str(int(_stats.get("gold", 0))), ART_COINS_RECT, number_fs)

	var level: int = values.level
	var exp_value: int = values.exp
	var exp_target := mini(99999, 100 * level * level)
	if in_art:
		_draw_value("exp_label", font, "EXP", Rect2(404, 38, 110, 22), fs, HORIZONTAL_ALIGNMENT_CENTER)
		_draw_value("exp", font, "%d/%d" % [exp_value, exp_target], ART_EXP_RECT, fs, HORIZONTAL_ALIGNMENT_CENTER)
		_draw_value("level_label", font, "Lv", Rect2(517, 38, 30, 22), fs, HORIZONTAL_ALIGNMENT_CENTER)
		_draw_value("level", font, str(level), ART_LEVEL_RECT, number_fs, HORIZONTAL_ALIGNMENT_CENTER)

	_draw_item_icon(_weapon_texture, x, ICON_WEAPON_RECT, scale_factor)
	_draw_item_icon(_spell_texture, x, ICON_SPELL_RECT, scale_factor)

func _draw_item_icon(texture: Texture2D, origin_x: float, source_rect: Rect2, scale_factor: float) -> void:
	if texture == null:
		return
	var target := Rect2(Vector2(origin_x, _dock_y) + source_rect.position * scale_factor, source_rect.size * scale_factor)
	draw_texture_rect(texture, target, false)

# Widest values the HUD census exercises. They decide, once per font and size,
# whether the art's rects can hold the scaled numbers; a still wider value shrinks
# to its rect but is never drawn below MIN_VALUE_SIZE.
func _value_cases() -> Array:
	return [
		["strength", "999", ART_STRENGTH_RECT, 15.0], ["defense", "999", ART_DEFENSE_RECT, 15.0],
		["magic", "999", ART_MAGIC_RECT, 15.0], ["health", "999 / 999", ART_HEALTH_VALUE_RECT, 14.0],
		["gold", "999999", ART_COINS_RECT, 15.0], ["exp_label", "EXP", Rect2(404, 38, 110, 22), 14.0],
		["exp", "99999/99999", ART_EXP_RECT, 14.0], ["level_label", "Lv", Rect2(517, 38, 30, 22), 14.0],
		["level", "99", ART_LEVEL_RECT, 15.0],
	]

func _target(source_rect: Rect2) -> Rect2:
	return Rect2(Vector2((size.x - _dock_width) * 0.5, _dock_y) + source_rect.position * _dock_scale, source_rect.size * _dock_scale)

# Largest size not above `requested` whose text fits `target`; 0 when none reaches
# MIN_VALUE_SIZE. `line_box` fits the whole line (the 100% rule); otherwise only the
# ascent, because digits have no descenders.
func _fit(font: Font, text: String, target: Rect2, requested: int, line_box: bool) -> int:
	var outline := maxi(1, ceili(_dock_scale))
	var fitted := requested
	while fitted >= MIN_VALUE_SIZE:
		var height := font.get_height(fitted) if line_box else font.get_ascent(fitted)
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fitted).x + outline * 2 <= target.size.x and height + outline * 2 <= target.size.y: return fitted
		fitted -= 1
	return 0

func _scaled_size(font: Font, text: String, source_rect: Rect2, base_request: float) -> int:
	var target := _target(source_rect)
	var at_100 := _fit(font, text, target, maxi(MIN_VALUE_SIZE, roundi(base_request * _dock_scale)), true)
	if at_100 == 0: return 0
	var wanted := roundi(float(at_100) * _text_scale)
	return wanted if _fit(font, text, target, wanted, false) == wanted else 0

# True when the original rects cannot hold the numbers at the requested text size.
func uses_readout() -> bool:
	var font := get_theme_font("font")
	if font == null: return false
	var key := [font.get_instance_id(), _dock_scale, _text_scale]
	if _readout_cache.get("key") != key:
		var needed := false
		for value_case in _value_cases():
			if _scaled_size(font, value_case[1], value_case[2], value_case[3]) == 0: needed = true
		_readout_cache = {"key": key, "value": needed}
	return _readout_cache.value

# Sizes of the numbers drawn on the art in the last frame, by field.
func drawn_sizes() -> Dictionary:
	return _drawn_sizes.duplicate()

func _draw_value(field: String, font: Font, text: String, source_rect: Rect2, base_request: float, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var target := _target(source_rect)
	var outline := maxi(1, ceili(_dock_scale))
	var at_100 := _fit(font, text, target, maxi(MIN_VALUE_SIZE, roundi(base_request * _dock_scale)), true)
	var fitted_size := maxi(MIN_VALUE_SIZE, _fit(font, text, target, roundi(float(maxi(at_100, MIN_VALUE_SIZE)) * _text_scale), false))
	_drawn_sizes[field] = fitted_size
	var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fitted_size).x
	var text_x := target.position.x + outline
	if alignment == HORIZONTAL_ALIGNMENT_CENTER:
		text_x = target.get_center().x - text_width * 0.5
	var baseline := target.get_center().y + (font.get_ascent(fitted_size) - font.get_descent(fitted_size)) * 0.5
	var position := Vector2(text_x, baseline)
	# A complete outline separates every edge from the textured stone without
	# concealing any of the original artwork behind a rectangular value chip.
	draw_string_outline(font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fitted_size, outline, Color.BLACK)
	draw_string(font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fitted_size, COLOR_TEXT)
