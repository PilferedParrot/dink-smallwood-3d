extends SceneTree
# Labelled scenarios: source maps/placements, startup and campaign skipped.
# Held PUSH uses real physical input; talk/hit/touch controls enter the actual
# sprite-event dispatcher with a synthetic NPC procedure to expose old tails.
class TickProbe extends Node:
	signal done
	func _physics_process(_delta: float) -> void: done.emit()
class ObservedFPS extends "res://scripts/fps_game.gd":
	var dispatches: Array = []
	var lines: Array = []
	var max_instance_tasks := 0
	func _run_event(id: int, event: String) -> void:
		if event == "push" and entities.has(id) and not vm._procedure_code(str(entities[id].get("script","")),event).is_empty():
			dispatches.append({"id":id,"script":entities[id].script,"ms":Time.get_ticks_msec()})
		super._run_event(id,event)
		var count := 0
		for task in vm._live_tasks:
			if vm._task_sprite(int(task)) == id: count += 1
		max_instance_tasks = maxi(max_instance_tasks,count)
	func _record_dialogue(line: String, speaker_name: String = "") -> void:
		lines.append({"text":line,"ms":Time.get_ticks_msec(),"dispatch_count":dispatches.size()})
		super._record_dialogue(line,speaker_name)
var game
var probe: TickProbe
var failures: Array[String] = []
var records: Array = []
var report_path := ""
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report_path=arg.trim_prefix("--report=")
	_run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); push_error(message)
func ticks(count: int) -> void:
	for _i in count: await probe.done
func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new(); event.physical_keycode=code; event.pressed=pressed
	Input.parse_input_event(event); Input.flush_buffered_events()
func target(script: String) -> int:
	for id in game.entities:
		if game.entities[id].get("script","") == script: return id
	return 0
func prepare(screen: int, vision: int = 0, strength: int = 4) -> void:
	await game._new_game(); game.vm.cancel_all(); game.ui.cancel_speech(); game.ui.close_menu()
	game.vm.globals.merge({"vision":vision,"strength":strength,"story":0,"rock_placement":0,"caveguy":0},true)
	game.load_map(screen,false); game.vm.cancel_all(); game.ui.cancel_speech()
	game.entities[1].nocontrol=0; game.entities[1].frozen=false
	game.playing=true; game.changing=false; game.attack_cooldown=0.0; game.warp_cooldown=0.0
	game.dispatches.clear(); game.lines.clear(); game.dialogue_log.clear(); game.max_instance_tasks=0
func held_case(script: String, screen: int, vision: int, weak: bool = false) -> void:
	await prepare(screen,vision,3 if weak else 4)
	var id := target(script)
	check(id != 0,script+": source placement exists")
	if id == 0: return
	var rect: Rect2=game._hard_rect(game.entities[id])
	var approach: Array=[]
	for fraction in [0.5,0.25,0.75]:
		var candidates := [
			[Vector2(rect.position.x-5,lerpf(rect.position.y,rect.end.y,fraction)),KEY_D],
			[Vector2(rect.end.x+5,lerpf(rect.position.y,rect.end.y,fraction)),KEY_A],
			[Vector2(lerpf(rect.position.x,rect.end.x,fraction),rect.end.y+5),KEY_W],
			[Vector2(lerpf(rect.position.x,rect.end.x,fraction),rect.position.y-5),KEY_S]]
		# A northward rock push leaves it in place, avoiding earned cave entry.
		# The successful eastward moving branch already has its separate gate.
		if script == "s1-roc": candidates=[candidates[2],candidates[3]]
		for candidate in candidates:
			if not game._blocked(candidate[0],1): approach=candidate; break
		if not approach.is_empty(): break
	check(not approach.is_empty(),script+": free source approach")
	if approach.is_empty(): return
	game.entities[1].x=approach[0].x; game.entities[1].y=approach[0].y
	game.fps_yaw=0; game._sync_fps_camera()
	key(approach[1],true)
	var max_tasks := 0
	for _i in Engine.physics_ticks_per_second*5:
		await ticks(1)
		max_tasks=maxi(max_tasks,game.vm._live_tasks.size())
	key(approach[1],false); await ticks(1)
	# Finish the last table wait and let replacement-speech continuations settle.
	await create_timer(0.6).timeout; await ticks(2)
	var events: Array=game.dispatches.duplicate(true)
	var lines: Array=game.lines.duplicate(true)
	var expected: String={"s1-roc":"It's too heavy for me." if weak else "It won't budge from this angle.", "s1-h1-4":"This table must be bolted", "s2-idol":"Uh, darn thing won't budge!!", "s3-rock":"Ugh, stupid rocks."}[script]
	check(not events.is_empty(),script+": five-second hold dispatches source PUSH")
	check(game.max_instance_tasks <= 1,script+": repeated PUSH never stacks a sprite script's continuation")
	check(not lines.is_empty(),script+": original PUSH emits dialogue")
	for line in lines:
		check(expected in str(line.text),script+": recent_dialogue contains only the authored branch")
	if script == "s1-h1-4":
		for line in lines:
			var latest := 0
			for event in events:
				if int(event.ms) <= int(line.ms): latest=maxi(latest,int(event.ms))
			check(int(line.ms)-latest >= 500-1000.0/Engine.physics_ticks_per_second,
				"Table speech cannot resume an older500ms wait after re-entry")
	else:
		check(lines.size()==events.size(),script+": each located PUSH executes its one authored speech line")
	check(game.dialogue_log.size()==lines.size(),script+": recent_dialogue and observed line trace agree")
	records.append({"script":script,"weak":weak,"held_frames":Engine.physics_ticks_per_second*5,
		"dispatches":events,"recent_dialogue":game.dialogue_log.duplicate(),"line_events":lines,
		"max_vm_live_tasks":max_tasks,"max_instance_tasks":game.max_instance_tasks,
		"vm_live_tasks":game.vm._live_tasks.size()})
func literal(value: Variant) -> Dictionary: return {"kind":"literal","value":value}
func event_controls() -> void:
	await prepare(1)
	var npc := target("s1-h1-m")
	check(npc != 0,"Source mother NPC exists for event-entry controls")
	if npc == 0: return
	# One shared local survives re-entry; only the newest wait may run its tail.
	game.vm.story.scripts["event-reentry-fixture"]={"procedures":{}}
	for event in ["talk","hit","touch"]:
		game.vm.story.scripts["event-reentry-fixture"].procedures[event]={"code":[
			{"op":"inc","target":"&entered","value":literal(1)},
			{"op":"call","name":"say_stop","args":[literal("NPC waiting during "+event),literal(npc)]},
			{"op":"inc","target":"&finished","value":literal(1)}]}
	game.entities[npc].script="event-reentry-fixture"
	for event in ["talk","hit","touch"]:
		game.vm.cancel_all(); game.ui.cancel_speech(); await ticks(2)
		game.vm.clear_sprite_locals(npc)
		var locals: Dictionary=game.vm._locals_for("event-reentry-fixture",npc)
		locals.entered=0; locals.finished=0
		game._run_event(npc,event); game._run_event(npc,event)
		var live: int=game.vm._live_tasks.size()
		check(live==1,event+": re-entry restarts one live NPC continuation")
		check(locals.entered==2,event+": both entries execute and preserve script locals")
		game.ui.cancel_speech()
		for _i in Engine.physics_ticks_per_second:
			await ticks(1)
			if game.vm._live_tasks.is_empty(): break
		check(locals.finished==1,event+": only the newest continuation reaches its tail")
		check(game.vm._live_tasks.is_empty(),event+": no leftover VM task after newest speech ends")
		records.append({"event":event,"live_after_reentry":live,"locals":locals.duplicate(true)})
var external_finished := 0
func external_probe(npc: int) -> void:
	await game.dink_call("external",["event-reentry-fixture","external-wait"],{"sprite_id":npc})
	external_finished += 1
func independent_controls() -> void:
	game.vm.cancel_all(); game.ui.cancel_speech(); await ticks(3)
	var npc := target("event-reentry-fixture")
	var other := 900001
	game.entities[other]={"script":"event-reentry-fixture","active":1,"type":1}
	var procedures: Dictionary=game.vm.story.scripts["event-reentry-fixture"].procedures
	procedures["sleep"]={"code":[
		{"op":"set","target":"&kept","expr":{"kind":"call","name":"wait","args":[literal(400)]}},
		{"op":"inc","target":"&completion","value":literal(1)}]}
	procedures["external-wait"]={"code":[
		{"op":"set","target":"&private_marker","expr":literal(17),"declare":"int"},
		{"op":"call","name":"wait","args":[literal(300)]}]}
	procedures["main"]={"code":[
		{"op":"call","name":"script_attach","args":[literal(npc)]},
		{"op":"set","target":"&private_marker","expr":literal(19),"declare":"int"},
		{"op":"call","name":"wait","args":[literal(350)]}]}
	game.vm.story.scripts["independent-script"]={"procedures":{"sleep":procedures.sleep.duplicate(true)}}
	var own: Dictionary=game.vm._locals_for("event-reentry-fixture",npc)
	var theirs: Dictionary=game.vm._locals_for("event-reentry-fixture",other)
	var second: Dictionary=game.vm._locals_for("independent-script",npc)
	own.completion=0; own.kept=41; own.private_marker=41; theirs.completion=0; second.completion=0
	game.vm.run("event-reentry-fixture","sleep",npc)
	game.vm.run("event-reentry-fixture","sleep",other)
	game.vm.run("independent-script","sleep",npc)
	external_probe(npc)
	await game.dink_call("spawn",["event-reentry-fixture"],{})
	game._run_event(npc,"talk")
	check(game.vm._live_tasks.size()==5,"Re-entry preserves another owner, another script, external and spawned instances")
	check(own.private_marker==41,"External/spawn locals do not overwrite the sprite instance's locals")
	# A failed procedure lookup must preserve the existing cursor/continuation.
	game.vm.run("event-reentry-fixture","missing-procedure",npc)
	check(game.vm._live_tasks.size()==5,"A missing procedure does not cancel a valid live event")
	game.ui.cancel_speech(); await create_timer(0.65).timeout; await ticks(3)
	check(own.completion==0 and own.kept==41,"Replaced timer cannot run its old tail or overwrite replacement locals with a cancelled result")
	check(theirs.completion==1 and second.completion==1,"Other owners and scripts retain their own continuations")
	check(external_finished==1,"External finishes independently when its owning sprite re-enters a procedure")
	check(game.vm._live_tasks.is_empty(),"All independent controls drain their VM tasks")
	records.append({"control":"independent-instances","own":own.duplicate(true),"other":theirs.duplicate(true),
		"second_script":second.duplicate(true),"external_finished":external_finished})
func spawned_local_control() -> void:
	game.vm.story.scripts["spawned-local-control"]={"procedures":{
		"main":{"code":[
			{"op":"set","target":"&saved_local","expr":literal(9),"declare":"int"},
			{"op":"call","name":"set_callback_random","args":[literal("again"),literal(100),literal(100)]}]},
		"again":{"code":[
			{"op":"inc","target":"&saved_local","value":literal(1)},
			{"op":"set","target":"&spawn_observed","expr":{"kind":"ref","name":"&saved_local"}}]}}}
	await game.dink_call("spawn",["spawned-local-control"],{})
	await create_timer(0.3).timeout; await ticks(2)
	check(game.vm.globals.get("spawn_observed",0)==10,"Spawned instance retains its locals across a named callback")
	records.append({"control":"spawned-locals","observed":game.vm.globals.get("spawn_observed",0)})
func _run() -> void:
	probe=TickProbe.new(); probe.process_physics_priority=100; root.add_child(probe)
	game=ObservedFPS.new(); root.add_child(game); await process_frame
	for fixture in [["s1-roc",277,0],["s1-h1-4",1,0],["s2-idol",579,0],["s3-rock",590,1]]:
		await held_case(fixture[0],fixture[1],fixture[2])
	await held_case("s1-roc",277,0,true)
	await event_controls()
	await independent_controls()
	await spawned_local_control()
	game.vm.cancel_all(); game.ui.cancel_speech(); game.queue_free(); await process_frame
	if not report_path.is_empty():
		var file:=FileAccess.open(report_path,FileAccess.WRITE)
		file.store_string(JSON.stringify({"setup":"Scenario maps/startup skipped; real held PUSH input; injected NPC event procedures for continuation controls","records":records,"failures":failures},"  ")); file.close()
	print("PUSH REENTRY PASS" if failures.is_empty() else "PUSH REENTRY FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
