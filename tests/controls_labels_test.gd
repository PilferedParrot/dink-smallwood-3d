# UI label census; synthetic binding records bypass gameplay collision setup.
# This gate certifies names, not gameplay dispatch or scrolling reachability.
extends SceneTree
const UI = preload("res://scripts/game_ui.gd")
const B = preload("res://scripts/input_bindings.gd")
var failures: Array[String] = []
var count := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); push_error(message)
func acceptable(text: String) -> bool:
	var raw := RegEx.new()
	raw.compile("(?i)(launch[0-9a-f]|mediaplay|mediastop|medianext|mediaprevious|volumedown|volumeup|volumemute|kp_|joy_axis|joy_button|pageup|pagedown)")
	return not text.is_empty() and raw.search(text) == null
func run() -> void:
	root.size = Vector2i(1280,800)
	var ui := UI.new()
	root.add_child(ui)
	ui.set_text_scale(1.3)
	ui.show_settings({})
	ui.show_controls()
	for i in 4: await process_frame
	var samples: Array = []
	for code in range(KEY_F13,KEY_F24+1):
		check(B.event_label(B.key(code)) == "F%d" % (13+code-KEY_F13),"Function key is readable")
		samples.append(B.key(code))
	for code in range(KEY_LAUNCH0,KEY_LAUNCHF+1):
		check(B.event_label(B.key(code)) == "Application key %d" % (code-KEY_LAUNCH0+1),"Application key is readable")
		samples.append(B.key(code))
	for code in [KEY_MEDIAPLAY,KEY_MEDIASTOP,KEY_MEDIAPREVIOUS,KEY_MEDIANEXT,KEY_MEDIARECORD,KEY_VOLUMEDOWN,KEY_VOLUMEUP,KEY_VOLUMEMUTE,KEY_KP_ENTER,KEY_PAGEUP,KEY_PAGEDOWN]: samples.append(B.key(code))
	for axis in range(JOY_AXIS_MAX):
		for direction in [-1,1]: samples.append(B.axis(axis,direction))
	for event in samples:
		check(acceptable(B.event_label(event)),"Unusual label is readable: "+str(event))
	for area in B.SCOPES:
		for unusual in [false,true]:
			ui.bindings.overrides.clear()
			if unusual:
				ui.bindings.overrides[area] = {}
				for id in ui.bindings.actions:
					if ui.bindings.actions[id].contexts.has(area):
						ui.bindings.overrides[area][id] = [B.key(KEY_LAUNCH7),B.key(KEY_F24),B.key(KEY_MEDIAPLAY),B.key(KEY_VOLUMEUP),B.axis(JOY_AXIS_LEFT_X,-1),B.axis(JOY_AXIS_LEFT_Y,1),B.axis(JOY_AXIS_TRIGGER_RIGHT,1)]
			ui.controls_menu._select_group(area)
			for i in 3: await process_frame
			for id in ui.bindings.actions:
				if not ui.bindings.actions[id].contexts.has(area): continue
				check(acceptable(ui.bindings.label(id,false,area,true)),"Registry action label: "+area+"/"+id)
				var records: Array = ui.bindings.events(id,area)
				for index in records.size():
					var button: Button = ui.controls_menu.buttons[id+"_"+str(index)]
					check(acceptable(button.text),"Actual slot button label: "+area+"/"+id)
					count += 1
	check(B.event_label(B.axis(JOY_AXIS_LEFT_X,-1)) != B.event_label(B.axis(JOY_AXIS_LEFT_Y,-1)),"Horizontal and vertical pad directions have distinct labels")
	print("CONTROLS LABELS "+("PASS" if failures.is_empty() else "FAIL")+" slots="+str(count)+" unusual="+str(samples.size()))
	ui.queue_free()
	for i in 3: await process_frame
	quit(0 if failures.is_empty() else 1)
