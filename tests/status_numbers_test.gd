# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
extends SceneTree
## Rendered UI fixture, no campaign progression. The text-size setting must change the
## status numbers a player sees across its whole range, never below a stated minimum.
const UI = preload("res://scripts/game_ui.gd")
const BAR = preload("res://scripts/dink_status_bar.gd")
var MINIMUM: int = (BAR as Script).get_script_constant_map().get("MIN_VALUE_SIZE", 10)
const SCALES := [1.0, 1.05, 1.15, 1.3, 1.35, 1.5, 2.0]
var ui
var failures: Array[String] = []
var report: Array = []
var output_dir := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out-dir="): output_dir = arg.trim_prefix("--out-dir=")
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func draw_frames() -> void:
	for _i in 6: await process_frame
	await RenderingServer.frame_post_draw

# Independent of the bar's own bookkeeping: the pixels a player sees. Height of the
# count of numeral-coloured pixels inside the original STRENGTH rect (area grows with
# every pixel of font size, where a bounding box can stay equal across one step).
func ink_pixels(image: Image, target: Rect2) -> int:
	var count := 0
	for y in range(int(target.position.y), int(target.end.y) + 1):
		for x in range(int(target.position.x), int(target.end.x) + 1):
			var c := image.get_pixel(x, y)
			if absf(c.r - BAR.COLOR_TEXT.r) < 0.06 and absf(c.g - BAR.COLOR_TEXT.g) < 0.06 and absf(c.b - BAR.COLOR_TEXT.b) < 0.06:
				count += 1
	return count

func strength_rect() -> Rect2:
	var art: Rect2 = ui.status_dock.get_global_transform() * ui.status_dock.art_rect()
	var k := art.size.x / 640.0
	# The window stretches the logical canvas; read the rect where it is drawn.
	return root.get_final_transform() * Rect2(art.position + BAR.ART_STRENGTH_RECT.position * k, BAR.ART_STRENGTH_RECT.size * k)

func run() -> void:
	ui = UI.new()
	root.add_child(ui)
	for size in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		root.size = size
		for _i in 20: await process_frame
		for plain in [false, true]:
			ui.set_plain_font(plain)
			var inks: Array = []
			var previous_size := 0
			var previous_readout := false
			for scale in SCALES:
				ui.set_text_scale(scale)
				ui.close_menu()
				ui.show_hud({"life": 12, "lifemax": 20, "strength": 888, "defense": 888, "magic": 888, "gold": 999999, "exp": 99999, "level": 99, "location": "Stonebrook"})
				await draw_frames()
				var tag := "%s plain=%s scale=%.2f" % [size, plain, scale]
				var dock = ui.status_dock
				# The pixel checks below need no API from the bar, so this also runs on older trees.
				var has_api: bool = dock.has_method("uses_readout")
				var readout: bool = dock.uses_readout() if has_api else dock.readout.visible
				var drawn: Dictionary = dock.drawn_sizes() if has_api else {}
				var image := root.get_texture().get_image()
				check(image.get_size() == Vector2i(size), "captured " + str(image.get_size()) + " for a " + str(size) + " window")
				var ink := ink_pixels(image, strength_rect())
				if not output_dir.is_empty():
					var top: float = minf(dock.readout_top(), dock.global_position.y + dock.art_rect().position.y) - 8.0
					var crop: Rect2 = root.get_final_transform() * Rect2(0, top, root.size.x / root.get_final_transform().get_scale().x, 400.0)
					crop = crop.intersection(Rect2(Vector2.ZERO, Vector2(image.get_size())))
					image.get_region(Rect2i(crop)).save_png(output_dir.path_join("status-%d-%s-%03d.png" % [size.x, "plain" if plain else "default", roundi(scale * 100)]))
				if readout:
					check(drawn.is_empty(), tag + ": the art carries no numbers once the readout shows them")
					var readout_size: int = dock.readout_labels.life.get_theme_font_size("font_size")
					check(readout_size >= MINIMUM, tag + ": readout size " + str(readout_size) + " below minimum")
					check(readout_size > previous_size, tag + ": readout size " + str(readout_size) + " does not grow from " + str(previous_size))
					check(not dock.readout.visible or ink == 0, tag + ": numerals still drawn on the art under the readout")
					previous_size = readout_size
				else:
					check(not has_api or drawn.size() == 9, tag + ": expected nine fitted values, got " + str(drawn.keys()))
					for field in drawn:
						check(drawn[field] >= MINIMUM, tag + ": " + field + " drawn at " + str(drawn[field]) + ", below minimum")
					check(not has_api or drawn.get("strength", 0) > previous_size or previous_readout, tag + ": strength drawn at " + str(drawn.get("strength", 0)) + ", not larger than " + str(previous_size))
					for earlier in inks:
						# Single-pixel steps can rasterise to equal ink; steps of 15% cannot.
						if scale - earlier[0] >= 0.149: check(ink > earlier[1], tag + ": strength shows " + str(ink) + " ink pixels, not more than " + str(earlier[1]) + " at scale " + str(earlier[0]))
					inks.append([scale, ink])
					previous_size = drawn.get("strength", 0)
				previous_readout = readout
				report.append({"tag": tag, "readout": readout, "strength": drawn.get("strength", dock.readout_labels.life.get_theme_font_size("font_size")), "ink": ink})
				print("STATUS ", JSON.stringify(report.back()))
	# The floor: a viewport too narrow for numerals of MIN_VALUE_SIZE inside the art's rects
	# moves them to the readout rather than drawing them smaller. The game stretches its
	# canvas to at least 1280 wide, so a bare SubViewport stands in for the narrow case.
	for width in [400, 1280]:
		var box := SubViewport.new()
		box.size = Vector2i(width, 300)
		box.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(box)
		var bar = BAR.new()
		box.add_child(bar)
		bar.size = Vector2(width, 196)
		bar.update_stats({"life": 12, "lifemax": 20, "strength": 888, "defense": 888, "magic": 888, "gold": 999999, "exp": 99999, "level": 99})
		await draw_frames()
		if bar.has_method("uses_readout"):
			var narrow: bool = width < 900
			check(bar.uses_readout() == narrow, "%d px wide: the readout shows the numbers exactly when the art cannot hold the minimum size (shown: %s)" % [width, bar.uses_readout()])
			for field in bar.drawn_sizes(): check(bar.drawn_sizes()[field] >= MINIMUM, "%d px wide: %s drawn below the minimum" % [width, field])
			print("STATUS FLOOR width=", width, " readout=", bar.uses_readout(), " drawn=", bar.drawn_sizes().values().min() if not bar.drawn_sizes().is_empty() else "none")
		box.queue_free()
	for line in report: if line.tag.contains("scale=1.00"): check(not line.readout and line.ink > 0, line.tag + ": original art shows its numbers at 100%")
	ui.queue_free()
	await process_frame
	print("STATUS NUMBERS PASS" if failures.is_empty() else "STATUS NUMBERS FAIL " + str(failures.size()))
	quit(0 if failures.is_empty() else 1)
