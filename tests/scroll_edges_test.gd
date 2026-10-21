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

func sweep(tag: String, scroll: ScrollContainer, slot: Control = null) -> void:
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
		check(cut.is_empty(), "%s stop %d (scroll %d of %d): cut at an edge: %s" % [tag, stops, scroll.scroll_vertical, maximum, str(cut.slice(0, 3))])
		check(EDGES.shown(scroll) >= 1, "%s stop %d: the viewport shows no whole line or control" % [tag, stops])
		if slot != null:
			# A card is sized to whole atoms: the viewport fills the slot the card gives it, no empty strip under the text.
			var strip := slot.get_global_rect().end.y - scroll.get_global_rect().end.y
			check(strip < 1.0, "%s stop %d (scroll %d of %d): %d px empty strip under the text in the card" % [tag, stops, scroll.scroll_vertical, maximum, roundi(strip)])
		elif scroll == ui.menu_scroll:
			# The parent box is the page's slot; what the viewport leaves of it is the free space.
			var wasted := EDGES.waste(scroll, scroll.get_parent().get_global_rect().end.y - scroll.get_global_rect().end.y)
			check(wasted == 0.0, "%s stop %d (scroll %d of %d): %d px empty under the viewport while the next line or control would fit" % [tag, stops, scroll.scroll_vertical, maximum, wasted])

# The timed speech scroll: continuous while it moves (partial lines pass through, at the reading pace),
# whole lines at load and at the end, and the viewport is whole lines the entire time.
func timed(tag: String) -> void:
	ui.cancel_speech()
	ui.show_speech("Every line of a long conversation can be read. ".repeat(70), "Conversation", 0, 600000, false)
	await settle(14)
	var scroll: ScrollContainer = ui.menu_scroll
	var label: Label = ui.column.get_child(0)
	var pitch := float(label.get_line_height() + label.get_theme_constant("line_spacing"))
	pages += 1
	stops += 1
	check(scroll.scroll_vertical == 0 and EDGES.cuts(scroll).is_empty(), "%s: the timed card does not open on whole lines: %s" % [tag, str(EDGES.cuts(scroll).slice(0, 3))])
	check(ui.menu_box.get_global_rect().end.y - scroll.get_global_rect().end.y < 1.0, "%s: empty strip under the timed text" % tag)
	var spacing := float(label.get_theme_constant("line_spacing"))
	check(absf((scroll.size.y + spacing) / pitch - roundf((scroll.size.y + spacing) / pitch)) * pitch < 1.0, "%s: the timed viewport is not whole lines (%.1f px of pitch %.1f)" % [tag, scroll.size.y, pitch])
	# Round 2: the card's viewport is the NEAREST whole line to the share the 35% cap allows (within half a line of it),
	# unless the reading floor (two lines) is the larger.
	var share: float = ui.root.size.y * 0.35 - (ui.panel.size.y - scroll.size.y)
	var floor_px := 2.0 * pitch - spacing
	check(scroll.size.y >= floor_px - 1.0 and (scroll.size.y <= floor_px + 1.0 or absf(scroll.size.y - share) <= pitch / 2.0 + 1.0), "%s: the timed viewport %.1f px is not the nearest whole line to the cap share %.1f (pitch %.1f)" % [tag, scroll.size.y, share, pitch])
	var off_grid := 0
	var moved := 0
	var largest := 0.0
	var previous := 0.0
	ui.timed_phase = 1
	for i in 8000:
		ui._advance_timed_speech(0.25)
		await process_frame
		var here := float(scroll.scroll_vertical)
		if here != previous: moved += 1
		largest = maxf(largest, here - previous)
		previous = here
		if absf(fposmod(here, pitch)) > 0.5 and absf(fposmod(here, pitch) - pitch) > 0.5: off_grid += 1
		if ui.timed_phase == 2: break
	stops += 1
	check(ui.timed_phase == 2, "%s: the timed scroll never reached its end" % tag)
	check(EDGES.cuts(scroll).is_empty(), "%s: the timed scroll ends on a cut line: %s" % [tag, str(EDGES.cuts(scroll).slice(0, 3))])
	check(moved > 20 and off_grid > moved / 4 and largest < pitch, "%s: the timed scroll is not continuous (moved %d, off-grid %d, largest step %.1f, pitch %.1f)" % [tag, moved, off_grid, largest, pitch])
	ui.cancel_speech()

# Reachability: stepping the way a wheel does visits every line or control, Home and End reach both ends.
func reach(tag: String, scroll: ScrollContainer) -> void:
	var all: Array[Dictionary] = []
	EDGES.atoms(scroll.get_child(0), all)
	var bar := scroll.get_v_scroll_bar()
	var maximum := int(bar.max_value - bar.page)
	scroll.scroll_vertical = 0
	await settle(6)
	check(scroll.scroll_vertical == 0, "%s: Home does not reach the top (%d)" % [tag, scroll.scroll_vertical])
	var seen := {}
	var guard := 0
	while guard < 3000:
		guard += 1
		var now: Array[Dictionary] = []
		EDGES.atoms(scroll.get_child(0), now)
		for atom in now:
			if scroll.get_global_rect().grow(0.5).encloses(atom.rect): seen[atom.what] = true
		var before := scroll.scroll_vertical
		if before >= maximum: break
		scroll.scroll_vertical = before + maxi(1, roundi(bar.page / 8.0))
		await settle(4)
		if scroll.scroll_vertical <= before: break
	var missing := 0
	for atom in all:
		if not seen.has(atom.what) and atom.rect.size.y <= scroll.size.y + 1: missing += 1
	check(missing == 0, "%s: stepping never showed %d of %d lines or controls" % [tag, missing, all.size()])
	scroll.scroll_vertical = int(bar.max_value)
	await settle(6)
	check(scroll.scroll_vertical >= maximum - 1, "%s: End does not reach the bottom (%d of %d)" % [tag, scroll.scroll_vertical, maximum])
	var final: Array[Dictionary] = []
	EDGES.atoms(scroll.get_child(0), final)
	check(scroll.get_global_rect().grow(0.5).encloses(final.back().rect), "%s: End does not show the last line or control whole" % tag)

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
	# Look-alike control: a card one pixel short of whole lines must fail.
	box.size.y = whole - 1.0
	await settle()
	check(not EDGES.cuts(box).is_empty(), "calibration: a viewport one pixel short of whole lines is reported as a cut")
	box.size.y = whole
	await settle()
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
				await sweep(tag + " speech", ui.menu_scroll, ui.menu_box)
				await reach(tag + " speech", ui.menu_scroll)
				await timed(tag + " timed speech")
				ui.show_choices("Will you help the village? " + "The prompt has its own reading viewport. ".repeat(14), ["Yes, I will help the village.", "Tell me more before I choose.", "I need some time to think about it."])
				await sweep(tag + " choice prompt", ui.choice_prompt_scroll, ui.get("choice_prompt_box"))
				await reach(tag + " choice prompt", ui.choice_prompt_scroll)
				await sweep(tag + " choice answers", ui.menu_scroll, ui.menu_box)
				await reach(tag + " choice answers", ui.menu_scroll)
				# A long prompt with fewer answers: the answer area's content fits its slot, and the prompt's rounding
				# must not leave the difference as an empty strip.
				var answers := ["Yes, I will help the village.", "Tell me more before I choose.", "I need some time to think about it."]
				for count in [1, 2]:
					ui.show_choices("Will you help the village? " + "The prompt has its own reading viewport. ".repeat(14), answers.slice(0, count))
					await sweep(tag + " choice prompt %d answers" % count, ui.choice_prompt_scroll, ui.get("choice_prompt_box"))
					await sweep(tag + " choice answers (%d)" % count, ui.menu_scroll, ui.menu_box)
				ui.cancel_speech()
				ui.queue_free()
				await process_frame
	var by_page := {}
	for failure in failures:
		var name: String = failure.split(" stop ")[0].split(" plain=")[0] + " " + failure.split(" stop ")[0].split("scale=")[1].split(" ", true, 1)[1]
		var kind := "cut" if failure.contains("cut at an edge") else ("waste" if failure.contains("empty under") else ("strip" if failure.contains("empty strip") else "collapsed"))
		name += " [" + kind + "]"
		by_page[name] = int(by_page.get(name, 0)) + 1
	for name in by_page: print("EDGE FAILURES ", name, " ", by_page[name])
	print("SCROLL EDGES pages=", pages, " stops=", stops)
	print("SCROLL EDGES PASS" if failures.is_empty() else "SCROLL EDGES FAIL " + str(failures.size()))
	quit(0 if failures.is_empty() else 1)
