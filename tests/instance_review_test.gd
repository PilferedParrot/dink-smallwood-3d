extends SceneTree
# Review controls: labelled injected item/NPC procedures on source maps; setup
# skips progression. Every attempted use/event/choice confirmation is real input.
# FreeDink109.6 brain_keyboard.cpp:298-300 reuses weapon_script for USE;
# :219-220 gates player actions for choices before talk/weapon/magic dispatch.
class TickProbe extends Node:
	signal done
	func _physics_process(_delta: float) -> void: done.emit()
class Probe2D extends "res://scripts/game.gd":
	var talks := 0
	var attacks := 0
	var casts := 0
	func _talk() -> void: talks+=1; super._talk()
	func _attack() -> void: attacks+=1; super._attack()
	func _cast() -> void: casts+=1; super._cast()
class ProbeFPS extends "res://scripts/fps_game.gd":
	var talks := 0
	var attacks := 0
	var casts := 0
	func _talk() -> void: talks+=1; super._talk()
	func _fps_attack() -> void: attacks+=1; super._fps_attack()
	func _cast() -> void: casts+=1; super._cast()
var game
var probe: TickProbe
var failures: Array[String] = []
var records: Array = []
var report_path := ""
var selected := "all"
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report_path=arg.trim_prefix("--report=")
		if arg.begins_with("--case="): selected=arg.trim_prefix("--case=")
	_run.call_deferred()
func check(ok: bool, text: String) -> void:
	if not ok: failures.append(text); push_error(text)
func ticks(count: int) -> void:
	for _i in count: await probe.done
func key(code: Key, pressed: bool) -> void:
	var event:=InputEventKey.new(); event.physical_keycode=code; event.pressed=pressed
	Input.parse_input_event(event); Input.flush_buffered_events()
func tap(code: Key) -> void:
	key(code,true); await ticks(1); key(code,false); await ticks(1)
func literal(value: Variant) -> Dictionary: return {"kind":"literal","value":value}
func prepare(fps: bool = false) -> void:
	game=ProbeFPS.new() if fps else Probe2D.new(); root.add_child(game); await process_frame
	await game._new_game(); game.vm.cancel_all(); game.ui.cancel_speech(); game.ui.close_menu()
	game.load_map(1,false); game.vm.cancel_all()
	game.entities[1].frozen=false; game.entities[1].nocontrol=0; game.attack_cooldown=0
	game.playing=true; game.changing=false
	# Z avoids the menu-confirm alias on the normal2D Space attack binding.
	check(game.bindings.set_bindings("attack",[{"type":"key","physical":KEY_Z}]).ok,"Fixture attack remap succeeds")
func cleanup() -> void:
	game.vm.cancel_all(); game.ui.cancel_speech(); game.ui.close_menu()
	await ticks(2); game.queue_free(); await process_frame
func item_use() -> void:
	await prepare()
	game.vm.story.scripts["item-reentry-fixture"]={"procedures":{"use":{"code":[
		{"op":"inc","target":"&use_starts","value":literal(1)},
		{"op":"call","name":"wait","args":[literal(1000)]},
		{"op":"call","name":"wait","args":[literal(1000)]},
		{"op":"inc","target":"&use_tails","value":literal(1)}]}}}
	game.items=[{"script":"item-reentry-fixture","name":"Review item"}]
	game.vm.globals.merge({"cur_weapon":1,"use_starts":0,"use_tails":0},true)
	await tap(KEY_Z)
	check(game.vm.globals.use_starts==1 and game.vm._live_tasks.size()==1,"First physical attack starts one awaiting item USE on sprite1")
	await create_timer(0.5).timeout
	check(game.attack_cooldown<=0 and not game.entities[1].get("nocontrol",false),"Refire uses normally recovered attack control")
	check(game.vm.globals.use_tails==0,"First item USE is still mid-await before refire")
	await tap(KEY_Z)
	check(game.vm.globals.use_starts==2 and game.vm._live_tasks.size()==1,"Refired USE restarts the existing sprite1script cursor")
	var tasks: Dictionary=game.vm._live_tasks.duplicate(true)
	for task in tasks.values(): check(int(task.instance_sprite)==1,"Item continuation belongs to player sprite1")
	await create_timer(2.1).timeout; await ticks(2)
	check(game.vm.globals.use_tails==1 and game.vm._live_tasks.is_empty(),"Only the newest multi-await item USE completes")
	records.append({"case":"item","attacks":game.attacks,"starts":game.vm.globals.use_starts,"tails":game.vm.globals.use_tails,"tasks_after_refire":tasks})
	await cleanup()
func choice_input(fps: bool) -> void:
	await prepare(fps)
	var npc := 0
	for id in game.entities:
		if game.entities[id].get("script","")=="s1-h1-m": npc=id; break
	check(npc!=0,"Source NPC exists for modal-choice input")
	if npc==0: await cleanup(); return
	game.vm.story.scripts["choice-reentry-fixture"]={"procedures":{"talk":{"code":[
		{"op":"inc","target":"&choice_starts","value":literal(1)},
		{"op":"choice_start"},
		{"op":"choice_title","text":literal("A modal review choice")},
		{"op":"choice_option","text":literal("Continue"),"result":literal(7)},
		{"op":"choice_end"},
		{"op":"inc","target":"&choice_tails","value":literal(1)}]}}}
	game.entities[npc].script="choice-reentry-fixture"
	game.entities[1].x=game.entities[npc].x; game.entities[1].y=float(game.entities[npc].y)+20
	game.entities[1].dir=8
	if fps: game.fps_yaw=0; game._sync_fps_camera()
	game.vm.globals.merge({"choice_starts":0,"choice_tails":0},true)
	# This first Talk is also a positive reachability/control check for retrying it.
	await tap(KEY_E); await ticks(6)
	check(game.vm.globals.choice_starts==1 and game.ui.modal and game.ui.dialogue_mode,"Physical Talk opens an owned script choice")
	var task_ids: Array=game.vm._live_tasks.keys()
	var serial: int=game.ui.page_serial
	var pos: Vector2=game._position2(1)
	var handlers: Array=[game.talks,game.attacks,game.casts]
	await tap(KEY_E); await tap(KEY_Z); await tap(KEY_Q)
	key(KEY_W,true); await ticks(30); key(KEY_W,false); await ticks(1)
	check(game.vm.globals.choice_starts==1 and game.vm.globals.choice_tails==0,"Choice blocks event re-entry and keeps its original caller waiting")
	check(game.vm._live_tasks.keys()==task_ids and task_ids.size()==1,"Choice retains its exact live task instead of replacing it")
	check([game.talks,game.attacks,game.casts]==handlers,"Modal choice gates Talk, weapon and magic handlers")
	check(game._position2(1).is_equal_approx(pos),"Modal choice gates real held movement/PUSH input")
	check(game.ui.page_serial==serial and game.ui.modal and game.ui.page=="dialogue","Gameplay retries cannot replace or orphan the visible choice")
	await tap(KEY_ENTER)
	for _i in Engine.physics_ticks_per_second:
		await ticks(1)
		if game.vm._live_tasks.is_empty(): break
	check(game.vm.globals.choice_starts==1 and game.vm.globals.choice_tails==1,"One normal confirmation completes only the original choice caller")
	check(not game.ui.modal and not game.ui.dialogue_mode and not game.ui.panel.visible and game.vm._live_tasks.is_empty(),"Choice confirmation leaves no hanging UI or VM task")
	await tap(KEY_Z); await tap(KEY_Q)
	check(game.attacks>handlers[1] and game.casts>handlers[2],"Weapon and magic input dispatch resume after the choice closes")
	records.append({"case":"choice","fps":fps,"starts":game.vm.globals.choice_starts,"tails":game.vm.globals.choice_tails,"held_task_ids":task_ids,"handlers_while_modal":handlers})
	await cleanup()
func _run() -> void:
	probe=TickProbe.new(); probe.process_physics_priority=100; root.add_child(probe)
	check(selected in ["item","choice","all"],"Known review test case requested")
	if selected in ["item","all"]: await item_use()
	if selected in ["choice","all"]:
		await choice_input(false); await choice_input(true)
	if not report_path.is_empty():
		var file:=FileAccess.open(report_path,FileAccess.WRITE)
		file.store_string(JSON.stringify({"setup":"Injected item/NPC scripts, progression skipped, physical input through real handlers","records":records,"failures":failures},"  ")); file.close()
	print("INSTANCE REVIEW PASS" if failures.is_empty() else "INSTANCE REVIEW FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
