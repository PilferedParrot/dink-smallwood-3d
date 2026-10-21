extends SceneTree

const UI = preload("res://scripts/game_ui.gd")

# A wrapped speech line never ends inside a word. Godot's AUTOWRAP_ARBITRARY breaks
# anywhere to fill the line; the cards use word wrapping, so a break may fall only
# at whitespace, and the sample's words all fit the card's width on their own.
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func settle() -> void:
	for _i in 14: await process_frame

func sample() -> String:
	var words := ["Every", "wanderer", "gathers", "beneath", "the", "supercalifragilistic", "oak,", "and", "Dink", "listens", "to", "extraordinarily", "long-winded", "stories", "about", "dragons", "of", "Stonebrook."]
	var text := ""
	for i in 150: text += words[(i * 7 + i / 5) % words.size()] + " "
	return text.strip_edges()

# Indices i where the text breaks to a new line between two non-space characters (inside a word).
func mid_word_breaks(label: Label) -> Array[int]:
	var found: Array[int] = []
	var text := label.text
	for i in text.length() - 1:
		if text[i] == " " or text[i] == "\n" or text[i + 1] == " " or text[i + 1] == "\n": continue
		var here := label.get_character_bounds(i)
		var next := label.get_character_bounds(i + 1)
		if next.position.y > here.position.y + 1.0: found.append(i)
	return found

func _initialize() -> void:
	create_timer(160.0).timeout.connect(func(): quit(3))
	_run.call_deferred()

func _run() -> void:
	await process_frame
	root.size = Vector2i(1280, 800)
	await process_frame
	var breaks_seen := 0
	for plain in [false, true]:
		for scale in [1.0, 1.5, 2.0]:
			var ui := UI.new()
			root.add_child(ui)
			ui.set_plain_font(plain)
			ui.set_text_scale(scale)
			ui.show_hud({"life": 12, "lifemax": 20, "location": "Stonebrook village"})
			for timed in [true, false]:
				ui.show_dialogue("Opening.", "Dink")
				ui.cancel_speech()
				if timed: ui.show_speech(sample(), "Dink", 0, 600000, false)
				else: ui.show_dialogue(sample(), "Dink", true)
				await settle()
				var tag := "%s%d%% %s" % ["plain " if plain else "", roundi(scale * 100), "timed" if timed else "blocking"]
				var label: Label = ui.column.get_child(0)
				var lines := label.get_line_count()
				check(lines >= 10, "%s: the sample wraps over many lines (%d)" % [tag, lines])
				check(label.autowrap_mode != TextServer.AUTOWRAP_ARBITRARY, "%s: the card does not wrap arbitrarily" % tag)
				var bad := mid_word_breaks(label)
				breaks_seen += lines - 1
				check(bad.is_empty(), "%s: no line ends inside a word (breaks inside words after characters %s of %d lines)" % [tag, bad.slice(0, 5), lines])
			ui.cancel_speech()
			ui.queue_free()
			await process_frame
	check(breaks_seen >= 100, "The check saw many line breaks (%d)" % breaks_seen)
	if failures.is_empty():
		print("SPEECH WORD INTEGRITY PASS")
	quit(1 if not failures.is_empty() else 0)
