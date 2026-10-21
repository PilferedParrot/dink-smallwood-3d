# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
extends RefCounted
## Both edges of a text scroll area stay on whole lines and whole controls. The atoms
## are the lines of every visible Label and every other visible leaf control. The top
## edge snaps to an atom boundary in the direction the player scrolled (or to keep the
## focused control whole); the viewport then ends on the last atom boundary that fits,
## so a heading, a line of prose or a button is never cut through. An atom taller than
## the area keeps native scrolling. The space left under the viewport (less than one
## atom) stays empty inside the box that owns the area, so the footer keeps its place and
## the page's size never depends on the viewport (no layout feedback).
var active := false
var _scroll_ref: WeakRef
var _box_ref: WeakRef
var _ui_ref: WeakRef
var _queued := false
var _running := false
var _again := false
var _direction := 0
var _stable_top := 0.0
var _applying := false
var _key := ""

func _init(scroll: ScrollContainer, box: Control, ui: Node) -> void:
	_scroll_ref = weakref(scroll)
	_box_ref = weakref(box)
	_ui_ref = weakref(ui)
	scroll.get_v_scroll_bar().value_changed.connect(_value_changed)
	scroll.sort_children.connect(_changed, CONNECT_DEFERRED)
	box.resized.connect(_changed)
	ui._focus_scroll_owner(scroll).settled.connect(_changed)

# A new page starts with the whole slot (what the area did before fitting); the fit
# then trims the bottom edge to whole atoms as soon as the page is laid out.
func begin_page(on: bool) -> void:
	var scroll: ScrollContainer = _scroll_ref.get_ref()
	if not is_instance_valid(scroll): return
	active = on
	_key = ""
	_direction = 0
	_stable_top = 0.0
	scroll.anchor_bottom = 1.0
	scroll.offset_bottom = 0.0
	_changed()

func _changed() -> void:
	if not active or _queued: return
	_queued = true
	_refit.call_deferred()

func _value_changed(value: float) -> void:
	if _applying or not active: return
	_direction = signi(roundi(value - _stable_top))
	_changed()

# Atoms in the content's coordinates: {top, bottom} of each Label line and leaf control.
func _atoms(node: Node, origin: float, found: Array[Vector2]) -> void:
	var children: Array[Control] = []
	for child in node.get_children():
		if child is Control and child.visible: children.append(child)
	if node is Label and not node.text.is_empty():
		var pitch := float(node.get_line_height()) + float(node.get_theme_constant("line_spacing"))
		var top: float = node.get_global_rect().position.y - origin
		var height: float = node.get_global_rect().size.y
		for line in maxi(1, node.get_line_count()):
			found.append(Vector2(top + line * pitch, top + minf((line + 1) * pitch, height)))
	elif (children.is_empty() or node is BaseButton) and node is Control and node.get_global_rect().size.y > 0:
		var rect: Rect2 = node.get_global_rect()
		found.append(Vector2(rect.position.y - origin, rect.end.y - origin))
	# A button is one atom, icon and frame together; a chest slot is a button holding a picture.
	if node is BaseButton: return
	for child in children: _atoms(child, origin, found)

func _refit() -> void:
	_queued = false
	if _running:
		_again = true
		return
	_running = true
	await _fit()
	_running = false
	if _again:
		_again = false
		_changed()

func _fit() -> void:
	var scroll: ScrollContainer = _scroll_ref.get_ref()
	var box: Control = _box_ref.get_ref()
	var ui = _ui_ref.get_ref()
	if not active or not is_instance_valid(scroll) or not is_instance_valid(box) or not is_instance_valid(ui) or not scroll.is_visible_in_tree() or scroll.get_child_count() == 0: return
	var content: Control = scroll.get_child(0)
	var slot: float = box.size.y
	if slot < 1 or content.size.y < 1: return
	var found: Array[Vector2] = []
	_atoms(content, content.get_global_rect().position.y, found)
	if found.is_empty(): return
	var height := content.size.y
	var tops: Array[float] = [0.0]
	for atom in found:
		if atom.x > 0.5 and not tops.has(snappedf(atom.x, 0.01)) and not _straddled(found, atom.x): tops.append(snappedf(atom.x, 0.01))
	tops.sort()
	# The control the player is working with stays whole, unless the player has scrolled
	# away from it: manual reading wins until focus or the control itself changes.
	var must := Vector2(-1, -1)
	var focus: Control = ui.get_viewport().gui_get_focus_owner()
	if focus != null and not ui._focus_scroll_owner(scroll).manual_holds() and content.is_ancestor_of(focus) and focus.is_visible_in_tree():
		var rect: Rect2 = focus.get_global_rect()
		var local := Vector2(rect.position.y - content.get_global_rect().position.y, rect.end.y - content.get_global_rect().position.y)
		if local.y - local.x <= slot: must = local
	var current := float(scroll.scroll_vertical)
	var valid: Array[float] = []
	var heights := {}
	for top in tops:
		if top >= height - 1.0 and top > 0.0: continue
		var fitted := _span(found, top, slot, height)
		if must.x >= 0.0 and (must.x < top - 0.5 or must.y > top + fitted + 0.5): continue
		valid.append(top)
		heights[top] = fitted
	if valid.is_empty():
		return
	var chosen: float = valid[0]
	var best := INF
	for top in valid:
		var gap: float = top - current
		var distance := absf(gap)
		# Toward the player's direction of travel; nearest when there is none.
		if _direction > 0 and gap < -0.5: distance += 100000.0
		elif _direction < 0 and gap > 0.5: distance += 100000.0
		if distance < best:
			best = distance
			chosen = top
	# A step must not skip a line. Unless it arrives at an end of the page (Home, End), take
	# the boundary nearest the place they asked for on the near side of it, provided it
	# moves on from where the page was.
	var at_end: bool = chosen <= 0.5 or chosen + float(heights[chosen]) >= height - 0.5
	var reached := INF
	for top in valid:
		if at_end: break
		if _direction > 0 and top > _stable_top + 0.5 and top <= current + 0.5 and (reached == INF or top > reached): reached = top
		elif _direction < 0 and top < _stable_top - 0.5 and top >= current - 0.5 and (reached == INF or top < reached): reached = top
	if reached != INF: chosen = reached
	var viewport_height: float = heights[chosen]
	var key := "%d|%d|%d|%d" % [roundi(chosen), roundi(viewport_height), roundi(slot), roundi(height)]
	if key == _key and absf(scroll.scroll_vertical - chosen) < 1.0:
		_direction = 0
		return
	_key = key
	scroll.anchor_bottom = 0.0
	scroll.offset_bottom = viewport_height
	_apply_top(scroll, chosen)
	if absf(scroll.get_v_scroll_bar().value - chosen) > 1.0:
		# The scroll bar had not yet taken the new viewport; once more after it has.
		await scroll.get_tree().process_frame
		if not is_instance_valid(scroll) or not active: return
		_apply_top(scroll, chosen)
	_stable_top = chosen
	_direction = 0

func _apply_top(scroll: ScrollContainer, top: float) -> void:
	_applying = true
	scroll.get_v_scroll_bar().set_value_no_signal(top)
	scroll.queue_sort()
	_applying = false

# Height of the viewport whose top is `top`: it ends on the last atom bottom that fits.
func _span(found: Array[Vector2], top: float, slot: float, height: float) -> float:
	if height - top <= slot + 0.5: return maxf(1.0, height - top)
	var end := top
	for atom in found:
		if atom.y > top + 0.5 and atom.y <= top + slot + 0.5 and atom.y > end and not _straddled(found, atom.y): end = atom.y
	# One atom taller than the area keeps native scrolling.
	return slot if end <= top + 0.5 else end - top

# An edge at `y` would cut through an atom that starts above it and ends below it.
func _straddled(found: Array[Vector2], y: float) -> bool:
	for atom in found:
		if atom.x < y - 0.5 and atom.y > y + 0.5: return true
	return false
