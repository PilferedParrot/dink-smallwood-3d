extends SceneTree
# Script-fixture, progression skipped. FreeDink109.6 dinkc_bindings.cpp:1321-1326
# sets the caller to sprite 1000 and calls draw_screen_game, whose kill_all_scripts
# (dinkc.cpp:872-892) kills every script not on sprite 1000. A caller keeps its tail;
# any other waiting screen script does not. Advances by controlled waits and frames.
const GAME=preload("res://scripts/fps_game.gd")
class WaitGame extends GAME:
	signal release_wait(script_name: String)
	var waiting: Dictionary={}
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
	game.vm.globals.caller_tail=0; game.vm.globals.victim_tail=0; game.vm.globals.sprite1000_tail=0
	game.vm.story.scripts["fv-caller"]={"procedures":{"main":{"code":[
		{"op":"call","name":"wait","args":[literal(1)]},
		{"op":"call","name":"force_vision","args":[literal(2)]},
		{"op":"call","name":"wait","args":[literal(1)]},
		{"op":"inc","target":"&caller_tail","value":literal(1)}]}}}
	game.vm.story.scripts["fv-victim"]={"procedures":{"main":{"code":[
		{"op":"call","name":"wait","args":[literal(1)]},
		{"op":"inc","target":"&victim_tail","value":literal(1)}]}}}
	# Pseudo-sprite 1000 scripts (FreeDink key/magic scripts) also survive.
	game.vm.story.scripts["fv-keeper"]={"procedures":{"main":{"code":[
		{"op":"call","name":"script_attach","args":[literal(1000)]},
		{"op":"call","name":"wait","args":[literal(1)]},
		{"op":"inc","target":"&sprite1000_tail","value":literal(1)}]}}}
	game.vm.run("fv-caller","main",7,true)
	game.vm.run("fv-victim","main",8,true)
	game.vm.run("fv-keeper","main",9,true)
	check(await settle(game,"fv-caller",1) and await settle(game,"fv-victim",1) and await settle(game,"fv-keeper",1),"All three scripts reach their first wait")
	check(game.vm._live_tasks.size()==3,"Three live tasks before force_vision")
	game.release_wait.emit("fv-caller")
	check(await settle(game,"fv-caller",2),"Caller resumes, force_visions and reaches its second wait")
	check(game.vm._live_tasks.size()==2,"Rebuild leaves only the caller and the sprite-1000 script live")
	game.release_wait.emit("fv-victim")
	game.release_wait.emit("fv-keeper")
	game.release_wait.emit("fv-caller")
	for frame in range(30): await process_frame
	check(game.vm.globals.victim_tail==0,"Other screen script's pending tail does not run after force_vision")
	check(game.vm.globals.caller_tail==1,"force_vision caller still completes its tail")
	check(game.vm.globals.sprite1000_tail==1,"Sprite-1000 script survives the rebuild and completes")
	check(game.vm._live_tasks.is_empty(),"No task is left live")
	game.vm.cancel_all(); game.queue_free(); await process_frame
	print("FORCE VISION CANCEL PASS" if failures.is_empty() else str(failures))
	quit(0 if failures.is_empty() else 1)
