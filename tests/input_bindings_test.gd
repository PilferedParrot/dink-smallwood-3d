extends SceneTree

var registry_script = preload("res://scripts/input_bindings.gd")
var failures: Array[String] = []
var seen: Array[String] = []
var watching := ""
var phase := ""

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="): phase = arg.trim_prefix("--phase=")
		if arg.begins_with("--registry="): registry_script = load(arg.trim_prefix("--registry="))
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var observer := Node.new()
	observer.set_script(load(get_script().resource_path.get_base_dir()+"/input_observer.gd"))
	observer.owner_tree = self
	root.add_child(observer)
	match phase:
		"write", "read": await table()
		"robustness": await robustness()
	if failures.is_empty(): print("BINDINGS PASS "+phase)
	else: print("BINDINGS FAIL "+phase+": "+str(failures.size()))
	quit(0 if failures.is_empty() else 1)

func inject(record: Dictionary, pressed: bool) -> void:
	var event: InputEvent = registry_script.to_event(record)
	if event is InputEventJoypadMotion:
		event.device = 3
		if not pressed: event.axis_value = 0.0
	else:
		event.pressed = pressed
		if event is InputEventJoypadButton: event.device = 3
		if event is InputEventKey: event.keycode = event.physical_keycode
	Input.parse_input_event(event)
	await process_frame
	await physics_frame

func table() -> void:
	var specimen = registry_script.new()
	var rows := 0
	for action in specimen.actions:
		if specimen.actions[action].reserved: continue
		for scope in specimen.actions[action].contexts:
			var mode := "2d" if scope == "2d" else "fps"
			var path := "user://table-%s-%s.json" % [scope,action]
			var b = registry_script.new(mode,path)
			b.load_settings({"music":0.33,"sentinel":"keep me"})
			if phase == "write":
				check(b.reset_action(action,"refuse",scope).ok,"Reset default bindings "+scope+"/"+action)
				var replacement := [registry_script.key(KEY_F13)]
				if scope == "menu" and action in b.ESSENTIAL_MENU: replacement.append(registry_script.pad(JOY_BUTTON_PADDLE1))
				check(b.set_bindings(action,replacement,"refuse",scope).ok,"Persist "+scope+"/"+action)
			else:
				b.install()
				watching = action
				seen.clear()
				await inject(registry_script.key(KEY_F13),true)
				check(seen.has(action) and Input.is_action_pressed(action),"Restart real input "+scope+"/"+action)
				await inject(registry_script.key(KEY_F13),false)
				for old in b.defaults(action,scope):
					seen.clear()
					await inject(old,true)
					check(not seen.has(action) and not Input.is_action_pressed(action),"Old default inactive "+scope+"/"+action+" "+str(old))
					await inject(old,false)
				check(b.settings.music == 0.33 and b.settings.sentinel == "keep me","Preserve unrelated settings")
				rows += 1
	print("TABLE_ROWS="+str(rows))

func write(path: String, value: String) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(value)
	file.close()

func robustness() -> void:
	var b = registry_script.new("fps","user://robustness.json")
	write(b.settings_path,"broken json")
	b.load_settings()
	check(not b.warnings.is_empty() and b.events("attack") == b.defaults("attack"),"Corrupt file warns and defaults")
	check(FileAccess.get_file_as_string(b.settings_path) == "broken json","Corrupt file preserved")
	var legacy := JSON.stringify({"music":0.55,"text_scale":1.2,"custom":"old"})
	write(b.settings_path,legacy)
	b.load_settings()
	check(b.warnings.is_empty() and b.settings.music == 0.55 and b.settings.text_scale == 1.2,"0.3.2 settings unchanged")
	check(FileAccess.get_file_as_string(b.settings_path) == legacy,"0.3.2 load leaves file bytes unchanged")
	var data := {"version":1,"contexts":{"fps":{"attack":[registry_script.key(KEY_K)],"unknown":[registry_script.key(KEY_J)],"talk":[{"type":"key","physical":"oops"}],"jump":false},"lost":{}}}
	write(b.settings_path,JSON.stringify({"music":0.44,"bindings_v1":data}))
	b.load_settings()
	check(b.events("attack") == [registry_script.key(KEY_K)],"Malformed neighbors do not discard valid override")
	check(b.events("talk") == b.defaults("talk") and b.events("jump") == b.defaults("jump"),"Malformed actions default separately")
	check(b.warnings.size() == 4,"Each malformed/unknown record warns")
	write(b.settings_path,JSON.stringify({"bindings_v1":{}}))
	b.load_settings()
	check(not b.warnings.is_empty(),"Explicit empty persisted envelope warns")
	for invalid in [null,[],42,"oops",{"version":2,"contexts":{}},{"version":true,"contexts":{}},{"version":"1","contexts":{}},{"version":null,"contexts":{}},{"version":1,"contexts":[]}]:
		b.load_overrides(invalid)
		check(b.events("attack") == b.defaults("attack"),"Malformed envelope defaults")
	for invalid in [null,[],{}, {"type":"key","physical":-1},{"type":"key","physical":0},{"type":"key","physical":1.5},{"type":"key","physical":97},{"type":"key","physical":KEY_K,"shift":"yes"},{"type":"mouse","button":99},{"type":"pad","button":-1},{"type":"axis","axis":1,"direction":0},{"type":"object","resource":"evil"}]:
		check(registry_script.normalize(invalid).is_empty(),"Reject malformed event "+str(invalid))
	check(not registry_script.normalize(registry_script.key(KEY_SECTION)).is_empty(),"Non-ASCII named physical keys remain valid")
	b.load_overrides({})
	check(b.set_bindings("attack",[registry_script.key(KEY_K)]).ok,"Set attack K")
	var before: String = FileAccess.get_file_as_string(b.settings_path)
	var refusal: Dictionary = b.set_bindings("talk",[registry_script.key(KEY_K)])
	check(not refusal.ok and refusal.conflicts.has("attack"),"Overlapping context conflict returned")
	check(FileAccess.get_file_as_string(b.settings_path) == before,"Refusal leaves disk unchanged")
	check(b.set_bindings("talk",[registry_script.key(KEY_K)],"swap").ok,"Swap supported")
	check(b.events("attack") == b.defaults("talk") and b.events("talk") == [registry_script.key(KEY_K)],"Swap entire action event lists")
	var restarted = registry_script.new("fps",b.settings_path)
	restarted.load_settings()
	check(restarted.events("talk") == [registry_script.key(KEY_K)] and restarted.events("attack") == b.defaults("talk"),"Swapped bindings survive restart")
	check(b.set_bindings("ui_accept",[registry_script.key(KEY_K),registry_script.pad(JOY_BUTTON_PADDLE1)]).ok,"Disjoint menu/gameplay contexts can share with both essential devices")
	check(not b.set_bindings("fullscreen",[registry_script.key(KEY_K)]).ok,"Global binding overlaps menus and gameplay")
	for keycode in [KEY_ESCAPE,KEY_F9]:
		check(not b.set_bindings("magic",[registry_script.key(keycode)]).ok,"Reserved key cannot be taken")
	check(not b.set_bindings("bug_report",[registry_script.key(KEY_K)]).ok,"Reserved action cannot be remapped")
	check(not b.set_bindings("escape",[]).ok,"Guaranteed exit cannot be unbound")
	check(b.reset_all().ok,"Reset all")
	for reserved_menu_binding in [registry_script.key(KEY_M),registry_script.pad(JOY_BUTTON_START)]:
		var menu_collision: Dictionary = b.set_bindings("ui_accept",[reserved_menu_binding])
		check(not menu_collision.ok and menu_collision.error == "conflict","Map/pause overlap with menu confirmation")
	check(b.reset_action("ui_cancel").ok,"Intentional Escape alias can reset")
	check(b.set_bindings("attack",[registry_script.mouse(MOUSE_BUTTON_MIDDLE)]).ok,"Mouse remapping")
	check(b.reset_action("attack").ok and b.events("attack") == b.defaults("attack"),"Reset one")
	check(b.set_bindings("talk",[registry_script.pad(JOY_BUTTON_B)]).ok,"Pad remapping")
	var pad_restart = registry_script.new("fps",b.settings_path)
	pad_restart.load_settings()
	check(pad_restart.events("talk") == [registry_script.pad(JOY_BUTTON_B)],"Pad persists")
	if OS.has_feature("linux"):
		var full = registry_script.new("fps","user://short-write.json")
		write(full.settings_path,JSON.stringify({"music":0.7}))
		full.load_settings()
		var dir := DirAccess.open("user://")
		check(dir.create_link("/dev/full",ProjectSettings.globalize_path(full.settings_path+".tmp")) == OK,"Short-write fixture uses an isolated symlink")
		var short_write: Dictionary = full.set_bindings("attack",[registry_script.key(KEY_K)])
		check(not short_write.ok and full.events("attack") == full.defaults("attack"),"Short write leaves live bindings unchanged")
		check(JSON.parse_string(FileAccess.get_file_as_string(full.settings_path)).music == 0.7,"Short write preserves previous settings file")
	b.settings_path = "user://nonexistent-folder/settings.json"
	var disk_failure: Dictionary = b.set_bindings("attack",[registry_script.key(KEY_K)])
	check(not disk_failure.ok and disk_failure.error == "write_failed" and b.events("attack") == b.defaults("attack"),"Write failure is transactional")
