extends SceneTree

const UI = preload("res://scripts/game_ui.gd")

# Named geometries really are the geometries run, and a card whose text needs more
# than six lines shows all of them where its 35% share has the room. The project
# stretches the 1280x800 base with aspect "expand", so a 16:9 window keeps the
# 800 px canvas height (1422x800 at 1920x1080) and only a taller window gives a
# taller canvas: 1280x1600 is the geometry in which seven and eight lines fit, and in
# which a twenty-line card scrolls while still showing more than six.
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func settle() -> void:
	for _i in 14: await process_frame

func numbered(count: int) -> String:
	var lines: Array[String] = []
	for i in count: lines.append("Line %d of this card." % (i + 1))
	return "\n".join(lines)

func _initialize() -> void:
	create_timer(160.0).timeout.connect(func(): quit(3))
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var shown_most := 0
	var overflow_most := 0
	for geometry in [{"window": Vector2i(1920, 1080), "canvas": Vector2(1422, 800)}, {"window": Vector2i(1280, 1600), "canvas": Vector2(1280, 1600)}]:
		root.size = geometry.window
		await settle()
		check(root.size == geometry.window, "Window %s took effect (root is %s)" % [geometry.window, root.size])
		for plain in [false, true]:
			for scale in [1.0, 1.5, 2.0]:
				var ui := UI.new()
				root.add_child(ui)
				ui.set_plain_font(plain)
				ui.set_text_scale(scale)
				ui.show_hud({"life": 12, "lifemax": 20, "location": "Stonebrook village"})
				await settle()
				var canvas: Vector2 = ui.root.size
				var tag := "%s %s%s" % [geometry.window, "plain " if plain else "", "%d%%" % roundi(scale * 100)]
				check(absf(canvas.x - geometry.canvas.x) <= 1.0 and absf(canvas.y - geometry.canvas.y) <= 1.0, "%s: canvas is the stretched named geometry %s (is %s)" % [tag, geometry.canvas, canvas])
				for count in [7, 8, 20]:
					for timed in [true, false]:
						ui.cancel_speech()
						# A blocking card first moves the interface off its title page, as in play.
						ui.show_dialogue("Opening.", "Dink")
						ui.cancel_speech()
						if timed: ui.show_speech(numbered(count), "Dink", 0, 600000, false)
						else: ui.show_dialogue(numbered(count), "Dink", false)
						await settle()
						if ui.column.get_child_count() == 0:
							check(false, "%s %d lines: no card opened (page %s)" % [tag, count, ui.page])
							continue
						var label: Label = ui.column.get_child(0)
						check(label.get_line_count() == count, "%s %d lines: the sample is %d lines (is %d)" % [tag, count, count, label.get_line_count()])
						var spacing := float(label.get_theme_constant("line_spacing"))
						var pitch := float(label.get_line_height()) + spacing
						var chrome: float = ui.panel.size.y - ui.menu_scroll.size.y
						var in_view := int(floor((ui.menu_scroll.size.y + spacing + 1.0) / pitch))
						var bar: VScrollBar = ui.menu_scroll.get_v_scroll_bar()
						var kind := "%s %d lines %s" % [tag, count, "timed" if timed else "plain speech"]
						shown_most = maxi(shown_most, in_view)
						print("CARD LINES ", kind, " in_view=", in_view, " chrome=", chrome, " pitch=", pitch, " scroll=", bar.max_value, "/", bar.page)
						# Where the 35% share holds all of them (whole lines), all of them are in view, none behind a scroll.
						if chrome + count * pitch <= canvas.y * 0.35 - pitch:
							check(in_view >= count and bar.max_value <= bar.page + 1.0, "%s: the card shows all %d lines (%d in view, scroll %s/%s)" % [kind, count, in_view, bar.max_value, bar.page])
						# Otherwise the rest stay reachable, and the card still shows every whole line its share holds.
						else:
							check(bar.max_value >= float(count) * pitch - spacing - 1.0, "%s: every line is reachable (scroll range %s for %d lines)" % [kind, bar.max_value, count])
							var share_lines := int(floor((canvas.y * 0.35 - chrome) / pitch))
							check(in_view >= share_lines, "%s: an overflowing card shows the %d whole lines its share holds (%d in view)" % [kind, share_lines, in_view])
							overflow_most = maxi(overflow_most, in_view)
				ui.cancel_speech()
				ui.queue_free()
				await process_frame
	check(shown_most > 6, "At least one named geometry shows more than six lines at once (most seen: %d)" % shown_most)
	# Precondition for the no-cap claim on the scrolling path: some overflowing card had room for more than six.
	check(overflow_most > 6, "At least one overflowing card shows more than six lines at once (most seen: %d)" % overflow_most)
	print("CARD LINES MOST in_view=", shown_most, " overflowing=", overflow_most)
	if failures.is_empty():
		print("SPEECH CARD LINES PASS")
	quit(1 if not failures.is_empty() else 0)
