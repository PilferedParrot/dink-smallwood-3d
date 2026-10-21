# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
extends RefCounted
const INPUT_BINDINGS = preload("res://scripts/input_bindings.gd")
## One owner for automatic resets/focus corrections. Native user scrolling wins
## until focus changes. Native follow_focus supplies pad neighbor search; its
## provisional offset is reconciled after native sorting before drawing.
signal settled
var applying := false
var _queued := false
var _running := false
var _generation := 0
var _serial := -1
var _manual := false
var _reset := false
var _last_focus: WeakRef
var _target: WeakRef
var _scroll_ref: WeakRef
var _ui_ref: WeakRef

func _init(scroll: ScrollContainer, ui: Node) -> void:
	_scroll_ref = weakref(scroll)
	_ui_ref = weakref(ui)
	scroll.follow_focus = true
	scroll.sort_children.connect(_sorted, CONNECT_DEFERRED)
	scroll.resized.connect(_resized)
	scroll.tree_exiting.connect(cancel)
	scroll.gui_input.connect(_user_input)
	scroll.get_v_scroll_bar().gui_input.connect(_user_input)
	scroll.get_v_scroll_bar().value_changed.connect(_value_changed)

func automatic_active() -> bool:
	return not _manual and (_queued or _running or applying)

# True while the player's own scrolling holds the view away from the focused control.
func manual_holds() -> bool:
	return _manual

func _current(target: Control) -> bool:
	var ui = _ui_ref.get_ref()
	return is_instance_valid(ui) and ui.is_inside_tree() and ui.page_serial == _serial and is_instance_valid(target) and target.is_inside_tree() and target.is_visible_in_tree() and ui.get_viewport().gui_get_focus_owner() == target

func _focused() -> Control:
	var target: Control = _target.get_ref() if _target != null else null
	return target if _current(target) else null

# `interaction` is the player changing the focused control itself (a slider step, a
# toggle, a key press): it is on screen to them, so manual scrolling no longer holds it away.
func request_focus(target: Control, serial: int, interaction: bool = false) -> bool:
	var scroll: ScrollContainer = _scroll_ref.get_ref()
	if not is_instance_valid(scroll) or not scroll.is_inside_tree() or not scroll.is_ancestor_of(target): return false
	if target == scroll.get_v_scroll_bar() or target == scroll.get_h_scroll_bar(): return false
	if not interaction and _manual and _serial == serial and _last_focus != null and _last_focus.get_ref() == target: return false
	_serial = serial
	_last_focus = weakref(target)
	_target = weakref(target)
	_manual = false
	_generation += 1
	_queue()
	return true

func request_reset(serial: int, new_page: bool = false) -> void:
	if new_page or serial != _serial:
		cancel()
		_serial = serial
		_last_focus = null
		_manual = false
	elif _manual:
		return
	_reset = true
	_generation += 1
	_queue()

func note_focus_lost() -> void:
	_last_focus = null

func cancel() -> void:
	_generation += 1
	_target = null
	_reset = false
	_manual = true
	settled.emit()

func set_position(value: float, manual: bool = true, emit_change: bool = true) -> void:
	if manual: cancel()
	var scroll: ScrollContainer = _scroll_ref.get_ref()
	if not is_instance_valid(scroll): return
	applying = true
	if emit_change: scroll.scroll_vertical = roundi(value)
	else:
		scroll.get_v_scroll_bar().set_value_no_signal(value)
		scroll.queue_sort()
	applying = false

func _user_input(event: InputEvent) -> void:
	if INPUT_BINDINGS.is_manual_scroll_gesture(event): cancel()

func _value_changed(_value: float) -> void:
	if not applying and not _queued and not _running: cancel()

func _resized() -> void:
	if not _manual and (_reset or _focused() != null):
		_generation += 1
		_queue()

func _sorted() -> void:
	if _manual or _queued or _running: return
	var scroll: ScrollContainer = _scroll_ref.get_ref()
	var target := _focused()
	if not is_instance_valid(scroll) or target == null: return
	# Arbitrarily oversized answers retain native within-answer scrolling.
	if target.size.x > scroll.size.x + 1 or target.size.y > scroll.size.y + 1: return
	if not scroll.get_global_rect().grow(1).encloses(target.get_global_rect()):
		_generation += 1
		_queue()

func _queue() -> void:
	if _queued or _running: return
	_queued = true
	_reconcile.call_deferred()

func _reconcile() -> void:
	_queued = false
	if _running: return
	_running = true
	for _attempt in 8:
		var scroll: ScrollContainer = _scroll_ref.get_ref()
		var ui = _ui_ref.get_ref()
		if _manual or not is_instance_valid(scroll) or not scroll.is_inside_tree() or not is_instance_valid(ui): break
		var target := _focused()
		if not _reset and target == null: break
		var generation := _generation
		var containers: Array[Container] = []
		var parent: Node = target.get_parent() if target != null else scroll
		while parent != null:
			if parent is Container: containers.push_front(parent)
			parent = parent.get_parent()
		var sorted := true
		for container in containers:
			if not await ui._sort_for_focus(container):
				sorted = false
				break
		if not sorted: break
		if generation != _generation: continue
		if _manual or ui.page_serial != _serial: break
		target = _focused()
		applying = true
		if _reset:
			scroll.scroll_vertical = 0
			_reset = false
		if target != null: scroll.ensure_control_visible(target)
		applying = false
		if not await ui._sort_for_focus(scroll): break
		if generation == _generation: break
	_running = false
	settled.emit()
	_sorted()
