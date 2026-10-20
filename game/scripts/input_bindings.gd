# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
# Runtime InputMap owner. Identity is physical; labels follow the active layout.
extends RefCounted
signal changed
const SETTINGS_KEY := "bindings_v1"
const VERSION := 1
const SCOPES := ["2d", "fps", "menu", "global"]
const ESSENTIAL_MENU := ["ui_up","ui_down","ui_left","ui_right","ui_accept","ui_cancel"]
var context := "fps"
var settings_path := "user://settings.json"
var settings: Dictionary = {}
var overrides: Dictionary = {}
var actions: Dictionary = {}
var warnings: Array[String] = []
var backup_required := false

func _init(mode: String = "fps", path: String = "user://settings.json") -> void:
	assert(mode in ["2d", "fps"])
	context = mode
	settings_path = path
	_build_registry()

static func key(code: int) -> Dictionary:
	return {"type":"key", "physical":code}

static func mouse(button: int) -> Dictionary:
	return {"type":"mouse", "button":button}

static func is_manual_scroll_gesture(event: InputEvent) -> bool:
	return event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]

static func pad(button: int) -> Dictionary:
	return {"type":"pad", "button":button}

static func axis(index: int, direction: int) -> Dictionary:
	return {"type":"axis", "axis":index, "direction":direction}

func _add(id: String, title: String, defaults: Dictionary, reserved := false) -> void:
	actions[id] = {"id":id, "name":title, "contexts":defaults.keys(), "defaults":defaults, "reserved":reserved}

func _both(id: String, title: String, events: Array) -> void:
	_add(id, title, {"2d":events, "fps":events})

func _build_registry() -> void:
	for row in [["left","Move left",KEY_A,KEY_LEFT,JOY_AXIS_LEFT_X,-1], ["right","Move right",KEY_D,KEY_RIGHT,JOY_AXIS_LEFT_X,1], ["up","Move forward",KEY_W,KEY_UP,JOY_AXIS_LEFT_Y,-1], ["down","Move backward",KEY_S,KEY_DOWN,JOY_AXIS_LEFT_Y,1]]:
		_both(row[0], row[1], [key(row[2]),key(row[3]),axis(row[4],row[5])])
	_both("talk", "Talk / examine", [key(KEY_E),key(KEY_ENTER),pad(JOY_BUTTON_A)])
	_add("attack", "Attack", {"2d":[key(KEY_SPACE),pad(JOY_BUTTON_X)], "fps":[mouse(MOUSE_BUTTON_LEFT),pad(JOY_BUTTON_X),axis(JOY_AXIS_TRIGGER_RIGHT,1)]})
	_add("magic", "Magic", {"2d":[key(KEY_Q),pad(JOY_BUTTON_Y)], "fps":[key(KEY_Q),mouse(MOUSE_BUTTON_RIGHT),pad(JOY_BUTTON_Y),axis(JOY_AXIS_TRIGGER_LEFT,1)]})
	_both("pause", "Pause", [key(KEY_ESCAPE),pad(JOY_BUTTON_START)])
	_both("inventory", "Equipment", [key(KEY_I),pad(JOY_BUTTON_BACK)])
	_both("map", "World map", [key(KEY_M)])
	_add("camera", "Camera angle", {"2d":[key(KEY_R),pad(JOY_BUTTON_RIGHT_STICK)]})
	_add("jump", "Jump", {"fps":[key(KEY_SPACE),pad(JOY_BUTTON_RIGHT_STICK)]})
	_add("sprint", "Sprint", {"fps":[key(KEY_SHIFT),pad(JOY_BUTTON_LEFT_STICK)]})
	for row in [["look_left","Look left",JOY_AXIS_RIGHT_X,-1], ["look_right","Look right",JOY_AXIS_RIGHT_X,1], ["look_up","Look up",JOY_AXIS_RIGHT_Y,-1], ["look_down","Look down",JOY_AXIS_RIGHT_Y,1]]:
		_add(row[0],row[1],{"fps":[axis(row[2],row[3])]})
	_add("weapon_previous", "Previous weapon", {"fps":[pad(JOY_BUTTON_LEFT_SHOULDER)]})
	_add("weapon_next", "Next weapon", {"fps":[pad(JOY_BUTTON_RIGHT_SHOULDER)]})
	for i in range(9): _add("weapon_%d" % (i+1), "Weapon slot %d" % (i+1), {"fps":[key(KEY_1+i)]})
	_both("help", "Controls help", [key(KEY_F1)])
	_add("fullscreen", "Fullscreen", {"global":[key(KEY_F11)]})
	_add("bug_report", "Local bug report", {"fps":[key(KEY_F9)]}, true)
	# Escape is an immutable fallback, independent of remappable Pause/Back.
	_add("escape", "Guaranteed back / pause", {"global":[key(KEY_ESCAPE)]}, true)
	for row in [["ui_up","Menu up",KEY_UP,JOY_BUTTON_DPAD_UP,JOY_AXIS_LEFT_Y,-1], ["ui_down","Menu down",KEY_DOWN,JOY_BUTTON_DPAD_DOWN,JOY_AXIS_LEFT_Y,1], ["ui_left","Menu left / decrease",KEY_LEFT,JOY_BUTTON_DPAD_LEFT,JOY_AXIS_LEFT_X,-1], ["ui_right","Menu right / increase",KEY_RIGHT,JOY_BUTTON_DPAD_RIGHT,JOY_AXIS_LEFT_X,1]]:
		_add(row[0],row[1],{"menu":[key(row[2]),pad(row[3]),axis(row[4],row[5])]})
	_add("ui_accept", "Confirm / continue", {"menu":[key(KEY_ENTER),key(KEY_KP_ENTER),key(KEY_SPACE),pad(JOY_BUTTON_A)]})
	# Keep the native ui_select alias synchronized with confirmation.
	_add("ui_cancel", "Menu back", {"menu":[key(KEY_ESCAPE),pad(JOY_BUTTON_B)]})
	_add("ui_focus_next", "Next menu control", {"menu":[key(KEY_TAB)]})
	# Explicit modifiers keep Tab and Shift+Tab distinct in the native UI.
	_add("ui_focus_prev", "Previous menu control", {"menu":[{"type":"key","physical":KEY_TAB,"shift":true}]})
	_add("ui_page_up", "Read prompt up", {"menu":[key(KEY_PAGEUP),axis(JOY_AXIS_RIGHT_Y,-1)]})
	_add("ui_page_down", "Read prompt down", {"menu":[key(KEY_PAGEDOWN),axis(JOY_AXIS_RIGHT_Y,1)]})
	_add("ui_home", "Scroll to start", {"menu":[key(KEY_HOME)]})
	_add("ui_end", "Scroll to end", {"menu":[key(KEY_END)]})
	# Pause/back and map-toggle also consume input while their menus are open.
	for id in ["pause","map"]: actions[id]["menu_active"] = true

func _warn(message: String) -> void:
	warnings.append(message)
	push_warning("Input bindings: " + message)

func scope_for(action: String, scope: String = "") -> String:
	if not scope.is_empty(): return scope
	if actions.has(action) and actions[action].contexts == ["global"]: return "global"
	return "menu" if actions.has(action) and actions[action].contexts == ["menu"] else context

func defaults(action: String, scope: String = "") -> Array:
	return actions.get(action, {}).get("defaults", {}).get(scope_for(action,scope), []).duplicate(true)

func events(action: String, scope: String = "") -> Array:
	var area := scope_for(action,scope)
	return overrides.get(area, {}).get(action, defaults(action,area)).duplicate(true)

static func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= low and value <= high

# Only plain data is accepted. No object/resource deserialization from user files.
static func normalize(record: Variant) -> Dictionary:
	if not record is Dictionary or not record.get("type") is String: return {}
	match record.type:
		"key":
			if not _integer(record.get("physical"), 1, KEY_UNKNOWN-1): return {}
			var code := int(record.physical)
			var name := OS.get_keycode_string(code)
			if name.is_empty() or OS.find_keycode_from_string(name) != code: return {}
			var result := key(code)
			for modifier in ["shift","ctrl","alt","meta"]:
				if record.has(modifier):
					if not record[modifier] is bool: return {}
					if record[modifier]: result[modifier] = true
			return result
		"mouse":
			return mouse(int(record.button)) if _integer(record.get("button"),1,MOUSE_BUTTON_XBUTTON2) else {}
		"pad":
			return pad(int(record.button)) if _integer(record.get("button"),0,JOY_BUTTON_MAX-1) else {}
		"axis":
			if not _integer(record.get("axis"),0,JOY_AXIS_MAX-1) or not _integer(record.get("direction"),-1,1) or record.direction == 0: return {}
			return axis(int(record.axis),int(record.direction))
	return {}

static func from_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var record := key(event.physical_keycode)
		for pair in [["shift",event.shift_pressed],["ctrl",event.ctrl_pressed],["alt",event.alt_pressed],["meta",event.meta_pressed]]:
			if pair[1] and event.physical_keycode != {"shift":KEY_SHIFT,"ctrl":KEY_CTRL,"alt":KEY_ALT,"meta":KEY_META}[pair[0]]: record[pair[0]] = true
		return normalize(record)
	if event is InputEventMouseButton: return normalize(mouse(event.button_index))
	if event is InputEventJoypadButton: return normalize(pad(event.button_index))
	if event is InputEventJoypadMotion and absf(event.axis_value) > 0.5: return normalize(axis(event.axis,int(signf(event.axis_value))))
	return {}

static func to_event(record: Dictionary) -> InputEvent:
	var event: InputEvent
	match record.type:
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = int(record.physical)
			k.shift_pressed = record.get("shift",false)
			k.ctrl_pressed = record.get("ctrl",false)
			k.alt_pressed = record.get("alt",false)
			k.meta_pressed = record.get("meta",false)
			event = k
		"mouse":
			var m := InputEventMouseButton.new()
			m.button_index = int(record.button)
			event = m
		"pad":
			var p := InputEventJoypadButton.new()
			p.device = -1
			p.button_index = int(record.button)
			event = p
		"axis":
			var a := InputEventJoypadMotion.new()
			a.device = -1
			a.axis = int(record.axis)
			a.axis_value = float(record.direction)
			event = a
	return event

func _valid_list(records: Variant) -> bool:
	if not records is Array or records.size() > 32: return false
	for record in records:
		if normalize(record).is_empty(): return false
	return true

func _reserved(action: String, record: Dictionary) -> bool:
	# Reserve the physical key regardless of modifiers, in all contexts.
	if record.type == "key" and int(record.physical) == KEY_F9: return action != "bug_report"
	if record.type == "key" and int(record.physical) == KEY_ESCAPE: return action not in ["escape","pause","ui_cancel"]
	return false

static func _same(a: Dictionary, b: Dictionary) -> bool:
	return normalize(a) == normalize(b)

static func _overlap(action: String, a: Dictionary, other: String, b: Dictionary) -> bool:
	if a.type == "key" and b.type == "key" and a.physical == b.physical:
		# Native focus traversal matches Tab modifiers exactly.
		if action in ["ui_focus_next","ui_focus_prev"] and other in ["ui_focus_next","ui_focus_prev"]: return _same(a,b)
		return true
	return _same(a,b)

func conflicts(action: String, records: Array, scope: String = "", proposed: Variant = null) -> Array[String]:
	var area := scope_for(action,scope)
	if proposed == null: proposed = overrides
	var result: Array[String] = []
	for record in records:
		if _reserved(action,record):
			var reserved := "bug_report" if int(record.get("physical",0)) == KEY_F9 else "escape"
			if not result.has(reserved): result.append(reserved)
		for other in actions:
			if other == action or other == "escape": continue
			var areas: Array = actions[other].contexts.duplicate() if area == "global" else [area,"global"]
			if area == "menu" and actions[other].get("menu_active",false): areas.append_array(["2d","fps"])
			if area in ["2d","fps"] and actions[action].get("menu_active",false): areas.append("menu")
			for other_area in areas:
				if not actions[other].contexts.has(other_area): continue
				for binding in proposed.get(other_area,{}).get(other,defaults(other,other_area)):
					if record.type == "key" and int(record.physical) == KEY_ESCAPE and action in ["pause","ui_cancel"] and other in ["pause","ui_cancel"]: continue
					if _overlap(action,record,other,binding) and not result.has(other): result.append(other)
	return result

func _menu_device_error(proposed: Dictionary) -> Dictionary:
	for action in ESSENTIAL_MENU:
		var keyboard := false
		var controller := false
		for record in proposed.get("menu",{}).get(action,defaults(action,"menu")):
			keyboard = keyboard or record.type == "key"
			controller = controller or record.type in ["pad","axis"]
		if not keyboard or not controller:
			return {"ok":false,"error":"menu_device_required","action":action,"device":"keyboard" if not keyboard else "pad"}
	return {}

func load_settings(base: Dictionary = {}) -> Dictionary:
	settings = base.duplicate(true)
	warnings.clear()
	backup_required = false
	if FileAccess.file_exists(settings_path):
		var parser := JSON.new()
		if parser.parse(FileAccess.get_file_as_string(settings_path)) == OK and parser.data is Dictionary:
			settings.merge(parser.data,true)
			var envelope: Variant = settings.get(SETTINGS_KEY,{})
			if settings.has(SETTINGS_KEY) and (not envelope is Dictionary or not _integer(envelope.get("version"),VERSION,VERSION) or not envelope.get("contexts") is Dictionary):
				backup_required = true
		else:
			backup_required = true
			_warn("Corrupt settings file; using defaults (file left intact).")
	if settings.has(SETTINGS_KEY) and settings[SETTINGS_KEY] is Dictionary and settings[SETTINGS_KEY].is_empty():
		overrides.clear()
		_warn("Malformed bindings envelope; using defaults.")
	else:
		load_overrides(settings.get(SETTINGS_KEY,{}))
	return settings

func load_overrides(data: Variant) -> void:
	overrides.clear()
	if data is Dictionary and data.is_empty(): return # 0.3.2 settings
	if not data is Dictionary or not _integer(data.get("version"),VERSION,VERSION) or not data.get("contexts") is Dictionary:
		_warn("Unsupported or malformed bindings; using defaults.")
		return
	for area in data.contexts:
		if area not in SCOPES or not data.contexts[area] is Dictionary:
			_warn("Unknown or malformed context: %s" % str(area))
			continue
		overrides[area] = {}
		for action in data.contexts[area]:
			var records: Variant = data.contexts[area][action]
			if not actions.has(action) or not actions[action].contexts.has(area) or actions[action].reserved or not _valid_list(records):
				_warn("Invalid action/events: %s/%s; using defaults." % [area,action])
				continue
			var cleaned: Array = []
			for record in records: cleaned.append(normalize(record))
			var reserved := false
			for record in cleaned: reserved = reserved or _reserved(action,record)
			if reserved:
				_warn("Reserved binding: %s/%s; using defaults." % [area,action])
			else: overrides[area][action] = cleaned
	# Repair each essential action independently before considering collisions.
	for action in ESSENTIAL_MENU:
		if not overrides.get("menu",{}).has(action): continue
		var single := {"menu":{action:overrides.menu[action]}}
		var guard := _menu_device_error(single)
		if not guard.is_empty():
			_warn("Menu device missing: %s/%s; using defaults." % [action,guard.device])
			overrides.menu.erase(action)
	# Compare overrides in registry order, independent of JSON insertion order.
	# An explicit empty mask prevents defaults from rejecting a legitimate swap
	# before the other override has been considered.
	var mask := {}
	for action in actions:
		for area in actions[action].contexts:
			if not mask.has(area): mask[area] = {}
			mask[area][action] = []
	var accepted := {}
	var later_collisions: Array = []
	for action in actions:
		for area in actions[action].contexts:
			if not overrides.get(area,{}).has(action): continue
			var records: Array = overrides[area][action]
			if not conflicts(action,records,area,mask).is_empty():
				_warn("Conflicting later binding: %s/%s; using defaults." % [area,action])
				later_collisions.append([area,action])
				continue
			if not accepted.has(area): accepted[area] = {}
			accepted[area][action] = records
			mask[area][action] = records
	# A later action's fallback must not reintroduce the winning key. Retain
	# every unrelated default slot; the essential menu device minimum wins if
	# no safe fallback can preserve it.
	for pair in later_collisions:
		var area: String = pair[0]
		var action: String = pair[1]
		var fallback: Array = []
		for record in defaults(action,area):
			if conflicts(action,[record],area,mask).is_empty(): fallback.append(record)
		if fallback == defaults(action,area): continue
		var proposal := accepted.duplicate(true)
		if not proposal.has(area): proposal[area] = {}
		proposal[area][action] = fallback
		if not _menu_device_error(proposal).is_empty(): continue
		accepted = proposal
		_warn("Removed colliding fallback slots: %s/%s." % [area,action])
	overrides = accepted
	# A dropped override restores a default. Reject any override that would
	# collide with that fallback, repeating until the final installed map is safe.
	for _pass in range(actions.size()+1):
		var any_rejected := false
		for area in SCOPES:
			var rejected: Array = []
			for action in overrides.get(area,{}):
				if not conflicts(action,overrides[area][action],area).is_empty(): rejected.append(action)
			for action in rejected:
				_warn("Binding conflicts with restored default: %s/%s; using defaults." % [area,action])
				overrides[area].erase(action)
				any_rejected = true
		if not any_rejected: break

func install() -> void:
	for action in actions:
		if not InputMap.has_action(action): InputMap.add_action(action,0.2)
		Input.action_release(action)
		InputMap.action_erase_events(action)
		var area := scope_for(action)
		for record in events(action,area): InputMap.action_add_event(action,to_event(record))
	# Native selection and confirmation share one configured binding list.
	InputMap.action_erase_events("ui_select")
	for record in events("ui_accept","menu"): InputMap.action_add_event("ui_select",to_event(record))

func _write_settings(data: Dictionary) -> Dictionary:
	if backup_required and FileAccess.file_exists(settings_path):
		var backup := settings_path+".bak"
		var suffix := 1
		while FileAccess.file_exists(backup) or DirAccess.dir_exists_absolute(backup):
			backup = settings_path+".bak.%d" % suffix
			suffix += 1
		if DirAccess.copy_absolute(settings_path,backup) != OK or FileAccess.get_sha256(settings_path) != FileAccess.get_sha256(backup):
			return {"ok":false,"error":"write_failed","reason":"backup_failed"}
		backup_required = false
	var file := FileAccess.open(settings_path+".tmp",FileAccess.WRITE)
	if file == null: return {"ok":false,"error":"write_failed"}
	file.store_string(JSON.stringify(data))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(settings_path+".tmp")
		return {"ok":false,"error":"write_failed"}
	if DirAccess.rename_absolute(settings_path+".tmp",settings_path) != OK: return {"ok":false,"error":"write_failed"}
	return {"ok":true}

func save_settings() -> Dictionary:
	return _write_settings(settings)

func _commit(next: Dictionary) -> Dictionary:
	var data := settings.duplicate(true)
	data[SETTINGS_KEY] = {"version":VERSION,"contexts":next}
	var saved := _write_settings(data)
	if not saved.ok: return saved
	overrides = next
	settings[SETTINGS_KEY] = data[SETTINGS_KEY]
	install()
	changed.emit()
	return {"ok":true}

# Replacement applies to the whole action, across input devices. Swap exchanges
# complete binding lists with one conflicting action; never mutates on refusal.
func set_bindings(action: String, records: Array, policy := "refuse", scope: String = "") -> Dictionary:
	var area := scope_for(action,scope)
	if not actions.has(action) or not actions[action].contexts.has(area): return {"ok":false,"error":"unknown_action"}
	if actions[action].reserved: return {"ok":false,"error":"reserved"}
	if policy not in ["refuse","swap"] or not _valid_list(records): return {"ok":false,"error":"malformed_events"}
	var cleaned: Array = []
	for record in records:
		var value := normalize(record)
		if _reserved(action,value): return {"ok":false,"error":"reserved","conflicts":conflicts(action,[value],area)}
		if not cleaned.has(value): cleaned.append(value)
	var collision := conflicts(action,cleaned,area)
	if not collision.is_empty() and (policy != "swap" or collision.size() != 1 or actions[collision[0]].reserved or not actions[collision[0]].contexts.has(area)):
		return {"ok":false,"error":"conflict","conflicts":collision}
	var next := overrides.duplicate(true)
	if not next.has(area): next[area] = {}
	if not collision.is_empty(): next[area][collision[0]] = events(action,area)
	next[area][action] = cleaned
	for id in next[area]:
		var remaining := conflicts(id,next[area][id],area,next)
		if not remaining.is_empty(): return {"ok":false,"error":"conflict","conflicts":remaining}
	var guard := _menu_device_error(next)
	if not guard.is_empty(): return guard
	return _commit(next)

func add_binding(action: String, record: Dictionary, policy := "refuse", scope: String = "") -> Dictionary:
	if policy not in ["refuse","swap"]: return {"ok":false,"error":"malformed_events"}
	var records := events(action,scope)
	records.append(record)
	# Adding has no old slot to exchange. A collision is always a refusal.
	return set_bindings(action,records,"refuse",scope)

func replace_binding(action: String, index: int, record: Dictionary, policy := "refuse", scope: String = "") -> Dictionary:
	var area := scope_for(action,scope)
	if not actions.has(action) or not actions[action].contexts.has(area): return {"ok":false,"error":"unknown_action"}
	if actions[action].reserved: return {"ok":false,"error":"reserved"}
	var records := events(action,area)
	if index < 0 or index >= records.size(): return {"ok":false,"error":"invalid_index"}
	var value := normalize(record)
	if value.is_empty() or policy not in ["refuse","swap"]: return {"ok":false,"error":"malformed_events"}
	if _reserved(action,value): return {"ok":false,"error":"reserved"}
	var old: Dictionary = records[index]
	records[index] = value
	var collision := conflicts(action,[value],area)
	if policy == "refuse" or collision.is_empty(): return set_bindings(action,records,"refuse",area)
	if collision.size() != 1 or actions[collision[0]].reserved or not actions[collision[0]].contexts.has(area):
		return {"ok":false,"error":"conflict","conflicts":collision}
	var other: String = collision[0]
	var other_records := events(other,area)
	var indices: Array[int] = []
	for slot in range(other_records.size()):
		if _overlap(action,value,other,other_records[slot]): indices.append(slot)
	if indices.size() != 1: return {"ok":false,"error":"conflict","conflicts":collision}
	if _reserved(other,old): return {"ok":false,"error":"reserved"}
	other_records[indices[0]] = old
	var next := overrides.duplicate(true)
	if not next.has(area): next[area] = {}
	next[area][action] = records
	next[area][other] = other_records
	for id in next[area]:
		var remaining := conflicts(id,next[area][id],area,next)
		if not remaining.is_empty(): return {"ok":false,"error":"conflict","conflicts":remaining}
	var guard := _menu_device_error(next)
	if not guard.is_empty(): return guard
	return _commit(next)

func remove_binding(action: String, index: int, scope: String = "") -> Dictionary:
	if not actions.has(action) or not actions[action].contexts.has(scope_for(action,scope)): return {"ok":false,"error":"unknown_action"}
	if actions[action].reserved: return {"ok":false,"error":"reserved"}
	var records := events(action,scope)
	if index < 0 or index >= records.size(): return {"ok":false,"error":"invalid_index"}
	records.remove_at(index)
	return set_bindings(action,records,"refuse",scope)

func reset_action(action: String, policy := "refuse", scope: String = "") -> Dictionary:
	if not actions.has(action): return {"ok":false,"error":"unknown_action"}
	return set_bindings(action,defaults(action,scope),policy,scope)

func reset_all() -> Dictionary:
	return _commit({})

func gameplay_actions() -> Array[String]:
	var result: Array[String] = []
	for action in actions:
		if actions[action].contexts.has(context) and action not in ["escape","bug_report","fullscreen"]: result.append(action)
	return result

static func key_display_name(code: int) -> String:
	var names := {
		KEY_KP_ENTER:"Numpad Enter", KEY_KP_MULTIPLY:"Numpad ×", KEY_KP_DIVIDE:"Numpad /",
		KEY_KP_SUBTRACT:"Numpad −", KEY_KP_ADD:"Numpad +", KEY_KP_PERIOD:"Numpad .",
		KEY_BACKTAB:"Shift+Tab", KEY_PRINT:"Print Screen", KEY_CAPSLOCK:"Caps Lock",
		KEY_NUMLOCK:"Num Lock", KEY_SCROLLLOCK:"Scroll Lock", KEY_PAGEUP:"Page Up", KEY_PAGEDOWN:"Page Down",
		KEY_VOLUMEDOWN:"Volume down", KEY_VOLUMEUP:"Volume up", KEY_VOLUMEMUTE:"Mute",
		KEY_MEDIAPLAY:"Media play", KEY_MEDIASTOP:"Media stop", KEY_MEDIAPREVIOUS:"Previous track",
		KEY_MEDIANEXT:"Next track", KEY_MEDIARECORD:"Media record", KEY_HOMEPAGE:"Browser home",
		KEY_BACK:"Browser back", KEY_FORWARD:"Browser forward", KEY_REFRESH:"Browser refresh",
		KEY_STOP:"Browser stop", KEY_SEARCH:"Search", KEY_FAVORITES:"Favorites",
		KEY_LAUNCHMAIL:"Open mail", KEY_LAUNCHMEDIA:"Open media", KEY_STANDBY:"Sleep",
		KEY_GLOBE:"Globe", KEY_KEYBOARD:"Keyboard", KEY_JIS_EISU:"Eisu", KEY_JIS_KANA:"Kana"
	}
	if names.has(code): return names[code]
	if code >= KEY_KP_0 and code <= KEY_KP_9: return "Numpad %d" % (code-KEY_KP_0)
	if code >= KEY_LAUNCH0 and code <= KEY_LAUNCHF: return "Application key %d" % (code-KEY_LAUNCH0+1)
	var text := OS.get_keycode_string(code)
	# Future engine identifiers must not leak camel-case/raw tokens to players.
	if text.is_empty(): return "Key 0x%X" % code
	for i in range(1,text.length()):
		if text[i] == text[i].to_upper() and text[i] != text[i].to_lower() and text[i-1] != text[i-1].to_upper():
			return "Key 0x%X" % code
	return text

static func is_modifier(record: Dictionary) -> bool:
	return record.get("type","") == "key" and int(record.get("physical",0)) in [KEY_SHIFT,KEY_CTRL,KEY_ALT,KEY_META]

static func event_label(record: Dictionary) -> String:
	if record.type == "key":
		var code := int(record.physical)
		if DisplayServer.get_name() != "headless":
			var local := DisplayServer.keyboard_get_label_from_physical(code)
			if local != 0: code = local
		var label := key_display_name(code)
		for modifier in ["shift","ctrl","alt","meta"]:
			if record.get(modifier,false): label = modifier.capitalize()+"+"+label
		return label
	if record.type == "mouse":
		return {1:"Left click",2:"Right click",3:"Middle click",4:"Wheel up",5:"Wheel down",6:"Wheel left",7:"Wheel right",8:"Mouse 4",9:"Mouse 5"}.get(int(record.button),"Mouse %d" % int(record.button))
	if record.type == "pad":
		return {JOY_BUTTON_A:"A",JOY_BUTTON_B:"B",JOY_BUTTON_X:"X",JOY_BUTTON_Y:"Y",JOY_BUTTON_BACK:"Back",JOY_BUTTON_START:"Start",JOY_BUTTON_LEFT_STICK:"LS click",JOY_BUTTON_RIGHT_STICK:"RS click",JOY_BUTTON_LEFT_SHOULDER:"LB",JOY_BUTTON_RIGHT_SHOULDER:"RB",JOY_BUTTON_DPAD_UP:"D-pad up",JOY_BUTTON_DPAD_DOWN:"D-pad down",JOY_BUTTON_DPAD_LEFT:"D-pad left",JOY_BUTTON_DPAD_RIGHT:"D-pad right"}.get(int(record.button),"Pad %d" % int(record.button))
	var axis_id := int(record.axis)
	var direction := int(record.direction)
	if axis_id in [JOY_AXIS_LEFT_X,JOY_AXIS_LEFT_Y,JOY_AXIS_RIGHT_X,JOY_AXIS_RIGHT_Y]:
		var stick := "LS" if axis_id in [JOY_AXIS_LEFT_X,JOY_AXIS_LEFT_Y] else "RS"
		var horizontal := axis_id in [JOY_AXIS_LEFT_X,JOY_AXIS_RIGHT_X]
		return stick + " " + (("left" if direction < 0 else "right") if horizontal else ("up" if direction < 0 else "down"))
	if axis_id in [JOY_AXIS_TRIGGER_LEFT,JOY_AXIS_TRIGGER_RIGHT]:
		return ("LT" if axis_id == JOY_AXIS_TRIGGER_LEFT else "RT") + (" release" if direction < 0 else " press")
	return "Pad axis %d %s" % [axis_id+1, "−" if direction < 0 else "+"]

func label(action: String, controller := false, scope: String = "", all_devices := false) -> String:
	var preferred: Array[String] = []
	var fallback: Array[String] = []
	for record in events(action,scope):
		var text := event_label(record)
		if not fallback.has(text): fallback.append(text)
		if all_devices or (record.type in ["pad","axis"]) == controller:
			if not preferred.has(text): preferred.append(text)
	return " / ".join(preferred if not preferred.is_empty() else fallback) if not fallback.is_empty() else "Unbound"

# Compact strips name the first binding on the active device, with a fallback
# to the other device when an action was deliberately moved across devices.
func short_label(action: String, controller := false) -> String:
	return label(action,controller).split(" / ")[0]

func movement_label(controller := false) -> String:
	var labels: Array[String] = []
	for id in ["up","left","down","right"]: labels.append(short_label(id,controller))
	if controller and labels.all(func(value: String): return value.begins_with("LS")): return "LS"
	return "".join(labels) if labels.all(func(value: String): return value.length() == 1) else "/".join(labels)

func look_label(controller := true, all_devices := false) -> String:
	var ids := ["look_left","look_right","look_up","look_down"]
	var original_stick := true
	for id in ids: original_stick = original_stick and events(id) == defaults(id)
	if original_stick: return "RS"
	var parts: Array[String] = []
	for id in ids:
		parts.append("%s %s" % [actions[id].name.trim_prefix("Look "),label(id,controller,"",all_devices)])
	return ", ".join(parts)
