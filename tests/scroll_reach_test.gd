# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
extends SceneTree
## UI fixture, no campaign progression. Reachability, not only clean edges: with the real
## Home, End, Page Up and Page Down key events, every menu scroll area reaches scroll 0 and
## its maximum, and stepping through it in each direction brings every line and control
## fully into view. Manual reading must win over the focused control (A1a-2 fix round).
const UI = preload("res://scripts/game_ui.gd")
const EDGES = preload("scroll_edges_oracle.gd")
var ui
var failures: Array[String] = []
var stops := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func settle(count := 10) -> void:
	for _i in count: await process_frame

func tap(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
	await settle()

func maximum(scroll: ScrollContainer) -> int:
	var bar := scroll.get_v_scroll_bar()
	return int(round(bar.max_value - bar.page))

# Atoms in the content's coordinates, and which of them the viewport shows whole right now.
func seen(scroll: ScrollContainer, universe: Dictionary) -> void:
	var found: Array[Dictionary] = []
	EDGES.atoms(scroll.get_child(0), found)
	var origin: float = scroll.get_child(0).get_global_rect().position.y
	var area: Rect2 = scroll.get_global_rect()
	for atom in found:
		var rect: Rect2 = atom.rect
		var key := "%d|%s" % [roundi(rect.position.y - origin), atom.what]
		if not universe.has(key): universe[key] = false
		if rect.size.y > area.size.y + 1 or area.grow(1).encloses(rect): universe[key] = true

func reach(tag: String, scroll: ScrollContainer) -> void:
	await settle(14)
	stops += 1
	await tap(KEY_END)
	var top := maximum(scroll)
	check(scroll.scroll_vertical >= top - 1, "%s: End settles at %d, maximum %d" % [tag, scroll.scroll_vertical, top])
	await tap(KEY_HOME)
	check(scroll.scroll_vertical == 0, "%s: Home settles at %d, not 0" % [tag, scroll.scroll_vertical])
	for direction in [1, -1]:
		var universe := {}
		if direction < 0:
			await tap(KEY_END)
		await seen(scroll, universe)
		for _step in 80:
			var before := scroll.scroll_vertical
			await tap(KEY_PAGEDOWN if direction > 0 else KEY_PAGEUP)
			await seen(scroll, universe)
			if scroll.scroll_vertical == before: break
		var missed: Array[String] = []
		for key in universe: if not universe[key]: missed.append(key)
		check(missed.is_empty(), "%s: paging %s never shows %d of %d: %s" % [tag, "down" if direction > 0 else "up", missed.size(), universe.size(), str(missed.slice(0, 3))])
		check(scroll.scroll_vertical == (maximum(scroll) if direction > 0 else 0), "%s: paging %s ends at %d, not the %s" % [tag, "down" if direction > 0 else "up", scroll.scroll_vertical, "maximum" if direction > 0 else "top"])

func run() -> void:
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
				await reach(tag + " title", ui.menu_scroll)
				ui.show_pause()
				await reach(tag + " pause", ui.menu_scroll)
				ui.show_settings({"text_scale": scale, "plain_font": plain})
				await reach(tag + " settings", ui.menu_scroll)
				ui.show_journal("You have explored Stonebrook.\n\nRecent conversations\n\n" + "A long journal entry remains readable while scrolling. ".repeat(50))
				await reach(tag + " journal", ui.menu_scroll)
				ui.show_credits()
				await reach(tag + " credits", ui.menu_scroll)
				var items: Array = []
				var spells: Array = []
				for i in 16: items.append({"name": "Long named weapon %d" % i, "script": "item-fst"})
				for i in 9: spells.append({"name": "Fireball %d" % i, "script": "item-fb"})
				ui.show_hud({"life": 12, "lifemax": 20, "strength": 999, "defense": 999, "magic": 999, "gold": 999999, "exp": 99999, "level": 99, "cur_weapon": 1, "cur_magic": 1, "weapon_item": items[0], "spell_item": spells[0], "location": "Stonebrook village"})
				ui.show_inventory(items, spells)
				await reach(tag + " equipment", ui.menu_scroll)
				ui.show_controls()
				for group in ui.bindings.SCOPES:
					ui.controls_menu._select_group(group)
					await reach(tag + " controls " + group, ui.controls_menu.scroll)
				ui.queue_free()
				await process_frame
	print("SCROLL REACH surfaces=", stops)
	print("SCROLL REACH PASS" if failures.is_empty() else "SCROLL REACH FAIL " + str(failures.size()))
	quit(0 if failures.is_empty() else 1)
