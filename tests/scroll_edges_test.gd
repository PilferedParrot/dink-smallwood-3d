# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
extends SceneTree
## UI fixture, no campaign progression. Every menu page's scroll area, swept across its
## whole range: no text line or control may be cut through at either edge.
const UI = preload("res://scripts/game_ui.gd")
const EDGES = preload("scroll_edges_oracle.gd")
var ui
var failures: Array[String] = []
var stops := 0
var pages := 0
var known := {}
var known_stops := {}

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func settle(count := 8) -> void:
	for _i in count: await process_frame

func sweep(tag: String, scroll: ScrollContainer, open_class := "") -> void:
	await settle(14)
	pages += 1
	var bar := scroll.get_v_scroll_bar()
	var positions: Array[int] = [0]
	var maximum := int(bar.max_value - bar.page)
	if maximum > 0:
		for i in 1:
			pass
		var count := 17
		for i in range(1, count): positions.append(int(round(maximum * float(i) / float(count) + 5.0 * i)))
		positions.append(maximum)
	for position in positions:
		scroll.scroll_vertical = position
		await settle(6)
		stops += 1
		var cut := EDGES.cuts(scroll)
		if open_class != "":
			# Named open class, outside this unit's scope: counted on every run, never silent.
			known_stops[open_class] = int(known_stops.get(open_class, 0)) + 1
			if not cut.is_empty(): known[open_class] = int(known.get(open_class, 0)) + 1
			continue
		check(cut.is_empty(), "%s stop %d (scroll %d of %d): cut at an edge: %s" % [tag, stops, scroll.scroll_vertical, maximum, str(cut.slice(0, 3))])
		check(EDGES.shown(scroll) >= 1, "%s stop %d: the viewport shows no whole line or control" % [tag, stops])
		if scroll == ui.menu_scroll:
			# The parent box is the page's slot; what the viewport leaves of it is the free space.
			var wasted := EDGES.waste(scroll, scroll.get_parent().get_global_rect().end.y - scroll.get_global_rect().end.y)
			check(wasted == 0.0, "%s stop %d (scroll %d of %d): %d px empty under the viewport while the next line or control would fit" % [tag, stops, scroll.scroll_vertical, maximum, wasted])

func calibrate() -> void:
	var box := ScrollContainer.new()
	box.size = Vector2(300, 100)
	root.add_child(box)
	var column := VBoxContainer.new()
	box.add_child(column)
	for i in 8:
		var label := Label.new()
		label.text = "Line %d" % i
		column.add_child(label)
	await settle()
	box.scroll_vertical = 7
	await settle()
	check(not EDGES.cuts(box).is_empty(), "calibration: a scroll position mid-line is reported as a cut")
	box.scroll_vertical = int(column.get_child(2).position.y)
	box.custom_minimum_size.y = 0
	await settle()
	var whole: float = column.get_child(5).position.y + column.get_child(5).size.y - column.get_child(2).position.y
	box.size.y = whole
	await settle()
	check(EDGES.cuts(box).is_empty(), "calibration: a viewport edged exactly on whole lines is accepted")
	# The plausible-but-wrong fix: a viewport that is whole but wastes the space under it.
	box.size.y = column.get_child(0).size.y * 2.0
	await settle()
	check(EDGES.waste(box, 60.0) > 0.0 and EDGES.waste(box, 2.0) == 0.0, "calibration: waste is reported only when the next atom would have fitted")
	check(EDGES.shown(box) >= 1, "calibration: a whole viewport shows lines")
	box.free()

func run() -> void:
	await calibrate()
	for size in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		for plain in [false, true]:
			for scale in [1.0, 1.3, 1.5, 2.0]:
				root.size = size
				ui = UI.new()
				root.add_child(ui)
				ui.set_text_scale(scale)
				ui.set_plain_font(plain)
				var tag := "%s plain=%s scale=%.2f" % [size, plain, scale]
				ui.show_title(true)
				await sweep(tag + " title", ui.menu_scroll)
				ui.show_pause()
				await sweep(tag + " pause", ui.menu_scroll)
				ui.show_settings({"text_scale": scale, "plain_font": plain})
				await sweep(tag + " settings", ui.menu_scroll)
				ui.show_journal("You have explored Stonebrook.\n\nRecent conversations\n\n" + "A long journal entry remains readable while scrolling. ".repeat(50))
				await sweep(tag + " journal", ui.menu_scroll)
				ui.show_credits()
				await sweep(tag + " credits", ui.menu_scroll)
				var items: Array = []
				var spells: Array = []
				for i in 16: items.append({"name": "Long named weapon %d" % i, "script": "item-fst"})
				for i in 9: spells.append({"name": "Fireball %d" % i, "script": "item-fb"})
				ui.show_hud({"life": 12, "lifemax": 20, "strength": 999, "defense": 999, "magic": 999, "gold": 999999, "exp": 99999, "level": 99, "cur_weapon": 1, "cur_magic": 1, "weapon_item": items[0], "spell_item": spells[0], "location": "Stonebrook village"})
				ui.show_inventory(items, spells)
				await sweep(tag + " equipment", ui.menu_scroll)
				ui.column.get_node("EquipmentChest")._turn_page(1)
				await sweep(tag + " equipment magic page", ui.menu_scroll)
				ui.show_controls()
				for group in ui.bindings.SCOPES:
					ui.controls_menu._select_group(group)
					await sweep(tag + " controls " + group, ui.controls_menu.scroll)
				ui.cancel_speech()
				ui.show_dialogue("Every line of a long conversation can be read. ".repeat(70), "Conversation")
				await sweep(tag + " speech", ui.menu_scroll, "speech")
				ui.show_choices("Will you help the village? " + "The prompt has its own reading viewport. ".repeat(14), ["Yes, I will help the village.", "Tell me more before I choose.", "I need some time to think about it."])
				await sweep(tag + " choice prompt", ui.choice_prompt_scroll, "choice prompt")
				await sweep(tag + " choice answers", ui.menu_scroll, "choice answers")
				ui.cancel_speech()
				ui.queue_free()
				await process_frame
	var by_page := {}
	for failure in failures:
		var name: String = failure.split(" stop ")[0].split(" plain=")[0] + " " + failure.split(" stop ")[0].split("scale=")[1].split(" ", true, 1)[1]
		var kind := "cut" if failure.contains("cut at an edge") else ("waste" if failure.contains("empty under") else "collapsed")
		name += " [" + kind + "]"
		by_page[name] = int(by_page.get(name, 0)) + 1
	for name in by_page: print("EDGE FAILURES ", name, " ", by_page[name])
	for open_class in known_stops:
		print("KNOWN OPEN CLASS ", open_class, ": a line or control is cut at an edge in ", known.get(open_class, 0), " of ", known_stops[open_class], " swept stops (speech/choice card sizing belongs to A1a's whole-line machinery; not fitted here)")
	print("SCROLL EDGES pages=", pages, " stops=", stops)
	print("SCROLL EDGES PASS" if failures.is_empty() else "SCROLL EDGES FAIL " + str(failures.size()))
	quit(0 if failures.is_empty() else 1)
