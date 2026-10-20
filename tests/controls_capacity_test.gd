# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
extends SceneTree
## UI fixture, no campaign progression. At every scroll stop of every Controls tab where
## rows are still hidden, the empty space under the visible rows must be smaller than
## the shortest remaining row: otherwise the page wastes capacity a row could use.
const UI = preload("res://scripts/game_ui.gd")
var ui
var failures: Array[String] = []
var stops := 0
var worst := 0.0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func settle() -> void:
	for _i in 14: await process_frame

# Measured from the drawn layout, not from the page's own fitting variables.
func spare(menu) -> float:
	# Between the end of the visible rows and where the footer must start.
	var gap: float = menu.get_theme_constant("separation")
	return menu.get_global_rect().end.y - menu.footer.size.y - gap - menu.scroll.get_global_rect().end.y - gap

func hidden_below(menu) -> bool:
	return menu.body.size.y > menu.scroll.scroll_vertical + menu.scroll.size.y + 1

func shortest_remaining(menu) -> float:
	var shortest := INF
	for row in menu.rows:
		if row.position.y + 1 >= menu.scroll.scroll_vertical + menu.scroll.size.y or row.position.y > menu.scroll.scroll_vertical + 1: shortest = minf(shortest, row.size.y)
	return shortest

# Returns the wasted pixels when a row of the shortest remaining height would have fit.
func waste(menu) -> float:
	if not hidden_below(menu): return 0.0
	var gap: float = menu.body.get_theme_constant("separation")
	var free := spare(menu)
	return free if free >= shortest_remaining(menu) + gap else 0.0

func calibrate() -> void:
	ui = UI.new()
	root.add_child(ui)
	root.size = Vector2i(1280, 800)
	ui.set_text_scale(2.0)
	ui.show_controls()
	await settle()
	var menu = ui.controls_menu
	check(waste(menu) == 0.0, "calibration: the page as shipped is a fully used look-alike")
	var shipped: int = menu.scroll.size_flags_vertical
	menu.scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	menu.scroll.custom_minimum_size.y = 40
	await settle()
	check(waste(menu) > 0.0, "calibration: a viewport much shorter than the page is reported as wasting capacity")
	menu.scroll.size_flags_vertical = shipped
	menu.scroll.custom_minimum_size.y = 0
	await settle()
	ui.queue_free()
	await process_frame

func run() -> void:
	await calibrate()
	for size in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		for plain in [false, true]:
			for scale in [1.0, 1.3, 1.5, 2.0]:
				ui = UI.new()
				root.add_child(ui)
				root.size = size
				ui.set_text_scale(scale)
				ui.set_plain_font(plain)
				ui.show_controls()
				await settle()
				for group in ui.bindings.SCOPES:
					ui.controls_menu._select_group(group)
					await settle()
					var menu = ui.controls_menu
					for index in menu.rows.size():
						menu.scroll.scroll_vertical = int(menu.rows[index].position.y)
						await settle()
						stops += 1
						var wasted := waste(menu)
						worst = maxf(worst, wasted)
						check(wasted == 0.0, "%s plain=%s scale=%.2f tab=%s stop=%d: %d px empty under the rows while a row of %d px was left hidden" % [size, plain, scale, group, index, wasted, shortest_remaining(menu)])
				ui.queue_free()
				await process_frame
	print("CONTROLS CAPACITY stops=", stops, " worst_waste=", worst)
	print("CONTROLS CAPACITY PASS" if failures.is_empty() else "CONTROLS CAPACITY FAIL " + str(failures.size()))
	quit(0 if failures.is_empty() else 1)
