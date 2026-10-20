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

func leaves(node: Node, found: Array[Control]) -> void:
	var children: Array[Control] = []
	for child in node.get_children():
		if child is Control and child.visible: children.append(child)
	if children.is_empty() and node is Control: found.append(node)
	for child in children: leaves(child, found)

# The first control below the viewport edge: what the leftover space could still show.
func next_hidden(menu) -> Control:
	var all: Array[Control] = []
	leaves(menu.body, all)
	var edge: float = menu.scroll.get_global_rect().end.y
	var next: Control
	for control in all:
		if control.get_global_rect().position.y >= edge - 1 and (next == null or control.get_global_rect().position.y < next.get_global_rect().position.y): next = control
	return next

# Controls the viewport edge cuts through (taller-than-viewport ones scroll natively).
func cut_controls(menu) -> Array[String]:
	var all: Array[Control] = []
	leaves(menu.body, all)
	var area: Rect2 = menu.scroll.get_global_rect()
	var found: Array[String] = []
	for control in all:
		var rect := control.get_global_rect()
		if rect.size.y > area.size.y or rect.intersection(area).size.y <= 1: continue
		if not area.grow(1).encloses(rect): found.append(str(control.get("text")) if control is Button or control is Label else str(control.name))
	return found

# Returns the wasted pixels when the next hidden control would have fit in the empty space.
func waste(menu) -> float:
	var next := next_hidden(menu)
	if next == null: return 0.0
	var free := spare(menu)
	# Fits if its far edge lands inside the empty space under the rows.
	return free if next.get_global_rect().end.y <= menu.scroll.get_global_rect().end.y + free + 1 else 0.0

func calibrate() -> void:
	ui = UI.new()
	root.add_child(ui)
	root.size = Vector2i(1280, 800)
	ui.set_text_scale(2.0)
	ui.show_controls()
	await settle()
	var menu = ui.controls_menu
	check(waste(menu) == 0.0, "calibration: the page as shipped is a fully used look-alike")
	check(cut_controls(menu).is_empty(), "calibration: the page as shipped cuts no control")
	menu.set_process(false)
	menu.scroll.custom_minimum_size.y = 40
	await settle()
	check(waste(menu) > 0.0, "calibration: a viewport much shorter than the page is reported as wasting capacity")
	menu.scroll.custom_minimum_size.y = 100
	await settle()
	check(not cut_controls(menu).is_empty(), "calibration: a viewport edge through a heading or button is reported")
	menu.set_process(true)
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
						var next := next_hidden(menu)
						check(wasted == 0.0, "%s plain=%s scale=%.2f tab=%s stop=%d: %d px empty under the rows while the next control (%d px) was left hidden" % [size, plain, scale, group, index, wasted, next.size.y if next != null else 0])
						var cut := cut_controls(menu)
						check(cut.is_empty(), "%s plain=%s scale=%.2f tab=%s stop=%d: viewport edge cuts through %s" % [size, plain, scale, group, index, str(cut)])
				ui.queue_free()
				await process_frame
	print("CONTROLS CAPACITY stops=", stops, " worst_waste=", worst)
	print("CONTROLS CAPACITY PASS" if failures.is_empty() else "CONTROLS CAPACITY FAIL " + str(failures.size()))
	quit(0 if failures.is_empty() else 1)
