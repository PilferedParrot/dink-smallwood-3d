extends SceneTree
## UI-only reading coverage. No campaign progression/timing claim.
const UI = preload("res://scripts/game_ui.gd")
var ui
var lines: Array[String] = []
var failures: Array[String] = []
var checked := 0

func _initialize() -> void:
	_run.call_deferred()

func collect(value: Variant) -> void:
	if value is Dictionary:
		if (value.get("op") == "call" or value.get("kind") == "call") and str(value.get("name", "")).to_lower() in ["say", "say_xy"]:
			lines.append(str(value.args[0].value))
		for child in value.values(): collect(child)
	elif value is Array:
		for child in value: collect(child)

func coverage(text: String, stalled := false) -> void:
	ui.cancel_speech()
	ui.show_dialogue(text, "Dink", false)
	for _i in 8: await process_frame
	var label: Label = ui.column.get_child(0)
	var seen := {}
	var line_count := label.get_line_count()
	var line_height := float(label.get_line_height())
	var step := line_height + label.get_theme_constant("line_spacing")
	var frames := 0
	var elapsed := 0.0
	var previous_y := label.global_position.y
	var fast_scroll := false
	var words := text.replace("\n", " ").replace("\t", " ").split(" ", false).size()
	var reading := maxf(words / (170.0 / 60.0), text.length() / 17.0)
	var limit := ceili((reading * 3 + 20) * 12)
	while ui.page == "dialogue" and frames < limit:
		var movement := previous_y - label.global_position.y
		if not stalled and movement > label.get_combined_minimum_size().y / maxf(reading, 0.001) / 12.0 + 1.1: fast_scroll = true
		previous_y = label.global_position.y
		var viewport: Rect2 = ui.menu_scroll.get_global_rect()
		for i in line_count:
			var top := label.global_position.y + i * step
			if top >= viewport.position.y - 1 and top + line_height <= viewport.end.y + 1: seen[i] = true
		if stalled:
			ui._process(100.0)
			elapsed += 100
		else: elapsed += 1.0 / 12.0
		await process_frame
		frames += 1
	if fast_scroll or seen.size() != line_count or ui.page == "dialogue" or (not stalled and elapsed + 1 < reading):
		failures.append("Reading coverage %s/%s lines, closed=%s duration=%s budget=%s fast_scroll=%s text=%s" % [seen.size(),line_count,ui.page != "dialogue",elapsed,reading,fast_scroll,text.left(70)])
	checked += 1

func _run() -> void:
	collect(JSON.parse_string(FileAccess.get_file_as_string("res://data/story.json")).scripts)
	if lines.size() != 348: failures.append("Timed source census changed: " + str(lines.size()))
	lines.append("A long timed paragraph must expose every wrapped line before it expires. ".repeat(35))
	lines.append("Unbroken".repeat(100))
	lines.append("One\nTwo\nThree\nFour\nFive\nSix\nSeven\nEight\nNine\nTen\n".repeat(4))
	ui = UI.new()
	root.add_child(ui)
	await process_frame
	ui.close_menu()
	for size in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		root.size = size
		for style in [{"scale":1.0,"plain":false},{"scale":1.5,"plain":false},{"scale":2.0,"plain":false},{"scale":1.0,"plain":true},{"scale":1.5,"plain":true},{"scale":2.0,"plain":true}]:
			var scale: float = style.scale
			ui.set_plain_font(style.plain)
			ui.set_text_scale(scale)
			for text in lines: await coverage(text)
			await coverage(lines[-3], true)
			print("TIMED READING progress ", size, " scale=",scale," checked=",checked," failures=",failures.size())
	ui.cancel_speech()
	ui.queue_free()
	for _i in 3: await process_frame
	print(JSON.stringify({"checked":checked,"source":348,"failures":failures}))
	print("TIMED READING PASS" if failures.is_empty() else "TIMED READING FAIL")
	quit(0 if failures.is_empty() else 1)
