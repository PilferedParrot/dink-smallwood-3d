extends SceneTree

const UI = preload("res://scripts/game_ui.gd")
const FIT = preload("res://scripts/text_scroll_fit.gd")

# whole_height() on a content area whose size has not reflowed to its atoms yet.
# A plain Control content is not resized by its text, so its size can stay below
# the bottom of the lines it holds: that state is not a fit (the mother-visibility
# case) and the area must keep the whole slot until the content has reflowed.
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func settle() -> void:
	for _i in 4: await process_frame

func area(ui: Node, view_height: float, text: String) -> Array:
	var box := Control.new()
	box.size = Vector2(400, 300)
	root.add_child(box)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2.ZERO
	scroll.size = Vector2(400, view_height)
	box.add_child(scroll)
	var content := Control.new()
	scroll.add_child(content)
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size = Vector2(380, 10)
	label.text = text
	content.add_child(label)
	await settle()
	label.size = Vector2(380, 10)
	await settle()
	return [FIT.new(scroll, box, ui), scroll, content, label]

func _init() -> void:
	await process_frame
	root.size = Vector2i(1280, 800)
	var ui := UI.new()
	root.add_child(ui)
	await settle()
	var slot := 100.0
	# Not reflowed: content is 30 px tall but its lines end well below the slot.
	var tall: Array = await area(ui, 30.0, "Line of text that goes on.\n".repeat(8))
	var fit = tall[0]
	var content: Control = tall[2]
	var atoms: Array[Vector2] = []
	fit._atoms(content, content.get_global_rect().position.y, atoms)
	var bottom := 0.0
	for atom in atoms: bottom = maxf(bottom, atom.y)
	check(content.size.y <= slot + 0.5 and bottom > slot + 0.5, "Fixture: content (%s) is within the slot but its lines end below it (%s)" % [content.size.y, bottom])
	check(is_equal_approx(fit.whole_height(slot), slot), "Content not yet reflowed to its atoms keeps the slot, not the lines' bottom (%s)" % fit.whole_height(slot))
	check(is_equal_approx(fit.whole_height(slot, 20.0), slot), "A reading floor does not turn an un-reflowed size into a fit")
	# Control: genuinely fits (one line within the slot): the area is as tall as its content.
	var small: Array = await area(ui, 30.0, "One short line.")
	var small_atoms: Array[Vector2] = []
	small[0]._atoms(small[2], small[2].get_global_rect().position.y, small_atoms)
	var small_bottom := 0.0
	for atom in small_atoms: small_bottom = maxf(small_bottom, atom.y)
	var got: float = small[0].whole_height(slot)
	check(small_bottom > 0.5 and small_bottom <= slot and is_equal_approx(got, small_bottom), "A fitting one-line area is as tall as its content (%s vs %s)" % [got, small_bottom])
	if failures.is_empty():
		print("TEXT SCROLL FIT WHOLE HEIGHT PASS")
	quit(1 if not failures.is_empty() else 0)
