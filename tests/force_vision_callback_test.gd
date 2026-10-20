extends SceneTree
# Script-fixture, progression skipped. FreeDink109.6 dinkc_bindings.cpp:1321-1326
# sets the caller to sprite 1000 and calls draw_screen_game, whose kill_all_scripts
# (dinkc.cpp:872-892) kills every script not on sprite 1000. A caller keeps its tail;
# any other waiting screen script does not. FreeDink kills a callback only with its owning
# script (dinkc.cpp:817-843), so a sprite-1000 owner's callback survives (dinkc.cpp:872-894).
# Argument --control uses draw_screen (no rebuild): the callback must fire either way.
# Advances by controlled waits and frames.
const GAME=preload("res://scripts/fps_game.gd")
class WaitGame extends GAME:
	signal release_wait(script_name: String)
	signal release_callbacks
	var waiting: Dictionary={}
	var callbacks_pending: int=0
	func _callback_timer(_seconds: float) -> void:
		callbacks_pending+=1
		await release_callbacks
	func dink_call(command: String,args: Array,context: Dictionary) -> Variant:
		var who: String=str(context.get("script",""))
		if command.to_lower()=="wait" and who.begins_with("fv-"):
			waiting[who]=int(waiting.get(who,0))+1
			while true:
				var released: String=await release_wait
				if released==who: break
			return 0
		return await super.dink_call(command,args,context)
var failures: Array[String]=[]
var control: bool=OS.get_cmdline_user_args().has("--control")
func _initialize() -> void: run.call_deferred()
func literal(value: Variant) -> Dictionary: return {"kind":"literal","value":value}
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); push_error(message)
func settle(game: WaitGame, who: String, count: int) -> bool:
	for frame in range(120):
		if int(game.waiting.get(who,0))>=count: return true
		await process_frame
	return false
func run() -> void:
	var game=WaitGame.new(); game.test_mode=true; root.add_child(game); await process_frame
	await game._new_game(); game.vm.cancel_all(); game.load_map(439,false)
	game.world.screens["439"].script=""
	game.vm.globals.callback_tail=0; game.vm.globals.victim_callback=0; game.vm.globals.caller_tail=0; game.vm.globals.victim_tail=0; game.vm.globals.sprite1000_tail=0
	game.vm.story.scripts["fv-caller"]={"procedures":{"main":{"code":[
		{"op":"call","name":"wait","args":[literal(1)]},
		{"op":"call","name":"draw_screen" if control else "force_vision","args":[literal(2)]},
		{"op":"call","name":"wait","args":[literal(1)]},
		{"op":"inc","target":"&caller_tail","value":literal(1)}]}}}
	game.vm.story.scripts["fv-victim"]={"procedures":{"main":{"code":[
		{"op":"call","name":"set_callback_random","args":[literal("cb"),literal(1),literal(1)]},
		{"op":"call","name":"wait","args":[literal(1)]},
		{"op":"inc","target":"&victim_tail","value":literal(1)}]}}}
	game.vm.story.scripts["fv-victim"].procedures["cb"]={"code":[{"op":"inc","target":"&victim_callback","value":literal(1)}]}
	# Pseudo-sprite 1000 scripts (FreeDink key/magic scripts) also survive.
	game.vm.story.scripts["fv-keeper"]={"procedures":{"main":{"code":[
		{"op":"call","name":"script_attach","args":[literal(1000)]},
		{"op":"call","name":"set_callback_random","args":[literal("cb"),literal(1),literal(1)]},
		{"op":"call","name":"wait","args":[literal(1)]},
		{"op":"inc","target":"&sprite1000_tail","value":literal(1)}]}}}
	game.vm.story.scripts["fv-keeper"].procedures["cb"]={"code":[{"op":"inc","target":"&callback_tail","value":literal(1)}]}
	game.vm.run("fv-caller","main",7,true)
	game.vm.run("fv-victim","main",8,true)
	game.vm.run("fv-keeper","main",9,true)
	check(await settle(game,"fv-caller",1) and await settle(game,"fv-victim",1) and await settle(game,"fv-keeper",1),"All three scripts reach their first wait")
	check(game.callbacks_pending==2,"Victim and keeper each hold one pending callback")
	check(game.vm._live_tasks.size()==3,"Three live tasks before force_vision")
	game.release_wait.emit("fv-caller")
	check(await settle(game,"fv-caller",2),"Caller resumes, force_visions and reaches its second wait")
	check(control or game.vm._live_tasks.size()==2,"Rebuild leaves only the caller and the sprite-1000 script live")
	game.release_wait.emit("fv-victim")
	game.release_wait.emit("fv-keeper")
	game.release_wait.emit("fv-caller")
	game.release_callbacks.emit()
	for frame in range(30): await process_frame
	check(control or game.vm.globals.victim_tail==0,"Other screen script's pending tail does not run after force_vision")
	check(control or game.vm.globals.victim_callback==0,"Other screen script's callback dies with it")
	check(game.vm.globals.caller_tail==1,"force_vision caller still completes its tail")
	check(game.vm.globals.sprite1000_tail==1,"Sprite-1000 script survives the rebuild and completes")
	check(game.vm._live_tasks.is_empty(),"No task is left live")
	check(not control or game.vm.globals.victim_callback==1,"Control: without a rebuild the victim's callback fires")
	check(game.vm.globals.callback_tail==1,"Sprite-1000 callback fires once, surviving the rebuild")
	game.vm.cancel_all(); game.queue_free(); await process_frame
	print("FORCE VISION CALLBACK PASS" if failures.is_empty() else str(failures))
	quit(0 if failures.is_empty() else 1)
