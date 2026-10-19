extends SceneTree
## UI-only census: no story execution or campaign reachability claim. The
## companion speech_layout_test exercises every DinkC owner and real input.
const UI = preload("res://scripts/game_ui.gd")
const SPEECH := ["say", "say_xy", "say_stop", "say_stop_npc", "say_stop_xy"]
var ui
var cases: Array[Dictionary] = []
var counts: Dictionary = {}
var failures: Array[String] = []
var checked := 0

func _initialize() -> void:
	_run.call_deferred()

func collect(value: Variant, script: String, source_line: int = 0) -> void:
	if value is Dictionary:
		source_line = int(value.get("line", source_line))
		var command := str(value.get("name", ""))
		if (value.get("op") == "call" or value.get("kind") == "call") and command in SPEECH:
			var first: Dictionary = value.args[0]
			if first.get("kind") != "literal" or not first.get("value") is String:
				failures.append("Census needs a policy for nonliteral speech in " + script)
			else:
				cases.append({"owner": command, "text": first.value, "script": script, "line": source_line})
			counts[command] = int(counts.get(command, 0)) + 1
		elif value.get("op") in ["choice_title", "choice_option"]:
			cases.append({"owner": value.op, "text": value.text, "script": script, "line": source_line})
			counts[value.op] = int(counts.get(value.op, 0)) + 1
		for child in value.values(): collect(child, script, source_line)
	elif value is Array:
		for child in value: collect(child, script, source_line)

func _run() -> void:
	var story: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/story.json"))
	for script in story.scripts: collect(story.scripts[script], script)
	# Validate the instrument on known source cases, plus the full owner set.
	var source_count := cases.size()
	collect({"kind": "literal", "name": "say", "value": "Not an executable call."}, "inert")
	collect({"op": "call", "name": "sp_x", "args": [{"kind": "literal", "value": "say"}]}, "inert")
	if cases.size() != source_count: failures.append("Census classified inert text as speech")
	for owner in SPEECH:
		if int(counts.get(owner, 0)) == 0: failures.append("Census missed owner " + owner)
	if not cases.any(func(row): return row.text == "I don't own a map yet."):
		failures.append("Census missed BUTTON6 negative ownership line")
	if not cases.any(func(row): return row.text == "The best in bows" and row.owner == "say_xy"):
		failures.append("Census missed speech inside a DinkC expression")
	ui = UI.new()
	root.add_child(ui)
	await process_frame
	ui.close_menu()
	for size in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		root.size = size
		for scale in [0.85, 1.0, 1.3]:
			ui.set_text_scale(scale)
			for row in cases:
				# All literal texts are checked, including unexpanded interpolation
				# tokens. Synthetic long strings test unbounded expansion separately.
				# Release the preceding modal owner: otherwise a timed request would
				# queue behind it and the instrument would measure the wrong text.
				ui.cancel_speech()
				if row.owner == "choice_title": ui.show_choices(row.text, ["First", "Second"])
				elif row.owner == "choice_option": ui.show_choices("What will you do?", [row.text, "Second"])
				else: ui.show_dialogue(row.text, "Conversation", row.owner.begins_with("say_stop"))
				for _i in 6: await process_frame
				var displayed := [ui.heading.text]
				for child in ui.column.get_children(): displayed.append(child.text)
				if not row.text in displayed or not ui.panel.visible:
					failures.append("Census measured the wrong card for %s:%s" % [row.script, row.line])
				var dock = ui.status_dock
				var art := Rect2(dock.global_position + Vector2((dock.size.x - dock._dock_width) * 0.5, dock._dock_y),
					Vector2(dock._dock_width, dock.STATUS_HEIGHT * dock._dock_scale))
				var bounds: Rect2 = ui.panel.get_global_rect()
				for decoration in [ui.panel_underlay, ui.vines_left, ui.vines_right]: bounds = bounds.merge(decoration.get_global_rect())
				if bounds.intersects(art) or bounds.position.y < 0 or ui.panel.size.y > ui.root.size.y * 0.35 + 1:
					failures.append("%s:%s %s %s scale=%s bounds=%s art=%s" % [row.script, row.line, row.owner, size, scale, bounds, art])
				checked += 1
			print("SPEECH CENSUS progress size=", size, " scale=", scale, " checked=", checked, " failures=", failures.size())
	print("SPEECH CENSUS ", JSON.stringify({"counts": counts, "source_cases": cases.size(), "checked": checked, "failures": failures}))
	ui.cancel_speech()
	ui.queue_free()
	for _i in 3: await process_frame
	print("SPEECH CENSUS PASS" if failures.is_empty() else "SPEECH CENSUS FAIL")
	quit(0 if failures.is_empty() else 1)
